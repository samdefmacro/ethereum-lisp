# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: the repo-local KZG verifier path is now proven through live
  `engine_getPayloadV3`, `engine_getPayloadV4`, a non-empty
  `engine_getPayloadV5`, and direct `engine_getBlobsV1` runner boundary
  retrieval; the highest-value remaining gap is cell-proof lookup rather than
  first-generation blob retrieval.
- Recent commits reviewed: the latest validated slice moved the smoke from
  imported non-empty V5 bundle retrieval into direct full-size
  `engine_getBlobsV1` proof with the shared large-response reader hardened.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records direct live `engine_getBlobsV1` retrieval; the roadmap now treats
  `engine_getBlobsV2` / `engine_getBlobsV3` cell-proof proof as the next
  bounded KZG follow-up.
- Relevant loop state: direct versioned-hash blob retrieval is covered at the
  process boundary, but live cell-proof blob lookup is still missing from the
  runner smoke.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke from direct live
  `engine_getBlobsV1` retrieval into direct `engine_getBlobsV2` /
  `engine_getBlobsV3` cell-proof process-boundary proof.
- Value: highest; it closes the next obvious blob-era runner gap after live
  V1 lookup and keeps momentum on the KZG boundary.
- Risk: medium; it stays in runner smoke/assertion code, but it will need a
  seeded cell-proof sidecar shape and larger response assertions.
- Required validation: focused escalated engine-only smoke for the cell-proof
  lookup path, `git diff --check`, and verifier review. Full suite only if the
  helper or listener surface broadens beyond smoke/assertion code.
- Decision: selected.
- Reason: it is the most direct continuation of the completed direct V1 blob
  lookup slice and preserves the current runner-boundary priority.

### Candidate B

- Objective: widen the same runner proof to `engine_getPayloadV6` with
  non-empty blob bundle plus execution requests.
- Value: medium; useful fork-surface depth, but lower leverage than direct
  cell-proof lookup because V1 already proves blob retrieval.
- Risk: medium; it adds another payload-envelope variant without closing the
  direct cell-proof lookup gap.
- Required validation: focused escalated smoke and `git diff --check`;
  broader gates only if shared helpers change.
- Decision: defer.
- Reason: lower leverage than direct `engine_getBlobsV2` / `engine_getBlobsV3`
  lookup.

### Candidate C

- Objective: revisit unrelated Shanghai txpool or replacement runner coverage.
- Value: low for current priority because the blob-era KZG boundary still has
  a narrower missing live path.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on selected slice.
- Decision: defer.
- Reason: loses momentum on the highest-value blob-era runner gap.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from direct live
`engine_getBlobsV1` retrieval to direct `engine_getBlobsV2` /
`engine_getBlobsV3` cell-proof process-boundary proof.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The live verifier opt-in smoke proves direct cell-proof retrieval through
  `engine_getBlobsV2` / `engine_getBlobsV3`, not only V1 blob lookup.
- The seeded runner sidecar carries the full proof-cardinality shape expected
  by the direct cell-proof methods.
- Smoke reporting captures enough direct lookup evidence to debug Cancun
  cell-proof retrieval regressions at the runner boundary.

Non-goals:

- Do not redesign production KZG verification, payload construction, or blob
  sidecar storage.
- Do not widen unrelated V2 Shanghai runner assertions in the same run.
- Do not add broad new fixture families if the existing seeded runner path can
  exercise `engine_getBlobsV2` / `engine_getBlobsV3`.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getBlobsV2` / `engine_getBlobsV3` retrieval with at least one
  returned blob record carrying the expected full cell-proof cardinality.
- The smoke/assertion surface fails clearly when verifier opt-in is absent,
  unavailable, or when the returned proof list is malformed, truncated, or has
  the wrong cardinality.
- Any shared helper change stays scoped to supporting the direct cell-proof
  lookup path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/helper code only.
- Escalate to Tier 3 only if production listener or Engine implementation code
  must change.

Focused gates:

- focused escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  covering direct `engine_getBlobsV2` / `engine_getBlobsV3` retrieval
- any direct CLI regression added for cell-proof response handling

Required pre-commit gates:

- `git diff --check`
- focused escalated smoke gate for the selected blob lookup path
- independent verifier `PASS`
- full suite only if the helper or implementation change is broad enough to
  justify it under `docs/loop/validation.md`

Full-suite policy:

- Not mandatory if the diff remains test-only/shared-helper-only and the
  verifier agrees the focused gate is sufficient.
- Mandatory once before commit if the change reaches shared production code or
  broader listener behavior.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If direct cell-proof lookup still requires a broader helper or fixture than
  the current seeded path can support, stop and record the exact shape or
  response-handling blocker instead of widening scope ad hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke cell-proof runner lookup`

## Blockers

- If the current seeded sidecar cannot exercise `engine_getBlobsV2` /
  `engine_getBlobsV3` without broader fixture plumbing, record the exact
  missing proof-shape boundary and the smallest viable helper change instead
  of widening into unrelated test infrastructure cleanup.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child and its seeded
  database path instead of introducing a second verifier configuration flow.
- Prefer extending the existing seeded blob sidecar into a full cell-proof
  shape over inventing a second unrelated blob fixture.
- Keep the slice centered on direct live cell-proof lookup, not additional
  payload-envelope variants.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
