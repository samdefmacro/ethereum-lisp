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
  `engine_getPayloadBodiesByRangeV2`, and a sparse mixed-hit
  `engine_getPayloadBodiesByRangeV2` response with a leading `null`
  placeholder and the later Amsterdam V6 body in the same range.
- Recent commits reviewed: the latest validated slices moved the runner proof
  from by-hash payload-body retrieval into canonical by-range retrieval and
  then into sparse mixed-hit range/null behavior without widening production
  code.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records sparse mixed-hit by-range proof; the roadmap now treats
  invalid/oversized by-range request handling as the next bounded process
  boundary gap.
- Relevant loop state: the remaining narrow runner gap on this line is no
  longer success-path sparse range ordering; it is boundary enforcement for
  invalid or oversized `engine_getPayloadBodiesByRangeV2` requests.

## Candidate Ranking

### Candidate A

- Objective: prove live runner-bound
  `engine_getPayloadBodiesByRangeV2` oversized-count handling, especially the
  existing `count > 1024` error contract already covered in core tests.
- Value: highest; it promotes an already-defined Engine API limit from
  in-process coverage to the KZG opt-in process boundary without widening
  scope.
- Risk: low-medium; likely smoke/assertion/report work only unless the runner
  boundary reveals a production mismatch.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused engine-only CLI coverage if report assertions change,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: it closes the next obvious range-contract edge while reusing the
  same KZG opt-in subprocess and seeded V6 context.

### Candidate B

- Objective: prove non-positive `start` / `count` validation at the same
  process boundary.
- Value: medium; still useful, but the oversized-count contract is already
  codified in core tests and is a cleaner first promotion target.
- Risk: low-medium; may be smoke-only, but it is less central than the
  explicit 1024-body limit already documented in the Engine API.
- Required validation: likely the same Tier 1 focused smoke/report gates.
- Decision: defer.
- Reason: the oversized-count error is the tighter next slice.

### Candidate C

- Objective: widen the current sparse success probe into broader multi-hit
  success ranges or unrelated blob-era runner surface.
- Value: lower than Candidate A because the next missing contract edge is
  request-bound error handling, not another success-path variant.
- Risk: medium; it risks scope creep and duplicate proof.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than promoting the existing oversized-count contract
  to the runner boundary.

## Selected Objective

Prove live runner-bound `engine_getPayloadBodiesByRangeV2` oversized-count
handling under KZG verifier opt-in, using the existing engine-only smoke child
to request more than 1024 bodies and lock the expected error contract.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The engine-only `kzgOptIn` smoke proves live
  `engine_getPayloadBodiesByRangeV2` oversized-count rejection, not only
  success-path sparse range retrieval.
- The nested runner report records enough oversized-request evidence to debug
  RPC error-code/message regressions at the process boundary.
- The existing sparse mixed-hit success assertions remain intact on the same
  runner path.

Non-goals:

- Do not widen into other by-range validation variants unless the oversized
  request reveals a concrete shared bug.
- Do not revisit already-proven by-hash, single-hit by-range, sparse mixed-hit
  by-range, or direct blob/cell-proof retrieval unless the oversized request
  regresses them.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live oversized-count proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` rejects an oversized `count` request with
  the expected Engine error code/message.
- The smoke/assertion surface fails clearly if the oversized request no longer
  returns the documented error code, the documented 1024-body limit message, or
  if the runner silently returns a success result instead of the error.
- The existing sparse mixed-hit success probe remains green in the same smoke
  path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report code only.
- Escalate to Tier 2 only if the oversized request uncovers a shared
  production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
- focused CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` if report assertions
  change

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the new oversized-count path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as
  `src/engine-rpc.lisp` changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner already normalizes the oversized request through a different
  error envelope than the in-process core test, stop and record that exact
  mismatch instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range limit`

## Blockers

- If the oversized-count proof reveals a real production mismatch that needs
  broader Engine RPC work, stop and write that narrower blocker instead of
  widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, and sparse mixed-hit success probe instead of inventing
  a second verifier configuration flow.
- Prefer extending the current nested report contract over adding a separate
  smoke mode.
- Keep the slice centered on live oversized
  `engine_getPayloadBodiesByRangeV2` behavior, not broader Amsterdam fixture
  realism.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
