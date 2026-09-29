#!/usr/bin/env bash
# Add a reference callTracer trace to blocks of a Hoodi replay corpus.
#
# Control-plane tool: bash, curl, jq and a sha256 tool only. It runs no project
# code and makes read-only JSON-RPC calls, one at a time.
#
# For every block N already in the corpus (scripts/fetch-hoodi-replay-corpus.sh)
# it writes, next to that block's files:
#
#   calltrace.json           the `result` of debug_traceBlockByNumber(N,
#                            {"tracer":"callTracer"}), verbatim
#   calltrace.manifest.json  number, block hash, source URL, client version,
#                            fetch time and the sha256 of calltrace.json
#
# The block's own manifest.json is left alone, so a corpus fetched before this
# script still verifies. HOODI-REPLAY-CALL-TRACES-MATCH-THE-REFERENCE compares
# our debug_traceBlockByNumber with calltrace.json for every block that has
# one. A block that already has a verifying calltrace.manifest.json is skipped.
#
# Usage:
#   scripts/fetch-hoodi-call-traces.sh BLOCK...
#
# Environment: HOODI_REPLAY_DIR, HOODI_REPLAY_RPC, HOODI_REPLAY_DELAY and
# HOODI_REPLAY_TIMEOUT, as for fetch-hoodi-replay-corpus.sh.

set -euo pipefail

RPC="${HOODI_REPLAY_RPC:-https://rpc.hoodi.ethpandaops.io}"
DEST="${HOODI_REPLAY_DIR:-.hoodi-replay}"
DELAY="${HOODI_REPLAY_DELAY:-0.2}"
TIMEOUT="${HOODI_REPLAY_TIMEOUT:-300}"

die() {
  echo "fetch-hoodi-call-traces: $*" >&2
  exit 2
}

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "sha256sum or shasum is required"
fi
case "$(basename "$DEST")" in
  .hoodi-replay*) ;;
  *) die "HOODI_REPLAY_DIR must name a .hoodi-replay* directory, got $DEST" ;;
esac
[[ "$DELAY" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "HOODI_REPLAY_DELAY must be a number"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "HOODI_REPLAY_TIMEOUT must be an integer"
[ "$#" -gt 0 ] || die "name at least one block"

# rpc METHOD PARAMS OUT: write the call's `result` to OUT, retrying a failed
# call three times.
rpc() {
  local method="$1" params="$2" out="$3" attempt
  local body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
  for attempt in 1 2 3 4; do
    if curl -sS --fail -m "$TIMEOUT" -X POST \
         -H 'content-type: application/json' --data "$body" \
         -o "$out.response" "$RPC" 2>"$out.curl-error" \
       && jq -e 'type == "object" and (has("error") | not)
                 and has("result") and .result != null' \
            "$out.response" >/dev/null 2>&1; then
      jq -c '.result' "$out.response" > "$out"
      rm -f "$out.response" "$out.curl-error"
      sleep "$DELAY"
      return 0
    fi
    echo "  $method attempt $attempt failed:" \
         "$(head -c 300 "$out.curl-error" 2>/dev/null)" >&2
    sleep $((attempt * 3))
  done
  rm -f "$out.response" "$out.curl-error"
  return 1
}

failed=0
for number in "$@"; do
  [[ "$number" =~ ^[0-9]+$ ]] || die "not a block number: $number"
  dir="$DEST/$number"
  if [ ! -f "$dir/manifest.json" ]; then
    echo "block $number: not in the corpus ($dir/manifest.json missing)" >&2
    failed=1
    continue
  fi
  if [ -f "$dir/calltrace.manifest.json" ] && [ -f "$dir/calltrace.json" ] \
     && [ "$(jq -r '.sha256' "$dir/calltrace.manifest.json")" \
          = "$(sha256 "$dir/calltrace.json")" ]; then
    echo "block $number: calltrace.json verifies, skipped"
    continue
  fi
  block_hash="$(jq -r '.hash' "$dir/manifest.json")"
  tmp="$dir/.calltrace.json.partial"
  client="$dir/.calltrace-client.partial"
  if rpc debug_traceBlockByNumber \
         "[\"$(printf '0x%x' "$number")\",{\"tracer\":\"callTracer\"}]" "$tmp" \
     && rpc web3_clientVersion '[]' "$client" \
     && [ "$(jq -r 'length' "$tmp")" \
          = "$(jq -r '.transactions | length' "$dir/block.json")" ]; then
    mv "$tmp" "$dir/calltrace.json"
    jq -n --argjson number "$number" --arg hash "$block_hash" \
          --arg source "$RPC" --arg client "$(jq -r '.' "$client")" \
          --arg fetched "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          --arg sha "$(sha256 "$dir/calltrace.json")" \
       '{number: $number, hash: $hash, source: $source,
         clientVersion: $client, fetchedAt: $fetched, sha256: $sha}' \
       > "$dir/calltrace.manifest.json"
    rm -f "$client"
    echo "block $number: calltrace.json fetched"
  else
    rm -f "$tmp" "$client"
    echo "block $number: failed" >&2
    failed=1
  fi
done
exit "$failed"
