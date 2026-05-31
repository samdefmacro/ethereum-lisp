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
- **Partial:** trie/state compatibility, EVM fixture coverage, txpool
  admission, concrete HTTP/socket serving, and cross-client fixture breadth for
  the Engine import path.
- **Missing for Phase A:** fixture-grade MPT (Section 3) capable of matching
  broad reference state roots, wider execution-spec fixture ingestion, and
  broader cross-client state-transition coverage beyond the current pinned
  Shanghai Engine smoke.
- **Next checkpoint:** replace the current in-repo seed fixture cases with a
  bounded transcribed subset from the pinned execution-spec-tests release,
  starting with transaction vectors and trie/state-root cases. The selected
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

Status: first pass complete.

Implemented:

- ASDF/source-loadable project structure
- byte-vector, hex, quantity, address, hash32, uint256 helpers
- canonical RLP encoder/decoder with non-canonical rejection tests
- self-contained test runner
- reference-source map

## 1. Cryptographic Primitives

- Keccak-256 with Ethereum padding
- secp256k1 public-key recovery and signature verification
- address derivation
- Bloom filter primitives
- versioned-hash helpers for blob transactions

Validation targets: geth `crypto`, Nethermind `Nethermind.Crypto` and
`Nethermind.Core/Crypto`, and Reth/Rust primitive/KZG integration points.

Status: basic Keccak-256, SHA-256, EIP-4844 KZG commitment versioned-hash
helper, and secp256k1 public-key/address recovery are complete. Transaction
signature verification now has a first-pass low-`s` helper for sender recovery;
broader fixture coverage remains.

## 2. Consensus Data Types

- `address`, `hash32`, `quantity`, `account`
- legacy, access-list, dynamic-fee, blob, set-code transaction envelopes
- withdrawals, logs, receipts, headers, blocks
- canonical RLP for all pre-SSZ execution payload structures
- transaction sender recovery

Validation targets: geth `core/types`, Nethermind `Nethermind.Core`, and
Reth/Rust primitive transaction and block types.

Status: first pass for accounts, legacy tx, EIP-2930 tx, EIP-1559 tx,
EIP-4844 blob tx envelope encoding/hashing, EIP-7702 set-code tx envelope
encoding/hashing, legacy EIP-155 plus unprotected signing hash and sender
recovery, and EIP-2930/EIP-1559/EIP-4844/EIP-7702 typed signing hash plus
sender recovery; EIP-7702 authorization tuple authority recovery is also
present. The Phase A transaction harness now replays protected/unprotected
transfer, protected calldata, and protected/unprotected contract-creation
legacy txbytes plus
access-list transfer, access-list calldata, access-list
calldata-with-storage-keys, and contract creation, and dynamic-fee transfer,
calldata, access-list
calldata-with-storage-keys, duplicate access-list, and contract creation typed
txbytes through hash, sender, decoded payload, access-list projection, and
intrinsic-gas checks.
The full transaction fixture selector additionally covers an EIP-4844 blob
message-call with non-empty calldata and access-list data, keeping blob
versioned-hash handling tied to regular typed payload projection. It also
covers an EIP-7702 set-code message-call with non-empty calldata and
access-list data, tying authorization-list handling to regular typed payload
projection.
Blob sidecars now have a first-pass data
shape and commitment-to-versioned-hash
validation layer; callers that require KZG proof verification now fail
explicitly until a trusted-setup-backed verifier is wired in, so blob sidecars
remain shape-checked only rather than Phase A VALID. Set-code execution
semantics remain. Withdrawals/root derivation, receipts, logs bloom, and block
headers/body-root derivation are present.

## 3. Merkle Patricia Trie and State

- hex-prefix nibble encoding
- branch, extension, leaf nodes
- secure trie key hashing
- account and storage trie roots
- proofs and proof verification
- journaled state overlay for transaction execution

Validation targets: geth `trie` and `core/state`, Nethermind `Nethermind.Trie`
and `Nethermind.State`, and Reth trie/provider boundaries.

Status: minimal in-memory root calculation, code storage, snapshot/restore, and
secure state root prototype are implemented. The minimal legacy transfer spine
now avoids creating empty zero-value recipients and preserves value balance for
self-transfers. Fixture-driven state-root coverage now locks balance-add
updates, including withdrawal/reward-style creation of a funded account and
balance changes that preserve existing code and storage commitments across
leaf, branch, extension, and branch-into-extension account trie roots, with
zero-amount balance credits locked as root-preserving no-ops for missing and
existing accounts, plus matching geth-shaped state proof fixtures for
balance-add creation, zero-amount no-ops, branch/extension/branch-extension
account-trie updates, and code/storage-preserving updates; retained-state
`eth_getProof` also covers balance-add proofs across those nontrivial
account-trie layouts.
The same fixture path now covers transaction-like `transferValue` state
updates, locking nonzero sender debit plus recipient-account creation and the
zero-value missing-recipient no-op boundary, with a geth-shaped recipient
state proof after transfer. Retained-state `eth_getProof` RPC coverage now
replays the same committed transfer snapshots by block hash for sender,
recipient, and zero-value missing-recipient proofs. The fixture seed set also
covers a branch-root account trie transfer, including the recipient proof below
a hashed branch child, and retained-state RPC coverage now replays that
branch-root transfer snapshot as well. The same branch-root proof boundary now
locks the debited sender proof, so both sides of the transfer are checked
through fixture replay and retained-state RPC. Extension-root and branch-with-
extension-child transfer layouts are now covered the same way, including
sender and recipient proof nodes plus retained-state `eth_getProof` RPC replay
from committed block-hash snapshots.
The geth-derived secure account state root is now also represented in
state-proof fixtures: the deterministic account nonce/balance set from
`makeAccounts` locks the secure root and exact account proof nodes for the
first account, tying state proof replay to the same reference account-trie
coverage used by the trie and state-root gates.
Retained-state `eth_getProof` now replays that same secure account snapshot by
block hash and compares the RPC proof with the core proof primitive. The
secure account proof fixture now covers all three deterministic accounts under
that root, so each hashed branch child is represented by exact account proof
nodes.
Storage-root fixtures now lock zero-value
writes to absent storage slots as no-ops for missing accounts, funded accounts
with empty storage, and branch-shaped / extension-shaped secure storage tries.
Matching state-proof fixtures now cover missing, funded, and code-account
cases where a zero-value storage write preserves the expected account
presence/absence while keeping the storage trie empty, and retained-state
`eth_getProof` RPC reads verify the same boundaries from committed snapshots.
State-proof fixtures and retained-state `eth_getProof` RPC reads also cover
same-slot storage overwrites, proving the final storage value and a sibling
missing slot from the committed snapshot.
Code-deletion proof fixtures also lock both pruning of code-created empty
accounts and preservation of funded accounts after their code hash returns to
the empty-code hash, with retained-state `eth_getProof` RPC reads now
verifying those same committed snapshot boundaries.
Code-deletion proof coverage now also spans branch, extension, and
branch-into-extension account-trie layouts, proving funded-account code
clearing keeps the account while returning the empty-code hash.
State-proof fixtures now also cover the storage-trie branch- and
extension-preserving delete boundaries: after deleting one present child from a
three-slot secure storage trie, geth-shaped proof objects verify retained
storage roots, present slots, and missing deleted slots against the
non-collapsed branch/extension outcomes. Retained-state `eth_getProof` RPC
coverage now verifies those same committed snapshot boundaries by block hash,
and the two-slot delete-collapse boundary now has retained-state RPC proof
coverage for both the surviving slot and the deleted missing slot.
State-proof coverage also locks branch- and extension-shaped storage-trie
updates where one secure-hashed slot is overwritten while sibling present-slot
and missing-slot proofs remain valid against the updated storage root.
State-proof fixtures now also lock account-trie delete-collapse proofs for
branch-to-leaf, extension-to-leaf, and branch-plus-extension-to-extension
`clearAccount` outcomes, proving the surviving account against the compressed
state root. Retained-state `eth_getProof` RPC coverage now verifies the same
three account-trie delete-collapse snapshots by block hash, including both
the surviving account and the pruned account's missing-proof result.
The same proof/RPC boundary now covers pruned accounts that carried non-empty
code and non-empty storage before `clearAccount`, locking both survivor proofs
and deleted-account missing proofs after branch, extension, and
branch-plus-extension compression.
Code-update proof coverage now locks overwriting non-empty code with new
non-empty code through both fixture replay and retained-state `eth_getProof`,
including the updated account code hash and retained empty storage root.
The same code-update proof boundary now covers branch, extension, and
branch-into-extension account-trie layouts, including expected proof depths in
retained-state `eth_getProof` snapshots.
Code-update proof coverage also includes the non-empty-storage account case,
locking the updated code hash while retaining the storage root plus present
and missing storage proofs after the code overwrite.
State-root fixtures now lock the matching non-empty-storage code update
boundary, proving the account RLP and final state root retain the storage
commitment while only the code hash changes.
The trie harness now covers secure-key branch, extension, delete-collapse,
delete-to-empty, and missing-delete no-op replay in both seed vectors and
selected EEST-style secureTrie samples, including no-op deletion over branch
and path-compressed extension roots. It also gates secure duplicate-key
overwrites that preserve branch and extension roots, so update replay cannot be
covered only by a single-key leaf overwrite. The selected EEST-style trie
subset also reports present/missing proof-key coverage for both secure and
plain replay, so root-only fixture expansion cannot silently drop proof
verification. It also carries the geth `TestInsert` shared-prefix case for
`doe` / `dog` / `dogglesworth`, locking the reference root, compressed
extension path, hashed child reference, and final lookups in both seed and
EEST-style replay. It now also carries the geth `TestDelete` sequence for
`do` / `ether` / `horse` / `shaman` / `doge` / `dog`, locking the
post-deletion reference root, retained lookups, missing-key proofs, and
compressed extension shape after deleting `ether` and `shaman`.
The same seed/EEST-style trie path now includes geth's long leaf-value
`TestInsert` case for key `A` with a 50-byte value, locking the
`0xd23786fb4a010da3ce639d66d5e904a11dbc02746d1ce25029e53290cabf28ab`
root and leaf value projection.
It also carries geth `TestTinyTrie` account-trie roots for keys ending
`0x1337`, `0x1338`, and `0x1339`, including deterministic RLP account
values and the progressive single-leaf-to-extension transition rooted at
`0x8c6a85a4d9fda98feff88450299e574e5378e32391f75a055d470ac0653f1005`,
`0xec63b967e98a5720e7f720482151963982890d82c9093c0d486b7eb8883a66b1`,
and `0x0608c1d1dc3905fa22204c7a0e43644831c3b6d3def0f274be623a948197e64a`.
The MPT can now export deterministic final key/value pairs, and the
three-account TinyTrie fixture rebuilds a fresh trie from that export to match
geth's iterator-style reconstruction check before broader state snapshot
persistence lands. State snapshot export now also sorts account addresses and
storage slots before replay callbacks, so retained-state commits and fixture
exports no longer depend on hash-table iteration order. The selected
EEST-style trie subset now applies that final entry-pair export/rebuild check
to every replayed plain and secure trie case and gates secure/plain replay
counts in its Phase A summary, so external-style trie imports keep deterministic
snapshot/rebuild coverage rather than only root/proof assertions.
The seed trie fixture format now also accepts explicit `expectedEntryPairs`,
and the geth three-account TinyTrie case locks the exported final leaf order
and values directly before rebuilding from `mpt-entry-pairs`.
The state-root fixture now replays the geth-derived secure account RLPs through
`state-db-set-account`, gating the secure account-trie root and hashed branch
child references at the state layer as well as the raw trie layer.
The MPT export path now also supports geth-style half-open range iteration
through `mpt-entry-range`, with fixture coverage for bounded and unbounded
entry ranges before broader snapshot/export consumers depend on it.
The selected EEST-style trie subset now derives the same entry-range checks
for every replayed plain and secure case, comparing range output against final
entry pairs across full, lower/upper-bounded, equal-bound, and multi-entry
bounded windows.
The trie fixture gate now explicitly requires the current geth-derived proof,
large-value, account-step, insert/delete, empty-value, replication, random,
range, and secure account/delete families plus the Nethermind partial-path
proof-node case to remain present on the expected plain or secure path.
State snapshot export now exposes the same half-open secure-key range ordering
for account and storage entries, giving later proof/range-sync code a
deterministic boundary instead of re-scanning hash-table state.
The state-root fixture harness now accepts explicit account/storage range
expectations, and the multi-account secure-state seed pins full and bounded
proof-key range output.
The secure-key counterpart now hashes geth's deterministic account addresses
before replay and locks the one-, two-, and three-account roots
`0xc8c796b39027107040d7bae53042070762d888d7ec5e8fa875c95bde2ab3e8a5`,
`0x95e5d195992feeb1c07e0725456fde075005f3fe3ae2270b0b956004049de80f`,
and `0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d`.
That secure three-account case now also locks the sorted hashed-key
`mpt-entry-pairs` export and rebuilds from those exact final account RLP
values, with seed coverage requiring a secure entry-pair replay case.
Trie-vector fixtures can now assert proof-node RLP prefixes as well, and the
seed set locks Nethermind's `GetBranchNodesWithPartialPath` root and branch
node encodings for the shared-prefix hex-key case, including the branch RLP
that Nethermind records as geth-compatible output. The geth `TestDelete`
replay now also locks exact proof-node RLP prefixes for a retained key and a
deleted-key missing proof after deletion-driven extension compression. The
seed fixture runner also accepts empty `put` values as delete operations,
matching geth `TestEmptyValues` and locking that path to the same root,
lookup, and proof-node encoding expectations.
Persistence integration, deletion edge cases, and broader fixture
compatibility remain.
The selected EEST-style trie subset also covers secure hex byte-string
key/value replay with deletion to a non-empty secure root, so external fixture
ingestion now exercises byte-oriented secure trie inputs as well as ASCII
samples. Local trie-vector seeds can now express hex byte values directly,
including non-text leaf values, and verify those values through root, lookup,
and proof assertions. The selected EEST-style subset now gates plain hex byte
values alongside secure hex byte values, including object-form plain byte
values, and covers deletion of a child from a valueless plain root branch
collapsing back to a leaf.
The selected EEST-style account step-3 cases now carry explicit fixture `out`
maps for both plain geth TinyTrie keys and secure geth account addresses,
including present account RLP assertions and missing-account assertions gated
as required reference-derived coverage.

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
- *Partial:* fixture-backed CALL/CREATE/precompile breadth, exact gas parity
  for all edge cases, EIP-7702 delegated-code execution beyond the covered
  paths, and stopgap BN254 pairing behavior behind an explicit backend boundary
  until a full pairing library lands.
- *Missing for Phase A:* broader pinned execution-spec state fixtures, real
  KZG point-evaluation verification before Cancun blob execution can enter the
  Phase A gate, and any EOF support until an explicit activated-fork rule is
  chosen.

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
  Ethash reward hook, and Merge/Paris validation.
- *Partial:* EIP-7702 set-code execution beyond delegation shape, blob
  transaction semantics without KZG verification, and broader post-execution
  rollback symmetry across all failure modes.
- *Missing for Phase A:* broader pinned post-Merge Shanghai state-transition
  fixture breadth around the existing smoke path, plus Cancun blob execution
  acceptance once real KZG verification is available.

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
  admission, HTTP stream/listener serving, telemetry hooks, and a devnet CLI
  shell that loads genesis and exposes the current head.
- *Partial:* txpool policy beyond the current in-memory pending pool,
  cross-client Engine fixture breadth beyond the pinned v5.4.0 Shanghai
  `engine_newPayloadV2` replay slice, authenticated process wiring, and
  concrete long-running devnet/Hive process ergonomics.
- *Missing for Phase A:* broader Hive-style Engine smoke breadth around the
  existing Shanghai path, plus any Cancun blob execution acceptance until real
  KZG verification is available.

Detailed historical implementation notes for this section now live in
`docs/status.md` under "Section 7: Engine API and JSON-RPC".

## 8. Compatibility Harness

- Ethereum execution-spec-tests fixture runner
- RLP/trie/blockchain fixtures
- cross-check selected fixtures against geth, Nethermind, and Reth/Rust outputs
  where available
- CI entry points for SBCL

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
