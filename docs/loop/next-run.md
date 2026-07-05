# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: Codex
- Implementer model: recommended default implementer model
- Verifier model: different model from implementer when available
- Target branch: `main`
- Stop state: pending orchestrator; the next loop run must perform fresh
  orientation before selecting another implementation slice.

## Previous Run Result

- Completed objective: `DEVNET-RUNNER-TXPOOL-LIFETIME`
- Stop state: `SUCCESS_COMMITTED` once the current implementation commit is
  created and pushed.
- Behavior delivered:
  - `--txpool.lifetime` parses bare seconds and geth-style composite
    `d`/`h`/`m`/`s` durations such as `3h0m0s`.
  - Geth TOML `[Eth.TxPool] Lifetime` imports through the existing devnet
    config path, with explicit CLI flags taking precedence.
  - Devnet summaries, readiness data, and lifecycle telemetry report
    `txpoolLifetimeSeconds`.
  - Public txpool cleanup deterministically removes stale queued/basefee/blob
    entries before public txpool and transaction hash views expose them.
  - Pending executable transactions remain visible even when older than the
    configured lifetime.
  - Same-sender replacement transactions refresh their effective age.

## Validation Summary

- `sbcl --noinform --non-interactive --load tests/load-tests.lisp --eval
  '(quit)'` passed after the final parser update, with existing style warnings.
- Focused tests passed after the final parser update:
  - `DEVNET-CLI-MAIN-APPLIES-GETH-CONFIG-FILE-VALUES`
  - `DEVNET-CLI-MAIN-EXPLICIT-OPTIONS-OVERRIDE-GETH-CONFIG-FILE`
  - `DEVNET-CLI-MAIN-ACCEPTS-GETH-STYLE-TXPOOL-AND-DATABASE-FLAGS`
  - `ETH-RPC-TXPOOL-LIFETIME-EXPIRES-QUEUED-VIEW-TRANSACTIONS`
- `git diff --check` passed.
- `sbcl --script tests/run-tests.lisp` was run once for this implementation
  batch before the final parser refinement. It reached and passed the new
  txpool lifetime and CLI coverage, then failed only at the known sandbox
  socket-gated `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` gate.
- The required escalated socket gate passed:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level and devnet `status: ok`.
- Independent verifier review initially found the missing geth-style composite
  duration support; after the parser/test fix, verifier status was `PASS`.

## Next Orchestrator Instructions

The next loop run must not continue this completed lifetime slice. It should:

1. Run the standard start-of-run protocol from `docs/loop/runbook.md`.
2. Check `git status --short --branch` and recent commits.
3. Read `docs/tasks.md`, `docs/roadmap.md`, `docs/loop/state.md`, and
   `docs/loop/validation.md`.
4. Rank plausible next slices by value, risk, validation cost, and roadmap
   alignment.
5. Prefer executable Phase B devnet/Engine/process-runner readiness or
   txpool/chain-store correctness over fixture widening or docs-only churn.
6. Generate a fresh one-run contract in this file before any new
   implementation work begins.

## Known Constraints

- Real KZG integration remains valuable but should wait for a concrete trusted
  backend/library decision unless orientation finds that decision already made.
- Official v5.4.0 fixtures remain expected at
  `.cache/eest-v5.4.0/root/fixtures` with archive SHA256
  `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`.
- Devnet/socket gates require local socket/network escalation and must not be
  silently skipped when selected behavior depends on process boundaries.
