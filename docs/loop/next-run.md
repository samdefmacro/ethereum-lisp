# Next Run

## Run Metadata

- Date: 2026-07-04
- Orchestrator model: Codex
- Implementer model: recommended default implementer model
- Verifier model: different model from implementer when available
- Target branch: `main`
- Stop state: pending implementer; the implementer must end in exactly one
  runbook stop state, preferably `SUCCESS_COMMITTED`

## Orientation Summary

- Git state: `main` is aligned with `origin/main`; dirty files are the
  orchestrator-generated loop contract updates in `docs/loop/next-run.md`,
  `docs/loop/state.md`, and `docs/tasks.md`. No dirty implementation files
  were reported during orientation.
- Recent commits reviewed:
  - `80e347b Enforce txpool slot admission limits`
  - `d8b0d07 Add autonomous development loop docs`
  - `70158f2 Honor txpool local exemptions`
  - `987e4ed Enforce txpool queue limit admission`
  - `d430af9 Enforce txpool price bump admission`
  - `db1bcbb Enforce txpool price limit admission`
  - `5bf1423 Enforce unprotected RPC transaction flag`
  - `fc9aea4 Import miner gas limit from geth config`
  - `c5a04f2 Honor disabled HTTP host in geth config`
  - `5c63dd3 Parse geth config for devnet runners`
  - `9ef6a7b Accept geth chain preset runner flags`
  - `b296db7 Accept geth config flag in devnet CLI`
- Relevant task/roadmap anchors:
  - `DEVNET-RUNNER-TXPOOL-LIFETIME` is now the active unchecked task.
  - Roadmap Section 7 still lists txpool policy beyond the current in-memory
    pending pool, including lifetime/eviction knobs, as partial.
  - Real KZG verification remains the only broad explicit unchecked task, but
    it needs an external trusted backend decision before it is the best default
    implementation slice.
- Relevant loop state:
  - The previous txpool slot-limit slice is closed, validated, independently
    reviewed, committed, and pushed as `80e347b`.
  - Current strategic preference remains Phase B devnet/Engine/process-runner
    readiness and executable txpool behavior over fixture widening.

## Candidate Ranking

### Candidate A

- Objective: Make `--txpool.lifetime` affect real public txpool eviction for
  stale queued-view transactions.
- Value: High. It closes a documented Phase B txpool policy gap, turns another
  geth/Hive runner flag from compatibility parsing into behavior, and affects
  public RPC visibility in devnet scenarios.
- Risk: Medium. The implementation may need deterministic admission-time
  metadata and cleanup boundaries across pending, queued, basefee, blob, and
  hash lookup views.
- Required validation:
  - focused txpool and CLI tests while iterating;
  - `git diff --check`;
  - `sbcl --script tests/run-tests.lisp` once before commit;
  - escalated `sbcl --script scripts/devnet-smoke-gate.lisp -- --json` if
    listener/process-reporting behavior changes.
- Decision: Selected.
- Reason: It is the highest-value unblocked executable-client slice found by
  orientation and aligns with Phase B devnet/Hive txpool readiness.

### Candidate B

- Objective: Integrate real KZG proof verification.
- Value: High for Cancun/blob acceptance and future Engine capability
  advertisement.
- Risk: High. It requires selecting or providing a trusted backend/library and
  trusted setup path; the current command-backed verifier hook is present, but
  a default real backend is an external dependency decision.
- Required validation:
  - KZG proof-vector coverage;
  - blob sidecar validation tests;
  - Engine capability negotiation tests;
  - full suite.
- Decision: Deferred.
- Reason: Valuable but externally constrained. Do not make it the default
  automation slice without a concrete backend input.

### Candidate C

- Objective: Classify remaining official v5.4.0 fixture drift.
- Value: Medium. It improves the map of upstream/pinned gaps.
- Risk: Low to medium.
- Required validation:
  - selector probe/classifier output against
    `.cache/eest-v5.4.0/root/fixtures`;
  - pinned smoke gate only if pinned tables change.
- Decision: Deferred.
- Reason: Useful, but lower priority than executable Phase B txpool behavior
  now that the local devnet/process surface is the strategic focus.

## Selected Objective

Implement deterministic txpool lifetime eviction for stale queued-view public
transactions, wired from `--txpool.lifetime` and geth TOML config into the
devnet/public-RPC txpool path.

## Scope

Allowed files/modules:

- `src/core.lisp`
- `src/public-rpc.lisp`
- `src/cli.lisp`
- `tests/core-tests.lisp`
- `tests/cli-tests.lisp`
- `scripts/devnet-smoke-gate.lisp` only if the behavior must be visible in the
  socket/process smoke report
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Parse `--txpool.lifetime DURATION` as a non-negative duration and reject
  malformed values deterministically.
- Import geth TOML `[Eth.TxPool] Lifetime` when present, with explicit CLI
  flags taking precedence.
- Report the effective txpool lifetime in devnet JSON summaries, ready files,
  and lifecycle telemetry when configured.
- Track deterministic admission age for public txpool entries without tests
  depending on wall-clock sleeps.
- Expire stale queued-view entries from queued/basefee/blob subpools before
  public txpool views and hash lookup expose them.
- Do not expire executable pending transactions in this slice.
- Same-sender/same-nonce replacements should refresh the entry's effective
  age.

Non-goals:

- Do not implement txpool journaling or `--txpool.rejournal`.
- Do not add block production, mining, or periodic background cleanup.
- Do not change pending slot/queue/price/local exemption semantics except where
  needed to preserve lifetime cleanup correctness.
- Do not start real KZG integration.
- Do not widen pinned fixture tables.

## Acceptance Criteria

- `--txpool.lifetime` accepts documented duration forms already supported by
  the CLI compatibility parser or adds one consistent parser used by tests.
- Malformed lifetime values fail with a specific diagnostic.
- Config-file lifetime import and CLI override precedence are covered.
- Public txpool status/content/inspect/hash views no longer expose stale
  queued-view entries after deterministic cleanup.
- Pending executable entries remain visible even when older than the configured
  lifetime.
- Replacements refresh age and are not immediately evicted because of the
  replaced transaction's old timestamp.
- `docs/tasks.md`, `docs/roadmap.md`, and `docs/loop/state.md` are updated only
  for actual status changes.
- A verifier reviews the final diff against this run specification before
  commit.

## Validation Plan

Focused gates:

- Add and run focused txpool/CLI tests if a local narrow test entrypoint exists;
  otherwise rely on the full suite once after implementation.
- Use deterministic injected time or explicit admission timestamps in tests.

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Escalation requirements:

- If the implementation changes listener/process-runner reporting or the
  standalone devnet smoke report, request local socket/network escalation for:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`
- Do not silently skip a required socket gate.

## Commit And Push Policy

- Commit allowed: yes, only after deterministic gates and verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Expire stale txpool queued transactions`

## Blockers

- No current git synchronization blocker.
- KZG integration remains blocked on concrete trusted-backend selection, but it
  does not block this txpool lifetime slice.

## Implementer Notes

- Keep the slice vertical and bounded: CLI/config parsing, core txpool cleanup,
  public RPC visibility, and tests.
- Prefer deterministic cleanup at public RPC/admission boundaries over a
  background timer; long-running scheduling is outside this slice.
- Be careful with local transaction exemptions: lifetime behavior should be
  specified and tested explicitly if local entries are affected. If existing
  geth semantics are unclear from local code, preserve local entries unless the
  implementation can justify expiring them.
- Avoid wall-clock sleeps in tests. Add an injectable clock or metadata helper
  if needed.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
