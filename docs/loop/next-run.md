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
  `engine_getPayloadV3`, `engine_getPayloadV4`, a non-empty
  `engine_getPayloadV5`, direct `engine_getBlobsV1`, and direct
  `engine_getBlobsV2` / `engine_getBlobsV3` cell-proof runner boundary
  retrieval; the next bounded gap is an Amsterdam-era payload envelope rather
  than another direct lookup variant.
- Recent commits reviewed: the latest validated slice moved the smoke from
  direct V1 blob lookup into full cell-proof `engine_getBlobsV2` /
  `engine_getBlobsV3` retrieval with explicit proof-cardinality assertions.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records live V1/V2/V3 blob lookup proof; the roadmap now treats non-empty
  `engine_getPayloadV6` retrieval as the next bounded blob-era follow-up.
- Relevant loop state: direct versioned-hash blob and cell-proof retrieval are
  covered at the process boundary, but the runner smoke still lacks a non-empty
  Amsterdam-era `engine_getPayloadV6` envelope proof.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke from imported non-empty
  `engine_getPayloadV5` retrieval into imported non-empty
  `engine_getPayloadV6` process-boundary proof.
- Value: highest; it closes the next obvious blob-era runner gap after direct
  V1/V2/V3 lookup and proves the Amsterdam-era execution-request envelope over
  the live listener.
- Risk: medium; it stays in runner smoke/assertion code, but it needs one more
  seeded prepared-payload variant and tighter envelope assertions.
- Required validation: focused escalated engine-only smoke for the V6 payload
  path, `git diff --check`, and verifier review. Full suite only if the helper
  or listener surface broadens beyond smoke/assertion code.
- Decision: selected.
- Reason: it is the highest-leverage continuation of the current KZG runner
  line without widening into unrelated surface area.

### Candidate B

- Objective: widen the same verifier opt-in runner proof to live
  `engine_getPayloadBodiesByHashV2` retrieval for blob-era payload bodies.
- Value: medium; useful listener depth, but lower leverage than a non-empty
  `engine_getPayloadV6` envelope because the direct lookup/report path is
  already strong and V6 still lacks process proof.
- Risk: medium; it adds another response family and likely needs more seeded
  fixture plumbing than the V6 envelope extension.
- Required validation: focused escalated smoke and `git diff --check`;
  broader gates only if shared helpers change.
- Decision: defer.
- Reason: lower leverage than proving the last missing non-empty payload
  envelope variant first.

### Candidate C

- Objective: revisit unrelated Shanghai txpool or replacement runner coverage.
- Value: low for current priority because the blob-era KZG boundary still has a
  narrower missing live path.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on selected slice.
- Decision: defer.
- Reason: loses momentum on the highest-value blob-era runner gap.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from imported non-empty
`engine_getPayloadV5` retrieval to imported non-empty
`engine_getPayloadV6` process-boundary proof.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The live verifier opt-in smoke proves non-empty Amsterdam-era
  `engine_getPayloadV6` retrieval, not only V3/V4 empty bundles plus V5
  bundle-only proof.
- The seeded runner database carries one V6 prepared payload with execution
  requests and a blob bundle through the existing engine-only `kzgOptIn` path.
- Smoke reporting captures enough V6 envelope evidence to debug execution
  request, block access list, and blob-bundle regressions at the runner
  boundary.

Non-goals:

- Do not redesign production KZG verification, payload construction, or blob
  sidecar storage.
- Do not widen unrelated Shanghai runner assertions in the same run.
- Do not broaden into payload-bodies V2 retrieval unless the V6 path proves
  impossible with the existing seeded database shape.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadV6` retrieval for an imported non-empty prepared payload
  carrying both execution requests and a blob bundle.
- The smoke/assertion surface fails clearly when verifier opt-in is absent,
  unavailable, or when the returned V6 envelope omits or malforms the expected
  Amsterdam-era fields.
- Any shared helper change stays scoped to supporting the imported V6 payload
  lookup path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/helper code only.
- Escalate to Tier 3 only if production listener or Engine implementation code
  must change.

Focused gates:

- focused escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  covering imported non-empty `engine_getPayloadV6`
- any direct CLI regression added for the V6 response contract

Required pre-commit gates:

- `git diff --check`
- focused escalated smoke gate for the selected V6 payload path
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
- If imported non-empty `engine_getPayloadV6` still requires broader fixture
  plumbing than the current seeded path can support, stop and record the exact
  missing envelope-shape boundary instead of widening scope ad hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V6 runner payload lookup`

## Blockers

- If the current seeded database cannot exercise imported non-empty
  `engine_getPayloadV6` without broader fixture plumbing, record the exact
  missing envelope-shape boundary and the smallest viable helper change instead
  of widening into unrelated test infrastructure cleanup.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child and temporary database
  path instead of introducing a second verifier configuration flow.
- Prefer extending the existing imported blob sidecar seed into a V6 prepared
  payload over inventing a second unrelated blob fixture family.
- Keep the slice centered on live `engine_getPayloadV6`, not additional direct
  lookup or payload-bodies variants.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
