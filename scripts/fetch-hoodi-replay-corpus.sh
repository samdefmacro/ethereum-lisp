#!/usr/bin/env bash
# Fetch a Hoodi differential-replay corpus: real blocks plus a reference
# client's view of executing them.
#
# Control-plane tool: bash, curl, jq and a sha256 tool only. It runs no project
# code and makes read-only JSON-RPC calls, one at a time.
#
# For every block N it writes one directory DEST/N/ holding the JSON-RPC
# `result` of each call, verbatim:
#
#   block.json      eth_getBlockByNumber(N, true)
#   raw-block.json  debug_getRawBlock(N): the block's exact RLP, as a hex string
#   receipts.json   eth_getBlockReceipts(N)
#   prestate.json   debug_traceBlockByNumber(N, prestateTracer)
#   diff.json       debug_traceBlockByNumber(N, prestateTracer, diffMode)
#   parent.json     eth_getBlockByNumber(N-1, false)
#   witness.json    debug_executionWitness(N): the trie nodes, bytecodes and
#                   ancestor headers that executing N reads (skipped when
#                   HOODI_REPLAY_WITNESS=0)
#   codes.json      eth_getCode(A, N-1) for each withdrawal recipient A that
#                   has code: crediting a withdrawal runs no code, so a
#                   witness omits it, while the node loads every account's code
#   manifest.json   number, hash, parent hash, source URL, client version and
#                   the sha256 of every file above
#
# The replay test (HOODI-REPLAY-BLOCKS-MATCH-THE-REFERENCE-CLIENT) reads these.
# The witness is what makes the replay exact: its nodes hash to the parent's
# state root, so the pre-state is authenticated by the block hash rather than
# trusted from the server. The traces and receipts are the server's view.
#
# Idempotent and resumable: a block whose manifest verifies is skipped; a block
# is fetched into DEST/.partial-N and renamed into place only when every call
# succeeded and the cross-file checks passed, so an interrupted run leaves no
# half block behind. A block whose manifest does not verify is reported and
# left alone (delete it to fetch it again). A verified block fetched before
# codes.json existed gets it added, and its manifest rewritten, in place. The
# exit status is non-zero when any block failed.
#
# Usage:
#   scripts/fetch-hoodi-replay-corpus.sh [BLOCK | FROM..TO | @FILE]...
#
# With no argument it fetches the default corpus: 3685380..3685600 (the window
# the R6 live run executed, including 3685491), 3684027 (the gas-mismatch block
# of docs/evidence/sec5-hoodi-gas-mismatch.txt, the harness's regression
# control) and 100 blocks sampled evenly across the 50,000 blocks below the
# head. The sample is written to
# DEST/sample-blocks.txt on first use and reused afterwards, so a resumed run
# fetches the same blocks.
#
# Environment:
#   HOODI_REPLAY_DIR      destination (default .hoodi-replay; the basename must
#                         start with .hoodi-replay, which .gitignore covers)
#   HOODI_REPLAY_RPC      endpoint (default https://rpc.hoodi.ethpandaops.io)
#   HOODI_REPLAY_DELAY    seconds between calls (default 0.2)
#   HOODI_REPLAY_TIMEOUT  per-call timeout in seconds (default 300)
#   HOODI_REPLAY_WITNESS  1 (default) to fetch the execution witness, 0 not to

set -euo pipefail

RPC="${HOODI_REPLAY_RPC:-https://rpc.hoodi.ethpandaops.io}"
DEST="${HOODI_REPLAY_DIR:-.hoodi-replay}"
DELAY="${HOODI_REPLAY_DELAY:-0.2}"
TIMEOUT="${HOODI_REPLAY_TIMEOUT:-300}"
WITNESS="${HOODI_REPLAY_WITNESS:-1}"
DEFAULT_FROM=3685380
DEFAULT_TO=3685600
DEFAULT_CONTROLS=3684027
SAMPLE_COUNT=100
SAMPLE_SPAN=50000

die() {
  echo "fetch-hoodi-replay-corpus: $*" >&2
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
case "$WITNESS" in
  0|1) ;;
  *) die "HOODI_REPLAY_WITNESS must be 0 or 1" ;;
esac
[[ "$DELAY" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "HOODI_REPLAY_DELAY must be a number"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "HOODI_REPLAY_TIMEOUT must be an integer"
mkdir -p "$DEST"

# rpc METHOD PARAMS OUT: write the call's `result` to OUT. A transport error,
# an HTTP error, a JSON-RPC error or a null result is retried three times and
# then fails the call.
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
         "$(head -c 300 "$out.curl-error" 2>/dev/null)" \
         "$(jq -c '.error // empty' "$out.response" 2>/dev/null | head -c 300)" >&2
    sleep $((attempt * 3))
  done
  rm -f "$out.response" "$out.curl-error"
  return 1
}

hex() { printf '0x%x' "$1"; }

# count_up FROM TO: the integers FROM..TO, one per line. (BSD seq prints
# seven-digit numbers in exponent form.)
count_up() {
  local i
  for ((i = $1; i <= $2; i++)); do echo "$i"; done
}

corpus_files() {
  echo block.json raw-block.json receipts.json prestate.json diff.json parent.json
  [ "$WITNESS" = 0 ] || echo witness.json
  echo codes.json
}

# fetch_codes DIR N: codes.json, the code of N's withdrawal recipients at N-1.
fetch_codes() {
  local dir="$1" number="$2" address p codes='[]'
  p="\"$(hex $((number - 1)))\""
  for address in $(jq -r '[.withdrawals // [] | .[].address] | unique | .[]' \
                     "$dir/block.json"); do
    rpc eth_getCode "[\"$address\",$p]" "$dir/.code.json" || return 1
    codes="$(jq -c --slurpfile c "$dir/.code.json" \
               'if $c[0] == "0x" then . else . + $c end' <<<"$codes")"
  done
  rm -f "$dir/.code.json"
  printf '%s\n' "$codes" > "$dir/codes.json"
}

# write_manifest DIR N: the manifest over every corpus file DIR holds.
write_manifest() {
  local dir="$1" number="$2" files='{}' name
  for name in $(corpus_files); do
    files="$(jq -c --arg k "$name" --arg v "$(sha256 "$dir/$name")" \
               '. + {($k): $v}' <<<"$files")"
  done
  jq -n --argjson number "$number" --argjson files "$files" \
        --arg source "$RPC" --arg client "$CLIENT_VERSION" \
        --arg fetched "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --slurpfile b "$dir/block.json" \
     '{number: $number, hash: $b[0].hash, parentHash: $b[0].parentHash,
       source: $source, clientVersion: $client, fetchedAt: $fetched,
       files: $files}' > "$dir/manifest.json.tmp"
  mv "$dir/manifest.json.tmp" "$dir/manifest.json"
}

# manifest_verifies DIR: every file the manifest names hashes to its entry.
manifest_verifies() {
  local dir="$1" name expected
  [ -f "$dir/manifest.json" ] || return 1
  while IFS=$'\t' read -r name expected; do
    [ -f "$dir/$name" ] || return 1
    [ "$(sha256 "$dir/$name")" = "$expected" ] || return 1
  done < <(jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$dir/manifest.json")
  if [ "$WITNESS" = 1 ]; then
    jq -e '.files | has("witness.json")' "$dir/manifest.json" >/dev/null || return 1
  fi
}

# check_block DIR N: the cross-file invariants a replay relies on.
check_block() {
  local dir="$1" number="$2"
  jq -e --arg n "$(hex "$number")" '.number == $n and (.hash | test("^0x[0-9a-f]{64}$"))' \
     "$dir/block.json" >/dev/null || { echo "  block.json is not block $number" >&2; return 1; }
  jq -e --arg n "$(hex $((number - 1)))" --slurpfile b "$dir/block.json" \
     '.number == $n and .hash == $b[0].parentHash' "$dir/parent.json" >/dev/null \
    || { echo "  parent.json is not the parent of block $number" >&2; return 1; }
  jq -e 'type == "string" and test("^0x[0-9a-f]+$")' "$dir/raw-block.json" >/dev/null \
    || { echo "  raw-block.json is not a hex string" >&2; return 1; }
  local file
  for file in receipts.json prestate.json diff.json; do
    jq -e --slurpfile b "$dir/block.json" '
      ($b[0].transactions | map(.hash)) as $hashes
      | type == "array" and length == ($hashes | length)
        and ([.[] | (.transactionHash // .txHash)] == $hashes)' \
       "$dir/$file" >/dev/null \
      || { echo "  $file does not follow block $number's transactions" >&2; return 1; }
  done
  if [ "$WITNESS" = 1 ]; then
    jq -e '(.state | type == "array") and (.codes | type == "array")
           and (.headers | type == "array") and (.headers | length > 0)' \
       "$dir/witness.json" >/dev/null \
      || { echo "  witness.json is malformed" >&2; return 1; }
  fi
}

fetch_block() {
  local number="$1" final="$DEST/$1" partial="$DEST/.partial-$1"
  if [ -e "$final" ]; then
    if manifest_verifies "$final"; then
      if jq -e '.files | has("codes.json")' "$final/manifest.json" >/dev/null; then
        echo "block $number: present"
        return 0
      fi
      fetch_codes "$final" "$number" \
        || { echo "block $number: FAILED adding codes.json" >&2; return 1; }
      # Keep what the manifest says about the other files' fetch.
      jq --arg v "$(sha256 "$final/codes.json")" --arg client "$CLIENT_VERSION" \
         --arg fetched "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         '.files["codes.json"] = $v | .codesClientVersion = $client
          | .codesFetchedAt = $fetched' \
         "$final/manifest.json" > "$final/manifest.json.tmp"
      mv "$final/manifest.json.tmp" "$final/manifest.json"
      echo "block $number: codes.json added"
      return 0
    fi
    echo "block $number: $final exists but its manifest does not verify; delete it to fetch again" >&2
    return 1
  fi
  rm -rf "$partial"
  mkdir -p "$partial"
  local n p
  n="\"$(hex "$number")\""
  p="\"$(hex $((number - 1)))\""
  echo "block $number: fetching"
  rpc eth_getBlockByNumber "[$n,true]" "$partial/block.json" \
    && rpc debug_getRawBlock "[$n]" "$partial/raw-block.json" \
    && rpc eth_getBlockReceipts "[$n]" "$partial/receipts.json" \
    && rpc debug_traceBlockByNumber "[$n,{\"tracer\":\"prestateTracer\"}]" \
           "$partial/prestate.json" \
    && rpc debug_traceBlockByNumber \
           "[$n,{\"tracer\":\"prestateTracer\",\"tracerConfig\":{\"diffMode\":true}}]" \
           "$partial/diff.json" \
    && rpc eth_getBlockByNumber "[$p,false]" "$partial/parent.json" \
    && { [ "$WITNESS" = 0 ] \
           || rpc debug_executionWitness "[$n]" "$partial/witness.json"; } \
    && check_block "$partial" "$number" \
    && fetch_codes "$partial" "$number" \
    || { echo "block $number: FAILED" >&2; rm -rf "$partial"; return 1; }
  write_manifest "$partial" "$number"
  mv "$partial" "$final"
  echo "block $number: done"
}

ensure_sample() {
  local sample="$DEST/sample-blocks.txt"
  [ ! -s "$sample" ] || return 0
  local head_file="$DEST/.head.json" head step i
  rpc eth_blockNumber '[]' "$head_file" || die "cannot read the head block number"
  head=$(( $(jq -r . "$head_file") ))
  rm -f "$head_file"
  step=$((SAMPLE_SPAN / SAMPLE_COUNT))
  for ((i = 0; i < SAMPLE_COUNT; i++)); do
    echo $((head - SAMPLE_SPAN + i * step))
  done > "$sample.tmp"
  mv "$sample.tmp" "$sample"
}

expand_argument() {
  local argument="$1"
  if [[ "$argument" =~ ^[0-9]+$ ]]; then
    echo "$argument"
  elif [[ "$argument" =~ ^([0-9]+)\.\.([0-9]+)$ ]]; then
    [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] || die "empty range $argument"
    count_up "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$argument" == @* ]]; then
    local file="${argument#@}" line
    [ -f "$file" ] || die "no such block list: $file"
    while read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      [[ "$line" =~ ^[0-9]+$ ]] || die "bad block number in $file: $line"
      echo "$line"
    done < "$file"
  else
    die "unrecognised argument $argument (expected N, FROM..TO or @FILE)"
  fi
}

version_file="$DEST/.client-version.json"
rpc web3_clientVersion '[]' "$version_file" || die "cannot reach $RPC"
CLIENT_VERSION="$(jq -r . "$version_file")"
rm -f "$version_file"
echo "source: $RPC ($CLIENT_VERSION)"

# Expand the selection in this shell, through a file, so a bad argument or an
# unreachable head stops the run instead of silently shortening the list.
list="$DEST/.selection.txt"
if [ "$#" -eq 0 ]; then
  ensure_sample
  { count_up "$DEFAULT_FROM" "$DEFAULT_TO"
    printf '%s\n' $DEFAULT_CONTROLS
    cat "$DEST/sample-blocks.txt"; } > "$list"
else
  : > "$list"
  for argument in "$@"; do
    expand_argument "$argument" >> "$list" || exit 2
  done
fi
blocks=()
while read -r number; do blocks+=("$number"); done < "$list"
rm -f "$list"
[ "${#blocks[@]}" -gt 0 ] || die "no blocks selected"

failed=0
for number in "${blocks[@]}"; do
  [ "$number" -gt 0 ] || die "block 0 has no parent"
  fetch_block "$number" || failed=$((failed + 1))
done
echo "blocks: ${#blocks[@]} selected, $failed failed"
[ "$failed" -eq 0 ]
