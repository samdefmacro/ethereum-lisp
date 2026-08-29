#!/bin/bash
#
# Report this node's enode URL. Hive copies this into the simulator container
# and runs it there to find out how to dial us.
#
# It prints the node's own advertised enode and nothing else.  The entry point
# supplies --nat extip:<container IPv4>, while the public admin handler obtains
# this value without recursively taking the node-store lock.  Do not synthesize
# an address here: Hive's devp2p result must exercise precisely what the node
# reports through admin_nodeInfo.

set -e

RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
    "localhost:8545")

echo "$RESPONSE" | jq -r '.result.enode'
