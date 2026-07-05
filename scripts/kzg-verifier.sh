#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
tool_dir="$script_dir/../tools/kzg-verifier"
cache_dir="$script_dir/../.cache/go-build-kzg"
tmp_dir="$script_dir/../.cache/go-tmp-kzg"

mkdir -p "$cache_dir" "$tmp_dir"

cd "$tool_dir"
exec env \
  GOWORK=off \
  GOCACHE="$cache_dir" \
  GOTMPDIR="$tmp_dir" \
  GOPROXY=off \
  GOSUMDB=off \
  go run -mod=vendor . "$@"
