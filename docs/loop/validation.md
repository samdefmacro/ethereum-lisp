# Loop Validation

This file defines validation gates that loop agents should reference when
generating `docs/loop/next-run.md`.

## Common Gates

- Formatting/patch hygiene:
  - `git diff --check`
- Full Lisp test suite for broad or production-code batches:
  - `sbcl --script tests/run-tests.lisp`
- Phase A fixture/import smoke:
  - `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json`
- Phase A plus devnet smoke:
  - `sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet`
- Standalone devnet smoke:
  - `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`

Devnet/socket gates require local socket/network escalation. If escalation is
unavailable, mark the run `BLOCKED_VALIDATION` unless the selected slice has a
different sufficient deterministic gate.

## Gate Tiers

Use the narrowest deterministic gate that proves the selected slice. Do not
spend an implementation run's main budget revalidating unrelated subsystems
when the diff is test-only, docs-only, or a narrowly scoped smoke-harness
assertion.

- Tier 0 docs-only loop/process changes:
  - run `git diff --check`;
  - do not run the full suite.
- Tier 1 test-only regressions or classifier/report assertion changes:
  - run the new or changed test directly, if callable;
  - run `git diff --check`;
  - verifier review may approve commit without a full suite when no production
    code changed and the focused gate proves the acceptance criteria.
- Tier 2 narrow implementation changes:
  - run focused unit, CLI, fixture, or smoke coverage for the behavior;
  - run `git diff --check`;
  - run the full suite only when the touched production path is shared,
    consensus-critical, persistence-affecting, or lacks a narrow deterministic
    gate.
- Tier 3 process-boundary, listener, database, or consensus-surface changes:
  - run the focused escalated smoke gate first;
  - run `git diff --check`;
  - run the full suite once before commit.

When a run needs devnet/socket coverage, request local socket/network
escalation before the focused gate instead of first running the same gate in
the sandbox and rerunning after a predictable bind failure.

## Gate Selection

- Pinned fixture widening or drift classification:
  - run the relevant selector probe or classifier;
  - run `scripts/phase-a-smoke-gate.lisp` with the pinned v5.4.0 root when the
    pinned table changes;
  - run the full test suite once before commit only when production code or
    pinned selector behavior changed.
- Devnet/process-runner behavior:
  - run the narrow devnet smoke gate or a focused CLI/process test while
    iterating;
  - request local socket/network escalation before the devnet/socket gate;
  - run the full test suite once before commit for listener lifecycle,
    authenticated Engine/public RPC separation, persistence, shutdown, or
    production runner behavior changes;
  - for smoke-report assertion-only changes, focused escalated smoke plus
    verifier review is sufficient unless the verifier identifies broader risk;
  - run an escalated devnet/socket smoke gate before commit when listener,
    readiness, shutdown, Engine/public separation, or process-boundary behavior
    changed.
- Txpool, chain-store, retained-state, sender-recovery, or persistence
  correctness:
  - add direct unit coverage for the affected behavior;
  - run focused tests where available;
  - run the full test suite once before commit when production code changed in
    shared execution, txpool, chain-store, retained-state, or persistence
    paths;
  - for test-only regression additions over already-correct behavior, focused
    coverage plus `git diff --check` and verifier review is sufficient;
  - run devnet smoke when public RPC/process behavior or restored state is part
    of the behavior.
- Docs-only loop/process changes:
  - no full suite required;
  - run `git diff --check` if markdown edits are staged with code or if
    whitespace-sensitive formatting changed.

## Verifier Checklist

Verifier review should answer:

- Does the diff satisfy every acceptance criterion in `docs/loop/next-run.md`?
- Are the tests focused on the behavior rather than implementation details?
- Did the implementer avoid unrelated refactors and unrelated dirty work?
- Are docs/tasks/roadmap updated only when project status changed?
- Are known blockers accurately preserved in `docs/loop/state.md`?
- Is the commit/push decision supported by deterministic gate output?

The verifier should report `PASS`, `FAIL`, or `BLOCKED`, with file/line
references for actionable findings.
