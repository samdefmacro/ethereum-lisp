# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: the previous run is expected to have committed and pushed
  `DEVNET-RUNNER-DEV-PERIOD-SELECTION`.
- Recent commits reviewed in the previous run: `3ae54ca`, `d09fbce`,
  `c787e9f`, `86ce18c`, and `44c5d20`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The latest
  slice bounds dev-period transaction selection by the child block gas limit
  before block execution.
- Relevant loop state: txpool lifetime, journal, rejournal, rejournal smoke,
  dev-period deterministic tick behavior, dev-period smoke coverage, and
  gas-bounded dev-period prefix selection are closed. The next useful
  block-production gap is fuller deterministic selection across independent
  senders without violating per-sender nonce order.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-DEV-PERIOD-MULTI-SENDER-SELECTION`,
  letting local dev-period mining continue with another sender's nonce-safe
  fitting transaction when the current sender's head transaction would exceed
  the remaining block gas.
- Value: high; improves executable local devnet block production while keeping
  the txpool-visible gas-limit behavior closed in the previous slice.
- Risk: medium; selection must preserve per-sender nonce ordering and must not
  hide transactions left for later blocks.
- Required validation: focused CLI/dev-period multi-sender tests,
  `git diff --check`, full test suite once, and independent verifier review.
- Decision: selected.
- Reason: it is the closest executable Phase B follow-up to the gas-bounded
  prefix behavior and moves local devnet mining closer to usable process-runner
  behavior.

### Candidate B

- Objective: expose a runner-facing payload-building API that reuses local
  devnet block-construction policy.
- Value: medium-high; moves toward Engine API realism.
- Risk: medium-high; public Engine semantics and fork-specific payload fields
  need a tighter contract than the current local mining path.
- Required validation: focused Engine RPC tests, standalone devnet smoke if
  process behavior changes, and full suite.
- Decision: defer.
- Reason: transaction selection policy should be more complete before sharing
  it through a broader Engine-facing surface.

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

Implement `DEVNET-RUNNER-DEV-PERIOD-MULTI-SENDER-SELECTION`: improve local
dev-period block production so bounded selection can continue across
independent senders when one sender's next nonce-safe transaction does not fit,
while preserving per-sender nonce order and public txpool visibility for all
non-selected transactions.

## Scope

Allowed files/modules:

- `src/cli.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Dev-period mining groups or otherwise reasons about recoverable pending
  transactions by sender so nonce order is preserved per sender.
- If one sender's head transaction exceeds the remaining child block gas, the
  selector may continue to another sender's head transaction that fits.
- The selected transaction set must still fit within the child block gas limit.
- Non-selected transactions remain visible through pending txpool/public hash
  views for later blocks.
- Mined transactions continue to be indexed with correct transaction and
  receipt lookup visibility.

Non-goals:

- Do not implement P2P mining, consensus duties, mev/payload fee auctions, or
  a full geth txpool replacement.
- Do not broaden official fixture pins in this slice.
- Do not change listener lifecycle or standalone smoke behavior unless the
  implementation truly crosses a process boundary.

## Acceptance Criteria

- A focused test proves a fitting transaction from a second sender can be mined
  after a first sender's next transaction does not fit the remaining gas.
- A focused test or assertion proves same-sender nonce order is not violated.
- Non-selected transactions remain visible in pending txpool views and by
  transaction hash after the tick.
- Existing single-sender gas-bounded selection and single-transaction
  dev-period behavior remain intact.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Focused CLI/dev-period tests for multi-sender selection, nonce safety, and
  pending leftovers.

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
- Commit message: `Pack dev period transactions by sender`

## Blockers

- No current git synchronization blocker.
- If the existing txpool representation cannot recover sender identity or
  preserve nonce-safe grouping without a broad ownership refactor, stop with
  `BLOCKED_DEV_PERIOD_MULTI_SENDER_TXPOOL_ORDERING` and document the exact
  boundary.

## Implementer Notes

- Start from the current `devnet-node-pending-mining-transactions` ordering and
  `devnet-node-select-mining-transactions` gas-bounding path.
- Keep the selector deterministic and local to dev-period mining; do not
  change txpool admission policy unless a concrete correctness boundary
  requires it.
- If process-boundary behavior is unchanged, do not rerun the standalone
  devnet smoke gate for this slice.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
