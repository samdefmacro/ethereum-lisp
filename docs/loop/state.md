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

No dirty implementation work is recorded by the loop. The txpool rejournal
slice has been implemented, validated, independently reviewed, and is pending
commit and push in the current run.

Closed behavior from the latest slice:

- `--txpool.rejournal DURATION` parses as a meaningful non-negative duration
  rather than a compatibility-only consumed value.
- Geth TOML `[Eth.TxPool] Rejournal` imports through the runner config path,
  with explicit CLI flags taking precedence.
- Devnet summaries, readiness data, and lifecycle telemetry report
  `txpoolRejournalSeconds`.
- When both `--txpool.journal` and a positive rejournal interval are
  configured, serve mode starts a shutdown-aware background tick that refreshes
  the same txpool-only KV journal export used by clean shutdown.
- No-journal behavior remains a no-op, and zero/nil rejournal intervals do not
  start the periodic refresh path.

Closed validation:

- Focused rejournal/journal/config tests passed:
  `DEVNET-CLI-TXPOOL-REJOURNAL-REFRESHES-LIVE-JOURNAL`,
  `DEVNET-CLI-TXPOOL-REJOURNAL-WITHOUT-JOURNAL-IS-NOOP`,
  `DEVNET-CLI-TXPOOL-JOURNAL-PERSISTS-PENDING-TRANSACTIONS`,
  `DEVNET-CLI-MAIN-JSON-SUMMARY-AND-READY-FILE`,
  `DEVNET-CLI-MAIN-APPLIES-GETH-CONFIG-FILE-VALUES`, and
  `DEVNET-CLI-MAIN-EXPLICIT-OPTIONS-OVERRIDE-GETH-CONFIG-FILE`,
  `DEVNET-CLI-MAIN-ACCEPTS-GETH-STYLE-TXPOOL-AND-DATABASE-FLAGS`.
- `git diff --check` passed after the final doc refresh.
- `sbcl --script tests/run-tests.lisp` was run once for this implementation
  batch and failed only at the known sandbox socket-gated
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` test.
- The required escalated devnet smoke gate passed:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level, devnet, and engine-only devnet `status: ok`.
- Independent verifier review returned `PASS`; its only residual risk was the
  real process-boundary smoke coverage now captured as
  `DEVNET-RUNNER-TXPOOL-REJOURNAL-SMOKE`.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

After this commit, the next loop run should consume the refreshed
`docs/loop/next-run.md` as an implementer contract for
`DEVNET-RUNNER-TXPOOL-REJOURNAL-SMOKE`. Do not continue the completed txpool
journal or rejournal implementation tasks. Prefer Phase B
devnet/Engine/process-runner readiness or txpool/chain-store correctness
unless orientation finds a higher-value executable-client issue.
