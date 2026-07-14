# Validation

This file defines the stable verification commands for development work. Tests
are split into explicit layers; the default test runner command is intentionally
not the complete suite.

## Commands

- Fast process-free unit layer:

  ```sh
  make test-unit
  ```

- Persistence, socket, fixture-adapter, and external KZG integration layer:

  ```sh
  make test-integration
  ```

- Standalone CLI, restart, signal, and devnet process layer:

  ```sh
  make test-e2e E2E_JOBS=4
  ```

- Complete acceptance suite:

  ```sh
  make test-all E2E_JOBS=4
  ```

`sbcl --script tests/run-tests.lisp` runs only the unit layer. It must never be
reported as complete validation. `--layer all` is the direct-runner equivalent
when the Make target is unsuitable.

Optional official fixtures are enabled with
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`. A clean skip caused by an absent
optional fixture root is not evidence that the external fixture profile passed.

## Change Gates

- Documentation-only changes: `git diff --check`; no Lisp suite is required.
- Narrow domain changes: focused owning-module tests, `make test-unit`, and
  `git diff --check`.
- Persistence, KZG, or socket integration changes: focused tests,
  `make test-integration`, `make test-unit`, and `git diff --check`.
- CLI, listener lifecycle, database restart, Engine/public separation, or
  process-boundary changes: focused smoke coverage, all three layers through
  `make test-all E2E_JOBS=4`, and `git diff --check`.
- Consensus, execution, state-root, receipt-root, canonical-chain, or broad
  architecture changes: focused regression coverage followed by
  `make test-all E2E_JOBS=4` and `git diff --check`.

Local socket/process gates may require execution outside a restricted sandbox.
Request that permission before running a gate that predictably binds listeners.

## Fixture Gates

- In-repository import profile:

  ```sh
  sbcl --script scripts/phase-a-smoke-gate.lisp -- --json
  ```

- Import plus local devnet/process profile:

  ```sh
  sbcl --script scripts/phase-a-smoke-gate.lisp -- --json --devnet
  ```

- Standalone devnet profile:

  ```sh
  sbcl --script scripts/devnet-smoke-gate.lisp -- --json
  ```

Run a smoke profile when the changed behavior participates in that profile; do
not use a smoke report as a substitute for the owning unit or integration test.

## Review Gate

Production changes receive an independent diff review after deterministic
checks pass. Review verifies the stated outcome, architecture ownership,
rollback/error behavior, test relevance, and absence of unrelated changes.
