#!/usr/bin/env bash
#
# Release artifacts written next to an exported runtime image archive.
#
#   scripts/release-artifacts.sh sbom IMAGE ARTIFACT
#       ARTIFACT.sbom.cdx.json: a CycloneDX 1.5 SBOM of IMAGE.
#   scripts/release-artifacts.sh validate-sbom SBOM
#       Check SBOM against the CycloneDX 1.5 schema with the CycloneDX
#       project's validator (digest-pinned container, no network).
#
# scripts/dev.sh runtime-export calls this after `docker image save`; it is
# not a separate release step. Nothing here builds or compiles anything and no
# third-party tool is installed: the image's own package database and file
# digests are read by running IMAGE itself, networkless, read-only, as its own
# non-root user and with no capabilities; the build inputs come from
# tools/build-inputs/inputs.lock AT THE IMAGE'S REVISION (git show), not from
# the working tree; the JSON is assembled here in plain shell.
#
# What the SBOM lists (plan section 10):
#   metadata.component  the image: revision, image ID, platform, and the
#                       SHA-256 of the inputs.lock it was built from
#   components          every Debian package installed in the image (dpkg);
#                       every file below /usr/local and /opt, which dpkg does
#                       not know (the client executable, RocksDB, libethckzg,
#                       libethbls, the io_uring probe, the KZG setup, the
#                       genesis allocations), each with its SHA-256; and every
#                       inputs.lock entry of the image's architecture: scope
#                       "required" for what is compiled or copied into the
#                       image (SBCL, RocksDB, c-kzg-4844, blst, the Quicklisp
#                       systems), "excluded" for build-only inputs (the
#                       Quicklisp client and dist indexes)
# The output is a function of the image and the revision only: the timestamp
# is the commit time and the serial number is derived from the image ID, so
# two exports of one image produce the same bytes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
LOCK_PATH=tools/build-inputs/inputs.lock

die() { echo "ERROR: $*" >&2; exit 2; }

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

json() { # a JSON string literal; refuses control characters
  local s="$1"
  case "$s" in
    *[$'\001'-$'\037']*) die "control character in SBOM value: $s" ;;
  esac
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

property() { # NAME VALUE
  printf '{"name":%s,"value":%s}' "$(json "$1")" "$(json "$2")"
}

purl_name() { # pkg:type/ns/NAME@version?q -> NAME
  local purl="${1%%@*}"
  printf '%s' "${purl##*/}"
}

purl_version() {
  local purl="${1#*@}"
  printf '%s' "${purl%%\?*}"
}

# Prints, as tab-separated lines: os ID VERSION_ID / deb NAME VERSION ARCH /
# file PATH SHA256. Runs the image under test with nothing it could reach.
image_listing() { # IMAGE PLATFORM
  "$DOCKER" run --rm -i --platform "$2" --network none --read-only \
    --cap-drop ALL --security-opt no-new-privileges \
    --label io.common-lisp-workbench.project=ethereum-lisp \
    --entrypoint /bin/sh "$1" -s <<'LISTING'
set -eu
. /etc/os-release
printf 'os\t%s\t%s\n' "$ID" "$VERSION_ID"
dpkg-query -W -f='deb\t${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort
find /usr/local /opt -type f -exec sha256sum {} + | LC_ALL=C sort -k2 \
  | while read -r sum path; do printf 'file\t%s\t%s\n' "$path" "$sum"; done
LISTING
}

sbom() { # IMAGE ARTIFACT
  [ "$#" -eq 2 ] || die "usage: release-artifacts.sh sbom IMAGE ARTIFACT"
  local image="$1" artifact="$2" out="$2.sbom.cdx.json"
  local revision image_id platform arch lock lock_sha timestamp serial listing
  local kind a b c distro="" first=1 name larch scope sha purl cscope hashes
  [ ! -e "$out" ] || die "refusing existing SBOM: $out"
  revision="$("$DOCKER" image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || die "image $image carries no revision label"
  image_id="$("$DOCKER" image inspect --format '{{.Id}}' "$image")"
  platform="$("$DOCKER" image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
  arch="${platform#*/}"
  lock="$(git -C "$ROOT" show "$revision:$LOCK_PATH")" \
    || die "revision $revision has no $LOCK_PATH"
  lock_sha="$(printf '%s\n' "$lock" | sha256_stdin)"
  timestamp="$(TZ=UTC git -C "$ROOT" show -s \
    --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$revision")"
  serial="$(printf 'ethereum-lisp-sbom %s' "$image_id" | sha256_stdin)"
  serial="${serial:0:8}-${serial:8:4}-5${serial:13:3}-8${serial:17:3}-${serial:20:12}"
  listing="$(image_listing "$image" "$platform")"

  {
    printf '{\n"bomFormat":"CycloneDX",\n"specVersion":"1.5",\n'
    printf '"serialNumber":"urn:uuid:%s",\n"version":1,\n' "$serial"
    printf '"metadata":{"timestamp":%s,\n' "$(json "$timestamp")"
    printf ' "tools":{"components":[{"type":"application","name":"scripts/release-artifacts.sh","version":%s}]},\n' \
      "$(json "$revision")"
    printf ' "component":{"type":"container","bom-ref":"image","name":"ethereum-lisp-runtime","version":%s,\n' \
      "$(json "$revision")"
    printf '  "properties":[%s,%s,%s,%s]}},\n' \
      "$(property org.opencontainers.image.revision "$revision")" \
      "$(property ethereum-lisp:image-id "$image_id")" \
      "$(property ethereum-lisp:platform "$platform")" \
      "$(property ethereum-lisp:inputs-lock-sha256 "$lock_sha")"
    printf '"components":[\n'

    while IFS=$'\t' read -r kind a b c; do
      case "$kind" in
        os) distro="$a-$b" ;;
        deb)
          [ "$first" -eq 1 ] || printf ',\n'
          first=0
          purl="pkg:deb/${distro%%-*}/$a@$b?arch=$c&distro=$distro"
          printf '{"type":"library","bom-ref":%s,"name":%s,"version":%s,"purl":%s,"scope":"required"}' \
            "$(json "$purl")" "$(json "$a")" "$(json "$b")" "$(json "$purl")"
          ;;
        file)
          [ "$first" -eq 1 ] || printf ',\n'
          first=0
          printf '{"type":"file","bom-ref":%s,"name":%s,"hashes":[{"alg":"SHA-256","content":%s}],"scope":"required"}' \
            "$(json "file:$a")" "$(json "$a")" "$(json "$b")"
          ;;
      esac
    done <<<"$listing"

    while read -r name larch scope sha purl; do
      case "$name" in ''|'#'*) continue ;; esac
      [ "$larch" = any ] || [ "$larch" = "$arch" ] || continue
      case ",$scope," in
        *,runtime,*) cscope=required ;;
        *,build,*) cscope=excluded ;;
        *) continue ;;
      esac
      # A file input's lock digest is the file's SHA-256; a git or Debian
      # input's is a tree digest (verify-inputs.sh), so it is a property only.
      case "$name" in
        ql-archive/*|quicklisp-*|rocksdb-source)
          hashes=",\"hashes\":[{\"alg\":\"SHA-256\",\"content\":$(json "$sha")}]" ;;
        *) hashes="" ;;
      esac
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '{"type":"library","bom-ref":%s,"name":%s,"version":%s,"purl":%s%s,"scope":%s,"properties":[%s,%s,%s]}' \
        "$(json "input:$name:$larch")" "$(json "$(purl_name "$purl")")" \
        "$(json "$(purl_version "$purl")")" "$(json "$purl")" "$hashes" "$(json "$cscope")" \
        "$(property ethereum-lisp:input "$name")" \
        "$(property ethereum-lisp:input-scope "$scope")" \
        "$(property ethereum-lisp:inputs-lock-sha256 "$sha")"
    done <<<"$lock"
    printf '\n]\n}\n'
  } >"$out.tmp"
  mv "$out.tmp" "$out"
  printf 'sbom %s sha256 %s\n' "$out" "$(sha256_stdin <"$out")"
}

# The CycloneDX project's own validator, by index digest, networkless and
# read-only; it reads only the SBOM. Used by validate-sbom and release-verify.
CYCLONEDX_CLI_IMAGE=cyclonedx/cyclonedx-cli:0.33.1@sha256:252c2e26f468c25fea1e63ecde1bc3198ad6e9dbb57f5ed3236bddcb2281b3a7

validate_sbom() { # SBOM
  [ "$#" -eq 1 ] || die "usage: release-artifacts.sh validate-sbom SBOM"
  local sbom
  [ -f "$1" ] || die "no SBOM at $1"
  sbom="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  "$DOCKER" run --rm --network none --read-only \
    --cap-drop ALL --security-opt no-new-privileges \
    --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:exec,mode=1777 --env HOME=/tmp \
    --env DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    --label io.common-lisp-workbench.project=ethereum-lisp \
    --mount "type=bind,src=$sbom,dst=/in/sbom.cdx.json,readonly" \
    "$CYCLONEDX_CLI_IMAGE" validate \
      --input-file /in/sbom.cdx.json --input-format json \
      --input-version v1_5 --fail-on-errors
}

cmd="${1:-}"
[ "$#" -eq 0 ] || shift
case "$cmd" in
  sbom) sbom "$@" ;;
  validate-sbom) validate_sbom "$@" ;;
  -h|--help|"") sed -n '2,/^$/p' "${BASH_SOURCE[0]}" ;;
  *) die "unknown command: $cmd" ;;
esac
