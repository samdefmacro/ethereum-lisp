# Next Run

## Run Metadata

- Date: 2026-07-06
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: the repo-local KZG verifier path is now proven through live
  `engine_getPayloadV3`, `engine_getPayloadV4`, non-empty
  `engine_getPayloadV5`, non-empty `engine_getPayloadV6`, direct
  `engine_getBlobsV1`, direct `engine_getBlobsV2` / `engine_getBlobsV3`,
  live `engine_getPayloadBodiesByHashV2`, single-hit
  `engine_getPayloadBodiesByRangeV2`, a sparse mixed-hit
  `engine_getPayloadBodiesByRangeV2` response with a leading `null`
  placeholder, the live oversized `count > 1024` error contract, live
  zero-start / zero-count positivity errors, and now live malformed-start and
  malformed-count invalid-params envelopes.
- Recent commits reviewed: the latest validated slices moved the runner proof
  from by-hash payload-body retrieval into canonical by-range retrieval, sparse
  mixed-hit range/null behavior, oversized-count request-boundary coverage,
  non-positive request-boundary coverage, malformed-start quantity coverage,
  and now malformed-count quantity coverage without widening production code
  beyond the child connection budget.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records malformed-count by-range proof; the roadmap now treats one broader
  params-envelope contract as the next bounded gap.
- Relevant loop state: the remaining narrow runner gap on this line is no
  longer success-path range ordering, oversized-count rejection, zero-valued
  positivity rejection, malformed-start quantity validation, or malformed-count
  quantity validation; it is one broader params-envelope request boundary.

## Candidate Ranking

### Candidate A

- Objective: prove one live runner-bound
  `engine_getPayloadBodiesByRangeV2` params-envelope rejection for a non-array
  or otherwise structurally invalid `params` value.
- Value: highest; it closes the next remaining request-shape gap on the same
  live KZG opt-in runner path after quantity-field and positivity boundaries
  are locked.
- Risk: low-medium; likely smoke/assertion/report work only unless the runner
  boundary reveals a production mismatch in JSON-RPC parameter validation.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused engine-only CLI coverage if report assertions change,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: one concrete params-envelope failure is the tightest remaining
  request-boundary slice on this runner surface.

### Candidate B

- Objective: widen the same live probe into multiple params-envelope failures
  such as wrong param count plus malformed scalar/array shapes in one batch.
- Value: medium; it could increase coverage, but it risks widening the report
  contract before one representative envelope failure is locked.
- Risk: medium; broader batching makes failures harder to localize and may
  force production-code work if envelopes diverge.
- Required validation: likely the same Tier 1 focused smoke/report gates.
- Decision: defer.
- Reason: one representative params-envelope failure keeps the slice bounded.

### Candidate C

- Objective: widen unrelated blob-era runner surface or revisit already-proven
  by-range quantity cases.
- Value: lower than Candidate A because the remaining gap is request-envelope
  validation, not another quantity or success-path variant.
- Risk: medium; it risks duplicate proof and scope creep.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the remaining by-range request
  boundary.

## Selected Objective

Prove one live runner-bound params-envelope rejection for
`engine_getPayloadBodiesByRangeV2` under KZG verifier opt-in, using the
existing engine-only smoke child to send one structurally invalid `params`
shape and lock the expected invalid-params contract.

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

- The engine-only `kzgOptIn` smoke proves live
  `engine_getPayloadBodiesByRangeV2` rejects one broader params-envelope
  request shape, not only sparse success responses, malformed quantities,
  oversized counts, or zero-valued numeric bounds.
- The nested runner report records enough params-envelope evidence to debug
  error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, zero-start/zero-count error probes, and
  oversized-count error probe remain intact on the same runner path.

Non-goals:

- Do not batch multiple params-envelope shapes unless the first representative
  request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, malformed-start, malformed-count, zero-valued positive-number
  rejection, oversized-count rejection, or direct blob/cell-proof retrieval
  unless the new request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live params-envelope proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects the selected params-envelope
  request with the expected invalid-params error code/message.
- The smoke/assertion surface fails clearly if the live request no longer
  returns the documented validation envelope or if the runner silently returns
  a success result instead of the error.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, zero-start/zero-count error probes, and
  oversized-count error probe remain green in the same smoke path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report or adjacent core test
  code only.
- Escalate to Tier 2 only if the live malformed request uncovers a shared
  production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
- focused CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` if report assertions
  change
- focused core coverage only if a new in-process malformed-request regression
  test is added

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the new params-envelope path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected params-envelope failure through a
  different error envelope than the in-process core path, stop and record that
  exact mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range params envelope`

## Blockers

- If the selected params-envelope proof reveals a real production mismatch that
  needs broader Engine RPC work, stop and write that narrower blocker instead
  of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, sparse mixed-hit success probe, malformed-start probe,
  malformed-count probe, zero-start/zero-count probes, and oversized-count
  probe instead of inventing a second verifier configuration flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on one live params-envelope
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism or general malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation and focused validation.
