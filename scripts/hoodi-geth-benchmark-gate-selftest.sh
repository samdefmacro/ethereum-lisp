#!/usr/bin/env bash
#
# Network-free self-test for scripts/hoodi-geth-benchmark-gate.sh.
#
# Copies the broker and the log redaction filter into a scratch checkout and
# puts stub git, ssh, docker, curl, chown and sleep first on PATH.  The ssh
# stub runs the broker's remote script with the local bash, moving every
# remote /data/ path below the scratch directory; the docker stub models a
# small daemon (one directory of fields per container).  A modelled Git
# history (STUB_HISTORY, STUB_SIDE) drives the live gate's revision fence and
# the RUNTIME-REVISION marker: every refusal (no mutation flag, a malformed
# revision or allowance, a revision that is not an ancestor of HEAD, a
# runtime-sensitive change since it, a dirty checkout, a source container at
# another revision or on another datadir, a newer, unknown, diverged or
# malformed marker, a marker changed between the read and the restore) is
# paired with an accepted case or the HOODI_GATE_ALLOW_DOWNGRADE override.
# A geth container that dies prints its log masked by
# scripts/hoodi-log-redact.sh.  No stub removes anything, and the last check
# asserts nothing was removed.
#
# Run it from the tests (tests/control-plane-broker-tests.lisp) in the
# project container; it prints one line per check and exits non-zero on any
# failure or if no check ran.

set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hoodi-geth-benchmark-gate-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
bin="$work/bin"
mkdir -p "$repo/scripts" "$bin"
cp "$source_root/scripts/hoodi-geth-benchmark-gate.sh" "$source_root/scripts/hoodi-log-redact.sh" \
    "$repo/scripts/"
broker="$repo/scripts/hoodi-geth-benchmark-gate.sh"

old_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
head_rev=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
newer_rev=cccccccccccccccccccccccccccccccccccccccc
unknown_rev=dddddddddddddddddddddddddddddddddddddddd
side_rev=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
geth_id=sha256:9389d3371a5cde510edb5dfa10a759f7ef98bd8676e6491ce79ab1050306478b

# STUB_HISTORY models one line of commits, oldest first, and STUB_SIDE commits
# known to the checkout but on another line.  STUB_SENSITIVE is what
# `git diff --name-only` reports; STUB_DIRTY=1 makes the checkout dirty.
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
    cat-file)
        rev="${3%%^*}"
        [ "$(pos "$rev")" -gt 0 ] && exit 0
        case " ${STUB_SIDE:-} " in *" $rev "*) exit 0 ;; *) exit 1 ;; esac ;;
    diff)
        case " $* " in
            *" --quiet "*) [ "${STUB_DIRTY:-0}" = 0 ] ;;
            *) printf '%s' "${STUB_SENSITIVE:-}" ;;
        esac ;;
    status) [ "${STUB_DIRTY:-0}" = 0 ] || echo "?? stray" ;;
    *) echo "git stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

# The ssh stub runs the remote script with the local bash; every remote path
# argument under /data/ is moved below STUB_REMOTE_DATA.  STUB_SSH_HOOK runs
# (with sh -c) just before the STUB_SSH_HOOK_CALL-th ssh call.
cat > "$bin/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "$STUB_LOG"
if [ -n "${STUB_SSH_HOOK:-}" ]; then
    calls=$(( $(cat "$STUB_SSH_COUNT" 2>/dev/null || echo 0) + 1 ))
    echo "$calls" > "$STUB_SSH_COUNT"
    [ "$calls" != "${STUB_SSH_HOOK_CALL:-0}" ] || sh -c "$STUB_SSH_HOOK"
fi
shift
args=()
for arg in "$@"; do args+=("${arg//\/data\//$STUB_REMOTE_DATA/}"); done
exec "${args[@]}"
STUB

# A small Docker daemon: one directory per container under STUB_STATE holding
# its labels, image, /data mount, user, state and log.  `docker run --detach`
# creates one (STUB_RUN_DIES: it exits at once; STUB_RUN_LOG: what it logged).
cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
field() { cat "$STUB_STATE/$1/$2" 2>/dev/null || true; }
set_field() { printf '%s\n' "$3" > "$STUB_STATE/$1/$2"; }
last_arg() { for arg; do :; done; printf '%s' "$arg"; }
case "$1" in
    image)
        case "$4" in
            '{{.Id}}') echo "$STUB_IMAGE_ID" ;;
            '{{.Os}}/{{.Architecture}}') echo linux/amd64 ;;
            *) echo "docker stub: unexpected image format $4" >&2; exit 99 ;;
        esac ;;
    network) true ;;
    run)
        case " $* " in *" --rm "*) exit 0 ;; esac
        shift
        name=""; user=""; agent=""; datadir=""; image=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --name) name="$2"; shift ;;
                --user) user="$2"; shift ;;
                --label) case "$2" in agent=*) agent="${2#agent=}" ;; esac; shift ;;
                --mount)
                    case "$2" in
                        *,target=/data) datadir="${2#type=bind,source=}"; datadir="${datadir%,target=/data}" ;;
                    esac
                    shift ;;
                --security-opt|--network|--network-alias|--publish|--cap-drop|--pull) shift ;;
                sha256:*) image="$1"; break ;;
            esac
            shift
        done
        mkdir -p "$STUB_STATE/$name"
        set_field "$name" agent "$agent"; set_field "$name" image "$image"
        set_field "$name" datadir "$datadir"; set_field "$name" user "$user"
        set_field "$name" running true
        [ -z "${STUB_RUN_DIES:-}" ] || set_field "$name" running false
        [ -z "${STUB_RUN_LOG:-}" ] || cp "$STUB_RUN_LOG" "$STUB_STATE/$name/log" ;;
    container)
        name="$(last_arg "$@")"
        [ -d "$STUB_STATE/$name" ] || { echo "Error: No such container: $name" >&2; exit 1; }
        [ "${3:-}" = --format ] || exit 0
        case "$4" in
            'container={{.Name}}'*) echo "container=/$name running=$(field "$name" running) stub-summary" ;;
            '{{ index .Config.Labels "agent" }}') field "$name" agent ;;
            '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}') field "$name" gate ;;
            '{{ index .Config.Labels "org.opencontainers.image.revision" }}') field "$name" image-revision ;;
            '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}') field "$name" datadir ;;
            '{{.Config.User}}') field "$name" user ;;
            '{{.Image}}') field "$name" image ;;
            '{{.State.Running}}') field "$name" running ;;
            *) echo "docker stub: unexpected format $4" >&2; exit 99 ;;
        esac ;;
    stop)
        name="$(last_arg "$@")"
        [ -d "$STUB_STATE/$name" ] || exit 1
        set_field "$name" running false ;;
    start)
        [ -d "$STUB_STATE/$2" ] || exit 1
        set_field "$2" running true ;;
    port)
        [ "$(field "$2" running)" = true ] || exit 1
        echo "127.0.0.1:18545" ;;
    logs) cat "$STUB_STATE/$(last_arg "$@")/log" 2>/dev/null || true ;;
    *) echo "docker stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

# STUB_CURL_FAIL=1: no RPC answers (a node that never came up).
cat > "$bin/curl" <<'STUB'
#!/bin/sh
[ -z "${STUB_CURL_FAIL:-}" ] || exit 7
echo '{"jsonrpc":"2.0","id":1,"result":"0x88bb0"}'
STUB
# The test container cannot chown to the node user; the call is only logged.
cat > "$bin/chown" <<'STUB'
#!/bin/sh
echo "chown $*" >> "$STUB_LOG"
STUB
cat > "$bin/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$bin"/*

export PATH="$bin:$PATH"
export STUB_LOG="$work/stub.log" STUB_STATE="$work/state" STUB_IMAGE_ID="$geth_id"
export STUB_REMOTE_DATA="$work/remote-data" STUB_SSH_COUNT="$work/ssh-count"
all_log="$work/all.log"
: > "$STUB_LOG"; : > "$all_log"

root="$STUB_REMOTE_DATA/hoodi-sec5-20260814"
geth_name=hoodi-geth-v1.17.4-baseline
geth_datadir="$root/geth-v1.17.4-baseline"
source_a=hoodi-el-sec5-aaaaaaaa
source_b=hoodi-el-sec5-bbbbbbbb
datadir_a="$root/datadir-aaaaaaaa"
datadir_b="$root/datadir-bbbbbbbb"
local_a=/data/hoodi-sec5-20260814/datadir-aaaaaaaa
mkdir -p "$STUB_REMOTE_DATA/hoodi/jwt"
echo 00 > "$STUB_REMOTE_DATA/hoodi/jwt/jwt.hex"

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

has() {  # LINE: the last run printed exactly this line.
    if grep -qxF -- "$1" "$out"; then
        record ok "prints: $1"
    else
        echo "missing line: $1" >> "$out"
        record fail "prints: $1"
    fi
}
says() {  # TEXT: the last run printed TEXT somewhere.
    if grep -qF -- "$1" "$out"; then
        record ok "says: $1"
    else
        echo "missing text: $1" >> "$out"
        record fail "says: $1"
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
logged() {  # TEXT: the stub log shows this call.
    if grep -qF -- "$1" "$STUB_LOG"; then
        record ok "calls: $1"
    else
        record fail "calls: $1" "$STUB_LOG"
    fi
}
no_ssh() {
    if grep -q '^ssh ' "$STUB_LOG"; then
        record fail "$1: no remote contact" "$STUB_LOG"
    else
        record ok "$1: no remote contact"
    fi
}
no_lifecycle_call() {
    if grep -qE '^docker (run|start|stop)' "$STUB_LOG"; then
        record fail "$1: no container was started or stopped" "$STUB_LOG"
    else
        record ok "$1: no container was started or stopped"
    fi
}
marker_is() {  # DATADIR WANT DESCRIPTION
    local got
    got="$(cat "$1/RUNTIME-REVISION" 2>/dev/null || echo absent)"
    if [ "$got" = "$2" ]; then
        record ok "$3: the marker reads $2"
    else
        echo "the marker reads $got" > "$work/detail"
        record fail "$3: the marker reads $2" "$work/detail"
    fi
}

reset_world() {
    cat "$STUB_LOG" >> "$all_log"
    rm -rf "$STUB_STATE" "$root" "$STUB_SSH_COUNT"
    mkdir -p "$STUB_STATE/hoodi-lighthouse-public" "$root"
    echo true > "$STUB_STATE/hoodi-lighthouse-public/running"
    unset HOODI_GETH_ALLOW_MUTATION HOODI_GATE_RUNTIME_REVISION HOODI_GATE_ALLOW_DOWNGRADE \
        HOODI_GETH_SOURCE_DATADIR HOODI_GETH_SOURCE_CONTAINER STUB_RUN_DIES STUB_RUN_LOG \
        STUB_SSH_HOOK STUB_SSH_HOOK_CALL STUB_SIDE STUB_SENSITIVE STUB_DIRTY STUB_CURL_FAIL
    export STUB_HEAD="$head_rev" STUB_HISTORY="$old_rev $head_rev $newer_rev"
    : > "$STUB_LOG"
}

# plant_source NAME REVISION DATADIR [RUNNING]: a live-gate EL container.
plant_source() {
    local dir="$STUB_STATE/$1"
    mkdir -p "$dir" "$3"
    echo codex-sec5-live-gate > "$dir/agent"
    echo "$2" > "$dir/gate"; echo "$2" > "$dir/image-revision"
    echo "$3" > "$dir/datadir"; echo 1000:1000 > "$dir/user"
    echo "sha256:runtime-$2" > "$dir/image"; echo "${4:-true}" > "$dir/running"
}
# plant_geth: the benchmark geth container start created, running, with the
# source stopped.
plant_geth() {
    local dir="$STUB_STATE/$geth_name"
    mkdir -p "$dir" "$geth_datadir"
    echo codex-geth-same-host-benchmark > "$dir/agent"
    echo "$geth_id" > "$dir/image"; echo "$geth_datadir" > "$dir/datadir"
    echo 1000:1000 > "$dir/user"; echo true > "$dir/running"
}
plant_marker() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/RUNTIME-REVISION"; }
mutate() { env HOODI_GETH_ALLOW_MUTATION=1 "$@"; }

# --- usage ---------------------------------------------------------------------
reset_world
run 0 "help" -- "$broker" help
says "Usage: scripts/hoodi-geth-benchmark-gate.sh ACTION"
says "HOODI_GATE_RUNTIME_REVISION (default HEAD)"
says "HOODI_GATE_ALLOW_DOWNGRADE=1 overrides that and leaves the newer"
says "HOODI_GETH_SOURCE_DATADIR (default"
says "prints its last 80 log lines with peer"
run 2 "an unknown action" -- "$broker" frobnicate
says "unknown action: frobnicate"
says "Usage: scripts/hoodi-geth-benchmark-gate.sh ACTION"
no_ssh "usage"

# --- the revision fence on the control plane ------------------------------------
reset_world
run 1 "start without the mutation flag" -- "$broker" start
has "ERROR: start changes remote state; set HOODI_GETH_ALLOW_MUTATION=1 after explicit authorization"
run 1 "restore without the mutation flag" -- "$broker" restore
has "ERROR: restore changes remote state; set HOODI_GETH_ALLOW_MUTATION=1 after explicit authorization"
no_ssh "the mutation flag"

run 1 "a malformed runtime revision" -- env HOODI_GATE_RUNTIME_REVISION=HEAD "$broker" status
has "ERROR: revision must be a full lowercase hexadecimal Git id"
run 1 "a short runtime revision" -- env HOODI_GATE_RUNTIME_REVISION=aaaaaaaa "$broker" status
has "ERROR: revision must contain exactly 40 hexadecimal characters"
run 1 "HOODI_GATE_ALLOW_DOWNGRADE=2" -- env HOODI_GATE_ALLOW_DOWNGRADE=2 "$broker" status
has "ERROR: downgrade allowance must be zero or one"
run 1 "a source datadir outside /data/hoodi-sec5-*" -- \
    env HOODI_GETH_SOURCE_DATADIR=/srv/datadir-aaaaaaaa "$broker" status
has "ERROR: source datadir must stay below /data/hoodi-sec5-*: /srv/datadir-aaaaaaaa"
export STUB_SIDE="$side_rev"
run 1 "a runtime revision that is not an ancestor of HEAD" -- \
    env HOODI_GATE_RUNTIME_REVISION="$side_rev" "$broker" status
has "ERROR: runtime revision $side_rev is not an ancestor of checkout HEAD $head_rev"
no_ssh "control-plane refusals"

# A runtime-sensitive change since the runtime revision refuses start and
# restore; status stays available (the control).
reset_world
export HOODI_GATE_RUNTIME_REVISION="$old_rev" STUB_SENSITIVE="src/protocol/p2p/rlpx.lisp"
run 1 "start after a runtime-sensitive change" -- mutate "$broker" start
has "ERROR: checkout changed runtime-sensitive paths after $old_rev: src/protocol/p2p/rlpx.lisp"
run 1 "restore after a runtime-sensitive change" -- mutate "$broker" restore
has "ERROR: checkout changed runtime-sensitive paths after $old_rev: src/protocol/p2p/rlpx.lisp"
no_ssh "runtime-sensitive refusals"
plant_source "$source_b" "$old_rev" "$datadir_b"
run 0 "status after a runtime-sensitive change" -- "$broker" status
has "runtime-revision=$old_rev head=$head_rev source=$source_b source-datadir=/data/hoodi-sec5-20260814/datadir-bbbbbbbb"

reset_world
export STUB_DIRTY=1
run 1 "start from a dirty checkout" -- mutate "$broker" start
has "ERROR: checkout has unstaged changes"
no_ssh "dirty checkout"

# --- start: the source must be the live gate at exactly the runtime revision ----
reset_world
plant_source "$source_a" "$head_rev" "$datadir_a"
run 0 "start from the source at HEAD" -- mutate "$broker" start
has "source=$source_a source-revision=$head_rev source-datadir=$datadir_a"
has "rpc-port=18545 datadir=$geth_datadir source-running=false"
logged "docker stop --time 30 $source_a"
logged "docker run --detach --pull never --name $geth_name"

reset_world
plant_source "$source_a" "$old_rev" "$datadir_a"
run 1 "start from a source at another revision" -- mutate "$broker" start
has "source EL gate revision mismatch: $old_rev, expected $head_rev (HOODI_GATE_RUNTIME_REVISION)"
no_lifecycle_call "source at another revision"

reset_world
plant_source "$source_a" "$head_rev" "$datadir_a"
echo "$old_rev" > "$STUB_STATE/$source_a/image-revision"
run 1 "start from a source whose image is another revision" -- mutate "$broker" start
has "source EL image revision mismatch: $old_rev, expected $head_rev (HOODI_GATE_RUNTIME_REVISION)"
no_lifecycle_call "source image at another revision"

reset_world
plant_source "$source_a" "$head_rev" "$datadir_b"
run 1 "start from a source on another datadir" -- mutate "$broker" start
has "source EL datadir mismatch: $datadir_b, expected $datadir_a (HOODI_GETH_SOURCE_DATADIR)"
no_lifecycle_call "source on another datadir"

reset_world
plant_source "$source_a" "$head_rev" "$datadir_a"
echo codex-somebody-else > "$STUB_STATE/$source_a/agent"
run 1 "start from a source this gate does not own" -- mutate "$broker" start
has "source EL ownership mismatch"
no_lifecycle_call "foreign source"

# The override: an older runtime revision is accepted when every change since
# is outside the runtime (docs, the gate scripts), and then its container and
# datadir are the defaults.
reset_world
plant_source "$source_b" "$old_rev" "$datadir_b"
export HOODI_GATE_RUNTIME_REVISION="$old_rev"
run 0 "start from an older source after docs-only changes" -- mutate "$broker" start
has "source=$source_b source-revision=$old_rev source-datadir=$datadir_b"
logged "docker stop --time 30 $source_b"

# --- start: a geth that dies prints its log masked ------------------------------
pub128=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
id64=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
geth_log="$work/geth.log"
printf '%s\n' \
    "INFO [09-29|12:00:00.000] Started P2P networking self=enode://$pub128@165.154.224.110:30303" \
    "DEBUG[09-29|12:00:01.000] Adding p2p peer id=$id64 addr=203.0.113.7:30303 conn=dyndial" \
    "WARN [09-29|12:00:02.000] Snapshot extension registration failed peer=2001:db8::7 err=timeout" \
    "Fatal: Failed to start the node: listen tcp 127.0.0.1:8545: bind: address already in use" \
    > "$geth_log"
reset_world
plant_source "$source_a" "$head_rev" "$datadir_a"
export STUB_RUN_DIES=1 STUB_RUN_LOG="$geth_log" STUB_CURL_FAIL=1
run 1 "start whose geth dies" -- mutate "$broker" start
has "INFO [09-29|12:00:00.000] Started P2P networking self=enode://01234567…cdef@<addr>"
has "DEBUG[09-29|12:00:01.000] Adding p2p peer id=fedcba98…3210 addr=<ip>:30303 conn=dyndial"
has "WARN [09-29|12:00:02.000] Snapshot extension registration failed peer=<ip> err=timeout"
has "Fatal: Failed to start the node: listen tcp 127.0.0.1:8545: bind: address already in use"
has "geth public RPC did not become ready"
lacks "$pub128"
lacks "$id64"
lacks "165.154.224.110"
lacks "203.0.113.7"
lacks "2001:db8::7"
# The rollback gives the alias back to the source.
logged "docker start $source_a"

# --- restore: the RUNTIME-REVISION marker ----------------------------------------
restore_world() {  # SOURCE-REVISION: a running geth over a stopped source
    reset_world
    plant_source "$source_a" "$1" "$datadir_a" false
    plant_geth
}

restore_world "$head_rev"
plant_marker "$datadir_a" "$head_rev"
run 0 "restore over the source's own marker" -- mutate "$broker" restore
has "runtime-order=same revision=$head_rev source=$local_a/RUNTIME-REVISION"
has "runtime-revision-marker=$head_rev written runtime=$head_rev"
has "source=$source_a running=true geth=$geth_name running=false geth-datadir=$geth_datadir preserved=true alias=hoodi-el-public-36a22e47"
logged "docker stop --time 30 $geth_name"
logged "docker start $source_a"
marker_is "$datadir_a" "$head_rev" "restore"

restore_world "$head_rev"
run 0 "restore over a datadir without a marker" -- mutate "$broker" restore
has "runtime-order=first datadir=$local_a (no marker)"
marker_is "$datadir_a" "$head_rev" "restore without a marker"

restore_world "$head_rev"
plant_marker "$datadir_a" "$old_rev"
run 0 "restore over an older marker" -- mutate "$broker" restore
has "runtime-order=newer revision=$head_rev last=$old_rev source=$local_a/RUNTIME-REVISION"
marker_is "$datadir_a" "$head_rev" "restore over an older marker"

# A newer runtime opened the datadir while geth held the alias: refused ...
restore_world "$head_rev"
plant_marker "$datadir_a" "$newer_rev"
run 1 "restore over a newer marker" -- mutate "$broker" restore
has "ERROR: refusing to start $head_rev on $local_a: $head_rev is older than its last runtime revision $newer_rev ($local_a/RUNTIME-REVISION); a newer runtime may have written what this one cannot read (set HOODI_GATE_ALLOW_DOWNGRADE=1 only after checking that it can)"
no_lifecycle_call "restore over a newer marker"
marker_is "$datadir_a" "$newer_rev" "refused restore"

# ... unless the downgrade is explicitly allowed, and then the marker keeps
# the newer revision.
restore_world "$head_rev"
plant_marker "$datadir_a" "$newer_rev"
export HOODI_GATE_ALLOW_DOWNGRADE=1
run 0 "an allowed restore over a newer marker" -- mutate "$broker" restore
has "runtime-order=downgrade-allowed reason=$head_rev is older than its last runtime revision $newer_rev ($local_a/RUNTIME-REVISION)"
has "runtime-revision-marker=$newer_rev written runtime=$head_rev"
logged "docker start $source_a"
marker_is "$datadir_a" "$newer_rev" "allowed restore"

# A marker this checkout cannot order is refused, and allowed with the
# override (a malformed one is then replaced by the runtime revision).
for kind in unknown side malformed; do
    restore_world "$head_rev"
    case "$kind" in
        unknown)
            plant_marker "$datadir_a" "$unknown_rev"; keep="$unknown_rev"
            want="its last runtime revision $unknown_rev ($local_a/RUNTIME-REVISION) is not a commit in this checkout" ;;
        side)
            export STUB_SIDE="$side_rev"
            plant_marker "$datadir_a" "$side_rev"; keep="$side_rev"
            want="$head_rev does not descend from its last runtime revision $side_rev ($local_a/RUNTIME-REVISION)" ;;
        malformed)
            plant_marker "$datadir_a" not-a-revision; keep="$head_rev"
            want="its marker $local_a/RUNTIME-REVISION is malformed" ;;
    esac
    run 1 "restore over a marker that is $kind" -- mutate "$broker" restore
    says "$want"
    no_lifecycle_call "$kind marker"
    run 0 "an allowed restore over a marker that is $kind" -- \
        mutate env HOODI_GATE_ALLOW_DOWNGRADE=1 "$broker" restore
    says "runtime-order=downgrade-allowed reason=$want"
    marker_is "$datadir_a" "$keep" "allowed restore over a $kind marker"
done

# The host re-reads the marker before stopping anything: a marker written
# between the control plane's read (call 1) and the restore (call 2) is
# refused; the same hook before the read is the control.
restore_world "$head_rev"
plant_marker "$datadir_a" "$head_rev"
export STUB_SSH_HOOK="printf '%s\n' $newer_rev > $datadir_a/RUNTIME-REVISION" STUB_SSH_HOOK_CALL=2
run 1 "a marker written between the read and the restore" -- mutate "$broker" restore
says "RUNTIME-REVISION in $datadir_a changed since the control plane checked it: now $newer_rev, checked $head_rev; nothing was started"
no_lifecycle_call "marker changed under the restore"

restore_world "$head_rev"
plant_marker "$datadir_a" "$head_rev"
export STUB_SSH_HOOK="printf '%s\n' $newer_rev > $datadir_a/RUNTIME-REVISION" STUB_SSH_HOOK_CALL=1
run 1 "a marker written before the read" -- mutate "$broker" restore
says "is older than its last runtime revision $newer_rev ($local_a/RUNTIME-REVISION)"
lacks "changed since the control plane checked it"

# restore keeps the revision fence on the source as well.
restore_world "$old_rev"
run 1 "restore of a source at another revision" -- mutate "$broker" restore
has "source EL gate revision mismatch: $old_rev, expected $head_rev (HOODI_GATE_RUNTIME_REVISION)"
no_lifecycle_call "restore of a source at another revision"

# --- status prints the marker ----------------------------------------------------
restore_world "$head_rev"
run 0 "status of a datadir without a marker" -- "$broker" status
has "runtime-revision=$head_rev head=$head_rev source=$source_a source-datadir=$local_a"
has "source-runtime-revision-marker=absent"
plant_marker "$datadir_a" "$newer_rev"
run 0 "status of a datadir with a marker" -- "$broker" status
has "source-runtime-revision-marker=$newer_rev"
no_lifecycle_call "status"

cat "$STUB_LOG" >> "$all_log"
: > "$out"
if grep -qE '^docker (rm|container rm|image rm|volume|system)' "$all_log"; then
    grep -E '^docker (rm|container rm|image rm|volume|system)' "$all_log" > "$out"
    record fail "no action removes anything"
else
    record ok "no action removes anything"
fi

echo "hoodi-geth-benchmark-gate selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
