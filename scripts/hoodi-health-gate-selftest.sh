#!/usr/bin/env bash
#
# Network-free self-test for scripts/hoodi-health-probe.sh and the read-only
# scripts/hoodi-health-gate.sh.
#
# Copies the probe, the gate and the log redaction filter into a scratch
# checkout and puts stub git, ssh, docker, curl, du, df, date and crontab
# first on PATH.  The docker stub models the EL and Lighthouse containers (one
# directory of fields each) and answers only inspect, port and stats; curl
# answers the EL's JSON-RPC and Lighthouse's API from STUB_* values; the ssh
# stub runs the gate's remote script with the local bash, moving every remote
# /data/ path below the scratch directory; crontab answers -l only.
#
# The probe half drives every alert rule with a fixture value on each side of
# its threshold (a control that must not alert), the restart-count baseline,
# log rotation, the rewrite of latest.txt, the knob refusals, and the absence
# of peer identities (scripts/hoodi-log-redact.sh leaves every record
# unchanged).  The gate half pairs each refusal with an accepted case and
# checks status and report against planted records, and that neither action
# writes anything on the remote side.  No stub starts, stops or removes a
# container, and the last checks assert nothing asked to.
#
# Run it from the tests (tests/control-plane-broker-tests.lisp) in the project
# container; it prints one line per check and exits non-zero on any failure or
# if no check ran.

set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hoodi-health-gate-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
bin="$work/bin"
mkdir -p "$repo/scripts" "$bin"
cp "$source_root/scripts/hoodi-health-gate.sh" "$source_root/scripts/hoodi-health-probe.sh" \
    "$source_root/scripts/hoodi-log-redact.sh" "$repo/scripts/"
gate="$repo/scripts/hoodi-health-gate.sh"
probe_copy="$repo/scripts/hoodi-health-probe.sh"

head_rev=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
old_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
side_rev=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
el=hoodi-el-sec5-aaaaaaaa
cl=hoodi-lighthouse-public
real_date="$(command -v date)"

# STUB_HISTORY models one line of commits, oldest first; a revision outside
# it is not an ancestor of anything.
cat > "$bin/git" <<'STUB'
#!/bin/sh
[ "$1" = -C ] && shift 2
pos() {
    i=0
    for r in ${STUB_HISTORY:-}; do
        i=$((i + 1))
        [ "$r" = "$1" ] && { echo "$i"; return; }
    done
    echo 0
}
case "$1" in
    rev-parse) echo "$STUB_HEAD" ;;
    merge-base)
        a="$(pos "$3")"; b="$(pos "$4")"
        [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -le "$b" ] ;;
    *) echo "git stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

cat > "$bin/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "$STUB_LOG"
shift
args=()
for arg in "$@"; do args+=("${arg//\/data\//$STUB_REMOTE_DATA/}"); done
exec "${args[@]}"
STUB

# One directory per container under STUB_STATE: running, status, restarts,
# oom, exit, started, memlimit, datadir.  A missing container behaves as
# Docker's does: an empty line on stdout and exit 1.
cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
field() { cat "$STUB_STATE/$1/$2" 2>/dev/null || true; }
last_arg() { for arg; do :; done; printf '%s' "$arg"; }
case "$1" in
    container)
        name="$(last_arg "$@")"
        [ -d "$STUB_STATE/$name" ] || { echo; echo "Error: No such container: $name" >&2; exit 1; }
        case "$4" in
            '{{.State.Running}} {{.State.Status}}'*)
                echo "$(field "$name" running) $(field "$name" status) $(field "$name" restarts)" \
                     "$(field "$name" oom) $(field "$name" exit) $(field "$name" started)" \
                     "$(field "$name" memlimit) $(field "$name" datadir)" ;;
            '{{.State.Running}}') field "$name" running ;;
            *) echo "docker stub: unexpected format $4" >&2; exit 99 ;;
        esac ;;
    port)
        [ -d "$STUB_STATE/$2" ] && [ "$(field "$2" running)" = true ] || exit 1
        case "$3" in
            8545/tcp) echo "127.0.0.1:18545" ;;
            5052/tcp) echo "127.0.0.1:15052" ;;
            *) exit 1 ;;
        esac ;;
    stats)
        [ "$(field "$(last_arg "$@")" running)" = true ] || exit 1
        echo "${STUB_CPU:-140.37%} ${STUB_MEM:-1.5GiB} / 12GiB" ;;
    *) echo "docker stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

# The EL answers on 18545, Lighthouse on 15052.  STUB_RPC_FAIL / STUB_CL_FAIL
# make one of them refuse.  Each answer carries a 64-hex hash or a node id
# the probe must never copy.
cat > "$bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
data=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        --data) data="$2"; shift ;;
        http://*) url="$1" ;;
    esac
    shift
done
hash=0x5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed
case "$url" in
    http://127.0.0.1:18545)
        [ -z "${STUB_RPC_FAIL:-}" ] || exit 7
        case "$data" in
            *eth_getBlockByNumber*)
                printf '{"jsonrpc":"2.0","id":1,"result":{"hash":"%s","number":"0x%x","timestamp":"0x%x","miner":"0x0000000000000000000000000000000000000000"}}\n' \
                    "$hash" "$STUB_BLOCK" "$STUB_BLOCK_TS" ;;
            *eth_syncing*)
                if [ -n "${STUB_SYNCING:-}" ]; then
                    echo '{"jsonrpc":"2.0","id":1,"result":{"startingBlock":"0x0","currentBlock":"0x10","highestBlock":"0x20"}}'
                else
                    echo '{"jsonrpc":"2.0","id":1,"result":false}'
                fi ;;
            *net_peerCount*) printf '{"jsonrpc":"2.0","id":1,"result":"0x%x"}\n' "$STUB_PEERS" ;;
            *) exit 22 ;;
        esac ;;
    http://127.0.0.1:15052/eth/v1/node/syncing)
        [ -z "${STUB_CL_FAIL:-}" ] || exit 7
        printf '{"data":{"is_syncing":%s,"is_optimistic":%s,"el_offline":%s,"head_slot":"%s","sync_distance":"0"}}\n' \
            "${STUB_CL_SYNCING:-false}" "${STUB_CL_OPTIMISTIC:-false}" "${STUB_CL_EL_OFFLINE:-false}" "$STUB_SLOT" ;;
    http://127.0.0.1:15052/eth/v1/beacon/genesis)
        [ -z "${STUB_CL_FAIL:-}" ] || exit 7
        echo '{"data":{"genesis_time":"1742213400","genesis_validators_root":"0x212f13fc4df078b6cb7db228f1c8307566dcecf900867401a92023d7ba99cb5f","genesis_fork_version":"0x10000910"}}' ;;
    *) exit 7 ;;
esac
STUB

cat > "$bin/du" <<'STUB'
#!/bin/sh
echo "du $*" >> "$STUB_LOG"
for arg; do :; done
printf '%s\t%s\n' "${STUB_DU:-500000000000}" "$arg"
STUB
cat > "$bin/df" <<'STUB'
#!/bin/sh
echo "df $*" >> "$STUB_LOG"
printf ' Avail\n%s\n' "${STUB_DF:-233862381568}"
STUB
# With STUB_NOW set, date answers the probe's two formats from it; otherwise
# it is the real date.
cat > "$bin/date" <<STUB
#!/bin/sh
if [ -n "\${STUB_NOW:-}" ]; then
    case " \$* " in
        *" +%s "*) echo "\$STUB_NOW"; exit 0 ;;
        *" +%Y-%m-%dT%H:%M:%SZ "*) echo 2026-09-30T12:00:00Z; exit 0 ;;
    esac
fi
exec "$real_date" "\$@"
STUB
# crontab -l only: STUB_CRONTAB is the user's crontab file (absent: no
# crontab), STUB_CRONTAB_ERROR a failure.  Anything else is a write, which
# the gate must never make.
cat > "$bin/crontab" <<'STUB'
#!/bin/sh
echo "crontab $*" >> "$STUB_LOG"
[ "$*" = -l ] || { echo "crontab stub: unexpected write $*" >&2; exit 97; }
if [ -n "${STUB_CRONTAB_ERROR:-}" ]; then
    echo "$STUB_CRONTAB_ERROR" >&2; exit 1
elif [ -f "$STUB_CRONTAB" ]; then
    cat "$STUB_CRONTAB"
else
    echo "no crontab for ubuntu" >&2; exit 1
fi
STUB
chmod +x "$bin"/*

export PATH="$bin:$PATH"
export STUB_LOG="$work/stub.log" STUB_STATE="$work/state" STUB_REMOTE_DATA="$work/remote-data"
export STUB_CRONTAB="$work/crontab"
all_log="$work/all.log"
: > "$STUB_LOG"; : > "$all_log"

hdir="$work/health"
root="$STUB_REMOTE_DATA/hoodi-sec5-20260814"
rhealth="$root/health"
local_rhealth=/data/hoodi-sec5-20260814/health
now=1790747023

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
        sed 's/^/#   /' "${3:-$out}"
    fi
}
run() {  # STATUS DESCRIPTION -- COMMAND...
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
has() {
    if grep -qxF -- "$1" "$out"; then record ok "prints: $1"
    else echo "missing line: $1" >> "$out"; record fail "prints: $1"; fi
}
says() {
    if grep -qF -- "$1" "$out"; then record ok "says: $1"
    else echo "missing text: $1" >> "$out"; record fail "says: $1"; fi
}
lacks() {
    if grep -qF -- "$1" "$out"; then echo "unexpected text: $1" >> "$out"; record fail "never prints: $1"
    else record ok "never prints: $1"; fi
}
no_ssh() {
    if grep -q '^ssh ' "$STUB_LOG"; then record fail "$1: no remote contact" "$STUB_LOG"
    else record ok "$1: no remote contact"; fi
}
# token KEY=VALUE: the newest probe.log line carries this field.
token() {
    tail -n 1 "$hdir/probe.log" 2>/dev/null | tr ' ' '\n' > "$work/tokens" || true
    if grep -qxF -- "$1" "$work/tokens"; then record ok "probe.log field $1"
    else tail -n 1 "$hdir/probe.log" > "$work/detail" 2>&1 || true; record fail "probe.log field $1" "$work/detail"; fi
}
# alerted CONDITION: the newest run raised CONDITION and logged it once.
alerted() {
    tail -n 1 "$hdir/probe.log" | tr ' ' '\n' | sed -n 's/^alerts=//p' | tr ',' '\n' > "$work/raised"
    if grep -qxF -- "$1" "$work/raised" &&
       [ "$(grep -c " epoch=$now condition=$1 " "$hdir/ALERTS.log" 2>/dev/null)" = 1 ]; then
        record ok "alert $1 raised and logged once"
    else
        { tail -n 1 "$hdir/probe.log"; cat "$hdir/ALERTS.log" 2>/dev/null; } > "$work/detail"
        record fail "alert $1 raised and logged once" "$work/detail"
    fi
}
# quiet DESCRIPTION: the newest run raised nothing and logged nothing new.
quiet() {
    local before="$1" description="$2" after
    after="$(count_lines "$hdir/ALERTS.log")"
    if tail -n 1 "$hdir/probe.log" | grep -q ' alert=0 alerts=none$' && [ "$after" = "$before" ]; then
        record ok "$description raises no alert"
    else
        { tail -n 1 "$hdir/probe.log"; cat "$hdir/ALERTS.log" 2>/dev/null; } > "$work/detail"
        record fail "$description raises no alert" "$work/detail"
    fi
}
count_lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
alert_lines() { count_lines "$hdir/ALERTS.log"; }
latest_is() {
    if grep -qxF -- "$1" "$hdir/latest.txt" 2>/dev/null; then record ok "latest.txt reads $1"
    else cp "$hdir/latest.txt" "$work/detail" 2>/dev/null || echo "no latest.txt" > "$work/detail"
         record fail "latest.txt reads $1" "$work/detail"; fi
}

plant_container() {  # NAME RUNNING [RESTARTS] [STARTED]
    local dir="$STUB_STATE/$1"
    mkdir -p "$dir"
    echo "$2" > "$dir/running"
    if [ "$2" = true ]; then echo running > "$dir/status"; else echo exited > "$dir/status"; fi
    echo "${3:-0}" > "$dir/restarts"; echo false > "$dir/oom"; echo 0 > "$dir/exit"
    echo "${4:-2026-09-30T04:55:35.041068608Z}" > "$dir/started"
    echo 12884901888 > "$dir/memlimit"
    mkdir -p "$work/datadir-a18b84e2"
    echo "$work/datadir-a18b84e2" > "$dir/datadir"
}
# fresh_world: a healthy node and Lighthouse, an empty health directory.
fresh_world() {
    cat "$STUB_LOG" >> "$all_log"
    : > "$STUB_LOG"
    rm -rf "$STUB_STATE" "$hdir" "$STUB_REMOTE_DATA" "$STUB_CRONTAB"
    plant_container "$el" true
    plant_container "$cl" true
    unset STUB_RPC_FAIL STUB_CL_FAIL STUB_SYNCING STUB_CL_OPTIMISTIC STUB_CL_EL_OFFLINE \
        STUB_CL_SYNCING STUB_CPU STUB_MEM STUB_DU STUB_DF STUB_CRONTAB_ERROR \
        HOODI_GATE_RUNTIME_REVISION HOODI_GATE_REMOTE_ROOT HOODI_GATE_HOST \
        HOODI_GATE_CONTAINER HOODI_HEALTH_ALERT_TAIL
    export STUB_NOW="$now" STUB_BLOCK=3723345 STUB_BLOCK_TS=$((now - 10)) STUB_PEERS=22
    export STUB_SLOT=4044468
    export STUB_HEAD="$head_rev" STUB_HISTORY="$old_rev $head_rev"
}
probe() {  # [NAME=VALUE...]: run the probe against the stub world
    env HOODI_HEALTH_DIR="$hdir" HOODI_HEALTH_CONTAINER="$el" "$@" bash "$probe_copy"
}

# === the probe ===================================================================

# --- a healthy node ---------------------------------------------------------------
fresh_world
run 0 "a probe of a healthy node" -- probe
token "container=$el"
token "running=true"
token "restarts=0"
token "block=3723345"
token "block_age_s=10"
token "syncing=false"
token "peers=22"
token "mem_bytes=1610612736"
token "mem_limit=12884901888"
token "cpu_pct=140.37"
token "datadir=$work/datadir-a18b84e2"
token "datadir_bytes=500000000000"
if grep -qxF "du -sb $work/datadir-a18b84e2" "$STUB_LOG"; then
    record ok "the datadir measured is the EL's /data mount"
else
    record fail "the datadir measured is the EL's /data mount" "$STUB_LOG"
fi
token "data_free_bytes=233862381568"
token "cl_running=true"
token "cl_is_syncing=false"
token "cl_is_optimistic=false"
token "cl_el_offline=false"
token "cl_head_slot=4044468"
token "cl_head_age_s=7"
quiet 0 "a healthy node"
if [ "$(wc -l < "$hdir/probe.log" | tr -d ' ')" = 1 ] && head -c 21 "$hdir/probe.log" | grep -qx '2026-09-30T12:00:00Z '; then
    record ok "one probe.log line that starts with the ISO time"
else
    record fail "one probe.log line that starts with the ISO time" "$hdir/probe.log"
fi
latest_is "time=2026-09-30T12:00:00Z"
latest_is "epoch=$now"
latest_is "alert=0"
latest_is "alerts=none"
[ ! -e "$hdir/ALERTS.log" ] && record ok "a healthy node writes no ALERTS.log" ||
    record fail "a healthy node writes no ALERTS.log" "$hdir/ALERTS.log"
export STUB_SYNCING=1
run 0 "a probe of a node that is still syncing" -- probe
token "syncing=true"
echo /data/hoodi-sec5-20260814/datadir-gone > "$STUB_STATE/$el/datadir"
run 0 "a probe whose /data mount is not on this filesystem" -- probe
token "datadir_bytes=na"

# --- knob refusals ------------------------------------------------------------------
fresh_world
run 2 "a probe without HOODI_HEALTH_CONTAINER" -- env HOODI_HEALTH_DIR="$hdir" bash "$probe_copy"
says "HOODI_HEALTH_CONTAINER must name the EL container"
run 2 "a probe with a non-integer knob" -- probe HOODI_HEALTH_MIN_PEERS=three
says "every numeric knob must be a non-negative integer: three"
run 2 "a probe with an unsafe container name" -- probe HOODI_HEALTH_CONTAINER='a;b'
[ ! -e "$hdir/probe.log" ] && record ok "a refused probe writes no record" ||
    record fail "a refused probe writes no record" "$hdir/probe.log"

# --- every alert rule, each with its control ---------------------------------------
fresh_world
export STUB_BLOCK_TS=$((now - 121))
run 0 "a block 121 s old" -- probe
token "block_age_s=121"
alerted block-age
fresh_world
export STUB_BLOCK_TS=$((now - 120))
run 0 "a block 120 s old" -- probe
quiet 0 "a block exactly at the 120 s limit"

fresh_world
export STUB_PEERS=2
run 0 "two peers" -- probe
alerted peers-low
fresh_world
export STUB_PEERS=3
run 0 "three peers" -- probe
quiet 0 "three peers"

fresh_world
export STUB_CL_EL_OFFLINE=true
run 0 "Lighthouse reporting the EL offline" -- probe
token "cl_el_offline=true"
alerted cl-el-offline
fresh_world
export STUB_CL_OPTIMISTIC=true
run 0 "Lighthouse optimistic" -- probe
token "cl_is_optimistic=true"
alerted cl-optimistic
fresh_world
export STUB_CL_SYNCING=true
run 0 "Lighthouse still syncing" -- probe
token "cl_is_syncing=true"
quiet 0 "Lighthouse is_syncing alone"
fresh_world
export STUB_CL_FAIL=1
run 0 "Lighthouse's API refusing" -- probe
alerted cl-unavailable
fresh_world
echo false > "$STUB_STATE/$cl/running"
run 0 "Lighthouse stopped" -- probe
token "cl_running=false"
alerted cl-unavailable

fresh_world
export STUB_DF=$((42949672960 - 1))
run 0 "/data one byte under 40 GiB free" -- probe
alerted data-free-low
fresh_world
export STUB_DF=42949672960
run 0 "/data at exactly 40 GiB free" -- probe
quiet 0 "/data at exactly 40 GiB free"

fresh_world
export STUB_MEM=11.5GiB
run 0 "11.5 GiB of a 12 GiB limit" -- probe
alerted mem-high
fresh_world
export STUB_MEM=10GiB
run 0 "10 GiB of a 12 GiB limit" -- probe
quiet 0 "10 GiB of a 12 GiB limit"
fresh_world
echo 1000 > "$STUB_STATE/$el/memlimit"
export STUB_MEM=900B
run 0 "exactly 90% of the limit" -- probe
quiet 0 "exactly 90% of the limit"
export STUB_MEM=901B
run 0 "just over 90% of the limit" -- probe
alerted mem-high
fresh_world
echo 0 > "$STUB_STATE/$el/memlimit"
export STUB_MEM=11.5GiB
run 0 "no Docker memory limit" -- probe
token "mem_limit=12884901888"
alerted mem-high

fresh_world
export STUB_RPC_FAIL=1
run 0 "an EL whose RPC refuses" -- probe
token "block=na"
alerted el-rpc-unavailable

fresh_world
echo false > "$STUB_STATE/$el/running"
echo 137 > "$STUB_STATE/$el/exit"
echo exited > "$STUB_STATE/$el/status"
echo true > "$STUB_STATE/$el/oom"
run 0 "an OOM-killed EL" -- probe
token "running=false"
token "exit=137"
alerted container-not-running
alerted oom-killed
if grep -q 'curl .*18545' "$STUB_LOG"; then
    record fail "a stopped EL is not asked over RPC" "$STUB_LOG"
else
    record ok "a stopped EL is not asked over RPC"
fi
if [ "$(grep -c " epoch=$now " "$hdir/ALERTS.log")" = 2 ]; then
    record ok "two conditions are two ALERTS.log lines"
else
    record fail "two conditions are two ALERTS.log lines" "$hdir/ALERTS.log"
fi
latest_is "alert=1"
latest_is "alerts=container-not-running,oom-killed"
# latest.txt is rewritten, not appended: a healthy run after it reads alert=0.
plant_container "$el" true
run 0 "a healthy run after an alert" -- probe
latest_is "alert=0"
if grep -c '^alert=' "$hdir/latest.txt" | grep -qx 1; then
    record ok "latest.txt holds one record"
else
    record fail "latest.txt holds one record" "$hdir/latest.txt"
fi

fresh_world
rm -rf "${STUB_STATE:?}/$el"
run 0 "an absent EL container" -- probe
token "running=absent"
token "restarts=na"
alerted container-not-running

# --- restarts -------------------------------------------------------------------------
fresh_world
run 0 "the first probe (restart baseline 0)" -- probe
quiet 0 "the first probe"
echo 1 > "$STUB_STATE/$el/restarts"
echo 2026-09-30T13:00:00.000000000Z > "$STUB_STATE/$el/started"
run 0 "a probe after Docker restarted the EL" -- probe
alerted restart-count-grew
lines="$(alert_lines)"
run 0 "the probe after that" -- probe
quiet "$lines" "an unchanged restart count"
echo 2026-09-30T14:00:00.000000000Z > "$STUB_STATE/$el/started"
run 0 "a probe after a manual restart" -- probe
alerted started-at-changed
lines="$(alert_lines)"
# A different container is a new baseline, not a restart.
plant_container hoodi-el-sec5-cccccccc true 5 2026-09-30T15:00:00.000000000Z
run 0 "a probe of another container" -- probe HOODI_HEALTH_CONTAINER=hoodi-el-sec5-cccccccc
quiet "$lines" "a new container's first probe"

# --- rotation ---------------------------------------------------------------------------
fresh_world
mkdir -p "$hdir"
printf 'older line\n' > "$hdir/probe.log.1"
# One probe line is well under 2000 bytes, so the cap is reached only by the
# planted content.
head -c 2000 /dev/zero | tr '\0' x > "$hdir/probe.log"; echo >> "$hdir/probe.log"
run 0 "a probe at the rotation size" -- probe HOODI_HEALTH_LOG_MAX_BYTES=2000
if [ "$(wc -l < "$hdir/probe.log" | tr -d ' ')" = 1 ] && grep -q "^2026-09-30T12:00:00Z epoch=$now " "$hdir/probe.log" &&
   grep -q '^xxxx' "$hdir/probe.log.1" && ! grep -q 'older line' "$hdir/probe.log.1"; then
    record ok "probe.log is renamed to probe.log.1 once, replacing the older .1"
else
    { echo "--- probe.log"; cat "$hdir/probe.log"; echo "--- probe.log.1"; cat "$hdir/probe.log.1"; } > "$work/detail"
    record fail "probe.log is renamed to probe.log.1 once, replacing the older .1" "$work/detail"
fi
run 0 "a probe below the rotation size" -- probe HOODI_HEALTH_LOG_MAX_BYTES=2000
if [ "$(wc -l < "$hdir/probe.log" | tr -d ' ')" = 2 ] && grep -q '^xxxx' "$hdir/probe.log.1"; then
    record ok "below the size, probe.log grows and probe.log.1 stays"
else
    record fail "below the size, probe.log grows and probe.log.1 stays" "$hdir/probe.log"
fi
head -c 2000 /dev/zero | tr '\0' y > "$hdir/ALERTS.log"; echo >> "$hdir/ALERTS.log"
export STUB_PEERS=1
run 0 "an alert at the rotation size" -- probe HOODI_HEALTH_LOG_MAX_BYTES=2000
if grep -q '^yyyy' "$hdir/ALERTS.log.1" && [ "$(wc -l < "$hdir/ALERTS.log" | tr -d ' ')" = 1 ]; then
    record ok "ALERTS.log rotates the same way"
else
    record fail "ALERTS.log rotates the same way" "$hdir/ALERTS.log"
fi

# --- one run at a time ----------------------------------------------------------------
fresh_world
if command -v flock >/dev/null 2>&1; then
    mkdir -p "$hdir"
    run 0 "a probe while another holds the lock" -- \
        flock -n "$hdir/.probe.lock" env HOODI_HEALTH_DIR="$hdir" HOODI_HEALTH_CONTAINER="$el" bash "$probe_copy"
    token "skipped=previous-probe-still-running"
    [ ! -e "$hdir/latest.txt" ] && record ok "a skipped probe leaves latest.txt alone" ||
        record fail "a skipped probe leaves latest.txt alone" "$hdir/latest.txt"
    run 0 "a probe once the lock is free" -- probe
    token "running=true"
else
    echo "# flock is absent here: the one-run-at-a-time path is not exercised"
fi

# --- no peer identity crosses into a record ---------------------------------------------
fresh_world
export STUB_PEERS=1 STUB_CL_EL_OFFLINE=true
run 0 "a probe with alerts" -- probe
. "$repo/scripts/hoodi-log-redact.sh"
for f in probe.log ALERTS.log latest.txt; do
    if hoodi_redact_peer_identities < "$hdir/$f" | cmp -s - "$hdir/$f"; then
        record ok "$f carries nothing the redaction filter would mask"
    else
        record fail "$f carries nothing the redaction filter would mask" "$hdir/$f"
    fi
done
# The positive control: the filter does mask the hash the stub answered with.
if printf 'hash=0x5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed5eed\n' |
   hoodi_redact_peer_identities | grep -qx 'hash=0x5eed5eed…5eed'; then
    record ok "the redaction filter masks the hash the probe was answered with"
else
    record fail "the redaction filter masks the hash the probe was answered with" /dev/null
fi
cat "$hdir"/probe.log "$hdir"/ALERTS.log "$hdir"/latest.txt > "$out"
lacks "5eed5eed"
lacks "genesis_validators_root"

# === the gate ===================================================================
fresh_world
unset STUB_NOW
run 0 "help" -- "$gate" help
says "Usage: scripts/hoodi-health-gate.sh ACTION [HOURS]"
says "HOODI_GATE_RUNTIME_REVISION       full runtime revision (default HEAD)"
run 2 "an unknown action" -- "$gate" frobnicate
says "unknown action: frobnicate"
run 2 "install, which this broker does not offer" -- "$gate" install
run 2 "uninstall, which this broker does not offer" -- "$gate" uninstall
no_ssh "usage"

run 1 "a malformed runtime revision" -- env HOODI_GATE_RUNTIME_REVISION=HEAD "$gate" status
has "ERROR: revision must be a full lowercase hexadecimal Git id"
run 1 "a short runtime revision" -- env HOODI_GATE_RUNTIME_REVISION=aaaaaaaa "$gate" status
has "ERROR: revision must contain exactly 40 hexadecimal characters"
run 1 "a runtime revision that is not an ancestor of HEAD" -- \
    env HOODI_GATE_RUNTIME_REVISION="$side_rev" "$gate" status
has "ERROR: runtime revision $side_rev is not an ancestor of checkout HEAD $head_rev"
run 1 "a remote root outside /data/hoodi-sec5-*" -- env HOODI_GATE_REMOTE_ROOT=/srv/hoodi "$gate" status
has "ERROR: remote root must stay below /data/hoodi-sec5-*: /srv/hoodi"
run 1 "a remote root with .." -- env HOODI_GATE_REMOTE_ROOT=/data/hoodi-sec5-x/../etc "$gate" status
has "ERROR: remote root must be a normalized path of plain characters: /data/hoodi-sec5-x/../etc"
run 1 "a remote root with a glob" -- env HOODI_GATE_REMOTE_ROOT='/data/hoodi-sec5-*' "$gate" status
says "remote root must be a normalized path of plain characters"
run 1 "an unsafe SSH host" -- env HOODI_GATE_HOST='a b' "$gate" status
has "ERROR: unsafe SSH host: a b"
run 1 "an unsafe container name" -- env HOODI_GATE_CONTAINER='x;y' "$gate" status
has "ERROR: unsafe Docker name: x;y"
run 1 "report over zero hours" -- "$gate" report 0
has "ERROR: report hours must be between 1 and 8760"
run 1 "report over a year and an hour" -- "$gate" report 8761
has "ERROR: report hours must be between 1 and 8760"
run 1 "report over a word" -- "$gate" report day
has "ERROR: report hours must be an integer"
no_ssh "control-plane refusals"
# The accepted side of the fence: an older runtime revision on this line.
run 0 "status for an older runtime revision" -- env HOODI_GATE_RUNTIME_REVISION="$old_rev" "$gate" status
has "runtime-revision=$old_rev head=$head_rev container=hoodi-el-sec5-bbbbbbbb health-dir=$local_rhealth"

# --- status -------------------------------------------------------------------------------
fresh_world
unset STUB_NOW
run 0 "status before the probe was ever put on the host" -- "$gate" status
has "runtime-revision=$head_rev head=$head_rev container=$el health-dir=$local_rhealth"
has "cron-line=absent (no crontab)"
has "probe=absent"
has "latest=absent"
has "alerts-logged=0"

# The probe placed on the host as it would be, run twice (one alert).
mkdir -p "$rhealth"
cp "$probe_copy" "$rhealth/hoodi-health-probe.sh"
real_now="$("$real_date" -u +%s)"
export STUB_NOW="$real_now" STUB_BLOCK_TS=$((real_now - 10)) STUB_SLOT=$(( (real_now - 1742213400) / 12 ))
env HOODI_HEALTH_DIR="$rhealth" HOODI_HEALTH_CONTAINER="$el" bash "$rhealth/hoodi-health-probe.sh"
export STUB_PEERS=1
env HOODI_HEALTH_DIR="$rhealth" HOODI_HEALTH_CONTAINER="$el" bash "$rhealth/hoodi-health-probe.sh"
unset STUB_NOW
printf '%s\n' "# */5 * * * * bash $rhealth/hoodi-health-probe.sh" "0 3 * * * /usr/bin/true" > "$STUB_CRONTAB"
run 0 "status with a commented-out mention only" -- "$gate" status
has "cron-line=absent"
printf '%s\n' "*/5 * * * * bash $rhealth/hoodi-health-probe.sh >/dev/null 2>&1" >> "$STUB_CRONTAB"
: > "$STUB_LOG"
run 0 "status of a probe that runs" -- "$gate" status
has "cron-line=present count=1"
has "probe=installed matches-checkout=true"
says "probe-stale=false"
has "latest: alert=1"
has "latest: alerts=peers-low"
has "latest: peers=1"
has "alerts-logged=1"
says "alert: 2026-09-30T12:00:00Z epoch=$real_now condition=peers-low peers=1<3 container=$el"
export STUB_CRONTAB_ERROR="crontab: cannot open the spool"
run 0 "status when crontab -l fails" -- "$gate" status
has "cron-line=unreadable"
unset STUB_CRONTAB_ERROR
run 0 "status with a one-line alert tail" -- env HOODI_HEALTH_ALERT_TAIL=1 "$gate" status
says "condition=peers-low"
echo "# local edit" >> "$rhealth/hoodi-health-probe.sh"
run 0 "status of an installed probe that differs from the checkout" -- "$gate" status
says "probe=installed matches-checkout=false sha256="
sed -i.bak "s/^epoch=.*/epoch=$((real_now - 1000))/" "$rhealth/latest.txt" && rm -f "$rhealth/latest.txt.bak"
run 0 "status of a probe that stopped running" -- "$gate" status
says "probe-stale=true"

# --- report ----------------------------------------------------------------------------------
fresh_world
unset STUB_NOW
mkdir -p "$rhealth"
t="$("$real_date" -u +%s)"
line() {  # ISO EPOCH FIELDS...
    local iso="$1" epoch="$2"; shift 2
    printf '%s epoch=%s container=%s %s\n' "$iso" "$epoch" "$el" "$*"
}
{
    line 2026-09-28T00:00:00Z $((t - 108000)) running=true restarts=0 block=100 block_age_s=999 mem_bytes=999999999999 peers=0 data_free_bytes=1 alert=1 alerts=peers-low
    line 2026-09-30T08:00:00Z $((t - 14400)) running=true restarts=0 block=1000 block_age_s=5 mem_bytes=100 peers=10 data_free_bytes=5000 alert=0 alerts=none
    line 2026-09-30T09:00:00Z $((t - 10800)) running=true restarts=0 block=1300 block_age_s=130 mem_bytes=300 peers=4 data_free_bytes=4000 alert=1 alerts=block-age
} > "$rhealth/probe.log.1"
{
    printf '2026-09-30T09:30:00Z epoch=%s container=%s skipped=previous-probe-still-running\n' $((t - 9000)) "$el"
    line 2026-09-30T10:00:00Z $((t - 7200)) running=true restarts=1 block=1360 block_age_s=12 mem_bytes=200 peers=2 data_free_bytes=4500 alert=1 alerts=peers-low
    line 2026-09-30T11:00:00Z $((t - 3000)) running=false restarts=1 block=na block_age_s=na mem_bytes=na peers=na data_free_bytes=4400 alert=1 alerts=container-not-running,cl-unavailable
} > "$rhealth/probe.log"
{
    printf '2026-09-28T00:00:00Z epoch=%s condition=peers-low peers=0<3 container=%s\n' $((t - 108000)) "$el"
    printf '2026-09-30T09:00:00Z epoch=%s condition=block-age block=1300 block_age_s=130>120 container=%s\n' $((t - 10800)) "$el"
    printf '2026-09-30T10:00:00Z epoch=%s condition=peers-low peers=2<3 container=%s\n' $((t - 7200)) "$el"
    printf '2026-09-30T11:00:00Z epoch=%s condition=container-not-running running=false container=%s\n' $((t - 3000)) "$el"
    printf '2026-09-30T11:00:00Z epoch=%s condition=cl-unavailable cl_running=true container=%s\n' $((t - 3000)) "$el"
} > "$rhealth/ALERTS.log"
run 0 "report over the last day" -- "$gate" report
has "health-dir=$local_rhealth window-hours=24"
has "samples=5 skipped=1 first=2026-09-30T08:00:00Z last=2026-09-30T11:00:00Z"
has "block-first=1000 block-last=1360 block-advance=360"
has "block-rate-per-min min=1.00 max=5.00"
has "block-age-max-s=130 mem-peak-bytes=300 peers-min=2 peers-max=10 data-free-min-bytes=4000"
has "restarts-first=0 restarts-last=1 not-running-samples=1 alert-samples=3"
has "alert-lines=4"
has "alert-condition=block-age count=1"
has "alert-condition=peers-low count=1"
has "alert-condition=container-not-running count=1"
has "alert-condition=cl-unavailable count=1"
run 0 "report over the last hour" -- "$gate" report 1
has "samples=1 skipped=0 first=2026-09-30T11:00:00Z last=2026-09-30T11:00:00Z"
has "block-first=na block-last=na block-advance=na"
has "alert-lines=2"
run 0 "report over two days" -- "$gate" report 48
says "samples=6 skipped=1 first=2026-09-28T00:00:00Z"
has "alert-lines=5"

fresh_world
unset STUB_NOW
mkdir -p "$rhealth"
run 1 "report with no probe.log" -- "$gate" report
says "no probe.log in $rhealth: has the probe run?"

# --- status and report write nothing on the remote side ----------------------------------------
fresh_world
unset STUB_NOW
mkdir -p "$rhealth"
cp "$probe_copy" "$rhealth/hoodi-health-probe.sh"
export STUB_NOW="$("$real_date" -u +%s)" STUB_PEERS=1
env HOODI_HEALTH_DIR="$rhealth" HOODI_HEALTH_CONTAINER="$el" bash "$rhealth/hoodi-health-probe.sh"
unset STUB_NOW
snapshot() { (cd "$STUB_REMOTE_DATA" && find . -print | LC_ALL=C sort | while read -r p; do
    if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p")"; else printf '%s dir\n' "$p"; fi
done); }
snapshot > "$work/before"
run 0 "status" -- "$gate" status
run 0 "report" -- "$gate" report
snapshot > "$work/after"
if cmp -s "$work/before" "$work/after"; then
    record ok "status and report change nothing on the remote side"
else
    diff "$work/before" "$work/after" > "$work/detail" || true
    record fail "status and report change nothing on the remote side" "$work/detail"
fi

cat "$STUB_LOG" >> "$all_log"
: > "$out"
if grep -E '^docker (run|start|stop|restart|kill|rm|update|exec|pause|unpause|create|image|volume|system|network)' "$all_log" > "$out"; then
    record fail "neither the probe nor the gate asks Docker to change anything"
else
    record ok "neither the probe nor the gate asks Docker to change anything"
fi
if grep -E '^crontab ' "$all_log" | grep -vxF 'crontab -l' > "$out"; then
    record fail "nothing writes a crontab"
else
    record ok "nothing writes a crontab"
fi

echo "hoodi-health-gate selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
