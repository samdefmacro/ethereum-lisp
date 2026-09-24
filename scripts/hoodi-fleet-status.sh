#!/usr/bin/env bash
#
# Read-only fleet view of the Section 5 Hoodi host, in one call.
#
# Prints host memory and /data usage, then discovers what is on the host and
# asks the reviewed brokers for their read-only evidence:
#
#   live gate    scripts/hoodi-live-gate.sh status and logs, for every running
#                container labelled agent=codex-sec5-live-gate with a
#                gate-revision label (revision, container name and memory
#                limit are read from that container);
#   Hive gate    scripts/hoodi-hive-gate.sh status, for the newest run runner
#                of each suite (identity read from its run-root label);
#   shadow gate  scripts/hoodi-shadow-gate.sh status.
#
# It never mutates: the only actions it runs are those brokers' documented
# read-only actions, it strips every mutation and privilege allowance from
# their environment, and its own remote script runs only free, df and
# `docker ps`/`docker container inspect`.  No mutation variable is needed.
# One section failing (an older revision not in this checkout, a stopped
# container, a dropped ssh session after three tries) does not hide the
# others; the exit status is non-zero when any section failed.
#
# Environment: HOODI_GATE_HOST (default test-ethereum-sophon2-symbiosis);
# HOODI_GATE_MEMORY_BYTES overrides the discovered live-gate memory limit;
# HOODI_FLEET_SKIP_LOGS=1 omits the live-gate logs summary.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${HOODI_GATE_HOST:-test-ethereum-sophon2-symbiosis}"
skip_logs="${HOODI_FLEET_SKIP_LOGS:-0}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
case "$skip_logs" in 0|1) ;; *) fail "HOODI_FLEET_SKIP_LOGS must be 0 or 1" ;; esac
[ $# -eq 0 ] || { echo "Usage: scripts/hoodi-fleet-status.sh (no arguments; read-only)" >&2; exit 2; }

sections=0
failed=0

# read_only BROKER ARGS...: a sibling broker with every mutation and
# privilege allowance removed from its environment, retried while ssh itself
# fails (exit 255; the VPN drops about one session in four).
read_only() {
    local attempt status
    for attempt in 1 2 3; do
        status=0
        env -u HOODI_GATE_ALLOW_MUTATION -u HOODI_SHADOW_ALLOW_MUTATION \
            -u HOODI_HIVE_NESTED_DOCKER_PRIVILEGED -u HOODI_GATE_ALLOW_SAME_REVISION_PROFILE \
            "$@" || status=$?
        [ "$status" = 255 ] || return "$status"
        echo "fleet-note=ssh-dropped attempt=$attempt" >&2
    done
    return 255
}

# section NAME COMMAND...: run one read-only piece and record its status.
section() {
    local name="$1" status=0
    shift
    echo "==== $name"
    "$@" || status=$?
    echo "section=$name exit=$status"
    sections=$((sections + 1))
    [ "$status" = 0 ] || failed=$((failed + 1))
}

discovery="$(mktemp "${TMPDIR:-/tmp}/hoodi-fleet-status.XXXXXX")"
trap 'rm -f "$discovery"' EXIT

discover() {
    local attempt status
    # The retry loop is spelled out here, not delegated to read_only, so that
    # every attempt re-reads the here-document.
    for attempt in 1 2 3; do
        status=0
        ssh "$host" bash -s > "$discovery" <<'REMOTE' || status=$?
set -eu
date -u +fleet-timestamp=%Y-%m-%dT%H:%M:%SZ
free -b | awk '/^Mem:/ {printf "host-memory total=%s used=%s available=%s\n", $2, $3, $7}'
df -B1 /data | awk 'NR == 2 {printf "host-data total=%s used=%s available=%s utilization=%s\n", $2, $3, $4, $5}'
docker ps --filter label=agent=codex-sec5-live-gate --filter label=io.ethereum-lisp.gate-revision \
    --format '{{.Names}}' |
    while IFS= read -r name || [ -n "$name" ]; do
        docker container inspect --format \
            'discover-live={{.Name}}|{{index .Config.Labels "io.ethereum-lisp.gate-revision"}}|{{.HostConfig.Memory}}' \
            "$name"
    done
# docker ps lists the newest first; keep the newest run runner per suite.
docker ps -a --filter label=io.ethereum-lisp.hive-role=run --format \
    '{{.Names}}|{{.Label "io.ethereum-lisp.hive-revision"}}|{{.Label "io.ethereum-lisp.hive-suite"}}|{{.Label "io.ethereum-lisp.hive-run-root"}}' |
    awk -F'|' '!seen[$3]++ {print "discover-hive=" $0}'
REMOTE
        [ "$status" = 255 ] || break
        echo "fleet-note=ssh-dropped attempt=$attempt" >&2
    done
    grep -v '^discover-' "$discovery" || true
    return "$status"
}

section host discover

live_gate() {
    local name="$1" revision="$2" memory="$3" status=0
    printf 'live-gate container=%s revision=%s memory=%s\n' "$name" "$revision" "$memory"
    read_only env HOODI_GATE_HOST="$host" HOODI_GATE_RUNTIME_REVISION="$revision" \
        HOODI_GATE_CONTAINER="$name" HOODI_GATE_MEMORY_BYTES="$memory" \
        "$repo_root/scripts/hoodi-live-gate.sh" status || status=$?
    if [ "$skip_logs" = 0 ]; then
        read_only env HOODI_GATE_HOST="$host" HOODI_GATE_RUNTIME_REVISION="$revision" \
            HOODI_GATE_CONTAINER="$name" HOODI_GATE_MEMORY_BYTES="$memory" \
            "$repo_root/scripts/hoodi-live-gate.sh" logs || status=$?
    fi
    return "$status"
}

hive_gate() {
    local runner="$1" revision="$2" suite="$3" root="$4" run_id
    run_id="${root##*/}"
    if [[ "$run_id" =~ ^([0-9a-f]{8})-(rpc-compat|engine|devp2p)-full-r([1-9][0-9]{0,3})-([0-9]{8}T[0-9]{6}Z)$ ]] &&
       [ "${BASH_REMATCH[2]}" = "$suite" ] && [ "${BASH_REMATCH[1]}" = "${revision:0:8}" ]; then
        read_only env HOODI_GATE_HOST="$host" HOODI_HIVE_REVISION="$revision" \
            "$repo_root/scripts/hoodi-hive-gate.sh" status \
            --sim "$suite" --run "${BASH_REMATCH[3]}" --stamp "${BASH_REMATCH[4]}"
    else
        echo "hive-runner=$runner unrecognised run root: $run_id" >&2
        return 1
    fi
}

live_found=0
while IFS='|' read -r name revision memory; do
    name="${name#discover-live=}"
    name="${name#/}"
    case "$name" in *[!A-Za-z0-9_.-]*|'') echo "unsafe live container name skipped" >&2; continue ;; esac
    case "$revision" in *[!0-9a-f]*|'') echo "live container $name has no usable revision" >&2; continue ;; esac
    [ "${#revision}" -eq 40 ] || { echo "live container $name has no usable revision" >&2; continue; }
    memory="${HOODI_GATE_MEMORY_BYTES:-$memory}"
    case "$memory" in *[!0-9]*|'') echo "live container $name has no usable memory limit" >&2; continue ;; esac
    live_found=1
    section "live-gate $name" live_gate "$name" "$revision" "$memory"
done < <(grep '^discover-live=' "$discovery" || true)
[ "$live_found" = 1 ] || echo "live-gate=none-running"

hive_found=0
while IFS='|' read -r runner revision suite root; do
    runner="${runner#discover-hive=}"
    case "$runner$suite" in *[!A-Za-z0-9_.-]*|'') echo "unsafe Hive runner skipped" >&2; continue ;; esac
    case "$revision" in *[!0-9a-f]*|'') echo "Hive runner $runner has no usable revision" >&2; continue ;; esac
    [ "${#revision}" -eq 40 ] || { echo "Hive runner $runner has no usable revision" >&2; continue; }
    hive_found=1
    section "hive-gate $runner" hive_gate "$runner" "$revision" "$suite" "$root"
done < <(grep '^discover-hive=' "$discovery" || true)
[ "$hive_found" = 1 ] || echo "hive-gate=no-runs"

section shadow-gate read_only env HOODI_SHADOW_HOST="$host" "$repo_root/scripts/hoodi-shadow-gate.sh" status

echo "fleet-status sections=$sections failed=$failed"
[ "$failed" = 0 ]
