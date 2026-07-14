# Current Status

Last updated: 2026-07-14

This is a replace-in-place snapshot of verified project state. It is not a
backlog or implementation history; completed detail is available from Git.

## Baseline

- Branch baseline at the start of this phase:
  `codex/goal-led-live-persistence` at `ae2602d`.
- `make docker-test-all` passed on 2026-07-14 with 984 tests passed,
  5 optional-fixture tests skipped, and 0 failed: unit 710/3 skipped,
  integration 215/2 skipped, and e2e 59/0 skipped.
- The skipped tests require an external EEST fixture root and are not counted
  as external fixture validation.

## Verified Phase Closures

### Verifiable Shanghai import

Closed for the pinned EEST v5.4.0 post-Merge Shanghai profile:

- genesis and retained state loading;
- executable known-parent `engine_newPayloadV2` import;
- atomic transaction execution and commitment validation;
- strict sender recovery;
- receipt, logs bloom, gas-used, and state-root validation;
- canonical forkchoice switching, checkpoint ancestry, and reorg visibility;
- pinned state, transaction, trie, and blockchain fixture adapters.

The remaining official v5.4.0 transaction candidates are Prague/EIP-7702
cases outside this Shanghai closure profile, not known Shanghai drift.

### Local Engine/RPC devnet

Closed for the repository-local process profile:

- genesis/datadir initialization and geth-shaped process arguments;
- split JWT-authenticated Engine and unauthenticated public HTTP listeners;
- readiness, telemetry, PID artifacts, signal shutdown, and listener cleanup;
- Engine capability exchange, forkchoice, payload preparation/retrieval, and
  executable payload import;
- retained-state reads, call simulation, gas estimation, access-list creation,
  receipts, logs, filters, and canonical block/transaction lookup;
- policy-driven pending, queued, base-fee, and blob transaction-pool views,
  replacement, limits, expiry, journal restore, and dev-period selection;
- development KV export/import, restart, bounded state pruning, side reorg,
  displaced-transaction reinsertion, and safe/finalized restoration;
- opt-in trusted-setup-backed KZG verification and capability gating.

This closure means the local process contract is usable for controlled devnet
scenarios. The repository has not demonstrated a run under the external
Ethereum Hive harness and does not claim devp2p or live network sync.

The current payload builder is a development minimum: it selects executable
pending transactions deterministically, but does not claim fee-optimal package
selection, execution-aware gas repacking, or blob-sidecar construction.

## Current Architecture

- Consensus, transaction, block, state, EVM, execution, Engine, RPC, transport,
  persistence, and CLI responsibilities have explicit package boundaries.
- The in-memory chain-store and transaction-pool components are composed by a
  cross-domain node-store service.
- A generic byte-key/value protocol supports memory and S-expression
  file-backed development databases with ordered batches and range iteration.
- Chain, state snapshot, checkpoint, transaction-location, txpool, invalid
  payload, remote block, blob-sidecar, and prepared-payload records can be
  exported to KV and validated through staged import.
- Engine `newPayload` imports are hash-addressed candidates and do not become
  canonical, expose canonical receipts, or remove included txpool transactions
  before a successful forkchoice transition.
- Each `VALID` `engine_newPayloadV1` through V5 candidate now writes its block,
  header, receipts, and state records, plus any missing ancestry, to the
  configured development database before the response. Existing bytes must
  match, repeat delivery is idempotent, and the batch does not write canonical,
  checkpoint, transaction-location, or txpool records.
- An empty configured database is seeded with the current canonical genesis
  view and an explicit head bound before listeners become ready. A validated
  legacy baseline without a head checkpoint is migrated once at startup; live
  direct-key deltas reject an unbounded baseline. A nonempty database without
  a chain baseline is rejected instead of being overwritten.
- A successful `engine_forkchoiceUpdatedV1` through V4 now publishes canonical,
  safe, finalized, transaction-location, state, and txpool changes to the
  configured development database in one file batch before returning `VALID`.
  A durable-write error restores the prior in-memory view and returns JSON-RPC
  `-32603` instead of an Engine payload status.
- Forkchoice persistence is logically record-scoped. The canonical service
  emits installed/displaced blocks and affected txpool hashes; the exporter
  performs direct keyed reads and writes only for affected heights,
  checkpoints, immutable block/header/receipt/state records, transaction
  locations, and final txpool records. It does not iterate the database or the
  complete known block/state view.
- A direct-key canonical reconciliation walk stops at the first persisted
  common ancestor. It flushes locally canonicalized blocks before a same-head
  forkchoice response and handles a persisted higher or divergent head while
  retaining hash-addressed displaced block records and deleting their stale
  transaction locations. Delta export requires the chain baseline seeded by
  startup rather than partially initializing an empty database.
- Txpool mutations accumulate a hash-scoped dirty set from the last successful
  chain-database commit. The set survives atomic snapshots, covers startup
  normalization and journal-derived mutations, joins the next forkchoice
  batch, and is acknowledged only after a successful atomic KV apply.
- Dev-period execution first stages a noncanonical block and post-state, then
  explicitly selects it as canonical to produce the same transition descriptor
  used by forkchoice persistence. Execution, head/checkpoint publication,
  receipt/state/location indexes, txpool reconciliation, and the synchronous
  record-scoped database callback share one rollback boundary under the
  node-store guard. A failed KV batch restores the prior public view, leaves the
  tick immediately retryable, emits a warning, and is retried by the live
  worker on a later tick when the adapter classifies it as a transient
  file-write error. Validation, corruption, and callback invariant errors
  fail-stop instead; no-database dev mode preserves in-memory sealing without a
  storage callback. Local sealing always extends the consensus-selected head,
  never an unselected `newPayload` side candidate.
- Engine RPC, public RPC, dev-period sealing, pruning, rejournaling, and
  lifecycle export share one node-store guard, so another thread cannot observe
  or mutate a tentative canonical view while its durable batch is pending.
- Restart tolerates an independently persisted txpool journal that lags the
  authoritative canonical database, while the generic KV importer remains
  strict about duplicate indexed transactions.
- Unit, integration, and process tests collectively cover candidate exporter
  conflicts and idempotence, delta scope without database iteration,
  checkpoint-only updates, extension/short/same-height reorgs, DB-ahead
  reconciliation, startup txpool normalization, persistence failure rollback
  and retry, concurrent public reads, stale-journal recovery, and SIGKILL
  recovery before forkchoice, after forkchoice, and immediately after a local
  dev-period receipt becomes public without a shutdown export.

## Principal Gaps

1. The chain database and independently refreshed txpool journal have no shared
   generation marker. The current empty/nonempty selection rule can skip a
   newer journal overlay or reintroduce a stale noncanonical transaction.
2. Lifecycle export remains a full readable-store snapshot even though live
   `newPayload`, forkchoice, and dev-period commits are record-scoped.
3. Trie/state data is restored from whole account snapshots rather than durable
   content-addressed trie/state nodes with an explicit retention policy.
4. The file backend uses temp-file replacement but does not fsync the file and
   containing directory, so the verified SIGKILL/process-crash contract is not
   a power-loss durability claim.
5. Header/body/execution/receipt/index stages do not yet have persisted progress
   markers and unwind functions.
6. There is no implemented discovery, RLPx, `eth`, or `snap` peer path.
7. External Hive interoperability has not been demonstrated.

## Active Objective

The active Phase C objective is the next recovery-authority slice:

> Give the synchronously committed chain database and the independently
> refreshed transaction-pool journal an explicit generation and authority
> contract, so restart deterministically accepts a compatible newer overlay,
> ignores stale data, and never reintroduces a canonical transaction.

The slice must define persisted generation metadata, update ordering, startup
selection, and failure semantics without pretending the two files share one
atomic write. The canonical chain database remains authoritative for included
transactions; a journal overlay is eligible only under the explicit generation
rule. It must preserve database-only, journal-only, and no-persistence modes,
and must not introduce networking or a new database dependency, add trie-node
storage, claim power-loss durability, or add historical pruning.

Acceptance requires deterministic tests for fresh/equal/newer/stale generation
combinations, crashes on both sides of chain and journal updates, malformed or
incompatible metadata, canonical-transaction suppression, independent diff
review, and the gates selected by `docs/validation.md`.
