# ethereum-lisp

A Common Lisp implementation of the Ethereum execution layer.

This repository is intentionally being built in small, testable layers while
cross-checking behavior against:

- `references/go-ethereum` (`geth`)
- `references/nethermind` (`Nethermind`)
- `references/reth` (`Reth`, Rust reference architecture, when present)

The reference repositories are local clones for reading and comparison only;
they are ignored by git. `references/reth` is optional until that clone is
available locally, but the roadmap and task backlog now treat Reth/revm as the
Rust-side comparison point for architecture, provider boundaries, EVM behavior,
txpool, RPC, and Engine API work.

## Current scope

The current milestone is moving from an in-memory Engine/RPC prototype toward a
verifiable chain-import core:

- keep a straightforward Common Lisp substrate and test runner
- allow ASDF/Quicklisp dependencies when they make core implementation,
  validation, or developer workflows more maintainable
- introduce a chain-store boundary with explicit canonical indexes
- route `engine_newPayload` through real block execution when parent state is
  available
- validate imported blocks against state root, receipts root, logs bloom, gas
  used, and forkchoice state
- add external fixture harnesses before widening nonessential RPC, txpool,
  persistence, networking, or CLI surface area

The project currently ships an SBCL script entry point for running the core
suite.

Implemented so far:

- RLP, Keccak-256, and basic Ethereum domain types
- Merkle Patricia Trie encoding and root calculation
- account, transaction, receipt, bloom, and header encodings
- in-memory secure state root prototype
- a broad first-pass EVM interpreter with fork gates, precompile scaffolding,
  access-list warming, memory/gas accounting, CALL/CREATE paths, refunds, logs,
  and Cancun/Prague/Amsterdam-oriented fields where currently modeled
- signed transaction and block execution paths with receipt/root/logs-bloom
  derivation and rollback coverage
- geth/Nethermind-shaped Engine payload projection, in-memory payload storage,
  forkchoice checkpoints, public JSON-RPC read methods, polling filters, a
  policy-driven local transaction pool, and a stream-based HTTP adapter
- explicit JSON null/false/empty-container values at RPC boundaries, defensive
  byte ownership for hashes and addresses, and typed node configuration
- extensible chain-store and transaction protocols, application-level txpool
  admission, and capability-gated Engine method registration

The main gap is no longer "can the project parse Ethereum-shaped objects"; it
is whether those objects can be imported, executed, stored, reorged, queried,
and fixture-checked like a real execution client.

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

See `docs/reference-map.md` for the source modules used as the main comparison
points, `docs/roadmap.md` for the long-running implementation plan, and
`docs/tasks.md` for the tactical backlog used by long-running implementation
work.
