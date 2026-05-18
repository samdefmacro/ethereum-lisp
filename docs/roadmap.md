# Roadmap

The goal is a Common Lisp Ethereum execution-layer client. The work is split
into milestones that can be validated independently.

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
`Nethermind.Core/Crypto`.

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

Validation targets: geth `core/types`, Nethermind `Nethermind.Core`.

Status: first pass for accounts, legacy tx, EIP-2930 tx, EIP-1559 tx,
EIP-4844 blob tx envelope encoding/hashing, EIP-7702 set-code tx envelope
encoding/hashing, legacy EIP-155 signing hash and sender recovery, and
EIP-2930/EIP-1559/EIP-4844/EIP-7702 typed signing hash plus sender recovery;
EIP-7702 authorization tuple authority recovery is also present. Blob
sidecars now have a first-pass data shape and commitment-to-versioned-hash
validation layer; actual KZG proof verification remains. Set-code execution
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
and `Nethermind.State`.

Status: minimal in-memory root calculation, code storage, snapshot/restore, and
secure state root prototype are implemented. The minimal legacy transfer spine
now avoids creating empty zero-value recipients and preserves value balance for
self-transfers. Proofs, persistence integration, deletion edge cases, and
fixture compatibility remain.

## 4. EVM

- stack, memory, gas accounting, execution frames
- opcode table by fork
- arithmetic, bitwise, environmental, memory, storage, flow, call, create, log
- refunds and warm/cold access rules
- precompiles
- EOF support when required by activated forks

Validation targets: geth `core/vm`, Nethermind `Nethermind.Evm`.

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
each pair contains a zero/infinity element; G2 pairing inputs now receive
first-pass field-coordinate and twist-curve validation for those skipped
pairs, with oversized-coordinate and off-curve failure coverage. BLAKE2F is present for
EIP-152 valid and malformed-input paths. The Cancun KZG point-evaluation
precompile address is now recognized with the fixed 50,000 gas cost, 192-byte
input length validation, and versioned-hash/commitment mismatch failure
coverage; actual KZG proof verification remains.
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

Validation targets: geth `core`, Nethermind `Nethermind.Consensus`.

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
declared by the blob transaction.
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

- pluggable key-value database
- freezer/history abstractions
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

Status: initial local Engine payload projection is present. Blocks can be
converted into geth-shaped `ExecutableData` payload envelopes, including
header fields, encoded transactions, optional withdrawals, optional execution
requests, blob gas counters, and Amsterdam slot numbers. JSON-RPC transport and
`newPayload` status handling remain. The reverse raw-transaction path has begun
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
parameter gates now cover V1 through V5 fork requirements before block import.
A small in-memory Engine payload store now models known-block, missing-parent,
missing-parent-state, and invalid-ancestor status branches for the future
database-backed import path.

Networking, discovery, and txpool sophistication are intentionally later than
deterministic execution correctness.

## 8. Compatibility Harness

- Ethereum execution-spec-tests fixture runner
- RLP/trie/blockchain fixtures
- cross-check selected fixtures against geth and Nethermind outputs
- CI entry points for SBCL

## Working Principle

Each milestone should leave the repository in a runnable state. We build
consensus-critical behavior before ergonomics, and keep APIs small until tests
make the next abstraction obvious.
