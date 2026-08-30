#!/usr/bin/env bash
#
# Run a Hive suite against this client, from a pinned Hive checkout.
#
# One entry point for CI and for a developer, so that a suite which passes
# locally and a suite which passes in .github/workflows/hive.yml are the same
# suite at the same Hive commit -- a Hive result that does not name its commit
# is not evidence of anything (PROJECT.md).
#
# Usage:
#   scripts/hive-run.sh [--sim SUITE] [--sim-limit REGEX] [--prepare-only]
#
# Environment:
#   HIVE_WORKDIR       where the pinned checkout lives
#                      (default .dev-runtime/hive-gate, already git-ignored;
#                      scripts/dev.sh owns only .dev-runtime/swank-dev)
#   RUNTIME_IMAGE      client base image name  (default ethereum-lisp-runtime)
#   RUNTIME_TAG        client base image tag   (default hive-local)
#   RUNTIME_PREBUILT   set to 1 to use an existing image instead of building
#   HIVE_RESULTS       results directory (default $HIVE_WORKDIR/results)
#   HIVE_EXTRA_ARGS    appended to the hive command line verbatim
#   HIVE_EXPECTED_TESTS exact executed-test count; full pinned engine and
#                       rpc-compat runs select their known inventories
#
# Running Hive needs a Go toolchain and a dockerd on the same host, because
# Hive dials the client containers by their bridge address for its liveness
# check. That rules out macOS + Docker Desktop, where the daemon lives in a VM
# the host cannot route into, so this script prepares everything and stops
# there. A real Hive run belongs on the reviewed Linux CI/remote-release path.

set -euo pipefail

# The baseline recorded in docs/gap-analysis/public-testnet-readiness-plan.md.
# Bumping it means re-reading clients.md for contract changes and re-checking
# tools/hive/mapper.jq against clients/go-ethereum/mapper.jq at the new commit.
HIVE_COMMIT="dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c"
HIVE_REPO="https://github.com/ethereum/hive"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="${HIVE_WORKDIR:-$repo_root/.dev-runtime/hive-gate}"
hive_dir="$workdir/hive"
runtime_image="${RUNTIME_IMAGE:-ethereum-lisp-runtime}"
runtime_tag="${RUNTIME_TAG:-hive-local}"
results_dir="${HIVE_RESULTS:-$workdir/results}"

sim="ethereum/engine"
sim_limit=""
prepare_only=0

while [ $# -gt 0 ]; do
    case "$1" in
        --sim)          sim="$2"; shift 2 ;;
        --sim-limit)    sim_limit="$2"; shift 2 ;;
        --prepare-only) prepare_only=1; shift ;;
        -h|--help)      sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

log() { printf '==> %s\n' "$*"; }

# Hive itself is a Go program that must share a Linux host with the Docker
# daemon it uses to inspect client bridge addresses. Check those external
# runner prerequisites before creating a checkout or client definition, so a
# missing runner contract is reported as environment evidence rather than an
# ambiguous mid-run shell failure.
command -v docker >/dev/null 2>&1 || {
    echo "FATAL: Hive requires Docker on the Linux runner" >&2
    exit 1
}
docker info >/dev/null 2>&1 || {
    echo "FATAL: Hive requires a reachable Docker daemon on the Linux runner" >&2
    exit 1
}
command -v go >/dev/null 2>&1 || {
    echo "FATAL: Hive requires a Go toolchain on the Linux runner; use the reviewed CI/remote runner rather than installing one on a control-plane host" >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "FATAL: Hive result validation requires jq on the Linux runner" >&2
    exit 1
}

# --- client base image ------------------------------------------------------

if [ "${RUNTIME_PREBUILT:-0}" = "1" ]; then
    log "using prebuilt $runtime_image:$runtime_tag"
    docker image inspect "$runtime_image:$runtime_tag" >/dev/null
else
    log "building $runtime_image:$runtime_tag from Dockerfile.runtime"
    docker build \
        --file "$repo_root/Dockerfile.runtime" \
        --tag "$runtime_image:$runtime_tag" \
        --build-arg "REVISION=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)" \
        "$repo_root"
fi

# --- pinned hive checkout ---------------------------------------------------

mkdir -p "$workdir"
if [ ! -d "$hive_dir/.git" ]; then
    log "cloning hive into $hive_dir"
    git init --quiet "$hive_dir"
    git -C "$hive_dir" remote add origin "$HIVE_REPO"
fi
if [ "$(git -C "$hive_dir" rev-parse HEAD 2>/dev/null || true)" != "$HIVE_COMMIT" ]; then
    log "checking out hive $HIVE_COMMIT"
    git -C "$hive_dir" fetch --depth 1 origin "$HIVE_COMMIT"
    git -C "$hive_dir" checkout --quiet --force FETCH_HEAD
fi
# A pin that is not verified is a wish. Hive is fetched over the network on
# every CI run, so confirm the tree really is the commit the results will claim.
actual_commit="$(git -C "$hive_dir" rev-parse HEAD)"
if [ "$actual_commit" != "$HIVE_COMMIT" ]; then
    echo "FATAL: hive checkout is $actual_commit, expected $HIVE_COMMIT" >&2
    exit 1
fi

# --- client definition ------------------------------------------------------

log "installing clients/ethereum-lisp from tools/hive"
rm -rf "$hive_dir/clients/ethereum-lisp"
mkdir -p "$hive_dir/clients/ethereum-lisp"
cp "$repo_root"/tools/hive/* "$hive_dir/clients/ethereum-lisp/"

client_file="$workdir/clients.yaml"
cat > "$client_file" <<YAML
- client: ethereum-lisp
  nametag: ethereum-lisp
  build_args:
    baseimage: $runtime_image
    tag: $runtime_tag
YAML

mkdir -p "$results_dir"
if find "$results_dir" -mindepth 1 -print -quit | grep -q .; then
    echo "FATAL: HIVE_RESULTS must be empty for a new evidence run: $results_dir" >&2
    exit 1
fi

hive_args=(--client-file "$client_file" --sim "$sim" --results-root "$results_dir")
if [ -n "$sim_limit" ]; then
    hive_args+=(--sim.limit "$sim_limit")
fi
if [ -n "${HIVE_EXTRA_ARGS:-}" ]; then
    # Word splitting is the point: HIVE_EXTRA_ARGS is a command-line fragment.
    # shellcheck disable=SC2206
    hive_args+=(${HIVE_EXTRA_ARGS})
fi

if [ "$prepare_only" = "1" ]; then
    log "prepared; not running hive (--prepare-only)"
    printf '    cd %s && go build . && ./hive %s\n' "$hive_dir" "${hive_args[*]}"
    exit 0
fi

if [ "$(uname -s)" = "Darwin" ]; then
    cat >&2 <<'MSG'
Refusing to run hive on macOS.

Hive must share a host with dockerd: it checks client liveness by dialling the
container's bridge address on port 8545, which is not routable from a macOS
host talking to a Docker Desktop VM. It also wants a Go toolchain on the host,
which this machine deliberately does not have.

Everything up to the run is done. Use --prepare-only to silence this, and run
the suite on Linux (.github/workflows/hive.yml does exactly that).
MSG
    exit 1
fi

log "building hive"
(cd "$hive_dir" && go build .)

log "hive --sim $sim (hive $HIVE_COMMIT)"
hive_status=0
(cd "$hive_dir" && ./hive "${hive_args[@]}") || hive_status=$?

# A green process with no tests is not conformance evidence. Validate fresh
# result JSON even when Hive itself failed, so every run leaves an honest count
# manifest and a missing/empty artifact is a harder failure than test failures.
result_file_count=0
executed_test_count=0
passed_test_count=0
while IFS= read -r -d '' result_file; do
    if ! jq -e '.testCases | type == "array"' "$result_file" >/dev/null; then
        echo "FATAL: invalid Hive suite result: $result_file" >&2
        exit 3
    fi
    result_file_count=$((result_file_count + 1))
    count="$(jq '[.testCases[]?] | length' "$result_file")"
    passed="$(jq '[.testCases[]? | select(.summaryResult.pass == true)] | length' \
        "$result_file")"
    executed_test_count=$((executed_test_count + count))
    passed_test_count=$((passed_test_count + passed))
done < <(find "$results_dir" -maxdepth 1 -type f -name '*.json' \
         ! -name hive.json -print0)

if [ "$result_file_count" -eq 0 ] || [ "$executed_test_count" -eq 0 ]; then
    echo "FATAL: Hive executed zero tests for $sim" >&2
    exit 3
fi

expected_test_count="${HIVE_EXPECTED_TESTS:-}"
if [ -z "$expected_test_count" ] && [ -z "$sim_limit" ]; then
    case "$sim" in
        ethereum/engine) expected_test_count=403 ;;
        ethereum/rpc-compat|rpc-compat) expected_test_count=243 ;;
    esac
fi
if [ -n "$expected_test_count" ] \
   && [ "$executed_test_count" -ne "$expected_test_count" ]; then
    echo "FATAL: Hive executed $executed_test_count tests for $sim; expected $expected_test_count" >&2
    exit 3
fi

printf 'hive %s :: %s :: %s/%s passed\n' \
    "$HIVE_COMMIT" "$sim" "$passed_test_count" "$executed_test_count"
exit "$hive_status"
