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

`ethereum-lisp` is the canonical public API. The legacy `ethereum-lisp.core`
package is generated directly from that API and owns no symbols or
implementation. File size and name prefixes are not module boundaries: a
refactor must first identify an owner, its public contract, and the allowed
dependency direction. Split code only when the resulting units have cohesive
behavior and communicate through an explicit API or state object.

The current source ownership map is:

- `packages-foundation.lisp`: base package definitions for bytes, hex,
  database, telemetry, RLP, types, crypto, and trie.
- `packages-json.lisp`: generic JSON value, object-access, and quantity codec
  package definition shared by genesis, Engine API, and public RPC.
- `packages-protocol.lisp`: independent chain-configuration and transaction
  domain package definitions.
- `packages-models.lisp`: account and receipt protocol-model package
  definitions, ordered by their explicit domain dependencies.
- `packages-blocks.lisp`: execution-request, block-access-list, and block
  package definitions with their dependency order made explicit.
- `packages-genesis.lisp`: genesis data, parsing, and block-construction
  package definition over JSON and protocol-model contracts.
- `packages-consensus.lisp`: pure transaction, header, body, fork, root, and
  receipt consensus-validation package definition.
- `package-tools.lisp`: package-definition helpers for owner-grouped public
  APIs and exact compatibility re-exports.
- `packages-facade.lisp`: the single public API manifest, grouped by the
  package that owns each symbol. Every public symbol is listed once.
- `packages-core.lisp`: generated compatibility facade over
  `ethereum-lisp`; it owns no symbols and cannot expose internal APIs.
- `packages-runtime.lisp`: state, EVM, execution, and their explicit
  genesis/store bridge package definitions, with no core aggregate dependency.
- `packages-cli.lisp`: the CLI composition package. It consumes the canonical
  public API and explicitly imports the small txpool and persistence ports
  needed for node assembly; it does not depend on `ethereum-lisp.core`.
- `cli-types.lisp`: typed Engine/Public endpoint, txpool-policy, and KZG
  configuration values composed by `devnet-node`; compatibility readers keep
  older callers stable without duplicating scalar configuration slots.
- `database-*.lisp`: key-value database protocol, chain-record key encoding,
  memory/file backends, write batches, and chain-record access helpers.
- `crypto-constants.lisp`: hash, KZG, secp256k1, SHA-256, Keccak, and
  RIPEMD-160 constants and round tables.
- `crypto-words.lisp`: 32-bit/64-bit rotation and endian load/store helpers.
- `crypto-keccak.lisp`: Ethereum legacy Keccak-256 sponge implementation and
  its canonical empty code/trie hashes.
- `crypto-sha256.lisp`: SHA-256 compression and digest helpers.
- `crypto-ripemd160.lisp`: RIPEMD-160 compression and digest helpers.
- `crypto-kzg.lisp`: KZG commitment versioned-hash conversion.
- `crypto-math.lisp`: fixed-width integer encoding and modular arithmetic.
- `crypto-secp256k1.lisp`: secp256k1 point arithmetic, key/address
  derivation, and public key recovery.
- `trie-encoding.lisp`: hex-prefix nibble encoding primitives.
- `trie-types.lisp`: Merkle Patricia Trie node and in-memory store types.
- `trie-store.lisp`: mutable trie entry put/get/delete and ordered scans.
- `trie-nodes.lisp`: canonical node construction, node RLP references, and
  root hash derivation.
- `trie-proofs.lisp`: proof construction and proof verification.
- `ethereum-lisp.validation` / `validation.lisp`: the shared error taxonomy for
  decoding, parameters, consensus, configuration, storage, and unavailable
  state, plus protocol value and fixed-byte validation helpers. The legacy
  block-validation condition remains available for compatibility.
- `ethereum-lisp.chain-config` / `chain-config-*.lisp`: an independent
  protocol package for chain configuration types, fork activation predicates,
  blob schedule selection, and effective chain-rule construction. Core
  re-exports this API for compatibility.
- `ethereum-lisp.transactions` / `transactions-*.lisp`: the transaction
  domain owns envelopes, codecs, signatures, generic cross-envelope readers,
  fee rules, and fork support policy. New envelope types extend the reader and
  sender protocols with methods instead of changing central type switches. It
  depends on chain rules and protocol primitives, not on
  `ethereum-lisp.core`; core re-exports its public API for compatibility.
- `ethereum-lisp.json` / `json-values.lisp` / `json-read.lisp` /
  `json-write.lisp` / `json-object-fields.lisp`: explicit null, false, and
  empty-object values; JSON parsing and encoding; shape predicates; object
  access; and quantity decoding without genesis or RPC ownership. RPC parsing
  preserves JSON type distinctions while legacy fixture readers can request
  their compatibility representation.
- `ethereum-lisp.json-rpc` / `json-rpc-protocol.lisp` /
  `json-rpc-codecs.lisp`: transport-independent JSON-RPC 2.0 envelope
  validation, response construction, and common field/parameter coercion. It
  contains no Engine, public method, chain, or HTTP policy.
- `engine-api-methods.lisp`: the authoritative Engine method registry and
  public namespace filters. Method availability and advertised capabilities
  derive from the same KZG-aware metadata.
- `ethereum-lisp.genesis` / `genesis-*.lisp`: genesis account values,
  genesis-specific field and alloc parsing, chain-config conversion, file I/O,
  and fork-aware genesis block construction. It consumes JSON, chain config,
  receipt, execution-request, and block contracts without depending on core.
- `ethereum-lisp.accounts` / `accounts.lisp`: state-account values, encoding,
  and hashing, independent from the core compatibility aggregate.
- `transactions-legacy.lisp`: legacy transaction envelope, RLP, signing hash,
  EIP-155 chain-id handling, and sender recovery.
- `transactions-access-list.lisp`: EIP-2930 access lists and access-list
  transaction encoding/decoding.
- `transactions-dynamic-fee.lisp`: EIP-1559 dynamic-fee transaction
  encoding/decoding and signing hash.
- `transactions-blob.lisp`: EIP-4844 blob transaction and blob sidecar
  structures.
- `transactions-set-code-authorization.lisp`: EIP-7702 authorization tuples
  and delegation code helpers.
- `transactions-set-code.lisp`: EIP-7702 set-code transaction
  encoding/decoding.
- `transactions-accessors.lisp`: cross-type transaction accessors, type
  dispatch, blob gas counting, and access-list sizing.
- `transactions.lisp`: transaction fork validation, gas-price calculation,
  unified encoding/decoding, and sender dispatch.
- `ethereum-lisp.receipts` / `receipts.lisp`: withdrawals, logs, blooms,
  receipts, and trie-list roots. The package depends explicitly on the
  transaction contract used for typed receipt and transaction roots.
- `ethereum-lisp.txpool.index` / `txpool-types.lisp` /
  `txpool-index-*.lisp`: store-independent pending, queued, basefee, and blob
  indexes, sender/nonce/hash keys, conflict handling, replacement rules,
  insertion, and views. Chain store holds this model, but the model has no
  chain-store dependency.
- `ethereum-lisp.blocks` / `blocks-*.lisp` / `block-header-rlp.lisp`: block
  header/body values, canonical codecs, commitment derivation, construction,
  and hashing. It depends on transaction, receipt, execution-request, and
  block-access-list contracts, never on the core compatibility aggregate.
- `ethereum-lisp.consensus` / `consensus-*.lisp` /
  `block-validation-*.lisp`: protocol constants and pure transaction, header,
  fork, fee, body, root, and receipt validation. The package consumes stable
  protocol models and never accesses stores, Engine state, txpool, or RPC.
- `ethereum-lisp.execution-requests` / `execution-requests.lisp`: execution
  request validation and hashing, independent from block access lists.
- `ethereum-lisp.block-access-lists` / `block-access-list-*.lisp`: Amsterdam
  access-list values, field validation, RLP codecs, and body hashing.
- `blocks-access-list-commitment.lisp`: block-level consistency check between
  typed and encoded access-list bodies; this adapter owns the dependency on a
  block object instead of placing it in the access-list package.
- `genesis-block.lisp`: fork-aware genesis header and block construction.
- `ethereum-lisp.kzg` / `kzg-*.lisp`: KZG constants, verifier ports,
  command-backed adapter, field/blob proof verification, and sidecar
  validation. CLI dynamically injects a verifier object without mutating
  process-global verifier functions.
- `ethereum-lisp.engine-payloads` / `engine-payload-*.lisp`: Engine payload
  values and statuses, defensive codecs, block mapping, fork-version checks,
  payload-id derivation, and empty payload construction. Stores and RPC depend
  on this contract; the package has no store, RPC, or HTTP dependency.
- `ethereum-lisp.engine` / `engine-payload-status.lisp`: Engine newPayload and
  forkchoice state transitions over the payload, consensus, and chain-store
  contracts. It owns cache/import status decisions but has no JSON-RPC or HTTP
  dependency.
- `ethereum-lisp.engine-api` / Engine RPC codecs, handlers,
  `engine-api-methods.lisp`, and `engine-api-dispatch.lisp`: the Engine JSON-RPC
  wire adapter over `json-rpc` and the Engine service. It contains no Public
  RPC routing or HTTP transport.
- `ethereum-lisp.public-api` / Public RPC codecs, handlers, namespace routers,
  and `public-api-dispatch.lisp`: the public JSON-RPC adapter over state,
  execution, chain-store, txpool, and shared Engine payload rendering. Only
  the aggregate public method handler is exported; HTTP remains outside.
- `ethereum-lisp.txpool.application` / `txpool-admission-service.lisp`: typed
  admission policy, transaction preflight, subpool routing, and promotion.
  `eth_sendRawTransaction` decodes and delegates to this service rather than
  coordinating domain state in the wire handler.
- `ethereum-lisp.rpc` / `rpc-router.lisp` and `rpc-json.lisp`: request context,
  Engine/Public method composition, batch handling, and JSON codecs. It has no
  transport dependency; legacy `engine-rpc-handle-*` functions are thin
  adapters over the context API.
- `ethereum-lisp.rpc-http` / `rpc-http/`: JWT authentication, HTTP parsing and
  policy, telemetry, request/stream handling, service configuration, listener
  adapters, and the serve loop. A service owns one `rpc-context`, so transport
  configuration does not duplicate RPC policy state.
- `ethereum-lisp.core` / `packages-core.lisp`: compatibility re-export facade.
  No implementation is defined in this package.
- `ethereum-lisp.chain-store.model` / `chain-store-types.lisp`: checkpoint,
  transaction-location, filter, and blob lookup records. The model owns no
  storage behavior and has no txpool dependency.
- `ethereum-lisp.chain-store.state` / `chain-store-state.lisp`: mutable
  in-memory chain data, state projections, caches, filters, and checkpoints.
  It depends on chain-store records but has no txpool dependency.
- `ethereum-lisp.node-state` / `node-state.lisp`: the explicit in-memory node
  aggregate that composes one chain-store state component with one txpool
  index component. Cross-domain lifecycle ownership belongs here rather than
  in either domain model.
- `ethereum-lisp.node-store` / `node-store-snapshots.lisp` and
  `node-store-blocks.lisp`: atomic snapshot, rollback, component replacement,
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
- `ethereum-lisp.canonical-chain` / `canonical-chain.lisp`: canonical path
  discovery, index replacement, displaced transaction recovery, txpool
  reconciliation, filter notification, and a transition descriptor
  containing installed/displaced blocks and affected txpool hashes. This is an
  application service over chain-store and txpool, with each phase expressed
  as a separate step.
- `ethereum-lisp.node-store.persistence`: the node-level database adapter for
  atomic KV snapshots, record-scoped live deltas, and staged, validated
  restore. It imports only the canonical transition descriptor API and owns
  orchestration across chain and txpool components; record codecs remain
  grouped by the domain data they persist. Database, chain-store, canonical
  chain, and txpool never depend on this adapter.
- `node-store-persistence-metadata.lisp`: versioned persistence authority
  records binding an artifact role, chain ID, genesis hash, lifecycle-unique
  authority ID, publication generation, and base chain generation. Metadata is
  populated into the same KV batch as the chain delta or complete txpool
  snapshot it describes.
- `node-store-staged-import.lisp`: private, versioned staged-import control and
  materialization. It binds authority, chain, genesis, and the complete chain
  configuration; pins a finalized anchor; advances header, body, execution,
  receipt-verification, and transaction-index stages atomically; persists
  reverse-order unwind intent; and hydrates only a fresh startup store. It does
  not publish canonical indexes or checkpoints and is currently an offline,
  block-serial, single-writer boundary.
- `chain-store-copy-values.lisp`: defensive copying for shared store values,
  filters, checkpoints, and blob proof records.
- `chain-store-copy-blocks.lisp`: defensive copying for block headers, logs,
  receipts, blocks, prepared payloads, and transactions.
- `txpool-index-copy.lisp`: txpool deep-copy behavior that preserves shared
  transaction identity across subpool and sender indexes without depending on
  chain-store copying helpers.
- `chain-store-copy-locations.lisp`: transaction-location deep-copy helpers
  that keep copied blocks, receipts, and transactions aligned.
- `node-store-snapshots.lisp`: shared in-memory-store guard plus memory-store
  snapshot/restore and atomic commit helpers.
- `chain-store-filters.lisp`: in-memory block, log, and pending transaction
  filter registration and notifications using explicit filter metadata rather
  than inspecting JSON-RPC request objects.
- `chain-store-cache.lisp`: in-memory remote block, invalid payload,
  prepared payload, and blob sidecar caches.
- `chain-store-memory-blocks.lisp`: in-memory block storage, lookup, and
  forkchoice checkpoint updates.
- `chain-store-memory.lisp`: public chain-store queries and commands around the
  memory-store implementation.
- `chain-store-state-availability.lisp`: retained state availability checks
  and state snapshot pruning.
- `chain-store-account-state.lisp`: retained account balance, nonce, code, and
  storage read/write helpers.
- `chain-store-state-iteration.lisp`: retained account and storage iteration
  helpers for export and state projection.
- `chain-store-canonical-indexes.lisp`: canonical hash, block number, parent,
  block-membership, and ancestor checks.
- `chain-store-transaction-locations.lisp`: canonical transaction location
  indexing and lookup.
- `txpool-chain-rules.lisp`: txpool admission rules that need current
  chain state.
- `txpool-reorg.lisp`: displaced transaction reinsertion after
  canonical reorgs.
- `txpool-store.lisp`: the chain-store adapter for txpool access,
  conflict/replacement checks, and low-level subpool indexing.
- `txpool-store-admission.lisp`: validated insertion into pending, queued,
  basefee, and blob subpools through one shared admission path.
- `txpool-store-views.lisp` and `txpool-store-accounting.lisp`: sender-index
  queries and replacement-aware balance accounting.
- `txpool-views.lisp`: txpool lookup, list, count, sender view, and mining
  selection helpers.
- `txpool-parked-pruning.lisp`: overbudget parked-transaction ordering,
  removal, and balance-aware pruning.
- `txpool-promotion-rules.lisp`: shared funding, nonce, local exemption, and
  pending insertion helpers for txpool promotion.
- `txpool-queued-promotion.lisp`: queued transaction promotion by sender and
  nonce continuity.
- `txpool-basefee-promotion.lisp`: basefee transaction promotion and queued
  tail draining after basefee promotion.
- `txpool-cleanup-lifecycle.lisp`: stale nonce and expired queued-view
  transaction removal.
- `txpool-cleanup-new-head.lisp`: invalid sender, sender-code, gas-limit, and
  blob-fee cleanup after canonical-head changes.
- `txpool-pending-revalidation.lisp`: pending transaction demotion and sender
  revalidation after canonical-head changes.
- `chain-store-export-indexes.lisp`: checkpoint and index KV export records.
- `chain-store-export-blocks.lisp`: block and receipt KV export records.
- `chain-store-export-transactions.lisp`: transaction location KV export
  records.
- `chain-store-export-state.lisp`: state snapshot KV export records.
- `chain-store-export-txpool.lisp`: txpool KV export records.
- `chain-store-export-invalid-tipsets.lisp`: invalid tipset KV export records.
- `chain-store-export-remote-blocks.lisp`: remote block KV export records.
- `chain-store-export-blob-sidecars.lisp`: blob sidecar KV export records.
- `chain-store-export-prepared-payloads.lisp`: prepared payload KV export
  records.
- `chain-store-export.lisp`: compatibility package entry for chain-store export
  modules.
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
- `database-batch.lisp` / `database-memory.lisp`: write-batch application is
  atomic from the active handle's perspective. Memory applies to a shadow table
  and swaps on success; the file backend restores its in-memory table when
  durable replacement fails. This is logical batch atomicity, not an fsync or
  multi-handle serialization guarantee.
- `block-validation-fees.lisp`: base-fee, gas-limit, blob-gas, and blob base
  fee validation.
- `block-validation-forks.lisp`: fork-specific header field presence and Merge
  transition checks.
- `block-validation-header.lisp`: header shape validation, parent linkage,
  fork-aware header checks, and chain-config header validation.
- `block-validation-body.lisp`: withdrawal, transaction, ommer, blob-gas, and
  body-config validation helpers.
- `block-validation-roots.lisp`: body root and body commitment checks.
- `block-validation-receipts.lisp`: receipt/log validation and execution
  commitment root checks.
- `engine-rpc-payload-input-codecs.lisp`: Engine payload JSON object decoding.
- `engine-rpc-payload-codecs.lisp`: Engine payload/status object rendering.
- `engine-rpc-forkchoice-codecs.lisp`: forkchoice state and payload attribute
  validation.
- `engine-rpc-capabilities.lisp`: Engine capability lists, client version, and
  transition configuration rendering.
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
- `engine-api-dispatch.lisp`: final Engine API method dispatch.
- `public-rpc-params.lisp`: shared public JSON-RPC address, hash, block tag,
  and block id parameter coercion.
- `public-rpc-metadata.lisp`: web3, net, rpc_modules, and basic eth metadata
  handlers.
- `public-rpc-fees.lisp`: gas price, priority fee, base fee, and blob base-fee
  handlers.
- `public-rpc-fee-history.lisp`: `eth_feeHistory` parameter validation and
  response construction.
- `public-rpc-state-queries.lisp`: public account balance, nonce, code, and
  storage reads.
- `public-rpc-state-proofs.lisp`: `eth_getProof` storage slot coercion and
  proof response construction.
- `public-rpc-call-objects.lisp`: public call-object parsing, simulation gas
  defaults, and transaction synthesis.
- `public-rpc-call-simulation.lisp`: public call simulation and `eth_call`
  response handling.
- `public-rpc-gas.lisp`: `eth_estimateGas` gas caps and binary search.
- `public-rpc-access-lists.lisp`: `eth_createAccessList` access collection and
  response rendering.
- `public-rpc-transaction-fields.lisp`: transaction JSON field rendering,
  access list rendering, type-specific fields, and sender/gas-price helpers.
- `public-rpc-transaction-objects.lisp`: transaction JSON object assembly,
  lookup wrappers, pending transaction helpers, and shared JSON array
  normalization.
- `public-rpc-transactions.lisp`: raw transaction and transaction lookup
  handlers.
- `public-rpc-txpool-views.lisp`: txpool JSON table and transaction view
  helpers.
- `txpool-admission-service.lisp`: application-level
  `eth_sendRawTransaction` validation, admission policy, subpool routing, and
  promotion rules.
- `public-rpc-txpool-locals.lisp`: local transaction exemption predicates and
  expiry cleanup.
- `public-rpc-send-raw-transaction.lisp`: `eth_sendRawTransaction` handler.
- `public-rpc-txpool-handlers.lisp`: `eth_pendingTransactions` and `txpool_*`
  namespace handlers.
- `public-rpc-receipts.lisp`: log, receipt, and block receipt result
  construction and handlers.
- `public-rpc-header-objects.lisp`: public header result objects and header
  lookup handlers.
- `public-rpc-block-*.lisp`: public block RLP sizing, block result objects,
  block lookup handlers, and transaction-count handlers.
- `public-rpc-ommer-handlers.lisp`: public ommer count and ommer lookup
  handlers.
- `public-rpc-log-filters.lisp`: public log filter parsing, matching, block
  selection, and log result construction.
- `public-rpc-filter-changes.lisp`: log, block, and pending-transaction filter
  change calculation.
- `public-rpc-filter-handlers.lisp`: public filter install/query/uninstall
  handlers.
- `public-rpc-dispatch-*.lisp`: public JSON-RPC dispatch context plus
  metadata, state, block, transaction, filter, and txpool method routing.
- `public-api-dispatch.lisp`: final public JSON-RPC method dispatch.
- `rpc-http/auth.lisp`: Engine API JWT token creation and validation.
- `rpc-http/parser.lisp`: HTTP parsing and bounded stream request reading.
- `rpc-http/telemetry.lisp`: request/response telemetry extraction.
- `rpc-http/policy.lisp`: CORS/host policy and response rendering.
- `rpc-http/handler.lisp`: context-based request and single-stream handling,
  plus legacy store/config adapters.
- `rpc-http/service.lisp`: HTTP service model, validation, and RPC context
  construction.
- `rpc-http/listener.lisp`: connection/listener contracts and the SBCL socket
  adapter.
- `rpc-http/server.lisp`: configured stream delegation and listener serve loop.
- `state-types.lisp`: state units, mutable state records, proof records,
  range records, and state key coercion helpers.
- `state-db.lisp`: mutable account/code/storage access, copy/restore helpers,
  and storage trie proof primitives.
- `state-roots.lisp`: account trie construction, account proofs, and state
  root rendering.
- `state-proofs.lisp`: proof result construction and verification.
- `ethereum-lisp.state-proof-json` / `state-proof-json.lisp`: state-proof
  JSON-RPC object conversion and parsing outside the state domain.
- `state-ranges.lisp`: account/storage range iteration and deterministic
  state export helpers.
- `ethereum-lisp.genesis-state` / `genesis-state.lisp`: the application bridge
  that materializes genesis allocations in state and derives genesis roots,
  headers, and blocks. The state domain itself has no genesis dependency.
- `evm-types.lisp`: EVM errors, result/context records, precompile address
  activation, gas constants, and fixed precompile tables.
- `ethereum-lisp.evm` is a public facade that only re-exports the supported
  context, result, precompile-address, and execution API.
  `ethereum-lisp.evm.internal` owns runtime, precompile, and interpreter
  implementation symbols; application layers must not use that package.
- `evm-runtime-context.lisp`: child EVM context construction and inherited
  frame fields for CREATE and CALL-family opcodes.
- `evm-runtime-base.lisp`: EVM word arithmetic, fork checks, errors, and stack
  pop/push helpers.
- `evm-runtime-memory.lisp`: memory expansion, data slicing, memory copy, and
  mload/mstore helpers.
- `evm-runtime-opcodes.lisp`: PUSH immediate decoding, byte extraction, EXP
  gas, jump-destination checks, and base opcode gas.
- `evm-runtime-conversions.lisp`: word/address/hash conversions and
  difficulty/prev-randao context lookup.
- `evm-runtime-transient-storage.lisp`: transient storage keys, load/store,
  and frame snapshot copy/restore helpers.
- `evm-runtime-storage-gas.lisp`: SSTORE refund keys, cleared-slot snapshots,
  and dynamic SSTORE gas calculation.
- `evm-runtime-access-lists.lisp`: account/storage warm access tracking and
  EIP-2929 access gas charging.
- `evm-runtime-selfdestructs.lisp`: selfdestruct address snapshots, marking,
  and finalization.
- `evm-runtime-snapshots.lisp`: frame/execution snapshot capture,
  access-list snapshot refresh, and restore helpers for rollback.
- `evm-runtime-state.lisp`: account mutation, value transfer, delegated code
  resolution, and selfdestruct state updates.
- `evm-runtime-create.lisp`: CREATE/CREATE2 address derivation, initcode gas,
  code size limits, and created-code validation.
- `evm-runtime-gas.lisp`: remaining gas, EIP-150 child gas, and call stipend
  accounting helpers.
- `evm-runtime-block.lisp`: nonce increment, account-code hash, blockhash, and
  blobhash word helpers.
- `evm-precompiles-utils.lisp`: shared precompile byte, endian, and fixed-size
  integer helpers.
- `evm-precompiles-modexp.lisp`: EIP-198 modular exponentiation gas and
  execution.
- `evm-precompiles-bn254-base.lisp`: BN254 base field, G1, Fp2, and basic
  add/mul precompile helpers.
- `evm-precompiles-bn254-g2.lisp`: BN254 G2 parsing, subgroup checks, and
  Fp2 equality helpers.
- `evm-precompiles-bn254-fields.lisp`: BN254 Fp6/Fp12 arithmetic and
  Frobenius constants.
- `evm-precompiles-bn254-pairing.lisp`: BN254 Miller loop, final
  exponentiation, pairing backend, and pairing precompile.
- `evm-precompiles-kzg.lisp`: KZG point-evaluation precompile.
- `evm-precompiles-blake2f.lisp`: BLAKE2F compression precompile and gas
  calculation.
- `evm-precompiles-dispatch.lisp`: ecrecover, precompile gas precheck, and
  final precompile dispatch.
- `evm-interpreter-results.lisp`: child execution result rollback, gas,
  return-data, and log merge helpers for the bytecode interpreter.
- `evm-interpreter-create.lisp`: shared CREATE/CREATE2 child execution,
  rollback, code-deposit, and result mapping helpers.
- `evm-interpreter-call.lisp`: declarative CALL-family plans plus the shared
  memory, access-gas, snapshot, child execution, rollback, and result-merge
  pipeline.
- `evm-interpreter-machine.lisp`: explicit mutable call-frame state and the
  stack, gas, memory, halt, and result operations that preserve its invariants.
- `evm/opcodes/`: opcode semantics grouped by protocol responsibility:
  arithmetic, environment, state/memory, stack/log, and system operations.
  Handlers receive one machine object and do not own the fetch loop.
- `evm/interpreter.lisp`: one-step fetch, base-gas charging, step limits, and
  opcode-family dispatch.
- `evm.lisp`: stable public execution entry point; it owns frame lifetime but
  contains no opcode semantics.
- `execution-contract.lisp`: execution validation condition plus gas, nonce,
  code-size, refund, and proof-of-work reward constants.
- `execution-state.lisp`: account mutation helpers, code resolution, contract
  address derivation, and collision checks.
- `execution-rewards.lisp`: block beneficiary and ommer reward calculation.
- `execution-gas.lisp`: transaction gas math, effective gas price, initcode
  and runtime code limits, and intrinsic gas helpers.
- `execution-transaction-fields.lisp`: execution transaction scalar,
  access-list, set-code, and sender-code field validation.
- `execution-validation.lisp`: fork-aware transaction and transaction-list
  validation orchestration.
- `execution-set-code.lisp`: EIP-7702 authorization application and refund
  accounting.
- `execution-accounting.lisp`: sender upfront charge, value transfer,
  gas refund, priority fee payment, and receipt finalization.
- `execution-access.lisp`: access-list/precompile prewarming and accessed
  address/storage table construction.
- `execution-rules.lisp`: fork-rule selection, blob gas limits, and block blob
  base-fee derivation.
- `execution-context.lisp`: EVM context creation for message execution.
- `execution-call-simulation.lisp`: copied-state call execution for
  `eth_call`, gas estimation, and access-list simulation.
- `execution-apply-contract.lisp`: state-mutating contract creation.
- `execution-signatures.lisp`: transaction chain-id selection and sender
  recovery helpers.
- `execution-apply-message.lisp`: state-mutating message application and
  signed/legacy wrappers.
- `execution-message-lists.lisp`: transaction-list execution and execution
  result construction.
- `execution-legacy.lisp`: withdrawal application and legacy transaction-list
  entry points over the EVM-backed message executor, without a partial state
  fallback.
- `execution-block-body-validation.lisp`: block body commitment checks,
  access-list body normalization, and execution root validation.
- `execution-block-validation.lisp`: fork body-shape checks and block header
  snapshot/restore helpers.
- `execution-block-execution.lisp`: shared block execution skeleton plus
  signed and legacy block execution entry points.
- `ethereum-lisp.execution-service` / `execution-service.lisp`: state-db and
  chain-store projection, atomic block commit, and Engine payload import. The
  execution domain itself contains no storage adapter dependency.
- `cli-types.lisp`: devnet CLI records, defaults, embedded dev genesis,
  canonical-transition persistence port, and shutdown signal helpers.
- `cli-files.lisp`: CLI file, datadir, JWT secret, and KV database path
  helpers.
- `cli-devnet-persistence.lisp`: devnet persisted chain and txpool import
  helpers.
- `cli-devnet-node.lisp`: devnet node construction, genesis import, service
  construction, and Merge option overrides.
- `cli-devnet-runtime.lisp`: devnet state pruning, txpool journaling, database
  export, and guarded dev-period sealing that stages execution noncanonically,
  publishes an explicit canonical transition, and commits its record-scoped
  delta before releasing public visibility.
- `cli-devnet-summary.lisp`: devnet status summaries and JSON summary
  objects.
- `cli-devnet-background.lisp`: devnet periodic background worker threads;
  explicitly classified dev-period file-write failures are warned and retried
  on a later tick, while execution, validation, corruption, and callback
  invariant failures retain fail-stop shutdown semantics.
- `cli-devnet-service.lisp`: devnet listener serving and
  startup orchestration.
- `cli-option-definitions.lisp`: geth-compatible option arity metadata.
- `cli-args.lisp`: command-line token normalization, boolean token handling,
  and command-token lookup.
- `cli-config-toml.lisp`: minimal TOML value parsing for geth-compatible
  devnet config files.
- `cli-config.lisp`: geth config-file key mapping and config-to-CLI option
  application.
- `cli-parsers.lisp`: CLI scalar parsers for ports, durations, quantities,
  addresses, RPC prefixes, API module filters, CORS, and vhosts.
- `cli-options.lisp`: geth-compatible devnet option aggregation.
- `cli-output.lisp`: CLI usage, version, summary, ready-file, and pid-file
  output helpers.
- `cli-kzg.lisp`: CLI-scoped KZG verifier hook configuration.
- `cli-telemetry.lisp`: CLI telemetry fields and lifecycle event emission.
- `cli-telemetry-sinks.lisp`: CLI telemetry stream sink selection and error
  logging.
- `cli-init.lisp`: `init` command option parsing and datadir initialization.
- `cli.lisp`: top-level command dispatcher.
## Dependency Rules

- Consensus data types may use primitives, RLP, crypto, trie, and chain rules.
- State may use account types and trie commitments, but not genesis parsing.
- Genesis-state assembly may bridge genesis input and mutable state.
- Node state may compose chain-store state and txpool index state; neither
  domain may own the other domain's mutable state.
- EVM may use state and consensus types, but not RPC or CLI.
- Execution may use EVM, state, and consensus types, but not chain store.
- Execution services may bridge pure execution, state, and chain-store APIs.
- Bridge and transport APIs are exported only by their owning packages; domain
  packages do not re-export higher-layer symbols for qualified-name
  compatibility. The top-level public facade is the compatibility boundary.
- Architecture tests require the project package graph to remain acyclic and
  every non-facade package to own each symbol it exports.
- RPC may use execution and store APIs, but protocol types must not depend on
  RPC JSON shapes.
- HTTP transport may call RPC dispatch, but RPC dispatch should not depend on
  sockets or listener state.
- CLI and devnet lifecycle are top-level orchestration only.

## Refactor Order

Prefer behavior-preserving slices:

1. Identify the owner, public contract, invariants, and allowed dependencies.
2. Define or tighten the package boundary and its tests.
3. Move or consolidate the cohesive implementation behind that boundary.
4. Update load order and run the full test suite.

Avoid mixing file moves, semantic fixes, and API changes in one slice.
