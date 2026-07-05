# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: this run is expected to have committed and pushed
  `DEVNET-RUNNER-PREPARED-PAYLOAD-TXPOOL-SELECTION`.
- Current completed slice: Engine prepared payload construction reuses the
  shared deterministic, gas-limited, sender-aware public txpool selection path;
  `engine_getPayloadV1` can return selected txpool-backed transactions while
  selected and non-selected txpool entries remain visible before
  import/forkchoice, and non-empty prepared payload ids include the selected
  transaction root to avoid stale txpool-independent cache reuse.
- Validation from the completed slice: focused Engine RPC coverage passed,
  `git diff --check` passed, the sandbox full-suite attempt failed at the
  expected local socket/devnet smoke boundary, and the escalated full suite
  passed with `890 tests passed, 5 skipped`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The next
  useful gap is proving the txpool-backed prepared-payload path across the real
  standalone devnet Engine/public listener boundary.

## Candidate Ranking

### Candidate A

- Objective: implement
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION`, extending the
  standalone devnet smoke/process-runner path to prove txpool-backed prepared
  payload selection through real authenticated Engine and public RPC listeners.
- Value: high; it moves the new prepared-payload behavior from in-process RPC
  coverage to the Hive-style runner boundary.
- Risk: medium; it touches smoke orchestration and local socket behavior, so
  validation must use escalated local socket/network permissions.
- Required validation: focused standalone smoke command, `git diff --check`,
  full suite once, and independent verifier review.
- Decision: selected.
- Reason: after prepared payloads can include selected txpool transactions
  in-process, the next runner-visible gap is proving the same behavior across
  real process/listener boundaries.

### Candidate B

- Objective: add more in-process prepared-payload edge tests, such as V2/V3
  payload envelopes or no-fitting transaction cases.
- Value: medium; useful coverage, but less runner-visible than the process
  smoke gate.
- Risk: low-medium; mostly in-process tests.
- Required validation: focused Engine RPC coverage and full suite if code
  changes.
- Decision: defer.
- Reason: the process boundary has higher value for Phase B readiness.

### Candidate C

- Objective: classify remaining official v5.4.0 fixture drift.
- Value: medium; useful consensus map, but less directly executable than
  runner-visible Engine/devnet behavior.
- Risk: low-medium.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority still favors Phase B executable client
  behavior.

## Selected Objective

Implement `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION`: prove the
txpool-backed prepared-payload path across the standalone devnet
Engine/public RPC listener boundary, with JSON evidence useful for
Hive/process-runner checks.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/core-tests.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The standalone devnet smoke gate starts a split Engine/public devnet, admits
  pending public txpool transactions, prepares a payload through authenticated
  `engine_forkchoiceUpdated*`, and retrieves it through authenticated
  `engine_getPayload*`.
- The JSON smoke report includes evidence that a selected transaction appears
  in the prepared payload.
- The JSON smoke report includes evidence that selected and non-selected
  txpool entries remain public-visible before import/forkchoice.
- Existing empty-payload, import/forkchoice, readiness, shutdown, and listener
  contract checks remain intact.

Non-goals:

- Do not change txpool selection policy unless the process smoke exposes a
  concrete implementation bug.
- Do not broaden official fixture pins.
- Do not change listener lifecycle, JWT auth, or public/Engine namespace
  separation except where necessary to observe the existing behavior.
- Do not add broad sleeps; prefer existing polling/readiness helpers.

## Acceptance Criteria

- A focused standalone devnet smoke invocation passes with local socket/network
  escalation and reports prepared-payload txpool evidence.
- The process-boundary test verifies `engine_getPayload*` returns at least one
  selected public txpool transaction.
- The process-boundary test verifies selected and non-selected txpool entries
  are still visible in public txpool views before import/forkchoice.
- Existing smoke JSON fields and old all-fixtures behavior remain stable.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Escalated standalone smoke command for the new prepared-payload txpool probe,
  likely `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- Any narrow focused test added for JSON report shape.

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
- Commit message: `Smoke prepared payload txpool selection`

## Blockers

- No current git synchronization blocker.
- If the standalone smoke gate cannot observe txpool-backed prepared payloads
  without changing listener/process ownership semantics, stop with
  `BLOCKED_SMOKE_PREPARED_PAYLOAD_TXPOOL_BOUNDARY` and document the exact
  missing boundary.

## Implementer Notes

- Derive the current task from this file, not from stale heartbeat text.
- Reuse existing smoke helpers for raw transaction submission, Engine payload
  preparation, payload retrieval, public txpool inspection, and JSON evidence.
- Keep selected transactions in txpool until import/forkchoice removes them
  through the existing mined-transaction path.
- Avoid expanding the smoke matrix beyond the prepared-payload txpool contract.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
