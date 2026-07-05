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
  `engine_getPayloadV3`, `engine_getPayloadV4`, and a non-empty
  `engine_getPayloadV5` runner boundary; the highest-value remaining gap is
  direct blob lookup rather than payload-envelope shape.
- Recent commits reviewed: the latest validated slice moved the smoke from
  empty V3/V4 bundle presence into imported non-empty V5 bundle retrieval.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records live non-empty V5 `blobsBundle` retrieval; the roadmap now treats
  direct `engine_getBlobsV1` runner proof as the next bounded KZG follow-up.
- Relevant loop state: blob-carrying payload-envelope retrieval is covered at
  the process boundary, but direct versioned-hash blob lookup is still missing
  from live runner smoke.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke from imported non-empty
  `engine_getPayloadV5` bundle retrieval into direct `engine_getBlobsV1`
  process-boundary proof, likely by hardening the shared test HTTP reader for
  large blob JSON responses.
- Value: highest; it closes the remaining obvious live blob retrieval gap
  after the new V5 bundle proof.
- Risk: medium; it stays in runner smoke/assertion code, but it likely touches
  shared test I/O helpers handling large responses.
- Required validation: focused escalated engine-only smoke for the blob lookup
  path, `git diff --check`, and verifier review. Full suite only if the shared
  test helper change justifies broader coverage.
- Decision: selected.
- Reason: it is the most direct continuation of the completed V5 blob-bundle
  slice and preserves the current runner-boundary priority.

### Candidate B

- Objective: widen the same runner proof to `engine_getPayloadV6` with
  non-empty blob bundle plus execution requests.
- Value: medium; useful fork-surface depth, but lower leverage than direct
  blob lookup because V5 already proves blob-carrying envelope retrieval.
- Risk: medium; it adds another payload-envelope variant without closing the
  direct blob lookup gap.
- Required validation: focused escalated smoke and `git diff --check`;
  broader gates only if shared helpers change.
- Decision: defer.
- Reason: lower leverage than `engine_getBlobsV1`.

### Candidate C

- Objective: revisit unrelated Shanghai txpool or replacement runner coverage.
- Value: low for current priority because the blob-era KZG boundary still has
  a narrower missing live path.
- Risk: low-medium, but it would interrupt the current KZG continuity.
- Required validation: depends on selected slice.
- Decision: defer.
- Reason: loses momentum on the highest-value blob-era runner gap.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from imported non-empty
`engine_getPayloadV5` bundle retrieval to direct live `engine_getBlobsV1`
process-boundary proof.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The live verifier opt-in smoke proves direct blob retrieval through
  `engine_getBlobsV1`, not only blob-carrying payload envelopes.
- Shared smoke/test response handling tolerates the large blob JSON body
  without recursion or stack exhaustion.
- Smoke reporting captures enough direct blob lookup evidence to debug Cancun
  blob retrieval regressions at the runner boundary.

Non-goals:

- Do not redesign production KZG verification, payload construction, or blob
  sidecar storage.
- Do not widen unrelated V2 Shanghai runner assertions in the same run.
- Do not add broad new fixture families if the existing seeded runner path can
  exercise `engine_getBlobsV1`.

## Acceptance Criteria

- Focused process-boundary coverage proves live verifier opt-in
  `engine_getBlobsV1` blob retrieval with at least one returned blob/proof
  record.
- The smoke/assertion surface fails clearly when verifier opt-in is absent,
  unavailable, or when the lookup result is malformed or truncated.
- Any shared helper change stays scoped to supporting large runner JSON
  response handling for this blob lookup path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/helper code only.
- Escalate to Tier 3 only if production listener or Engine implementation code
  must change.

Focused gates:

- focused escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  covering direct `engine_getBlobsV1` retrieval
- any direct CLI regression added for large-response handling

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
- If direct blob lookup still requires a broader helper or fixture than the
  current seeded V5 path can support, stop and record the exact response
  handling blocker instead of widening scope ad hoc.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke direct blob runner lookup`

## Blockers

- If the current shared HTTP reader cannot handle the full
  `engine_getBlobsV1` JSON body without broader refactoring, record the exact
  failure mode and the smallest viable helper boundary instead of widening into
  unrelated test infrastructure cleanup.

## Implementer Notes

- Reuse the existing engine-only `kzgOptIn` smoke child and its seeded
  database path instead of introducing a second verifier configuration flow.
- Prefer a bounded helper improvement that makes the real `engine_getBlobsV1`
  response readable over inventing smaller fake blob payloads.
- Keep the slice centered on direct live blob lookup, not additional payload
  envelope variants.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
