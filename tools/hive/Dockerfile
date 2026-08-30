# Hive client definition for ethereum-lisp.
#
# Copy this directory into a Hive checkout as clients/ethereum-lisp/ (see
# scripts/hive-run.sh, which does that and pins the checkout) and Hive will
# build it with `docker build .` in that directory -- so everything ADDed below
# must live in this directory, not elsewhere in the repo.
#
# Following Hive's convention (clients/go-ethereum/Dockerfile), the client
# itself comes from a prebuilt image rather than being compiled here: building
# it needs SBCL, a C toolchain and a RocksDB compile, and a Hive run should not
# pay for that. Build the base first with:
#
#   docker build --file Dockerfile.runtime --tag ethereum-lisp-runtime:local .
#
# then point Hive at it with a client file:
#
#   - client: ethereum-lisp
#     build_args:
#       baseimage: ethereum-lisp-runtime
#       tag: local
ARG baseimage=ethereum-lisp-runtime
ARG tag=latest

FROM ${baseimage}:${tag}

# The entry point needs jq for the genesis translation, and the enode retriever
# needs curl. Neither belongs in the runtime image itself, which is why they are
# installed in this derived test-harness layer instead.
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq \
    && rm -rf /var/lib/apt/lists/*

# Hive reads /version.txt after the build and attaches it to every test result.
# The commit is embedded in src/api/engine/capabilities.lisp while the runtime
# executable is saved, so this is the same exact-revision identity the Engine
# API reports rather than an adapter-local Git description.
RUN /usr/local/bin/ethereum-lisp version > /version.txt

ADD ethereum-lisp.sh /ethereum-lisp.sh
ADD mapper.jq /mapper.jq
RUN chmod +x /ethereum-lisp.sh

RUN mkdir /hive-bin
ADD enode.sh /hive-bin/enode.sh
RUN chmod +x /hive-bin/enode.sh

# The runtime image runs as uid 10001 with a read-only-friendly layout, and the
# adapter keeps that: /hive is the only thing it writes. Hive uploads
# /genesis.json as root-owned 0644, which this user can read.
RUN mkdir -p /hive && chown 10001:10001 /hive
USER 10001:10001

# 8545 public JSON-RPC (hive's liveness check), 8551 Engine API, 30303 devp2p.
# 8546 is not exposed: the client has a WebSocket server, but --ws.api is
# accepted and discarded, so the port would not honour a namespace list.
EXPOSE 8545 8551 30303

ENTRYPOINT ["/ethereum-lisp.sh"]
