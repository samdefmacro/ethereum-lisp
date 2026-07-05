# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: this run is expected to start after `Smoke prepared payload txpool replacement` has been committed and pushed to `origin/main`.
- Recent commits reviewed: prepared-payload txpool selection/import work, the in-process replacement-cache slice, and the standalone replacement smoke slice are already on `main`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC process-runner readiness remains the highest-value roadmap track; the next process-boundary gap is widening replacement-smoke breadth across the pinned Shanghai smoke table.
- Relevant loop state: the standalone split Engine/public smoke path now proves same-sender/same-nonce replacement refreshes the prepared-payload cache, changes the payload id, and preserves replacement-only public/canonical evidence. The remaining gap is fixture breadth across the current all-fixtures runner table.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-FIXTURE-BREADTH`, reusing the now-green replacement workflow across the current pinned Shanghai all-fixtures smoke table.
- Value: high; it extends an executable runner-boundary contract across the existing fixture breadth without widening fork scope.
- Risk: medium; it touches the standalone smoke harness and aggregate report/test expectations, but should reuse the already validated single-fixture replacement path.
- Required validation: focused escalated all-fixtures devnet smoke, `git diff --check`, and independent verifier review; full suite only if production code changes or verifier flags broader risk.
- Decision: selected.
- Reason: it is the narrowest follow-up that materially improves runner-facing confidence while preserving the current Shanghai/V2 scope.

### Candidate B

- Objective: add process-boundary smoke coverage for V3/V4 prepared-payload variants.
- Value: medium; useful later-fork coverage once the Shanghai replacement path is broad and stable.
- Risk: medium-high because blob/KZG-gated capability boundaries can widen scope or force fallback logic.
- Required validation: focused devnet smoke, likely full suite if production code changes.
- Decision: defer.
- Reason: the all-fixtures Shanghai replacement breadth is a tighter continuation of the current slice and avoids premature far-fork expansion.

### Candidate C

- Objective: integrate a real trusted-setup-backed KZG verifier through the existing point/blob proof hooks.
- Value: high strategically, but broader than the current runner-boundary thread.
- Risk: high; backend pinning, setup artifact management, and proof-vector replay make this a larger vertical slice.
- Required validation: KZG vector coverage and full suite.
- Decision: defer.
- Reason: it is the right next frontier after the current runner-boundary table is more complete, but it is not the narrowest executable follow-up for the next single run.

## Selected Objective

Implement `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-FIXTURE-BREADTH`: widen the standalone split Engine/public replacement-cache smoke path across the current pinned Shanghai all-fixtures runner table while preserving the existing bounded single-fixture contract.

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

- `scripts/devnet-smoke-gate.lisp -- --json --all-fixtures` reuses the replacement-cache workflow for each current pinned Shanghai smoke fixture.
- Each per-case result preserves original and replacement payload-id evidence plus replacement-only public/canonical transaction evidence.
- Aggregate connection totals and suite-level assertions remain coherent across the expanded case table.

Non-goals:

- Do not widen V3/V4 or blob-era Engine coverage.
- Do not change txpool replacement price-bump policy unless the all-fixtures smoke exposes a direct correctness bug.
- Do not rename restored-db report fields unless the naming drift blocks the acceptance criteria.
- Do not broaden official fixture pins beyond the current pinned Shanghai smoke table.

## Acceptance Criteria

- The all-fixtures standalone smoke path proves the original txpool-backed prepared payload and the replacement payload-id refresh for each current pinned Shanghai smoke case.
- The repeated same-head/same-attributes preparation returns a distinct second payload id per case.
- The replacement `engine_getPayloadV2` result includes the replacement raw transaction and excludes the original raw transaction per case.
- Public txpool sender/nonce visibility before import exposes only the replacement per case.
- Existing single-fixture replacement smoke evidence and connection-contract expectations remain stable.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 2 if the run stays in smoke/test/docs scope; escalate to Tier 3 only if a production listener/txpool path needs a real fix.

Focused gates:

- `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures`

Required pre-commit gates:

- `git diff --check`
- independent verifier `PASS`

Full-suite policy:

- Not required when the run stays in smoke-harness, report, and test-assertion scope.
- Required once before commit if production code changes in shared Engine/public RPC, txpool, or core prepared-payload paths, or if verifier review identifies a broader regression risk.

Escalation requirements:

- Request local socket/network escalation before the all-fixtures devnet smoke gate.
- If a production-code fix is needed and triggers the full-suite policy, request escalation for the full suite instead of spending time on a predictable sandbox bind failure.

## Commit And Push Policy

- Commit allowed: yes, after applicable deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Widen replacement smoke fixture coverage`

## Blockers

- No current git synchronization blocker.
- If the all-fixtures replacement workflow cannot be reused without exposing a real fixture-specific production bug, stop with `BLOCKED_REPLACEMENT_ALL_FIXTURES_DRIFT` and record the exact failing fixture family plus the observed divergence.

## Implementer Notes

- Derive the current task from this file, not from stale heartbeat text.
- Prefer reusing the already green single-fixture replacement workflow over introducing a second replacement-specific code path.
- Keep aggregate connection-contract updates synchronized between standalone smoke output, Phase A wrapper expectations, and CLI JSON assertions.
- If a failure turns out to be stale smoke/test accounting rather than a client bug, keep the fix in the harness/assertions and do not broaden production scope.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
