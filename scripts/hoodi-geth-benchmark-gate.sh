#!/usr/bin/env bash
set -euo pipefail

# Same-host Hoodi SNAP benchmark for the already-pinned geth image. This gate
# preserves both clients and both datadirs, gives only one EL the stable
# Lighthouse alias at a time, and rolls back every failed cutover.
#
# The ethereum-lisp EL it stops (start) and starts again (restore) is a live
# gate container, so it keeps the live gate's revision fence
# (scripts/hoodi-live-gate.sh): the source must carry exactly the checkout's
# runtime revision (HOODI_GATE_RUNTIME_REVISION, default HEAD, which may lag
# HEAD only across docs and the reviewed gate scripts), and restore refuses to
# start it on a datadir whose RUNTIME-REVISION marker names a newer runtime
# unless HOODI_GATE_ALLOW_DOWNGRADE=1.  Container logs printed on a failure
# are masked by scripts/hoodi-log-redact.sh.  The stubbed self-test is
# scripts/hoodi-geth-benchmark-gate-selftest.sh.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-status}"

usage() {
    cat <<'USAGE'
Usage: scripts/hoodi-geth-benchmark-gate.sh ACTION

Read-only action: status
Mutating actions: start, restore

start stops the exact live-gate ethereum-lisp source EL and starts the pinned
geth image on a fresh datadir under the same Lighthouse alias; restore stops
geth and starts the source again. Both require HOODI_GETH_ALLOW_MUTATION=1
and a clean checkout, and neither removes a container, image or datadir.

Revision fence (the live gate's): the source container (default
hoodi-el-sec5-<rev8>, HOODI_GETH_SOURCE_CONTAINER) must be labelled with the
runtime revision HOODI_GATE_RUNTIME_REVISION (default HEAD) and mounted on
HOODI_GETH_SOURCE_DATADIR (default
/data/hoodi-sec5-20260814/datadir-<rev8>). That revision may be an ancestor of
HEAD only when every change since is below docs/ or a reviewed Hoodi gate
script; otherwise start and restore refuse. restore refuses to start the
source on a datadir whose RUNTIME-REVISION marker names a revision that is
not the runtime revision or an ancestor of it (older, unknown, diverged or
malformed); HOODI_GATE_ALLOW_DOWNGRADE=1 overrides that and leaves the newer
revision in the marker.

When geth does not come up, start prints its last 80 log lines with peer
identities masked (node ids and keys to their first 8 and last 4 hex digits,
enode endpoints, enr records, and every IPv4/IPv6 address but loopback;
scripts/hoodi-log-redact.sh). The full log stays on the remote host in
Docker's container log.
USAGE
}

case "$action" in
    status|start|restore) ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "unknown action: $action" >&2; usage >&2; exit 2 ;;
esac

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_GATE_RUNTIME_REVISION:-$actual_head}"
case "$revision" in
    *[!0-9a-f]*|'') fail "revision must be a full lowercase hexadecimal Git id" ;;
esac
[ "${#revision}" -eq 40 ] || fail "revision must contain exactly 40 hexadecimal characters"
short_revision="${revision:0:8}"

host="${HOODI_GETH_HOST:-test-ethereum-server}"
image="${HOODI_GETH_IMAGE:-ethereum/client-go:v1.17.4}"
expected_image_id="${HOODI_GETH_IMAGE_ID:-sha256:9389d3371a5cde510edb5dfa10a759f7ef98bd8676e6491ce79ab1050306478b}"
container="${HOODI_GETH_CONTAINER:-hoodi-geth-v1.17.4-baseline}"
datadir="${HOODI_GETH_DATADIR:-/data/hoodi-sec5-20260814/geth-v1.17.4-baseline}"
source="${HOODI_GETH_SOURCE_CONTAINER:-hoodi-el-sec5-${short_revision}}"
source_datadir="${HOODI_GETH_SOURCE_DATADIR:-/data/hoodi-sec5-20260814/datadir-${short_revision}}"
lighthouse="${HOODI_GETH_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
cl_network="${HOODI_GETH_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_GETH_EGRESS_NETWORK:-hoodi-net}"
cl_alias="${HOODI_GETH_CL_ALIAS:-hoodi-el-public-36a22e47}"
jwt_dir="${HOODI_GETH_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_GETH_PUBLIC_IP:-165.154.224.110}"
p2p_port="${HOODI_GETH_P2P_PORT:-30303}"
ready_timeout="${HOODI_GETH_READY_TIMEOUT:-600}"
# restore refuses to start the source on a datadir whose RUNTIME-REVISION
# marker names a newer revision (a descendant of the source's, or one this
# checkout cannot order): that runtime may have written state the source
# cannot read.  1 overrides it, knowingly.
allow_downgrade="${HOODI_GATE_ALLOW_DOWNGRADE:-0}"
log_redact_lib="$repo_root/scripts/hoodi-log-redact.sh"

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$image" in *[!A-Za-z0-9_.:/@+-]*|'') fail "unsafe image: $image" ;; esac
case "$expected_image_id" in sha256:*) ;; *) fail "image id must use sha256" ;; esac
image_digest="${expected_image_id#sha256:}"
case "$image_digest" in *[!0-9a-f]*|'') fail "unsafe image digest" ;; esac
[ "${#image_digest}" -eq 64 ] || fail "image id must contain a 64-character digest"
case "$container" in *[!A-Za-z0-9_.-]*|'') fail "unsafe container: $container" ;; esac
case "$source" in *[!A-Za-z0-9_.-]*|'') fail "unsafe source container: $source" ;; esac
case "$datadir$source_datadir$jwt_dir" in
    *'..'*|*$'\n'*|*$'\r'*|*$'\t'*|*' '*) fail "remote paths must be absolute, normalized, and whitespace-free" ;;
esac
case "$datadir" in /data/hoodi-sec5-*/geth-*) ;; *) fail "unsafe geth datadir: $datadir" ;; esac
case "$source_datadir" in
    /data/hoodi-sec5-*/*) ;;
    *) fail "source datadir must stay below /data/hoodi-sec5-*: $source_datadir" ;;
esac
case "$source_datadir" in */|*//*) fail "source datadir must be a normalized path" ;; esac
case "$datadir/" in "$source_datadir"/*) fail "geth datadir must not be inside the source datadir" ;; esac
case "$source_datadir/" in "$datadir"/*) fail "source datadir must not be inside the geth datadir" ;; esac
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$p2p_port" in *[!0-9]*|'') fail "P2P port must be an integer" ;; esac
[ "$p2p_port" -ge 1024 ] && [ "$p2p_port" -le 65535 ] || fail "P2P port is out of range"
case "$ready_timeout" in *[!0-9]*|'') fail "ready timeout must be an integer" ;; esac
[ "$ready_timeout" -ge 30 ] && [ "$ready_timeout" -le 1800 ] || fail "ready timeout is out of range"
case "$allow_downgrade" in
    0|1) ;;
    *) fail "downgrade allowance must be zero or one" ;;
esac
[ -f "$log_redact_lib" ] || fail "log redaction filter is absent: $log_redact_lib"

# The live gate's revision fence: a runtime revision behind HEAD is accepted
# only for read-only status, or when nothing runtime-sensitive changed since.
if [ "$actual_head" != "$revision" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "runtime revision $revision is not an ancestor of checkout HEAD $actual_head"
    runtime_sensitive_changes="$(git -C "$repo_root" diff --name-only \
        "$revision" "$actual_head" -- . \
        ':(exclude)docs/**' \
        ':(exclude)scripts/hoodi-live-gate.sh' \
        ':(exclude)scripts/hoodi-live-gate-selftest.sh' \
        ':(exclude)scripts/hoodi-fleet-status.sh' \
        ':(exclude)scripts/hoodi-fleet-status-selftest.sh' \
        ':(exclude)scripts/hoodi-hive-gate.sh' \
        ':(exclude)scripts/hoodi-hive-gate-remote.sh' \
        ':(exclude)scripts/hoodi-hive-gate-selftest.sh' \
        ':(exclude)tests/control-plane-broker-tests.lisp' \
        ':(exclude)scripts/hoodi-log-redact.sh' \
        ':(exclude)scripts/hoodi-geth-benchmark-gate.sh' \
        ':(exclude)scripts/hoodi-geth-benchmark-gate-selftest.sh' \
        ':(exclude)scripts/hoodi-lisp-benchmark-gate.sh')"
    case "$action" in
        status) ;;
        *) [ -z "$runtime_sensitive_changes" ] ||
               fail "checkout changed runtime-sensitive paths after $revision: $runtime_sensitive_changes" ;;
    esac
fi

require_clean_checkout() {
    git -C "$repo_root" diff --quiet || fail "checkout has unstaged changes"
    git -C "$repo_root" diff --cached --quiet || fail "checkout has staged changes"
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "checkout has untracked files"
}

require_mutation() {
    [ "${HOODI_GETH_ALLOW_MUTATION:-}" = 1 ] ||
        fail "$action changes remote state; set HOODI_GETH_ALLOW_MUTATION=1 after explicit authorization"
    require_clean_checkout
}

# Functions the remote scripts share, sent ahead of each one.  The marker
# functions keep the rules and messages of scripts/hoodi-live-gate.sh.
# (A function that prints them, not a $(...) capture: bash would otherwise
# parse the heredoc's comments for quotes while scanning the substitution.)
print_remote_lib() {
    cat <<'LIB'
gate_fail() {
    echo "$*" >&2
    exit 1
}

# gate_verify_source CONTAINER REVISION DATADIR: the source EL is a live-gate
# container at exactly REVISION, on DATADIR, with an explicit non-root user.
gate_verify_source() {
    vs_agent="$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$1")"
    vs_gate="$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$1")"
    vs_image="$(docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$1")"
    vs_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$1")"
    vs_user="$(docker container inspect --format '{{.Config.User}}' "$1")"
    [ "$vs_agent" = codex-sec5-live-gate ] || gate_fail "source EL ownership mismatch"
    [ "$vs_gate" = "$2" ] ||
        gate_fail "source EL gate revision mismatch: ${vs_gate:-none}, expected $2 (HOODI_GATE_RUNTIME_REVISION)"
    [ "$vs_image" = "$2" ] ||
        gate_fail "source EL image revision mismatch: ${vs_image:-none}, expected $2 (HOODI_GATE_RUNTIME_REVISION)"
    [ "$vs_datadir" = "$3" ] ||
        gate_fail "source EL datadir mismatch: ${vs_datadir:-none}, expected $3 (HOODI_GETH_SOURCE_DATADIR)"
    case "$vs_user" in
        0|0:*|*:0|'') gate_fail "source EL user is not an explicit non-root user" ;;
    esac
}

# gate_read_runtime_revision DATADIR: the marker's revision, "absent", or
# "malformed" (anything but one 40-hex line, a symbolic link included).
gate_read_runtime_revision() {
    rr_file="$1/RUNTIME-REVISION"
    if [ -L "$rr_file" ]; then
        echo malformed
    elif [ ! -e "$rr_file" ]; then
        echo absent
    elif [ ! -f "$rr_file" ] || [ "$(( $(wc -c < "$rr_file") ))" -ne 41 ]; then
        echo malformed
    else
        rr_value="$(head -n 1 "$rr_file")"
        case "$rr_value" in
            *[!0-9a-f]*) echo malformed ;;
            *) if [ "${#rr_value}" -eq 40 ]; then echo "$rr_value"; else echo malformed; fi ;;
        esac
    fi
}

# gate_require_runtime_revision DATADIR EXPECTED: the marker still reads what
# the control plane judged, so nothing can slip in between the two.
gate_require_runtime_revision() {
    rq_now="$(gate_read_runtime_revision "$1")"
    [ "$rq_now" = "$2" ] ||
        gate_fail "RUNTIME-REVISION in $1 changed since the control plane checked it: now $rq_now, checked $2; nothing was started"
}

# gate_write_runtime_revision DATADIR MARKER RUNTIME: record MARKER just before
# RUNTIME starts on DATADIR, through a rename.
gate_write_runtime_revision() {
    rw_partial="$1/.RUNTIME-REVISION.partial"
    rm -f "$rw_partial"
    printf '%s\n' "$2" > "$rw_partial"
    mv -f "$rw_partial" "$1/RUNTIME-REVISION"
    printf 'runtime-revision-marker=%s written runtime=%s\n' "$2" "$3"
}
LIB
}

# remote ARG...: run the remote script on stdin, after the shared functions
# and the log redaction filter, with the given positional arguments.
remote() {
    { print_remote_lib; cat "$log_redact_lib"; cat; } | ssh "$host" bash -s -- "$@"
}

# read_runtime_marker: the source datadir's RUNTIME-REVISION marker (a
# revision, "absent" or "malformed").  Read-only on the remote side.
print_runtime_marker() {
    remote "$source_datadir" <<'REMOTE'
set -eu
printf 'runtime-revision-marker-read=%s\n' "$(gate_read_runtime_revision "$1")"
REMOTE
}
read_runtime_marker() {
    local marker
    marker="$(print_runtime_marker | sed -n 's/^runtime-revision-marker-read=//p')" ||
        fail "could not read the runtime revision marker in $source_datadir"
    case "$marker" in
        absent|malformed) ;;
        *[!0-9a-f]*|'') fail "unexpected runtime revision marker read: $marker" ;;
        *) [ "${#marker}" -eq 40 ] || fail "unexpected runtime revision marker read: $marker" ;;
    esac
    printf '%s' "$marker"
}

# decide_runtime_order MARKER: refuse to start the source's revision on a
# datadir that a newer runtime has opened, unless HOODI_GATE_ALLOW_DOWNGRADE=1
# (scripts/hoodi-live-gate.sh, decide_runtime_order, with no fallback).  Sets
# marker_to_write: the runtime revision, or on an allowed downgrade the newer
# revision it replaces, so a later start is still judged against that.
decide_runtime_order() {
    local last="$1" marker_file="$source_datadir/RUNTIME-REVISION" reason=""
    marker_to_write="$revision"
    if [ "$last" = absent ]; then
        printf 'runtime-order=first datadir=%s (no marker)\n' "$source_datadir"
        return 0
    elif [ "$last" = malformed ]; then
        reason="its marker $marker_file is malformed"
    elif [ "$last" = "$revision" ]; then
        printf 'runtime-order=same revision=%s source=%s\n' "$revision" "$marker_file"
        return 0
    elif ! git -C "$repo_root" cat-file -e "$last^{commit}" 2>/dev/null; then
        reason="its last runtime revision $last ($marker_file) is not a commit in this checkout, so $revision cannot be shown to be at least it"
    elif git -C "$repo_root" merge-base --is-ancestor "$last" "$revision"; then
        printf 'runtime-order=newer revision=%s last=%s source=%s\n' "$revision" "$last" "$marker_file"
        return 0
    elif git -C "$repo_root" merge-base --is-ancestor "$revision" "$last"; then
        reason="$revision is older than its last runtime revision $last ($marker_file)"
    else
        reason="$revision does not descend from its last runtime revision $last ($marker_file)"
    fi
    [ "$allow_downgrade" = 1 ] ||
        fail "refusing to start $revision on $source_datadir: $reason; a newer runtime may have written what this one cannot read (set HOODI_GATE_ALLOW_DOWNGRADE=1 only after checking that it can)"
    printf 'runtime-order=downgrade-allowed reason=%s\n' "$reason"
    [ "$last" = malformed ] || marker_to_write="$last"
}

status() {
    printf 'runtime-revision=%s head=%s source=%s source-datadir=%s\n' \
        "$revision" "$actual_head" "$source" "$source_datadir"
    remote "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" "$source_datadir" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"; source_datadir="$9"
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
printf 'source-runtime-revision-marker=%s\n' "$(gate_read_runtime_revision "$source_datadir")"
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
    remote "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$lighthouse" "$cl_network" "$egress_network" "$cl_alias" \
        "$jwt_dir" "$public_ip" "$p2p_port" "$ready_timeout" \
        "$revision" "$source_datadir" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
lighthouse="$6"; cl_network="$7"; egress_network="$8"; cl_alias="$9"
jwt_dir="${10}"; public_ip="${11}"; p2p_port="${12}"; ready_timeout="${13}"
revision="${14}"; source_datadir="${15}"

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
gate_verify_source "$source" "$revision" "$source_datadir"
source_user="$(docker container inspect --format '{{.Config.User}}' "$source")"
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
        printf 'source=%s source-revision=%s source-datadir=%s\n' "$source" "$revision" "$source_datadir"
        exit 0
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$container")" = true ] || break
    sleep 1
done
docker logs --tail 80 "$container" 2>&1 | tail -n 80 | hoodi_redact_peer_identities >&2 || true
echo "geth public RPC did not become ready" >&2
exit 1
REMOTE
}

restore() {
    require_mutation
    # Restore starts the source runtime again: it is not started on a datadir
    # a newer runtime has opened since (for example a live-gate upgrade that
    # reused this datadir while geth held the alias).
    local runtime_marker
    runtime_marker="$(read_runtime_marker)"
    decide_runtime_order "$runtime_marker"
    remote "$image" "$expected_image_id" "$container" "$datadir" \
        "$source" "$cl_alias" "$ready_timeout" "$revision" "$source_datadir" \
        "$runtime_marker" "$marker_to_write" <<'REMOTE'
set -eu
image="$1"; expected="$2"; container="$3"; datadir="$4"; source="$5"
cl_alias="$6"; ready_timeout="$7"; revision="$8"; source_datadir="$9"
expected_marker="${10}"; marker_to_write="${11}"
[ "$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$container")" = \
   codex-geth-same-host-benchmark ] || { echo "geth benchmark ownership mismatch" >&2; exit 1; }
[ "$(docker container inspect --format '{{.Image}}' "$container")" = "$expected" ] || {
    echo "geth benchmark image mismatch" >&2; exit 1;
}
actual_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
[ "$actual_datadir" = "$datadir" ] || { echo "geth benchmark datadir mismatch" >&2; exit 1; }
gate_verify_source "$source" "$revision" "$source_datadir"
gate_require_runtime_revision "$source_datadir" "$expected_marker"

docker stop --time 30 "$container" >/dev/null
rollback() { docker stop --time 10 "$source" >/dev/null 2>&1 || true; docker start "$container" >/dev/null 2>&1 || true; }
trap rollback EXIT HUP INT TERM
gate_write_runtime_revision "$source_datadir" "$marker_to_write" "$revision"
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
esac
