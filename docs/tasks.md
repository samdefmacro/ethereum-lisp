# Tasks

This file is the execution backlog for the Common Lisp Ethereum execution-layer
client. `docs/roadmap.md` remains the strategic map; this file is the tactical
queue for small, testable slices.

Automation should pick the highest-priority unchecked task whose dependencies
are done, implement only one coherent slice, run the listed validation, update
this file when status changes, then commit and push green work.

Priority guide:

- `P0`: moves the project toward a real execution client, not just a wider RPC
  surface.
- `P1`: important client functionality after the P0 path is shaped.
- `P2`: production hardening, networking, performance, and tooling depth.

Task states:

- `[ ]`: not started.
- `[~]`: started but incomplete.
- `[x]`: complete.

## Current Focus

Move from an in-memory Engine/RPC prototype toward a verifiable chain-import
core:

1. Split the oversized core into stable modules.
2. Introduce a chain-store boundary with canonical indexes.
3. Make `engine_newPayload` execute and validate blocks against state.
4. Add external fixture compatibility harnesses.
5. Only then broaden txpool, RPC, networking, and persistence.

## P0: Reference And Harness

- [ ] Add a Rust execution-client reference map.
  - Milestone: 0 / 8
  - References: Reth repository layout, especially crates for primitives,
    consensus, EVM integration, provider, pipeline, txpool, RPC, and Engine API.
  - Acceptance: `docs/reference-map.md` names the Rust reference client and
    maps the same major areas already mapped for geth and Nethermind.
  - Validation: docs-only diff; no SBCL run required.

- [ ] Add an execution-spec-tests fixture root configuration.
  - Milestone: 8
  - References: geth `tests`, Nethermind `src/tests`, Ethereum
    execution-spec-tests fixture layout.
  - Acceptance: tests can discover an optional local fixture root from an
    environment variable and skip cleanly when it is absent.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Add a small fixture runner skeleton for blockchain/state tests.
  - Milestone: 8
  - Dependencies: execution-spec-tests fixture root configuration.
  - Acceptance: one minimal hand-written fixture can be parsed, selected, and
    reported through the existing test runner without changing consensus logic.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Add fixture-driven transaction encoding/hash vectors.
  - Milestone: 2 / 8
  - References: geth `core/types`, Nethermind `Nethermind.Core`, Rust
    primitives/reference transaction tests.
  - Acceptance: legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702 transaction
    encoding/hash/sender recovery are covered by external-style fixtures.
  - Validation: `sbcl --script tests/run-tests.lisp`.

## P0: Module Boundaries

- [ ] Split chain configuration and fork rules out of `src/core.lisp`.
  - Milestone: 5
  - References: geth `params`, Nethermind chain spec/config modules, Reth chain
    spec primitives.
  - Acceptance: `chain-config`, `chain-rules`, fork activation, and genesis
    config parsing live in a dedicated source file with no behavior change.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Split block/header/body validation out of `src/core.lisp`.
  - Milestone: 5
  - References: geth `core/block_validator.go`, `consensus/misc`; Nethermind
    validation modules.
  - Acceptance: header/body/post-execution validation moves behind a clear
    module boundary; public APIs and tests remain unchanged.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Split Engine API payload/RPC handlers out of `src/core.lisp`.
  - Milestone: 7
  - References: geth `beacon/engine`, `eth/catalyst`; Nethermind Engine RPC;
    Reth Engine API crates.
  - Acceptance: `engine_*` parsing, dispatch, and response shaping are isolated
    from consensus types and block execution.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Split public JSON-RPC and txpool placeholder handlers out of `src/core.lisp`.
  - Milestone: 7
  - References: geth `internal/ethapi`, `eth/filters`, `core/txpool`;
    Nethermind JSON-RPC modules; Reth RPC and txpool crates.
  - Acceptance: `eth_*`, `net_*`, `web3_*`, `txpool_*`, and filter handlers are
    isolated while preserving current JSON output.
  - Validation: `sbcl --script tests/run-tests.lisp`.

## P0: Chain Store And Canonical Indexes

- [ ] Define a chain-store interface over the current memory payload store.
  - Milestone: 6 / 7
  - References: geth `core/rawdb`, `core/blockchain.go`; Nethermind DB/provider
    abstractions; Reth provider traits.
  - Acceptance: known block, block-by-number, transaction location, receipts,
    state-available, head/safe/finalized, and prepared payload lookups go
    through a small chain-store boundary.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Add explicit canonical hash indexes.
  - Milestone: 6
  - Dependencies: chain-store interface.
  - References: geth canonical hash tables in `core/rawdb`; Reth provider
    canonical chain indexes.
  - Acceptance: block-number lookup uses a canonical hash index rather than
    implicitly trusting the latest inserted block at that number.
  - Validation: add competing same-number block coverage and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] Represent canonical head, safe head, and finalized head as typed store
  checkpoints.
  - Milestone: 6 / 7
  - Dependencies: chain-store interface.
  - Acceptance: forkchoice checkpoint data is not just loose hash slots on the
    memory store; block tag resolution uses the checkpoint abstraction.
  - Validation: existing forkchoice/block tag tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add a first reorg-aware canonical update path.
  - Milestone: 6
  - Dependencies: canonical hash indexes and typed checkpoints.
  - References: geth `BlockChain.SetCanonical`, Reth canonical chain provider.
  - Acceptance: switching canonical head rewrites number-to-hash indexes for
    the affected in-memory range and leaves side-chain blocks retrievable by
    hash.
  - Validation: add two-branch in-memory tests and run
    `sbcl --script tests/run-tests.lisp`.

## P0: Engine Payload Import

- [ ] Route `engine_newPayload` through block execution when parent state is
  available.
  - Milestone: 5 / 7
  - Dependencies: chain-store interface.
  - References: geth `eth/catalyst`, `core/state_processor.go`; Nethermind
    block processor; Reth consensus/executor integration.
  - Acceptance: valid executable payloads with known parent state execute
    transactions, compute receipts/state root/logs bloom/gas used, and are
    stored as known blocks.
  - Validation: add a one-transaction payload import test and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] Map post-execution validation failures to Engine `INVALID` payload status.
  - Milestone: 7
  - Dependencies: executed `engine_newPayload`.
  - Acceptance: bad state root, receipts root, logs bloom, or gas used returns
    Engine-style `INVALID` with latest-valid hash behavior matching the current
    invalid-ancestor cache model.
  - Validation: add invalid payload status tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] Persist block receipts and state snapshots from executed Engine payloads.
  - Milestone: 5 / 6 / 7
  - Dependencies: executed `engine_newPayload`.
  - Acceptance: `eth_getTransactionReceipt`, `eth_getBlockReceipts`,
    `eth_getBalance`, `eth_getCode`, `eth_getStorageAt`, and
    `eth_getTransactionCount` can answer against blocks imported via
    `engine_newPayload`.
  - Validation: add Engine-imported block RPC tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] Make `engine_forkchoiceUpdated` update canonical chain state, not only
  block tags.
  - Milestone: 6 / 7
  - Dependencies: canonical update path.
  - Acceptance: VALID forkchoice head rewires canonical indexes and public
    `latest`/`pending` views follow that canonical head.
  - Validation: forkchoice branch switch tests plus
    `sbcl --script tests/run-tests.lisp`.

## P0: State, Trie, And Proof Correctness

- [ ] Replace the minimal trie root prototype with node-shape compatible MPT
  insertion/deletion coverage.
  - Milestone: 3
  - References: geth `trie`, Nethermind `Nethermind.Trie`, Reth/trie crates.
  - Acceptance: branch, extension, and leaf node encodings are covered by
    fixtures including deletion and path-compression edge cases.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Add account/storage proof generation and verification.
  - Milestone: 3 / 7
  - Dependencies: compatible MPT insertion/deletion.
  - References: geth `eth_getProof`, trie proof APIs; Nethermind proof APIs.
  - Acceptance: local state can produce and verify account/storage proofs for
    retained state snapshots.
  - Validation: dedicated proof tests and `sbcl --script tests/run-tests.lisp`.

- [ ] Add persistent state snapshot/change-set interfaces.
  - Milestone: 3 / 6
  - Dependencies: chain-store interface.
  - Acceptance: transaction/block execution can commit state changes behind an
    interface that can later be backed by a real database.
  - Validation: state rollback/commit tests plus
    `sbcl --script tests/run-tests.lisp`.

## P0: EVM Correctness Gaps

- [ ] Add an EVM state-test fixture runner.
  - Milestone: 4 / 8
  - References: Ethereum execution-spec-tests, geth state tests, Nethermind EVM
    test runners, Reth/revm fixtures.
  - Acceptance: at least one external-style EVM state fixture can drive the
    Common Lisp EVM and compare post-state/root/logs.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Expand CALL-family semantics toward spec completeness.
  - Milestone: 4
  - References: geth `core/vm`, Nethermind EVM, revm behavior.
  - Acceptance: nested value transfer, returndata, gas, access-list, static
    context, revert, and code-resolution cases are fixture-backed beyond the
    current hand-written tests.
  - Validation: targeted CALL fixtures plus `sbcl --script tests/run-tests.lisp`.

- [ ] Complete non-empty BN254 pairing precompile coverage.
  - Milestone: 4
  - References: geth `crypto/bn256`, EVM precompile tests, Nethermind
    precompiles.
  - Acceptance: valid non-empty pairing vectors and invalid subgroup/curve
    vectors are covered.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] Integrate real KZG proof verification.
  - Milestone: 1 / 4 / 5
  - References: geth `crypto/kzg4844`, Reth KZG integration.
  - Acceptance: blob sidecars and the point-evaluation precompile verify actual
    proofs rather than only shape/versioned-hash checks.
  - Validation: KZG vector tests plus `sbcl --script tests/run-tests.lisp`.

- [ ] Add EOF planning notes and fork gates.
  - Milestone: 4
  - References: geth and Reth EOF support status for active forks.
  - Acceptance: roadmap/tasks identify exact EOF requirements before any EOF
    implementation begins.
  - Validation: docs-only diff.

## P1: Txpool Beyond Placeholder

- [ ] Extract txpool state from the Engine payload memory store.
  - Milestone: 7
  - Dependencies: module split or chain-store boundary.
  - References: geth `core/txpool`, Reth transaction pool subpools.
  - Acceptance: pending transaction storage, filters, and RPC views use a
    txpool object rather than direct payload-store hash tables.
  - Validation: existing txpool/RPC tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add sender/nonce keyed txpool indexing.
  - Milestone: 7
  - Dependencies: extracted txpool state.
  - Acceptance: pending transactions are indexed by hash and sender/nonce, and
    txpool content APIs no longer rebuild all groupings from scratch.
  - Validation: add duplicate sender/nonce tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add basic txpool admission preflight.
  - Milestone: 7
  - Dependencies: sender/nonce keyed txpool indexing.
  - References: geth txpool validation, Reth transaction validation.
  - Acceptance: raw submissions recover sender, validate transaction type
    against chain rules, intrinsic gas, fee fields, nonce shape, and basic
    sender-code restrictions before entering pending.
  - Validation: invalid raw tx admission tests and
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add same-sender same-nonce replacement policy.
  - Milestone: 7
  - Dependencies: basic txpool admission preflight.
  - Acceptance: a higher-priced replacement can replace a pending transaction,
    while insufficient price bumps are rejected or ignored according to the
    selected geth/Reth-compatible policy.
  - Validation: replacement tests and `sbcl --script tests/run-tests.lisp`.

- [ ] Add queued/basefee/blob subpool placeholders.
  - Milestone: 7
  - Dependencies: replacement policy.
  - References: Reth pending/queued/basefee/blob pools, geth txpool queues.
  - Acceptance: txpool status/content can distinguish pending from queued, and
    fee/basefee-ineligible transactions have a defined place.
  - Validation: txpool status/content tests and
    `sbcl --script tests/run-tests.lisp`.

## P1: Public RPC Execution APIs

- [ ] Add `eth_call` against retained state.
  - Milestone: 7
  - Dependencies: chain-store state snapshots and EVM context cleanup.
  - References: geth `internal/ethapi`, Nethermind RPC, Reth RPC.
  - Acceptance: simple calls execute without committing state and return output
    or revert data.
  - Validation: `eth_call` tests plus `sbcl --script tests/run-tests.lisp`.

- [ ] Add `eth_estimateGas` first-pass binary search.
  - Milestone: 7
  - Dependencies: `eth_call`.
  - Acceptance: simple transfer and contract-call gas estimates are bounded by
    block gas limit and detect reverts.
  - Validation: estimate tests plus `sbcl --script tests/run-tests.lisp`.

- [ ] Add `eth_createAccessList` first-pass support.
  - Milestone: 7
  - Dependencies: EVM access tracking extraction.
  - Acceptance: EVM execution can return touched accounts/storage keys for a
    call-style simulation.
  - Validation: access-list RPC tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add subscription-compatible filter lifecycle notes before implementing
  WebSocket subscriptions.
  - Milestone: 7
  - References: geth filters/subscriptions, Nethermind subscriptions, Reth RPC.
  - Acceptance: tasks/roadmap describe polling filters versus subscription
    semantics and cleanup/timeout expectations.
  - Validation: docs-only diff.

## P1: Persistence

- [ ] Define a minimal key-value database protocol.
  - Milestone: 6
  - References: geth `ethdb`, Nethermind DB abstractions, Reth database/provider.
  - Acceptance: put/get/delete/batch/iterator semantics are described and
    backed by an in-memory implementation.
  - Validation: database protocol tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add a file-backed development database backend.
  - Milestone: 6
  - Dependencies: key-value protocol.
  - Acceptance: blocks/headers/receipts can survive process restart in a simple
    non-production backend.
  - Validation: round-trip persistence tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] Add freezer/static-history planning notes.
  - Milestone: 6
  - References: geth freezer, Reth static files.
  - Acceptance: document what data will move to append-only/static storage and
    what remains in mutable key-value state.
  - Validation: docs-only diff.

## P1: Networking And Sync Shell

- [ ] Add a concrete local socket backend for the HTTP service.
  - Milestone: 7
  - Dependencies: current stream service.
  - Acceptance: a local process can serve JSON-RPC over a TCP port in tests or
    a small dev command.
  - Validation: service test plus `sbcl --script tests/run-tests.lisp`.

- [ ] Add devp2p/discovery architecture notes.
  - Milestone: 6 / future networking
  - References: geth `p2p`, `p2p/discover`, Reth networking crates,
    Nethermind networking.
  - Acceptance: document the minimal pieces required before implementation:
    ENR, discovery, RLPx, eth protocol, snap protocol, peer scoring.
  - Validation: docs-only diff.

- [ ] Add staged-sync pipeline planning notes.
  - Milestone: 6 / future sync
  - References: Reth staged sync, geth downloader/snap sync, Nethermind sync.
  - Acceptance: identify initial stages for headers, bodies, senders,
    execution, receipts, indexes, and unwind.
  - Validation: docs-only diff.

## P2: Production Depth

- [ ] Add metrics/logging abstraction.
  - Milestone: future operations
  - Acceptance: tests and services can emit structured logs/metrics without
    hardcoding a backend.
  - Validation: unit tests for disabled/default logging behavior.

- [ ] Add CLI entry point for local devnet experiments.
  - Milestone: future node shell
  - Dependencies: socket-backed HTTP service and chain-store interface.
  - Acceptance: one command can load genesis, start RPC, and expose current
    chain id/head.
  - Validation: smoke test or documented manual command.

- [ ] Add Hive compatibility plan.
  - Milestone: 8
  - Acceptance: document what a Hive runner needs from the Lisp client:
    startup, Engine API auth, JSON-RPC ports, genesis loading, and logs.
  - Validation: docs-only diff.

- [ ] Add pruning/history retention strategy.
  - Milestone: 6 / production storage
  - Dependencies: persistence backend.
  - Acceptance: document archive/full/pruned modes and which RPC methods depend
    on retained historical state.
  - Validation: docs-only diff.

## Recently Completed

- [x] Track forkchoice `head` for `latest`, `pending`, `eth_blockNumber`, and
  head fee paths.
- [x] Track forkchoice `safe` and `finalized` block tags.
- [x] Accept public `safe` and `finalized` block tags.
- [x] Add `eth_feeHistory`.
- [x] Add log, block, and pending-transaction polling filters.
- [x] Add local pending transaction RPC views and txpool placeholder methods.
- [x] Fold pending txpool transactions into
  `eth_getTransactionCount(..., "pending")`.
- [x] Remove pending transactions when the same hash is retained in a block.
- [x] Avoid re-adding mined raw transactions to the pending pool.
- [x] Deduplicate repeated pending raw transaction submissions and pending
  filter notifications.
