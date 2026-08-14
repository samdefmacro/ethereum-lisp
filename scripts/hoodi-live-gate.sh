#!/usr/bin/env bash
#
# Reproducible control-plane broker for the Section 5 live Hoodi gate.
#
# The client itself always runs in the reviewed runtime image on the remote
# Linux host.  This script runs only ssh/scp, Git identity checks, Docker image
# inspection, and remote Docker lifecycle commands.  Mutating actions require
# HOODI_GATE_ALLOW_MUTATION=1 and are deliberately split from read-only
# inspection so an evidence refresh cannot accidentally replace a container.
#
# Defaults describe the dedicated server resources created for the Section 5
# gate.  Override them only with the documented HOODI_GATE_* variables; every
# remote path is still required to remain below /data/hoodi-sec5-*.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-inspect}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

note() {
    echo "==> $*"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail "sha256sum or shasum is required"
    fi
}

revision="${HOODI_GATE_REVISION:-$(git -C "$repo_root" rev-parse HEAD)}"
case "$revision" in
    *[!0-9a-f]*|'') fail "revision must be a full lowercase hexadecimal Git id" ;;
esac
[ "${#revision}" -eq 40 ] || fail "revision must contain exactly 40 hexadecimal characters"
short_revision="${revision:0:8}"

host="${HOODI_GATE_HOST:-test-ethereum-server}"
remote_root="${HOODI_GATE_REMOTE_ROOT:-/data/hoodi-sec5-20260814}"
image="${HOODI_GATE_IMAGE:-ethereum-lisp-runtime:sec5-${short_revision}-amd64}"
artifact="${HOODI_GATE_ARTIFACT:-/private/tmp/ethereum-lisp-runtime-sec5-${short_revision}-amd64.tar}"
container="${HOODI_GATE_CONTAINER:-hoodi-el-sec5-${short_revision}}"
datadir="${HOODI_GATE_DATADIR:-$remote_root/datadir-${short_revision}}"
remote_artifact="$remote_root/${artifact##*/}"

lighthouse_container="${HOODI_GATE_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
old_container="${HOODI_GATE_OLD_CONTAINER:-hoodi-el-sec5-rehearsal-old3}"
cl_network="${HOODI_GATE_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_GATE_EGRESS_NETWORK:-hoodi-net}"
cl_alias="${HOODI_GATE_CL_ALIAS:-hoodi-el-public-frozen}"
jwt_dir="${HOODI_GATE_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_GATE_PUBLIC_IP:-165.154.224.110}"
restart_ready_timeout="${HOODI_GATE_RESTART_READY_TIMEOUT:-300}"

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$remote_root" in
    /data/hoodi-sec5-*) ;;
    *) fail "remote root must stay below /data/hoodi-sec5-*" ;;
esac
case "$remote_root$datadir$remote_artifact$jwt_dir" in
    *'..'*|*$'\n'*|*$'\r'*|*$'\t'*|*' '*) fail "remote paths must be absolute, normalized, and whitespace-free" ;;
esac
case "$datadir" in "$remote_root"/*) ;; *) fail "datadir must stay below $remote_root" ;; esac
case "$remote_artifact" in "$remote_root"/*) ;; *) fail "artifact must stay below $remote_root" ;; esac
case "$image" in *[!A-Za-z0-9_.:/+-]*|'') fail "unsafe image name: $image" ;; esac
for name in "$container" "$lighthouse_container" "$old_container" "$cl_network" "$egress_network" "$cl_alias"; do
    case "$name" in *[!A-Za-z0-9_.-]*|'') fail "unsafe Docker name: $name" ;; esac
done
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$restart_ready_timeout" in
    *[!0-9]*|'') fail "restart ready timeout must be an integer number of seconds" ;;
esac
[ "$restart_ready_timeout" -ge 30 ] && [ "$restart_ready_timeout" -le 1800 ] ||
    fail "restart ready timeout must be between 30 and 1800 seconds"

actual_head="$(git -C "$repo_root" rev-parse HEAD)"
[ "$actual_head" = "$revision" ] || fail "requested revision $revision is not checkout HEAD $actual_head"

require_clean_checkout() {
    git -C "$repo_root" diff --quiet || fail "checkout has unstaged changes"
    git -C "$repo_root" diff --cached --quiet || fail "checkout has staged changes"
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "checkout has untracked files"
}

require_mutation() {
    [ "${HOODI_GATE_ALLOW_MUTATION:-}" = "1" ] ||
        fail "$action changes remote state; set HOODI_GATE_ALLOW_MUTATION=1 only after explicit authorization"
    require_clean_checkout
}

require_local_artifact() {
    [ -f "$artifact" ] || fail "runtime artifact is absent: $artifact"
    artifact_sha256="$(sha256_file "$artifact")"
}

inspect_local_image() {
    local image_revision image_platform
    image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")" ||
        fail "local image is absent: $image"
    image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
    [ "$image_revision" = "$revision" ] ||
        fail "local image revision is $image_revision, expected $revision"
    [ "$image_platform" = "linux/amd64" ] ||
        fail "local image platform is $image_platform, expected linux/amd64"
    docker image inspect --format \
        'local-image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} size={{.Size}}' \
        "$image"
}

inspect_gate() {
    require_clean_checkout
    require_local_artifact
    note "local exact-revision inputs"
    inspect_local_image
    printf 'artifact=%s sha256=%s\n' "$artifact" "$artifact_sha256"

    note "remote read-only state"
    ssh "$host" bash -s -- \
        "$revision" "$image" "$remote_root" "$remote_artifact" "$container" \
        "$lighthouse_container" "$old_container" "$cl_network" "$egress_network" <<'REMOTE'
set -eu
revision="$1"; image="$2"; remote_root="$3"; remote_artifact="$4"; container="$5"
lighthouse="$6"; old="$7"; cl_network="$8"; egress_network="$9"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
df -h "$remote_root"
for network in "$cl_network" "$egress_network"; do
    docker network inspect --format 'network={{.Name}} driver={{.Driver}} internal={{.Internal}} scope={{.Scope}}' "$network"
done
for name in "$lighthouse" "$old" "$container"; do
    if docker container inspect "$name" >/dev/null 2>&1; then
        docker container inspect --format \
            'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Config.Image}} labels={{json .Config.Labels}}' \
            "$name"
    else
        printf 'container=/%s absent\n' "$name"
    fi
done
if docker image inspect "$image" >/dev/null 2>&1; then
    docker image inspect --format \
        'remote-image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }}' \
        "$image"
else
    printf 'remote-image=%s absent expected-revision=%s\n' "$image" "$revision"
fi
if [ -f "$remote_artifact" ]; then
    sha256sum "$remote_artifact"
else
    printf 'remote-artifact=%s absent\n' "$remote_artifact"
fi
REMOTE
}

upload_artifact() {
    require_mutation
    require_local_artifact
    local state partial
    partial="$remote_artifact.partial-$artifact_sha256"

    state="$(ssh "$host" bash -s -- "$remote_root" "$remote_artifact" "$partial" "$artifact_sha256" <<'REMOTE'
set -eu
remote_root="$1"; final="$2"; partial="$3"; expected="$4"
install -d -m 0755 "$remote_root"
if [ -e "$final" ]; then
    actual="$(sha256sum "$final" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || {
        echo "existing artifact checksum $actual does not match $expected" >&2
        exit 1
    }
    printf present
elif [ -e "$partial" ]; then
    echo "refusing to overwrite interrupted upload $partial" >&2
    exit 1
else
    printf upload
fi
REMOTE
)"
    if [ "$state" = "present" ]; then
        note "remote artifact already has the expected checksum"
        return
    fi
    [ "$state" = "upload" ] || fail "unexpected upload preflight result: $state"

    note "uploading the runtime-only image archive"
    scp "$artifact" "$host:$partial"
    ssh "$host" bash -s -- "$remote_artifact" "$partial" "$artifact_sha256" <<'REMOTE'
set -eu
final="$1"; partial="$2"; expected="$3"
actual="$(sha256sum "$partial" | awk '{print $1}')"
[ "$actual" = "$expected" ] || {
    echo "uploaded artifact checksum $actual does not match $expected" >&2
    exit 1
}
chmod 0600 "$partial"
[ ! -e "$final" ] || { echo "refusing to overwrite $final" >&2; exit 1; }
mv "$partial" "$final"
printf 'uploaded-artifact=%s sha256=%s\n' "$final" "$actual"
REMOTE
}

load_image() {
    require_mutation
    require_local_artifact
    note "loading the checksum-verified image on the remote Docker daemon"
    ssh "$host" bash -s -- "$revision" "$image" "$remote_artifact" "$artifact_sha256" <<'REMOTE'
set -eu
revision="$1"; image="$2"; artifact="$3"; expected="$4"
[ -f "$artifact" ] || { echo "artifact is absent: $artifact" >&2; exit 1; }
actual="$(sha256sum "$artifact" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { echo "artifact checksum mismatch: $actual" >&2; exit 1; }
if docker image inspect "$image" >/dev/null 2>&1; then
    installed_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
    installed_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
    [ "$installed_revision" = "$revision" ] && [ "$installed_platform" = "linux/amd64" ] || {
        echo "refusing existing mismatched image $image ($installed_platform $installed_revision)" >&2
        exit 1
    }
else
    docker image load --input "$artifact"
fi
docker image inspect --format \
    'remote-image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image"
REMOTE
}

start_gate() {
    require_mutation
    note "cutting the existing Lighthouse alias over to the exact-revision EL"
    ssh "$host" bash -s -- \
        "$revision" "$image" "$container" "$datadir" "$jwt_dir" "$public_ip" \
        "$lighthouse_container" "$old_container" "$cl_network" "$egress_network" "$cl_alias" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; jwt_dir="$5"; public_ip="$6"
lighthouse="$7"; old="$8"; cl_network="$9"; egress_network="${10}"; cl_alias="${11}"

image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
[ "$image_revision" = "$revision" ] || { echo "image revision mismatch: $image_revision" >&2; exit 1; }
[ "$image_platform" = "linux/amd64" ] || { echo "image platform mismatch: $image_platform" >&2; exit 1; }
[ "$(docker container inspect --format '{{.State.Running}}' "$lighthouse")" = true ] || {
    echo "required Lighthouse container is not running: $lighthouse" >&2
    exit 1
}
docker network inspect "$cl_network" >/dev/null
docker network inspect "$egress_network" >/dev/null
[ -r "$jwt_dir/jwt.hex" ] || { echo "JWT file is not readable: $jwt_dir/jwt.hex" >&2; exit 1; }
if docker container inspect "$container" >/dev/null 2>&1; then
    echo "refusing to replace existing gate container: $container" >&2
    exit 1
fi

gate_uid="$(id -u)"; gate_gid="$(id -g)"
[ "$gate_uid" -ne 0 ] || { echo "remote gate must run as a non-root uid" >&2; exit 1; }
if [ -d "$datadir" ]; then
    [ -z "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
        echo "fresh gate datadir is not empty: $datadir" >&2
        exit 1
    }
else
    install -d -m 0700 "$datadir"
fi

old_was_running=false
if docker container inspect "$old" >/dev/null 2>&1 &&
   [ "$(docker container inspect --format '{{.State.Running}}' "$old")" = true ]; then
    old_agent="$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$old")"
    old_revision="$(docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$old")"
    [ "$old_agent" = codex-sec5-rehearsal ] && [ "$old_revision" = section5-livefix18-20260812 ] || {
        echo "refusing to stop container with unexpected ownership: $old" >&2
        exit 1
    }
    docker stop --time 30 "$old" >/dev/null
    old_was_running=true
fi

rollback() {
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker stop --time 10 "$container" >/dev/null 2>&1 || true
    fi
    if [ "$old_was_running" = true ]; then
        docker start "$old" >/dev/null 2>&1 || true
    fi
}

if ! docker run --detach --pull never \
    --name "$container" \
    --label agent=codex-sec5-live-gate \
    --label "io.ethereum-lisp.gate-revision=$revision" \
    --user "$gate_uid:$gate_gid" \
    --read-only \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" \
    --network-alias "$cl_alias" \
    --publish 30303:30303/tcp \
    --publish 30303:30303/udp \
    --publish 127.0.0.1::8545 \
    "$image" \
    --hoodi \
    --datadir /data \
    --nat "extip:$public_ip" \
    --http \
    --http.addr 0.0.0.0 \
    --http.port 8545 \
    --http.api eth,net,web3,txpool,admin \
    --http.vhosts '*' \
    --authrpc.addr 0.0.0.0 \
    --authrpc.port 8551 \
    --authrpc.jwtsecret /jwt/jwt.hex \
    --authrpc.vhosts '*' \
    --maxpeers 25 >/dev/null; then
    rollback
    exit 1
fi

if ! docker network connect "$egress_network" "$container"; then
    rollback
    echo "failed to attach $container to $egress_network; old container restored" >&2
    exit 1
fi
sleep 2
if [ "$(docker container inspect --format '{{.State.Running}}' "$container")" != true ]; then
    docker logs "$container" 2>&1 | tail -80 >&2 || true
    rollback
    echo "exact-revision EL exited during startup; old container restored" >&2
    exit 1
fi
docker container inspect --format \
    'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} networks={{json .NetworkSettings.Networks}}' \
    "$container"
printf 'fresh-datadir=%s uid=%s gid=%s\n' "$datadir" "$gate_uid" "$gate_gid"
REMOTE
}

remote_status() {
    note "remote gate status"
    ssh "$host" bash -s -- "$revision" "$image" "$container" "$datadir" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
[ "$image_revision" = "$revision" ] || { echo "image revision mismatch: $image_revision" >&2; exit 1; }
docker image inspect --format \
    'image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image"
docker container inspect --format \
    'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} networks={{json .NetworkSettings.Networks}}' \
    "$container"
printf 'datadir-bytes='
du -sb "$datadir" | awk '{print $1}'

rpc_port="$(docker port "$container" 8545/tcp | awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}')"
[ -n "$rpc_port" ] || { echo "public RPC loopback port is unavailable" >&2; exit 1; }
rpc() {
    method="$1"
    curl --silent --show-error --max-time 10 \
        --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" \
        "http://127.0.0.1:$rpc_port"
}
printf 'eth_blockNumber='; rpc eth_blockNumber; printf '\n'
printf 'eth_syncing='; rpc eth_syncing; printf '\n'
printf 'net_peerCount='; rpc net_peerCount; printf '\n'
printf 'admin_nodeInfo='; rpc admin_nodeInfo; printf '\n'
REMOTE
}

restart_gate() {
    require_mutation
    note "recording progress, restarting the same container, and recording it again"
    ssh "$host" bash -s -- \
        "$revision" "$container" "$datadir" "$restart_ready_timeout" <<'REMOTE'
set -eu
revision="$1"; container="$2"; datadir="$3"; ready_timeout="$4"
label="$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$container")"
[ "$label" = "$revision" ] || { echo "gate ownership mismatch: $label" >&2; exit 1; }
mount_source="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
[ "$mount_source" = "$datadir" ] || { echo "gate datadir mismatch: $mount_source" >&2; exit 1; }

rpc_port="$(docker port "$container" 8545/tcp | awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}')"
rpc() {
    method="$1"
    curl --silent --show-error --max-time 10 \
        --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" \
        "http://127.0.0.1:$rpc_port"
}
date -u +before-timestamp=%Y-%m-%dT%H:%M:%SZ
printf 'before-started='; docker container inspect --format '{{.State.StartedAt}}' "$container"
printf 'before-datadir-bytes='; du -sb "$datadir" | awk '{print $1}'
printf 'before-block='; rpc eth_blockNumber; printf '\n'
printf 'before-syncing='; rpc eth_syncing; printf '\n'

docker stop --time 30 "$container" >/dev/null
docker start "$container" >/dev/null

ready=false
for _ in $(seq 1 "$ready_timeout"); do
    if rpc eth_chainId >/dev/null 2>&1; then
        ready=true
        break
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$container")" = true ] ||
        break
    sleep 1
done
[ "$ready" = true ] || {
    docker logs "$container" 2>&1 | tail -80 >&2 || true
    echo "public RPC did not return within ${ready_timeout}s after restart" >&2
    exit 1
}
date -u +after-timestamp=%Y-%m-%dT%H:%M:%SZ
printf 'after-started='; docker container inspect --format '{{.State.StartedAt}}' "$container"
printf 'after-datadir-bytes='; du -sb "$datadir" | awk '{print $1}'
printf 'after-block='; rpc eth_blockNumber; printf '\n'
printf 'after-syncing='; rpc eth_syncing; printf '\n'
REMOTE
}

gate_logs() {
    note "recent EL and CL evidence logs"
    ssh "$host" bash -s -- "$container" "$lighthouse_container" <<'REMOTE'
set -eu
container="$1"; lighthouse="$2"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
printf '%s\n' '--- ethereum-lisp (last 500 lines) ---'
docker logs --tail 500 --timestamps "$container" 2>&1
printf '%s\n' '--- lighthouse (last 250 lines) ---'
docker logs --tail 250 --timestamps "$lighthouse" 2>&1
REMOTE
}

case "$action" in
    inspect) inspect_gate ;;
    upload) upload_artifact ;;
    load) load_image ;;
    start) start_gate ;;
    status) remote_status ;;
    restart) restart_gate ;;
    logs) gate_logs ;;
    *)
        cat >&2 <<USAGE
Usage: scripts/hoodi-live-gate.sh ACTION

Read-only actions: inspect, status, logs
Mutating actions:  upload, load, start, restart

Mutating actions require HOODI_GATE_ALLOW_MUTATION=1. The default artifact,
image, container, and datadir are derived from the current full Git revision.
HOODI_GATE_RESTART_READY_TIMEOUT may override the bounded 300-second restart
readiness window (accepted range: 30-1800 seconds).
USAGE
        exit 2
        ;;
esac
