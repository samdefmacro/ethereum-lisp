#!/usr/bin/env bash
#
# Verify a signed runtime release offline: signature, checksums, provenance,
# SBOM, and the image inside the archive, against each other.
#
#   scripts/release-verify.sh ARTIFACT PUBLIC-KEY
#   scripts/release-verify.sh --self-test
#
# ARTIFACT is the exported image archive (ethereum-lisp-runtime-*.tar); next to
# it must lie ARTIFACT.sbom.cdx.json, ARTIFACT.provenance.json,
# ARTIFACT.SHA256SUMS and ARTIFACT.SHA256SUMS.sig, as written by
# scripts/dev.sh runtime-export and runtime-sign. PUBLIC-KEY is the signer's
# cosign.pub, obtained from the signer, not from next to the archive.
#
# Checks, in order; the first failure ends the run with exit 1:
#   1. the cosign signature over ARTIFACT.SHA256SUMS verifies with PUBLIC-KEY
#      (cosign in a digest-pinned container, no network, no transparency log);
#   2. ARTIFACT.SHA256SUMS names exactly the archive, the SBOM and the
#      provenance, and each file's SHA-256 matches;
#   3. inside the archive every blob hashes to its own name, the image ID the
#      SBOM records is the archive's index entry, that index reaches the
#      config manifest.json names, and the config's revision label is the
#      revision the SBOM and provenance record;
#   4. the provenance is an in-toto v1 / SLSA v1 statement whose subject is the
#      archive (name and SHA-256), whose invocation is that image ID, whose
#      source commit and inputs.lock SHA-256 are the SBOM's, and whose SBOM
#      byproduct is this SBOM's SHA-256;
#   5. the SBOM is valid CycloneDX 1.5 (the CycloneDX validator, pinned, no
#      network);
#   6. when this checkout holds that revision, inputs.lock there hashes to the
#      recorded SHA-256 (skipped, and said so, otherwise).
# No JSON tool is needed on the host: the provenance and SBOM are read in the
# exact layout scripts/release-artifacts.sh writes, and anything else fails.
#
# --self-test builds a small synthetic release in a temporary directory with a
# throwaway key, requires it to verify, then requires each of six mutations
# to fail for its own reason (tampered archive, tampered SBOM with rewritten
# checksums, another signer's key, a mismatched provenance or SBOM that was
# re-signed, a tampered image config inside a re-signed archive).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
ARTIFACTS="$ROOT/scripts/release-artifacts.sh"
LOCK_PATH=tools/build-inputs/inputs.lock
COSIGN_IMAGE="$(sed -n 's/^COSIGN_IMAGE=//p' "$ARTIFACTS")"

fail() { echo "release-verify: FAIL: $*" >&2; exit 1; }
say() { echo "release-verify: $*"; }

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

sha256_file() { sha256_stdin <"$1"; }

abs() { printf '%s/%s' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"; }

# The file with its newlines removed, so a check can name a whole field.
flat() { tr -d '\n' <"$1"; }

contains() { # HAYSTACK NEEDLE
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

verify_signature() { # SUMS SIG PUBKEY
  "$DOCKER" run --rm --network none --read-only \
    --cap-drop ALL --security-opt no-new-privileges \
    --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777 --env HOME=/tmp \
    --label io.common-lisp-workbench.project=ethereum-lisp \
    --mount "type=bind,src=$(abs "$3"),dst=/run/cosign/cosign.pub,readonly" \
    --mount "type=bind,src=$(abs "$1"),dst=/run/release/SHA256SUMS,readonly" \
    --mount "type=bind,src=$(abs "$2"),dst=/run/release/SHA256SUMS.sig,readonly" \
    "$COSIGN_IMAGE" verify-blob --insecure-ignore-tlog=true \
      --key /run/cosign/cosign.pub \
      --signature /run/release/SHA256SUMS.sig \
      /run/release/SHA256SUMS >/dev/null 2>&1
}

tar_member() { tar -xOf "$1" "$2" 2>/dev/null; }

verify() { # ARTIFACT PUBKEY
  local artifact="$1" pubkey="$2" dir base sbom prov sums sig
  local line want got name count=0 image_id revision lock_sha tar_sha sbom_sha
  local sbom_flat prov_flat config linked=0 index blob digest members blobs=""
  [ -f "$artifact" ] || fail "no archive at $artifact"
  [ -f "$pubkey" ] || fail "no public key at $pubkey"
  dir="$(dirname "$artifact")"
  base="$(basename "$artifact")"
  sbom="$artifact.sbom.cdx.json"
  prov="$artifact.provenance.json"
  sums="$artifact.SHA256SUMS"
  sig="$artifact.SHA256SUMS.sig"
  for name in "$sbom" "$prov" "$sums" "$sig"; do
    [ -f "$name" ] || fail "missing $name"
  done

  # 1. Signature.
  verify_signature "$sums" "$sig" "$pubkey" \
    || fail "signature over $(basename "$sums") does not verify with $pubkey"
  say "signature ok ($(basename "$sums"), key sha256 $(sha256_file "$pubkey"))"

  # 2. Checksums: exactly these three names, each matching.
  while IFS= read -r line; do
    count=$((count + 1))
    want="${line%%  *}"
    name="${line#*  }"
    case "$name" in
      "$base"|"$base.sbom.cdx.json"|"$base.provenance.json") ;;
      *) fail "SHA256SUMS names an unexpected file: $name" ;;
    esac
    got="$(sha256_file "$dir/$name")"
    [ "$got" = "$want" ] || fail "$name has sha256 $got, SHA256SUMS says $want"
  done <"$sums"
  [ "$count" -eq 3 ] || fail "SHA256SUMS has $count lines, want 3"
  tar_sha="$(sha256_file "$artifact")"
  sbom_sha="$(sha256_file "$sbom")"
  say "checksums ok (archive sha256 $tar_sha)"

  # The identities the SBOM records (metadata.component properties).
  sbom_flat="$(flat "$sbom")"
  revision="$(printf '%s' "$sbom_flat" \
    | grep -Eo '\{"name":"org\.opencontainers\.image\.revision","value":"[0-9a-f]{40}"\}' \
    | head -1 | grep -Eo '[0-9a-f]{40}' || true)"
  image_id="$(printf '%s' "$sbom_flat" \
    | grep -Eo '\{"name":"ethereum-lisp:image-id","value":"sha256:[0-9a-f]{64}"\}' \
    | head -1 | grep -Eo 'sha256:[0-9a-f]{64}' || true)"
  lock_sha="$(printf '%s' "$sbom_flat" \
    | grep -Eo '"component":\{"type":"container".*"ethereum-lisp:inputs-lock-sha256","value":"[0-9a-f]{64}"\}\]\}\}' \
    | grep -Eo '"ethereum-lisp:inputs-lock-sha256","value":"[0-9a-f]{64}"' \
    | head -1 | grep -Eo '[0-9a-f]{64}' || true)"
  [ -n "$revision" ] && [ -n "$image_id" ] && [ -n "$lock_sha" ] \
    || fail "SBOM does not record a revision, image ID and inputs.lock SHA-256"

  # 3. The image inside the archive, read member by member (nothing unpacked).
  members="$(tar -tf "$artifact")" || fail "cannot read the archive"
  for blob in $(printf '%s\n' "$members" | grep -E '^blobs/sha256/[0-9a-f]{64}$' || true); do
    [ "$(tar_member "$artifact" "$blob" | sha256_stdin)" = "${blob##*/}" ] \
      || fail "archive blob ${blob##*/} does not hash to its name"
    blobs="$blobs ${blob##*/}"
  done
  config="$(tar_member "$artifact" manifest.json \
    | grep -Eo '"Config":"blobs/sha256/[0-9a-f]{64}"' | head -1 | grep -Eo '[0-9a-f]{64}' || true)"
  [ -n "$config" ] && contains "$blobs " " $config " || fail "manifest.json names no config blob"
  if [ "sha256:$config" = "$image_id" ]; then
    linked=1   # classic image store: the image ID is the config digest
  else
    index="$(tar_member "$artifact" index.json | tr -d '\n' || true)"
    contains "$index" "\"digest\":\"$image_id\"" || fail "image ID $image_id is not the archive's index entry"
    contains "$blobs " " ${image_id#sha256:} " || fail "archive lacks the blob of $image_id"
    for digest in $(tar_member "$artifact" "blobs/sha256/${image_id#sha256:}" \
                      | grep -Eo 'sha256:[0-9a-f]{64}' | sort -u || true); do
      if contains "$blobs " " ${digest#sha256:} " && \
         tar_member "$artifact" "blobs/sha256/${digest#sha256:}" | grep -Eq "\"digest\": ?\"sha256:$config\""; then
        linked=1
      fi
    done
  fi
  [ "$linked" -eq 1 ] || fail "image ID $image_id does not reach config $config"
  tar_member "$artifact" "blobs/sha256/$config" \
    | grep -q "\"org.opencontainers.image.revision\":\"$revision\"" \
    || fail "image config does not carry revision $revision"
  say "image ok ($image_id, config sha256:$config, revision $revision)"

  # 4. Provenance.
  prov_flat="$(flat "$prov")"
  for want in \
    "\"_type\": \"https://in-toto.io/Statement/v1\"" \
    "\"subject\": [{\"name\": \"$base\", \"digest\": {\"sha256\": \"$tar_sha\"}}]," \
    "\"predicateType\": \"https://slsa.dev/provenance/v1\"" \
    "\"revision\": \"$revision\"," \
    "\"digest\": {\"gitCommit\": \"$revision\"}}" \
    "#tools/build-inputs/inputs.lock\", \"digest\": {\"sha256\": \"$lock_sha\"}}" \
    "\"invocationId\": \"$image_id\"," \
    "{\"name\": \"$base.sbom.cdx.json\", \"mediaType\": \"application/vnd.cyclonedx+json\", \"digest\": {\"sha256\": \"$sbom_sha\"}}"
  do
    contains "$prov_flat" "$want" || fail "provenance lacks: $want"
  done
  say "provenance ok (subject $base, source $revision, inputs.lock sha256 $lock_sha)"

  # 5. SBOM schema.
  "$ARTIFACTS" validate-sbom "$sbom" >/dev/null 2>&1 || fail "SBOM is not valid CycloneDX 1.5"
  say "sbom ok (CycloneDX 1.5, sha256 $sbom_sha)"

  # 6. The lock at that revision, when this checkout has it.
  if git -C "$ROOT" cat-file -e "$revision^{commit}" 2>/dev/null; then
    got="$(git -C "$ROOT" show "$revision:$LOCK_PATH" | sha256_stdin)"
    [ "$got" = "$lock_sha" ] || fail "inputs.lock at $revision hashes to $got, the release says $lock_sha"
    say "source ok (inputs.lock at $revision matches)"
  else
    say "source not checked: this checkout does not hold $revision"
  fi
  say "PASS $base"
}

# ---------------------------------------------------------------------------
# Self-test: a synthetic release that must verify, and six that must not.
# ---------------------------------------------------------------------------

expect_fail() { # REASON-SUBSTRING ARTIFACT PUBKEY
  local out
  if out="$(verify "$2" "$3" 2>&1)"; then
    printf '%s\n' "$out" >&2
    echo "SELF-TEST FAILED: a release that must fail ($1) verified" >&2
    exit 1
  fi
  contains "$out" "$1" || {
    printf '%s\n' "$out" >&2
    echo "SELF-TEST FAILED: expected a failure naming '$1'" >&2
    exit 1
  }
  echo "self-test ok: refused ($1)"
}

self_test() {
  local work rev lock_sha a pub config config_sha index_sha
  work="$(mktemp -d "${TMPDIR:-/tmp}/ethereum-lisp-release-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
  rev="$(git -C "$ROOT" rev-parse HEAD)"
  lock_sha="$(git -C "$ROOT" show "HEAD:$LOCK_PATH" | sha256_stdin)"
  export COSIGN_PASSWORD=self-test

  make_release() { # NAME REVISION-IN-CONFIG
    local name="$1" label_rev="$2" image
    image="$work/$name.image"
    mkdir -p "$image/blobs/sha256"
    printf '{"architecture":"amd64","config":{"Labels":{"org.opencontainers.image.revision":"%s"}},"os":"linux"}' \
      "$label_rev" >"$image/config"
    config_sha="$(sha256_file "$image/config")"
    mv "$image/config" "$image/blobs/sha256/$config_sha"
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:%s","size":1},"layers":[]}' \
      "$config_sha" >"$image/manifest"
    local manifest_sha
    manifest_sha="$(sha256_file "$image/manifest")"
    mv "$image/manifest" "$image/blobs/sha256/$manifest_sha"
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest": "sha256:%s","size":1}]}' \
      "$manifest_sha" >"$image/index"
    index_sha="$(sha256_file "$image/index")"
    mv "$image/index" "$image/blobs/sha256/$index_sha"
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.index.v1+json","digest":"sha256:%s","size":1}]}' \
      "$index_sha" >"$image/index.json"
    printf '[{"Config":"blobs/sha256/%s","RepoTags":["ethereum-lisp-runtime:self-test"],"Layers":[]}]' \
      "$config_sha" >"$image/manifest.json"
    (cd "$image" && tar -cf "$work/$name.tar" manifest.json index.json blobs)
  }

  write_sbom() { # ARTIFACT REVISION IMAGE-ID LOCK-SHA
    cat >"$1.sbom.cdx.json" <<EOF
{
"bomFormat":"CycloneDX",
"specVersion":"1.5",
"serialNumber":"urn:uuid:00000000-0000-5000-8000-000000000000",
"version":1,
"metadata":{"timestamp":"2026-01-01T00:00:00Z",
 "component":{"type":"container","bom-ref":"image","name":"ethereum-lisp-runtime","version":"$2",
  "properties":[{"name":"org.opencontainers.image.revision","value":"$2"},{"name":"ethereum-lisp:image-id","value":"$3"},{"name":"ethereum-lisp:platform","value":"linux/amd64"},{"name":"ethereum-lisp:inputs-lock-sha256","value":"$4"}]}},
"components":[
]
}
EOF
  }

  write_rest() { # ARTIFACT REVISION IMAGE-ID  (provenance, checksums, signature)
    rm -f "$1.provenance.json" "$1.SHA256SUMS" "$1.SHA256SUMS.sig"
    "$ARTIFACTS" write-provenance "$1.provenance.json" \
      "subject_name=$(basename "$1")" "subject_sha=$(sha256_file "$1")" \
      "revision=$2" "lock_sha=$lock_sha" "image=ethereum-lisp-runtime:self-test" \
      "image_id=$3" "platform=linux/amd64" \
      "sbom_name=$(basename "$1").sbom.cdx.json" "sbom_sha=$(sha256_file "$1.sbom.cdx.json")" \
      "builder_version=self-test" "started=2026-01-01T00:00:00Z" \
      "finished=2026-01-01T00:00:01Z" \
      "base=debian:bookworm-slim@sha256:$(printf '%064d' 0)"
    "$ARTIFACTS" checksums "$1" >/dev/null
    COSIGN_KEY="$work/keys/cosign.key" "$ARTIFACTS" sign "$1" >/dev/null
  }

  "$ARTIFACTS" generate-key "$work/keys" >/dev/null
  "$ARTIFACTS" generate-key "$work/other-keys" >/dev/null
  pub="$work/keys/cosign.pub"

  a="$work/ethereum-lisp-runtime-self-test.tar"
  make_release ethereum-lisp-runtime-self-test "$rev"
  write_sbom "$a" "$rev" "sha256:$index_sha" "$lock_sha"
  write_rest "$a" "$rev" "sha256:$index_sha"
  verify "$a" "$pub" >/dev/null || { verify "$a" "$pub" || true; echo "SELF-TEST FAILED: the clean release did not verify" >&2; exit 1; }
  echo "self-test ok: clean synthetic release verifies"

  expect_fail "signature over" "$a" "$work/other-keys/cosign.pub"

  cp "$a" "$a.orig"
  printf 'x' >>"$a"
  expect_fail "SHA256SUMS says" "$a" "$pub"
  mv "$a.orig" "$a"

  # An SBOM changed after signing, with the checksum file rewritten to match:
  # only the signature can catch it.
  cp "$a.sbom.cdx.json" "$a.sbom.orig"
  cp "$a.SHA256SUMS" "$a.sums.orig"
  sed -i.bak 's/linux\/amd64/linux\/arm64/' "$a.sbom.cdx.json"
  rm -f "$a.SHA256SUMS" "$a.sbom.cdx.json.bak"
  "$ARTIFACTS" checksums "$a" >/dev/null
  expect_fail "signature over" "$a" "$pub"
  mv "$a.sbom.orig" "$a.sbom.cdx.json"
  mv "$a.sums.orig" "$a.SHA256SUMS"

  # Correctly signed, internally inconsistent: the provenance names another
  # revision.
  write_rest "$a" "$(printf '%040d' 0)" "sha256:$index_sha"
  expect_fail "provenance lacks" "$a" "$pub"

  # Correctly signed, but the SBOM records an image ID the archive lacks.
  write_sbom "$a" "$rev" "sha256:$(printf '%064d' 0)" "$lock_sha"
  write_rest "$a" "$rev" "sha256:$(printf '%064d' 0)"
  expect_fail "is not the archive's index entry" "$a" "$pub"

  # Correctly signed, but the image config inside carries another revision.
  rm -f "$a"
  make_release ethereum-lisp-runtime-self-test "$(printf '%040d' 1)"
  write_sbom "$a" "$rev" "sha256:$index_sha" "$lock_sha"
  write_rest "$a" "$rev" "sha256:$index_sha"
  expect_fail "does not carry revision" "$a" "$pub"

  echo "release-verify self-test PASSED"
}

case "${1:-}" in
  --self-test) [ "$#" -eq 1 ] || exit 2; self_test ;;
  -h|--help|"") sed -n '2,/^$/p' "${BASH_SOURCE[0]}" ;;
  *) [ "$#" -eq 2 ] || { echo "usage: scripts/release-verify.sh ARTIFACT PUBLIC-KEY" >&2; exit 2; }
     verify "$1" "$2" ;;
esac
