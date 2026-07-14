# Current Status

Last updated: 2026-07-13

This is a replace-in-place snapshot of verified project state. It is not a
backlog or implementation history; completed detail is available from Git.

## Baseline

- Branch baseline at the start of this update: `main` at `5585cfe`.
- The worktree was clean and aligned with `origin/main`.
- `make test-all E2E_JOBS=4` passed on 2026-07-13 with 961 tests passed,
  5 optional-fixture tests skipped, and 0 failed: unit 698/3 skipped,
  integration 205/2 skipped, and e2e 58/0 skipped.
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
  view before listeners become ready. A nonempty database without a chain
  baseline is rejected instead of being overwritten.
- A successful `engine_forkchoiceUpdatedV1` through V4 now publishes canonical,
  safe, finalized, transaction-location, state, and txpool changes to the
  configured development database in one file batch before returning `VALID`.
  A durable-write error restores the prior in-memory view and returns JSON-RPC
  `-32603` instead of an Engine payload status.
- Engine RPC, public RPC, dev-period sealing, pruning, rejournaling, and
  lifecycle export share one node-store guard, so another thread cannot observe
  or mutate the tentative forkchoice view while its durable batch is pending.
- Restart tolerates an independently persisted txpool journal that lags the
  authoritative canonical database, while the generic KV importer remains
  strict about duplicate indexed transactions.
- Unit, integration, and process tests collectively cover candidate exporter
  conflicts and idempotence, persistence failure rollback, concurrent public
  reads, stale-journal recovery, and SIGKILL recovery both before and after
  forkchoice without a shutdown export.

## Principal Gaps

1. The live forkchoice adapter still scans the complete known
   block/state/txpool view to construct each batch; it is not logically
   record-scoped incremental persistence.
2. Dev-period blocks still depend on lifecycle export rather than a durable
   commit before public canonical visibility.
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

The active Phase C objective is the next record-scoped durability slice:

> Replace the live forkchoice full-known-store export with a logical delta batch
> scoped to the selected canonical transition: changed canonical/checkpoint
> indexes, newly required block/header/receipt/state records, affected
> transaction locations, and coupled txpool changes must commit before the
> `VALID` response.

The slice must preserve reorg and stale-journal behavior, delete obsolete
canonical/location records, avoid scanning or rewriting unrelated side-chain
records at the logical KV layer, and retain the existing in-memory rollback and
shared request guard. It must not claim physical incremental I/O from the
S-expression backend, introduce networking, a new database dependency,
trie-node storage, power-loss guarantees, or historical pruning.

Acceptance requires extension and reorg restart tests, focused delta-scope and
failure/rollback tests, an independent diff review, and the gates selected by
`docs/validation.md`.
