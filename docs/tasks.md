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

Task IDs are stable anchors for automation and progress reports. Queue sections
should reference IDs instead of duplicating task checkboxes; add IDs to tasks as
soon as they enter an active queue or dependency chain.

## Current Focus

Phase A is a verifiable chain-import core. The Phase A scope and invariants are
defined in `docs/roadmap.md` ("Phase A Scope Gate") and bind every task below
until the smoke path passes once end-to-end:

- target fork: post-Merge Shanghai via `engine_newPayloadV2`;
- atomic import (snapshot → execute → derive → validate → commit, all or
  nothing);
- strict sender recovery on every signed import/admission/mined-tx path;
- receipt-derivation invariants locked;
- reorg invariants on canonical / safe / finalized indexes;
- comparison against a pinned execution-spec-tests release and a small
  in-repo fixture set.

The end-to-end smoke scenario is:

1. load genesis/state;
2. accept an executable `engine_newPayloadV2` whose parent state is available;
3. execute transactions atomically and validate state root, receipts root,
   logs bloom, and gas used;
4. persist enough block, receipt, and state snapshot data for local RPC reads;
5. apply `engine_forkchoiceUpdated` to canonical indexes and verify side-chain
   blocks remain hash-retrievable;
6. compare the same path against the pinned fixtures and, where local
   reference clones exist, a recorded geth/Nethermind/Reth commit.

While Phase A is open, do not expand Engine/RPC/txpool surface beyond fixing
Phase A blockers (see `PHASE-A-SURFACE-FREEZE`). Module splits should usually
happen as part of a vertical slice above; avoid broad behavior-preserving
refactors while the chain import path still lacks storage, atomic commit,
execution wiring, and fixture validation.

## Immediate Queue

Long-running automation should pick from this queue before other P0 items unless
a listed dependency is blocked. Order matters: earlier items unblock later
ones.

- `HARNESS-FIXTURE-ROOT`
- `HARNESS-TX-VECTORS`
- `TRIE-FIXTURE-GRADE`
- `HARNESS-FIXTURE-RUNNER`
- `STORE-CHAIN-INTERFACE`
- `STATE-ATOMIC-COMMIT`
- `SENDER-RECOVERY-ENFORCEMENT`
- `RECEIPT-DERIVATION-INVARIANTS`
- `ENGINE-EXECUTE-NEWPAYLOAD`
- `STORE-CANONICAL-INDEXES`
- `STORE-REORG-INVARIANTS`

## P0: Phase A Discipline

- [x] `PHASE-A-SCOPE-GATE`: Lock the Phase A fork target and fixture pin.
  - Milestone: 5 / 7 / 8
  - References: `docs/roadmap.md` ("Phase A Scope Gate"), Ethereum
    execution-spec-tests release tags, geth/Nethermind fork activation tables.
  - Acceptance: a short note in `docs/roadmap.md` or `docs/tasks.md` records
    (a) Phase A target fork (default: post-Merge Shanghai via
    `engine_newPayloadV2`), (b) the pinned `ethereum/execution-spec-tests`
    release commit or tag the smoke path will compare against, and (c) which
    later forks (Cancun blob path, Prague requests, Amsterdam BAL, BPOx) are
    explicitly out of Phase A. KZG real verification only becomes a Phase A
    blocker if Cancun is chosen.
  - Validation: docs-only diff.
  - Result: Phase A is locked to post-Merge Shanghai via
    `engine_newPayloadV2`; fixtures are pinned to
    `ethereum/execution-spec-tests` standard release `v5.4.0` (`88e9fb8` tag
    target), using `fixtures_stable.tar.gz` with Shanghai smoke-path
    selectors. Cancun blob execution/KZG, Prague requests, Osaka/Fusaka
    additions, Amsterdam BAL/devnet releases, BPOx, and zkEVM fixtures remain
    outside Phase A.

- [x] `PHASE-A-SURFACE-FREEZE`: Freeze new Engine/RPC/txpool surface until the
  Phase A smoke path passes end-to-end.
  - Milestone: project hygiene
  - Dependencies: `PHASE-A-SCOPE-GATE`.
  - Acceptance: `docs/roadmap.md` and `docs/tasks.md` make the freeze explicit
    (already drafted in the roadmap "Surface freeze" paragraph), and any new
    task that would expand Engine versions, far-fork support (Amsterdam BAL
    beyond what already parses, BPO5, `engine_getPayloadV6`), or non-blocker
    public RPC surface is rejected or filed under P1/P2.
  - Validation: docs-only diff plus reviewer discipline.
  - Result: the roadmap and task backlog now bind automation to Phase A
    blockers and defer Engine/RPC/txpool surface expansion until the smoke path
    closes.

- [x] `REF-COMMIT-PIN`: Require reference-client commit recording on tasks that
  claim parity comparison.
  - Milestone: documentation maintenance
  - References: `docs/reference-map.md` ("Comparison rule"), `docs/roadmap.md`
    ("Reference Pinning Rule").
  - Acceptance: `docs/reference-map.md` is updated to state that PRs/tasks
    must record the inspected geth / Nethermind / Reth commit or tag, and that
    a missing local clone forces an explicit "fixture-only" or
    "single-client" downgrade in the PR description rather than a silent skip.
  - Validation: docs-only diff.
  - Result: `docs/reference-map.md` now requires exact reference commit/tag
    recording for parity claims and explicit downgrade wording when a local
    reference clone is missing.

## P0: Reference And Harness

- [x] `REF-RETH-MAP`: Add a Rust execution-client reference map.
  - Milestone: 0 / 8
  - References: Reth repository layout, especially crates for primitives,
    consensus, EVM integration, provider, pipeline, txpool, RPC, and Engine API.
  - Acceptance: `docs/reference-map.md` names the Rust reference client and
    maps the same major areas already mapped for geth and Nethermind.
  - Validation: docs-only diff; no SBCL run required.

- [x] `REF-RETH-LOCAL`: Document local Reth reference availability.
  - Milestone: 0 / 8
  - Dependencies: `REF-RETH-MAP`.
  - References: Reth repository and `docs/reference-map.md`.
  - Acceptance: the reference map or setup notes explain how to provide
    `references/reth`, how absent optional Rust references are skipped, and how
    a task should report the Reth commit/version it inspected when available.
  - Validation: docs-only diff.

- [ ] `HARNESS-FIXTURE-ROOT`: Add an execution-spec-tests fixture root
  configuration.
  - Milestone: 8
  - References: geth `tests`, Nethermind `src/tests`, Ethereum
    execution-spec-tests fixture layout.
  - Acceptance: tests can discover an optional local fixture root from an
    environment variable and skip cleanly when it is absent.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `HARNESS-FIXTURE-RUNNER`: Add a small fixture runner skeleton for
  blockchain/state tests.
  - Milestone: 8
  - Dependencies: `HARNESS-FIXTURE-ROOT`.
  - Acceptance: one minimal hand-written fixture can be parsed, selected, and
    reported through the existing test runner without changing consensus logic.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `HARNESS-TX-VECTORS`: Add fixture-driven transaction encoding/hash
  vectors.
  - Milestone: 2 / 8
  - Dependencies: `PHASE-A-SCOPE-GATE` (for fork-set selection); no code
    dependencies — this is a near-free, high-coverage slice.
  - References: geth `core/types`, Nethermind `Nethermind.Core`, Rust
    primitives/reference transaction tests, the pinned execution-spec-tests
    release.
  - Acceptance: legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702 transaction
    encoding/hash/sender recovery are covered by external-style fixtures
    drawn from the pinned release. Sender recovery is exercised on every
    typed transaction case so the result feeds `SENDER-RECOVERY-ENFORCEMENT`.
  - Validation: `sbcl --script tests/run-tests.lisp`.

## P0: Module Boundaries

These tasks reduce long-term maintenance risk, but they should normally be
selected when they unblock the chain-store, Engine import, fixture harness, or
state/EVM correctness work above. Prefer extracting the **minimum boundary**
required by the current vertical slice (e.g. just the chain-rules entry points
used by Engine import) over a full behavior-preserving file move; full module
splits can land after the Phase A smoke path closes.

- [ ] `MOD-CHAIN-CONFIG`: Split chain configuration and fork rules out of
  `src/core.lisp`.
  - Milestone: 5
  - References: geth `params`, Nethermind chain spec/config modules, Reth chain
    spec primitives.
  - Acceptance: `chain-config`, `chain-rules`, fork activation, and genesis
    config parsing live in a dedicated source file with no behavior change.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `MOD-BLOCK-VALIDATION`: Split block/header/body validation out of
  `src/core.lisp`.
  - Milestone: 5
  - References: geth `core/block_validator.go`, `consensus/misc`; Nethermind
    validation modules.
  - Acceptance: header/body/post-execution validation moves behind a clear
    module boundary; public APIs and tests remain unchanged.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `MOD-ENGINE-RPC`: Split Engine API payload/RPC handlers out of
  `src/core.lisp`.
  - Milestone: 7
  - References: geth `beacon/engine`, `eth/catalyst`; Nethermind Engine RPC;
    Reth Engine API crates.
  - Acceptance: `engine_*` parsing, dispatch, and response shaping are isolated
    from consensus types and block execution.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `MOD-PUBLIC-RPC-TXPOOL`: Split public JSON-RPC and txpool placeholder
  handlers out of `src/core.lisp`.
  - Milestone: 7
  - References: geth `internal/ethapi`, `eth/filters`, `core/txpool`;
    Nethermind JSON-RPC modules; Reth RPC and txpool crates.
  - Acceptance: `eth_*`, `net_*`, `web3_*`, `txpool_*`, and filter handlers are
    isolated while preserving current JSON output.
  - Validation: `sbcl --script tests/run-tests.lisp`.

## P0: Chain Store And Canonical Indexes

- [ ] `STORE-CHAIN-INTERFACE`: Define a chain-store interface over the current
  memory payload store.
  - Milestone: 6 / 7
  - References: geth `core/rawdb`, `core/blockchain.go`; Nethermind DB/provider
    abstractions; Reth provider traits.
  - Acceptance: known block, block-by-number, transaction location, receipts,
    state-available, head/safe/finalized, and prepared payload lookups go
    through a small chain-store boundary.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `STORE-CANONICAL-INDEXES`: Add explicit canonical hash indexes.
  - Milestone: 6
  - Dependencies: `STORE-CHAIN-INTERFACE`.
  - References: geth canonical hash tables in `core/rawdb`; Reth provider
    canonical chain indexes.
  - Acceptance: block-number lookup uses a canonical hash index rather than
    implicitly trusting the latest inserted block at that number.
  - Validation: add competing same-number block coverage and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] `STORE-CHECKPOINTS`: Represent canonical head, safe head, and finalized
  head as typed store checkpoints.
  - Milestone: 6 / 7
  - Dependencies: `STORE-CHAIN-INTERFACE`.
  - Acceptance: forkchoice checkpoint data is not just loose hash slots on the
    memory store; block tag resolution uses the checkpoint abstraction.
  - Validation: existing forkchoice/block tag tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] `STORE-CANONICAL-REORG`: Add a first reorg-aware canonical update path.
  - Milestone: 6
  - Dependencies: `STORE-CANONICAL-INDEXES` and `STORE-CHECKPOINTS`.
  - References: geth `BlockChain.SetCanonical`, Reth canonical chain provider.
  - Acceptance: switching canonical head rewrites number-to-hash indexes for
    the affected in-memory range and leaves side-chain blocks retrievable by
    hash.
  - Validation: add two-branch in-memory tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] `STORE-REORG-INVARIANTS`: Lock reorg invariants on canonical, safe, and
  finalized indexes.
  - Milestone: 6 / 7
  - Dependencies: `STORE-CANONICAL-REORG`.
  - References: geth `BlockChain.SetCanonical` plus `core/blockchain_reader`,
    Reth canonical chain provider, Nethermind block tree.
  - Acceptance: tests assert that after a canonical switch (a) side-chain
    blocks remain retrievable by hash, (b) number-to-hash, transaction
    lookup, and receipt lookup only return canonical results, (c) `safe`
    and `finalized` checkpoints never move to a block that is not an
    ancestor of the new head, and (d) `latest`/`pending` block-tag
    resolution follows the new canonical head immediately.
  - Validation: two-branch reorg fixtures plus
    `sbcl --script tests/run-tests.lisp`.

## P0: Engine Payload Import

- [ ] `ENGINE-EXECUTE-NEWPAYLOAD`: Route `engine_newPayload` through block
  execution when parent state is available.
  - Milestone: 5 / 7
  - Dependencies: `STORE-CHAIN-INTERFACE`, `STATE-ATOMIC-COMMIT`,
    `TRIE-FIXTURE-GRADE`, `SENDER-RECOVERY-ENFORCEMENT`,
    `RECEIPT-DERIVATION-INVARIANTS`.
  - References: geth `eth/catalyst`, `core/state_processor.go`; Nethermind
    block processor; Reth consensus/executor integration.
  - Acceptance: a valid executable `engine_newPayloadV2` payload with known
    parent state executes transactions atomically (via
    `STATE-ATOMIC-COMMIT`), derives receipts/state root/logs bloom/gas used,
    is stored as a known block when commitments match, and leaves no
    partial state when any commitment or signature check fails. The
    one-transaction smoke fixture from `HARNESS-FIXTURE-RUNNER` is the
    primary success case.
  - Validation: add a one-transaction `newPayloadV2` import test plus a
    bad-commitment rollback test, and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] `ENGINE-INVALID-POST-EXECUTION`: Map post-execution validation failures
  to Engine `INVALID` payload status.
  - Milestone: 7
  - Dependencies: `ENGINE-EXECUTE-NEWPAYLOAD`.
  - Acceptance: bad state root, receipts root, logs bloom, or gas used returns
    Engine-style `INVALID` with latest-valid hash behavior matching the current
    invalid-ancestor cache model.
  - Validation: add invalid payload status tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] `ENGINE-PERSIST-EXECUTED-BLOCK`: Persist block receipts and state
  snapshots from executed Engine payloads.
  - Milestone: 5 / 6 / 7
  - Dependencies: `ENGINE-EXECUTE-NEWPAYLOAD`.
  - Acceptance: `eth_getTransactionReceipt`, `eth_getBlockReceipts`,
    `eth_getBalance`, `eth_getCode`, `eth_getStorageAt`, and
    `eth_getTransactionCount` can answer against blocks imported via
    `engine_newPayload`.
  - Validation: add Engine-imported block RPC tests and run
    `sbcl --script tests/run-tests.lisp`.

- [ ] `ENGINE-FORKCHOICE-CANONICAL`: Make `engine_forkchoiceUpdated` update
  canonical chain state, not only block tags.
  - Milestone: 6 / 7
  - Dependencies: `STORE-CANONICAL-REORG`.
  - Acceptance: VALID forkchoice head rewires canonical indexes and public
    `latest`/`pending` views follow that canonical head.
  - Validation: forkchoice branch switch tests plus
    `sbcl --script tests/run-tests.lisp`.

## P0: State, Trie, And Proof Correctness

- [ ] `TRIE-FIXTURE-GRADE`: Replace the minimal trie root prototype with
  node-shape compatible MPT insertion/deletion coverage sufficient for the
  Phase A smoke path.
  - Milestone: 3
  - Dependencies: `PHASE-A-SCOPE-GATE`.
  - References: geth `trie`, Nethermind `Nethermind.Trie`, Reth/trie crates,
    pinned execution-spec-tests trie vectors.
  - Acceptance: branch, extension, and leaf node encodings (including empty
    children, single-child collapse, embedded-vs-hashed reference, deletion,
    and path-compression edge cases) are covered by external fixture vectors.
    Account, storage, and secure-trie roots match reference output for the
    genesis allocation used by the Phase A smoke path; zero-value storage
    writes correctly delete keys; empty accounts and EIP-161 state-clearing
    behavior produce reference-matching roots.
  - Validation: trie-vector tests plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] `STATE-PROOFS`: Add account/storage proof generation and verification.
  - Milestone: 3 / 7
  - Dependencies: `TRIE-FIXTURE-GRADE`.
  - References: geth `eth_getProof`, trie proof APIs; Nethermind proof APIs.
  - Acceptance: local state can produce and verify account/storage proofs for
    retained state snapshots.
  - Validation: dedicated proof tests and `sbcl --script tests/run-tests.lisp`.

- [ ] `STATE-ATOMIC-COMMIT`: Add an atomic state/receipt/index commit boundary
  for block import.
  - Milestone: 3 / 5 / 6
  - Dependencies: `STORE-CHAIN-INTERFACE`.
  - References: geth `core/state` journal/snapshot, Reth `BundleState` /
    `ExecutionOutcome`, Nethermind state snapshot.
  - Acceptance: a single block-import call takes a pre-state snapshot, runs
    transaction execution, derives receipts / state root / logs bloom / gas
    used, validates post-execution commitments, and only then commits state,
    receipt, and number/hash/tx-lookup indexes; any failure rolls all of
    those back so no partial state is observable through state DB or RPC.
  - Validation: failure-injection tests covering bad state root, bad
    receipts root, bad logs bloom, bad gas used, and intra-tx errors, plus
    `sbcl --script tests/run-tests.lisp`.

- [ ] `SENDER-RECOVERY-ENFORCEMENT`: Require real sender recovery on every
  signed import, admission, and mined-tx RPC path.
  - Milestone: 1 / 2 / 5 / 7
  - Dependencies: `HARNESS-TX-VECTORS`.
  - References: geth `types.Sender`, Reth `SignedTransaction::recover_signer`,
    Nethermind tx signature handling.
  - Acceptance: signed block import, `eth_sendRawTransaction`, and mined
    transaction RPC objects never substitute a zero address or empty sender;
    invalid signatures (wrong chain id, high-s, malformed yParity, malformed
    EIP-7702 authorization tuple at the transaction level) reject the
    payload/admission outright. A test enumerates each path and asserts that
    sender recovery failure cannot leak state mutation.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [ ] `RECEIPT-DERIVATION-INVARIANTS`: Lock typed receipt encoding and
  derivation invariants on the import path.
  - Milestone: 2 / 5
  - References: geth `core/types/receipt`, Reth receipt encoding, Nethermind
    receipt building.
  - Acceptance: receipt-root derivation is covered against fixtures for
    legacy, EIP-2930, EIP-1559, and EIP-4844 receipt types; cumulative-gas
    monotonicity, log order, logs-bloom membership, contract-address
    derivation for CREATE/CREATE2, and post-Byzantium status semantics are
    asserted from import (not only from hand-built receipt lists). Pre-
    Byzantium post-state receipts are explicitly out of Phase A scope and
    rejected by config.
  - Validation: receipt fixture tests plus
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
  - Dependencies: `PHASE-A-SCOPE-GATE`. Only blocks Phase A if the scope gate
    selects Cancun (or later) as the Phase A target fork; for the default
    Shanghai target this remains P0 but follows the smoke-path closure.
  - References: geth `crypto/kzg4844`, Reth KZG integration, c-kzg-4844
    trusted-setup file.
  - Acceptance: blob sidecars and the point-evaluation precompile verify
    actual proofs rather than only shape/versioned-hash checks. The trusted
    setup file source is documented and pinned. If real KZG cannot land in
    Phase A's window, blob transactions and `engine_newPayloadV3+` are
    explicitly recorded as "shape-checked only, not Phase A VALID".
  - Validation: KZG vector tests plus `sbcl --script tests/run-tests.lisp`.

- [ ] Add EOF planning notes and fork gates.
  - Milestone: 4
  - References: geth and Reth EOF support status for active forks.
  - Acceptance: roadmap/tasks identify exact EOF requirements before any EOF
    implementation begins.
  - Validation: docs-only diff.

## P1: Documentation Health

- [~] `DOC-ROADMAP-STATUS-SPLIT`: Split detailed implementation history out of
  the strategic roadmap.
  - Milestone: documentation maintenance
  - Status: a Done/Partial/Missing summary header has been added to Section 5
    Block Execution; the detailed prose log below it has not yet been moved
    out. Remaining work is to add equivalent summary headers to other
    milestone sections (especially Section 4 EVM and Section 7 Engine/RPC)
    and migrate the historical prose into `docs/status.md` or a changelog
    document.
  - Acceptance: every milestone section in `docs/roadmap.md` opens with a
    concise Done/Partial/Missing/Next summary, and detailed historical
    implementation notes are preserved in `docs/status.md` or an equivalent
    status/changelog document.
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

- [x] Document optional local Reth reference availability and skip/reporting
  rules.
- [x] Add Reth/Rust as a formal reference target and align README/roadmap/tasks
  around the Phase A chain-import focus.
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
