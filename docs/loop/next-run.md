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
  `engine_getBlobsV1`, and direct `engine_getBlobsV2` / `engine_getBlobsV3`
  cell-proof runner-boundary retrieval; the next bounded gap is payload-body
  retrieval rather than another payload-envelope variant.
- Recent commits reviewed: the latest validated slice seeded an Amsterdam-era
  V6 prepared payload into the existing `kzgOptIn` database path and tightened
  the focused smoke/report assertions around live `engine_getPayloadV6`.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records live V6 envelope proof; the roadmap now treats
  `engine_getPayloadBodiesByHashV2` retrieval as the next bounded blob-era
  follow-up.
- Relevant loop state: blob-era payload envelopes and direct blob/cell-proof
  lookups are covered at the process boundary, but the runner smoke still
  lacks a live Amsterdam-era payload-body response proof.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke from imported non-empty
  `engine_getPayloadV6` retrieval into live
  `engine_getPayloadBodiesByHashV2` process-boundary proof.
- Value: highest; it closes the next obvious blob-era runner gap after V6
  envelope proof and exercises the Amsterdam payload-body/block-access-list
  response family over the live listener.
- Risk: medium; it should stay in runner smoke/assertion code, but it may need
  one more seeded-hash/report helper if the current `kzgOptIn` contract does
  not already expose the imported block hash needed for the lookup.
- Required validation: focused escalated engine-only smoke for the V2
  payload-body path, `git diff --check`, and verifier review. Full suite only
  if the helper or listener surface broadens beyond smoke/assertion code.
- Decision: selected.
- Reason: it is the highest-leverage continuation of the current KZG runner
  line without widening into unrelated surface area.

### Candidate B

- Objective: widen the same verifier opt-in runner proof to live
  `engine_getPayloadBodiesByRangeV2` retrieval for blob-era payload bodies.
- Value: medium; useful listener depth, but lower leverage than a hash-pinned
  body lookup because the by-hash variant is the narrower bridge from the now
  imported V6 payload proof.
- Risk: medium; it adds range-window semantics and likely needs more fixture
  plumbing or multiple imported block hashes than the by-hash extension.
- Required validation: focused escalated smoke and `git diff --check`;
  broader gates only if shared helpers change.
- Decision: defer.
- Reason: lower leverage than proving the simpler by-hash payload-body
  contract first.

### Candidate C

- Objective: revisit unrelated Shanghai txpool or replacement runner coverage.
- Value: low for current priority because the blob-era KZG boundary still has a
  narrower missing live payload-body path.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on selected slice.
- Decision: defer.
- Reason: loses momentum on the highest-value blob-era runner gap.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from imported non-empty
`engine_getPayloadV6` retrieval to live
`engine_getPayloadBodiesByHashV2` process-boundary proof.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The live verifier opt-in smoke proves Amsterdam-era
  `engine_getPayloadBodiesByHashV2` retrieval, not only payload envelopes and
  direct blob lookups.
- The existing `kzgOptIn` seed/report path exposes the imported block hash
  needed to request the V2 payload body through the live Engine listener.
- Smoke reporting captures enough body-response evidence to debug transaction
  list and block-access-list regressions at the runner boundary.

Non-goals:

- Do not redesign production KZG verification, payload construction, or blob
  sidecar storage.
- Do not widen unrelated Shanghai runner assertions in the same run.
- Do not broaden into `engine_getPayloadBodiesByRangeV2` unless the by-hash
  path proves impossible with the existing seeded database shape.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getPayloadBodiesByHashV2` retrieval for the imported Amsterdam-era
  block seeded through the existing `kzgOptIn` path.
- The smoke/assertion surface fails clearly when verifier opt-in is absent,
  unavailable, or when the returned V2 payload body omits or malforms the
  expected transaction/body/block-access-list fields.
- Any shared helper change stays scoped to supporting the imported V2
  payload-body lookup path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/helper code only.
- Escalate to Tier 3 only if production listener or Engine implementation code
  must change.

Focused gates:

- focused escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  covering imported Amsterdam-era `engine_getPayloadBodiesByHashV2`
- any direct CLI regression added for the V2 payload-body response contract

Required pre-commit gates:

- `git diff --check`
- focused escalated smoke gate for the selected V2 payload-body path
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
- If the imported Amsterdam-era body lookup still requires broader fixture or
  canonical-import plumbing than the current seeded path can support, stop and
  record the exact missing body-response boundary instead of widening scope ad
  hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke V2 payload body lookup`

## Blockers

- If the current seeded/imported database cannot exercise
  `engine_getPayloadBodiesByHashV2` without broader fixture plumbing, record
  the exact missing body-response boundary and the smallest viable helper
  change instead of widening into unrelated test infrastructure cleanup.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child and temporary database
  path instead of introducing a second verifier configuration flow.
- Prefer extending the existing imported V6 seed/report path over inventing a
  second unrelated blob fixture family.
- Keep the slice centered on live `engine_getPayloadBodiesByHashV2`, not
  range-based payload bodies or unrelated direct lookup variants.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
