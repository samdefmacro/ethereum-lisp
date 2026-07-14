# ethereum-lisp

A Common Lisp implementation of the Ethereum execution layer.

This repository is intentionally being built in small, testable layers while
cross-checking behavior against:

- `references/go-ethereum` (`geth`)
- `references/nethermind` (`Nethermind`)
- `references/reth` (`Reth`, Rust reference architecture, when present)

The reference repositories are local clones for reading and comparison only;
they are ignored by git. `references/reth` is optional until that clone is
available locally. Reth/revm is the Rust-side comparison point for architecture,
provider boundaries, EVM behavior, txpool, RPC, and Engine API work.

## Current scope

The pinned Shanghai import profile and repository-local Engine/RPC devnet
profile are closed. Current work is moving the client from snapshot-oriented
development persistence toward incremental durability and staged sync:

- persist dev-period canonical sealing before it becomes publicly visible
- define an explicit generation/authority rule between the chain database and
  the independently refreshed transaction-pool journal
- add persisted staged-import progress and unwind behavior
- implement networking only after durable import and unwind contracts are
  established

The project currently ships an SBCL script entry point for running the core
suite.

Implemented so far:

- RLP, Keccak-256, and basic Ethereum domain types
- fixture-backed Merkle Patricia Trie roots, proofs, range iteration, and state
  commitments
- account, transaction, receipt, bloom, and header encodings
- a broad first-pass EVM interpreter with fork gates, precompile scaffolding,
  access-list warming, memory/gas accounting, CALL/CREATE paths, refunds, logs,
  and Cancun/Prague/Amsterdam-oriented fields where currently modeled
- signed transaction and block execution paths with receipt/root/logs-bloom
  derivation and rollback coverage
- geth/Nethermind-shaped Engine payload handling, forkchoice checkpoints,
  public JSON-RPC read/simulation methods, polling filters, a policy-driven
  local transaction pool, and concrete split HTTP socket listeners
- explicit JSON null/false/empty-container values at RPC boundaries, defensive
  byte ownership for hashes and addresses, and typed node configuration
- extensible chain-store, transaction-pool, persistence, and execution-service
  boundaries; application-level admission; capability-gated Engine methods;
  and restart/reorg coverage over the development KV snapshot format
- synchronous record-scoped persistence for successful canonical forkchoice
  transitions, including direct-key canonical reconciliation, coupled txpool
  dirty tracking, in-memory rollback on write failure, cross-service mutation
  isolation, and reorg/SIGKILL restart coverage
- synchronous record-scoped persistence for each successful noncanonical
  `newPayload` candidate, with fresh-database baseline seeding, conflict checks,
  explicit head bounds and legacy-baseline migration, rollback on write
  failure, and pre-forkchoice SIGKILL recovery

The main durability gap is now local publication: dev-period blocks still
depend on a later forkchoice call or lifecycle export instead of committing
before canonical visibility. The transaction-pool journal also lacks an
explicit generation marker relative to the chain database. The development
file backend still rewrites its complete S-expression image for a logical
record batch. Durable trie nodes, staged sync/unwind, devp2p, and external Hive
validation remain future work.

## Run tests

Local SBCL builds and tests run inside Docker so compiler caches, temporary
artifacts, child processes, and loopback listeners stay isolated from macOS.
The repository is mounted read-only; only the container-local `.cache` tmpfs
is writable. The container has no external network or published host ports;
real socket tests use loopback only inside its network namespace:

```sh
make docker-test-unit
make docker-test-integration
make docker-test-e2e                 # two bounded workers by default
make docker-test-e2e DOCKER_E2E_JOBS=4
make docker-test-all                 # required before publishing a phase
make docker-test-unit DOCKER_TEST_ARGS="--match TRANSACTION"
make docker-sbcl DOCKER_SBCL_ARGS="--script scripts/phase-a-smoke-gate.lisp -- --json"
```

The Docker image includes SBCL, Go 1.24 for the vendored KZG verifier, and the
small set of process tools exercised by the suite. Each test invocation first
loads all test definitions once, preventing concurrent ASDF compilation races.

Inside CI or an already isolated Linux container, the underlying commands are
shown below. Never invoke these directly on the macOS development host:

```sh
sbcl --script tests/run-tests.lisp
sbcl --script tests/run-tests.lisp --layer integration
sbcl --script tests/run-tests.lisp --layer e2e
sbcl --script tests/run-tests.lisp --layer all
```

`integration` includes persistence, fixture adapters, and external KZG
verification. `e2e` launches standalone SBCL processes and may bind local
sockets. Run every layer before publishing an architectural change.

Focused runs and discovery remain Docker-isolated:

```sh
make docker-test-unit DOCKER_TEST_ARGS="--list"
make docker-test-integration DOCKER_TEST_ARGS="--list --verbose"
make docker-test-unit DOCKER_TEST_ARGS="--match TRANSACTION"
make docker-test-unit DOCKER_TEST_ARGS="--exclude SMOKE --exclude OPTIONAL"
make docker-test-unit DOCKER_TEST_ARGS="--timing --slow 1"
```

`--layer` may be repeated to compose layers. `--timing` reports execution
totals and the ten slowest selected tests; `--slow SECONDS` limits that report
to tests at or above the threshold.

The corresponding inner Make targets used by CI and the Docker wrapper are:

```sh
make test-unit
make test-integration
make test-e2e                 # four bounded workers by default
make test-e2e E2E_JOBS=2
make test-all                 # runs the three layers concurrently
```

`unit` requires only SBCL and should complete in about one minute.
`integration` also exercises file persistence, local sockets, and the vendored
Go KZG verifier, so it requires Go and permission to bind loopback sockets.
`e2e` launches standalone SBCL processes, uses isolated temporary roots per
worker, and requires the same loopback/process permissions. Optional external
EEST fixture tests remain controlled by
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` and skip cleanly when it is absent.
When set to a host directory, the Docker wrapper mounts it read-only at
`/fixtures/execution-spec-tests` and forwards that container path to SBCL.

## Reference layout

See `PROJECT.md` for the project contract, `docs/status.md` for the current
verified snapshot and active objective, `docs/architecture.md` for package and
dependency boundaries, `docs/validation.md` for acceptance commands, and
`docs/reference-map.md` for reference-client comparison points.
