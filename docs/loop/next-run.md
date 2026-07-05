# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: this run is expected to start after
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION` has been committed
  and pushed to `origin/main`.
- Current completed slice: the standalone devnet smoke gate proves
  txpool-backed prepared-payload selection across the real authenticated
  Engine/public listener boundary. It admits public txpool transactions,
  prepares a second payload through authenticated `engine_forkchoiceUpdatedV2`,
  retrieves it through authenticated `engine_getPayloadV2`, reports selected
  raw transaction/hash evidence, and confirms selected plus non-selected
  txpool entries remain public-visible before import/forkchoice.
- Validation from the completed slice: focused escalated standalone smoke
  passed, `git diff --check` passed, escalated full suite passed with
  `890 tests passed, 5 skipped`, and independent verifier review passed after
  the CLI tests locked the new JSON evidence fields.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The next
  useful gap is importing and forkchoice-updating the txpool-backed prepared
  payload across the same standalone listener boundary, then proving canonical
  public visibility and txpool cleanup.

## Candidate Ranking

### Candidate A

- Objective: implement
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-IMPORT`, extending the
  standalone devnet smoke/process-runner path from prepared-payload selection
  to import/forkchoice of that txpool-backed prepared payload.
- Value: high; it closes the next runner-visible gap between payload
  preparation and canonical public RPC behavior.
- Risk: medium; it touches smoke sequencing, Engine import/forkchoice
  ordering, and public txpool visibility after import.
- Required validation: focused standalone smoke command, `git diff --check`,
  full suite once, and independent verifier review.
- Decision: selected.
- Reason: after the runner can observe txpool-backed prepared payload
  selection, the next executable-client behavior is proving that importing the
  prepared payload advances canonical public transaction/receipt visibility and
  removes the selected transaction from txpool views.

### Candidate B

- Objective: add in-process prepared-payload edge coverage for V2/V3 payload
  envelopes or no-fitting transaction cases.
- Value: medium; useful coverage, but less runner-visible than the import
  boundary.
- Risk: low-medium; mostly in-process tests.
- Required validation: focused Engine RPC coverage and full suite if code
  changes.
- Decision: defer.
- Reason: the process boundary remains the more valuable Phase B readiness
  path.

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

Implement `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-IMPORT`: import and
forkchoice the txpool-backed prepared payload across the standalone devnet
Engine/public RPC listener boundary, then prove canonical public transaction
and receipt visibility plus txpool cleanup.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `tests/core-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The standalone devnet smoke gate reuses the txpool-backed prepared payload
  produced after public txpool admission.
- The smoke gate imports that prepared payload through authenticated Engine RPC
  and follows it with authenticated forkchoice.
- The JSON smoke report includes evidence that the selected transaction becomes
  canonical through public transaction, receipt, block, and raw transaction RPC
  views.
- The JSON smoke report includes evidence that the selected transaction is
  removed from public txpool views after import while non-selected basefee and
  nonce-gapped queued transactions remain queued.
- Existing empty prepared payload, selection-only evidence, readiness,
  shutdown, and listener contract checks remain intact.

Non-goals:

- Do not change the txpool selection policy unless import exposes a concrete
  implementation bug.
- Do not broaden official fixture pins.
- Do not change listener lifecycle, JWT auth, or public/Engine namespace
  separation except where necessary to observe import/forkchoice behavior.
- Do not add broad sleeps; prefer existing polling/readiness helpers.

## Acceptance Criteria

- A focused standalone devnet smoke invocation passes with local socket/network
  escalation and reports txpool-backed prepared-payload import evidence.
- The process-boundary test verifies `engine_newPayload*` and
  `engine_forkchoiceUpdated*` accept the txpool-backed prepared payload.
- The process-boundary test verifies public canonical transaction and receipt
  lookups expose the selected transaction after import/forkchoice.
- The process-boundary test verifies the selected transaction is absent from
  public txpool views after import and non-selected queued entries remain
  visible.
- Existing smoke JSON fields and all-fixtures behavior remain stable.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Escalated standalone smoke command for the new import/forkchoice probe:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
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
- Commit message: `Smoke prepared payload txpool import`

## Blockers

- No current git synchronization blocker.
- If importing the txpool-backed prepared payload requires behavior that the
  current Engine RPC implementation cannot expose across the listener boundary,
  stop with `BLOCKED_SMOKE_PREPARED_PAYLOAD_TXPOOL_IMPORT` and document the
  exact missing boundary.

## Implementer Notes

- Derive the current task from this file, not from stale heartbeat text.
- Reuse existing smoke helpers for raw transaction submission, Engine payload
  preparation, payload retrieval, payload import, forkchoice, public canonical
  transaction/receipt reads, and public txpool inspection.
- Keep non-selected queued/basefee transactions in txpool after the selected
  transaction is imported.
- Avoid expanding the smoke matrix beyond the prepared-payload txpool import
  contract.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
