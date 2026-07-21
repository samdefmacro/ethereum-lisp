#!/bin/sh
set -eu

# Build the EIP-2537 backend once and exec it, so the caller supervises the
# helper binary directly rather than a `go run` wrapper process. A persistent
# backend is terminated by signal, and only an exec'd binary receives it.

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
tool_dir="$script_dir/../tools/bls12381"
cache_dir="$script_dir/../.cache/go-build-bls12381"
tmp_dir="$script_dir/../.cache/go-tmp-bls12381"
bin_dir="$script_dir/../.cache/bin"

mkdir -p "$cache_dir" "$tmp_dir" "$bin_dir"

cd "$tool_dir"
env \
  GOWORK=off \
  GOCACHE="$cache_dir" \
  GOTMPDIR="$tmp_dir" \
  GOPROXY=off \
  GOSUMDB=off \
  go build -mod=vendor -o "$bin_dir/bls12381" .

exec "$bin_dir/bls12381" "$@"
