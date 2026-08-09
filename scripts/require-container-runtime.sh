#!/bin/sh
# Source this guard before invoking an application toolchain. It is a
# fail-closed workflow check, not an adversarial sandbox boundary.
if [ "${ETHEREUM_LISP_CONTAINER_RUNTIME:-}" != 1 ]; then
  printf '%s\n' \
    'ERROR: ethereum-lisp application toolchains run only inside the project container.' \
    'Use cl-workbench, scripts/dev.sh, or make docker-*; no host fallback is permitted.' \
    >&2
  exit 2
fi
