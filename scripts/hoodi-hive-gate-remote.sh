# shellcheck shell=bash
#
# Remote halves of scripts/hoodi-hive-gate.sh.  Sourced by that broker after
# it has parsed and validated every identity; this file only defines
# functions and never runs anything on its own.  Each function prints what it
# is about to do, then sends one reviewed script to the host with
# `ssh HOST bash -s -- ARGS`.  Every positional argument is non-empty (ssh
# joins the command into one string and would drop an empty slot) and
# whitespace-free (validated by the broker).

# --- inspect (read-only) ------------------------------------------------------

inspect_gate() {
    note "inspect: read-only; local artifacts, then remote memory, disk, containers, images, staging"
    printf 'revision=%s head=%s host=%s\n' "$revision" "$actual_head" "$host"
    local file
    for file in "$source_artifact" "$runtime_artifact"; do
        if [ -f "$file" ]; then
            printf 'local-artifact=%s sha256=%s\n' "$file" "$(sha256_file "$file")"
        else
            printf 'local-artifact=%s absent\n' "$file"
        fi
    done
    ssh "$host" bash -s -- \
        "$hive_root" "$remote_source" "$remote_runtime" "$runner_image" "$runtime_image" \
        "$hive_binary" "$hive_binary_sha256" "$agent_label" \
        "$run_root" "$runner_container" <<'REMOTE'
set -eu
hive_root="$1"; remote_source="$2"; remote_runtime="$3"; runner_image="$4"
runtime_image="$5"; hive_binary="$6"; hive_binary_sha="$7"; agent="$8"
run_root="$9"; runner="${10}"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
free -b
df -B1 /data
echo "running containers:"
docker ps --format 'container={{.Names}} image={{.Image}} status={{.Status}} labels={{.Labels}}'
live_el="$(docker ps --filter "label=agent=$agent" --filter label=io.ethereum-lisp.gate-revision --format '{{.Names}}')"
printf 'live-el-running=%s\n' "${live_el:-none}"
runners="$(docker ps --filter label=io.ethereum-lisp.hive-role --format '{{.Names}}')"
printf 'hive-runners-running=%s\n' "${runners:-none}"
if docker image inspect "$runner_image" >/dev/null 2>&1; then
    docker image inspect --format \
        'runner-image={{.Id}} platform={{.Os}}/{{.Architecture}} user={{.Config.User}} entrypoint={{json .Config.Entrypoint}} cmd={{json .Config.Cmd}} volumes={{json .Config.Volumes}}' \
        "$runner_image"
else
    printf 'runner-image=%s absent\n' "$runner_image"
fi
if docker image inspect "$runtime_image" >/dev/null 2>&1; then
    docker image inspect --format \
        'host-runtime-image={{.Id}} platform={{.Os}}/{{.Architecture}} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} user={{.Config.User}}' \
        "$runtime_image"
else
    printf 'host-runtime-image=%s absent (not required: runs load the archive into their nested daemon)\n' "$runtime_image"
fi
for file in "$remote_source" "$remote_runtime"; do
    if [ -f "$file" ]; then sha256sum "$file"; else printf 'staged=%s absent\n' "$file"; fi
done
if [ -f "$hive_binary" ]; then
    printf 'hive-binary=%s sha256=%s expected=%s\n' "$hive_binary" \
        "$(sha256sum "$hive_binary" | awk '{print $1}')" "$hive_binary_sha"
else
    printf 'hive-binary=%s absent expected=%s\n' "$hive_binary" "$hive_binary_sha"
fi
if [ -d "$hive_root/runs" ]; then
    echo "existing run roots:"
    ls -1 "$hive_root/runs"
fi
if [ "$run_root" != none ]; then
    if [ -d "$run_root" ]; then printf 'run-root=%s present\n' "$run_root"; else printf 'run-root=%s absent\n' "$run_root"; fi
    if docker container inspect "$runner" >/dev/null 2>&1; then
        docker container inspect --format \
            'runner={{.Name}} running={{.State.Running}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' "$runner"
    else
        printf 'runner=/%s absent\n' "$runner"
    fi
fi
REMOTE
}

# --- upload (mutating) --------------------------------------------------------

upload_one() {
    local file="$1" remote="$2" expected="$3" state partial
    partial="$remote.partial-$expected"
    state="$(ssh "$host" bash -s -- "$staging" "$remote" "$partial" "$expected" <<'REMOTE'
set -eu
dir="$1"; final="$2"; partial="$3"; expected="$4"
install -d -m 0755 "$dir"
if [ -e "$final" ]; then
    actual="$(sha256sum "$final" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || { echo "existing $final checksum $actual does not match $expected" >&2; exit 1; }
    printf present
elif [ -e "$partial" ]; then
    echo "refusing to overwrite interrupted upload $partial" >&2
    exit 1
else
    printf upload
fi
REMOTE
)"
    if [ "$state" = present ]; then
        note "remote $remote already has sha256 $expected"
        return
    fi
    [ "$state" = upload ] || fail "unexpected upload preflight result: $state"
    note "uploading $file to $host:$remote"
    # -O: legacy SCP; the host's sftp-server closes the connection
    # (scripts/hoodi-live-gate.sh).  The checksum is verified after arrival.
    scp -O "$file" "$host:$partial"
    ssh "$host" bash -s -- "$remote" "$partial" "$expected" <<'REMOTE'
set -eu
final="$1"; partial="$2"; expected="$3"
actual="$(sha256sum "$partial" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { echo "uploaded checksum $actual does not match $expected" >&2; exit 1; }
chmod 0600 "$partial"
[ ! -e "$final" ] || { echo "refusing to overwrite $final" >&2; exit 1; }
mv "$partial" "$final"
printf 'uploaded=%s sha256=%s\n' "$final" "$actual"
REMOTE
}

upload_artifacts() {
    require_mutation
    note "upload: stage the exact source and runtime archives under $staging on $host"
    if [ ! -f "$source_artifact" ]; then
        note "building $source_artifact with git archive --format=tar $revision"
        [ ! -e "$source_artifact.partial" ] || fail "refusing to overwrite $source_artifact.partial"
        git -C "$repo_root" archive --format=tar "$revision" > "$source_artifact.partial"
        mv "$source_artifact.partial" "$source_artifact"
    fi
    local_artifacts
    verify_source_archive
    inspect_local_runtime_image
    printf 'source=%s sha256=%s\n' "$source_artifact" "$source_sha256"
    printf 'runtime=%s sha256=%s\n' "$runtime_artifact" "$runtime_sha256"
    upload_one "$source_artifact" "$remote_source" "$source_sha256"
    upload_one "$runtime_artifact" "$remote_runtime" "$runtime_sha256"
}

# --- prepare and run (mutating) ----------------------------------------------

remote_run_args() {
    printf '%s\n' \
        "$revision" "$suite" "$hive_sim" "$expected_tests" "$suite_log" \
        "$run_root" "$nested_root" "$runner_container" "$prepare_container" \
        "$runner_image" "$runtime_repository" "$runtime_tag" \
        "$remote_source" "$remote_runtime" "$hive_binary" "$hive_binary_sha256" \
        "$runner_memory" "$runner_memory_swap" "$memory_need_bytes" "$disk_need_bytes" \
        "$refuse_live_el" "$agent_label" "${source_sha256:-none}" "${runtime_sha256:-none}"
}

# The remote half of prepare and run.  It re-checks every precondition first
# and mutates only after all of them hold; each refusal is one "REFUSE:" line.
# The runner script it writes stays in the evidence root with its SHA-256 as
# the reviewed runner identity of the run.
remote_gate() {
    local mode="$1"
    # Word splitting is intended: every value is validated whitespace-free.
    # shellcheck disable=SC2046
    ssh "$host" bash -s -- "$mode" $(remote_run_args) <<'REMOTE'
set -eu
mode="$1"; revision="$2"; suite="$3"; hive_sim="$4"; expected_tests="$5"; suite_log="$6"
run_root="$7"; nested_root="$8"; runner="$9"; prep="${10}"; runner_image="${11}"
runtime_repository="${12}"; runtime_tag="${13}"; remote_source="${14}"; remote_runtime="${15}"
hive_binary="${16}"; hive_binary_sha="${17}"; memory="${18}"; memory_swap="${19}"
memory_need="${20}"; disk_need="${21}"; refuse_live_el="${22}"; agent="${23}"
source_sha="${24}"; runtime_sha="${25}"

refuse() { echo "REFUSE: $*" >&2; exit 1; }

date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
for name in "$runner" "$prep"; do
    if docker container inspect "$name" >/dev/null 2>&1; then
        refuse "container $name already exists; use a new run ordinal"
    fi
done
disk_avail="$(df -B1 --output=avail /data | tail -n 1 | tr -d ' ')"
case "$disk_avail" in ''|*[!0-9]*) refuse "cannot read /data available bytes" ;; esac
printf 'data-available-bytes=%s need=%s\n' "$disk_avail" "$disk_need"
[ "$disk_avail" -ge "$disk_need" ] || refuse "/data has $disk_avail available bytes, below $disk_need"
mem_avail="$(free -b | awk '/^Mem:/ {print $7}')"
case "$mem_avail" in ''|*[!0-9]*) refuse "cannot read MemAvailable from free -b" ;; esac
if [ "$mode" = prepare ]; then
    # prepare always uses the smallest reviewed runner shape (r19 rpc-compat).
    mem_gate=4831838208
else
    mem_gate="$memory_need"
fi
printf 'mem-available-bytes=%s need=%s\n' "$mem_avail" "$mem_gate"
[ "$mem_avail" -ge "$mem_gate" ] || refuse "MemAvailable $mem_avail is below the $mode need $mem_gate for $suite"
if [ "$mode" = run ] && [ "$refuse_live_el" = 1 ]; then
    live_el="$(docker ps --filter "label=agent=$agent" --filter label=io.ethereum-lisp.gate-revision --format '{{.Names}}')"
    [ -z "$live_el" ] ||
        refuse "live EL $live_el is running; $suite runs only in the EL-stopped window (acceptance plan step 3b)"
fi
others="$(docker ps --filter label=io.ethereum-lisp.hive-role --format '{{.Names}}')"
[ -z "$others" ] || refuse "another Hive runner is running: $others"
docker image inspect "$runner_image" >/dev/null 2>&1 || refuse "runner image $runner_image is absent on the host"

if [ "$mode" = prepare ]; then
    [ ! -e "$run_root" ] || refuse "evidence root $run_root already exists; use a new run identity"
    [ ! -e "$nested_root" ] || refuse "nested Docker root $nested_root already exists"
    [ -f "$remote_source" ] || refuse "staged source archive is absent: $remote_source"
    [ -f "$remote_runtime" ] || refuse "staged runtime archive is absent: $remote_runtime"
    [ "$(sha256sum "$remote_source" | awk '{print $1}')" = "$source_sha" ] ||
        refuse "staged source checksum differs from $source_sha"
    [ "$(sha256sum "$remote_runtime" | awk '{print $1}')" = "$runtime_sha" ] ||
        refuse "staged runtime checksum differs from $runtime_sha"
    [ -f "$hive_binary" ] || refuse "pinned Hive binary is absent: $hive_binary"
    [ "$(sha256sum "$hive_binary" | awk '{print $1}')" = "$hive_binary_sha" ] ||
        refuse "Hive binary checksum differs from $hive_binary_sha"

    install -d -m 0755 "$run_root" "$run_root/src" "$run_root/results" "$run_root/artifacts" \
        "$run_root/hive-gate/hive" "$nested_root"
    tar -xf "$remote_source" -C "$run_root/src"
    cp "$remote_source" "$remote_runtime" "$run_root/artifacts/"
    cp "$hive_binary" "$run_root/hive-gate/hive/hive"
    chmod 0755 "$run_root/hive-gate/hive/hive"
    (cd "$run_root/artifacts" && sha256sum ./*) > "$run_root/artifacts.sha256"
    printf '%s  %s\n' "$hive_binary_sha" ./hive-gate/hive/hive >> "$run_root/artifacts.sha256"
    cat > "$run_root/runner.sh" <<'RUNNER'
#!/bin/sh
# Outer-runner body written by scripts/hoodi-hive-gate-remote.sh.  Starts the
# nested Docker daemon, loads and verifies the exact runtime archive, then
# runs scripts/hive-run.sh from the extracted source.  Hive's status goes to
# the evidence root; the runner exits 0 once Hive has run, as r54 did.
set -eu
mode="$1"
ev=/evidence
for tool in dockerd docker bash git jq sha256sum tar; do
    command -v "$tool" >/dev/null 2>&1 || { echo "runner: missing $tool" >&2; exit 1; }
done
dockerd --data-root /var/lib/docker --host unix:///var/run/docker.sock \
    > "$ev/nested-dockerd-$mode.log" 2>&1 &
dockerd_pid=$!
stop_dockerd() {
    docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$ev/nested-docker-$mode-final.txt" 2>&1 || true
    kill -TERM "$dockerd_pid" 2>/dev/null || true
    wait "$dockerd_pid" 2>/dev/null || true
}
trap stop_dockerd EXIT
tries=0
until docker info >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -le 120 ] || { echo "runner: nested dockerd did not become ready" >&2; exit 1; }
    sleep 1
done
docker version --format 'nested-docker client={{.Client.Version}} server={{.Server.Version}}' \
    > "$ev/nested-docker-$mode-version.txt"
image="$RUNTIME_IMAGE:$RUNTIME_TAG"
if ! docker image inspect "$image" >/dev/null 2>&1; then
    [ "$mode" = prepare ] ||
        { echo "runner: $image is absent from the nested daemon; prepare did not load it" >&2; exit 1; }
    docker image load --input "$ev/artifacts/$RUNTIME_ARCHIVE"
fi
docker image inspect --format \
    '{{.Id}} {{.Os}}/{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}} {{.Config.User}}' \
    "$image" > "$ev/nested-runtime-inspect-$mode.txt"
read -r _id platform image_revision image_user < "$ev/nested-runtime-inspect-$mode.txt"
[ "$platform" = linux/amd64 ] && [ "$image_revision" = "$EXPECTED_REVISION" ] &&
    [ "$image_user" = ethereum:ethereum ] ||
    { echo "runner: nested runtime identity mismatch: $platform $image_revision $image_user" >&2; exit 1; }
cd "$ev/src"
export RUNTIME_PREBUILT=1 HIVE_WORKDIR="$ev/hive-gate" HIVE_RESULTS="$ev/results"
unset HIVE_EXTRA_ARGS HIVE_EXPECTED_TESTS
# The evidence root is a bind mount owned by the host user while the runner's
# git runs as the container user, so git refuses the Hive checkout under
# "dubious ownership" (observed on the first d203fee6 rpc-compat prepare,
# 2026-09-23T13:24Z).  Whitelist the evidence root through git's environment
# rather than writing a config file into the read-only runner.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
if [ "$EXPECTED_TESTS" != none ]; then
    export HIVE_EXPECTED_TESTS="$EXPECTED_TESTS"
fi
status=0
if [ "$mode" = prepare ]; then
    bash scripts/hive-run.sh --sim "$HIVE_SIM" --prepare-only > "$ev/hive-prepare.log" 2>&1 || status=$?
    echo "EXIT=$status" > "$ev/prepare-status.txt"
    exit "$status"
fi
date -u +%Y-%m-%dT%H:%M:%SZ > "$ev/hive-start.txt"
bash scripts/hive-run.sh --sim "$HIVE_SIM" > "$ev/$SUITE_LOG" 2>&1 || status=$?
echo "EXIT=$status" > "$ev/hive-status.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$ev/hive-stop.txt"
exit 0
RUNNER
    sha256sum "$run_root/runner.sh" | awk '{print $1}' > "$run_root/runner.sh.sha256"
    printf 'run-root=%s\nrunner-script-sha256=%s\n' "$run_root" "$(cat "$run_root/runner.sh.sha256")"
    name="$prep"
    runner_mem=3g
    runner_swap=3584m
else
    [ -f "$run_root/prepared.txt" ] || refuse "evidence root $run_root is not prepared (run prepare first)"
    [ -z "$(find "$run_root/results" -mindepth 1 -print -quit)" ] ||
        refuse "results directory is not empty: $run_root/results"
    [ ! -e "$run_root/hive-status.txt" ] || refuse "evidence root already holds a Hive status; use a new run identity"
    [ "$(sha256sum "$run_root/runner.sh" | awk '{print $1}')" = "$(cat "$run_root/runner.sh.sha256")" ] ||
        refuse "runner script changed since prepare"
    name="$runner"
    runner_mem="$memory"
    runner_swap="$memory_swap"
fi

# The outer runner shape from r19/r29/r54: 2 CPUs, the suite's memory and
# memory-plus-swap, 1,024 PIDs, read-only root, no published port, the default
# bridge (never the Hoodi networks), binds limited to this run's evidence root
# and nested-Docker path, and bounded tmpfs.  --privileged is inferred, not
# recorded: it is what lets the nested daemon start.
set -- --name "$name" \
    --label "agent=$agent" \
    --label "io.ethereum-lisp.hive-role=$mode" \
    --label "io.ethereum-lisp.hive-revision=$revision" \
    --label "io.ethereum-lisp.hive-suite=$suite" \
    --label "io.ethereum-lisp.hive-run-root=$run_root" \
    --cpus 2 --memory "$runner_mem" --memory-swap "$runner_swap" --pids-limit 1024 \
    --read-only --privileged --network bridge --restart no \
    --tmpfs /run:rw,size=64m --tmpfs /var/run:rw,size=64m --tmpfs /tmp:rw,size=1g \
    --volume "$run_root:/evidence" \
    --volume "$nested_root:/var/lib/docker" \
    --env "EXPECTED_REVISION=$revision" \
    --env "RUNTIME_IMAGE=$runtime_repository" \
    --env "RUNTIME_TAG=$runtime_tag" \
    --env "RUNTIME_ARCHIVE=${remote_runtime##*/}" \
    --env "HIVE_SIM=$hive_sim" \
    --env "EXPECTED_TESTS=$expected_tests" \
    --env "SUITE_LOG=$suite_log" \
    --env "HIVE_PREBUILT_BINARY_SHA256=$hive_binary_sha" \
    --entrypoint /bin/sh

if [ "$mode" = prepare ]; then
    echo "prepare: foreground $name (hive-run.sh --sim $hive_sim --prepare-only)"
    status=0
    docker run --rm "$@" "$runner_image" /evidence/runner.sh prepare || status=$?
    printf 'prepare-runner-exit=%s\n' "$status"
    [ ! -f "$run_root/prepare-status.txt" ] || cat "$run_root/prepare-status.txt"
    tail -n 20 "$run_root/hive-prepare.log" 2>/dev/null || true
    [ "$status" = 0 ] || { echo "prepare failed; evidence root retained: $run_root" >&2; exit 1; }
    date -u +prepared=%Y-%m-%dT%H:%M:%SZ > "$run_root/prepared.txt"
    printf 'prepared=%s\n' "$run_root"
else
    echo "run: detached $name (hive-run.sh --sim $hive_sim, expected tests $expected_tests)"
    docker run --detach "$@" "$runner_image" /evidence/runner.sh run
    docker container inspect --format \
        'runner={{.Name}} id={{.Id}} started={{.State.StartedAt}} memory={{.HostConfig.Memory}} swap={{.HostConfig.MemorySwap}} pids={{.HostConfig.PidsLimit}} readonly={{.HostConfig.ReadonlyRootfs}} privileged={{.HostConfig.Privileged}} ports={{json .HostConfig.PortBindings}} binds={{json .HostConfig.Binds}}' \
        "$name" | tee "$run_root/runner-start-inspect.txt"
fi
REMOTE
}

prepare_run() {
    require_mutation
    require_nested_privilege
    local_artifacts
    verify_source_archive
    note "prepare: fresh evidence root $run_root on $host"
    note "prepare: extract $remote_source, stage the runtime archive and Hive binary, load the runtime into the nested daemon, hive-run.sh --sim $hive_sim --prepare-only"
    remote_gate prepare
}

start_run() {
    require_mutation
    require_nested_privilege
    note "run: start detached outer runner $runner_container ($runner_image) for $hive_sim"
    note "run: bounds 2 CPU, memory $runner_memory, memory+swap $runner_memory_swap, 1024 PIDs; needs MemAvailable >= $memory_need_bytes"
    remote_gate run
}

# --- status, logs, collect (read-only) ----------------------------------------

remote_status() {
    note "status: read-only runner state and Hive summary for $run_id"
    ssh "$host" bash -s -- "$run_root" "$runner_container" "$suite_log" <<'REMOTE'
set -eu
run_root="$1"; runner="$2"; suite_log="$3"
date -u +timestamp=%Y-%m-%dT%H:%M:%SZ
free -b
if docker container inspect "$runner" >/dev/null 2>&1; then
    docker container inspect --format \
        'runner={{.Name}} status={{.State.Status}} running={{.State.Running}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' \
        "$runner"
    if [ "$(docker container inspect --format '{{.State.Running}}' "$runner")" = true ]; then
        docker stats --no-stream --format 'runner-stats mem={{.MemUsage}} pids={{.PIDs}} cpu={{.CPUPerc}}' "$runner"
    fi
else
    printf 'runner=/%s absent\n' "$runner"
fi
for file in prepared.txt prepare-status.txt hive-start.txt hive-status.txt hive-stop.txt; do
    if [ -f "$run_root/$file" ]; then printf '%s: %s\n' "$file" "$(cat "$run_root/$file")"; fi
done
if [ -f "$run_root/$suite_log" ]; then
    grep -E '^hive [0-9a-f]+ ::|^FATAL|^go-ethereum |^execution-apis ' "$run_root/$suite_log" ||
        echo "summary: not yet printed"
else
    printf 'log=%s absent\n' "$run_root/$suite_log"
fi
REMOTE
}

remote_logs() {
    note "logs: read-only tail of the runner and the Hive log for $run_id"
    ssh "$host" bash -s -- "$run_root" "$runner_container" "$suite_log" <<'REMOTE'
set -eu
run_root="$1"; runner="$2"; suite_log="$3"
if docker container inspect "$runner" >/dev/null 2>&1; then
    docker logs --tail 100 "$runner" 2>&1
else
    printf 'runner=/%s absent\n' "$runner"
fi
for file in hive-prepare.log "$suite_log"; do
    if [ -f "$run_root/$file" ]; then
        echo "--- $file (last 200 lines)"
        tail -n 200 "$run_root/$file"
    fi
done
REMOTE
}

collect_run() {
    note "collect: copy results and logs of $run_id to $collect_dir (the remote is only read)"
    [ ! -e "$collect_dir" ] || fail "local evidence directory already exists: $collect_dir"
    local state
    state="$(ssh "$host" bash -s -- "$run_root" "$runner_container" <<'REMOTE'
set -eu
run_root="$1"; runner="$2"
docker container inspect "$runner" >/dev/null 2>&1 || { echo "REFUSE: runner $runner is absent" >&2; exit 1; }
running="$(docker container inspect --format '{{.State.Running}}' "$runner")"
[ "$running" = false ] || { echo "REFUSE: runner $runner is still running" >&2; exit 1; }
[ -f "$run_root/hive-status.txt" ] || { echo "REFUSE: $run_root has no hive-status.txt" >&2; exit 1; }
docker container inspect --format \
    'runner={{.Name}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' \
    "$runner"
REMOTE
)" || fail "collect preconditions failed"
    command -v jq >/dev/null 2>&1 || fail "jq is required to count results"
    mkdir -p "$collect_dir"
    printf '%s\n' "$state" > "$collect_dir/runner-final-inspect.txt"
    ssh "$host" bash -s -- "$run_root" <<'REMOTE' | tar -xf - -C "$collect_dir"
set -eu
cd "$1"
set -- results
for file in hive-status.txt hive-start.txt hive-stop.txt prepared.txt prepare-status.txt \
            hive-prepare.log hive-rpc-full.log hive-engine-full.log hive-devp2p-full.log \
            artifacts.sha256 runner.sh runner.sh.sha256 runner-start-inspect.txt \
            nested-runtime-inspect-prepare.txt nested-runtime-inspect-run.txt \
            nested-docker-prepare-version.txt nested-docker-run-version.txt \
            nested-docker-prepare-final.txt nested-docker-run-final.txt; do
    if [ -e "$file" ]; then set -- "$@" "$file"; fi
done
tar -cf - "$@"
REMOTE
    note "collected into $collect_dir"
    cat "$collect_dir/runner-final-inspect.txt"
    cat "$collect_dir/hive-status.txt"
    grep -E '^hive [0-9a-f]+ ::|^FATAL|^go-ethereum |^execution-apis ' "$collect_dir/$suite_log" || true
    local file total=0 passed=0 count ok name expected
    for file in "$collect_dir"/results/*.json; do
        [ -f "$file" ] || continue
        [ "${file##*/}" != hive.json ] || continue
        name="$(jq -r '.name // "unnamed"' "$file")"
        count="$(jq '[.testCases[]?] | length' "$file")"
        ok="$(jq '[.testCases[]? | select(.summaryResult.pass == true)] | length' "$file")"
        printf 'suite=%s selected=%s passed=%s failed=%s file=%s\n' \
            "$name" "$count" "$ok" "$((count - ok))" "${file##*/}"
        jq -r '.testCases[]? | select(.summaryResult.pass != true) | "  not ok: " + .name' "$file"
        total=$((total + count))
        passed=$((passed + ok))
    done
    case "$suite" in rpc-compat) expected=234 ;; engine) expected=403 ;; *) expected=48 ;; esac
    printf 'total selected=%s passed=%s failed=%s expected=%s\n' \
        "$total" "$passed" "$((total - passed))" "$expected"
    (cd "$collect_dir" && find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort |
        while IFS= read -r path; do printf '%s  %s\n' "$(sha256_file "$path")" "$path"; done) \
        > "$collect_dir/manifest.sha256"
    printf 'manifest=%s entries=%s sha256=%s\n' "$collect_dir/manifest.sha256" \
        "$(wc -l < "$collect_dir/manifest.sha256" | tr -d ' ')" \
        "$(sha256_file "$collect_dir/manifest.sha256")"
}
