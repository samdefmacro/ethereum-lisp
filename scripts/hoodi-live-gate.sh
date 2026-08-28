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

actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_GATE_RUNTIME_REVISION:-$actual_head}"
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
seccomp_profile="$repo_root/tools/runtime/docker-26.1.4-io-uring-seccomp.json"
remote_seccomp_profile="$remote_root/${seccomp_profile##*/}"
expected_seccomp_sha256="68afe4d839d125a335c352d1707caa1482923a4c2adf5fa7c1789ca1da72672b"

lighthouse_container="${HOODI_GATE_LIGHTHOUSE_CONTAINER:-hoodi-lighthouse-public}"
old_container="${HOODI_GATE_OLD_CONTAINER:-hoodi-el-sec5-rehearsal-old3}"
previous_container="${HOODI_GATE_PREVIOUS_CONTAINER:-}"
previous_revision="${HOODI_GATE_PREVIOUS_REVISION:-}"
cl_network="${HOODI_GATE_CL_NETWORK:-hoodi-frozen}"
egress_network="${HOODI_GATE_EGRESS_NETWORK:-hoodi-net}"
# Lighthouse's persisted execution endpoint uses this stable network alias.
# Every replacement EL must claim the same name or the CL remains online but
# reports its execution layer offline after an otherwise successful upgrade.
cl_alias="${HOODI_GATE_CL_ALIAS:-hoodi-el-public-36a22e47}"
jwt_dir="${HOODI_GATE_JWT_DIR:-/data/hoodi/jwt}"
public_ip="${HOODI_GATE_PUBLIC_IP:-165.154.224.110}"
p2p_port="${HOODI_GATE_P2P_PORT:-30303}"
restart_ready_timeout="${HOODI_GATE_RESTART_READY_TIMEOUT:-600}"
# The saved SBCL core reserves a 6 GiB dynamic space.  Leave one GiB for the
# native database, stacks, and runtime metadata, but never let an accidental
# regression consume the whole dedicated host.
memory_limit_bytes=7516192768
allocation_profile_seconds="${HOODI_GATE_ALLOC_PROFILE_SECONDS:-0}"
allow_same_revision_profile="${HOODI_GATE_ALLOW_SAME_REVISION_PROFILE:-0}"

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$remote_root" in
    /data/hoodi-sec5-*) ;;
    *) fail "remote root must stay below /data/hoodi-sec5-*" ;;
esac
case "$remote_root$datadir$remote_artifact$remote_seccomp_profile$jwt_dir" in
    *'..'*|*$'\n'*|*$'\r'*|*$'\t'*|*' '*) fail "remote paths must be absolute, normalized, and whitespace-free" ;;
esac
case "$datadir" in "$remote_root"/*) ;; *) fail "datadir must stay below $remote_root" ;; esac
case "$remote_artifact" in "$remote_root"/*) ;; *) fail "artifact must stay below $remote_root" ;; esac
case "$image" in *[!A-Za-z0-9_.:/+-]*|'') fail "unsafe image name: $image" ;; esac
for name in "$container" "$lighthouse_container" "$old_container" "$cl_network" "$egress_network" "$cl_alias"; do
    case "$name" in *[!A-Za-z0-9_.-]*|'') fail "unsafe Docker name: $name" ;; esac
done
[ -z "$previous_container" ] ||
    case "$previous_container" in *[!A-Za-z0-9_.-]*) fail "unsafe previous container name: $previous_container" ;; esac
[ -z "$previous_revision" ] || {
    case "$previous_revision" in *[!0-9a-f]*) fail "previous revision must be lowercase hexadecimal" ;; esac
    [ "${#previous_revision}" -eq 40 ] || fail "previous revision must contain exactly 40 hexadecimal characters"
}
case "$public_ip" in *[!0-9.]*|'') fail "public IP must be an IPv4 literal" ;; esac
case "$p2p_port" in *[!0-9]*|'') fail "P2P port must be an integer" ;; esac
[ "$p2p_port" -ge 1024 ] && [ "$p2p_port" -le 65535 ] ||
    fail "P2P port must be between 1024 and 65535"
case "$restart_ready_timeout" in
    *[!0-9]*|'') fail "restart ready timeout must be an integer number of seconds" ;;
esac
[ "$restart_ready_timeout" -ge 30 ] && [ "$restart_ready_timeout" -le 1800 ] ||
    fail "restart ready timeout must be between 30 and 1800 seconds"
case "$allocation_profile_seconds" in
    *[!0-9]*|'') fail "allocation profile seconds must be an integer" ;;
esac
[ "$allocation_profile_seconds" -le 300 ] ||
    fail "allocation profile seconds must be at most 300"
case "$allow_same_revision_profile" in
    0|1) ;;
    *) fail "same-revision profile allowance must be zero or one" ;;
esac

if [ "$actual_head" != "$revision" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "runtime revision $revision is not an ancestor of checkout HEAD $actual_head"
    runtime_sensitive_changes="$(git -C "$repo_root" diff --name-only \
        "$revision" "$actual_head" -- . \
        ':(exclude)docs/**' \
        ':(exclude)scripts/hoodi-live-gate.sh' \
        ':(exclude)scripts/hoodi-geth-benchmark-gate.sh' \
        ':(exclude)scripts/hoodi-lisp-benchmark-gate.sh')"
    [ -z "$runtime_sensitive_changes" ] ||
        fail "checkout changed runtime-sensitive paths after $revision: $runtime_sensitive_changes"
fi

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
    [ -f "$seccomp_profile" ] || fail "seccomp profile is absent: $seccomp_profile"
    seccomp_sha256="$(sha256_file "$seccomp_profile")"
    [ "$seccomp_sha256" = "$expected_seccomp_sha256" ] ||
        fail "seccomp profile checksum is $seccomp_sha256, expected $expected_seccomp_sha256"
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
    printf 'seccomp-profile=%s sha256=%s\n' "$seccomp_profile" "$seccomp_sha256"

    note "remote read-only state"
    ssh "$host" bash -s -- \
        "$revision" "$image" "$remote_root" "$remote_artifact" "$remote_seccomp_profile" \
        "$expected_seccomp_sha256" "$container" "$lighthouse_container" \
        "$old_container" "$cl_network" "$egress_network" <<'REMOTE'
set -eu
revision="$1"; image="$2"; remote_root="$3"; remote_artifact="$4"; remote_seccomp="$5"
expected_seccomp="$6"; container="$7"; lighthouse="$8"; old="$9"
cl_network="${10}"; egress_network="${11}"
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
if [ -f "$remote_seccomp" ]; then
    actual_seccomp="$(sha256sum "$remote_seccomp" | awk '{print $1}')"
    printf 'remote-seccomp=%s sha256=%s expected=%s\n' \
        "$remote_seccomp" "$actual_seccomp" "$expected_seccomp"
else
    printf 'remote-seccomp=%s absent expected=%s\n' \
        "$remote_seccomp" "$expected_seccomp"
fi
REMOTE
}

upload_seccomp_profile() {
    local state partial
    partial="$remote_seccomp_profile.partial-$seccomp_sha256"
    state="$(ssh "$host" bash -s -- \
        "$remote_root" "$remote_seccomp_profile" "$partial" "$seccomp_sha256" <<'REMOTE'
set -eu
remote_root="$1"; final="$2"; partial="$3"; expected="$4"
install -d -m 0755 "$remote_root"
if [ -e "$final" ]; then
    actual="$(sha256sum "$final" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || {
        echo "existing seccomp checksum $actual does not match $expected" >&2
        exit 1
    }
    printf present
elif [ -e "$partial" ]; then
    echo "refusing to overwrite interrupted seccomp upload $partial" >&2
    exit 1
else
    printf upload
fi
REMOTE
)"
    if [ "$state" = "present" ]; then
        note "remote io_uring seccomp profile already has the expected checksum"
        return
    fi
    [ "$state" = "upload" ] || fail "unexpected seccomp upload preflight result: $state"
    note "uploading the pinned Docker 26.1.4 io_uring seccomp profile"
    scp "$seccomp_profile" "$host:$partial"
    ssh "$host" bash -s -- \
        "$remote_seccomp_profile" "$partial" "$seccomp_sha256" <<'REMOTE'
set -eu
final="$1"; partial="$2"; expected="$3"
actual="$(sha256sum "$partial" | awk '{print $1}')"
[ "$actual" = "$expected" ] || {
    echo "uploaded seccomp checksum $actual does not match $expected" >&2
    exit 1
}
chmod 0600 "$partial"
[ ! -e "$final" ] || { echo "refusing to overwrite $final" >&2; exit 1; }
mv "$partial" "$final"
printf 'uploaded-seccomp=%s sha256=%s\n' "$final" "$actual"
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
        upload_seccomp_profile
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
    upload_seccomp_profile
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
        "$remote_seccomp_profile" "$expected_seccomp_sha256" \
        "$lighthouse_container" "$old_container" "$cl_network" "$egress_network" \
        "$cl_alias" "$p2p_port" "$memory_limit_bytes" \
        "$allocation_profile_seconds" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; jwt_dir="$5"; public_ip="$6"
seccomp_profile="$7"; expected_seccomp="$8"; lighthouse="$9"; old="${10}"
cl_network="${11}"; egress_network="${12}"; cl_alias="${13}"; p2p_port="${14}"
memory_limit="${15}"
allocation_profile_seconds="${16}"

image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
[ "$image_revision" = "$revision" ] || { echo "image revision mismatch: $image_revision" >&2; exit 1; }
[ "$image_platform" = "linux/amd64" ] || { echo "image platform mismatch: $image_platform" >&2; exit 1; }
[ "$(docker version --format '{{.Server.Version}}')" = "26.1.4" ] || {
    echo "the pinned seccomp profile requires Docker server 26.1.4" >&2
    exit 1
}
[ -f "$seccomp_profile" ] || { echo "seccomp profile is absent: $seccomp_profile" >&2; exit 1; }
actual_seccomp="$(sha256sum "$seccomp_profile" | awk '{print $1}')"
[ "$actual_seccomp" = "$expected_seccomp" ] || {
    echo "seccomp profile checksum mismatch: $actual_seccomp" >&2
    exit 1
}
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
docker run --rm --pull never \
    --user "$gate_uid:$gate_gid" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --security-opt "seccomp=$seccomp_profile" \
    --memory "$memory_limit" \
    --memory-swap "$memory_limit" \
    --network none \
    --entrypoint /usr/local/libexec/ethereum-lisp-io-uring-probe \
    "$image"
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
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --security-opt "seccomp=$seccomp_profile" \
    --memory "$memory_limit" \
    --memory-swap "$memory_limit" \
    --env "ETHEREUM_LISP_ALLOC_PROFILE_SECONDS=$allocation_profile_seconds" \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" \
    --network-alias "$cl_alias" \
    --publish "$p2p_port:$p2p_port/tcp" \
    --publish "$p2p_port:$p2p_port/udp" \
    --publish 127.0.0.1::8545 \
    "$image" \
    --hoodi \
    --datadir /data \
    --port "$p2p_port" \
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
    --maxpeers 50 >/dev/null; then
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
    'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} memory={{.HostConfig.Memory}} memory-swap={{.HostConfig.MemorySwap}} caps={{json .HostConfig.CapDrop}} security-options={{len .HostConfig.SecurityOpt}} networks={{len .NetworkSettings.Networks}}' \
    "$container"
printf 'fresh-datadir=%s uid=%s gid=%s\n' "$datadir" "$gate_uid" "$gate_gid"
REMOTE
}

upgrade_gate() {
    require_mutation
    [ -n "$previous_container" ] || fail "upgrade requires HOODI_GATE_PREVIOUS_CONTAINER"
    [ -n "$previous_revision" ] || fail "upgrade requires HOODI_GATE_PREVIOUS_REVISION"
    [ "$previous_container" != "$container" ] || fail "upgrade requires a new container name"
    if [ "$previous_revision" = "$revision" ]; then
        [ "$allow_same_revision_profile" = 1 ] ||
            fail "upgrade requires a new runtime revision"
        [ "$allocation_profile_seconds" -gt 0 ] ||
            fail "same-revision replacement requires a non-zero allocation profile duration"
    fi
    note "replacing the exact previous EL while preserving its durable datadir"
    ssh "$host" bash -s -- \
        "$revision" "$image" "$container" "$datadir" "$jwt_dir" "$public_ip" \
        "$remote_seccomp_profile" "$expected_seccomp_sha256" \
        "$lighthouse_container" "$previous_container" "$previous_revision" \
        "$cl_network" "$egress_network" "$cl_alias" "$p2p_port" \
        "$restart_ready_timeout" "$memory_limit_bytes" \
        "$allocation_profile_seconds" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; datadir="$4"; jwt_dir="$5"; public_ip="$6"
seccomp_profile="$7"; expected_seccomp="$8"; lighthouse="$9"; previous="${10}"
previous_revision="${11}"; cl_network="${12}"; egress_network="${13}"
cl_alias="${14}"; p2p_port="${15}"; ready_timeout="${16}"
memory_limit="${17}"
allocation_profile_seconds="${18}"

image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
image_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
[ "$image_revision" = "$revision" ] || { echo "image revision mismatch: $image_revision" >&2; exit 1; }
[ "$image_platform" = "linux/amd64" ] || { echo "image platform mismatch: $image_platform" >&2; exit 1; }
[ "$(docker version --format '{{.Server.Version}}')" = "26.1.4" ] || {
    echo "the pinned seccomp profile requires Docker server 26.1.4" >&2
    exit 1
}
[ -f "$seccomp_profile" ] || { echo "seccomp profile is absent: $seccomp_profile" >&2; exit 1; }
actual_seccomp="$(sha256sum "$seccomp_profile" | awk '{print $1}')"
[ "$actual_seccomp" = "$expected_seccomp" ] || {
    echo "seccomp profile checksum mismatch: $actual_seccomp" >&2
    exit 1
}
[ "$(docker container inspect --format '{{.State.Running}}' "$lighthouse")" = true ] || {
    echo "required Lighthouse container is not running: $lighthouse" >&2
    exit 1
}
previous_initially_running="$(docker container inspect --format '{{.State.Running}}' "$previous")"
case "$previous_initially_running" in
    true|false) ;;
    *) echo "previous gate has an unknown running state: $previous_initially_running" >&2; exit 1 ;;
esac
previous_agent="$(docker container inspect --format '{{ index .Config.Labels "agent" }}' "$previous")"
previous_gate_revision="$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$previous")"
previous_image_revision="$(docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$previous")"
previous_datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$previous")"
previous_user="$(docker container inspect --format '{{.Config.User}}' "$previous")"
previous_read_only="$(docker container inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$previous")"
[ "$previous_agent" = codex-sec5-live-gate ] || { echo "previous gate ownership mismatch: $previous_agent" >&2; exit 1; }
[ "$previous_gate_revision" = "$previous_revision" ] || { echo "previous gate revision mismatch: $previous_gate_revision" >&2; exit 1; }
[ "$previous_image_revision" = "$previous_revision" ] || { echo "previous image revision mismatch: $previous_image_revision" >&2; exit 1; }
[ "$previous_datadir" = "$datadir" ] || { echo "previous datadir mismatch: $previous_datadir" >&2; exit 1; }
[ "$previous_read_only" = true ] || { echo "previous gate root filesystem is not read-only" >&2; exit 1; }
case "$previous_user" in 0|0:*|*:0|'') echo "previous gate does not have an explicit non-root user" >&2; exit 1 ;; esac
docker run --rm --pull never \
    --user "$previous_user" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --security-opt "seccomp=$seccomp_profile" \
    --memory "$memory_limit" \
    --memory-swap "$memory_limit" \
    --network none \
    --entrypoint /usr/local/libexec/ethereum-lisp-io-uring-probe \
    "$image"
[ -d "$datadir" ] && [ -n "$(find "$datadir" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
    echo "upgrade datadir is absent or empty: $datadir" >&2
    exit 1
}
[ -r "$jwt_dir/jwt.hex" ] || { echo "JWT file is not readable: $jwt_dir/jwt.hex" >&2; exit 1; }
docker network inspect "$cl_network" >/dev/null
docker network inspect "$egress_network" >/dev/null
if docker container inspect "$container" >/dev/null 2>&1; then
    echo "refusing to replace existing upgrade container: $container" >&2
    exit 1
fi

resolve_rpc_port() {
    docker port "$1" 8545/tcp |
        awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}'
}
rpc() {
    rpc_container="$1"; method="$2"; max_time="${3:-10}"
    rpc_port="$(resolve_rpc_port "$rpc_container")"
    [ -n "$rpc_port" ] || return 1
    curl --silent --show-error --max-time "$max_time" \
        --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" \
        "http://127.0.0.1:$rpc_port"
}

if [ "$previous_initially_running" != true ]; then
    docker start "$previous" >/dev/null
fi
previous_ready=false
previous_ready_deadline="$(( $(date +%s) + ready_timeout ))"
while :; do
    previous_ready_now="$(date +%s)"
    previous_ready_remaining="$(( previous_ready_deadline - previous_ready_now ))"
    [ "$previous_ready_remaining" -gt 0 ] || break
    if [ "$previous_ready_remaining" -gt 10 ]; then
        previous_attempt_timeout=10
    else
        previous_attempt_timeout="$previous_ready_remaining"
    fi
    if rpc "$previous" eth_chainId "$previous_attempt_timeout" >/dev/null 2>&1; then
        previous_ready=true
        break
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$previous")" = true ] || break
    sleep 1
done
if [ "$previous_ready" != true ]; then
    docker logs "$previous" 2>&1 | tail -80 >&2 || true
    if [ "$previous_initially_running" != true ]; then
        docker stop --time 10 "$previous" >/dev/null 2>&1 || true
    fi
    echo "previous public RPC did not return within ${ready_timeout}s" >&2
    exit 1
fi

date -u +before-timestamp=%Y-%m-%dT%H:%M:%SZ
printf 'before-container=%s\n' "$previous"
printf 'before-started='; docker container inspect --format '{{.State.StartedAt}}' "$previous"
printf 'before-datadir-bytes='; du -sb "$datadir" | awk '{print $1}'
printf 'before-block='; rpc "$previous" eth_blockNumber; printf '\n'
printf 'before-syncing='; rpc "$previous" eth_syncing; printf '\n'

docker stop --time 30 "$previous" >/dev/null
rollback() {
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker stop --time 10 "$container" >/dev/null 2>&1 || true
    fi
    docker start "$previous" >/dev/null 2>&1 || true
}
trap rollback EXIT HUP INT TERM

if ! docker run --detach --pull never \
    --name "$container" \
    --label agent=codex-sec5-live-gate \
    --label "io.ethereum-lisp.gate-revision=$revision" \
    --label "io.ethereum-lisp.gate-upgraded-from=$previous_revision" \
    --user "$previous_user" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --security-opt "seccomp=$seccomp_profile" \
    --memory "$memory_limit" \
    --memory-swap "$memory_limit" \
    --env "ETHEREUM_LISP_ALLOC_PROFILE_SECONDS=$allocation_profile_seconds" \
    --mount "type=bind,source=$datadir,target=/data" \
    --mount "type=bind,source=$jwt_dir,target=/jwt,readonly" \
    --network "$cl_network" \
    --network-alias "$cl_alias" \
    --publish "$p2p_port:$p2p_port/tcp" \
    --publish "$p2p_port:$p2p_port/udp" \
    --publish 127.0.0.1::8545 \
    "$image" \
    --hoodi \
    --datadir /data \
    --port "$p2p_port" \
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
    --maxpeers 50 >/dev/null; then
    rollback
    trap - EXIT HUP INT TERM
    exit 1
fi
if ! docker network connect "$egress_network" "$container"; then
    rollback
    trap - EXIT HUP INT TERM
    echo "failed to attach upgraded gate to $egress_network; previous container restored" >&2
    exit 1
fi

ready=false
ready_deadline="$(( $(date +%s) + ready_timeout ))"
while :; do
    ready_now="$(date +%s)"
    ready_remaining="$(( ready_deadline - ready_now ))"
    [ "$ready_remaining" -gt 0 ] || break
    if [ "$ready_remaining" -gt 10 ]; then attempt_timeout=10; else attempt_timeout="$ready_remaining"; fi
    if rpc "$container" eth_chainId "$attempt_timeout" >/dev/null 2>&1; then
        ready=true
        break
    fi
    [ "$(docker container inspect --format '{{.State.Running}}' "$container")" = true ] || break
    sleep 1
done
if [ "$ready" != true ]; then
    docker logs "$container" 2>&1 | tail -80 >&2 || true
    rollback
    trap - EXIT HUP INT TERM
    echo "upgraded public RPC did not return within ${ready_timeout}s; previous container restored" >&2
    exit 1
fi
trap - EXIT HUP INT TERM
date -u +after-timestamp=%Y-%m-%dT%H:%M:%SZ
printf 'after-container=%s\n' "$container"
printf 'after-started='; docker container inspect --format '{{.State.StartedAt}}' "$container"
printf 'after-datadir-bytes='; du -sb "$datadir" | awk '{print $1}'
printf 'after-block='; rpc "$container" eth_blockNumber; printf '\n'
printf 'after-syncing='; rpc "$container" eth_syncing; printf '\n'
printf 'previous-running='; docker container inspect --format '{{.State.Running}}' "$previous"
docker container inspect --format \
    'container={{.Name}} running={{.State.Running}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} memory={{.HostConfig.Memory}} memory-swap={{.HostConfig.MemorySwap}} caps={{json .HostConfig.CapDrop}} security-options={{len .HostConfig.SecurityOpt}} revision={{index .Config.Labels "io.ethereum-lisp.gate-revision"}} upgraded-from={{index .Config.Labels "io.ethereum-lisp.gate-upgraded-from"}} networks={{len .NetworkSettings.Networks}}' \
    "$container"
REMOTE
}

remote_status() {
    note "remote gate status"
    ssh "$host" bash -s -- \
        "$revision" "$image" "$container" "$remote_root" "$memory_limit_bytes" <<'REMOTE'
set -eu
revision="$1"; image="$2"; container="$3"; remote_root="$4"; memory_limit="$5"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
[ "$image_revision" = "$revision" ] || { echo "image revision mismatch: $image_revision" >&2; exit 1; }
docker image inspect --format \
    'image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image"
actual_memory="$(docker container inspect --format '{{.HostConfig.Memory}}' "$container")"
actual_memory_swap="$(docker container inspect --format '{{.HostConfig.MemorySwap}}' "$container")"
[ "$actual_memory" = "$memory_limit" ] || {
    echo "gate memory limit mismatch: $actual_memory" >&2
    exit 1
}
[ "$actual_memory_swap" = "$memory_limit" ] || {
    echo "gate memory-swap limit mismatch: $actual_memory_swap" >&2
    exit 1
}
datadir="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
case "$datadir" in
    "$remote_root"/*) ;;
    *) echo "container datadir is outside the reviewed remote root" >&2; exit 1 ;;
esac
docker container inspect --format \
    'container={{.Name}} running={{.State.Running}} started={{.State.StartedAt}} image={{.Image}} user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} memory={{.HostConfig.Memory}} memory-swap={{.HostConfig.MemorySwap}} caps={{json .HostConfig.CapDrop}} security-options={{len .HostConfig.SecurityOpt}} networks={{len .NetworkSettings.Networks}}' \
    "$container"
printf 'datadir-bytes='
du -sb "$datadir" | awk '{print $1}'
printf 'datadir=%s\n' "$datadir"

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
REMOTE
}

restart_gate() {
    require_mutation
    note "recording progress, restarting the same container, and recording it again"
    ssh "$host" bash -s -- \
        "$revision" "$container" "$datadir" "$restart_ready_timeout" \
        "$memory_limit_bytes" <<'REMOTE'
set -eu
revision="$1"; container="$2"; datadir="$3"; ready_timeout="$4"
memory_limit="$5"
label="$(docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$container")"
[ "$label" = "$revision" ] || { echo "gate ownership mismatch: $label" >&2; exit 1; }
mount_source="$(docker container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")"
[ "$mount_source" = "$datadir" ] || { echo "gate datadir mismatch: $mount_source" >&2; exit 1; }
actual_memory="$(docker container inspect --format '{{.HostConfig.Memory}}' "$container")"
actual_memory_swap="$(docker container inspect --format '{{.HostConfig.MemorySwap}}' "$container")"
[ "$actual_memory" = "$memory_limit" ] || {
    echo "gate memory limit mismatch: $actual_memory" >&2
    exit 1
}
[ "$actual_memory_swap" = "$memory_limit" ] || {
    echo "gate memory-swap limit mismatch: $actual_memory_swap" >&2
    exit 1
}

resolve_rpc_port() {
    docker port "$container" 8545/tcp |
        awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}'
}
rpc() {
    method="$1"
    max_time="${2:-10}"
    rpc_port="$(resolve_rpc_port)"
    [ -n "$rpc_port" ] || return 1
    curl --silent --show-error --max-time "$max_time" \
        --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" \
        "http://127.0.0.1:$rpc_port"
}
date -u +before-timestamp=%Y-%m-%dT%H:%M:%SZ
printf 'before-started='; docker container inspect --format '{{.State.StartedAt}}' "$container"
before_running="$(docker container inspect --format '{{.State.Running}}' "$container")"
printf 'before-running=%s\n' "$before_running"
printf 'before-finished='; docker container inspect --format '{{.State.FinishedAt}}' "$container"
printf 'before-exit='; docker container inspect --format '{{.State.ExitCode}}' "$container"
printf 'before-oom='; docker container inspect --format '{{.State.OOMKilled}}' "$container"
printf 'before-datadir-bytes='; du -sb "$datadir" | awk '{print $1}'
if before_block="$(rpc eth_blockNumber)"; then
    printf 'before-block=%s\n' "$before_block"
else
    printf '%s\n' 'before-block=unavailable'
fi
if before_syncing="$(rpc eth_syncing)"; then
    printf 'before-syncing=%s\n' "$before_syncing"
else
    printf '%s\n' 'before-syncing=unavailable'
fi

if [ "$before_running" = true ]; then
    docker stop --time 30 "$container" >/dev/null
fi
docker start "$container" >/dev/null

ready=false
ready_deadline="$(( $(date +%s) + ready_timeout ))"
while :; do
    ready_now="$(date +%s)"
    ready_remaining="$(( ready_deadline - ready_now ))"
    [ "$ready_remaining" -gt 0 ] || break
    if [ "$ready_remaining" -gt 10 ]; then
        attempt_timeout=10
    else
        attempt_timeout="$ready_remaining"
    fi
    if rpc eth_chainId "$attempt_timeout" >/dev/null 2>&1; then
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
    note "recent aggregate EL and CL evidence"
    ssh "$host" bash -s -- "$container" "$lighthouse_container" <<'REMOTE'
set -eu
container="$1"; lighthouse="$2"
el_log="$(mktemp)"; cl_log="$(mktemp)"
trap 'rm -f "$el_log" "$cl_log"' EXIT HUP INT TERM
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
docker logs --tail 2000 "$container" >"$el_log" 2>&1
docker logs --tail 1000 "$lighthouse" >"$cl_log" 2>&1
printf 'el-lines=%s\n' "$(wc -l <"$el_log" | tr -d ' ')"
for event in \
    peer.snap.target_stale \
    peer.snap.pivot_rebased \
    peer.snap.progress \
    peer.snap.page_profile \
    peer.snap.storage_profile \
    peer.snap.heal_progress \
    peer.snap.dependency_failed \
    peer.snap.dependencies_unavailable \
    peer.snap.pivot_unavailable \
    peer.snap.storage_failed \
    peer.snap.import_failed \
    peer.snap.target_completed
do
    count="$(grep -F -c "$event" "$el_log" || true)"
    printf 'el-event=%s count=%s\n' "$event" "$count"
done
storage_profile="$(grep -F 'peer.snap.storage_profile' "$el_log" | tail -1 || true)"
if [ -n "$storage_profile" ]; then
    for field in \
        pivot totalPages totalSlots totalLogicalBytes trieRecords \
        batchOperations logicalBytes completedTasks requestMs proofMs \
        materializeMs commitMs elapsedMs slotsPerSecond logicalBytesPerSecond
    do
        value="$(
            printf '%s\n' "$storage_profile" |
                sed -n "s/.*(\"$field\" \\. \"\([0-9][0-9]*\)\").*/\1/p"
        )"
        if [ -n "$value" ]; then
            printf 'el-storage-profile=%s value=%s\n' "$field" "$value"
        fi
    done
fi
# Profiler rows are deliberately schema-bounded and contain no peer or network
# identity. Never print any other raw EL/CL line from this evidence broker.
grep -E '^allocation-profile-row([[:space:]]|$)' "$el_log" || true
printf 'cl-lines=%s\n' "$(wc -l <"$cl_log" | tr -d ' ')"
printf 'cl-error-count=%s\n' "$(grep -F -i -c 'error' "$cl_log" || true)"
printf 'cl-execution-offline-count=%s\n' \
    "$(grep -F -i -c 'execution layer is not online' "$cl_log" || true)"
printf 'cl-synced-count=%s\n' "$(grep -F -c 'Synced' "$cl_log" || true)"
REMOTE
}

case "$action" in
    inspect) inspect_gate ;;
    upload) upload_artifact ;;
    load) load_image ;;
    start) start_gate ;;
    upgrade) upgrade_gate ;;
    status) remote_status ;;
    restart) restart_gate ;;
    logs) gate_logs ;;
    *)
        cat >&2 <<USAGE
Usage: scripts/hoodi-live-gate.sh ACTION

Read-only actions: inspect, status, logs
Mutating actions:  upload, load, start, upgrade, restart

Mutating actions require HOODI_GATE_ALLOW_MUTATION=1. The default artifact,
image, container, and datadir are derived from the current full Git revision.
Upgrade additionally requires HOODI_GATE_PREVIOUS_CONTAINER and
HOODI_GATE_PREVIOUS_REVISION, and reuses only that container's exact non-empty
HOODI_GATE_DATADIR. HOODI_GATE_P2P_PORT selects the bounded public P2P port.
An exact same-revision diagnostic replacement additionally requires
HOODI_GATE_ALLOW_SAME_REVISION_PROFILE=1, a new container name, and a non-zero
HOODI_GATE_ALLOC_PROFILE_SECONDS value.
HOODI_GATE_RESTART_READY_TIMEOUT may override the bounded 600-second restart
readiness window (accepted range: 30-1800 seconds).
USAGE
        exit 2
        ;;
esac
