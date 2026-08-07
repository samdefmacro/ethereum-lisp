#!/bin/sh
# Build an archivable EEST conformance report from a test-run log.
#
# The suite already prints what it measured: one
# `EEST-CONFORMANCE <family>: selected=N skipped=N executed=[...]` line per
# family (tests/fixture-runner-conformance-manifest.lisp). Those counts have
# only ever existed in a CI log that ages out, so "conformance passed" could
# never afterwards be checked against WHICH corpus, at WHICH revision, having
# executed HOW MANY vectors. This writes the lines out beside the identity of
# the corpus that produced them and the revision under test, in a form
# actions/upload-artifact can archive.
#
# The manifest lines are copied VERBATIM. Which families exist and which axes
# appear inside executed=[...] are the suite's business and are still being
# extended; a report that re-parsed them into a fixed shape would silently drop
# whatever it did not already know about.
#
# Corpus identity is DERIVED, never restated. Release, archive name and pinned
# SHA-256 are read out of scripts/fetch-eest-fixtures.sh -- the single place
# they are pinned -- and the archive on disk is re-hashed, so the report records
# the digest of the bytes that were actually used rather than an assertion about
# them. The upstream commit is the one field the fetcher does not carry; it is
# keyed BY DIGEST below rather than by baseline name, so bumping a pin can never
# leave the previous commit attached to the new corpus.
#
# Usage:
#   scripts/conformance-report.sh --log FILE --output FILE
#                                 [--fixture-root DIR] [--baseline NAME]
#                                 [--job NAME] [--require-manifest]
#
# --fixture-root is the path the fetcher printed; the baseline is derived from
# it, so the report describes the corpus that was really mounted instead of one
# the caller claims. --baseline overrides that when no root is available.
#
# The output file is always written, including on every failure path: a report
# that appeared only on success would be missing exactly when it matters most.
# Exit 0 usable report / 1 report written but not trustworthy as evidence (the
# corpus could not be identified, the archive digest disagrees with the pin, or
# --require-manifest was given and the run emitted no counts) / 2 usage. Missing
# metadata that leaves the report usable is recorded as report-gaps and exits 0.

set -eu

log=""
output=""
fixture_root=""
baseline=""
job="conformance"
require_manifest=0
fetcher="scripts/fetch-eest-fixtures.sh"

usage() {
    cat >&2 <<'USAGE'
usage: conformance-report.sh --log FILE --output FILE
                             [--fixture-root DIR] [--baseline NAME]
                             [--job NAME] [--require-manifest]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log) log="${2:?--log requires a value}"; shift 2 ;;
        --output) output="${2:?--output requires a value}"; shift 2 ;;
        --fixture-root) fixture_root="${2:?--fixture-root requires a value}"; shift 2 ;;
        --baseline) baseline="${2:?--baseline requires a value}"; shift 2 ;;
        --job) job="${2:?--job requires a value}"; shift 2 ;;
        --require-manifest) require_manifest=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "conformance-report: unknown argument $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$log" ] || [ -z "$output" ]; then
    usage
    exit 2
fi

if [ ! -f "$fetcher" ]; then
    echo "conformance-report: ${fetcher} not found; run from the repository root" >&2
    exit 2
fi

# One pass over the fetcher yields every pinned baseline as
# name<TAB>release<TAB>archive<TAB>sha256<TAB>extract-dir. A refactor that this
# no longer understands produces no rows at all, which surfaces below as an
# unresolved identity rather than as a confidently wrong one.
pinned_baselines() {
    awk '
      function value(line,   v) {
          v = substr(line, index(line, "=") + 1)
          gsub(/^"|"$/, "", v)
          return v
      }
      function flush() {
          if (arm != "" && release != "" && archive != "" && sha != "" && dir != "")
              printf "%s\t%s\t%s\t%s\t%s\n", arm, release, archive, sha, dir
          arm = ""; release = ""; archive = ""; sha = ""; dir = ""
      }
      { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line) }
      line ~ /^[A-Za-z0-9._@-]+\)$/ { flush(); arm = substr(line, 1, length(line) - 1); next }
      line == ";;" { flush(); next }
      arm == "" { next }
      line ~ /^EEST_RELEASE="/ { release = value(line); next }
      line ~ /^EEST_ARCHIVE="/ { archive = value(line); next }
      line ~ /^EEST_SHA256="/ { sha = value(line); next }
      line ~ /^EEST_EXTRACT_DIR="/ { dir = value(line); next }
      END { flush() }
    ' "$fetcher"
}

# Upstream commit for a pinned archive digest, per PROJECT.md and the "Pinned
# verification baseline" section of
# docs/gap-analysis/public-testnet-readiness-plan.md. Keyed on the digest, not
# the baseline name: a release tag can be moved and a baseline name reused, so a
# name-keyed table would keep reporting the old commit for a re-pinned corpus.
# An unknown digest reports itself unrecorded rather than guessing.
upstream_commit_for_digest() {
    case "$1" in
        92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909)
            echo "88e9fb8" ;;
        3586193db06d4d5745d5e90b3c3008c2255a4e19ccd8f11a3ce887aec8c0b17c)
            echo "87aba1a38a476b31f819a2390eb481527e6dc683" ;;
        02e3eca2ede5b424f4dbf2461caf592e6b43b56d55bbd64213dd01f63af9a583)
            echo "882909a2c88751a31fa99a65176563a16c527893" ;;
        *)
            echo "unrecorded" ;;
    esac
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "unavailable-no-sha256-tool"
    fi
}

# Two collectors, because they mean different things. A defect makes the report
# untrustworthy as evidence and fails the run; a gap leaves it usable but says
# what is missing, and must not redden a build over metadata.
defects=""
gaps=""
defect() {
    echo "conformance-report: $1" >&2
    defects="${defects}${defects:+; }$1"
}
gap() {
    echo "conformance-report: $1" >&2
    gaps="${gaps}${gaps:+; }$1"
}

# Identity of the corpus. Prefer deriving the baseline from the root that was
# actually mounted.
if [ -z "$baseline" ] && [ -n "$fixture_root" ]; then
    wanted_dir="$(basename "$fixture_root")"
    baseline="$(pinned_baselines |
        awk -F'\t' -v dir="$wanted_dir" '$5 == dir { print $1; exit }')"
    if [ -z "$baseline" ]; then
        defect "no pinned baseline in ${fetcher} extracts to '${wanted_dir}'"
    fi
fi

eest_release="unresolved"
eest_archive="unresolved"
eest_sha256_pinned="unresolved"
eest_extract_dir="unresolved"
if [ -n "$baseline" ]; then
    row="$(pinned_baselines |
        awk -F'\t' -v name="$baseline" '$1 == name { print; exit }')"
    if [ -n "$row" ]; then
        eest_release="$(printf '%s' "$row" | cut -f2)"
        eest_archive="$(printf '%s' "$row" | cut -f3)"
        eest_sha256_pinned="$(printf '%s' "$row" | cut -f4)"
        eest_extract_dir="$(printf '%s' "$row" | cut -f5)"
    else
        defect "baseline '${baseline}' is not pinned in ${fetcher}"
    fi
else
    defect "corpus baseline could not be resolved (pass --fixture-root or --baseline)"
fi

# Re-hash the archive the fetcher verified. The fetcher refuses to extract a
# corpus whose digest does not match its pin, so agreement here re-proves that
# the extracted tree came from the pinned bytes; disagreement means the archive
# changed after verification and the counts cannot be attributed to the pin.
eest_sha256_observed="not-checked"
if [ "$eest_archive" != "unresolved" ] && [ -n "$fixture_root" ]; then
    archive_path="$(dirname "$fixture_root")/${eest_archive}"
    if [ -f "$archive_path" ]; then
        eest_sha256_observed="$(sha256_of "$archive_path")"
        if [ "$eest_sha256_observed" != "$eest_sha256_pinned" ]; then
            defect "archive digest ${eest_sha256_observed} does not match the pinned ${eest_sha256_pinned}"
        fi
    else
        eest_sha256_observed="archive-absent"
    fi
fi

eest_upstream_commit="$(upstream_commit_for_digest "$eest_sha256_pinned")"
if [ "$eest_upstream_commit" = "unrecorded" ] && [ "$eest_sha256_pinned" != "unresolved" ]; then
    gap "no upstream commit recorded for digest ${eest_sha256_pinned}; add it to $0"
fi

# Revision under test. A report generated from a dirty tree is not attributable
# to a commit, so say so rather than printing the commit alone. --no-optional-locks
# because generating a report must not write to the repository it describes, and
# a failed status must not be mistaken for a clean one.
if revision="$(git rev-parse HEAD 2>/dev/null)"; then
    if worktree_status="$(git --no-optional-locks status --porcelain 2>/dev/null)"; then
        if [ -n "$worktree_status" ]; then
            revision_clean="no"
        else
            revision_clean="yes"
        fi
    else
        revision_clean="unknown"
        gap "could not determine whether the tree under test is clean"
    fi
else
    revision="unavailable"
    revision_clean="unknown"
    gap "no git revision available for the tree under test"
fi

# The manifest lines, verbatim from the first EEST-CONFORMANCE token onward so a
# harness prefix cannot hide one, and with no interpretation of their contents.
manifest=""
if [ -f "$log" ]; then
    manifest="$(tr -d '\r' < "$log" | sed -n 's/.*\(EEST-CONFORMANCE .*\)$/\1/p')"
else
    gap "log file ${log} does not exist"
fi
if [ -n "$manifest" ]; then
    manifest_lines="$(printf '%s\n' "$manifest" | wc -l | tr -d ' ')"
else
    manifest_lines=0
fi

mkdir -p "$(dirname "$output")"
{
    echo "# EEST conformance report"
    echo "#"
    echo "# Generated by scripts/conformance-report.sh. The count-manifest lines are"
    echo "# copied verbatim from the run; everything above them identifies the corpus"
    echo "# and the revision those counts describe."
    echo
    echo "report-version: 1"
    echo "job: ${job}"
    echo "generated-utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [ -n "${GITHUB_RUN_ID:-}" ]; then
        echo "ci-run: ${GITHUB_REPOSITORY:-unknown}/${GITHUB_WORKFLOW:-unknown} run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT:-1}"
        echo "ci-ref: ${GITHUB_REF:-unknown}"
    fi
    echo
    echo "revision-under-test: ${revision}"
    echo "revision-tree-clean: ${revision_clean}"
    echo
    echo "eest-baseline: ${baseline:-unresolved}"
    echo "eest-release: ${eest_release}"
    echo "eest-upstream-commit: ${eest_upstream_commit}"
    echo "eest-archive: ${eest_archive}"
    echo "eest-sha256-pinned: ${eest_sha256_pinned}"
    echo "eest-sha256-observed: ${eest_sha256_observed}"
    echo "eest-extract-dir: ${eest_extract_dir}"
    echo "eest-fixture-root: ${fixture_root:-unset}"
    echo
    echo "manifest-lines: ${manifest_lines}"
    if [ -n "$manifest" ]; then
        printf '%s\n' "$manifest"
    fi
    if [ -n "$gaps" ]; then
        echo
        echo "report-gaps: ${gaps}"
    fi
    if [ -n "$defects" ]; then
        echo
        echo "report-defects: ${defects}"
    fi
} > "$output"

echo "conformance-report: wrote ${output} (${manifest_lines} manifest lines)" >&2

# A conformance job that emitted no manifest line measured nothing -- the corpus
# was not mounted, or no selector was set -- and that is the exact silent green
# the manifest exists to prevent, so callers that expect counts say so.
if [ "$require_manifest" -eq 1 ] && [ "$manifest_lines" -eq 0 ]; then
    echo "conformance-report: no EEST-CONFORMANCE lines in ${log}; the run measured nothing" >&2
    exit 1
fi

[ -z "$defects" ] || exit 1
