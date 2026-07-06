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
  zero-start / zero-count positivity errors, live malformed-start and
  malformed-count invalid-params envelopes, a live one-element-array
  params-envelope invalid-params contract, and now one live scalar non-array
  invalid-request contract.
- Recent commits reviewed: the latest validated slices moved the runner proof
  from by-hash payload-body retrieval into canonical by-range retrieval, sparse
  mixed-hit range/null behavior, oversized-count request-boundary coverage,
  non-positive request-boundary coverage, malformed quantity coverage,
  missing-count params-envelope coverage, and now one broader non-array
  invalid-request proof without widening production code beyond the child
  connection budget.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records one scalar non-array invalid-request proof; the roadmap now treats
  one additional non-array request shape such as `params:null` as the next
  bounded gap on this runner line.
- Relevant loop state: the remaining narrow runner gap on this line is no
  longer success-path range ordering, oversized-count rejection, zero-valued
  positivity rejection, malformed-start quantity validation, malformed-count
  quantity validation, missing-count params-array validation, or one scalar
  non-array invalid-request boundary; it is one additional non-array request
  shape at the same generic invalid-request seam.

## Candidate Ranking

### Candidate A

- Objective: prove one live runner-bound `params:null`
  `engine_getPayloadBodiesByRangeV2` request returns the existing JSON-RPC
  invalid-request `-32600` / `"Invalid Request"` envelope.
- Value: highest; it extends the same generic request-shape coverage with a
  structurally distinct non-array form after the scalar proof is locked.
- Risk: low-medium; likely smoke/assertion/report work only unless the runner
  special-cases JSON null differently from other invalid envelopes.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused engine-only CLI coverage if report assertions change,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: `params:null` is the tightest next representative shape without
  widening into a multi-shape malformed-request batch.

### Candidate B

- Objective: prove one live runner-bound empty-object `params` request returns
  the generic invalid-request envelope.
- Value: medium; it would widen non-array coverage, but it is slightly less
  canonical than `null` immediately after the scalar proof.
- Risk: medium; object handling could tempt broader malformed-shape batching.
- Required validation: likely the same Tier 1 focused smoke/report gates.
- Decision: defer.
- Reason: `null` is the cleaner next representative before object shapes.

### Candidate C

- Objective: widen unrelated blob-era runner surface or revisit already-proven
  by-range request boundaries.
- Value: lower than Candidate A because the remaining gap is still generic
  request-shape coverage, not another success-path or blob-surface variant.
- Risk: medium; it risks duplicate proof and scope creep.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing one more invalid-request shape on the
  same boundary.

## Selected Objective

Prove one live runner-bound `params:null` invalid-request rejection for
`engine_getPayloadBodiesByRangeV2` under KZG verifier opt-in, using the
existing engine-only smoke child to send a JSON null `params` value and lock
the expected generic JSON-RPC invalid-request contract.

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
  `engine_getPayloadBodiesByRangeV2` rejects one `params:null` request with
  the expected generic JSON-RPC invalid-request envelope, not only sparse
  success responses, malformed quantities, missing-array elements, a scalar
  non-array request, oversized counts, or zero-valued numeric bounds.
- The nested runner report records enough `params:null` request evidence to
  debug error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, zero-start/zero-count error probes,
  and oversized-count error probe remain intact on the same runner path.

Non-goals:

- Do not batch multiple new malformed `params` shapes unless the `params:null`
  request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, malformed-start, malformed-count, one-element-array missing-count,
  scalar non-array invalid-request, zero-valued positive-number rejection,
  oversized-count rejection, or direct blob/cell-proof retrieval unless the
  new request regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live `params:null` invalid-request proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects the selected `params:null`
  request with the expected JSON-RPC invalid-request error code/message.
- The smoke/assertion surface fails clearly if the live request no longer
  returns the documented validation envelope or if the runner silently returns
  a success result instead of the error.
- The existing sparse mixed-hit success probe, malformed-start error probe,
  malformed-count error probe, one-element-array missing-count error probe,
  scalar non-array invalid-request probe, zero-start/zero-count error probes,
  and oversized-count error probe remain green in the same smoke path.
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
- focused escalated engine-only smoke for the new `params:null` path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected `params:null` failure through a
  different error envelope than the in-process core path, stop and record that
  exact mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range null params`

## Blockers

- If the selected `params:null` invalid-request proof reveals a real
  production mismatch that needs broader Engine RPC work, stop and write that
  narrower blocker instead of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, sparse mixed-hit success probe, malformed-start probe,
  malformed-count probe, one-element-array missing-count probe, scalar
  non-array invalid-request probe, zero-start/zero-count probes, and
  oversized-count probe instead of inventing a second verifier configuration
  flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on one live `params:null`
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism or general malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation and focused validation.
