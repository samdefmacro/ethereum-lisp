#!/usr/bin/env bash
set -euo pipefail

# Read-only control-plane broker for the unattended Hoodi health probe
# (scripts/hoodi-health-probe.sh).  The probe runs on the remote host every
# five minutes and writes only below REMOTE_ROOT/health; this broker reads
# what it recorded.  It never starts, stops or removes a container, an image
# or a datadir, never writes on the remote host, and never deletes a probe
# record.  Scheduling the probe on the host is not part of this broker.
#
# The revision fence is the live gate's: the watched container (default
# hoodi-el-sec5-<rev8>) belongs to the runtime revision
# HOODI_GATE_RUNTIME_REVISION (default HEAD), which must be the checkout's HEAD
# or an ancestor of it.  Output that crosses the broker is piped through
# scripts/hoodi-log-redact.sh on the remote host; the probe records no peer
# identity in the first place.  The stubbed self-test is
# scripts/hoodi-health-gate-selftest.sh.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-status}"

usage() {
    cat <<'USAGE'
Usage: scripts/hoodi-health-gate.sh ACTION [HOURS]

Read-only actions:
  status       the probe's latest.txt, the tail of ALERTS.log, whether a
               crontab line for the probe is present, whether the installed
               probe matches this checkout, and probe-stale=true when
               latest.txt is older than 15 minutes
  report [N]   a summary of probe.log (and probe.log.1) over the last N hours
               (default 24): samples, block advance, min/max block rate per
               minute, memory peak, peers min/max, block age max, /data free
               min, restarts, and alert counts by condition

Environment:
  HOODI_GATE_HOST                   SSH host (default test-ethereum-server)
  HOODI_GATE_REMOTE_ROOT            below /data/hoodi-sec5-* (default
                                    /data/hoodi-sec5-20260814); the probe
                                    writes REMOTE_ROOT/health only
  HOODI_GATE_RUNTIME_REVISION       full runtime revision (default HEAD)
  HOODI_GATE_CONTAINER              EL container (default hoodi-el-sec5-<rev8>)
  HOODI_HEALTH_ALERT_TAIL           ALERTS.log lines status prints (20)

Files on the host (REMOTE_ROOT/health): hoodi-health-probe.sh, probe.log
(one line per run), probe.log.1, latest.txt, ALERTS.log (one line per alert
condition), ALERTS.log.1, probe.err.
USAGE
}

case "$action" in
    status|report) ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "unknown action: $action" >&2; usage >&2; exit 2 ;;
esac

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

report_hours="${2:-24}"
case "$report_hours" in *[!0-9]*|'') fail "report hours must be an integer" ;; esac
[ "$report_hours" -ge 1 ] && [ "$report_hours" -le 8760 ] ||
    fail "report hours must be between 1 and 8760"

actual_head="$(git -C "$repo_root" rev-parse HEAD)"
revision="${HOODI_GATE_RUNTIME_REVISION:-$actual_head}"
case "$revision" in
    *[!0-9a-f]*|'') fail "revision must be a full lowercase hexadecimal Git id" ;;
esac
[ "${#revision}" -eq 40 ] || fail "revision must contain exactly 40 hexadecimal characters"
short_revision="${revision:0:8}"

host="${HOODI_GATE_HOST:-test-ethereum-server}"
remote_root="${HOODI_GATE_REMOTE_ROOT:-/data/hoodi-sec5-20260814}"
container="${HOODI_GATE_CONTAINER:-hoodi-el-sec5-${short_revision}}"
alert_tail="${HOODI_HEALTH_ALERT_TAIL:-20}"
probe_script="$repo_root/scripts/hoodi-health-probe.sh"
log_redact_lib="$repo_root/scripts/hoodi-log-redact.sh"

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$remote_root" in
    *[!A-Za-z0-9_./-]*|*..*|*//*|*/) fail "remote root must be a normalized path of plain characters: $remote_root" ;;
    /data/hoodi-sec5-*) ;;
    *) fail "remote root must stay below /data/hoodi-sec5-*: $remote_root" ;;
esac
health_dir="$remote_root/health"
case "$container" in *[!A-Za-z0-9_.-]*|'') fail "unsafe Docker name: $container" ;; esac
case "$alert_tail" in *[!0-9]*|'') fail "alert tail must be a non-negative integer: $alert_tail" ;; esac
[ -f "$probe_script" ] || fail "probe is absent: $probe_script"
[ -f "$log_redact_lib" ] || fail "log redaction filter is absent: $log_redact_lib"

# The live gate's revision fence: the runtime revision must be the checkout's
# HEAD or an ancestor of it.
if [ "$actual_head" != "$revision" ]; then
    git -C "$repo_root" merge-base --is-ancestor "$revision" "$actual_head" ||
        fail "runtime revision $revision is not an ancestor of checkout HEAD $actual_head"
fi

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail "sha256sum or shasum is required"
    fi
}

# Functions the remote scripts share.  (A function that prints them, not a
# $(...) capture: bash would otherwise parse the heredoc's comments for
# quotes while scanning the substitution.)
print_remote_lib() {
    cat <<'LIB'
gate_fail() {
    echo "$*" >&2
    exit 1
}
LIB
}

# remote ARG...: run the remote script on stdin, after the shared functions
# and the log redaction filter, with the given positional arguments (none of
# which may contain whitespace: ssh joins them into one command line).
remote() {
    { print_remote_lib; cat "$log_redact_lib"; cat; } | ssh "$host" bash -s -- "$@"
}

status() {
    local expected_sha
    expected_sha="$(sha256_file "$probe_script")"
    printf 'runtime-revision=%s head=%s container=%s health-dir=%s\n' \
        "$revision" "$actual_head" "$container" "$health_dir"
    remote "$health_dir" "$expected_sha" "$alert_tail" <<'REMOTE'
set -eu
dir="$1"; expected_sha="$2"; alert_tail="$3"
{
# crontab -l only reads.  A line is the probe's when it names the probe.
if listing="$(crontab -l 2>&1)"; then
    lines="$(printf '%s\n' "$listing" | grep -v '^[[:space:]]*#' | grep -cF -- "$dir/hoodi-health-probe.sh" || true)"
    if [ "$lines" -gt 0 ]; then
        echo "cron-line=present count=$lines"
    else
        echo "cron-line=absent"
    fi
else
    case "$listing" in
        "no crontab for "*) echo "cron-line=absent (no crontab)" ;;
        *) echo "cron-line=unreadable" ;;
    esac
fi
if [ -f "$dir/hoodi-health-probe.sh" ]; then
    installed_sha="$(sha256sum "$dir/hoodi-health-probe.sh" | awk '{print $1}')"
    if [ "$installed_sha" = "$expected_sha" ]; then
        echo "probe=installed matches-checkout=true"
    else
        echo "probe=installed matches-checkout=false sha256=$installed_sha"
    fi
else
    echo "probe=absent"
fi
if [ -f "$dir/latest.txt" ]; then
    now="$(date -u +%s)"
    epoch="$(sed -n 's/^epoch=//p' "$dir/latest.txt" | head -n 1)"
    case "$epoch" in
        ''|*[!0-9]*) echo "latest-age-s=unknown probe-stale=true" ;;
        *) age=$(( now - epoch ))
           if [ "$age" -gt 900 ]; then stale=true; else stale=false; fi
           echo "latest-age-s=$age probe-stale=$stale" ;;
    esac
    sed 's/^/latest: /' "$dir/latest.txt"
else
    echo "latest=absent"
fi
if [ -f "$dir/ALERTS.log" ]; then
    echo "alerts-logged=$(wc -l < "$dir/ALERTS.log" | tr -d ' ')"
    tail -n "$alert_tail" "$dir/ALERTS.log" | sed 's/^/alert: /'
else
    echo "alerts-logged=0"
fi
} | hoodi_redact_peer_identities
REMOTE
}

report() {
    printf 'health-dir=%s window-hours=%s\n' "$health_dir" "$report_hours"
    remote "$health_dir" "$report_hours" <<'REMOTE'
set -eu
dir="$1"; hours="$2"
cutoff=$(( $(date -u +%s) - hours * 3600 ))
files=""
for f in "$dir/probe.log.1" "$dir/probe.log"; do [ ! -f "$f" ] || files="$files $f"; done
[ -n "$files" ] || gate_fail "no probe.log in $dir: has the probe run?"
{
# shellcheck disable=SC2086
awk -v cutoff="$cutoff" '
function num(v) { return v ~ /^-?[0-9]+(\.[0-9]+)?$/ }
function show(v) { return v == "" ? "na" : v }
function rate2(v) { return v == "" ? "na" : sprintf("%.2f", v) }
{
    split("", f)
    for (i = 2; i <= NF; i++) {
        eq = index($i, "=")
        if (eq > 0) f[substr($i, 1, eq - 1)] = substr($i, eq + 1)
    }
    if (!num(f["epoch"]) || f["epoch"] + 0 < cutoff) next
    samples++
    if (samples == 1) first = $1
    last = $1
    if ("skipped" in f) { skipped++; next }
    if (f["alert"] == "1") alert_samples++
    if (f["running"] != "true") not_running++
    if (num(f["block"])) {
        b = f["block"] + 0; e = f["epoch"] + 0
        if (block_first == "") block_first = b
        block_last = b
        if (prev_block != "" && e > prev_epoch) {
            rate = (b - prev_block) * 60 / (e - prev_epoch)
            if (rate_min == "" || rate < rate_min) rate_min = rate
            if (rate_max == "" || rate > rate_max) rate_max = rate
        }
        prev_block = b; prev_epoch = e
    }
    if (num(f["mem_bytes"]) && (mem_peak == "" || f["mem_bytes"] + 0 > mem_peak)) mem_peak = f["mem_bytes"] + 0
    if (num(f["peers"])) {
        p = f["peers"] + 0
        if (peers_min == "" || p < peers_min) peers_min = p
        if (peers_max == "" || p > peers_max) peers_max = p
    }
    if (num(f["block_age_s"]) && (age_max == "" || f["block_age_s"] + 0 > age_max)) age_max = f["block_age_s"] + 0
    if (num(f["data_free_bytes"]) && (free_min == "" || f["data_free_bytes"] + 0 < free_min)) free_min = f["data_free_bytes"] + 0
    if (num(f["restarts"])) { if (restarts_first == "") restarts_first = f["restarts"]; restarts_last = f["restarts"] }
}
END {
    printf "samples=%d skipped=%d first=%s last=%s\n", samples, skipped, show(first), show(last)
    printf "block-first=%s block-last=%s block-advance=%s\n", show(block_first), show(block_last), \
        (block_first == "" ? "na" : block_last - block_first)
    printf "block-rate-per-min min=%s max=%s\n", rate2(rate_min), rate2(rate_max)
    printf "block-age-max-s=%s mem-peak-bytes=%s peers-min=%s peers-max=%s data-free-min-bytes=%s\n", \
        show(age_max), show(mem_peak), show(peers_min), show(peers_max), show(free_min)
    printf "restarts-first=%s restarts-last=%s not-running-samples=%d alert-samples=%d\n", \
        show(restarts_first), show(restarts_last), not_running, alert_samples
}' $files
alert_files=""
for f in "$dir/ALERTS.log.1" "$dir/ALERTS.log"; do [ ! -f "$f" ] || alert_files="$alert_files $f"; done
if [ -n "$alert_files" ]; then
    # shellcheck disable=SC2086
    awk -v cutoff="$cutoff" '
    {
        e = ""; c = ""
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^epoch=/) e = substr($i, 7)
            if ($i ~ /^condition=/) c = substr($i, 11)
        }
        if (e == "" || e + 0 < cutoff) next
        n++; by[c]++
    }
    END {
        printf "alert-lines=%d\n", n
        for (c in by) printf "alert-condition=%s count=%d\n", c, by[c]
    }' $alert_files | sort
else
    echo "alert-lines=0"
fi
} | hoodi_redact_peer_identities
REMOTE
}

case "$action" in
    status) status ;;
    report) report ;;
esac
