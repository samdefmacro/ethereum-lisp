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
- full-suite policy;
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

For non-doc code changes:

1. Run focused tests or smoke gates while iterating.
2. Run `sbcl --script tests/run-tests.lisp` once before commit.
3. Do not rerun the full suite unless it failed, a fix was made, and the rerun
   is needed to verify that fix.
4. For devnet/socket smoke gates, request the required local socket/network
   escalation. Do not silently skip the gate.
5. Use `git diff --check` before staging.

Docs-only loop changes do not require the full suite, but they should still
avoid touching unrelated implementation files.

## Commit Policy

Commit only after the applicable deterministic gates and verifier review pass.
Do not commit unrelated dirty work. If unrelated user or previous-agent changes
are present, leave them untouched and report them separately.

Commit messages should describe the behavior or loop contract added, not the
mechanics of agent execution.

