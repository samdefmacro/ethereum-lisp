#!/bin/sh
set -eu

# Opt-in byte-level interoperability gate against pinned go-ethereum commit
# 38271784c2b31926563806da9a2e023b88f5e7a8 (v1.17.6-unstable).
# All toolchains run in session-namespaced Docker images; the final checks run
# offline so a green result cannot depend on a mutable remote checkout.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SLUG=${ETHEREUM_LISP_NET08_SLUG:-ethereum-lisp-gap-network-sync-net08}
PROJECT_IMAGE="ethereum-lisp-sbcl-test:${SLUG}"
INTEROP_IMAGE="ethereum-lisp-geth-interop:${SLUG}"

docker build \
  --label "agent=${SLUG}" \
  --file "$ROOT/Dockerfile" \
  --tag "$PROJECT_IMAGE" \
  "$ROOT"

docker build \
  --label "agent=${SLUG}" \
  --build-arg "PROJECT_IMAGE=${PROJECT_IMAGE}" \
  --file "$ROOT/tests/interop/discv5/Dockerfile" \
  --tag "$INTEROP_IMAGE" \
  "$ROOT/tests/interop/discv5"

docker run --rm --init --network none \
  --label "agent=${SLUG}" \
  --volume "$ROOT:/workspace:ro" \
  --tmpfs /tmp/ethereum-lisp-asdf-cache:exec,mode=1777 \
  --workdir /workspace \
  --env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
  "$PROJECT_IMAGE" \
  sh scripts/docker-test.sh unit --match DISCV5-OFFICIAL

docker run --rm --network none \
  --label "agent=${SLUG}" \
  "$INTEROP_IMAGE" \
  go test -count=1 /opt/discv5-interop
