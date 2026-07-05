# Loop State

Last updated: 2026-07-05

## Project State

- The repository target is a usable Common Lisp Ethereum execution-layer
  client.
- Phase A's bounded in-repo chain-import smoke path is documented as closed for
  the current Shanghai fixture set.
- Current highest strategic priority is Phase B local devnet, Engine/public RPC
  process behavior, Hive/process-runner readiness, and txpool/chain-store
  correctness that affects executable client behavior.
- Official execution-spec-tests v5.4.0 stable fixtures are expected at
  `.cache/eest-v5.4.0/root/fixtures` with archive SHA256
  `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`.

## Current Dirty Work

No intended dirty implementation work should remain after the current validated
batch is committed and pushed. The latest completed slice is
`ENGINE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-CACHE`; the next run spec is
prepared for
`DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT`.

Closed behavior from the latest slice:

- Positive `--dev.period DURATION` parses through the shared geth-style
  duration path and rejects malformed or negative values.
- Devnet summaries, readiness data, and lifecycle telemetry report
  `devPeriodSeconds`.
- Long-running devnet serve mode starts a shutdown-aware background dev-period
  tick when the configured period is positive.
- The deterministic tick path can seal currently pending, recoverable public
  txpool transactions into a local child block on top of the current devnet
  head.
- The sealed block uses the existing signed-block execution and commit path,
  advances public latest-head state, indexes included transaction/receipt
  lookups, and removes mined transactions from pending txpool visibility.
- The standalone devnet smoke gate txpool-rejournal helper now waits for the
  full expected journal record count before reporting, removing a race between
  "target record observed" and "all expected records flushed".
- The geth-style mining/archive/metrics CLI flag test now creates a readable
  temporary TOML config instead of depending on a fixed `/tmp` file.
- The standalone devnet smoke gate now runs an independent `--dev.period=1s`
  listener-boundary probe that submits a public raw transaction, waits for the
  background period tick to seal it, and reports mined transaction, receipt,
  block, and txpool cleanup evidence.
- The dev-period smoke probe uses a stable one-transfer fixture independent of
  the surrounding all-fixtures payload case, so the runner-boundary period tick
  contract is not coupled to unrelated fixture transaction shapes.
- The local dev-period tick now selects a deterministic prefix of recoverable
  public txpool transactions whose cumulative gas limit fits the child block
  gas limit, enters block execution only when at least one transaction fits,
  and leaves non-selected pending transactions visible for later blocks.
- The local dev-period selector is now sender-aware: when one sender's next
  nonce-safe transaction would exceed the remaining child block gas, that
  sender is skipped for the rest of the current block while later independent
  sender heads may still be selected if they fit.
- The shared local mining selector now lives in core and is reused by both the
  dev-period block-production path and Engine prepared-payload construction.
- Engine `engine_forkchoiceUpdated*` prepared payloads now select recoverable
  public pending txpool transactions with the deterministic, gas-limited,
  sender-aware policy.
- Non-empty prepared payloads execute the selected signed transactions against
  parent state to materialize payload block commitments without committing the
  block or removing txpool entries.
- Non-empty prepared payload ids include the selected transaction root, so a
  repeated same-head/same-attributes `engine_forkchoiceUpdated*` call after
  txpool changes gets a distinct cache key instead of reusing stale empty
  payloads.
- `engine_getPayloadV1` returns selected transaction bytes for prepared local
  payloads, while selected and non-selected txpool entries remain
  public-visible before import/forkchoice.
- The standalone devnet smoke gate now proves txpool-backed prepared-payload
  selection across the real authenticated Engine/public listener boundary. It
  admits public txpool transactions, prepares a second payload through
  authenticated `engine_forkchoiceUpdatedV2`, retrieves it through
  authenticated `engine_getPayloadV2`, reports the selected transaction
  raw bytes/hash, and runs a post-preparation public `txpool_contentFrom`
  query proving the selected pending transaction and non-selected basefee /
  nonce-gapped queued transactions remain public-visible before
  import/forkchoice.
- The standalone devnet smoke gate now imports that retrieved txpool-backed
  prepared payload through authenticated `engine_newPayloadV2`, canonicalizes it
  through `engine_forkchoiceUpdatedV2`, verifies public canonical transaction,
  receipt, raw transaction, and block visibility for the selected transaction,
  and verifies txpool cleanup removes the mined transaction while non-selected
  basefee and nonce-gapped entries remain queued.
- Focused in-process Engine RPC coverage now proves same-head/same-attributes
  prepared-payload cache refresh when a valid same-sender/same-nonce public
  txpool replacement changes the selected transaction without changing the
  selected transaction count. The second payload id is distinct,
  `engine_getPayloadV1` returns only the replacement raw transaction, and
  `txpool_contentFrom` exposes only the replacement at that sender/nonce before
  import.

Closed validation:

- Focused dev-period coverage passed inside the full suite:
  `DEVNET-CLI-DEV-PERIOD-PARSES-AND-REPORTS-DURATION` and
  `DEVNET-CLI-DEV-PERIOD-TICK-SEALS-PUBLIC-TXPOOL-TRANSACTION`,
  plus `DEVNET-CLI-DEV-PERIOD-TICK-CARRIES-ACTIVE-FORK-BODIES` for
  fork-active Cancun/Prague/Amsterdam empty body/header fields.
- The focused escalated standalone smoke gate passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- `git diff --check` passed.
- The first escalated `sbcl --script tests/run-tests.lisp` run failed in
  `DEVNET-SMOKE-GATE-SCRIPT-RUNS-ALL-PINNED-FIXTURES` because the new
  dev-period probe was mistakenly coupled to each payload fixture's txpool
  transaction shape.
- After changing the probe to use a stable one-transfer fixture, the focused
  escalated all-fixtures smoke command passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures ...`.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `886 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`; residual risk is limited to the
  intentional stable Shanghai one-transfer probe fixture, which proves the
  runner-boundary period tick contract but does not claim per-fixture mining
  semantics.
- Focused direct CLI coverage for
  `DEVNET-CLI-DEV-PERIOD-TICK-BOUNDS-TRANSACTIONS-BY-GAS-LIMIT` passed during
  the current run.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `887 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risks: the no-fitting
  first-transaction edge is covered by the selector shape but does not yet have
  focused coverage, and receipt visibility for the multi-transaction bounded
  case relies on the existing single-transaction dev-period receipt coverage.
- Focused direct CLI coverage for
  `DEVNET-CLI-DEV-PERIOD-TICK-SELECTS-FITTING-SECOND-SENDER` and
  `DEVNET-CLI-DEV-PERIOD-TICK-BOUNDS-TRANSACTIONS-BY-GAS-LIMIT` passed during
  the current run.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `888 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risks: the case where
  the first sorted sender head does not fit but a later sender head does is
  covered by the sender-aware selector structure but not yet by a dedicated
  focused test, and no explicit third same-sender nonce fixture asserts blocked
  sender tails beyond the currently non-fitting nonce.
- Focused direct Engine RPC coverage for
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-SELECTS-PENDING-TXPOOL-TRANSACTIONS`
  and
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-PAYLOAD-ID-TRACKS-TXPOOL-SELECTION`
  passed during the current run.
- `git diff --check` passed.
- The first sandbox `sbcl --script tests/run-tests.lisp` run reached the new
  focused prepared-payload test but failed at the local socket/devnet Phase A
  smoke gate under sandbox restrictions.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- Independent verifier review returned `PASS` after the prepared-payload cache
  key was changed to include the selected transaction root for non-empty
  txpool-backed payloads. Residual risks: replacement churn preserving
  transaction count and V2/V3 prepared-payload txpool variants remain useful
  follow-up coverage, but are not blocking this slice.
- Focused escalated standalone smoke for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION` passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- `git diff --check` passed.
- The first escalated `sbcl --script tests/run-tests.lisp` run failed because
  `tests/cli-tests.lisp` still hard-coded the old standalone smoke connection
  contract (`engineWorkflowConnections=12`, `publicTxpoolConnections=19`).
- After updating the connection-contract assertions to the new
  `engineWorkflowConnections=14`, `publicTxpoolConnections=20`, single-case
  `engineConnections=19`, `publicConnections=46`, and `totalConnections=65`,
  the escalated `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- The first independent verifier review for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION` returned `FAIL`
  because the runtime smoke report emitted txpool-backed prepared-payload JSON
  evidence, but `tests/cli-tests.lisp` only asserted the new connection counts.
- `tests/cli-tests.lisp` now asserts `preparedTxpoolPayloadId`,
  `engineGetPayloadV2TxpoolParentHash`,
  `engineGetPayloadV2TxpoolBlockNumber`,
  `engineGetPayloadV2TxpoolTransactionCount`,
  `engineGetPayloadV2TxpoolSelectedTransactionRaw`,
  `engineGetPayloadV2TxpoolSelectedTransactionHash`,
  `engineGetPayloadV2TxpoolSelectedStillPending`,
  `engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued`, and
  `engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued` against the
  corresponding prepared payload and public txpool fields.
- After the JSON evidence assertions were added, the escalated
  `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- The second independent verifier review returned `PASS`: the verifier found
  the smoke report evidence and CLI JSON field assertions sufficient for the
  selected runner-boundary slice.
- Focused escalated standalone smoke for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-IMPORT` passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`. Key report fields
  include `engineNewPayloadV2TxpoolImportStatus=VALID`,
  `engineForkchoiceUpdatedV2TxpoolImportStatus=VALID`,
  `txpoolImportTxpoolStatusPending=0x0`,
  `txpoolImportTxpoolStatusQueued=0x2`, and
  `txpoolImportSelectedStillPending=false`.
- A fresh escalated all-fixtures devnet smoke command passed after the suite
  head assertions were updated to expect the imported txpool payload as the
  restored canonical head:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures ...`.
- Final pre-commit validation passed:
  `git diff --check` and `sbcl --script tests/run-tests.lisp`
  (`890 tests passed, 5 skipped`).
- Independent verifier review returned `PASS`. Residual risks: coverage is
  still the V2 Shanghai-style prepared-payload path; V3/V4 prepared-payload
  variants and same-sender replacement-cache churn remain follow-up scope.
- Focused direct Engine RPC coverage for
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-REFRESHES-TXPOOL-REPLACEMENT-PAYLOAD-ID`
  passed during the current run.
- `git diff --check` passed.
- The first sandbox `sbcl --script tests/run-tests.lisp` run failed in
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE`, consistent with the
  local socket/devnet smoke-gate sandbox restriction.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `891 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risk: coverage is
  intentionally in-process and V1-only; the split public/Engine listener and
  V2 smoke boundary is documented as the next run.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

The next highest-value Phase B slice is
`DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT`: promote the
same-sender/same-nonce replacement-cache boundary from in-process Engine RPC
coverage to the standalone split Engine/public listener smoke path, report the
two payload ids, replacement raw transaction evidence, and public txpool
sender/nonce visibility, and keep existing txpool-backed prepared-payload
selection/import evidence stable.
