#!/usr/bin/env bash
#
# Exercise the Hive client adapter without Hive.
#
# Hive cannot run on every machine this repository is developed on, and a Hive
# run is a slow way to discover that the entry point mistyped a flag. This
# starts tools/hive's image the way Hive starts it -- /genesis.json uploaded,
# HIVE_* in the environment, no arguments -- and checks the three things the
# adapter is responsible for: that the genesis translation produces a chain the
# client accepts, that the Engine port authenticates with Hive's fixed secret,
# and that the variables the client cannot honour are refused rather than
# ignored.
#
# It proves the adapter, not conformance. Nothing here says anything about
# whether a Hive suite passes.
#
# Usage: scripts/hive-adapter-smoke.sh [CLIENT_IMAGE]

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
slug="${SMOKE_SLUG:-eth-sec2-hive}"
runtime_image="${RUNTIME_IMAGE:-ethereum-lisp-runtime}"
runtime_tag="${RUNTIME_TAG:-hive-local}"
image="${1:-ethereum-lisp-hive:$runtime_tag}"

# The runtime gate deliberately exercises release architecture images (often
# linux/amd64 on an arm64 workstation).  Propagate the inspected base image
# platform to the wrapper build so BuildKit does not try to resolve a local
# amd64-only tag as a native arm64 manifest.
base_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' \
    "$runtime_image:$runtime_tag" 2>/dev/null || true)"
case "$base_platform" in
    linux/amd64|linux/arm64) ;;
    *)
        echo "FAIL: cannot determine a supported platform for $runtime_image:$runtime_tag" >&2
        exit 1
        ;;
esac

jwt_ascii="secretsecretsecretsecretsecretse"
chain_id=7337
chain_id_hex="0x1ca9"

tmpdir="$(mktemp -d)"
containers=()
cleanup() {
    for c in "${containers[@]:-}"; do
        [ -n "$c" ] && docker rm --force "$c" >/dev/null 2>&1 || true
    done
    rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok - $*"; }

# After the client is up, its own log is usually the only place the reason
# lives -- the JSON-RPC layer answers "Internal error" and says no more.
# $container, not ${containers[-1]}: negative subscripts need bash 4.3 and the
# macOS system bash is 3.2.
fail_with_log() {
    echo "--- client log ---" >&2
    docker logs "$container" 2>&1 | tail -40 >&2
    fail "$@"
}

echo "==> building $image from tools/hive"
docker build \
    --platform "$base_platform" \
    --file "$repo_root/tools/hive/Dockerfile" \
    --build-arg "baseimage=$runtime_image" \
    --build-arg "tag=$runtime_tag" \
    --tag "$image" \
    "$repo_root/tools/hive" >/dev/null

# Shaped like the genesis Hive uploads: a body plus a config that mapper.jq
# replaces wholesale from the environment. The bogus chainId is here on purpose
# -- if the mapping silently failed, eth_chainId would answer 0x1 and the test
# below would catch it.
cat > "$tmpdir/genesis.json" <<'JSON'
{
  "config": { "chainId": 1 },
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
chmod 644 "$tmpdir/genesis.json"

hive_env=(
    --env "HIVE_CHAIN_ID=$chain_id"
    --env "HIVE_NETWORK_ID=$chain_id"
    --env HIVE_FORK_HOMESTEAD=0
    --env HIVE_FORK_TANGERINE=0
    --env HIVE_FORK_SPURIOUS=0
    --env HIVE_FORK_BYZANTIUM=0
    --env HIVE_FORK_CONSTANTINOPLE=0
    --env HIVE_FORK_PETERSBURG=0
    --env HIVE_FORK_ISTANBUL=0
    --env HIVE_FORK_BERLIN=0
    --env HIVE_FORK_LONDON=0
    --env HIVE_MERGE_BLOCK_ID=0
    --env HIVE_TERMINAL_TOTAL_DIFFICULTY=0
    --env HIVE_SHANGHAI_TIMESTAMP=0
    --env HIVE_CANCUN_TIMESTAMP=0
    --env HIVE_LOGLEVEL=3
)

# --- the variables that must be refused -------------------------------------

# Each of these selects behaviour the client does not have. Accepting one and
# running anyway would put a node into a suite it cannot pass for a reason no
# log would explain, so the contract is: exit non-zero, name the variable.
check_refused() { # name value expected-message-fragment
    local name="$1" value="$2" expected="$3"
    local container="$slug-refuse-$$-$RANDOM" output status
    containers+=("$container")
    set +e
    output="$(docker run --name "$container" --label "agent=$slug" \
        "${hive_env[@]}" --env "$name=$value" \
        --mount "type=bind,source=$tmpdir/genesis.json,target=/genesis.json,readonly" \
        "$image" 2>&1)"
    status=$?
    set -e
    docker rm --force "$container" >/dev/null 2>&1 || true
    [ "$status" -ne 0 ] || fail "$name=$value was accepted; it must be refused"
    case "$output" in
        *"$expected"*) ok "$name=$value refused: $expected" ;;
        *) fail "$name=$value exited $status without saying '$expected': $output" ;;
    esac
}

echo "==> refusals"
check_refused HIVE_CLIQUE_PERIOD 1 'HIVE_CLIQUE_*'
check_refused HIVE_MINER 0x0000000000000000000000000000000000000001 'HIVE_MINER'
check_refused HIVE_GRAPHQL_ENABLED 1 'HIVE_GRAPHQL_ENABLED'
check_refused HIVE_NODETYPE snap 'HIVE_NODETYPE=snap'
check_refused HIVE_AMSTERDAM_TIMESTAMP 100 'HIVE_AMSTERDAM_TIMESTAMP'

# --- the normal path --------------------------------------------------------

container="$slug-adapter-$$"
containers+=("$container")
echo "==> starting $image as hive would"
docker run --detach --name "$container" --label "agent=$slug" \
    "${hive_env[@]}" \
    --mount "type=bind,source=$tmpdir/genesis.json,target=/genesis.json,readonly" \
    --publish 127.0.0.1::8545 \
    --publish 127.0.0.1::8551 \
    "$image" >/dev/null

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]; then
    docker logs "$container" 2>&1 | tail -40 >&2
    fail "the adapter exited during startup"
fi

rpc_url="http://$(docker port "$container" 8545 | head -1)"
engine_url="http://$(docker port "$container" 8551 | head -1)"

post() {
    local url="$1"; shift
    if [ $# -gt 0 ] && [ -n "$1" ]; then
        curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
             -H "Authorization: $1" --data @- "$url"
    else
        curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
             --data @- "$url"
    fi
}

ready=0
for _ in $(seq 1 60); do
    if printf '%s' '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        | post "$rpc_url" >/dev/null 2>&1; then
        ready=1; break
    fi
    sleep 1
done
[ "$ready" = "1" ] || { docker logs "$container" 2>&1 | tail -40 >&2; fail "8545 never opened"; }

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | post "$rpc_url")"
case "$response" in
    *"\"result\":\"$chain_id_hex\""*) ok "HIVE_CHAIN_ID=$chain_id reached the client as $chain_id_hex" ;;
    *) fail "eth_chainId returned: $response (mapper.jq did not apply)" ;;
esac

# The eth1 role requires /hive-bin/enode.sh, which must expose exactly the
# dial target reported by admin_nodeInfo.  The container bridge address is
# deliberately asserted rather than merely printed: otherwise an accidental
# regression to 0.0.0.0/loopback would silently exclude the client from devp2p.
node_info="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"admin_nodeInfo","params":[]}' | post "$rpc_url")"
enode="$(docker exec "$container" /hive-bin/enode.sh)"
case "$enode" in
    enode://*@*:[0-9]*) ;;
    *) fail "enode.sh returned '$enode'; admin_nodeInfo said: $node_info" ;;
esac
advertised_host="${enode#*@}"
advertised_host="${advertised_host%%:*}"
case "$advertised_host" in
    0.0.0.0|127.*|::|"")
        fail "enode.sh advertised unroutable host '$advertised_host': $node_info"
        ;;
esac
case "$node_info" in
    *"\"enode\":\"$enode\""*) ok "enode.sh returned routable admin_nodeInfo address" ;;
    *) fail "enode.sh differs from admin_nodeInfo: '$enode' vs $node_info" ;;
esac

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
header="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)"
payload="$(printf '{"iat":%s}' "$(date +%s)" | b64url)"
signature="$(printf '%s' "$header.$payload" | openssl dgst -sha256 -hmac "$jwt_ascii" -binary | b64url)"
token="$header.$payload.$signature"

response="$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"engine_exchangeCapabilities","params":[["engine_newPayloadV3"]]}' \
    | post "$engine_url" "Bearer $token")"
case "$response" in
    *engine_newPayloadV3*) ok "engine_exchangeCapabilities under hive's JWT secret" ;;
    *) fail "engine call with hive's secret returned: $response" ;;
esac

echo "PASS: the hive adapter maps HIVE_* onto flags this client implements"
