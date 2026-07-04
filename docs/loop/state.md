# Loop State

Last updated: 2026-07-04

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

The working tree currently contains an uncommitted txpool slot-limit slice:

- `src/core.lisp`
- `src/public-rpc.lisp`
- `src/cli.lisp`
- `tests/core-tests.lisp`
- `tests/cli-tests.lisp`
- `docs/tasks.md`
- `docs/roadmap.md`

Intended behavior of that slice:

- `--txpool.accountslots` and `--txpool.globalslots` cap new pending public
  `eth_sendRawTransaction` admissions.
- Same-sender/same-nonce replacements do not consume another pending slot.
- Local senders bypass pending slot caps unless `--txpool.nolocals` disables
  local exemptions.
- Geth TOML `[Eth.TxPool] AccountSlots` and `GlobalSlots` import through the
  devnet runner config path.

Known validation status:

- `git diff --check` passed.
- A first `sbcl --script tests/run-tests.lisp` run found an accessor bug; the
  accessor was fixed.
- A second full-suite run reached and passed the new slot-limit and CLI tests,
  then failed at a known socket-gated devnet smoke path.
- The required escalated devnet smoke gate could not run because the execution
  environment rejected escalation due to a usage-limit blocker.

Do not commit or push the dirty txpool slice until the required validation
blocker is resolved or the user explicitly accepts the risk.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

Before selecting new implementation work, resolve or explicitly classify the
dirty txpool slot-limit slice:

1. If local escalation is available, run the devnet smoke gate required by
   `docs/loop/validation.md`.
2. If it passes, run verifier review, then commit and push the txpool slice.
3. If escalation is still unavailable, keep the slice uncommitted and generate
   a `BLOCKED_VALIDATION` run specification rather than stacking more code on
   top of it.

