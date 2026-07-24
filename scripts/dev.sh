#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT/.dev-runtime/swank-dev"
METRICS_LOG="$RUNTIME_DIR/eval-metrics.log"
PORT="${ETHEREUM_LISP_SWANK_PORT:-4006}"

DOCKER="${DOCKER:-docker}"
IMAGE="${ETHEREUM_LISP_DEV_IMAGE:-ethereum-lisp-dev:go1.24-bookworm}"
CONTAINER="${ETHEREUM_LISP_DEV_CONTAINER:-ethereum-lisp-dev}"

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
  ETHEREUM_LISP_DEV_IMAGE      Dev image tag, default
                               ethereum-lisp-dev:go1.24-bookworm. Kept
                               separate from the DOCKER_TEST_IMAGE tag so
                               building it never disturbs a concurrent
                               `make docker-test-*` run.
  ETHEREUM_LISP_DEV_CONTAINER  Container name, default ethereum-lisp-dev.
                               Override it to run two agents' warm images
                               side by side on one machine.
  ETHEREUM_LISP_SWANK_PORT     Swank port INSIDE the container, default 4006
  DEV_EVAL_TIMEOUT             Eval timeout seconds, default 20 (test: 600,
                               test-all: 3600); on timeout the form is
                               interrupted and the image survives
  DEV_EVAL_MAX_OUTPUT          Output cap in chars, default 10000
  DOCKER                       Docker CLI, default docker

Eval exit codes: 0 ok, 1 lisp error, 2 connection error, 3 timed out
(interrupted), 4 hard hang (restart the image). Every eval is logged to
.dev-runtime/swank-dev/eval-metrics.log (timestamp, exit code, duration,
form snippet).

Cold-image test layers stay in the Makefile (make docker-test-unit /
docker-test-integration / docker-test-e2e) — use those for final
verification; use the warm image for the development loop.
USAGE
}

container_state() { # prints running|stopped|absent
  local state
  state="$($DOCKER inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
  case "$state" in
    running) echo running ;;
    "") echo absent ;;
    *) echo stopped ;;
  esac
}

image_exists() {
  $DOCKER image inspect "$IMAGE" >/dev/null 2>&1
}

build_image() {
  echo "Building $IMAGE ..."
  $DOCKER build --file "$ROOT/Dockerfile" --tag "$IMAGE" "$ROOT"
}

# Mirrors the Makefile's DOCKER_TEST_RUN mounts so the warm image sees the
# same filesystem shape as the cold gates: the workspace read-only, with
# writable tmpfs where the suite needs to write. --network none still
# provides loopback, which is all Swank needs.
start_server() {
  mkdir -p "$RUNTIME_DIR"
  case "$(container_state)" in
    running)
      echo "Dev container already running: $CONTAINER"
      return 0
      ;;
    stopped)
      echo "Removing exited container $CONTAINER"
      $DOCKER rm -f "$CONTAINER" >/dev/null
      ;;
  esac
  image_exists || build_image
  $DOCKER run --detach --init --name "$CONTAINER" \
    --network none \
    --volume "$ROOT:/workspace:ro" \
    --tmpfs "/workspace/.cache:exec,mode=1777" \
    --tmpfs "/private/tmp:exec,mode=1777" \
    --workdir /workspace \
    --env ETHEREUM_LISP_SWANK_PORT="$PORT" \
    --env ETHEREUM_LISP_DEV_IMAGE_WAIT=1 \
    --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
    "$IMAGE" \
    sbcl --noinform --load scripts/dev-image.lisp >/dev/null

  local i
  for i in {1..600}; do
    if $DOCKER logs "$CONTAINER" 2>&1 | grep -q "Swank listening"; then
      echo "Started ethereum-lisp dev container $CONTAINER (Swank on :$PORT inside)"
      return 0
    fi
    if [[ "$(container_state)" != running ]]; then
      echo "Dev container exited during startup:" >&2
      $DOCKER logs "$CONTAINER" 2>&1 | tail -40 >&2
      return 1
    fi
    sleep 1
  done
  echo "Timed out waiting for Swank in $CONTAINER" >&2
  $DOCKER logs "$CONTAINER" 2>&1 | tail -40 >&2
  return 1
}

stop_server() {
  if [[ "$(container_state)" == absent ]]; then
    echo "No dev container is running."
  else
    $DOCKER rm -f "$CONTAINER" >/dev/null
    echo "Removed dev container $CONTAINER"
  fi
}

status_server() {
  echo "Dev container $CONTAINER: $(container_state)"
  echo "Dev image $IMAGE: $(image_exists && echo present || echo absent)"
}

require_running() {
  if [[ "$(container_state)" != running ]]; then
    echo "Dev container $CONTAINER is not running; run: scripts/dev.sh start" >&2
    return 2
  fi
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
  $DOCKER exec "${args[@]}" "$CONTAINER" \
    sbcl --script scripts/dev-swank-eval.lisp "$@"
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
  $DOCKER exec --interactive=false --workdir /workspace "$CONTAINER" \
    sbcl --non-interactive --load scripts/docs-check.lisp
}

show_logs() {
  $DOCKER logs "$CONTAINER" "$@"
}

open_shell() {
  require_running || return $?
  $DOCKER exec --interactive --tty --workdir /workspace "$CONTAINER" bash
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  start) start_server ;;
  stop) stop_server ;;
  status) status_server ;;
  build) build_image ;;
  eval) eval_form "$@" ;;
  test) test_one "$@" ;;
  test-all) test_all ;;
  docs-check) docs_check ;;
  logs) show_logs "$@" ;;
  shell) open_shell ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
