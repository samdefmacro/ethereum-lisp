# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: replacement-fixture breadth is already validated on `main`; the
  KZG proof verification is now landed, validated, and committed locally in
  the loop workspace; the next actionable slice is the highest-value blob-era
  process-boundary follow-up.
- Recent commits reviewed: the recent replacement-fixture breadth closure is on
  `main`, and this run added the repo-local vendored KZG verifier helper,
  canonical point/blob vector replay, verifier pass, and a clean full-suite
  result of `894 tests passed, 5 skipped`.
- Relevant task/roadmap anchors: `Integrate real KZG proof verification` is
  now closed in `docs/tasks.md`; the roadmap's cryptographic-primitives section
  now treats KZG verification as done and points next work at blob-era
  prepared-payload process-boundary smoke.
- Relevant loop state: the repository has repo-local KZG verification through
  the existing point/blob hooks and CLI opt-in surface, but the live smoke
  surface still proves only the engine-only capability opt-in path rather than
  blob-era prepared-payload V3/V4 workflows.

## Candidate Ranking

### Candidate A

- Objective: extend prepared-payload process-boundary smoke to exercise
  blob-era `engine_getPayloadV3/V4` paths under the repo-local KZG verifier
  opt-in.
- Value: highest; real KZG verification is now present, so the next gap is
  proving blob-era prepared-payload behavior across the runner/devnet boundary
  instead of only through unit coverage and engine-only capability smoke.
- Risk: medium-high; it touches listener/process-boundary behavior, payload
  version negotiation, and blob-era fixture shaping.
- Required validation: focused escalated devnet/Phase-A smoke covering the new
  blob-era prepared-payload path, `git diff --check`, and the full suite once
  before commit.
- Decision: selected.
- Reason: it builds directly on the newly landed KZG verifier slice and is the
  highest-value remaining production-facing gap.

### Candidate B

- Objective: add pending-filter and txpool-journal propagation assertions for
  prepared-payload replacement flows.
- Value: medium; it closes the last notable residual from the replacement smoke
  breadth slice.
- Risk: medium because it adds more event/process-boundary assertions but does
  not expand fork coverage.
- Required validation: focused escalated devnet smoke and `git diff --check`;
  full suite only if production code changes.
- Decision: defer.
- Reason: useful follow-up, but blob-era prepared-payload coverage now has
  higher leverage because the verifier backend is finally real and pinned.

### Candidate C

- Objective: remove the visible local Go toolchain prerequisite from the
  repo-local KZG verifier helper.
- Value: low-medium; it would improve contributor ergonomics, but the current
  prerequisite is explicit and non-blocking.
- Risk: medium-high because cross-platform binary distribution or a native
  replacement could widen the slice substantially.
- Required validation: focused KZG vector coverage, `git diff --check`, and
  likely the full suite if the helper integration changes.
- Decision: defer.
- Reason: it is not blocking correctness or current process-boundary coverage,
  and it should not displace the more valuable blob-era smoke expansion.

## Selected Objective

Extend blob-era prepared-payload process-boundary smoke so the repo-local KZG
verifier opt-in proves `engine_getPayloadV3/V4` behavior through the live
runner/devnet boundary instead of only through unit tests and engine-only
capability negotiation.

## Scope

Allowed files/modules:

- `src/cli.lisp`
- `scripts/devnet-smoke-gate.lisp`
- `scripts/phase-a-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `tests/core-tests.lisp`
- `tests/evm-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The live smoke surface can run a blob-era prepared-payload path with the
  repo-local KZG verifier configured and prove the expected `engine_getPayload`
  versioned response boundary.
- Blob-era smoke reporting captures the verifier opt-in state and the selected
  payload-version path clearly enough to debug future Cancun/Prague regressions.
- Any missing glue for the verifier-backed blob-era prepared-payload runner
  path is covered by direct CLI/process tests rather than hidden behind manual
  local setup.

Non-goals:

- Do not replace or rework the repo-local KZG helper unless the smoke slice
  proves that a small integration fix is necessary.
- Do not widen unrelated txpool replacement assertions in the same run.
- Do not add large new fixture families when a pinned blob-era prepared-payload
  path can be exercised with existing smoke infrastructure.

## Acceptance Criteria

- Focused process-boundary coverage proves at least one blob-era prepared
  payload workflow reaches the live `engine_getPayloadV3` or
  `engine_getPayloadV4` boundary with the repo-local KZG verifier configured.
- The smoke/assertion surface fails clearly when the verifier opt-in is absent,
  unavailable, or misreported for that blob-era path.
- The diff remains scoped to blob-era prepared-payload smoke/assertion glue and
  any minimal runner wiring needed to exercise it.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 3 process-boundary smoke.

Focused gates:

- focused escalated blob-era devnet/Phase-A smoke covering the prepared-payload
  path under verifier opt-in
- any direct CLI/process regression added for the new path

Required pre-commit gates:

- `git diff --check`
- focused escalated smoke gate for the selected blob-era prepared-payload path
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Full-suite policy:

- Mandatory once before commit because listener/process-boundary behavior and
  prepared-payload version negotiation are Tier 3 surfaces.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the selected path needs a blob-era fixture or runner artifact that is not
  already pinned in-repo, request approval instead of inventing ad hoc local
  substitutes.

## Commit And Push Policy

- Commit allowed: only after the backend/setup/vector inputs are present and
  the focused blob-era smoke path, `git diff --check`, full suite, and verifier
  review all pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Expand blob-era prepared payload smoke`

## Blockers

- If the blob-era prepared-payload path cannot be exercised through existing
  pinned smoke infrastructure without introducing unrelated fixture churn,
  stop and record the exact missing fixture or runner input instead of widening
  scope.

## Implementer Notes

- Reuse the repo-local `scripts/kzg-verifier.sh` opt-in surface and existing
  blob-era runner plumbing instead of creating a second KZG configuration path.
- Prefer asserting the prepared-payload version boundary with existing pinned
  smoke fixtures before adding new fixture breadth.
- Keep the slice centered on process-boundary proof that blob-era payload
  selection works when the verifier is present; do not backslide into
  unit-test-only coverage.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
