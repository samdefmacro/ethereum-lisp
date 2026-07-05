# Loop State

Last updated: 2026-07-05

## Project State

- The repository target is a usable Common Lisp Ethereum execution-layer
  client.
- Phase A's bounded in-repo chain-import smoke path is documented as closed for
  the current Shanghai fixture set.
- Current highest strategic priority is Phase B local devnet, Engine/public RPC
  process behavior, Hive/process-runner readiness, and txpool/chain-store
  correctness that affects executable client behavior.
- Official execution-spec-tests v5.4.0 stable fixtures are expected at
  `.cache/eest-v5.4.0/root/fixtures` with archive SHA256
  `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`.

## Current Dirty Work

No dirty implementation work is recorded by the loop. The txpool lifetime
slice has been implemented, validated, independently reviewed, and closed by
the current run.

Closed behavior from the latest slice:

- `--txpool.lifetime` parses bare seconds and geth-style composite
  `d`/`h`/`m`/`s` durations such as `3h0m0s`.
- Geth TOML `[Eth.TxPool] Lifetime` imports through the devnet runner config
  path, with explicit CLI flags taking precedence.
- Devnet summaries, readiness data, and lifecycle telemetry report
  `txpoolLifetimeSeconds`.
- Public txpool cleanup deterministically removes stale queued/basefee/blob
  entries before public txpool and transaction hash views expose them.
- Pending executable transactions remain visible even when older than the
  configured lifetime.
- Same-sender replacement transactions refresh their effective age.

Closed validation:

- `sbcl --noinform --non-interactive --load tests/load-tests.lisp --eval
  '(quit)'` passed after the final parser update, with existing style warnings.
- Focused tests passed after the final parser update:
  `DEVNET-CLI-MAIN-APPLIES-GETH-CONFIG-FILE-VALUES`,
  `DEVNET-CLI-MAIN-EXPLICIT-OPTIONS-OVERRIDE-GETH-CONFIG-FILE`,
  `DEVNET-CLI-MAIN-ACCEPTS-GETH-STYLE-TXPOOL-AND-DATABASE-FLAGS`, and
  `ETH-RPC-TXPOOL-LIFETIME-EXPIRES-QUEUED-VIEW-TRANSACTIONS`.
- `git diff --check` passed.
- `sbcl --script tests/run-tests.lisp` was run once for this implementation
  batch before the final parser refinement. It reached and passed the new
  txpool lifetime and CLI tests, then failed only at the known sandbox
  socket-gated
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` test.
- The required escalated devnet smoke gate passed:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level `status: ok` and devnet `status: ok`.
- Independent verifier review initially found the missing geth-style composite
  duration support; after the parser/test fix, verifier status was `PASS`.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

The next loop run should start from the refreshed `docs/loop/next-run.md` and
perform fresh orientation before selecting another implementation slice. Do not
continue the completed txpool lifetime task. Prefer Phase B
devnet/Engine/process-runner readiness or txpool/chain-store correctness unless
orientation finds a higher-value executable-client issue.
