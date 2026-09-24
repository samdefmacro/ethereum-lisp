#!/usr/bin/env bash
#
# Release artifacts written next to an exported runtime image archive.
#
#   scripts/release-artifacts.sh sbom IMAGE ARTIFACT
#       ARTIFACT.sbom.cdx.json: a CycloneDX 1.5 SBOM of IMAGE.
#   scripts/release-artifacts.sh validate-sbom SBOM
#       Check SBOM against the CycloneDX 1.5 schema with the CycloneDX
#       project's validator (digest-pinned container, no network).
#   scripts/release-artifacts.sh provenance IMAGE ARTIFACT
#       ARTIFACT.provenance.json: an in-toto v1 Statement with a SLSA v1
#       provenance predicate whose subject is the archive's SHA-256, naming
#       the source revision, the inputs.lock SHA-256, the base image digest,
#       the builder, and the SBOM's SHA-256 as a byproduct.
#   scripts/release-artifacts.sh checksums ARTIFACT
#       ARTIFACT.SHA256SUMS over the archive, the SBOM and the provenance.
#   COSIGN_PASSWORD=... scripts/release-artifacts.sh generate-key DIR
#       An encrypted cosign key pair in DIR, which must lie outside the
#       checkout. For a local signer; keep a real release key elsewhere.
#   COSIGN_KEY=PATH COSIGN_PASSWORD=... scripts/release-artifacts.sh sign ARTIFACT
#       ARTIFACT.SHA256SUMS.sig, a cosign signature over the checksum file,
#       made offline (no transparency-log upload) with the key file PATH.
#
# scripts/dev.sh runtime-export runs sbom, provenance and checksums after
# `docker image save`; scripts/dev.sh runtime-sign runs sign; and
# scripts/release-verify.sh checks all of it offline. The key is never in the
# repository and never passed on a command line: COSIGN_KEY names a file
# outside the checkout (refused otherwise) and COSIGN_PASSWORD reaches the
# container through the environment only. Nothing here builds or compiles anything and no
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

# ---------------------------------------------------------------------------
# Provenance, checksums and signature.
# ---------------------------------------------------------------------------

# Signing runs cosign v2.6.5 by index digest (linux/amd64 and linux/arm64):
# networkless, read-only, no capabilities, the host user, and no host path but
# the key and the one file it signs or checks.
COSIGN_IMAGE=gcr.io/projectsigstore/cosign:v2.6.5@sha256:ad281047f85c5e1fc6ffbc30c2b55be3b07b4032bef715a12122ce5829619aca
SOURCE_REPO="${RELEASE_SOURCE_REPO:-https://github.com/samdefmacro/ethereum-lisp}"
BUILD_TYPE="$SOURCE_REPO/blob/main/docs/runbook.md#release-verification"

sha256_file() { sha256_stdin <"$1"; }

# write_provenance OUT KEY=VALUE... : an in-toto v1 Statement with a SLSA v1
# provenance predicate, one field per line so release-verify.sh can read it
# back without a JSON tool. Every value is passed in, so the self-test can
# build one without Docker.
write_provenance() {
  local out="$1" subject_name subject_sha revision lock_sha image image_id
  local platform sbom_name sbom_sha builder_version started finished base kv
  shift
  for kv in "$@"; do
    case "$kv" in
      subject_name=*) subject_name="${kv#*=}" ;;
      subject_sha=*) subject_sha="${kv#*=}" ;;
      revision=*) revision="${kv#*=}" ;;
      lock_sha=*) lock_sha="${kv#*=}" ;;
      image=*) image="${kv#*=}" ;;
      image_id=*) image_id="${kv#*=}" ;;
      platform=*) platform="${kv#*=}" ;;
      sbom_name=*) sbom_name="${kv#*=}" ;;
      sbom_sha=*) sbom_sha="${kv#*=}" ;;
      builder_version=*) builder_version="${kv#*=}" ;;
      started=*) started="${kv#*=}" ;;
      finished=*) finished="${kv#*=}" ;;
      base=*) base="${kv#*=}" ;;
      *) die "write_provenance: unknown field $kv" ;;
    esac
  done
  {
    printf '{\n'
    printf '"_type": "https://in-toto.io/Statement/v1",\n'
    printf '"subject": [\n'
    printf '{"name": %s,\n "digest": {"sha256": %s}}\n' "$(json "$subject_name")" "$(json "$subject_sha")"
    printf '],\n'
    printf '"predicateType": "https://slsa.dev/provenance/v1",\n'
    printf '"predicate": {\n'
    printf '"buildDefinition": {\n'
    printf '"buildType": %s,\n' "$(json "$BUILD_TYPE")"
    printf '"externalParameters": {\n'
    printf '"source": %s,\n' "$(json "$SOURCE_REPO")"
    printf '"revision": %s,\n' "$(json "$revision")"
    printf '"dockerfile": "Dockerfile.runtime",\n'
    printf '"image": %s,\n' "$(json "$image")"
    printf '"platform": %s\n' "$(json "$platform")"
    printf '},\n'
    printf '"resolvedDependencies": [\n'
    printf '{"uri": %s,\n "digest": {"gitCommit": %s}},\n' \
      "$(json "git+$SOURCE_REPO@$revision")" "$(json "$revision")"
    printf '{"uri": %s,\n "digest": {"sha256": %s}},\n' \
      "$(json "git+$SOURCE_REPO@$revision#tools/build-inputs/inputs.lock")" "$(json "$lock_sha")"
    printf '{"uri": %s,\n "digest": {"sha256": %s}}\n' \
      "$(json "pkg:docker/${base%@*}")" "$(json "${base##*sha256:}")"
    printf ']\n'
    printf '},\n'
    printf '"runDetails": {\n'
    printf '"builder": {"id": %s,\n "version": {"docker": %s}},\n' \
      "$(json "$SOURCE_REPO/blob/$revision/scripts/dev.sh#runtime-build")" "$(json "$builder_version")"
    printf '"metadata": {"invocationId": %s,\n "startedOn": %s,\n "finishedOn": %s},\n' \
      "$(json "$image_id")" "$(json "$started")" "$(json "$finished")"
    printf '"byproducts": [\n'
    printf '{"name": %s,\n "mediaType": "application/vnd.cyclonedx+json",\n "digest": {"sha256": %s}},\n' \
      "$(json "$sbom_name")" "$(json "$sbom_sha")"
    printf '{"name": "image-id",\n "digest": {"sha256": %s}}\n' "$(json "${image_id#sha256:}")"
    printf ']\n'
    printf '}\n'
    printf '}\n'
    printf '}\n'
  } >"$out.tmp"
  mv "$out.tmp" "$out"
}

# The base image the runtime stage is built FROM, read from Dockerfile.runtime
# at the image's revision (the last FROM line; digest-pinned by pins-check).
runtime_base_image() { # REVISION
  git -C "$ROOT" show "$1:Dockerfile.runtime" \
    | awk 'toupper($1) == "FROM" && $2 ~ /@sha256:/ { ref = $2 } END { print ref }'
}

provenance() { # IMAGE ARTIFACT
  [ "$#" -eq 2 ] || die "usage: release-artifacts.sh provenance IMAGE ARTIFACT"
  local image="$1" artifact="$2" out="$2.provenance.json" sbom="$2.sbom.cdx.json"
  local revision image_id platform lock_sha base
  [ -f "$artifact" ] || die "no archive at $artifact"
  [ -f "$sbom" ] || die "no SBOM at $sbom; run the sbom step first"
  [ ! -e "$out" ] || die "refusing existing provenance: $out"
  revision="$("$DOCKER" image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || die "image $image carries no revision label"
  image_id="$("$DOCKER" image inspect --format '{{.Id}}' "$image")"
  platform="$("$DOCKER" image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
  lock_sha="$(git -C "$ROOT" show "$revision:$LOCK_PATH" | sha256_stdin)"
  base="$(runtime_base_image "$revision")"
  [ -n "$base" ] || die "no digest-pinned FROM in Dockerfile.runtime at $revision"
  write_provenance "$out" \
    "subject_name=$(basename "$artifact")" \
    "subject_sha=$(sha256_file "$artifact")" \
    "revision=$revision" \
    "lock_sha=$lock_sha" \
    "image=$image" \
    "image_id=$image_id" \
    "platform=$platform" \
    "sbom_name=$(basename "$sbom")" \
    "sbom_sha=$(sha256_file "$sbom")" \
    "builder_version=$("$DOCKER" version --format '{{.Server.Version}}')" \
    "started=$("$DOCKER" image inspect --format '{{.Created}}' "$image")" \
    "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "base=$base"
  printf 'provenance %s sha256 %s\n' "$out" "$(sha256_file "$out")"
}

# ARTIFACT.SHA256SUMS: the one file the signature covers. It names the archive,
# the SBOM and the provenance by base name, so the four travel as a set.
write_sums() { # ARTIFACT
  local artifact="$1" dir base out="$1.SHA256SUMS" file
  dir="$(dirname "$artifact")"
  base="$(basename "$artifact")"
  [ ! -e "$out" ] || die "refusing existing checksum file: $out"
  for file in "$base" "$base.sbom.cdx.json" "$base.provenance.json"; do
    [ -f "$dir/$file" ] || die "missing $dir/$file"
    printf '%s  %s\n' "$(sha256_file "$dir/$file")" "$file"
  done >"$out.tmp"
  mv "$out.tmp" "$out"
  printf 'checksums %s\n' "$out"
}

refuse_inside_checkout() { # PATH WHAT
  local path
  path="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  case "$path/" in
    "$(cd "$ROOT" && pwd -P)"/*) die "$2 must live outside the repository: $1" ;;
  esac
}

cosign_run() { # MOUNT... -- COSIGN-ARGS...
  local -a mounts=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    mounts+=(--mount "$1")
    shift
  done
  shift
  "$DOCKER" run --rm --network none --read-only \
    --cap-drop ALL --security-opt no-new-privileges \
    --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:mode=1777 --env HOME=/tmp \
    --label io.common-lisp-workbench.project=ethereum-lisp \
    --env COSIGN_PASSWORD \
    ${mounts[@]+"${mounts[@]}"} \
    "$COSIGN_IMAGE" "$@"
}

# generate-key DIR: an encrypted cosign key pair in DIR (outside the checkout),
# protected by COSIGN_PASSWORD. For a local or throwaway signer; a release key
# belongs in the operator's own custody, never in the repository.
generate_key() {
  [ "$#" -eq 1 ] || die "usage: release-artifacts.sh generate-key DIR"
  local dir="$1"
  [ -n "${COSIGN_PASSWORD+set}" ] || die "set COSIGN_PASSWORD (may be empty) first"
  mkdir -p "$dir"
  dir="$(cd "$dir" && pwd -P)"
  refuse_inside_checkout "$dir/cosign.key" "the signing key"
  [ ! -e "$dir/cosign.key" ] && [ ! -e "$dir/cosign.pub" ] || die "refusing existing key in $dir"
  cosign_run "type=bind,src=$dir,dst=/keys" -- \
    generate-key-pair --output-key-prefix /keys/cosign >/dev/null
  printf 'public key %s sha256 %s\n' "$dir/cosign.pub" "$(sha256_file "$dir/cosign.pub")"
}

# sign ARTIFACT: signs ARTIFACT.SHA256SUMS with the key file COSIGN_KEY (an
# encrypted cosign key, outside the checkout; COSIGN_PASSWORD unlocks it) and
# writes ARTIFACT.SHA256SUMS.sig. No transparency-log upload: the signature is
# verified offline against the published public key.
sign() {
  [ "$#" -eq 1 ] || die "usage: COSIGN_KEY=PATH release-artifacts.sh sign ARTIFACT"
  local artifact="$1" sums="$1.SHA256SUMS" key="${COSIGN_KEY:-}"
  [ -n "$key" ] && [ -f "$key" ] || die "COSIGN_KEY must name the private key file"
  [ -n "${COSIGN_PASSWORD+set}" ] || die "set COSIGN_PASSWORD for $key"
  refuse_inside_checkout "$key" "the signing key"
  [ -f "$sums" ] || die "no checksum file at $sums"
  [ ! -e "$sums.sig" ] || die "refusing existing signature: $sums.sig"
  cosign_run \
    "type=bind,src=$(cd "$(dirname "$key")" && pwd -P)/$(basename "$key"),dst=/run/cosign/cosign.key,readonly" \
    "type=bind,src=$(cd "$(dirname "$sums")" && pwd -P)/$(basename "$sums"),dst=/run/release/SHA256SUMS,readonly" \
    -- sign-blob --yes --tlog-upload=false --key /run/cosign/cosign.key \
       /run/release/SHA256SUMS >"$sums.sig.tmp" 2>/dev/null \
    || { rm -f "$sums.sig.tmp"; die "cosign sign-blob failed"; }
  mv "$sums.sig.tmp" "$sums.sig"
  printf 'signature %s\n' "$sums.sig"
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
  provenance) provenance "$@" ;;
  checksums) [ "$#" -eq 1 ] || die "usage: release-artifacts.sh checksums ARTIFACT"; write_sums "$1" ;;
  generate-key) generate_key "$@" ;;
  sign) sign "$@" ;;
  # For scripts/release-verify.sh --self-test only: a provenance statement
  # from explicit values, with no image.
  write-provenance) [ "$#" -ge 1 ] || die "usage: write-provenance OUT KEY=VALUE..."; write_provenance "$@" ;;
  -h|--help|"") sed -n '2,/^$/p' "${BASH_SOURCE[0]}" ;;
  *) die "unknown command: $cmd" ;;
esac
