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
  committing writes, and `eth_estimateGas` can binary-search retained-state
  call simulations for simple transfers and contract calls while detecting
  reverts. `eth_createAccessList` can turn retained-state call access tracking
  into geth-shaped access-list and gas-used results. Signed block import,
  Engine payload import, transaction admission, and mined transaction RPC
  objects require real sender recovery rather than zero-address fallbacks. The
  in-memory Engine import path is atomic for state DB plus block, receipt,
  transaction, account, pending/filter, blob sidecar, prepared payload,
  forkchoice checkpoint, and invalid-payload cache indexes.
- **Partial:** txpool admission, concrete HTTP/socket serving, production
  persistence, and cross-client process-level fixture breadth beyond the
  current bounded Engine import path. A standalone
  `scripts/devnet-smoke-gate.lisp` now exercises the local split
  Engine/public listener boundary with authenticated payload import,
  forkchoice, and public retained-state reads.
- **Current Phase A smoke gate:** `scripts/phase-a-smoke-gate.lisp` now fails
  unless the in-repo Phase A fixture root has selector-gated state,
  transaction, and blockchain replay coverage, including both `blockRlp` and
  `engineNewPayloadV2`. Its `--pinned-v5.4.0` mode validates the official
  stable archive's pinned Shanghai blockchain replay table while explicitly
  reporting that the archive lacks `state_tests` / `transaction_tests` suites;
  `--root PATH` makes the fixture root explicit for CI and automation.
  The gate now executes the selected state-test cases, transaction vectors,
  and blockchain replay imports rather than only reporting selector counts,
  and its text/JSON output records per-suite execution counts.
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
  dispatch.
- *Partial:* fixture-backed CALL/CREATE/precompile breadth, exact gas parity
  for all edge cases, EIP-7702 delegated-code execution beyond the covered
  paths, and KZG proof verification.
- *Missing for Phase A:* broader pinned execution-spec state-transition replay
  beyond the current selector-gated replay (London
  legacy/access-list/dynamic-fee vectors, expected-exception handling,
  Shanghai PUSH0 replay, and optional-root discovery workflow); real KZG
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
  backend now persists records across process restarts
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
  receipt, transaction, account, storage, pending/filter, blob sidecar, and
  invalid-payload cache indexes needed by the in-memory Phase A smoke path.
- *Partial:* production database layout, freezer/history retention, pruning
  modes, sync-stage persistence, and durable trie-node storage remain later
  work.
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
  split-listener shutdown, and
  has a split-listener smoke covering authenticated Engine JSON-RPC,
  `engine_newPayloadV2` import,
  `engine_forkchoiceUpdatedV2`, and unauthenticated public latest-state reads.
- *Partial:* txpool policy beyond the current in-memory pending pool,
  cross-client Engine fixture breadth beyond the pinned v5.4.0 Shanghai
  `engine_newPayloadV2` replay slice, and concrete long-running devnet/Hive
  lifecycle ergonomics beyond the current readiness, log-file, and shutdown
  contract.
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
  The individual state, transaction, and blockchain selector-listing scripts
  now also emit JSON so selector drift checks can consume structured output
  directly. `scripts/phase-a-smoke-gate.lisp` wraps those selector contracts in
  a pass/fail acceptance gate for the current bounded Phase A smoke: in-repo
  roots must include state, transaction, `blockRlp`, and `engineNewPayloadV2`
  coverage, while pinned v5.4.0 roots must match the official Shanghai
  blockchain replay table and report absent suites explicitly.
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
