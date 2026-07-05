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

The current run is implementing
`DEVNET-RUNNER-PREPARED-PAYLOAD-TXPOOL-SELECTION`. Code changes, focused
Engine RPC coverage, `git diff --check`, and escalated full-suite validation
are complete. Independent verifier review returned `PASS`; commit and push are
pending.

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

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

The current loop run should finish
`DEVNET-RUNNER-PREPARED-PAYLOAD-TXPOOL-SELECTION` by committing and pushing the
validated work. After that, the next highest-value Phase B slice is
`DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION`: prove the
txpool-backed prepared-payload path across the standalone devnet
Engine/public listener boundary and report runner-visible evidence.
