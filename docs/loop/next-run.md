# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: current run is expected to commit and push
  `DEVNET-RUNNER-DEV-PERIOD-TICK` before the next run starts.
- Recent commits reviewed: `c787e9f`, `86ce18c`, `44c5d20`, `7f79d65`,
  `df4afd2`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The
  previous slice made `--dev.period` parse/report and added a deterministic
  block-production tick plus background serve-mode thread.
- Relevant loop state: txpool lifetime, journal, rejournal, rejournal smoke,
  and dev-period deterministic tick behavior are closed. The remaining
  dev-period gap is runner-visible process smoke coverage for the background
  tick.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-DEV-PERIOD-SMOKE`, proving
  `--dev.period` background block production across the standalone devnet
  smoke/process boundary.
- Value: high; converts the new deterministic tick into a Hive-style runner
  contract and directly advances executable local devnet behavior.
- Risk: medium; touches the long standalone smoke script and introduces bounded
  waiting around live process behavior.
- Required validation: focused escalated standalone devnet smoke gate,
  `git diff --check`, full test suite once, and independent verifier review.
- Decision: selected.
- Reason: it closes the process-boundary gap left by the completed
  dev-period tick implementation before moving to a different Phase B area.

### Candidate B

- Objective: add fee/gas-aware transaction selection to local dev-period block
  sealing.
- Value: medium-high; improves block production robustness for multi-tx pools.
- Risk: medium-high; policy choices around ordering, affordability, and gas
  limits need careful reference-client comparison.
- Required validation: focused txpool/block-construction tests plus full suite.
- Decision: defer.
- Reason: first lock the one-transaction process contract before broadening
  local mining policy.

### Candidate C

- Objective: classify remaining v5.4.0 official fixture drift into passing,
  known implementation drift, out-of-scope fork/feature, and implementation
  bug-candidate groups.
- Value: medium; useful consensus map but less directly executable than
  runner-visible devnet block production.
- Risk: low-medium; mostly scripts/docs with possible narrow fixture pins.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority still favors Phase B executable client
  behavior.

## Selected Objective

Implement `DEVNET-RUNNER-DEV-PERIOD-SMOKE`: extend the standalone devnet smoke
gate so a real runner process with a short positive `--dev.period` admits a
public txpool transaction, seals it into a local block, and reports
runner-visible evidence before shutdown.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `src/cli.lisp` only for narrowly fixing a process-boundary bug exposed by
  the smoke gate
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The standalone devnet smoke gate configures a short positive `--dev.period`
  for a bounded process-boundary scenario.
- The smoke gate admits a public raw transaction and waits for the background
  dev-period tick to mine it.
- The JSON report includes mined transaction hash, block number/hash, receipt
  evidence, and post-mining txpool pending/queued counts or equivalent
  visibility proof.
- If the background tick does not mine the transaction before the bounded
  deadline, the smoke gate fails with observed block/txpool state.

Non-goals:

- Do not broaden mining policy beyond the already implemented one-block local
  tick unless the smoke exposes a concrete correctness bug.
- Do not implement P2P mining, consensus duties, payload-building APIs, or
  reference-client fixture widening in this slice.
- Do not add unbounded sleeps or open-ended polling.

## Acceptance Criteria

- `scripts/devnet-smoke-gate.lisp -- --json` proves a `--dev.period`-driven
  local block was sealed by a real long-running devnet process.
- The report contains stable runner-facing fields for the mined transaction,
  block, receipt, and txpool cleanup evidence.
- Existing Engine/public split, txpool journal/rejournal, and connection-count
  report contracts remain intact.
- The test harness fails clearly if the dev-period tick never seals the
  submitted transaction.
- Docs reflect only actual status changes.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation before running standalone devnet or
  Phase A devnet smoke gates. Do not silently skip them.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke test dev period mining`

## Blockers

- No current git synchronization blocker.
- If local socket/network escalation is unavailable, stop with
  `BLOCKED_SOCKET_ESCALATION` and record the exact unrun smoke command.
- If the current dev-period background thread cannot seal from the real
  process boundary without a larger block-production refactor, stop with
  `BLOCKED_DEV_PERIOD_PROCESS_SMOKE` and document the precise missing boundary.

## Implementer Notes

- Reuse existing public txpool transaction fixtures and report-field patterns
  from the current standalone smoke gate.
- Keep the process wait bounded and diagnostic: report observed latest block,
  pending txpool counts, and transaction lookup state on timeout.
- Avoid changing core block construction unless the smoke reveals a real bug.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
