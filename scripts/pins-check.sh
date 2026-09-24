#!/usr/bin/env bash
#
# Fail when a build or CI input is referenced by a name that can move.
#
#   scripts/pins-check.sh              check this checkout (tracked files only)
#   scripts/pins-check.sh --self-test  prove every rule can fail, then pass
#
# Rules (plan section 10, "digest-pinned ... pin CI actions"):
#
#   Dockerfiles   every FROM names image:tag@sha256:<64 hex>. The tag stays in
#                 the reference so a refresh knows what it tracks; Docker
#                 resolves the digest and ignores the tag. Two exceptions: an
#                 earlier stage of the same file (FROM native AS lisp), and a
#                 FROM through a build argument whose previous non-blank line
#                 is "# pins-check: project-image" -- an image this repository
#                 builds itself (the Hive wrapper, the discv5 interop test), so
#                 no registry digest exists for it.
#   Workflows     every `uses:` names owner/repo@<40-hex commit> followed by a
#                 comment naming the release it resolves (# v4.4.0); local
#                 actions (./...) are exempt, docker:// actions and `image:`
#                 keys need image:tag@sha256.
#   Inputs        tools/build-inputs/inputs.lock is well formed with every
#                 digest recorded, each name a Dockerfile passes to
#                 verify-inputs.sh has a line, and the vendored RocksDB archive
#                 and the digest inlined in the Dockerfiles match its line.
#
# The script only reads files. It needs bash (3.2 is enough), git and the
# POSIX text tools, so it runs on the control plane and in CI without a
# project container. Exit 0 = no violation, 1 = violations (each printed as
# PIN-VIOLATION file:line: reason), 2 = usage or an empty selection.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PINNED_IMAGE_RE='^[^@[:space:]]+:[^@:/[:space:]]+@sha256:[0-9a-f]{64}$'
ANY_DIGEST_RE='@sha256:[0-9a-f]{64}$'
COMMIT_RE='^[0-9a-f]{40}$'
FROM_RE='^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+'
USES_RE='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*([^[:space:]#]+)'
IMAGE_RE='^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*([^[:space:]#]+)'
IMAGE_OPT_RE='[[:space:]]image=([^[:space:],]+)'
VERSION_COMMENT_RE='#[[:space:]]*v?[0-9]'
PROJECT_IMAGE_MARK_RE='^[[:space:]]*#[[:space:]]*pins-check:[[:space:]]*project-image([[:space:]]|$)'

violations=0
from_lines=0
uses_lines=0

violation() { # FILE LINE REASON
  printf 'PIN-VIOLATION %s:%s: %s\n' "$1" "$2" "$3"
  violations=$((violations + 1))
}

strip_quotes() {
  local value="$1"
  value="${value//\"/}"
  value="${value//\'/}"
  printf '%s' "$value"
}

lowercase() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# Sets from_alias to the stage name the line declares (lower case), or "".
# Not a command substitution: the counters and violations must survive.
from_alias=""
check_from_line() { # LABEL LINENO LINE PREVIOUS-NONBLANK STAGES
  local label="$1" lineno="$2" line="$3" previous="$4" stages="$5"
  local -a words
  local i=1 ref="" alias=""
  from_alias=""
  read -r -a words <<<"$line"
  while [ "$i" -lt "${#words[@]}" ]; do
    case "${words[$i]}" in
      --*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$i" -lt "${#words[@]}" ]; then
    ref="${words[$i]}"
    if [ $((i + 2)) -lt "${#words[@]}" ]; then
      case "${words[$((i + 1))]}" in
        [Aa][Ss]) alias="${words[$((i + 2))]}" ;;
      esac
    fi
  fi
  from_lines=$((from_lines + 1))
  if [ -z "$ref" ]; then
    violation "$label" "$lineno" "FROM names no image"
  elif [ "$ref" = scratch ]; then
    :
  elif case "$stages" in *" $(lowercase "$ref") "*) true ;; *) false ;; esac; then
    :
  elif [[ $ref == *'$'* ]]; then
    if ! [[ $previous =~ $PROJECT_IMAGE_MARK_RE ]]; then
      violation "$label" "$lineno" \
        "FROM $ref goes through a build argument; digest-pin it or mark a project-built image with '# pins-check: project-image' on the line above"
    fi
  elif [[ $ref =~ $PINNED_IMAGE_RE ]]; then
    :
  elif [[ $ref =~ $ANY_DIGEST_RE ]]; then
    violation "$label" "$lineno" "FROM $ref is digest-pinned but drops its tag; write image:tag@sha256:..."
  else
    violation "$label" "$lineno" "FROM $ref is not pinned by digest (image:tag@sha256:...)"
  fi
  from_alias="$(lowercase "$alias")"
}

check_dockerfile() { # FILE [LABEL]
  local file="$1" label="${2:-$1}" lineno=0 line previous="" stages=" "
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    if [[ $line =~ $FROM_RE ]]; then
      check_from_line "$label" "$lineno" "$line" "$previous" "$stages"
      [ -z "$from_alias" ] || stages="$stages$from_alias "
    fi
    case "$line" in
      *[![:space:]]*) previous="$line" ;;
    esac
  done <"$file"
}

check_workflow() { # FILE [LABEL]
  local file="$1" label="${2:-$1}" lineno=0 line value ref
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    if [[ $line =~ $USES_RE ]]; then
      uses_lines=$((uses_lines + 1))
      value="$(strip_quotes "${BASH_REMATCH[2]}")"
      case "$value" in
        ./*) ;;
        docker://*)
          [[ ${value#docker://} =~ $PINNED_IMAGE_RE ]] || \
            violation "$label" "$lineno" "uses: $value is not image:tag@sha256:..."
          ;;
        *@*)
          ref="${value##*@}"
          if ! [[ $ref =~ $COMMIT_RE ]]; then
            violation "$label" "$lineno" "uses: $value is not pinned to a full commit SHA"
          elif ! [[ $line =~ $VERSION_COMMENT_RE ]]; then
            violation "$label" "$lineno" "uses: $value names no release in a trailing comment (# vX.Y.Z)"
          fi
          ;;
        *) violation "$label" "$lineno" "uses: $value names no ref" ;;
      esac
    elif [[ $line =~ $IMAGE_RE ]]; then
      value="$(strip_quotes "${BASH_REMATCH[2]}")"
      [[ $value =~ $PINNED_IMAGE_RE ]] || \
        violation "$label" "$lineno" "image: $value is not image:tag@sha256:..."
    elif [[ $line =~ $IMAGE_OPT_RE ]]; then
      # A buildx driver's BuildKit image (driver-opts: image=...) runs every
      # build step, so it is as much a build input as a FROM.
      value="$(strip_quotes "${BASH_REMATCH[1]}")"
      [[ $value =~ $PINNED_IMAGE_RE ]] || \
        violation "$label" "$lineno" "image=$value is not image:tag@sha256:..."
    fi
  done <"$file"
}

# ---------------------------------------------------------------------------
# tools/build-inputs/inputs.lock, from the control plane. The lock itself is
# enforced inside the build (tools/build-inputs/verify-inputs.sh); this catches
# what a build cannot: a malformed or unrecorded (TBD) line, a duplicate, a
# name a Dockerfile verifies that has no line, and the vendored RocksDB archive
# or the digest written inline into the Dockerfiles drifting from the lock.
# ---------------------------------------------------------------------------

LOCK_PATH=tools/build-inputs/inputs.lock
ROCKSDB_ARCHIVE=tools/rocksdb/rocksdb-11.1.2.tar.gz
SHA256_RE='^[0-9a-f]{64}$'
VERIFY_REF_RE='(^|verify-inputs\.sh)[[:space:]]+(file|git|deb)[[:space:]]+([^[:space:]\\]+)[[:space:]]+[^[:space:]\\]+'
lock_entries=0

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

check_inputs() { # ROOT DOCKERFILE...
  local root="$1" lock="$1/$LOCK_PATH" lineno=0 line seen=" " names=" "
  local rocksdb_lock="" actual dockerfile inline ref
  local -a fields
  shift
  if [ ! -f "$lock" ]; then
    violation "$LOCK_PATH" 0 "missing"
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"
    case "$line" in *[![:space:]]*) ;; *) continue ;; esac
    read -r -a fields <<<"$line"
    if [ "${#fields[@]}" -ne 5 ]; then
      violation "$LOCK_PATH" "$lineno" "want NAME ARCH SCOPE SHA256 PURL, got ${#fields[@]} fields"
      continue
    fi
    lock_entries=$((lock_entries + 1))
    case "${fields[1]}" in
      any|amd64|arm64) ;;
      *) violation "$LOCK_PATH" "$lineno" "${fields[0]}: unknown arch ${fields[1]}" ;;
    esac
    case ",${fields[2]}," in
      *,runtime,*|*,build,*|*,test,*) ;;
      *) violation "$LOCK_PATH" "$lineno" "${fields[0]}: scope ${fields[2]} names none of runtime, build, test" ;;
    esac
    [[ ${fields[3]} =~ $SHA256_RE ]] || \
      violation "$LOCK_PATH" "$lineno" "${fields[0]} (${fields[1]}): ${fields[3]} is not a recorded SHA-256"
    case "${fields[4]}" in
      pkg:*@*) ;;
      *) violation "$LOCK_PATH" "$lineno" "${fields[0]}: ${fields[4]} is not a versioned package URL" ;;
    esac
    case "$seen" in
      *" ${fields[0]}/${fields[1]} "*) violation "$LOCK_PATH" "$lineno" "${fields[0]} (${fields[1]}) is listed twice" ;;
    esac
    seen="$seen${fields[0]}/${fields[1]} "
    names="$names${fields[0]} "
    [ "${fields[0]}" != rocksdb-source ] || rocksdb_lock="${fields[3]}"
  done <"$lock"

  if [ -f "$root/$ROCKSDB_ARCHIVE" ]; then
    actual="$(sha256_file "$root/$ROCKSDB_ARCHIVE")"
    [ "$actual" = "$rocksdb_lock" ] || \
      violation "$ROCKSDB_ARCHIVE" 0 "sha256 $actual, inputs.lock rocksdb-source says ${rocksdb_lock:-nothing}"
  else
    violation "$ROCKSDB_ARCHIVE" 0 "missing"
  fi
  for dockerfile in "$@"; do
    if grep -q "$(basename "$ROCKSDB_ARCHIVE")" "$root/$dockerfile"; then
      inline="$(grep -Eo '[0-9a-f]{64}  /opt/rocksdb' "$root/$dockerfile" | head -1 | cut -d' ' -f1 || true)"
      [ -n "$inline" ] && [ "$inline" = "$rocksdb_lock" ] || \
        violation "$dockerfile" 0 "inline RocksDB sha256 '${inline}' differs from inputs.lock '${rocksdb_lock}'"
    fi
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))
      if [[ $line =~ $VERIFY_REF_RE ]]; then
        ref="${BASH_REMATCH[3]}"
        case "$names" in
          *" $ref "*) ;;
          *) violation "$dockerfile" "$lineno" "verifies $ref, which inputs.lock does not list" ;;
        esac
      fi
    done <"$root/$dockerfile"
  done
}

check_repository() {
  local file dockerfiles=0 workflows=0
  local -a verifying=()
  while IFS= read -r file; do
    case "$file" in
      Dockerfile|*/Dockerfile|Dockerfile.*|*/Dockerfile.*|*.Dockerfile|*.dockerfile)
        dockerfiles=$((dockerfiles + 1))
        check_dockerfile "$ROOT/$file" "$file"
        if grep -q 'verify-inputs\.sh' "$ROOT/$file"; then
          verifying+=("$file")
        fi
        ;;
      .github/workflows/*.yml|.github/workflows/*.yaml|.github/actions/*/action.yml|.github/actions/*/action.yaml)
        workflows=$((workflows + 1))
        check_workflow "$ROOT/$file" "$file"
        ;;
    esac
  done < <(git -C "$ROOT" ls-files)
  check_inputs "$ROOT" ${verifying[@]+"${verifying[@]}"}
  printf 'pins-check: %d Dockerfiles (%d FROM lines, %d verifying inputs), %d workflows (%d uses lines), %d inputs.lock entries, %d violations\n' \
    "$dockerfiles" "$from_lines" "${#verifying[@]}" "$workflows" "$uses_lines" "$lock_entries" "$violations"
  # A check that selected nothing is not a pass.
  if [ "$from_lines" -eq 0 ] || [ "$uses_lines" -eq 0 ] || \
     [ "${#verifying[@]}" -eq 0 ] || [ "$lock_entries" -eq 0 ]; then
    echo "ERROR: pins-check selected no FROM, uses, verifying Dockerfile or lock entry" >&2
    return 2
  fi
  [ "$violations" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Self-test: each rule is fed an input it must flag, and a clean input it must
# pass. A rule that never fires would otherwise look exactly like a clean tree.
# ---------------------------------------------------------------------------

expect_violations() { # WANT KIND FILE
  local want="$1" kind="$2" file="$3" output got
  violations=0
  from_lines=0
  uses_lines=0
  if [ "$kind" = dockerfile ]; then
    output="$(check_dockerfile "$file" "$(basename "$file")"; echo "violations=$violations")"
  elif [ "$kind" = inputs ]; then
    output="$(check_inputs "$file" Dockerfile; echo "violations=$violations")"
  else
    output="$(check_workflow "$file" "$(basename "$file")"; echo "violations=$violations")"
  fi
  got="${output##*violations=}"
  if [ "$got" != "$want" ]; then
    printf '%s\n' "$output" >&2
    echo "SELF-TEST FAILED: $(basename "$file") gave $got violations, expected $want" >&2
    return 1
  fi
  echo "self-test ok: $(basename "$file") -> $got violations"
}

self_test() {
  local dir digest commit
  dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$dir'" EXIT
  digest="sha256:$(printf '%064d' 0 | tr 0 a)"
  commit="$(printf '%040d' 0 | tr 0 b)"

  cat >"$dir/good.Dockerfile" <<EOF
FROM debian:bookworm-slim@$digest AS native
FROM native AS lisp
FROM --platform=linux/amd64 golang:1.24-bookworm@$digest
ARG PROJECT_IMAGE=example
# pins-check: project-image
FROM \${PROJECT_IMAGE}
FROM scratch
EOF
  cat >"$dir/bad.Dockerfile" <<EOF
FROM debian:bookworm-slim
FROM debian@$digest
ARG base=example
FROM \${base}:latest
FROM --platform=linux/amd64 alpine:3.20 AS tool
FROM lisp
EOF
  cat >"$dir/good.yml" <<EOF
jobs:
  x:
    steps:
      - uses: actions/checkout@$commit # v4.4.0
      - uses: ./.github/actions/local
      - uses: "docker://alpine:3.20@$digest"
    container:
      image: postgres:16@$digest
      - uses: docker/setup-buildx-action@$commit # v3.12.0
        with:
          driver-opts: image=moby/buildkit:buildx-stable-1@$digest
EOF
  cat >"$dir/bad.yml" <<EOF
jobs:
  x:
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@$commit
      - uses: docker://alpine:3.20
      - uses: actions/checkout
    container:
      image: postgres:16
      - uses: docker/setup-buildx-action@$commit # v3.12.0
        with:
          driver-opts: image=moby/buildkit:buildx-stable-1
EOF

  local root sha
  for root in "$dir/good-root" "$dir/bad-root"; do
    mkdir -p "$root/tools/rocksdb" "$root/tools/build-inputs"
    printf 'rocksdb\n' >"$root/$ROCKSDB_ARCHIVE"
  done
  sha="$(sha256_file "$dir/good-root/$ROCKSDB_ARCHIVE")"
  cat >"$dir/good-root/$LOCK_PATH" <<EOF
# comment
rocksdb-source   any    runtime,test  $sha  pkg:github/facebook/rocksdb@v11.1.2
blst             any    runtime,test  $(printf '%064d' 0 | tr 0 c)  pkg:github/supranational/blst@abc
sbcl             amd64  runtime,test  $(printf '%064d' 0 | tr 0 d)  pkg:deb/debian/sbcl@2:2.2.9-1
sbcl             arm64  runtime,test  $(printf '%064d' 0 | tr 0 e)  pkg:deb/debian/sbcl@2:2.2.9-1
EOF
  cat >"$dir/good-root/Dockerfile" <<EOF
RUN echo "$sha  /opt/rocksdb-11.1.2.tar.gz" | sha256sum -c -
RUN /opt/build-inputs/verify-inputs.sh deb sbcl sbcl
RUN git clone https://example.invalid/c.git /opt/c \\
    && /opt/build-inputs/verify-inputs.sh \\
        git blst /opt/c/blst \\
    && make
EOF
  # Seven faults: tampered archive, unrecorded digest, duplicate, unknown
  # scope, short line, stale inline digest, and a verified name with no line.
  printf 'tampered\n' >"$dir/bad-root/$ROCKSDB_ARCHIVE"
  cat >"$dir/bad-root/$LOCK_PATH" <<EOF
rocksdb-source   any    runtime,test  $sha  pkg:github/facebook/rocksdb@v11.1.2
blst             any    runtime,test  TBD  pkg:github/supranational/blst@abc
sbcl             amd64  runtime,test  $(printf '%064d' 0 | tr 0 d)  pkg:deb/debian/sbcl@2:2.2.9-1
sbcl             amd64  runtime,test  $(printf '%064d' 0 | tr 0 d)  pkg:deb/debian/sbcl@2:2.2.9-1
quicklisp-client any    shipped       $(printf '%064d' 0 | tr 0 e)  pkg:generic/quicklisp-client@2021-02-13
broken           any    runtime       $(printf '%064d' 0 | tr 0 f)
EOF
  cat >"$dir/bad-root/Dockerfile" <<EOF
RUN echo "$(printf '%064d' 0)  /opt/rocksdb-11.1.2.tar.gz" | sha256sum -c -
RUN git clone https://example.invalid/c.git /opt/c \\
    && /opt/build-inputs/verify-inputs.sh \\
        git c-kzg-4844 /opt/c \\
        git blst /opt/c/blst \\
    && make
EOF

  expect_violations 0 dockerfile "$dir/good.Dockerfile"
  expect_violations 5 dockerfile "$dir/bad.Dockerfile"
  expect_violations 0 workflow "$dir/good.yml"
  expect_violations 6 workflow "$dir/bad.yml"
  expect_violations 0 inputs "$dir/good-root"
  expect_violations 7 inputs "$dir/bad-root"
  echo "pins-check self-test PASSED"
}

case "${1:-}" in
  "") check_repository ;;
  --self-test) self_test ;;
  -h|--help) sed -n '2,31p' "${BASH_SOURCE[0]}" ;;
  *) echo "usage: scripts/pins-check.sh [--self-test]" >&2; exit 2 ;;
esac
