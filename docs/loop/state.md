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

No dirty implementation work is expected after the current run commits and
pushes. The dev-period tick slice has been implemented, validated,
independently reviewed, and is pending commit/push in the current run.

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

Closed validation:

- Focused dev-period coverage passed inside the full suite:
  `DEVNET-CLI-DEV-PERIOD-PARSES-AND-REPORTS-DURATION` and
  `DEVNET-CLI-DEV-PERIOD-TICK-SEALS-PUBLIC-TXPOOL-TRANSACTION`,
  plus `DEVNET-CLI-DEV-PERIOD-TICK-CARRIES-ACTIVE-FORK-BODIES` for
  fork-active Cancun/Prague/Amsterdam empty body/header fields.
- The focused escalated standalone smoke gate passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- `git diff --check` passed.
- The first escalated `sbcl --script tests/run-tests.lisp` run exposed and
  helped fix a pre-existing standalone smoke race in txpool rejournal record
  counting.
- The second escalated full-suite run exposed and helped fix a pre-existing
  hard-coded `/tmp/ethereum-lisp-geth.toml` test fixture dependency.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `886 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. The earlier high-severity
  concern around post-Shanghai fork body/header fields was resolved by the
  active-fork body coverage above. Residual risk is limited to background
  thread lifecycle/process-boundary coverage, which is the selected next
  `DEVNET-RUNNER-DEV-PERIOD-SMOKE` slice.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

The next loop run should consume the refreshed `docs/loop/next-run.md` as an
implementer contract for `DEVNET-RUNNER-DEV-PERIOD-SMOKE`. Do not continue the
completed txpool lifetime, journal, rejournal, rejournal smoke, or dev-period
tick tasks. The next highest-value Phase B slice is to prove the background
`--dev.period` tick across the standalone process/smoke boundary and report
runner-visible mined-block evidence.
