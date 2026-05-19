# Reference Map

This map records the modules to compare while implementing each layer.

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

Reth is the Rust-side architecture reference. The local clone is expected at
`references/reth` when available; until then these paths are the target map for
the clone to provide.

Availability rule:

- `references/reth` is optional and may be absent in local workspaces.
- Tasks that need Rust-side source comparison should check whether
  `references/reth` exists before inspecting it.
- When the clone is absent, reference-comparison tasks should skip the Rust
  source read cleanly and report that only geth/Nethermind were available.
- When the clone is present, task reports should name the Reth commit or version
  inspected alongside any paths used.

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

## Comparison rule

For each implemented feature:

1. Identify the geth source path and tests.
2. Identify the Nethermind source path and tests.
3. Identify the Reth/Rust source path or crate boundary when the feature has a
   clear Rust architecture analogue and the local reference is available.
4. Record the exact reference commit, release tag, or version inspected for
   each reference client that supports a parity claim. If a local clone is
   absent, explicitly report the downgrade as "fixture-only",
   "single-client comparison", or "geth/Nethermind-only comparison".
5. Write Lisp behavior tests with Ethereum fixture examples where possible.
6. Prefer consensus behavior over local API shape when the clients organize
   code differently.
