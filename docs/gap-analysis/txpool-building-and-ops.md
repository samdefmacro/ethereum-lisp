# Transaction pool, block building, and node operations — gap analysis

This audit covers one area: transaction-pool admission and policy, the
payload-building path that a consensus client drives through
`engine_forkchoiceUpdated`, and node operations — process lifecycle,
configuration surface, logging, metrics, and recovery. The Engine API and
JSON-RPC wire surfaces belong to `rpc-and-engine.md`; block execution, header
validation and state storage belong to `block-execution-and-types.md` and
`state-trie-storage.md`. Where a finding here is the building-side or
pool-side consequence of one of theirs, it says so and does not restate it.

The findings below describe the tree as audited on 2026-07-28.  The remediation
status near the end records what has since been implemented and verified on
`gap/txpool-build-ops`.

## Sources read

| Side | Version | Commit | Date read |
| --- | --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` | 2026-07-28 |

Ours: the working tree at the time of the audit, 2026-07-28. Function names are
the durable identifier; prefer them over line numbers when a line has moved.

Our code read in full: `src/storage/txpool/` (index and service),
`src/application/services/txpool-admission.lisp`,
`src/application/services/canonical-chain.lisp`, `src/api/engine/forkchoice.lisp`,
`src/protocol/engine-payloads/build.lisp`, `src/app/cli/` (options, config,
devnet node, service, background, persistence, files, metrics server,
telemetry), `src/foundation/telemetry.lisp`, `src/transport/http/server.lisp`,
`src/api/rpc/router.lisp`, and the execution-side accounting and validation
entry points that a built block passes through.

**Executed versus source-read.** One claim in this document was established by
executing forms against the warm dev image: the blob-transaction path
(POOL-13 / BUILD-08), where a signed blob transaction was rejected by
`engine-payload-store-put-pending-transaction`,
`...put-queued-transaction` and `...put-basefee-transaction`, accepted by
`...put-blob-transaction`, and then absent from
`engine-payload-store-pending-mining-transactions`. That is the observation the
RPC audit asked for and it is reported as executed. The warm image was lost
mid-audit — a later eval exited 137 (out of memory) and took the shared
container down with it, and this session is not permitted to restart it — so
**every other claim in this document is a source reading**, not an execution.
Several would be settled by a small eval and are flagged in the final section
so a later pass can convert them.

## Executive summary

Ordered by impact on running this node as the execution client behind a real
validator.

1. **A single unexecutable transaction in the pending list aborts the whole
   payload build, and `forkchoiceUpdated` then returns an error with no payload
   id** (BUILD-01). Both references start from an empty block that is always
   returnable and skip the offending transaction. Ours has no per-transaction
   skip: the validator gets no payload for that slot at all.
2. **The pending list is filtered against the head's base fee but the block is
   built at the child's base fee**, which is up to 12.5% higher, so any pending
   transaction whose fee cap falls in that window triggers BUILD-01 on an
   ordinary rising-base-fee block with no adversary involved (BUILD-02).
3. **Admission omits the EIP-7623 floor-data-gas and EIP-3860 initcode-size
   checks that block execution enforces**, so a cheap remote transaction can be
   accepted into the pending list and then abort every payload build until it is
   evicted — and nothing evicts it (POOL-02, POOL-03).
4. **The payload is built once, synchronously, at `forkchoiceUpdated` time and
   never improved** (BUILD-03). geth rebuilds every two seconds while the
   consensus client waits and returns the best block; Nethermind does the same.
   We hand back whatever the pool held at the instant of the call.
5. **The block gas limit is copied from the parent and `--miner.gaslimit` is
   never consulted when building**, so an operator cannot move the gas limit and
   the node will not follow a network-wide change (BUILD-04).
6. **Every pool limit defaults to unlimited, and when a limit is set the pool
   rejects the newcomer instead of evicting the cheapest resident** (POOL-07,
   POOL-08). A default-configured node has no bound on pool memory; a
   limit-configured node turns away a high-fee transaction while cheap ones sit
   in the pool.
7. **Fifty-six command-line flags are accepted, consumed, and discarded**,
   including `--verbosity`, `--syncmode`, `--log.format`, the log-rotation
   family, the cache family, `--nodiscover`, `--pprof`, `--mine`, and every
   chain preset (OPS-01). Silently ignoring a flag is worse than rejecting it.
8. **There are no chain presets, so `--genesis` is mandatory** and joining
   mainnet, sepolia, hoodi or holesky means sourcing a genesis file elsewhere
   (OPS-02).
9. **The data directory is not locked, so two processes can open the same
   datadir** and interleave their writes to the same database file (OPS-03).
10. **Metrics are event counts and nothing else** — no pool-size, head-number or
    peer-count gauge — and `--log-file` truncates the previous run's log on
    startup, destroying the record of the crash the operator is restarting from
    (OPS-04, OPS-06).

## Findings

### Pool admission and validation

**POOL-01 — No transaction size cap.**
Verdict MISSING. Severity correctness.
Ours: `validate-txpool-admission`
(`src/application/services/txpool-admission.lisp:105-146`) validates type,
data, recipient, scalars, signature, access list, set-code fields, blob fields,
blob fee cap, intrinsic gas, the block gas limit and the EIP-7825 cap. Nothing
looks at the encoded size. Reference: geth rejects above `opts.MaxSize`
(`core/txpool/validation.go:70-71`) before any expensive check, with
`txMaxSize = 128KB` for the legacy pool (`core/txpool/legacypool/legacypool.go:56`)
and 1MB for the blob pool (`core/txpool/blobpool/blobpool.go:70`); Nethermind
enforces the same two numbers in `SizeTxFilter`
(`src/Nethermind/Nethermind.TxPool/Filters/SizeTxFilter.cs:14-25`, defaults in
`TxPoolConfig.cs:24-25`). Consequence: one `eth_sendRawTransaction` carrying a
multi-megabyte calldata blob is admitted and retained. It will not fit a block
(the gas limit stops that) but it occupies pool memory indefinitely, and with no
global slot limit by default (POOL-07) a caller can repeat it.

**POOL-02 — No EIP-3860 initcode-size check at admission.**
Verdict MISSING. Severity loses-money-or-blocks-validation.
Ours: admission computes intrinsic gas with `:eip3860-p`
(`src/application/services/txpool-admission.lisp:125-132`), which charges the
per-word initcode cost but does not apply the 49152-byte cap.
`validate-contract-initcode-size` is called only on the execution path
(`src/runtime/execution/validation.lisp:42-43`). Reference: geth applies
`vm.CheckMaxInitCodeSize` during pool validation
(`core/txpool/validation.go:87-91`); Nethermind has `ContractSizeTxValidator`
(`src/Nethermind/Nethermind.Consensus/Validators/TxValidator.cs:174-179`).
Consequence: an over-sized creation transaction enters the pending list, is
selected for a block, and then fails inside `execute-signed-block` — which under
BUILD-01 aborts the entire payload. The transaction is not removed by that
failure, so every subsequent build fails the same way.

**POOL-03 — No EIP-7623 floor-data-gas check at admission.**
Verdict MISSING. Severity loses-money-or-blocks-validation.
Ours: admission compares the gas limit against `transaction-intrinsic-gas` only
(`src/application/services/txpool-admission.lisp:125-132`), while
`charge-sender-upfront` requires
`(max intrinsic-gas (transaction-effective-floor-gas ...))`
(`src/runtime/execution/accounting.lisp:16-19`). The two thresholds differ for a
calldata-heavy transaction after Prague. Reference: geth checks
`core.FloorDataGas` in pool validation and returns `ErrFloorDataGas`
(`core/txpool/validation.go:141-153`); Nethermind's `IntrinsicGasTxValidator`
covers the floor (`TxValidator.cs:129-151`). Consequence: identical to POOL-02
and cheaper to trigger — a transaction whose gas limit sits between intrinsic
and floor gas is admitted and then poisons every payload build. This is the
lowest-cost remote denial of block production in the pool today.

**POOL-04 — The minimum-fee check reads the fee cap, not the effective tip.**
Verdict DIVERGENT. Severity correctness.
Ours: `validate-admission-policy` compares
`transaction-max-fee-per-gas` against the configured price limit
(`src/application/services/txpool-admission.lisp:158-164`). Reference: geth
compares `tx.GasTipCap()` against `opts.MinTip`, which the pool sets from its
dynamic `gasTip` (`core/txpool/validation.go:157-158`,
`core/txpool/legacypool/legacypool.go:565`); Nethermind has both a
`FeeTooLowFilter` and a `PriorityFeeTooLowFilter`
(`src/Nethermind/Nethermind.TxPool/Filters/`). Consequence: a transaction with a
very large fee cap and a zero tip passes our price floor and is admitted, then
sorts last during selection (`transaction-effective-tip` correctly values it at
its remaining room above the base fee) and occupies a slot that a paying
transaction could have used. The reverse also holds: on a chain with a high base
fee, a transaction paying a healthy tip is admitted or rejected on a criterion
unrelated to what it pays us.

**POOL-05 — No EIP-7702 authority reservation or delegated-account in-flight limit.**
Verdict MISSING. Severity correctness.
Ours: `txpool-admit-transaction` validates set-code field shape and
authorization-signature values
(`src/application/services/txpool-admission.lisp:224-225`,
`src/protocol/consensus/transaction-validation.lisp:170-191`), and
`validate-txpool-sender-code` rejects a sender with non-delegation code
(`:58-65`). A search for `authority` across `src/storage/txpool/` and the
admission service returns nothing else. Reference: geth's `validateAuth` allows
at most one in-flight transaction for a delegated account or one with a pending
authorization, rejects a gapped nonce from a delegated account
(`ErrOutOfOrderTxFromDelegated`), and reserves an authority address against
other subpools (`core/txpool/legacypool/legacypool.go:600-660`); Nethermind's
`DelegatedAccountFilter` returns `DelegatorHasPendingTx` and
`NotCurrentNonceForDelegation`
(`src/Nethermind/Nethermind.TxPool/Filters/DelegatedAccountFilter.cs:19-32`).
Consequence: an attacker can stack many transactions from a delegated account
and many set-code transactions naming the same authority. Each is individually
valid at admission; most become unexecutable the moment the first one lands,
which under BUILD-01 turns into a failed payload build rather than a skipped
transaction. This is the pool-side counterpart of the non-fork-gated delegation
noted in `evm-and-gas.md`.

**POOL-06 — Nonce and balance are not checked at all when head state is unavailable.**
Verdict DIVERGENT. Severity correctness.
Ours: `validate-txpool-sender-state` performs the nonce-too-low and
balance-versus-cost checks inside
`(when (and head (chain-store-state-available-p store (block-hash head))) ...)`
(`src/application/services/txpool-admission.lisp:67-81`); when state is missing
the function returns `t`. The same guard appears in
`txpool-queued-nonce-gap-p` (`:88-89`), so a transaction admitted in that window
also skips the pending-versus-queued decision and lands directly in the pending
list. Reference: geth's stateful validation has no such bypass —
`ValidateTransactionWithState` requires a `*state.StateDB`
(`core/txpool/validation.go:267`) and the pool is reset to a head whose
state it holds. Consequence: on a node that is syncing or that has a head
without state, `eth_sendRawTransaction` accepts transactions with any nonce and
any balance straight into the pending list. When state arrives, the new-head
reconciliation demotes them (`canonical-chain-reconcile-txpool`,
`src/application/services/canonical-chain.lisp:113-127`), but a build attempted
before that reconciliation hits BUILD-01.

**POOL-07 — Every pool limit defaults to unlimited.**
Verdict DIVERGENT. Severity operability.
Ours: `txpool-admission-policy` has no default for `price-limit`,
`price-bump-percent`, `account-slot-limit`, `global-slot-limit`,
`account-queue-limit`, `global-queue-limit`
(`src/application/services/txpool-admission.lisp:3-13`); the CLI passes
`(getf options :txpool-...)` straight through
(`src/app/cli/cli.lisp:55-65`), which is `NIL` when the flag is absent; and each
limit check is guarded by the limit being non-`NIL`
(`src/storage/txpool/index/insert.lisp:27-39`, `:93-105`). The replacement bump
is the one exception: `NIL` falls back to
`+txpool-replacement-price-bump-percent+`, which is 10
(`src/storage/txpool/index/replacement.lisp:6-7`). Reference: geth's
`DefaultConfig` is `PriceLimit 1`, `PriceBump 10`, `AccountSlots 16`,
`GlobalSlots 5120`, `AccountQueue 64`, `GlobalQueue 1024`, `Lifetime 3h`
(`core/txpool/legacypool/legacypool.go:161-174`), and `sanitize` raises an
out-of-range value rather than accepting it (`:176-206`); Nethermind's default
pool `Size` is 2048 (`src/Nethermind/Nethermind.TxPool/TxPoolConfig.cs:13`).
Consequence: a node started the way our own documentation starts one has no
bound on how much pool memory remote traffic can consume, and no minimum price.
Our 10% bump makes no parity claim in the source; it happens to equal geth's
`PriceBump`.

**POOL-08 — A full pool rejects the newcomer instead of evicting the cheapest resident.**
Verdict DIVERGENT. Severity correctness.
Ours: when the pending table has reached `global-slot-limit`, insertion signals
`"Pending transaction exceeds txpool global slot limit"`
(`src/storage/txpool/index/insert.lisp:27-31`), and the per-account case behaves
the same way (`:32-39`). Nothing anywhere selects a victim for eviction.
Reference: geth, on overflow, first asks whether the newcomer is underpriced
relative to the pool and only then rejects it; otherwise it discards enough of
the cheapest transactions to make room
(`core/txpool/legacypool/legacypool.go:706-732`), and separately spills the
largest accounts' highest nonces from pending into the queue. Consequence: once
the pool is at its limit, price stops mattering. A 100 gwei transaction is
refused with a JSON-RPC error while 1 gwei transactions keep their slots, so the
node stops taking the traffic that pays best and a proposing validator builds from a
frozen, cheap pool.

**POOL-09 — The basefee and blob subpools have no limits at all.**
Verdict MISSING. Severity operability.
Ours: `engine-pending-txpool-put-basefee-transaction` and
`...put-blob-transaction` both route through
`engine-pending-txpool-put-flat-transaction`
(`src/storage/txpool/index/insert.lisp:134-209`), whose parameter list has no
slot or queue limit — only the pending and queued subpools take limits at all.
Reference: geth counts every subpool against `GlobalSlots + GlobalQueue`
(`core/txpool/legacypool/legacypool.go:726`) and caps blob storage separately at
`Datacap` (2.5GB in the current rollout,
`core/txpool/blobpool/config.go:33-37`); Nethermind bounds persistent blob
storage at `PersistentBlobStorageSize` (`TxPoolConfig.cs:15`). Consequence: even
an operator who sets every flag we accept has no bound on the two subpools that
remote traffic can most easily fill — anything priced below the current base fee
lands in the basefee subpool, and blob transactions land in a subpool that
nothing ever drains (POOL-14).

**POOL-10 — Lifetime eviction runs only when a public JSON-RPC request arrives.**
Verdict DIVERGENT. Severity operability.
Ours: `engine-payload-store-remove-expired-txpool-queued-view-transactions`
(`src/storage/txpool/service/cleanup-lifecycle.lisp:72-92`) is called from
exactly one place — the head of the public RPC dispatch,
`engine-rpc-handle-public-method`
(`src/api/public/dispatch/dispatch.lisp:19-25`, clock supplied at
`src/transport/http/handler.lisp:77`). It is not on any timer, and
`txpool-lifetime-seconds` has no default, so it does nothing at all unless
`--txpool.lifetime` is given. Reference: geth's pool loop ticks a one-minute
`evictionInterval` independently of any request
(`core/txpool/legacypool/legacypool.go:79`, `:353`) with a three-hour default
`Lifetime` (`:173`). Consequence: a validator-attached node that exposes only
the authenticated engine port — the recommended posture — never expires a queued,
basefee or blob transaction. Combined with POOL-09 the non-pending subpools grow
monotonically for the life of the process.

**POOL-11 — Promotion on a new head ignores the slot limits.**
Verdict DIVERGENT. Severity completeness.
Ours: admission passes the configured limits when promoting after an insert
(`src/application/services/txpool-admission.lisp:206-220`), but the new-head
path calls `engine-payload-store-promote-queued-transactions` and
`...promote-basefee-and-queued-transactions` with no limit arguments at all
(`src/application/services/canonical-chain.lisp:122-127`). Reference: geth's reorg
runs `promoteExecutables` and then `truncatePending` and `truncateQueue`, which
enforce `AccountSlots` and the global bounds, on every reset
(`core/txpool/legacypool/legacypool.go:1255`, `:1279-1280`, `:1405`, `:1437`).
Consequence: the
pending-list limits an operator configures hold on the submission path and are
silently exceeded on the block-arrival path, so `txpool_status` can report more
pending transactions than `--txpool.globalslots` permits.

**POOL-12 — Blob replacement does not require a blob-fee-cap bump, and uses 10% rather than 100%.**
Verdict DIVERGENT. Severity correctness.
Ours: `engine-pending-txpool-replacement-transaction-p` requires the execution
fee cap and the priority fee to be both strictly greater and bumped by the
configured percentage (`src/storage/txpool/index/replacement.lisp:15-28`), and
that same predicate is what the blob subpool uses
(`src/storage/txpool/index/insert.lisp:155-160`). `transaction-blob-fee-cap` is
never consulted. Reference: geth's blob pool requires all three caps — execution
fee, tip, and blob fee — to be strictly greater and bumped
(`core/txpool/blobpool/blobpool.go:1665-1692`), with `PriceBump 100`
(`core/txpool/blobpool/config.go:36`) rather than the legacy pool's 10; the
`--txpool.blobpool.pricebump` flag we accept is discarded (OPS-01). The legacy
replacement rule itself is parity: geth also demands strictly-greater on both
caps plus the percentage threshold (`core/txpool/legacypool/list.go:305-325`).
Consequence: a blob transaction can be replaced without paying more for its
blobs, which is the exact griefing the 100% bump exists to price. Today the
consequence is contained by POOL-14 — those transactions cannot be mined by us
anyway.

### Blob transactions

**POOL-13 — There is no blob pool, and pooled blob transactions are inert.**
Verdict MISSING. Severity completeness.
Ours (executed): a signed blob transaction is rejected by
`engine-payload-store-put-pending-transaction`,
`...put-queued-transaction` and `...put-basefee-transaction` —
`validate-store-transaction`
(`src/storage/txpool/service/store-admission.lisp:16`) refuses a
`blob-transaction` in any non-blob subpool and refuses a non-blob transaction in
the blob subpool — and is accepted only by
`engine-payload-store-put-blob-transaction`. After that insertion,
`engine-payload-store-pending-mining-transactions` returned nothing: it reads
`engine-payload-store-pending-transactions` and nothing else
(`src/storage/txpool/service/views.lisp:111-116`). Admission routes blob
transactions there unconditionally
(`src/application/services/txpool-admission.lisp:176-179`), and the gossip
broadcast reads only the pending subpool
(`src/app/cli/devnet/peer-sync.lisp:107-110`), and lifetime expiry is off by
default (POOL-10). Reference: geth's blob pool is a separate subpool with its
own on-disk store, `Datacap` eviction and eviction-by-blob-fee
(`core/txpool/blobpool/blobpool.go`), and the miner interleaves blob and plain
transactions by tip in one loop (`miner/worker.go:461-485`); Nethermind keeps
blob transactions in `BlobTxStorage` with `BlobsSupportMode.StorageWithReorgs`
(`src/Nethermind/Nethermind.TxPool/TxPoolConfig.cs:14-15`). Consequence: a blob
transaction submitted to us is accepted, stored, counted by `txpool_status`,
never mined, never gossiped, and never expires. The sender sees a hash and an
accepted submission for a transaction that will not be included by this node and
will not reach anyone who could include it.

**POOL-14 — Blob sidecars are never verified, and the pooled transaction has nowhere to carry them.**
Verdict MISSING. Severity completeness.
Ours: the `blob-transaction` struct carries `blob-versioned-hashes` and no
blobs, commitments or proofs (`src/protocol/transactions/blob.lisp`);
`blob-transaction-from-rlp` requires exactly 14 fields, so the four-element
EIP-4844 network wrapper that a real sender submits does not decode at all.
`validate-blob-sidecar-fields` and `validate-blob-sidecar-kzg-proofs`
(`src/protocol/kzg/validation.lisp:68`, `:87`) have no caller in `src/` outside
package export lists. Admission checks the versioned-hash shape and the blob fee
cap (`src/application/services/txpool-admission.lisp:117-124`) and stops.
Reference: geth verifies the sidecar's commitment hashes, proof count and
sidecar version during pool validation and verifies the cells cryptographically
in `ValidateCells` (`core/txpool/validation.go:171-215`); Nethermind calls
`proofsManager.ValidateProofs` on the mempool path
(`src/Nethermind/Nethermind.Consensus/Validators/TxValidator.cs:309-313`).
Consequence: pool-side sidecar verification is not merely unimplemented, it is
structurally impossible — there is no sidecar on the object to verify. This is
the honest reason `engine_getPayloadV3+` returns an empty `blobsBundle`
(RPC-06): the built block cannot contain a blob transaction, so an empty bundle
is consistent with the payload rather than contradicting it. `PROJECT.md`'s
"real cryptography on real paths" is satisfied in the negative here — we do not
fake a verification, we decline the transaction shape — but the capability
boundary is not visible to a submitter, who gets an accepted hash.

### Pool structure that is at parity or better

Recorded so a later reader does not mistake absence of a finding for absence of
a check.

Sender recovery is real and chain-id-bound on every admission
(`txpool-admit-transaction`, `src/application/services/txpool-admission.lisp:226-232`).
The balance check accumulates the cost of the sender's already-pooled
transactions rather than checking one transaction in isolation
(`engine-payload-store-sender-admission-expenditure`, called at `:76-80`).
Pending/queued separation, nonce-gap detection and promotion exist
(`txpool-queued-nonce-gap-p` at `:83-94`; the promote calls at `:206-220`).
New-head reconciliation removes stale, over-gas-limit, invalid-sender,
underpriced-blob and non-delegation-code transactions, revalidates the pending
list against fresh nonce and balance with cumulative cost accounting, demotes
rather than drops, and re-injects transactions from displaced blocks
(`src/storage/txpool/service/cleanup-new-head.lisp`,
`.../pending-revalidation.lisp`, `.../reorg.lisp`, orchestrated by
`canonical-chain-set-head`, `src/application/services/canonical-chain.lisp:129-171`).
That covers the reorg-safety principle in `PROJECT.md`.

Persistence is stronger than geth's here, not weaker. The pool is written into
the chain database on every forkchoice persist and re-imported at startup, and
the optional `--txpool.journal` artifact carries a generation number, a
base-chain generation, an authority id, the chain id and the genesis hash, with
an explicit freshness comparison that refuses to let a stale journal override a
newer database (`devnet-cli-journal-authoritative-p`,
`src/app/cli/devnet/persistence.lisp:165-201`;
`devnet-cli-import-persistent-state` at `:286-417`). geth's `transactions.rlp`
has none of that structure. The metadata carries a format version that is
checked on read (`src/storage/node-store/persistence/metadata.lisp:3`, `:126-128`).

**POOL-15 — Gossip pushes full transactions from the pending subpool only, rescanning it per peer per tick.**
Verdict DIVERGENT. Severity performance.
Ours: `devnet-peer-pending-broadcast` closes over a per-session known-hash set
and, on each tick, walks the entire pending list to find up to 64 unseen
transactions (`src/app/cli/devnet/peer-sync.lisp:84-119`). The file documents
the poll-and-diff choice and why the dirty-key set was not reused. Queued,
basefee and blob transactions are never announced. Reference: geth announces
hashes to most peers and sends full bodies to a square-root subset, driven by a
subscription rather than a poll (`eth/handler.go` `BroadcastTransactions`);
Nethermind's `TxBroadcaster` does the same split. Consequence: cost is
O(pending) per peer per tick rather than O(new), and a transaction that is
queued on our node — a nonce gap we cannot fill but a peer might — is never
offered to anyone. Correct as far as it goes, and the file says so.

### Payload and block building

**BUILD-01 — One unexecutable transaction aborts the entire payload build.**
Verdict DIVERGENT. Severity loses-money-or-blocks-validation.
Ours: `engine-rpc-build-prepared-payload` executes the selected transaction list
in one `execute-signed-block` call
(`src/api/engine/forkchoice.lisp:50-62`) with no per-transaction recovery. The
caller wraps it in `handler-case` for `block-validation-error` and converts that
into `engine-rpc-fail +engine-rpc-error-invalid-payload-attributes+`
(`:187-193`), so `forkchoiceUpdated` returns `-38003` and `payloadId` is never
set. Worse, the execution-side per-transaction failures signal
`transaction-validation-error`, which is a direct subtype of `error` and not of
`block-validation-error` (`src/runtime/execution/contract.lisp:5`), so
"Invalid transaction nonce" and "Insufficient sender balance" from
`charge-sender-upfront` (`src/runtime/execution/accounting.lisp:12-31`) escape
that handler, escape the router — which handles `engine-rpc-error`,
`block-validation-error`, `invalid-parameters-error`, `state-unavailable-error`
and `storage-error` and nothing else
(`src/api/rpc/router.lisp:190-226`) — and are caught only by the per-connection
guard, which logs a warning and closes the socket with no response written
(`src/transport/http/server.lisp:46-63`). Reference: geth's
`commitTransactions` treats a failed transaction as a reason to skip that
account and continue (`miner/worker.go:537-551`), and the payload always has a
returnable empty block behind it (`miner/payload_building.go:80-86`); Nethermind
likewise starts from an empty block and improves it
(`src/Nethermind/Nethermind.Merge.Plugin/BlockProduction/PayloadPreparationService.cs:104`).
Consequence: for a proposing validator this is a missed slot. The
`block-validation-error` class yields an error code the consensus client can log;
the `transaction-validation-error` class yields no JSON-RPC response at all, so
the client sees its `engine_forkchoiceUpdated` time out.

**BUILD-02 — The pending list is filtered at the head's base fee and built at the child's.**
Verdict DIVERGENT. Severity loses-money-or-blocks-validation.
Ours: admission and revalidation both use the head header's own base fee —
`txpool-basefee-ineligible-p`
(`src/application/services/txpool-admission.lisp:96-103`) and
`engine-payload-store-revalidate-pending-transactions`, which reads
`(block-header-base-fee-per-gas header)` of the head
(`src/storage/txpool/service/pending-revalidation.lisp:66-68`). The build uses
the child's base fee, `(expected-base-fee-per-gas parent-header)`, both for
ordering (`src/api/engine/forkchoice.lisp:171-172`) and in the header
(`src/protocol/engine-payloads/build.lisp:95-98`). Execution then rejects any
transaction whose cap is below the header's base fee
(`validate-1559-transaction-fees`,
`src/protocol/transactions/transactions.lisp:63-64`). Reference: geth filters
the pending set with `filter.BaseFee` set to the pending block's base fee, not
the head's (`core/txpool/legacypool/legacypool.go:515-520`, called from the
miner with `env.header.BaseFee`). Consequence: on any block where the base fee
rises — a block above the gas target, i.e. roughly half of them on a busy chain
— a pending transaction whose cap lies in the 12.5% window between the two base
fees is selected and aborts the build under BUILD-01. This needs no adversary
and no unusual configuration.

**BUILD-03 — The payload is built once and never improved.**
Verdict MISSING. Severity loses-money-or-blocks-validation.
Ours: `engine-rpc-handle-forkchoice-updated` selects transactions, derives a
candidate id and builds the block inline, storing the finished block
(`src/api/engine/forkchoice.lisp:162-193`); if a payload with that id already
exists it is not rebuilt (`:179-181`). There is no background worker, no
recommit interval, and no deadline. Reference: geth's `buildPayload` starts a
goroutine with a `Recommit` timer — two seconds by default
(`miner/miner.go:64`) — that rebuilds repeatedly, keeps the highest-fee result
(`miner/payload_building.go:111-146`, `:283-323`), and terminates on a
slot-length timeout (`:288`); `Resolve` returns the best block built so far
(`:152-175`). Nethermind's `ImproveBlock` recurses with a dynamic delay until
`GetPayload` is called
(`.../PayloadPreparationService.cs:138-215`, `:384-399`). Consequence: we
capture the pool as it stood at the instant of the `forkchoiceUpdated` call and
ignore everything that arrives during the seconds the consensus client is
waiting. Because our payload id is derived from the transaction list root
(`engine-payload-id-with-transactions`,
`src/protocol/engine-payloads/build.lisp:36-47`; see RPC-01 on the id
derivation), a second `forkchoiceUpdated` with identical attributes and a
changed pool produces a *different* id rather than improving the payload behind
the existing one.

**BUILD-04 — The gas limit is copied from the parent; `--miner.gaslimit` never reaches the builder.**
Verdict DIVERGENT. Severity correctness.
Ours: `engine-build-empty-payload` sets
`:gas-limit (block-header-gas-limit parent-header)`
(`src/protocol/engine-payloads/build.lisp:92`) and the dev sealer does the same
(`src/app/cli/devnet/runtime.lisp:114`). `--miner.gaslimit` is parsed into
`:miner-gas-limit` (`src/app/cli/options/options.lisp:320`) and reaches only the
dev-mode genesis writer; `devnet-cli-make-node` does not pass it
(`src/app/cli/cli.lisp:23-81`), so the `Eth.Miner GasCeil` TOML key that maps to
it (`src/app/cli/config/config.lisp`) is equally inert. Reference: geth computes
`core.CalcGasLimit(parent.GasLimit, gasCeil)`
(`miner/worker.go:287`, `:307`), which moves the limit toward the ceiling by at
most `parentGasLimit/1024 - 1` per block
(`core/block_validator.go:228-249`), with `GasCeil` defaulting to 60,000,000
(`miner/miner.go:57`) and settable at runtime via `SetGasCeil` (`:124`); after
Amsterdam the ceiling comes from the consensus client's `targetGasLimit`
(`miner/worker.go:279-281`), which we also ignore (RPC-04). Consequence: the gas
limit of a chain we propose on can never change. An operator who wants to raise
or lower it has no way to do so, and a network-wide gas-limit vote proceeds
without us.

**BUILD-05 — Ordering is per-sender by the first transaction's tip, with no re-comparison after each inclusion.**
Verdict DIVERGENT. Severity performance.
Ours: `engine-payload-store-pending-mining-transactions` groups the pending list
by sender, keys each group on the effective tip of its lowest-nonce transaction,
sorts the groups, and then emits each group whole
(`src/storage/txpool/service/views.lisp:121-135`). The docstring explains why the
key is the lowest nonce and that this is what makes profitability and nonce
order compatible; that reasoning is sound for choosing *which sender goes next*
but the code never returns to the question. `transaction-effective-tip`
(`:61-71`) computes `min(tip, cap - baseFee)` correctly. Reference: geth keeps a
heap of per-account heads and, after including one transaction, pushes the
sender's next transaction into the heap and re-heapifies, so the comparison is
redone at every step (`core/txpool/txorder/ordering.go:130-148`, driven by
`miner/worker.go:474-485`, which also interleaves the plain and blob heaps by
comparing their peeks). Consequence: a sender whose first transaction pays 100
and whose second pays 1 has both included ahead of another sender paying 50
throughout. The recent "Order block building by what transactions actually pay"
change fixed the large problem — the previous order was by address, which ignored
price entirely — and this is the remaining half: correct sender selection,
no re-selection.

**BUILD-06 — Selection packs against declared gas limits and never reclaims unused gas.**
Verdict DIVERGENT. Severity performance.
Ours: `engine-select-mining-transactions` accumulates
`transaction-gas-limit` and blocks a sender once one of its transactions does not
fit (`src/storage/txpool/service/views.lisp:137-155`). The blocked-sender
behaviour matches geth's `txs.Pop()` on a gas miss. But the budget is spent at
declared limits and never adjusted by what execution actually used, because
selection completes before any execution happens. Reference: geth commits
transactions one at a time against a live `GasPool` that is charged actual usage
(`miner/worker.go:455-458` and `commitTransaction`), so the space a
transaction did not use is available to the next one. Consequence: blocks we
build are systematically under-full — a transaction declaring 1,000,000 gas and
using 21,000 costs us 979,000 gas of block space and the fees it would have
earned.

**BUILD-07 — No block size bound during selection.**
Verdict MISSING. Severity correctness.
Ours: nothing in `engine-select-mining-transactions` or
`engine-rpc-build-prepared-payload` measures the encoded size of the block being
assembled. Reference: geth stops adding transactions when
`env.size+tx.Size()` would reach `params.MaxBlockSize` less a buffer zone
(`miner/worker.go:83-85`, applied at `:517-520`). Consequence: on an Amsterdam
chain we can build a block that exceeds the EIP-7934 RLP size cap, which every
other client will reject. The validation side of that cap belongs to
`block-execution-and-types.md`; this is the building side.

**BUILD-08 — A built payload can never contain a blob transaction, so blob gas is always zero.**
Verdict MISSING. Severity completeness.
Ours: `engine-build-empty-payload` sets `:blob-gas-used 0` whenever the
attributes carry a parent beacon root
(`src/protocol/engine-payloads/build.lisp:103-106`) and nothing later raises it,
which is correct precisely because POOL-13 makes a blob transaction
unselectable. Selection has no blob-count or blob-gas budget. Reference: geth
caps blobs per block during selection
(`miner/worker.go:406-407`, `:461-464`, `:500-505`). Consequence: this is the
settled answer to the question the RPC audit left open — the empty `blobsBundle`
in `engine_getPayloadV3+` (RPC-06) is a missing feature and not an internal
inconsistency, because the payload it accompanies provably carries no blob
commitments. Cross-references RPC-06 and RPC-07.

**BUILD-09 — Building is synchronous inside the `forkchoiceUpdated` request, with no deadline.**
Verdict DIVERGENT. Severity operability.
Ours: the build runs on the HTTP worker handling the call
(`src/api/engine/forkchoice.lisp:187-193`). The only bound is the connection
deadline in the HTTP layer
(`engine-rpc-http-with-request-deadline`,
`src/transport/http/server.lisp:50-54`), which cancels the connection rather
than the build. Reference: geth returns the payload id immediately and builds
asynchronously under a slot-length timeout
(`miner/payload_building.go:288`). Consequence: a large pool makes
`forkchoiceUpdated` slow in proportion to the block being built, and the
consensus client's own timeout, not ours, decides what happens.

### What the build gets right

`engine-rpc-prepared-payload-body-arguments` passes `:requests '()` for Prague
(`src/api/engine/forkchoice.lisp:16-17`), which looks wrong and is not:
`execute-signed-block` derives the request list from execution and overrides the
supplied value when derivation succeeds
(`src/runtime/execution/block-execution.lisp:129-141`). Withdrawals come from
the attributes, the fee recipient becomes the beneficiary, and the excess blob
gas is derived from the parent with the EIP-7918 flag threaded through
(`src/protocol/engine-payloads/build.lisp:49-70`, `:86-121`) — with a comment
explaining that a non-derived value would be rejected by our own header
validation. The Amsterdam block access list is passed as empty
(`src/api/engine/forkchoice.lisp:18-19`) and is not derived from execution; that
gap is `block-execution-and-types.md`'s, and it means an Amsterdam block we build
would carry an empty access list.

### Node lifecycle, configuration and operations

**OPS-01 — Fifty-six flags are accepted, consumed, and discarded.**
Verdict DIVERGENT. Severity operability.
Ours: the option loop ends with two catch-all clauses that consume a flag and
its value and do nothing with them
(`src/app/cli/options/options.lisp:281-285`), backed by
`*devnet-cli-value-options*` and `*devnet-cli-optional-boolean-options*`
(`src/app/cli/options/definitions.lisp:3-43`). Comparing those lists against the
flags the loop actually branches on leaves 42 value flags and 14 boolean flags
that are parsed and dropped:

| Group | Discarded flags |
| --- | --- |
| Chain selection | `--mainnet`, `--sepolia`, `--holesky`, `--hoodi`, `--goerli`, `--syncmode` |
| Logging | `--verbosity`, `--log.file`, `--log.format`, `--log.maxsize`, `--log.maxbackups`, `--log.maxage`, `--log.compress` |
| Caches and database | `--cache`, `--cache.database`, `--cache.gc`, `--cache.trie`, `--gcmode`, `--state.scheme`, `--db.engine`, `--datadir.ancient`, `--snapshot`, `--txlookuplimit`, `--history.transactions` |
| Networking | `--nodiscover`, `--nat`, `--netrestrict`, `--identity`, `--discovery.port`, `--discovery.dns` |
| RPC and IPC | `--ipcdisable`, `--ipcpath`, `--ipcapi`, `--rpc.gascap`, `--rpc.evmtimeout`, `--rpc.txfeecap`, `--rpc.batch-request-limit`, `--rpc.batch-response-max-size`, `--http.idletimeout`, `--ws.api`, `--graphql`, `--graphql.addr`, `--graphql.port`, `--graphql.vhosts`, `--graphql.corsdomain` |
| Mining | `--mine`, `--miner.gasprice` |
| Blob pool | `--txpool.blobpool.datacap`, `--txpool.blobpool.pricebump` |
| Accounts | `--unlock`, `--password`, `--allow-insecure-unlock`, `--nousb` |
| Profiling | `--pprof`, `--pprof.addr`, `--pprof.port` |

`--miner.gaslimit` and `--dev.gaslimit` are a fourth category: parsed into the
options plist and used only for dev-mode genesis, never for building (BUILD-04).
The RPC audit found this pattern for the IPC and `--rpc.*` flags (RPC-38); it is
far wider than that. Reference: geth registers each flag against a config field
and its TOML loader errors on an unknown key
(`cmd/utils/flags.go`, `cmd/geth/config.go`). Consequence: an operator can
migrate a geth command line verbatim, see the node start, and believe that
verbosity, sync mode, cache sizing, discovery, profiling and log rotation are in
effect. None of them are. Our TOML loader compounds this by silently ignoring
unknown keys (`src/app/cli/config/config.lisp`), so a typo produces a default
rather than an error.

**OPS-02 — No chain presets; `--genesis` is mandatory.**
Verdict MISSING. Severity completeness.
Ours: the preset flags are in the discarded boolean list
(`src/app/cli/options/definitions.lisp:42`), and startup fails with
`"--genesis is required unless --datadir contains an initialized genesis or --dev is enabled"`
(`src/app/cli/cli.lisp:198-199`). No embedded genesis or bootnode set exists for
any public network. Reference: geth ships genesis blocks and bootnodes for
mainnet, sepolia, holesky and hoodi (`core/genesis.go`, `params/bootnodes.go`)
and selects them from the preset flag. Consequence: joining a public network
requires sourcing a genesis file and a bootnode list from elsewhere, and any
mismatch is the operator's to detect. This is an honest capability boundary
rather than a bug — but the flags are accepted, which hides it.

**OPS-03 — The data directory is not locked.**
Verdict MISSING. Severity correctness.
Ours: `src/app/cli/devnet/files.lisp` derives the database, genesis and JWT
paths under the datadir (`:248-276`) and creates them; there is no lock file and
no `flock`. A search for `flock`, `"LOCK"` or a lock file across `src/` returns
nothing. `--pid-file` writes a pid (`src/app/cli/cli.lisp:220-222`) and is never
read back or used for exclusion. Reference: geth takes an exclusive `flock` on
`<instance>/LOCK` at startup and returns `ErrDatadirUsed` if it is held
(`node/node.go:315-321`), releasing it on close (`:325-331`). Consequence: two
processes can open the same datadir. Both import the same chain database, both
believe they own it, and both write generation-stamped exports to the same file;
the generation and authority-id checks in
`devnet-cli-journal-authoritative-p` will eventually detect the divergence and
fail one of them at *startup*, but nothing prevents concurrent writes while both
are running. Restarting a node without confirming the old one is gone is an
ordinary operator mistake, and it should fail immediately and loudly.

**OPS-04 — `--log-file` truncates the previous run's log.**
Verdict DIVERGENT. Severity operability.
Ours: `call-with-devnet-cli-telemetry-sink` opens the log with
`:if-exists :supersede`
(`src/app/cli/telemetry/sinks.lisp:49-53`). The error-path logger appends
(`:28-31`), so the two disagree. Reference: geth opens a plain log file with
`O_CREATE|O_APPEND|O_WRONLY` (`internal/debug/flags.go:223`) and, with
`--log.rotate`, hands it to lumberjack with size, backup, age and compression
settings (`:206-221`). Consequence: the restart an operator performs *because*
the node died overwrites the log that would explain why. Combined with OPS-01
(the whole rotation flag family is discarded) there is no retention story at all.

**OPS-05 — No log levels, no structured format, no rotation.**
Verdict MISSING. Severity operability.
Ours: `telemetry-log` records a level on the event
(`src/foundation/telemetry.lisp:127-134`) and no sink filters on it —
`stream-telemetry-sink` writes every event as a Lisp plist via `write`
(`:101-116`). There is no JSON or logfmt renderer for the log stream (the
Prometheus renderer at `:162-183` is for metrics), and `--verbosity`,
`--log.format` and the rotation family are discarded (OPS-01). Reference: geth
has five levels, `terminal`, `logfmt` and `json` handlers and per-module
overrides (`internal/debug/flags.go:60-110`); Nethermind uses NLog with
configurable targets. Consequence: an operator cannot turn the volume down on a
busy node or up while debugging, and cannot feed our log stream to any standard
collector without writing a Lisp-plist parser.

**OPS-06 — Metrics are event counts only.**
Verdict DIVERGENT. Severity operability.
Ours: the counting sink increments one counter per event name
(`src/foundation/telemetry.lisp:83-93`) and the endpoint renders them as a
single Prometheus counter with the event name as a label,
`ethereum_lisp_events_total{event="..."}` (`:162-183`), served at `/metrics` and
at geth's `/debug/metrics/prometheus`
(`src/app/cli/devnet/metrics-server.lisp:122-131`). The design rationale — that
counting events the node already emits cannot fall out of step with what it does
— is written down in the source and is a real advantage. What it cannot express
is a level. Reference: geth publishes gauges for `txpool/pending`,
`txpool/queued`, `txpool/slots`, `txpool/pending/accounts`,
`txpool/queued/accounts`
(`core/txpool/legacypool/legacypool.go:113-118`) and for `chain/head/block`,
`chain/head/header`, `chain/head/finalized`, `chain/head/safe`
(`core/blockchain.go:63-67`), plus timers for block insertion and execution;
Nethermind exposes a comparable set through `Nethermind.Monitoring`.
Consequence: the questions an operator actually asks — how many transactions are
pending, what block are we on, is the head advancing, how many peers — cannot be
answered from our metrics endpoint. A rate of `event="..."` counters is a
derivative, and no derivative recovers the level.

**OPS-07 — Any startup failure prints the whole usage string after the error.**
Verdict DIVERGENT. Severity operability.
Ours: the top-level handler prints the condition and then
`devnet-cli-print-usage` (`src/app/cli/cli.lisp:229-236`), whose body is one
format string of roughly four thousand characters listing every flag
(`src/app/cli/output.lisp:5`). Reference: geth's `utils.Fatalf` prints the
message and exits; usage is printed only for a usage error. Consequence: the one
line that says "Devnet database has no restartable head checkpoint" or
"Persistence artifact chain id is incompatible" is followed by a wall of flag
names, in a terminal and in whatever captured stderr. For the missing-state case
the state audit describes, this is the entire operator-facing surface of an
unrecoverable condition.

**OPS-08 — No profiling endpoint and no health endpoint.**
Verdict MISSING. Severity operability.
Ours: the metrics endpoint answers `/metrics` and
`/debug/metrics/prometheus` and 404s everything else
(`src/app/cli/devnet/metrics-server.lisp:129-131`); `--pprof`, `--pprof.addr`
and `--pprof.port` are discarded (OPS-01). Reference: geth serves the Go
`net/http/pprof` handlers plus `debug_` RPC methods for stack dumps, CPU and
heap profiles (`internal/debug/`). Consequence: a node that is slow or stuck
cannot be profiled in place. The `--ready-file` written at listener-ready
(`src/app/cli/cli.lisp:135-142`) is a startup signal, not a liveness probe, so
there is nothing an orchestrator can poll to decide the process is still healthy.

**OPS-09 — Unclean shutdown has no repair path, and the operator surface for it is one line plus usage.**
Verdict MISSING. Severity operability.
Ours: the export happens in the `unwind-protect` cleanup of the serve path
(`src/app/cli/cli.lisp:159`) and on each forkchoice persist
(`devnet-cli-forkchoice-persistence-function`,
`src/app/cli/devnet/persistence.lisp:80-100`), so a kill between persists loses
the interval. On restart, import validates the chain id, genesis hash, authority
id, generation ordering and the presence of a head checkpoint, and signals if any
of them fail (`:116-135`, `:239-254`, `:310-321`). Signal handling itself is
correct: SIGINT and SIGTERM request shutdown and are restored on exit
(`call-with-devnet-shutdown-signal-handlers`,
`src/app/cli/devnet/types.lisp:471-494`), listeners and workers are drained in
order (`src/app/cli/devnet/service.lisp:180-235`). What does not exist is any
remedy. There is no rewind, no repair, no "reset to block N", and no offline
inspection command — `init` is the only subcommand besides `devnet`
(`src/app/cli/init.lisp`). Reference: geth offers `geth removedb`,
`geth db inspect`, `geth import`/`export`, and `debug_setHead` for exactly this
situation. Consequence: as `state-trie-storage.md` established, a persisted head
whose state is missing fails startup outright. Combined with OPS-07 the operator
sees one sentence and a usage dump, and the only available action is to delete
the datadir and resync. That is an honest fail-stop rather than silent
corruption — which is the right choice per `PROJECT.md` — but there is no tooling
between "it starts" and "delete everything".

**OPS-10 — Persisted format has a version but no migration.**
Verdict MISSING. Severity completeness.
Ours: `+node-store-persistence-metadata-version+` is 1 and a mismatch signals
`"Unsupported node persistence metadata version"`
(`src/storage/node-store/persistence/metadata.lisp:3`, `:126-128`). There is no
upgrade path from an older version to a newer one. Reference: geth versions the
database and migrates in place where it can (`core/rawdb`), and prints an
explicit instruction when it cannot. Consequence: the first format change orphans
every existing datadir, with a resync as the only remedy. Detection is correct
and that is the harder half; recording this so the second half is not forgotten.

## Validation-check matrix — pool admission

Ours is `validate-txpool-admission` plus `validate-admission-policy` plus
`txpool-admit-transaction`
(`src/application/services/txpool-admission.lisp:105-165`, `:222-237`) unless
noted. geth is `core/txpool/validation.go` plus
`core/txpool/legacypool/legacypool.go`; Nethermind is
`src/Nethermind/Nethermind.Consensus/Validators/TxValidator.cs` plus
`src/Nethermind/Nethermind.TxPool/Filters/`.

| Check | geth | Nethermind | Ours |
| --- | --- | --- | --- |
| Signature valid, real sender recovery | yes (`validation.go:117-120`) | yes (`RecoverAuthorityFilter`, signature in `TxValidator`) | yes (`:226-232`) |
| Chain id matches | yes (`validation.go:117`, via signer) | yes (`ExpectedChainIdTxValidator`, `TxValidator.cs:159-163`) | yes (`:229-230`) |
| Transaction type enabled at head fork | yes (`validation.go:75-85`) | yes (`NotSupportedTxFilter`, `TxTypeTxFilter`) | yes (`validate-transaction-type-for-config`, `:109-110`) |
| Encoded size cap | yes, 128KB / 1MB (`validation.go:70`) | yes, 128KiB / 1MiB (`SizeTxFilter.cs:14-25`) | **no** (POOL-01) |
| Fee cap ≥ tip cap | yes (`validation.go:114`) | yes (`GasFieldsTxValidator`) | yes (`validate-transaction-scalar-fields`) |
| Fee-cap / tip 256-bit sanity | yes (`validation.go:107-113`) | yes (`GasFieldsTxValidator`) | yes (`uint256-p` in `validate-1559-transaction-fees`) |
| Nonce ≤ 2^64-1 (EIP-2681) | yes (`validation.go:122-124`) | yes | yes, structurally (`uint64` scalar check) |
| Nonce not below state nonce | yes (`ValidateTransactionWithState`) | yes (`LowNonceFilter`) | yes, but skipped without head state (`:74-75`, POOL-06) |
| Balance covers gas + value + blob cost | yes (`ValidateTransactionWithState`) | yes (`BalanceTooLowFilter`, `BalanceZeroFilter`) | yes, cumulative over pooled txs; skipped without head state (`:76-80`) |
| Intrinsic gas floor | yes (`validation.go:131-139`) | yes (`IntrinsicGasTxValidator`) | yes (`:125-132`) |
| EIP-7623 floor data gas | yes (`validation.go:141-153`) | yes (`IntrinsicGasTxValidator`) | **no** (POOL-03) |
| Gas limit ≤ head block gas limit | yes (`validation.go:102-105`) | yes (`GasLimitTxFilter`) | yes (`:133-137`) |
| EIP-7825 per-tx gas cap | yes (`validation.go:92-94`) | yes (spec-driven) | yes, Osaka-gated (`:138-143`) |
| Initcode size cap (EIP-3860) | yes (`validation.go:87-91`) | yes (`ContractSizeTxValidator`) | **no** (POOL-02) |
| Minimum tip / price floor | tip vs `MinTip` (`validation.go:157`) | `PriorityFeeTooLowFilter`, `FeeTooLowFilter` | fee cap vs price limit (POOL-04) |
| Base-fee eligibility routing | pending vs queued by base fee | `FeeTooLowFilter` + `MinBaseFeeThreshold` | yes, own basefee subpool (`:96-103`, `:180-183`) |
| Unprotected legacy tx gated | yes (`--rpc.allow-unprotected-txs`) | yes | yes (`:152-157`) |
| Sender has no non-delegation code | yes (`DeployedCodeFilter` equivalent in state validation) | yes (`DeployedCodeFilter`) | yes (`:58-65`) |
| Set-code tx has ≥1 authorization | yes (`validation.go:163-167`) | yes (`NonSetCodeFieldsTxValidator`) | yes (`:174-176` in consensus validation) |
| Authorization signature values valid | yes | yes | yes (`:225`) |
| Delegated-account in-flight limit | yes (`legacypool.go:600-623`) | yes (`DelegatedAccountFilter.cs:19-32`) | **no** (POOL-05) |
| Authority reserved against other txs | yes (`legacypool.go:627-660`) | yes (`DelegationCache`) | **no** (POOL-05) |
| Blob versioned-hash shape and count | yes (`validation.go:181-186`) | yes (`BlobFieldsTxValidator`, `TxValidator.cs:214-272`) | yes (`:117-120`) |
| Blob fee cap ≥ minimum / current | yes, ≥1 wei (`validation.go:175`) | yes | yes, vs current blob base fee (`:121-124`) |
| Blob sidecar present and consistent | yes (`validation.go:178-190`) | yes (`TxValidator.cs:309-313`) | **no**, structurally impossible (POOL-14) |
| Blob KZG proofs verified | yes (`ValidateCells`, `validation.go:192-215`) | yes (`ValidateProofs`) | **no** (POOL-14) |
| Duplicate-hash rejection | yes (`legacypool.go:668-671`) | yes (`AlreadyKnownTxFilter`) | yes (`:233-234`) |

## Remediation plan

Ordered so that each item is verifiable on its own and earlier items unblock
later ones. Sizes are S (a day or less), M (a few days), L (a week or more).

1. **Make a failing transaction skip its sender instead of failing the build (L).**
   BUILD-01. Depends on nothing; blocks everything else in the building area.
   Requires a per-transaction commit boundary inside the build path — execute
   incrementally against the working state, and on a per-transaction condition
   drop that sender's remaining transactions and continue, as geth does at
   `miner/worker.go:537-551`. Two secondary fixes belong here: make
   `transaction-validation-error` reachable by the same handler that catches
   `block-validation-error` so no failure mode can leave a request without a
   response, and keep an always-returnable empty payload behind every payload id
   so `forkchoiceUpdated` never answers a valid attribute set with an error.
   Verification: a test that admits a transaction whose gas limit is below the
   EIP-7623 floor, then asserts `forkchoiceUpdated` with attributes returns a
   payload id and that `getPayload` returns a block excluding it; and a second
   test asserting a JSON-RPC response is produced (not a closed connection) when
   a pending transaction's sender balance is short.
2. **Filter the pending set at the child's base fee (S).** BUILD-02. Independent
   of item 1 and worth doing first because it is the routine trigger: pass
   `(expected-base-fee-per-gas parent-header)` where selection currently relies
   on a pending list filtered at the head's base fee, and skip transactions whose
   cap is below it. Verification: a test with a parent above the gas target and a
   pending transaction whose cap sits between the two base fees, asserting the
   built block excludes it and the build succeeds.
3. **Add the missing admission checks (S).** POOL-01, POOL-02, POOL-03.
   Independent. Encoded-size cap, EIP-3860 initcode cap, EIP-7623 floor data gas
   — the last two by calling the same functions the execution path already uses,
   so the two thresholds cannot drift. Verification: three tests asserting
   `eth_sendRawTransaction` rejects each shape, plus a test that the pool cannot
   hold a transaction that `charge-sender-upfront` would refuse.
4. **Give every pool limit a default and evict on overflow (M).** POOL-07,
   POOL-08, POOL-09. Depends on nothing. Adopt geth's defaults explicitly, or
   pick our own and document the divergence; extend limits to the basefee and
   blob subpools; and on overflow discard the cheapest resident unless the
   newcomer is the cheapest, which needs a price-ordered view the pool does not
   have today. Verification: a test filling the pool to its limit and asserting a
   higher-priced arrival is admitted and the cheapest resident is gone; a test
   asserting the basefee subpool is bounded.
5. **Target a gas ceiling and honour `--miner.gaslimit` (S).** BUILD-04. Depends
   on nothing. Thread the option through `devnet-cli-make-node` to the builder
   and apply the 1/1024 hone-toward-target rule; the Amsterdam
   `targetGasLimit` half depends on RPC-04. Verification: a test building on a
   parent with limit L and a configured ceiling above it, asserting the built
   header's limit is `L + L/1024 - 1`.
6. **Run pool maintenance on a timer (S).** POOL-10. Depends on nothing.
   Move lifetime expiry off the public-RPC dispatch path onto the existing
   background worker alongside the rejournal thread, and give the lifetime a
   default. Verification: a test that a queued transaction expires on a node with
   no public RPC listener at all.
7. **Improve the payload while the consensus client waits (L).** BUILD-03,
   BUILD-09. Depends on item 1 — rebuilding is pointless while one bad
   transaction can fail a rebuild — and on the payload-id derivation question in
   RPC-01, since improvement requires a stable id. Verification: a test that
   admits a high-tip transaction after `forkchoiceUpdated` returns and asserts
   `getPayload` for the same id returns a block containing it.
8. **Re-compare senders after each inclusion, and pack against actual gas (M).**
   BUILD-05, BUILD-06. Depends on item 1, because both require selection and
   execution to interleave rather than selection completing first. Verification:
   the ordering test from `txpool-mining-order-tests.lisp` extended with the
   100/1 versus 50 case; and a test asserting a block includes a second
   transaction that only fits once the first one's unused gas is reclaimed.
9. **Lock the data directory (S).** OPS-03. Independent. Verification: a test
   that starting a second node on the same datadir fails with a distinct error
   while the first is running.
10. **Fix the operator-facing output (S).** OPS-04, OPS-07. Independent. Append
    to the log rather than truncating it; print usage only for a usage error.
    Verification: a test asserting a second run's log still contains the first
    run's records; a test asserting a startup failure's stderr does not contain
    the usage string.
11. **Publish gauges, not only counters (M).** OPS-06. Independent. Add a gauge
    kind to the telemetry sink and expose pending, queued, basefee and blob
    counts, head/safe/finalized numbers, and peer count. Verification: a scrape
    test asserting the exposition contains a `# TYPE ... gauge` line for pool
    size and that the value tracks an admitted transaction.
12. **Stop accepting flags we ignore (M).** OPS-01. Independent, and largely a
    decision rather than a construction: for each discarded flag, either
    implement it, reject it with a message naming what is unsupported, or accept
    it while emitting a warning at startup that names it. Verification: a test
    enumerating the accepted-option lists and asserting every entry is either
    consumed into the options plist or produces a warning. The RPC audit proposes
    the same shape of test for its subset (RPC-38); one test should cover both.
13. **Enforce the EIP-7702 pool rules (M).** POOL-05. Depends on item 4 for the
    reservation bookkeeping. Verification: a test asserting a second in-flight
    transaction from a delegated account is rejected, and that a set-code
    transaction naming an authority with pending transactions is rejected.
14. **Decide the blob story (L).** POOL-13, POOL-14, POOL-12, BUILD-08. Depends
    on items 1 and 4. This is a design decision before it is work: either carry
    sidecars on the pooled transaction — which means a network-wrapper codec, KZG
    verification at admission wired to the existing
    `validate-blob-sidecar-kzg-proofs`, blob-aware selection with a per-block
    blob budget, a real `blobsBundle` (RPC-06), and blob-specific replacement
    and eviction rules — or reject blob transactions at admission with a clear
    message so a submitter learns immediately that this node does not carry them.
    The second is small and honest; the first is what a mainnet client needs.
    Verification for the honest path: a test asserting
    `eth_sendRawTransaction` of a type-3 transaction is refused with a message
    naming the limitation, and that `txpool_status` never reports a blob
    transaction.

## Remediation status (2026-07-29)

Implemented in `gap/txpool-build-ops`:

- BUILD-01 and BUILD-02: poisoned senders no longer poison the payload and
  child-base-fee eligibility is checked during selection.
- POOL-01 through POOL-11: encoded-size, initcode, Prague floor-gas, effective
  tip, delegated-authority and bounded-capacity rules are enforced. Default
  price, replacement, account, global and lifetime limits are active; overflow
  evicts lower-value residents, and canonical promotion preserves the policy.
- BUILD-03 and BUILD-09: `forkchoiceUpdated` publishes a stable payload id
  before pool execution, a background worker improves open payloads, and
  `getPayload` performs a final improvement before closing the candidate.
- BUILD-04 through BUILD-07: `--miner.gaslimit` reaches Engine and dev-period
  construction with protocol-compliant honing; sender heads are re-ranked after
  each nonce; execution and filling interleave against actual cumulative gas;
  and Osaka payloads enforce the EIP-7934 RLP-size cap.
- POOL-10 and OPS-03, OPS-04, OPS-06, OPS-07: the datadir has an exclusive
  process lock, txpool lifetime cleanup has an independent worker, logs append,
  ordinary startup failures no longer dump usage, and Prometheus exposes live
  pool/head/finality/peer gauges.
- POOL-12 through POOL-14 and BUILD-08: EIP-4844 pooled wrappers carry
  sidecars, public and peer admission verifies sidecar shape and KZG proofs,
  blob replacement applies the blob-specific bump, payloads include blob gas,
  and `blobsBundle` is assembled from stored sidecars.
- POOL-15: a bounded txpool change log drives hash announcements from every
  subpool; blob fetch and relay preserves the verified sidecar.
- Compatibility-only CLI flags now emit an explicit ignored-option warning
  instead of disappearing silently.
- OPS-02: public-chain flags now select a validated preset bundle through the
  exported network-provider seam. The bundle supplies canonical genesis JSON,
  network id and bootnodes; startup fails explicitly if the network package has
  not installed a complete bundle. This keeps canonical chain data in the
  network-owned branch without silently treating a public-chain flag as a
  no-op.

The ordered remediation plan above is complete in this branch. Canonical public
chain data remains owned by the network package and plugs into
`*DEVNET-CHAIN-PRESET-PROVIDER*`; that merge seam is an integration boundary,
not an unimplemented fallback in this area.

Cold Docker verification after remediation: unit 933 passed / 3 skipped,
integration 304 passed / 2 skipped, and the complete two-worker E2E layer
passed 59 tests. The E2E workers completed in 303 and 386 seconds respectively,
with explicit zero exit status under a 600-second worker bound.

## Out of scope, and left unverified

Out of scope by assignment: the Engine API and JSON-RPC wire surfaces
(`rpc-and-engine.md`), including the payload-id derivation, the empty
`blockValue`, and the `-38003` versus `-38005` code choices; block and header
validation and the Amsterdam block access list
(`block-execution-and-types.md`); state, trie and storage behaviour including
the absence of a rewind path (`state-trie-storage.md`); EVM and gas accounting
(`evm-and-gas.md`); and the devp2p handshake, discovery and sync protocol beyond
the transaction-broadcast seam in POOL-15.

Overlaps to dedupe: BUILD-08 settles RPC-06; BUILD-04 shares the gas-limit
question with RPC-04; OPS-01 is the general case of RPC-38; POOL-05 is the
pool-side face of the EIP-7702 delegation gating in `evm-and-gas.md`; BUILD-07
is the building side of the block-size cap owned by
`block-execution-and-types.md`; OPS-09 is the operational face of the
missing-state fail-stop owned by `state-trie-storage.md`.

Left unverified, and why:

- **Every claim except POOL-13's pooling-and-selection behaviour is a source
  reading.** The warm image died mid-audit (exit 137, container stopped) and this
  session may not restart it. The claims most worth converting to executions are:
  BUILD-01's two failure classes, by building a payload with a poisoned pending
  list and observing what `forkchoiceUpdated` returns in each case; BUILD-02, by
  admitting a transaction inside the base-fee window and attempting a build; and
  the exact `NIL`-default behaviour of the pool limits, by inspecting a node's
  policy struct after startup with no `--txpool.*` flags.
- **The discarded-flag count of 56** was derived by comparing the two accepted-option
  lists against the flags the parser branches on, both read from source. A flag
  consumed in `init.lisp`'s separate parser rather than in `options.lisp` would
  make the count slightly high; spot checks on `--verbosity`, `--syncmode`,
  `--nodiscover`, `--log.format` and the chain presets confirmed those five
  appear nowhere in `src/` outside the definition list, the usage string and the
  TOML mapper.
- **Whether two concurrently running processes on one datadir actually corrupt
  the database**, as opposed to one of them failing at the next generation check.
  The generation and authority-id machinery is careful enough that the outcome is
  not obvious from reading, and establishing it needs two processes and a
  filesystem, not an eval.
- **Nethermind's block-production transaction ordering** was not read in the
  detail geth's was; the Nethermind citations here are for pool filters,
  configuration defaults and the payload-improvement loop only.
- **Whether the dev-period sealer shares BUILD-01's failure mode.** It calls the
  same selection and the same `execute-signed-block`
  (`src/app/cli/devnet/runtime.lisp:88-130`) so it almost certainly does, but the
  surrounding worker's error classification was not traced to the point where the
  observable behaviour — retry, skip, or fail-stop the node — could be stated.
