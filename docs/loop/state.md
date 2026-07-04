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
- Independent verifier review then found a pending slot-cap bypass in
  queued/basefee promotion. The promotion path was fixed to re-park
  transactions when pending slot caps are full, and regression tests were added
  for queued-first account/global slot-cap promotion.
- After that fix, `sbcl --script tests/run-tests.lisp` reached and passed the
  txpool slot-limit and related promotion tests, then failed only at the known
  sandbox socket-gated
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` test.
- The required escalated devnet smoke gate was run again successfully:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level `status: ok` and devnet `status: ok`.
- Second independent verifier review passed after the queued/basefee promotion
  fix.

The dirty txpool slice is ready to commit and push.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

After the txpool slot-limit slice is committed and pushed:

1. Generate a fresh `docs/loop/next-run.md`.
2. Prefer the next Phase B local devnet / Engine RPC process behavior or
   Hive/process-runner readiness slice unless orientation finds a higher-value
   executable-client correctness issue.
3. Keep fixture widening as a fallback unless it is part of explicit drift
   classification.
