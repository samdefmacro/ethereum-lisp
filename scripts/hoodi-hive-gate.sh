#!/usr/bin/env bash
#
# Reproducible control-plane broker for the Section 5 remote Hive gates
# (rpc-compat 234, Engine/auth 403, devp2p 48).
#
# Hive cannot run on this macOS control plane (scripts/hive-run.sh refuses it):
# it must share a Linux host with the Docker daemon whose client containers it
# dials.  Every accepted Section 5 Hive result (r19 rpc-compat, r29 Engine,
# r54 devp2p) ran scripts/hive-run.sh inside a fresh, bounded "outer runner"
# container on the Hoodi host.  That runner carried its own nested Docker
# daemon, into which the exact runtime archive was loaded; the launcher that
# created it was an external supervisor that is no longer on this machine
# (docs/evidence/sec5-8e95b990-acceptance-plan.txt, finding F2).  This script
# is the checked-in replacement, reconstructed from the retained records, in
# the shape of scripts/hoodi-live-gate.sh:
#
#   - it runs only git, ssh, scp, tar, jq and read-only local Docker inspection;
#   - read-only actions (inspect, status, logs, collect) never change remote
#     state; mutating actions (upload, prepare, run) require
#     HOODI_GATE_ALLOW_MUTATION=1, a clean checkout, and the revision fence;
#   - every remote path stays below /data/hoodi-sec5-*, every run gets a fresh
#     previously absent evidence root, and nothing is ever deleted.
#
# The remote halves (the scripts sent over ssh) live in
# scripts/hoodi-hive-gate-remote.sh, which only defines functions.  The
# stubbed self-test is scripts/hoodi-hive-gate-selftest.sh.
#
# Transcribed from the records (docs/hive-gate.md, "Remote runs"): runner
# bounds 2 CPU / 3g+3584m (rpc-compat, r19) or 8g+10g (Engine r29, devp2p
# r54), 1,024 PIDs, read-only root, no published port, not on the Hoodi
# networks, binds limited to the evidence root and the nested-Docker path,
# bounded tmpfs; the runtime archive loaded into the runner's nested daemon
# (r35, r43); the hive-run.sh environment and HIVE_EXPECTED_TESTS=48 for devp2p
# only; the pinned Hive binary checksum; the runner exiting 0 with Hive's own
# status in hive-status.txt (r54).
#
# INFERRED, NOT IN ANY RECORD -- review before the first run:
#   1. --privileged for the outer runner.  A Docker daemon inside a container
#      needs it; no record names the flag.  prepare and run therefore require
#      HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 as an explicit acknowledgement.
#   2. The runner image's contents (dockerd, docker, bash, git, jq, sha256sum,
#      tar) and entrypoint.  The runner script checks the tools and overrides
#      the entrypoint with /bin/sh; `inspect` prints the image configuration.
#   3. The host path of the pinned Hive binary (default
#      /data/hoodi-sec5-hive/staging/hive-dde4f59d, HOODI_HIVE_BINARY).
#   4. The tmpfs sizes (/run and /var/run 64 MiB, /tmp 1 GiB).
#   5. No run timeout: r39 used a 2 h bound, which the ~2 h 06 min r29 Engine
#      run would exceed, so none is imposed; watch with `status`.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat >&2 <<'USAGE'
Usage: scripts/hoodi-hive-gate.sh ACTION [--sim SUITE --run N --stamp STAMP]

Read-only actions: inspect, status, logs, collect
Mutating actions:  upload, prepare, run

SUITE is rpc-compat, engine, or devp2p. N is the run ordinal (1-9999) and
STAMP the run's UTC timestamp, YYYYMMDDTHHMMSSZ; together they name the fresh
evidence root /data/hoodi-sec5-hive/runs/<rev8>-<suite>-full-r<N>-<STAMP> and
the runner container sec5-hive-<rev8>-<suite>-full-r<N>. prepare, run, status,
logs, and collect require all three; inspect accepts them optionally.

Mutating actions require HOODI_GATE_ALLOW_MUTATION=1, a clean checkout, and a
revision fence: HOODI_HIVE_REVISION (default HEAD) must be HEAD or an ancestor
with no runtime-sensitive change since. prepare and run additionally require
HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1, the explicit acknowledgement that the
outer runner starts its own Docker daemon and therefore runs --privileged.

run refuses unless MemAvailable reaches the suite's need (rpc-compat 4.5 GiB,
engine and devp2p 8 GiB), /data has 12 GiB available, no other Hive runner is
running, and, for engine and devp2p, no live-gate EL container is running.
USAGE
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

note() {
    echo "==> $*"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail "sha256sum or shasum is required"
    fi
}

sha256_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        fail "sha256sum or shasum is required"
    fi
}

# --- arguments ----------------------------------------------------------------

[ $# -ge 1 ] || { usage; exit 2; }
action="$1"
shift
case "$action" in
    inspect|status|logs|collect|upload|prepare|run) ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "unknown action: $action" >&2; usage; exit 2 ;;
esac

suite=""
run_ordinal=""
run_stamp=""
while [ $# -gt 0 ]; do
    case "$1" in
        --sim)
            [ $# -ge 2 ] || fail "--sim needs a value"
            suite="$2"; shift 2 ;;
        --run)
            [ $# -ge 2 ] || fail "--run needs a value"
            run_ordinal="$2"; shift 2 ;;
        --stamp)
            [ $# -ge 2 ] || fail "--stamp needs a value"
            run_stamp="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

# The per-suite contract, transcribed from the accepted records:
#   rpc-compat  r19 (sec5-6e3e9b1d-hive-rpc-compat.txt): 2 CPU, 3 GiB,
#               3.5 GiB with swap; HIVE_EXPECTED_TESTS unset, hive-run.sh
#               enforces 234.
#   engine      r29 (sec5-3305307d-hive-engine-auth.txt): 2 CPU, 8 GiB,
#               10 GiB with swap (3 GiB OOM-killed, 4 GiB produced resets);
#               unset, hive-run.sh enforces 403 for an unlimited run, whose
#               count contains no per-suite loader entries.
#   devp2p      r54 (sec5-03957929-hive-devp2p-r54.txt): 2 CPU, 8 GiB,
#               10 GiB with swap; HIVE_EXPECTED_TESTS=48 is mandatory because
#               hive-run.sh has no built-in devp2p inventory.
# The MemAvailable preconditions are the acceptance plan's step-3 decision.
hive_sim="none"
runner_memory="none"
runner_memory_swap="none"
memory_need_bytes="0"
expected_tests="none"
suite_log="none"
refuse_live_el=0
case "$suite" in
    '') ;;
    rpc-compat)
        hive_sim="ethereum/rpc-compat"; runner_memory=3g; runner_memory_swap=3584m
        memory_need_bytes=4831838208; suite_log=hive-rpc-full.log ;;
    engine)
        hive_sim="ethereum/engine"; runner_memory=8g; runner_memory_swap=10g
        memory_need_bytes=8589934592; suite_log=hive-engine-full.log; refuse_live_el=1 ;;
    devp2p)
        hive_sim="devp2p"; runner_memory=8g; runner_memory_swap=10g
        memory_need_bytes=8589934592; suite_log=hive-devp2p-full.log; refuse_live_el=1
        expected_tests=48 ;;
    *) fail "unknown suite: $suite (expected rpc-compat, engine, or devp2p)" ;;
esac

if [ -n "$run_ordinal" ]; then
    case "$run_ordinal" in *[!0-9]*|0*) fail "run ordinal must be a positive integer without leading zeros" ;; esac
    [ "${#run_ordinal}" -le 4 ] || fail "run ordinal must be at most 9999"
fi
if [ -n "$run_stamp" ]; then
    case "$run_stamp" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
        *) fail "run stamp must be a UTC timestamp YYYYMMDDTHHMMSSZ" ;;
    esac
fi

case "$action" in
    prepare|run|status|logs|collect)
        [ -n "$suite" ] || fail "$action requires --sim SUITE"
        [ -n "$run_ordinal" ] || fail "$action requires --run N"
        [ -n "$run_stamp" ] || fail "$action requires --stamp YYYYMMDDTHHMMSSZ"
        ;;
    upload)
        [ -z "$suite$run_ordinal$run_stamp" ] || fail "upload stages artifacts only; it takes no run identity"
        ;;
    inspect)
        if [ -n "$suite$run_ordinal$run_stamp" ]; then
            [ -n "$suite" ] && [ -n "$run_ordinal" ] && [ -n "$run_stamp" ] ||
                fail "inspect takes either no run identity or all of --sim, --run, --stamp"
        fi
        ;;
esac

# --- identities ---------------------------------------------------------------

actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_HIVE_REVISION:-$actual_head}"
case "$revision" in
    *[!0-9a-f]*|'') fail "revision must be a full lowercase hexadecimal Git id" ;;
esac
[ "${#revision}" -eq 40 ] || fail "revision must contain exactly 40 hexadecimal characters"
short_revision="${revision:0:8}"

host="${HOODI_GATE_HOST:-test-ethereum-sophon2-symbiosis}"
hive_root="${HOODI_HIVE_REMOTE_ROOT:-/data/hoodi-sec5-hive}"
staging="$hive_root/staging"
source_artifact="${HOODI_HIVE_SOURCE_ARTIFACT:-/private/tmp/ethereum-lisp-source-${short_revision}.tar}"
runtime_artifact="${HOODI_HIVE_RUNTIME_ARTIFACT:-/private/tmp/ethereum-lisp-runtime-sec5-${short_revision}-amd64.tar}"
remote_source="$staging/${source_artifact##*/}"
remote_runtime="$staging/${runtime_artifact##*/}"
runtime_repository="ethereum-lisp-runtime"
runtime_tag="sec5-${short_revision}-amd64"
runtime_image="$runtime_repository:$runtime_tag"
runner_image="${HOODI_HIVE_RUNNER_IMAGE:-ethereum-lisp-sec5-hive-runner:docker27-amd64}"
# The pinned Hive binary identity retained by r19, r29, r30, r39 and r54.  The
# runner has no Go toolchain; hive-run.sh verifies this checksum itself.
hive_binary="${HOODI_HIVE_BINARY:-$staging/hive-dde4f59d}"
hive_binary_sha256="cff9f5c075d1214076e4a1d02dff0ff55ac9a3225f0b91f5f52eb12515d17308"
disk_need_bytes=12884901888
agent_label="codex-sec5-live-gate"

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$hive_root" in
    /data/hoodi-sec5-*) ;;
    *) fail "remote root must stay below /data/hoodi-sec5-*" ;;
esac
case "$hive_root$remote_source$remote_runtime$hive_binary" in
    *'..'*|*$'\n'*|*$'\r'*|*$'\t'*|*' '*) fail "remote paths must be absolute, normalized, and whitespace-free" ;;
esac
case "$hive_binary" in "$hive_root"/*) ;; *) fail "Hive binary must stay below $hive_root" ;; esac
case "${source_artifact##*/}${runtime_artifact##*/}" in
    *[!A-Za-z0-9_.-]*) fail "artifact file names must be plain" ;;
esac
case "$runner_image" in *[!A-Za-z0-9_.:/+-]*|'') fail "unsafe runner image name: $runner_image" ;; esac

run_id="none"
run_root="none"
nested_root="none"
runner_container="none"
prepare_container="none"
if [ -n "$suite" ]; then
    run_id="${short_revision}-${suite}-full-r${run_ordinal}-${run_stamp}"
    run_root="$hive_root/runs/$run_id"
    nested_root="$hive_root/nested-docker/$run_id"
    runner_container="sec5-hive-${short_revision}-${suite}-full-r${run_ordinal}"
    prepare_container="sec5-hive-${short_revision}-${suite}-prep-r${run_ordinal}"
fi
collect_dir="${HOODI_HIVE_COLLECT_DIR:-/private/tmp/sec5-hive-evidence/$run_id}"

# --- revision fence -----------------------------------------------------------

if [ "$actual_head" != "$revision" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "Hive revision $revision is not an ancestor of checkout HEAD $actual_head"
    runtime_sensitive_changes="$(git -C "$repo_root" diff --name-only \
        "$revision" "$actual_head" -- . \
        ':(exclude)docs/**' \
        ':(exclude)scripts/hoodi-live-gate.sh' \
        ':(exclude)scripts/hoodi-hive-gate.sh' \
        ':(exclude)scripts/hoodi-hive-gate-remote.sh' \
        ':(exclude)scripts/hoodi-hive-gate-selftest.sh' \
        ':(exclude)tests/control-plane-broker-tests.lisp' \
        ':(exclude)scripts/hoodi-geth-benchmark-gate.sh' \
        ':(exclude)scripts/hoodi-lisp-benchmark-gate.sh')"
    # Read-only evidence stays available for an older revision; nothing that
    # stages, prepares or starts a run may act for a revision the checkout has
    # moved past in runtime-sensitive paths.
    case "$action" in
        inspect|status|logs|collect) ;;
        *) [ -z "$runtime_sensitive_changes" ] ||
               fail "checkout changed runtime-sensitive paths after $revision: $runtime_sensitive_changes" ;;
    esac
fi

require_clean_checkout() {
    git -C "$repo_root" diff --quiet || fail "checkout has unstaged changes"
    git -C "$repo_root" diff --cached --quiet || fail "checkout has staged changes"
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "checkout has untracked files"
}

require_mutation() {
    [ "${HOODI_GATE_ALLOW_MUTATION:-}" = "1" ] ||
        fail "$action changes remote state; set HOODI_GATE_ALLOW_MUTATION=1 only after explicit authorization"
    require_clean_checkout
}

require_nested_privilege() {
    # Inferred item 1 in the header: the records establish a nested Docker
    # daemon inside the outer runner but never record the flag permitting it.
    [ "${HOODI_HIVE_NESTED_DOCKER_PRIVILEGED:-}" = "1" ] ||
        fail "$action starts a --privileged outer runner for its nested Docker daemon; set HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 only after reviewing $runner_image"
}

local_artifacts() {
    [ -f "$source_artifact" ] || fail "source archive is absent: $source_artifact (upload builds it)"
    [ -f "$runtime_artifact" ] || fail "runtime archive is absent: $runtime_artifact"
    source_sha256="$(sha256_file "$source_artifact")"
    runtime_sha256="$(sha256_file "$runtime_artifact")"
}

verify_source_archive() {
    local expected
    expected="$(git -C "$repo_root" archive --format=tar "$revision" | sha256_stdin)"
    [ "$source_sha256" = "$expected" ] ||
        fail "source archive $source_artifact is $source_sha256, but git archive $revision is $expected"
}

inspect_local_runtime_image() {
    local image_revision image_platform
    image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$runtime_image")" ||
        fail "local runtime image is absent: $runtime_image"
    image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$runtime_image")"
    [ "$image_revision" = "$revision" ] ||
        fail "local runtime image revision is $image_revision, expected $revision"
    [ "$image_platform" = "linux/amd64" ] ||
        fail "local runtime image platform is $image_platform, expected linux/amd64"
}

# shellcheck source=scripts/hoodi-hive-gate-remote.sh
. "$repo_root/scripts/hoodi-hive-gate-remote.sh"

case "$action" in
    inspect) inspect_gate ;;
    upload) upload_artifacts ;;
    prepare) prepare_run ;;
    run) start_run ;;
    status) remote_status ;;
    logs) remote_logs ;;
    collect) collect_run ;;
esac
