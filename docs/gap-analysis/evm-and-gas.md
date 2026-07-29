# EVM, precompiles, gas, and fork activation — gap analysis

## Sources read

| Side | Version | Commit | Read on |
| --- | --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` (sparse: `src/Nethermind`) | 2026-07-28 |

Both are the local checkouts under `references/`. Every reference citation below is
a path relative to `references/go-ethereum` or `references/nethermind`, with the
line numbers as they stand at those commits. Our own citations are relative to
the repository root at the working tree of 2026-07-28.

This document covers the interpreter, the precompiles, gas accounting, and fork
and EIP activation. It is a companion to `docs/gas-parity.md`, not a replacement:
that document is the authority on gas arithmetic and its remediation plan, and
the reconciliation section below states which of its findings this pass touches.

**Nothing here was executed.** `scripts/dev.sh status` reports the dev container
and image absent, and this audit was not permitted to start them, so no number in
this document came out of a running image. In the vocabulary
`docs/gas-parity.md` establishes, every finding below is *inferred by reading*
both sides. Structural claims — an opcode byte that no dispatch branch reaches, a
missing fork parameter, an absent constant — are conclusive on their own.
Behavioral claims about magnitudes are not, and are marked UNVERIFIED where the
magnitude matters.

## Remediation status (2026-07-29)

The audit above remains the historical evidence snapshot; this status records
what the `gap/evm-gas` remediation changed afterward.

- Completed: Amsterdam Engine capability gating (including independent KZG,
  BLS, and Amsterdam-execution predicates); `SLOTNUM`, `DUPN`, `SWAPN`, and
  `EXCHANGE`; EIP-7954's 65,536-byte code limit; EIP-7708 transfer logs;
  typed KZG unavailability; Prague-only EIP-7702 resolution; the EIP-161 empty
  account predicate; post-merge fork-order validation; EIP-8246's
  created-contract self-destruct-to-self balance-only result.
- Completed performance fixes: each frame builds a jump-destination bitmap once,
  EVM memory grows on a geometric backing store while preserving logical
  word-aligned size, and stack overflow checks use a frame-local O(1) depth
  counter.
- Partially completed: the fork matrix now pins all four Amsterdam opcode costs,
  pre-Amsterdam rejection, Osaka/Amsterdam precompile count, code limits, and
  transfer-log behavior. It now also pins EIP-8037/8038 regular/state budget
  conservation, the complete SSTORE cases table, every account and call-family
  opcode, CREATE/CREATE2/code deposit, SELFDESTRUCT, refunds, access-list
  pricing, transaction receipts, and Osaka/Amsterdam prices. A pinned Amsterdam
  EEST corpus is still unavailable.
- Completed: EIP-8037/8038 multidimensional gas is wired through EVM frames,
  transactions, receipts, transaction lists, and block gas accounting.
  `amsterdam-execution-available-p` is now true. Engine Amsterdam methods are
  advertised and dispatched only when the independent KZG and BLS dependencies
  are also available.

The final isolated Docker verification completed with 948 unit tests passed
(3 skipped), 304 integration tests passed (2 skipped), 59 e2e tests passed, and
the documentation transcript check passed. These are remediation results, not
retroactive evidence for the original audit.

## Executive summary

The ordered list of the most consequential gaps:

1. Amsterdam has no EVM implementation at all: the four opcodes both references
   define (`SLOTNUM`, `DUPN`, `SWAPN`, `EXCHANGE`) are absent, and so is the
   EIP-8037/8038 state-gas metering and repricing that changes the cost of every
   state-touching instruction at that fork (EVM-01, EVM-02).
2. `engine_newPayloadV5` is nevertheless enabled and dispatched whenever the
   configured chain reaches Amsterdam, so the node will accept and execute
   Amsterdam payloads under near-Osaka rules instead of refusing them — the
   capability-gating principle in `PROJECT.md` is not honoured for this fork
   (EVM-04).
3. Our Amsterdam contract-code-size limit is 32,768 where both references use
   65,536 (EIP-7954), and the derived initcode limit is half what it should be;
   the same wrong constant appears a second time in the block-access-list module
   (EVM-03). This is `docs/gas-parity.md` item 5.5, still open, now re-attributed
   and confirmed against both references.
4. EIP-7708 ETH-transfer system logs are absent, so at Amsterdam every value
   transfer and every `SELFDESTRUCT` payout would produce a different receipt,
   log index, and bloom than either reference (EVM-05).
5. EIP-7702 delegation resolution is not fork-gated: we resolve a `0xef0100`
   designator into the target's code at every fork, where geth resolves only
   under Prague (EVM-07).
6. Jump-destination validity is recomputed by re-scanning the contract from
   offset 0 on every `JUMP` and `JUMPI`, with no analysis cache; both references
   compute a bitmap once and cache it by code hash (EVM-12).
7. EVM memory is reallocated and fully copied on every expansion, aligned to the
   next 32-byte boundary and nothing more, so growing memory a word at a time is
   quadratic in the final size; geth's `Memory.Resize` appends and Nethermind
   pools (EVM-10).
8. The 1024-item stack limit is enforced by taking `length` of a linked list on
   every push, so the check is linear in the current stack depth (EVM-11).
9. The `POINT_EVALUATION` precompile converts "the KZG backend is not installed"
   into "the proof is invalid", fabricating a consensus verdict — exactly the
   failure mode the BLS precompile file documents itself as avoiding. The Engine
   path is honestly gated, so this bites the simulation and call paths (EVM-09).
10. `EXTCODEHASH` returns a non-zero hash for a code-less account that has
    storage, where both references return zero, because our `empty-account-p`
    carries a storage-root term (EVM-08). This is the value-visible half of
    `docs/gas-parity.md` item 4.3, which recorded only the gas half.

## Reconciliation with `docs/gas-parity.md`

That document's findings were re-read against the two pinned references here.
This pass did not re-derive its gas arithmetic — the differential results it
reports are stronger evidence than reading, and re-running them needs a warm
image. What this pass can say:

| gas-parity item | Status after this pass |
| --- | --- |
| 1.1 delegation target of `tx.to` never warmed | Still open. `transaction-accessed-addresses-table` (`src/runtime/execution/access.lisp`) is unchanged and still warms no delegation target. |
| 1.2 invalid authorization tuples warm too early | Still open; `access.lisp` still takes no chain id. |
| 1.3 EIP-7918 uses the parent's update fraction | Still open. Block/consensus area; not re-examined here beyond confirming the call sites still exist. |
| 2.1 EIP-7623 floor missing from estimation, admission, building | Still open. Estimator and pool area; not re-examined here. |
| 3.1 EEST corpus unwired | Still open, and it is the reason every finding below could survive. `.eest-fixtures` does not exist. |
| 4.1 fork-blind base gas and ungated EIP-2929 surcharges | Still open, confirmed by reading: `opcode-base-gas` (`src/runtime/evm/opcodes.lisp:42`) still takes only the opcode byte, and `account-cold-access-surcharge` / `storage-access-cost` (`src/runtime/evm/access-lists.lisp:42,65`) still take a context but never read `evm-context-chain-rules`. |
| 4.2 63/64 rule ungated | Still open: `child-call-gas-limit` and `child-create-gas-limit` (`src/runtime/evm/gas.lisp:11,18`) take no rules. |
| 4.3 account predicates | Still open, and **wider than recorded**: see EVM-08. `empty-account-p` (`src/runtime/evm/state.lisp:7-15`) also changes the value `EXTCODEHASH` pushes, not only gas. |
| 4.7 EIP-170 limit not gated on EIP-158 | Still open: `chain-rules-contract-code-size-limit` (`src/protocol/chain-config/rules.lisp:9-12`) branches only on Amsterdam. Confirmed against geth `core/vm/common.go` at this commit. |
| 5.5 Amsterdam code-size constants | Still open, and re-attributed: see EVM-03. The relevant EIP at these commits is **7954**, not 7907, and geth 1.17.6 implements the size change without any excess-code metering. |

Two of that document's cautions are worth restating because this pass depended
on them. `nil` chain rules mean latest-fork behavior throughout our EVM
(`context-fork-enabled-p`, `src/runtime/evm/base.lisp:9-11`), so a reader
checking a fork gate must supply real rules. And its "structural differences with
identical outcomes" section already disposes of several things that look like
findings in the interpreter — base gas charged before operands are popped, the
stack limit enforced on push rather than validated before the handler runs, and
`BLAKE2F` returning no up-front price for a malformed length. This pass agrees
with all three and does not re-litigate them.

## Findings

### EVM-01 — Amsterdam opcodes are not implemented

**Verdict:** MISSING. **Severity:** consensus-breaking on any chain that
activates Amsterdam.

Both references define four opcodes at Amsterdam that we do not implement:

| Opcode | Byte | EIP | geth | Nethermind |
| --- | --- | --- | --- | --- |
| `SLOTNUM` | `0x4b` | 7843 | `core/vm/eips.go:579-586`, `core/vm/opcodes.go:108` | `Nethermind.Evm/Instruction.cs:70` |
| `DUPN` | `0xe6` | 8024 | `core/vm/eips.go:340-346`, `core/vm/opcodes.go:232` | `Nethermind.Evm/Instruction.cs:162` |
| `SWAPN` | `0xe7` | 8024 | `core/vm/eips.go:347-352`, `core/vm/opcodes.go:233` | `Nethermind.Evm/Instruction.cs:163` |
| `EXCHANGE` | `0xe8` | 8024 | `core/vm/eips.go:353-358`, `core/vm/opcodes.go:234` | `Nethermind.Evm/Instruction.cs:164` |

geth installs them in `newAmsterdamInstructionSet` (`core/vm/jump_table.go:106-112`).

Our dispatcher (`src/runtime/evm/interpreter/interpreter.lisp:3-19`) routes
`0x30`–`0x4a` to the environment family and `0xf0`–`0xff` to the system family.
`0x4b` and `0xe6`–`0xe8` fall through to the final clause and raise
"Unsupported EVM opcode", which is the invalid-opcode path.

Observable consequence: any Amsterdam block containing a transaction that
executes one of these four instructions halts the frame with all gas consumed
where both references execute it, producing a different `gasUsed`, receipt root,
and state root. `SLOTNUM` in particular needs no arguments, so a two-byte
contract is enough to diverge.

Note that Amsterdam is not scheduled on mainnet at these commits — geth leaves
`AmsterdamTime` unset for mainnet while setting `OsakaTime`, `BPO1Time`, and
`BPO2Time` (`params/config.go:64-67`) — so the reachable target today is a
devnet. Our own `chain-config` accepts `amsterdam-time`
(`src/protocol/chain-config/types.lisp:70,105`).

### EVM-02 — EIP-8037 state-gas metering and EIP-8038 repricing are absent

**Verdict:** MISSING. **Severity:** consensus-breaking on any chain that
activates Amsterdam.

geth installs both together (`core/vm/jump_table.go:110`,
`core/vm/eips.go:588-614`), replacing the dynamic-gas function of `CREATE`,
`CREATE2`, `SLOAD`, `SSTORE`, `BALANCE`, `EXTCODEHASH`, `EXTCODESIZE`,
`EXTCODECOPY`, the whole call family, and `SELFDESTRUCT`, and changing
`CREATE`/`CREATE2` constant gas to `params.CreateAccessAmsterdam`. The new
constants are in `params/protocol_params.go:114-125`: cold account access 3,000
(from 2,600), account write 8,000, call value 10,300, cold storage access 3,000
(from 2,100), storage write 10,000, storage clear refund 12,480 (from 4,800),
create access 11,000, access-list address and storage-key costs 3,000 each.
Nethermind sets `IsEip8037Enabled` and `IsEip8038Enabled` at Amsterdam
(`Nethermind.Specs/Forks/25_Amsterdam.cs:24-25`).

EIP-8037 is not only a table of constants. geth's gas functions return a
`GasCosts` struct carrying `RegularGas` and `StateGas` separately, and the
interpreter charges them through two different paths depending on whether
`StateGas` is zero (`core/vm/jump_table.go:27-33`,
`core/vm/interpreter.go:220-231`). Our machine carries a single `gas-used`
integer (`src/runtime/evm/interpreter/machine.lisp:28`) and
`evm-machine-charge-gas` (`machine.lisp:73-78`) is scalar, so the metering
dimension does not exist in our design. Our constants are the Berlin ones
(`src/runtime/evm/types.lisp:175-183`) with no Amsterdam variants.

Observable consequence: every state-touching instruction in an Amsterdam block
is mispriced, so `gasUsed` and the receipt root differ on essentially any
non-trivial transaction.

### EVM-03 — the Amsterdam code-size limit is 32,768 instead of 65,536

**Verdict:** DIVERGENT. **Severity:** consensus-breaking on any chain that
activates Amsterdam.

`+amsterdam-max-contract-code-size+` is 32,768
(`src/protocol/chain-config/types.lisp:23`), so
`chain-rules-contract-code-size-limit` returns 32,768 and
`chain-rules-contract-initcode-size-limit` returns 65,536
(`src/protocol/chain-config/rules.lisp:9-15`). The same wrong number appears
independently as `+block-access-list-amsterdam-max-code-size+`
(`src/protocol/block-access-lists/types.lisp:4`).

Both references use 65,536, attributing it to EIP-7954: geth
`params/protocol_params.go:163-164` (`MaxCodeSizeAmsterdam = 65536`,
`MaxInitCodeSizeAmsterdam = 2 * MaxCodeSizeAmsterdam`), and Nethermind
`Nethermind.Core/CodeSizeConstants.cs:9`
(`MaxCodeSizeEip7954 = 65_536`) selected at
`Nethermind.Specs/Forks/25_Amsterdam.cs:22`.

This is `docs/gas-parity.md` item 5.5. Two corrections to how it was recorded
there. The EIP is 7954, not 7907 — 7907's number appears nowhere in geth 1.17.6.
And that item's second half, EIP-7907 `EXCESS_CODE_COST` metering, has no
counterpart in either reference at these commits, so deferring it was right and
it should not be described as a gap against geth.

Observable consequence: we reject a 32,769-byte deposited contract and a
65,537-byte initcode that both references accept, so any Amsterdam block
deploying a large contract fails validation here.

### EVM-04 — `engine_newPayloadV5` is enabled at Amsterdam with no Amsterdam EVM

**Verdict:** DIVERGENT. **Severity:** consensus-breaking; capability-gating
violation.

`engine-rpc-validate-new-payload-fork` accepts version 5 exactly when the
payload's timestamp is at or after Amsterdam
(`src/api/engine/new-payload.lisp:19-28`), and `forkchoiceUpdatedV4` is likewise
required from Amsterdam (`src/api/engine/forkchoice.lisp:89-92`). Nothing in the
method registry (`src/api/engine/methods.lisp:14-28`) marks the Amsterdam
methods as unavailable, and the only availability predicate applied to Engine
dispatch is the KZG one (`src/api/engine/methods.lisp:90-95`).

So a consensus client driving this node across an Amsterdam activation gets a
`VALID` or `INVALID` verdict computed with EVM-01, EVM-02, EVM-03, and EVM-05
all in force. `PROJECT.md` requires the opposite: "Later-fork and KZG-backed
Engine methods stay gated when their verifier or execution semantics are
unavailable, instead of silently returning wrong answers." The KZG side of that
sentence is implemented properly and is a good model for the fix.

Reference behavior is not the comparison here — the comparison is our own
contract. For completeness, geth's Amsterdam Engine surface is real because its
EVM implements the fork.

Observable consequence: an Amsterdam devnet gets confidently wrong `newPayload`
verdicts instead of an honest `-38005`-style refusal, which is worse than not
supporting the fork.

### EVM-05 — EIP-7708 ETH-transfer system logs are absent

**Verdict:** MISSING. **Severity:** consensus-breaking on any chain that
activates Amsterdam.

geth emits a `Transfer(address,address,uint256)` log for a moved balance in two
places: on every value transfer (`core/evm.go:147`, calling
`types.EthTransferLog`, defined at `core/types/log.go:68-75` with the topic
constant at `params/protocol_params.go:279`), and inside `SELFDESTRUCT`
(`core/vm/instructions.go:966-970`, guarded by `evm.chainRules.IsAmsterdam`).
Nethermind sets `IsEip7708Enabled` at Amsterdam
(`Nethermind.Specs/Forks/25_Amsterdam.cs:17`).

We emit logs only from the `LOG0`–`LOG4` handlers
(`src/runtime/evm/opcodes/stack-log.lisp:24-51`). `transfer-call-value`
(`src/runtime/evm/state.lisp:57-73`) and `selfdestruct-account`
(`src/runtime/evm/state.lisp:82-92`) move balances without touching the log
list, and there is no system-log constructor anywhere in `src/runtime/evm/`.

Observable consequence: at Amsterdam, a plain value-carrying `CALL` produces one
fewer log here than in either reference. Log count, log index, receipt logs
bloom, and the receipts root all differ, so the block is rejected — and every
downstream log index shifts, which also corrupts `eth_getLogs` results for the
block.

### EVM-06 — the fork schedule has no Bogota and no order validation

**Verdict:** MISSING. **Severity:** completeness.

geth 1.17.6 defines a fork after Amsterdam: `BogotaTime`
(`params/config.go:466`), a `bogotaInstructionSet` that currently equals
Amsterdam's (`core/vm/jump_table.go:71,95-98`), `Rules.IsBogota`
(`params/config.go:1437`), and a precompile selection for it
(`core/vm/contracts.go:221-222,248-249`). Nethermind 1.40.0 has no Bogota
(`Nethermind.Specs/Forks/` stops at `25_Amsterdam.cs`). We have no Bogota
either (`src/protocol/chain-config/types.lisp:70-71` ends at `amsterdam-time`
and `ubt-time`). Since Bogota's rule set is empty relative to Amsterdam at this
commit, the practical cost is only that a genesis naming `bogotaTime` is
silently ignored rather than rejected.

Separately and more usefully: geth validates that a configuration's forks are
scheduled in ascending order, and that no fork is enabled with its predecessor
unset, in `CheckConfigForkOrder` (`params/config.go:930`). We have no
counterpart — `chain-config-from-genesis-config`
(`src/protocol/genesis/chain-config.lisp:48`) is the only genesis entry point
and does no ordering check, and each `chain-config-<fork>-p` predicate in
`src/protocol/chain-config/forks.lisp:9-88` tests only its own field against
`chain-config-london-p`. A configuration with `osakaTime` set and `pragueTime`
unset therefore yields rules where `osaka-p` is true and `prague-p` false, which
enables `CLZ` and EIP-7883 `MODEXP` pricing while leaving the BLS precompiles
inactive (`src/runtime/evm/types.lisp:43-46`) and the EIP-7702 call-family
delegation charge switched off (`src/runtime/evm/interpreter/call.lisp:68-69`).
No such fork combination exists, and geth would refuse the config at load.

Observable consequence: a hand-written or mistyped devnet genesis produces an
impossible ruleset that executes without complaint, and the resulting divergence
looks like an EVM bug rather than a configuration error.

### EVM-07 — EIP-7702 delegation resolution is not fork-gated

**Verdict:** DIVERGENT. **Severity:** correctness; reachable only pre-Prague.

`evm-resolved-code` (`src/runtime/evm/state.lisp:75-80`) takes no rules
argument: it reads the account's code, and if `set-code-delegation-target`
recognises a 23-byte `0xef0100`-prefixed designator
(`src/protocol/transactions/set-code-authorization.lisp:82-88`) it returns the
target's code instead. Its call site in the call family
(`src/runtime/evm/interpreter/call.lisp:208`) is unconditional.
`execution-resolved-code` (`src/runtime/execution/state.lisp:30-35`) has the
same shape and the same absence of a gate.

geth resolves only under Prague: `resolveCode` returns the raw code when
`!evm.chainRules.IsPrague` (`core/vm/evm.go:712-716`), and `resolveCodeHash` is
gated the same way (`core/vm/evm.go:726-731`). Nethermind reaches delegation
through `IsDelegatedCode` on a spec-selected path
(`Nethermind.Evm/State/IReadOnlyStateProvider.cs`).

The inconsistency is visible inside our own file: the *gas* for the delegation
target is correctly gated on Prague
(`src/runtime/evm/interpreter/call.lisp:68-80`) while the *semantics* two dozen
lines later are not. Pre-Prague we would therefore execute the target's code
without charging the delegation access cost — divergent on both axes at once.

Reachability requires an account whose code is exactly `0xef0100` followed by 20
bytes on a pre-Prague ruleset. EIP-3541 forbids deploying `0xef`-prefixed code
from London on, and our `invalid-created-runtime-code-p` enforces that
(`src/runtime/evm/create.lisp:41-46`), so the shape arises from a pre-London
deployment or a genesis allocation. Both occur in historical replay and in EEST
pre-state.

Observable consequence: a pre-London block calling such an account executes
different code here than in geth, so state root and `gasUsed` both differ.

### EVM-08 — `EXTCODEHASH` and the emptiness predicate disagree with both references

**Verdict:** DIVERGENT. **Severity:** correctness.

`empty-account-p` (`src/runtime/evm/state.lisp:7-15`) requires four things:
nonce zero, balance zero, an empty storage root, and an empty code hash. Both
references use the three-way test without the storage term: geth's
`stateObject.empty()` is `Nonce == 0 && Balance.IsZero() && CodeHash ==
EmptyCodeHash` (`core/state/state_object.go:91-93`), reached through
`StateDB.Empty` (`core/state/statedb.go:323-326`); Nethermind's `IsDeadAccount`
returns `account?.IsEmpty ?? true`
(`Nethermind.State/StateProvider.cs:113-117`), and `Account.IsEmpty` is
`Balance.IsZero && Nonce == 0 && CodeHash == Keccak.OfAnEmptyString`
(`Nethermind.Core/Account.cs:140`).

`docs/gas-parity.md` item 4.3 records the gas consequence of this. The part it
did not record is that the predicate also determines a *pushed value*:
`account-code-hash-word` (`src/runtime/evm/block.lisp:14-22`) returns 0 when
`empty-account-p` holds and the code hash otherwise, and it is what `EXTCODEHASH`
pushes (`src/runtime/evm/opcodes/environment.lisp:186-190`). geth's
`opExtCodeHash` clears the slot when `StateDB.Empty(address)` and otherwise
pushes `GetCodeHash` (`core/vm/instructions.go:391-400`).

For a code-less account with nonce 0, balance 0, and at least one storage slot
set, we are not empty and push `keccak256("")`; both references are empty and
push 0.

Reachability is the same shape as item 4.3's: genesis allocations and
EIP-7610-style pre-existing storage produce it, ordinary execution does not,
because our `CREATE` path sets the nonce to 1 before initcode runs
(`src/runtime/evm/interpreter/create.lisp:45-51`). EEST pre-state sections are
exactly how such accounts get constructed, so this is a plausible fixture
failure rather than a live-network one. Unlike item 4.3 this half is *not*
pre-Berlin-only: it is reachable at Cancun, Prague, and Osaka today.

Observable consequence: a contract branching on `EXTCODEHASH == 0` takes the
other branch, which can change the whole transaction, not just its gas.

### EVM-09 — `POINT_EVALUATION` reports a verdict when the KZG backend is missing

**Verdict:** DIVERGENT. **Severity:** correctness.

`run-kzg-point-evaluation-precompile`
(`src/runtime/evm/precompiles/kzg.lisp:22-27`) wraps `verify-kzg-point-proof` in
`(handler-case ... (error (condition) (fail-precompile gas "~A" condition)))`.
`verify-kzg-point-proof` signals a plain `error` with the message "KZG point
proof verification is not available" when no verifier is installed
(`src/protocol/kzg/validation.lisp:34-36`, availability decided by
`kzg-point-proof-verification-available-p`,
`src/protocol/kzg/verifier-hooks.lisp:34-35`). The `handler-case` therefore
turns "we cannot check" into "the proof is invalid", and the precompile fails and
burns the child gas limit
(`src/runtime/evm/interpreter/results.lisp:16-21`).

The BLS precompile file states the correct rule and follows it: only "a definite
verdict that the input is invalid becomes a precompile failure", while a backend
that cannot be consulted signals `bls12381-unavailable-error`, which is
deliberately not caught so the node refuses to validate
(`src/runtime/evm/precompiles/bls12381.lisp:51-67`). geth has no analogue
because its KZG backend is compiled in; the relevant reference point is that
`kzgPointEvaluation.Run` fails only on a real verification failure
(`core/vm/contracts.go`, `kzgPointEvaluation`).

Scope, stated fairly: the Engine surface *is* honestly gated. Every Cancun and
later `newPayload`, `getPayload`, `forkchoiceUpdated`, and `getBlobs` method is
marked `:kzg-p t` (`src/api/engine/methods.lisp:15-28`) and
`engine-rpc-engine-method-p` refuses them unless
`kzg-proof-verification-available-p` holds
(`src/api/engine/methods.lisp:90-95`). So a node with no KZG backend cannot be
driven across Cancun through the Engine at all, and the finding is not
consensus-breaking on that path. It bites `eth_call`, `eth_estimateGas`, and any
simulation or direct block-execution entry point, which are not behind that
gate, and it would become consensus-relevant the moment an import path bypasses
the Engine.

Observable consequence: on a node without the KZG helper, `eth_call` against a
contract that verifies a blob proof reports a failed call instead of an error,
so a caller cannot distinguish "your proof is wrong" from "this node cannot
check proofs".

### EVM-10 — memory expansion reallocates and copies the whole buffer

**Verdict:** DIVERGENT. **Severity:** performance, with denial-of-service
potential. Magnitude UNVERIFIED.

`ensure-memory-size` (`src/runtime/evm/memory.lisp:9-14`) allocates a fresh
byte vector of exactly `32 * ceil(size / 32)` and `replace`s the old contents
into it. There is no capacity slack, so an `MSTORE` at a new high-water mark
allocates and copies everything written so far. `mstore`, `mstore8`,
`copy-into-memory`, `copy-memory-region`, and `memory-slice` all route through
it (`memory.lisp:41-101`), and the machine stores the returned vector back into
the frame (`src/runtime/evm/opcodes/state-memory.lisp:37,43`).

geth's `Memory.Resize` appends, so the slice's capacity grows geometrically and
expansion is amortized constant (`core/vm/memory.go:81-89`). Nethermind uses a
pooled buffer with an explicit ceiling (`Nethermind.Evm/EvmPooledMemory.cs:19-21`).

The complexity claim is structural and follows from the code: growing memory to
`n` bytes one word at a time copies on the order of `n²/64` bytes. What is
UNVERIFIED is the wall-clock consequence, because nothing was executed. The
input that would settle it is a loop of `MSTORE` at monotonically increasing
offsets, run at a realistic block gas limit; memory gas is
`3w + w²/512`, so a 30,000,000-gas budget buys roughly 10⁵ words, and the
quadratic term is what needs measuring.

Observable consequence: not a wrong result — gas is charged identically — but a
block that both references import in milliseconds could take far longer here,
which is a liveness problem for a node expected to keep up with a chain.

### EVM-11 — the stack limit check is linear in stack depth

**Verdict:** DIVERGENT. **Severity:** performance. Magnitude UNVERIFIED.

`stack-push` calls `(length stack)` on every push to compare against
`+stack-limit+` (`src/runtime/evm/base.lisp:22-25`), and the stack is an
ordinary list (`src/runtime/evm/interpreter/machine.lisp:29`). `DUP` and `SWAP`
also call `length` and then `nth`
(`src/runtime/evm/opcodes/stack-log.lisp:12-23`).

geth precomputes `minStack` and `maxStack` per operation and compares them
against an O(1) `stack.len()` before the handler runs
(`core/vm/interpreter.go:189-193`, table entries throughout
`core/vm/jump_table.go`). Nethermind uses a pooled array-backed stack
(`Nethermind.Evm/EvmStack.cs`, `Nethermind.Evm/StackPool.cs`).

`docs/gas-parity.md` already establishes that enforcing the limit on push rather
than before the handler is observationally equivalent, and this finding does not
dispute that; it is about the cost of the check, not its placement. As with
EVM-10 the complexity is structural and the magnitude is UNVERIFIED.

### EVM-12 — jump-destination analysis is redone on every jump

**Verdict:** DIVERGENT. **Severity:** performance, with denial-of-service
potential. Magnitude UNVERIFIED.

`valid-jump-destination-p` (`src/runtime/evm/opcodes.lisp:37-40`) checks that
the target byte is `0x5b` and then calls `code-position-p`
(`opcodes.lisp:26-35`), which walks the code from `pc = 0`, skipping `PUSH`
immediates, until it reaches or passes the destination. It is called from `JUMP`
and `JUMPI` (`src/runtime/evm/opcodes/state-memory.lisp:15,25`) with no memo,
no per-frame cache, and no cross-frame cache.

Both references compute a bitmap once per code object and cache it. geth's
`Contract.validJumpdest` calls `isCode`, which consults `c.analysis`, then a
`JumpDestCache` keyed by code hash, and only then runs `codeBitmap`
(`core/vm/contract.go:66-99`, cache interface at `core/vm/jumpdests.go:21-47`,
bitmap at `core/vm/analysis_legacy.go:64`). Nethermind's
`JumpDestinationAnalyzer.ValidateJump` builds the bitmap lazily once and has a
vectorized populate path (`Nethermind.Evm/CodeAnalysis/JumpDestinationAnalyzer.cs:32-39,106-117`),
cached through `CodeInfo`.

The worst case is a tight loop at the end of a large contract: each `JUMPI`
costs 10 gas and triggers a scan proportional to the code length. A 24,576-byte
contract at a 30,000,000-gas block limit admits on the order of a million
back-edges, each scanning up to 24,576 bytes. That product is the number that
needs measuring; it is UNVERIFIED here.

Observable consequence: same as EVM-10 — correct results, potentially
unacceptable import latency, and a cheap adversarial input to produce it.

### EVM-13 — no interpreter-side tracing hooks beyond call boundaries

**Verdict:** MISSING. **Severity:** completeness. Deliberate and documented.

`src/runtime/evm/tracing.lisp` provides exactly one hook pair, opened and closed
around `execute-message-call-child`
(`src/runtime/evm/interpreter/call.lisp:265-272`). Its header argues the case
explicitly (`tracing.lisp:10-14`): a call tracer needs call boundaries, and an
opcode hook would cost something on every step. Two limitations are named rather
than hidden (`call.lisp:259-264`): `CREATE` and `CREATE2` frames are not traced
at all because they do not go through that function, and `DELEGATECALL` and
`CALLCODE` are reported as `CALL`.

For contrast, geth's interpreter carries `OnOpcode`, `OnFault`, and a gas-change
hook inside the run loop — the error path at `core/vm/interpreter.go:139-157` and
the per-step calls at `core/vm/interpreter.go:236-245` — plus
`OnBlockHashRead` in `opBlockhash` (`core/vm/instructions.go:427-429`) and
enter/exit hooks in `opSelfdestruct6780`
(`core/vm/instructions.go:972-979`).

Consequence, confined to the interpreter side of the boundary since RPC tracing
is another auditor's area: `debug_traceTransaction` with `structLog`,
`prestateTracer`, `4byteTracer`, or any per-opcode tracer cannot be implemented
on this surface, and `callTracer` output will mislabel three of the five frame
kinds. This is a documented limitation, not a defect — but it is a real
capability gap and the frame-type mislabelling is worth fixing independently,
since the information is available at the opcode handler.

### EVM-14 — no precompile result cache

**Verdict:** MISSING. **Severity:** performance.

geth 1.17.6 carries a shared precompile result cache: `PrecompileCache`
(`core/vm/precompile_cache.go:57`), consulted from `RunPrecompiledContract` for
pure precompiles with a bounded output (`core/vm/contracts.go:286-302`,
`cacheablePrecompile` at `core/vm/precompile_cache.go:183`). Gas accounting and
state touching are identical on hit and miss; only recomputation is skipped.

We have no equivalent: `execute-precompile`
(`src/runtime/evm/precompiles/dispatch.lisp:178-189`) always runs the
precompile. This matters more for us than for geth, because several of our
precompiles are pure Lisp — the BN254 pairing and its G2 subgroup check
(`src/runtime/evm/precompiles/bn254-g2.lisp:57-58` performs a full scalar
multiplication by the curve order per input point) and `MODEXP`
(`src/runtime/evm/precompiles/modexp.lisp:3-15`) are the expensive ones.

Also absent, and worth recording next to it: geth touches the precompile
address for block-level access-list recording under Amsterdam
(`core/vm/contracts.go:283-285`). We do not, which is part of EVM-02's fork gap.

Observable consequence: repeated identical precompile calls within a block — a
common shape in rollup verifier contracts — cost full recomputation here.

### EVM-15 — `PREVRANDAO` selection is not derived from the fork schedule

**Verdict:** DIVERGENT on derivation; equivalence UNVERIFIED. **Severity:**
completeness.

geth swaps `DIFFICULTY` for `PREVRANDAO` in the jump table at the merge
(`core/vm/jump_table.go:144-153`) and carries `Rules.IsMerge`
(`params/config.go:1431`, computed as `isMerge && c.IsLondon(num)` at
`params/config.go:1417`).

Our `chain-rules` has no merge or Paris field at all
(`src/protocol/chain-config/types.lisp:116-166`). Opcode `0x44` reads
`evm-context-difficulty-or-random-word`
(`src/runtime/evm/opcodes/environment.lisp:218-224`), which selects on the
context's `random-p` flag; that flag is set from `block-header-post-merge-p`
on the block-execution and system-call paths
(`src/runtime/execution/block-execution.lisp:121`,
`src/runtime/execution/system-calls.lisp:63`) and hardcoded to `t` in call
simulation (`src/api/public/state/call-simulation.lisp:73`).

Deriving the choice from the header rather than the schedule is defensible and
may be exactly equivalent for well-formed chains. What is UNVERIFIED is whether
`block-header-post-merge-p` and `IsMerge` agree on every input the import path
can construct, in particular for a header at the terminal block and for a
simulation over a pre-merge block — the simulation path's hardcoded `t` would
report a `PREVRANDAO` value for a pre-merge block where geth reports difficulty.

Observable consequence, if the equivalence fails: `0x44` pushes the wrong value,
which for a contract using it as a randomness source changes the transaction.

### EVM-16 — BLS backend availability is not represented in the Engine gate

**Verdict:** MISSING. **Severity:** completeness. The refusal itself is honest.

The BLS precompiles fail loudly and correctly when their backend is absent:
`run-bls12381-operation` signals `bls12381-unavailable-error`
(`src/protocol/bls12381/backend-hooks.lisp:52-64`) and
`call-bls12381-backend` deliberately does not catch it
(`src/runtime/evm/precompiles/bls12381.lisp:51-67`), so the node refuses to
validate rather than fabricating a verdict. That is the behavior `PROJECT.md`
asks for and the pattern EVM-09 should copy.

What is missing is the advertisement half. The Engine method registry gates on
KZG only (`src/api/engine/methods.lisp:15-28`), so a node whose BLS helper
binary was not built still advertises and accepts `engine_newPayloadV4`. It will
then fail to import the first Prague block that calls a BLS precompile, at
import time, with an error that reads as an internal fault rather than as a
missing capability. There is no `bls12381-available-p` predicate exposed
alongside `kzg-proof-verification-available-p`
(`src/packages/bls12381.lisp:13` exports only the condition).

Observable consequence: a misbuilt node syncs Prague until it meets a BLS-using
transaction and then stalls, instead of declining Prague up front.

### EVM-17 — EOF: absent in both references, absent here

**Verdict:** not a gap. Recorded so it is not rediscovered.

geth 1.17.6 reserves the EOF opcode names (`EOFCREATE` `0xec`,
`RETURNDATALOAD` `0xf7`, `EXTCALL` `0xf8` — `core/vm/opcodes.go:235,248-249`)
but installs no EOF instruction set: `core/vm/jump_table.go:54-72` lists no EOF
variant, `core/vm/eips.go:29-48` registers no EOF activator, and there is no
container validator in `core/vm/`. Nethermind 1.40.0 likewise has no EOF fork in
`Nethermind.Specs/Forks/`. We have no EOF either. There is nothing to close, and
work on EOF would be speculative against these commits.

### EVM-18 — Amsterdam EIP inventory beyond the EVM items above

**Verdict:** mixed; several UNVERIFIED. **Severity:** completeness.

Nethermind enumerates Amsterdam as EIP-2780, 7976, 7981, 7708, 7778, 7843,
7928, 7954, 8024, 8037, 8038, 8246, 8282
(`Nethermind.Specs/Forks/25_Amsterdam.cs:14-27`). Our status per item, restricted
to what this pass established by reading:

| EIP | geth evidence | Our status |
| --- | --- | --- |
| 7843 `SLOTNUM` | `core/vm/eips.go:579-586` | MISSING — EVM-01 |
| 8024 `DUPN`/`SWAPN`/`EXCHANGE` | `core/vm/eips.go:340-359` | MISSING — EVM-01 |
| 8037 state-gas metering | `core/vm/eips.go:588-614` | MISSING — EVM-02 |
| 8038 state-access repricing | `params/protocol_params.go:114-125` | MISSING — EVM-02 |
| 7954 code-size increase | `params/protocol_params.go:163-164` | DIVERGENT — EVM-03 |
| 7708 ETH-transfer logs | `core/evm.go:147`, `core/vm/instructions.go:966-970` | MISSING — EVM-05 |
| 8246 `SELFDESTRUCT`-to-self burn removal | `core/vm/instructions.go:950-957` | Pre-Amsterdam behavior matches: our `selfdestruct-account` is a no-op when beneficiary equals self (`src/runtime/evm/state.lisp:85`), and `finalize-evm-selfdestructs` then clears the account (`src/runtime/evm/selfdestructs.lisp:24-29`), so the balance is destroyed exactly as geth's explicit `SubBalance` destroys it. The Amsterdam *removal* of that burn is MISSING. |
| 7928 block-level access lists | `core/vm/contracts.go:283-285`, `core/state/statedb.go:328` | Partially present outside the EVM (`src/protocol/block-access-lists/`); the interpreter-side account and precompile touching is MISSING. Depth of the block-level implementation is out of this area's scope. |
| 2780, 7976, 7981, 7778, 8282 | `params/protocol_params.go:95,109,265`, `core/state_transition.go:143,174,191-205` | UNVERIFIED here. All five land in intrinsic gas, calldata pricing, access-list pricing, block gas policy, or the requests surface — the transaction and block auditors' areas. Recorded so the Amsterdam inventory is complete, not assessed. |

## What was checked and found to match

Recorded so that a later pass does not spend the time again. All of this is
"read on both sides", not executed.

**Opcode coverage through Osaka is complete and correctly gated.** Every opcode
geth's jump table defines from Frontier through Osaka has a dispatch branch, and
every fork gate matches the fork at which geth installs the operation:
`SHL`/`SHR`/`SAR` and `EXTCODEHASH` and `CREATE2` at Constantinople
(`src/runtime/evm/opcodes/arithmetic.lisp:77,84,91`,
`environment.lisp:176-178`, `system.lisp:43-45`; geth
`core/vm/jump_table.go:186-221`); `RETURNDATASIZE`, `RETURNDATACOPY`, `REVERT`,
`STATICCALL` at Byzantium (`environment.lisp:149,156`, `system.lisp:167,225`;
geth `core/vm/jump_table.go:225-257`); `CHAINID` and `SELFBALANCE` at Istanbul
(`environment.lisp:234,242`; geth `core/vm/eips.go:80-110`); `BASEFEE` at London
(`environment.lisp:253`; geth `core/vm/eips.go:173-181`); `PUSH0` at Shanghai
(`state-memory.lisp:186`; geth `core/vm/eips.go:228-236`); `BLOBHASH`,
`BLOBBASEFEE`, `TLOAD`, `TSTORE`, `MCOPY` at Cancun
(`environment.lisp:261,270`, `state-memory.lisp:143,157,170`; geth
`core/vm/jump_table.go:126-134`); `CLZ` at Osaka (`arithmetic.lisp:97-99`; geth
`core/vm/eips.go:308-316`); `DELEGATECALL` at Homestead (`system.lisp:143`; geth
`core/vm/jump_table.go:281-292`). Undefined ranges — `0x0c`–`0x0f`,
`0x21`–`0x2f`, `0x4c`–`0x4f`, `0xa5`–`0xef` minus the Amsterdam three, `0xfe`
— all reach a `fail`, which is geth's `opUndefined` outcome.

**`CLZ` semantics match.** `(- 256 (integer-length a))`
(`arithmetic.lisp:100-101`) equals geth's `256 - x.BitLen()`
(`core/vm/eips.go:292-296`), including 256 for a zero operand.

**Arithmetic edge cases match.** Division and modulus by zero yield zero;
`SDIV(-2^255, -1)` wraps to `2^255`; `SMOD`'s sign follows the dividend;
`SIGNEXTEND` and `BYTE` are identity and zero respectively above index 31;
`ADDMOD`/`MULMOD` with a zero modulus yield zero; `EXP(0,0)` is 1. Wrapping is
applied centrally in `stack-push` (`base.lisp:25`), so intermediate bignums
cannot leak.

**Every precompile geth defines at every fork is implemented and gated at the
right fork.** `active-precompile-address-number-p`
(`src/runtime/evm/types.lisp:37-48`) activates 1–4 always, 5–8 at Byzantium, 9
at Istanbul, 10 at Cancun, `0x0b`–`0x11` at Prague, and `0x100` at Osaka, which
is exactly geth's set progression (`core/vm/contracts.go:61-172`) and
`activePrecompiledContracts` (`core/vm/contracts.go:217-238`). Dispatch covers
all eighteen (`src/runtime/evm/precompiles/dispatch.lisp:13-35,79-176`). No
precompile exists in either reference that we lack.

**`ECRECOVER` input handling matches.** We right-pad to 128 bytes, require bytes
32–62 to be zero, and require the recovery id to be 0 or 1 after subtracting 27
(`dispatch.lisp:64-77`, `src/foundation/crypto/secp256k1.lisp:61-68`). geth does
the same with a byte underflow producing a value above 1
(`core/vm/contracts.go:314-343`). A malformed `v` yields empty output at full
cost on both sides.

**`BLAKE2F` input validation matches.** Exactly 213 bytes, final-flag byte
restricted to 0 or 1, rounds read big-endian from the first four bytes
(`src/runtime/evm/precompiles/blake2f.lisp:13-27,64-69`).

**BN254 point validation is present, including the G2 subgroup check.**
`bn254-g2-on-curve-p` and `bn254-g2-subgroup-p`
(`src/runtime/evm/precompiles/bn254-g2.lisp:8,57-58,76-80`) reject off-curve and
off-subgroup twist points before pairing, which is what geth gets from
`newTwistPoint`'s unmarshal (`core/vm/contracts.go:707-715`).

**`MODEXP` fork gating matches.** EIP-2565 pricing from Berlin, EIP-7883 pricing
and the EIP-7823 1024-byte length cap from Osaka
(`src/runtime/evm/precompiles/modexp.lisp:48-81`), matching geth's
`bigModExp{eip2565, eip7823, eip7883}` flags per fork set
(`core/vm/contracts.go:75,102,131,157`). `docs/gas-parity.md` differentially
verified the arithmetic; this pass verified only the gates.

**Interpreter mechanics match on the items checked.** The stack limit is 1024
and the call/create depth limit is 1024 (`src/runtime/evm/types.lisp:158-159`),
matching geth's `params.StackLimit` and `params.CallCreateDepth`. A call at the
depth limit pushes 0, transfers no value, and returns the whole child gas
(`src/runtime/evm/interpreter/call.lisp:167-169`), and `CREATE` at the limit or
with insufficient balance or a nonce at `2^64-1` pushes 0 without incrementing
the nonce (`src/runtime/evm/interpreter/create.lisp:27-35`). Static-call write
protection covers `SSTORE`, `TSTORE`, `LOG*`, `CREATE`, `CREATE2`,
`SELFDESTRUCT`, and value-bearing `CALL`
(`state-memory.lisp:65,159`, `stack-log.lisp:27`, `system.lisp:11,46,81,192`),
and `read-only-p` propagates into children and is never cleared
(`src/runtime/evm/context.lisp:35`, call sites in `system.lisp:98,133,162,186`).
`RETURNDATACOPY` bounds-checks against the buffer rather than padding
(`memory.lisp:79-83`), matching geth's `ErrReturnDataOutOfBounds`. Revert
preserves return data and restores the frame snapshot while an exceptional halt
discards return data and burns the child gas limit
(`system.lisp:224-234`, `results.lisp:3-28`). Return data is reset per frame
(`machine.lisp:31-32,46-50`). `MSIZE` reports the word-aligned length
(`state-memory.lisp:132`, `memory.lisp:6-14`). One level of EIP-7702 delegation
is resolved and no further (`state.lisp:75-80`), matching geth's `resolveCode`.

**`SELFDESTRUCT`-to-self is equivalent pre-Amsterdam** — see the EIP-8246 row of
EVM-18 for the reasoning. `docs/gas-parity.md` listed this as read-but-not-run;
it is still not run, but the two code paths now have a stated argument for
equivalence.

## Remediation plan for this area

Ordered by consensus risk against chains this client can actually be pointed at,
then by cost. Sizes are S (hours), M (a day or two), L (more). Each item names
the verification that would prove it fixed and the `PROJECT.md` principle it
protects.

**1 — Gate the Amsterdam Engine methods on Amsterdam EVM support. (S)**
Dependencies: none. Add an Amsterdam-execution availability predicate and mark
`engine_newPayloadV5`, `engine_getPayloadV6`, and `engine_forkchoiceUpdatedV4`
unavailable until items 2–5 land, following the `:kzg-p` pattern already in
`src/api/engine/methods.lisp:14-28`. This is the cheapest item in the plan and
it converts four consensus-breaking gaps into one honest refusal.
Verification: an Engine test asserting `engine_newPayloadV5` is neither
advertised by `engine_exchangeCapabilities` nor dispatched while the predicate is
false, mirroring the existing KZG capability tests.
Protects: **capability gating**.

**2 — Implement the four Amsterdam opcodes. (M)**
Dependencies: none. `SLOTNUM` needs a slot number on the EVM context and in the
block environment, which is the larger part of the work; `DUPN`, `SWAPN`, and
`EXCHANGE` are immediate-operand stack operations and need the immediate decoder
that geth has at `core/vm/instructions.go:983` onward. All four need Amsterdam
fork gates in the style of `require-context-fork`.
Verification: EEST `blockchain_tests`/`state_tests` for the Amsterdam fork once
item 8 supplies them; before that, unit tests in a new `tests/evm-amsterdam-tests.lisp`
asserting each opcode's stack effect, its gas, and that it raises pre-Amsterdam.
Protects: **derived, not trusted** — a block's `gasUsed` and receipts must come
from executing what the block actually says.

**3 — Correct the Amsterdam code-size constants. (S)**
Dependencies: none; do it with item 2 so Amsterdam changes land together. Set
`+amsterdam-max-contract-code-size+` to 65,536
(`src/protocol/chain-config/types.lisp:23`) and
`+block-access-list-amsterdam-max-code-size+` to match
(`src/protocol/block-access-lists/types.lisp:4`). Check whether the two should
be one constant.
Verification: a unit test asserting the Amsterdam code and initcode limits are
65,536 and 131,072 and that Osaka's remain 24,576 and 49,152; an EEST Amsterdam
`state_tests` deployment case once available.
Protects: **derived, not trusted**.

**4 — Implement EIP-7708 ETH-transfer system logs. (M)**
Dependencies: item 3 only for sequencing. The transfer log must be emitted from
wherever balance movement is authoritative — `transfer-call-value`
(`src/runtime/evm/state.lisp:57-73`) and `selfdestruct-account`
(`state.lisp:82-92`) for the EVM, plus the transaction-level transfer on the
execution path — and it must enter the same log list that `LOG*` appends to, in
the right order, so bloom and log index come out right. Note geth emits it for
the transfer itself, unconditionally on the Amsterdam rule, and separately in
`SELFDESTRUCT`.
Verification: a unit test asserting log count, topic, and data for a
value-carrying `CALL` at Amsterdam and its absence at Osaka; a receipts test
asserting the bloom and cumulative log index; EEST Amsterdam fixtures once
available.
Protects: **derived, not trusted** — receipts, log order, and bloom values are
computed, never taken from input.

**5 — Implement EIP-8037 and EIP-8038 as one change. (L) — COMPLETED**
Dependencies: item 6 (the fork-matrix gas test) should exist first, for the same
reason `docs/gas-parity.md` makes 3.2 a prerequisite of its 4.1: this change
touches the pricing of instructions that are correct today. It also wants
gas-parity 4.1 to have landed, because both thread `chain-rules` through the
same functions and doing it twice is wasted work. The scalar `gas-used` on
`evm-machine` (`machine.lisp:28`) has to become a two-dimensional budget, and
every `evm-machine-charge-gas` call site has to say which dimension it is
charging.
Verification: a fork-matrix table extended with an Amsterdam column; EEST
Amsterdam fixtures. Do not attempt this without the table.
Protects: **derived, not trusted**.

Remediation result (2026-07-29): `evm-gas-costs` and `evm-gas-budget` carry
regular gas, state gas, signed net state use, and regular spill. LIFO state
refunds repay spill before the state reservoir. The model is propagated across
CALL/CREATE child frames and transaction/block accounting. Tests transcribe
geth v1.17.5's SSTORE cases and pin SLOAD, all account reads, all four call
variants, CREATE/CREATE2 and code deposit, SELFDESTRUCT, access-list pricing,
refund/failure paths, receipt dimensions, and Engine capability/dispatch
gating. The external Amsterdam EEST corpus named above remains unavailable; it
is not an unimplemented semantic item.

**6 — Extend the fork-matrix gas test to Amsterdam and pin Osaka. (M)**
Dependencies: none, and it should start before item 5. This is
`docs/gas-parity.md` item 3.2 with a wider column set. The tables that matter
for this area are per-fork `(bytecode, expected gas)` rows derived from geth's
jump table at each fork, and per-fork precompile activation counts.
Verification: it *is* the verification for items 2, 3, and 5.
Protects: **derived, not trusted**.

**7 — Fix the honest-gating inconsistency in `POINT_EVALUATION`. (S)**
Dependencies: none. Narrow the `handler-case` in
`src/runtime/evm/precompiles/kzg.lisp:22-27` so an unavailable backend
propagates instead of becoming a precompile failure, exactly as
`call-bls12381-backend` does, which probably means giving the KZG module a
distinct unavailability condition rather than a plain `error`. Do the same audit
on the `handler-case` in `validate-blob-sidecar-kzg-proofs`
(`src/protocol/kzg/validation.lisp:78-84`), which has the same shape.
Verification: a unit test binding `*kzg-verifier*` to `nil` and asserting the
precompile signals rather than returning failure, plus the existing
point-evaluation tests with a verifier installed to confirm real failures still
fail.
Protects: **capability gating**.

**8 — Fork-gate EIP-7702 delegation resolution. (S)**
Dependencies: none. Add a rules parameter to `evm-resolved-code`
(`src/runtime/evm/state.lisp:75-80`) and `execution-resolved-code`
(`src/runtime/execution/state.lisp:30-35`) and return raw code when Prague is
not active. The call sites are few.
Verification: a unit test executing an account whose code is a delegation
designator under Cancun rules and asserting the designator bytes execute (which
means an immediate invalid-opcode halt on `0xef`), and under Prague rules
asserting the target runs. EEST `state_tests` for pre-Prague forks would cover
it once item 9 lands.
Protects: **derived, not trusted**.

**9 — Drop the storage-root term from `empty-account-p`. (S)**
Dependencies: this is the same edit as `docs/gas-parity.md` item 4.3 and should
land with it, not separately — but note that this pass widens its scope, so the
test set has to cover the `EXTCODEHASH` value as well as the gas. Check the
other caller in `src/runtime/evm/block.lisp` and confirm
`contract-address-collision-p` (`state.lisp:34-44`) keeps its storage term,
which is correct per EIP-7610 and must not be swept up in the change.
Verification: a unit test with a code-less, nonce-zero, balance-zero account
carrying one storage slot, asserting `EXTCODEHASH` pushes 0, asserting the
zero-value `CALL` and `SELFDESTRUCT` beneficiary gas from gas-parity 4.3, and a
separate test asserting the create-collision predicate still rejects that
account as a `CREATE2` target.
Protects: **derived, not trusted**.

**10 — Add fork-order validation to chain-config loading. (S)**
Dependencies: none. Port the shape of geth's `CheckConfigForkOrder`
(`params/config.go:930`) into `chain-config-from-genesis-config`
(`src/protocol/genesis/chain-config.lisp:48`): ascending activation points, and
no fork enabled with a mandatory predecessor unset.
Verification: unit tests rejecting a config with `osakaTime` set and
`pragueTime` unset, and one with `cancunTime` after `pragueTime`; a positive
test that mainnet's real schedule still loads.
Protects: **capability gating** — an impossible ruleset should be refused, not
executed.

**11 — Cache jump-destination analysis. (M)**
Dependencies: none. Compute a bitmap once per code object and cache it, keyed by
code hash for deployed code and per-frame for initcode, following geth's split
between `Contract.analysis` and the code-hash cache
(`core/vm/contract.go:66-99`). The cache belongs on the EVM context or on a
per-execution object, not in a global, so it cannot leak across blocks.
Verification: a unit test asserting a jump-heavy contract's gas is unchanged
(this must not alter a single gas number), plus a timing assertion or a
benchmark recorded outside the test suite. Establishing the magnitude of the
current cost is itself part of the work, since it is UNVERIFIED here.
Protects: nothing in the correctness list directly; it protects the node's
ability to keep up with a chain, which is a liveness precondition for all of
them.

**12 — Give memory geometric growth. (S)**
Dependencies: none, and it is a smaller change than item 11 for a comparable
benefit. Grow the backing vector with slack — doubling, floored at the aligned
size — while continuing to report the word-aligned *logical* size to `MSIZE`
and to memory-expansion gas, which must not change by a single unit.
Verification: a unit test asserting `MSIZE` and memory gas are byte-identical
before and after for a range of expansion sequences, including zero-size regions
at large offsets; the existing `tests/evm-memory-control-tests.lisp` should pass
untouched.
Protects: liveness, as item 11.

**13 — Make the stack limit check constant-time. (S)**
Dependencies: none. Track the depth on the machine alongside the stack, or move
to a vector-backed stack. The observable behavior must not change — including
the ordering `docs/gas-parity.md` blesses, where an overflow is reported on push.
Verification: the existing stack tests, plus a test asserting the error at
exactly 1025 pushes and success at 1024.
Protects: liveness.

**14 — Represent BLS availability in the Engine gate. (S)**
Dependencies: none. Export a `bls12381-available-p`-style predicate from
`src/protocol/bls12381/` and add a `:bls-p` marker to the Prague and later
Engine methods, alongside `:kzg-p`.
Verification: an Engine test asserting `engine_newPayloadV4` is not dispatched
with the BLS backend absent.
Protects: **capability gating**.

**15 — Extend interpreter tracing hooks, or narrow the documented claim. (M)**
Dependencies: none, and it is the lowest-priority item here. Two separable
pieces: label `CREATE`, `CREATE2`, `DELEGATECALL`, and `CALLCODE` frames
correctly, which is cheap and purely additive
(`src/runtime/evm/interpreter/call.lisp:265-272`,
`src/runtime/evm/interpreter/create.lisp`); and decide whether a per-opcode hook
is wanted at all, given that `tracing.lisp:10-14` argues against it on cost
grounds. If the answer is no, the RPC-side documentation should say plainly which
tracers can never be served.
Verification: call-tracer tests asserting the frame type for each of the five
call kinds.
Protects: nothing in the correctness list; this is an observability and honesty
item.

**16 — Consider a precompile result cache. (M)**
Dependencies: prefer after items 11 and 12, which are cheaper and broader.
Follow geth's constraint that gas accounting and state effects are identical on
hit and miss (`core/vm/contracts.go:286-302`), and keep the cache scoped so it
cannot outlive a block.
Verification: a test asserting identical gas and output for a repeated
precompile call with the cache enabled and disabled.
Protects: liveness.

## Explicitly out of scope or left unverified

**Nothing in this document was executed.** The dev container and image were
absent and this audit could not start them, so there is not a single measured
number here. Where `docs/gas-parity.md` has differential tests over generated
input spaces, this document has source reading. That is adequate for structural
claims — an absent opcode, an absent constant, a missing parameter — and
inadequate for anything about magnitude. Do not carry any finding here into a
commit message as verified.

**Gas arithmetic was not re-derived.** `docs/gas-parity.md` covers memory
expansion, the dynamic gas of every instruction family, `SSTORE`/`SLOAD` under
EIP-2929 and EIP-3529, the call family with the stipend and the 63/64 rule,
`CREATE`/`CREATE2` with EIP-3860, `EXP`, `LOG`, the copy family, `KECCAK256`,
`SELFDESTRUCT`, `TSTORE`/`TLOAD`, EIP-7702 delegation costs, blob gas, and the
EIP-7623 calldata floor. This pass confirmed that its open findings are still
open by re-reading the cited functions, and did not attempt to improve on its
numbers. Its own limitation stands: its reference pins are spread across three
geth versions and three Nethermind versions, and its item 3.4 — re-verify every
finding against one pinned reference — is now cheaper than when it was written,
because `references/` exists.

**Performance magnitudes are UNVERIFIED.** EVM-10, EVM-11, and EVM-12 state
complexity claims that follow from the code and give the input shape that would
measure them. None was measured. It is possible that constant factors make one
or more of them a non-issue at realistic block gas limits; it is also possible
that one of them is the single largest practical problem in this area. A
follow-up should benchmark all three before any of items 11–13 is scheduled,
because the ordering among them depends on the answer.

**EIP-7928 depth was not assessed.** `src/protocol/block-access-lists/` exists
and this pass only established that the interpreter-side touching geth performs
(`core/vm/contracts.go:283-285`, `core/state/statedb.go:328`) has no counterpart
in our EVM. Whether the block-level implementation is otherwise complete belongs
to the block-execution and state auditors.

**Five Amsterdam EIPs were not assessed:** 2780, 7976, 7981, 7778, and 8282.
They land in intrinsic gas, calldata pricing, access-list pricing, block gas
policy, and the requests surface. See the EVM-18 table for the geth entry points.

**The merge predicate equivalence was not settled** (EVM-15). Whether
`block-header-post-merge-p` agrees with geth's `IsMerge` on every header the
import path can construct — and what the call-simulation path's hardcoded
`:random-p t` does for a pre-merge block — needs either a proof or a test.

**Pre-Berlin reachability is still open**, as `docs/gas-parity.md` records:
nothing here established whether the block-import path ever constructs
pre-Berlin `chain-rules` in production. EVM-07's practical reachability inherits
that uncertainty.

**Not examined at all in this area:** the transaction and receipt layer, the
txpool, networking, storage, the RPC surface including tracing endpoints, block
building, and consensus header validation. Where a finding above touches those,
it says so.

**Overlaps to dedupe with other auditors.** EVM-04 and EVM-16 are Engine-API
capability findings surfaced from the EVM side. EVM-05 changes receipts, blooms,
and log indexes, so it overlaps the receipt and `eth_getLogs` areas. EVM-08
concerns an account-emptiness predicate that the state layer also depends on.
EVM-09's simulation half belongs to whoever owns `eth_call` and
`eth_estimateGas`. EVM-06's fork-order validation is a genesis and chain-config
concern. The EIP-7928 row of EVM-18 is mostly block execution.
