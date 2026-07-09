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
- `chain-config-*.lisp`: chain configuration types, fork activation
  predicates, blob schedule selection, and effective chain-rule construction.
- `chain-config.lisp`: compatibility package entry for chain config modules.
- `genesis-types.lisp`: genesis constants and alloc account structure.
- `genesis-object-fields.lisp`: shared genesis object lookup and scalar field
  parsing helpers.
- `genesis-alloc.lisp`: genesis account code, storage, and alloc parsing.
- `genesis-json-read.lisp`: small JSON reader and JSON shape predicates.
- `genesis-json-write.lisp`: JSON writer helpers.
- `genesis-chain-config.lisp`: genesis config to fork-rule chain config
  conversion.
- `genesis-io.lisp`: genesis JSON string/file entry points and expected
  state-root parsing.
- `genesis.lisp`: compatibility package entry for genesis modules.
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
- `transactions-set-code-authorization.lisp`: EIP-7702 authorization tuples
  and delegation code helpers.
- `transactions-set-code.lisp`: EIP-7702 set-code transaction
  encoding/decoding.
- `transactions-accessors.lisp`: cross-type transaction accessors, type
  dispatch, blob gas counting, and access-list sizing.
- `transactions.lisp`: transaction fork validation, gas-price calculation,
  unified encoding/decoding, and sender dispatch.
- `receipts.lisp`: withdrawals, logs, blooms, receipts, trie-list roots.
- `txpool-types.lisp`: txpool index structure required by the store type.
- `blocks-*.lisp` and `block-header-rlp.lisp`: block header/body structures,
  block hashing, construction, and block RLP encode/decode helpers.
- `blocks.lisp`: compatibility package entry for block modules.
- `consensus-validation.lisp`: shared consensus validation primitives,
  hash equality, sized-byte checks, and fee-market calculations.
- `consensus-field-validation.lisp`: shared scalar, byte, hash, address, and
  ordering validators for consensus-facing objects.
- `consensus-transaction-validation.lisp`: consensus-facing transaction field
  validation for block, RPC, and txpool admission paths.
- `block-access-list-types.lisp`: Amsterdam block access list structures.
- `block-access-list-execution-requests.lisp`: execution request validation and
  hashing.
- `block-access-list-validation.lisp`: Amsterdam block access list account,
  storage, and ordering validators.
- `block-access-list-rlp.lisp`: block access list RLP encoding and decoding.
- `block-access-list-commitments.lisp`: block access list hash and encoded-body
  consistency checks.
- `block-access-list.lisp`: compatibility package entry for block access list
  modules.
- `genesis-block.lisp`: fork-aware genesis header and block construction.
- `kzg-verifier-hooks.lisp`: optional KZG point/blob proof verifier hook
  variables and availability checks.
- `kzg-command-verifier.lisp`: command-backed KZG verifier adapter.
- `kzg-validation.lisp`: KZG field, point/blob proof, and blob sidecar
  validation.
- `kzg.lisp`: compatibility package entry for KZG modules.
- `engine-payload-types.lisp`: Engine payload structs, forkchoice payload
  attributes, status constants, and prepared payload validation.
- `engine-payload-codecs.lisp`: defensive payload copying and block-to-payload
  conversion.
- `engine-payload-block-fields.lisp`: executable-data transaction decoding,
  versioned-hash validation, and required field checks.
- `engine-payload-blocks.lisp`: executable-data payload-to-block
  reconstruction.
- `engine-payload-validation.lisp`: `newPayload` parameter, fork-version, and
  payload status validation.
- `engine-payload-build.lisp`: payload-id derivation and empty payload
  construction.
- `engine-payloads.lisp`: Engine payload compatibility loader.
- `chain-store-types.lisp`: in-memory chain store records, filter cursors,
  blob lookup records, and shared store key helpers.
- `chain-store-memory-guards.lisp`: shared memory-store type checks for
  in-memory-only chain-store operations.
- `chain-store-copy-values.lisp`: defensive copying for shared store values,
  filters, checkpoints, and blob proof records.
- `chain-store-copy-blocks.lisp`: defensive copying for block headers, logs,
  receipts, blocks, prepared payloads, and transactions.
- `chain-store-copy-txpool.lisp`: txpool deep-copy helpers that preserve
  shared transaction identity across txpool indexes.
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
- `txpool-index-keys.lisp`: txpool sender/nonce/hash keys and admission
  timestamps.
- `txpool-index-tables.lisp`: generic sender/nonce table indexing helpers.
- `txpool-index-subpools.lisp`: pending, queued, basefee, and blob subpool
  wrappers.
- `txpool-index-replacement.lisp`: replacement price-bump checks.
- `txpool-index-conflicts.lisp`: cross-subpool conflicts and replacement
  removal.
- `txpool-index-insert.lisp`: txpool insertion paths for all subpools.
- `txpool-index-views.lisp`: txpool lookup, list, count, and empty views.
- `txpool-index.lisp`: compatibility package entry for txpool index modules.
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
- `evm-runtime-base.lisp`: EVM word arithmetic, fork checks, errors, and stack
  pop/push helpers.
- `evm-runtime-memory.lisp`: memory expansion, data slicing, memory copy, and
  mload/mstore helpers.
- `evm-runtime-opcodes.lisp`: PUSH immediate decoding, byte extraction, EXP
  gas, jump-destination checks, and base opcode gas.
- `evm-runtime-conversions.lisp`: word/address/hash conversions and
  difficulty/prev-randao context lookup.
- `evm-runtime-access.lisp`: transient storage, storage/access warming,
  selfdestruct snapshots, and dynamic SSTORE gas.
- `evm-runtime-state.lisp`: execution snapshot restore, account mutation,
  value transfer, delegated code resolution, and selfdestruct state updates.
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
- `evm.lisp`: bytecode interpreter loop and opcode execution.
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
- `cli-devnet-node.lisp`: devnet node construction, genesis import, service
  construction, and Merge option overrides.
- `cli-devnet-runtime.lisp`: devnet state pruning, txpool journaling,
  dev-period block sealing, and database export.
- `cli-devnet-summary.lisp`: devnet status summaries and JSON summary
  objects.
- `cli-devnet-service.lisp`: devnet background threads, listener serving, and
  startup orchestration.
- `cli-devnet.lisp`: devnet compatibility loader.
- `cli-args.lisp`: command-line token normalization, option arity metadata,
  boolean token handling, and command-token lookup.
- `cli-config-toml.lisp`: minimal TOML value parsing for geth-compatible
  devnet config files.
- `cli-config.lisp`: geth config-file key mapping and config-to-CLI option
  application.
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
