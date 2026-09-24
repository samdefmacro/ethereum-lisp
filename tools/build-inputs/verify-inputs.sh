#!/bin/bash
#
# Fail a Docker build closed when a downloaded input is not the pinned one.
#
# Runs INSIDE the build (Dockerfile and Dockerfile.runtime COPY this directory
# to /opt/build-inputs), right after each download and before anything loads,
# executes or compiles what was downloaded. The pins live in inputs.lock next
# to this script; see its header for the format.
#
#   verify-inputs.sh CHECK [CHECK ...]
#
#   file NAME PATH       SHA-256 of one file
#   git NAME DIR         the checkout's HEAD must be the commit the PURL names,
#                        and the tree digest (below) must match
#   deb NAME PACKAGE     the installed Debian package must be the version the
#                        PURL names, and the digest of its files under
#                        /usr/bin and /usr/lib/PACKAGE must match (per arch)
#   quicklisp-dist DIR   distinfo.txt, systems.txt and releases.txt, and every
#                        archives/*.tgz, each against its own entry; an archive
#                        with no entry fails, and so does an empty archives/
#
# Tree digest: SHA-256 of the `sha256sum` listing of every regular file below
# DIR (paths relative, .git excluded, byte-sorted), plus one "link PATH ->
# TARGET" line per symlink. It does not depend on the git version, clone depth
# or file modes, only on content and names.
#
# Every check runs even after one fails, so a single build prints every
# mismatch. A failing check prints INPUT-MISMATCH and a `record:` line holding
# the observed value in inputs.lock format; the exit status is 1. Never paste a
# record line without checking the input it describes came from where it
# should (see inputs.lock).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK="${BUILD_INPUTS_LOCK:-$HERE/inputs.lock}"
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
failures=0

die() { echo "verify-inputs: $*" >&2; exit 2; }

# lock_field NAME COLUMN -> the column of NAME's entry for this arch (or any).
lock_field() {
  awk -v name="$1" -v arch="$ARCH" -v column="$2" '
    /^[[:space:]]*(#|$)/ { next }
    $1 == name && ($2 == arch || $2 == "any") { print $column; found = 1; exit }
    END { if (!found) exit 1 }' "$LOCK"
}

purl_version() { # pkg:type/ns/name@VERSION?qualifiers -> VERSION
  local purl="$1"
  purl="${purl#*@}"
  printf '%s' "${purl%%\?*}"
}

tree_digest() {
  (
    cd "$1"
    find . -name .git -prune -o -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 --no-run-if-empty sha256sum
    find . -name .git -prune -o -type l -print0 \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' link; do
          printf 'link %s -> %s\n' "$link" "$(readlink "$link")"
        done
  ) | sha256sum | cut -d' ' -f1
}

compare() { # NAME ACTUAL [RECORD-ARCH [RECORD-SCOPE RECORD-PURL]]
  local name="$1" actual="$2" expected
  expected="$(lock_field "$name" 4 || true)"
  if [ -n "$expected" ] && [ "$expected" = "$actual" ]; then
    echo "input ok: $name ($ARCH) sha256 $actual"
    return 0
  fi
  failures=$((failures + 1))
  if [ -z "$expected" ]; then
    echo "INPUT-MISMATCH: $name ($ARCH) has no entry in inputs.lock" >&2
  else
    echo "INPUT-MISMATCH: $name ($ARCH) expected sha256 $expected, got $actual" >&2
  fi
  printf 'record: %s %s %s %s %s\n' "$name" "${3:-any}" "${4:-SCOPE}" \
    "$actual" "${5:-$(lock_field "$name" 5 || echo PURL)}" >&2
}

check_file() {
  [ -f "$2" ] || die "file $1: missing $2"
  compare "$1" "$(sha256sum "$2" | cut -d' ' -f1)"
}

check_git() {
  local name="$1" dir="$2" want head
  [ -d "$dir" ] || die "git $name: missing $dir"
  want="$(purl_version "$(lock_field "$name" 5 || echo '@none')")"
  head="$(git -C "$dir" rev-parse HEAD)"
  if [ "$head" != "$want" ]; then
    failures=$((failures + 1))
    echo "INPUT-MISMATCH: $name HEAD is $head, inputs.lock pins $want" >&2
  fi
  compare "$name" "$(tree_digest "$dir")"
}

check_deb() {
  local name="$1" package="$2" want version digest
  want="$(purl_version "$(lock_field "$name" 5 || echo '@none')")"
  version="$(dpkg-query -W -f '${Version}' "$package")"
  if [ "$version" != "$want" ]; then
    failures=$((failures + 1))
    echo "INPUT-MISMATCH: $name is Debian $package $version, inputs.lock pins $want" >&2
  fi
  digest="$(
    dpkg -L "$package" \
      | { grep -E "^/usr/(bin|lib/$package)/" || true; } \
      | while IFS= read -r path; do
          if [ -f "$path" ] && [ ! -L "$path" ]; then printf '%s\n' "$path"; fi
        done \
      | LC_ALL=C sort \
      | xargs --no-run-if-empty sha256sum \
      | sha256sum | cut -d' ' -f1
  )"
  compare "$name" "$digest" "$ARCH"
}

check_quicklisp_dist() {
  local dir="$1" index archive base line project url prefix count=0
  [ -d "$dir" ] || die "quicklisp-dist: missing $dir"
  for index in distinfo systems releases; do
    check_file "quicklisp-dist-$index" "$dir/$index.txt"
  done
  for archive in "$dir"/archives/*.tgz; do
    [ -f "$archive" ] || continue
    count=$((count + 1))
    base="$(basename "$archive")"
    # releases.txt: project url size file-md5 content-sha1 prefix [system-file...]
    line="$(awk -v f="$base" '
      !/^#/ { n = split($2, p, "/"); if (p[n] == f) { print $1, $2, $6; exit } }' \
      "$dir/releases.txt")"
    project="${line%% *}"
    url="$(printf '%s' "$line" | cut -d' ' -f2)"
    prefix="${line##* }"
    compare "ql-archive/$base" "$(sha256sum "$archive" | cut -d' ' -f1)" any SCOPE \
      "pkg:generic/$project@${prefix#"$project"-}?download_url=$url"
  done
  if [ "$count" -eq 0 ]; then
    failures=$((failures + 1))
    echo "INPUT-MISMATCH: quicklisp-dist $dir/archives holds no archive" >&2
  else
    echo "input ok: $count Quicklisp archives checked"
  fi
}

[ -f "$LOCK" ] || die "no inputs.lock at $LOCK"
[ "$#" -gt 0 ] || die "usage: verify-inputs.sh CHECK [CHECK ...]"
while [ "$#" -gt 0 ]; do
  case "$1" in
    file) [ "$#" -ge 3 ] || die "file NAME PATH"; check_file "$2" "$3"; shift 3 ;;
    git) [ "$#" -ge 3 ] || die "git NAME DIR"; check_git "$2" "$3"; shift 3 ;;
    deb) [ "$#" -ge 3 ] || die "deb NAME PACKAGE"; check_deb "$2" "$3"; shift 3 ;;
    quicklisp-dist) [ "$#" -ge 2 ] || die "quicklisp-dist DIR"; check_quicklisp_dist "$2"; shift 2 ;;
    *) die "unknown check: $1" ;;
  esac
done
if [ "$failures" -ne 0 ]; then
  echo "verify-inputs: $failures input(s) differ from inputs.lock; build refused" >&2
  exit 1
fi
