# Next Run

## Run Metadata

- Date: 2026-07-06
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: `main` was clean relative to `origin/main` at orientation time
  after fetching, with only the expected loop lock/automation worktree edits
  during implementation.
- Recent commits reviewed: the latest validated slices finished the bounded
  KZG malformed-object matrix through missing-count and unexpected-key object
  proofs without widening production code.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records the full malformed-object `engine_getPayloadBodiesByRangeV2`
  listener matrix through the unexpected-key request `{"foo":"0x1"}`.
- Relevant loop state: `docs/loop/state.md` now recommends pivoting from
  further malformed-object KZG opt-in coverage to the matching hidden-method
  rejection contract without KZG verifier opt-in.

## Candidate Ranking

### Candidate A

- Objective: prove one live non-KZG engine-only
  `engine_getPayloadBodiesByRangeV2` request is rejected at the listener
  boundary instead of merely being hidden from `engine_exchangeCapabilities`.
- Value: highest; it closes the disabled-path process contract for the same
  method family now that the KZG opt-in malformed-object matrix is covered.
- Risk: low-medium; likely smoke/assertion/report work only unless the live
  non-KZG listener unexpectedly exposes or differently normalizes the method.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused CLI coverage if report assertions change, `git diff --check`,
  verifier review, and the full suite only if production code changes.
- Decision: selected.
- Reason: it locks the negative process contract adjacent to the now-complete
  KZG positive-path proofs while keeping validation cost low.

### Candidate B

- Objective: continue widening malformed-object request-shape coverage beyond
  the now-proven unexpected-key request.
- Value: lower; it keeps grinding the same matrix after the bounded
  unexpected-key proof already closed the obvious stale-assumption gap.
- Risk: medium; it raises maintenance churn without improving the hidden-path
  contract.
- Required validation: same as Candidate A, potentially with more report churn.
- Decision: defer.
- Reason: lower leverage than closing the disabled-path listener contract.

### Candidate C

- Objective: switch to unrelated blob-era or public-RPC runner surface.
- Value: lower than Candidate A because the current
  `engine_getPayloadBodiesByRangeV2` listener line still has one clear
  negative-path proof missing.
- Risk: medium.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the hidden-method contract.

## Selected Objective

Prove one live non-KZG engine-only `engine_getPayloadBodiesByRangeV2` request
is rejected at the process boundary, using the existing engine-only smoke path
without verifier opt-in to lock the disabled-method envelope rather than only
capability omission.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The engine-only non-KZG smoke proves live
  `engine_getPayloadBodiesByRangeV2` is rejected at the listener boundary when
  verifier opt-in is absent, not only omitted from capability advertisement.
- The smoke/report surface records enough disabled-method error evidence to
  debug code/message drift at the process boundary.
- The existing non-KZG capability guard remains intact, and the existing KZG
  opt-in positive-path payload-body probes remain intact on their current
  runner path.

Non-goals:

- Do not add more malformed-object KZG request shapes unless the non-KZG
  negative request uncovers a shared bug.
- Do not revisit already-proven KZG opt-in by-hash/by-range success probes,
  malformed quantity/object envelopes, direct blob/cell retrieval, or payload
  envelope coverage unless the new negative-path request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live disabled-method proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live non-KZG
  `engine_getPayloadBodiesByRangeV2` is rejected with the documented disabled
  method envelope.
- The smoke/assertion surface fails clearly if the live request becomes
  available, returns a different error envelope, or includes a success result.
- The existing non-KZG capability guard and KZG opt-in positive-path payload
  body probes remain green in the same smoke path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report or adjacent core test
  code only.
- Escalate to Tier 2 only if the live hidden-method request uncovers a shared
  production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
- focused CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` if report assertions
  change

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the selected non-KZG hidden-method
  path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected non-KZG request through a different
  disabled-method envelope than expected, stop and record that exact mismatch
  instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range hidden without KZG`

## Blockers

- If the selected non-KZG request proof reveals a real production mismatch
  that needs broader Engine RPC work, stop and write that narrower blocker
  instead of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only smoke path and non-KZG capability guard
  instead of inventing a second listener configuration flow.
- Prefer extending the current report contract over adding a separate smoke
  mode.
- Keep the slice centered on one live non-KZG
  `engine_getPayloadBodiesByRangeV2` disabled-method behavior, not broader
  Amsterdam fixture realism or new malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation.
