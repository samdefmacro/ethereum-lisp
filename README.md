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

- replace the live forkchoice full-store scan with record-scoped durable batches
- persist dev-period canonical sealing before it becomes publicly visible
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
- synchronous live persistence for successful canonical forkchoice transitions,
  with in-memory rollback on write failure, cross-service mutation isolation,
  stale-journal recovery, and SIGKILL restart coverage
- synchronous record-scoped persistence for each successful noncanonical
  `newPayload` candidate, with fresh-database baseline seeding, conflict checks,
  rollback on write failure, and pre-forkchoice SIGKILL recovery

The main durability gap is now granularity: forkchoice commits still scan the
whole known block/state view, and dev-period blocks still depend on lifecycle
export. The development file backend also rewrites its complete S-expression
image for a logical record batch. Durable trie nodes, staged sync/unwind,
devp2p, and external Hive validation remain future work.

## Run tests

```sh
sbcl --script tests/run-tests.lisp
```

The default command runs the process-free `unit` layer. The remaining stable
layer commands are:

```sh
sbcl --script tests/run-tests.lisp --layer integration
sbcl --script tests/run-tests.lisp --layer e2e
sbcl --script tests/run-tests.lisp --layer all
```

`integration` includes persistence, fixture adapters, and external KZG
verification. `e2e` launches standalone SBCL processes and may bind local
sockets. Run every layer before publishing an architectural change.

Focused runs and discovery are available without editing the suite:

```sh
sbcl --script tests/run-tests.lisp --list
sbcl --script tests/run-tests.lisp --layer integration --list --verbose
sbcl --script tests/run-tests.lisp --match TRANSACTION
sbcl --script tests/run-tests.lisp --exclude SMOKE --exclude OPTIONAL
sbcl --script tests/run-tests.lisp --layer unit --timing --slow 1
```

`--layer` may be repeated to compose layers. `--timing` reports execution
totals and the ten slowest selected tests; `--slow SECONDS` limits that report
to tests at or above the threshold.

Stable developer and CI commands are also available:

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

## Reference layout

See `PROJECT.md` for the project contract, `docs/status.md` for the current
verified snapshot and active objective, `docs/architecture.md` for package and
dependency boundaries, `docs/validation.md` for acceptance commands, and
`docs/reference-map.md` for reference-client comparison points.
