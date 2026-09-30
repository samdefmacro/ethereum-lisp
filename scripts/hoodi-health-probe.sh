#!/usr/bin/env bash
#
# Unattended health probe for the long-running Hoodi node.  It is meant to run
# ON THE REMOTE HOST every five minutes, as the SSH user, from a scheduler the
# operator sets up; scripts/hoodi-health-gate.sh (status, report) reads what
# it records.  It needs only bash, docker, curl, awk,
# sed and date (flock and timeout are used when present) and never changes a
# container: every Docker call is an inspect, a port lookup or a one-shot
# stats read.
#
# Each run appends ONE line to HEALTH_DIR/probe.log -- the ISO time, then
# key=value fields -- and rewrites HEALTH_DIR/latest.txt (one key=value per
# line).  A condition in the alert rules below also appends one line per
# condition to HEALTH_DIR/ALERTS.log and sets alert=1.  probe.log and
# ALERTS.log are renamed to .1 once they reach HOODI_HEALTH_LOG_MAX_BYTES
# (one generation is kept; nothing is ever deleted otherwise).
#
# Nothing here prints a peer identity: the fields are counts, block numbers,
# times, byte sizes and container state.  Keep it that way (the gate's
# self-test runs scripts/hoodi-log-redact.sh over the output and requires it
# unchanged).
#
# Alert rules (condition names as they appear in ALERTS.log):
#   container-not-running  the EL container is absent or not running
#   oom-killed             Docker reports the EL was OOM-killed
#   restart-count-grew     Docker's restart count rose since the last run
#   started-at-changed     the EL started again with the same restart count
#                          (a manual restart, a daemon or host restart)
#   el-rpc-unavailable     the EL is running but eth_getBlockByNumber fails
#   block-age              our latest block is older than BLOCK_AGE_MAX seconds
#   peers-low              net_peerCount below MIN_PEERS
#   cl-unavailable         Lighthouse is not running or /eth/v1/node/syncing fails
#   cl-el-offline          Lighthouse reports el_offline=true
#   cl-optimistic          Lighthouse reports is_optimistic=true
#   data-free-low          /data has less than MIN_FREE_BYTES available
#   mem-high               EL memory above MEM_PCT_MAX percent of its limit
#
# Knobs (environment):
#   HOODI_HEALTH_DIR             output directory (default
#                                /data/hoodi-sec5-20260814/health)
#   HOODI_HEALTH_CONTAINER       EL container (required)
#   HOODI_HEALTH_CL_CONTAINER    Lighthouse container (hoodi-lighthouse-public)
#   HOODI_HEALTH_DATA_MOUNT      filesystem whose free space is watched (/data)
#   HOODI_HEALTH_BLOCK_AGE_MAX   seconds (120)
#   HOODI_HEALTH_MIN_PEERS       (3)
#   HOODI_HEALTH_MIN_FREE_BYTES  (42949672960, 40 GiB)
#   HOODI_HEALTH_MEM_PCT_MAX     integer percent (90)
#   HOODI_HEALTH_MEM_LIMIT_BYTES used when Docker reports no limit
#                                (12884901888, 12 GiB)
#   HOODI_HEALTH_SECONDS_PER_SLOT beacon slot length (12)
#   HOODI_HEALTH_LOG_MAX_BYTES   rotation size (52428800, 50 MiB)

set -u
# cron's PATH is minimal; append the system directories rather than prepend
# them, so a caller's PATH (the self-test's stubs) still wins.
PATH="${PATH:-}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

dir="${HOODI_HEALTH_DIR:-/data/hoodi-sec5-20260814/health}"
container="${HOODI_HEALTH_CONTAINER:-}"
cl_container="${HOODI_HEALTH_CL_CONTAINER:-hoodi-lighthouse-public}"
data_mount="${HOODI_HEALTH_DATA_MOUNT:-/data}"
block_age_max="${HOODI_HEALTH_BLOCK_AGE_MAX:-120}"
min_peers="${HOODI_HEALTH_MIN_PEERS:-3}"
min_free_bytes="${HOODI_HEALTH_MIN_FREE_BYTES:-42949672960}"
mem_pct_max="${HOODI_HEALTH_MEM_PCT_MAX:-90}"
default_mem_limit="${HOODI_HEALTH_MEM_LIMIT_BYTES:-12884901888}"
seconds_per_slot="${HOODI_HEALTH_SECONDS_PER_SLOT:-12}"
log_max_bytes="${HOODI_HEALTH_LOG_MAX_BYTES:-52428800}"

probe_fail() {
    echo "hoodi-health-probe: $*" >&2
    exit 2
}

case "$container" in
    *[!A-Za-z0-9_.-]*|'') probe_fail "HOODI_HEALTH_CONTAINER must name the EL container" ;;
esac
case "$cl_container" in
    *[!A-Za-z0-9_.-]*|'') probe_fail "unsafe Lighthouse container name: $cl_container" ;;
esac
for knob in "$block_age_max" "$min_peers" "$min_free_bytes" "$mem_pct_max" \
            "$default_mem_limit" "$seconds_per_slot" "$log_max_bytes"; do
    case "$knob" in *[!0-9]*|'') probe_fail "every numeric knob must be a non-negative integer: $knob" ;; esac
done

mkdir -p "$dir" || probe_fail "cannot create $dir"
probe_log="$dir/probe.log"
alerts_log="$dir/ALERTS.log"
state_file="$dir/.probe.state"
exec 2>>"$dir/probe.err"

# bounded CMD...: run a command under timeout(1) when it exists, so a hung
# daemon or socket cannot hold the cron slot forever.
bounded() {
    local limit="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$limit" "$@"
    else
        "$@"
    fi
}

# rotate FILE: rename FILE to FILE.1 (replacing an older .1) once it has
# reached the size cap.
rotate() {
    local size
    [ -f "$1" ] || return 0
    size="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
    case "$size" in *[!0-9]*|'') return 0 ;; esac
    [ "$size" -ge "$log_max_bytes" ] || return 0
    mv -f "$1" "$1.1"
}

now="$(date -u +%s)"
iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# One run at a time: a probe still waiting on a hung daemon makes the next
# one record that it was skipped instead of piling up.
if command -v flock >/dev/null 2>&1; then
    exec 9>>"$dir/.probe.lock"
    if ! flock -n 9; then
        rotate "$probe_log"
        printf '%s epoch=%s container=%s skipped=previous-probe-still-running\n' \
            "$iso" "$now" "$container" >> "$probe_log"
        exit 0
    fi
fi

# json_field KEY: the scalar value of "KEY" in the JSON on stdin, with its
# quotes removed ("" when absent; the last occurrence if KEY repeats).  Every
# key read here occurs once in its answer and holds a string, number or
# boolean, so this needs no JSON parser on the host.
json_field() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1
}

# hex_to_dec VALUE: a 0x quantity as decimal, "na" otherwise.
hex_to_dec() {
    case "$1" in
        0x[0-9a-fA-F]*) local digits="${1#0x}"
            case "$digits" in *[!0-9a-fA-F]*) echo na ;; *) echo "$((16#$digits))" ;; esac ;;
        *) echo na ;;
    esac
}

# loopback_port CONTAINER PORT: the host port Docker published PORT on at
# 127.0.0.1 (the node's public RPC and Lighthouse's API are ephemeral).
loopback_port() {
    bounded 30 docker port "$1" "$2" 2>/dev/null |
        awk -F: '/^127[.]0[.]0[.]1:/ {print $NF; exit}'
}

rpc() {  # PORT METHOD PARAMS
    bounded 20 curl -fsS --max-time 10 --header 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}" \
        "http://127.0.0.1:$1" 2>/dev/null
}

# to_bytes: a Docker size (1.478GiB, 512MiB, 900kB, 0B) as whole bytes.
to_bytes() {
    awk -v s="$1" 'BEGIN {
        if (match(s, /^[0-9.]+/) == 0) { print "na"; exit }
        n = substr(s, 1, RLENGTH); u = substr(s, RLENGTH + 1)
        m["B"] = 1; m["KiB"] = 1024; m["MiB"] = 1048576; m["GiB"] = 1073741824
        m["TiB"] = 1099511627776; m["kB"] = 1000; m["KB"] = 1000; m["MB"] = 1000000
        m["GB"] = 1000000000; m["TB"] = 1000000000000
        if (!(u in m)) { print "na"; exit }
        printf "%.0f\n", n * m[u]
    }'
}

# --- the EL container ---------------------------------------------------------
running=absent; status=absent; restarts=na; oom=na; exit_code=na
started=na; mem_limit=na; datadir=na
inspect="$(bounded 30 docker container inspect --format \
    '{{.State.Running}} {{.State.Status}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.ExitCode}} {{.State.StartedAt}} {{.HostConfig.Memory}} {{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' \
    "$container" 2>/dev/null)" && [ -n "$inspect" ] && {
    read -r running status restarts oom exit_code started mem_limit datadir <<EOF
$inspect
EOF
    [ -n "$datadir" ] || datadir=na
}
case "$mem_limit" in ''|0|*[!0-9]*) mem_limit="$default_mem_limit" ;; esac

cpu_pct=na; mem_bytes=na
if [ "$running" = true ]; then
    stats="$(bounded 60 docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$container" 2>/dev/null)"
    if [ -n "$stats" ]; then
        cpu_pct="$(printf '%s' "$stats" | awk '{sub(/%$/, "", $1); print $1}')"
        mem_bytes="$(to_bytes "$(printf '%s' "$stats" | awk '{print $2}')")"
        case "$cpu_pct" in ''|*[!0-9.]*) cpu_pct=na ;; esac
    fi
fi

datadir_bytes=na
if [ "$datadir" != na ] && [ -d "$datadir" ]; then
    datadir_bytes="$(bounded 120 du -sb "$datadir" 2>/dev/null | awk '{print $1}')"
    case "$datadir_bytes" in ''|*[!0-9]*) datadir_bytes=na ;; esac
fi
data_free=na
data_free="$(bounded 30 df -B1 --output=avail "$data_mount" 2>/dev/null | awk 'NR == 2 {print $1}')"
case "$data_free" in ''|*[!0-9]*) data_free=na ;; esac

# --- the EL's public RPC --------------------------------------------------------
block=na; block_ts=na; block_age=na; syncing=na; peers=na
if [ "$running" = true ]; then
    rpc_port="$(loopback_port "$container" 8545/tcp)"
    if [ -n "$rpc_port" ]; then
        latest="$(rpc "$rpc_port" eth_getBlockByNumber '["latest",false]')"
        block="$(hex_to_dec "$(printf '%s' "$latest" | json_field number)")"
        block_ts="$(hex_to_dec "$(printf '%s' "$latest" | json_field timestamp)")"
        [ "$block_ts" = na ] || block_age=$(( now - block_ts ))
        # false, or an object (read here as its opening brace) while syncing;
        # an error answer carries no result at all.
        case "$(rpc "$rpc_port" eth_syncing '[]' | json_field result)" in
            false) syncing=false ;;
            '') syncing=na ;;
            *) syncing=true ;;
        esac
        peers="$(hex_to_dec "$(rpc "$rpc_port" net_peerCount '[]' | json_field result)")"
    fi
fi

# --- Lighthouse -------------------------------------------------------------------
cl_running="$(bounded 30 docker container inspect --format '{{.State.Running}}' "$cl_container" 2>/dev/null)"
[ -n "$cl_running" ] || cl_running=absent
cl_syncing=na; cl_optimistic=na; cl_el_offline=na; cl_head_slot=na; cl_head_age=na
if [ "$cl_running" = true ]; then
    cl_port="$(loopback_port "$cl_container" 5052/tcp)"
    if [ -n "$cl_port" ]; then
        node="$(bounded 20 curl -fsS --max-time 10 "http://127.0.0.1:$cl_port/eth/v1/node/syncing" 2>/dev/null)"
        cl_syncing="$(printf '%s' "$node" | json_field is_syncing)"
        cl_optimistic="$(printf '%s' "$node" | json_field is_optimistic)"
        cl_el_offline="$(printf '%s' "$node" | json_field el_offline)"
        cl_head_slot="$(printf '%s' "$node" | json_field head_slot)"
        genesis="$(bounded 20 curl -fsS --max-time 10 "http://127.0.0.1:$cl_port/eth/v1/beacon/genesis" 2>/dev/null |
            json_field genesis_time)"
        case "$cl_head_slot" in ''|*[!0-9]*) cl_head_slot=na ;; esac
        case "$genesis" in ''|*[!0-9]*) genesis=na ;; esac
        if [ "$cl_head_slot" != na ] && [ "$genesis" != na ]; then
            cl_head_age=$(( now - genesis - cl_head_slot * seconds_per_slot ))
        fi
        for v in cl_syncing cl_optimistic cl_el_offline; do
            case "${!v}" in true|false) ;; *) printf -v "$v" na ;; esac
        done
    fi
fi

# --- alert rules ------------------------------------------------------------------
prev_container=""; prev_restarts=""; prev_started=""
if [ -f "$state_file" ]; then
    read -r prev_container prev_restarts prev_started < "$state_file" || true
fi
alerts=""
details=()
raise() {  # CONDITION DETAIL
    alerts="${alerts:+$alerts,}$1"
    details+=("condition=$1 $2")
}
[ "$running" = true ] || raise container-not-running "running=$running status=$status exit=$exit_code"
[ "$oom" != true ] || raise oom-killed "oom=true exit=$exit_code"
if [ "$prev_container" = "$container" ] && [ "$restarts" != na ]; then
    case "$prev_restarts" in
        ''|*[!0-9]*) ;;
        *) if [ "$restarts" -gt "$prev_restarts" ]; then
               raise restart-count-grew "restarts=$prev_restarts->$restarts"
           elif [ "$started" != na ] && [ -n "$prev_started" ] && [ "$started" != "$prev_started" ]; then
               raise started-at-changed "started=$prev_started->$started"
           fi ;;
    esac
fi
if [ "$running" = true ] && [ "$block" = na ]; then
    raise el-rpc-unavailable "block=na"
fi
if [ "$block_age" != na ] && [ "$block_age" -gt "$block_age_max" ]; then
    raise block-age "block=$block block_age_s=$block_age>$block_age_max"
fi
if [ "$peers" != na ] && [ "$peers" -lt "$min_peers" ]; then
    raise peers-low "peers=$peers<$min_peers"
fi
if [ "$cl_running" != true ] || [ "$cl_el_offline" = na ]; then
    raise cl-unavailable "cl_running=$cl_running"
fi
[ "$cl_el_offline" != true ] || raise cl-el-offline "cl_el_offline=true"
[ "$cl_optimistic" != true ] || raise cl-optimistic "cl_is_optimistic=true"
if [ "$data_free" != na ] && [ "$data_free" -lt "$min_free_bytes" ]; then
    raise data-free-low "data_free_bytes=$data_free<$min_free_bytes"
fi
if [ "$mem_bytes" != na ] && [ $(( mem_bytes * 100 )) -gt $(( mem_limit * mem_pct_max )) ]; then
    raise mem-high "mem_bytes=$mem_bytes>${mem_pct_max}%_of_$mem_limit"
fi
alert=0
[ -z "$alerts" ] || alert=1

# --- records ------------------------------------------------------------------------
fields=(
    "epoch=$now" "container=$container" "running=$running" "status=$status"
    "restarts=$restarts" "oom=$oom" "exit=$exit_code" "started=$started"
    "mem_bytes=$mem_bytes" "mem_limit=$mem_limit" "cpu_pct=$cpu_pct"
    "datadir=$datadir" "datadir_bytes=$datadir_bytes" "data_free_bytes=$data_free"
    "block=$block" "block_ts=$block_ts" "block_age_s=$block_age"
    "syncing=$syncing" "peers=$peers"
    "cl_running=$cl_running" "cl_is_syncing=$cl_syncing"
    "cl_is_optimistic=$cl_optimistic" "cl_el_offline=$cl_el_offline"
    "cl_head_slot=$cl_head_slot" "cl_head_age_s=$cl_head_age"
    "alert=$alert" "alerts=${alerts:-none}"
)

rotate "$probe_log"
printf '%s %s\n' "$iso" "${fields[*]}" >> "$probe_log"

if [ "$alert" = 1 ]; then
    rotate "$alerts_log"
    for d in "${details[@]}"; do
        printf '%s epoch=%s %s container=%s\n' "$iso" "$now" "$d" "$container" >> "$alerts_log"
    done
fi

{
    printf 'time=%s\n' "$iso"
    printf '%s\n' "${fields[@]}"
} > "$dir/.latest.txt.partial" && mv -f "$dir/.latest.txt.partial" "$dir/latest.txt"

if [ "$restarts" != na ]; then
    printf '%s %s %s\n' "$container" "$restarts" "$started" > "$dir/.probe.state.partial" &&
        mv -f "$dir/.probe.state.partial" "$state_file"
fi
rotate "$dir/probe.err"
exit 0
