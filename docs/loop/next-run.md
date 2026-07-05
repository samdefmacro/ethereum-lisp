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
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-IMPORT` has been committed and
  pushed to `origin/main`.
- Current completed slice: the standalone devnet smoke gate imports a
  txpool-backed prepared payload through authenticated `engine_newPayloadV2`,
  canonicalizes it through `engine_forkchoiceUpdatedV2`, proves public
  canonical transaction/receipt/raw/block visibility for the selected
  transaction, and proves txpool cleanup removes the mined selected
  transaction while non-selected basefee and nonce-gapped entries remain queued.
- Validation from the completed slice: focused escalated standalone smoke,
  fresh all-fixtures devnet smoke, `git diff --check`, and
  `sbcl --script tests/run-tests.lisp` passed (`890 tests passed, 5 skipped`);
  independent verifier review returned `PASS`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC correctness
  remains the highest-value roadmap track. The next useful gap is prepared
  payload cache refresh under same-sender/same-nonce txpool replacement, where
  transaction count can stay constant while selected transaction contents
  change.

## Candidate Ranking

### Candidate A

- Objective: implement
  `ENGINE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-CACHE`, locking prepared payload
  id/content refresh after a valid same-sender/same-nonce public txpool
  replacement.
- Value: high; it closes the residual cache correctness risk identified after
  txpool-backed prepared payload selection and import.
- Risk: medium; it touches Engine RPC prepared-payload behavior and txpool
  replacement semantics, but should be testable with focused in-process
  coverage.
- Required validation: focused Engine RPC/txpool test, `git diff --check`, full
  suite once, and independent verifier review.
- Decision: selected.
- Reason: cache reuse with same-head/same-attributes and same selected
  transaction count is a plausible correctness bug unless the selected
  transaction root/content is explicitly guarded.

### Candidate B

- Objective: add process-boundary smoke coverage for V3/V4 prepared payload
  variants.
- Value: medium; useful later-fork coverage, but current KZG/later-fork support
  is intentionally capability-gated.
- Risk: medium-high because it may require broader fork/KZG plumbing.
- Required validation: focused devnet smoke and full suite.
- Decision: defer.
- Reason: replacement/cache correctness is narrower and directly follows the
  current Shanghai txpool-backed prepared-payload path.

### Candidate C

- Objective: classify remaining official v5.4.0 fixture drift.
- Value: medium; useful consensus map, but less directly executable than the
  current Phase B Engine/txpool correctness path.
- Risk: low-medium.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority still favors executable client behavior.

## Selected Objective

Implement `ENGINE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-CACHE`: prove and, if
needed, fix same-head/same-attributes prepared-payload cache refresh when a
valid same-sender/same-nonce public txpool replacement changes the selected
transaction without changing selected transaction count.

## Scope

Allowed files/modules:

- `src/engine-rpc.lisp`
- `src/txpool.lisp`
- `src/core/*.lisp`
- `tests/core-tests.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- A first prepared-payload call over an executable public txpool transaction
  returns a payload id whose payload contains the original raw transaction.
- After a valid same-sender/same-nonce replacement is admitted, a second
  same-head/same-attributes prepared-payload call returns a distinct payload id.
- `engine_getPayload*` for the second id returns the replacement raw
  transaction and not the original raw transaction.
- Public txpool sender/nonce indexes expose only the replacement before import.
- If the implementation already behaves correctly, add focused regression
  coverage and document the closed risk.

Non-goals:

- Do not change replacement price-bump policy except to fix a directly exposed
  bug in this path.
- Do not widen standalone devnet smoke unless in-process coverage cannot expose
  the cache boundary.
- Do not broaden official fixture pins.
- Do not change listener lifecycle, JWT auth, or public/Engine namespace
  separation.

## Acceptance Criteria

- Focused Engine RPC/txpool coverage demonstrates the first prepared payload
  contains the original transaction.
- The same focused coverage admits a valid same-sender/same-nonce replacement
  and demonstrates the second prepared payload has a different payload id.
- The second `engine_getPayload*` result includes the replacement raw
  transaction and excludes the original raw transaction.
- The public txpool view before import exposes the replacement and not the old
  transaction for that sender/nonce.
- Existing prepared-payload txpool selection/import behavior remains stable.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- A targeted Engine RPC/txpool test invocation if the test runner supports a
  direct test name.
- Otherwise, run the narrowest available core/CLI test command that exercises
  the new regression.

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation before running standalone devnet or
  Phase A devnet smoke gates. This slice should prefer in-process coverage and
  may not need socket escalation unless the implementation requires a
  process-boundary repro.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Test prepared payload txpool replacement cache`

## Blockers

- No current git synchronization blocker.
- If the current test harness cannot construct a valid same-sender/same-nonce
  replacement without broad fixture work, stop with
  `BLOCKED_PREPARED_PAYLOAD_REPLACEMENT_FIXTURE` and document the exact missing
  helper or fixture.

## Implementer Notes

- Derive the current task from this file, not from stale heartbeat text.
- Prefer reusing existing txpool transaction fixture helpers and Engine RPC
  prepared-payload tests.
- Keep the test focused on the cache boundary: original selected transaction,
  valid replacement, distinct payload id, replacement payload contents, and
  txpool sender/nonce visibility.
- If code changes are necessary, preserve the existing selected-transaction-root
  payload-id contract.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
