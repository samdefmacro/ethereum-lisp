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
  outcomes: two-child delete collapse to a leaf and three-child delete
  preservation of the branch root. It also gates extension-subtree child
  deletion that compresses all the way back to a single leaf, covering the
  path-compression boundary beyond root-branch cases. The selected Phase A
  transaction subset now gates dynamic-fee contract creation alongside legacy
  creation, so typed sender recovery and `to = null` decoding are represented
  before pinned transaction-test replacement. The Shanghai
  `engine_newPayloadV2` smoke now covers legacy transfer, access-list transfer,
  dynamic-fee typed transfer, contract creation, withdrawals, multi-transaction
  receipt ordering/cumulative gas, safe/finalized checkpoint tags, and
  two-branch canonical switching, with canonical `eth_getProof` replay and
  verification over the imported child state root plus branch-switch proof
  reads that distinguish canonical `latest` from hash-addressed non-canonical
  child state. The same smoke path now exercises retained storage proofs and
  verifies geth-shaped `storageProof.value` quantities against the imported
  child state root; remaining Engine fixture work is mainly pinned-fixture
  breadth rather than new smoke-path shape.

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
transfer and contract-creation legacy txbytes plus access-list and dynamic-fee
typed txbytes through hash, sender, decoded payload, and intrinsic-gas checks.
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
Storage-root fixtures now lock zero-value
writes to absent storage slots as no-ops for missing accounts, funded accounts
with empty storage, and branch-shaped / extension-shaped secure storage tries.
Matching state-proof fixtures now cover missing, funded, and code-account
cases where a zero-value storage write preserves the expected account
presence/absence while keeping the storage trie empty, and retained-state
`eth_getProof` RPC reads verify the same boundaries from committed snapshots.
Code-deletion proof fixtures also lock both pruning of code-created empty
accounts and preservation of funded accounts after their code hash returns to
the empty-code hash, with retained-state `eth_getProof` RPC reads now
verifying those same committed snapshot boundaries.
The trie harness now covers secure-key branch, extension, delete-collapse,
delete-to-empty, and missing-delete no-op replay in both seed vectors and
selected EEST-style secureTrie samples, including no-op deletion over branch
and path-compressed extension roots. Persistence
integration, deletion edge cases, and broader fixture compatibility remain.
The selected EEST-style trie subset also covers secure hex byte-string
key/value replay with deletion to a non-empty secure root, so external fixture
ingestion now exercises byte-oriented secure trie inputs as well as ASCII
samples. Local trie-vector seeds can now express hex byte values directly,
including non-text leaf values, and verify those values through root, lookup,
and proof assertions. The selected EEST-style subset now gates plain hex byte
values alongside secure hex byte values, and covers deletion of a child from a
valueless plain root branch collapsing back to a leaf.

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
  paths, and stopgap BN254 pairing behavior until a full pairing library lands.
- *Missing for Phase A:* broader pinned execution-spec state fixtures, real
  KZG point-evaluation verification before Cancun blob execution can enter the
  Phase A gate, and any EOF support until an explicit activated-fork rule is
  chosen.

The detailed implementation log below is preserved for historical context and
is queued for migration into a status document via `DOC-ROADMAP-STATUS-SPLIT`.

Status: interpreter skeleton implemented for a growing opcode subset. Initial
gas-limit accounting, 1024-item stack limit enforcement, unsigned and signed
arithmetic/comparison, EXP, SHA3,
environment reads, external-code reads, calldata/codecopy, jumpdest analysis,
storage, transient storage (`TLOAD`/`TSTORE`) with frame rollback, first-pass
Yellow Paper memory expansion gas for `MLOAD`/`MSTORE`/`MSTORE8`, `SHA3`,
copy-family opcodes, `MCOPY`, `LOG0`-`LOG4`, `RETURN`, and `REVERT` plus
CALL-family argument/output ranges and CREATE/CREATE2 initcode ranges, plus
per-word hash/copy gas and log topic/data gas; active memory size is now
word-aligned for `MSIZE`, and memory gas is charged before EIP-150 child gas
clamping. EIP-3855 `PUSH0` base gas, returndata copy, `GAS` remaining-gas
reporting under supplied execution gas limits, minimal same-state CALL,
CALLCODE, DELEGATECALL, STATICCALL paths
with stack-gas forwarding to child frames plus child rollback/read-only
propagation, first-pass child gas-used charging, and EIP-150 63/64 child gas
clamping plus value-call stipend, value-transfer, and new-account gas, and
insufficient-balance value-call failure coverage; self-CALL value transfer now
preserves the account balance instead of double-applying the value. Minimal CREATE/CREATE2 are
present with initcode child gas-used charging, 63/64 child gas clamping, and
runtime code deposit gas charging plus code-deposit out-of-gas and
EIP-3541-prefixed runtime rejection coverage; successful CREATE/CREATE2 now
retain initcode logs in parent execution results for receipt/log bloom
derivation, while reverted initcode discards those child logs; top-level legacy
contract creation receipts now cover successful initcode logs plus reverted and
invalid-runtime log discard behavior. Collision failure now consumes the clamped
child gas under supplied execution gas limits, and creator nonce overflow is
rejected before incrementing the nonce.
First-pass SELFDESTRUCT balance transfer/halt behavior is present, including
the EIP-6780 existing-account self-beneficiary no-op balance case, without
account deletion or refunds. EVM execution results now carry a first-pass
refund counter, including EIP-3529 SSTORE nonzero-to-zero clear refunds that
merge upward only from successful child frames and are discarded on REVERT/error.
Nested CALL coverage now exercises both successful child refund propagation and
reverted child refund discard; direct reverted EVM results also clear their
frame-local refund counter. Same-frame SSTORE nonzero-to-zero-to-nonzero
recreation now reverses the earlier clear refund at both EVM-result and
top-level receipt/refund settlement layers, and slots that were originally zero
but are created and then cleared do not receive an SSTORE clear refund. Dirty
SSTORE writes that reset a slot back to its original value now receive the
EIP-3529 reset refund, including original-nonzero clear-then-reset paths and
original-zero create-then-reset paths. Nested EVM frames now share storage
original-value tracking so DELEGATECALL/CALLCODE reset-refund accounting uses
the transaction-level original slot value, and they share/restorably snapshot
SSTORE clear-refund markers so delegated child writes can reverse parent-frame
clear refunds without leaking changes across reverted child frames. The first
EIP-2929 warm/cold storage-access state is present for `SLOAD` and `SSTORE`:
`SLOAD` charges 2100 gas for the first `(address, slot)` read and 100 gas for
subsequent warm reads, while `SSTORE` now uses EIP-2200/EIP-2929 dynamic write
costs with EIP-3529 refunds and shared warm-slot state restored on frame
`REVERT`/error. Account-access charging is present for `BALANCE`,
`EXTCODESIZE`, `EXTCODECOPY`, `EXTCODEHASH`, the `CALL` family, and
`SELFDESTRUCT`: account-reading opcodes charge the 2600 cold account cost on
first touch and the 100 warm read cost on subsequent touches, while
`SELFDESTRUCT` charges the full 2600 cold beneficiary access cost only when the
beneficiary is cold. `SELFDESTRUCT` also charges the 25,000 new-account cost
when transferring a nonzero balance to an empty beneficiary. Account access
state is restored on frame `REVERT`/error. Implemented precompile addresses are
prewarmed in fresh EVM transaction contexts and execution-layer message
contexts, using `chain-rules` when present so Frontier/Homestead only prewarms
`0x01`-`0x04`, Byzantium adds `0x05`-`0x08`, Istanbul adds `0x09`, and Cancun
adds `0x0a`; precompile execution uses the same active-address gates.
Execution-layer transaction contexts now prewarm the sender, coinbase, and the
recipient or created contract address. Transaction
access-list storage keys and addresses now prewarm the EVM storage and account
access sets for the implemented execution paths. Internal
`CREATE`/`CREATE2` now also prewarm the computed created address before
initcode execution and collision handling.
Cancun blob environment reads
(`BLOBHASH`/`BLOBBASEFEE`) are present. When an EVM context carries
`chain-rules`, the first fork-specific opcode gates are enforced:
`DELEGATECALL` requires Homestead, `RETURNDATASIZE`/`RETURNDATACOPY`, `REVERT`,
and `STATICCALL` require Byzantium, `SHL`/`SHR`/`SAR`, `EXTCODEHASH`, and
`CREATE2` require Constantinople, `CHAINID`/`SELFBALANCE` require Istanbul,
`BASEFEE` requires London, `PUSH0` requires Shanghai, and
`BLOBHASH`/`BLOBBASEFEE`, `TLOAD`/`TSTORE`, and `MCOPY` require Cancun.
ECRECOVER, SHA256, RIPEMD160, and
identity precompiles are reachable through CALL, CALLCODE, DELEGATECALL, and
STATICCALL with first-pass precompile gas charging and out-of-gas handling;
ECRECOVER includes geth-vector address recovery plus invalid high-`v` handling.
MODEXP is present with Berlin/EIP-2565 gas accounting, BN254 `ECADD`/`ECMUL`
precompiles are present with Istanbul gas costs and invalid-point failure
coverage, BN254 pairing now covers the empty-input true result and malformed
input-size failure using Istanbul gas constants, plus non-empty inputs where
each pair contains a zero/infinity element, explicit non-empty cancellation
relations, and non-cancelled non-zero inputs that return false instead of a
precompile failure; G2 pairing inputs now receive first-pass field-coordinate
and twist-curve validation for those skipped pairs, with oversized-coordinate
and off-curve failure coverage. BLAKE2F is present for
EIP-152 valid and malformed-input paths. The Cancun KZG point-evaluation
precompile address is now recognized with the fixed 50,000 gas cost, 192-byte
input length validation, and versioned-hash/commitment mismatch failure
coverage. The matched versioned-hash path is also covered through the current
explicit verifier-unavailable failure; actual KZG proof verification remains,
with required verification paths expected to fail explicitly until the verifier
lands.
CREATE/CREATE2 now include
first-pass EIP-3860 initcode word/hash gas in opcode gas accounting, with
direct oversized-initcode rejection coverage for both opcodes when Shanghai
rules are active; before Shanghai, CREATE skips the EIP-3860 word charge and
CREATE2 keeps only its EIP-1014 hash-cost component. First-pass
dynamic memory gas is now covered for the currently implemented memory-touching
opcodes; full CALL-family/create semantics, full non-empty BN254 pairing, KZG
proof verification and later precompiles, refunds, and fork-specific tables
remain. CREATE collision handling is covered for nonce/code collisions.

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
  in-memory receipt / log / state-root derivation, broad EIP coverage up to
  Cancun fields, receipt-derivation invariants on the import path, block-body
  and post-execution commitment preflight, Ethash reward hook, and Merge/Paris
  validation.
- *Partial:* atomic state/receipt/index commit semantics on validation
  failure, EIP-7702 set-code execution beyond delegation shape, blob
  transaction semantics without KZG verification, and post-execution rollback
  symmetry across all failure modes.
- *Missing for Phase A:* an atomic block-import commit boundary, fixture-grade
  state-root verification (depends on Section 3 trie work), strict sender
  recovery on every signed import/admission/mined RPC path, and a pinned
  post-Merge Shanghai fixture set the smoke path is compared against.

The detailed implementation log below is preserved for historical context and
is queued for migration into a status document via `DOC-ROADMAP-STATUS-SPLIT`.

Status: minimal legacy transfer, contract-creation, recipient-code execution,
EIP-4895 withdrawal balance-crediting, and a lightweight legacy block execution
path are implemented with nonce, balance, intrinsic-gas validation, receipts,
logs, top-level revert/error rollback, state/tx/receipt/withdrawal root output,
gas-used header population, and body/header root validation for ommers,
transactions, withdrawals, and blob gas used. Post-execution validation now
checks gas-used, logs bloom, receipts root, and state root against the block
header, and block execution rejects supplied post-execution gas-used, state,
receipt, and logs-bloom commitments before overwriting them when constructing
the executed block. Block execution now snapshots and restores the input state
and mutable header fields when execution-phase validation fails, including
gas-pool exhaustion and supplied post-execution commitment mismatches. Sender nonce validation now also rejects the EIP-2681 max nonce
overflow case before charging gas or mutating balances; transaction values
above uint256, transaction nonces above uint64, and transaction gas limits
above uint64 are likewise rejected before nonce or balance mutation. EIP-1559 base-fee
calculation and header base-fee validation have a
first pass, along with basic parent-relative header checks for parent hash,
block number, timestamp, gas-used, extra-data size, and gas-limit delta/minimum
bounds; header import validation now also preflights core header field shapes
before parent hash, seal, base-fee, blob-gas, or fork-specific comparisons.
The London fork block gas-limit delta now uses the EIP-1559 elastic
parent gas-limit adjustment. Cancun blob gas header field-shape validation checks that `blobGasUsed`
and `excessBlobGas` appear together, that `blobGasUsed` is blob-sized, and that
`parentBeaconRoot` is present for Cancun-shaped headers and absent before
Cancun, while `excessBlobGas` follows the first-pass EIP-4844 parent update formula.
Prague execution requests now have the same first-pass header field-shape
guard: `requestsHash` is required when requests are enabled and rejected before
Prague, and blocks can carry requests bodies whose hash is derived into and
validated against the header.
Execution request body validation now checks each request item is byte-vector
shaped and contains a request type byte before hashing, body validation, or
block execution state mutation.
Withdrawal body validation now also checks withdrawal field shapes before root
comparison or state mutation, including uint256 index/validator/amount fields
and address-typed recipients.
Transaction access-list execution now validates access-list entry, address, and
storage-key shapes before intrinsic gas calculation, sender gas purchase, or
EVM context prewarming; block body validation applies the same access-list
field-shape checks before transaction root derivation.
Block body validation also checks set-code transaction recipient,
authorization-list presence, and authorization tuple field shapes before
transaction root derivation.
Transaction data fields are now normalized through byte-sequence validation
before intrinsic gas calculation, sender gas purchase, or transaction root
derivation.
Transaction recipient fields are also validated before transaction root
derivation, and message execution rejects non-address recipients before sender
nonce or balance mutation.
Block body validation now checks transaction nonce/gas-limit uint64 bounds,
value uint256 bounds, and execution/blob fee-cap uint256 bounds before
transaction root derivation.
Transaction signature scalar fields (`chainId`, `v`, `yParity`, `r`, and `s`)
are likewise checked for uint256 shape before transaction root derivation.
Block body validation now also checks that the transactions body is a list of
transaction objects before blob-gas aggregation or transaction root derivation.
The ommers body is likewise checked as a list of block headers before
`ommersHash` derivation or Post-Merge ommer rejection.
Withdrawal and execution-request bodies now validate their list container shape
before withdrawal-root or requests-hash derivation.
Header body commitments (`ommersHash`, `transactionsRoot`, optional
`withdrawalsRoot`, and optional `requestsHash`) are shape-checked before
commitment comparison.
Post-execution commitment validation now also checks logs bloom, receipts root,
header state root, computed state root, and gas-used shapes before comparing
the executed results.
Receipt and log bodies are now field-validated before execution-root
derivation, including receipt list/object shape, cumulative gas bounds,
post-state root bytes, log address/topic/data shapes, and supplied typed
transaction list shape. Receipt list validation also rejects non-increasing
cumulative gas sequences before deriving roots.
A first-pass chain configuration model is present for block-number forks
through London and timestamp forks through Prague, including geth-compatible
activation predicates and config-driven header validation for Shanghai,
Cancun, and Prague field requirements. A geth-style `chain-rules` snapshot now
materializes the active fork booleans for a block number/timestamp pair and can
answer whether a transaction type is supported under those rules. EVM contexts
can now carry this rules snapshot, and message execution can derive it from a
chain config for the current block number/timestamp; message and block
execution now reject typed transactions before their activating fork before
sender nonce or balance mutation, with block execution preflighting the full
transaction list and config-driven London base-fee plus
withdrawals/requests/Cancun header body shape before applying any transaction
state changes. Transaction type validation can now use the same chain
configuration to reject access-list transactions before Berlin, dynamic-fee
transactions before London, blob transactions before Cancun, and set-code
transactions before Prague; a config-driven block body validation entry point
now applies those transaction-type gates before the existing body root/hash
checks. A first-pass full-block validation entry point now combines
parent/header validation with config-driven body validation for block import and
Engine API scaffolding.
Osaka activation is now represented in chain config and chain-rules snapshots,
and config-driven header validation applies the first-pass EIP-7918
`excessBlobGas` update when the blob reserve price is above the current blob
price. Prague, Osaka, BPO1, BPO2, BPO3, and BPO4 now select their fork-specific
target/max blob schedule defaults and blob base-fee update fractions for
header/body validation and execution blob-fee debits; config-aware body
validation and block execution therefore allow the higher 9-, 15-, 21-, and
32-blob aggregate limits at the appropriate schedule points while preserving
the lower per-blob transaction cap. Chain configs can also carry an explicit
timestamp-keyed custom blob schedule, including geth-style `bpo5Time` plus
`blobSchedule.bpo5`; config-derived chain-rules snapshot the active
target/max/update-fraction values so execution paths that only receive rules
still use the same blob limits and fee update fraction. A first-pass geth
genesis config conversion layer now accepts parsed `config` objects, including
the `blobSchedule` fork map, and builds the same chain-config/custom-schedule
model used by validation and execution. It also preserves geth/Nethermind
Merge-era config fields such as `terminalTotalDifficultyPassed`,
`mergeNetsplitBlock`, and `depositContractAddress`, carries DAO and
difficulty-bomb delay fork fields, and recognizes Nethermind's
`tangerineWhistleBlock`/`spuriousDragonBlock` aliases for EIP-150, EIP-155,
and EIP-158 transitions. Amsterdam and UBT activation timestamps are now
represented in chain configs and rules snapshots, with geth-style
`enableUBTAtGenesis` preserved for future Verkle/Binary-tree genesis handling.
Amsterdam header shape is now represented as well: genesis parsing accepts
geth-style `balHash`/`blockAccessListHash` plus `slotNumber`, active Amsterdam
genesis headers default the block access-list hash to the empty RLP list hash
and slot number to zero, and config-driven header validation gates those fields
at the Amsterdam timestamp. Blocks can now carry a first-pass empty Amsterdam
block-access-list body, derive its empty-list commitment into `balHash`, and
validate body/header BAL presence and hash consistency. Non-empty BAL encoding
is also present: block-access accounts encode in geth's six-field RLP shape,
account addresses and storage-read slots are validated in strict lexicographic
order, slot-key/value fields use geth-compatible uint256 RLP integer encoding,
and account shells plus sorted storage-read/storage-write/balance-change lists
plus nonce-change/code-change lists can now contribute to `balHash`; block
body validation also enforces the fork-specific code-change size limit (24 KiB
before Amsterdam, 32 KiB at Amsterdam) and the Amsterdam BAL item budget
(`accounts + changed/read storage slots <= block_gas_limit / 2000`). BAL RLP
wire payloads can now decode back into typed account/change structures and are
rejected with block-validation errors for malformed RLP, malformed account
shape, and invalid address lengths; decoded payloads are validated through the
same ordering, size, and item-budget checks before being accepted, and a
wire-RLP hash helper verifies then hashes encoded BAL bytes for Engine payload
and database paths. Blocks can also be constructed from encoded BAL RLP,
decoding the body while deriving the header commitment from the supplied wire
bytes and retaining the encoded bytes for later payload/database serving.
Body validation now checks that any retained encoded BAL bytes still decode to
the same typed BAL body before accepting the `balHash` commitment.
Amsterdam header validation also now requires child slot numbers to strictly
exceed the parent once the parent is already Amsterdam-shaped.
A small dependency-free genesis JSON
reader now supports the JSON shapes needed for geth-style `config` objects and
can build chain configs directly from JSON strings or files.
Blob transaction body validation rejects empty blob hash lists, missing or
wrong-sized versioned hashes, and non-`0x01` versioned hashes, rejects blob
transactions of type contract creation, and enforces first-pass Cancun blob
count/gas limits. Blob sidecars now validate
blob, KZG commitment, and KZG proof byte sizes, require matching sidecar list
lengths, and verify that sidecar commitments derive the versioned hashes
declared by the blob transaction. A separate proof-verification-required path
fails loudly while real KZG verification is unavailable.
Blob base fee calculation now implements the EIP-4844 fake exponential using
default Cancun parameters, and blob transaction body validation checks
`maxFeePerBlobGas` against the derived blob base fee when the header carries
`excessBlobGas`; blob fee caps outside uint256 are also rejected before state
mutation. EIP-1559 transaction fee cap validation and effective gas
price derivation now cover legacy and typed fee-market transactions, and the
message execution path can apply first-pass EIP-1559 dynamic-fee transfers with
base-fee-aware gas charging; block body validation now checks EIP-1559
execution gas fee caps against the header base fee before root/import
acceptance, and fee-market validation rejects execution gas fee caps and
priority fee caps outside uint256 before state mutation;
transaction constructors reject negative fee fields before they can enter normal
validation; upfront balance validation now uses
`maxFeePerGas` and blob fee caps while actual debits use effective/base fees.
Block/message execution now credits the effective priority fee to the header
beneficiary/coinbase, leaves the base fee burned, and refunds unused gas for
first-pass simple value transfers plus EVM success/REVERT paths based on
interpreter-reported gas used. Top-level zero-value sends to empty recipients
now avoid creating empty accounts, and self-transfers preserve value balance
while still charging gas. Top-level contract creation now includes a
first-pass code deposit gas charge (`200 * runtime-code-bytes`) on successful
deployment, and rejects code-deposit out-of-gas by consuming the full
transaction gas limit without installing code; it also rejects EIP-3541
`0xEF`-prefixed runtime code when London rules are active, while allowing that
prefix before London; runtime code above the fork-specific 24576-byte or
Amsterdam 32768-byte limit is rejected, and creation initcode above the paired
49152-byte or Amsterdam 65536-byte limit is rejected before execution when
Shanghai rules are active. Intrinsic gas now uses the 53000 contract-creation
base cost and applies the EIP-3860 initcode word cost only when Shanghai rules
are active, alongside EIP-2930 access-list address and storage-key costs. Block execution
now enforces a first-pass gas pool check against the header gas limit before
applying each transaction, and passes header environment fields into
transaction EVM contexts for `COINBASE`, `TIMESTAMP`, `NUMBER`, pre-Merge
`DIFFICULTY`/post-Merge `PREVRANDAO`, `GASLIMIT`, and `BASEFEE`. Cancun blob
transactions now validate their blob fee
cap during message execution and supply
blob versioned hashes/blob base fee to the EVM context for `BLOBHASH` and
`BLOBBASEFEE`; first-pass blob execution also debits `blobGasUsed * blobBaseFee`
from the sender, and block execution preflights supplied body commitments
including `transactionsRoot`, `ommersHash`, `withdrawalsRoot`, `requestsHash`,
`balHash`, and `blobGasUsed` before mutating state while still populating those
fields when building a block from transactions. Execution block preflight now
also requires/prohibits Amsterdam block-access-list bodies according to the
active chain config; legacy and signed execution block entry points can accept
encoded BAL RLP, decode it for validation, and preserve the original encoded
bytes in the produced block. Execution commitment preflight now uses those
encoded BAL bytes when checking `balHash`, matching Engine/database payload
commitments even when accepted uint encodings differ from canonical typed
re-encoding. Execution also checks aggregate blob gas against the fork-specific
limit, allowing Osaka's higher 9-blob block aggregate while keeping the prior
6-blob limit before Osaka. Prague execution requests hash derivation is present
using SHA-256 over non-empty request payload hashes, and request bodies are
field-validated before hash derivation, body-root validation, or execution
state mutation; Engine-style request bodies now must contain both a request
type and payload, and request types must be strictly increasing so each type
appears at most once. Blocks can now carry requests bodies whose header
`requestsHash` is derived and validated, and the legacy and signed block
execution entry points can now carry those requests bodies into the produced
block as well. Receipt trie derivation now uses EIP-2718 typed
receipt encodings when paired with typed transactions. Signed message execution
can now recover the transaction sender from legacy/EIP-155/EIP-2718 signatures
before applying the message, and passes the recovered/expected chain id into the
EVM context. Signed transaction lists can now produce execution results with
state/transaction/receipt roots, and a first-pass signed block execution entry
point applies the same sender recovery per transaction while preserving header
environment, gas-limit, receipt/root, withdrawal, and blob-gas accounting
behavior; signed transaction list execution now preflights the full batch of
signatures before mutating state, so a later invalid signature cannot leave
earlier transactions applied; it also preflights recovered sender code for the
full signed batch before applying the first transaction. Transaction list
execution also preflights list container/element shape, recipient, data,
scalar bounds/fee caps, access-list, blob, set-code authorization field shapes,
intrinsic gas sufficiency, and initcode size for the whole batch before
applying the first transaction. Block execution now feeds opcode `0x44` with
pre-Merge `DIFFICULTY` or post-Merge `PREVRANDAO` according to the header's
difficulty field. Historical Ethash block beneficiary and ommer rewards now have a
first-pass execution hook, with Frontier, Byzantium, and Constantinople base
reward selection behind an explicit block-execution option; post-Merge
zero-difficulty headers skip those Ethash rewards on the same execution path.
First-pass Merge/Paris header and body validation now rejects PoS headers with
nonzero nonce or non-empty ommers hash, rejects post-Merge bodies containing
ommers, and prevents a post-Merge parent from being followed by a nonzero
difficulty child; post-Merge header gas limits are also capped at the geth
beacon maximum of `2^63 - 1`.
Genesis JSON loading now has a first-pass allocation path: geth-style `alloc`
objects are parsed into genesis account descriptors with balance, nonce, code,
and storage, and those descriptors can initialize the in-memory state DB with
deterministic account/code/storage roots. Genesis storage entries now follow
geth's account JSON compatibility for short hex keys and values by left-padding
them to 32 bytes before state insertion. The genesis path can now compute the
state root directly from `alloc` and validate an optional JSON `stateRoot`
against that computed root. A first-pass genesis header constructor now maps
geth-style JSON fields onto `block-header`, including genesis gas-limit and
difficulty defaults plus London, Shanghai, Cancun, and Prague fork-default
commitment fields. Genesis block constructors can now wrap either an explicit
genesis header or geth-style genesis JSON into a `block`, using the computed
allocation state root when requested and carrying empty Shanghai withdrawals
and Prague execution-request bodies whenever those header commitments are
active. Genesis header JSON parsing now also accepts the `mixhash` alias used
by Nethermind's geth-style loader and preserves supplied
`parentBeaconBlockRoot` values only for Cancun-active genesis headers, while
still defaulting that Cancun root to zero when absent. Chain config parsing now
preserves `terminalTotalDifficulty`, and TTD=0 genesis configs default a
missing genesis difficulty to zero for merge-at-genesis fixtures.
Typed transaction execution semantics, full nested contract creation/inter-
contract calls, storage/selfdestruct refund counters and richer EVM gas
scheduling, full header validation including difficulty/seal rules and fork
schedules, remaining genesis fixture edge-case compatibility, remaining
allocation edge-case compatibility, and deeper blob
transaction validation remain. EIP-7702 set-code execution has a first-pass
transaction-shape layer: set-code messages reject contract creation and empty
authorization lists, and intrinsic gas now charges the authorization-list
upfront cost at 25,000 gas per authorization tuple. Existing authority accounts
now add the EIP-7702 12,500 gas refund to the transaction refund counter,
capped with the post-EIP-3529 1/5 gas-used refund quotient, while newly
created authority accounts are covered to receive no existing-account refund.
Recipient-code execution now also applies EVM-produced refund counters for
successful calls, with coverage that reverted top-level execution discards
SSTORE clear refunds.
Top-level sender validation now rejects senders with ordinary contract code
while allowing empty accounts and EIP-7702 delegation designators.
Valid authorization tuples are applied before the transaction call, advancing
the authority nonce and installing or clearing EIP-7702 delegation designator
code (`0xef0100 || address`), and this authorization state is covered to
persist even when recipient EVM execution reverts. Multiple authorizations for
the same authority are covered to apply sequentially when their nonces advance
in list order, with later entries replacing earlier delegation code. Invalid
authorization tuples such as
wrong-chain authorizations, nonce mismatches, max-uint64 authorization nonces
that cannot be incremented, authorities that already hold ordinary
non-delegation code, or signatures modified to target the zero address are
skipped without failing the transaction or contributing existing-account
refunds. Structurally malformed authorization tuples, including missing
delegation addresses or overwide encoded fields, are rejected before sender gas
or nonce mutation. The zero-address clear path is covered with a valid signed
authorization fixture and clears existing delegation code.
Top-level message execution now resolves
delegation designators to the target account code while preserving the
originally called account as the EVM address; EVM `CALL` now does the same for
delegated callees, and `CALLCODE`/`DELEGATECALL`/`STATICCALL` resolve delegated
code while preserving their existing address, caller, value, and read-only
context semantics. Delegation targets that point at precompile addresses are
covered to behave like empty resolved code rather than indirectly executing the
precompile, matching geth and Nethermind. `EXTCODESIZE`, `EXTCODECOPY`, and
`EXTCODEHASH` are covered
for the geth-compatible behavior of observing the delegation designator
code/hash itself rather than the resolved target code.

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
  cross-client Engine fixture breadth, authenticated process wiring, and
  concrete long-running devnet/Hive process ergonomics.
- *Missing for Phase A:* pinned execution-spec / Hive-style Engine smoke
  breadth around the existing Shanghai path, plus any Cancun blob execution
  acceptance until real KZG verification is available.

The detailed implementation log below is preserved for historical context and
is queued for migration into a status document via `DOC-ROADMAP-STATUS-SPLIT`.

Status: initial local Engine payload projection is present. Blocks can be
converted into geth-shaped `ExecutableData` payload envelopes, including
header fields, encoded transactions, optional withdrawals, optional execution
requests, blob gas counters, and Amsterdam slot numbers. The reverse raw-transaction path has begun
with legacy, EIP-2930 access-list, EIP-1559 dynamic-fee, EIP-4844 blob, and
EIP-7702 set-code transaction RLP decoding, so Engine payload transaction bytes
can start feeding back into local transaction/root validation; `ExecutableData`
now has a helper that decodes its transaction byte list back into local
transaction envelopes and a first no-hash conversion path back into local block
headers/bodies, plus a hash-checking wrapper for the normal `newPayload`
payload import path. The reverse Engine import path also checks supplied
blob `versionedHashes` against decoded blob transactions, and has a first
stateless `newPayload` parameter-status wrapper that maps local validation
errors into Engine-style payload status objects. Version-specific `newPayload`
parameter gates now cover V1 through V5 fork requirements before block import,
including Amsterdam `slotNumber` and `blockAccessList` requirements for
`engine_newPayloadV5`.
A small in-memory Engine payload store now models known-block, missing-parent,
missing-parent-state, and invalid-ancestor status branches for the future
database-backed import path. It can also iterate retained account projections
for state-available blocks so execution can rebuild a parent `state-db` from
balance, nonce, code, and storage indexes before importing a child payload.
The execution layer now has a narrow Engine payload import helper that runs
ready-parent payload blocks through the signed block atomic commit path, and
the memory `newPayload` status path can inject that importer and translate
post-execution commitment failures into Engine `INVALID` status without
storing the bad block; tests cover state-root, receipts-root, logs-bloom, and
gas-used mismatches with `latestValidHash` pointing at the known parent. That
import hook is now threaded through parsed
JSON-RPC objects, request strings, HTTP request strings, stream handling, and
the HTTP service configuration, so configured services can execute
ready-parent `engine_newPayload` imports. The production Engine HTTP service
constructor now selects that executable importer by default when the execution
package is loaded, while direct request helpers can still run the compatibility
store-only path by omitting an importer. A parsed JSON-RPC object dispatcher
can now route `engine_newPayloadV1` through `engine_newPayloadV5` calls into
that store and
return Engine-style payload status result objects. The same core can now encode
single and batch JSON-RPC response strings for request-string entry points,
and advertises the currently implemented `engine_newPayloadV1` through
`engine_newPayloadV5` plus `engine_forkchoiceUpdatedV1`,
`engine_forkchoiceUpdatedV2`,
`engine_forkchoiceUpdatedV3`,
`engine_forkchoiceUpdatedV4`,
`engine_getClientVersionV1`, and
`engine_exchangeTransitionConfigurationV1` methods through
`engine_exchangeCapabilities`; `engine_getClientVersionV1` now returns the
local Common Lisp client identity, and
`engine_exchangeTransitionConfigurationV1` returns the local terminal
difficulty with zero terminal-block defaults. `engine_forkchoiceUpdatedV1` now
parses forkchoice state and V1 payload attributes, maps known memory-store
heads to `VALID`, unknown heads to `SYNCING`, and zero heads or cached invalid
tipsets to `INVALID`; nonzero safe/finalized checkpoint hashes are also checked
against the local memory store and rejected with the Engine API `Invalid
forkchoice state` error code `-38002` when unavailable, and valid
head/safe/finalized checkpoints are retained for public block-tag resolution. It can
prepare a deterministic in-memory empty child payload when V1 payload
attributes are supplied for a valid head. The prepared payload is keyed by an 8-byte
Engine-style payload id and can be fetched through `engine_getPayloadV1`, which
returns the execution payload object for the prepared block and reports missing
ids with the Engine API `Unknown payload` error code `-38001`.
`engine_forkchoiceUpdatedV2` now reuses the same forkchoice status machinery,
prepares deterministic V2 child payloads, and carries PayloadAttributesV2
withdrawals into the prepared block. `engine_forkchoiceUpdatedV3` extends that
prepared-payload path with required PayloadAttributesV3
`parentBeaconBlockRoot`, retaining it on the prepared Cancun header and
initializing zero blob-gas fields for `engine_getPayloadV3`.
`engine_forkchoiceUpdatedV4` now adds required PayloadAttributesV4
`slotNumber`, carries it into the prepared Amsterdam header, and exposes it
through the prepared-payload `engine_getPayloadV4` path. The first
`engine_getPayloadV2` path is
also wired through the same prepared-payload
store and returns a geth/Nethermind-shaped payload envelope with
`executionPayload` and `blockValue`; `engine_getPayloadV3` now returns the
Cancun envelope shape with an empty V1 `blobsBundle` and explicit
`shouldOverrideBuilder` false marker for locally prepared payloads, and
`engine_getPayloadV4` carries Prague `executionRequests` through the same
envelope path. Prepared payloads can now retain blob sidecar bundles for
`engine_getPayloadV5`, which returns the Osaka envelope with serialized
V2 `blobsBundle` data and execution requests. `engine_getPayloadV6` now exposes
Amsterdam payload fields, including `slotNumber` and retained encoded
`blockAccessList` RLP, alongside the same V2 blob bundle envelope.
`engine_getPayloadBodiesByHashV1` can now
serve transaction/withdrawal bodies from the same memory store, preserving
request order, returning `null` for unknown hashes, and rejecting over-1024
body requests with Engine `Too large request` error code `-38004`.
`engine_getPayloadBodiesByHashV2` reuses that path and includes retained
encoded Amsterdam block-access-list RLP as `blockAccessList` when present.
`engine_getPayloadBodiesByRangeV1` is also present with a first memory-store
block-number index, positive start/count validation, head-number clipping, and
the same 1024-body limit; `engine_getPayloadBodiesByRangeV2` now follows that
same indexed range path while surfacing retained block-access-list RLP. Payload build
requests with semantically invalid V1 attributes, such as a timestamp not
greater than the parent head, now report Engine API `Invalid payload attributes`
with error code `-38003`. `engine_getBlobsV1` now has a first memory-store
blob sidecar index keyed by KZG versioned hash, returns V1 `blob`/`proof`
objects in request order, preserves `null` for missing blob data, advertises
the capability, and rejects over-128 blob requests with Engine `Too large
request` error code `-38004`. The same memory index now also accepts Osaka
cell-proof sidecars with 128 proofs per blob and serves
`engine_getBlobsV2`/`engine_getBlobsV3`: V2 returns a full ordered
`blob`/`proofs` list only when every requested blob is available and otherwise
returns `null`, while V3 keeps request order and allows per-item `null`
partial responses. The first public `eth_*` read methods are now wired through
the same JSON-RPC dispatcher: `web3_clientVersion` returns the local client
identity string, `web3_sha3` computes Keccak-256 over supplied hex bytes,
`net_version` returns the configured network id as a decimal string, and
`net_listening`/`net_peerCount` report the current non-networked local node
state as JSON `false` and `0x0`,
`eth_chainId` returns the configured EIP-155
chain id, `eth_blockNumber` returns the current forkchoice head number with a
memory-store maximum fallback,
`eth_protocolVersion` reports the current highest supported devp2p `eth`
protocol as `0x46`/ETH70,
`eth_syncing` returns JSON `false` for the current local non-networked
memory-store execution node, `eth_accounts` returns an empty local-wallet
account list until wallet support exists, `eth_coinbase` returns the zero
address for the current non-mining local node, `eth_mining` reports JSON
`false` and `eth_hashrate` reports `0x0` for that non-mining mode,
`eth_baseFee` estimates the
next block's EIP-1559 base fee from the current memory-store head,
`eth_maxPriorityFeePerGas` exposes the current deterministic local tip
suggestion, and `eth_gasPrice` combines that tip with the current head base fee
when present for legacy transaction callers;
`eth_blobBaseFee` exposes the current head blob base fee when Cancun blob-gas
fields are present, and `eth_feeHistory` now returns a first memory-store fee
history window with base fee progression, gas-used ratios, optional blob fee
history, retained forkchoice `latest`/`pending` head-tag resolution plus
`safe`/`finalized` checkpoints, and zero-filled reward percentile placeholders
until transaction reward accounting is indexed,
`eth_getBalance` can read retained per-block account balance snapshots by
block tag, number, or hash while returning `null` when the block or retained
state is unavailable, `eth_getTransactionCount` does the same for retained
account nonce snapshots and now folds local pending txpool transactions into
the `"pending"` nonce result, `eth_getCode` returns retained account bytecode
snapshots with empty code for missing accounts, `eth_getStorageAt` reads
retained account storage slot snapshots as 32-byte words with zero words for
missing accounts/slots, `eth_call` executes a first legacy-style call object
against retained block state, returning EVM output/revert data while discarding
state writes, `eth_estimateGas` reuses that retained-state simulation to cap
estimates by the block/request gas limit, reject reverting calls, and
binary-search a first simple transfer/contract-call gas result,
`eth_createAccessList` surfaces touched accounts/storage keys from the same
simulation as a first geth-shaped `accessList`/`gasUsed` result, and
`eth_getHeaderByNumber`/`eth_getHeaderByHash` can return canonical memory-store
headers for `latest`, `pending`, `safe`, `finalized`, `earliest`, hex block
quantities, or block hashes, with `safe`/`finalized` following retained
forkchoice checkpoints when present, using the geth-style header object shape while
returning JSON `null` for unknown blocks. `eth_getBlockByNumber`/`eth_getBlockByHash` now handle both the
transaction-hash form (`fullTx=false`) and full mined transaction object form
(`fullTx=true`) for memory-store blocks, adding block size, ommer hashes, and
Shanghai withdrawals while returning `null` for unknown block ids. The matching
`eth_getBlockTransactionCountByNumber` and
`eth_getBlockTransactionCountByHash` read endpoints now return transaction
counts for canonical memory-store blocks and JSON `null` for unknown blocks.
`eth_getUncleCountByBlockNumber` and `eth_getUncleCountByBlockHash` likewise
return ommer counts from the in-memory block body with the same unknown-block
`null` behavior. `eth_getUncleByBlockNumberAndIndex` and
`eth_getUncleByBlockHashAndIndex` can now return header-only ommer block
objects from memory-store blocks, with JSON `null` for unknown blocks and
out-of-range ommer indexes. Raw transaction lookup by block id and index is now present
for both `eth_getRawTransactionByBlockNumberAndIndex` and
`eth_getRawTransactionByBlockHashAndIndex`, returning consensus transaction
bytes or JSON `null` for unknown blocks and out-of-range indexes. The
structured companions `eth_getTransactionByBlockNumberAndIndex` and
`eth_getTransactionByBlockHashAndIndex` now return mined transaction RPC
objects with block location metadata, effective gas price, typed transaction
fee/access-list fields, and the same unknown/out-of-range `null` behavior.
The in-memory payload store now also indexes transactions by hash as blocks are
inserted, enabling `eth_getTransactionByHash` and `eth_getRawTransactionByHash`
for known canonical memory-store transactions with JSON `null` for unknown
hashes. Receipts supplied with memory-store blocks are retained alongside that
transaction index, enabling `eth_getTransactionReceipt` with mined receipt
metadata, gas accounting, logs, logs bloom, typed transaction status, and
effective gas price. `eth_getBlockReceipts` now exposes the same retained
receipt objects by block tag, number, or hash for known memory-store blocks;
`eth_getLogs` can scan retained memory-store receipts by block range or
`blockHash`, address filter, and positional topic filters, returning canonical
log objects and empty JSON arrays for no matches. The first stateful log
filter methods are also present: `eth_newFilter` registers memory-store log
criteria, `eth_getFilterLogs` replays the matching retained logs,
`eth_getFilterChanges` advances a per-filter log cursor for polling retained
block logs, `eth_newBlockFilter` registers a head cursor for polling newly
retained block hashes through the same changes endpoint, and
`eth_newPendingTransactionFilter` registers a pending transaction hash queue
for locally submitted pending transactions. `eth_uninstallFilter` removes
registered filters while returning false for unknown ids. `eth_sendRawTransaction` now
decodes raw transaction bytes, records the decoded transaction in a local
pending-transaction placeholder, and returns the transaction hash; locally
submitted pending raw bytes are also visible through
`eth_getRawTransactionByHash`, while `eth_getTransactionByHash` now returns a
geth-style pending transaction object with null block location metadata for
those locally submitted transactions; duplicate submissions of the same
pending hash are idempotent and do not emit duplicate pending-filter changes,
while a later retained block containing the same transaction hash removes the
local pending placeholder so mined lookup metadata takes over, and resubmitting
that mined raw transaction returns its hash without re-adding it to the pending
pool. `eth_pendingTransactions` exposes the
same local pending placeholder as a deterministic hash-sorted array of pending
transaction objects, and `txpool_status` reports the local pending count with
zero queued transactions until a queued pool exists. `txpool_content` now
exposes the same local pending transactions grouped by sender address and
decimal nonce, with an empty queued object placeholder; `txpool_contentFrom`
returns the same nonce-keyed pending/queued shape filtered to one sender
address, and `txpool_inspect` exposes a matching sender/nonce grouping with
geth-style human-readable transaction summaries. Full txpool admission rules
remain a later networking/txpool slice, but raw local submissions now run a
basic admission preflight for fork transaction type support, scalar/fee/nonce
shapes, intrinsic gas, access-list/blob/set-code field shapes, and
non-delegation sender code before entering pending. When the latest head has
retained account state, raw submissions also reject transactions below the
retained sender nonce and insufficient retained sender balance for the
maximum upfront execution/blob gas plus value. Same-sender same-nonce pending
replacements now follow a geth-style 10% fee bump policy, replacing the
indexed transaction only when both fee cap and priority fee clear the bump
threshold. The txpool object now also has queued, basefee, and blob placeholder
subpools, and `txpool_*` RPC views read queued data from the queued subpool
instead of hard-coded empty placeholders. Public JSON-RPC and txpool
placeholder handlers have also been split out of `src/core.lisp` into
`src/public-rpc.lisp` behind a dedicated public method dispatcher, leaving the
core RPC path focused on the generic JSON-RPC envelope, Engine/Public dispatch
delegation, and HTTP serving shell.
Filter lifecycle scope is intentionally polling-only for now. The current
filter ids belong to the JSON-RPC polling methods (`eth_newFilter`,
`eth_newBlockFilter`, `eth_newPendingTransactionFilter`,
`eth_getFilterChanges`, `eth_getFilterLogs`, and `eth_uninstallFilter`) and
represent in-memory cursors or pending hash queues. Future WebSocket
subscriptions should use a separate subscription registry and transport-owned
lifetime: subscription ids are created by `eth_subscribe`, removed by
`eth_unsubscribe` or connection close, and should stream events without
advancing polling filter cursors. Before subscriptions land, the polling
filter store should gain explicit timeout/cleanup policy compatible with
geth-style filter expiry, while keeping `eth_uninstallFilter` idempotent for
unknown or expired polling ids.
A first HTTP POST adapter now
validates request method and JSON content type before handing the body to the
shared JSON-RPC dispatcher. The HTTP adapter can also enforce Engine-style JWT
Bearer authentication with HS256 signatures, 32-byte secrets, `iat` freshness,
and optional `exp` rejection. A single-connection stream adapter now reads one
HTTP request from an input stream and writes the response to an output stream,
and an Engine HTTP service configuration object now bundles the authenticated
endpoint defaults, payload store, chain config, JWT secret, and clock provider,
while a small listener/connection accept loop can now serve repeated stream
connections and close them deterministically. The outer local transport shell is
now present for SBCL: a `sb-bsd-sockets` TCP listener adapts localhost socket
connections into the same stream service and is covered by an end-to-end
JSON-RPC socket test.

Networking, discovery, and txpool sophistication are intentionally later than
deterministic execution correctness.

Future node shell and network work should start from a narrow architecture
slice rather than a full peer-to-peer client. The first devp2p milestone is to
model identities and advertised capabilities: local node key, ENR fields,
listening endpoints, fork id, supported `eth`/`snap` protocol versions, and
chain identity. Discovery should come next as an isolated table/update path
that can parse and persist candidate ENRs before any RLPx session is trusted.
Only after that should RLPx handshakes, `eth` status exchange, block/header
requests, transaction propagation, `snap` state range requests, and peer
scoring be wired into sync or txpool code. Peer scoring should begin with
small deterministic penalties for bad status, invalid responses, timeout, and
duplicate useless data, leaving reputation persistence and DoS policy for a
later production-storage slice.

The first sync design should follow a staged pipeline with explicit unwind
boundaries. A minimal full/snap-compatible plan is: header download and
validation; canonical header selection; body download; sender recovery;
execution into an isolated state batch; receipt/log derivation; canonical
transaction/receipt/log indexes; and final forkchoice checkpoint publication.
Each stage needs a persisted progress marker and an unwind function that can
roll back to a parent block when forkchoice changes or execution fails. Snap
sync can later replace the early execution-state population with account and
storage range ingestion, but it should still feed the same execution,
receipt, and index stages once state is available.

Hive compatibility should be treated as a runner contract around the local
node shell. The client needs a command that loads a supplied genesis, starts
authenticated Engine API and public JSON-RPC listeners on requested ports,
prints machine-readable endpoint/JWT/log locations, and shuts down cleanly on
process termination. Hive-facing logs should include startup config, fork
activation, Engine payload status, JSON-RPC method errors, and final shutdown
state without requiring interactive REPL access.

History retention should be explicit before any pruning implementation. Archive
mode keeps all historical state, receipts, bodies, logs, and indexes. Full mode
keeps all canonical block bodies and receipts but may keep only recent state
snapshots plus enough trie/storage history for configured reorg depth. Pruned
mode may drop historical state and old receipts/log indexes beyond a retention
window, but public RPC methods that depend on dropped data must return the same
class of missing-data/null/error responses consistently. `eth_getProof`,
historical `eth_call`, historical balance/storage/code reads, log scans,
receipts, and transaction lookups must each declare which retention modes they
support before pruning is enabled.

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
