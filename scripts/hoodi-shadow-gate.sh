#!/usr/bin/env bash
set -euo pipefail

# Same-host Hoodi Engine shadow gate. Lighthouse remains authoritative through
# ethereum-lisp; a bounded internal-only proxy mirrors identical Engine calls
# to a pinned geth. Mutations are explicit and every alias cutover has rollback.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-status}"
actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_SHADOW_PROXY_REVISION:-$actual_head}"
short_revision="${revision:0:8}"

host="${HOODI_SHADOW_HOST:-test-ethereum-server}"
remote_root="${HOODI_SHADOW_REMOTE_ROOT:-/data/hoodi-sec5-20260830}"
proxy_image="${HOODI_SHADOW_PROXY_IMAGE:-ethereum-lisp-shadow-engine-proxy:sec5-${short_revision}-amd64}"
proxy_container="${HOODI_SHADOW_PROXY_CONTAINER:-hoodi-engine-shadow-proxy-${short_revision}}"
artifact="${HOODI_SHADOW_ARTIFACT:-/private/tmp/ethereum-lisp-shadow-engine-proxy-sec5-${short_revision}-amd64.tar}"
remote_artifact="$remote_root/${artifact##*/}"

source="${HOODI_SHADOW_SOURCE_CONTAINER:-hoodi-lisp-79fd759a-fresh-final}"
source_revision="${HOODI_SHADOW_SOURCE_REVISION:-79fd759a12d090da947b4eed3f95e8fb2b893f20}"
lighthouse="${HOODI_SHADOW_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
geth_image="${HOODI_SHADOW_GETH_IMAGE:-ethereum/client-go:v1.17.4}"
geth_image_id="${HOODI_SHADOW_GETH_IMAGE_ID:-sha256:9389d3371a5cde510edb5dfa10a759f7ef98bd8676e6491ce79ab1050306478b}"
geth_legacy="${HOODI_SHADOW_GETH_LEGACY_CONTAINER:-hoodi-geth-v1.17.4-baseline}"
geth_container="${HOODI_SHADOW_GETH_CONTAINER:-hoodi-geth-v1.17.4-shadow}"
geth_datadir="${HOODI_SHADOW_GETH_DATADIR:-/data/hoodi-sec5-20260814/geth-v1.17.4-baseline}"

cl_network="${HOODI_SHADOW_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_SHADOW_EGRESS_NETWORK:-hoodi-net}"
stable_alias="${HOODI_SHADOW_STABLE_ALIAS:-hoodi-el-public-36a22e47}"
source_alias="${HOODI_SHADOW_SOURCE_ALIAS:-hoodi-lisp-shadow-primary}"
geth_alias="${HOODI_SHADOW_GETH_ALIAS:-hoodi-geth-shadow}"
jwt_dir="${HOODI_SHADOW_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_SHADOW_PUBLIC_IP:-165.154.224.110}"
geth_p2p_port="${HOODI_SHADOW_GETH_P2P_PORT:-30304}"
ready_timeout="${HOODI_SHADOW_READY_TIMEOUT:-600}"
geth_memory_bytes=2147483648
proxy_memory_bytes=134217728
required_soak_seconds=604800
head_interval_seconds=12

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

require_mutation() {
    [ "${HOODI_SHADOW_ALLOW_MUTATION:-}" = 1 ] ||
        fail "$action changes remote state; set HOODI_SHADOW_ALLOW_MUTATION=1"
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "mutation requires a clean checkout"
}

require_local_artifact() {
    [ -f "$artifact" ] || fail "proxy artifact is absent: $artifact"
    artifact_sha256="$(sha256_file "$artifact")"
    image_revision="$(docker image inspect \
        --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
        "$proxy_image")" || fail "local proxy image is absent: $proxy_image"
    image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$proxy_image")"
    [ "$image_revision" = "$revision" ] ||
        fail "local proxy revision is $image_revision, expected $revision"
    [ "$image_platform" = linux/amd64 ] ||
        fail "local proxy platform is $image_platform, expected linux/amd64"
}

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$remote_root" in /data/hoodi-sec5-*) ;; *) fail "unsafe remote root: $remote_root" ;; esac
case "$remote_artifact" in "$remote_root"/*) ;; *) fail "unsafe remote artifact" ;; esac
case "$artifact" in /private/tmp/ethereum-lisp-shadow-engine-proxy-*.tar) ;;
    *) fail "artifact must be a named tar below /private/tmp" ;;
esac
case "$geth_datadir" in /data/hoodi-sec5-*/geth-*) ;; *) fail "unsafe geth datadir" ;; esac
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$geth_p2p_port" in *[!0-9]*|'') fail "geth P2P port must be an integer" ;; esac
[ "$geth_p2p_port" -ge 1024 ] && [ "$geth_p2p_port" -le 65535 ] || fail "geth P2P port is out of range"
case "$ready_timeout" in *[!0-9]*|'') fail "ready timeout must be an integer" ;; esac
[ "$ready_timeout" -ge 30 ] && [ "$ready_timeout" -le 1800 ] || fail "ready timeout is out of range"
for value in "$proxy_image" "$geth_image"; do
    case "$value" in *[!A-Za-z0-9_.:/@+-]*|'') fail "unsafe image name: $value" ;; esac
done
for value in "$proxy_container" "$source" "$lighthouse" "$geth_legacy" \
    "$geth_container" "$cl_network" "$egress_network" "$stable_alias" \
    "$source_alias" "$geth_alias"; do
    case "$value" in *[!A-Za-z0-9_.-]*|'') fail "unsafe Docker name: $value" ;; esac
done
case "$revision$source_revision" in *[!0-9a-f]*) fail "unsafe revision" ;; esac
[ "${#revision}" -eq 40 ] && [ "${#source_revision}" -eq 40 ] || fail "revisions must be full Git ids"
if [ "$revision" != "$actual_head" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "proxy revision $revision is not an ancestor of checkout HEAD $actual_head"
fi
case "$geth_image_id" in sha256:*) ;; *) fail "geth image id must use sha256" ;; esac
geth_digest="${geth_image_id#sha256:}"
case "$geth_digest" in *[!0-9a-f]*|'') fail "unsafe geth image digest" ;; esac
[ "${#geth_digest}" -eq 64 ] || fail "geth image digest must contain 64 hex characters"

upload_artifact() {
    require_mutation
    require_local_artifact
    partial="$remote_artifact.partial-$artifact_sha256"
    state="$(ssh "$host" bash -s -- "$remote_root" "$remote_artifact" "$partial" "$artifact_sha256" <<'REMOTE'
set -eu
root="$1"; final="$2"; partial="$3"; expected="$4"
install -d -m 0755 "$root"
if [ -e "$final" ]; then
    actual="$(sha256sum "$final" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || { echo "existing artifact checksum mismatch" >&2; exit 1; }
    printf present
elif [ -e "$partial" ]; then
    echo "refusing interrupted upload: $partial" >&2
    exit 1
else
    printf upload
fi
REMOTE
)"
    if [ "$state" = present ]; then
        printf 'remote-artifact=%s already-present sha256=%s\n' "$remote_artifact" "$artifact_sha256"
        return
    fi
    [ "$state" = upload ] || fail "unexpected upload preflight: $state"
    scp "$artifact" "$host:$partial"
    ssh "$host" bash -s -- "$remote_artifact" "$partial" "$artifact_sha256" <<'REMOTE'
set -eu
final="$1"; partial="$2"; expected="$3"
actual="$(sha256sum "$partial" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { echo "uploaded artifact checksum mismatch" >&2; exit 1; }
chmod 0600 "$partial"
[ ! -e "$final" ] || { echo "refusing to overwrite $final" >&2; exit 1; }
mv "$partial" "$final"
printf 'remote-artifact=%s sha256=%s\n' "$final" "$actual"
REMOTE
}

load_image() {
    require_mutation
    require_local_artifact
    ssh "$host" bash -s -- "$revision" "$proxy_image" "$remote_artifact" "$artifact_sha256" <<'REMOTE'
set -eu
revision="$1"; image="$2"; artifact="$3"; expected="$4"
[ -f "$artifact" ] || { echo "artifact is absent: $artifact" >&2; exit 1; }
actual="$(sha256sum "$artifact" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { echo "artifact checksum mismatch" >&2; exit 1; }
if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker image load --input "$artifact"
fi
installed_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
installed_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
[ "$installed_revision" = "$revision" ] || { echo "proxy image revision mismatch" >&2; exit 1; }
[ "$installed_platform" = linux/amd64 ] || { echo "proxy image platform mismatch" >&2; exit 1; }
docker image inspect --format 'image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} user={{.Config.User}}' "$image"
REMOTE
}

remote_action() {
    ssh "$host" bash -s -- \
        "$action" "$revision" "$proxy_image" "$proxy_container" \
        "$source" "$source_revision" "$lighthouse" "$geth_image" \
        "$geth_image_id" "$geth_legacy" "$geth_container" "$geth_datadir" \
        "$cl_network" "$egress_network" "$stable_alias" "$source_alias" \
        "$geth_alias" "$jwt_dir" "$public_ip" "$geth_p2p_port" \
        "$ready_timeout" "$geth_memory_bytes" "$proxy_memory_bytes" \
        "$required_soak_seconds" "$head_interval_seconds" <<'REMOTE'
set -eu
action="$1"; revision="$2"; proxy_image="$3"; proxy="$4"; source="$5"
source_revision="$6"; lighthouse="$7"; geth_image="$8"; geth_id="$9"
legacy="${10}"; geth="${11}"; geth_datadir="${12}"; cl_network="${13}"
egress_network="${14}"; stable_alias="${15}"; source_alias="${16}"
geth_alias="${17}"; jwt_dir="${18}"; public_ip="${19}"
geth_p2p_port="${20}"; ready_timeout="${21}"; geth_memory="${22}"
proxy_memory="${23}"; required_soak="${24}"; head_interval="${25}"

container_exists() { docker container inspect "$1" >/dev/null 2>&1; }
running() { [ "$(docker container inspect --format '{{.State.Running}}' "$1")" = true ]; }
label() { docker container inspect --format "{{ index .Config.Labels \"$2\" }}" "$1"; }
rpc_port() {
    docker port "$1" 8545/tcp 2>/dev/null |
        awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}'
}
rpc() {
    rpc_container="$1"; rpc_method="$2"; rpc_params="${3:-[]}"
    port="$(rpc_port "$rpc_container")"
    [ -n "$port" ] || return 1
    curl --silent --show-error --max-time 10 \
        --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$rpc_method\",\"params\":$rpc_params}" \
        "http://127.0.0.1:$port"
}
sync_complete() { rpc "$1" eth_syncing | grep -F '"result":false' >/dev/null; }
block_hash() {
    response="$(rpc "$1" eth_getBlockByNumber "[\"$2\",false]")"
    printf '%s\n' "$response" | sed -n 's/.*"hash":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}
has_alias() {
    docker container inspect --format '{{range $name, $network := .NetworkSettings.Networks}}{{printf "%s " $name}}{{json $network.Aliases}}{{println}}{{end}}' "$1" |
        grep -F "$cl_network " | grep -F "\"$2\"" >/dev/null
}
proxy_probe() { docker exec "$proxy" /usr/local/bin/shadow-engine-proxy --probe-path="$1"; }
metric() { printf '%s\n' "$1" | awk -v name="$2" '$1 == name {print $2}'; }
assert_base() {
    running "$source" || { echo "source is not running" >&2; exit 1; }
    running "$lighthouse" || { echo "Lighthouse is not running" >&2; exit 1; }
    [ "$(label "$source" agent)" = codex-sec5-live-gate ] || { echo "source ownership mismatch" >&2; exit 1; }
    [ "$(label "$source" io.ethereum-lisp.gate-revision)" = "$source_revision" ] || { echo "source revision mismatch" >&2; exit 1; }
    docker network inspect "$cl_network" >/dev/null
    docker network inspect "$egress_network" >/dev/null
}
assert_proxy_image() {
    [ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$proxy_image")" = "$revision" ] || { echo "proxy revision mismatch" >&2; exit 1; }
    [ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$proxy_image")" = linux/amd64 ] || { echo "proxy platform mismatch" >&2; exit 1; }
    proxy_user="$(docker image inspect --format '{{.Config.User}}' "$proxy_image")"
    case "$proxy_user" in ''|0|0:*|*:0|root|root:*) echo "proxy image is not explicitly non-root" >&2; exit 1 ;; esac
}
assert_geth() {
    running "$geth" || { echo "geth shadow is not running" >&2; exit 1; }
    [ "$(label "$geth" agent)" = codex-sec5-engine-shadow-geth ] || { echo "geth shadow ownership mismatch" >&2; exit 1; }
    [ "$(docker container inspect --format '{{.Image}}' "$geth")" = "$geth_id" ] || { echo "geth shadow image mismatch" >&2; exit 1; }
    actual_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$geth")"
    [ "$actual_datadir" = "$geth_datadir" ] || { echo "geth shadow datadir mismatch" >&2; exit 1; }
}
run_proxy() {
    phase="$1"; soak_epoch="${2:-}"; soak_iso="${3:-}"
    docker run --detach --pull never --name "$proxy" \
        --label agent=codex-sec5-engine-shadow-proxy \
        --label "io.ethereum-lisp.shadow-revision=$revision" \
        --label "io.ethereum-lisp.shadow-phase=$phase" \
        --label "io.ethereum-lisp.shadow-soak-start-epoch=$soak_epoch" \
        --label "io.ethereum-lisp.shadow-soak-start=$soak_iso" \
        --user 10001:10001 --read-only --cap-drop ALL \
        --security-opt no-new-privileges --memory "$proxy_memory" \
        --memory-swap "$proxy_memory" --pids-limit 64 \
        --network "$cl_network" --network-alias "$stable_alias" \
        --env "SHADOW_PROXY_PRIMARY_URL=http://$source_alias:8551" \
        --env "SHADOW_PROXY_SECONDARY_URL=http://$geth_alias:8551" \
        --env "SHADOW_PROXY_PRIMARY_RPC_URL=http://$source_alias:8545" \
        --env "SHADOW_PROXY_SECONDARY_RPC_URL=http://$geth_alias:8545" \
        --env "SHADOW_PROXY_HEAD_INTERVAL_SECONDS=$head_interval" \
        "$proxy_image" >/dev/null
}
wait_proxy_traffic() {
    deadline="$(( $(date +%s) + ready_timeout ))"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if running "$proxy" && proxy_probe /healthz >/dev/null 2>&1; then
            metrics="$(proxy_probe /metrics)"
            requests="$(metric "$metrics" shadow_primary_requests_total)"
            errors="$(metric "$metrics" shadow_primary_errors_total)"
            if [ "${requests:-0}" -gt 0 ] && [ "${errors:-1}" -eq 0 ]; then return 0; fi
        fi
        sleep 2
    done
    return 1
}
wait_heads_equal() {
    deadline="$(( $(date +%s) + ready_timeout ))"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if sync_complete "$source" && sync_complete "$geth"; then
            source_latest="$(block_hash "$source" latest)"
            geth_latest="$(block_hash "$geth" latest)"
            source_finalized="$(block_hash "$source" finalized)"
            geth_finalized="$(block_hash "$geth" finalized)"
            if [ -n "$source_latest" ] && [ "$source_latest" = "$geth_latest" ] &&
               [ -n "$source_finalized" ] && [ "$source_finalized" = "$geth_finalized" ]; then
                return 0
            fi
        fi
        sleep 2
    done
    return 1
}

case "$action" in
status)
    date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
    free -b
    printf 'filesystem='; df -B1 --output=size,used,avail,pcent /data | tail -1
    for image in "$proxy_image" "$geth_image"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            docker image inspect --format 'image={{index .RepoTags 0}} id={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} user={{.Config.User}}' "$image"
        else
            printf 'image=%s absent\n' "$image"
        fi
    done
    for name in "$source" "$lighthouse" "$legacy" "$geth" "$proxy"; do
        if container_exists "$name"; then
            docker container inspect --format 'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} memory={{.HostConfig.Memory}} read-only={{.HostConfig.ReadonlyRootfs}} labels={{json .Config.Labels}}' "$name"
        else
            printf 'container=/%s absent\n' "$name"
        fi
    done
    for name in "$source" "$geth"; do
        if container_exists "$name" && running "$name"; then
            printf '%s-block=' "$name"; rpc "$name" eth_blockNumber || true; printf '\n'
            printf '%s-syncing=' "$name"; rpc "$name" eth_syncing || true; printf '\n'
        fi
    done
    if container_exists "$source"; then
        printf 'source-gate-revision=%s stable-alias=' "$(label "$source" io.ethereum-lisp.gate-revision)"
        if has_alias "$source" "$stable_alias"; then printf 'true\n'; else printf 'false\n'; fi
    fi
    if container_exists "$proxy" && running "$proxy"; then
        proxy_probe /healthz >/dev/null
        proxy_probe /metrics
    fi
    ;;
start-geth)
    assert_base
    sync_complete "$source" || { echo "source must be snap-to-head before geth shadow starts" >&2; exit 1; }
    [ "$(docker image inspect --format '{{.Id}}' "$geth_image")" = "$geth_id" ] || { echo "geth image id mismatch" >&2; exit 1; }
    [ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$geth_image")" = linux/amd64 ] || { echo "geth platform mismatch" >&2; exit 1; }
    container_exists "$legacy" || { echo "legacy geth evidence container is absent" >&2; exit 1; }
    running "$legacy" && { echo "legacy geth must remain stopped" >&2; exit 1; }
    [ "$(label "$legacy" agent)" = codex-geth-same-host-benchmark ] || { echo "legacy geth ownership mismatch" >&2; exit 1; }
    legacy_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$legacy")"
    [ "$legacy_datadir" = "$geth_datadir" ] || { echo "legacy geth datadir mismatch" >&2; exit 1; }
    container_exists "$geth" && { echo "refusing existing geth shadow container" >&2; exit 1; }
    [ -d "$geth_datadir" ] && [ -n "$(find "$geth_datadir" -mindepth 1 -maxdepth 1 -print -quit)" ] || { echo "geth datadir is absent or empty" >&2; exit 1; }
    [ -r "$jwt_dir/jwt.hex" ] || { echo "JWT is not readable" >&2; exit 1; }
    available="$(awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo)"
    [ "$available" -ge 3221225472 ] || { echo "less than 3 GiB memory is available" >&2; exit 1; }
    legacy_user="$(docker container inspect --format '{{.Config.User}}' "$legacy")"
    case "$legacy_user" in ''|0|0:*|*:0) echo "legacy geth user is not explicitly non-root" >&2; exit 1 ;; esac
    cleanup_geth() {
        if container_exists "$geth" && [ "$(label "$geth" agent)" = codex-sec5-engine-shadow-geth ]; then
            docker rm --force "$geth" >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_geth EXIT HUP INT TERM
    docker run --detach --pull never --name "$geth" \
        --label agent=codex-sec5-engine-shadow-geth \
        --label "io.ethereum-lisp.shadow-source=$source" \
        --label "io.ethereum-lisp.shadow-geth-image=$geth_id" \
        --user "$legacy_user" --read-only --cap-drop ALL \
        --security-opt no-new-privileges --memory "$geth_memory" \
        --memory-swap "$geth_memory" --pids-limit 512 \
        --mount "type=bind,source=$geth_datadir,target=/data" \
        --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
        --network "$cl_network" --network-alias "$geth_alias" \
        --publish "$geth_p2p_port:$geth_p2p_port/tcp" \
        --publish "$geth_p2p_port:$geth_p2p_port/udp" \
        --publish 127.0.0.1::8545 \
        "$geth_id" --hoodi --datadir /data --syncmode snap --state.scheme path \
        --cache 768 --port "$geth_p2p_port" --nat "extip:$public_ip" \
        --maxpeers 50 --ipcdisable --http --http.addr 0.0.0.0 --http.port 8545 \
        --http.api eth,net,web3,txpool,admin --http.vhosts '*' \
        --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
        --authrpc.jwtsecret /jwt/jwt.hex --authrpc.vhosts '*' >/dev/null
    docker network connect "$egress_network" "$geth"
    deadline="$(( $(date +%s) + ready_timeout ))"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if rpc "$geth" eth_chainId >/dev/null 2>&1; then
            trap - EXIT HUP INT TERM
            docker container inspect --format 'geth={{.Name}} running={{.State.Running}} image={{.Image}} user={{.Config.User}} memory={{.HostConfig.Memory}} read-only={{.HostConfig.ReadonlyRootfs}} networks={{len .NetworkSettings.Networks}}' "$geth"
            printf 'geth-datadir=%s preserved=true phase=awaiting-engine-fanout\n' "$geth_datadir"
            exit 0
        fi
        running "$geth" || break
        sleep 2
    done
    docker logs --tail 80 "$geth" >&2 || true
    echo "geth public RPC did not become ready" >&2
    exit 1
    ;;
cutover)
    assert_base; assert_proxy_image; assert_geth
    sync_complete "$source" || { echo "source is no longer snap-to-head" >&2; exit 1; }
    container_exists "$proxy" && { echo "refusing existing proxy container" >&2; exit 1; }
    has_alias "$source" "$stable_alias" || { echo "source does not own the stable alias" >&2; exit 1; }
    has_alias "$geth" "$geth_alias" || { echo "geth shadow alias is absent" >&2; exit 1; }
    docker stop --time 30 "$lighthouse" >/dev/null
    rollback_cutover() {
        docker rm --force "$proxy" >/dev/null 2>&1 || true
        docker network disconnect "$cl_network" "$source" >/dev/null 2>&1 || true
        docker network connect --alias "$stable_alias" "$cl_network" "$source" >/dev/null 2>&1 || true
        docker start "$lighthouse" >/dev/null 2>&1 || true
    }
    trap rollback_cutover EXIT HUP INT TERM
    docker network disconnect "$cl_network" "$source"
    docker network connect --alias "$source_alias" "$cl_network" "$source"
    run_proxy catchup
    docker start "$lighthouse" >/dev/null
    wait_proxy_traffic || { docker logs --tail 80 "$proxy" >&2 || true; echo "Lighthouse did not reach primary through proxy" >&2; exit 1; }
    trap - EXIT HUP INT TERM
    printf 'cutover=complete phase=catchup authority=%s shadow=%s alias=%s\n' "$source" "$geth" "$stable_alias"
    proxy_probe /metrics
    ;;
reset-soak)
    assert_base; assert_proxy_image; assert_geth
    running "$proxy" || { echo "proxy is not running" >&2; exit 1; }
    [ "$(label "$proxy" agent)" = codex-sec5-engine-shadow-proxy ] || { echo "proxy ownership mismatch" >&2; exit 1; }
    [ "$(label "$proxy" io.ethereum-lisp.shadow-revision)" = "$revision" ] || { echo "proxy revision mismatch" >&2; exit 1; }
    [ "$(label "$proxy" io.ethereum-lisp.shadow-phase)" = catchup ] || { echo "only catchup phase may start a new soak clock" >&2; exit 1; }
    wait_heads_equal || { echo "geth did not reach the same latest and finalized heads" >&2; exit 1; }
    docker stop --time 30 "$lighthouse" >/dev/null
    rollback_reset() {
        docker rm --force "$proxy" >/dev/null 2>&1 || true
        run_proxy catchup >/dev/null 2>&1 || true
        docker start "$lighthouse" >/dev/null 2>&1 || true
    }
    trap rollback_reset EXIT HUP INT TERM
    docker rm --force "$proxy" >/dev/null
    soak_epoch="$(date +%s)"; soak_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run_proxy soak "$soak_epoch" "$soak_iso"
    docker start "$lighthouse" >/dev/null
    wait_proxy_traffic || { echo "soak proxy did not receive healthy primary traffic" >&2; exit 1; }
    trap - EXIT HUP INT TERM
    printf 'soak-start=%s soak-start-epoch=%s required-seconds=%s\n' "$soak_iso" "$soak_epoch" "$required_soak"
    proxy_probe /metrics
    ;;
complete)
    assert_base; assert_proxy_image; assert_geth
    running "$proxy" || { echo "proxy is not running" >&2; exit 1; }
    [ "$(label "$proxy" agent)" = codex-sec5-engine-shadow-proxy ] || { echo "proxy ownership mismatch" >&2; exit 1; }
    [ "$(label "$proxy" io.ethereum-lisp.shadow-revision)" = "$revision" ] || { echo "proxy revision mismatch" >&2; exit 1; }
    [ "$(label "$proxy" io.ethereum-lisp.shadow-phase)" = soak ] || { echo "proxy is not in soak phase" >&2; exit 1; }
    soak_epoch="$(label "$proxy" io.ethereum-lisp.shadow-soak-start-epoch)"
    case "$soak_epoch" in *[!0-9]*|'') echo "invalid soak start epoch" >&2; exit 1 ;; esac
    now="$(date +%s)"; age="$(( now - soak_epoch ))"
    [ "$age" -ge "$required_soak" ] || { printf 'shadow-soak=incomplete elapsed-seconds=%s required-seconds=%s\n' "$age" "$required_soak" >&2; exit 1; }
    wait_heads_equal || { echo "clients do not share latest and finalized heads" >&2; exit 1; }
    balanced=false
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        metrics="$(proxy_probe /metrics)"
        primary="$(metric "$metrics" shadow_primary_requests_total)"
        primary_errors="$(metric "$metrics" shadow_primary_errors_total)"
        started="$(metric "$metrics" shadow_mirror_started_total)"
        succeeded="$(metric "$metrics" shadow_mirror_succeeded_total)"
        mirror_errors="$(metric "$metrics" shadow_mirror_errors_total)"
        dropped="$(metric "$metrics" shadow_mirror_dropped_total)"
        mismatches="$(metric "$metrics" shadow_status_mismatches_total)"
        observations="$(metric "$metrics" shadow_head_observations_total)"
        head_rpc_errors="$(metric "$metrics" shadow_head_rpc_errors_total)"
        lag_violations="$(metric "$metrics" shadow_head_lag_violations_total)"
        root_mismatches="$(metric "$metrics" shadow_head_root_mismatches_total)"
        max_lag="$(metric "$metrics" shadow_head_max_lag_blocks)"
        minimum_observations="$(( required_soak / head_interval * 95 / 100 ))"
        if [ "${primary:-0}" -gt 0 ] && [ "${primary_errors:-1}" -eq 0 ] &&
           [ "${mirror_errors:-1}" -eq 0 ] && [ "${dropped:-1}" -eq 0 ] &&
           [ "${mismatches:-1}" -eq 0 ] && [ "${started:-0}" -eq "${succeeded:-1}" ] &&
           [ "${observations:-0}" -ge "$minimum_observations" ] &&
           [ "${head_rpc_errors:-1}" -eq 0 ] && [ "${lag_violations:-1}" -eq 0 ] &&
           [ "${root_mismatches:-1}" -eq 0 ] && [ "${max_lag:-3}" -le 2 ]; then
            balanced=true; break
        fi
        sleep 1
    done
    [ "$balanced" = true ] || { echo "shadow counters do not satisfy the zero-error gate" >&2; printf '%s\n' "$metrics" >&2; exit 1; }
    printf 'shadow-soak=PASSED elapsed-seconds=%s latest=%s finalized=%s\n' "$age" "$source_latest" "$source_finalized"
    printf '%s\n' "$metrics"
    ;;
restore)
    assert_base; assert_geth
    running "$proxy" || { echo "proxy is not running" >&2; exit 1; }
    [ "$(label "$proxy" agent)" = codex-sec5-engine-shadow-proxy ] || { echo "proxy ownership mismatch" >&2; exit 1; }
    has_alias "$source" "$source_alias" || { echo "source primary alias is absent" >&2; exit 1; }
    has_alias "$proxy" "$stable_alias" || { echo "proxy stable alias is absent" >&2; exit 1; }
    docker stop --time 30 "$lighthouse" >/dev/null
    docker stop --time 10 "$proxy" >/dev/null
    rollback_restore() {
        docker stop --time 10 "$lighthouse" >/dev/null 2>&1 || true
        docker network disconnect "$cl_network" "$source" >/dev/null 2>&1 || true
        docker network connect --alias "$source_alias" "$cl_network" "$source" >/dev/null 2>&1 || true
        docker start "$proxy" >/dev/null 2>&1 || true
        docker start "$lighthouse" >/dev/null 2>&1 || true
    }
    trap rollback_restore EXIT HUP INT TERM
    docker network disconnect "$cl_network" "$source"
    docker network connect --alias "$stable_alias" "$cl_network" "$source"
    docker start "$lighthouse" >/dev/null
    deadline="$(( $(date +%s) + ready_timeout ))"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if running "$lighthouse" && sync_complete "$source"; then
            docker stop --time 30 "$geth" >/dev/null
            trap - EXIT HUP INT TERM
            printf 'restore=complete authority=%s proxy-running=false geth-running=false datadir-preserved=%s\n' "$source" "$geth_datadir"
            exit 0
        fi
        sleep 2
    done
    echo "direct Lighthouse-to-source restore did not become ready" >&2
    exit 1
    ;;
*) echo "unsupported remote action: $action" >&2; exit 2 ;;
esac
REMOTE
}

case "$action" in
inspect)
    if [ -f "$artifact" ]; then
        require_local_artifact
        printf 'local-image=%s revision=%s artifact=%s sha256=%s\n' \
            "$proxy_image" "$revision" "$artifact" "$artifact_sha256"
    else
        printf 'local-artifact=%s absent expected-revision=%s\n' "$artifact" "$revision"
    fi
    action=status
    remote_action
    ;;
upload) upload_artifact ;;
load) load_image ;;
status|start-geth|cutover|reset-soak|complete|restore)
    case "$action" in status|complete) ;; *) require_mutation ;; esac
    remote_action
    ;;
*) fail "usage: $0 inspect|upload|load|status|start-geth|cutover|reset-soak|complete|restore" ;;
esac
