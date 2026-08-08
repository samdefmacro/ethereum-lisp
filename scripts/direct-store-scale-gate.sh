#!/bin/sh
set -eu

# This wrapper runs inside the memory-limited container created by the
# Makefile.  Separate SBCL processes make the second invocation a real restart.
sbcl --script scripts/direct-store-scale-gate.lisp \
  seed /scale-db 32768 16384 402653184

# Prove the persisted dataset itself, not only the sum of input value lengths,
# exceeds the container's 384 MiB RAM limit. The bodies are pseudo-random, but
# this physical-size check prevents an unexpectedly compressible fixture from
# turning the acceptance gate into a smaller-than-RAM test.
database_kib=$(du -sk /scale-db | cut -f1)
if [ "$database_kib" -le 393216 ]; then
  echo "scale database is only ${database_kib} KiB; expected more than 393216 KiB" >&2
  exit 1
fi
echo "PERSISTED_SIZE_OK database_kib=${database_kib} ram_limit_kib=393216"

sbcl --script scripts/direct-store-scale-gate.lisp \
  open /scale-db 268435456 30
