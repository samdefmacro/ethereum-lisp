# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: Codex
- Implementer model: recommended default implementer model
- Verifier model: different model from implementer when available
- Target branch: `main`
- Stop state: pending implementer; the loop driver should consume this run
  contract immediately instead of waiting for another automation edge.

## Orientation Summary

- Git state: `main` was aligned with `origin/main` at orientation; the
  preceding implementation batch is expected to commit
  `Persist devnet txpool journal records` before this contract is consumed.
- Recent commits reviewed:
  - `df4afd2 Expire stale txpool queued transactions`
  - `ced7535 Close autonomous loop handoff gap`
  - `80e347b Enforce txpool slot admission limits`
  - `d8b0d07 Add autonomous development loop docs`
  - `70158f2 Honor txpool local exemptions`
  - `987e4ed Enforce txpool queue limit admission`
  - `d430af9 Enforce txpool price bump admission`
  - `db1bcbb Enforce txpool price limit admission`
- Relevant task/roadmap anchors:
  - `DEVNET-RUNNER-TXPOOL-JOURNAL` is closed by the preceding batch.
  - `DEVNET-RUNNER-TXPOOL-REJOURNAL` is the next unchecked Phase B txpool
    runner-readiness task.
  - Roadmap Section 7 still lists periodic rejournaling and broader eviction
    policy as a partial gap.
  - Real KZG integration remains valuable but externally constrained by trusted
    backend/library selection.
- Relevant loop state:
  - Loop v2 requires this pending implementer task to be consumed directly.
  - Do not regenerate another run spec before implementation unless orientation
    finds a precise blocker.

## Candidate Ranking

### Candidate A

- Objective: Make `--txpool.rejournal DURATION` periodically refresh the
  configured `--txpool.journal` file during long-lived devnet serve mode.
- Value: High. It completes the geth/Hive txpool journal flag pair and improves
  runner realism for processes that stay alive after transactions enter the
  public txpool.
- Risk: Medium. Timer/background behavior can introduce nondeterminism unless
  tests use a controllable scheduler or direct tick path.
- Required validation:
  - focused CLI/serve-mode or scheduler coverage while iterating;
  - `git diff --check`;
  - `sbcl --script tests/run-tests.lisp` once before commit;
  - request local socket/network escalation for any devnet process smoke gate.
- Decision: Selected.
- Reason: It is the most direct executable Phase B continuation after journal
  import/export, and it turns an existing geth-shaped no-op into observable
  process behavior.

### Candidate B

- Objective: Move to another Phase B listener/readiness/process-runner
  lifecycle gap.
- Value: High.
- Risk: Medium.
- Required validation:
  - focused process/CLI coverage;
  - `git diff --check`;
  - `sbcl --script tests/run-tests.lisp`;
  - escalated socket smoke gate when listener behavior changes.
- Decision: Deferred.
- Reason: Rejournaling is smaller, already scaffolded by the journal slice,
  and directly improves txpool process-runner fidelity.

### Candidate C

- Objective: Classify remaining official v5.4.0 fixture drift.
- Value: Medium.
- Risk: Low to medium.
- Required validation:
  - bounded fixture drift scripts and documentation updates.
- Decision: Deferred.
- Reason: Executable devnet/process behavior remains the strategic priority.

## Selected Objective

Implement deterministic `--txpool.rejournal DURATION` behavior for devnet
serve mode so an active txpool journal is refreshed during long-running
processes without relying on shutdown alone.

## Scope

Allowed files/modules:

- `src/cli.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Parse and retain `--txpool.rejournal DURATION` as a meaningful non-negative
  duration option rather than only consuming it as a compatibility value.
- Import geth TOML `[Eth.TxPool] Rejournal` through the existing config-file
  path, with explicit CLI flags preserving precedence.
- Report the effective value in devnet summaries, readiness JSON, and
  lifecycle telemetry.
- When both `--txpool.journal` and a positive rejournal duration are set for
  serve mode, refresh the txpool-only journal through the same KV export path
  used by clean shutdown.
- Keep no-journal and zero-duration behavior unchanged.
- Prefer deterministic tests through an injectable scheduler/tick helper or
  direct exported refresh function; avoid wall-clock sleeps in unit tests.

Non-goals:

- Do not change txpool admission, replacement, lifetime, local, slot, queue, or
  journal import semantics.
- Do not implement broader txpool eviction policy.
- Do not widen official fixtures or start real KZG integration.

## Acceptance Criteria

- CLI `--txpool.rejournal DURATION` and geth TOML `[Eth.TxPool] Rejournal`
  parsing are covered.
- Summary JSON exposes the effective rejournal duration when configured.
- A focused deterministic test proves a configured journal can be refreshed
  while the node is live, without waiting for shutdown.
- A focused test proves no journal file is written by rejournal behavior when
  `--txpool.journal` is absent.
- Existing `--txpool.journal` import/export tests still pass.
- `docs/tasks.md`, `docs/roadmap.md`, and `docs/loop/state.md` reflect only
  actual status changes.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Run direct CLI tests for rejournal parsing/reporting and deterministic live
  refresh behavior.
- Rerun the existing txpool journal focused tests touched by the implementation.

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation for any devnet process smoke gate or
  test that binds local listeners.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Refresh devnet txpool journals periodically`

## Blockers

- No current git synchronization blocker.
- Real KZG integration remains blocked on concrete trusted-backend selection,
  but it does not block this txpool rejournal slice.

## Implementer Notes

- Reuse the existing txpool-only KV export helper from the journal slice.
- Keep timer behavior explicit and testable. If existing serve-mode structure
  lacks a clean deterministic hook, add the smallest local hook needed rather
  than sleeping in tests.
- If orientation finds that serve-mode has no safe place for a periodic tick,
  write a precise blocker and do not fake coverage with shutdown-only behavior.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: timer behavior must stay deterministic in tests.
