# Next Run

## Run Metadata

- Date: 2026-07-04
- Orchestrator model: Codex
- Implementer model: pending assignment
- Verifier model: pending assignment, should differ from implementer when
  possible
- Target branch: `main`
- Stop state: `BLOCKED_VALIDATION` until the required devnet/socket gate can
  run

## Orientation Summary

- Git state: `main` is aligned with `origin/main`, with existing uncommitted
  txpool slot-limit implementation changes plus this loop migration.
- Recent commits reviewed:
  - `70158f2 Honor txpool local exemptions`
  - `987e4ed Enforce txpool queue limit admission`
  - `d430af9 Enforce txpool price bump admission`
  - `db1bcbb Enforce txpool price limit admission`
  - `5bf1423 Enforce unprotected RPC transaction flag`
  - `fc9aea4 Import miner gas limit from geth config`
  - `c5a04f2 Honor disabled HTTP host in geth config`
  - `5c63dd3 Parse geth config for devnet runners`
  - `9ef6a7b Accept geth chain preset runner flags`
  - `b296db7 Accept geth config flag in devnet CLI`
  - `bc38e99 Use Hive KZG aliases in devnet smoke`
  - `b4cd063 Cover KZG verifier Hive aliases`
- Relevant task/roadmap anchors:
  - Phase B devnet/process-runner readiness remains the preferred strategic
    path.
  - Txpool correctness affecting public RPC admission is also high value.
  - `DEVNET-RUNNER-TXPOOL-SLOT-LIMITS` is implemented in the dirty tree but
    not committed.
- Relevant loop state:
  - `docs/loop/state.md` records the dirty txpool slice and the validation
    blocker.

## Candidate Ranking

### Candidate A

- Objective: Resolve validation and review for the existing txpool
  account/global slot-limit slice.
- Value: High.
- Risk: Low implementation risk, medium environment risk because a socket-gated
  smoke gate requires escalation.
- Required validation:
  - `git diff --check`
  - `sbcl --script tests/run-tests.lisp` status already known from the latest
    run, with only the socket-gated path blocking
  - `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` with
    local socket/network escalation
  - independent verifier review before commit
- Decision: Selected.
- Reason: The code is already implemented and directly advances public txpool
  admission behavior. Stacking another feature on top of an uncommitted,
  validation-blocked slice would increase integration risk.

### Candidate B

- Objective: Start another Phase B devnet/process-runner slice.
- Value: High.
- Risk: High while current txpool changes remain dirty and unverified.
- Required validation: full suite plus devnet/socket smoke gate depending on
  scope.
- Decision: Deferred.
- Reason: It would compound the current dirty work before closing the existing
  validation loop.

### Candidate C

- Objective: Official v5.4.0 fixture drift classification.
- Value: Medium.
- Risk: Low to medium.
- Required validation: classifier/probe output and possibly pinned smoke gate.
- Decision: Deferred.
- Reason: Useful, but lower value than closing the already-implemented Phase B
  txpool behavior slice.

## Selected Objective

Complete the validation loop for the dirty txpool account/global slot-limit
slice. If the required escalated gate is unavailable, do not edit more
implementation code and do not commit the dirty slice.

## Scope

Allowed files/modules:

- Existing dirty txpool slot-limit files only if a verifier or gate finds a
  concrete bug:
  - `src/core.lisp`
  - `src/public-rpc.lisp`
  - `src/cli.lisp`
  - `tests/core-tests.lisp`
  - `tests/cli-tests.lisp`
  - `docs/tasks.md`
  - `docs/roadmap.md`
- Loop files under `docs/loop/` for status updates.

Expected behavior changes:

- No new behavior should be added beyond the existing txpool slot-limit slice.
- The next run should either validate and commit it, or preserve the
  validation blocker.

Non-goals:

- Do not widen fixtures.
- Do not start another devnet runner feature.
- Do not refactor unrelated txpool or RPC code.
- Do not commit without deterministic validation and verifier approval.

## Acceptance Criteria

- The required devnet/socket smoke gate runs with escalation and passes, or the
  run is reported as `BLOCKED_VALIDATION`.
- `git diff --check` passes after any additional edits.
- If any code fix is made, the full suite policy in `docs/loop/validation.md`
  is followed.
- A verifier reviews the diff against this run specification.
- On success, the txpool slice is committed and pushed.
- On blocker, `docs/loop/state.md` remains accurate and no unrelated work is
  added.

## Validation Plan

Focused gates:

- `git diff --check`
- `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet`

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp` if code changes after the last full
  suite run
- independent verifier `PASS`

Escalation requirements:

- The devnet/socket smoke gate requires local socket/network escalation.

## Commit And Push Policy

- Commit allowed: only after deterministic gates and verifier review pass.
- Push allowed: yes, if commit succeeds and remote authentication is available.
- Commit message: `Enforce txpool slot admission limits`

## Blockers

- The previous escalation request for the devnet/socket smoke gate was rejected
  by the environment due to a usage-limit blocker.

## Implementer Notes

- Treat the current txpool code as implemented but unvalidated.
- Do not interpret the full-suite socket-gated failure as a code failure unless
  the escalated devnet smoke gate also fails with a behavior-specific error.
- Do not touch unrelated dirty work.

## Verifier Result

- Status: pending.
- Findings: pending.
- Residual risk: pending.

