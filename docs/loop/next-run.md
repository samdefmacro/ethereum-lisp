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
  live `engine_getPayloadBodiesByHashV2`, single-hit and sparse mixed-hit
  `engine_getPayloadBodiesByRangeV2`, oversized/zero/malformed quantity
  rejection, one-element params-array rejection, scalar non-array
  invalid-request, `params:null` invalid-params, non-empty object invalid-params,
  and now empty-object invalid-params at the engine-only listener boundary.
- Recent commits reviewed: the latest validated slices walked the same runner
  matrix through malformed quantities, one-element params-envelope coverage,
  scalar non-array invalid-request coverage, null-params invalid-params,
  non-empty object invalid-params, and now empty-object invalid-params
  without widening production code.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records the empty-object request proof; the remaining narrow gap on this
  line is a single-key object-valued request that omits `start`.
- Relevant loop state: `docs/loop/state.md` now treats the `{}` request proof
  as closed and recommends one single-key object-valued `params` request such
  as `{"count":"0x1"}` before widening into unrelated blob-era runner work.

## Candidate Ranking

### Candidate A

- Objective: prove one live single-key object-valued
  `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"count":"0x1"}` returns the current missing-start invalid-params
  envelope at the engine-only KZG runner boundary.
- Value: highest; it closes another distinct malformed object shape on the
  same listener path after the empty-object proof landed.
- Risk: low-medium; likely smoke/assertion/report work only unless the live
  listener diverges from the documented in-process contract.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused CLI coverage if report assertions change, `git diff --check`,
  verifier review, and the full suite only if production code changes.
- Decision: selected.
- Reason: it extends the same malformed request-shape matrix with one more
  bounded object form without broadening into unrelated runner surface.

### Candidate B

- Objective: batch multiple additional malformed object shapes on the same
  boundary.
- Value: lower; it risks widening scope after the empty-object proof already
  closed the last explicitly queued gap.
- Risk: medium; it increases validation and review cost without a clear
  priority edge over one more bounded single-key proof.
- Required validation: same as Candidate A, potentially with more report churn.
- Decision: defer.
- Reason: lower leverage than one more bounded object-shape proof.

### Candidate C

- Objective: switch to unrelated blob-era or public-RPC runner surface.
- Value: lower than Candidate A because this listener-bound malformed-request
  line is still one bounded slice away from a cleaner close-out.
- Risk: medium.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the next malformed request-shape proof.

## Selected Objective

Prove one live single-key object-valued
`engine_getPayloadBodiesByRangeV2` `params` request under KZG verifier opt-in,
using the existing engine-only smoke child to send a request such as
`{"count":"0x1"}` and lock the current missing-start invalid-params envelope
at the process boundary.

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
  `engine_getPayloadBodiesByRangeV2` rejects one single-key object-valued
  `params` request with the documented invalid-params envelope, not only
  sparse success responses, malformed quantities, missing-array elements,
  scalar non-array invalid-request, null-params invalid-params, non-empty
  object invalid-params, empty-object invalid-params, oversized counts, or
  zero-valued numeric bounds.
- The nested runner report records enough single-key object request evidence to
  debug error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, null-params invalid-params probe,
  non-empty object invalid-params probe, empty-object invalid-params probe,
  zero-start/zero-count error probes, and oversized-count error probe remain
  intact on the same runner path.

Non-goals:

- Do not batch multiple new malformed object shapes unless the selected
  single-key request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, malformed-start, malformed-count, one-element-array missing-count,
  scalar non-array invalid-request, null-params invalid-params, non-empty
  object invalid-params, empty-object invalid-params, zero-valued
  positive-number rejection, oversized-count rejection, or direct blob/cell-proof
  retrieval unless the new request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live single-key object request proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects the selected single-key object
  request with the documented invalid-params code/message.
- The smoke/assertion surface fails clearly if the live request no longer
  returns the documented validation envelope or if the runner silently returns
  a success result instead of the error.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, null-params invalid-params probe,
  non-empty object invalid-params probe, empty-object invalid-params probe,
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
- focused escalated engine-only smoke for the selected single-key object path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected single-key object failure through a
  different error envelope than the documented in-process path, stop and
  record that exact mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range missing start object params`

## Blockers

- If the selected single-key object request proof reveals a real production
  mismatch that needs broader Engine RPC work, stop and write that narrower
  blocker instead of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, sparse mixed-hit success probe, malformed-start probe,
  malformed-count probe, one-element-array missing-count probe, scalar
  non-array invalid-request probe, null-params invalid-params probe,
  non-empty object invalid-params probe, empty-object invalid-params probe,
  zero-start/zero-count probes, and oversized-count probe instead of
  inventing a second verifier configuration flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on one live single-key object-valued
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism or general malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation.
