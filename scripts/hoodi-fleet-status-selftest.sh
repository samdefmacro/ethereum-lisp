#!/usr/bin/env bash
#
# Network-free self-test for scripts/hoodi-fleet-status.sh.
#
# Copies the fleet script into a scratch checkout next to stub live, Hive and
# shadow brokers that only record how they were called, and puts stub ssh,
# docker, free and df first on PATH (the ssh stub runs the discovery script
# with the local bash).  It checks that the fleet script discovers the live
# container and the newest run runner per suite from their labels, calls only
# the brokers' read-only actions, strips every mutation allowance from their
# environment, retries a dropped ssh session, and keeps reporting the other
# sections when one fails.
#
# Run it from the tests (tests/control-plane-broker-tests.lisp) in the
# project container; it prints one line per check and exits non-zero on any
# failure or if no check ran.

set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hoodi-fleet-status-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
bin="$work/bin"
mkdir -p "$repo/scripts" "$bin"
cp "$source_root/scripts/hoodi-fleet-status.sh" "$repo/scripts/"
fleet="$repo/scripts/hoodi-fleet-status.sh"

live_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
hive_rev=cccccccccccccccccccccccccccccccccccccccc

for broker in hoodi-live-gate.sh hoodi-hive-gate.sh hoodi-shadow-gate.sh; do
    cat > "$repo/scripts/$broker" <<STUB
#!/bin/sh
echo "broker $broker \$* mutation=\${HOODI_GATE_ALLOW_MUTATION:-unset} shadow-mutation=\${HOODI_SHADOW_ALLOW_MUTATION:-unset} privileged=\${HOODI_HIVE_NESTED_DOCKER_PRIVILEGED:-unset} revision=\${HOODI_GATE_RUNTIME_REVISION:-}\${HOODI_HIVE_REVISION:-} container=\${HOODI_GATE_CONTAINER:-} memory=\${HOODI_GATE_MEMORY_BYTES:-} host=\${HOODI_GATE_HOST:-}\${HOODI_SHADOW_HOST:-}" >> "\$STUB_LOG"
echo "stub $broker \$1"
case "$broker" in
    hoodi-live-gate.sh) [ "\${STUB_LIVE_FAIL:-0}" = 0 ] || { echo "FAIL: stub live gate" >&2; exit 1; } ;;
esac
exit 0
STUB
done

cat > "$bin/ssh" <<'STUB'
#!/bin/sh
echo "ssh $*" >> "$STUB_LOG"
if [ "${STUB_SSH_DROPS:-0}" -gt 0 ]; then
    dropped="$(cat "$STUB_DROP_COUNT" 2>/dev/null || echo 0)"
    if [ "$dropped" -lt "$STUB_SSH_DROPS" ]; then
        echo $((dropped + 1)) > "$STUB_DROP_COUNT"
        cat > /dev/null
        echo "ssh: connection reset" >&2
        exit 255
    fi
fi
shift
exec "$@"
STUB

cat > "$bin/docker" <<'STUB'
#!/bin/sh
echo "docker $*" >> "$STUB_LOG"
case "$1 $2" in
    "ps --filter") printf '%s' "${STUB_LIVE_NAMES:-}" ;;
    "container inspect")
        for arg; do name="$arg"; done
        echo "discover-live=/$name|$STUB_LIVE_REV|12884901888" ;;
    "ps -a") cat "$STUB_HIVE_RUNNERS" ;;
    *) echo "docker stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

cat > "$bin/free" <<'STUB'
#!/bin/sh
echo "               total        used        free      shared  buff/cache   available"
echo "Mem:     16765079552  3343441920  1000000000           0  1000000000 13066436608"
STUB

cat > "$bin/df" <<'STUB'
#!/bin/sh
echo "Filesystem 1B-blocks Used Available Use% Mounted on"
echo "/dev/vdb 738678194176 589851533312 116576686080 84% /data"
STUB
chmod +x "$bin"/* "$repo"/scripts/*

hive_runners="$work/hive-runners"
cat > "$hive_runners" <<RUNNERS
sec5-hive-cccccccc-engine-full-r2|$hive_rev|engine|/data/hoodi-sec5-hive/runs/cccccccc-engine-full-r2-20260924T010000Z
sec5-hive-cccccccc-devp2p-full-r1|$hive_rev|devp2p|/data/hoodi-sec5-hive/runs/cccccccc-devp2p-full-r1-20260923T230000Z
sec5-hive-cccccccc-engine-full-r1|$hive_rev|engine|/data/hoodi-sec5-hive/runs/cccccccc-engine-full-r1-20260923T200000Z
RUNNERS

export PATH="$bin:$PATH"
export STUB_LOG="$work/stub.log" STUB_HIVE_RUNNERS="$hive_runners" STUB_DROP_COUNT="$work/drops"

checks=0
failures=0
out="$work/out"

reset_world() {
    export STUB_LIVE_NAMES="hoodi-el-sec5-bbbbbbbb" STUB_LIVE_REV="$live_rev"
    export STUB_LIVE_FAIL=0 STUB_SSH_DROPS=0
    unset HOODI_GATE_MEMORY_BYTES HOODI_FLEET_SKIP_LOGS
    rm -f "$STUB_DROP_COUNT"
    : > "$STUB_LOG"
}

record() {
    checks=$((checks + 1))
    if [ "$1" = ok ]; then
        echo "ok $checks - $2"
    else
        failures=$((failures + 1))
        echo "not ok $checks - $2"
        sed 's/^/#   /' "$out"
        sed 's/^/#   log: /' "$STUB_LOG"
    fi
}

run() {  # STATUS DESCRIPTION -- COMMAND...
    local want="$1" description="$2" status=0
    shift 3
    "$@" > "$out" 2>&1 || status=$?
    if [ "$status" = "$want" ]; then record ok "$description exits $want"; else
        echo "exit $status, wanted $want" >> "$out"; record fail "$description exits $want"; fi
}

prints() {
    if grep -qxF -- "$1" "$out"; then record ok "prints: $1"; else record fail "prints: $1"; fi
}

logged() {  # the stub log holds a line containing TEXT
    if grep -qF -- "$1" "$STUB_LOG"; then record ok "calls: $1"; else record fail "calls: $1"; fi
}

not_logged() {
    if grep -qF -- "$1" "$STUB_LOG"; then record fail "never calls: $1"; else record ok "never calls: $1"; fi
}

# --- a healthy host ---------------------------------------------------------------
reset_world
run 0 "fleet status" -- env HOODI_GATE_ALLOW_MUTATION=1 HOODI_SHADOW_ALLOW_MUTATION=1 \
    HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 "$fleet"
prints "host-memory total=16765079552 used=3343441920 available=13066436608"
prints "host-data total=738678194176 used=589851533312 available=116576686080 utilization=84%"
prints "live-gate container=hoodi-el-sec5-bbbbbbbb revision=$live_rev memory=12884901888"
logged "broker hoodi-live-gate.sh status mutation=unset shadow-mutation=unset privileged=unset revision=$live_rev container=hoodi-el-sec5-bbbbbbbb memory=12884901888 host=test-ethereum-sophon2-symbiosis"
logged "broker hoodi-live-gate.sh logs mutation=unset"
logged "broker hoodi-hive-gate.sh status --sim engine --run 2 --stamp 20260924T010000Z mutation=unset shadow-mutation=unset privileged=unset revision=$hive_rev"
logged "broker hoodi-hive-gate.sh status --sim devp2p --run 1 --stamp 20260923T230000Z"
not_logged "--run 1 --stamp 20260923T200000Z"
logged "broker hoodi-shadow-gate.sh status mutation=unset shadow-mutation=unset privileged=unset"
prints "fleet-status sections=5 failed=0"
# Only read-only actions reach a broker.
if grep '^broker ' "$STUB_LOG" | awk '{print $3}' | grep -qvxE 'status|logs'; then
    cp "$STUB_LOG" "$out"; record fail "only status and logs are called"
else
    record ok "only status and logs are called"
fi

# --- overrides and options -------------------------------------------------------------
reset_world
export HOODI_GATE_MEMORY_BYTES=8589934592 HOODI_FLEET_SKIP_LOGS=1
run 0 "fleet status with overrides" -- "$fleet"
logged "broker hoodi-live-gate.sh status mutation=unset shadow-mutation=unset privileged=unset revision=$live_rev container=hoodi-el-sec5-bbbbbbbb memory=8589934592"
not_logged "broker hoodi-live-gate.sh logs"
reset_world
run 2 "an argument" -- "$fleet" stop
not_logged "ssh "
run 1 "an unsafe host" -- env HOODI_GATE_HOST='bad host' "$fleet"

# --- nothing running --------------------------------------------------------------------
reset_world
export STUB_LIVE_NAMES=""
run 0 "fleet status with no live EL" -- "$fleet"
prints "live-gate=none-running"
not_logged "broker hoodi-live-gate.sh"

# --- one section failing does not hide the others ----------------------------------------
reset_world
export STUB_LIVE_FAIL=1
run 1 "fleet status with a failing live gate" -- "$fleet"
prints "fleet-status sections=5 failed=1"
logged "broker hoodi-shadow-gate.sh status"

# --- a dropped ssh session is retried -----------------------------------------------------
reset_world
export STUB_SSH_DROPS=1
run 0 "fleet status after one dropped session" -- "$fleet"
prints "fleet-note=ssh-dropped attempt=1"
prints "host-memory total=16765079552 used=3343441920 available=13066436608"
reset_world
export STUB_SSH_DROPS=5
run 1 "fleet status when every session drops" -- "$fleet"
prints "section=host exit=255"

# --- an unrecognised run root is reported, not guessed ---------------------------------------
reset_world
cp "$hive_runners" "$hive_runners.good"
echo "sec5-hive-cccccccc-rpc-compat-full-r1|$hive_rev|rpc-compat|/data/elsewhere/odd-run" > "$hive_runners"
run 1 "fleet status with an odd run root" -- "$fleet"
if grep -qF "unrecognised run root: odd-run" "$out"; then record ok "names the odd run root"; else record fail "names the odd run root"; fi
not_logged "broker hoodi-hive-gate.sh"
cp "$hive_runners.good" "$hive_runners"

echo "hoodi-fleet-status selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
