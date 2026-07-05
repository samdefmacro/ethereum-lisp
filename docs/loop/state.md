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

No dirty implementation work is recorded by the loop. The txpool journal slice
has been implemented, validated, independently reviewed, and closed by the
current run.

Closed behavior from the latest slice:

- `--txpool.journal PATH` parses as a real path-bearing devnet option.
- Geth TOML `[Eth.TxPool] Journal` imports through the same runner config
  path, with explicit CLI flags taking precedence.
- Devnet summaries, readiness data, and lifecycle telemetry report
  `txpoolJournalPath`.
- Clean no-serve summary export and serve shutdown export write current txpool
  records to the configured txpool-only KV journal.
- Startup imports existing journal txpool records after genesis/database
  restore only when database restore has not already populated txpool state,
  avoiding duplicate pooled hash/nonce failures when `--database` and
  `--txpool.journal` point at the same previously exported pool.
- Journal import reuses the existing KV txpool validation path and
  restored-txpool consistency cleanup, so wrong-chain journal records fail
  before publishing restored txpool contents.

Closed validation:

- Focused journal/config tests passed:
  `DEVNET-CLI-TXPOOL-JOURNAL-PERSISTS-PENDING-TRANSACTIONS`,
  `DEVNET-CLI-TXPOOL-JOURNAL-COEXISTS-WITH-DATABASE-RESTORE`,
  `DEVNET-CLI-TXPOOL-JOURNAL-REJECTS-WRONG-CHAIN-TRANSACTIONS`,
  `DEVNET-CLI-MAIN-APPLIES-GETH-CONFIG-FILE-VALUES`, and
  `DEVNET-CLI-MAIN-ACCEPTS-GETH-STYLE-TXPOOL-AND-DATABASE-FLAGS`.
- `git diff --check` passed after the final doc refresh.
- `sbcl --script tests/run-tests.lisp` was run once for this implementation
  batch and failed only at the known sandbox socket-gated
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` test.
- The required escalated devnet smoke gate passed:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level `status: ok` and devnet `status: ok`.
- Independent verifier review returned `PASS` for the initial journal diff.
  After the database-plus-journal duplicate-import boundary was added, an
  incremental verifier review also returned `PASS`.

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
`DEVNET-RUNNER-TXPOOL-REJOURNAL`. Do not continue the completed txpool journal
task. Prefer Phase B devnet/Engine/process-runner readiness or
txpool/chain-store correctness unless orientation finds a higher-value
executable-client issue.
