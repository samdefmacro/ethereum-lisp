#!/bin/sh
set -eu

layer=${1:-all}
if [ "$#" -gt 0 ]; then
  shift
fi

case "$layer" in
  unit|integration|e2e|all)
    ;;
  *)
    printf '%s\n' "usage: $0 [unit|integration|e2e|all]" >&2
    exit 2
    ;;
esac

# The all-layer runner starts three SBCL processes concurrently. Compile and
# load the suite once first so those workers only read the shared ASDF cache.
sbcl --script tests/run-tests.lisp --layer all --list >/dev/null

case "$layer" in
  unit)
    sbcl --script tests/run-tests.lisp --layer unit "$@"
    ;;
  integration)
    sbcl --script tests/run-tests.lisp --layer integration "$@"
    ;;
  e2e)
    sbcl --script tests/run-tests.lisp \
      --layer e2e \
      --jobs "${E2E_JOBS:-2}" \
      --worker-timeout "${E2E_WORKER_TIMEOUT:-900}" \
      "$@"
    ;;
  all)
    if [ "$#" -ne 0 ]; then
      printf '%s\n' "the all-layer Docker gate does not accept focused arguments" >&2
      exit 2
    fi
    make test-all E2E_JOBS="${E2E_JOBS:-2}"
    ;;
esac
