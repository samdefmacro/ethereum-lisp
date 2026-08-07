#!/bin/bash
#
# Report this node's enode URL. Hive copies this into the simulator container
# and runs it there to find out how to dial us.
#
# It prints what the client reports and nothing else, which today is "null":
# admin_nodeInfo answers -32603 because its handler takes the node store guard
# that the RPC request already holds. Even once that is fixed the address will
# be loopback, because --nat is parsed by the CLI and then dropped on the way to
# MAKE-DEVNET-NODE. Both are client defects (docs/hive-gate.md); synthesising an
# enode here would hide them behind the harness and make the devp2p suites look
# closer to passing than they are.

set -e

RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
    "localhost:8545")

echo "$RESPONSE" | jq -r '.result.enode'
