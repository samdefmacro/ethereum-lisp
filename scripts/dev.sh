#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT/.dev-runtime/swank-dev"
PORT="${ETHEREUM_LISP_SWANK_PORT:-4006}"

DOCKER=docker
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "ERROR: sha256sum or shasum is required for runtime identity" >&2
    return 1
  fi
}

CHECKOUT_ID="$(printf '%s' "$ROOT" | sha256_stdin)"
CHECKOUT_SHORT="${CHECKOUT_ID:0:12}"
SESSION_ID="ethereum-lisp-$CHECKOUT_SHORT"
IMAGE_FINGERPRINT="$(
  cd "$ROOT"
  for input in \
    Dockerfile \
    tools/rocksdb/rocksdb-11.1.2.tar.gz \
    tools/rocksdb/io-uring-kernel-compat.patch \
    tools/rocksdb/io-uring-probe.c \
    tools/ckzg-ffi/shim.c \
    tools/bls-ffi/shim.c
  do
    printf '%s ' "$input"
    git hash-object "$input"
  done | sha256_stdin
)"
IMAGE_SHORT="${IMAGE_FINGERPRINT:0:12}"
IMAGE="${ETHEREUM_LISP_DEV_IMAGE:-ethereum-lisp-dev:go1.24-bookworm-$IMAGE_SHORT}"
COLD_IMAGE="ethereum-lisp-sbcl-test:go1.24-bookworm-$IMAGE_SHORT"
CONTAINER="${ETHEREUM_LISP_DEV_CONTAINER:-ethereum-lisp-dev-$CHECKOUT_SHORT}"
PROJECT_LABEL="io.common-lisp-workbench.project"
CHECKOUT_LABEL="io.common-lisp-workbench.checkout"
MANAGED_LABEL="io.common-lisp-workbench.managed"
RUNTIME_LABEL="io.common-lisp-workbench.runtime-fingerprint"

usage() {
  cat <<'USAGE'
Usage: scripts/dev.sh COMMAND [ARGS]

Persistent Swank development helper for ethereum-lisp. The warm image runs
INSIDE A CONTAINER: PROJECT.md forbids running SBCL on the macOS host, and
this machine is shared with other agents. The container runs
scripts/dev-image.lisp (project + tests loaded, Swank listening on loopback)
as its main process; every eval is a `docker exec` of the hardened eval
client, so the Swank port is never published outside the container.

Commands:
  start              Start the warm dev container (tests loaded, Swank up)
  stop               Remove the dev container
  status             Show whether the dev container is running
  eval FORM          Evaluate FORM in the warm image through Swank
  test NAME          Run one test: eval (run-ethereum-lisp-test "NAME")
  test-all           Run the full suite in the warm image (long timeout)
  docs-check         Verify PAX documentation transcripts (docs/*.lisp)
  cold-test LAYER    Run unit, integration, e2e, or all in a fresh container
  cold-docs          Verify PAX transcripts in a fresh container
  cold-scale         Run the production-store scale gate in containers
  eest-fixtures BASELINE DESTINATION
                     Fetch a checksum-pinned EEST corpus in a narrow container
  runtime-build TAG  Build the reviewed non-root Dockerfile.runtime image
  runtime-export TAG ARTIFACT
                     Export an exact-revision linux/amd64 runtime archive
  runtime-smoke TAG  Run the reviewed runtime image smoke gate
  shadow-proxy-format
                     Format the Engine shadow proxy in a narrow container mount
  shadow-proxy-test  Build and test the Engine shadow proxy with no network
  shadow-proxy-build TAG
                     Build its reviewed non-root runtime image
  shadow-proxy-export TAG ARTIFACT
                     Export an exact-revision linux/amd64 proxy archive
  shadow-proxy-smoke TAG
                     Verify the final proxy image and container boundary
  hive-adapter-smoke TAG
                     Verify the Hive client wrapper against a reviewed runtime
  logs               Show the dev container's output
  build              Build the dev image
  shell              Open an interactive shell in the dev container
  help               Show this help

Environment:
  ETHEREUM_LISP_DEV_IMAGE      Dev image tag, default is build-input-specific
                               ethereum-lisp-dev:go1.24-bookworm-<input hash>. Kept
                               separate from the DOCKER_TEST_IMAGE tag so
                               building it never disturbs a concurrent cold
                               verification run.
  ETHEREUM_LISP_DEV_CONTAINER  Container name, default is checkout-specific.
                               An override is accepted only when its ownership
                               labels match this physical checkout.
  ETHEREUM_LISP_SWANK_PORT     Swank port INSIDE the container, default 4006
  DEV_EVAL_TIMEOUT             Eval timeout seconds, default 20 (test: 600,
                               test-all: 3600); on timeout the form is
                               interrupted and the image survives
  DEV_EVAL_MAX_OUTPUT          Output cap in chars, default 10000
  RUNTIME_PLATFORM             Optional runtime-build target: linux/amd64 or
                               linux/arm64 (defaults to Docker's native target)
  SHADOW_PROXY_PLATFORM        Optional shadow-proxy-build target with the
                               same accepted platform values
Eval exit codes: 0 ok, 1 lisp error, 2 connection error, 3 timed out
(interrupted), 4 hard hang (restart the image). Common Lisp Workbench records
payload-free operation outcomes in .cl-workbench/state; it does not append raw
forms to the historical .dev-runtime eval metrics file.

Canonical cold-image verification uses `cl-workbench validation run` with the
`cold-unit`, `cold-integration`, `cold-e2e`, `cold-all`, `cold-docs`, or
`cold-scale` profile. Reviewed runtime-image verification uses the
`runtime-smoke IMAGE` profile. The Workbench adapter delegates direct argv to
this script's existing brokers. Calling those low-level commands directly does
not create a Workbench validation event. The brokers accept only reviewed
arguments and construct Docker invocations without executing a host build
system; use the warm image for the development loop.
USAGE
}

container_exists() {
  "$DOCKER" container inspect "$CONTAINER" >/dev/null 2>&1
}

container_owned() {
  local actual_project actual_checkout actual_managed actual_fingerprint
  container_exists || return 1
  actual_project="$("$DOCKER" inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.project" }}' \
    "$CONTAINER")"
  actual_checkout="$("$DOCKER" inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.checkout" }}' \
    "$CONTAINER")"
  actual_managed="$("$DOCKER" inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.managed" }}' \
    "$CONTAINER")"
  actual_fingerprint="$("$DOCKER" inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.runtime-fingerprint" }}' \
    "$CONTAINER")"
  [ "$actual_project" = "ethereum-lisp" ] && \
    [ "$actual_checkout" = "$CHECKOUT_ID" ] && \
    [ "$actual_managed" = "true" ] && \
    [ "$actual_fingerprint" = "$IMAGE_FINGERPRINT" ]
}

require_owned_container() {
  if ! container_owned; then
    echo "ERROR: refusing foreign or unlabeled container: $CONTAINER" >&2
    echo "       expected checkout ownership: $CHECKOUT_ID" >&2
    return 2
  fi
}

container_state() { # prints running|stopped|absent
  local state
  if ! container_exists; then
    echo absent
    return 0
  fi
  require_owned_container || return $?
  state="$("$DOCKER" inspect --format '{{.State.Status}}' "$CONTAINER")"
  case "$state" in
    running) echo running ;;
    "") echo absent ;;
    *) echo stopped ;;
  esac
}

image_exists() {
  "$DOCKER" image inspect "$IMAGE" >/dev/null 2>&1
}

image_owned() {
  local actual_project actual_fingerprint
  image_exists || return 1
  actual_project="$("$DOCKER" image inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.project" }}' \
    "$IMAGE")"
  actual_fingerprint="$("$DOCKER" image inspect \
    --format '{{ index .Config.Labels "io.common-lisp-workbench.runtime-fingerprint" }}' \
    "$IMAGE")"
  [ "$actual_project" = ethereum-lisp ] && \
    [ "$actual_fingerprint" = "$IMAGE_FINGERPRINT" ]
}

require_owned_image() {
  if ! image_owned; then
    echo "ERROR: refusing foreign or unlabeled image: $IMAGE" >&2
    return 2
  fi
}

build_image() {
  echo "Building $IMAGE ..."
  "$DOCKER" build \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$RUNTIME_LABEL=$IMAGE_FINGERPRINT" \
    --file "$ROOT/Dockerfile" --tag "$IMAGE" "$ROOT"
}

# Mirrors the Makefile's DOCKER_TEST_RUN mounts so the warm image sees the
# same filesystem shape as the cold gates: the workspace read-only, with
# writable tmpfs where the suite needs to write. --network none still
# provides loopback, which is all Swank needs.
start_server() {
  local state
  mkdir -p "$RUNTIME_DIR"
  state="$(container_state)" || return $?
  case "$state" in
    running)
      echo "Dev container already running: $CONTAINER"
      return 0
      ;;
    stopped)
      echo "Removing exited container $CONTAINER"
      require_owned_container
      "$DOCKER" rm -f "$CONTAINER" >/dev/null
      ;;
  esac
  if image_exists; then
    require_owned_image
  else
    build_image
  fi
  "$DOCKER" run --detach --init --name "$CONTAINER" \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$CHECKOUT_LABEL=$CHECKOUT_ID" \
    --label "$MANAGED_LABEL=true" \
    --label "$RUNTIME_LABEL=$IMAGE_FINGERPRINT" \
    --network none \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --pids-limit 4096 \
    --volume "$ROOT:/workspace:ro" \
    --tmpfs "/workspace/.cache:exec,mode=1777" \
    --tmpfs "/tmp:exec,mode=1777" \
    --tmpfs "/private/tmp:exec,mode=1777" \
    --workdir /workspace \
    --env ETHEREUM_LISP_SWANK_PORT="$PORT" \
    --env ETHEREUM_LISP_DEV_IMAGE_WAIT=1 \
    --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
    "$IMAGE" \
    sbcl --noinform --load scripts/dev-image.lisp >/dev/null

  local i
  for i in {1..600}; do
    if "$DOCKER" logs "$CONTAINER" 2>&1 | grep -q "Swank listening"; then
      echo "Started ethereum-lisp dev container $CONTAINER (Swank on :$PORT inside)"
      return 0
    fi
    state="$(container_state)" || return $?
    if [[ "$state" != running ]]; then
      echo "Dev container exited during startup:" >&2
      "$DOCKER" logs "$CONTAINER" 2>&1 | tail -40 >&2
      return 1
    fi
    sleep 1
  done
  echo "Timed out waiting for Swank in $CONTAINER" >&2
  "$DOCKER" logs "$CONTAINER" 2>&1 | tail -40 >&2
  return 1
}

stop_server() {
  local state
  state="$(container_state)" || return $?
  if [[ "$state" == absent ]]; then
    echo "No dev container is running."
  else
    require_owned_container
    "$DOCKER" rm -f "$CONTAINER" >/dev/null
    echo "Removed dev container $CONTAINER"
  fi
}

status_server() {
  local state
  state="$(container_state)" || return $?
  echo "Dev container $CONTAINER: $state"
  if image_exists; then
    require_owned_image
    echo "Dev image $IMAGE: present (ownership verified)"
  else
    echo "Dev image $IMAGE: absent"
  fi
  echo "Checkout identity: $CHECKOUT_ID"
  if [ "$state" = running ]; then
    verify_running_boundary
  fi
}

require_running() {
  local state
  state="$(container_state)" || return $?
  if [[ "$state" != running ]]; then
    echo "Dev container $CONTAINER is not running; run: scripts/dev.sh start" >&2
    return 2
  fi
}

verify_running_boundary() {
  require_owned_container
  local network read_only mount published security cap_drop socket_mount
  network="$("$DOCKER" inspect --format '{{.HostConfig.NetworkMode}}' "$CONTAINER")"
  read_only="$("$DOCKER" inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$CONTAINER")"
  mount="$("$DOCKER" inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.RW}}|{{.Source}}{{end}}{{end}}' \
    "$CONTAINER")"
  published="$("$DOCKER" port "$CONTAINER")"
  security="$("$DOCKER" inspect --format '{{json .HostConfig.SecurityOpt}}' "$CONTAINER")"
  cap_drop="$("$DOCKER" inspect --format '{{json .HostConfig.CapDrop}}' "$CONTAINER")"
  socket_mount="$("$DOCKER" inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}present{{end}}{{end}}' \
    "$CONTAINER")"
  [ "$network" = none ] || { echo "ERROR: dev container network is $network" >&2; return 1; }
  [ "$read_only" = true ] || { echo "ERROR: dev container rootfs is writable" >&2; return 1; }
  [ "$mount" = "false|$ROOT" ] || { echo "ERROR: /workspace is not this checkout read-only" >&2; return 1; }
  [ -z "$published" ] || { echo "ERROR: dev container publishes a host port" >&2; return 1; }
  case "$security" in *no-new-privileges*) ;; *) echo "ERROR: no-new-privileges is absent" >&2; return 1 ;; esac
  case "$cap_drop" in *ALL*) ;; *) echo "ERROR: capabilities are not fully dropped" >&2; return 1 ;; esac
  [ -z "$socket_mount" ] || { echo "ERROR: Docker socket is mounted" >&2; return 1; }
  echo "Container boundary: verified (network none, no ports, read-only checkout/rootfs)"
}

doctor() {
  command -v "$DOCKER" >/dev/null 2>&1 || {
    echo "ERROR: Docker CLI is unavailable; host interpreter fallback is forbidden" >&2
    return 1
  }
  "$DOCKER" version >/dev/null 2>&1 || {
    echo "ERROR: Docker daemon is unavailable; host interpreter fallback is forbidden" >&2
    return 1
  }
  status_server
}

identity_field() {
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    checkout-id) printf '%s\n' "$CHECKOUT_ID" ;;
    session-id) printf '%s\n' "$SESSION_ID" ;;
    container) printf '%s\n' "$CONTAINER" ;;
    image) printf '%s\n' "$IMAGE" ;;
    image-fingerprint) printf '%s\n' "$IMAGE_FINGERPRINT" ;;
    port) printf '%s\n' "$PORT" ;;
    *) echo "ERROR: unknown identity field: $1" >&2; return 2 ;;
  esac
}

# Workbench adapter-only path. The canonical client is streamed over stdin;
# it is never copied into this project or persisted in the container.
exec_workbench_eval_client() {
  [ "$#" -ge 2 ] || {
    echo "ERROR: adapter-eval requires CLIENT and FORM" >&2
    return 2
  }
  local client="$1"
  shift
  [ -f "$client" ] || { echo "ERROR: canonical eval client is unavailable" >&2; return 2; }
  require_running || return $?
  local args=(--interactive --workdir /workspace
              --env DEV_SWANK_HOST=127.0.0.1
              --env DEV_SWANK_PORT="$PORT")
  [[ -n "${DEV_EVAL_TIMEOUT:-}" ]] && args+=(--env DEV_EVAL_TIMEOUT="$DEV_EVAL_TIMEOUT")
  [[ -n "${DEV_EVAL_MAX_OUTPUT:-}" ]] && args+=(--env DEV_EVAL_MAX_OUTPUT="$DEV_EVAL_MAX_OUTPUT")
  [[ -n "${DEV_SWANK_PACKAGE:-}" ]] && args+=(--env DEV_SWANK_PACKAGE="$DEV_SWANK_PACKAGE")
  "$DOCKER" exec "${args[@]}" "$CONTAINER" \
    sbcl --script /dev/stdin "$@" <"$client"
}

eval_form() {
  if [[ $# -eq 0 ]]; then
    echo "eval requires a Lisp FORM argument" >&2
    return 2
  fi
  local workbench="${CL_WORKBENCH_BIN:-cl-workbench}"
  if [[ "$workbench" = */* ]]; then
    [ -x "$workbench" ] || {
      echo "ERROR: Common Lisp Workbench CLI is not executable: $workbench" >&2
      return 2
    }
  elif ! command -v "$workbench" >/dev/null 2>&1; then
    echo "ERROR: cl-workbench is unavailable; host Lisp fallback is forbidden" >&2
    return 2
  fi
  "$workbench" repl eval "$@"
}

test_one() {
  if [[ $# -ne 1 ]]; then
    echo "test requires one test name, e.g. trie-fixture-vectors" >&2
    return 2
  fi
  DEV_EVAL_TIMEOUT="${DEV_EVAL_TIMEOUT:-600}" \
    eval_form "(cl-user::run-ethereum-lisp-test \"$1\")"
}

test_all() {
  DEV_EVAL_TIMEOUT="${DEV_EVAL_TIMEOUT:-3600}" \
    eval_form '(cl-user::run-ethereum-lisp-tests)'
}

docs_check() {
  require_running || return $?
  "$DOCKER" exec --interactive=false --workdir /workspace "$CONTAINER" \
    sbcl --non-interactive --load scripts/docs-check.lisp
}

build_cold_image() {
  echo "Building $COLD_IMAGE ..."
  "$DOCKER" build \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$RUNTIME_LABEL=$IMAGE_FINGERPRINT" \
    --file "$ROOT/Dockerfile" --tag "$COLD_IMAGE" "$ROOT"
}

run_cold_container() {
  local fixture_root="${ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT:-}"
  local retained_container="${COLD_TEST_CONTAINER:-}"
  local args=(run --init
              --network none
              --read-only
              --cap-drop ALL
              --security-opt no-new-privileges
              --pids-limit 4096
              --volume "$ROOT:/workspace:ro"
              --tmpfs "/workspace/.cache:exec,mode=1777"
              --tmpfs "/tmp:exec,mode=1777"
              --tmpfs "/private/tmp:exec,mode=1777"
              --workdir /workspace
              --env "E2E_JOBS=${COLD_E2E_JOBS:-2}"
              --env E2E_WORKER_TIMEOUT=900
              --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache)
  if [ -n "$retained_container" ]; then
    case "$retained_container" in
      ethereum-lisp-cold-*)
        case "$retained_container" in
          *[!a-z0-9-]*)
            echo "ERROR: COLD_TEST_CONTAINER must start with ethereum-lisp-cold- and contain only lowercase letters, digits, and hyphens" >&2
            return 2
            ;;
          *)
            args+=(--name "$retained_container")
            ;;
        esac
        ;;
      *)
        echo "ERROR: COLD_TEST_CONTAINER must start with ethereum-lisp-cold- and contain only lowercase letters, digits, and hyphens" >&2
        return 2
        ;;
    esac
  else
    args+=(--rm)
  fi
  if [ -n "$fixture_root" ]; then
    [ -d "$fixture_root" ] || {
      echo "ERROR: execution-spec fixture root is not a directory: $fixture_root" >&2
      return 2
    }
    fixture_root="$(cd "$fixture_root" && pwd -P)"
    args+=(--mount "type=bind,source=$fixture_root,target=/fixtures/execution-spec-tests,readonly")
    args+=(--env ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=/fixtures/execution-spec-tests)
  fi
  local selector
  for selector in \
    ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS \
    ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS \
    ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS \
    ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS
  do
    if [ -n "${!selector:-}" ]; then
      args+=(--env "$selector=${!selector}")
    fi
  done
  "$DOCKER" "${args[@]}" "$COLD_IMAGE" "$@"
}

validate_cold_value() {
  [ "$#" -eq 2 ] || return 2
  local option="$1" value="$2"
  [ -n "$value" ] || {
    echo "ERROR: $option requires a value" >&2
    return 2
  }
  case "$value" in
    *[!A-Za-z0-9_.:/+-]*)
      echo "ERROR: unsafe $option value: $value" >&2
      return 2
      ;;
  esac
}

cold_test() {
  [ "$#" -ge 1 ] || {
    echo "cold-test requires a layer: unit, integration, e2e, or all" >&2
    return 2
  }
  local layer="$1" jobs="" has_test_args=0
  local test_argv=()
  shift
  case "$layer" in
    unit|integration|e2e|all) ;;
    *)
      echo "ERROR: unknown cold-test layer: $layer" >&2
      return 2
      ;;
  esac

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --list|--verbose|--timing)
        [ "$layer" != all ] || {
          echo "ERROR: $1 is not supported with cold-test all" >&2
          return 2
        }
        test_argv+=("$1")
        has_test_args=1
        ;;
      --match|--exclude)
        [ "$layer" != all ] || {
          echo "ERROR: $1 is not supported with cold-test all" >&2
          return 2
        }
        local option="$1"
        shift
        [ "$#" -gt 0 ] || {
          echo "ERROR: $option requires a value" >&2
          return 2
        }
        validate_cold_value "$option" "$1" || return $?
        test_argv+=("$option" "$1")
        has_test_args=1
        ;;
      --slow)
        [ "$layer" != all ] || {
          echo "ERROR: --slow is not supported with cold-test all" >&2
          return 2
        }
        shift
        [ "$#" -gt 0 ] || {
          echo "ERROR: --slow requires a non-negative number" >&2
          return 2
        }
        [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
          echo "ERROR: --slow requires a non-negative number" >&2
          return 2
        }
        test_argv+=(--slow "$1")
        has_test_args=1
        ;;
      --jobs)
        [ "$layer" = e2e ] || [ "$layer" = all ] || {
          echo "ERROR: --jobs is supported only for e2e or all" >&2
          return 2
        }
        shift
        [ "$#" -gt 0 ] || {
          echo "ERROR: --jobs requires a positive integer" >&2
          return 2
        }
        [[ "$1" =~ ^[1-9][0-9]*$ ]] && [ "$1" -le 16 ] || {
          echo "ERROR: --jobs requires an integer from 1 through 16" >&2
          return 2
        }
        jobs="$1"
        ;;
      *)
        echo "ERROR: unsupported cold-test argument: $1" >&2
        return 2
        ;;
    esac
    shift
  done

  build_cold_image
  if [ "$has_test_args" -eq 1 ]; then
    COLD_E2E_JOBS="${jobs:-2}" run_cold_container \
      sh scripts/docker-test.sh "$layer" "${test_argv[@]}"
  else
    COLD_E2E_JOBS="${jobs:-2}" run_cold_container \
      sh scripts/docker-test.sh "$layer"
  fi
}

cold_docs() {
  [ "$#" -eq 0 ] || {
    echo "ERROR: cold-docs accepts no arguments" >&2
    return 2
  }
  build_cold_image
  run_cold_container sbcl --non-interactive --load scripts/docs-check.lisp
}

eest_fixtures() {
  [ "$#" -eq 2 ] || {
    echo "ERROR: eest-fixtures requires BASELINE and DESTINATION" >&2
    return 2
  }
  local baseline="$1" destination="$2" destination_parent
  case "$baseline" in
    legacy-v5.4.0|stable-v20.0.2|amsterdam-v7.2.1) ;;
    *)
      echo "ERROR: unsupported EEST baseline: $baseline" >&2
      return 2
      ;;
  esac
  case "$destination" in
    /*) ;;
    *) destination="$ROOT/$destination" ;;
  esac
  case "$destination" in
    "$ROOT"/.eest-fixtures*) ;;
    *)
      echo "ERROR: EEST destination must be a .eest-fixtures* path in this checkout" >&2
      return 2
      ;;
  esac
  case "$destination" in
    *'..'*|*$'\n'*|*$'\r'*|*$'\t'*|*' '*)
      echo "ERROR: EEST destination must be normalized and contain no whitespace" >&2
      return 2
      ;;
  esac
  [ ! -L "$destination" ] || {
    echo "ERROR: refusing symlink EEST destination: $destination" >&2
    return 2
  }
  destination_parent="$(dirname "$destination")"
  [ -d "$destination_parent" ] || {
    echo "ERROR: EEST destination parent is absent: $destination_parent" >&2
    return 2
  }
  [ "$(cd "$destination_parent" && pwd -P)" = "$ROOT" ] || {
    echo "ERROR: EEST destination parent is not this checkout" >&2
    return 2
  }
  mkdir -p "$destination"

  build_cold_image
  "$DOCKER" run --rm --init \
    --network bridge \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --pids-limit 256 \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,source=$ROOT,target=/workspace,readonly" \
    --mount "type=bind,source=$destination,target=/fixtures-cache" \
    --tmpfs "/tmp:exec,mode=1777" \
    --workdir /workspace \
    --env "EEST_BASELINE=$baseline" \
    "$COLD_IMAGE" \
    sh scripts/fetch-eest-fixtures.sh /fixtures-cache
}

run_cold_scale_gate() {
  local scale_cache="ethereum-lisp-scale-cache-$CHECKOUT_SHORT-$$"
  if "$DOCKER" volume inspect "$scale_cache" >/dev/null 2>&1; then
    echo "ERROR: refusing pre-existing scale cache volume: $scale_cache" >&2
    return 2
  fi
  "$DOCKER" volume create \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$CHECKOUT_LABEL=$CHECKOUT_ID" \
    --label "$MANAGED_LABEL=true" \
    "$scale_cache" >/dev/null
  cleanup_scale_cache() {
    local project checkout managed
    project="$("$DOCKER" volume inspect --format \
      '{{ index .Labels "io.common-lisp-workbench.project" }}' "$scale_cache" 2>/dev/null || true)"
    checkout="$("$DOCKER" volume inspect --format \
      '{{ index .Labels "io.common-lisp-workbench.checkout" }}' "$scale_cache" 2>/dev/null || true)"
    managed="$("$DOCKER" volume inspect --format \
      '{{ index .Labels "io.common-lisp-workbench.managed" }}' "$scale_cache" 2>/dev/null || true)"
    if [ "$project" = ethereum-lisp ] && [ "$checkout" = "$CHECKOUT_ID" ] && \
       [ "$managed" = true ]; then
      if ! "$DOCKER" volume rm "$scale_cache" >/dev/null 2>&1; then
        echo "WARNING: could not remove owned scale cache: $scale_cache" >&2
      fi
    else
      echo "WARNING: refusing cleanup of foreign scale cache: $scale_cache" >&2
    fi
  }
  trap cleanup_scale_cache EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  "$DOCKER" run --rm --init --network none \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --pids-limit 4096 \
    --volume "$ROOT:/workspace:ro" \
    --mount "type=volume,source=$scale_cache,target=/tmp/ethereum-lisp-asdf-cache" \
    --tmpfs "/tmp:exec,mode=1777" \
    --tmpfs "/private/tmp:exec,mode=1777" \
    --workdir /workspace \
    --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
    "$COLD_IMAGE" sbcl --non-interactive \
    --eval '(require :asdf)' \
    --eval '(asdf:load-asd #P"/workspace/ethereum-lisp.asd")' \
    --eval '(asdf:load-system :ethereum-lisp)'

  # The gate intentionally writes more than 384 MiB to /scale-db in the
  # container's disposable writable layer. It never mounts that path to macOS.
  "$DOCKER" run --rm --init --network none \
    --memory 384m --memory-swap 384m \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --pids-limit 4096 \
    --volume "$ROOT:/workspace:ro" \
    --mount "type=volume,source=$scale_cache,target=/tmp/ethereum-lisp-asdf-cache" \
    --tmpfs "/tmp:exec,mode=1777" \
    --tmpfs "/private/tmp:exec,mode=1777" \
    --workdir /workspace \
    --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
    "$COLD_IMAGE" sh scripts/direct-store-scale-gate.sh

  cleanup_scale_cache
  if "$DOCKER" volume inspect "$scale_cache" >/dev/null 2>&1; then
    echo "ERROR: owned scale cache remains after cleanup: $scale_cache" >&2
    return 1
  fi
  trap - EXIT HUP INT TERM
}

cold_scale() {
  [ "$#" -eq 0 ] || {
    echo "ERROR: cold-scale accepts no arguments" >&2
    return 2
  }
  build_cold_image
  run_cold_scale_gate
}

validate_runtime_image() {
  [ "$#" -eq 1 ] || return 2
  local image="$1"
  [ -n "$image" ] || {
    echo "ERROR: runtime image name must not be empty" >&2
    return 2
  }
  case "$image" in
    *[!A-Za-z0-9_.:/+-]*)
      echo "ERROR: unsafe runtime image name: $image" >&2
      return 2
      ;;
  esac
}

runtime_build() {
  [ "$#" -le 1 ] || {
    echo "ERROR: runtime-build accepts at most one image tag" >&2
    return 2
  }
  local image="${1:-ethereum-lisp-runtime:local}"
  local platform="${RUNTIME_PLATFORM:-}"
  validate_runtime_image "$image" || return $?
  case "$platform" in
    ""|linux/amd64|linux/arm64) ;;
    *)
      echo "ERROR: unsupported runtime platform: $platform" >&2
      return 2
      ;;
  esac
  echo "Building reviewed runtime image $image ..."
  local args=(build)
  [ -z "$platform" ] || args+=(--platform "$platform")
  "$DOCKER" "${args[@]}" \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --file "$ROOT/Dockerfile.runtime" \
    --tag "$image" \
    --build-arg "REVISION=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
    "$ROOT"
}

runtime_export() {
  [ "$#" -eq 2 ] || {
    echo "ERROR: runtime-export requires IMAGE and ARTIFACT" >&2
    return 2
  }
  local image="$1" artifact="$2" revision image_revision platform
  validate_runtime_image "$image" || return $?
  case "$artifact" in
    /private/tmp/ethereum-lisp-runtime-*.tar) ;;
    *)
      echo "ERROR: runtime artifact must be a named tar below /private/tmp" >&2
      return 2
      ;;
  esac
  [ ! -e "$artifact" ] || {
    echo "ERROR: refusing existing runtime artifact: $artifact" >&2
    return 1
  }
  revision="$(git -C "$ROOT" rev-parse HEAD)"
  image_revision="$($DOCKER image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image")"
  platform="$($DOCKER image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
  [ "$image_revision" = "$revision" ] || {
    echo "ERROR: runtime image revision is $image_revision, expected $revision" >&2
    return 1
  }
  [ "$platform" = linux/amd64 ] || {
    echo "ERROR: runtime export requires linux/amd64, got $platform" >&2
    return 1
  }
  "$DOCKER" image save --output "$artifact" "$image"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$artifact"
  else
    shasum -a 256 "$artifact"
  fi
}

runtime_smoke() {
  [ "$#" -le 1 ] || {
    echo "ERROR: runtime-smoke accepts at most one image tag" >&2
    return 2
  }
  local image="${1:-ethereum-lisp-runtime:local}"
  validate_runtime_image "$image" || return $?
  "$ROOT/scripts/hive-runtime-smoke.sh" "$image"
}

shadow_proxy_format() {
  [ "$#" -eq 0 ] || {
    echo "ERROR: shadow-proxy-format accepts no arguments" >&2
    return 2
  }
  build_cold_image
  "$DOCKER" run --rm --init --network none --read-only \
    --user "$(id -u):$(id -g)" \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --pids-limit 128 \
    --volume "$ROOT/tools/shadow-proxy:/workspace:rw" \
    --tmpfs "/tmp:exec,mode=1777" \
    --workdir /workspace \
    "$COLD_IMAGE" gofmt -w main.go main_test.go
}

shadow_proxy_test() {
  [ "$#" -eq 0 ] || {
    echo "ERROR: shadow-proxy-test accepts no arguments" >&2
    return 2
  }
  "$DOCKER" build \
    --network none \
    --target test \
    --file "$ROOT/tools/shadow-proxy/Dockerfile" \
    "$ROOT/tools/shadow-proxy"
}

shadow_proxy_build() {
  [ "$#" -le 1 ] || {
    echo "ERROR: shadow-proxy-build accepts at most one image tag" >&2
    return 2
  }
  local image="${1:-ethereum-lisp-shadow-engine-proxy:local}"
  local platform="${SHADOW_PROXY_PLATFORM:-}"
  validate_runtime_image "$image" || return $?
  case "$platform" in
    ""|linux/amd64|linux/arm64) ;;
    *)
      echo "ERROR: unsupported shadow proxy platform: $platform" >&2
      return 2
      ;;
  esac
  local args=(build)
  [ -z "$platform" ] || args+=(--platform "$platform")
  "$DOCKER" "${args[@]}" \
    --network none \
    --file "$ROOT/tools/shadow-proxy/Dockerfile" \
    --tag "$image" \
    --build-arg "REVISION=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
    "$ROOT/tools/shadow-proxy"
}

shadow_proxy_export() {
  [ "$#" -eq 2 ] || {
    echo "ERROR: shadow-proxy-export requires IMAGE and ARTIFACT" >&2
    return 2
  }
  local image="$1" artifact="$2" revision image_revision platform
  validate_runtime_image "$image" || return $?
  case "$artifact" in
    /private/tmp/ethereum-lisp-shadow-engine-proxy-*.tar) ;;
    *)
      echo "ERROR: shadow proxy artifact must be a named tar below /private/tmp" >&2
      return 2
      ;;
  esac
  [ ! -e "$artifact" ] || {
    echo "ERROR: refusing existing shadow proxy artifact: $artifact" >&2
    return 1
  }
  revision="$(git -C "$ROOT" rev-parse HEAD)"
  image_revision="$($DOCKER image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image")"
  platform="$($DOCKER image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
  [ "$image_revision" = "$revision" ] || {
    echo "ERROR: shadow proxy image revision is $image_revision, expected $revision" >&2
    return 1
  }
  [ "$platform" = linux/amd64 ] || {
    echo "ERROR: shadow proxy export requires linux/amd64, got $platform" >&2
    return 1
  }
  "$DOCKER" image save --output "$artifact" "$image"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$artifact"
  else
    shasum -a 256 "$artifact"
  fi
}

shadow_proxy_smoke() {
  [ "$#" -le 1 ] || {
    echo "ERROR: shadow-proxy-smoke accepts at most one image tag" >&2
    return 2
  }
  local image="${1:-ethereum-lisp-shadow-engine-proxy:local}"
  local revision container network port user image_revision metrics
  revision="$(git -C "$ROOT" rev-parse HEAD)"
  container="ethereum-lisp-shadow-proxy-smoke-$CHECKOUT_SHORT"
  network="ethereum-lisp-shadow-proxy-smoke-$CHECKOUT_SHORT"
  validate_runtime_image "$image" || return $?
  [ "$($DOCKER image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = \
    linux/arm64 ] || {
      echo "ERROR: local shadow proxy smoke requires a native linux/arm64 image" >&2
      return 1
  }
  image_revision="$($DOCKER image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "$image")"
  [ "$image_revision" = "$revision" ] || {
    echo "ERROR: shadow proxy image revision is $image_revision, expected $revision" >&2
    return 1
  }
  user="$($DOCKER image inspect --format '{{.Config.User}}' "$image")"
  case "$user" in
    ""|0|0:*|*:0|root|root:*)
      echo "ERROR: shadow proxy image user is not explicitly non-root: $user" >&2
      return 1
      ;;
  esac
  if "$DOCKER" container inspect "$container" >/dev/null 2>&1; then
    echo "ERROR: refusing existing shadow proxy smoke container: $container" >&2
    return 1
  fi
  if "$DOCKER" network inspect "$network" >/dev/null 2>&1; then
    echo "ERROR: refusing existing shadow proxy smoke network: $network" >&2
    return 1
  fi
  cleanup_shadow_proxy_smoke() {
    "$DOCKER" stop --time 3 "$container" >/dev/null 2>&1 || true
    "$DOCKER" network rm "$network" >/dev/null 2>&1 || true
  }
  trap cleanup_shadow_proxy_smoke EXIT HUP INT TERM
  "$DOCKER" network create --internal \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$CHECKOUT_LABEL=$CHECKOUT_ID" \
    "$network" >/dev/null
  "$DOCKER" run --rm --detach --name "$container" \
    --label "$PROJECT_LABEL=ethereum-lisp" \
    --label "$CHECKOUT_LABEL=$CHECKOUT_ID" \
    --network "$network" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 128m --memory-swap 128m \
    --pids-limit 64 \
    --env SHADOW_PROXY_PRIMARY_URL=http://127.0.0.1:1 \
    --env SHADOW_PROXY_SECONDARY_URL=http://127.0.0.1:2 \
    "$image" >/dev/null
  local ready=0
  for _ in {1..30}; do
    if "$DOCKER" exec "$container" \
       /usr/local/bin/shadow-engine-proxy --probe-path=/healthz >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  [ "$ready" -eq 1 ] || {
    "$DOCKER" logs "$container" >&2 || true
    echo "ERROR: shadow proxy health endpoint did not become ready" >&2
    return 1
  }
  metrics="$("$DOCKER" exec "$container" \
    /usr/local/bin/shadow-engine-proxy --probe-path=/metrics)"
  for name in \
    shadow_primary_requests_total \
    shadow_primary_errors_total \
    shadow_mirror_started_total \
    shadow_mirror_succeeded_total \
    shadow_mirror_errors_total \
    shadow_mirror_dropped_total \
    shadow_status_mismatches_total \
    shadow_head_observations_total \
    shadow_head_rpc_errors_total \
    shadow_head_lag_violations_total \
    shadow_head_root_mismatches_total \
    shadow_head_latest_lag_blocks \
    shadow_head_max_lag_blocks
  do
    printf '%s\n' "$metrics" | grep -Fx "$name 0" >/dev/null || {
      echo "ERROR: shadow proxy metric did not start at zero: $name" >&2
      return 1
    }
  done
  "$DOCKER" container inspect --format \
    'shadow-proxy-smoke user={{.Config.User}} read-only={{.HostConfig.ReadonlyRootfs}} memory={{.HostConfig.Memory}} memory-swap={{.HostConfig.MemorySwap}} caps={{json .HostConfig.CapDrop}} security={{json .HostConfig.SecurityOpt}} pids={{.HostConfig.PidsLimit}} networks={{len .NetworkSettings.Networks}}' \
    "$container"
  echo "shadow-proxy-smoke revision=$revision health=ready metrics=zero"
  cleanup_shadow_proxy_smoke
  trap - EXIT HUP INT TERM
}

hive_adapter_smoke() {
  [ "$#" -le 1 ] || {
    echo "ERROR: hive-adapter-smoke accepts at most one runtime image tag" >&2
    return 2
  }
  local image="${1:-ethereum-lisp-runtime:local}"
  local image_name image_tag
  validate_runtime_image "$image" || return $?
  case "$image" in
    *:*) image_name="${image%:*}"; image_tag="${image##*:}" ;;
    *)   image_name="$image"; image_tag="latest" ;;
  esac
  RUNTIME_IMAGE="$image_name" RUNTIME_TAG="$image_tag" \
    "$ROOT/scripts/hive-adapter-smoke.sh"
}

show_logs() {
  require_owned_container
  "$DOCKER" logs "$CONTAINER" "$@"
}

open_shell() {
  require_running || return $?
  "$DOCKER" exec --interactive --tty --workdir /workspace "$CONTAINER" bash
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  start) start_server ;;
  stop) stop_server ;;
  status) status_server ;;
  doctor) doctor ;;
  identity) identity_field "$@" ;;
  build) build_image ;;
  adapter-eval) exec_workbench_eval_client "$@" ;;
  eval) eval_form "$@" ;;
  test) test_one "$@" ;;
  test-all) test_all ;;
  docs-check) docs_check ;;
  cold-test) cold_test "$@" ;;
  cold-docs) cold_docs "$@" ;;
  cold-scale) cold_scale "$@" ;;
  eest-fixtures) eest_fixtures "$@" ;;
  runtime-build) runtime_build "$@" ;;
  runtime-export) runtime_export "$@" ;;
  runtime-smoke) runtime_smoke "$@" ;;
  shadow-proxy-format) shadow_proxy_format "$@" ;;
  shadow-proxy-test) shadow_proxy_test "$@" ;;
  shadow-proxy-build) shadow_proxy_build "$@" ;;
  shadow-proxy-export) shadow_proxy_export "$@" ;;
  shadow-proxy-smoke) shadow_proxy_smoke "$@" ;;
  hive-adapter-smoke) hive_adapter_smoke "$@" ;;
  logs) show_logs "$@" ;;
  shell) open_shell ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
