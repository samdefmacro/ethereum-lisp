# Loop Validation

This file defines validation gates that loop agents should reference when
generating `docs/loop/next-run.md`.

## Common Gates

- Formatting/patch hygiene:
  - `git diff --check`
- Full Lisp test suite for non-doc implementation batches:
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

## Gate Selection

- Pinned fixture widening or drift classification:
  - run the relevant selector probe or classifier;
  - run `scripts/phase-a-smoke-gate.lisp` with the pinned v5.4.0 root when the
    pinned table changes;
  - run the full test suite once before commit if code changed.
- Devnet/process-runner behavior:
  - run the narrow devnet smoke gate or a focused CLI/process test while
    iterating;
  - run the full test suite once before commit;
  - run an escalated devnet/socket smoke gate before commit when listener,
    readiness, shutdown, Engine/public separation, or process-boundary behavior
    changed.
- Txpool, chain-store, retained-state, sender-recovery, or persistence
  correctness:
  - add direct unit coverage for the affected behavior;
  - run focused tests where available;
  - run the full test suite once before commit;
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

