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
# that must never reach the output.  No stub lets a container be stopped,
# started, run or loaded: the final check asserts none was reached.
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

cat > "$bin/ssh" <<'STUB'
#!/bin/sh
echo "ssh $*" >> "$STUB_LOG"
shift
exec "$@"
STUB

cat > "$bin/docker" <<'STUB'
#!/bin/sh
echo "docker $*" >> "$STUB_LOG"
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
STUB

cat > "$bin/curl" <<'STUB'
#!/bin/sh
for arg; do
    case "$arg" in
        *eth_syncing*) echo "$STUB_SYNCING"; exit 0 ;;
        *eth_blockNumber*) echo "$STUB_BLOCK"; exit 0 ;;
    esac
done
echo '{"jsonrpc":"2.0","id":1,"result":null}'
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

record() {
    checks=$((checks + 1))
    if [ "$1" = ok ]; then
        echo "ok $checks - $2"
    else
        failures=$((failures + 1))
        echo "not ok $checks - $2"
        sed 's/^/#   /' "$out"
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

echo "hoodi-live-gate selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
