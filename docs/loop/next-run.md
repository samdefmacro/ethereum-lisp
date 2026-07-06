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
  placeholder, live oversized/zero/malformed quantity rejection, a one-element
  params-array invalid-params contract, a scalar non-array invalid-request
  contract, and now a distinct `params:null` invalid-params contract.
- Recent commits reviewed: the latest validated slices moved the runner proof
  through canonical by-range retrieval, sparse mixed-hit range/null behavior,
  oversized-count request-boundary coverage, non-positive request-boundary
  coverage, malformed quantity coverage, missing-count params-envelope
  coverage, scalar non-array invalid-request coverage, and now a null-params
  invalid-params proof without widening production code.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records both scalar non-array invalid-request and `params:null`
  invalid-params proofs; the remaining narrow gap on this line is one
  object-valued non-array request shape at the same runner boundary.
- Relevant loop state: in-process `engine-rpc-handle-get-payload-bodies-by-range`
  currently normalizes a non-empty object-valued `params` request such as
  `{"start":"0x1","count":"0x1"}` into the invalid-params
  `-32602` / `"start must be a non-negative quantity"` envelope.

## Candidate Ranking

### Candidate A

- Objective: prove one live runner-bound non-empty object-valued
  `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"start":"0x1","count":"0x1"}` returns the existing invalid-params
  `-32602` / `"start must be a non-negative quantity"` envelope.
- Value: highest; it extends the same malformed request-shape matrix with a
  distinct non-array object form after the scalar and null proofs are locked.
- Risk: low-medium; likely smoke/assertion/report work only unless the live
  listener diverges from the in-process contract.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused engine-only CLI coverage if report assertions change,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: it is the next bounded malformed shape that still exercises the same
  process boundary without broadening into unrelated blob-era surface.

### Candidate B

- Objective: revisit already-proven malformed quantity or scalar/null request
  shapes on the same runner path.
- Value: lower; it would duplicate current proof instead of extending the
  request-shape matrix.
- Risk: low.
- Required validation: same as Candidate A.
- Decision: defer.
- Reason: lower leverage than one new object-valued request shape.

### Candidate C

- Objective: widen unrelated blob-era runner surface or broader Engine RPC
  malformed-request batching.
- Value: lower than Candidate A because the remaining narrow gap is still one
  object-valued request-shape proof at the same boundary.
- Risk: medium; it risks scope creep and unnecessary validation cost.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the next malformed request-shape proof.

## Selected Objective

Prove one live runner-bound non-empty object-valued
`engine_getPayloadBodiesByRangeV2` `params` request under KZG verifier opt-in,
using the existing engine-only smoke child to send a JSON object like
`{"start":"0x1","count":"0x1"}` and lock the current invalid-params
`-32602` / `"start must be a non-negative quantity"` contract at the process
boundary.

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
  `engine_getPayloadBodiesByRangeV2` rejects one object-valued `params`
  request with the expected invalid-params envelope, not only sparse success
  responses, malformed quantities, missing-array elements, a scalar non-array
  invalid-request, a null-params invalid-params request, oversized counts, or
  zero-valued numeric bounds.
- The nested runner report records enough object-valued request evidence to
  debug error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, null-params invalid-params probe,
  zero-start/zero-count error probes, and oversized-count error probe remain
  intact on the same runner path.

Non-goals:

- Do not batch multiple new malformed object shapes unless the selected object
  request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, malformed-start, malformed-count, one-element-array missing-count,
  scalar non-array invalid-request, null-params invalid-params, zero-valued
  positive-number rejection, oversized-count rejection, or direct blob/cell-
  proof retrieval unless the new request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live object-valued request proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects the selected object-valued
  request with the expected invalid-params error code/message.
- The smoke/assertion surface fails clearly if the live request no longer
  returns the documented validation envelope or if the runner silently returns
  a success result instead of the error.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, null-params invalid-params probe,
  zero-start/zero-count error probes, and oversized-count error probe remain
  green in the same smoke path.
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
- focused escalated engine-only smoke for the new object-valued path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected object-valued failure through a
  different error envelope than the in-process core path, stop and record that
  exact mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range object params`

## Blockers

- If the selected object-valued request proof reveals a real production
  mismatch that needs broader Engine RPC work, stop and write that narrower
  blocker instead of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, sparse mixed-hit success probe, malformed-start probe,
  malformed-count probe, one-element-array missing-count probe, scalar
  non-array invalid-request probe, null-params invalid-params probe,
  zero-start/zero-count probes, and oversized-count probe instead of
  inventing a second verifier configuration flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on one live object-valued
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism or general malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation and focused validation.
