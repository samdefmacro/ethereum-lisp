# Validation Commands

These commands are available when a change needs verification. During feature
development, run the smallest check that directly covers the changed behavior.
The full suite is for an explicit user request, release/CI work, or a genuinely
broad high-risk change; it is not a routine prerequisite for implementing a
feature.

Local SBCL builds and tests run inside Docker on macOS so compiler caches,
temporary artifacts, child processes, and loopback listeners remain isolated.

## Test Layers

```sh
make docker-test-unit
make docker-test-integration
make docker-test-e2e
make docker-test-all
```

- `unit` covers process-free domain behavior.
- `integration` covers persistence, sockets, fixture adapters, and KZG command
  integration.
- `e2e` covers standalone CLI, restart, signals, and devnet processes.
- `all` composes every layer and is intentionally the most expensive option.

Focused selection is available through `DOCKER_TEST_ARGS`, for example:

```sh
make docker-test-unit DOCKER_TEST_ARGS="--match TRANSACTION"
```

Optional official fixtures use `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`. A
missing optional fixture root produces a skip and is not evidence that external
fixture validation passed.

Verification should not expand into unrelated coverage work, documentation
maintenance, repeated baselines, or a second development objective. Report an
unrelated failure separately and continue the requested feature when it is safe
to do so.
