# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `PENDING_IMPLEMENTER`

## Orientation Summary

- Git state: implementation commit `86ce18c` completed the previous
  `DEVNET-RUNNER-TXPOOL-REJOURNAL-SMOKE` slice locally; next-run generation is
  docs-only follow-up work.
- Recent commits reviewed: `86ce18c`, `44c5d20`, `7f79d65`, `df4afd2`,
  `ced7535`.
- Relevant task/roadmap anchors: Phase B local devnet / Engine RPC
  process-runner readiness remains the highest-value roadmap track. The
  roadmap explicitly records `--dev.period` as a compatibility no-op until
  block-production timing is implemented.
- Relevant loop state: txpool lifetime, journal, rejournal, and rejournal
  smoke coverage are closed. Do not continue those completed tasks.

## Candidate Ranking

### Candidate A

- Objective: implement `DEVNET-RUNNER-DEV-PERIOD-TICK`, giving
  `--dev.period` a deterministic local block-production tick.
- Value: high; moves the devnet from passive Engine/import testing toward a
  usable local execution client that can admit public transactions and advance
  chain state itself.
- Risk: medium-high; touches devnet lifecycle, block construction, public RPC
  visibility, txpool mined-transaction cleanup, and possibly background
  scheduler shutdown.
- Required validation: focused CLI/core public-RPC tests, `git diff --check`,
  full test suite once, and escalated devnet smoke if listener/process behavior
  is wired in this slice.
- Decision: selected.
- Reason: best alignment with executable client behavior and the Phase B
  roadmap after closing txpool runner knobs.

### Candidate B

- Objective: classify remaining v5.4.0 official fixture drift into passing,
  known implementation drift, out-of-scope fork/feature, and implementation
  bug-candidate groups.
- Value: medium; useful map for future consensus coverage but less directly
  executable than local devnet block production.
- Risk: low-medium; mostly scripts/docs, with possible narrow fixture pins.
- Required validation: fixture classifier smoke and Phase A smoke gate when
  selectors change.
- Decision: defer.
- Reason: current strategic priority prefers Phase B executable behavior.

### Candidate C

- Objective: broaden txpool eviction policy beyond the existing lifetime,
  canonical nonce/basefee/blob/gas-limit, local, and slot/queue coverage.
- Value: medium-high; txpool correctness remains important for a usable client.
- Risk: medium; meaningful policy choices require careful reference-client
  comparison.
- Required validation: focused txpool admission/promotion tests plus full suite.
- Decision: defer.
- Reason: current txpool runner knobs are saturated enough that devnet block
  production is now a higher-leverage vertical slice.

## Selected Objective

Implement `DEVNET-RUNNER-DEV-PERIOD-TICK`: make positive `--dev.period`
schedule or expose a deterministic devnet mining tick that can seal a local
block containing pending public txpool transactions.

## Scope

Allowed files/modules:

- `src/cli.lisp`
- `src/core.lisp`
- `src/public-rpc.lisp`
- `tests/cli-tests.lisp`
- `tests/core-tests.lisp`
- `scripts/devnet-smoke-gate.lisp` only if the process-boundary smoke can be
  kept bounded and deterministic in this slice
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Positive `--dev.period` is parsed as a real non-negative duration and
  reported as an effective dev-period setting in summaries, readiness data, and
  lifecycle telemetry.
- A deterministic scheduler/tick path can construct, execute, commit, and index
  one local block from currently pending executable txpool transactions on top
  of the current devnet head.
- Public `latest` block/state and transaction/receipt lookup APIs observe the
  newly sealed block.
- Mined transactions are removed from pending txpool visibility after sealing.

Non-goals:

- Do not implement production PoW/PoS consensus, peer networking, proposer
  duties, or real timestamp policy beyond the local devnet tick needed here.
- Do not change Engine API payload import semantics unless necessary to reuse
  existing block construction boundaries.
- Do not introduce wall-clock-only sleeps in tests when an injectable tick or
  bounded smoke wait can prove behavior.
- Do not widen official fixtures in this slice.

## Acceptance Criteria

- `--dev.period DURATION` rejects malformed/negative values through the same
  duration parser style used by txpool durations.
- Devnet summaries/readiness/telemetry expose the effective dev period.
- A focused deterministic test submits a public raw transaction, runs the dev
  period tick, then verifies:
  - public `eth_blockNumber` or equivalent latest-head state advances;
  - the transaction has a block hash/number/index through public lookup;
  - the transaction receipt is indexed;
  - pending txpool views no longer expose the mined transaction.
- If a background serve-mode scheduler is wired in this slice, it must be
  shutdown-aware and have a bounded smoke validation path.
- Docs reflect only actual status changes.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Focused gates:

- Run focused CLI/core tests for dev-period parsing/reporting and deterministic
  block-production tick behavior.
- If listener/process behavior changes, run escalated:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- Request local socket/network escalation before running any devnet/socket
  smoke gate. Do not silently skip it.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Implement dev period mining tick`

## Blockers

- No current git synchronization blocker.
- If local socket/network escalation is unavailable for required process smoke,
  stop with `BLOCKED_SOCKET_ESCALATION` and record the exact unrun command.
- If existing block construction APIs cannot safely seal a local txpool block
  without a large refactor, stop with `BLOCKED_DEV_PERIOD_BLOCK_CONSTRUCTION`
  and document the precise missing boundary instead of forcing broad churn.

## Implementer Notes

- Prefer reusing existing prepared-payload, block execution, txpool mined
  removal, and public RPC indexing paths before adding new block-construction
  machinery.
- Keep the first slice narrow: one deterministic tick that seals one
  txpool-backed block is enough if the background periodic scheduler would make
  the change too broad.
- Preserve the existing Engine/public RPC separation and shutdown contracts.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
