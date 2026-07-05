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
  live `engine_getPayloadBodiesByHashV2`, and a live single-hit
  `engine_getPayloadBodiesByRangeV2` response for the same Amsterdam-era V6
  block after engine-only forkchoice selection.
- Recent commits reviewed: the latest validated slice exported state
  availability for the seeded V6 block, used live `engine_forkchoiceUpdatedV2`
  to make it canonical inside the KZG-only smoke child, then proved
  `engine_getPayloadBodiesByRangeV2` plus the matching non-KZG capability
  negative guards.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records both by-hash and single-hit by-range payload-body proof; the roadmap
  now treats broader multi-slot range/null behavior as the next bounded
  blob-era follow-up.
- Relevant loop state: blob-era payload envelopes, direct blob/cell-proof
  lookups, and both by-hash and single-hit by-range Amsterdam payload-body
  retrieval are covered at the process boundary; the remaining narrow runner
  gap is mixed-hit range/null behavior for sparse canonical slots.

## Candidate Ranking

### Candidate A

- Objective: prove a mixed-hit live
  `engine_getPayloadBodiesByRangeV2` response where the requested range
  includes one missing earlier canonical slot and the already-proven Amsterdam
  V6 slot.
- Value: highest; it completes the most obvious remaining range-contract
  assertion without leaving the current runner boundary.
- Risk: low-medium; likely smoke/assertion/report work plus one additional
  range query over the same selected V6 head.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  `git diff --check`, focused engine-only CLI coverage if assertions change,
  verifier review, and the full suite only if production code changes.
- Decision: selected.
- Reason: it stays on the same KZG smoke child and extends the new range proof
  into the next concrete contract edge instead of widening scope.

### Candidate B

- Objective: probe oversized or otherwise invalid
  `engine_getPayloadBodiesByRangeV2` request bounds at the runner boundary.
- Value: medium; useful contract hardening, but lower value than proving the
  still-missing mixed-hit null placeholder behavior.
- Risk: low-medium; may stay smoke-only, but it is less central than the live
  sparse-range success shape.
- Required validation: likely Tier 1 with smoke/report assertions only.
- Decision: defer.
- Reason: the success-path null placeholder contract is the more direct gap.

### Candidate C

- Objective: widen the Amsterdam seed into executable blob-transaction import
  or unrelated txpool/listener work.
- Value: low for current priority because the blob-era runner line still has a
  clean smaller next step.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the remaining sparse range-contract
  coverage.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from single-hit live
`engine_getPayloadBodiesByRangeV2` into mixed-hit sparse-range proof with a
missing earlier slot and the Amsterdam V6 body in the same response.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The engine-only `kzgOptIn` smoke proves a mixed-hit Amsterdam-era
  `engine_getPayloadBodiesByRangeV2` response, not only the single-hit range
  lookup.
- The nested runner report records enough sparse-range evidence to debug null
  placeholders, live body ordering, and `blockAccessList` regressions at the
  process boundary.
- The nested KZG connection/shutdown contract grows only as needed for the new
  sparse-range request.

Non-goals:

- Do not revisit the by-hash coexistence production fix unless the sparse
  range path reveals a concrete bug.
- Do not broaden into unrelated blob lookup or payload-envelope variants.
- Do not refactor general payload storage or Engine RPC plumbing outside the
  minimal support needed for the live sparse-range proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` retrieval for a requested range whose
  earlier slot is missing while the later Amsterdam-era V6 slot is present.
- The smoke/assertion surface fails clearly if the sparse range loses the
  leading `null` placeholder, reorders the live body, omits `transactions`,
  omits `withdrawals`, or omits/malforms `blockAccessList` on the V6 hit.
- Any code change stays scoped to the live sparse-range proof and does not
  regress the landed by-hash or single-hit by-range proofs.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report code only.
- Escalate to Tier 2 only if the sparse-range proof uncovers a shared
  production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
- focused CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` if report assertions or
  capability guards change

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the new sparse-range path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as `src/core.lisp`
  or shared Engine RPC code changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the current selected V6 head cannot exercise the sparse-range null
  response without a broader fixture redesign, stop and record the exact range
  hole that is missing rather than widening scope ad hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body sparse range`

## Blockers

- If the sparse-range proof requires broader production changes than the
  current by-hash / single-hit range coexistence path, stop and write that
  narrower blocker instead of expanding into a larger blob fixture project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child, seeded V6 known /
  prepared block path, and live forkchoice-selection step instead of inventing
  a second verifier configuration flow.
- Prefer extending the current nested report contract over adding a second
  unrelated smoke mode.
- Keep the slice centered on live `engine_getPayloadBodiesByRangeV2` sparse
  behavior, not broader Amsterdam fixture realism.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
