#!/bin/sh
set -eu

sbcl_command=${SBCL:-sbcl}
e2e_jobs=${E2E_JOBS:-4}
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
report_root=$(mktemp -d "${TMPDIR:-/tmp}/ethereum-lisp-test-layers.XXXXXX")
pids=""

cleanup() {
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  rm -rf "$report_root"
}
trap cleanup EXIT HUP INT TERM

run_layer() {
  layer=$1
  shift
  (
    cd "$root"
    exec "$sbcl_command" --script tests/run-tests.lisp --layer "$layer" "$@"
  ) >"$report_root/$layer.out" 2>"$report_root/$layer.err" &
  pid=$!
  pids="$pids $pid"
  eval "${layer}_pid=$pid"
}

run_layer unit
run_layer integration
run_layer e2e --jobs "$e2e_jobs"

failed=0
for layer in unit integration e2e; do
  eval "pid=\${${layer}_pid}"
  if ! wait "$pid"; then
    failed=1
  fi
done
pids=""

for layer in unit integration e2e; do
  printf '%s\n' "== $layer =="
  cat "$report_root/$layer.out"
  if [ -s "$report_root/$layer.err" ]; then
    cat "$report_root/$layer.err" >&2
  fi
done

exit "$failed"
