#!/usr/bin/env bash
#
# Network-free self-test for the read-only evidence actions of
# scripts/hoodi-live-gate.sh (logs and complete).
#
# Copies the broker into a scratch checkout and puts stub git, ssh, docker,
# curl and date first on PATH.  The ssh stub runs the broker's remote script
# with the local bash, and the docker stub serves a fixed, timestamped EL log
# shaped like the node's real telemetry (engine.rpc.http.request with bare
# integer fields, node.store_guard.long_hold with string fields,
# engine.rpc.http.connection.error), so the host-side awk/sed runs for real.
# Every summary line is checked against a value computed by hand from the
# fixture, the not-at-head explanation has a positive control on each side of
# its 30 s threshold, and the raw-line boundary is checked with marker text
# that must never reach the output.  In that first part no stub lets a
# container be stopped, started, run or loaded, and a check asserts none was.
#
# The second part drives the mutating actions (start, upgrade, restart) and
# status against a modelled Docker daemon (STUB_MODE=lifecycle): containers
# are directories of fields, `docker run --detach` records its arguments, and
# every remote /data/ path is moved into the scratch directory.  It checks the
# persistent node key: the run line mounts the key directory at /nodekey and
# passes --nodekey (with a positive control per missing piece), a key that is
# not 0600 or not owned by uid 1000 is refused before any container starts,
# restart refuses a container created without the key, and status prints the
# node id but never the key.  It also drives stop: the missing mutation flag, a
# timeout outside 30-600 s and each ownership mismatch are refused before any
# docker stop (both timeout bounds and the clean stop are the controls), and a
# clean stop is told apart from a SIGKILLed, OOM-killed or faulted one by exit
# code, OOMKilled, the RocksDB "Shutdown complete" count and the fault lines;
# restart and upgrade stop through the same helper and grace.
#
# Run it from the tests (tests/control-plane-broker-tests.lisp) in the
# project container; it prints one line per check and exits non-zero on any
# failure or if no check ran.

set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hoodi-live-gate-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
bin="$work/bin"
mkdir -p "$repo/scripts" "$bin"
cp "$source_root/scripts/hoodi-live-gate.sh" "$repo/scripts/"
broker="$repo/scripts/hoodi-live-gate.sh"
real_date="$(command -v date)"

head_rev=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

cat > "$bin/git" <<'STUB'
#!/bin/sh
[ "$1" = -C ] && shift 2
case "$1" in
    rev-parse) echo "$STUB_HEAD" ;;
    merge-base) true ;;
    diff) case " $* " in *" --quiet "*) true ;; *) printf '' ;; esac ;;
    status) true ;;
    *) echo "git stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

# The ssh stub runs the remote script with the local bash.  With
# STUB_REMOTE_DATA set, every remote path argument under /data/ is moved below
# that scratch directory, so a mutating action's remote side can create and
# check real directories without touching /data.
cat > "$bin/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "$STUB_LOG"
shift
if [ -n "${STUB_REMOTE_DATA:-}" ]; then
    args=()
    for arg in "$@"; do args+=("${arg//\/data\//$STUB_REMOTE_DATA/}"); done
    set -- "${args[@]}"
fi
exec "$@"
STUB

# STUB_MODE=readonly (the default) serves only logs and port and refuses every
# other Docker call.  STUB_MODE=lifecycle models a small remote Docker daemon:
# one directory per container under STUB_STATE holding its labels, mounts,
# user, arguments and state, created by `docker run --detach` or by the test.
cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
if [ "${STUB_MODE:-readonly}" = readonly ]; then
    case "$1" in
        logs)
            timestamps=0
            for arg; do
                case "$arg" in --timestamps) timestamps=1 ;; esac
                name="$arg"
            done
            case "$name" in
                hoodi-lighthouse-public) printf '%s\n' "INFO Synced slot: 1" ;;
                *) if [ "$timestamps" = 1 ]; then
                       cat "$STUB_EL_LOG"
                   else
                       sed 's/^[^ ]* //' "$STUB_EL_LOG"
                   fi ;;
            esac ;;
        port) echo "127.0.0.1:18545" ;;
        *) echo "docker stub: unexpected $*" >&2; exit 99 ;;
    esac
    exit 0
fi
field() { cat "$STUB_STATE/$1/$2" 2>/dev/null || true; }
set_field() { printf '%s\n' "$3" > "$STUB_STATE/$1/$2"; }
last_arg() { for arg; do :; done; printf '%s' "$arg"; }
case "$1" in
    version) echo 26.1.4 ;;
    image)
        format="$4"
        case "$format" in
            *'.Id'*) echo "image=sha256:stub platform=linux/amd64 revision=$STUB_HEAD" ;;
            *'.Os'*) echo linux/amd64 ;;
            *) echo "$STUB_HEAD" ;;
        esac ;;
    network) true ;;
    run)
        case " $* " in *" --rm "*) exit 0 ;; esac
        shift
        name=""; user=""; agent=""; gate=""; datadir=""; nodekey=""; image_seen=0; args=""
        while [ $# -gt 0 ]; do
            if [ "$image_seen" = 1 ]; then args="$args $1"; shift; continue; fi
            case "$1" in
                --name) name="$2"; shift ;;
                --user) user="$2"; shift ;;
                --label)
                    case "$2" in
                        agent=*) agent="${2#agent=}" ;;
                        io.ethereum-lisp.gate-revision=*) gate="${2#*=}" ;;
                    esac
                    shift ;;
                --mount)
                    case "$2" in
                        *,target=/data) datadir="${2#type=bind,source=}"; datadir="${datadir%,target=/data}" ;;
                        *,target=/nodekey) nodekey="${2#type=bind,source=}"; nodekey="${nodekey%,target=/nodekey}" ;;
                    esac
                    shift ;;
                --env|--network|--network-alias|--publish|--security-opt|--memory|--memory-swap|--cap-drop|--pull) shift ;;
                ethereum-lisp-runtime:*) image_seen=1 ;;
            esac
            shift
        done
        mkdir -p "$STUB_STATE/$name"
        set_field "$name" agent "$agent"; set_field "$name" gate "$gate"
        set_field "$name" image-revision "$STUB_HEAD"; set_field "$name" datadir "$datadir"
        set_field "$name" nodekey "$nodekey"; set_field "$name" user "$user"
        set_field "$name" args "${args# }"; set_field "$name" running true
        set_field "$name" exit 0; set_field "$name" oom false
        set_field "$name" memory "${STUB_MEMORY:-7516192768}" ;;
    container)
        name="$(last_arg "$@")"
        if [ ! -d "$STUB_STATE/$name" ]; then
            [ "$3" = --format ] && echo
            echo "Error: No such container: $name" >&2
            exit 1
        fi
        [ "$3" = --format ] || exit 0
        format="$4"
        case "$format" in
            'container={{.Name}}'*) echo "container=/$name running=$(field "$name" running) stub-summary" ;;
            '{{.State.Running}} {{.State.ExitCode}} {{.State.OOMKilled}}')
                echo "$(field "$name" running) $(field "$name" exit) $(field "$name" oom)" ;;
            *'"agent"'*) field "$name" agent ;;
            *'io.ethereum-lisp.gate-revision'*) field "$name" gate ;;
            *'org.opencontainers.image.revision'*) field "$name" image-revision ;;
            *'.Destination "/data"'*) field "$name" datadir ;;
            *'.Destination "/nodekey"'*) field "$name" nodekey ;;
            *'.Config.User'*) field "$name" user ;;
            *'ReadonlyRootfs'*) echo true ;;
            *'MemorySwap'*|*'.HostConfig.Memory'*) field "$name" memory ;;
            *'.State.StartedAt'*|*'.State.FinishedAt'*) echo 2026-09-29T00:00:00Z ;;
            *'.State.ExitCode'*) field "$name" exit ;;
            *'.State.OOMKilled'*) field "$name" oom ;;
            *'.State.Running'*) field "$name" running ;;
            *'.Args'*) printf '%s \n' "$(field "$name" args)" ;;
            *) echo "docker stub: unexpected format $format" >&2; exit 99 ;;
        esac ;;
    start)
        [ -d "$STUB_STATE/$2" ] || exit 1
        set_field "$2" running true ;;
    stop)
        # STUB_STOP_OUTCOME: clean (the default: exit 0 and RocksDB's
        # "Shutdown complete" in the datadir's LOG), killed (SIGKILL after the
        # grace: 137, no line), oom (137 and OOMKilled), fault (clean, but
        # SBCL's memory-fault lines in the log).
        name="$(last_arg "$@")"
        [ -d "$STUB_STATE/$name" ] || exit 1
        [ "$(field "$name" running)" = true ] || exit 0
        set_field "$name" running false
        log="$(field "$name" datadir)/chaindata/LOG"
        case "${STUB_STOP_OUTCOME:-clean}" in
            clean|fault)
                set_field "$name" exit 0
                [ ! -d "${log%/LOG}" ] || echo "[db/db_impl.cc:500] Shutdown complete" >> "$log" ;;
            killed) set_field "$name" exit 137 ;;
            oom) set_field "$name" exit 137; set_field "$name" oom true ;;
        esac
        if [ "${STUB_STOP_OUTCOME:-clean}" = fault ]; then
            echo "CORRUPTION WARNING in SBCL pid 7 tid 8: Memory fault at 0x10 (pc=0x20)" >> "$STUB_STATE/$name/log"
        fi ;;
    logs) name="$(last_arg "$@")"; cat "$STUB_STATE/$name/log" 2>/dev/null || true ;;
    port) echo "127.0.0.1:18545" ;;
    stats) echo "runtime=cpu=1.00% memory=1GiB / 7GiB blockIo=0B / 0B pids=10" ;;
    *) echo "docker stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

node_id=1111111111111111111111111111111111111111111111111111111111111111
node_pubkey="${node_id//1/2}${node_id//1/2}"
cat > "$bin/curl" <<STUB
#!/bin/sh
for arg; do
    case "\$arg" in
        *eth_syncing*) echo "\$STUB_SYNCING"; exit 0 ;;
        *eth_blockNumber*) echo "\$STUB_BLOCK"; exit 0 ;;
        *eth_chainId*) echo '{"jsonrpc":"2.0","id":1,"result":"0x88bb0"}'; exit 0 ;;
        *admin_nodeInfo*)
            echo '{"jsonrpc":"2.0","id":1,"result":{"id":"$node_id","name":"ethereum-lisp","enode":"enode://$node_pubkey@165.154.224.110:30303","ip":"165.154.224.110"}}'
            exit 0 ;;
    esac
done
echo '{"jsonrpc":"2.0","id":1,"result":null}'
STUB

# The remote user, and the owner that stat reports.  The test container cannot
# chown, so the stat stub keeps the real mode and type but reports the owner
# the test asks for (STUB_DIR_OWNER, STUB_KEY_OWNER for nodekey.hex).
cat > "$bin/id" <<'STUB'
#!/bin/sh
case "$1" in
    -u) echo "${STUB_UID:-1000}" ;;
    -g) echo "${STUB_GID:-1000}" ;;
    *) echo "id stub: unexpected $*" >&2; exit 99 ;;
esac
STUB
real_stat="$(command -v stat)"
cat > "$bin/stat" <<STUB
#!/bin/sh
[ "\$1" = -c ] || { echo "stat stub: unexpected \$*" >&2; exit 99; }
mode="\$("$real_stat" -c %a "\$3")" || exit 1
case "\$3" in
    */nodekey.hex) owner="\${STUB_KEY_OWNER:-1000:1000}" ;;
    *) owner="\${STUB_DIR_OWNER:-1000:1000}" ;;
esac
case "\$2" in
    %u:%g:%a) echo "\$owner:\$mode" ;;
    %u:%a) echo "\${owner%%:*}:\$mode" ;;
    *) echo "stat stub: unexpected format \$2" >&2; exit 99 ;;
esac
STUB
cat > "$bin/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB

cat > "$bin/date" <<STUB
#!/bin/sh
if [ "\$*" = "-u +%s" ] && [ -n "\${STUB_NOW:-}" ]; then
    echo "\$STUB_NOW"
    exit 0
fi
exec "$real_date" "\$@"
STUB
chmod +x "$bin"/*

# --- the fixture log ------------------------------------------------------------
# Timestamps are Docker's RFC 3339 receive stamps; one line per second.
el_log="$work/el.log"
ts() { printf '2026-09-24T01:00:%02d.123456789Z' "$1"; }
req() {  # SECOND METHOD FIELDS...
    local second="$1" method="$2"
    shift 2
    printf '%s (:KIND :LOG :NAME "engine.rpc.http.request" :VALUE :INFO :FIELDS (("endpoint" . "0.0.0.0:8551") ("host" . "0.0.0.0") ("port" . 8551) ("httpMethod" . "POST") ("httpTarget" . "/") ("rpcMethods" . "%s") ("status" . "200") ("readMs" . 0)%s))\n' \
        "$(ts "$second")" "$method" "$*"
}
hold() {  # SECOND HOLDER MS
    printf '%s (:KIND :LOG :NAME "node.store_guard.long_hold" :VALUE :INFO :FIELDS (("holder" . "%s") ("holdMs" . "%s") ("releaseHookMs" . "0") ("engineWaiting" . "true")))\n' \
        "$(ts "$1")" "$2" "$3"
}
conn_error() {  # SECOND PORT TEXT
    printf '%s (:KIND :LOG :NAME "engine.rpc.http.connection.error" :VALUE :WARN :FIELDS (("endpoint" . "127.0.0.1:%s") ("host" . "0.0.0.0") ("port" . %s) ("error" . "%s")))\n' \
        "$(ts "$1")" "$2" "$2" "$3"
}
{
    printf '%s (:KIND :LOG :NAME "peer.snap.target_completed" :VALUE :INFO :FIELDS (("target" . "3680556")))\n' "$(ts 0)"
    printf '%s (:KIND :LOG :NAME "peer.snap.heal_progress" :VALUE :INFO :FIELDS (("pivot" . "3680492") ("frontierWorks" . "0") ("completed" . "T")))\n' "$(ts 0)"
    req 1 engine_newPayloadV4 ' ("handlerMs" . 25269) ("handlerGcMs" . 320) ("handlerCpuMs" . 5837) ("heapMb" . 395) ("guardWaitMs" . 19425) ("guardWaitedFor" . "leakmarker-guardwaited:36877") ("npExecuteMs" . 5832) ("npExecuteGcMs" . 26) ("npExecuteCpuMs" . 5821) ("npTrieNodeReads" . 20) ("rpcPayloadStatus" . "VALID")'
    req 2 engine_newPayloadV4 ' ("handlerMs" . 100) ("guardWaitMs" . 10) ("npExecuteMs" . 50) ("npExecuteGcMs" . 5) ("npExecuteCpuMs" . 40) ("rpcPayloadStatus" . "VALID")'
    hold 3 engine_newPayloadV4 5996
    req 4 engine_forkchoiceUpdatedV3 ' ("handlerMs" . 580) ("guardWaitMs" . 580) ("guardWaitedFor" . "leakmarker-guardwaited:0")'
    hold 5 ethereum-lisp-devnet-dial-session 110731
    req 10 engine_newPayloadV4 ' ("handlerMs" . 4) ("rpcPayloadStatus" . "SYNCING")'
    hold 20 engine_newPayloadV4 5844
    for second in 21 22 23 24 25 26 27 28 29 30; do
        req "$second" eth_syncing " (\"handlerMs\" . $(( second - 20 )))"
    done
    conn_error 31 8551 'HTTP request exceeded the 30 second deadline'
    conn_error 32 8551 'HTTP request exceeded the 30 second deadline'
    conn_error 33 8545 'HTTP connection exceeded the 30 second idle deadline'
    conn_error 34 8551 'leakmarker-error from 192.0.2.7 reset by peer'
    printf '%s allocation-profile-row rank=1 bytes=4096\n' "$(ts 35)"
} > "$el_log"
epoch_of_second() { "$real_date" -u -d "2026-09-24T01:00:$(printf '%02d' "$1")Z" +%s; }

export PATH="$bin:$PATH"
export STUB_LOG="$work/stub.log" STUB_EL_LOG="$el_log" STUB_HEAD="$head_rev"
: > "$STUB_LOG"

checks=0
failures=0
out="$work/out"

# record ok|fail DESCRIPTION [DETAIL-FILE]: a failure prints DETAIL-FILE
# (default: the last run's output).
record() {
    checks=$((checks + 1))
    if [ "$1" = ok ]; then
        echo "ok $checks - $2"
    else
        failures=$((failures + 1))
        echo "not ok $checks - $2"
        sed 's/^/#   /' "${3:-$out}"
    fi
}

# run STATUS DESCRIPTION -- COMMAND...: the command must exit with STATUS.
run() {
    local want="$1" description="$2" status=0
    shift 3
    "$@" > "$out" 2>&1 || status=$?
    if [ "$status" = "$want" ]; then
        record ok "$description exits $want"
    else
        echo "exit $status, wanted $want" >> "$out"
        record fail "$description exits $want"
    fi
}

# has LINE: the last run printed exactly this line.
has() {
    if grep -qxF -- "$1" "$out"; then
        record ok "prints: $1"
    else
        echo "missing line: $1" >> "$out"
        record fail "prints: $1"
    fi
}

lacks() {
    if grep -qF -- "$1" "$out"; then
        echo "unexpected text: $1" >> "$out"
        record fail "never prints: $1"
    else
        record ok "never prints: $1"
    fi
}

# --- logs: the Engine and store-guard summary -----------------------------------
run 0 "logs" -- "$broker" logs
logs_out="$work/logs.out"
cp "$out" "$logs_out"
has "el-engine-requests method=engine_newPayloadV4 count=3"
has "el-engine-requests method=engine_forkchoiceUpdatedV3 count=1"
has "el-engine-requests method=eth_syncing count=10"
has "el-engine-requests-total count=14"
has "el-engine-latency series=handlerMs method=engine_newPayloadV4 samples=3 min=4 p50=100 p90=25269 max=25269"
has "el-engine-latency series=npExecuteMs method=engine_newPayloadV4 samples=2 min=50 p50=50 p90=5832 max=5832"
has "el-engine-latency series=handlerMs method=engine_forkchoiceUpdatedV3 samples=1 min=580 p50=580 p90=580 max=580"
# Ten samples 1..10: nearest rank puts p50 at the 5th and p90 at the 9th.
has "el-engine-latency series=handlerMs method=eth_syncing samples=10 min=1 p50=5 p90=9 max=10"
has "el-engine-np-cpu-gc samples=2 npExecuteCpuMs-sum=5861 npExecuteGcMs-sum=31"
has "el-engine-guard-wait samples=3 maxMs=19425"
has "el-engine-last-new-payload timestamp=$(ts 10) method=engine_newPayloadV4 status=SYNCING"
has "el-guard-long-hold holder=engine_newPayloadV4 count=2 maxMs=5996"
has "el-guard-long-hold holder=ethereum-lisp-devnet-dial-session count=1 maxMs=110731"
has "el-guard-long-hold-total count=3 maxMs=110731"
has "el-guard-long-hold-last timestamp=$(ts 20) holder=engine_newPayloadV4 holdMs=5844"
has "el-connection-error port=8551 class=request-deadline-30s count=2"
has "el-connection-error port=8545 class=idle-deadline-30s count=1"
has "el-connection-error port=8551 class=other count=1"
has "el-connection-error-total count=4"
# The existing aggregate still reads the node's lines once Docker's stamps are
# stripped: the anchored profiler-row pass-through is the control for that.
has "allocation-profile-row rank=1 bytes=4096"
has "el-event=peer.snap.target_completed count=1"
has "el-heal-progress=completed value=true"
lacks "leakmarker"
lacks "(:KIND"
lacks "192.0.2.7"

# The output is stable: a second run over the same log prints the same lines.
run 0 "logs again" -- "$broker" logs
grep -v '^timestamp=' "$logs_out" > "$work/logs.a"
grep -v '^timestamp=' "$out" > "$work/logs.b"
if cmp -s "$work/logs.a" "$work/logs.b"; then
    record ok "logs output is identical across runs"
else
    diff "$work/logs.a" "$work/logs.b" > "$out" || true
    record fail "logs output is identical across runs"
fi

# An empty window still prints every total, with zeros and none-in-window.
saved_log="$el_log.full"
cp "$el_log" "$saved_log"
: > "$el_log"
run 0 "logs over an empty window" -- "$broker" logs
has "el-engine-requests-total count=0"
has "el-guard-long-hold-total count=0 maxMs=0"
has "el-engine-last-new-payload timestamp=none-in-window"
has "el-connection-error-total count=0"
cp "$saved_log" "$el_log"

# --- complete: why the node is not at the head ----------------------------------
export STUB_SYNCING='{"jsonrpc":"2.0","id":1,"result":{"startingBlock":"0x10","currentBlock":"0x10","highestBlock":"0x5c"}}'
export STUB_BLOCK='{"jsonrpc":"2.0","id":1,"result":"0x10"}'
export STUB_NOW="$(( $(epoch_of_second 20) + 100 ))"
run 1 "complete while syncing" -- "$broker" complete
has "completion-eth-syncing=not-false"
has "completion-why=syncing current=16 highest=92 gap=76 last-new-payload=$(ts 10) age=110s np-status=SYNCING guard=no-release-logged-since:$(ts 20) guard-release-age=100s last-long-hold=engine_newPayloadV4:5844ms@$(ts 20)"
lacks "leakmarker"

# Control on the other side of the 30 s threshold: a recent release.
export STUB_NOW="$(( $(epoch_of_second 20) + 10 ))"
run 1 "complete while syncing after a recent release" -- "$broker" complete
has "completion-why=syncing current=16 highest=92 gap=76 last-new-payload=$(ts 10) age=20s np-status=SYNCING guard=released:$(ts 20) guard-release-age=10s last-long-hold=engine_newPayloadV4:5844ms@$(ts 20)"

# Control: at the head, complete passes and gives no explanation.
export STUB_SYNCING='{"jsonrpc":"2.0","id":1,"result":false}'
export STUB_BLOCK='{"jsonrpc":"2.0","id":1,"result":"0x400000"}'
run 0 "complete at the head" -- "$broker" complete
has "completion-eth-syncing=false"
has "completion-canonical-block=4194304"
lacks "completion-why"

# A runtime fault still fails completion first, timestamps and all.
printf '%s CORRUPTION WARNING in SBCL pid 7: Memory fault at 0x10\n' "$(ts 36)" >> "$el_log"
run 1 "complete with a runtime fault" -- "$broker" complete
has "completion-runtime-fault=1"
cp "$saved_log" "$el_log"

# --- mutating actions stay behind the flag --------------------------------------
ssh_before="$(grep -c '^ssh ' "$STUB_LOG" || true)"
run 1 "restart without the mutation flag" -- "$broker" restart
has "FAIL: restart changes remote state; set HOODI_GATE_ALLOW_MUTATION=1 only after explicit authorization"
if [ "$(grep -c '^ssh ' "$STUB_LOG" || true)" = "$ssh_before" ]; then
    record ok "restart refusal made no remote contact"
else
    cp "$STUB_LOG" "$out"; record fail "restart refusal made no remote contact"
fi

: > "$out"
if grep -qE '^docker (run|start|stop|restart|rm|container rm|image load|network)' "$STUB_LOG"; then
    cp "$STUB_LOG" "$out"; record fail "no remote mutation was reached"
else
    record ok "no remote mutation was reached"
fi

# ================================================================================
# Lifecycle actions against the modelled daemon.  Nothing here reaches a real
# Docker daemon or /data: docker is the lifecycle stub and every remote /data/
# path lives under $remote_data.
# ================================================================================
export STUB_MODE=lifecycle STUB_STATE="$work/state" HOODI_GATE_ALLOW_MUTATION=1
remote_data="$work/remote-data"
export STUB_REMOTE_DATA="$remote_data"
root="$remote_data/hoodi-sec5-20260814"
nk="$root/nodekey"
key="$nk/nodekey.hex"
new_container=hoodi-el-sec5-aaaaaaaa
prev_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
prev_container=hoodi-el-sec5-bbbbbbbb
prev_datadir="$root/datadir-bbbbbbbb"
mkdir -p "$root" "$remote_data/hoodi/jwt" "$STUB_STATE"
cp "$source_root/tools/runtime/docker-26.1.4-io-uring-seccomp.json" "$root/"
echo 00 > "$remote_data/hoodi/jwt/jwt.hex"
key_marker=leakmarker-secret-node-key

lifecycle_log="$work/lifecycle.log"
: > "$lifecycle_log"
reset_world() {
    cat "$STUB_LOG" >> "$lifecycle_log"
    rm -rf "$STUB_STATE" "$root/datadir-aaaaaaaa"
    mkdir -p "$STUB_STATE/hoodi-lighthouse-public"
    echo true > "$STUB_STATE/hoodi-lighthouse-public/running"
    unset STUB_UID STUB_KEY_OWNER STUB_DIR_OWNER HOODI_GATE_PREVIOUS_CONTAINER \
        HOODI_GATE_PREVIOUS_REVISION HOODI_GATE_DATADIR STUB_STOP_OUTCOME \
        HOODI_GATE_STOP_TIMEOUT
    : > "$STUB_LOG"
}

# plant_key MODE: an existing node key whose content must never be printed.
plant_key() {
    mkdir -p "$nk"; chmod 0700 "$nk"
    rm -f "$key"; echo "$key_marker" > "$key"; chmod "$1" "$key"
}

# plant_container NAME REVISION DATADIR NODEKEY-SOURCE ARGS: a gate container
# created earlier, running.
plant_container() {
    local dir="$STUB_STATE/$1"
    mkdir -p "$dir" "$3"
    echo codex-sec5-live-gate > "$dir/agent"
    echo "$2" > "$dir/gate"; echo "$2" > "$dir/image-revision"
    echo "$3" > "$dir/datadir"; echo "$4" > "$dir/nodekey"; echo "$5" > "$dir/args"
    echo 1000:1000 > "$dir/user"; echo 7516192768 > "$dir/memory"
    echo true > "$dir/running"; echo 0 > "$dir/exit"; echo false > "$dir/oom"
    touch "$3/CURRENT"
    # A running node's RocksDB LOG: started at open, no "Shutdown complete".
    mkdir -p "$3/chaindata"
    echo "[db/db_impl_open.cc:2100] DB pointer 0x1" > "$3/chaindata/LOG"
}

# run_line_has_nodekey: the last `docker run --detach` carries the node key
# mount and flag.  Returns non-zero, without recording, when it does not.
run_line_has_nodekey() {
    local line
    line="$(grep '^docker run --detach' "$STUB_LOG" | tail -1)"
    case "$line " in *" --mount type=bind,source=$nk,target=/nodekey "*) ;; *) return 1 ;; esac
    case "$line " in *" --nodekey /nodekey/nodekey.hex "*) ;; *) return 1 ;; esac
}
# These read the stub log and leave the last run's output for later checks.
check_run_line() {
    if run_line_has_nodekey; then
        record ok "$1: docker run mounts $nk at /nodekey and passes --nodekey"
    else
        grep '^docker run --detach' "$STUB_LOG" > "$work/detail" ||
            echo "no docker run --detach" > "$work/detail"
        record fail "$1: docker run mounts $nk at /nodekey and passes --nodekey" "$work/detail"
    fi
}
no_detached_run() {
    if grep -q '^docker run --detach' "$STUB_LOG"; then
        record fail "$1: no container was started" "$STUB_LOG"
    else
        record ok "$1: no container was started"
    fi
}
no_lifecycle_call() {
    if grep -qE '^docker (run --detach|start|stop)' "$STUB_LOG"; then
        record fail "$1: no container was started or stopped" "$STUB_LOG"
    else
        record ok "$1: no container was started or stopped"
    fi
}

# --- start: the node key directory is created and mounted ------------------------
reset_world
rm -rf "$nk"
run 0 "start with no node key directory" -- "$broker" start
has "nodekey-dir=$nk created"
has "nodekey-file=absent (the node creates it on its first start)"
check_run_line "start"
nk_mode="$("$real_stat" -c %a "$nk" 2>&1 || true)"
if [ "$nk_mode" = 700 ]; then
    record ok "start creates the node key directory with mode 0700"
else
    echo "$nk_mode" > "$out"; record fail "start creates the node key directory with mode 0700"
fi

# Positive controls: the run-line check fails on a broker that drops either the
# mount or the flag, so the check above cannot pass vacuously.
sed '/,target=\/nodekey" \\$/d' "$broker" > "$repo/scripts/hoodi-live-gate-nomount.sh"
sed '/^    --nodekey \/nodekey\/nodekey.hex \\$/d' "$broker" > "$repo/scripts/hoodi-live-gate-noflag.sh"
chmod +x "$repo/scripts/hoodi-live-gate-nomount.sh" "$repo/scripts/hoodi-live-gate-noflag.sh"
for variant in nomount noflag; do
    reset_world
    run 0 "start with a broker whose run line lacks the node key ($variant)" -- \
        "$repo/scripts/hoodi-live-gate-$variant.sh" start
    : > "$out"
    if run_line_has_nodekey; then
        grep '^docker run --detach' "$STUB_LOG" > "$out"
        record fail "control: the run-line check fails without the node key ($variant)"
    else
        record ok "control: the run-line check fails without the node key ($variant)"
    fi
done

# An existing key is accepted and never printed.
reset_world
plant_key 0600
run 0 "start with an existing 0600 key" -- "$broker" start
has "nodekey-file=present uid=1000 mode=600"
check_run_line "start with an existing key"
lacks "$key_marker"

# --- start: refusals, each against the accepted case above -----------------------
reset_world
plant_key 0644
run 1 "start with a 0644 key" -- "$broker" start
has "node key must be owned by uid 1000 with mode 0600: $key is 1000:644"
no_detached_run "0644 key"

reset_world
plant_key 0600
export STUB_KEY_OWNER=1001:1000
run 1 "start with a key owned by uid 1001" -- "$broker" start
has "node key must be owned by uid 1000 with mode 0600: $key is 1001:600"
no_detached_run "foreign key owner"

reset_world
plant_key 0600
chmod 0755 "$nk"
run 1 "start with a 0755 key directory" -- "$broker" start
has "node key directory must be owned by 1000:1000 with mode 0700: $nk is 1000:1000:755"
no_detached_run "0755 key directory"
chmod 0700 "$nk"

reset_world
plant_key 0600
mv "$key" "$nk/elsewhere"
ln -s "$nk/elsewhere" "$key"
run 1 "start with a symbolic-link key" -- "$broker" start
has "node key is a symbolic link: $key"
no_detached_run "symbolic-link key"
rm -f "$key" "$nk/elsewhere"

reset_world
plant_key 0600
export STUB_UID=1001
run 1 "start as uid 1001" -- "$broker" start
has "the node must run as 1000:1000, the owner of its node key; got: 1001:1000"
no_detached_run "foreign node user"

run 1 "a node key directory outside /data/hoodi-sec5-*" -- \
    env HOODI_GATE_NODEKEY_DIR=/data/hoodi/nodekey "$broker" start
has "FAIL: node key directory must stay below /data/hoodi-sec5-*"
run 1 "a node key directory inside the datadir" -- \
    env HOODI_GATE_NODEKEY_DIR=/data/hoodi-sec5-20260814/datadir-aaaaaaaa/nodekey "$broker" start
has "FAIL: node key directory must not be inside the datadir"

# --- upgrade: the replacement takes the persistent key ---------------------------
reset_world
plant_key 0600
plant_container "$prev_container" "$prev_rev" "$prev_datadir" "" "--hoodi --datadir /data"
export HOODI_GATE_PREVIOUS_CONTAINER="$prev_container" HOODI_GATE_PREVIOUS_REVISION="$prev_rev" \
    HOODI_GATE_DATADIR=/data/hoodi-sec5-20260814/datadir-bbbbbbbb
run 0 "upgrade from a container without the node key" -- "$broker" upgrade
has "nodekey-file=present uid=1000 mode=600"
check_run_line "upgrade"
lacks "$key_marker"

reset_world
plant_key 0600
plant_container "$prev_container" "$prev_rev" "$prev_datadir" "" "--hoodi --datadir /data"
echo 1001:1001 > "$STUB_STATE/$prev_container/user"
export HOODI_GATE_PREVIOUS_CONTAINER="$prev_container" HOODI_GATE_PREVIOUS_REVISION="$prev_rev" \
    HOODI_GATE_DATADIR=/data/hoodi-sec5-20260814/datadir-bbbbbbbb
run 1 "upgrade of a container running as 1001:1001" -- "$broker" upgrade
has "the node must run as 1000:1000, the owner of its node key; got: 1001:1001"
no_lifecycle_call "upgrade from a foreign user"

# --- restart: only a container created with the key -------------------------------
with_key_args="--hoodi --datadir /data --nodekey /nodekey/nodekey.hex --port 30303"
reset_world
plant_key 0600
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "$nk" "$with_key_args"
run 0 "restart a container created with the node key" -- "$broker" restart
has "nodekey-file=present uid=1000 mode=600"
lacks "$key_marker"

reset_world
plant_key 0600
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "" "--hoodi --datadir /data"
run 1 "restart a container without the node key mount" -- "$broker" restart
has "container $new_container does not mount the node key directory $nk at /nodekey: none"
no_lifecycle_call "restart without the mount"

reset_world
plant_key 0600
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "$nk" "--hoodi --datadir /data"
run 1 "restart a container without --nodekey" -- "$broker" restart
has "container $new_container does not pass --nodekey /nodekey/nodekey.hex"
no_lifecycle_call "restart without the flag"

reset_world
plant_key 0640
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "$nk" "$with_key_args"
run 1 "restart with a 0640 key" -- "$broker" restart
has "node key must be owned by uid 1000 with mode 0600: $key is 1000:640"
no_lifecycle_call "restart with a 0640 key"

# --- status: the identity, never the key ---------------------------------------------
reset_world
plant_key 0600
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "$nk" "$with_key_args"
run 0 "status of a container with the node key" -- "$broker" status
has "nodekey-mount=$nk"
has "nodekey-file=present uid=1000 mode=600"
has "node-id=$node_id"
has "node-pubkey=$node_pubkey"
lacks "$key_marker"

chmod 0644 "$key"
run 1 "status with a 0644 key" -- "$broker" status
has "node key must be owned by uid 1000 with mode 0600: $key is 1000:644"

reset_world
plant_container "$new_container" "$head_rev" "$root/datadir-aaaaaaaa" "" "--hoodi --datadir /data"
run 0 "status of a container without the node key" -- "$broker" status
has "nodekey-mount=absent (identity is datadir-local and changes with the datadir)"
has "node-id=$node_id"

# --- stop: SIGTERM with a bounded grace, then a clean/unclean verdict ----------------
# logged TEXT: the stub log of the last world holds a line with TEXT.
logged() {
    if grep -qF -- "$1" "$STUB_LOG"; then
        record ok "calls: $1"
    else
        record fail "calls: $1" "$STUB_LOG"
    fi
}
no_stop_call() {
    if grep -q '^docker stop' "$STUB_LOG"; then
        record fail "$1: no container was stopped" "$STUB_LOG"
    else
        record ok "$1: no container was stopped"
    fi
}
datadir_a="$root/datadir-aaaaaaaa"
plant_gate() {  # the running gate container stop acts on
    plant_container "$new_container" "$head_rev" "$datadir_a" "$nk" "$with_key_args"
}

# Refusals that never reach the host.
reset_world
plant_key 0600
plant_gate
run 1 "stop without the mutation flag" -- env -u HOODI_GATE_ALLOW_MUTATION "$broker" stop
has "FAIL: stop changes remote state; set HOODI_GATE_ALLOW_MUTATION=1 only after explicit authorization"
for bad in 29 601 12s; do
    run 1 "stop with HOODI_GATE_STOP_TIMEOUT='$bad'" -- env HOODI_GATE_STOP_TIMEOUT="$bad" "$broker" stop
    case "$bad" in
        29|601) has "FAIL: stop timeout must be between 30 and 600 seconds" ;;
        *) has "FAIL: stop timeout must be an integer number of seconds" ;;
    esac
done
: > "$out"
if grep -q '^ssh ' "$STUB_LOG"; then
    cp "$STUB_LOG" "$out"; record fail "refused stops made no remote contact"
else
    record ok "refused stops made no remote contact"
fi
# Positive controls for the timeout bounds: both ends are accepted and used.
for good in 30 600; do
    reset_world
    plant_key 0600
    plant_gate
    run 0 "stop with HOODI_GATE_STOP_TIMEOUT=$good" -- env HOODI_GATE_STOP_TIMEOUT="$good" "$broker" stop
    logged "docker stop --time $good $new_container"
done

# Ownership: each mismatch is refused before any stop; the clean case below is
# the control.
for mismatch in agent gate image datadir user; do
    reset_world
    plant_key 0600
    plant_gate
    case "$mismatch" in
        agent) echo codex-ethereum-lisp-same-host-benchmark > "$STUB_STATE/$new_container/agent"
               message="gate ownership mismatch: agent=codex-ethereum-lisp-same-host-benchmark" ;;
        gate) echo "$prev_rev" > "$STUB_STATE/$new_container/gate"
              message="gate ownership mismatch: $prev_rev" ;;
        image) echo "$prev_rev" > "$STUB_STATE/$new_container/image-revision"
               message="gate image revision mismatch: $prev_rev" ;;
        datadir) echo "$prev_datadir" > "$STUB_STATE/$new_container/datadir"
                 message="gate datadir mismatch: $prev_datadir" ;;
        user) echo 0:0 > "$STUB_STATE/$new_container/user"
              message="gate does not have an explicit non-root user: $new_container" ;;
    esac
    run 1 "stop with a $mismatch mismatch" -- "$broker" stop
    has "$message"
    no_stop_call "$mismatch mismatch"
done

reset_world
plant_key 0600
plant_gate
echo false > "$STUB_STATE/$new_container/running"
run 1 "stop of a container that is not running" -- "$broker" stop
has "gate container is not running: $new_container"
no_stop_call "not running"

# The verdicts.
reset_world
plant_key 0600
plant_gate
run 0 "a clean stop" -- "$broker" stop
logged "docker stop --time 120 $new_container"
has "stop-exit=0 oom-killed=false running=false"
has "stop-shutdown-complete=0->1"
has "stop-runtime-faults=0"
has "stop-clean=true"
: > "$out"
if [ -d "$STUB_STATE/$new_container" ] && [ -f "$datadir_a/CURRENT" ]; then
    record ok "a clean stop keeps the container and the datadir"
else
    record fail "a clean stop keeps the container and the datadir"
fi

for outcome in killed oom fault; do
    reset_world
    plant_key 0600
    plant_gate
    export STUB_STOP_OUTCOME="$outcome"
    run 1 "an unclean stop ($outcome)" -- "$broker" stop
    case "$outcome" in
        killed)
            has "stop-exit=137 oom-killed=false running=false"
            has "stop-shutdown-complete=0->0"
            has "stop-clean=false reason=exit-137,shutdown-complete-0-to-0" ;;
        oom)
            has "stop-exit=137 oom-killed=true running=false"
            has "stop-clean=false reason=exit-137,oom-killed,shutdown-complete-0-to-0" ;;
        fault)
            has "stop-shutdown-complete=0->1"
            has "stop-runtime-faults=1"
            has "stop-clean=false reason=runtime-faults-1" ;;
    esac
done

# restart and upgrade stop through the same helper and grace.
reset_world
plant_key 0600
plant_gate
run 0 "restart with HOODI_GATE_STOP_TIMEOUT=200" -- env HOODI_GATE_STOP_TIMEOUT=200 "$broker" restart
logged "docker stop --time 200 $new_container"
has "stop-shutdown-complete=0->1"
has "stop-clean=true"

reset_world
plant_key 0600
plant_gate
export STUB_STOP_OUTCOME=killed
run 1 "restart after an unclean stop" -- "$broker" restart
has "stop-clean=false reason=exit-137,shutdown-complete-0-to-0"
has "restarted, but the stop before it was not clean (see stop-clean above)"
logged "docker start $new_container"

reset_world
plant_key 0600
plant_container "$prev_container" "$prev_rev" "$prev_datadir" "" "--hoodi --datadir /data"
export HOODI_GATE_PREVIOUS_CONTAINER="$prev_container" HOODI_GATE_PREVIOUS_REVISION="$prev_rev" \
    HOODI_GATE_DATADIR=/data/hoodi-sec5-20260814/datadir-bbbbbbbb
run 0 "upgrade stops the previous container through the helper" -- "$broker" upgrade
logged "docker stop --time 120 $prev_container"
has "previous-stop-clean=true"

cat "$STUB_LOG" >> "$lifecycle_log"
: > "$out"
if grep -qE '^docker (rm|container rm|image rm|volume|system)' "$lifecycle_log"; then
    grep -E '^docker (rm|container rm|image rm|volume|system)' "$lifecycle_log" > "$out"
    record fail "no lifecycle action removes anything"
else
    record ok "no lifecycle action removes anything"
fi

echo "hoodi-live-gate selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
