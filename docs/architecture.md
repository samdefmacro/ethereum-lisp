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

- `core-constants.lisp`: protocol constants shared across core modules.
- `accounts.lisp`: state account encoding and hashing.
- `transactions.lisp`: transaction envelopes, RLP, signing hashes, senders.
- `receipts.lisp`: withdrawals, logs, blooms, receipts, trie-list roots.
- `txpool-types.lisp`: txpool index structure required by the store type.
- `txpool.lisp`: pending/queued/basefee/blob txpool admission, promotion,
  revalidation, and mining selection helpers.
- `chain-store-persistence.lisp`: chain-store KV export/import records,
  validation, staging, and restore consistency.
- `core.lisp`: remaining genesis/block/store/RPC/KZG implementation.

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
