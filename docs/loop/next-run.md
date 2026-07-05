# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: this run is expected to start after
  `ENGINE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-CACHE` has been committed and
  pushed to `origin/main`.
- Recent commits reviewed: prepared-payload txpool selection/import work and
  dev-period txpool mining slices are already on `main`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track.
- Relevant loop state: in-process Engine RPC coverage now proves that a valid
  same-sender/same-nonce public txpool replacement changes the prepared payload
  id and `engine_getPayloadV1` contents for same-head/same-attributes
  preparation. The remaining gap is proving the same boundary across the real
  split Engine/public listener smoke path.

## Candidate Ranking

### Candidate A

- Objective: implement
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT`, promoting the
  txpool replacement prepared-payload cache boundary to the standalone devnet
  process-runner smoke gate.
- Value: high; it turns the just-locked Engine RPC invariant into
  runner-facing evidence across authenticated Engine and public RPC listeners.
- Risk: medium; it touches the standalone smoke harness and JSON/text report
  assertions, but should reuse the existing V2 txpool-backed prepared-payload
  import flow.
- Required validation: focused standalone devnet smoke with local
  socket/network escalation, `git diff --check`, full suite once, and
  independent verifier review.
- Decision: selected.
- Reason: it directly advances executable Phase B process behavior and closes
  the current residual process-boundary gap without requiring KZG or far-fork
  support.

### Candidate B

- Objective: add process-boundary smoke coverage for V3/V4 prepared payload
  variants.
- Value: medium; useful later-fork coverage after the Shanghai V2 path is
  robust.
- Risk: medium-high because blob-era Engine capability advertisement is
  intentionally KZG-gated and far-fork payload bodies can widen scope.
- Required validation: focused devnet smoke and full suite.
- Decision: defer.
- Reason: the replacement-cache V2 boundary is narrower, executable now, and
  follows directly from the just-added in-process regression.

### Candidate C

- Objective: classify remaining official v5.4.0 fixture drift.
- Value: medium; useful consensus map, but less directly tied to local devnet
  executable client behavior.
- Risk: low-medium.
- Required validation: classifier smoke and Phase A smoke gate if selectors
  change.
- Decision: defer.
- Reason: Phase B process-runner readiness remains the strategic priority.

## Selected Objective

Implement `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT`: extend
the standalone devnet smoke/process-runner path so a valid same-sender/same-
nonce public txpool replacement refreshes the txpool-backed prepared-payload
cache across the real authenticated Engine/public RPC listener split.

## Scope

Allowed files/modules:

- `scripts/devnet-smoke-gate.lisp`
- `tests/cli-tests.lisp`
- `src/engine-rpc.lisp`
- `src/public-rpc.lisp`
- `src/txpool.lisp`
- `src/core/*.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The standalone smoke gate admits an executable public transaction, prepares
  and retrieves a txpool-backed payload through authenticated
  `engine_forkchoiceUpdatedV2` / `engine_getPayloadV2`, then admits a valid
  same-sender/same-nonce replacement before importing the first prepared
  payload.
- Repeating the same-head/same-attributes Engine preparation returns a distinct
  second payload id.
- The second retrieved payload includes the replacement raw transaction and
  excludes the original raw transaction.
- Public `txpool_contentFrom` before import exposes only the replacement at
  that sender/nonce.
- JSON/text smoke output reports the two payload ids, replacement raw
  transaction/hash evidence, and txpool sender/nonce replacement evidence.

Non-goals:

- Do not change txpool replacement price-bump policy unless this smoke exposes
  a direct bug.
- Do not widen V3/V4 or KZG-gated Engine coverage.
- Do not alter listener lifecycle, JWT auth, or public/Engine namespace
  separation except to preserve existing smoke contracts.
- Do not broaden official fixture pins.

## Acceptance Criteria

- Focused standalone smoke proves the original txpool-backed prepared payload
  contains the original raw transaction.
- The same smoke admits a valid replacement and proves the second same-head/
  same-attributes prepared payload has a distinct payload id.
- The second `engine_getPayloadV2` result contains the replacement raw
  transaction and not the original raw transaction.
- Public txpool sender/nonce visibility before import exposes the replacement
  and not the old transaction.
- Existing txpool-backed prepared-payload selection/import smoke evidence
  remains stable.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation for the standalone devnet smoke gate
  and for the full suite if local socket/devnet tests require it under the
  sandbox.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Smoke prepared payload txpool replacement`

## Blockers

- No current git synchronization blocker.
- If the smoke harness cannot admit a valid replacement through public RPC
  without destabilizing the existing prepared-payload import flow, stop with
  `BLOCKED_DEVNET_REPLACEMENT_SMOKE_FIXTURE` and document the exact fixture or
  harness gap.

## Implementer Notes

- Derive the current task from this file, not from stale heartbeat text.
- Reuse the existing txpool-backed prepared-payload selection/import smoke
  workflow where possible.
- Keep the replacement check before importing the first prepared payload so the
  same parent/head attributes can expose prepared-payload cache refresh.
- Preserve existing report fields unless a field is intentionally extended.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
