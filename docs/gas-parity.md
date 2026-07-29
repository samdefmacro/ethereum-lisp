# Gas Parity

This document records the results of a three-part comparison of this client's
gas accounting against go-ethereum, Nethermind, and `ethereum/execution-specs`,
and lays out an ordered plan to close the gaps it found.

Nothing in the plan has been implemented. Every item below describes work that
remains to be done; no statement here should be read as a claim that a fix is
in the tree. The findings themselves are a snapshot of the code at commit
`28e9912072135bebc3f49bc75226d6fed68dc21f`, and the line numbers cited are
relative to that commit — function names are the durable identifier, so prefer
them when a line has moved.

Remediation update (2026-07-29): `gap/evm-gas` closes item 4.3's account
predicate and item 5.5's corrected EIP-7954 code/initcode limits. It also adds
Amsterdam opcode and transfer-log coverage, typed KZG backend refusal, Prague
delegation gating, per-frame jump analysis, geometric EVM memory growth, and an
O(1) stack-depth guard. The broad fork-aware gas schedule in item 4.1 and
Amsterdam EIP-8037/8038 multidimensional gas are still open; the latter keeps
Amsterdam Engine capability advertisement and dispatch disabled. The detailed
status and dependency boundary are in `docs/gap-analysis/evm-and-gas.md`.

The most important thing a reader can take from this document is not the fix
list but the section on what is already correct. Several apparent bugs in this
client are deliberate or harmless, and one of them is the sort of thing a
well-meaning contributor would "fix" into a genuine consensus divergence.

## Scope and provenance

Three audits split the gas surface between them and worked in parallel. The
opcode audit covered everything charged inside the interpreter loop for an
individual instruction: constant base costs, dynamic gas, the call and create
families, EIP-2929 account warming, the `GAS` opcode, out-of-gas ordering, and
integer semantics. The storage and precompile audit covered `SLOAD`/`SSTORE`
cost and refunds, EIP-2930/2929 access-list warming and journaling, EIP-1153
transient storage, EIP-6780 `SELFDESTRUCT`, and the gas formula of every
precompile the client implements. The transaction, block, and RPC audit covered
intrinsic gas, transaction gas settlement, receipts and cumulative gas,
block-level gas and fee-market fields, blob gas, block building, and the gas
RPC surfaces.

Each audit worked the same way: read the corresponding upstream code, then
exercise this client's equivalent inside a warm dev image and compare concrete
numbers. Several results are differential tests against a transcription of the
upstream formula rather than single spot checks, and those are the strongest
evidence in the whole exercise.

### Reference versions

The audits ran independently and did not coordinate their pins. This matters
enough that it is recorded per audit rather than flattened:

| Audit | go-ethereum | Nethermind | execution-specs |
| --- | --- | --- | --- |
| Opcode / interpreter | `v1.17.5` (`9621c6ad10934a01b5514886fb6fbd87640b6c05`) | `1.39.2` (`6568910591e4618dc49d54285b6213c3753d7243`) | not read |
| Storage / precompiles | `v1.16.3` (tag; commit hash not recorded) | `1.34.1` (`c4238a37787abd95cc849aa817ffa9a6eef567dd`) | `master`, unpinned, fetched 2026-07-28 |
| Transaction / block / RPC | `v1.16.6` (`386c3de6c45f3e185279e6760a17f88fb98dc81a`) | `master` @ `e52dc19a56a46f58170a730822580774d403c838` | `master` @ `85a36ccae03b0958d9bfb0a6e6d9e08f0e5c79db` |

The opcode audit additionally read EIP-7907 from `ethereum/EIPs@master` while
that EIP was in `Draft` status, fetched 2026-07-28. EIP texts consulted for
rounding details across the three audits were 198, 1108, 1153, 1283, 1706,
2200, 2537, 2565, 2929, 2930, 3529, 3651, 4844, 6780, 7702, 7823, 7883, 7907,
and 7951.

There is no `references/` checkout on this machine (see `docs/reference-map.md`),
so upstream sources were fetched over the network into scratch space for the
duration of the audits. That scratch space is not durable and the copies should
not be assumed to exist.

### The mixed-version problem

`PROJECT.md` requires that a parity claim name the exact version and the code
path exercised. Each finding below therefore carries the version it was
actually read against, and no finding should be quoted as parity with "geth"
unqualified. Three different geth versions, three different Nethermind
versions, and two different execution-specs heads — one of them an unpinned
branch — are enough spread that a behavior could have changed upstream between
`v1.16.3` and `v1.17.5` without any audit noticing.

That is not hypothetical. Re-checking the audits' citations turned up exactly
one case where the geth version read determined the conclusion, and the
conclusion was wrong (see "One negative result that did not survive
re-checking"). Re-verifying every finding against a single pinned reference
version is therefore itself a task in the plan, not a formality — it is item
3.4.

## Reading a finding: verified versus inferred

Each audit separated what it confirmed by running code from what it concluded
by reading, and that distinction is preserved here. A finding marked *verified*
has concrete numbers from both sides: this client's number came out of a warm
image, and upstream's came from either a transcription of the upstream formula
or hand-evaluation of the upstream source. A finding marked *inferred* means
the upstream source was read and the divergence follows from it, but nothing
was executed on one or both sides. Inferred findings are not weaker in
confidence for structural claims — the absence of a `chain-rules` parameter in
a function signature is conclusive on its own — but they have not been reduced
to a pair of differing integers, so the exact magnitude of the divergence is
not pinned.

Do not upgrade an inferred finding to a verified one when carrying it forward
into a commit message or a changelog entry.

## Confirmed correct — and things that look wrong but are not

### Differentially tested and matching

The following were checked against a transcription of the upstream formula over
a generated input space, not spot-checked:

The EIP-1559 base fee (`expected-base-fee-per-gas` in
`src/protocol/consensus/validation.lisp`) matched geth's `CalcBaseFee` on 20,000
random `(gasLimit, gasUsed, baseFee)` triples with zero mismatches, and
`fake_exponential` (`src/protocol/consensus/block-validation/fees.lisp`) matched
on 1,600 random `(excess, updateFraction)` pairs across the Cancun,
Prague/Osaka, BPO1 and BPO2 fractions. Both implementations combine two
successive upstream divisions into one, which is identical by the floor
identity `floor(floor(x/a)/b) = floor(x/(a·b))`.

`MODEXP` pricing (EIP-198, EIP-2565, EIP-7883, EIP-7823) matched a transcription
of geth's `bigModExp.RequiredGas` on **24,775** generated
`(baseLen, expLen, modLen, expHead)` shapes covering every rounding boundary —
lengths 0, 1, 31, 32, 33, 64, 1023, 1024, 1025, exponent heads with bit lengths
0 through 256, and randomised combinations — across all three pricing regimes,
with zero mismatches. This confirms the `iteration_count` clamp, the
`adjusted_exp_len` split at `expLen > 32`, the Berlin ceiling-division of
`multiplication_complexity`, EIP-7883's 500-gas minimum, and its `words² × 2`
branch for `maxLen > 32`.

The `SSTORE` composition of EIP-2200 with EIP-2929 (`sstore-dynamic-gas` in
`src/runtime/evm/storage-gas.lisp`) matched a transcription of geth's
`gasSStoreEIP3529` and `SstoreClearsScheduleRefundEIP3529` on all **78** state
transitions of `original × current × new × warm/cold`, including double-writes,
clear-then-restore, and reset-to-original, exactly on both gas and refund. The
`SstoreResetGasEIP2200 − ColdSloadCostEIP2929` term and the
`WarmStorageReadCostEIP2929` branches are therefore confirmed, as is the
EIP-2200 sentry check against remaining gas.

Both BLS12-381 MSM discount tables were diffed against
`Bls12381G1MultiExpDiscountTable` and `Bls12381G2MultiExpDiscountTable` entry by
entry: **identical across all 128 entries each**, including the G2 table's
genuinely duplicated `1000, 1000` opening, which looks like a typo but is what
both upstream and the EIP specify. The computed MSM gas then matched a
geth-derived formula on 817 input lengths per curve, covering every valid `k`
from 1 to 200 plus malformed lengths and `k` above the table bound.

### Verified by targeted execution and matching

Berlin-and-later opcode costs are correct throughout the interpreter. Every
entry in `opcode-base-gas` matches the Cancun/Osaka schedule, including the
easily-mistaken ones (`CLZ` 5, `MCOPY` 3, `BLOBHASH` 3, `BLOBBASEFEE` 2,
`TLOAD`/`TSTORE` 100, `PUSH0` 2, `SELFBALANCE` 5), and every gas constant in
`src/runtime/evm/types.lisp` matches `params/protocol_params.go`. Memory
expansion implements `3·words + words²/512` with ceiling word rounding exactly
as `memoryGasCost` does, with zero-size regions contributing nothing regardless
of offset. Dynamic word costs for `KECCAK256`, the `LOG` family, and the copy
family all match. `EXP` is the one dynamic cost in the interpreter that is
already fork-correct. The create family is correct on CREATE2 hash cost,
EIP-3860 initcode word cost at both 2 and 8 per word, the Shanghai-gated 49,152
initcode limit, 200-per-byte code deposit, and EIP-3541's `0xEF` rejection
ordering. The call family reproduces geth's `gasCallIntrinsic` plus `callGas`
arithmetic end to end at Berlin, including the 2300 stipend being added to the
child without being charged to the parent.

Gas arithmetic runs on bignums throughout, so there is no truncation or
wraparound to find: `MSTORE` and `MLOAD` at offset `2^256-1`, and `KECCAK256`
with size `2^256-1`, all produce an ordinary out-of-gas rather than an
arithmetic error or a heap exhaustion, reaching the same outcome geth reaches
through `ErrGasUintOverflow`. Gas is charged before any allocation.

Access-set journaling on revert is correct: a child that warms an address and
then reverts leaves that address cold, while the callee itself stays warm,
because the callee is warmed by the gas function before the child snapshot is
taken. EIP-6780 created-address marking runs after the snapshot and is
correctly un-marked by a revert while the address stays warm. EIP-1153
transient storage costs 100 each way with no refund interaction, is a fresh
table per transaction, and is restored on revert. The EIP-2930/3651 pre-warming
set matches geth's `Prepare` call, and the number of pre-warmed precompiles
equals geth's `ActivePrecompiles` count at Byzantium, Istanbul, Berlin, Cancun,
Prague, and Osaka.

EIP-3529 constants match digit for digit, the refund is capped at `gasUsed/5`,
and — this ordering is easy to get wrong — the cap is applied *before* the
EIP-7623 calldata floor, matching geth's `calcRefund`-then-clamp sequence. A
Prague transaction with 100 non-zero calldata bytes bills 25,000 where intrinsic
is 22,600; the same transaction on Cancun bills 22,600.

`SELFDESTRUCT` under EIP-6780 and EIP-3529 is correct: flat 5000 plus a cold
beneficiary surcharge of 2600 and `CallNewAccountGas` of 25,000 when the
beneficiary is empty and the contract's balance is non-zero, and no refund. The
remaining precompiles are correct: `ECRECOVER`, `SHA256`, `RIPEMD160` and
`IDENTITY` word costs; BN254 under EIP-1108 including the floored pairing
division that prices a malformed length and then fails; `POINT_EVALUATION` at a
flat 50,000; `P256VERIFY` at a flat 6900 charged whether or not the signature
verifies. Precompile gas-charging order matches, with an out-of-gas boundary
that is exact at `required == supplied` and fails at `required == supplied + 1`.

On the transaction and block side: gas-limit bounds validation is a
character-for-character match for `misc.VerifyGaslimit`; `gasUsed <= gasLimit`
is enforced; the up-front gas purchase splits into geth's `mgval` and
`balanceCheck` exactly, including blob gas; refund payout and coinbase tip
match `returnGas` and the `effectiveTip` computation, with blob gas burned and
never refunded; the block gas pool check is equivalent to geth's
`gp.SubGas(tx.Gas())`; cumulative gas and receipt derivation hold the
"derived, not trusted" line on the Engine import path; EIP-7702's 25,000
intrinsic per tuple and 12,500 refund for an existing authority match; the
non-EIP-7918 excess-blob-gas rule and the blob-gas header shape rules match;
and `eth_blobBaseFee` correctly uses the head header's own blob schedule.

### Structural differences with identical outcomes

These are real differences from upstream that a reader will notice and should
leave alone, because the consensus outcome is identical in each case.

`step-evm-machine` charges an instruction's base cost before the handler pops
its operands, and the 1024-entry stack limit is enforced on push, whereas geth
validates `minStack`/`maxStack` before calling `UseGas`. An `ADD` with 2 gas and
an empty stack therefore reports out-of-gas where geth reports stack underflow.
Both are exceptional halts that consume all remaining gas and revert the frame,
so only the error string and the tracer output differ. The same argument covers
the internal ordering of memory-expansion gas against access and value gas
inside the message-call path, and initcode word gas against memory gas inside
`CREATE`.

`BLAKE2F` returns no required gas for a malformed input length, so nothing is
charged up front and the precompile then fails and burns the whole child gas
limit; geth returns zero from `RequiredGas` and errors in `Run`, zeroing
remaining gas in `evm.Call`. Identical observable result. EIP-7823's 1024-byte
`MODEXP` length cap is likewise enforced in `validate-modexp-input-lengths`,
reached from `precompile-required-gas`, where geth enforces it in `Run` — again
both consume all supplied gas.

`apply-refund-counter-to-receipt` applies a refund only when the counter is
positive, so a negative total silently becomes no refund, where geth's
`SubRefund` panics on a counter below zero. The audit could not construct a
bytecode sequence producing a negative total and argued that none exists: the
counter is per-frame, and every `-4800` decrement is guarded by a
`cleared-storage-slots` entry that only a preceding `+4800` in the same context
can set. That argument is *inferred, not executed*. The recommended action is
therefore to add an assertion so a future refactor that does break the
invariant fails loudly, not to change any number. Relatedly, the
`cleared-storage-slots` guard on the `-4800` path is redundant but equivalent to
geth's unconditional `SubRefund`, and should not be removed on the assumption
that it is dead code.

Two findings look like they contradict each other and do not. The opcode audit
reports that `empty-account-p` wrongly includes a storage-root term, measuring a
`SELFDESTRUCT` beneficiary surcharge of 0 where upstream charges 25,000; the
storage audit reports `SELFDESTRUCT` gas as verified correct at 32,603. Both
are right — they used different account shapes. The storage audit's beneficiary
was genuinely empty; the opcode audit's had a storage slot set with no code, a
shape only genesis allocations or EIP-7610-style pre-existing storage produce.
The predicate bug is item 4.3; the ordinary path is correct.

### One negative result that did not survive re-checking

The opcode audit reported that this client applies the EIP-170 24,576-byte
deposited-code-size limit at every fork, and concluded that this *matches* geth
because geth's `CheckMaxCodeSize` has no EIP-158 gate — recording it explicitly
so that it would not be mistaken for a bug later.

That conclusion is wrong, and re-reading the fetched reference copy is what
showed it. In geth `v1.17.5`, `CheckMaxCodeSize` (`core/vm/common.go:42-54`)
reads `if rules.IsAmsterdam { … } else if rules.IsEIP158 { … }` and returns nil
when neither holds, and every call site in `initNewContract` goes through it.
Geth `v1.16.3`, before the helper was extracted, has the gate inline as
`if evm.chainRules.IsEIP158 && len(ret) > params.MaxCodeSize`. Both versions
gate on EIP-158, as Nethermind's `CodeDepositHandler` does via
`spec.LimitCodeSize`, and as the EIP-170 text and `execution-specs` do.

This client does not. `invalid-created-runtime-code-p`
(`src/runtime/evm/create.lisp:41-46`) compares against
`chain-rules-contract-code-size-limit` in
`src/protocol/chain-config/rules.lisp:9-12`,
which varies only at Amsterdam and has no EIP-158 branch — so the 24,576-byte
limit applies at Frontier, which the audit itself measured.

So this is a real divergence rather than a match. It stays very low priority
for a different reason: depositing 24,577 bytes costs 4,915,400 gas in deposit
charges alone, above the mainnet block gas limit in force when EIP-170 activated
— under five million at the time — so the case is unreachable in the historical
range where the missing gate would matter. It joins the pre-Berlin cluster as
item 4.7. The lesson worth carrying is the one
in "The mixed-version problem": a parity claim resting on one version's
refactored helper needs the version named and the branch quoted.

## Remediation plan

Tiers are ordered by reachability on the forks this client actually targets,
then by severity. Effort estimates are the audits' own and are rough. The
dependency table at the end of this section collects the couplings.

### Tier 1 — consensus-breaking and reachable on targeted forks

These three produce a different `gasUsed`, receipt root, and state root than
upstream on forks this client models and intends to execute. Each is small.

**1.1 — EIP-7702: the delegation target of `tx.to` is never warmed.**
`transaction-accessed-addresses-table` (`src/runtime/execution/access.lisp:16-35`)
pre-warms precompiles, sender, destination, coinbase from Shanghai, access-list
addresses, and authorization authorities. It never warms the delegation target
of `tx.to`. `execution-resolved-code` (`src/runtime/execution/state.lisp:30-35`)
resolves the delegation for execution but does not touch the access set. Geth
`v1.16.6` warms it in `core/state_transition.go:509-516`, and critically that
block sits *outside* the `if msg.SetCodeAuthorizations != nil` guard that closes
at line 507 — so it applies to any non-create transaction whose `tx.to` holds a
delegation designator, including a plain legacy transfer. `execution-specs`
does the same in `prague/vm/interpreter.py:126-134`. *Verified:* a transaction
to an EOA delegated to a contract whose code reads its own delegation target's
balance produced `cumulativeGasUsed` 23,605 here (21000 + 3 + **2600 cold** + 2)
against upstream's 21,105 (21000 + 3 + **100 warm** + 2) — a 2500-gas
divergence. The `CALL`-opcode path is a control and is correct.

The fix warms `set-code-delegation-target` of the destination, with no gas
charge. Prefer to do it immediately before execution in `apply-message` rather
than inside the access table: geth resolves the delegation *after* applying
authorizations, so a transaction that installs a delegation on its own target
still warms correctly, and building the table earlier cannot see that. Verify
with a unit test asserting 21,105 for the probe shape above, and re-run the
existing EIP-7702 call-path tests to confirm the control case is unchanged.
Effort: about an hour plus the test.

**1.2 — EIP-7702: invalid authorization tuples warm their authority too early.**
`access.lisp:28-34` warms every authority that recovers, with a comment stating
that this happens "even when the tuple is later found invalid". There is no
chain-ID check and no nonce-overflow check on this path. Geth `v1.16.6`
(`core/state_transition.go:573-592`) returns on `ErrAuthorizationWrongChainID`
and on `ErrAuthorizationNonceOverflow` *before* reaching
`AddAddressToAccessList(authority)`; the "added even if invalid" comment at
line 591 refers only to the later destination-has-code and nonce-mismatch
checks. `execution-specs` has the identical ordering in
`prague/vm/eoa_delegation.py:167,170,178`. *Verified:* a tuple declaring
`chain_id = 1337` on a chain-ID-1 transaction leaves its authority warm here,
as does a tuple with `nonce = 2^64-1`; both are cold upstream, so any later
`CALL`, `BALANCE`, or `EXTCODE*` on that address costs 100 here against 2600
upstream.

The fix gates warming on `auth.chain_id ∈ {chain_id, 0}` and on
`nonce < 2^64-1`, while continuing to warm authorities whose tuples fail the
destination-has-code or nonce-mismatch checks. `chain_id = 0` is a legitimate
wildcard upstream and must keep warming. The reason these checks are absent is
structural: `transaction-accessed-addresses-table` takes `chain-rules` but no
chain id, so the value is not available to it. It has exactly one caller
(`src/runtime/execution/context.lisp:43-47`), and the chain id is already in
scope there — the same `let` binds `:chain-id chain-id` into the EVM context at
line 35 — so threading it is a one-line change at the call site plus a new
keyword parameter. Verify with two unit tests asserting the authority is cold
for a chain-ID mismatch and for a nonce overflow, and two asserting it stays
warm for the wildcard and for the two later failure kinds. Effort: about two
hours plus tests.

**1.3 — EIP-7918 uses the parent's blob-base-fee update fraction.**
`expected-excess-blob-gas`
(`src/protocol/consensus/block-validation/fees.lisp:55-86`) evaluates the
EIP-7918 reserve-price comparison with `parent-update-fraction`, which
`validate-block-header-against-config`
(`src/protocol/consensus/block-validation/header.lisp:183-203`) resolves from
the parent's timestamp. The comment at `fees.lisp:66-70` asserts that using the
child's fraction would split the chain. Both references do the opposite: geth
`v1.16.6`'s `CalcExcessBlobGas` resolves `latestBlobConfig(config, headTimestamp)`
— the child's schedule — and `execution-specs` Osaka's
`calculate_excess_blob_gas` calls `calculate_blob_gas_price`, which resolves the
current fork's `BLOB_BASE_FEE_UPDATE_FRACTION`. The comment's rationale is
inverted. *Verified:* a parent with `excessBlobGas = 90,000,000`,
`blobGasUsed = 1,310,720`, and `baseFeePerGas = 1 gwei`, with a child on BPO1
(target 10, max 15, fraction 8,346,193), yields 90,000,000 here and 90,436,906
in both references. The branch flips because
`blobBaseFee(90e6, 5_007_716) = 63,863,924` exceeds the `baseFee/16 = 62,500,000`
reserve threshold while `blobBaseFee(90e6, 8_346_193) = 48,211` does not — the
same parent header therefore admits two different valid-looking children.

This can only bite at a fork boundary that changes the update fraction while
EIP-7918 is active, which means the BPO transitions. Prague→Osaka is safe, and
this was verified rather than assumed: both share target 6, max 9, and fraction
5,007,716 in this client's schedule. Osaka→BPO1 and later are not safe, and
BPO1 through BPO5 constants and timings already exist in the config, so this is
reachable as soon as a BPO fork activates. The fix switches the comparison to
the child's fraction and corrects the comment, and must also be applied to
`build-payload-excess-blob-gas` (`src/protocol/engine-payloads/build.lisp:49-70`)
and `eth-rpc-fee-history-next-blob-base-fee`
(`src/api/public/metadata/fee-history.lisp:107-128`), which make the same
choice. Verify with a BPO-boundary test using the numbers above; the existing
`eth-rpc-fee-history-next-blob-base-fee-applies-eip7918` test exercises only a
single-fork case and will not catch it. Effort: about an hour plus the test.

### Tier 2 — not consensus, but breaks this node in practice

**2.1 — The EIP-7623 floor is missing from estimation, admission, and payload
building.** These three are one fix, because separately each looks minor and
together they are a self-inflicted denial of block production on Prague.

`eth_estimateGas` returns values this same node's execution then rejects. The
simulation path `execute-message-call`
(`src/runtime/execution/call-simulation.lisp:125-240`) never computes the
floor: it binds no `*transaction-floor-gas*`, never calls
`transaction-effective-floor-gas`, and `validate-call-transaction-fields`
(`src/runtime/execution/validation.lisp:46-62`) checks only
`gasLimit >= intrinsic`. The binary search then seeds its lower bound at the
intrinsic gas (`src/api/public/state/gas.lisp:67`), so nothing lifts the answer
to the floor. *Verified end to end:* against a Prague-configured store,
`eth_estimateGas` for a call carrying 100 non-zero calldata bytes returned
`0x5848` (22,600) with no error, where the floor for that calldata is 25,000 —
and `execute-message-call` at `gasLimit = 22600` reports success while
`apply-message` on the same transaction raises "Gas limit below intrinsic gas".
Geth's estimator never probes below the floor because it seeds `lo` from a run
at `hi` whose `UsedGas` has already been raised to `floorDataGas`, and it
deliberately does not treat `ErrFloorDataGas` as retryable.

The txpool has the matching hole. `validate-txpool-admission`
(`src/application/services/txpool-admission.lisp:125-132`) checks
`gasLimit >= transaction-intrinsic-gas` and, separately, the EIP-7825 cap at
lines 138-143 — so the omission is specifically the floor. Geth's
`ValidateTransaction` rejects `tx.Gas() < FloorDataGas(tx.Data())` under Prague;
Nethermind folds the same rule into `MinimalGas = max(Standard, FloorGas)`.

The third part is what turns an admission bug into an outage. The payload
builder selects pooled transactions (`src/api/engine/forkchoice.lisp:162-174`)
and then executes the whole block. One admitted below-floor transaction makes
`charge-sender-upfront` raise, which aborts the entire payload build and
surfaces as an `invalid payload attributes` Engine error rather than skipping
the transaction. Geth's miner skips a failing transaction and keeps building.
A wallet using this node's own `eth_estimateGas` will submit exactly such a
transaction, so the loop closes on itself.

The fix has three parts. Make the simulation path floor-aware, by binding
`*transaction-floor-gas*` or returning the floor alongside the gas, rejecting
`gasLimit < max(intrinsic, floor)` there, and seeding the estimator's lower
bound at `max(intrinsic, floor)`. Add the floor check to txpool admission.
Separately, make the builder skip a transaction that fails execution instead of
aborting the payload, which needs a per-transaction rollback boundary in the
build path. Verify with a Prague estimate test asserting 25,000 for the
100-byte-calldata call, an admission test rejecting a below-floor transaction,
and a build test that produces a valid payload while one selected transaction
fails. Effort: about half a day for the estimator, an hour for the admission
check, and about half a day for skip-on-failure. The builder change is worth
doing even if the other two land first, because any future execution failure of
a selected transaction stalls block production the same way.

Note that the estimator and admission parts are *evidence-verified* on the
execution side and *inferred* on the upstream side for the pool rule; the
builder abort behavior was established by reading the code path, not by
provoking it.

### Tier 3 — the test gate

Every Tier 1 and Tier 4 finding survived because nothing in the suite would
catch it. This tier is the reason the others exist, and its placement deserves
an explicit argument rather than a number.

**3.1 — Wire the pinned EEST corpus.** `.eest-fixtures` does not exist and
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` is unset, so the EEST `v5.4.0` corpus
pinned in `PROJECT.md` contributes nothing today, and `docs/validation.md` is
correct that a missing optional fixture root produces a skip rather than
evidence. `make eest-fixtures` exists and fetches into `.eest-fixtures`
(`Makefile:11,47-48`), so the fetch itself is already automated; what is missing
is running it and wiring the root into the layered test targets. Separately,
the bundled corpus under `tests/fixtures/execution-spec-tests-root/fixtures` is
27 hand-authored JSON files: nine `phase-a` engine fixtures under
`blockchain_tests_engine/shanghai/` and nothing at all under `blockchain_tests/`,
one state-test sample each under `state_tests/london/` and
`state_tests/shanghai/`, three trie vector files, and thirteen
transaction-*shape* fixtures of which twelve are Prague EIP-7702 encoding cases.
No bundled fixture exercises Cancun or Prague block execution, blob gas, or the
calldata floor, and none of the Prague fixtures executes a block. The
state-fixture
selectors hardcode the fork list as `'("London" "Shanghai")` —
`tests/fixture-runner-state-selectors.lisp:50` and 30 further occurrences in
that file, plus one in `tests/evm-fixture-tests.lisp:679` — so extending
coverage past Shanghai means replacing that literal with a parameter as well as
supplying fixtures.

Everything Cancun-and-later therefore has zero fixture coverage: transient
storage, EIP-6780, point evaluation, the BLS precompiles, EIP-7702, the
EIP-7883 and EIP-7823 `MODEXP` repricings, `P256VERIFY`, blob gas, and the
calldata floor. This is the single largest gap in the audits, and it would have
caught items 1.1, 1.2, and most of 2.1 for free. Effort: days. Verify by
observing non-skipped Cancun and Prague fixture counts in the integration layer.

**3.2 — A table-driven fork-matrix gas test.** For each fork, a fixed list of
`(bytecode, expected gas)` rows derived from geth's per-fork jump table. The
opcode audit's recommendation was blunt: this is the highest value per hour in
its whole list, higher than any single fix, because it would have caught four of
its findings in one pass and would keep catching them. Effort: about half a day.

**3.3 — Targeted unit tests for the Tier 1 and Tier 2 fixes.** Written from the
concrete numbers already in the audits, listed with each item above. These are
cheap and they give each Tier 1 fix a target immediately, without waiting for
3.1. The same applies to a set of small gaps the audits flagged separately:
transient-storage cost is asserted nowhere; the BLS discount tables are only
spot-checked against the same table they price from, pinning entries 0 and 127
by literal value and nothing between; the refund cap boundary at
`refund > gasUsed/5` is untested; EIP-7623 has no test at all, under any name
the audit grepped for; intrinsic gas has no cross-fork differential test; and no
test asserts an upper gas cap for `eth_call` — the one test that exists asserts
the deliberate *absence* of the block-limit clamp. Effort: about three hours for
the batch.

**3.4 — Re-verify every finding against one pinned reference version.** Pick a
single geth tag, a single Nethermind tag, and a single execution-specs commit;
record them; re-derive the upstream side of each finding below and each
verified-correct claim above. The EIP-170 correction in this document is the
existence proof that this is substantive work rather than bookkeeping. Effort:
about a day, and it should happen before any finding here is quoted as a parity
claim in a commit message.

**Where this tier belongs.** The reconciled ordering places the test gate third,
and for 3.1 that is right — it is days of work and the three Tier 1 fixes are
hours each, so blocking them on the corpus would be a poor trade. Start 3.1 in
parallel and let it validate the Tier 1 fixes after the fact; use 3.3 to give
each Tier 1 fix a target now.

Item 3.2 is different, and the opcode audit's reasoning should be honoured
rather than flattened into "tests come third". That audit recommended writing
the fork-matrix test *before or alongside* the base-gas fix so that the fix has
a target. Its target is the Tier 4 cluster, not Tier 1 — so 3.2 belongs
immediately before item 4.1, where it is a genuine prerequisite rather than a
convenience. The reason is specific: 4.1 is the only change in this plan that
can regress behavior which is currently *correct*. Berlin-and-later totals are
right today precisely because a fork-blind base cost of 100 and a fork-blind
surcharge of 2500 sum to the correct 2600, so any partial or mistaken threading
of fork rules through that path breaks a fork the client actually executes in
order to fix forks it does not. A table that pins Berlin-and-later costs before
the refactor starts is the difference between a safe change and a gamble. If
Tier 4 is never scheduled, 3.2 loses most of its value with it — which is an
argument for treating 3.2 and 4.1 as one piece of work rather than for
promoting 3.2 on its own.

### Tier 4 — fork gating for historical replay only

Everything in this tier is a genuine consensus divergence, and none of it is
reachable on the forks this client targets for live operation. The operational
target is post-merge Engine-API operation, so pre-London blocks are never
executed in production. The `chain-config` does model Homestead, EIP-150/155/158,
Byzantium, Constantinople, Petersburg, Istanbul, Muir Glacier, Berlin, London,
the glaciers, the Merge, Shanghai, Cancun, Prague, Osaka, BPO1–BPO5, Amsterdam,
and UBT, and every item here is reachable through the EVM and execution APIs
today — which is how the audits measured them. What is not established is
whether the block-import path ever constructs pre-Berlin `chain-rules` in
production; the opcode audit explicitly declined to claim either way.

The honest implication is that this tier is optional. It matters if and only if
pre-Berlin historical replay becomes a goal. Until then the cheapest correct
action is not the fix but a stated scope boundary — **item 4.0** — which is the
storage audit's recommendation to document the London-and-later floor at
`opcode-base-gas`,
`sstore-dynamic-gas`, and `apply-refund-counter-to-receipt`, or to assert it, so
that pointing this client at a Berlin chain or a Berlin EEST fixture fails
loudly instead of quietly producing wrong numbers. That is an hour of work
against roughly a week for the full tier, and it should be taken first
regardless of whether the rest is ever scheduled.

**4.1 — Fork-aware base gas and gated EIP-2929 surcharges, as one change.**
`opcode-base-gas` (`src/runtime/evm/opcodes.lisp:42`) is a pure function of the
opcode byte, takes no `chain-rules`, and encodes the Berlin/Cancun schedule;
`step-evm-machine` calls it with nothing but the opcode. Meanwhile
`account-cold-access-surcharge`, `charge-account-access-gas`,
`charge-cold-account-access-gas` and `storage-access-cost`
(`src/runtime/evm/access-lists.lisp:42-85`) take a context but never consult
`evm-context-chain-rules`, and are called unconditionally from `BALANCE`,
`EXTCODESIZE`, `EXTCODECOPY`, `EXTCODEHASH`, the call family, and
`SELFDESTRUCT`. Geth `v1.17.5` builds a different jump table per fork and then
overlays EIP changes, installing the cold/warm dynamic gas functions only when
EIP-2929 is enabled; pre-Berlin tables have no cold/warm concept at all.
*Verified:* `BALANCE` in a three-instruction program costs 2603 here at every
fork from Frontier to Berlin, where geth charges 23 at Frontier and Homestead,
403 from Tangerine Whistle, and 703 at Istanbul. `EXTCODESIZE`, `EXTCODECOPY`,
`CALL`, `DELEGATECALL`, `STATICCALL` and `SELFDESTRUCT` are all likewise
constant across forks here. The same fork-blindness covers `SLOAD` and `SSTORE`
pricing, which the storage audit reported independently: an `SSTORE` clearing a
non-zero slot refunds 4800 at Byzantium, Istanbul and London alike, where
upstream refunds 15,000 at the first two.

These must land together. The Berlin totals are correct because 100 and 2500
sum to 2600; gating one without the other breaks Berlin. The fix threads
`chain-rules` into `opcode-base-gas` — the value is already on the machine
context at the single call site — and adds rules tests inside the access-list
surcharge functions. Verify against the fork-matrix table from 3.2, which must
exist first. Effort: about a day plus the test.

**4.2 — Gate the 63/64 rule on EIP-150.** `all-but-one-64th` is applied with no
fork test in both `child-call-gas-limit` and `child-create-gas-limit`
(`src/runtime/evm/gas.lisp:8-19`), neither of which takes `chain-rules`. Geth
returns the raw requested amount when `!isEip150`, and only reserves the 64th in
`opCreate` under `IsEIP150`; Nethermind gates on `spec.Use63Over64Rule` and
otherwise takes the requested amount verbatim. *Verified:* a parent with a
100,000 gas limit requesting `0xffffffff` forwards a capped 95,855 to the child
at every fork including Frontier, where upstream would forward the full request
and immediately run out of gas. The divergence runs both ways: for a callee
needing slightly more than the cap, Frontier-era geth can hand over everything
remaining while this client always withholds a 64th. The fix adds a rules
argument to both functions, with two call sites. The Berlin side of this path
was separately confirmed correct and must stay so. Effort: about an hour.

**4.3 — Split the pre- and post-EIP-158 account predicates.** Two problems in
`src/runtime/evm/state.lisp`. `call-value-extra-gas` (lines 17-26) wraps
everything including the 25,000 new-account charge in `(when (plusp value) …)`,
where geth charges `CallNewAccountGas` for a *value-independent*
`!StateDB.Exist(address)` test pre-EIP-158 and only gates on value afterwards;
Nethermind is identical in structure. *Verified:* a zero-value `CALL` to a
non-existent address costs 2621 here at every fork, where Frontier-era geth
charges 25,061 and Tangerine-era 25,721. And `empty-account-p` (lines 7-15)
requires an empty storage root in addition to nonce 0, balance 0 and empty code
hash, where geth's `stateObject.empty()` and Nethermind's `IsDeadAccount` are
the three-way test only, as are EIP-161 and the Yellow Paper `EMPTY` predicate.
*Verified:* an account with only a storage slot set is not empty here, producing
a 9000 call-value charge where upstream produces 34,000, and a zero
`SELFDESTRUCT` beneficiary surcharge where upstream produces 25,000. The
reachability of the predicate half is medium confidence — it needs a code-less
account with non-empty storage, which genesis allocations and EIP-7610-style
pre-existing storage produce but ordinary execution does not. The fix gives both
`call-value-extra-gas` and `selfdestruct-extra-gas` an `exist`-based branch for
pre-EIP-158 and drops the storage-root term from the predicate; check the other
`empty-account-p` caller in `src/runtime/evm/block.lisp` before changing it.
Effort: about two hours.

**4.4 — Add the pre-London `SELFDESTRUCT` refund.** The `SELFDESTRUCT` handler
(`src/runtime/evm/opcodes/system.lisp`) never touches the refund counter, which
is correct from London on. Geth adds 24,000 whenever the contract has not
already self-destructed, at every fork through Berlin, via the pre-2929 path and
then `makeSelfdestructGasFn` with refunds enabled; EIP-3529 flips it off at
London. *Inferred, not executed* — the audit read this and did not build a
self-destructing-contract probe. The fix is one guarded increment. Effort: about
an hour.

**4.5 — Implement EIP-2 pre-Homestead code-deposit semantics.** In
`execute-contract-creation` (`src/runtime/evm/interpreter/create.lisp:78-89`) a
deposit that does not fit in the child gas calls `fail`, which unwinds to the
`evm-error` handler at lines 97-105: the state snapshot is restored, 0 is
pushed, and the child's gas is consumed. Geth distinguishes
`ErrCodeStoreOutOfGas` and, pre-Homestead, treats it as a *success* — skipping
`RevertToSnapshot`, returning the leftover gas, and pushing the created address
rather than zero, leaving the account in place with empty code. This is exactly
what EIP-2 changed. *Inferred, not executed.* The fix needs a distinct condition
type instead of the generic `fail` so the handler can special-case it; the work
is in the snapshot and gas bookkeeping rather than the branch. Effort: about
half a day.

**4.6 — Fork-gate intrinsic gas and the refund quotient.** Three related
signature gaps. `transaction-intrinsic-gas`
(`src/runtime/execution/gas.lisp:24-41`)
charges a flat 4 per zero calldata byte and 16 per non-zero byte with no fork
argument, where `core.IntrinsicGas` uses `TxDataNonZeroGasFrontier` of 68 unless
`rules.IsIstanbul`; *verified:* calldata `01 02 00 03` costs 21,052 here under
both Frontier-era and Istanbul rules, where geth gives 21,208 before Istanbul.
The same function unconditionally uses the 53,000 contract-creation base
whenever `to` is absent, where geth uses it only under Homestead and charges the
plain 21,000 before; *verified:* 53,052 here against geth's 21,208 for the same
pre-Homestead creation. And `apply-refund-counter-to-receipt`
(`src/runtime/execution/accounting.lisp:59-67`) divides by
`+refund-quotient-eip3529+` of 5 and takes no rules argument at all, where
`calcRefund` uses 2 before London; *inferred*, and the absent parameter is
conclusive for the cap itself.

The fix threads rules into both functions. Note that this changes a public
signature used by the RPC and pool layers — `eth-rpc-call-intrinsic-gas`
(`src/api/public/state/gas.lisp:24-32`) and `validate-txpool-admission`
(`src/application/services/txpool-admission.lisp:125-129`) both currently pass
only `:eip3860-p`. Verify with a cross-fork intrinsic-gas table test. Effort:
about a day including callers and tests. The refund-quotient half should land
with 4.1's refund-amount changes, since pre-London both the amounts and the cap
differ and fixing one alone produces a number that matches neither fork.

**4.7 — Gate the EIP-170 code-size limit on EIP-158.** As established above,
`invalid-created-runtime-code-p` and `chain-rules-contract-code-size-limit`
apply the 24,576-byte limit at every fork, where both geth versions read,
Nethermind, the EIP text and `execution-specs` gate it on EIP-158. Unreachable
in historical replay because the deposit alone costs more gas than the era's
block limit allowed. Effort: minutes, but it needs the Amsterdam branch left
intact and is not worth doing outside a Tier 4 pass.

### Tier 5 — RPC completeness and unscheduled forks

None of these breaks consensus. Several make this node unusable as a wallet
backend, which is a real cost, just not a correctness one. All are *inferred by
reading* upstream unless noted.

**5.1 — Introduce a real RPC gas cap and wire `--rpc.gascap` to it.**
`eth-rpc-call-object-default-gas-limit`
(`src/api/public/state/call-objects.lisp:5-10`)
defaults `eth_call` and `eth_createAccessList` to `2^64 - 1`, and nothing clamps
a caller-supplied `gas` for either — an unbounded-work surface on a public
endpoint. Geth defaults and clamps both to `RPCGasCap`, 50,000,000 by default.
The CLI accepts `--rpc.gascap` (`src/app/cli/options/definitions.lisp:23`) but
the value is never plumbed into a handler, so the flag is a compatibility no-op.
The same change should fix the estimator's bounds:
`eth-rpc-call-object-gas-cap` (`src/api/public/state/gas.lisp:6-14`) returns
`min(requested, headerGasLimit)` and errors when intrinsic exceeds it, where
geth honours a caller-supplied `gas` above the block limit up to the cap, and
additionally clamps to `params.MaxTxGas` of `2^24` when the target block is
Osaka. This client can currently return an Osaka estimate above `2^24` that no
block can include, because `validate-call-transaction-fields` omits the
EIP-7825 cap check that `validate-execution-transaction-fields` has. Note that
`eth-rpc-call-default-gas-is-not-block-gas-limited` pins the permissive
*default* deliberately; what differs from geth is the absence of any upper
clamp, so that test should survive the change. Effort: about half a day for the
whole cluster.

**5.2 — Implement real `eth_feeHistory` rewards and a tip oracle.**
`eth-rpc-fee-history-zero-reward`
(`src/api/public/metadata/fee-history.lisp:138-140`)
returns `0x0` for every requested percentile of every block, where geth computes
real per-percentile effective priority fees from each block's transactions. The
same stub appears in `engine-rpc-suggest-gas-tip-cap`
(`src/api/public/metadata/fees.lisp:3-5`), so `eth_maxPriorityFeePerGas` returns
0 and `eth_gasPrice` returns exactly the base fee. Any fee oracle built on this
node suggests a zero tip. Self-contained, and needed before a wallet can use
this node for fee estimation. Effort: one to two days.

**5.3 — Add `blobGasUsed` and `blobGasPrice` to receipts.**
`eth-rpc-receipt-object`
(`src/api/public/transactions/receipts.lisp:37-93`) emits no blob fields, where
geth's receipt marshaller includes both for type-3 transactions; confirmed
absent across `src/api/`. The header already carries `excessBlobGas`, so the
price is derivable. Cancun and later. Effort: about two hours.

**5.4 — Iterate `eth_createAccessList` to a fixpoint.**
`engine-rpc-handle-eth-create-access-list` in
`src/api/public/state/access-lists.lisp:71-105`
runs the call once with whatever access list the caller supplied and reports
that run's `gasUsed` alongside the derived list. Geth re-executes with the
derived list until the tracer's output stabilises and returns the gas used by
that final run, so its `gasUsed` is what a transaction actually carrying the
list would pay — intrinsic 2400 and 1900 per entry, minus the warm-access
savings. The number this client returns is neither the one nor the other.
Effort: about half a day.

**5.5 — Correct the Amsterdam code-size constants, and decide about EIP-7907
metering.** `+amsterdam-max-contract-code-size+` is 32,768
(`src/protocol/chain-config/types.lisp:23`), so
`chain-rules-contract-code-size-limit` returns 32,768 and the derived initcode
limit is 65,536 (`src/runtime/evm/types.lisp:168-171`). EIP-7907 specifies
65,536 and 131,072, and geth `v1.17.5` agrees. *Verified:* Amsterdam rules here
report a 32,768 limit and reject a 65,537-byte initcode that geth allows.
Separately, EIP-7907's `EXCESS_CODE_COST` — 2 gas per 32-byte word above 24 KB,
plus a cold-`SLOAD` surcharge for cold code, applied to `CALL`, `CALLCODE`,
`DELEGATECALL`, `STATICCALL`, `EXTCODESIZE`, `EXTCODECOPY` and to a large
transaction entry point — has no implementation at all. **EIP-7907 was in
`Draft` status when read and Amsterdam is unscheduled**, so the specification
may still move; the constant change is minutes and the metering is about a day
of new dynamic-gas work on six opcodes, best deferred until Amsterdam's scope
settles.

### Recorded but not scheduled

Five findings are real but low-value, kept here so they are not rediscovered as
novel. `eth_estimateGas` does not recap by the sender's available balance, where
geth reduces its upper bound to `available / feeCap` and returns an insufficient
funds error when the value or blob cost alone exceeds the balance; this client's
simulation never charges gas up front, so an underfunded sender gets an
optimistic estimate. The simulation path ignores EIP-7702 authorizations, since
`apply-set-code-authorizations` is called only from `apply-message` — currently
unreachable, because `eth-rpc-call-object-transaction` can only synthesise
legacy, access-list and dynamic-fee transactions, so a caller cannot supply an
authorization list at all; it becomes live the moment that changes.
`eth_feeHistory`'s `gasUsedRatio` returns a Lisp rational that the JSON writer
renders to 12 decimal digits where geth emits a float64 — valid JSON, valid
magnitude, cosmetic. Block building packs by accumulated gas *limit* rather than
against a pool that returns unused gas, so it fits less work per block than
geth's miner; a fill-efficiency difference only, and the builder provably cannot
produce a block whose `gasUsed` mismatches execution because it executes the
block it builds. And there is no `MaxGasLimit` header bound: header validation
requires only `uint256-p` where geth rejects a gas limit above `2^63-1`.
Reaching `2^63` from a sane genesis takes roughly 44,600 blocks of maximum
1/1024 growth with a cooperating builder, so it is unreachable on a real network
but reachable on an adversarial or very long-running devnet; the check is about
fifteen minutes of work, and the audit noted it did not confirm whether the
header RLP decoder independently bounds the field to `uint64`.

Two further observations are worth knowing without being findings. Blob
transactions are never selected by the payload builder — they live in a separate
subpool the builder does not read — so blob-gas-aware packing is vacuously safe
today, and correspondingly untested. And `nil` chain rules default to
latest-fork pricing throughout the codebase, which means a test written with
`nil` rules silently gets Osaka behavior, including the `MODEXP` 1024-byte cap
and EIP-7883 prices. That is a convention rather than a divergence, but it is a
trap for anyone writing the fork-matrix test in 3.2.

### Dependencies and couplings

| Item | Effort | Must land with / after |
| --- | --- | --- |
| 1.1 delegation target warming | ~1h + test | — |
| 1.2 authorization warming order | ~2h + tests | — (needs chain id threaded from `context.lisp`) |
| 1.3 EIP-7918 child fraction | ~1h + test | all three call sites together |
| 2.1 EIP-7623 floor triangle | ~1d total | estimator and pool parts belong together; builder part independent but needed to prevent the outage |
| 3.1 EEST corpus | days | fork-selector parameterisation is part of it |
| 3.2 fork-matrix gas test | ~0.5d | before 4.1 — prerequisite, not convenience |
| 3.3 targeted unit tests | ~3h | alongside Tier 1 and 2 |
| 3.4 single-version re-verification | ~1d | before quoting any finding as a parity claim |
| 4.0 scope comment or assertion | ~1h | take this first if Tier 4 is not scheduled |
| 4.1 base gas + 2929 gating | ~1d | **one change**; after 3.2 |
| 4.2 63/64 gating | ~1h | after 4.1 (shares the rules plumbing) |
| 4.3 account predicates | ~2h | check `block.lisp` caller first |
| 4.4 pre-London selfdestruct refund | ~1h | after 4.1 |
| 4.5 EIP-2 deposit semantics | ~0.5d | — |
| 4.6 intrinsic gas + refund quotient | ~1d | refund-quotient half with 4.1 |
| 4.7 EIP-170 EIP-158 gate | minutes | within a Tier 4 pass |
| 5.1 RPC gas cap cluster | ~0.5d | — |
| 5.2 fee history and tip oracle | 1–2d | — |
| 5.3 receipt blob fields | ~2h | — |
| 5.4 access-list fixpoint | ~0.5d | — |
| 5.5 Amsterdam constants | minutes / ~1d | draft EIP; defer the metering |

## Limitations of this analysis

The reference versions are inconsistent across the three audits, as tabulated
above, and no finding here should be quoted as parity with an unqualified
upstream client. Item 3.4 exists to fix this, and the EIP-170 correction shows
it is not a formality.

Several claims are inferred from reading rather than executed, and are marked as
such per finding. The pre-London upstream numbers in particular were derived
from pinned source rather than from a running geth or Nethermind; the
pre-Homestead code-deposit path and the pre-London `SELFDESTRUCT` refund were
read and never probed; and the argument that no bytecode can drive the total
refund counter negative is reasoning, not a search.

Two reachability questions are open. Nothing established whether the block
import path ever constructs pre-Berlin `chain-rules` in production, so the
practical reachability of the whole Tier 4 cluster for this client as deployed
is unknown — the audits measured them through the EVM and execution APIs, which
is a weaker statement. And the account shape needed for the `empty-account-p`
divergence in 4.3 was assessed at medium rather than high confidence.

Three narrower gaps: the storage and precompile audit recorded its geth pin by
tag without a commit hash and did not record the repository commit it audited,
so its findings are the least mechanically reproducible of the three; the same
audit read the `disable_precompiles` rule for a delegation pointing at a
precompile address and concluded this client's behavior is probably equivalent
without executing it; and the EIP-6780 state effects when the beneficiary is the
self-destructing contract itself were read, not run.

Finally, this document records the state of the code at one commit. It does not
track subsequent changes, and it asserts nothing about gas surfaces the three
audits did not cover.
