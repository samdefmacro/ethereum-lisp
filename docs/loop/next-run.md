# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: current run is expected to commit and push
  `DEVNET-RUNNER-DEV-PERIOD-SMOKE` before the next run starts.
- Recent commits reviewed: `d09fbce`, `c787e9f`, `86ce18c`, `44c5d20`,
  `7f79d65`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The latest
  slice locks the background `--dev.period` tick across the standalone smoke
  boundary with mined transaction, receipt, block, and txpool cleanup evidence.
- Relevant loop state: txpool lifetime, journal, rejournal, rejournal smoke,
  dev-period deterministic tick behavior, and dev-period smoke coverage are
  closed. The next valuable block-production gap is bounded transaction
  selection under the child block gas limit.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-DEV-PERIOD-SELECTION`, making local
  dev-period block production select a bounded executable transaction set
  instead of blindly attempting every recoverable pending transaction.
- Value: high; improves executable local devnet behavior and prevents
  block-production policy from accepting an unbounded pending set.
- Risk: medium; changes mining selection policy and must preserve pending
  txpool visibility for transactions left for later blocks.
- Required validation: focused CLI/dev-period tests while iterating,
  `git diff --check`, full test suite once, and independent verifier review.
- Decision: selected.
- Reason: after the period tick and smoke boundary are closed, bounded
  transaction selection is the next directly executable Phase B behavior gap.

### Candidate B

- Objective: expose a runner-facing payload-building API that reuses local
  devnet block-construction policy.
- Value: medium-high; moves toward Engine API realism.
- Risk: medium-high; public Engine semantics and fork-specific payload fields
  need a tighter contract than the current local mining path.
- Required validation: focused Engine RPC tests, standalone devnet smoke, and
  full suite.
- Decision: defer.
- Reason: transaction selection should be bounded before sharing policy through
  a broader Engine-facing surface.

### Candidate C

- Objective: classify remaining v5.4.0 official fixture drift into passing,
  known implementation drift, out-of-scope fork/feature, and implementation
  bug-candidate groups.
- Value: medium; useful consensus map, but less directly executable than
  runner-visible devnet block production.
- Risk: low-medium; mostly scripts/docs with possible narrow fixture pins.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority still favors Phase B executable client
  behavior.

## Selected Objective

Implement `DEVNET-RUNNER-DEV-PERIOD-SELECTION`: make the local dev-period
block-production tick choose a deterministic, bounded set of executable txpool
transactions that fits the child block gas limit, while keeping non-fitting
transactions visible for later blocks.

## Scope

Allowed files/modules:

- `src/cli.lisp`
- `tests/cli-tests.lisp`
- `scripts/devnet-smoke-gate.lisp` only if process-boundary behavior changes
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- The dev-period tick orders recoverable pending transactions deterministically
  by sender/nonce/hash, or by the closest existing local ordering that preserves
  nonce correctness.
- The selected transaction set must fit within the child block gas limit.
- Transactions that do not fit remain in pending txpool views for a later
  block instead of being silently mined, dropped, or hidden.
- Mined transactions continue to be indexed with correct transaction and
  receipt lookup visibility.

Non-goals:

- Do not implement P2P mining, consensus duties, mev/payload fee auctions, or
  a full geth txpool replacement.
- Do not broaden official fixture pins in this slice.
- Do not add unbounded sleeps or process-boundary smoke changes unless the
  implementation touches listener behavior.

## Acceptance Criteria

- A focused test proves the child block gas limit bounds the dev-period
  transaction set.
- A focused test proves at least one non-fitting pending transaction remains
  visible after the tick.
- Existing single-transaction dev-period behavior and public transaction,
  receipt, and block lookup visibility remain intact.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Focused CLI/dev-period tests for transaction selection and pending leftovers.

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation before running standalone devnet or
  Phase A devnet smoke gates. Do not silently skip them.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Bound dev period transaction selection`

## Blockers

- No current git synchronization blocker.
- If existing block construction cannot leave non-fitting transactions pending
  without a txpool ownership refactor, stop with
  `BLOCKED_DEV_PERIOD_SELECTION_TXPOOL_OWNERSHIP` and document the exact
  boundary.

## Implementer Notes

- Start by reading the current dev-period tick implementation in `src/cli.lisp`
  and existing txpool ordering helpers before adding a new ordering policy.
- Keep policy deterministic and minimal; prefer preserving existing txpool
  semantics over adding a broad scheduler abstraction.
- If process-boundary behavior is unchanged, do not rerun the standalone
  devnet smoke gate for this slice.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
