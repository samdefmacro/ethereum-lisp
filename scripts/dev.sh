#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT/.dev-runtime/swank-dev"
PIDFILE="$RUNTIME_DIR/swank.pid"
LOGFILE="$RUNTIME_DIR/swank.log"
METRICS_LOG="$RUNTIME_DIR/eval-metrics.log"
PORT="${ETHEREUM_LISP_SWANK_PORT:-4006}"
HOST="127.0.0.1"

usage() {
  cat <<'USAGE'
Usage: scripts/dev.sh COMMAND [ARGS]

Persistent Swank development helper for ethereum-lisp. Wraps
scripts/dev-image.lisp (which loads the project + tests and starts Swank when
ETHEREUM_LISP_SWANK_PORT is set) with lifecycle management and a hardened
eval client.

Commands:
  start              Start the warm dev image (tests loaded, Swank listening)
  stop               Stop the helper-managed image
  status             Show whether the helper-managed image/port is running
  eval FORM          Evaluate FORM in the warm image through Swank
  test NAME          Run one test: eval (run-ethereum-lisp-test "NAME")
  test-all           Run the full suite in the warm image (long timeout)
  help               Show this help

Environment:
  ETHEREUM_LISP_SWANK_PORT  Swank port, default 4006
  DEV_EVAL_TIMEOUT          Eval timeout seconds, default 20 (test: 600,
                            test-all: 3600); on timeout the form is
                            interrupted and the image survives
  DEV_EVAL_MAX_OUTPUT       Output cap in chars, default 10000

Eval exit codes: 0 ok, 1 lisp error, 2 connection error, 3 timed out
(interrupted), 4 hard hang (restart the image). Every eval is logged to
.dev-runtime/swank-dev/eval-metrics.log (timestamp, exit code, duration,
form snippet).

Cold-image test layers stay in the Makefile (make test-unit /
test-integration / test-e2e) — use those for final verification; use the
warm image for the development loop.
USAGE
}

is_pid_running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

port_listener() {
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
}

wait_for_port() {
  local i
  for i in {1..120}; do
    if port_listener | grep -q ":${PORT}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_server() {
  mkdir -p "$RUNTIME_DIR"
  if is_pid_running; then
    echo "Dev image already running: pid $(cat "$PIDFILE")"
    return 0
  fi
  if port_listener | grep -q ":${PORT}"; then
    echo "Port ${PORT} already has a listener; reusing it."
    return 0
  fi
  : > "$LOGFILE"
  (
    cd "$ROOT"
    exec env ETHEREUM_LISP_SWANK_PORT="$PORT" ETHEREUM_LISP_DEV_IMAGE_WAIT=1 \
      sbcl --noinform --load scripts/dev-image.lisp >>"$LOGFILE" 2>&1
  ) &
  echo $! > "$PIDFILE"
  if wait_for_port; then
    echo "Started ethereum-lisp dev image on ${HOST}:${PORT} (pid $(cat "$PIDFILE"))"
    echo "Log: $LOGFILE"
  else
    echo "Timed out waiting for Swank on port ${PORT}" >&2
    echo "Log: $LOGFILE" >&2
    return 1
  fi
}

stop_server() {
  if is_pid_running; then
    local pid
    pid="$(cat "$PIDFILE")"
    kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped dev image pid $pid"
  else
    rm -f "$PIDFILE"
    echo "No helper-managed dev image is running."
  fi
}

status_server() {
  if is_pid_running; then
    echo "Helper-managed process: running pid $(cat "$PIDFILE")"
  else
    echo "Helper-managed process: not running"
  fi
  if port_listener | grep -q ":${PORT}"; then
    echo "Port ${PORT}: listening"
  else
    echo "Port ${PORT}: not listening"
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

eval_form() {
  if [[ $# -eq 0 ]]; then
    echo "eval requires a Lisp FORM argument" >&2
    return 2
  fi
  local start rc=0
  start=$(date +%s)
  (cd "$ROOT" && DEV_SWANK_HOST="$HOST" DEV_SWANK_PORT="$PORT" \
    sbcl --script scripts/dev-swank-eval.lisp "$@") || rc=$?
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

cmd="${1:-help}"
shift || true
case "$cmd" in
  start) start_server ;;
  stop) stop_server ;;
  status) status_server ;;
  eval) eval_form "$@" ;;
  test) test_one "$@" ;;
  test-all) test_all ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
