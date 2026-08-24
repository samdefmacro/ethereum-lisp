#!/usr/bin/env bash
set -euo pipefail

# Same-host, fresh-datadir Hoodi SNAP benchmark for an exact ethereum-lisp
# runtime image.  The current live gate remains the rollback target; neither
# its datadir nor the benchmark datadir is copied, removed, or reused.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-status}"
actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_LISP_BENCH_RUNTIME_REVISION:-$actual_head}"
short_revision="${revision:0:8}"

host="${HOODI_LISP_BENCH_HOST:-test-ethereum-server}"
remote_root="${HOODI_LISP_BENCH_REMOTE_ROOT:-/data/hoodi-sec5-20260814}"
image="${HOODI_LISP_BENCH_IMAGE:-ethereum-lisp-runtime:sec5-${short_revision}-amd64}"
container="${HOODI_LISP_BENCH_CONTAINER:-hoodi-lisp-bench-${short_revision}-fresh1}"
datadir="${HOODI_LISP_BENCH_DATADIR:-$remote_root/lisp-${short_revision}-fresh1}"
source="${HOODI_LISP_BENCH_SOURCE_CONTAINER:-hoodi-el-sec5-${short_revision}}"
previous_revision="${HOODI_LISP_BENCH_PREVIOUS_REVISION:-$revision}"
previous_short_revision="${previous_revision:0:8}"
previous_image="${HOODI_LISP_BENCH_PREVIOUS_IMAGE:-ethereum-lisp-runtime:sec5-${previous_short_revision}-amd64}"
previous_container="${HOODI_LISP_BENCH_PREVIOUS_CONTAINER:-hoodi-lisp-bench-${previous_short_revision}-fresh1}"
lighthouse="${HOODI_LISP_BENCH_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
cl_network="${HOODI_LISP_BENCH_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_LISP_BENCH_EGRESS_NETWORK:-hoodi-net}"
cl_alias="${HOODI_LISP_BENCH_CL_ALIAS:-hoodi-el-public-36a22e47}"
jwt_dir="${HOODI_LISP_BENCH_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_LISP_BENCH_PUBLIC_IP:-165.154.224.110}"
p2p_port="${HOODI_LISP_BENCH_P2P_PORT:-30303}"
ready_timeout="${HOODI_LISP_BENCH_READY_TIMEOUT:-600}"
seccomp_profile="$remote_root/docker-26.1.4-io-uring-seccomp.json"
expected_seccomp_sha256="68afe4d839d125a335c352d1707caa1482923a4c2adf5fa7c1789ca1da72672b"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_mutation() {
    [ "${HOODI_LISP_BENCH_ALLOW_MUTATION:-}" = 1 ] ||
        fail "$action changes remote state; set HOODI_LISP_BENCH_ALLOW_MUTATION=1 after explicit authorization"
    git -C "$repo_root" diff --quiet || fail "checkout has unstaged changes"
    git -C "$repo_root" diff --cached --quiet || fail "checkout has staged changes"
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "checkout has untracked files"
}

case "$revision" in *[!0-9a-f]*|'') fail "unsafe runtime revision" ;; esac
[ "${#revision}" -eq 40 ] || fail "runtime revision must be a full Git id"
case "$previous_revision" in *[!0-9a-f]*|'') fail "unsafe previous runtime revision" ;; esac
[ "${#previous_revision}" -eq 40 ] || fail "previous runtime revision must be a full Git id"
if [ "$actual_head" != "$revision" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "runtime revision is not an ancestor of checkout HEAD"
    runtime_sensitive_changes="$(git -C "$repo_root" diff --name-only "$revision" "$actual_head" -- . \
        ':(exclude)docs/**' \
        ':(exclude)scripts/hoodi-live-gate.sh' \
        ':(exclude)scripts/hoodi-geth-benchmark-gate.sh' \
        ':(exclude)scripts/hoodi-lisp-benchmark-gate.sh')"
    [ -z "$runtime_sensitive_changes" ] ||
        fail "checkout changed runtime-sensitive paths after $revision: $runtime_sensitive_changes"
fi
case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host" ;; esac
case "$remote_root" in /data/hoodi-sec5-*) ;; *) fail "unsafe remote root" ;; esac
case "$datadir" in "$remote_root"/lisp-*) ;; *) fail "unsafe benchmark datadir" ;; esac
for candidate_image in "$image" "$previous_image"; do
    case "$candidate_image" in *[!A-Za-z0-9_.:/+-]*|'') fail "unsafe image" ;; esac
done
for name in "$container" "$previous_container" "$source" "$lighthouse" "$cl_network" "$egress_network" "$cl_alias"; do
    case "$name" in *[!A-Za-z0-9_.-]*|'') fail "unsafe Docker name: $name" ;; esac
done
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$p2p_port" in *[!0-9]*|'') fail "P2P port must be an integer" ;; esac
[ "$p2p_port" -ge 1024 ] && [ "$p2p_port" -le 65535 ] || fail "P2P port is out of range"
case "$ready_timeout" in *[!0-9]*|'') fail "ready timeout must be an integer" ;; esac
[ "$ready_timeout" -ge 30 ] && [ "$ready_timeout" -le 1800 ] || fail "ready timeout is out of range"

status() {
    ssh "$host" bash -s -- "$revision" "$image" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
docker image inspect --format \
    'image={{.RepoTags}} id={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image"
for network in "$cl_network" "$egress_network"; do
    docker network inspect --format 'network={{.Name}} driver={{.Driver}} internal={{.Internal}}' "$network"
done
for name in "$container" "$source" "$lighthouse"; do
    if docker container inspect "$name" >/dev/null 2>&1; then
        docker container inspect --format \
            'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} labels={{json .Config.Labels}}' \
            "$name"
    else
        printf 'container=/%s absent\n' "$name"
    fi
done
if [ -d "$datadir" ]; then
    if [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        du -sh "$datadir"
    else
        printf 'benchmark-datadir=%s empty\n' "$datadir"
    fi
else
    printf 'benchmark-datadir=%s absent\n' "$datadir"
fi
REMOTE
}

start() {
    require_mutation
    ssh "$host" bash -s -- "$revision" "$image" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" "$cl_alias" \
        "$jwt_dir" "$public_ip" "$p2p_port" "$ready_timeout" "$seccomp_profile" \
        "$expected_seccomp_sha256" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"; cl_alias="$9"
jwt_dir="${10}"; public_ip="${11}"; p2p_port="${12}"; ready_timeout="${13}"
seccomp_profile="${14}"; expected_seccomp="${15}"

[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")" = "$revision" ] || {
    echo "runtime image revision mismatch" >&2; exit 1;
}
[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = linux/amd64 ] || {
    echo "runtime image platform mismatch" >&2; exit 1;
}
[ "$(docker version --format '{{.Server.Version}}')" = 26.1.4 ] || {
    echo "pinned seccomp profile requires Docker server 26.1.4" >&2; exit 1;
}
[ "$(sha256sum "$seccomp_profile" | awk '{print $1}')" = "$expected_seccomp" ] || {
    echo "seccomp profile checksum mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$source")" = true ] || {
    echo "source EL is not running: $source" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$lighthouse")" = true ] || {
    echo "Lighthouse is not running: $lighthouse" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$source")" = codex-sec5-live-gate ] || {
    echo "source EL ownership mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$source")" = "$revision" ] || {
    echo "source EL revision mismatch" >&2; exit 1;
}
source_user="$(docker container inspect --format '{{.Config.User}}' "$source")"
case "$source_user" in 0|0:*|*:0|'') echo "source EL user is not explicitly non-root" >&2; exit 1 ;; esac
docker network inspect "$cl_network" >/dev/null
docker network inspect "$egress_network" >/dev/null
[ -r "$jwt_dir/jwt.hex" ] || { echo "JWT secret is not readable" >&2; exit 1; }
if docker container inspect "$container" >/dev/null 2>&1; then
    echo "refusing existing benchmark container: $container" >&2; exit 1
fi
if [ -d "$datadir" ] && [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "refusing non-empty benchmark datadir: $datadir" >&2; exit 1
fi
mkdir -p "$datadir"
uid="${source_user%%:*}"; gid="${source_user##*:}"
chown "$uid:$gid" "$datadir"

docker run --rm --pull never --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --security-opt "seccomp=$seccomp_profile" \
    --network none --entrypoint /usr/local/libexec/ethereum-lisp-io-uring-probe \
    "$image" >/dev/null

docker stop --time 30 "$source" >/dev/null
rollback() {
    docker stop --time 10 "$container" >/dev/null 2>&1 || true
    docker start "$source" >/dev/null 2>&1 || true
}
trap rollback EXIT HUP INT TERM
docker run --detach --pull never \
    --name "$container" \
    --label agent=codex-ethereum-lisp-same-host-benchmark \
    --label "io.ethereum-lisp.benchmark-source=$source" \
    --label "io.ethereum-lisp.gate-revision=$revision" \
    --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --security-opt "seccomp=$seccomp_profile" \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" --network-alias "$cl_alias" \
    --publish "$p2p_port:$p2p_port/tcp" --publish "$p2p_port:$p2p_port/udp" \
    --publish 127.0.0.1::8545 \
    "$image" \
    --hoodi --datadir /data --port "$p2p_port" --nat "extip:$public_ip" \
    --maxpeers 50 \
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
echo "ethereum-lisp benchmark RPC did not become ready" >&2
exit 1
REMOTE
}

resume() {
    require_mutation
    [ "$container" != "$previous_container" ] ||
        fail "resume requires a new benchmark container name"
    ssh "$host" bash -s -- "$revision" "$image" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" "$cl_alias" \
        "$jwt_dir" "$public_ip" "$p2p_port" "$ready_timeout" "$seccomp_profile" \
        "$expected_seccomp_sha256" "$previous_revision" "$previous_image" \
        "$previous_container" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"; cl_alias="$9"
jwt_dir="${10}"; public_ip="${11}"; p2p_port="${12}"; ready_timeout="${13}"
seccomp_profile="${14}"; expected_seccomp="${15}"; previous_revision="${16}"
previous_image="${17}"; previous_container="${18}"

[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")" = "$revision" ] || {
    echo "runtime image revision mismatch" >&2; exit 1;
}
[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = linux/amd64 ] || {
    echo "runtime image platform mismatch" >&2; exit 1;
}
[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$previous_image")" = "$previous_revision" ] || {
    echo "previous runtime image revision mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.Config.Image}}' "$previous_container")" = "$previous_image" ] || {
    echo "previous benchmark image mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.Image}}' "$previous_container")" = \
   "$(docker image inspect --format '{{.Id}}' "$previous_image")" ] || {
    echo "previous benchmark image id mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$previous_container")" = \
   codex-ethereum-lisp-same-host-benchmark ] || {
    echo "previous benchmark ownership mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$previous_container")" = "$previous_revision" ] || {
    echo "previous benchmark revision mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$previous_container")" = false ] || {
    echo "previous benchmark must be stopped" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$previous_container")" = true ] || {
    echo "previous benchmark root filesystem is not read-only" >&2; exit 1;
}
previous_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$previous_container")"
[ "$previous_datadir" = "$datadir" ] || { echo "previous benchmark datadir mismatch" >&2; exit 1; }
[ -d "$datadir" ] && [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
    echo "previous benchmark datadir is absent or empty" >&2; exit 1;
}
[ "$(docker version --format '{{.Server.Version}}')" = 26.1.4 ] || {
    echo "pinned seccomp profile requires Docker server 26.1.4" >&2; exit 1;
}
[ "$(sha256sum "$seccomp_profile" | awk '{print $1}')" = "$expected_seccomp" ] || {
    echo "seccomp profile checksum mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$source")" = true ] || {
    echo "source EL is not running: $source" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.State.Running}}' "$lighthouse")" = true ] || {
    echo "Lighthouse is not running: $lighthouse" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$source")" = codex-sec5-live-gate ] || {
    echo "source EL ownership mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$source")" = "$revision" ] || {
    echo "source EL revision mismatch" >&2; exit 1;
}
source_user="$(docker container inspect --format '{{.Config.User}}' "$source")"
case "$source_user" in 0|0:*|*:0|'') echo "source EL user is not explicitly non-root" >&2; exit 1 ;; esac
docker network inspect "$cl_network" >/dev/null
docker network inspect "$egress_network" >/dev/null
[ -r "$jwt_dir/jwt.hex" ] || { echo "JWT secret is not readable" >&2; exit 1; }
if docker container inspect "$container" >/dev/null 2>&1; then
    echo "refusing existing resume container: $container" >&2; exit 1
fi

docker run --rm --pull never --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --security-opt "seccomp=$seccomp_profile" \
    --network none --entrypoint /usr/local/libexec/ethereum-lisp-io-uring-probe \
    "$image" >/dev/null

docker stop --time 30 "$source" >/dev/null
rollback() {
    docker stop --time 10 "$container" >/dev/null 2>&1 || true
    docker start "$source" >/dev/null 2>&1 || true
}
trap rollback EXIT HUP INT TERM
docker run --detach --pull never \
    --name "$container" \
    --label agent=codex-ethereum-lisp-same-host-benchmark \
    --label "io.ethereum-lisp.benchmark-source=$source" \
    --label "io.ethereum-lisp.gate-revision=$revision" \
    --label "io.ethereum-lisp.resumed-from-container=$previous_container" \
    --label "io.ethereum-lisp.resumed-from-revision=$previous_revision" \
    --user "$source_user" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --security-opt "seccomp=$seccomp_profile" \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" --network-alias "$cl_alias" \
    --publish "$p2p_port:$p2p_port/tcp" --publish "$p2p_port:$p2p_port/udp" \
    --publish 127.0.0.1::8545 \
    "$image" \
    --hoodi --datadir /data --port "$p2p_port" --nat "extip:$public_ip" \
    --maxpeers 50 \
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
        date -u +resumed=%Y-%m-%dT%H:%M:%SZ
        docker container inspect --format \
            'container={{.Name}} running={{.State.Running}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} caps={{json .HostConfig.CapDrop}} security={{json .HostConfig.SecurityOpt}} networks={{json .NetworkSettings.Networks}} labels={{json .Config.Labels}}' \
            "$container"
        printf 'rpc-port=%s datadir=%s previous-container=%s preserved=true source-running=false\n' \
            "$rpc_port" "$datadir" "$previous_container"
        exit 0
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$container")" = true ] || break
    sleep 1
done
docker logs --tail 80 "$container" >&2 || true
echo "ethereum-lisp resumed benchmark RPC did not become ready" >&2
exit 1
REMOTE
}

restore() {
    require_mutation
    ssh "$host" bash -s -- "$revision" "$image" "$container" "$datadir" \
        "$source" "$ready_timeout" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; source="$5"; ready_timeout="$6"
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$container")" = \
   codex-ethereum-lisp-same-host-benchmark ] || { echo "benchmark ownership mismatch" >&2; exit 1; }
[ "$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$container")" = "$revision" ] || {
    echo "benchmark revision mismatch" >&2; exit 1;
}
[ "$(docker container inspect --format '{{.Config.Image}}' "$container")" = "$image" ] || {
    echo "benchmark image mismatch" >&2; exit 1;
}
actual_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
[ "$actual_datadir" = "$datadir" ] || { echo "benchmark datadir mismatch" >&2; exit 1; }
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$source")" = codex-sec5-live-gate ] || {
    echo "source EL ownership mismatch" >&2; exit 1;
}

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
        printf 'source=%s running=true benchmark=%s running=false benchmark-datadir=%s preserved=true\n' \
            "$source" "$container" "$datadir"
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
    resume) resume ;;
    restore) restore ;;
    *) fail "usage: scripts/hoodi-lisp-benchmark-gate.sh status|start|resume|restore" ;;
esac
