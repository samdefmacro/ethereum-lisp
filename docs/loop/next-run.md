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
  `DEVNET-RUNNER-DEV-PERIOD-MULTI-SENDER-SELECTION`.
- Recent commits reviewed in the previous run: `a2f067c`, `3ae54ca`,
  `d09fbce`, `c787e9f`, and `86ce18c`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The latest
  slice makes dev-period txpool selection deterministic, gas-limited, and
  sender-aware without changing listener/process behavior.
- Relevant loop state: txpool lifetime, journal, rejournal, rejournal smoke,
  dev-period deterministic tick behavior, dev-period smoke coverage,
  gas-bounded dev-period selection, and sender-aware multi-sender dev-period
  selection are closed. The next useful block-production gap is using that
  local selection policy for Engine prepared payloads returned by
  `engine_getPayload*`.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-PREPARED-PAYLOAD-TXPOOL-SELECTION`,
  reusing local devnet txpool selection when authenticated Engine payload
  attributes prepare payloads.
- Value: high; it moves the same executable local block-production behavior
  from the background dev-period tick into the Engine process-runner workflow
  Hive-style clients exercise.
- Risk: medium-high; prepared-payload caching and later import/forkchoice
  visibility must stay consistent, and non-selected txpool transactions must
  remain visible until a prepared payload is actually imported.
- Required validation: focused Engine RPC prepared-payload tests with pending
  txpool transactions, `git diff --check`, full suite once, and independent
  verifier review.
- Decision: selected.
- Reason: after the mining selection policy is bounded and sender-aware, the
  next runner-visible gap is sharing it with the authenticated Engine payload
  preparation path instead of leaving prepared payloads empty.

### Candidate B

- Objective: add focused no-fitting-first-transaction coverage for dev-period
  selection.
- Value: low-medium; it locks a residual edge from the previous selector
  slices.
- Risk: low; pure focused CLI coverage.
- Required validation: focused CLI/dev-period test and full suite if code
  changes.
- Decision: defer.
- Reason: the edge follows from the existing selector structure and is less
  valuable than moving selection into Engine prepared payloads.

### Candidate C

- Objective: classify remaining v5.4.0 official fixture drift into passing,
  known implementation drift, out-of-scope fork/feature, and implementation
  bug-candidate groups.
- Value: medium; useful consensus map, but less directly executable than
  runner-visible Engine/devnet block production.
- Risk: low-medium; mostly scripts/docs with possible narrow fixture pins.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority still favors Phase B executable client
  behavior.

## Selected Objective

Implement `DEVNET-RUNNER-PREPARED-PAYLOAD-TXPOOL-SELECTION`: when local devnet
Engine RPC receives payload attributes through `engine_forkchoiceUpdated*`,
prepared payload construction should use the same deterministic, gas-limited,
nonce-safe public txpool selection policy as dev-period mining, so
`engine_getPayload*` can return txpool-backed local payloads.

## Scope

Allowed files/modules:

- `src/core.lisp`
- `src/cli.lisp`
- `tests/core-tests.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Prepared payload construction for local devnet payload attributes can include
  recoverable public txpool transactions selected by the current deterministic
  gas-limited, sender-aware policy.
- `engine_getPayload*` returns the selected transaction list for the prepared
  payload.
- Transactions selected into a prepared payload remain in public txpool views
  until the payload is imported/forkchoiced through the existing Engine flow.
- Non-selected transactions remain visible in public txpool views.
- Empty-payload workflows remain valid when no pending transaction fits.

Non-goals:

- Do not implement P2P mining, consensus duties, mev/payload fee auctions, or
  a full geth txpool replacement.
- Do not broaden official fixture pins in this slice.
- Do not change listener lifecycle, JWT auth, public/Engine namespace
  separation, or standalone smoke behavior unless the implementation truly
  crosses a process boundary.

## Acceptance Criteria

- A focused Engine RPC test proves a prepared payload can include at least one
  pending public txpool transaction and `engine_getPayload*` returns it.
- A focused test proves non-selected pending transactions remain public-txpool
  visible before the prepared payload is imported.
- Existing empty prepared-payload Engine workflows remain intact.
- Existing dev-period sender-aware selection behavior remains intact.
- Full suite passes once after implementation.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Focused Engine RPC prepared-payload tests for txpool-backed payload contents
  and pending leftovers.
- Focused dev-period selection test if shared selection code moves.

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
- Commit message: `Select txpool transactions for prepared payloads`

## Blockers

- No current git synchronization blocker.
- If prepared-payload caching cannot safely reference txpool-selected
  transactions without changing import/forkchoice ownership semantics, stop
  with `BLOCKED_PREPARED_PAYLOAD_TXPOOL_OWNERSHIP` and document the exact
  boundary.

## Implementer Notes

- Start by locating current prepared-payload construction and cache storage.
- Prefer reusing or extracting the dev-period selection policy rather than
  creating a second divergent scheduler.
- Keep selected transactions in txpool until import/forkchoice removes them
  through the existing mined-transaction path.
- If process-boundary behavior is unchanged, do not rerun standalone devnet
  smoke for this slice.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
