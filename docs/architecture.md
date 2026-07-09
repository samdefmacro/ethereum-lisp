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
- `transactions-legacy.lisp`: legacy transaction envelope, RLP, signing hash,
  EIP-155 chain-id handling, and sender recovery.
- `transactions-access-list.lisp`: EIP-2930 access lists and access-list
  transaction encoding/decoding.
- `transactions-dynamic-fee.lisp`: EIP-1559 dynamic-fee transaction
  encoding/decoding and signing hash.
- `transactions-blob.lisp`: EIP-4844 blob transaction and blob sidecar
  structures.
- `transactions-set-code.lisp`: EIP-7702 authorization tuples, delegation
  code helpers, and set-code transaction encoding/decoding.
- `transactions.lisp`: cross-type transaction accessors, fork validation,
  gas-price calculation, unified encoding/decoding, and sender dispatch.
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
- `chain-store-filters.lisp`: in-memory block, log, and pending transaction
  filter registration and notifications.
- `chain-store-cache.lisp`: in-memory remote block, invalid payload,
  prepared payload, and blob sidecar caches.
- `chain-store-memory.lisp`: in-memory canonical chain and forkchoice
  checkpoint storage wrappers.
- `chain-store-state.lisp`: retained state projection, pruning, and
  deterministic account iteration for the in-memory chain store.
- `chain-store-canonical.lisp`: canonical block indexes, transaction
  location indexing, reorg handling, and txpool reinsertion after head changes.
- `txpool-index.lisp`: pending txpool subpool tables, sender/nonce indexes,
  replacement checks, and deterministic subpool views.
- `txpool.lisp`: engine payload store wrappers for pending/queued/basefee/blob
  txpool subpool admission and indexing.
- `txpool-views.lisp`: txpool lookup, list, count, sender view, and mining
  selection helpers.
- `txpool-promotion.lisp`: queued/basefee transaction promotion and
  overbudget parked-transaction pruning.
- `txpool-cleanup.lisp`: txpool stale, expired, sender-code, gas-limit,
  blob-fee, invalid-sender cleanup, and pending revalidation.
- `chain-store-export.lisp`: chain-store KV export records for indexes,
  blocks, state snapshots, txpool records, and payload caches.
- `chain-store-persistence-core.lisp`: chain-store KV import table staging,
  block/header indexes, canonical chain indexes, and checkpoints.
- `chain-store-persistence-receipts.lisp`: receipt/log RLP decoding and
  receipt record validation.
- `chain-store-persistence-state.lisp`: state snapshot import, trie-root
  reconstruction, and state-root validation.
- `chain-store-persistence-locations.lisp`: transaction-location record import
  and log-index consistency checks.
- `chain-store-persistence-txpool.lisp`: txpool record import, static/fork
  validation, subpool restoration, and post-import txpool consistency.
- `chain-store-persistence-side-data.lisp`: invalid-tipset and remote-block
  record import.
- `chain-store-persistence-blobs.lisp`: blob sidecar record decoding and
  versioned-hash indexing.
- `chain-store-persistence-prepared-payloads.lisp`: prepared-payload record
  decoding and cache restoration.
- `chain-store-persistence.lisp`: top-level chain-store KV import
  orchestration.
- `block-validation-forks.lisp`: fork-specific block header gas, blob gas,
  withdrawals, requests, Amsterdam, and Merge field rules.
- `block-validation-header.lisp`: header shape validation, parent linkage,
  fork-aware header checks, and chain-config header validation.
- `block-validation-body.lisp`: withdrawal, transaction, ommer, blob-gas, and
  body-config validation helpers.
- `block-validation-roots.lisp`: body root checks, receipt/log validation, and
  execution commitment validation.
- `block-validation.lisp`: block validation compatibility loader.
- `engine-payload-status.lisp`: Engine forkchoice/newPayload status for the
  in-memory chain store.
- `engine-rpc-protocol.lisp`: JSON-RPC envelopes, response helpers, and
  Engine/public method filters.
- `engine-rpc-codecs.lisp`: Engine API field coercion, payload/status object
  rendering, capability lists, and payload attribute validation.
- `engine-rpc-new-payload.lisp`: `engine_newPayload*`, capability exchange,
  client version, and transition configuration handlers.
- `engine-rpc-errors.lisp`: Engine API error condition and protocol error
  codes shared by Engine RPC handlers.
- `engine-rpc-payloads.lisp`: `engine_getPayload*` payload-id lookup and
  payload envelope handlers.
- `engine-rpc-blobs.lisp`: `engine_getBlobs*` and payload-body hash/range
  query handlers.
- `engine-rpc-forkchoice.lisp`: `engine_forkchoiceUpdated*` checkpoint
  updates, prepared payload construction, and payload-id caching.
- `engine-rpc.lisp`: final Engine API method dispatch.
- `public-rpc-params.lisp`: shared public JSON-RPC address, hash, block tag,
  and block id parameter coercion.
- `public-rpc-core.lisp`: web3/net/basic eth handlers and fee history
  helpers for the public JSON-RPC surface.
- `public-rpc-state.lisp`: public account state, proof, call simulation, gas
  estimation, and access-list handlers.
- `public-rpc-transaction-objects.lisp`: transaction JSON object conversion,
  access list rendering, pending transaction helpers, and shared JSON array
  normalization.
- `public-rpc-transactions.lisp`: raw transaction and transaction lookup
  handlers.
- `public-rpc-txpool.lisp`: sendRawTransaction admission, txpool views, and
  pending transaction handlers.
- `public-rpc-receipts.lisp`: log, receipt, and block receipt result
  construction and handlers.
- `public-rpc-blocks.lisp`: public header, block, pending block, transaction
  count, and ommer handlers.
- `public-rpc.lisp`: public log/filter handlers and final method dispatch.
- `engine-rpc-http-auth.lisp`: Engine API JWT token creation, validation, and
  signing helpers.
- `engine-rpc-http-wire.lisp`: HTTP request parsing, response formatting, CORS
  and host filtering, and request/response telemetry extraction.
- `engine-rpc-http.lisp`: JSON-RPC request dispatch and HTTP request/stream
  handlers.
- `engine-rpc-http-service.lisp`: HTTP service/listener abstractions, socket
  listener construction, and service-level telemetry.
- `state-types.lisp`: state constants, mutable state records, proof records,
  range records, and state key coercion helpers.
- `state-db.lisp`: mutable account/code/storage access, copy/restore helpers,
  and storage trie proof primitives.
- `state-roots.lisp`: account trie construction, account proofs, and state
  root rendering.
- `state-proofs.lisp`: proof result construction, verification, and JSON-RPC
  proof object conversion.
- `state-ranges.lisp`: account/storage range iteration and deterministic
  state export helpers.
- `state-genesis.lisp`: genesis allocation application, genesis state roots,
  and genesis block/header construction.
- `state-transactions.lisp`: withdrawal balance updates, intrinsic gas, and
  standalone legacy transaction execution fallback.
- `state.lisp`: state package compatibility loader.
- `evm-types.lisp`: EVM errors, result/context records, precompile address
  activation, gas constants, and fixed precompile tables.
- `evm-runtime.lisp`: EVM word, stack, memory, access-list, transient-storage,
  state mutation, account, create/call gas, and block-context helpers.
- `evm-precompiles.lisp`: Ethereum precompile implementations, BN254/KZG and
  BLAKE2F helpers, and precompile dispatch.
- `evm.lisp`: bytecode interpreter loop and opcode execution.
- `execution-context.lisp`: execution constants, transaction field
  validation, fork-rule helpers, access prewarming, and EVM context creation.
- `execution-message.lisp`: call simulation, message application, signed
  transaction sender recovery, and transaction-list execution.
- `execution-block-validation.lisp`: block body/fork shape checks, execution
  root validation, and block header snapshot/restore helpers.
- `execution.lisp`: block execution entry points and atomic chain-store
  commit helpers.
- `cli-types.lisp`: devnet CLI records, defaults, embedded dev genesis, and
  shutdown signal helpers.
- `cli-files.lisp`: CLI file, datadir, JWT secret, and KV database path
  helpers.
- `cli-devnet.lisp`: devnet node construction, lifecycle threads, listener
  startup, mining, journaling, and summaries.
- `cli-args.lisp`: command-line token normalization, option arity metadata,
  boolean token handling, and command-token lookup.
- `cli-config.lisp`: TOML config parsing and config-to-CLI option mapping.
- `cli-parsers.lisp`: CLI scalar parsers for ports, durations, quantities,
  addresses, RPC prefixes, API module filters, CORS, and vhosts.
- `cli-options.lisp`: geth-compatible devnet option aggregation.
- `cli-output.lisp`: CLI usage, version, summary, ready-file, and pid-file
  output helpers.
- `cli-telemetry.lisp`: CLI telemetry fields, KZG verifier scoping, and error
  logging.
- `cli-init.lisp`: `init` command option parsing and datadir initialization.
- `cli.lisp`: top-level command dispatcher.
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
