#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT/.dev-runtime/swank-dev"
METRICS_LOG="${DEV_EVAL_METRICS_LOG:-$RUNTIME_DIR/eval-metrics.log}"
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
    tools/ckzg-ffi/shim.c \
    tools/bls-ffi/shim.c
  do
    printf '%s ' "$input"
    git hash-object "$input"
  done | sha256_stdin
)"
IMAGE_SHORT="${IMAGE_FINGERPRINT:0:12}"
IMAGE="${ETHEREUM_LISP_DEV_IMAGE:-ethereum-lisp-dev:go1.24-bookworm-$IMAGE_SHORT}"
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
  logs               Show the dev container's output
  build              Build the dev image
  shell              Open an interactive shell in the dev container
  help               Show this help

Environment:
  ETHEREUM_LISP_DEV_IMAGE      Dev image tag, default is build-input-specific
                               ethereum-lisp-dev:go1.24-bookworm-<input hash>. Kept
                               separate from the DOCKER_TEST_IMAGE tag so
                               building it never disturbs a concurrent
                               `make docker-test-*` run.
  ETHEREUM_LISP_DEV_CONTAINER  Container name, default is checkout-specific.
                               An override is accepted only when its ownership
                               labels match this physical checkout.
  ETHEREUM_LISP_SWANK_PORT     Swank port INSIDE the container, default 4006
  DEV_EVAL_TIMEOUT             Eval timeout seconds, default 20 (test: 600,
                               test-all: 3600); on timeout the form is
                               interrupted and the image survives
  DEV_EVAL_MAX_OUTPUT          Output cap in chars, default 10000
Eval exit codes: 0 ok, 1 lisp error, 2 connection error, 3 timed out
(interrupted), 4 hard hang (restart the image). Every eval is logged to
.dev-runtime/swank-dev/eval-metrics.log (timestamp, exit code, duration,
form snippet).

Cold-image test layers stay in the Makefile (make docker-test-unit /
docker-test-integration / docker-test-e2e) — use those for final
verification; use the warm image for the development loop.
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

# Automatic per-eval metrics: timestamp, exit code (0 ok / 1 lisp-error /
# 2 connection / 3 timeout-interrupted / 4 hard-hang), duration, form snippet.
log_metrics() { # $1 rc, $2 start_epoch, $3 form
  local snip
  snip=$(printf '%s' "$3" | tr '\n' ' ' | cut -c1-80)
  mkdir -p "$RUNTIME_DIR"
  printf '%s rc=%s dur_s=%s form=%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$(( $(date +%s) - $2 ))" "$snip" \
    >> "$METRICS_LOG" 2>/dev/null || true
}

# The eval client runs inside the container too, so it reaches Swank over the
# container's loopback and the port is never exposed to the host.
exec_eval_client() {
  local args=(--interactive=false --workdir /workspace
              --env DEV_SWANK_HOST=127.0.0.1
              --env DEV_SWANK_PORT="$PORT")
  [[ -n "${DEV_EVAL_TIMEOUT:-}" ]] && args+=(--env DEV_EVAL_TIMEOUT="$DEV_EVAL_TIMEOUT")
  [[ -n "${DEV_EVAL_MAX_OUTPUT:-}" ]] && args+=(--env DEV_EVAL_MAX_OUTPUT="$DEV_EVAL_MAX_OUTPUT")
  # Read and evaluate in a domain package, so a form can use unqualified
  # symbols the way the sources do (e.g. DEV_SWANK_PACKAGE=ETHEREUM-LISP.TEST).
  [[ -n "${DEV_SWANK_PACKAGE:-}" ]] && args+=(--env DEV_SWANK_PACKAGE="$DEV_SWANK_PACKAGE")
  "$DOCKER" exec "${args[@]}" "$CONTAINER" \
    sbcl --script scripts/dev-swank-eval.lisp "$@"
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
  require_running || return $?
  local start rc=0
  start=$(date +%s)
  exec_eval_client "$@" || rc=$?
  log_metrics "$rc" "$start" "$*"
  return $rc
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
  logs) show_logs "$@" ;;
  shell) open_shell ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
