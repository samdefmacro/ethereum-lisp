#!/bin/bash
#
# Hive entry point for ethereum-lisp.
#
# Translates the Hive client contract (docs/clients.md at Hive
# dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c) into this client's CLI. Every flag
# below is one that src/app/cli/options/options.lisp genuinely implements --
# commit 05ef79d5 made the CLI reject unknown keys and behaviour-selecting
# no-ops, so an adapter that guessed would fail at startup instead of running a
# configuration nobody asked for.
#
# Where Hive asks for something the client does not have, this script says so
# and exits, rather than starting a node that will fail the tests for a reason
# the log does not explain. The full list, and what each one blocks, is in
# docs/hive-gate.md.
#
# Files placed by the simulator:
#   /genesis.json  (mandatory) geth-format genesis; mapped by /mapper.jq
#   /chain.rlp     (optional)  imported as a concatenated RLP block stream
#   /blocks/       (optional)  imported as numerically sorted individual blocks

set -e

client=/usr/local/bin/ethereum-lisp
workdir=/hive
genesis_out="$workdir/genesis.json"
jwtsecret="$workdir/jwtsecret"
datadir="$workdir/datadir"

mkdir -p "$datadir"

unsupported() {
    echo "FATAL: hive requested $1, which this client does not implement." >&2
    echo "       See docs/hive-gate.md; the adapter refuses rather than" >&2
    echo "       starting a node that would silently ignore it." >&2
    exit 1
}

# Hive reaches a client through its bridge address, not through the host
# port-publish mapping.  Advertise that address explicitly: the node otherwise
# emits 0.0.0.0 in admin_nodeInfo, which is a bind address, never a dial target.
# Do this before starting the client and fail closed when the container cannot
# identify a non-loopback IPv4 address.  Guessing an enode here would make a
# devp2p result non-reproducible.
advertised_ip="$(hostname -i 2>/dev/null | tr ' ' '\n' | awk \
    '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0 !~ /^127\./ { print; exit }')"
if [ -z "$advertised_ip" ]; then
    echo "FATAL: cannot determine a non-loopback IPv4 address for Hive enode advertisement" >&2
    exit 1
fi

# --- Refuse what we cannot do -----------------------------------------------

# No consensus-engine selection exists at all: no clique signer, no local block
# sealing. Post-merge suites drive blocks in over the Engine API and set none of
# these.
if [ -n "$HIVE_CLIQUE_PERIOD" ] || [ -n "$HIVE_CLIQUE_PRIVATEKEY" ]; then
    unsupported "clique proof-of-authority sealing (HIVE_CLIQUE_*)"
fi
if [ -n "$HIVE_MINER" ] || [ -n "$HIVE_MINER_EXTRA" ]; then
    unsupported "mining (HIVE_MINER/HIVE_MINER_EXTRA)"
fi

# --graphql is accepted by the CLI and does nothing, so mapping it would enter a
# client into the GraphQL suite that answers no GraphQL.
if [ -n "$HIVE_GRAPHQL_ENABLED" ]; then
    unsupported "the GraphQL endpoint (HIVE_GRAPHQL_ENABLED)"
fi

# --syncmode is rejected outright by the CLI. Full/archive is the only thing the
# node does, so those two map to "pass nothing"; snap and light do not.
case "$HIVE_NODETYPE" in
    "" | full | archive)
        ;;
    snap)
        unsupported "snap sync (HIVE_NODETYPE=snap)"
        ;;
    *)
        unsupported "HIVE_NODETYPE=$HIVE_NODETYPE"
        ;;
esac

# AMSTERDAM-EXECUTION-AVAILABLE-P is false and the V5/V6 Engine methods are
# unadvertised, so an Amsterdam run would activate a fork the client cannot
# execute.
if [ -n "$HIVE_AMSTERDAM_TIMESTAMP" ]; then
    unsupported "Amsterdam activation (HIVE_AMSTERDAM_TIMESTAMP)"
fi

# --- Configure the chain ----------------------------------------------------

if [ ! -f /genesis.json ]; then
    echo "FATAL: /genesis.json is missing; hive must upload it." >&2
    exit 1
fi

jq -f /mapper.jq /genesis.json > "$genesis_out"

case "$HIVE_LOGLEVEL" in
    4 | 5)
        echo "Genesis:"
        cat "$genesis_out"
        ;;
    *)
        echo "Genesis (alloc elided, use --sim.loglevel 4 or 5 for all of it):"
        jq '. + {"alloc": (.alloc|length|tostring + " accounts")}' "$genesis_out"
        ;;
esac

# The Engine API secret Hive's engine simulator authenticates with:
# globals.DefaultJwtTokenSecretBytes, the 32 ASCII bytes
# "secretsecretsecretsecretsecretse". The engine-auth suite tests wrong and
# stale tokens against it, so it has to be this exact value.
echo "0x7365637265747365637265747365637265747365637265747365637265747365" > "$jwtsecret"
chmod 600 "$jwtsecret"

# --- Report options deliberately not represented by a client flag ----------

if [ -n "$HIVE_LOGLEVEL" ]; then
    echo "NOTE: HIVE_LOGLEVEL=$HIVE_LOGLEVEL ignored; the client has no" >&2
    echo "      log-level flag (--verbosity is accepted and discarded)." >&2
fi

# --- Flags ------------------------------------------------------------------

# An array, not a string: --http.vhosts takes a literal '*', and a string
# expanded unquoted would let the shell glob it into the directory listing.
flags=(
    --genesis "$genesis_out"
    --datadir "$datadir"
    # Bind on all interfaces: the simulator reaches the container by its bridge
    # address, never over loopback.
    --http --http.addr 0.0.0.0 --http.port 8545
    --http.api admin,debug,eth,net,txpool,web3
    --http.vhosts '*' --http.corsdomain '*'
    --authrpc.addr 0.0.0.0 --authrpc.port 8551
    --authrpc.jwtsecret "$jwtsecret" --authrpc.vhosts '*'
    --port 30303
    --nat "extip:$advertised_ip"
)

# geth's adapter defaults to 1337 to keep clients off mainnet heuristics; use
# the same default so a simulator that sets neither behaves the same here.
if [ -n "$HIVE_NETWORK_ID" ]; then
    flags+=(--networkid "$HIVE_NETWORK_ID")
else
    flags+=(--networkid 1337)
fi

if [ -n "$HIVE_BOOTNODE" ]; then
    flags+=(--bootnodes "$HIVE_BOOTNODE")
fi

if [ -n "$HIVE_TARGET_GAS_LIMIT" ]; then
    flags+=(--miner.gaslimit "$HIVE_TARGET_GAS_LIMIT")
fi

if [ -n "$HIVE_ALLOW_UNPROTECTED_TX" ]; then
    flags+=(--rpc.allow-unprotected-txs)
fi

# The CLI imports these before it opens listeners.  A deterministic invalid
# fixture block leaves the already durable valid prefix in place and the node
# starts from that prefix, which is Hive's required last-valid-block behavior.
if [ -f /chain.rlp ]; then
    flags+=(--import-chain /chain.rlp)
fi
if [ -d /blocks ]; then
    flags+=(--import-blocks /blocks)
fi

echo "Container address: $advertised_ip"
echo "Running ethereum-lisp ${flags[*]}"

# exec so the client is PID 1 and takes hive's SIGTERM directly; the CLI
# installs its own signal handlers when serving.
exec "$client" "${flags[@]}"
