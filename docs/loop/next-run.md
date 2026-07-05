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
  and live `engine_getPayloadBodiesByHashV2` for the same Amsterdam-era V6
  block.
- Recent commits reviewed: the latest validated slice widened KV import so a
  known block can retain a matching prepared payload, then used that coexistence
  path to prove by-hash Amsterdam payload-body retrieval at the runner
  boundary.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records live by-hash payload-body proof; the roadmap now treats
  `engine_getPayloadBodiesByRangeV2` as the next bounded blob-era follow-up.
- Relevant loop state: blob-era payload envelopes, direct blob/cell-proof
  lookups, and by-hash Amsterdam payload-body retrieval are covered at the
  process boundary; the remaining narrow runner gap is range-based Amsterdam
  payload-body retrieval.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke from live
  `engine_getPayloadBodiesByHashV2` into live
  `engine_getPayloadBodiesByRangeV2`.
- Value: highest; it closes the next obvious Amsterdam payload-body runner gap
  while reusing the just-landed known/prepared coexistence seed.
- Risk: low-medium; likely smoke/assertion/report work plus one more Engine
  request in the nested connection contract.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  `git diff --check`, verifier review, and the full suite only if production
  code changes.
- Decision: selected.
- Reason: it continues the same runner surface with the smallest remaining
  bounded gap.

### Candidate B

- Objective: widen the Amsterdam seed again to exercise a live
  `engine_newPayloadV5` import path with executable blob transactions.
- Value: medium; useful long term, but materially larger than the remaining
  payload-body range proof.
- Risk: high; would require genuine executable blob-transaction fixture shape
  instead of the current bounded synthetic runner seed.
- Required validation: likely Tier 2 or Tier 3 with broader production and
  fixture risk.
- Decision: defer.
- Reason: larger than needed while a narrower runner-boundary proof remains.

### Candidate C

- Objective: return to unrelated txpool or listener slices.
- Value: low for current priority because the blob-era runner line still has a
  clean next step.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the remaining Amsterdam payload-body
  range contract.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from live
`engine_getPayloadBodiesByHashV2` into live
`engine_getPayloadBodiesByRangeV2` process-boundary proof.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The engine-only `kzgOptIn` smoke proves Amsterdam-era
  `engine_getPayloadBodiesByRangeV2`, not only the by-hash variant.
- The nested runner report records enough range-response evidence to debug
  transaction, withdrawal, and `blockAccessList` regressions at the process
  boundary.
- The nested KZG connection/shutdown contract grows only as needed for the new
  range request.

Non-goals:

- Do not revisit the by-hash coexistence production fix unless the range path
- reveals a concrete bug.
- Do not broaden into unrelated blob lookup or payload-envelope variants.
- Do not refactor general payload storage or Engine RPC plumbing outside the
  minimal support needed for the live range proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByRangeV2` retrieval for the imported Amsterdam-era
  V6 block range containing the already-proven by-hash block.
- The smoke/assertion surface fails clearly if the range lookup omits
  `transactions`, omits `withdrawals`, or omits/malforms `blockAccessList`.
- Any code change stays scoped to the live range proof and does not regress the
  landed by-hash proof.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report code only.
- Escalate to Tier 2 only if the range proof uncovers a shared production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the new range path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if any production file such as `src/core.lisp`
  or shared Engine RPC code changes.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the current imported V6 block cannot exercise the range response without a
  broader fixture redesign, stop and record the exact missing range boundary
  rather than widening scope ad hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body range lookup`

## Blockers

- If the range proof requires broader production changes than the current
  by-hash known/prepared coexistence path, stop and write that narrower blocker
  instead of expanding into a larger blob fixture project.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child and seeded V6 known /
  prepared block path instead of inventing a second verifier configuration
  flow.
- Prefer extending the current nested report contract over adding a second
  unrelated smoke mode.
- Keep the slice centered on live `engine_getPayloadBodiesByRangeV2`, not
  broader Amsterdam fixture realism.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
