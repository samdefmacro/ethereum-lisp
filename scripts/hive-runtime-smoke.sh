#!/usr/bin/env bash
#
# Smoke-test the runtime client image: start it from a genesis, then prove over
# the wire that the public and Engine endpoints answer.
#
# This is the part of the Hive gate that can be a real, blocking check today.
# It does not need Hive, a simulator, or a network of clients -- it needs only
# the image this repository builds -- so it catches the failure modes that would
# otherwise show up as an unexplained "client failed to start" inside a Hive
# run: a missing shared library, a saved core that will not restart, a
# non-root user that cannot write its datadir, an Engine port that accepts an
# unsigned request.
#
# Usage: scripts/hive-runtime-smoke.sh [IMAGE]
#   IMAGE defaults to $RUNTIME_IMAGE:$RUNTIME_TAG, itself defaulting to
#   ethereum-lisp-runtime:hive-local.
#
# Everything runs in containers except curl and openssl, which are host CLI
# tools. Ports are published ephemerally on 127.0.0.1 and read back, never
# fixed: this machine runs several agents at once and a hardcoded 8545 would
# either collide or, worse, silently answer from somebody else's node.

set -euo pipefail

image="${1:-${RUNTIME_IMAGE:-ethereum-lisp-runtime}:${RUNTIME_TAG:-hive-local}}"
slug="${SMOKE_SLUG:-eth-sec2-hive}"
container="$slug-smoke-$$"
chain_id_hex="0x539"   # 1337

# The same secret tools/hive/ethereum-lisp.sh writes, which is Hive's
# globals.DefaultJwtTokenSecretBytes: 32 ASCII bytes. Being ASCII is what lets
# `openssl dgst -hmac` take it directly, with no hexkey support required.
jwt_ascii="secretsecretsecretsecretsecretse"
jwt_hex="0x7365637265747365637265747365637265747365637265747365637265747365"

tmpdir="$(mktemp -d)"
cleanup() {
    docker rm --force "$container" >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok - $*"; }

cat > "$tmpdir/genesis.json" <<JSON
{
  "config": {
    "chainId": 1337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "mergeNetsplitBlock": 0,
    "terminalTotalDifficulty": 0,
    "terminalTotalDifficultyPassed": true,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "blobSchedule": {
      "cancun": { "target": 3, "max": 6, "baseFeeUpdateFraction": 3338477 }
    }
  },
  "nonce": "0x0",
  "timestamp": "0x0",
  "extraData": "0x",
  "gasLimit": "0x1c9c380",
  "difficulty": "0x0",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
    "0x0000000000000000000000000000000000001001": { "balance": "0xde0b6b3a7640000" }
  }
}
JSON
printf '%s\n' "$jwt_hex" > "$tmpdir/jwtsecret"
chmod 644 "$tmpdir/genesis.json" "$tmpdir/jwtsecret"

# The built-in presets resolve their allocation RLP through
# ASDF:SYSTEM-RELATIVE-PATHNAME at call time, which in a SAVE-LISP-AND-DIE image
# means the .asd path recorded at build time. Nothing else in this script would
# notice if that path stopped existing in the runtime layer, and the failure
# would surface as --hoodi being broken for an operator rather than in CI.
echo "==> built-in genesis presets"
preset_summary="$(docker run --rm --label "$slug-preset=1" --label "agent=$slug" \
    --read-only --mount type=tmpfs,destination=/data,tmpfs-mode=1777 \
    "$image" --hoodi --datadir /data --no-serve 2>&1)" || true
case "$preset_summary" in
    *":CHAIN-ID 560048"*) ok "--hoodi built its genesis from the packaged allocation" ;;
    *) fail "--hoodi did not build: $preset_summary" ;;
esac

echo "==> starting $image as $container"
# Not --rm: a container that dies during startup takes its logs with it, and
# that log is the whole diagnosis. cleanup() removes it either way.
docker run --detach \
    --name "$container" \
    --label "agent=$slug" \
    --read-only \
    --mount type=tmpfs,destination=/data,tmpfs-mode=1777 \
    --mount "type=bind,source=$tmpdir,target=/config,readonly" \
    --publish 127.0.0.1::8545 \
    --publish 127.0.0.1::8551 \
    "$image" \
    --genesis /config/genesis.json \
    --datadir /data \
    --networkid 1337 \
    --http --http.addr 0.0.0.0 --http.port 8545 \
    --http.api eth,net,web3,txpool \
    --http.vhosts '*' \
    --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
    --authrpc.jwtsecret /config/jwtsecret \
    --authrpc.vhosts '*' >/dev/null

if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]; then
    echo "--- container log ---" >&2
    docker logs "$container" 2>&1 | tail -40 >&2
    fail "the client exited during startup"
fi

rpc_url="http://$(docker port "$container" 8545 | head -1)"
engine_url="http://$(docker port "$container" 8551 | head -1)"
echo "    public RPC $rpc_url, engine $engine_url"

post() { # url [authorization-header]
    local url="$1"; shift
    if [ $# -gt 0 ] && [ -n "$1" ]; then
        curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
             -H "Authorization: $1" --data @- "$url"
    else
        curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
             --data @- "$url"
    fi
}

echo "==> waiting for the public endpoint"
ready=0
for _ in $(seq 1 60); do
    if printf '%s' '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        | post "$rpc_url" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
[ "$ready" = "1" ] || { docker logs "$container" 2>&1 | tail -40; fail "client never opened 8545"; }

# --- public RPC -------------------------------------------------------------

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | post "$rpc_url")"
case "$response" in
    *"\"result\":\"$chain_id_hex\""*) ok "eth_chainId = $chain_id_hex" ;;
    *) fail "eth_chainId returned: $response" ;;
esac

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' | post "$rpc_url")"
case "$response" in
    *ethereum-lisp*) ok "web3_clientVersion = $response" ;;
    *) fail "web3_clientVersion returned: $response" ;;
esac

# --- Engine API -------------------------------------------------------------

# Unauthenticated first. If this ever succeeds the JWT is not being enforced,
# and every later "the Engine API works" claim is worthless.
status="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"engine_exchangeCapabilities","params":[[]]}' \
    | curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' --data @- "$engine_url")"
[ "$status" = "401" ] || fail "unauthenticated engine call returned HTTP $status, expected 401"
ok "unauthenticated engine_exchangeCapabilities rejected with 401"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
header="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)"
payload="$(printf '{"iat":%s}' "$(date +%s)" | b64url)"
signature="$(printf '%s' "$header.$payload" \
    | openssl dgst -sha256 -hmac "$jwt_ascii" -binary | b64url)"
token="$header.$payload.$signature"

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"engine_exchangeCapabilities","params":[["engine_newPayloadV2"]]}' \
    | post "$engine_url" "Bearer $token")"
case "$response" in
    *engine_newPayloadV2*) ok "authenticated engine_exchangeCapabilities answered" ;;
    *) fail "authenticated engine call returned: $response" ;;
esac

# engine_getClientVersionV1 is what Hive records as the client identity, so a
# broken one turns every result row anonymous.
response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"engine_getClientVersionV1","params":[{"code":"XX","name":"hive","version":"0","commit":"0x00000000"}]}' \
    | post "$engine_url" "Bearer $token")"
case "$response" in
    *ethereum-lisp*) ok "engine_getClientVersionV1 = $response" ;;
    *) fail "engine_getClientVersionV1 returned: $response" ;;
esac

# --- the eth_* subset the Engine port must also serve -----------------------

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}' \
    | post "$engine_url" "Bearer $token")"
case "$response" in
    *result*) ok "eth_syncing on the Engine port answered" ;;
    *) fail "eth_syncing on the Engine port returned: $response" ;;
esac

echo "PASS: runtime image $image serves public RPC and an authenticated Engine API"
