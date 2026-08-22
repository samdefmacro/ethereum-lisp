#!/usr/bin/env bash
set -euo pipefail

# Same-host Hoodi SNAP benchmark for the already-pinned geth image. This gate
# preserves both clients and both datadirs, gives only one EL the stable
# Lighthouse alias at a time, and rolls back every failed cutover.

action="${1:-status}"
host="${HOODI_GETH_HOST:-test-ethereum-server}"
image="${HOODI_GETH_IMAGE:-ethereum/client-go:v1.17.4}"
expected_image_id="${HOODI_GETH_IMAGE_ID:-sha256:9389d3371a5cde510edb5dfa10a759f7ef98bd8676e6491ce79ab1050306478b}"
container="${HOODI_GETH_CONTAINER:-hoodi-geth-v1.17.4-baseline}"
datadir="${HOODI_GETH_DATADIR:-/data/hoodi-sec5-20260814/geth-v1.17.4-baseline}"
source="${HOODI_GETH_SOURCE_CONTAINER:-hoodi-el-sec5-ebaa1084}"
lighthouse="${HOODI_GETH_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
cl_network="${HOODI_GETH_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_GETH_EGRESS_NETWORK:-hoodi-net}"
cl_alias="${HOODI_GETH_CL_ALIAS:-hoodi-el-public-36a22e47}"
jwt_dir="${HOODI_GETH_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_GETH_PUBLIC_IP:-165.154.224.110}"
p2p_port="${HOODI_GETH_P2P_PORT:-30303}"
ready_timeout="${HOODI_GETH_READY_TIMEOUT:-600}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_mutation() {
    [ "${HOODI_GETH_ALLOW_MUTATION:-}" = 1 ] ||
        fail "$action changes remote state; set HOODI_GETH_ALLOW_MUTATION=1 after explicit authorization"
}

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$image" in *[!A-Za-z0-9_.:/@+-]*|'') fail "unsafe image: $image" ;; esac
case "$expected_image_id" in sha256:*) ;; *) fail "image id must use sha256" ;; esac
image_digest="${expected_image_id#sha256:}"
case "$image_digest" in *[!0-9a-f]*|'') fail "unsafe image digest" ;; esac
[ "${#image_digest}" -eq 64 ] || fail "image id must contain a 64-character digest"
case "$container" in *[!A-Za-z0-9_.-]*|'') fail "unsafe container: $container" ;; esac
case "$source" in *[!A-Za-z0-9_.-]*|'') fail "unsafe source container: $source" ;; esac
case "$datadir" in /data/hoodi-sec5-*/geth-*) ;; *) fail "unsafe geth datadir: $datadir" ;; esac
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$p2p_port" in *[!0-9]*|'') fail "P2P port must be an integer" ;; esac
[ "$p2p_port" -ge 1024 ] && [ "$p2p_port" -le 65535 ] || fail "P2P port is out of range"
case "$ready_timeout" in *[!0-9]*|'') fail "ready timeout must be an integer" ;; esac
[ "$ready_timeout" -ge 30 ] && [ "$ready_timeout" -le 1800 ] || fail "ready timeout is out of range"

status() {
    ssh "$host" bash -s -- "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
actual="$(docker image inspect --format '{{.Id}}' "$image")"
printf 'geth-image=%s actual=%s expected=%s platform=' "$image" "$actual" "$expected"
docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image"
for network in "$cl_network" "$egress_network"; do
    docker network inspect --format 'network={{.Name}} driver={{.Driver}} internal={{.Internal}}' "$network"
done
for name in "$container" "$source" "$lighthouse"; do
    if docker container inspect "$name" >/dev/null 2>&1; then
        docker container inspect --format \
            'container={{.Name}} running={{.State.Running}} image={{.Image}} user={{.Config.User}} labels={{json .Config.Labels}}' \
            "$name"
    else
        printf 'container=/%s absent\n' "$name"
    fi
done
if [ -d "$datadir" ]; then
    if [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        du -sh "$datadir"
    else
        printf 'geth-datadir=%s empty\n' "$datadir"
    fi
else
    printf 'geth-datadir=%s absent\n' "$datadir"
fi
REMOTE
}

start() {
    require_mutation
    ssh "$host" bash -s -- "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" "$cl_alias" \
        "$jwt_dir" "$public_ip" "$p2p_port" "$ready_timeout" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"; cl_alias="$9"
jwt_dir="${10}"; public_ip="${11}"; p2p_port="${12}"; ready_timeout="${13}"

[ "$(docker image inspect --format '{{.Id}}' "$image")" = "$expected" ] || {
    echo "geth image id mismatch" >&2; exit 1;
}
[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = linux/amd64 ] || {
    echo "geth image platform mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$source")" = true ] || {
    echo "source EL is not running: $source" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$lighthouse")" = true ] || {
    echo "Lighthouse is not running: $lighthouse" >&2; exit 1;
}
source_agent="$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$source")"
[ "$source_agent" = codex-sec5-live-gate ] || { echo "source EL ownership mismatch" >&2; exit 1; }
source_user="$(docker container inspect --format '{{.Config.User}}' "$source")"
case "$source_user" in 0|0:*|*:0|'') echo "source EL user is not an explicit non-root user" >&2; exit 1 ;; esac
docker network inspect "$cl_network" >/dev/null
docker network inspect "$egress_network" >/dev/null
[ -r "$jwt_dir/jwt.hex" ] || { echo "JWT secret is not readable" >&2; exit 1; }
if docker container inspect "$container" >/dev/null 2>&1; then
    echo "refusing existing geth benchmark container: $container" >&2; exit 1
fi
if [ -d "$datadir" ] && [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "refusing non-empty geth benchmark datadir: $datadir" >&2; exit 1
fi
mkdir -p "$datadir"
uid="${source_user%%:*}"; gid="${source_user##*:}"
chown "$uid:$gid" "$datadir"

docker run --rm --pull never --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --network none --entrypoint geth \
    "$expected" version >/dev/null

docker stop --time 30 "$source" >/dev/null
rollback() {
    docker stop --time 10 "$container" >/dev/null 2>&1 || true
    docker start "$source" >/dev/null 2>&1 || true
}
trap rollback EXIT HUP INT TERM
docker run --detach --pull never \
    --name "$container" \
    --label agent=codex-geth-same-host-benchmark \
    --label "io.ethereum-lisp.benchmark-source=$source" \
    --label "io.ethereum-lisp.benchmark-image=$expected" \
    --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" --network-alias "$cl_alias" \
    --publish "$p2p_port:$p2p_port/tcp" --publish "$p2p_port:$p2p_port/udp" \
    --publish 127.0.0.1::8545 \
    "$expected" \
    --hoodi --datadir /data --syncmode snap --state.scheme path --cache 4096 \
    --port "$p2p_port" --nat "extip:$public_ip" --maxpeers 50 --ipcdisable \
    --http --http.addr 0.0.0.0 --http.port 8545 \
    --http.api eth,net,web3,txpool,admin --http.vhosts '*' \
    --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
    --authrpc.jwtsecret /jwt/jwt.hex --authrpc.vhosts '*' >/dev/null
docker network connect "$egress_network" "$container"

rpc_port="$(docker port "$container" 8545/tcp | awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}')"
deadline="$(( $(date +%s) + ready_timeout ))"
while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -fsS --max-time 5 --header 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        "http://127.0.0.1:$rpc_port" >/dev/null 2>&1; then
        trap - EXIT HUP INT TERM
        date -u +started=%Y-%m-%dT%H:%M:%SZ
        docker container inspect --format \
            'container={{.Name}} running={{.State.Running}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} caps={{json .HostConfig.CapDrop}} security={{json .HostConfig.SecurityOpt}} networks={{json .NetworkSettings.Networks}}' \
            "$container"
        printf 'rpc-port=%s datadir=%s source-running=false\n' "$rpc_port" "$datadir"
        exit 0
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$container")" = true ] || break
    sleep 1
done
docker logs --tail 80 "$container" >&2 || true
echo "geth public RPC did not become ready" >&2
exit 1
REMOTE
}

restore() {
    require_mutation
    ssh "$host" bash -s -- "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$cl_alias" "$ready_timeout" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
cl_alias="$6"; ready_timeout="$7"
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$container")" = \
   codex-geth-same-host-benchmark ] || { echo "geth benchmark ownership mismatch" >&2; exit 1; }
[ "$(docker container inspect --format '{{.Image}}' "$container")" = "$expected" ] || {
    echo "geth benchmark image mismatch" >&2; exit 1;
}
actual_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
[ "$actual_datadir" = "$datadir" ] || { echo "geth benchmark datadir mismatch" >&2; exit 1; }
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$source")" = \
   codex-sec5-live-gate ] || { echo "source EL ownership mismatch" >&2; exit 1; }

docker stop --time 30 "$container" >/dev/null
rollback() { docker stop --time 10 "$source" >/dev/null 2>&1 || true; docker start "$container" >/dev/null 2>&1 || true; }
trap rollback EXIT HUP INT TERM
docker start "$source" >/dev/null
rpc_port="$(docker port "$source" 8545/tcp | awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}')"
deadline="$(( $(date +%s) + ready_timeout ))"
while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -fsS --max-time 5 --header 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        "http://127.0.0.1:$rpc_port" >/dev/null 2>&1; then
        trap - EXIT HUP INT TERM
        date -u +restored=%Y-%m-%dT%H:%M:%SZ
        printf 'source=%s running=true geth=%s running=false geth-datadir=%s preserved=true alias=%s\n' \
            "$source" "$container" "$datadir" "$cl_alias"
        exit 0
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$source")" = true ] || break
    sleep 1
done
echo "source EL did not become ready after restore" >&2
exit 1
REMOTE
}

case "$action" in
    status) status ;;
    start) start ;;
    restore) restore ;;
    *) fail "usage: scripts/hoodi-geth-benchmark-gate.sh status|start|restore" ;;
esac
