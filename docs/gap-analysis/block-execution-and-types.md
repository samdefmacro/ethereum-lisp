# Domain types, validation, and block execution — gap analysis

This document records an audit of one area of the client: the block, transaction
and receipt domain types, header and body validation, and the state-transition
pipeline that executes a block. It is a snapshot of the code, not a plan that
has been carried out. Nothing described here as missing or divergent has been
changed; the only file this audit wrote is this one.

## Sources read

| Side | Version | Commit | Read on |
| --- | --- | --- | --- |
| ethereum-lisp | working tree | `28e9912072135bebc3f49bc75226d6fed68dc21f` | 2026-07-28 |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` | 2026-07-28 |

Both reference checkouts are present under `references/`. The Nethermind
checkout is sparse and contains `src/Nethermind` only. Line numbers on all three
sides are relative to those commits; function and method names are the durable
identifier and should be preferred when a line has moved.

Our files read in full or in substantial part: `src/protocol/blocks/`
(`types.lisp`, `header-rlp.lisp`, `rlp-encode.lisp`, `rlp-decode.lisp`),
`src/protocol/transactions/` (all eight files), `src/protocol/receipts/`,
`src/protocol/execution-requests/`, `src/protocol/block-access-lists/`,
`src/protocol/genesis/`, `src/protocol/consensus/` (`validation.lisp`,
`transaction-validation.lisp`, and all of `block-validation/`),
`src/runtime/execution/` (block execution, system calls, message lists,
apply-message, apply-contract, accounting, gas, validation,
transaction-fields, signatures, set-code, prague-requests, rewards, rules),
`src/foundation/rlp.lisp`, `src/foundation/crypto/secp256k1.lisp`, the fixture
runner selectors and loaders under `tests/`, and `scripts/fetch-eest-fixtures.sh`.

Their counterparts: geth `core/types/`, `core/block_validator.go`,
`core/state_processor.go`, `core/genesis.go`, `consensus/beacon/consensus.go`,
`consensus/ethash/consensus.go`, `consensus/misc/eip1559/`,
`consensus/misc/eip4844/`, `consensus/misc/dao.go`, `params/config.go`;
Nethermind `Nethermind.Core/TxType.cs`, `Nethermind.Core/Transaction.cs`,
`Nethermind.Consensus/Validators/`, `Nethermind.Evm/BlobGasCalculator.cs`.

The warm dev container was absent for the duration of this audit
(`scripts/dev.sh status` reported both container and image absent) and the
instructions for this audit forbid starting it, so no finding below is backed by
an evaluation in a running image. Every claim about our behaviour comes from
reading the source. Where reading alone could not settle a question the verdict
is UNVERIFIED and says so.

This audit overlaps `docs/gas-parity.md` in two places, noted inline. Where it
does, this document is the later reading and is pinned to reference checkouts
that the gas-parity audit did not have.

## Executive summary

The ten most consequential gaps, ordered by consensus risk.

1. **EXEC-01** — The EIP-7918 reserve-price comparison uses the *parent's* blob
   base-fee update fraction where both geth and Nethermind use the *child's*.
   On the first block of a BPO fork that changes the fraction we can compute a
   different `excessBlobGas` than the rest of the network and split.
2. **EXEC-02** — Uncles are never validated beyond the header hash, yet uncle
   rewards are paid, so a pre-merge block can mint reward to fabricated uncles
   and still satisfy every check we run.
3. **EXEC-03** — Whether a block is post-merge is inferred from the header's own
   difficulty rather than from the chain configuration, so on a chain configured
   post-merge from genesis a block that declares PoW difficulty skips all the
   proof-of-stake header checks that geth applies.
4. **EXEC-04** — There is no proof-of-work seal verification and no difficulty
   formula: for any pre-merge header the difficulty field is accepted as given.
5. **EXEC-05** — The DAO fork is parsed from the chain config but neither the
   state transition nor the extra-data header rule is implemented, so a mainnet
   replay diverges at block 1,920,000.
6. **EXEC-06** — The block access list is validated when supplied but never
   derived from execution, so an Amsterdam block that omits it cannot be
   validated and we cannot produce one.
7. **EXEC-15** — No fixture the harness selects executes any fork later than
   Shanghai: 362 blockchain selectors are all `fork_Shanghai` and every state
   selector is London or Shanghai, so Cancun, Prague and Osaka block execution
   has zero fixture coverage and none of the findings above would be caught.
8. **EXEC-07** — Amsterdam's EIP-7997 irregular state transition and EIP-8282
   builder request types 0x03/0x04 are absent, so both the state root and the
   requests hash will be wrong at Amsterdam activation.
9. **EXEC-11** — There is no EIP-4844 network-wrapper codec and no EIP-7594
   version byte, and the KZG blob-proof verifier that does exist has no caller
   in `src/` at all, so no live path ever checks a blob against its commitment.
10. **EXEC-12** — There are no built-in chain presets, so the client cannot
    construct the mainnet, Sepolia, Holesky or Hoodi genesis state from anything
    in the tree.

## Findings

### EXEC-01 — EIP-7918 excess blob gas uses the parent's update fraction

**Verdict** DIVERGENT. **Severity** consensus-breaking.

Our evidence: `src/protocol/consensus/block-validation/fees.lisp:55-85`.
`expected-excess-blob-gas` takes both an `update-fraction` and a separate
`parent-update-fraction`, and the EIP-7918 reserve-price branch at lines 76-85
evaluates `blob-base-fee` of the parent's excess using `parent-update-fraction`.
The caller that supplies it is
`src/protocol/consensus/block-validation/header.lisp:183-203`, which resolves the
parent's own blob schedule specifically for this purpose. The choice is
deliberate and carries a comment at `fees.lisp:66-70` explaining it.

Reference evidence (geth): `consensus/misc/eip4844/eip4844.go:129-136` resolves
`bcfg` from `latestBlobConfig(config, headTimestamp)` — the *child's* timestamp —
and `:155-162` uses that same `bcfg` for `bcfg.blobPrice(parentExcessBlobGas)` at
`:159` in the reserve-price comparison. Reference evidence (Nethermind):
`src/Nethermind/Nethermind.Evm/BlobGasCalculator.cs:145-158` uses
`releaseSpec.BlobBaseFeeUpdateFraction`, and the release spec passed in by
`src/Nethermind/Nethermind.Consensus/Validators/HeaderValidator.cs:354` and
`:382-383` is the spec of the header being validated, not of its parent.

Consequence: consider the first block after a BPO fork that changes the update
fraction, where the parent's excess and base fee put the blob price near the
reserve price. Our fraction and theirs give different blob prices, the
comparison can fall on different sides, and the two implementations then compute
different `excessBlobGas` for the same parent. We reject the canonical header,
or accept one the network rejects. Both references agree with each other and
disagree with us, which makes this the clearest consensus risk in the area.

This is the same behaviour as `docs/gas-parity.md` finding 1.3, which recorded
the divergence but could not establish which side was right because it had no
pinned checkout. Both pinned references now answer it. Dedupe against that item.

### EXEC-02 — No uncle validation, but uncle rewards are paid

**Verdict** MISSING. **Severity** consensus-breaking on pre-merge chains.

Our evidence: the only uncle checks in the tree are the commitment hash and the
post-merge emptiness rule —
`src/protocol/consensus/block-validation/roots.lisp:55-59` and
`src/runtime/execution/block-body-validation.lisp:60-64`. Ommer shape validation
at `src/protocol/consensus/block-validation/body.lisp:35-40` checks only that
each entry is a `block-header`. Nothing bounds the count, checks ancestry or
depth, rejects duplicates, or validates the uncle header itself. Meanwhile
`src/runtime/execution/rewards.lisp:12-30` pays a reward per uncle:
`block-reward-for-rules` adds `base-reward/32` per uncle to the beneficiary and
`apply-block-ommer-rewards` credits each uncle's own beneficiary an amount
scaled by `(uncle.number + 8 - header.number)`.

Reference evidence (geth): `consensus/ethash/consensus.go:158-215` `VerifyUncles`
caps the count at `maxUncles`, walks seven ancestors, rejects duplicates and
ancestors, and verifies each uncle header. It is invoked from
`core/block_validator.go:64-66`. Reference evidence (Nethermind):
`src/Nethermind/Nethermind.Consensus/Validators/BlockValidator.cs:97-122`
enforces `spec.MaximumUncleCount` and then delegates to `UnclesValidator`.

Consequence: a pre-merge block carrying an arbitrary number of fabricated uncle
headers — any headers at all, as long as their RLP keccak equals the header's
`ommersHash` — passes every check we run and mints `base_reward/32` per uncle to
the beneficiary plus a scaled reward to each fabricated uncle's beneficiary. The
resulting state root differs from both references, which reject the block. The
`ommer-block-reward` term can also go negative for an uncle far below the block,
which `state-db` may or may not tolerate; that sub-case is UNVERIFIED.

This is only reachable on a chain that has pre-merge blocks. No in-repo document
found during this audit scopes proof-of-work out — `PROJECT.md`,
`docs/validation.md` and `docs/architecture.md` were searched for
"proof-of-work", "ethash", "pre-merge" and "PoW" with no match — so the omission
is undocumented rather than a stated limitation.

### EXEC-03 — Post-merge status is inferred from the header, not the config

**Verdict** DIVERGENT. **Severity** consensus-breaking, configuration dependent.

Our evidence: `src/protocol/consensus/block-validation/forks.lisp:69-71`.
`block-header-post-merge-p` is `(and (plusp number) (zerop difficulty))`, and
`src/protocol/consensus/block-validation/header.lisp:204` passes exactly that as
`:post-merge-p` even though it has the full chain config in hand. Every
proof-of-stake header rule — zero difficulty, zero nonce, empty uncle hash, the
`MaxGasLimit` bound — is inside `validate-block-merge-fields`
(`forks.lisp:86-98`) and runs only when that predicate is true. The config does
carry the merge fields: `chain-config-terminal-total-difficulty` and
`merge-netsplit-block` are parsed at
`src/protocol/genesis/chain-config.lisp:87-92`, but the only consumers found are
the Engine API's TTD echo (`src/api/engine/new-payload.lisp:138-145`) and
capabilities.

Reference evidence (geth): `consensus/beacon/consensus.go:211-234` runs the PoS
header checks unconditionally for any header the beacon engine routes to
`verifyHeader`, and the routing is by `IsPostMerge(number, time)` from the chain
config, not by the header's own difficulty. Reference evidence (Nethermind):
`src/Nethermind/Nethermind.Consensus/Validators/HeaderValidator.cs:89-90` calls
`ValidateTotalDifficulty` and `ValidateSeal` for every non-orphaned header, and
`:294-321` compares the declared total difficulty against
`parent.TotalDifficulty + header.Difficulty`.

Consequence: on a chain configured post-merge from genesis — the ordinary shape
for a devnet or an EEST blockchain fixture — a block at height 1 that declares
`difficulty = 0x20000`, a nonzero nonce, and a non-empty uncle hash is treated
by us as a pre-merge block. It skips all four PoS checks and, because of
EXEC-04, its difficulty is never checked against a formula either. Geth rejects
it with "invalid difficulty". The exposure is bounded once the chain is
established: `validate-block-merge-transition` (`forks.lisp:80-84`) refuses to
return to nonzero difficulty when the parent already has zero, so the attack
surface is the transition block and any chain whose earliest blocks we import.

### EXEC-04 — No proof-of-work seal or difficulty formula

**Verdict** MISSING. **Severity** correctness.

Our evidence: `validate-block-header-basics`
(`src/protocol/consensus/block-validation/header.lisp:62-174`) validates number,
timestamp, gas used against gas limit, the gas limit delta, extra-data length,
the fork-specific field presence rules, blob gas and base fee. It never computes
an expected difficulty and never checks a mix hash or nonce against an ethash
seal. `block-header-difficulty` is read in nine places across the tree and
written in none of the validation paths.

Reference evidence (geth): `consensus/ethash/consensus.go` `verifyHeader`
computes `CalcDifficulty(chain.Config(), header.Time, parent)` and compares, and
`VerifySeal` checks the PoW solution. Reference evidence (Nethermind):
`HeaderValidator.cs:214-217` delegates to `ISealValidator.ValidateParams`.

Consequence: any pre-merge header is accepted with any difficulty value. A
canonical-looking chain of low-difficulty headers costs nothing to produce.
Combined with EXEC-03 this means the client has no proof-of-work notion at all,
which is a defensible scope decision for a post-merge client but is not written
down anywhere in the repository.

### EXEC-05 — DAO fork parsed but not implemented

**Verdict** MISSING. **Severity** correctness (historical replay only).

Our evidence: `src/protocol/genesis/chain-config.lisp:52-53` parses
`daoForkBlock` and `daoForkSupport`, and
`src/protocol/chain-config/forks.lisp:12-13` exposes `chain-config-dao-fork-p`.
No caller applies a state transition. A search of `src/runtime/execution/` for
any DAO-related symbol returns nothing, and `validate-block-header-basics` has
no extra-data rule beyond the 32-byte length cap
(`header.lisp:130-132`).

Reference evidence (geth): `core/state_processor.go:82-83` calls
`misc.ApplyDAOHardFork` when the block number equals `DAOForkBlock`, and
`consensus/misc/dao.go:51-71` enforces `DAOForkBlockExtra` in the extra-data
field over the ten-block `DAOForkExtraRange`.

Consequence: replaying mainnet block 1,920,000 produces the wrong state root
because the drain-list balances are never moved to the refund contract, and
headers in blocks 1,920,000 through 1,920,009 are accepted regardless of their
extra-data. Only reachable on a full replay from genesis.

### EXEC-06 — Block access list is validated but never derived

**Verdict** MISSING. **Severity** completeness (becomes consensus-breaking at Amsterdam).

Our evidence: `src/runtime/execution/block-body-validation.lisp:91-115` compares
a *supplied* access list against the header commitment and fails with "Missing
block access list in block body" when the header commits to one and no body was
supplied. `src/runtime/execution/block-execution.lisp:50-54` only normalizes the
supplied input. Nothing in `src/runtime/execution/` constructs a
`block-access-list` from execution results; the types and the RLP codec exist
(`src/protocol/block-access-lists/`) but have no producer.

Reference evidence (geth): `core/block_validator.go:116-134` validates an
attached access list directly, and the comment at `:120-123` states explicitly
that when the block does not include one it is computed locally during execution
and checked against the header hash. The construction is threaded through
`core/state_processor.go:104` (pre-execution merge), `:128` (per-transaction
merge) and `:135` (post-execution merge). Reference evidence
(Nethermind): `BlockValidator.cs:82` `ValidateBlockLevelAccessList` and
`HeaderValidator.cs:385-395` `ValidateBlockAccessListHash`.

Consequence: at Amsterdam, an ordinary canonical block delivered over the wire
without an attached access list cannot be validated at all — we reject it as
missing a body field where geth builds the list and verifies the hash. We also
cannot produce a valid Amsterdam block, since the header commitment has no
source. Amsterdam is unscheduled, so this is completeness today.

### EXEC-07 — EIP-7997 and EIP-8282 absent from the pipeline

**Verdict** MISSING. **Severity** completeness (Amsterdam).

Our evidence: `src/runtime/execution/block-execution.lisp:99-106` runs exactly
two pre-execution system calls, EIP-4788 and EIP-2935. There is no irregular
state transition at Amsterdam activation.
`src/runtime/execution/prague-requests.lisp:15-17` defines request types 0x00,
0x01 and 0x02 only, and `derive-prague-execution-requests` (`:102-133`) collects
exactly those three.

Reference evidence (geth): `core/state_processor.go:161-164` applies
`misc.ApplyEIP7997` on the Amsterdam activation block when the parent is
pre-Amsterdam; `:206-214` calls `ProcessBuilderDepositQueue` and
`ProcessBuilderExitQueue` when Amsterdam is active, and `:391-401` shows those
emit request types 0x03 and 0x04.

Consequence: at Amsterdam activation the state root is wrong (missing factory
account) and the requests hash is wrong for every block (missing types 0x03 and
0x04). Not reachable until Amsterdam is scheduled.

### EXEC-08 — EIP-2935 system call failure is swallowed

**Verdict** DIVERGENT. **Severity** correctness (low reachability).

Our evidence: `src/runtime/execution/system-calls.lisp:115-136` calls
`execute-protocol-system-call` for the history contract with neither
`:require-code-p` nor `:require-success-p`, and `:74-91` shows that a revert or
an `evm-error` restores the snapshot and returns quietly.

Reference evidence (geth): `core/state_processor.go:369-372` — `ProcessParentBlockHash`
panics on any error returned by `evm.Call`. Note the contrast with
`ProcessBeaconBlockRoot` at `:339`, which discards the error deliberately; our
EIP-4788 handling matches geth there.

Consequence: on a chain whose history contract reverts, geth crashes the node
and imports nothing while we roll back the call and import the block. Only
reachable on a chain with a broken or absent EIP-2935 predeploy, where the two
implementations are already not going to agree. Recording it because the
asymmetry between geth's two system calls is easy to miss when this code is next
touched.

### EXEC-09 — Request system calls require code and success; geth does not

**Verdict** DIVERGENT. **Severity** correctness, direction undecided.

Our evidence: `src/runtime/execution/prague-requests.lisp:91-100`.
`checked-request-system-call-data` passes `:require-code-p t` and
`:require-success-p t`, so a withdrawal or consolidation predeploy that has no
code, or whose call reverts, fails the block
(`src/runtime/execution/system-calls.lisp:41-44` and `:76-79`).

Reference evidence (geth): `core/state_processor.go:403-441`
`processRequestsSystemCall` returns an error only when `evm.Call` errors, and a
call to a codeless address does not error — it returns empty output, which
`:433-435` skips. A missing predeploy therefore yields no requests and a valid
block in geth.

Consequence: on a Prague chain where the EIP-7002 or EIP-7251 predeploy is
absent, we reject the block and geth accepts it. Our behaviour matches the
"checked system call" the EIPs describe, so this is not obviously our bug; it
needs a decision against `ethereum/execution-specs` rather than against geth.
The empty-output case matches geth exactly: we append a request only when the
returned data is non-empty (`prague-requests.lisp:121,129`), as geth does at
`:433-435`.

### EXEC-10 — Withdrawals are applied before the request system calls

**Verdict** DIVERGENT. **Severity** correctness, no observable difference established.

Our evidence: `src/runtime/execution/block-execution.lisp:127-133` — withdrawals
are credited immediately after the transaction loop, and
`derive-prague-execution-requests` runs afterwards.

Reference evidence (geth): `core/state_processor.go:131` — `PostExecution`
(deposit log parsing plus the EIP-7002 and EIP-7251 system calls) runs first, and
`Engine().Finalize` at `:141`, which credits withdrawals
(`consensus/beacon/consensus.go:351-370`), runs after. Geth carries a `TODO` at
`:137-138` about folding `Finalize` into `PostExecution`.

Consequence: the two orders produce the same state only if the request
predeploys do not read any balance that a withdrawal can change. The canonical
EIP-7002 and EIP-7251 bytecode does not, so no divergence is expected in
practice, and our order is the one the execution specs describe. Recorded as a
structural difference rather than a bug; whether any observable difference
exists for a non-canonical predeploy is UNVERIFIED.

### EXEC-11 — No blob sidecar network wrapper, and the KZG check has no caller

**Verdict** MISSING. **Severity** completeness for the codec, correctness for
the unwired verifier — PROJECT.md names "real cryptography on real paths" as a
correctness principle and this is the clearest place the tree does not meet it.

Two separate absences, recorded together because they have the same cause.

The wrapper codec. `src/protocol/transactions/blob.lisp` defines
`blob-transaction-from-rlp` for the 14-field canonical form only (`:101-110`).
There is no decoder for the EIP-4844 network wrapper
(`[tx_payload, blobs, commitments, proofs]`) and no version byte anywhere. The
`blob-sidecar` struct is an Engine-API blobs bundle carrier; its consumers are
`src/api/engine/payload-codecs.lisp:74-87` and the store at
`src/storage/chain-store/service/cache.lisp:105-142`, which checks list lengths
only.

The verification. A real KZG verifier does exist and is properly capability
gated: `src/protocol/kzg/validation.lisp` defines `verify-kzg-blob-proof`
(`:52-66`), `validate-blob-sidecar-kzg-proofs` (`:68-85`) and
`validate-blob-sidecar-fields` (`:87-`), backed by a c-kzg CFFI binding at
`src/protocol/kzg/cffi-verifier.lisp:23-83`. But neither sidecar entry point has
a caller anywhere in `src/`: the only references outside the module are the two
package export lists (`src/packages/kzg.lisp:32`,
`src/packages/facade.lisp:371`). The commitment-to-versioned-hash relation *is*
checked where sidecars are read back from the key-value store
(`src/storage/node-store/persistence/import/blobs.lisp:56-64`), and that record
format already carries EIP-7594 cell proofs, but nothing on any live path
verifies a blob against its commitment and proof.

Reference evidence (geth): `core/types/tx_blob.go` `BlobTxSidecar` carries a
`Version` field for EIP-7594 and geth decodes and validates the wrapper.
Reference evidence (Nethermind):
`src/Nethermind/Nethermind.Core/Transaction.cs:391-395` defines
`ShardBlobNetworkWrapper(Blobs, Commitments, Proofs, ProofVersion)` with a
`ProofVersion` enum, and
`src/Nethermind/Nethermind.Core/Specs/IReleaseSpecExtensions.cs:56` selects
`ProofVersion.V1` under EIP-7594.

Consequence: we cannot accept, serve, or verify a pooled blob transaction, and
no code path we own ever runs a KZG proof check even though the verifier is
present and wired to a real backend. This is a *documented* limitation in its
first half, not an oversight:
`src/networking/eth-sync/gossip.lisp:15-21` states that blob transactions are
excluded from every announcement, broadcast and reply precisely because the
sidecar wire representation has moved and we build no blob payloads. Recorded
here because the missing codec is in the transaction types this area owns.
Overlaps networking and txpool.

### EXEC-12 — No built-in chain presets

**Verdict** MISSING. **Severity** completeness.

Our evidence: `src/protocol/genesis/` parses a genesis JSON document into a
chain config (`chain-config.lisp`), an allocation (`alloc.lisp`), and a header
and block (`block.lisp`). A search of `src/protocol/genesis/` and
`src/protocol/chain-config/` for "mainnet", "sepolia", "holesky" and "hoodi"
returns two prose comments and no data.

Reference evidence (geth): `core/genesis.go:642-690` defines
`DefaultGenesisBlock`, `DefaultSepoliaGenesisBlock`, `DefaultHoleskyGenesisBlock`
and `DefaultHoodiGenesisBlock`, each with an embedded allocation.

Consequence: the client cannot be started against a public network without an
externally supplied genesis JSON that includes the full allocation, and the
mainnet genesis state root cannot be reproduced from anything in the repository.
Related: `src/protocol/genesis/block.lisp` assigns fixed empty and zero values
for `blockAccessListHash` and `slotNumber` when they are absent from the JSON
rather than leaving them unset, which will need revisiting for an Amsterdam
genesis.

### EXEC-13 — Header RLP encoding is presence-driven, not fork-driven

**Verdict** DIVERGENT. **Severity** correctness (latent).

Our evidence: `src/protocol/blocks/header-rlp.lisp:29-67`. Each optional field is
appended only when its own accessor is non-nil, so the encoder produces a
*compacted* list rather than a positional one. A header with `parentBeaconRoot`
set but `blobGasUsed` unset silently emits the beacon root in the position where
a decoder expects `blobGasUsed`. Lines 54-62 emit a zero-length string in the
access-list-hash slot when only `slotNumber` is set. On the decode side,
`src/protocol/blocks/rlp-decode.lisp:5-7` accepts only the field counts
`(15 16 17 20 21 22 23)`, rejecting 18 and 19.

Reference evidence (geth): `core/types/block.go` tags every optional header field
`rlp:"optional"`, which means the encoder refuses to emit a set field after a nil
one and the decoder accepts every prefix length from 15 upward, deferring the
fork-shape question to header validation.

Consequence: for every shape a valid chain can produce, the two encodings agree,
because Cancun implies Shanghai implies London and the fields are therefore
always contiguous. The divergence is reachable only for a header constructed
in-process with a gap, which would hash to a value geth would never compute for
the same field set. The decoder's allowlist is what keeps this from being
reachable from the wire, which makes the allowlist load-bearing in a way the code
does not say. Rejecting counts 18 and 19 is not itself a consensus difference:
geth decodes those and then rejects them in header validation, so both
implementations refuse the block.

### EXEC-14 — Unbounded recursion in the RLP decoder

**Verdict** UNVERIFIED. **Severity** correctness if confirmed.

Our evidence: `src/foundation/rlp.lisp:58-70` and `:99-116`. `decode-list-payload`
and `rlp-decode` are mutually recursive with no depth counter, so decoding *n*
nested single-item lists (`0xc1` repeated *n* times followed by one byte) costs
*n* stack frames. A megabyte of such input asks for roughly a million frames.
SBCL signals control stack exhaustion as a `storage-condition`, which is not a
subtype of `error`, so the `handler-case ... (error ...)` wrappers that guard the
decode paths — for instance
`src/protocol/transactions/legacy.lisp:60` and
`src/runtime/execution/block-execution.lisp:186-189` — would not contain it.

Reference evidence (geth): the `rlp` package decodes into a known Go type, so
nesting depth is bounded by the target type rather than by the input; a
`[]byte`-shaped field cannot recurse. Nethermind's `RlpStream` is likewise
type-driven.

Consequence, if confirmed: a crafted block body or transaction from a peer
terminates the decoding thread, or the process, instead of being rejected. This
is marked UNVERIFIED rather than asserted because settling it requires running a
deep decode in an image, which this audit could not do. The other canonicality
rules in the same file are all present and correct: trailing bytes are rejected
at the top level (`:117-118`), non-minimal single-byte strings at `:86-88`,
long-form encodings of short payloads at `:94-96` and `:110-112`, and leading
zeros in a multi-byte length at `:48-50`. The one-byte-length case that the
leading-zero rule does not cover (`0xb8 0x00`) is caught by the short-payload
rule instead, so there is no hole there.

### EXEC-15 — No fixture the harness selects runs a fork later than Shanghai

**Verdict** MISSING (coverage). **Severity** correctness — this is the reason the
other findings survive.

Our evidence, all established by counting the selector files rather than by
running anything:

| Fixture format | Selectors | Forks selected |
| --- | --- | --- |
| `blockchain_tests_engine` | 362, of which 344 are `blockchain_test_engine_from_state_test` and 18 are `blockchain_test_engine` | `fork_Shanghai` only, 362 of 362 |
| `blockchain_tests` (non-engine) | 0 | none |
| `state_tests` | 94 explicit case names plus 21 generator functions | `fork_London` and `fork_Shanghai` only |
| `transaction_tests` | 12 real EEST files plus 30 vectors from a hand-authored sample | the 12 are all `prague/eip7702_set_code_tx/test_invalid_*`; the sample targets Shanghai |

Sources: `tests/fixture-runner-blockchain-selectors.lisp` (every `fork_` token in
the file is `fork_Shanghai`), `tests/fixture-runner-state-selectors.lisp`
(literal names at lines 688-782; `fork_London` appears 38 times and
`fork_Shanghai` 58, and the 21 generator functions interpolate over the same
two-element fork list), `tests/transaction-fixture-shape.lisp:9-34` and `:36-66`
(both positive case-name lists point at
`transaction_tests/phase-a-sample.json`, a hand-authored file, not at the pinned
corpus) and `:68-80` (the twelve genuine EEST files), and
`tests/transaction-fixture-shape.lisp:147-148`
(`+phase-a-eest-transaction-target-fork+` is `"Shanghai"`).

The bundled corpus under `tests/fixtures/execution-spec-tests-root/` is 27 JSON
files. The pinned corpus is fetched by `scripts/fetch-eest-fixtures.sh` — EEST
`v5.4.0`, `fixtures_stable.tar.gz`, sha256
`92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909` — into
`.eest-fixtures`, which does not exist on this machine, so today even the
Shanghai selectors above select nothing and the tests skip.

Consequence: blob gas, `excessBlobGas`, the EIP-7918 branch, the EIP-4788 and
EIP-2935 system calls, execution requests, EIP-7702 block execution, the
EIP-7623 calldata floor and the EIP-7825 gas cap have no executing fixture
anywhere in the suite. EXEC-01 in particular is exactly the kind of finding a
Cancun-or-later blockchain fixture set would catch immediately.

Two parts of this are UNVERIFIED. First, the exact number of state-test cases
the 21 generators expand to: arithmetic on the loop bounds puts it on the order
of 950 including the 94 literals, but that figure was computed by hand and not
executed. Second, the list of fixture families present in EEST `v5.4.0` that we
do not run: the archive is not on disk and this audit did not download it, so
the families can only be named by inference from the directory layout the
selectors use. What *is* verified is the fork ceiling, and that is the number
that matters.

This extends `docs/gas-parity.md` item 3.1, which quantified the bundled corpus
but not the pinned-corpus selectors. Dedupe against that item.

### EXEC-16 — `receipt-list-root` cannot encode typed receipts

**Verdict** DIVERGENT. **Severity** cosmetic (API hazard).

Our evidence: `src/protocol/receipts/receipts.lisp:136-137`. `receipt-list-root`
maps `receipt-rlp` over the receipts, which always produces the legacy
four-field encoding, because the `receipt` struct has no type field
(`:90-98`) — the type comes from the paired transaction via
`transaction-receipt-encoding` (`:119-124`). For any block containing a typed
transaction, `receipt-list-root` therefore returns a root that does not match
the header. It is exported from both `models` and `facade`
(`src/packages/models.lisp:67` and `src/packages/facade.lisp:1119`).

Reference evidence (geth): `core/types/receipt.go:362-378`
`Receipts.EncodeIndex` prefixes the type byte for anything other than
`LegacyTxType`; the type is a field on the receipt.

Consequence: no live path is affected — every internal caller uses
`transaction-receipt-list-root`, and the five test files that call
`receipt-list-root` do so deliberately, including
`tests/core-engine-rpc-new-payload-typed-receipt-tests.lisp:309-313`, which
asserts that the root it returns does *not* match the header for a type-2
transaction. The behaviour is therefore pinned rather than accidental. What
remains is a naming hazard: the function is exported from both `models` and
`facade` and its name reads like the general one.

### Verified as matching, worth not re-litigating

These were checked against the pinned references and agree. They are recorded so
that a future reader does not spend the same time on them, and so that nobody
"fixes" one into a divergence.

- Transaction type coverage is complete. Geth `core/types/transaction.go` and
  Nethermind `src/Nethermind/Nethermind.Core/TxType.cs:6-15` both define types
  0x00 through 0x04 and nothing else on L1; Nethermind's `DepositTx = 0x7E` is
  Optimism. Our `transaction-from-encoding`
  (`src/protocol/transactions/transactions.lisp:96-109`) handles exactly those
  five and rejects the rest, including the `0x00` type-byte form.
- The legacy-versus-typed discriminator `(> (aref bytes 0) #x7f)`
  (`transactions.lisp:100`) is byte-for-byte what geth's `UnmarshalBinary` uses.
  Bytes in `0x80..0xbf` fall into the legacy branch in both and are rejected
  there for not being a list.
- Signature malleability is enforced. `typed-transaction-sender`
  (`transactions.lisp:114-119`) passes `:low-s-p t`, and senders really are
  recovered by `secp256k1-recover-address` on the block path — this is not a
  trusted-from field.
- The gas-limit delta rule, the `MaxGasLimit` bound, the timestamp rule, the
  32-byte extra-data cap and the `gasUsed <= gasLimit` rule all match
  `consensus/beacon/consensus.go:211-242` and
  `consensus/misc/eip1559/eip1559.go:33-57`.
- Base fee: our `expected-base-fee-per-gas` combines geth's two successive
  divisions into one, which is the same floor. The gas-parity audit
  differentially tested this over 20,000 triples.
- Blob gas body checks match `core/block_validator.go:104-112`: the multiple-of-
  `GAS_PER_BLOB` rule, the header maximum, and the used-versus-counted equality.
- EIP-7934's block RLP size cap is implemented
  (`src/protocol/consensus/block-validation/body.lisp:93-96`) as in
  `core/block_validator.go:53-55` and Nethermind `BlockValidator.cs:124-136`.
- EIP-4788 is gated and handled as geth handles it, including geth's deliberate
  discarding of the call error at `core/state_processor.go:339`. EIP-2935 is
  gated on Prague-or-UBT exactly as at `:171-173`.
- `validate-set-code-authorization-signatures` is correctly *not* called on the
  block path — it is txpool-only
  (`src/application/services/txpool-admission.lisp:225` and
  `src/storage/node-store/persistence/import/txpool.lisp:74`). Calling it during
  block validation would reject blocks geth accepts, since EIP-7702 skips
  invalid authorization tuples rather than invalidating the transaction.
- Receipt trie values use the raw `type || rlp` concatenation
  (`receipts.lisp:119-124`), matching geth's `Receipts.EncodeIndex`, and
  `derive-list-root` keys by `rlp-encode` of the index, matching `DeriveSha`.
- Pre-Byzantium post-state receipts are representable
  (`receipts.lisp:90-105`) and the consensus receipt validator documents
  pre-Byzantium roots as out of scope. That is a stated limitation, not a gap.
- The receipt decoder validates the supplied bloom against the decoded logs
  (`src/storage/node-store/persistence/import/receipts.lisp:42`).
- The cumulative-gas monotonicity rule
  (`src/protocol/consensus/block-validation/receipts.lisp:70-73`) is stricter
  than geth, which checks no such thing, but every transaction costs at least
  21,000 gas so the strict form cannot reject a real block.
- Both the Engine path and the staged-import path do parent-linked header
  validation: `src/application/services/engine-payload-status.lisp:141` calls
  `validate-block-against-config`, and the `:headers` stage of
  `src/storage/node-store/persistence/staged-import.lisp` calls
  `validate-block-header-against-config` before persisting.

## Remediation plan for this area

Ordered by consensus risk, then by whether the item unblocks verification of the
others.

**1. Wire the pinned EEST corpus and lift the fork ceiling (L).** No dependency.
Fetch `v5.4.0` via `make eest-fixtures`, export
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` in the layered Docker targets, and
replace the hardcoded `'("London" "Shanghai")` fork list in
`tests/fixture-runner-state-selectors.lisp` and the all-Shanghai selector list in
`tests/fixture-runner-blockchain-selectors.lisp` with a parameter. Verify by
observing non-zero, non-skipped counts for the `cancun/`, `prague/` and `osaka/`
`blockchain_tests` and `blockchain_tests_engine` families, in particular
`cancun/eip4844_blobs/`, `prague/eip7002_el_triggerable_withdrawals/`,
`prague/eip7251_consolidations/`, `prague/eip6110_deposits/` and
`osaka/eip7918_blob_reserve_price/`. Protects "derived, not trusted" — nothing
below can be shown fixed without this. This is the same work as
`docs/gas-parity.md` item 3.1 and should be done once for both.

**2. Fix the EIP-7918 update fraction (S).** Depends on item 1 for proof, not for
the change. Pass the child's `update-fraction` as the reserve-price fraction in
`expected-excess-blob-gas` and delete the `parent-update-fraction` parameter and
the resolution of the parent schedule in `validate-block-header-against-config`.
Verify with `osaka/eip7918_blob_reserve_price/` and any BPO transition fixture
family in `v5.4.0`; a differential test against a transcription of
`calcExcessBlobGas` over a grid of parent excess, parent used and parent base fee
would be stronger. Protects the parity rule in PROJECT.md — a documented
deliberate choice that contradicts both references is still a split.

**3. Decide the merge boundary from the chain config (S).** No dependency. Thread
`chain-config-post-merge-p` — derived from `terminalTotalDifficulty` and
`mergeNetsplitBlock` — into `validate-block-header-against-config` in place of
`(block-header-post-merge-p header)`, and keep the header-derived predicate only
for the execution context's `random-p` flag, where it is describing an already
validated header. Verify with a blockchain fixture whose configuration is
post-merge from genesis and whose block 1 declares nonzero difficulty; EEST's
`paris/` families and any `blockchain_test` with `"paris"` in its network field
will do. Protects "derived, not trusted".

**4. Validate uncles, or refuse blocks that have them (M).** Depends on a
decision this audit cannot make: whether pre-merge chains are in scope. If they
are, implement geth's `VerifyUncles` — count cap, seven-ancestor walk, duplicate
and ancestor rejection, and full header verification of each uncle — in
`src/protocol/consensus/block-validation/roots.lisp` alongside the existing hash
check. If they are not, reject any non-empty ommer list unconditionally, remove
`apply-block-ommer-rewards`, and write the scope decision into
`docs/validation.md`. Verify with the legacy `blockchain_tests` uncle families
if in scope, or with a unit test in `tests/core-block-body-validation-tests.lisp`
asserting rejection if not. Protects "atomic import" and "derived, not trusted".

**5. Derive the block access list during execution (L).** Depends on item 1 for
Amsterdam fixtures. Accumulate a construction access list across the
pre-execution system calls, each transaction, and the post-execution calls, as
geth threads `bal.ConstructionBlockAccessList` through
`core/state_processor.go`, then hash it and compare against the header when the
body omits one. Verify with the `amsterdam/eip7928_block_access_lists/` family.
Protects "derived, not trusted" — this is the clearest current instance of
trusting a commitment we could compute.

**6. Bound RLP decoder recursion (S).** No dependency. First settle EXEC-14 by
decoding a deeply nested input in a dev image and observing what is signalled;
if it is a `storage-condition`, add an explicit depth parameter to `rlp-decode`
with a limit comfortably above any real block's nesting and signal `rlp-error`
past it. Verify with a unit test in `tests/rlp-tests.lisp` decoding
1,000,000 nested list prefixes and asserting `rlp-error`. Protects "atomic
import" — a decode failure must be a rejection, not a thread death.

**7. Give the KZG blob-proof check a caller (M).** Depends on nothing in this
list, but the wrapper codec in EXEC-11 belongs to the networking area and this
item is only half of that fix. Call `validate-blob-sidecar-fields` from wherever
a sidecar first enters the node — the Engine `getBlobs`/`newPayload` bundle path
and the key-value import at
`src/storage/node-store/persistence/import/blobs.lisp` — under the existing
capability gate, so that an unavailable c-kzg backend degrades rather than
silently accepts. Verify with `cancun/eip4844_blobs/` fixtures and by asserting
that a sidecar with a mismatched proof is rejected when the backend is present.
Protects "real cryptography on real paths", which is the principle this most
directly contradicts today: the verifier is present, correct-looking, and never
runs.

**8. Amsterdam pre- and post-execution transitions (M).** Depends on items 1 and
5. Add the EIP-7997 factory deployment on the activation block and the EIP-8282
builder deposit and exit queues as request types 0x03 and 0x04 in
`src/runtime/execution/prague-requests.lisp`. Verify with the
`amsterdam/eip7997_*` and `amsterdam/eip8282_*` families. Protects consensus
parity at the next fork; not urgent while Amsterdam is unscheduled.

**9. Chain presets and genesis parity (M).** No dependency. Embed the mainnet,
Sepolia, Holesky and Hoodi genesis configurations and allocations, and add a test
asserting that the genesis block hash computed from each preset equals the
published hash for that network. Protects nothing in consensus directly but is
the precondition for any Hive or public devnet run, which is how the rest of
this list gets exercised end to end.

**10. DAO fork, or an explicit scope statement (S).** Depends on the same
pre-merge decision as item 4. Either implement the drain-list transfer and the
extra-data rule, or state in `docs/validation.md` that mainnet history before
the merge is out of scope and stop parsing `daoForkBlock` as though it were
honoured. Protects honesty about what the client validates.

**11. Cosmetic and hygiene (S).** Make the header RLP encoder positional so a
gapped header cannot silently produce a shifted encoding (EXEC-13); either give
`receipt` a type field or unexport `receipt-list-root` (EXEC-16); resolve
EXEC-09 against `ethereum/execution-specs` and record the answer in a comment.

## Explicitly out of scope or left unverified

Out of scope for this audit by division of labour, and flagged for whoever owns
them:

- Gas arithmetic, in both senses: everything inside the interpreter loop (opcode
  gas, memory expansion, call and create gas, precompile pricing, EIP-2929
  warming) and transaction-level gas (intrinsic gas, the EIP-7623 calldata
  floor, refund settlement, the EIP-7825 cap). `docs/gas-parity.md` covers all
  of it. This audit confirmed only that the per-type hooks exist and are called
  from the right places — `transaction-intrinsic-gas` and
  `transaction-floor-data-gas` in `src/runtime/execution/gas.lisp`, and the
  EIP-7825 cap at `src/protocol/consensus/block-validation/body.lisp:79-83` —
  not that any number they produce is right.
- State and storage internals: the trie implementation, state root computation
  itself, journaling and snapshot semantics, account and storage encoding. This
  audit checked that we compute a root and compare it, not that the root is
  right.
- The Engine API surface, JSON-RPC shapes, payload status codes, and fork-choice
  handling, except where a validation call is made from that path.
- devp2p framing, discovery, the sync scheduler, and the transaction pool,
  except EXEC-11's overlap.
- KZG and BLS backend correctness. The Go helper binaries under `tools/` were
  not examined, and neither was the c-kzg CFFI binding beyond confirming it
  exists. EXEC-11 records only that the sidecar entry points have no caller, not
  that they would be correct if called.
- Pre-Byzantium receipt roots, which the code documents as out of Phase A scope.

Left unverified, honestly:

- **The RLP recursion consequence (EXEC-14).** The recursion is in the source and
  SBCL's control-stack-exhausted condition is a `storage-condition` rather than
  an `error`; that a crafted input actually escapes the handlers was not
  demonstrated, because the dev container was absent and this audit was not
  permitted to start it.
- **The exact state-test selector count (EXEC-15).** 94 literal names is counted;
  the 21 generators' expansion is hand-arithmetic, roughly 850 more.
- **Which EEST `v5.4.0` families exist but are not selected.** The archive was
  not downloaded, per instruction. Only the fork ceiling is established.
- **Whether `ommer-block-reward` can go negative** for an uncle more than eight
  blocks below the header, and what the state database does if it does.
- **Whether EXEC-10's ordering difference is observable** for any predeploy
  bytecode other than the canonical EIP-7002 and EIP-7251 contracts.
- **Nethermind's state-transition pipeline** was read only for header and body
  validation and blob gas. Its block processor was not compared
  transaction-by-transaction against ours; every state-transition finding above
  cites geth on the reference side, and geth alone where it says so.
- **No test was run.** The dev image was absent throughout, and the audit
  instructions forbid starting it and forbid running the suite. Every finding is
  from reading source on all three sides.

Findings that overlap other audit areas, for deduplication: EXEC-01 with
`docs/gas-parity.md` 1.3 (this document resolves the direction); EXEC-15 with
`docs/gas-parity.md` 3.1 (this document adds the pinned-corpus selector counts);
EXEC-11 with networking and txpool; EXEC-06 with whoever owns state and storage,
since deriving the access list requires hooks the state layer must provide;
EXEC-12 with whoever owns node startup and configuration.
