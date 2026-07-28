# Reference Map

This map records useful modules for work that needs reference-client source
comparison.

## go-ethereum

- Common types: `references/go-ethereum/common/types.go`
- Hex utilities: `references/go-ethereum/common/hexutil`
- RLP: `references/go-ethereum/rlp`
- Chain configuration and forks: `references/go-ethereum/params/config.go`
- Blocks and transactions: `references/go-ethereum/core/types`
- State database: `references/go-ethereum/core/state`
- Trie: `references/go-ethereum/trie`
- Raw database: `references/go-ethereum/core/rawdb`
- EVM: `references/go-ethereum/core/vm`
- Block processing: `references/go-ethereum/core/state_processor.go`
- Validation: `references/go-ethereum/core/block_validator.go`
- Engine API: `references/go-ethereum/beacon/engine`

## Nethermind

- Core domain types: `references/nethermind/src/Nethermind/Nethermind.Core`
- Address/hash/Keccak: `references/nethermind/src/Nethermind/Nethermind.Core/Crypto`
- RLP tests: `references/nethermind/src/Nethermind/Ethereum.Rlp.Test`
- Blocks and transactions: `references/nethermind/src/Nethermind/Nethermind.Core`
- State: `references/nethermind/src/Nethermind/Nethermind.State`
- Trie: `references/nethermind/src/Nethermind/Nethermind.Trie`
- EVM: `references/nethermind/src/Nethermind/Nethermind.Evm`
- Precompiles: `references/nethermind/src/Nethermind/Nethermind.Evm.Precompiles`
- Block processing: `references/nethermind/src/Nethermind/Nethermind.Consensus`
- JSON-RPC: `references/nethermind/src/Nethermind/Nethermind.JsonRpc`

## Reth / Rust

Reth is an optional Rust-side architecture reference. Its local clone may be
absent; the paths below are useful when it is available.

- Common primitives: `references/reth/crates/primitives`
- Chain specification and fork rules: `references/reth/crates/chainspec`
- Consensus validation: `references/reth/crates/consensus` and
  `references/reth/crates/ethereum/consensus`
- Transaction and block domain types: `references/reth/crates/primitives` and
  `references/reth/crates/ethereum/primitives`
- EVM integration: `references/reth/crates/evm`,
  `references/reth/crates/ethereum/evm`, and the upstream `revm` behavior
- Trie and state roots: `references/reth/crates/trie`
- Storage/provider boundaries: `references/reth/crates/storage/provider` and
  `references/reth/crates/storage/db`
- Chain import, canonical state, and unwind/reorg shape:
  `references/reth/crates/engine/tree`, `references/reth/crates/stages`, and
  provider canonical-chain traits
- Engine API: `references/reth/crates/engine`
- JSON-RPC: `references/reth/crates/rpc`
- Transaction pool: `references/reth/crates/transaction-pool`
- Networking and sync architecture: `references/reth/crates/net`

## devp2p and peering

- Peer lifecycle, inbound slots, and dial scheduling: `go-ethereum/p2p/server.go`,
  `p2p/dial.go`, `p2p/peer.go`
- eth protocol handlers and gossip propagation: `go-ethereum/eth/handler.go`,
  `eth/protocols/eth/handlers.go`
- `admin_*` RPC shapes: `go-ethereum/node/api.go`

**No `references/` checkout exists on this machine.** The peering work therefore
makes NO parity claim: every constant it introduces — the peer limit, the accept
tick, the handshake budget, the keepalive interval, the idle timeout — is
documented in its own docstring as our policy, not as matching another client.
Under the project contract a parity claim must name an exact version or commit
and the code path exercised, so checking these against a pinned clone is
separate work that must come before any such wording.

## Upstream versions actually fetched and read

No `references/` checkout exists on this machine, so reference source has been
fetched over the network into scratch space for the duration of a specific piece
of work. Scratch space is not durable, so the record of which version a
comparison read lives in the document that makes the claim, not alongside the
fetched copies.

The gas-accounting comparison recorded in `docs/gas-parity.md` read
go-ethereum `v1.17.5` (`9621c6ad10934a01b5514886fb6fbd87640b6c05`), `v1.16.6`
(`386c3de6c45f3e185279e6760a17f88fb98dc81a`), and `v1.16.3` (tag, commit hash
not recorded); Nethermind `1.39.2` (`6568910591e4618dc49d54285b6213c3753d7243`),
`1.34.1` (`c4238a37787abd95cc849aa817ffa9a6eef567dd`), and `master`
(`e52dc19a56a46f58170a730822580774d403c838`); and `ethereum/execution-specs` at
`85a36ccae03b0958d9bfb0a6e6d9e08f0e5c79db` and at an unpinned `master` head
fetched 2026-07-28. Which version backs which finding matters and is tabulated
per finding in that document — the spread across versions is itself a recorded
limitation there.

## Using the map

Consult reference clients when protocol behavior is ambiguous, consensus
compatibility is at risk, or the work makes an explicit parity claim. Ordinary
feature development does not require a multi-client comparison report.
