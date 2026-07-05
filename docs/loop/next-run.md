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
  placeholder and the later Amsterdam V6 body in the same range, the live
  oversized `count > 1024` error contract, and live zero-start / zero-count
  `-32602` positivity errors.
- Recent commits reviewed: the latest validated slices moved the runner proof
  from by-hash payload-body retrieval into canonical by-range retrieval, then
  into sparse mixed-hit range/null behavior, oversized-count request-boundary
  coverage, and now non-positive request-boundary coverage without widening
  production code.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records sparse mixed-hit plus zero/oversized by-range proof; the roadmap
  now treats broader malformed quantity/params handling as the next bounded
  process boundary gap.
- Relevant loop state: the remaining narrow runner gap on this line is no
  longer sparse range ordering, oversized-count rejection, or positive-number
  validation; it is one broader malformed-request envelope for
  `engine_getPayloadBodiesByRangeV2` request parameters.

## Candidate Ranking

### Candidate A

- Objective: prove live runner-bound
  `engine_getPayloadBodiesByRangeV2` malformed quantity validation,
  especially one bad-hex `start` or `count` request that should fail through
  the existing invalid-params envelope before positivity or size checks.
- Value: highest; it closes the next explicit malformed-request gap on the
  same live KZG opt-in runner path without revisiting already-proven success
  or numeric-boundary cases.
- Risk: low-medium; likely smoke/assertion/report work only unless the runner
  boundary reveals a production mismatch.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused engine-only CLI coverage if report assertions change,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: it is the next narrow contract edge after locking zero/oversized
  numeric bounds and reuses the same seeded V6 range-request path.

### Candidate B

- Objective: prove malformed quantity validation at the same process boundary,
  but batch both bad-hex `start` and bad-hex `count` shapes in one run.
- Value: medium; useful, but broader batching risks scope creep before one
  concrete malformed envelope is locked live.
- Risk: medium; likely still smoke-only, but it increases assertion surface
  and makes failures harder to localize.
- Required validation: likely the same Tier 1 focused smoke/report gates.
- Decision: defer.
- Reason: one malformed quantity proof is the tighter next slice.

### Candidate C

- Objective: widen the current sparse success probe into broader multi-hit
  success ranges or unrelated blob-era runner surface.
- Value: lower than Candidate A because the next missing contract edge is
  still malformed-request validation, not another success-path variant.
- Risk: medium; it risks scope creep and duplicate proof.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the remaining by-range validation edge.

## Selected Objective

Prove one live runner-bound malformed-quantity rejection for
`engine_getPayloadBodiesByRangeV2` under KZG verifier opt-in, using the
existing engine-only smoke child to send a bad-hex `start` or `count` value
and lock the expected invalid-params error contract.

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
  `engine_getPayloadBodiesByRangeV2` rejects one malformed quantity request,
  not only sparse success responses, oversized counts, or zero-valued numeric
  bounds.
- The nested runner report records enough malformed-request evidence to debug
  error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success probe, zero-start/zero-count error
  probes, and oversized-count error probe remain intact on the same runner
  path.

Non-goals:

- Do not batch multiple malformed quantity or params-envelope shapes unless
  the first malformed request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, zero-valued positive-number rejection, oversized-count rejection,
  or direct blob/cell-proof retrieval unless the new request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live malformed-quantity proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects the selected malformed quantity
  request with the expected invalid-params error code/message.
- The smoke/assertion surface fails clearly if the live request no longer
  returns the documented validation envelope or if the runner silently returns
  a success result instead of the error.
- The existing sparse mixed-hit success probe, zero-start/zero-count error
  probes, and oversized-count error probe remain green in the same smoke path.
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
- focused escalated engine-only smoke for the new malformed-quantity path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner already normalizes the malformed quantity through a different
  error envelope than the in-process core path, stop and record that exact
  mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range malformed quantity`

## Blockers

- If the malformed-quantity proof reveals a real production mismatch that
  needs broader Engine RPC work, stop and write that narrower blocker instead
  of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, sparse mixed-hit success probe, zero-start/zero-count
  probes, and oversized-count probe instead of inventing a second verifier
  configuration flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on one live malformed-quantity
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism or general malformed-request batching.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
