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

The project still has a legacy `ethereum-lisp.core` package. File size and
name prefixes are not module boundaries: a refactor must first identify an
owner, its public contract, and the allowed dependency direction. Split code
only when the resulting units have cohesive behavior and communicate through
an explicit API or state object. Keep compatibility facades thin, and move
implementation symbols into narrower packages as their contracts stabilize.

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
- `packages-core.lisp`: compatibility aggregate for the remaining core
  protocol surface; it re-exports narrower domain APIs while callers migrate.
- `packages-runtime.lisp`: state, EVM, execution, and CLI package definitions.
- `packages-facade.lisp`: top-level `ethereum-lisp` facade imports and
  exports.
- `packages.lisp`: package compatibility loader.
- `database-*.lisp`: key-value database protocol, chain-record key encoding,
  memory/file backends, write batches, and chain-record access helpers.
- `database.lisp`: compatibility package entry for database modules.
- `crypto-constants.lisp`: hash, KZG, secp256k1, SHA-256, Keccak, and
  RIPEMD-160 constants and round tables.
- `crypto-words.lisp`: 32-bit/64-bit rotation and endian load/store helpers.
- `crypto-keccak.lisp`: Ethereum legacy Keccak-256 sponge implementation.
- `crypto-sha256.lisp`: SHA-256 compression and digest helpers.
- `crypto-ripemd160.lisp`: RIPEMD-160 compression and digest helpers.
- `crypto-kzg.lisp`: KZG commitment versioned-hash conversion.
- `crypto-math.lisp`: fixed-width integer encoding and modular arithmetic.
- `crypto-secp256k1.lisp`: secp256k1 point arithmetic, key/address
  derivation, and public key recovery.
- `crypto-empty-hashes.lisp`: canonical empty code and empty trie hashes.
- `crypto.lisp`: compatibility package entry for crypto modules.
- `trie-encoding.lisp`: hex-prefix nibble encoding primitives.
- `trie-types.lisp`: Merkle Patricia Trie node and in-memory store types.
- `trie-store.lisp`: mutable trie entry put/get/delete and ordered scans.
- `trie-nodes.lisp`: canonical node construction, node RLP references, and
  root hash derivation.
- `trie-proofs.lisp`: proof construction and proof verification.
- `trie.lisp`: compatibility package entry for trie modules.
- `ethereum-lisp.validation` / `validation.lisp`: shared block validation
  condition plus protocol value and fixed-byte validation helpers. Core
  re-exports the public condition for compatibility.
- `ethereum-lisp.chain-config` / `chain-config-*.lisp`: an independent
  protocol package for chain configuration types, fork activation predicates,
  blob schedule selection, and effective chain-rule construction. Core
  re-exports this API for compatibility.
- `chain-config.lisp`: compatibility package entry for chain config modules.
- `ethereum-lisp.transactions` / `transactions-*.lisp`: the transaction
  domain owns envelopes, codecs, signatures, common accessors, fee rules, and
  fork support policy. It depends on chain rules and protocol primitives, not
  on `ethereum-lisp.core`; core re-exports its public API for compatibility.
- `ethereum-lisp.json` / `json-read.lisp` / `json-write.lisp` /
  `json-object-fields.lisp`: JSON parsing, encoding, shape predicates, object
  access, and quantity decoding without genesis or RPC ownership.
- `ethereum-lisp.genesis` / `genesis-*.lisp`: genesis account values,
  genesis-specific field and alloc parsing, chain-config conversion, file I/O,
  and fork-aware genesis block construction. It consumes JSON, chain config,
  receipt, execution-request, and block contracts without depending on core.
- `core-constants.lisp`: protocol constants shared across core modules.
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
  validation. CLI configures the verifier port without owning KZG behavior.
- `ethereum-lisp.engine-payloads` / `engine-payload-*.lisp`: Engine payload
  values and statuses, defensive codecs, block mapping, fork-version checks,
  payload-id derivation, and empty payload construction. Stores and RPC depend
  on this contract; the package has no store, RPC, or HTTP dependency.
- `ethereum-lisp.chain-store.model` / `chain-store-types.lisp`: in-memory
  store, checkpoint, transaction-location, filter, and blob lookup records.
  The model owns no storage behavior and depends only on protocol types and
  the txpool index model.
- `chain-store-memory-guards.lisp`: shared memory-store type checks for
  in-memory-only chain-store operations.
- `chain-store-copy-values.lisp`: defensive copying for shared store values,
  filters, checkpoints, and blob proof records.
- `chain-store-copy-blocks.lisp`: defensive copying for block headers, logs,
  receipts, blocks, prepared payloads, and transactions.
- `txpool-index-copy.lisp`: txpool deep-copy behavior that preserves shared
  transaction identity across subpool and sender indexes without depending on
  chain-store copying helpers.
- `chain-store-copy-locations.lisp`: transaction-location deep-copy helpers
  that keep copied blocks, receipts, and transactions aligned.
- `chain-store-snapshots.lisp`: memory-store snapshot/restore and atomic commit
  helpers.
- `chain-store-copy.lisp`: chain-store copy compatibility loader.
- `chain-store-filters.lisp`: in-memory block, log, and pending transaction
  filter registration and notifications.
- `chain-store-cache.lisp`: in-memory remote block, invalid payload,
  prepared payload, and blob sidecar caches.
- `chain-store-memory-blocks.lisp`: in-memory block storage, lookup, and
  forkchoice checkpoint updates.
- `chain-store-memory.lisp`: public chain-store wrappers around the
  memory-store implementation.
- `chain-store-state-availability.lisp`: retained state availability checks
  and state snapshot pruning.
- `chain-store-account-state.lisp`: retained account balance, nonce, code, and
  storage read/write helpers.
- `chain-store-state-iteration.lisp`: retained account and storage iteration
  helpers for export and state projection.
- `chain-store-state.lisp`: chain-store state compatibility loader.
- `chain-store-canonical-indexes.lisp`: canonical hash, block number, parent,
  block-membership, and ancestor checks.
- `chain-store-transaction-locations.lisp`: canonical transaction location
  indexing and lookup.
- `chain-store-txpool-rules.lisp`: txpool admission rules that need current
  chain state.
- `chain-store-reorg-txpool.lisp`: displaced transaction reinsertion after
  canonical reorgs.
- `chain-store-canonical-head.lisp`: canonical head updates, reorg cleanup,
  txpool refresh, and filter notifications.
- `chain-store-canonical.lisp`: compatibility package entry for canonical
  chain-store modules.
- `txpool-store-*.lisp`: engine payload store wrappers for txpool access,
  conflict/replacement checks, subpool indexing, admission, sender views, and
  accounting.
- `txpool.lisp`: compatibility package entry for txpool store modules.
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
- `txpool-promotion.lisp`: compatibility package entry for txpool promotion
  modules.
- `txpool-cleanup-lifecycle.lisp`: stale nonce and expired queued-view
  transaction removal.
- `txpool-cleanup-new-head.lisp`: invalid sender, sender-code, gas-limit, and
  blob-fee cleanup after canonical-head changes.
- `txpool-pending-revalidation.lisp`: pending transaction demotion and sender
  revalidation after canonical-head changes.
- `txpool-cleanup.lisp`: compatibility package entry for txpool cleanup
  modules.
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
- `block-validation.lisp`: block validation compatibility loader.
- `engine-payload-status.lisp`: Engine forkchoice/newPayload status for the
  in-memory chain store.
- `engine-rpc-protocol.lisp`: JSON-RPC envelopes, response helpers, and
  Engine/public method filters.
- `engine-rpc-field-codecs.lisp`: Engine API field coercion.
- `engine-rpc-payload-input-codecs.lisp`: Engine payload JSON object decoding.
- `engine-rpc-payload-codecs.lisp`: Engine payload/status object rendering.
- `engine-rpc-forkchoice-codecs.lisp`: forkchoice state and payload attribute
  validation.
- `engine-rpc-capabilities.lisp`: Engine capability lists, client version, and
  transition configuration rendering.
- `engine-rpc-codecs.lisp`: compatibility package entry for Engine RPC codecs.
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
- `public-rpc-call-defaults.lisp`: default gas-limit selection for public
  call-style methods.
- `public-rpc-metadata.lisp`: web3, net, rpc_modules, and basic eth metadata
  handlers.
- `public-rpc-fees.lisp`: gas price, priority fee, base fee, and blob base-fee
  handlers.
- `public-rpc-fee-history.lisp`: `eth_feeHistory` parameter validation and
  response construction.
- `public-rpc-core.lisp`: compatibility package entry for public RPC core
  modules.
- `public-rpc-state-queries.lisp`: public account balance, nonce, code, and
  storage reads.
- `public-rpc-state-proofs.lisp`: `eth_getProof` storage slot coercion and
  proof response construction.
- `public-rpc-call-objects.lisp`: public call-object parsing and transaction
  synthesis.
- `public-rpc-call-simulation.lisp`: public call simulation and `eth_call`
  response handling.
- `public-rpc-gas.lisp`: `eth_estimateGas` gas caps and binary search.
- `public-rpc-access-lists.lisp`: `eth_createAccessList` access collection and
  response rendering.
- `public-rpc-state.lisp`: compatibility package entry for public state RPC
  modules.
- `public-rpc-transaction-fields.lisp`: transaction JSON field rendering,
  access list rendering, type-specific fields, and sender/gas-price helpers.
- `public-rpc-transaction-objects.lisp`: transaction JSON object assembly,
  lookup wrappers, pending transaction helpers, and shared JSON array
  normalization.
- `public-rpc-transactions.lisp`: raw transaction and transaction lookup
  handlers.
- `public-rpc-txpool-views.lisp`: txpool JSON table and transaction view
  helpers.
- `public-rpc-txpool-admission.lisp`: `eth_sendRawTransaction` validation and
  txpool admission rules.
- `public-rpc-txpool-locals.lisp`: local transaction exemption predicates and
  expiry cleanup.
- `public-rpc-send-raw-transaction.lisp`: `eth_sendRawTransaction` handler.
- `public-rpc-txpool-handlers.lisp`: `eth_pendingTransactions` and `txpool_*`
  namespace handlers.
- `public-rpc-txpool.lisp`: compatibility package entry for txpool RPC modules.
- `public-rpc-receipts.lisp`: log, receipt, and block receipt result
  construction and handlers.
- `public-rpc-header-objects.lisp`: public header result objects and header
  lookup handlers.
- `public-rpc-block-*.lisp`: public block RLP sizing, block result objects,
  block lookup handlers, and transaction-count handlers.
- `public-rpc-ommer-handlers.lisp`: public ommer count and ommer lookup
  handlers.
- `public-rpc-blocks.lisp`: compatibility package entry for public block RPC
  modules.
- `public-rpc-log-filters.lisp`: public log filter parsing, matching, block
  selection, and log result construction.
- `public-rpc-filter-changes.lisp`: log, block, and pending-transaction filter
  change calculation.
- `public-rpc-filter-handlers.lisp`: public filter install/query/uninstall
  handlers.
- `public-rpc-dispatch-*.lisp`: public JSON-RPC dispatch context plus
  metadata, state, block, transaction, filter, and txpool method routing.
- `public-rpc.lisp`: final public JSON-RPC method dispatch.
- `engine-rpc-http-auth.lisp`: Engine API JWT token creation, validation, and
  signing helpers.
- `engine-rpc-http-parsing.lisp`: HTTP request-line, target, header,
  content-type, content-length, boundary, and body parsing helpers.
- `engine-rpc-http-telemetry.lisp`: HTTP request/response telemetry
  extraction for JSON-RPC methods, error codes, and payload statuses.
- `engine-rpc-http-request-read.lisp`: stream-to-request-string reader.
- `engine-rpc-http-response.lisp`: HTTP response and error response
  formatting helpers.
- `engine-rpc-http-policy.lisp`: CORS response headers and host allowlist
  checks.
- `engine-rpc-http-wire.lisp`: compatibility package entry for HTTP wire
  modules.
- `engine-rpc-dispatch.lisp` and `engine-rpc-json.lisp`: JSON-RPC object,
  batch, string, and encoded response handling.
- `engine-rpc-http-request.lisp` and `engine-rpc-http.lisp`: HTTP request
  validation, JSON-RPC body handling, stream response writing, and request
  telemetry.
- `engine-rpc-http-service-*.lisp`: Engine HTTP service configuration, listener
  abstractions, socket listener construction, stream delegation, and serve loop.
- `state-types.lisp`: state constants, mutable state records, proof records,
  range records, and state key coercion helpers.
- `state-db.lisp`: mutable account/code/storage access, copy/restore helpers,
  and storage trie proof primitives.
- `state-roots.lisp`: account trie construction, account proofs, and state
  root rendering.
- `state-proofs.lisp`: proof result construction and verification.
- `state-proof-rpc.lisp`: JSON-RPC proof object conversion and parsing.
- `state-ranges.lisp`: account/storage range iteration and deterministic
  state export helpers.
- `state-genesis.lisp`: genesis allocation application, genesis state roots,
  and genesis block/header construction.
- `state-transactions.lisp`: withdrawal balance updates, intrinsic gas, and
  standalone legacy transaction execution fallback.
- `state.lisp`: state package compatibility loader.
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
- `evm-runtime-access.lisp`: EVM access helper compatibility loader.
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
- `evm-runtime.lisp`: EVM runtime compatibility loader.
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
- `evm-precompiles.lisp`: EVM precompile compatibility loader.
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
- `execution-constants.lisp`: execution gas, nonce, code-size, refund, and
  proof-of-work reward constants.
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
- `execution-message.lisp`: compatibility package entry for execution message
  modules.
- `execution-block-body-validation.lisp`: block body commitment checks,
  access-list body normalization, and execution root validation.
- `execution-block-validation.lisp`: fork body-shape checks and block header
  snapshot/restore helpers.
- `execution-block-execution.lisp`: shared block execution skeleton plus
  signed and legacy block execution entry points.
- `execution-chain-state.lisp`: state-db to chain-store snapshot projection
  and retained-state reconstruction.
- `execution-block-commit.lisp`: atomic chain-store block commit and Engine
  payload commit entry points.
- `execution.lisp`: compatibility package entry for block execution modules.
- `cli-types.lisp`: devnet CLI records, defaults, embedded dev genesis, and
  shutdown signal helpers.
- `cli-files.lisp`: CLI file, datadir, JWT secret, and KV database path
  helpers.
- `cli-devnet-persistence.lisp`: devnet persisted chain and txpool import
  helpers.
- `cli-devnet-node.lisp`: devnet node construction, genesis import, service
  construction, and Merge option overrides.
- `cli-devnet-runtime.lisp`: devnet state pruning, txpool journaling,
  dev-period block sealing, and database export.
- `cli-devnet-summary.lisp`: devnet status summaries and JSON summary
  objects.
- `cli-devnet-background.lisp`: devnet periodic background worker threads.
- `cli-devnet-service.lisp`: devnet listener serving and
  startup orchestration.
- `cli-devnet.lisp`: devnet compatibility loader.
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
