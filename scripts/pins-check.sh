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

check_repository() {
  local file dockerfiles=0 workflows=0
  while IFS= read -r file; do
    case "$file" in
      Dockerfile|*/Dockerfile|Dockerfile.*|*/Dockerfile.*|*.Dockerfile|*.dockerfile)
        dockerfiles=$((dockerfiles + 1))
        check_dockerfile "$ROOT/$file" "$file"
        ;;
      .github/workflows/*.yml|.github/workflows/*.yaml|.github/actions/*/action.yml|.github/actions/*/action.yaml)
        workflows=$((workflows + 1))
        check_workflow "$ROOT/$file" "$file"
        ;;
    esac
  done < <(git -C "$ROOT" ls-files)
  printf 'pins-check: %d Dockerfiles (%d FROM lines), %d workflows (%d uses lines), %d violations\n' \
    "$dockerfiles" "$from_lines" "$workflows" "$uses_lines" "$violations"
  # A check that selected nothing is not a pass.
  if [ "$from_lines" -eq 0 ] || [ "$uses_lines" -eq 0 ]; then
    echo "ERROR: pins-check selected no FROM or no uses line" >&2
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

  expect_violations 0 dockerfile "$dir/good.Dockerfile"
  expect_violations 5 dockerfile "$dir/bad.Dockerfile"
  expect_violations 0 workflow "$dir/good.yml"
  expect_violations 6 workflow "$dir/bad.yml"
  echo "pins-check self-test PASSED"
}

case "${1:-}" in
  "") check_repository ;;
  --self-test) self_test ;;
  -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" ;;
  *) echo "usage: scripts/pins-check.sh [--self-test]" >&2; exit 2 ;;
esac
