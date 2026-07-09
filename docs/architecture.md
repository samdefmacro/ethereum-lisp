# Architecture

`ethereum-lisp` is organized as a small execution-layer client. Code should
move from protocol primitives toward node orchestration in one direction:

```text
bytes / hex / types
rlp / trie encoding / trie
crypto
chain config and fork rules
consensus data types
state
evm
execution
chain store and txpool
rpc schemas and handlers
http transport
node and cli
```

Lower layers must not depend on higher layers. When a higher layer needs a
small helper from a lower layer, move the helper down instead of reaching back
through a broad package dependency.

## Current Package Boundary

The project still has a large `ethereum-lisp.core` package. Refactors should
first split files while keeping this package stable, then tighten exports and
only split packages when the load order and public API are clear.

The first mechanical split is:

- `genesis.lisp`: genesis JSON parsing, alloc/config decoding, and genesis
  metadata helpers.
- `core-constants.lisp`: protocol constants shared across core modules.
- `accounts.lisp`: state account encoding and hashing.
- `transactions.lisp`: transaction envelopes, RLP, signing hashes, senders.
- `receipts.lisp`: withdrawals, logs, blooms, receipts, trie-list roots.
- `txpool-types.lisp`: txpool index structure required by the store type.
- `blocks.lisp`: block header/body structures, block hashing, and block RLP
  conversion.
- `consensus-validation.lisp`: shared block/transaction validation helpers
  and fee-market calculations used by consensus, RPC, and txpool paths.
- `block-access-list.lisp`: execution request hashing, shared field
  validators, and Amsterdam block access list RLP/validation.
- `genesis-block.lisp`: fork-aware genesis header and block construction.
- `kzg.lisp`: command-backed KZG verifier hooks and blob sidecar KZG
  validation.
- `engine-payloads.lisp`: Engine payload structs, forkchoice payload
  attributes, payload id derivation, and block/payload conversion.
- `chain-store-types.lisp`: in-memory chain store records, filter cursors,
  blob lookup records, and shared store key helpers.
- `chain-store-copy.lisp`: defensive copying, store snapshot/restore, and
  atomic commit helpers for the in-memory chain store.
- `chain-store-memory.lisp`: in-memory canonical chain, state projection,
  filter, invalid payload, prepared payload, and blob sidecar caches.
- `txpool.lisp`: pending/queued/basefee/blob txpool admission, promotion,
  revalidation, and mining selection helpers.
- `chain-store-persistence.lisp`: chain-store KV export/import records,
  validation, staging, and restore consistency.
- `engine-payload-status.lisp`: Engine forkchoice/newPayload status for the
  in-memory chain store.
- `engine-rpc-protocol.lisp`: JSON-RPC envelopes, response helpers, and
  Engine/public method filters.
- `engine-rpc-http.lisp`: JSON-RPC request dispatch, HTTP parsing, JWT auth,
  listener abstractions, and stream telemetry.
## Dependency Rules

- Consensus data types may use primitives, RLP, crypto, trie, and chain rules.
- State may use consensus account types and trie commitments.
- EVM may use state and consensus types, but not RPC or CLI.
- Execution may use EVM, state, consensus types, and chain store.
- RPC may use execution and store APIs, but protocol types must not depend on
  RPC JSON shapes.
- HTTP transport may call RPC dispatch, but RPC dispatch should not depend on
  sockets or listener state.
- CLI and devnet lifecycle are top-level orchestration only.

## Refactor Order

Prefer behavior-preserving slices:

1. Move cohesive definitions into a smaller file.
2. Update ASDF load order.
3. Run the full test suite.
4. Only then extract shared helpers or change package exports.

Avoid mixing file moves, semantic fixes, and API changes in one slice.
