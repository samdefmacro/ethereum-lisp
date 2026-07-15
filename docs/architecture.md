# Architecture

`ethereum-lisp` is organized as a small execution-layer client. Package
declarations load before all implementations, while implementation dependencies
move from protocol primitives toward node orchestration in one direction:

```text
packages (declarations only)
foundation
  -> protocol
       -> runtime core -----------+
       -> storage core -----------+-> application services
                                          |-> persistence adapters
                                          +-> API -> HTTP transport
persistence adapters + HTTP transport --------> app / CLI
```

Lower layers must not depend on higher layers. When a higher layer needs a
small helper from a lower layer, move the helper down instead of reaching back
through a broad package dependency.

The physical source tree and the production ASDF definition follow these
ownership layers. Package declarations and each implementation module retain
their required internal serial order, while explicit `:depends-on` edges keep
runtime/storage and persistence/API as parallel sibling layers where no real
dependency exists.

## Current Package Boundary

`ethereum-lisp` is the canonical public API. The legacy `ethereum-lisp.core`
package is generated directly from that API and owns no symbols or
implementation. File size and name prefixes are not module boundaries: a
refactor must first identify an owner, its public contract, and the allowed
dependency direction. Split code only when the resulting units have cohesive
behavior and communicate through an explicit API or state object.

Files under `src/packages/` are declaration manifests loaded before all
implementations. Their grouping preserves package declaration order; it does
not assign implementation-layer ownership. Key source responsibilities are:

- `src/packages/foundation.lisp`: base package definitions for bytes, hex,
  database, telemetry, RLP, types, crypto, and trie.
- `src/packages/json.lisp`: generic JSON and transport-independent JSON-RPC
  package declarations shared by genesis, Engine API, and public RPC.
- `src/packages/protocol.lisp`: independent chain-configuration and transaction
  domain package definitions.
- `src/packages/models.lisp`: account and receipt protocol-model package
  definitions, ordered by their explicit domain dependencies.
- `src/packages/blocks.lisp`: execution-request, block-access-list, and block
  package definitions with their dependency order made explicit.
- `src/packages/genesis.lisp`: genesis data, parsing, and block-construction
  package definition over JSON and protocol-model contracts.
- `src/packages/consensus.lisp`: pure transaction, header, body, fork, root, and
  receipt consensus-validation package definition.
- `src/packages/package-tools.lisp`: package-definition helpers for
  owner-grouped public APIs and exact compatibility re-exports.
- `src/packages/facade.lisp`: the single public API manifest, grouped by the
  package that owns each symbol. Every public symbol is listed once.
- `src/packages/core.lisp`: generated compatibility facade over
  `ethereum-lisp`; it owns no symbols and cannot expose internal APIs.
- `src/packages/runtime.lisp`: state, state-proof JSON, genesis-state, EVM,
  execution, and execution-service package declarations. Their implementations
  span runtime, API-adapter, and application-service directories.
- `src/packages/cli.lisp`: the CLI composition package. It consumes the canonical
  public API and explicitly imports the small txpool and persistence ports
  needed for node assembly; it does not depend on `ethereum-lisp.core`.
- `src/foundation/database/`: key-value database protocol, chain-record key
  encoding, memory/file backends, write batches, and chain-record access helpers.
- `src/foundation/crypto/constants.lisp`: hash, KZG, secp256k1, SHA-256,
  Keccak, and RIPEMD-160 constants and round tables.
- `src/foundation/crypto/words.lisp`: 32-bit/64-bit rotation and endian
  load/store helpers.
- `src/foundation/crypto/keccak.lisp`: Ethereum legacy Keccak-256 sponge
  implementation and its canonical empty code/trie hashes.
- `src/foundation/crypto/sha256.lisp`: SHA-256 compression and digest helpers.
- `src/foundation/crypto/ripemd160.lisp`: RIPEMD-160 compression and digest helpers.
- `src/foundation/crypto/kzg.lisp`: KZG commitment versioned-hash conversion.
- `src/foundation/crypto/math.lisp`: fixed-width integer encoding and modular arithmetic.
- `src/foundation/crypto/secp256k1.lisp`: secp256k1 point arithmetic, key/address
  derivation, and public key recovery.
- `src/foundation/trie/encoding.lisp`: hex-prefix nibble encoding primitives.
- `src/foundation/trie/types.lisp`: Merkle Patricia Trie node and in-memory store types.
- `src/foundation/trie/store.lisp`: mutable trie entry put/get/delete and ordered scans.
- `src/foundation/trie/nodes.lisp`: canonical node construction, node RLP references, and
  root hash derivation.
- `src/foundation/trie/proofs.lisp`: proof construction and proof verification.
- `ethereum-lisp.validation` / `src/foundation/validation.lisp`: the shared error taxonomy for
  decoding, parameters, consensus, configuration, storage, and unavailable
  state, plus protocol value and fixed-byte validation helpers. The legacy
  block-validation condition remains available for compatibility.
- `ethereum-lisp.chain-config` / `src/protocol/chain-config/`: an independent
  protocol package for chain configuration types, fork activation predicates,
  blob schedule selection, and effective chain-rule construction. Core
  re-exports this API for compatibility.
- `ethereum-lisp.transactions` / `src/protocol/transactions/`: the transaction
  domain owns envelopes, codecs, signatures, generic cross-envelope readers,
  fee rules, and fork support policy. New envelope types extend the reader and
  sender protocols with methods instead of changing central type switches. It
  depends on chain rules and protocol primitives, not on
  `ethereum-lisp.core`; core re-exports its public API for compatibility.
- `ethereum-lisp.json` / `src/foundation/json/values.lisp` / `src/foundation/json/read.lisp` /
  `src/foundation/json/write.lisp` / `src/foundation/json/object-fields.lisp`: explicit null, false, and
  empty-object values; JSON parsing and encoding; shape predicates; object
  access; and quantity decoding without genesis or RPC ownership. RPC parsing
  preserves JSON type distinctions while legacy fixture readers can request
  their compatibility representation.
- `ethereum-lisp.json-rpc` / `src/api/json-rpc/protocol.lisp` /
  `src/api/json-rpc/codecs.lisp`: transport-independent JSON-RPC 2.0 envelope
  validation, response construction, and common field/parameter coercion. It
  contains no Engine, public method, chain, or HTTP policy.
- `src/api/engine/methods.lisp`: the authoritative Engine method registry and
  public namespace filters. Method availability and advertised capabilities
  derive from the same KZG-aware metadata.
- `ethereum-lisp.genesis` / `src/protocol/genesis/`: genesis account values,
  genesis-specific field and alloc parsing, chain-config conversion, file I/O,
  and fork-aware genesis block construction. It consumes JSON, chain config,
  receipt, execution-request, and block contracts without depending on core.
- `ethereum-lisp.accounts` / `src/protocol/accounts/accounts.lisp`: state-account values, encoding,
  and hashing, independent from the core compatibility aggregate.
- `src/protocol/transactions/legacy.lisp`: legacy transaction envelope, RLP, signing hash,
  EIP-155 chain-id handling, and sender recovery.
- `src/protocol/transactions/access-list.lisp`: EIP-2930 access lists and access-list
  transaction encoding/decoding.
- `src/protocol/transactions/dynamic-fee.lisp`: EIP-1559 dynamic-fee transaction
  encoding/decoding and signing hash.
- `src/protocol/transactions/blob.lisp`: EIP-4844 blob transaction and blob sidecar
  structures.
- `src/protocol/transactions/set-code-authorization.lisp`: EIP-7702 authorization tuples
  and delegation code helpers.
- `src/protocol/transactions/set-code.lisp`: EIP-7702 set-code transaction
  encoding/decoding.
- `src/protocol/transactions/accessors.lisp`: cross-type transaction accessors, type
  dispatch, blob gas counting, and access-list sizing.
- `src/protocol/transactions/transactions.lisp`: transaction fork validation, gas-price calculation,
  unified encoding/decoding, and sender dispatch.
- `ethereum-lisp.receipts` / `src/protocol/receipts/receipts.lisp`: withdrawals, logs, blooms,
  receipts, and trie-list roots. The package depends explicitly on the
  transaction contract used for typed receipt and transaction roots.
- `ethereum-lisp.txpool.index` / `src/storage/txpool/index/types.lisp` /
  `src/storage/txpool/index/`: store-independent pending, queued, basefee, and blob
  indexes, sender/nonce/hash keys, conflict handling, replacement rules,
  insertion, and views. Chain store holds this model, but the model has no
  chain-store dependency.
- `ethereum-lisp.blocks` / `src/protocol/blocks/`: block
  header/body values, canonical codecs, commitment derivation, construction,
  and hashing. It depends on transaction, receipt, execution-request, and
  block-access-list contracts, never on the core compatibility aggregate.
- `ethereum-lisp.consensus` / `src/protocol/consensus/`: protocol constants and pure transaction, header,
  fork, fee, body, root, and receipt validation. The package consumes stable
  protocol models and never accesses stores, Engine state, txpool, or RPC.
- `ethereum-lisp.execution-requests` / `src/protocol/execution-requests/execution-requests.lisp`: execution
  request validation and hashing, independent from block access lists.
- `ethereum-lisp.block-access-lists` / `src/protocol/block-access-lists/`: Amsterdam
  access-list values, field validation, RLP codecs, and body hashing.
- `src/protocol/blocks/access-list-commitment.lisp`: block-level consistency check between
  typed and encoded access-list bodies; this adapter owns the dependency on a
  block object instead of placing it in the access-list package.
- `src/protocol/genesis/block.lisp`: fork-aware genesis header and block construction.
- `ethereum-lisp.kzg` / `src/protocol/kzg/`: KZG constants, verifier ports,
  command-backed adapter, field/blob proof verification, and sidecar
  validation. CLI dynamically injects a verifier object without mutating
  process-global verifier functions.
- `ethereum-lisp.engine-payloads` / `src/protocol/engine-payloads/`: Engine payload
  values and statuses, defensive codecs, block mapping, fork-version checks,
  payload-id derivation, and empty payload construction. Stores and RPC depend
  on this contract; the package has no store, RPC, or HTTP dependency.
- `ethereum-lisp.engine` / `src/application/services/engine-payload-status.lisp`: Engine newPayload and
  forkchoice state transitions over the payload, consensus, and chain-store
  contracts. It owns cache/import status decisions but has no JSON-RPC or HTTP
  dependency.
- `ethereum-lisp.engine-api` / Engine RPC codecs, handlers,
  `src/api/engine/methods.lisp`, and `src/api/engine/dispatch.lisp`: the Engine JSON-RPC
  wire adapter over `json-rpc` and the Engine service. It contains no Public
  RPC routing or HTTP transport.
- `ethereum-lisp.public-api` / Public RPC codecs, handlers, namespace routers,
  and `src/api/public/dispatch/dispatch.lisp`: the public JSON-RPC adapter over state,
  execution, chain-store, txpool, and shared Engine payload rendering. Only
  the aggregate public method handler is exported; HTTP remains outside.
- `ethereum-lisp.txpool.application` / `src/application/services/txpool-admission.lisp`: typed
  admission policy, transaction preflight, subpool routing, and promotion.
  `eth_sendRawTransaction` decodes and delegates to this service rather than
  coordinating domain state in the wire handler.
- `ethereum-lisp.rpc` / `src/api/rpc/router.lisp` and `src/api/rpc/json.lisp`: request context,
  Engine/Public method composition, batch handling, and JSON codecs. It has no
  transport dependency; legacy `engine-rpc-handle-*` functions are thin
  adapters over the context API.
- `ethereum-lisp.rpc-http` / `src/transport/http/`: JWT authentication, HTTP parsing and
  policy, telemetry, request/stream handling, service configuration, listener
  adapters, and the serve loop. A service owns one `rpc-context`, so transport
  configuration does not duplicate RPC policy state.
- `ethereum-lisp.core` / `src/packages/core.lisp`: compatibility re-export facade.
  No implementation is defined in this package.
- `ethereum-lisp.chain-store.model` / `src/storage/chain-store/model/types.lisp`: checkpoint,
  transaction-location, filter, and blob lookup records. The model owns no
  storage behavior and has no txpool dependency.
- `ethereum-lisp.chain-store.state` / `src/storage/chain-store/state/memory.lisp`: mutable
  in-memory chain data, state projections, caches, filters, and checkpoints.
  It depends on chain-store records but has no txpool dependency.
- `ethereum-lisp.node-state` / `src/storage/node-store/state.lisp`: the explicit in-memory node
  aggregate that composes one chain-store state component with one txpool
  index component. Cross-domain lifecycle ownership belongs here rather than
  in either domain model.
- `ethereum-lisp.node-store` / `src/storage/node-store/snapshots.lisp` and
  `src/storage/node-store/blocks.lisp`: atomic snapshot, rollback, component replacement,
  and block-import orchestration for the complete in-memory node. It is the
  lifecycle boundary that may coordinate both mutable domains.
- `ethereum-lisp.chain-store` / chain-store memory, copy, cache, filter,
  state, canonical-index, and transaction-location modules: in-memory chain
  behavior behind generic public chain operations with a memory-component
  fallback. Alternative stores can specialize the public protocol without
  exposing the in-memory representation. It does not depend on the node
  aggregate or txpool; canonical-head remains an application service because
  it coordinates multiple domains.
- `ethereum-lisp.txpool` / txpool store, admission, views, accounting,
  promotion, cleanup, and reorg modules: transaction-pool policy over the
  index model and chain-store query contract. It depends on chain-store in one
  direction, resolves pool state through its component protocol, and does not
  depend on the node aggregate. Canonical-head orchestrates the resulting
  service operations.
- `ethereum-lisp.canonical-chain` / `src/application/services/canonical-chain.lisp`: canonical path
  discovery, index replacement, displaced transaction recovery, txpool
  reconciliation, filter notification, and a transition descriptor
  containing installed/displaced blocks and affected txpool hashes. This is an
  application service over chain-store and txpool, with each phase expressed
  as a separate step.
- `ethereum-lisp.node-store.persistence`: the outward node database adapter for
  atomic KV snapshots, record-scoped live deltas, and staged, validated
  restore. Export/import codecs depend on database and storage contracts plus
  the canonical-transition descriptor; staged import additionally invokes
  `ethereum-lisp.execution-service` to execute and validate payloads before
  materialization. Database, chain-store, txpool, and canonical-chain do not
  depend on this adapter.
- `src/storage/node-store/persistence/metadata.lisp`: versioned persistence authority
  records binding an artifact role, chain ID, genesis hash, lifecycle-unique
  authority ID, publication generation, and base chain generation. Metadata is
  populated into the same KV batch as the chain delta or complete txpool
  snapshot it describes.
- `src/storage/node-store/persistence/staged-import.lisp`: private, versioned staged-import control and
  materialization. It binds authority, chain, genesis, and the complete chain
  configuration; pins a finalized anchor; advances header, body, execution,
  receipt-verification, and transaction-index stages atomically; persists
  reverse-order unwind intent; and hydrates only a fresh startup store. It does
  not publish canonical indexes or checkpoints and is currently an offline,
  block-serial, single-writer boundary.
- `src/storage/chain-store/service/copy/values.lisp`: defensive copying for shared store values,
  filters, checkpoints, and blob proof records.
- `src/storage/chain-store/service/copy/blocks.lisp`: defensive copying for block headers, logs,
  receipts, blocks, prepared payloads, and transactions.
- `src/storage/txpool/index/copy.lisp`: txpool deep-copy behavior that preserves shared
  transaction identity across subpool and sender indexes without depending on
  chain-store copying helpers.
- `src/storage/chain-store/service/copy/locations.lisp`: transaction-location deep-copy helpers
  that keep copied blocks, receipts, and transactions aligned.
- `src/storage/node-store/snapshots.lisp`: shared in-memory-store guard plus memory-store
  snapshot/restore and atomic commit helpers.
- `src/storage/chain-store/service/filters.lisp`: in-memory block, log, and pending transaction
  filter registration and notifications using explicit filter metadata rather
  than inspecting JSON-RPC request objects.
- `src/storage/chain-store/service/cache.lisp`: in-memory remote block, invalid payload,
  prepared payload, and blob sidecar caches.
- `src/storage/chain-store/service/memory-blocks.lisp`: in-memory block storage, lookup, and
  forkchoice checkpoint updates.
- `src/storage/chain-store/service/memory.lisp`: public chain-store queries and commands around the
  memory-store implementation.
- `src/storage/chain-store/service/state-availability.lisp`: retained state availability checks
  and state snapshot pruning.
- `src/storage/chain-store/service/account-state.lisp`: retained account balance, nonce, code, and
  storage read/write helpers.
- `src/storage/chain-store/service/state-iteration.lisp`: retained account and storage iteration
  helpers for export and state projection.
- `src/storage/chain-store/service/canonical-indexes.lisp`: canonical hash, block number, parent,
  block-membership, and ancestor checks.
- `src/storage/chain-store/service/transaction-locations.lisp`: canonical transaction location
  indexing and lookup.
- `src/storage/txpool/service/chain-rules.lisp`: txpool admission rules that need current
  chain state.
- `src/storage/txpool/service/reorg.lisp`: displaced transaction reinsertion after
  canonical reorgs.
- `src/storage/txpool/service/store.lisp`: the chain-store adapter for txpool access,
  conflict/replacement checks, and low-level subpool indexing.
- `src/storage/txpool/service/store-admission.lisp`: validated insertion into pending, queued,
  basefee, and blob subpools through one shared admission path.
- `src/storage/txpool/service/store-views.lisp` and `src/storage/txpool/service/store-accounting.lisp`: sender-index
  queries and replacement-aware balance accounting.
- `src/storage/txpool/service/views.lisp`: txpool lookup, list, count, sender view, and mining
  selection helpers.
- `src/storage/txpool/service/parked-pruning.lisp`: overbudget parked-transaction ordering,
  removal, and balance-aware pruning.
- `src/storage/txpool/service/promotion-rules.lisp`: shared funding, nonce, local exemption, and
  pending insertion helpers for txpool promotion.
- `src/storage/txpool/service/queued-promotion.lisp`: queued transaction promotion by sender and
  nonce continuity.
- `src/storage/txpool/service/basefee-promotion.lisp`: basefee transaction promotion and queued
  tail draining after basefee promotion.
- `src/storage/txpool/service/cleanup-lifecycle.lisp`: stale nonce and expired queued-view
  transaction removal.
- `src/storage/txpool/service/cleanup-new-head.lisp`: invalid sender, sender-code, gas-limit, and
  blob-fee cleanup after canonical-head changes.
- `src/storage/txpool/service/pending-revalidation.lisp`: pending transaction demotion and sender
  revalidation after canonical-head changes.
- `src/storage/node-store/persistence/export/indexes.lisp`: checkpoint and index KV export records.
- `src/storage/node-store/persistence/export/blocks.lisp`: block and receipt KV export records.
- `src/storage/node-store/persistence/export/transactions.lisp`: transaction location KV export
  records.
- `src/storage/node-store/persistence/export/state.lisp`: state snapshot KV export records.
- `src/storage/node-store/persistence/export/txpool.lisp`: txpool KV export records.
- `src/storage/node-store/persistence/export/invalid-tipsets.lisp`: invalid tipset KV export records.
- `src/storage/node-store/persistence/export/remote-blocks.lisp`: remote block KV export records.
- `src/storage/node-store/persistence/export/blob-sidecars.lisp`: blob sidecar KV export records.
- `src/storage/node-store/persistence/export/prepared-payloads.lisp`: prepared payload KV export
  records.
- `src/storage/node-store/persistence/export/orchestrator.lisp`: compatibility package entry for chain-store export
  modules.
- `src/storage/node-store/persistence/import/core.lisp`: chain-store KV import table staging,
  block/header indexes, canonical chain indexes, and checkpoints.
- `src/storage/node-store/persistence/import/receipts.lisp`: receipt/log RLP decoding and
  receipt record validation.
- `src/storage/node-store/persistence/import/state.lisp`: state snapshot import, trie-root
  reconstruction, and state-root validation.
- `src/storage/node-store/persistence/import/locations.lisp`: transaction-location record import
  and log-index consistency checks.
- `src/storage/node-store/persistence/import/txpool.lisp`: txpool record import, static/fork
  validation, subpool restoration, and post-import txpool consistency.
- `src/storage/node-store/persistence/import/side-data.lisp`: invalid-tipset and remote-block
  record import.
- `src/storage/node-store/persistence/import/blobs.lisp`: blob sidecar record decoding and
  versioned-hash indexing.
- `src/storage/node-store/persistence/import/prepared-payloads.lisp`: prepared-payload record
  decoding and cache restoration.
- `src/storage/node-store/persistence/import/orchestrator.lisp`: top-level chain-store KV import
  orchestration.
- `src/foundation/database/batch.lisp` / `src/foundation/database/memory.lisp`: write-batch application is
  atomic from the active handle's perspective. Memory applies to a shadow table
  and swaps on success; the file backend restores its in-memory table when
  durable replacement fails. This is logical batch atomicity, not an fsync or
  multi-handle serialization guarantee.
- `src/protocol/consensus/block-validation/fees.lisp`: base-fee, gas-limit, blob-gas, and blob base
  fee validation.
- `src/protocol/consensus/block-validation/forks.lisp`: fork-specific header field presence and Merge
  transition checks.
- `src/protocol/consensus/block-validation/header.lisp`: header shape validation, parent linkage,
  fork-aware header checks, and chain-config header validation.
- `src/protocol/consensus/block-validation/body.lisp`: withdrawal, transaction, ommer, blob-gas, and
  body-config validation helpers.
- `src/protocol/consensus/block-validation/roots.lisp`: body root and body commitment checks.
- `src/protocol/consensus/block-validation/receipts.lisp`: receipt/log validation and execution
  commitment root checks.
- `src/api/engine/payload-input-codecs.lisp`: Engine payload JSON object decoding.
- `src/api/engine/payload-codecs.lisp`: Engine payload/status object rendering.
- `src/api/engine/forkchoice-codecs.lisp`: forkchoice state and payload attribute
  validation.
- `src/api/engine/capabilities.lisp`: Engine capability lists, client version, and
  transition configuration rendering.
- `src/api/engine/new-payload.lisp`: `engine_newPayload*`, capability exchange,
  client version, and transition configuration handlers.
- `src/api/engine/errors.lisp`: Engine API error condition and protocol error
  codes shared by Engine RPC handlers.
- `src/api/engine/payloads.lisp`: `engine_getPayload*` payload-id lookup and
  payload envelope handlers.
- `src/api/engine/blobs.lisp`: `engine_getBlobs*` and payload-body hash/range
  query handlers.
- `src/api/engine/forkchoice.lisp`: `engine_forkchoiceUpdated*` checkpoint
  updates, prepared payload construction, and payload-id caching.
- `src/api/engine/dispatch.lisp`: final Engine API method dispatch.
- `src/api/public/params.lisp`: shared public JSON-RPC address, hash, block tag,
  and block id parameter coercion.
- `src/api/public/metadata/metadata.lisp`: web3, net, rpc_modules, and basic eth metadata
  handlers.
- `src/api/public/metadata/fees.lisp`: gas price, priority fee, base fee, and blob base-fee
  handlers.
- `src/api/public/metadata/fee-history.lisp`: `eth_feeHistory` parameter validation and
  response construction.
- `src/api/public/state/queries.lisp`: public account balance, nonce, code, and
  storage reads.
- `src/api/public/state/proofs.lisp`: `eth_getProof` storage slot coercion and
  proof response construction.
- `src/api/public/state/call-objects.lisp`: public call-object parsing, simulation gas
  defaults, and transaction synthesis.
- `src/api/public/state/call-simulation.lisp`: public call simulation and `eth_call`
  response handling.
- `src/api/public/state/gas.lisp`: `eth_estimateGas` gas caps and binary search.
- `src/api/public/state/access-lists.lisp`: `eth_createAccessList` access collection and
  response rendering.
- `src/api/public/transactions/fields.lisp`: transaction JSON field rendering,
  access list rendering, type-specific fields, and sender/gas-price helpers.
- `src/api/public/transactions/objects.lisp`: transaction JSON object assembly,
  lookup wrappers, pending transaction helpers, and shared JSON array
  normalization.
- `src/api/public/transactions/transactions.lisp`: raw transaction and transaction lookup
  handlers.
- `src/api/public/txpool/views.lisp`: txpool JSON table and transaction view
  helpers.
- `src/application/services/txpool-admission.lisp`: application-level
  `eth_sendRawTransaction` validation, admission policy, subpool routing, and
  promotion rules.
- `src/api/public/txpool/locals.lisp`: local transaction exemption predicates and
  expiry cleanup.
- `src/api/public/transactions/send-raw-transaction.lisp`: `eth_sendRawTransaction` handler.
- `src/api/public/txpool/handlers.lisp`: `eth_pendingTransactions` and `txpool_*`
  namespace handlers.
- `src/api/public/transactions/receipts.lisp`: log, receipt, and block receipt result
  construction and handlers.
- `src/api/public/blocks/header-objects.lisp`: public header result objects and header
  lookup handlers.
- `src/api/public/blocks/`: public block RLP sizing, block result objects,
  block lookup handlers, and transaction-count handlers.
- `src/api/public/blocks/ommer-handlers.lisp`: public ommer count and ommer lookup
  handlers.
- `src/api/public/filters/logs.lisp`: public log filter parsing, matching, block
  selection, and log result construction.
- `src/api/public/filters/changes.lisp`: log, block, and pending-transaction filter
  change calculation.
- `src/api/public/filters/handlers.lisp`: public filter install/query/uninstall
  handlers.
- `src/api/public/dispatch/`: public JSON-RPC dispatch context plus
  metadata, state, block, transaction, filter, and txpool method routing.
- `src/api/public/dispatch/dispatch.lisp`: final public JSON-RPC method dispatch.
- `src/transport/http/auth.lisp`: Engine API JWT token creation and validation.
- `src/transport/http/parser.lisp`: HTTP parsing and bounded stream request reading.
- `src/transport/http/telemetry.lisp`: request/response telemetry extraction.
- `src/transport/http/policy.lisp`: CORS/host policy and response rendering.
- `src/transport/http/handler.lisp`: context-based request and single-stream handling,
  plus legacy store/config adapters.
- `src/transport/http/service.lisp`: HTTP service model, validation, and RPC context
  construction.
- `src/transport/http/listener.lisp`: connection/listener contracts and the SBCL socket
  adapter.
- `src/transport/http/server.lisp`: configured stream delegation and listener serve loop.
- `src/runtime/state/types.lisp`: state units, mutable state records, proof records,
  range records, and state key coercion helpers.
- `src/runtime/state/db.lisp`: mutable account/code/storage access, copy/restore helpers,
  and storage trie proof primitives.
- `src/runtime/state/roots.lisp`: account trie construction, account proofs, and state
  root rendering.
- `src/runtime/state/proofs.lisp`: proof result construction and verification.
- `ethereum-lisp.state-proof-json` / `src/api/public/state/proof-json.lisp`: state-proof
  JSON-RPC object conversion and parsing outside the state domain.
- `src/runtime/state/ranges.lisp`: account/storage range iteration and deterministic
  state export helpers.
- `ethereum-lisp.genesis-state` / `src/application/services/genesis-state.lisp`: the application bridge
  that materializes genesis allocations in state and derives genesis roots,
  headers, and blocks. The state domain itself has no genesis dependency.
- `src/runtime/evm/types.lisp`: EVM errors, result/context records, precompile address
  activation, gas constants, and fixed precompile tables.
- `ethereum-lisp.evm` is a public facade that only re-exports the supported
  context, result, precompile-address, and execution API.
  `ethereum-lisp.evm.internal` owns runtime, precompile, and interpreter
  implementation symbols; application layers must not use that package.
- `src/runtime/evm/context.lisp`: child EVM context construction and inherited
  frame fields for CREATE and CALL-family opcodes.
- `src/runtime/evm/base.lisp`: EVM word arithmetic, fork checks, errors, and stack
  pop/push helpers.
- `src/runtime/evm/memory.lisp`: memory expansion, data slicing, memory copy, and
  mload/mstore helpers.
- `src/runtime/evm/opcodes.lisp`: PUSH immediate decoding, byte extraction, EXP
  gas, jump-destination checks, and base opcode gas.
- `src/runtime/evm/conversions.lisp`: word/address/hash conversions and
  difficulty/prev-randao context lookup.
- `src/runtime/evm/transient-storage.lisp`: transient storage keys, load/store,
  and frame snapshot copy/restore helpers.
- `src/runtime/evm/storage-gas.lisp`: SSTORE refund keys, cleared-slot snapshots,
  and dynamic SSTORE gas calculation.
- `src/runtime/evm/access-lists.lisp`: account/storage warm access tracking and
  EIP-2929 access gas charging.
- `src/runtime/evm/selfdestructs.lisp`: selfdestruct address snapshots, marking,
  and finalization.
- `src/runtime/evm/snapshots.lisp`: frame/execution snapshot capture,
  access-list snapshot refresh, and restore helpers for rollback.
- `src/runtime/evm/state.lisp`: account mutation, value transfer, delegated code
  resolution, and selfdestruct state updates.
- `src/runtime/evm/create.lisp`: CREATE/CREATE2 address derivation, initcode gas,
  code size limits, and created-code validation.
- `src/runtime/evm/gas.lisp`: remaining gas, EIP-150 child gas, and call stipend
  accounting helpers.
- `src/runtime/evm/block.lisp`: nonce increment, account-code hash, blockhash, and
  blobhash word helpers.
- `src/runtime/evm/precompiles/utils.lisp`: shared precompile byte, endian, and fixed-size
  integer helpers.
- `src/runtime/evm/precompiles/modexp.lisp`: EIP-198 modular exponentiation gas and
  execution.
- `src/runtime/evm/precompiles/bn254-base.lisp`: BN254 base field, G1, Fp2, and basic
  add/mul precompile helpers.
- `src/runtime/evm/precompiles/bn254-g2.lisp`: BN254 G2 parsing, subgroup checks, and
  Fp2 equality helpers.
- `src/runtime/evm/precompiles/bn254-fields.lisp`: BN254 Fp6/Fp12 arithmetic and
  Frobenius constants.
- `src/runtime/evm/precompiles/bn254-pairing.lisp`: BN254 Miller loop, final
  exponentiation, pairing backend, and pairing precompile.
- `src/runtime/evm/precompiles/kzg.lisp`: KZG point-evaluation precompile.
- `src/runtime/evm/precompiles/blake2f.lisp`: BLAKE2F compression precompile and gas
  calculation.
- `src/runtime/evm/precompiles/dispatch.lisp`: ecrecover, precompile gas precheck, and
  final precompile dispatch.
- `src/runtime/evm/interpreter/results.lisp`: child execution result rollback, gas,
  return-data, and log merge helpers for the bytecode interpreter.
- `src/runtime/evm/interpreter/create.lisp`: shared CREATE/CREATE2 child execution,
  rollback, code-deposit, and result mapping helpers.
- `src/runtime/evm/interpreter/call.lisp`: declarative CALL-family plans plus the shared
  memory, access-gas, snapshot, child execution, rollback, and result-merge
  pipeline.
- `src/runtime/evm/interpreter/machine.lisp`: explicit mutable call-frame state and the
  stack, gas, memory, halt, and result operations that preserve its invariants.
- `src/runtime/evm/opcodes/`: opcode semantics grouped by protocol responsibility:
  arithmetic, environment, state/memory, stack/log, and system operations.
  Handlers receive one machine object and do not own the fetch loop.
- `src/runtime/evm/interpreter/interpreter.lisp`: one-step fetch, base-gas charging, step limits, and
  opcode-family dispatch.
- `src/runtime/evm/execute.lisp`: stable public execution entry point; it owns frame lifetime but
  contains no opcode semantics.
- `src/runtime/execution/contract.lisp`: execution validation condition plus gas, nonce,
  code-size, refund, and proof-of-work reward constants.
- `src/runtime/execution/state.lisp`: account mutation helpers, code resolution, contract
  address derivation, and collision checks.
- `src/runtime/execution/rewards.lisp`: block beneficiary and ommer reward calculation.
- `src/runtime/execution/gas.lisp`: transaction gas math, effective gas price, initcode
  and runtime code limits, and intrinsic gas helpers.
- `src/runtime/execution/transaction-fields.lisp`: execution transaction scalar,
  access-list, set-code, and sender-code field validation.
- `src/runtime/execution/validation.lisp`: fork-aware transaction and transaction-list
  validation orchestration.
- `src/runtime/execution/set-code.lisp`: EIP-7702 authorization application and refund
  accounting.
- `src/runtime/execution/accounting.lisp`: sender upfront charge, value transfer,
  gas refund, priority fee payment, and receipt finalization.
- `src/runtime/execution/access.lisp`: access-list/precompile prewarming and accessed
  address/storage table construction.
- `src/runtime/execution/rules.lisp`: fork-rule selection, blob gas limits, and block blob
  base-fee derivation.
- `src/runtime/execution/context.lisp`: EVM context creation for message execution.
- `src/runtime/execution/call-simulation.lisp`: copied-state call execution for
  `eth_call`, gas estimation, and access-list simulation.
- `src/runtime/execution/apply-contract.lisp`: state-mutating contract creation.
- `src/runtime/execution/signatures.lisp`: transaction chain-id selection and sender
  recovery helpers.
- `src/runtime/execution/apply-message.lisp`: state-mutating message application and
  signed/legacy wrappers.
- `src/runtime/execution/message-lists.lisp`: transaction-list execution and execution
  result construction.
- `src/runtime/execution/legacy.lisp`: withdrawal application and legacy transaction-list
  entry points over the EVM-backed message executor, without a partial state
  fallback.
- `src/runtime/execution/block-body-validation.lisp`: block body commitment checks,
  access-list body normalization, and execution root validation.
- `src/runtime/execution/block-validation.lisp`: fork body-shape checks and block header
  snapshot/restore helpers.
- `src/runtime/execution/block-execution.lisp`: shared block execution skeleton plus
  signed and legacy block execution entry points.
- `ethereum-lisp.execution-service` / `src/application/services/execution.lisp`: state-db and
  chain-store projection, atomic block commit, and Engine payload import. The
  execution domain itself contains no storage adapter dependency.
- `src/app/cli/devnet/types.lisp`: devnet CLI records, defaults, embedded dev genesis,
  canonical-transition persistence port, and shutdown signal helpers.
- `src/app/cli/devnet/files.lisp`: CLI file, datadir, JWT secret, and KV database path
  helpers.
- `src/app/cli/devnet/persistence.lisp`: devnet persisted chain and txpool import
  helpers.
- `src/app/cli/devnet/node.lisp`: devnet node construction, genesis import, service
  construction, and Merge option overrides.
- `src/app/cli/devnet/runtime.lisp`: devnet state pruning, txpool journaling, database
  export, and guarded dev-period sealing that stages execution noncanonically,
  publishes an explicit canonical transition, and commits its record-scoped
  delta before releasing public visibility.
- `src/app/cli/devnet/summary.lisp`: devnet status summaries and JSON summary
  objects.
- `src/app/cli/devnet/background.lisp`: devnet periodic background worker threads;
  explicitly classified dev-period file-write failures are warned and retried
  on a later tick, while execution, validation, corruption, and callback
  invariant failures retain fail-stop shutdown semantics.
- `src/app/cli/devnet/service.lisp`: devnet listener serving and
  startup orchestration.
- `src/app/cli/options/definitions.lisp`: geth-compatible option arity metadata.
- `src/app/cli/options/args.lisp`: command-line token normalization, boolean token handling,
  and command-token lookup.
- `src/app/cli/config/toml.lisp`: minimal TOML value parsing for geth-compatible
  devnet config files.
- `src/app/cli/config/config.lisp`: geth config-file key mapping and config-to-CLI option
  application.
- `src/app/cli/options/parsers.lisp`: CLI scalar parsers for ports, durations, quantities,
  addresses, RPC prefixes, API module filters, CORS, and vhosts.
- `src/app/cli/options/options.lisp`: geth-compatible devnet option aggregation.
- `src/app/cli/output.lisp`: CLI usage, version, summary, ready-file, and pid-file
  output helpers.
- `src/app/cli/kzg.lisp`: CLI-scoped KZG verifier hook configuration.
- `src/app/cli/telemetry/telemetry.lisp`: CLI telemetry fields and lifecycle event emission.
- `src/app/cli/telemetry/sinks.lisp`: CLI telemetry stream sink selection and error
  logging.
- `src/app/cli/init.lisp`: `init` command option parsing and datadir initialization.
- `src/app/cli/cli.lisp`: top-level command dispatcher.

## Dependency Rules

- Consensus data types may use primitives, RLP, crypto, trie, and chain rules.
- State may use account types and trie commitments, but not genesis parsing.
- Genesis-state assembly may bridge genesis input and mutable state.
- Node state may compose chain-store state and txpool index state; neither
  domain may own the other domain's mutable state.
- EVM may use state and consensus types, but not RPC or CLI.
- Execution may use EVM, state, and consensus types, but not chain store.
- Application services may bridge runtime and storage-core APIs.
- Persistence and RPC/API adapters may depend on application services; runtime
  and storage-core packages must not depend on these adapters.
- Only `ethereum-lisp` and `ethereum-lisp.core` provide compatibility
  re-exports; domain packages do not re-export higher-layer symbols.
- Architecture tests require the project package graph to remain acyclic and
  every non-facade package to own each symbol it exports.
- RPC may use execution and store APIs, but protocol types must not depend on
  RPC JSON shapes.
- HTTP transport may call RPC dispatch, but RPC dispatch should not depend on
  sockets or listener state.
- CLI and devnet lifecycle are top-level orchestration only.
