# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: the repo-local KZG verifier path is now validated through live
  `engine_forkchoiceUpdatedV3/V4` and `engine_getPayloadV3/V4` runner smoke;
  the next process-boundary gap is blob-carrying retrieval rather than bare
  envelope negotiation.
- Recent commits reviewed: the replacement-fixture breadth closure and the
  trusted KZG verifier integration are already on `main`; the latest committed
  follow-up should be the V3/V4 prepared-payload runner smoke expansion from
  this run.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records live V3/V4 prepared-payload coverage; the roadmap now treats the
  next bounded KZG follow-up as blob-carrying process-boundary smoke.
- Relevant loop state: blob-era prepared-payload envelopes are proven across
  the runner boundary with verifier opt-in, but live blob bundle retrieval is
  not yet covered by the smoke surface.

## Candidate Ranking

### Candidate A

- Objective: extend the verifier opt-in runner smoke to prove blob-carrying
  process-boundary retrieval, such as `engine_getBlobsV1` and/or a higher
  blob-aware payload envelope that includes non-empty blob bundle fields.
- Value: highest; it moves the live runner proof from empty V3/V4 envelopes to
  actual blob-era retrieval behavior, which is the next material gap after the
  current slice.
- Risk: medium-high; it touches listener/process-boundary behavior, blob
  bundle shaping, and may require minimal fixture/rpc wiring.
- Required validation: focused escalated devnet smoke for the selected blob
  retrieval path, `git diff --check`, and the full suite once before commit.
- Decision: selected.
- Reason: it is the most direct continuation of the KZG/V3/V4 runner work and
  preserves the current high-value production boundary focus.

### Candidate B

- Objective: widen runner smoke assertions for prepared-payload replacement
  side effects such as filter/journal propagation.
- Value: medium; useful hardening, but it stays on Shanghai/V2 behavior and no
  longer outranks blob-era runner gaps.
- Risk: medium; it grows process-boundary assertions without widening fork
  behavior.
- Required validation: focused escalated devnet smoke and `git diff --check`;
  full suite only if production code changes.
- Decision: defer.
- Reason: lower leverage than blob-carrying KZG-backed retrieval.

### Candidate C

- Objective: remove the visible local Go toolchain prerequisite from the
  repo-local KZG helper.
- Value: low-medium; improves ergonomics, but the current requirement is
  explicit and not blocking correctness.
- Risk: medium-high because packaging/distribution work could sprawl beyond a
  bounded loop slice.
- Required validation: focused KZG vector coverage, `git diff --check`, and
  likely the full suite if helper integration changes.
- Decision: defer.
- Reason: not the highest-value process-boundary correctness gap.

## Selected Objective

Extend the repo-local verifier opt-in runner smoke from empty V3/V4 prepared
payload envelopes to a blob-carrying retrieval boundary, preferably through
`engine_getBlobsV1` or another existing live blob bundle surface.

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

- The live verifier opt-in smoke proves at least one blob-carrying retrieval
  path instead of only empty prepared-payload envelopes.
- Smoke reporting captures the blob bundle retrieval evidence clearly enough to
  debug Cancun/Prague regressions at the runner boundary.
- Any minimal missing glue is covered by direct CLI/process assertions rather
  than manual local setup.

Non-goals:

- Do not replace or redesign the repo-local KZG helper unless a small fix is
  required to reach the selected blob retrieval path.
- Do not widen unrelated txpool replacement or journaling assertions in the
  same run.
- Do not add broad new fixture families if an existing pinned/devnet path can
  exercise the blob retrieval boundary.

## Acceptance Criteria

- Focused process-boundary coverage proves at least one live blob-carrying
  verifier opt-in path, such as `engine_getBlobsV1` and/or a non-empty blob
  bundle in a retrieved payload envelope.
- The smoke/assertion surface fails clearly when the verifier opt-in is absent,
  unavailable, or misreported for that blob-carrying path.
- The diff remains scoped to blob-era runner smoke/assertion glue and any
  minimal wiring needed to expose the selected retrieval surface.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 3 process-boundary smoke.

Focused gates:

- focused escalated blob-era devnet/Phase-A smoke covering the selected
  blob-carrying retrieval path under verifier opt-in
- any direct CLI/process regression added for the new path

Required pre-commit gates:

- `git diff --check`
- focused escalated smoke gate for the selected blob-carrying path
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Full-suite policy:

- Mandatory once before commit because listener/process-boundary behavior and
  blob-era retrieval negotiation are Tier 3 surfaces.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the selected path needs a blob-era fixture or runner artifact that is not
  already pinned in-repo, request approval instead of inventing ad hoc local
  substitutes.

## Commit And Push Policy

- Commit allowed: only after the focused blob-era smoke path,
  `git diff --check`, full suite, and verifier review all pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke blob bundle runner boundary`

## Blockers

- If the selected blob-carrying path cannot be exercised through existing
  pinned smoke infrastructure without unrelated fixture churn, stop and record
  the exact missing fixture or runner input instead of widening scope.

## Implementer Notes

- Reuse the repo-local `scripts/kzg-verifier.sh` opt-in surface and the
  existing engine-only `kzgOptIn` smoke child instead of creating a second KZG
  configuration path.
- Prefer proving blob bundle retrieval with existing pinned/devnet fixtures
  before inventing new fixture breadth.
- Keep the slice centered on live process-boundary proof for blob-carrying
  retrieval, not unit-only behavior.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
