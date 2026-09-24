#!/usr/bin/env bash
#
# Network-free self-test for scripts/hoodi-hive-gate.sh.
#
# Copies the broker and its remote half into a scratch checkout and puts stub
# git, ssh, scp, docker, free and df first on PATH.  The ssh stub runs the
# broker's remote script with the local bash, so the refusal checks that live
# in the remote half (memory, disk, live EL, other runners, existing
# containers) run for real against stubbed Docker and host state.  Every
# refusal is paired with a positive control proving the same fixture passes
# that gate and stops at the next one, so a refusal cannot pass vacuously.
# No stub ever lets `docker run`, `docker image load` or scp happen: the
# final check asserts none of them was reached.
#
# Run it from the tests (tests/control-plane-broker-tests.lisp) in the
# project container; it prints one line per check and exits non-zero on any
# failure or if no check ran.

set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hoodi-hive-gate-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
bin="$work/bin"
mkdir -p "$repo/scripts" "$bin"
cp "$source_root/scripts/hoodi-hive-gate.sh" "$source_root/scripts/hoodi-hive-gate-remote.sh" "$repo/scripts/"
broker="$repo/scripts/hoodi-hive-gate.sh"

head_rev=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
old_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
gib=1073741824

cat > "$bin/git" <<'STUB'
#!/bin/sh
[ "$1" = -C ] && shift 2
case "$1" in
    rev-parse) echo "$STUB_HEAD" ;;
    merge-base) [ "${STUB_ANCESTOR:-1}" = 1 ] ;;
    diff)
        case " $* " in
            *" --quiet "*) [ "${STUB_DIRTY:-0}" = 0 ] ;;
            *) printf '%s' "${STUB_SENSITIVE:-}" ;;
        esac ;;
    status) [ "${STUB_DIRTY:-0}" = 0 ] || echo "?? stray" ;;
    archive) printf 'archive-%s' "$3" ;;
    *) echo "git stub: unexpected $*" >&2; exit 99 ;;
esac
STUB

cat > "$bin/ssh" <<'STUB'
#!/bin/sh
echo "ssh $*" >> "$STUB_LOG"
# The tar-upload checks stop at the first remote contact.
[ "${STUB_SSH_REFUSE:-0}" = 0 ] || { echo "ssh stub: remote contact refused" >&2; exit 97; }
shift
exec "$@"
STUB

cat > "$bin/scp" <<'STUB'
#!/bin/sh
echo "scp $*" >> "$STUB_LOG"
STUB

cat > "$bin/docker" <<'STUB'
#!/bin/sh
echo "docker $*" >> "$STUB_LOG"
# A control plane whose Docker Desktop is down.
[ "${STUB_DOCKER_DOWN:-0}" = 0 ] || { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
case "$1 $2" in
    "container inspect")
        for name in "$@"; do last="$name"; done
        case " ${STUB_CONTAINERS:-} " in
            *" $last "*)
                if [ "${3:-}" = --format ] && [ "${4:-}" = '{{.State.Running}}' ]; then
                    echo "${STUB_RUNNING:-false}"
                else
                    echo "runner=$last running=${STUB_RUNNING:-false}"
                fi ;;
            *) exit 1 ;;
        esac ;;
    "image inspect")
        [ "${STUB_IMAGES_ABSENT:-0}" = 0 ] || exit 1
        case "$*" in
            *image.revision*) echo "${STUB_IMAGE_REVISION:-$STUB_HEAD}" ;;
            *Architecture*) echo linux/amd64 ;;
            *) echo image-present ;;
        esac ;;
    "ps --filter")
        case "$*" in
            *io.ethereum-lisp.gate-revision*) printf '%s' "${STUB_LIVE_EL:-}" ;;
            *io.ethereum-lisp.hive-role*) printf '%s' "${STUB_RUNNERS:-}" ;;
        esac ;;
    "ps --format") echo "container=hoodi-lighthouse-public" ;;
    *) ;;
esac
STUB

cat > "$bin/free" <<'STUB'
#!/bin/sh
echo "               total        used        free      shared  buff/cache   available"
echo "Mem:     16106127360  1000000000  1000000000           0  1000000000 $STUB_AVAIL"
STUB

cat > "$bin/df" <<'STUB'
#!/bin/sh
case "$*" in
    *--output=avail*) echo "Avail"; echo "$STUB_DISK" ;;
    *) echo "Filesystem 1B-blocks Used Available Use% Mounted on"; echo "/dev/stub 1 1 $STUB_DISK 1% /data" ;;
esac
STUB
chmod +x "$bin"/*

source_tar="$work/ethereum-lisp-source-aaaaaaaa.tar"
runtime_tar="$work/ethereum-lisp-runtime-sec5-aaaaaaaa-amd64.tar"
printf 'archive-%s' "$head_rev" > "$source_tar"
printf 'runtime' > "$runtime_tar"

export PATH="$bin:$PATH"
export STUB_LOG="$work/stub.log"
: > "$STUB_LOG"

checks=0
failures=0
out="$work/out"

# Reset the stubbed world to a healthy host: plenty of memory and disk, no
# live EL, no runner, images present, clean checkout at HEAD.
reset_world() {
    export STUB_HEAD="$head_rev" STUB_ANCESTOR=1 STUB_SENSITIVE="" STUB_DIRTY=0
    export STUB_AVAIL=$((12 * gib)) STUB_DISK=$((40 * gib))
    export STUB_LIVE_EL="" STUB_RUNNERS="" STUB_CONTAINERS="" STUB_RUNNING=false
    export STUB_IMAGES_ABSENT=0 STUB_DOCKER_DOWN=0 STUB_SSH_REFUSE=0
    unset HOODI_HIVE_REVISION HOODI_GATE_ALLOW_MUTATION HOODI_HIVE_NESTED_DOCKER_PRIVILEGED
    unset HOODI_HIVE_IMAGE_TAR HOODI_HIVE_IMAGE_SHA256
    export HOODI_HIVE_SOURCE_ARTIFACT="$source_tar" HOODI_HIVE_RUNTIME_ARTIFACT="$runtime_tar"
    export HOODI_HIVE_COLLECT_DIR="$work/collect"
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
    fi
}

# expect STATUS SUBSTRING DESCRIPTION -- COMMAND...
# STATUS is 0, 1, or 2.  SUBSTRING must appear in the combined output.
expect() {
    local want="$1" text="$2" description="$3" status=0
    shift 4
    "$@" > "$out" 2>&1 || status=$?
    if [ "$status" = "$want" ] && grep -qF -- "$text" "$out"; then
        record ok "$description"
    else
        echo "exit $status, wanted $want and '$text'" >> "$out"
        record fail "$description"
    fi
}

# The log must not show any remote contact (for local refusals) or any
# mutation beyond the checks (for remote refusals).
expect_no_ssh() {
    if grep -q '^ssh ' "$STUB_LOG"; then
        cp "$STUB_LOG" "$out"; record fail "$1: no ssh"
    else
        record ok "$1: no ssh"
    fi
}

expect_no_mutation() {
    if grep -qE '^docker (run|image load|container rm|rm|stop)|^scp ' "$STUB_LOG"; then
        cp "$STUB_LOG" "$out"; record fail "$1: no remote mutation"
    else
        record ok "$1: no remote mutation"
    fi
}

id="--run 3 --stamp 20260923T120000Z"
mut() { env HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 "$@"; }

# --- argument parsing ----------------------------------------------------------
reset_world
expect 2 "Usage:" "no action prints usage" -- "$broker"
expect 2 "unknown action" "unknown action" -- "$broker" frobnicate
expect 2 "unknown argument" "unknown option" -- "$broker" status --bogus
expect 1 "requires --sim" "run without a suite" -- "$broker" run
expect 1 "unknown suite" "unknown suite" -- "$broker" run --sim sync $id
# shellcheck disable=SC2086
expect 1 "requires --stamp" "run without a stamp" -- "$broker" run --sim engine --run 3
expect 1 "positive integer" "leading-zero ordinal" -- "$broker" status --sim engine --run 03 --stamp 20260923T120000Z
expect 1 "UTC timestamp" "malformed stamp" -- "$broker" status --sim engine --run 3 --stamp 2026-09-23
expect 1 "takes no run identity" "upload with a run identity" -- "$broker" upload --sim engine
expect 1 "either no run identity" "inspect with a partial identity" -- "$broker" inspect --sim engine
expect 0 "Usage:" "help exits zero" -- "$broker" --help
expect_no_ssh "argument refusals"

# --- mutation flag, privilege acknowledgement, clean checkout ------------------
reset_world
for act in upload "prepare --sim engine $id" "run --sim engine $id"; do
    # shellcheck disable=SC2086
    expect 1 "HOODI_GATE_ALLOW_MUTATION=1" "$act without the mutation flag" -- "$broker" $act
done
# shellcheck disable=SC2086
expect 1 "HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1" "run without the privilege acknowledgement" -- \
    env HOODI_GATE_ALLOW_MUTATION=1 "$broker" run --sim engine $id
# shellcheck disable=SC2086
expect 1 "HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1" "prepare without the privilege acknowledgement" -- \
    env HOODI_GATE_ALLOW_MUTATION=1 "$broker" prepare --sim devp2p $id
export STUB_DIRTY=1
# shellcheck disable=SC2086
expect 1 "unstaged changes" "run from a dirty checkout" -- mut "$broker" run --sim engine $id
expect_no_ssh "local mutation refusals"

# --- revision fence ------------------------------------------------------------
reset_world
export HOODI_HIVE_REVISION="$old_rev" STUB_ANCESTOR=0
expect 1 "is not an ancestor" "non-ancestor revision refused even for inspect" -- "$broker" inspect
export STUB_ANCESTOR=1 STUB_SENSITIVE="src/cli/devnet.lisp"
# shellcheck disable=SC2086
expect 1 "runtime-sensitive paths" "ancestor with runtime changes refused for run" -- mut "$broker" run --sim engine $id
expect 1 "runtime-sensitive paths" "ancestor with runtime changes refused for upload" -- mut "$broker" upload
expect_no_ssh "revision refusals"
# Positive control: the same revision still serves read-only evidence.
expect 0 "live-el-running=none" "ancestor revision still inspects read-only" -- "$broker" inspect
export STUB_SENSITIVE=""
# shellcheck disable=SC2086
expect 1 "is not prepared" "docs-only ancestor passes the fence" -- mut "$broker" run --sim rpc-compat $id

# --- memory precondition -------------------------------------------------------
reset_world
export STUB_AVAIL=$((7 * gib))
# shellcheck disable=SC2086
expect 1 "REFUSE: MemAvailable" "engine refused below 8 GiB" -- mut "$broker" run --sim engine $id
# shellcheck disable=SC2086
expect 1 "REFUSE: MemAvailable" "devp2p refused below 8 GiB" -- mut "$broker" run --sim devp2p $id
export STUB_AVAIL=$((4 * gib))
# shellcheck disable=SC2086
expect 1 "REFUSE: MemAvailable" "rpc-compat refused below 4.5 GiB" -- mut "$broker" run --sim rpc-compat $id
# shellcheck disable=SC2086
expect 1 "REFUSE: MemAvailable" "prepare refused below 4.5 GiB" -- mut "$broker" prepare --sim rpc-compat $id
expect_no_mutation "memory refusals"
export STUB_AVAIL=$((9 * gib))
# shellcheck disable=SC2086
expect 1 "is not prepared" "engine passes the memory gate at 9 GiB" -- mut "$broker" run --sim engine $id
export STUB_AVAIL=$((5 * gib))
# shellcheck disable=SC2086
expect 1 "is not prepared" "rpc-compat passes the memory gate at 5 GiB" -- mut "$broker" run --sim rpc-compat $id

# --- live EL sequencing --------------------------------------------------------
reset_world
export STUB_LIVE_EL=hoodi-el-sec5-8e95b990
# shellcheck disable=SC2086
expect 1 "REFUSE: live EL hoodi-el-sec5-8e95b990 is running" "engine refused beside the live EL" -- \
    mut "$broker" run --sim engine $id
# shellcheck disable=SC2086
expect 1 "REFUSE: live EL" "devp2p refused beside the live EL" -- mut "$broker" run --sim devp2p $id
expect_no_mutation "live-EL refusals"
# shellcheck disable=SC2086
expect 1 "is not prepared" "rpc-compat may run beside the live EL" -- mut "$broker" run --sim rpc-compat $id
# shellcheck disable=SC2086
expect 1 "staged source archive is absent" "engine prepare is not blocked by the live EL" -- \
    mut "$broker" prepare --sim engine $id
export STUB_LIVE_EL=""
# shellcheck disable=SC2086
expect 1 "is not prepared" "engine passes once the EL is stopped" -- mut "$broker" run --sim engine $id

# --- disk, other runners, existing containers, runner image -------------------
reset_world
export STUB_DISK=$((8 * gib))
# shellcheck disable=SC2086
expect 1 "REFUSE: /data has" "run refused below 12 GiB of /data" -- mut "$broker" run --sim rpc-compat $id
export STUB_DISK=$((40 * gib)) STUB_RUNNERS=sec5-hive-aaaaaaaa-rpc-compat-full-r2
# shellcheck disable=SC2086
expect 1 "REFUSE: another Hive runner" "run refused beside another runner" -- mut "$broker" run --sim rpc-compat $id
export STUB_RUNNERS="" STUB_CONTAINERS=sec5-hive-aaaaaaaa-engine-full-r3
# shellcheck disable=SC2086
expect 1 "already exists" "run refused for an existing container" -- mut "$broker" run --sim engine $id
export STUB_CONTAINERS="" STUB_IMAGES_ABSENT=1
# shellcheck disable=SC2086
expect 1 "runner image" "run refused without the runner image" -- mut "$broker" run --sim engine $id
expect_no_mutation "host-state refusals"

# --- prepare reaches its staging checks, never a runner ------------------------
reset_world
# shellcheck disable=SC2086
expect 1 "REFUSE: staged source archive is absent" "prepare checks staging before any change" -- \
    mut "$broker" prepare --sim devp2p $id
printf 'different' > "$work/other.tar"
# shellcheck disable=SC2086
expect 1 "but git archive" "prepare refuses a source archive that is not git archive REV" -- \
    env HOODI_HIVE_SOURCE_ARTIFACT="$work/other.tar" \
        HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 "$broker" prepare --sim devp2p $id
expect_no_mutation "prepare refusals"

# --- read-only actions ---------------------------------------------------------
reset_world
export STUB_CONTAINERS=sec5-hive-aaaaaaaa-engine-full-r3 STUB_RUNNING=true
# shellcheck disable=SC2086
expect 1 "REFUSE: runner sec5-hive-aaaaaaaa-engine-full-r3 is still running" "collect refused while running" -- \
    "$broker" collect --sim engine $id
if [ -e "$work/collect" ]; then record fail "collect created no local directory"; else record ok "collect created no local directory"; fi
# shellcheck disable=SC2086
expect 0 "runner=sec5" "status reads the runner" -- "$broker" status --sim engine $id
# shellcheck disable=SC2086
expect 0 "run-root=/data/hoodi-sec5-hive/runs/aaaaaaaa-engine-full-r3-20260923T120000Z absent" \
    "inspect names the run root" -- "$broker" inspect --sim engine $id
expect 0 "hive-binary=/data/hoodi-sec5-hive/staging/hive-dde4f59d absent" "inspect reports the Hive binary" -- \
    "$broker" inspect
expect_no_mutation "read-only actions"

# --- upload from an exported archive (HOODI_HIVE_IMAGE_TAR) --------------------
# make_image_tar NAME TAG REVISION ARCH: a minimal `docker image save` archive
# (manifest.json plus one image configuration blob).
make_image_tar() {
    local dir="$work/tar-$1"
    mkdir -p "$dir/blobs/sha256"
    printf '{"architecture":"%s","os":"linux","config":{"User":"ethereum:ethereum","Labels":{"org.opencontainers.image.revision":"%s","org.opencontainers.image.title":"ethereum-lisp"}}}' \
        "$4" "$3" > "$dir/blobs/sha256/c0nf1g"
    printf '[{"Config":"blobs/sha256/c0nf1g","RepoTags":["%s"],"Layers":[]}]' "$2" > "$dir/manifest.json"
    tar -cf "$work/$1.tar" -C "$dir" manifest.json blobs
    sha256sum "$work/$1.tar" | awk '{print $1}'
}
good_tag="ethereum-lisp-runtime:sec5-aaaaaaaa-amd64"
good_tar="$work/ethereum-lisp-runtime-export-good.tar"
good_sha="$(make_image_tar ethereum-lisp-runtime-export-good "$good_tag" "$head_rev" amd64)"
old_tar_sha="$(make_image_tar ethereum-lisp-runtime-export-old "$good_tag" "$old_rev" amd64)"
arm_tar_sha="$(make_image_tar ethereum-lisp-runtime-export-arm "$good_tag" "$head_rev" arm64)"
tag_tar_sha="$(make_image_tar ethereum-lisp-runtime-export-tag "ethereum-lisp-runtime:local" "$head_rev" amd64)"
printf 'not an archive' > "$work/ethereum-lisp-runtime-export-junk.tar"
junk_sha="$(sha256sum "$work/ethereum-lisp-runtime-export-junk.tar" | awk '{print $1}')"
tar_upload() {  # TAR SHA
    env HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_IMAGE_TAR="$1" HOODI_HIVE_IMAGE_SHA256="$2" "$broker" upload
}
expect_no_docker() {
    if grep -q '^docker ' "$STUB_LOG"; then
        cp "$STUB_LOG" "$out"; record fail "$1: local Docker daemon not used"
    else
        record ok "$1: local Docker daemon not used"
    fi
}

reset_world
unset HOODI_HIVE_RUNTIME_ARTIFACT
export STUB_DOCKER_DOWN=1 STUB_SSH_REFUSE=1
# Control: with the daemon down, the ordinary path cannot identify the image.
expect 1 "local runtime image is absent" "upload without an archive needs the local daemon" -- \
    env HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_RUNTIME_ARTIFACT="$runtime_tar" "$broker" upload
: > "$STUB_LOG"
expect 97 "runtime-archive-image=$good_tag revision=$head_rev platform=linux/amd64" \
    "upload identifies the image from the archive and reaches the host" -- tar_upload "$good_tar" "$good_sha"
expect_no_docker "archive upload"
if grep -qF "runtime=$good_tar sha256=$good_sha" "$out"; then
    record ok "archive upload stages the pinned archive"
else
    record fail "archive upload stages the pinned archive"
fi
: > "$STUB_LOG"
expect 1 "but HOODI_HIVE_IMAGE_SHA256 is" "archive upload refuses a checksum mismatch" -- \
    tar_upload "$good_tar" "$old_tar_sha"
expect 1 "runtime archive revision is $old_rev, expected $head_rev" \
    "archive upload refuses another revision" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-old.tar" "$old_tar_sha"
expect 1 "expected linux/amd64" "archive upload refuses another platform" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-arm.tar" "$arm_tar_sha"
expect 1 "is not tagged $good_tag" "archive upload refuses another tag" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-tag.tar" "$tag_tar_sha"
expect 1 "has no manifest.json" "archive upload refuses a file that is not an image archive" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-junk.tar" "$junk_sha"
expect 1 "must be set together" "archive path without its checksum" -- \
    env HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_IMAGE_TAR="$good_tar" "$broker" upload
expect 1 "lowercase hexadecimal" "archive checksum in upper case" -- \
    tar_upload "$good_tar" "$(printf '%s' "$good_sha" | tr a-f A-F)"
expect 1 "name different archives" "archive and runtime-artifact overrides disagree" -- \
    env HOODI_HIVE_RUNTIME_ARTIFACT="$runtime_tar" HOODI_GATE_ALLOW_MUTATION=1 \
        HOODI_HIVE_IMAGE_TAR="$good_tar" HOODI_HIVE_IMAGE_SHA256="$good_sha" "$broker" upload
expect 1 "HOODI_GATE_ALLOW_MUTATION=1" "archive upload still needs the mutation flag" -- \
    env HOODI_HIVE_IMAGE_TAR="$good_tar" HOODI_HIVE_IMAGE_SHA256="$good_sha" "$broker" upload
# The revision fence is unchanged: a runtime-sensitive change since the
# revision refuses the archive path exactly as it refuses the image path.
export HOODI_HIVE_REVISION="$old_rev" STUB_SENSITIVE="src/cli/devnet.lisp"
expect 1 "runtime-sensitive paths" "archive upload keeps the revision fence" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-old.tar" "$old_tar_sha"
export STUB_SENSITIVE=""
printf 'archive-%s' "$old_rev" > "$work/ethereum-lisp-source-bbbbbbbb.tar"
export HOODI_HIVE_SOURCE_ARTIFACT="$work/ethereum-lisp-source-bbbbbbbb.tar"
expect 1 "is not tagged ethereum-lisp-runtime:sec5-bbbbbbbb-amd64" \
    "a docs-only ancestor passes the fence and needs its own tag" -- \
    tar_upload "$work/ethereum-lisp-runtime-export-old.tar" "$old_tar_sha"
export HOODI_HIVE_SOURCE_ARTIFACT="$source_tar"
unset HOODI_HIVE_REVISION
# shellcheck disable=SC2086
expect 1 "but HOODI_HIVE_IMAGE_SHA256 is" "prepare checks the archive pin before the host" -- \
    env HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 \
        HOODI_HIVE_IMAGE_TAR="$good_tar" HOODI_HIVE_IMAGE_SHA256="$old_tar_sha" \
        "$broker" prepare --sim devp2p $id
expect_no_docker "archive refusals"
if grep -q '^ssh \|^scp ' "$STUB_LOG"; then
    cp "$STUB_LOG" "$out"; record fail "archive refusals: no remote contact"
else
    record ok "archive refusals: no remote contact"
fi

echo "hoodi-hive-gate selftest: $checks checks, $failures failed"
[ "$checks" -gt 0 ] || { echo "no checks ran" >&2; exit 1; }
[ "$failures" -eq 0 ]
