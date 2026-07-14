# Validation

This file defines the stable verification commands for development work. Local
SBCL builds and tests run only inside Docker; do not invoke host SBCL on macOS.
Tests are split into explicit layers, and the default inner test runner command
is intentionally not the complete suite.

## Commands

- Fast process-free unit layer:

  ```sh
  make docker-test-unit
  ```

- Persistence, socket, fixture-adapter, and external KZG integration layer:

  ```sh
  make docker-test-integration
  ```

- Standalone CLI, restart, signal, and devnet process layer:

  ```sh
  make docker-test-e2e
  ```

- Complete acceptance suite:

  ```sh
  make docker-test-all
  ```

The Docker E2E gate uses two bounded workers by default; set
`DOCKER_E2E_JOBS=4` only when more local concurrency is appropriate. Inside CI
or an already isolated Linux container, `sbcl --script tests/run-tests.lisp`
runs only the unit layer. It must never be reported as complete validation.
`--layer all` is the container-internal direct-runner equivalent when the Make
target is unsuitable.

Optional official fixtures are enabled with
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`. The Docker wrapper treats its value
as a host directory, mounts it read-only at `/fixtures/execution-spec-tests`,
and passes that container path to SBCL. A clean skip caused by an absent
optional fixture root is not evidence that the external fixture profile passed.

## Change Gates

- Documentation-only changes: `git diff --check`; no Lisp suite is required.
- Narrow domain changes: focused owning-module tests, `make docker-test-unit`, and
  `git diff --check`.
- Persistence, KZG, or socket integration changes: focused tests,
  `make docker-test-integration`, `make docker-test-unit`, and
  `git diff --check`.
- CLI, listener lifecycle, database restart, Engine/public separation, or
  process-boundary changes: focused smoke coverage, all three layers through
  `make docker-test-all`, and `git diff --check`.
- Consensus, execution, state-root, receipt-root, canonical-chain, or broad
  architecture changes: focused regression coverage followed by
  `make docker-test-all` and `git diff --check`.

Docker socket/process gates may require permission to access the Docker daemon.
Their listeners stay in the container network namespace and publish no host
ports.

## Fixture Gates

- In-repository import profile:

  ```sh
  make docker-sbcl DOCKER_SBCL_ARGS="--script scripts/phase-a-smoke-gate.lisp -- --json"
  ```

- Import plus local devnet/process profile:

  ```sh
  make docker-sbcl DOCKER_SBCL_ARGS="--script scripts/phase-a-smoke-gate.lisp -- --json --devnet"
  ```

- Standalone devnet profile:

  ```sh
  make docker-sbcl DOCKER_SBCL_ARGS="--script scripts/devnet-smoke-gate.lisp -- --json"
  ```

Run a smoke profile when the changed behavior participates in that profile; do
not use a smoke report as a substitute for the owning unit or integration test.

## Review Gate

Production changes receive an independent diff review after deterministic
checks pass. Review verifies the stated outcome, architecture ownership,
rollback/error behavior, test relevance, and absence of unrelated changes.
