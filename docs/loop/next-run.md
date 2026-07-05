# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: Codex
- Implementer model: recommended default implementer model
- Verifier model: different model from implementer when available
- Target branch: `main`
- Stop state: pending implementer; the loop driver should consume this run
  contract immediately instead of generating another run spec.

## Orientation Summary

- Git state: `main` was aligned with `origin/main` at orientation. The current
  implementation batch is expected to commit `Refresh devnet txpool journals
  periodically` before this contract is consumed.
- Recent commits reviewed:
  - `7f79d65 Persist devnet txpool journal records`
  - `df4afd2 Expire stale txpool queued transactions`
  - `ced7535 Close autonomous loop handoff gap`
  - `80e347b Enforce txpool slot admission limits`
  - `d8b0d07 Add autonomous development loop docs`
  - `70158f2 Honor txpool local exemptions`
  - `987e4ed Enforce txpool queue limit admission`
  - `d430af9 Enforce txpool price bump admission`
- Relevant task/roadmap anchors:
  - `DEVNET-RUNNER-TXPOOL-REJOURNAL` is closed by the current batch.
  - `DEVNET-RUNNER-TXPOOL-REJOURNAL-SMOKE` is the next unchecked Phase B
    runner-readiness task.
  - Roadmap Section 7 still lists process-boundary rejournal smoke coverage and
    broader txpool eviction policy as partial gaps.
  - Real KZG integration remains valuable but externally constrained by trusted
    backend/library selection.
- Relevant loop state:
  - Loop v2 requires pending implementer contracts to be consumed directly.
  - This next run should validate the actual process boundary for the
    rejournal background path rather than reworking the deterministic helper
    tests from the current batch.

## Candidate Ranking

### Candidate A

- Objective: Lock `--txpool.rejournal` in the standalone devnet smoke gate by
  proving a real runner process refreshes the txpool journal before shutdown.
- Value: High. It validates the process-boundary behavior that unit-level tick
  tests cannot fully cover.
- Risk: Medium. It needs local listener/socket execution and must avoid flaky
  timing by polling a bounded journal condition.
- Required validation:
  - focused smoke-gate run with local socket/network escalation;
  - `git diff --check`;
  - `sbcl --script tests/run-tests.lisp` once before commit;
  - independent verifier review.
- Decision: Selected.
- Reason: It is the most direct Phase B continuation after adding periodic
  rejournaling, and it closes the main residual risk of that implementation.

### Candidate B

- Objective: Implement broader txpool eviction policy beyond lifetime and
  journaling.
- Value: Medium to high.
- Risk: Medium. It likely touches admission, visibility, and mining behavior.
- Required validation:
  - focused txpool admission/visibility tests;
  - `git diff --check`;
  - `sbcl --script tests/run-tests.lisp`;
  - devnet smoke escalation if public RPC behavior is exercised.
- Decision: Deferred.
- Reason: The process smoke is smaller, directly tied to the just-completed
  implementation, and reduces a concrete verification gap.

### Candidate C

- Objective: Classify remaining official v5.4.0 fixture drift.
- Value: Medium.
- Risk: Low to medium.
- Required validation:
  - bounded fixture drift scripts and documentation updates.
- Decision: Deferred.
- Reason: Executable devnet/process behavior remains the strategic priority.

## Selected Objective

Add a deterministic, bounded devnet smoke-gate check proving
`--txpool.rejournal` refreshes an active `--txpool.journal` file in a real
runner process before shutdown.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp` if a reusable test helper needs to be exposed or
  tightened
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Start the runner-facing devnet process with `--txpool.journal` and a short
  positive `--txpool.rejournal` value in the relevant smoke path.
- Admit a public txpool transaction after the process is ready.
- Poll the txpool-only journal file until the admitted transaction appears, or
  fail with a clear diagnostic before clean shutdown.
- Preserve existing smoke-gate checks and cleanup behavior.

Non-goals:

- Do not change txpool admission, replacement, lifetime, local, slot, queue, or
  journal import semantics.
- Do not add wall-clock-only unit tests when a bounded smoke poll can assert the
  real process behavior.
- Do not widen official fixtures or start real KZG integration.

## Acceptance Criteria

- The smoke gate proves a live runner process writes a refreshed txpool journal
  before clean shutdown when `--txpool.rejournal` is enabled.
- The failure message is specific when the journal never appears, remains
  unreadable, or lacks the expected txpool record.
- Existing devnet smoke checks still run and report their prior status shape.
- `docs/tasks.md`, `docs/roadmap.md`, and `docs/loop/state.md` reflect only
  actual status changes.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Run the focused standalone devnet smoke path with local socket/network
  escalation:
  `sbcl --script scripts/devnet-smoke-gate.lisp`.

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation before running the standalone devnet
  smoke gate or any test that binds local listeners. Do not silently skip the
  gate.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke test devnet txpool rejournaling`

## Blockers

- No current git synchronization blocker.
- If local socket/network escalation is unavailable, stop with
  `BLOCKED_SOCKET_ESCALATION` and record the exact unrun command.
- Real KZG integration remains blocked on concrete trusted-backend selection,
  but it does not block this smoke slice.

## Implementer Notes

- Prefer reusing existing smoke-gate JSON-RPC helpers and KV txpool record
  readers instead of adding parallel parsing code.
- Use a short rejournal duration and bounded polling loop. Keep the timeout
  explicit in failure messages.
- Make cleanup robust even when the smoke assertion fails.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: socket-gated process timing must remain bounded and
  diagnosable.
