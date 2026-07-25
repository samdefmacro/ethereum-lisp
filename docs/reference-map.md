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

## Using the map

Consult reference clients when protocol behavior is ambiguous, consensus
compatibility is at risk, or the work makes an explicit parity claim. Ordinary
feature development does not require a multi-client comparison report.
