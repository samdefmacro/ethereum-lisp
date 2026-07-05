# Loop Runbook

This directory defines the autonomous development loop for the Common Lisp
Ethereum execution-layer client. The loop is designed to avoid stale heartbeat
prompts by deriving each run from repository state, durable loop memory, and a
fresh task specification.

## Roles

- **Orchestrator:** reads project state and writes the next run specification.
  It does not edit implementation files or claim success for code changes.
- **Implementer:** executes one bounded task from the run specification.
  It may edit code, tests, and docs, but it must keep changes scoped.
- **Verifier:** reviews the diff, test output, and run specification with a
  code-review stance. It should use a different model from the implementer when
  possible. It may block commit/push.

The implementer must not be the only judge of success. Deterministic checks are
authoritative; model review is an additional guard, not a substitute for tests.

## Loop Health Check

Every automation that touches this loop must verify the workflow is actually
closed, not only that a prompt or run specification exists.

Required live edges:

- an orchestrator path can create or refresh `docs/loop/next-run.md`;
- an implementer path can consume a pending `docs/loop/next-run.md` and edit
  code;
- a verifier path can review implementation diffs before commit;
- a successful implementation path can commit, push, and either generate the
  next run specification or leave an explicit orchestrator wakeup.

If `docs/loop/next-run.md` has a pending implementer stop state but no active
consumer automation exists, the loop is `BLOCKED_EXTERNAL`; notify instead of
reporting `NOOP`. Do not delete the last active automation merely because the
orchestrator portion is producing no-op checks. Either convert it into a loop
driver or create the missing implementer automation first.

Loop contract documents may be dirty between orchestrator and implementer
runs. That is not implementation dirty work, but the implementer must account
for those files when staging and committing so generated run contracts do not
remain stranded indefinitely.

## Start-of-Run Protocol

Every loop run begins with a bounded orientation window:

1. Check `git status --short --branch`.
2. If `main` is behind `origin/main`, run `git pull --ff-only` before editing.
   Stop on any non-fast-forward synchronization blocker.
3. Read `docs/tasks.md`, `docs/roadmap.md`, `docs/loop/state.md`, and
   `docs/loop/validation.md`.
4. Review recent commits with `git log --oneline -12`.
5. Rank at least two plausible next slices unless a blocker makes the choice
   obvious.
6. Write or refresh `docs/loop/next-run.md` from `next-run-template.md`.

The selected slice must prefer executable client behavior over low-value local
hardening. Phase B devnet, Engine RPC process behavior, Hive/process-runner
readiness, txpool correctness, chain-store correctness, retained state, sender
recovery, persistence, and verified fixture drift classification are preferred
over mechanical fixture widening or docs-only churn.

## Dynamic Run Specification

`docs/loop/next-run.md` is the contract for one implementer pass. It should
include:

- the selected objective and why it is currently highest value;
- explicit non-goals and files/modules likely out of scope;
- expected behavior changes;
- acceptance criteria;
- narrow validation commands;
- full-suite policy, including whether the slice is Tier 0, 1, 2, or 3 under
  `docs/loop/validation.md`;
- commit/push policy;
- known blockers and escalation requirements.

If the best next step is blocked, the orchestrator writes a blocked run
specification instead of inventing unrelated work.

## Stop States

Every run must end in exactly one stop state:

- `SUCCESS_COMMITTED`: deterministic gates passed, verifier passed, work was
  committed, and push policy was satisfied.
- `SUCCESS_LOCAL_ONLY`: deterministic gates passed and verifier passed, but
  remote push was unavailable or explicitly not required.
- `NOOP`: orientation found no useful work and no state changed.
- `BLOCKED_SYNC`: git synchronization cannot fast-forward cleanly.
- `BLOCKED_VALIDATION`: required validation could not run or failed for a
  reason not fixed in the run.
- `BLOCKED_EXTERNAL`: external input, credentials, network, or local approval
  is required.
- `STALLED`: the same implementation attempt failed repeatedly without a clear
  new hypothesis.

Do not report budget exhaustion, partial tests, or model confidence as success.

## Validation Policy

For validation, apply the gate tiers in `docs/loop/validation.md`:

1. Run focused tests or smoke gates while iterating.
2. Use `git diff --check` before staging.
3. Run the full suite once before commit only for Tier 3 changes or Tier 2
   changes whose production-code risk justifies it.
4. Do not run the full suite for docs-only changes, and do not run it for
   test-only regression additions unless the verifier identifies a concrete
   broader risk.
5. Do not rerun the full suite unless it failed, a fix was made, and the rerun
   is needed to verify that fix.
6. For devnet/socket smoke gates, request the required local socket/network
   escalation before running the gate. Do not spend time on a predictable
   sandbox bind failure first.

Docs-only loop changes do not require the full suite, but they should still
avoid touching unrelated implementation files.

## Commit Policy

Commit only after the applicable deterministic gates and verifier review pass.
Do not commit unrelated dirty work. If unrelated user or previous-agent changes
are present, leave them untouched and report them separately.

Commit messages should describe the behavior or loop contract added, not the
mechanics of agent execution.
