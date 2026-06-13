# Roadmap

The goal is a Common Lisp Ethereum execution-layer client. The work is split
into milestones that can be validated independently.

This file is the strategic roadmap. Tactical implementation slices live in
`docs/tasks.md`; long-running automation should choose work from that backlog
instead of picking ad hoc roadmap items.

## Project Target

The project is not trying to become a production mainnet node in one jump. The
near-term target is a fixture-checkable execution client core:

1. **Phase A: verifiable chain import.** Load genesis/state, accept executable
   Engine payloads with known parent state, execute transactions, validate
   state/receipt/log/gas commitments, persist enough block/state data for local
   queries, and update canonical forkchoice state.
2. **Phase B: local devnet Engine/RPC node.** Serve Engine API and public
   JSON-RPC over a concrete local transport, with enough txpool and retained
   state behavior to drive small devnet scenarios.
3. **Phase C: persistence, sync, and production depth.** Add file-backed
   storage, staged sync shape, pruning/history policies, networking, metrics,
   and Hive-compatible process wiring.

Roadmap entries should stay strategic: each milestone should summarize what is
done, what is partial, what remains, and what validation closes the gap. Detailed
small-slice history belongs in `docs/tasks.md` or a future status/changelog
document.

## Phase A Scope Gate

Phase A locks a single fork target and a pinned fixture set so the smoke path
is unambiguous. Other forks and Engine/RPC versions remain implemented in the
tree but are explicitly outside the Phase A acceptance bar.

- **Target fork:** post-Merge Shanghai, driven through `engine_newPayloadV2`.
  Cancun and blob-aware paths only join Phase A once real KZG proof
  verification lands; until then they are exercised as shape checks only.
- **Fixture set:** `ethereum/execution-spec-tests` standard release `v5.4.0`
  (`88e9fb8` tag target), using `fixtures_stable.tar.gz` and initially
  selecting the post-Merge Shanghai cases needed by the Phase A smoke path,
  plus a small in-repo hand-written set. `fixtures_develop`, Osaka/Fusaka
  additions, BAL/devnet pre-releases, and zkEVM fixtures are outside Phase A
  unless a later task explicitly widens the gate.
- **Invariants required before Phase A closes:**
  - *Atomic import.* `engine_newPayload` runs pre-state snapshot → transaction
    execution → receipt/root derivation → post-execution commitment validation
    → block/state/receipt index commit, all or nothing. No partial state is
    visible if any later step fails.
  - *Strict sender recovery.* Every signed import, admission, and mined-tx RPC
    path requires real signature recovery. No zero-address or empty-sender
    fallback is allowed in those paths.
  - *Receipt root correctness.* Typed receipt encoding, cumulative-gas
    monotonicity, log order, logs bloom, contract-address derivation, and
    post-Byzantium status semantics are all locked. Pre-Byzantium post-state
    receipts are out of Phase A scope.
  - *Reorg invariants.* Side-chain blocks remain retrievable by hash, the
    canonical number-to-hash index only references canonical blocks,
    transaction and receipt lookups follow canonical rewrites, and `safe` /
    `finalized` may not move to a non-ancestor of the current head.

**Surface freeze.** While Phase A is open, new work on Engine/RPC/txpool
surface beyond fixing Phase A blockers is paused. Far-fork support (Amsterdam
BAL beyond what already parses, BPO5, `engine_getPayloadV6`) does not receive
new feature work until the Phase A smoke path passes once end-to-end. Bug
fixes in those areas are allowed; expansion is not.

## Current Strategic Read

- **Done:** project substrate, Ethereum domain types, RLP/Keccak basics, broad
  first-pass EVM/block-execution coverage, in-memory Engine payload storage,
  forkchoice checkpoints, public read RPCs, polling filters, local pending
  transaction placeholders, and the first chain-store boundary over the memory
  store with explicit canonical number-to-hash indexes and typed head/safe/
  finalized checkpoints. Engine forkchoice updates now drive the in-memory
  canonical-head switch path, including transaction, receipt, block-receipt,
  state, and log visibility across branch switches. Public `eth_call` can now
  execute simple retained-state calls against a copied state DB without
  committing writes, returning REVERT data while rejecting non-revert
  execution failures instead of reporting them as successful empty output, and
  `eth_estimateGas` can binary-search retained-state call simulations for
  simple transfers and contract calls while detecting reverts. These
  retained-state simulation APIs now also accept
  contract-creation call objects, executing initcode against copied state,
  returning creation output for `eth_call`, accounting for code-deposit gas in
  `eth_estimateGas` / `eth_createAccessList`, and leaving retained chain-store
  state unchanged. Call-object `value` is now applied inside the copied
  retained-state simulation for both recipient calls and contract creation, so
  balance reads observe the simulated transfer while overdrafts are rejected.
  `eth_estimateGas` now derives contract-creation intrinsic gas from the
  selected block's fork rules, so pre-Shanghai estimates do not include
  EIP-3860 initcode word gas while Shanghai-and-later estimates retain it.
  Call-object `accessList` entries now build typed access-list simulation
  transactions for `eth_call`, `eth_estimateGas`, and
  `eth_createAccessList`, so retained-state simulations honor warm-account /
  warm-storage behavior and access-list intrinsic gas.
  Explicit EIP-1559 call-object fee fields now build dynamic-fee simulation
  transactions, reject mixed legacy/dynamic fee arguments, and expose the
  base-fee-capped effective gas price to the `GASPRICE` opcode.
  Explicit call-object `chainId` values are validated against the configured
  chain before retained-state simulation runs. Explicit call-object `nonce`
  values are now honored by retained-state simulation transactions, including
  contract-creation address derivation without committing created code. When
  both calldata compatibility fields are present, `input` now takes precedence
  over `data` for retained-state simulations.
  Retained-state simulations also use call-style fee handling rather than
  live-transaction EIP-1559 fee-cap checks, so below-base-fee `gasPrice` and
  partial dynamic-fee call objects can still execute for local simulation.
  When the resulting call gas price is zero, the simulation EVM context lowers
  base fee to zero, matching geth `applyMessage` behavior for `BASEFEE`.
  Omitted gas on retained-state `eth_call` / `eth_createAccessList` now uses a
  call-style uint64 RPC gas cap instead of the selected block gas limit,
  matching geth `CallDefaults` gas-pool behavior while keeping explicit gas
  and `eth_estimateGas` caps unchanged.
  `eth_createAccessList` can turn retained-state call access tracking into
  geth-shaped access-list and gas-used results. Retained-state RPC block
  selectors now also accept EIP-1898-style `blockHash` /
  `blockNumber` objects, including `requireCanonical` rejection for side-chain
  hashes, so hash-pinned side-chain state can be read and simulated without
  changing canonical indexes. Signed block import,
  Engine payload import, transaction admission, and mined transaction RPC
  objects require real sender recovery rather than zero-address fallbacks. The
  in-memory Engine import path is atomic for state DB plus block, receipt,
  transaction, account, pending/filter, blob sidecar, prepared payload,
  forkchoice checkpoint, and invalid-payload cache indexes. Forkchoice
  checkpoint publication and canonical-head rewrite now share the same atomic
  commit boundary, so failed head rewrites do not leak partial head/safe/
  finalized checkpoint changes.
- **Partial:** txpool admission, concrete HTTP/socket serving, production
  persistence, and cross-client process-level fixture breadth beyond the
  current bounded Engine import path. Retained-state nonce-gap
  `eth_sendRawTransaction` submissions now route into the queued txpool view
  instead of pending and promote into pending when the gap closes, including
  after canonical-head updates advance retained sender nonces. Base-fee
  ineligible submissions now route into the basefee txpool view, and bumped
  same-sender/same-nonce replacements can move them into pending without
  leaving duplicate subpool entries behind; canonical-head updates also
  promote basefee entries that become eligible after a base-fee drop. Pending
  nonce RPCs count only the contiguous pending subpool span, so queued gaps and
  basefee-ineligible entries do not consume account nonces before promotion.
  Retained-balance admission now checks same-sender pending expenditure
  cumulatively, so new submissions cannot overdraft an account by ignoring
  already-pending transaction costs. When retained state is available, a
  missing sender balance entry is treated as the known zero balance rather
  than as unknown state, so absent senders cannot bypass txpool funding checks.
  Txpool admission now also rejects raw transactions whose gas limit exceeds
  the current head block gas limit, and canonical-head updates drop already
  pooled pending/queued/basefee/blob entries that exceed the new head gas
  limit before promotion or hash lookup can expose them again.
  Canonical-head updates prune stale txpool entries below the new retained
  sender nonce before promotion, so transactions made obsolete by another
  canonical branch disappear from txpool and hash lookups.
  Basefee subpool promotion now respects the pending-contiguous nonce boundary,
  so a base-fee drop cannot make nonce-gap transactions executable until the
  missing nonce is pending or retained state advances.
  Queued/basefee promotion also rechecks retained sender balance against
  cumulative pending expenditure, so transactions that were individually
  admissible while parked cannot overdraw the pending set after promotion.
  Canonical-head updates now revalidate pending transactions against the new
  retained base fee and sender balance before promotion, demoting
  non-executable pending entries so public pending views expose only the
  executable contiguous prefix.
  Nonce-gap routing now compares submissions against that pending-contiguous
  nonce, so follow-on same-sender transactions remain pending once earlier
  nonces are already pending. Blob transactions that pass Cancun/type/sender
  admission now route into the blob subpool, remain counted by
  `txpool_status`, and remain visible through hash lookup without pending-filter
  notification. `txpool_content`, `txpool_contentFrom`, and `txpool_inspect`
  now expose queued/basefee/blob queued-view entries from sender/nonce indexes
  instead of rebuilding sender groupings from concatenated subpool lists. Real
  sidecar/KZG-backed executable blob promotion remains outside the Shanghai
  Phase A gate. A standalone
  `scripts/devnet-smoke-gate.lisp` now exercises the local split
  Engine/public listener boundary with authenticated payload import,
  forkchoice, public retained-state reads, and ready/shutdown telemetry for
  both serving-style smoke runs and one-shot no-serve CLI runs. The development
  key-value
  database now has a stable chain-record namespace for block/header/receipt,
  canonical-hash, checkpoint, state, and transaction-location records, giving
  the future chain-store persistence backend ordered keys for canonical-height
  iteration, typed canonical-hash/checkpoint helpers, and batch helpers for
  atomic multi-record commits. The in-memory chain-store can now export its
  canonical number-to-hash indexes and head/safe/finalized checkpoints into
  that KV substrate while deleting stale canonical heights after reorg, and it
  can export known block/header/receipt records while preserving side-chain
  block records by hash. Canonical transaction-location indexes can also be
  exported to KV with stale entries deleted after reorg, and state-available
  account snapshots can be exported as block-hash keyed state records. A
  combined chain-store export path now writes those readable chain records
  through one KV batch, so encoding failures do not leave half-persisted
  indexes in the development store. The in-memory chain-store can now prune
  retained state snapshots before a block-number boundary while always
  preserving the current head retained state and preserving
  block/header/receipt, canonical-index, and transaction-location records; the
  next KV export deletes the corresponding historical state records instead of
  reviving pruned history. The same readable chain view can be
  restored from KV into a fresh memory store for local block, transaction, and
  retained-state reads, including decoded typed receipt records for restored
  block-receipt and transaction-receipt RPC visibility. KV import now stages
  and validates the restored readable tables before publishing them, including
  header namespace consistency, receipt roots, retained-state snapshot roots,
  retained-window canonical parent links, canonical transaction-location
  blocks and receipts, persisted forkchoice checkpoint ancestry/order, and
  head checkpoint state plus canonical-head alignment, so a malformed record
  does not clear or partially replace an existing in-memory chain-store view.
  The devnet CLI can now wire that development
  persistence path through `--database PATH`, restoring existing KV chain-store
  snapshots at startup, optionally pruning retained state before a configured
  block number on export, and exporting the current readable chain view on
  `--no-serve` or normal shutdown. Empty existing database files are treated as
  new stores, so first-run devnet startup preserves and exports the loaded
  genesis state instead of publishing an empty readable chain. Database startup
  also rejects snapshots whose persisted canonical genesis block conflicts
  with the supplied genesis file, while pruned retained-window snapshots
  without block 0 remain restorable. The standalone
  devnet smoke gate can now
  pass the same pruning boundary through its database export/restore check and
  verify a covered safe/finalized state snapshot is absent while the block and
  checkpoint records still restore. The same restored public RPC smoke now
  asserts that balance, nonce, code, storage, proof, call, estimate-gas, and
  access-list requests against the pruned checkpoint return the existing
  "state is not available" JSON-RPC errors, not default head state.
- **Current Phase A smoke gate:** `scripts/phase-a-smoke-gate.lisp` now fails
  unless the in-repo Phase A fixture root has selector-gated state,
  transaction, and blockchain replay coverage, including both `blockRlp` and
  `engineNewPayloadV2`. Its `--pinned-v5.4.0` mode validates the official
  stable archive's pinned Shanghai blockchain replay table while explicitly
  reporting that the archive lacks `state_tests` / `transaction_tests` suites;
  `--root PATH` makes the fixture root explicit for CI and automation.
  The gate now executes the selected state-test cases, transaction vectors,
  and blockchain replay imports rather than only reporting selector counts,
  and its text/JSON output records per-suite execution counts plus aggregate
  fixture/total case and executed counts. Its `--devnet` mode now runs the
  standalone devnet all-fixtures listener-boundary suite with per-case
  readiness JSON, `devnet.ready` / `devnet.shutdown` telemetry logs, and
  file-backed KV database export/restore enabled for every pinned Shanghai
  case, including the multi-transaction legacy-transfer payload. Restored KV
  snapshots are also served through a fresh public RPC
  listener and checked for `eth_blockNumber` plus retained-state balance,
  nonce, code, storage, and proof reads, EIP-1898 canonical `blockHash`
  balance reads with and without `requireCanonical`,
  `eth_getTransactionReceipt` canonical receipt lookup,
  `eth_getBlockByHash` / `eth_getBlockByNumber` canonical block lookup,
  block transaction counts, raw transaction by block/index,
  `eth_getTransactionByHash` and transaction by block/index canonical
  transaction lookup, safe/finalized checkpoint number/hash persistence plus
  `eth_getBlockByNumber("safe"|"finalized")` checkpoint-tag reads, and
  `eth_getBlockReceipts` block-receipt lookup. The same database-backed gate
  now also prepares an Engine payload through authenticated
  `engine_forkchoiceUpdatedV2`, exports it, restores the database into a fresh
  node, and verifies `engine_getPayloadV2` can read the prepared payload by id.
  It also submits an orphan `engine_newPayloadV2` through the authenticated
  Engine boundary and verifies the resulting `SYNCING` remote-block cache
  survives KV export/import into a fresh node. Known-parent invalid payloads
  now also populate the invalid-tipset cache through the same Engine boundary,
  and restored nodes reject descendants as linking to the previously rejected
  block. The database-backed gate also submits signed pending,
  basefee-ineligible, and nonce-gap queued transactions through public
  `eth_sendRawTransaction`, exports them with the KV snapshot, and verifies
  restored public txpool views (`eth_pendingTransactions`, `txpool_status`,
  `txpool_content`, `txpool_contentFrom`, and `eth_getRawTransactionByHash`)
  still expose the same pending and queued-view subpool contents. The same
  restored database gate now imports an executed empty sibling through
  authenticated Engine RPC, switches forkchoice to that sibling, verifies
  public canonical transaction/receipt lookups plus latest block-receipt and
  log queries follow the side head while the old child block remains
  hash-readable, rejects a non-ancestor `safe` checkpoint update before the
  valid switch, re-exports the database, and checks a fresh node restores the
  sibling as canonical head.
  Restored executable-code cases also probe an under-gassed `eth_call` and
  assert the public RPC reports the retained non-revert execution failure as a
  JSON-RPC error.
  Multi-transaction restored blocks verify all declared recipient balances plus
  every transaction's receipt, raw transaction, and block/index lookup. The
  top-level Phase A process gate therefore covers authenticated Engine import,
  forkchoice, public reads, runner readiness/shutdown signals, and readable
  chain-store persistence across the local process/database boundary. The
  standalone devnet gate can also export a pruned database snapshot and assert
  that covered safe/finalized state has been removed without losing the
  checkpoint block or head-state RPC readability, while retained-state reads
  and simulations against the pruned checkpoint fail with the explicit
  retained-state unavailable errors. The outer Phase A `--devnet` gate now
  runs that pruning contract across the pinned Shanghai all-fixtures set,
  reports covered pruned cases and pruned-error cases, and distinguishes
  fixtures whose checkpoint state is not covered by the selected pruning
  boundary.
- **Next checkpoint:** keep the current bounded Shanghai smoke gate stable and
  widen only through explicit upstream/pinned synchronization slices or
  concrete cross-client drift. The selected
  EEST-style trie subset now gates both valueless root-branch child deletion
  outcomes for both plain and secure replay: two-child delete collapse to a
  leaf and three-child delete preservation of the branch root. It also gates
  plain and secure
  extension-subtree child deletion that compresses all the way back to a
  single leaf, covering the path-compression boundary beyond root-branch cases
  for both raw and hashed-key replay. It also gates present sibling deletion
  that compresses a branch back to an extension root for both raw and
  hashed-key replay. The trie fixture gate now also includes a branch-root
  case whose populated child resolves to an extension, locking child-shape
  projections alongside embedded-vs-hashed child references before pinned
  trie vectors replace the seed set. The selected EEST-style trie subset
  now also gates a branch-root case whose populated child resolves to another
  branch, so nested branch child-shape projection is locked alongside the
  extension-child path before pinned trie vectors replace the seed set. The
  selected EEST-style trie subset
  now gates the same nested branch-child shape under secure-key hashing,
  keeping account/state-trie-like replay aligned with the plain seed shape.
  It also gates the secure-key counterpart for a branch root whose child
  resolves to an extension, so both nested branch and nested extension child
  shapes are represented before pinned trie vectors replace the seed set.
  The geth-derived secure account-RLP trie coverage now also locks the first
  proof node for the three-account branch-root case against geth's root-node
  RLP, adding direct proof encoding coverage on top of the secure account root
  hashes. Secure-key branch-root fixtures with nested branch and extension
  children now also pin exact present and missing proof-node RLP prefixes, so
  hashed-key proof encoding is checked across root-only misses and multi-node
  present paths.
  Geth-derived account-RLP state-root coverage now also gates the one-account
  leaf and two-account branch transitions before the final three-account
  branch root, keeping secure account-root evolution covered across the same
  reference sequence.
  The seed trie fixture now also locks deterministic `mpt-entry-pairs` export
  order and values for the one-, two-, and three-account geth TinyTrie
  progression on both plain and secure-key replay paths.
  The same geth TinyTrie account progression now pins exact present and
  missing proof-node RLPs for every plain and secure-key step, so account-trie
  proof encoding is locked alongside the root and entry-order checks. The
  selected EEST-style path now also carries explicit `out` maps for every
  plain and secure geth TinyTrie account step, so present/missing
  lookup/proof replay covers the leaf, branch-transition, and final
  three-account roots on the external adapter path.
  The same account-RLP coverage now extends to five geth-derived accounts on
  both plain TinyTrie and secure-key paths, pinning wider root, proof-node RLP,
  entry-export order, and explicit output-map replay beyond the original
  three-step sequence. Those five-account seed cases now also assert bounded
  and open-ended half-open `mpt-entry-range` iteration for both raw-key and
  secure hashed-key account tries. The selected EEST-style plain and secure
  five-account account cases now carry explicit fixture-provided range maps
  and gate them through the adapter, so external-style replay checks the same
  half-open iterator semantics as the seed vectors.
  Selected geth StackTrie table cases now also carry fixture-provided
  intermediate roots through the EEST-style adapter, and the Phase A gate
  requires all 69 post-insert roots from 21 StackTrie growth/divergence cases
  to match the seed references rather than checking only final roots.
  Selected EEST-style trie roots now also carry fixture-provided proof-node
  RLP assertions for 17 geth/secure cases, using exact-length or prefix
  comparison against `mpt-get-proof`, so external-style replay gates proof
  encoding rather than only root, lookup, and range behavior.
  The same selected plain and secure account progression roots now also
  carry fixture-provided entry-pair export assertions, comparing
  `mpt-entry-pairs` keys and values in exact order across 8 cases and 22
  entries, so the external adapter pins deterministic snapshot export data
  rather than only rebuilding from derived entries.
  The Phase A EEST trie coverage gate is now table-driven: one centralized
  reference gate list feeds the generic validators for required modes,
  explicit output maps, intermediate roots, entry-pair exports, proof nodes,
  and ranges, matching the reference-client pattern of fixture tables plus
  shared runners instead of scattered one-off validation calls. The same
  harness direction now covers blockchain fixture roots: discovered
  `blockchain_tests_engine` JSON files can be loaded into source-style named
  cases, selected by name, and reported with basic metadata before the next
  slice materializes a bounded pinned Shanghai blockchain case into the Engine
  import fixture path.
  The selected EEST-style trie subset now includes geth `TestEmptyValues`,
  proving that empty string updates delete existing keys and land on the same
  reference root as the explicit delete sequence while still exercising the
  branch-preserving delete path. It now also includes geth `TestReplication`,
  adding a long-key multi-leaf branch-root replay that locks
  `0x09c889feaafd53779755259beaa0ff41c32512c8cac45152af46fae7ebdef210`
  against geth reference commit `8a0223e`. That replay is now also present in
  the seed trie vector fixture with lookup/missing checks, root branch child
  projections, and a geth-derived proof-node RLP prefix for a retained key.
  The selected subset now also carries geth's fixed `TestRandomCases` fuzz
  regression, locking repeated
  hex-key overwrite, missing-delete, and short-key deletion replay to
  `0x380d56237a963e2c17a7c282142dc0b85d3236cd515d4f0348c787e70a68d24c`.
  That regression is now also present in the seed trie vector fixture with
  lookup/missing checks, root branch child projections, and a geth-derived
  proof-node RLP prefix for a retained hex key. The geth `TestLargeValue`
  boundary is now represented too, locking the `key1` / `key2` trie with a
  32-byte value against
  `0xafebee6cfce72f9d2a7a4f5926ac11f2a79bd75f3a9ae6358a08252ba5dce3be`
  and checking both present-key and missing-key proof-node prefixes in the
  seed fixture. The geth one-element proof boundary is represented as well,
  locking the single leaf proof node for present and missing lookups around
  `k` -> `v`. That one-element boundary now uses exact-length proof-node
  assertions, so a generated proof cannot grow extra nodes while preserving
  the same first RLP node. Proof verification now also rejects a tampered
  referenced node in that geth large-value proof shape, so proof-node hash
  binding is covered directly.
  Geth `TestSecureDelete` is now represented in both the seed trie fixture and
  selected secureTrie subset, locking the secure-key update/delete replay to
  root `0x29b235a58c3c25ab83010c327d5932bcf05324b7d6b1185e650798034783ca9d`
  plus retained/deleted lookups and proof-node RLP prefixes at geth reference
  commit `8a0223e`.
  The same selected EEST-style trie subset now gates object-form empty-value
  deletes on both secure and plain paths, keeping `""` / `"0x"` delete
  semantics covered outside the array-of-pairs adapter path. The importer now
  preserves the exact empty-value source as well, and the Phase A summary
  gates `0x`, string `""`, and object-form string empty-value deletes
  separately. The EEST trie-test adapter now also consumes optional `out`
  final-output maps, and the selected plain and secure subset verifies
  explicit present/missing output keys with trie lookup plus proof
  verification after root replay; those maps must cover every replay-derived
  final present key, with `null` entries reserved for extra missing-key
  assertions. That explicit final-output gate now also covers object-form
  `in` cases on both plain and secure replay, including present and missing
  key assertions, so imported Nethermind/geth-style object-form fixtures cannot
  bypass fixture-provided lookup expectations. Object-form trie-test inputs
  now also replay all key/value entry permutations, matching Nethermind's
  unordered `trieanyorder` treatment before broader pinned trie imports are
  enabled. The
  selected secure trie subset now also
  gates duplicate-key
  overwrites, so secure-key replay keeps the StateTrie-like final-write-wins
  boundary distinct from plain trie overwrite coverage. State-root fixtures now
  also cover storage write-then-zero deletion inside multi-account branch,
  extension, and branch-with-extension-child state roots, asserting the touched
  account's storage trie returns to empty while sibling account projections,
  path-compressed root nibbles, and state child references remain stable.
  Value-transfer state-root coverage now also locks transfers between
  accounts that already carry code and storage, so balance-only movement must
  preserve both accounts' code hashes, storage roots, and branch-shaped
  account-trie references.
  The public proof path now reuses the shared chain-store snapshot
  reconstruction helper, and chain-store roundtrip coverage asserts that a
  nontrivial value-transfer state reconstructs to the original state root.
  Chain-store account iteration now also sorts discovered account addresses
  and storage slots, keeping retained-state replay callbacks deterministic in
  the same way as direct state DB export.
  The selected Phase A transaction subset
  now gates access-list and dynamic-fee contract creation alongside legacy
  creation, including derived `contractAddress` checks from sender/nonce, so
  typed sender recovery, access-list projection, and `to = null` decoding are
  represented before pinned transaction-test replacement. It also gates a
  dynamic-fee transaction with a non-empty access list, keeping EIP-1559
  access-list intrinsic-gas and decoded projection coverage distinct from the
  EIP-2930-only access-list path. The subset now also gates the combined
  EIP-1559 dynamic-fee access-list contract-creation path, including
  non-empty access-list projection, `to = null`, initcode, and derived
  contract-address checks in one vector. It also gates a typed EIP-2930
  empty-access-list contract creation vector, so type-1 `to = null` and
  initcode coverage now covers both empty and non-empty access-list payloads,
  with selector summary gates for typed, EIP-2930, and dynamic-fee empty-list
  creation combinations. The EIP-1559 empty-access-list contract-creation
  boundary now has its own seed and EEST-shaped sample vector too, locking
  dynamic-fee `to = null` replay, derived contract address, and sparse
  Shanghai result expansion separately from the non-empty access-list creation
  case.
  It also gates a typed EIP-2930
  message-call with non-empty calldata, and the summary gate now requires that
  access-list calldata count explicitly so typed `input` decoding and calldata
  intrinsic gas are covered separately from legacy and EIP-1559 calldata. The same
  gate now also requires legacy calldata count explicitly, so the selected
  Shanghai subset keeps legacy, EIP-2930, and EIP-1559 calldata message-call
  paths distinct before pinned transaction-test replacement. The legacy
  calldata path now includes both unprotected and EIP-155 protected message
  calls, keeping protected sender recovery and non-empty input intrinsic gas
  covered together. Legacy contract-creation coverage now also includes an
  unprotected signature, so pre-EIP-155 sender recovery, `to = null`, initcode
  gas, and derived contract-address checks are covered together. It now also gates
  EIP-2930 and EIP-1559 access-list transactions that carry non-empty calldata,
  so access-list warming costs and calldata intrinsic-gas costs are exercised
  together instead of only as separate fixture paths. It also gates an
  EIP-2930 duplicate access-list message-call so duplicate address and storage
  key entries remain charged and projected as source order occurrences rather
  than collapsed sets. It now gates the same duplicate access-list boundary on
  an EIP-1559 dynamic-fee message-call, so dynamic-fee access-list projection
  and intrinsic-gas accounting cannot rely on the EIP-2930-only vector. It
  also gates an EIP-2930 address-only access-list message-call with no storage
  keys, keeping address warming cost visible separately from storage-key
  warming cost. The selected Shanghai subset now also gates the same
  address-only access-list boundary on an EIP-1559 dynamic-fee transaction, so
  dynamic-fee address warming cannot rely on the EIP-2930-only vector. The
  transaction fixture summaries now also distinguish
  typed empty-access-list payloads from non-empty access-list payloads, with
  explicit EIP-2930 and EIP-1559 empty-list gates. The calldata summary now
  also gates typed empty-access-list message calls for both EIP-2930 and
  EIP-1559, keeping empty-list `input` decoding distinct from non-empty
  access-list calldata paths. It also gates an EIP-1559
  dynamic-fee message-call with equal priority and max fee caps, locking the
  fee-market decoded-field
  boundary where `maxPriorityFeePerGas == maxFeePerGas` remains valid. The
  full EEST transaction selector now also gates EIP-4844
  `blobVersionedHashes` payloads, including a blob transaction that combines
  non-empty calldata with a non-empty access list, and EIP-7702
  `authorizationList` payloads, including a set-code transaction that combines
  multi-authorization, non-empty calldata, and a non-empty access list, so
  those post-Shanghai typed families cannot degrade to type-only coverage
  before pinned transaction-test replacement.
  The local envelope fixture entry point now applies those payload gates too,
  with blob coverage requiring access-list calldata and set-code coverage
  requiring multi-authorization plus access-list calldata rather than a single
  authorization-only placeholder. The in-repo EEST transaction-test root now
  also includes the full pinned v5.4.0 Prague/EIP-7702 invalid
  `eip7702_set_code_tx` group currently present in the local
  `fixtures_stable.tar.gz` archive: 12 source files and 53 invalid cases. The
  importer keeps invalid-only cases separate from successful hash/sender
  vectors while still decoding official payloads and gating the expected
  empty-authorization, invalid-authority-signature, and
  invalid-authorization-format exception distribution. Those invalid payloads
  now also replay through local transaction rejection paths: scalar RLP
  decoding, set-code field validation, and authorization-signature preflight
  together reject all 53 official invalid cases with no accepted payloads. That
  replay also locks the exact exception-to-rejection-stage distribution for the
  official invalid cases, so decode, set-code field, and signature-preflight
  regressions are distinguishable. The invalid transaction summary also locks
  per-source-file counts for all 12 transcribed v5.4.0 files plus each file's
  local rejection-stage distribution, so fixture-file omissions and
  source-local rejection-path drift cannot hide behind aggregate rejection
  totals. The same transaction fixture path now also includes a valid EIP-2930
  type-1 transaction payload transcribed from pinned v5.4.0
  `blockchain_tests_engine/berlin/eip2930_access_list/test_eip2930_tx_validity.json`,
  because the stable release's `transaction_tests` set only exposes invalid
  Prague cases; the seed-alignment gate locks its txbytes, hash, recovered
  sender, decoded fields, signature, intrinsic gas, and Berlin-through-Prague
  validity. It now also includes a valid EIP-1559 type-2 transaction payload
  transcribed from pinned v5.4.0
  `blockchain_tests_engine/london/eip1559_fee_market_change/test_eip1559_tx_validity.json`,
  locking dynamic-fee decoding, signature, sender/hash recovery, intrinsic
  gas, empty access-list projection, and London-through-Prague validity with
  pre-London typed-transaction rejections. It now also includes a valid
  unprotected legacy transaction payload transcribed from pinned v5.4.0
  `blockchain_tests_engine/frontier/validation/test_tx_nonce.json`, locking
  nonce/gas decoding, signature, sender/hash recovery, intrinsic gas,
  unprotected-signature classification, and all tracked-fork validity. It now
  includes a valid EIP-4844 blob transaction payload transcribed from pinned
  v5.4.0
  `blockchain_tests_engine/cancun/eip4844_blobs/test_valid_blob_tx_combinations.json`,
  locking blob fee decoding, versioned hash payloads, signature, sender/hash
  recovery, intrinsic gas, empty access-list projection, Cancun/Prague
  validity, and pre-Cancun typed-transaction rejections. Seed, Phase A, and
  full EEST-style transaction selectors now explicitly gate those transcribed
  pinned valid families, while the pinned EIP-7702 invalid group gates the
  set-code transaction-test side of the stable archive. Fixture root discovery
  now also covers `blockchain_tests_engine` and generic `blockchain_tests`
  layouts for both direct execution-spec-tests stable archive roots and
  geth-style `spec-tests/fixtures` checkouts, preferring the Engine layout
  that feeds the Phase A `engine_newPayloadV2` smoke path. Shared fixture JSON
  enumeration now reports source-relative names for trie, transaction, and
  blockchain roots and rejects empty blockchain roots before selector work can
  silently pass. The
  Shanghai
  `engine_newPayloadV2` smoke now
  covers legacy transfer, access-list
  transfer, dynamic-fee typed transfer, contract creation, withdrawals,
  multi-transaction receipt ordering/cumulative gas, safe/finalized checkpoint
  tags, and
  two-branch canonical switching, with canonical `eth_getProof` replay and
  verification over the imported child state root plus branch-switch proof
  reads that distinguish canonical `latest` from hash-addressed non-canonical
  child state. The same smoke path now exercises retained storage proofs and
  checkpoint-tag proof reads, verifying `latest` proofs against the child
  state root while `safe` and `finalized` proofs resolve to the retained
  parent state root; remaining Engine fixture work is mainly pinned-fixture
  breadth rather than new smoke-path shape. The state-root seed set now also
  locks storage overwrite-to-zero pruning plus storage-trie branch- and
  extension-preserving delete boundaries: after an overwritten slot is written
  back to zero, the funded account must retain an empty storage root/trie, and
  after a three-slot secure storage trie deletes one present child, retained
  hashed child references, compressed paths, account RLPs, storage roots, and
  final state roots must still match the two-slot non-collapsed outcomes. The
  retained-state proof path now also locks that overwrite-then-zero boundary as
  a geth-shaped `eth_getProof` response with an empty storage hash and null
  missing-slot proof for the pruned slot. It also locks branch- and
  extension-shaped storage-trie update proofs where one slot changes while
  sibling and missing-slot proofs remain valid against the updated storage
  root.
  Code-update and code-delete state-root fixtures now also cover branch-root,
  extension-root, and branch-with-extension-child account tries, asserting the
  updated or cleared code hash, retained sibling account projection, and
  non-leaf state-trie shape/reference invariants. Non-leaf `clearAccount`
  fixtures also prune accounts carrying both code and storage, locking
  branch/extension collapse outcomes and the branch-with-extension-child
  compression back to an extension root. Zero-amount `addBalance` no-op
  coverage now spans empty, leaf/funded, branch, extension, and
  branch-with-extension account-trie layouts, so missing reward/withdrawal
  targets cannot create empty accounts while preserving compressed paths and
  child-reference projections. The same zero-add no-op coverage now also locks
  existing-account branch, extension, and branch-with-extension layouts, so
  zero credits preserve balances and account RLPs in non-leaf state tries.
  State-proof fixtures and retained-state `eth_getProof` now cover both
  missing-account and existing-account non-leaf zero-add boundaries, including
  proof output against the unchanged roots. State-proof fixture requests now
  also accept short storage keys such as `0x1` and normalize them before proof
  lookup while keeping expected proof output canonical.

The long status paragraphs below preserve current implementation history. New
large status updates should either replace them with concise Done/Partial/Missing
summaries or move detailed history into a separate status document.

## 0. Project Substrate

- ASDF systems and packages
- byte-vector, hex, and integer utilities
- RLP encoder/decoder
- test runner and fixture layout
- reference-source map

**Phase A summary**

- *Done:* ASDF/source-loadable project structure, package layout, byte-vector,
  hex, quantity, address, hash32, uint256 helpers, canonical RLP
  encoder/decoder with non-canonical rejection tests, self-contained test
  runner, fixture layout, and reference-source map.
- *Partial:* broader CI matrix and packaging ergonomics beyond the current
  local SBCL runner.
- *Missing for Phase A:* no substrate blocker; keep new tooling work scoped to
  supporting the Phase A smoke path.
- *Next:* keep tactical automation pointed at `docs/tasks.md` and preserve
  reference-client commit pins for parity claims.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 0: Project Substrate".

## 1. Cryptographic Primitives

- Keccak-256 with Ethereum padding
- secp256k1 public-key recovery and signature verification
- address derivation
- Bloom filter primitives
- versioned-hash helpers for blob transactions

Validation targets: geth `crypto`, Nethermind `Nethermind.Crypto` and
`Nethermind.Core/Crypto`, and Reth/Rust primitive/KZG integration points.

**Phase A summary**

- *Done:* Keccak-256, SHA-256, RIPEMD-160, bloom primitives,
  secp256k1 public-key/address recovery, transaction signature verification,
  low-`s` sender-recovery helper, and EIP-4844 commitment versioned-hash
  helpers.
- *Partial:* KZG proof verification remains a stubbed boundary; callers that
  require trusted-setup-backed proof verification fail explicitly.
- *Missing for Phase A:* none for Shanghai. Real KZG verification only blocks
  Phase A if Cancun blob execution is admitted into the gate.
- *Next:* wire a trusted KZG backend before treating Cancun blob payloads as
  executable consensus cases.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 1: Cryptographic Primitives".

## 2. Consensus Data Types

- `address`, `hash32`, `quantity`, `account`
- legacy, access-list, dynamic-fee, blob, set-code transaction envelopes
- withdrawals, logs, receipts, headers, blocks
- canonical RLP for all pre-SSZ execution payload structures
- transaction sender recovery

Validation targets: geth `core/types`, Nethermind `Nethermind.Core`, and
Reth/Rust primitive transaction and block types.

**Phase A summary**

- *Done:* accounts, legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702
  transaction envelope encoding/hashing, legacy protected/unprotected signing
  hashes, typed transaction sender recovery, EIP-7702 authorization authority
  recovery, withdrawals, logs, receipts, headers, block body roots, and
  fixture-backed transaction vector replay through the Shanghai Phase A set.
- *Partial:* EIP-4844 blob sidecars and EIP-7702 set-code structures are
  shape-checked beyond Shanghai, but full blob proof verification and later
  fork execution semantics remain outside the Phase A gate.
- *Missing for Phase A:* no consensus data-type blocker for the Shanghai
  smoke path.
- *Next:* keep later-fork transaction families fixture-backed but outside
  Phase A until their execution semantics enter scope.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 2: Consensus Data Types".

## 3. Merkle Patricia Trie and State

- hex-prefix nibble encoding
- branch, extension, leaf nodes
- secure trie key hashing
- account and storage trie roots
- proofs and proof verification
- journaled state overlay for transaction execution

Validation targets: geth `trie` and `core/state`, Nethermind `Nethermind.Trie`
and `Nethermind.State`, and Reth trie/provider boundaries.

**Phase A summary**

- *Done:* fixture-grade in-memory MPT root/proof generation, secure key
  hashing, state/account/storage roots, state snapshot copy/restore,
  deterministic account/storage export and range iteration, retained-state
  account/storage proof generation, `eth_getProof` retained snapshot replay,
  geth/Nethermind-guided trie proof vectors, and pinned reference proof output
  coverage needed by the current Shanghai smoke path.
- *Partial:* broader external state-root fixture breadth and production
  storage/trie persistence remain later slices.
- *Missing for Phase A:* no narrow trie/proof hardening item should block the
  current Phase A gate unless a concrete implementation bug, missing
  consensus boundary, or reference-client drift is found.
- *Next:* only reopen this area for a real upstream/pinned EEST
  synchronization slice or a specific consensus bug.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 3: Merkle Patricia Trie and State".

## 4. EVM

- stack, memory, gas accounting, execution frames
- opcode table by fork
- arithmetic, bitwise, environmental, memory, storage, flow, call, create, log
- refunds and warm/cold access rules
- precompiles
- EOF support when required by activated forks

EOF planning gate: EOF is not part of the Phase A Shanghai smoke path and is
not enabled by the currently modeled Cancun, Prague, Osaka, or Amsterdam
surface. Before implementation starts, add an explicit chain-rule activation
flag for the first fork this client chooses to support with EOF, then land the
work in this order: EOF container parser/version gate, deployment validation,
legacy-vs-EOF code dispatch, EOF-specific instruction/control-flow validation,
and finally execution semantics with fixture-backed state tests. Until that
activation flag exists, EOF-formatted code remains out of consensus scope
beyond the existing legacy `0xef` runtime-code rejection behavior.

Validation targets: geth `core/vm`, Nethermind `Nethermind.Evm`, and Reth/revm
behavior.

**Phase A summary**

- *Done:* a broad interpreter skeleton with stack/memory/gas accounting,
  fork-gated opcode coverage, warm/cold access tracking, CALL-family frame
  rollback, CREATE/CREATE2 basics, SELFDESTRUCT, logs, returndata, transient
  storage, and precompile coverage through the current Phase A smoke needs.
  BN254 pairing now uses a native optimal Ate check against the full geth
  `bn256Pairing.json` vector set, with G2 subgroup validation before backend
  dispatch. The EEST-style state-test replay now maps
  `TransactionException.INTRINSIC_GAS_TOO_LOW` to local transaction validation
  errors and checks the exact expected-exception reason instead of accepting
  any failed execution.
- *Partial:* fixture-backed CALL/CREATE/precompile breadth, exact gas parity
  for all edge cases, EIP-7702 delegated-code execution beyond the covered
  paths, and KZG proof verification.
- *Missing for Phase A:* broader pinned execution-spec state-transition replay
  beyond the current selector-gated replay (London
  legacy/access-list/dynamic-fee vectors, broader expected-exception token
  coverage beyond the mapped intrinsic-gas token, Shanghai PUSH0 replay, and
  optional-root discovery workflow); real KZG
  point-evaluation verification before Cancun blob execution can enter the
  Phase A gate, and any EOF support until an explicit activated-fork rule is
  chosen.
- *Next:* keep Shanghai smoke execution stable; only widen EVM fixture breadth
  through pinned state-transition imports or concrete cross-client drift.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 4: EVM".

## 5. Block Execution

- fork schedule and chain configuration
- transaction validation
- base-fee, blob-gas, withdrawals, requests, and system calls
- block reward behavior for historical forks
- receipt and logs bloom generation
- post-state root validation

Validation targets: geth `core`, Nethermind `Nethermind.Consensus`, and
Reth consensus/executor integration.

**Phase A summary**

- *Done:* legacy and typed transaction execution shape through Shanghai,
  in-memory receipt / log / state-root derivation, retained-state account and
  storage proof generation, receipt-derivation invariants on the import path,
  block-body and post-execution commitment preflight, atomic block-import
  commit/rollback, strict sender recovery on signed import/admission paths,
  Ethash reward hook, Merge/Paris validation, and in-repo EEST-shaped
  blockchain replay for empty Engine payloads, standard block RLP, and a
  non-empty Shanghai Engine transfer payload.
- *Partial:* EIP-7702 set-code execution beyond delegation shape, blob
  transaction semantics without KZG verification, and broader post-execution
  rollback symmetry across all failure modes.
- *Missing for Phase A:* broader official pinned post-Merge Shanghai
  state-transition fixture breadth beyond the bounded in-repo replay gate,
  plus Cancun blob execution acceptance once real KZG verification is
  available.
- *Next:* drive any additional block-execution widening through bounded pinned
  fixtures rather than local one-off cases.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 5: Block Execution".

## 6. Persistence and Sync-Facing Interfaces

- pluggable key-value database: first-pass protocol and in-memory backend are
  present, covering byte-vector put/get/delete, ordered write batches, and
  sorted range iteration; a simple S-expression file-backed development
  backend now persists records across process restarts and replaces target
  files through same-directory temporary writes
- freezer/history abstractions: immutable finalized bodies, receipts,
  transaction lookup records, and historical header/body payload bytes should
  move to append-only/static files once finalized beyond the retention window;
  mutable forkchoice checkpoints, canonical number-to-hash indexes, txpool
  contents, recent state snapshots, trie node caches, and invalid-tipset caches
  remain in the key-value database
- canonical chain indexes
- snapshot/trie node access APIs
- import/export test fixtures

This does not need to become a high-performance production database in the
first pass, but interfaces must not block that path.

**Phase A summary**

- *Done:* memory key-value store, file-backed development store, canonical
  number/hash indexes, typed head/safe/finalized checkpoints, retained block,
  receipt, transaction, account, storage, txpool contents, pending/filter,
  blob sidecar, prepared payload, remote-block, and invalid-payload cache
  indexes needed by the in-memory Phase A smoke path,
  plus explicit retained-state snapshot pruning before a block-number boundary
  and devnet CLI restore/export/pruned-export wiring for file-backed KV
  chain-store snapshots. The process/database smoke gate now covers restored
  pending txpool visibility through public RPC, not only lower-level KV
  import/export helpers.
- *Partial:* production database layout, freezer/history retention, pruning
  modes, fuller sync-stage persistence, and durable trie-node storage remain
  later work.
- *Missing for Phase A:* no storage abstraction blocker for the in-memory
  Shanghai smoke path.
- *Next:* define retention/pruning contracts before enabling historical-data
  deletion or network sync.

## 7. Engine API and JSON-RPC

- Engine API payload validation/execution
- `eth_*` read RPC
- transaction submission and pool placeholder
- tracing/debug APIs after EVM is mature

**Phase A summary**

- *Done:* Engine payload object conversion, version-gated
  `engine_newPayloadV1` through `V5` parsing, executable known-parent import
  through the atomic signed-block path, forkchoice canonical-head switching,
  public read RPCs over retained state, polling filters, local raw-transaction
  admission, HTTP stream/listener serving, JWT-authenticated and
  namespace-filtered Engine/public service wiring, request/status/error-code
  and payload-status telemetry hooks, and a devnet CLI shell that loads
  genesis, serves both split listeners, atomically emits JSON readiness/head
  summaries and lifecycle telemetry for process runners using actual bound
  listener endpoints in serve mode, maps SIGINT/SIGTERM into coordinated
  split-listener shutdown, can restore/export file-backed KV chain-store
  snapshots through `--database PATH`, and
  has a split-listener smoke covering authenticated Engine JSON-RPC,
  `engine_newPayloadV2` import,
  `engine_forkchoiceUpdatedV2`, unauthenticated public latest-state reads, and
  standalone smoke-gate validation of readiness JSON, ready/shutdown
  telemetry, and file-backed KV chain-store restore/export across the local
  process boundary.
  Readiness files and lifecycle telemetry are now checked for head-state
  consistency: `devnet.ready` reports the pre-import parent head and
  `devnet.shutdown` reports the post-forkchoice imported child head, both with
  explicit process-id and state-availability fields for process runners; the
  standalone devnet smoke gate rejects readiness/log output whose lifecycle
  `processId` fields are missing or inconsistent. The CLI also supports a
  Hive-style `--pid-file PATH`, reports `pidFilePath` in summaries and
  telemetry, and the standalone plus Phase A devnet smoke gates verify the
  pid-file process id against readiness/log metadata. The top-level Phase A
  `--devnet` gate also validates the child report's ready/log/pid/database
  artifact paths and per-case counts before accepting the devnet suite.
  Standalone devnet smoke-gate reports also carry pinned EEST source metadata
  and local reference-client commit/status metadata, and concurrent standalone
  smoke-gate processes use distinct temp files so automation can run parallel
  checks without JWT cleanup races. Public `safe` / `finalized` block-tag
  number resolution requires explicit forkchoice checkpoint publication instead
  of falling back to `latest`, matching the geth/Nethermind checkpoint model.
  The all-fixtures devnet gate now also includes the pinned multi-transaction
  Shanghai legacy-transfer payload and verifies restored RPC visibility for
  every recipient balance and transaction in that block. It also includes a
  log-producing Shanghai contract call whose restored database snapshot is
  checked through receipt logs, block-receipt logs, and `eth_getLogs` by both
  block range and block hash, so the process/database smoke path now covers
  log visibility and bloom-backed receipt persistence instead of only empty-log
  transfers and creations. Restored snapshots now also verify
  `eth_getBlockByHash` and `eth_getBlockByNumber` with full transaction
  objects, so process-boundary checks cover object-form transaction hashes,
  block linkage, and transaction indexes in addition to hash-only block
  responses. The same restored snapshot smoke also exercises
  retained-state simulation RPCs (`eth_call`, `eth_estimateGas`, and
  `eth_createAccessList`) and then re-reads storage to prove simulation calls
  do not commit writes through the restored chain-store view. The direct RPC
  regression suite now also covers retained-state contract-creation
  simulations, fork-specific contract-creation estimate lower bounds, and
  value-bearing retained-state calls without committing sender, recipient, or
  created-contract balance changes. Txpool queued views now expose blob-subpool
  transactions through `txpool_content`, `txpool_contentFrom`, and
  `txpool_inspect` consistently with `txpool_status` queued counts.
- *Partial:* txpool policy beyond the current in-memory pending pool,
  cross-client Engine fixture breadth beyond the local pinned Shanghai
  `engine_newPayloadV2` smoke set, and concrete long-running devnet/Hive
  lifecycle ergonomics beyond the current readiness, log-file, shutdown, and
  bounded fixture-import smoke contract.
- *Missing for Phase A:* broader cross-client Engine payload smoke breadth
  around the existing Shanghai path, plus any Cancun blob execution acceptance
  until real KZG verification is available.
- *Next:* keep Engine/RPC surface frozen except for fixes needed by the
  bounded Shanghai import smoke and future Hive runner contract.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 7: Engine API and JSON-RPC".

## 8. Compatibility Harness

- Ethereum execution-spec-tests fixture runner
- RLP/trie/blockchain fixtures
- cross-check selected fixtures against geth, Nethermind, and Reth/Rust outputs
  where available
- CI entry points for SBCL

**Phase A summary**

- *Done:* fixture root discovery, pinned execution-spec-tests release metadata,
  transaction/trie/state/receipt/Engine fixture runners, real v5.4.0 Shanghai
  blockchain replay selector discovery and pinned replay, and reference-client
  commit recording discipline. The manual `tests/run-tests.lisp` path now also
  loads the CLI package and devnet CLI tests, including a split-listener
  Engine/public payload-import smoke, matching the ASDF test system. A
  scriptable Phase A fixture report now validates and prints, or emits JSON for,
  the selected state/transaction/blockchain ingestion tables for a suite root,
  and it can still validate the pinned v5.4.0 blockchain replay table when the
  stable archive extraction lacks `state_tests` or `transaction_tests` suites.
  Fixture report and smoke-gate outputs also record local geth, Nethermind, and
  optional Reth reference-client commit metadata when those clones are present,
  or explicit missing status when they are absent, so replay reports satisfy
  the reference pinning rule without relying on PR prose. The same metadata
  paths can be overridden with `ETHEREUM_LISP_GETH_ROOT`,
  `ETHEREUM_LISP_NETHERMIND_ROOT`, and `ETHEREUM_LISP_RETH_ROOT`, allowing
  automation to pin external local clones without repository-local checkouts.
  They also expose the pinned `ethereum/execution-spec-tests` source metadata
  at top level: release `v5.4.0`, tag target `88e9fb8`, and
  `fixtures_stable.tar.gz`. In pinned
  mode the fixture report and smoke gate require an explicit suite root or
  `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`, matching the optional fixture
  runner contract while keeping missing pinned fixture configuration
  distinguishable from selector drift. The fixture report also exposes
  `--help` without loading the test system, and the fixture synchronization
  scripts, fixture report, and smoke gate now classify selected-but-empty EEST
  suite roots as configuration errors before selector discovery or replay, so
  partial pinned extractions are not mistaken for selector drift.
  The individual state, transaction, and blockchain selector-listing scripts
  now also emit JSON so selector drift checks can consume structured output
  directly. `scripts/phase-a-smoke-gate.lisp` wraps those selector contracts in
  a pass/fail acceptance gate for the current bounded Phase A smoke: in-repo
  roots must include state, transaction, `blockRlp`, and `engineNewPayloadV2`
  coverage, while pinned v5.4.0 roots must match the official Shanghai
  blockchain replay table and report absent suites explicitly. Its `--devnet`
  mode also runs the standalone devnet listener-boundary all-fixtures smoke and
  includes that process-boundary report in the gate output. Pinned smoke-gate
  mode now requires an explicit root or
  `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`, so missing pinned fixture
  configuration is reported as such instead of being misclassified as selector
  drift against the in-repo seed root. The fixture report and selector-listing
  scripts now use the same configured-root error classification when either
  `--root PATH` or the environment variable points to a nonexistent path.
- *Partial:* broader cross-client process-level payload smoke coverage and wider
  pinned state-transition fixture breadth around the existing Shanghai path.
- *Missing for Phase A:* no harness blocker for the current bounded pinned
  `engine_newPayloadV2` replay; future widening should be explicit and
  selector-driven.
- *Next:* add only real upstream/pinned synchronization slices or concrete
  cross-client drift checks, not one-off local fixture hardening.

## Reference Pinning Rule

Every PR or task that claims comparison against geth, Nethermind, or Reth must
record the commit or release tag it inspected. When the local clone for a
reference client is absent, the PR or task must explicitly downgrade its claim
to "fixture-only" or "single-client comparison" instead of implying parity.
"Validated against the reference clients" without a commit reference is
treated as no comparison having been performed.

## Working Principle

Each milestone should leave the repository in a runnable state. We build
consensus-critical behavior before ergonomics, and keep APIs small until tests
make the next abstraction obvious.
