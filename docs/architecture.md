# Architecture

`ethereum-lisp` is a small execution-layer client. Package declarations load
before all implementations, and implementation dependencies move in one
direction, from protocol primitives toward node orchestration:

```text
packages (declarations only)
foundation
  -> protocol
       -> runtime core -----------+
       -> storage core -----------+-> application services
                                          |-> networking (devp2p / eth sync)
                                          |-> persistence adapters
                                          +-> API -> HTTP transport
networking + persistence adapters + HTTP transport --------> app / CLI
```

Lower layers must not depend on higher layers. When a higher layer needs a small
helper from a lower layer, move the helper down instead of reaching back through
a broad package dependency. The production ASDF definition follows these layers:
`runtime-core`/`storage-core` are parallel siblings over `protocol`, and
`networking`, `persistence-adapters`, and `api` are parallel siblings over
`application-services`.

## Where the per-file map lives

This document does not catalog every source file, because three authorities
already describe that and stay current on their own:

- **structure and dependency edges** — `ethereum-lisp.asd` (module layout and
  explicit `:depends-on`);
- **each file's responsibility** — its first comment block (`docs/style.md`
  requires one);
- **symbol ownership and the acyclic package graph** — the architecture tests.

What follows is only what those sources do not state: the boundary philosophy,
the non-obvious layer assignments, and the invariants that the code depends on
but does not explain.

## Package boundaries

`ethereum-lisp` is the canonical public API. The legacy `ethereum-lisp.core`
package is generated directly from that API and owns no symbols or
implementation. Only these two provide compatibility re-exports; domain packages
do not re-export higher-layer symbols.

File size and name prefixes are not module boundaries. A refactor must first
identify an owner, its public contract, and the allowed dependency direction,
and split code only when the resulting units have cohesive behavior and
communicate through an explicit API or state object. Files under `src/packages/`
are declaration manifests loaded before all implementations; their grouping
preserves declaration order and does not assign implementation-layer ownership.

The EVM shows the intended shape of a public boundary: `ethereum-lisp.evm` is a
facade that re-exports only the supported context, result, precompile-address,
and execution API, while `ethereum-lisp.evm.internal` owns the runtime,
precompile, and interpreter implementation symbols. Application layers must not
use the internal package.

## Layer bridge points

These packages sit at a layer that is not obvious from their directory. Placing
them by their physical location instead reintroduces dependency cycles:

- **`execution-service`, `canonical-chain`, `genesis-state`** are application
  services, not storage. `execution-service` projects state-db and chain-store
  and commits blocks atomically; `canonical-chain` coordinates chain-store,
  txpool, reorg, and filter notification; `genesis-state` bridges genesis input
  and mutable state. The domains they compose have no dependency on each other.
- **`engine` (payload status)** decides import/cache status using the chain
  store, so it is an application service, not a protocol model. The pure payload
  values live in `engine-payloads` under `protocol`.
- **`txpool.application`** is transaction preflight and admission policy, not
  txpool storage; `eth_sendRawTransaction` delegates to it.
- **`eth-sync`** (the networking layer) drives the eth wire protocol over a live
  RLPx connection. It depends on application services and the `p2p`/`eth-wire`
  protocol, and stays independent of the chain store by importing blocks through
  a caller-supplied callback.
- **persistence adapters** live physically under
  `src/storage/node-store/persistence/` but depend on application services:
  `staged-import` calls `execution-service` to validate payloads before
  materialization. They therefore load after application services, not as part
  of `storage-core`.

## Key invariants

Non-obvious properties the implementation relies on:

- **Atomic import.** An imported block publishes state, receipts, indexes, and
  forkchoice effects together; a failed validation or durable write never
  exposes a partial chain view. Write-batch application is atomic — memory swaps
  a shadow table on success; the file backend appends the whole batch as one
  CRC-framed, fsynced log record before the in-memory table changes.
- **State-root memoization.** Each `state-object` memoizes its storage root. A
  state root is taken over every account, but a block touches a handful, and
  rebuilding the untouched accounts' storage tries was ~93% of the cost
  (1769ms → 149ms per block at 400 accounts × 16 slots). `state-db-set-storage`
  is the only writer of a storage table and thus the only place the memo is
  dropped; deleting an account drops the whole object, and a clone keeps the
  memo because its storage is `equal`. A stale memo would be a wrong state root,
  so differential tests compare the memoized root against a cold recomputation.
- **Log-structured database.** The file backend is an append-only file of
  CRC-framed records replayed into an in-memory table on open, with
  fsync-per-write durability, torn-tail recovery, threshold-triggered compaction
  via a temp-file rename, and migration of v1 whole-file s-expression databases.
  Opens are pure reads; torn-tail truncation and v1 migration happen on the
  first durable write, so a rejected or read-only artifact is never modified.
  Concurrent handles on one path are not serialized.
- **State storage: diff vs baseline.** A block's state is either a full baseline
  snapshot in block-prefixed flat tables or a hash-addressed diff against its
  parent, resolved by walking the diff chain to the nearest baseline; stored
  defaults and `:ABSENT` markers tombstone zeroed slots and destroyed accounts.
  Commit policy writes a diff while the chain stays under the store's baseline
  interval (default 128) and a fresh baseline otherwise; pruning promotes a kept
  diff to a baseline before its ancestors drop.
- **Staged import boundary.** Staged import is a private, versioned, offline,
  block-serial, single-writer path. It binds authority/chain/genesis and the
  full chain configuration, pins a finalized anchor, advances header, body,
  execution, receipt-verification, and transaction-index stages atomically,
  persists reverse-order unwind intent, and hydrates only a fresh startup store.
  It does not publish canonical indexes or checkpoints.
- **Dev KV-handle cache.** Opening a log-structured database replays the whole
  file, so reopening one per write makes each persist O(file) and a run
  O(blocks²) in bytes replayed. The devnet CLI optionally caches one open handle
  per canonical output path for the node's lifetime
  (`call-with-devnet-cli-kv-database-cache`, off by default); a poisoned handle
  is dropped so the next caller reopens.

## Dependency Rules

- Consensus data types may use primitives, RLP, crypto, trie, and chain rules.
- devp2p/RLPx and eth-wire codecs are protocol types that use only foundation
  primitives (crypto, AES, HMAC, RLP, snappy) and chain rules; socket and
  datagram I/O live in the connection/discovery drivers and the networking
  layer, not in the codecs.
- State may use account types and trie commitments, but not genesis parsing.
- Genesis-state assembly may bridge genesis input and mutable state.
- Node state may compose chain-store state and txpool index state; neither
  domain may own the other domain's mutable state.
- EVM may use state and consensus types, but not RPC or CLI.
- Execution may use EVM, state, and consensus types, but not chain store.
- Application services may bridge runtime and storage-core APIs.
- Networking, persistence, and RPC/API adapters are sibling layers over
  application services; runtime and storage-core packages must not depend on
  them. The `eth-sync` layer additionally uses the p2p/eth-wire protocol and
  imports blocks through a caller-supplied callback rather than depending on the
  chain store directly.
- Only `ethereum-lisp` and `ethereum-lisp.core` provide compatibility
  re-exports; domain packages do not re-export higher-layer symbols.
- Architecture tests require the project package graph to remain acyclic and
  every non-facade package to own each symbol it exports.
- RPC may use execution and store APIs, but protocol types must not depend on
  RPC JSON shapes.
- HTTP transport may call RPC dispatch, but RPC dispatch should not depend on
  sockets or listener state.
- CLI and devnet lifecycle are top-level orchestration only.
