# Next Run

## Run Metadata

- Date: 2026-07-06
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: `main` contains the validated engine-only hidden-method batch plus
  refreshed loop bookkeeping after the non-KZG blob-lookup V2 listener proof.
- Recent commits reviewed: the latest validated slice closed the live non-KZG
  `engine_getBlobsV2` listener rejection contract and kept the engine-only
  serve connection/report contract aligned with the extra live probe.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-KZG-CAPABILITY-OPT-IN` now
  records the completed KZG opt-in positive-path blob/body matrix together
  with the live non-KZG by-range, by-hash, and blob-lookup V1/V2 hidden-method
  rejection proofs.
- This file is the fresh follow-up contract generated after the V2 slice
  passed focused validation and verifier review; the `PENDING` verifier state
  below applies only to the upcoming V3 slice.
- Relevant loop state: `docs/loop/state.md` now recommends pivoting to the
  sibling non-KZG hidden-method proof for `engine_getBlobsV3`.

## Candidate Ranking

### Candidate A

- Objective: prove one live non-KZG engine-only `engine_getBlobsV3` request is
  rejected at the listener boundary instead of merely being hidden from
  `engine_exchangeCapabilities`.
- Value: highest; it closes the next adjacent disabled-path blob-era process
  contract while reusing the same engine-only harness and the fail-closed
  production filter already proven for payload-bodies V2 and blob lookup V1/V2.
- Risk: low-medium; likely smoke/assertion/report work only unless the live
  non-KZG listener still exposes or differently normalizes the blob lookup
  method.
- Required validation: focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`,
  focused CLI coverage if report assertions change, `git diff --check`,
  verifier review, and the full suite only if production code changes or the
  verifier identifies broader risk.
- Decision: selected.
- Reason: it is the next highest-leverage sibling negative-path proof after
  closing both payload-bodies V2 listener-boundary contracts and the V1/V2
  blob-lookup boundaries.

### Candidate B

- Objective: pivot back to unrelated Phase B runner or txpool work.
- Value: lower than Candidate A because the blob-lookup hidden-method line
  still has one obvious listener-boundary proof missing.
- Risk: medium.
- Required validation: depends on slice.
- Decision: defer.
- Reason: lower leverage than finishing the remaining sibling blob-lookup
  proof first.

### Candidate C

- Objective: widen beyond the hidden-method proof into malformed-request
  matrices or broader Engine plumbing.
- Value: lower than Candidate A because the clean sibling negative-path proof
  is still available and bounded.
- Risk: medium-high.
- Required validation: likely broader than needed for this loop step.
- Decision: defer.
- Reason: unnecessary scope growth unless the V3 probe reveals a shared bug.

## Selected Objective

Prove one live non-KZG engine-only `engine_getBlobsV3` request is rejected at
the process boundary, using the existing engine-only smoke path without
verifier opt-in to lock the disabled-method envelope rather than only
capability omission.

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

- The engine-only non-KZG smoke proves live `engine_getBlobsV3` is rejected at
  the listener boundary when verifier opt-in is absent, not only omitted from
  capability advertisement.
- The smoke/report surface records enough disabled-method error evidence to
  debug code/message drift at the process boundary.
- The existing non-KZG capability guard remains intact, and the existing KZG
  opt-in positive-path blob/body probes remain intact on their current runner
  path.

Non-goals:

- Do not revisit the already-proven non-KZG payload-bodies V2 hidden-method
  contracts unless the blob-lookup probe reveals a shared regression.
- Do not widen the malformed-object KZG opt-in matrix or the positive-path
  blob/cell-proof evidence unless the new negative request uncovers a shared
  bug.
- Do not widen beyond `engine_getBlobsV3` unless this probe reveals a shared
  boundary bug.
- Do not refactor general Engine RPC plumbing outside the minimal support
  needed for the live disabled-method proof.

## Acceptance Criteria

- Focused process-boundary coverage proves live non-KZG `engine_getBlobsV3` is
  rejected with the documented disabled method envelope.
- The smoke/assertion surface fails clearly if the live request becomes
  available, returns a different error envelope, or includes a success result.
- The existing non-KZG capability guard and KZG opt-in positive-path blob/body
  probes remain green in the same smoke path.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 1 if the change stays in smoke/assertion/report or adjacent core test
  code only.
- Escalate to Tier 2 only if the live hidden-method request uncovers a shared
  production bug.

Focused gates:

- focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
- focused CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` if report assertions
  change

Required pre-commit gates:

- `git diff --check`
- focused escalated engine-only smoke for the selected non-KZG hidden-method
  path
- independent verifier `PASS`
- full suite only if production code changes or verifier flags broader risk

Full-suite policy:

- Not required for smoke/assertion-only report work.
- Mandatory once before commit if production files such as `src/engine-rpc.lisp`
  or `src/chain-store-memory.lisp` change.

Escalation requirements:

- Request local socket/network escalation before the focused smoke gate.
- If the runner normalizes the selected non-KZG request through a different
  disabled-method envelope than expected, stop and record that exact mismatch
  instead of broadening scope.

## Commit And Push Policy

- Commit allowed: only after the applicable focused gate, `git diff --check`,
  and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke cell proof V3 hidden without KZG`

## Blockers

- If the selected non-KZG request proof reveals a real production mismatch
  that needs broader Engine RPC work, stop and write that narrower blocker
  instead of widening into a larger blob-era project.

## Implementer Notes

- Reuse the existing engine-only smoke path and non-KZG capability guard
  instead of inventing a second listener configuration flow.
- Prefer extending the current report contract over adding a separate smoke
  mode.
- Keep the slice centered on one live non-KZG `engine_getBlobsV3`
  disabled-method behavior, not broader blob/cell-proof widening or new
  malformed-request batching.

## Verifier Result

- Status: `PENDING`
- Findings: none yet.
- Residual risk: pending implementation.
