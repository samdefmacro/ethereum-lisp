# ethereum-lisp

A Common Lisp implementation of the Ethereum execution layer.

This repository is built as a usable execution client, cross-checking protocol
behavior against reference implementations where compatibility matters:

- `references/go-ethereum` (`geth`)
- `references/nethermind` (`Nethermind`)
- `references/reth` (`Reth`, Rust reference architecture, when present)

The reference repositories are local clones for reading and comparison only;
they are ignored by git. `references/reth` is optional until that clone is
available locally. Reth/revm is the Rust-side comparison point for architecture,
provider boundaries, EVM behavior, txpool, RPC, and Engine API work.

## Implemented capabilities

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
  and restart/reorg coverage over the storage substrate
- a RocksDB-backed storage substrate (pinned 11.1.2, reached through its C API
  and CFFI), with the memory and CRC-framed log backends retained as
  deterministic reference implementations and durability-test oracles
- historical proof-of-work support: fork-specific difficulty, light Ethash seal
  verification, ommer rules and rewards, and the DAO-fork state transition,
  with the Merge boundary taken from chain configuration rather than a header
- devp2p networking: RLPx with Snappy compression, discv4 and authenticated
  discv5 discovery with NAT traversal, peer scoring and inbound admission
  limits, `eth` wire sync pipelined across multiple peers, and `snap` range
  serving from persistent state
- EIP-4844 and EIP-7594 blob transactions end to end: network-wrapper decoding,
  KZG-verified pool admission and gossip relay, blob-aware selection, and a
  `blobsBundle` assembled from stored sidecars
- embedded mainnet, Sepolia, Holesky, and Hoodi presets that reproduce their
  published genesis hashes
- synchronous record-scoped persistence for successful canonical forkchoice
  transitions, including direct-key canonical reconciliation, coupled txpool
  dirty tracking, in-memory rollback on write failure, cross-service mutation
  isolation, and reorg/SIGKILL restart coverage
- synchronous record-scoped persistence for each successful noncanonical
  `newPayload` candidate, with fresh-database baseline seeding, conflict checks,
  explicit head bounds and legacy-baseline migration, rollback on write
  failure, and pre-forkchoice SIGKILL recovery
- synchronous record-scoped persistence for locally sealed dev-period blocks:
  execution first stages a noncanonical candidate, then canonical publication,
  checkpoint/index updates, state, receipts, transaction locations, and coupled
  txpool changes commit under one guarded rollback boundary before public
  visibility; explicitly classified transient file-write failures retain the
  pending transaction, emit a warning, and retry on a later worker tick, while
  persistence invariants fail-stop, with SIGKILL restart coverage
- an explicit txpool persistence authority protocol shared by the chain
  database and independently refreshed journal: versioned role, chain,
  genesis, lifecycle authority, generation, and base-generation metadata is
  committed with each snapshot; only a compatible journal strictly newer than
  its DB base can replace the DB txpool, while equal/stale journals lose and
  canonical transactions are always suppressed; database and journal paths
  must resolve to distinct artifacts, and versioned snapshot/delta targets
  cannot be changed without publishing metadata in the same batch
- a local durable staged-import boundary with versioned, chain-config-bound
  control state; strict header/body/execution/receipt/transaction-index
  dependencies; real execution from a persisted parent; restart continuation;
  reverse-order unwind; and fresh-store hydration without publishing canonical
  state. Stage outputs and progress commit atomically, while canonical indexes,
  checkpoints, public transaction locations, and txpool ownership remain with
  forkchoice

## Run tests

Local application builds and tests run inside Docker so compiler caches, temporary
artifacts, child processes, and loopback listeners stay isolated from macOS.
The repository is mounted read-only; only the container-local `.cache` tmpfs
is writable. The container has no external network or published host ports;
real socket tests use loopback only inside its network namespace:

```sh
cl-workbench doctor --strict
cl-workbench repl start
cl-workbench repl eval '(+ 1 2)'
cl-workbench test trie-fixture-vectors
cl-workbench docs verify
cl-workbench repl stop
```

The managed adapter keeps the listener private to the project container and
streams the canonical Workbench client into it. Runtime container names derive
from the physical checkout, while image tags derive from pinned build inputs;
ownership labels prevent one checkout from stopping another.

Cold validation also stays container-only:

```sh
scripts/dev.sh cold-test unit
scripts/dev.sh cold-test integration
scripts/dev.sh cold-test e2e                 # two bounded workers by default
scripts/dev.sh cold-test e2e --jobs 4
scripts/dev.sh cold-test all                 # full validation when needed
scripts/dev.sh cold-test unit --match TRANSACTION
```

The Docker image includes SBCL, a pinned RocksDB build, the c-kzg-4844 and blst
shared libraries the KZG and BLS12-381 bindings dlopen, and the small set of
process tools exercised by the suite. Each test invocation first loads all test
definitions once, preventing concurrent ASDF compilation races.

Inside CI or the marked project image, the underlying commands are shown below.
They fail closed elsewhere; never invoke them directly on the macOS host:

```sh
sbcl --script tests/run-tests.lisp
sbcl --script tests/run-tests.lisp --layer integration
sbcl --script tests/run-tests.lisp --layer e2e
sbcl --script tests/run-tests.lisp --layer all
```

`integration` includes persistence, fixture adapters, and KZG verification
through the CFFI binding. `e2e` launches standalone SBCL processes and may bind
local sockets. During development, prefer the smallest layer directly related to
the change; use every layer for release/CI work or a genuinely broad high-risk
change.

Focused runs and discovery remain Docker-isolated:

```sh
scripts/dev.sh cold-test unit --list
scripts/dev.sh cold-test integration --list --verbose
scripts/dev.sh cold-test unit --match TRANSACTION
scripts/dev.sh cold-test unit --exclude SMOKE --exclude OPTIONAL
scripts/dev.sh cold-test unit --timing --slow 1
```

`--layer` may be repeated to compose layers. `--timing` reports execution
totals and the ten slowest selected tests; `--slow SECONDS` limits that report
to tests at or above the threshold.

The corresponding inner Make targets are CI/container internals:

```sh
make test-unit
make test-integration
make test-e2e                 # four bounded workers by default
make test-e2e E2E_JOBS=2
make test-all                 # runs the three layers concurrently
```

`unit` requires only SBCL and should complete in about one minute.
`integration` also exercises file persistence, local sockets, and the KZG CFFI
verifier, so it requires the c-kzg shared library and permission to bind
loopback sockets.
`e2e` launches standalone SBCL processes, uses isolated temporary roots per
worker, and requires the same loopback/process permissions. Optional external
EEST fixture tests remain controlled by
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` and skip cleanly when it is absent.
When set to a host directory, the Docker wrapper mounts it read-only at
`/fixtures/execution-spec-tests` and forwards that container path to SBCL.

## Reference layout

See `PROJECT.md` for the project contract, `docs/architecture.md` for package
and dependency boundaries, `docs/validation.md` for optional verification
commands, and `docs/reference-map.md` for reference-client comparison points.
