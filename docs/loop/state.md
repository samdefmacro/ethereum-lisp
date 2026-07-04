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

No dirty implementation work is recorded by the loop. The txpool
account/global slot-limit slice was validated, independently reviewed,
committed, and pushed as `80e347b Enforce txpool slot admission limits`.

Closed behavior from that slice:

- `--txpool.accountslots` and `--txpool.globalslots` cap new pending public
  `eth_sendRawTransaction` admissions.
- Same-sender/same-nonce replacements do not consume another pending slot.
- Local senders bypass pending slot caps unless `--txpool.nolocals` disables
  local exemptions.
- Queued/basefee promotion from public raw-transaction admission respects
  pending slot caps by leaving promotable transactions parked when pending is
  full.
- Geth TOML `[Eth.TxPool] AccountSlots` and `GlobalSlots` import through the
  devnet runner config path.

Closed validation:

- `git diff --check` passed.
- `sbcl --script tests/run-tests.lisp` reached and passed the txpool
  slot-limit and related promotion tests, then failed only at the known
  sandbox socket-gated
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE` test.
- The required escalated devnet smoke gate passed:
  `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet` exited 0
  with top-level `status: ok` and devnet `status: ok`.
- Second independent verifier review passed after the queued/basefee promotion
  fix.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.

## Next Recommended Orchestrator Decision

The next implementation run should start from the refreshed
`docs/loop/next-run.md`. Current best slice is to make the remaining
geth/Hive txpool lifetime runner knob affect real public txpool eviction
behavior, because it advances executable devnet/txpool behavior and closes a
documented Phase B partial gap without depending on external KZG libraries.
