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
refactors while trie compatibility, pinned fixture validation, and cross-client
state-transition coverage are still incomplete.

## Immediate Queue

Long-running automation should pick from this queue before other P0 items unless
a listed dependency is blocked. Order matters: earlier items unblock later
ones.

- `HARNESS-TX-VECTORS`
- `TRIE-FIXTURE-GRADE`

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

- [x] `HARNESS-FIXTURE-ROOT`: Add an execution-spec-tests fixture root
  configuration.
  - Milestone: 8
  - References: geth `tests`, Nethermind `src/tests`, Ethereum
    execution-spec-tests fixture layout.
  - Acceptance: tests can discover an optional local fixture root from an
    environment variable and skip cleanly when it is absent.
  - Validation: `sbcl --script tests/run-tests.lisp`.
  - Result: tests now discover an optional fixture root through
    `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`; absent, blank, or missing roots
    produce an explicit skip condition for external fixture tests instead of a
    failure.

- [x] `HARNESS-FIXTURE-RUNNER`: Add a small fixture runner skeleton for
  blockchain/state tests.
  - Milestone: 8
  - Dependencies: `HARNESS-FIXTURE-ROOT`.
  - Acceptance: one minimal hand-written fixture can be parsed, selected, and
    reported through the existing test runner without changing consensus logic.
  - Validation: `sbcl --script tests/run-tests.lisp`.
  - Result: added a minimal in-repo blockchain fixture at
    `tests/fixtures/execution-spec-tests/minimal-blockchain.json` plus a
    runner skeleton that parses it, selects a named case, and reports format,
    name, network, source, block count, and expected status through the current
    test runner.

- [~] `HARNESS-TX-VECTORS`: Add fixture-driven transaction encoding/hash
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
  - Progress: added an in-repo external-style transaction envelope vector
    runner covering legacy EIP-155, EIP-2930, EIP-1559, EIP-4844, and
    EIP-7702 raw encodings, transaction hashes, sender recovery, and
    wrong-chain sender rejection. The vectors now live in
    `tests/fixtures/execution-spec-tests/transaction-envelopes.json` and are
    parsed through the fixture runner shape instead of being embedded directly
    in Lisp. Reference source availability: geth `8a0223e`, Nethermind
    `1c72a72`; local Reth clone absent. Remaining work: draw or transcribe
    the same vector shape from the pinned
    `execution-spec-tests` release.
  - Progress: extended the transaction envelope fixture shape with per-fork
    validity checks. The same legacy, EIP-2930, EIP-1559, EIP-4844, and
    EIP-7702 raw vectors now assert type activation boundaries across
    Frontier, Berlin, London, Cancun, and Prague using the chain-config
    validator, matching the reference transaction-test pattern where each
    txbytes case records fork-specific success or rejection. Remaining work:
    draw or transcribe the vector data from the pinned `execution-spec-tests`
    release instead of the current in-repo seed vectors.
  - Progress: migrated the transaction fixture shape closer to
    execution-spec-tests transaction tests by using `txbytes` plus a
    per-fork `result` object. Valid fork entries now assert intrinsic gas,
    while invalid entries carry EEST-style exception tokens for pre-fork typed
    transaction rejection. The checked fixture now follows the `txbytes` /
    `result` layout used by reference transaction-test harnesses. Remaining
    work: replace the in-repo seed vectors with vectors drawn from the pinned
    `execution-spec-tests` release.
  - Progress: tightened invalid per-fork transaction fixture checks so
    EEST-style exception tokens are mapped to the local block validation error
    messages. The runner now verifies that pre-fork typed transaction cases
    fail for the expected reason, not merely with any error. Remaining work:
    replace the in-repo seed vectors with vectors drawn from the pinned
    `execution-spec-tests` release.
  - Progress: tightened transaction fixture coverage accounting. The runner
    now requires every vector's `result` object to include all currently
    checked fork labels and rejects unknown fork labels, preventing partial
    per-fork fixtures from silently reducing coverage. Remaining work:
    replace the in-repo seed vectors with vectors drawn from the pinned
    `execution-spec-tests` release.
  - Progress: added top-level transaction fixture metadata validation. The
    runner now checks the expected fixture format string, non-empty source
    note, and reference-client metadata before consuming vectors, so future
    pinned EEST fixture imports fail early if the wrapper shape drifts.
    Remaining work: replace the in-repo seed vectors with vectors drawn from
    the pinned `execution-spec-tests` release.
  - Progress: added machine-checked pinned EEST source metadata to the
    transaction envelope fixture wrapper. The runner now requires the Phase A
    release `v5.4.0`, tag target `88e9fb8`, and `fixtures_stable.tar.gz`
    archive metadata before consuming seed vectors, making fixture-only
    transaction coverage explicit until the pinned transaction cases are
    transcribed.
  - Progress: added transaction fixture coverage guards for required envelope
    families and duplicate vector identities. The runner now rejects missing
    legacy, EIP-2930, EIP-1559, EIP-4844, or EIP-7702 coverage, duplicate
    names, duplicate `txbytes` / `raw`, duplicate hashes, blank senders, and
    invalid chain ids before running per-fork checks.
  - Progress: expanded the local EEST-shaped transaction-test sample root from
    the Phase A three-type subset to all five envelope families. Root vector
    loading now decodes legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702
    `txbytes` / per-fork `result` cases, while the Phase A selector still
    gates its smoke subset to legacy, access-list, and dynamic-fee cases.
  - Progress: added all-family EEST/seed alignment checks for transaction
    vectors. The external-style transaction-test adapter now compares decoded
    legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702 vectors against the
    seed envelope fixture by type, chain id, `txbytes`, hash, sender, and
    per-fork result matrix.
  - Progress: added an explicit full-envelope EEST transaction selector and
    summary gate. The harness now has a stable all-family selector contract
    for legacy, EIP-2930, EIP-1559, EIP-4844, and EIP-7702 cases in addition
    to the narrower Shanghai Phase A smoke selector.
  - Progress: added transaction fixture result-shape validation. Per-fork
    `result` entries now reject unknown exception tokens, valid entries without
    `intrinsicGas`, invalid entries that carry an `intrinsicGas` field even
    when null, and malformed result objects before transaction decoding begins.
  - Progress: added transaction fixture vector-shape validation. Vectors now
    reject ambiguous `txbytes` / `raw` usage, empty encoded transaction bytes,
    malformed transaction hashes, and malformed sender addresses before the
    runner attempts to decode or recover the transaction.
  - Progress: added transaction type activation profile validation. The
    fixture runner now checks that legacy vectors are valid on every tracked
    fork, EIP-2930 vectors start at Berlin, EIP-1559 vectors start at London,
    EIP-4844 vectors start at Cancun, and EIP-7702 vectors start at Prague,
    with matching pre-fork exception tokens.
  - Progress: tightened EEST transaction-test ingestion so all successful fork
    entries for a single `txbytes` case must agree on the transaction hash and
    recovered sender before the case is converted into the local vector shape.
  - Progress: tightened EEST transaction-test result normalization so success
    and exception fields cannot be mixed in the same fork entry, and exception
    entries cannot carry orphan sender or intrinsic-gas fields.
  - Progress: tightened EEST transaction-test result normalization so explicit
    blank exception fields are rejected instead of being ignored on otherwise
    successful fork entries.
  - Progress: tightened EEST transaction-test result fork validation so unknown
    or duplicate fork labels are rejected before conversion to the local vector
    shape, preventing typoed fork results from being silently dropped.
  - Progress: tightened EEST transaction-test result normalization so unknown
    exception tokens are rejected before conversion, keeping pure-failure
    cases from degrading into vague "no successful tracked fork" errors.
  - Progress: tightened EEST transaction-test conversion so the selected
    successful result's hash and sender must match the decoded `txbytes`
    before the local vector is built.
  - Progress: tightened EEST transaction-test result normalization so
    prefixless or uppercase success `hash` and `sender` fields are normalized
    to canonical lowercase RPC hex before consistency and derived-value checks.
  - Progress: tightened EEST transaction-test case normalization so `txbytes`
    is canonicalized to lowercase RPC hex during import, preventing equivalent
    raw encodings with different casing from drifting through selection or
    uniqueness checks.
  - Progress: tightened EEST transaction-test conversion so every successful
    fork entry's `intrinsicGas` must match the decoded transaction before the
    local vector is built.
  - Progress: tightened EEST transaction-test result normalization so
    successful fork entries must provide canonical hex quantity `intrinsicGas`
    values instead of relying on the importer to normalize prefixless or
    leading-zero gas strings.
  - Progress: added canonical quantity validation for valid per-fork
    `intrinsicGas` expectations. Fixture results now reject missing, prefixless,
    or leading-zero gas quantities before comparing against locally derived
    intrinsic gas.
  - Progress: added decoded-envelope consistency validation. Transaction
    fixture vectors now reject cases whose declared type or `chainId` disagrees
    with the decoded raw transaction before hash, sender, and per-fork checks
    run.
  - Progress: moved fork coverage validation into transaction result-shape
    loading. Fixture vectors now reject missing tracked fork labels or unknown
    fork labels before transaction decoding and execution checks begin.
  - Progress: tightened per-fork result entry shape. Valid entries now reject
    explicit blank `exception` fields, and all entries reject unknown fields,
    leaving only the unambiguous `intrinsicGas` or non-empty `exception`
    forms.
  - Progress: moved decoded raw-transaction hash and sender checks into
    transaction fixture loading. Fixture vectors now fail during shape
    validation if `txbytes` decodes to a transaction whose hash or recovered
    sender disagrees with the fixture wrapper.
  - Progress: removed the legacy `raw` fallback from transaction envelope
    fixtures. The runner now requires `txbytes` exactly, matching geth's
    transaction-test utility shape and preventing mixed fixture dialects.
  - Progress: added field-whitelist validation to transaction fixture
    wrappers, `referenceClients`, and individual vectors. Unknown top-level,
    reference-client, or vector fields now fail before decoding, preventing
    misspelled imported EEST transaction assertions from being silently
    ignored.
  - Progress: moved transaction vector required-field checks into the vector
    shape phase. Vectors now reject missing `name`, `type`, `chainId`,
    `txbytes`, `hash`, `sender`, or `result`, unknown transaction types,
    negative/non-integer chain ids, and malformed result objects before
    uniqueness, decoding, or fork-result validation runs.
  - Progress: added duplicate-field and duplicate-fork rejection to the
    transaction fixture loader. Wrapper objects, `referenceClients`, vectors,
    result entries, and per-fork result maps now fail on duplicate keys before
    `assoc` can silently select one value and hide the other.
  - Progress: moved pinned `executionSpecTests` source-shape checks into the
    shared fixture validator. All pinned EEST-backed fixtures now reject
    unknown or duplicate release/tag/archive/status metadata fields before
    wrapper-specific validation proceeds.
  - Progress: moved transaction fixture intrinsic-gas consistency into the
    decoded-vector loader. Valid per-fork `intrinsicGas` entries now must match
    the value derived from decoded `txbytes`, so transcribed EEST vectors fail
    during fixture loading if their expected gas drifts from the encoded
    transaction.
  - Progress: added explicit Shanghai coverage to the transaction fixture fork
    matrix and made Cancun/Prague fixture configs include Shanghai activation.
    The Phase A target fork is now checked directly for every transaction
    envelope vector, while blob and set-code vectors still assert their
    Cancun/Prague activation boundaries.
  - Progress: added transaction-test fixture root discovery for pinned EEST
    layouts. The harness now detects both unpacked EEST archive roots
    (`fixtures/transaction_tests`) and geth-style checked-out spec-test roots
    (`spec-tests/fixtures/transaction_tests`), which prepares the next slice to
    load real pinned transaction vectors instead of seed vectors.
  - Progress: added a minimal EEST transaction-test file adapter. The harness
    now recognizes geth-style EEST JSON cases keyed by test name with `txbytes`
    plus per-fork `result` objects, validates case/result field shapes, and
    normalizes unprefixed EEST hash/sender hex into local `0x`-prefixed values
    before later vector conversion.
  - Progress: added conversion from normalized EEST transaction cases into the
    local transaction vector shape. The adapter now derives vector type and
    chain id from decoded `txbytes`, promotes a successful fork's hash/sender,
    requires all locally tracked fork results, and runs the existing local
    vector shape, fork-result, hash, sender, and intrinsic-gas checks.
  - Progress: added transaction-test root loading for EEST JSON files. The
    harness now recursively discovers JSON files under the selected
    `transaction_tests` root, loads all cases in deterministic path order, and
    converts the discovered cases into local transaction vectors through the
    same validation path used by the sample adapter.
  - Progress: wired the EEST transaction-test root loader into the optional
    external fixture test path. Runs without
    `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` now skip cleanly, while a
    configured root containing `transaction_tests` must load and convert at
    least one transaction vector.
  - Progress: reused the local transaction vector-set guards for EEST root
    imports. External transaction-test roots now run the same duplicate
    `name`, `txbytes`, and hash checks plus decoded vector validation as the
    in-repo transaction fixture, while leaving the seed fixture's stricter
    "all envelope families required" gate scoped to the seed wrapper.
  - Progress: preserved source-style names when loading EEST transaction-test
    roots. Root imports now sort case keys deterministically and name singleton
    files by their relative JSON path, while multi-case files use
    `relative/path.json/case-name`, matching the geth harness convention and
    preventing same-key cases in different files from colliding.
  - Progress: added source-name selectors for EEST transaction-test root
    loading. Callers can now pass explicit source-style case names to load and
    convert a bounded pinned subset first; missing selectors fail loudly so the
    Phase A pinned case list cannot silently drift.
  - Progress: centralized the Phase A EEST transaction selector list and wired
    the optional external transaction-test check through it. The current list
    names the in-repo `phase-a-sample.json` case; replacing it with real
    `v5.4.0` source-style names will make local and optional external runs use
    the same bounded pinned subset.
  - Progress: added validation for the Phase A EEST transaction selector list.
    The dedicated Phase A loader now rejects an empty list, blank selector
    names, and duplicate source-style names before attempting external fixture
    discovery.
  - Progress: added a transaction vector summary helper for pinned EEST
    subsets. The harness can now report the selected vector count, source-style
    names, and per-envelope-type counts, giving Phase A fixture expansion a
    stable coverage summary instead of only pass/fail validation.
  - Progress: wired the Phase A EEST transaction subset through a summary gate.
    The dedicated loader now checks that the loaded vector count and
    source-style names match the selector list and that at least one envelope
    type is represented, so future pinned selector updates cannot silently
    drift from the reported coverage summary.
  - Progress: expanded the in-repo EEST transaction-test sample used by the
    Phase A selector path from a legacy-only singleton to a source-style
    multi-case file covering both legacy EIP-155 and EIP-2930 access-list
    transactions. The root loader now exercises geth-style multi-case naming
    and typed transaction conversion directly before real pinned cases are
    swapped in.
  - Progress: added an EIP-1559 dynamic-fee case to the Phase A EEST
    transaction-test sample and selector list. The sample subset now covers
    legacy EIP-155 plus the two typed transaction families active at the
    Shanghai Phase A target, while still asserting pre-fork rejection on
    Frontier/Berlin where appropriate.
  - Progress: tightened the Phase A EEST transaction subset summary gate to
    require the Shanghai-active transaction families explicitly: legacy,
    EIP-2930 access-list, and EIP-1559 dynamic-fee. Selector changes that drop
    one of those families now fail before the optional external fixture path
    can report a misleading green summary.
  - Progress: tightened the same Phase A summary gate to reject Cancun/Prague
    only transaction families (`blob` and `set-code`) so the Shanghai fixture
    subset cannot silently widen past the Phase A scope gate.
  - Progress: tightened the Phase A transaction subset summary shape so type
    counts must be known, unique, and positive integers before required
    Shanghai families are checked.
  - Progress: tightened the Phase A transaction subset summary gate to require
    every selected vector to be valid on the target Shanghai fork with an
    explicit `intrinsicGas` result.
  - Progress: moved EEST transaction selector validation into the generic root
    loader so direct `:names` usage rejects blank or duplicate selectors before
    fixture discovery and filtering.
  - Progress: added EEST transaction-test file case-name validation. Imported
    transaction JSON files now reject blank, non-string, or duplicate top-level
    case names before normalization, so source-style selectors cannot be
    polluted by malformed fixture keys.
  - Progress: made EEST transaction-test selector filtering preserve selector
    order and reject duplicate loaded source-style case names, so Phase A
    subset summaries now fail if selected vector names do not exactly match
    the pinned selector list order.
  - Progress: tightened EEST transaction selector validation to require
    source-style JSON case names (`file.json` or `file.json/case`) and reject
    bare names, absolute paths, and parent-directory escapes before loading.
  - Progress: tightened the same selector shape to reject empty or doubled
    case separators such as `file.json/` and `file.json//case`.
  - Progress: tightened EEST transaction-test file loading so empty JSON files
    now fail loudly before normalization, preventing a discovered pinned source
    file from silently contributing zero cases to the selected subset.
  - Progress: tightened EEST transaction-test file entry validation so
    non-object top-level entries fail with an adapter-specific error before
    malformed JSON arrays can reach case-name normalization.
  - Progress: tightened EEST transaction-test case normalization so empty
    `result` objects are rejected before conversion, keeping malformed pinned
    cases from degrading into a later "no successful tracked fork" error.
  - Progress: tightened EEST transaction-test result fork validation so
    non-object result entries fail with an adapter-specific error before fork
    labels are read.
  - Progress: tightened EEST transaction-test case normalization itself to
    reject blank or non-string case names, so direct adapter calls preserve the
    same source-name invariant as file/root loading.
  - Progress: tightened EEST transaction-test result fork labels so direct
    adapter calls reject blank or non-string fork names before duplicate or
    known-fork validation runs.
  - Progress: tightened transaction fixture object-field validation so wrapper,
    vector, EEST case, and EEST result objects reject non-string field names
    before allowed-field checks run.
  - Progress: tightened EEST transaction selector-list shape validation so
    direct `:names` callers reject non-list selector values before iterating
    selector entries.
  - Progress: tightened EEST transaction selector entry validation so non-string
    selector names fail with an adapter-specific error before blank-name or
    source-style checks run.
  - Progress: lifted non-string fixture field-name rejection into the shared
    pinned EEST fixture validator, so transaction, trie, state, engine, and EVM
    metadata wrappers fail before allowed-field checks hit lower-level errors.
  - Progress: tightened EEST transaction selector source-style validation to
    reject doubled path separators, keeping selected names aligned with
    normalized relative fixture paths before root filtering.
  - Progress: tightened the Phase A EEST transaction subset summary gate so
    non-list vector inputs fail before summary construction, preserving a clear
    boundary for direct pinned-subset validator calls.
  - Progress: tightened EEST transaction root-file loading so generated
    source names must pass the same source-style selector validation before
    case normalization, catching mismatched root/path calls early.
  - Progress: tightened EEST transaction selector source-style validation so
    empty JSON file stems such as `.json/case` and `dir/.json/case` are
    rejected before Phase A pinned selector lists are accepted.
  - Progress: tightened EEST transaction selector source-style validation so
    the optional case suffix after `.json/` must be a single path segment,
    preventing malformed top-level case names from looking like nested files.
  - Progress: moved EEST transaction selector-list validation into the root
    case filter itself, so direct filter calls reject malformed selector
    inputs before matching against loaded cases.
  - Progress: tightened the transaction vector summary helper so direct calls
    reject non-list vector sets and non-object vector entries before counting
    names or envelope types.
  - Progress: tightened the transaction vector-set validator so direct callers
    reject non-list vector inputs before uniqueness, decoding, or per-fork
    checks run.
  - Progress: tightened transaction fixture result fork validation so malformed
    result entries, non-string fork labels, and blank fork labels fail before
    duplicate or known-fork checks run.
  - Progress: tightened transaction fixture result-shape validation so direct
    calls reject non-object vectors before required type/result field lookups.
  - Progress: reordered transaction fixture result fork validation so malformed
    fork entries are rejected before required-fork coverage checks scan the
    result map.
  - Progress: tightened transaction fixture type validation so non-string
    vector `type` values fail with a harness-level shape error before
    transaction type matching calls into `string=`.
  - Progress: tightened transaction fixture required string-field validation so
    non-string vector names fail with a harness-level shape error before blank
    string checks call into `length`.
  - Progress: tightened transaction fixture scalar hex-field validation so
    non-string or malformed `txbytes`, `hash`, and `sender` values fail with
    harness-level shape errors before lower-level hex/type parsers surface.
  - Progress: tightened transaction fixture metadata scalar validation so
    non-string wrapper `source`, `referenceClients.geth`, and
    `referenceClients.nethermind` values fail with harness-level shape errors,
    and locked malformed hash/sender wrapper errors with message checks.
  - Progress: tightened optional transaction fixture `referenceClients.reth`
    validation so the absent local Reth reference remains `null`, but provided
    values must be non-empty strings.
  - Progress: added an alignment check between the Phase A EEST transaction
    subset and the current seed transaction fixture. The harness now requires
    the Shanghai-active legacy, EIP-2930 access-list, and EIP-1559 dynamic-fee
    sample vectors to match the seed fixture on `txbytes`, hash, sender, chain
    id, and per-fork result matrix, creating a stronger bridge before the seed
    vectors are replaced by real pinned EEST cases.
  - Progress: added a named seed-vector coverage gate for the local transaction
    envelope fixture set. The runner now requires the legacy, EIP-2930,
    EIP-1559, EIP-4844, and EIP-7702 seed vector names in addition to type
    coverage, so fixture edits cannot silently replace one placeholder while
    preserving the same envelope-family matrix.

## P0: Module Boundaries

These tasks reduce long-term maintenance risk, but they should normally be
selected when they unblock the chain-store, Engine import, fixture harness, or
state/EVM correctness work above. Prefer extracting the **minimum boundary**
required by the current vertical slice (e.g. just the chain-rules entry points
used by Engine import) over a full behavior-preserving file move; full module
splits can land after the Phase A smoke path closes.

- [~] `MOD-CHAIN-CONFIG`: Split chain configuration and fork rules out of
  `src/core.lisp`.
  - Milestone: 5
  - References: geth `params`, Nethermind chain spec/config modules, Reth chain
    spec primitives.
  - Acceptance: `chain-config`, `chain-rules`, fork activation, and genesis
    config parsing live in a dedicated source file with no behavior change.
  - Validation: `sbcl --script tests/run-tests.lisp`.
  - Progress: started the module boundary by moving the pure `chain-config`,
    `chain-rules`, blob schedule entry structures, and fork activation
    predicates into `src/chain-config.lisp`. Genesis config parsing and blob
    schedule validation remain in `core.lisp` for a follow-up slice.
  - Progress: hardened the module-load validation path by making the
    EIP-7702 delegation prefix, Engine API payload status strings, and default
    Engine RPC host reload-safe under SBCL/ASDF. The main script test remains
    the primary validation, and ASDF load is now an additional module-boundary
    smoke check.
  - Progress: moved `chain-rules-transaction-type-supported-p` into
    `src/chain-config.lisp`, keeping typed-transaction fork activation rules
    with the chain-rules module boundary while preserving the existing public
    export and call sites.
  - Progress: moved `chain-config-rules` into `src/chain-config.lisp`, so the
    per-block fork-rule snapshot constructor now lives with the chain-rules
    structure and activation predicates. Blob schedule selection and genesis
    config parsing remain in `core.lisp` for follow-up slices.
  - Progress: moved blob schedule constants, `blob-schedule-values`, and
    `chain-rules-blob-schedule` into `src/chain-config.lisp`, keeping default
    blob schedule derivation with the fork-rule snapshot. Custom schedule
    validation/selection and genesis parsing remain in `core.lisp`.

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

- [x] `STORE-CHAIN-INTERFACE`: Define a chain-store interface over the current
  memory payload store.
  - Milestone: 6 / 7
  - References: geth `core/rawdb`, `core/blockchain.go`; Nethermind DB/provider
    abstractions; Reth provider traits.
  - Acceptance: known block, block-by-number, transaction location, receipts,
    state-available, head/safe/finalized, and prepared payload lookups go
    through a small chain-store boundary.
  - Progress:
    - Added a thin `chain-store-*` boundary over the memory payload store for
      known blocks, block-by-number, transaction locations, block receipts,
      state availability, forkchoice head/safe/finalized checkpoints, and
      prepared payloads.
    - Migrated public RPC block/transaction/receipt/log read paths, Engine
      payload-body lookups, forkchoice checkpoint checks, prepared payload
      lookups, and new-payload parent/state availability checks onto the
      chain-store boundary.
    - Added chain-store account balance/nonce/code/storage read/write wrappers
      and moved public account state RPC reads through that boundary.
    - Added chain-store head number and block-tag number wrappers, then moved
      public block-number/tag resolution, fee-history bounds, block filter
      cursors, and Engine payload-body range bounds through the boundary.
  - Follow-up:
    - Pending txpool and filter cursors remain in the in-memory store because
      they are pool/filter concerns rather than chain-store block/state indexes.
  - Validation: `sbcl --script tests/run-tests.lisp`.

- [x] `STORE-CANONICAL-INDEXES`: Add explicit canonical hash indexes.
  - Milestone: 6
  - Dependencies: `STORE-CHAIN-INTERFACE`.
  - References: geth canonical hash tables in `core/rawdb`; Reth provider
    canonical chain indexes.
  - Acceptance: block-number lookup uses a canonical hash index rather than
    implicitly trusting the latest inserted block at that number.
  - Progress:
    - Added an explicit number-to-canonical-hash index to the memory chain
      store. Block-number lookup now resolves canonical hash first, then block
      by hash, so same-height side-chain inserts remain retrievable by hash but
      do not replace the canonical block-number view.
  - Validation: add competing same-number block coverage and run
    `sbcl --script tests/run-tests.lisp`.

- [x] `STORE-CHECKPOINTS`: Represent canonical head, safe head, and finalized
  head as typed store checkpoints.
  - Milestone: 6 / 7
  - Dependencies: `STORE-CHAIN-INTERFACE`.
  - Acceptance: forkchoice checkpoint data is not just loose hash slots on the
    memory store; block tag resolution uses the checkpoint abstraction.
  - Progress:
    - Added a `chain-store-checkpoint` structure for `head`, `safe`, and
      `finalized`, replaced the memory store's loose checkpoint hash slots with
      typed checkpoint slots, and routed block tag / checkpoint block
      resolution through the checkpoint abstraction.
  - Validation: existing forkchoice/block tag tests plus
    `sbcl --script tests/run-tests.lisp`.

- [x] `STORE-CANONICAL-REORG`: Add a first reorg-aware canonical update path.
  - Milestone: 6
  - Dependencies: `STORE-CANONICAL-INDEXES` and `STORE-CHECKPOINTS`.
  - References: geth `BlockChain.SetCanonical`, Reth canonical chain provider.
  - Acceptance: switching canonical head rewrites number-to-hash indexes for
    the affected in-memory range and leaves side-chain blocks retrievable by
    hash.
  - Progress:
    - Added `chain-store-set-canonical-head`, which walks a known candidate
      head back to an already-canonical ancestor, rewrites the affected
      number-to-hash indexes, removes stale canonical markers above the new
      head, and updates the typed head checkpoint. Known side-chain blocks
      remain retrievable by hash.
  - Validation: add two-branch in-memory tests and run
    `sbcl --script tests/run-tests.lisp`.

- [x] `STORE-REORG-INVARIANTS`: Lock reorg invariants on canonical, safe, and
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
  - Progress:
    - Transaction-location lookup now filters out non-canonical blocks. After a
      canonical switch, orphaned branch transactions remain stored with their
      blocks but `chain-store-transaction-location`,
      `eth_getTransactionByHash`, and `eth_getTransactionReceipt` only expose
      transactions from the current canonical number-to-hash view.
    - Forkchoice checkpoint updates now reject `safe` or `finalized` hashes
      that are not ancestors of the requested head. Invalid checkpoint updates
      return Engine invalid-forkchoice-state errors and leave the previous
      typed checkpoints intact.
  - Validation: two-branch reorg fixtures plus
    `sbcl --script tests/run-tests.lisp`.

## P0: Engine Payload Import

- [x] `ENGINE-EXECUTE-NEWPAYLOAD`: Route `engine_newPayload` through block
  execution when parent state is available.
  - Milestone: 6 / 7
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
  - Progress: added the parent-state materialization step needed before
    Engine can execute imported payloads. The chain-store can now iterate the
    retained account projection for a state-available block, and execution can
    rebuild a `state-db` from balance, nonce, code, and storage indexes.
    Remaining work: call this helper from `engine_newPayload` for known-parent
    state, then run the payload through `execute-and-commit-signed-block`.
  - Progress: added `execute-and-commit-engine-payload`, which reconstructs
    the parent state and executes an Engine payload block through the signed
    block atomic commit path. `engine_newPayload` memory status now accepts an
    injectable import function, returns `VALID` after a successful executable
    import, and maps execution commitment failures to Engine `INVALID` without
    storing the bad block. Tests cover a ready-parent empty payload execution
    and a bad state-root rollback. Remaining work: wire the production RPC
    dispatcher to this import function and replace the empty payload smoke with
    the one-transaction `newPayloadV2` fixture.
  - Progress: threaded the executable import hook through the JSON-RPC and
    HTTP request/service entry points. Default `engine_newPayload` behavior
    remains compatibility-only storage, while configured services can now pass
    the real Engine payload importer through parsed request objects, JSON
    strings, HTTP request strings, and stream handling. Remaining work: make
    the production service constructor choose the execution importer by
    default once package layering is settled, and replace the empty payload
    smoke with the one-transaction `newPayloadV2` fixture.
  - Progress: added the first one-transaction `engine_newPayloadV2` JSON-RPC
    smoke through the configured execution importer. The test builds a
    Shanghai-shaped payload from a known parent state, includes a real EIP-155
    legacy transfer plus withdrawals, imports it through
    `engine-rpc-handle-request`, and asserts the executed child block, sender
    nonce/balance, recipient balance, withdrawal balance, state availability,
    and transaction lookup index are committed. Remaining work: make the
    production service constructor choose the execution importer by default
    once package layering is settled, and lift this smoke to a pinned fixture
    runner case that also drives forkchoice/canonical/public-RPC checks.
  - Progress: made the production Engine HTTP service constructor default to
    the executable payload importer when the execution package is loaded,
    while retaining an explicit `:import-function nil` compatibility escape
    hatch. The service configuration test now asserts the default importer is
    exactly `execute-and-commit-engine-payload`, not merely any function.
  - Progress: lifted the one-transaction Shanghai `engine_newPayloadV2`
    smoke into a pinned `engine-newpayload-v2` fixture. The fixture-driven
    test executes a real EIP-155 legacy transfer plus withdrawal from a
    known parent state, imports the executable payload through Engine RPC,
    validates committed account balances, receipt roots, state availability,
    and known-block storage, then applies `engine_forkchoiceUpdatedV1` and
    verifies canonical `eth_getTransactionReceipt` and `eth_getBalance`
    responses at `latest`.
  - Progress: added pinned EEST source metadata validation to the
    `engine-newpayload-v2` smoke fixture wrapper. The Engine fixture now
    machine-checks the Phase A release/tag/archive metadata, top-level wrapper
    fields, and reference-client pins before executing the smoke case.
  - Progress: tightened the Engine `engine-newPayloadV2` fixture loader so the
    `cases` list is validated before selection. The fixture now rejects empty
    case arrays, duplicate case names, blank/non-string names, and unknown
    case fields before the executable smoke replay can silently consume a
    malformed imported wrapper.
  - Progress: extended the same Engine fixture validation into the case body.
    `config`, `parent`, parent account, `payload`, withdrawal, and `expect`
    objects now reject unknown fields and malformed quantities, addresses,
    transaction bytes, withdrawal arrays, or non-`VALID` expected statuses
    before the smoke path constructs local blocks from fixture data.
  - Progress: tightened Engine fixture body validation against silent
    overwrites. Parent account lists now reject duplicate normalized addresses,
    and withdrawal lists reject duplicate withdrawal indexes before fixture
    replay can collapse conflicting entries into one local state transition.
  - Progress: added parent/payload coherence checks to the Engine
    `newPayloadV2` fixture gate. Fixture cases now reject non-contiguous child
    block numbers, non-increasing timestamps, invalid parent-relative gas
    limit changes, and payload base-fee values that do not match the parent.
  - Progress: added expectation coherence checks for the one-transfer Engine
    smoke fixture. Expected sender, nonce, recipient, balances, withdrawal
    credit, and typed receipt fields are now derived from the decoded
    transaction, parent state, and withdrawal list before fixture replay.
  - Progress: extended the fixture-driven `engine_newPayloadV2` smoke after
    forkchoice with canonical public RPC reads: `eth_getBlockByNumber`,
    `eth_getBlockByHash`, block transaction counts, raw transaction by block,
    transaction-by-block, and transaction-by-hash now all assert the imported
    block and transaction are visible through the canonical `latest` view.
  - Progress: extended the same Engine fixture parent-state shape with
    optional account code and storage entries, then asserted `eth_getCode` and
    `eth_getStorageAt` at `latest` after executable import and forkchoice. The
    Phase A smoke now verifies retained state snapshots expose balance, nonce,
    code, and storage through public RPC reads.
  - Progress: extended the fixture-driven Engine smoke with an imported
    sibling payload sharing the same parent. After forkchoice selects the
    transaction-bearing child, the side-chain block remains retrievable by
    hash and reports its own transaction count, while canonical `latest`
    block and transaction reads continue to resolve to the selected child.
  - Progress: extended the same fixture smoke into a two-branch canonical
    switch. Forkchoice can move from the transaction-bearing child to the
    sibling payload and back again; `latest`, canonical number indexes,
    transaction-by-hash, and receipt visibility now follow the selected branch
    while non-canonical blocks remain hash-retrievable.
  - Progress: added fixture-driven safe/finalized checkpoint assertions to the
    same branch-switch smoke. Forkchoice now carries the parent as both safe
    and finalized while switching heads, and public `safe` / `finalized` block
    tags are checked against that ancestor.
  - Progress: expanded the Engine `newPayloadV2` fixture smoke from a single
    legacy transfer case to a two-case set by adding a Shanghai EIP-1559
    dynamic-fee transfer with withdrawal. The same executable import,
    forkchoice, public RPC, side-chain, branch-switch, and checkpoint-tag
    assertions now run against both fixture cases.
  - Progress: expanded the Engine `newPayloadV2` fixture smoke with a
    Shanghai contract-creation transaction. The fixture validator now handles
    recipient-versus-contract expectations, and the smoke asserts
    `contractAddress` / null `to` receipt shape plus canonical visibility
    through the same branch-switch path.
  - Progress: added an Engine smoke coverage guard. Fixture validation now
    requires the selected smoke cases to include legacy transfer, dynamic-fee
    typed transfer, and contract-creation families, and rejects duplicate or
    missing smoke case selectors before replay.

- [x] `ENGINE-INVALID-POST-EXECUTION`: Map post-execution validation failures
  to Engine `INVALID` payload status.
  - Milestone: 7
  - Dependencies: `ENGINE-EXECUTE-NEWPAYLOAD`.
  - Acceptance: bad state root, receipts root, logs bloom, or gas used returns
    Engine-style `INVALID` with latest-valid hash behavior matching the current
    invalid-ancestor cache model.
  - Validation: add invalid payload status tests and run
    `sbcl --script tests/run-tests.lisp`.
  - Progress: covered all four post-execution commitment mismatch classes on
    the executable Engine import path. Bad state root, receipts root, logs
    bloom, and gas used now each return `INVALID`, report the specific
    validation error, set `latestValidHash` to the known parent, avoid storing
    the bad block, and cache it as invalid.

- [x] `ENGINE-PERSIST-EXECUTED-BLOCK`: Persist block receipts and state
  snapshots from executed Engine payloads.
  - Milestone: 5 / 6 / 7
  - Dependencies: `ENGINE-EXECUTE-NEWPAYLOAD`.
  - Acceptance: `eth_getTransactionReceipt`, `eth_getBlockReceipts`,
    `eth_getBalance`, `eth_getCode`, `eth_getStorageAt`, and
    `eth_getTransactionCount` can answer against blocks imported via
    `engine_newPayload`.
  - Validation: add Engine-imported block RPC tests and run
    `sbcl --script tests/run-tests.lisp`.
  - Progress: extended the executed Engine forkchoice fixture to cover the
    public RPC persistence surface for canonical imported blocks. After
    `engine_newPayloadV2` and forkchoice select the transaction branch, public
    RPC can answer `eth_getTransactionReceipt`, `eth_getBlockReceipts`,
    `eth_getBalance`, `eth_getTransactionCount`, `eth_getCode`, and
    `eth_getStorageAt` at `latest`; after forkchoice switches to the empty
    sibling, receipts/transaction lookup and state reads follow the selected
    sibling. The fixture now carries non-empty contract code and storage through
    both imported branches, so `eth_getCode` and `eth_getStorageAt` cover
    non-default persisted values.

- [x] `ENGINE-FORKCHOICE-CANONICAL`: Make `engine_forkchoiceUpdated` update
  canonical chain state, not only block tags.
  - Milestone: 6 / 7
  - Dependencies: `STORE-CANONICAL-REORG`.
  - Acceptance: VALID forkchoice head rewires canonical indexes and public
    `latest`/`pending` views follow that canonical head.
  - Validation: forkchoice branch switch tests plus
    `sbcl --script tests/run-tests.lisp`.
  - Progress: VALID `engine_forkchoiceUpdated` now calls the chain-store
    canonical head rewrite after safe/finalized checkpoint validation. The
    canonical rewrite path also accepts the sparse parent-zero fixtures used by
    the current memory-store tests. Coverage asserts forkchoice head 32
    rewires the canonical hash at that height, clears a stale higher canonical
    entry, and keeps public `latest`/`pending`/`eth_blockNumber` views on the
    forkchoice head. Remaining work: add an explicit two-branch Engine import
    fixture that switches between competing executed payloads and verifies
    transaction/receipt visibility follows the selected branch.
  - Progress: added the explicit two-branch executed Engine import fixture.
    Two `engine_newPayloadV2` children are imported from the same known parent:
    one contains a real signed transfer, the other is an empty sibling with
    withdrawals. Forkchoice first selects the transaction branch and public
    `eth_getTransactionByHash`, `eth_getTransactionReceipt`, and
    `eth_getBalance` at `latest` expose that branch; after switching to the
    empty sibling, the transaction and receipt disappear from canonical
    lookups and `latest` balance follows the selected sibling. Remaining work:
    extend this fixture into a multi-height reorg and block-receipt/log
    visibility check.
  - Progress: extended the executed Engine import fixture into a multi-height
    reorg. The transaction branch now imports an additional executed child at
    block 43; forkchoice can advance `latest`/`eth_blockNumber` to that child,
    then switch back to the competing block-42 sibling and clear the stale
    canonical block-43 index.
  - Progress: completed the log-producing Engine forkchoice fixture. A signed
    transaction now calls contract code that emits `LOG1`; after forkchoice
    selects that branch, `eth_getLogs` at `latest` returns the emitted log with
    the expected address, topic, data, block hash, and transaction hash. After
    forkchoice switches to the competing sibling, the canonical `latest` log
    query returns no logs.

## P0: State, Trie, And Proof Correctness

- [~] `TRIE-FIXTURE-GRADE`: Replace the minimal trie root prototype with
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
  - Progress: added explicit `mpt-delete`, in-repo trie vector fixtures for
    single-leaf, branch/extension shared-prefix, delete-collapse, and
    delete-to-empty-root cases, tests that compare expected root and root node
    shape, and state-root coverage ensuring zero-value storage writes do not
    create empty accounts while deletion prunes storage-created empty accounts.
    Added in-repo state-root fixture vectors for empty state, account
    nonce/balance, account storage, storage-created account pruning, and
    funded-account storage deletion. Empty-code writes now avoid creating
    accounts, code-created empty accounts are pruned after code deletion, and
    state-root fixture vectors cover code-root creation/deletion cases. Added
    `state-db-get-storage-root` and fixture assertions for per-account storage
    roots so Phase A genesis/proof work can compare state and storage
    commitments separately; account reads now return a committed account view
    whose `storage-root` reflects the current storage trie. Added an in-repo
    Phase A Shanghai genesis fixture with a locked `stateRoot`, funded account,
    code account, nonzero and zero storage entries, genesis header/block root
    checks, and contract storage-root checks. Added trie fixture coverage for
    the RLP child-reference threshold: compact extension children remain
    embedded, while larger children are referenced by their 32-byte Keccak hash.
    Added hex-key trie fixture operations and a sparse root-branch vector that
    asserts only the expected child slots are populated. Added prefix-key
    branch value coverage so a key ending at a branch preserves its value slot
    while longer sibling keys remain under child references. Added delete
    coverage for the inverse branch-value case: removing the root branch value
    collapses the remaining single child path back to a leaf with a locked root.
    Added duplicate-key overwrite coverage that locks the final leaf value and
    root hash after a later `put` replaces an earlier value for the same key.
    Added geth-aligned no-op delete coverage for a missing key, asserting that
    the existing leaf root, path, and value remain unchanged.
    Added branch missing-child delete no-op coverage, asserting that deleting a
    non-existent child slot from a sparse root branch preserves the original
    root and populated child indexes.
    Added branch child deletion coverage for the complementary root-value case:
    when deleting the only child from a root branch that still has a value slot,
    the branch collapses back to a terminator-only leaf with the root value
    preserved.
    Added the same branch-child deletion shape to the selected Phase A EEST
    trie subset, with a summary gate that fails if the root-value-preserving
    branch child delete case is dropped.
    Added fixture assertions for compressed root path nibbles on leaf and
    extension roots, locking the path-compression shape in addition to root
    hashes and node kinds.
    Added a multi-account secure state-root fixture that asserts account nonce,
    balance, storage root, code hash, and account RLP projections alongside the
    final root.
    Added account-update state-root coverage that replays repeated
    `setAccount` operations for the same address and asserts the final
    nonce/balance, empty storage/code commitments, account RLP, and state root.
    Added storage-update state-root coverage that writes the same storage slot
    twice, then asserts the final slot value, storage root projection, account
    RLP, and state root so storage overwrite semantics cannot regress.
    Added code-update state-root coverage that overwrites non-empty account code
    and asserts the final code hash, retained code bytes, account RLP, and
    state root.
    Added account-prune state-root coverage for the EIP-161-style empty-account
    clearing case: an explicit `clearAccount` fixture operation now prunes a
    non-empty account back to the empty state root while preserving direct
    `setAccount` empty-account existence semantics needed by `EXTCODEHASH`.
    Extended `clearAccount` state-root coverage to an account with both
    non-empty code and storage, and tightened final-state assertions so storage
    slots touched before a final account prune must read back as zero.
    Added multi-account `clearAccount` state-root coverage that prunes one
    account with code/storage while preserving a sibling account's storage
    root, account RLP projection, and final state root.
    Added direct state DB regression coverage for `state-db-clear-account`,
    checking missing-account no-op behavior plus removal of account, code,
    storage, and state-root entries.
    Added shared fixture metadata validation for trie and state-root vectors:
    both wrappers now machine-check the Phase A EEST release `v5.4.0`, tag
    target `88e9fb8`, and `fixtures_stable.tar.gz` archive before consuming
    seed cases.
    Added the same pinned-source metadata guard to the Phase A Shanghai
    genesis fixture before validating its state root, header root, account
    allocation, code hash, and storage root.
    Added Phase A Shanghai genesis fixture shape validation for top-level,
    config, account, and storage fields so the Phase A smoke genesis vector
    rejects wrapper drift before state-root assertions run.
    Added branch child-reference assertions to trie fixtures, including a
    mixed embedded/hashed branch case where a large child leaf crosses the
    32-byte RLP reference threshold while a sibling remains embedded.
    Added fixture-driven trie lookup assertions so shared-prefix, deletion,
    and mixed child-reference cases verify `mpt-get` results in addition to
    root hash and node-shape commitments.
    Added operation-derived final lookup assertions to the trie fixture
    runner. Every fixture case now replays its `put`/`delete` operations into
    an expected final key set and checks `mpt-get` for all touched keys,
    matching geth's update/delete/get semantics and preventing root-only
    vectors from hiding lookup regressions.
    Added operation-derived final account/code/storage assertions to the
    state-root fixture runner. State fixtures now replay `setAccount`,
    `setCode`, and `setStorage` into an expected final account model, then
    verify the local state DB read APIs for every touched account and storage
    slot in addition to the final root.
    Added state-root fixture operation-shape validation. State fixtures now
    reject malformed cases, short addresses, short storage slots, missing
    storage values, negative nonce / balance / storage quantities, malformed
    code hex, and malformed expected roots before replaying state operations.
    Added semantic coverage tags to trie vector cases plus runner-side guards
    for duplicate case names, unknown tags, and required MPT shape coverage.
    The trie fixture now fails early if leaf, branch, extension, deletion
    collapse, delete-to-empty, embedded-vs-hashed child reference, branch
    value, missing-delete no-op, duplicate-overwrite, hex-key, lookup, or
    mixed branch child-reference coverage is accidentally dropped.
    Added trie fixture operation-shape validation. Trie vector cases now reject
    missing or ambiguous key fields, `put` operations without `valueAscii`,
    `delete` operations that still carry a value, malformed expected lookup
    entries, and `expectedMissing` entries that accidentally encode a value.
    Added trie fixture expected-result validation. Trie vector cases now reject
    malformed expected roots, unknown root shapes, child-reference assertions
    on non-matching root shapes, malformed branch child indexes, malformed
    child-reference kinds, and invalid compressed root path nibbles before
    replaying operations.
    Added trie fixture field-whitelist validation. Trie cases, operations,
    expected lookup entries, and expected-missing entries now reject unknown
    fields before replay, preventing misspelled imported fixture assertions
    from being silently ignored.
    Added trie fixture wrapper metadata validation. The runner now checks the
    top-level fixture field set, format string, non-empty source note, and
    pinned EEST release/archive metadata before consuming trie cases.
    Added state-root fixture wrapper and projection-shape validation. The
    state-root runner now checks the top-level wrapper, source metadata, case
    and operation field sets, expected storage roots, and expected account
    projections before replaying state operations.
    Added duplicate-field rejection to trie and state-root fixture object
    validators. Wrappers, cases, operations, lookup expectations, storage-root
    projections, and account projections now fail before alist lookup can
    silently select one duplicate key and hide another.
    Added duplicate semantic-tag rejection to trie and state-root fixture
    cases so coverage maps cannot silently collapse repeated tags within a
    single case.
    Added duplicate-field and duplicate-key rejection to the Phase A Shanghai
    genesis fixture validators, including top-level/config/account fields,
    duplicate alloc addresses, and duplicate storage slots.
    Added semantic coverage tags to state-root fixture cases plus runner-side
    guards for duplicate case names, unknown tags, and required secure-state
    coverage. State-root fixtures now fail early if empty state, account root,
    storage root/delete/prune, code root/delete/prune, multi-account, account
    projection, or storage-root projection coverage is dropped.
    Added duplicate address rejection for state-root fixture account and
    storage-root projection lists, so imported fixture expectations cannot
    assert the same account twice with conflicting roots or balances.
    Added duplicate child-reference index rejection to trie fixture branch
    projection validation, including numeric aliases such as `1` and `01`.
    Added duplicate lookup-key rejection across trie fixture `expectedGets`
    and `expectedMissing`, including equivalent `keyAscii` / `keyHex` forms.
    Added trie-test root discovery for pinned EEST layouts. The harness now
    detects both unpacked EEST archive roots (`fixtures/trie_tests`) and
    geth-style checked-out spec-test roots (`spec-tests/fixtures/trie_tests`),
    and optional external trie tests skip cleanly when no configured root is
    present.
    Added recursive JSON discovery for EEST trie-test roots, including stable
    source-style relative filenames and a loud error for empty roots. This
    prepares the next adapter slice to consume pinned trie files deterministically.
    Added a minimal EEST trie-test file adapter. It now loads JSON files keyed
    by case name, validates the thin root-only case shape, normalizes unprefixed
    root hashes, and preserves source-style root case names for deterministic
    pinned-subset selection in follow-up slices. Reference availability for
    this adapter check: geth `8a0223e`, Nethermind `1c72a72`; local Reth clone
    absent.
    Added source-name selectors for EEST trie-test root loading. Phase A now
    has a centralized trie selector list and a dedicated loader that rejects
    empty, blank, duplicate, or missing source-style case names before a pinned
    trie subset can be consumed silently.
    Added a trie-test case summary helper for selected EEST subsets. The
    harness can now report selected case count, source-style names, and
    expected roots, giving external trie fixture runs a stable coverage summary
    before the adapter grows beyond root-only cases.
    Added duplicate source-name rejection for EEST trie-test root imports. Root
    loads now fail before selector filtering if two discovered cases normalize
    to the same source-style name.
    Added minimal `in` entry support to the EEST trie-test adapter. Root-only
    cases now carry key/value pairs that can be replayed into the local MPT and
    checked against the expected root, starting with a `dog` -> `puppy` sample
    vector.
    Added delete/null entry support to the EEST trie-test adapter. JSON `null`
    values in `in` entries now normalize to delete operations and replay
    through `mpt-delete`, with the sample vector covering `dog` -> `puppy`
    followed by delete back to the empty trie root.
    Added byte-string decoding for EEST trie-test `in` entries. `0x`-prefixed
    keys and values now decode as hex bytes while unprefixed strings continue
    to replay as ASCII, and malformed hex is rejected during fixture
    normalization.
    Added geth/Nethermind-aligned empty-value delete handling for EEST
    trie-test entries. Zero-length byte strings, including `""` and `"0x"`,
    now normalize to delete operations instead of value inserts.
    Added file-level duplicate case-name rejection to the EEST trie-test
    adapter so duplicate JSON case keys fail before direct file or root imports
    can silently consume ambiguous fixtures.
    Added selected EEST trie-test root replay assertions. Phase A trie root
    cases now run through the adapter and compare computed MPT roots against
    expected roots when an external trie-test root is configured, while still
    skipping cleanly without one.
    Added multi-case EEST trie-test file coverage. Root imports now exercise
    source-style `file.json/case` naming for files containing more than one
    case while preserving singleton file names for selected Phase A vectors.
    Added empty EEST trie-test file rejection so direct file and root imports
    fail loudly when a discovered JSON file contains no cases.
    Canonicalized EEST trie-test expected roots after hash32 validation so
    mixed-case or `0X`-prefixed fixture hashes compare against replayed MPT
    roots using the local stable lowercase `0x` representation.
    Canonicalized EEST trie-test `in` entry byte strings as well: prefixed
    hex keys and values now normalize to lowercase `0x` strings before replay,
    while unprefixed ASCII fixture strings remain unchanged.
    Hardened EEST trie-test root validation so null, blank, non-string, and
    malformed roots fail through adapter-specific errors before hash decoding.
    Wrapped malformed EEST trie-test root hash decoding with the source case
    name, so bad pinned vectors report the failing trie case instead of only a
    lower-level hex/hash error.
    Added EEST trie-test `in` entry indexes to adapter errors, so malformed
    key/value pairs in long pinned vectors identify the exact failing entry.
    Added case-specific EEST trie-test replay mismatch errors that report the
    failing case name plus expected and actual roots instead of a generic
    assertion failure.
    Moved EEST trie-test selector validation into the generic root loader so
    direct `:names` usage rejects blank or duplicate selectors before loading.
    Extended EEST trie-test subset summaries with per-case entry counts, making
    it visible whether selected pinned cases are empty roots or replay actual
    `in` operations.
    Added aggregate entry counts to EEST trie-test subset summaries, so selected
    pinned subsets report both per-case operation counts and total replay volume.
    Added write/delete entry counts to the same summaries, making it visible
    whether selected trie-test roots exercise deletion paths instead of only
    insert/update replay.
    Added string-valued object-form `in` support to the EEST trie-test adapter,
    matching the Nethermind classic TrieTest JSON path alongside the existing
    array-of-pairs path, with duplicate object-key rejection before replay.
    Added optional secure-key replay for EEST trie-test cases, hashing keys
    with Keccak before MPT insertion/deletion to match geth StateTrie /
    Nethermind secure trie fixture semantics for secure trie vectors.
    Added operation-derived final lookup checks to EEST trie-test replay, so
    each touched plain or secure key is verified for final value/missing status
    in addition to the expected root hash.
    Added secure-trie filename inference for EEST trie-test files: `secureTrie`
    source files default cases to secure-key replay unless an individual case
    explicitly overrides the `secure` flag.
    Expanded the Phase A selected EEST trie-test subset to replay both the
    plain sample vector and the secureTrie sample vector by default.
    Extended EEST trie-test subset summaries with secure/plain case counts so
    Phase A reports show whether secure-key replay coverage is present.
    Added Phase A EEST trie subset coverage validation: the selected set must
    include secure and plain trie cases plus write and delete entries.
    Added null-valued object-form `in` support to the EEST trie-test adapter,
    so JSON object entries can express deletes just like array-form
    `[key, null]` pairs.
    Tightened Phase A EEST trie subset summaries with secure/plain write and
    delete counters, and made coverage validation require secure trie writes
    plus plain trie deletes explicitly instead of only aggregate write/delete
    activity.
    Expanded the in-repo secureTrie EEST sample from a singleton insert case
    into source-style insert and delete cases, and tightened Phase A coverage
    to require secure trie deletes explicitly.
    Tightened Phase A EEST trie subset coverage again so plain trie writes are
    required explicitly, matching the existing plain delete and secure
    write/delete gates.
    Added a selected plain trie case with a non-empty final root and tightened
    the Phase A EEST subset gate so both secure and plain selections must
    include non-empty final roots, not only write/delete operations that net
    back to the empty trie.
    Expanded the selected plain EEST-style trie cases with branch-root and
    shared-prefix extension-root vectors, and made the Phase A subset summary
    replay root shapes so branch and extension coverage cannot silently drop.
    Added a selected EEST-style delete-collapse case whose final root remains
    non-empty, then tightened the Phase A subset gate to require deletion
    replay that exercises path compression instead of only delete-to-empty
    roots.
    Added a selected embedded-extension EEST-style case and tightened the
    Phase A subset summary/gate to require both embedded and hashed extension
    child references after replay, covering the MPT child-reference threshold
    explicitly in the selected external-style trie set.
    Added normalized duplicate-key rejection for EEST trie object-form `in`
    entries, so ASCII/hex aliases such as `dog` and `0x646f67` cannot replay
    as ambiguous duplicate keys.
    Added a selected mixed branch-child-reference EEST-style trie case and
    tightened the Phase A subset summary/gate to require both embedded and
    hashed branch child references after replay.
    Added a selected branch-value EEST-style trie case and tightened the Phase
    A subset summary/gate to require a replayed branch root value slot, covering
    the empty-key branch value shape in the external-style subset.
    Tightened EEST trie selector validation to require source-style JSON case
    names (`file.json` or `file.json/case`) and reject bare names, absolute
    paths, parent-directory escapes, empty case suffixes, and doubled case
    separators before loading.
    Added a selected branch-value deletion EEST-style trie case and tightened
    the Phase A subset summary/gate to require an empty-key delete whose final
    root remains non-empty, covering branch-value collapse after deletion.
    Added a selected secureTrie branch-root case and tightened the Phase A
    subset summary/gate to require secure-key replay that forms a branch root,
    broadening secure coverage beyond singleton leaf and delete-to-empty roots.
    Added a selected secureTrie extension-root case and tightened the Phase A
    subset summary/gate to require secure-key replay that forms an extension
    root, covering secure path compression beyond branch roots.
    Tightened the same summary/gate to track secure extension child-reference
    kinds separately and require a secure hashed extension child reference.
    Tightened secure branch-root summaries the same way: secure branch
    child-reference kinds are now tracked separately and must include hashed
    child references.
    Added a selected secureTrie delete-branch-child case whose final root
    remains non-empty, and tightened the Phase A subset summary/gate to require
    secure delete replay that preserves a non-empty final root.
    Added secure-key replay support to the seed trie-vector fixture runner
    itself, plus a secure delete-collapse vector that hashes logical keys before
    MPT replay and checks final secure-key lookups.
    Added secure branch-root and extension-root cases to the seed trie-vector
    fixture, with runner-side coverage guards requiring secure branch and
    secure extension roots so the local seed set stays aligned with the
    selected EEST-style secure trie subset.
    Added fixture-driven MPT proof assertions to trie vector lookups: every
    explicit `expectedGets` / `expectedMissing` entry now verifies the generated
    proof against the final root in addition to checking `mpt-get`, covering
    present and missing proofs across the seed fixture's plain, secure,
    shared-prefix, deletion, and child-reference cases. This also fixed branch
    value proof verification by reading the 17th RLP branch item portably.
    Added the same present/missing proof verification to EEST-style trie-test
    replay, so selected plain and secure external-style cases now check
    `mpt-get-proof` / `mpt-verify-proof` against every final touched key in
    addition to root and lookup assertions.
    Added secure single-leaf and secure delete-to-empty cases to the seed
    trie-vector fixture, and tightened seed coverage guards so secure leaf,
    branch, extension, and delete-to-empty root shapes all remain present.
    Tightened EEST trie selector validation to reject non-list selector sets,
    non-string selector names, doubled path separators, and nested case suffix
    paths, matching the stricter transaction selector boundary before pinned
    trie subset selection.
    Aligned trie source-style selector validation with transaction-test
    selector rules by rejecting `.json` names without a real file stem,
    including nested `dir/.json/case` selectors.
    Added account projection assertions to the funded-account storage-delete
    state-root vector, locking that zeroing the last storage slot restores the
    account storage root to the empty trie without pruning the non-empty
    account itself.
    Added matching account projection assertions to the funded-account
    code-delete state-root vector, locking that clearing code restores the empty
    code hash without pruning the non-empty account itself.
    Added a named seed-case coverage gate for the local state-root fixture set,
    so account, storage, code, prune, update, and multi-account vectors cannot
    silently disappear while still satisfying generic tag coverage.
    Added the same named seed-case coverage gate to the local trie-vector
    fixture set, locking the current leaf, branch, extension,
    child-reference, deletion, branch-value, duplicate-overwrite, and secure
    replay seed cases before they are replaced or extended with pinned EEST
    vectors.
    Remaining work: replace/extend the in-repo vectors with pinned
    execution-spec-tests trie fixtures and broaden secure/account trie root
    coverage against external references.

- [~] `STATE-PROOFS`: Add account/storage proof generation and verification.
  - Milestone: 3 / 7
  - Dependencies: `TRIE-FIXTURE-GRADE`.
  - References: geth `eth_getProof`, trie proof APIs; Nethermind proof APIs.
  - Acceptance: local state can produce and verify account/storage proofs for
    retained state snapshots.
  - Validation: dedicated proof tests and `sbcl --script tests/run-tests.lisp`.
  - Progress: added the first MPT proof primitive: `mpt-get-proof` emits the
    RLP node proof for a key path and `mpt-verify-proof` verifies present and
    missing keys against a root hash, including empty-root absence, bad-root,
    and unconsumed-node checks. Added a state account proof primitive:
    `state-db-get-account-proof` emits account trie proofs and
    `state-db-verify-account-proof` verifies present and missing addresses
    against a state root. Added a state storage proof primitive:
    `state-db-get-storage-proof` emits secure storage trie proofs and
    `state-db-verify-storage-proof` verifies present and missing slots against
    a storage root. Added `state-db-get-proof` / `state-db-verify-proof`
    proof-result structs that bundle decoded account fields, storage slot
    values, account proofs, and storage proofs in an `eth_getProof`-style
    shape. Added `state-proof-result-rpc-object` to encode the bundle using
    `eth_getProof` field names and hex/quantity values. Wired `eth_getProof`
    into the JSON-RPC dispatcher for retained chain-store state snapshots,
    including account proofs, storage proofs, missing accounts, missing state,
    and parameter validation. Aligned `eth_getProof` storage-key handling with
    geth's reference behavior: requests are capped at 1024 keys, short keys are
    returned as quantities, 32-byte keys are returned as fixed DATA, and
    no-prefix hex input is accepted before secure storage proof lookup.
    Added an external-style state proof fixture wrapper with pinned EEST source
    metadata, geth-shaped `AccountResult` / `StorageResult` expected objects,
    shape validation, coverage tags, and exact proof-vector replay for present
    accounts, missing accounts, present storage, and missing storage. Added a
    multi-storage fixture case that proves two present storage slots and one
    missing slot for the same account, and tightened the required fixture tags
    so multi-present-storage proof replay cannot silently drop. Added a direct
    verifier regression that checks multiple storage proof entries together and
    rejects tampered storage values or account-bound storage roots. Tightened
    state-proof fixture shape validation so each expected proof address,
    storage proof count, and storage proof key order must match the original
    request. Added a deleted-storage proof fixture case for a present account
    whose storage trie returns to the empty root, and made that missing-after-
    delete proof coverage a required state-proof fixture tag. Added normalized
    duplicate storage-key rejection for state-proof fixture requests, preventing
    exact proof vectors from inflating coverage with repeated keys. Tightened
    state-proof fixture proof-node validation so account and storage proof
    entries must be valid RLP nodes, not merely hex byte strings. Tightened
    storage proof shape validation so non-zero expected storage values must
    include proof nodes. Tightened account proof shape validation the same way:
    expected non-empty account fields now require account proof nodes, so
    transcribed `eth_getProof` fixtures cannot claim nonce, balance,
    storage-root, or code-hash state without carrying the proof nodes that
    verify those fields. Tightened missing-storage proof validation for
    non-empty storage tries as well: zero-valued storage proof entries now
    require proof nodes whenever the enclosing `storageHash` is non-empty, so
    missing-slot proofs cannot be confused with empty-trie absence. Added a
    direct verifier regression that rejects tampered account nonce, balance,
    storage root, and code hash fields when they no longer match the account
    proof RLP node, locking the `eth_getProof` account-result consistency
    check explicitly. Hardened `state-db-get-proof` result construction so
    account addresses, storage keys, storage roots, and code hashes are copied
    into the returned proof object instead of sharing caller-owned mutable byte
    vectors. Added a direct snapshot regression proving that a generated proof
    remains valid against its original state root after later state mutation,
    while failing against the mutated root. Added a named seed-case coverage
    gate for the state-proof fixture set, locking the present-account,
    missing-account, deleted-storage, and multi-storage proof vectors before
    they are replaced with transcribed reference output. Remaining work:
    replace the seed
    proof vectors with
    transcribed
    geth proof workload output or pinned execution-spec-tests proof fixtures
    once available.

- [x] `STATE-ATOMIC-COMMIT`: Add an atomic state/receipt/index commit boundary
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
  - Progress: added the first atomic commit boundary. The memory chain-store
    now snapshots and restores block, number, canonical hash, tx-location,
    state-availability, account, prepared-payload, pending/filter, and
    forkchoice checkpoint indexes. `execute-atomic-block-commit` combines that
    store rollback with `state-db-copy` / `state-db-restore`, and tests cover
    both multi-value success commit and injected failure rollback across
    state DB plus block/receipt/tx/account read indexes. Remaining work:
    wire this boundary into real block execution and add commitment-specific
    failure cases for state root, receipts root, logs bloom, gas used, and
    intra-tx errors.
  - Progress: added `execute-and-commit-block`, a narrow import entry point
    that runs a supplied block executor inside the atomic state/store boundary
    and writes the block/receipt/tx indexes only after execution succeeds.
    Tests now cover successful execution-store commit plus rollback for bad
    state root, receipts root, logs bloom, gas used, and intra-transaction
    errors. Remaining work: use the entry point from Engine `newPayload`,
    add signed-transaction sender recovery on that path, and persist executed
    state into the RPC account read indexes.
  - Progress: executed blocks now persist a read-only projection of the
    post-state into the chain-store account indexes. `state-db-for-each-account`
    exposes account/code/storage iteration without leaking the state DB hash
    tables, and `commit-state-db-to-chain-store` writes balances, nonces, code,
    and storage for the imported block hash. Remaining work: wire
    `execute-and-commit-block` into Engine `newPayload` and enforce signed
    sender recovery on that path.
  - Progress: added an Engine `newPayloadV2` atomic rollback check for
    post-execution commitment mismatches after a real signed transfer plus
    withdrawal. The invalid-import cases now cover state root, receipts root,
    logs bloom, and gas used, asserting that the child block, state
    availability marker, transaction lookup, and child account projection are
    absent while the parent account projection remains intact.
  - Progress: tightened the memory-store snapshot boundary for mutable filter
    objects. Atomic rollback now deep-copies log, block, and pending
    transaction filters, and coverage asserts that a failed atomic import
    rolls back both the pending transaction pool and pending-filter hash list.
  - Progress: extended memory-store snapshot isolation to prepared payload
    objects. Atomic rollback now copies prepared payload wrappers and blob
    bundles, and coverage asserts that a failed atomic import cannot leak
    mutations to an existing prepared payload entry.
  - Progress: extended memory-store snapshot isolation to stored blob sidecar
    response entries. Atomic rollback now copies blob/proof byte vectors, and
    coverage asserts that a failed atomic import cannot leak mutations to an
    existing `engine_getBlobs` response entry.
  - Progress: extended memory-store snapshot isolation to forkchoice
    checkpoint wrappers. Atomic rollback now copies head/safe/finalized
    checkpoint objects, and coverage asserts that a failed atomic import
    cannot leak mutations to the existing head checkpoint.
  - Progress: extended memory-store snapshot isolation to invalid payload
    cache entries. Atomic rollback now copies cached invalid block wrappers and
    their headers, and coverage asserts that failed imports cannot leak either
    mutations to an existing invalid marker or newly inserted invalid markers.
  - Result: Phase A atomic import acceptance is complete for the in-memory
    chain-store path. `engine_newPayloadV2` executable imports now run through
    the atomic state/store boundary, validate state root, receipts root, logs
    bloom, and gas used before commit, persist receipts and retained account
    projections only after success, and roll back state DB plus block,
    receipt, transaction, account, pending/filter, blob sidecar, prepared
    payload, forkchoice checkpoint, and invalid-payload cache indexes on
    injected failures.

- [x] `SENDER-RECOVERY-ENFORCEMENT`: Require real sender recovery on every
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
  - Progress: added `execute-and-commit-signed-block`, which routes signed
    block execution through the atomic block commit boundary while preserving
    `execute-signed-block` sender recovery. Tests cover successful recovered
    sender execution with block/transaction/account indexes committed, and a
    wrong-chain-id signature failure that leaves both state DB and chain-store
    indexes unchanged. Added `eth_sendRawTransaction` admission sender recovery
    against `chain-config-chain-id`; tests use a real EIP-155 legacy vector for
    successful pending admission and reject the same transaction under a wrong
    configured chain id while preserving pending pool and filter state. Added
    mined transaction object sender recovery enforcement for
    `eth_getTransactionByHash`, transaction-by-block/index, and full block
    transaction objects; stale or polluted blocks with unrecoverable senders now
    produce RPC errors instead of zero-address `from` fields. Added typed raw
    transaction admission coverage for malformed `yParity` and high-s
    signatures, asserting rejection preserves pending pool and filter state.
    Added `eth_sendRawTransaction` set-code authorization admission validation,
    rejecting malformed EIP-7702 authorization `yParity` and high-s signatures
    before pending insertion while preserving pending pool and filter state.
    Added Engine `newPayloadV2` sender-recovery enforcement coverage: a
    payload containing a real EIP-155 transaction signed for chain id 1 returns
    Engine `INVALID` when imported under chain id 2, preserves the parent
    state projection, and does not commit the child block, state availability,
    or transaction lookup index.

- [x] `RECEIPT-DERIVATION-INVARIANTS`: Lock typed receipt encoding and
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
  - Progress: added the first import-path receipt derivation check for
    contract creation. Following geth's `state_processor.go` /
    `types/receipt.go` behavior and Nethermind's receipt RPC shape, receipt
    JSON now derives `contractAddress` from the recovered sender and
    transaction nonce when `to` is `null`. A new Engine `newPayloadV2` test
    imports a signed contract-creation payload, reads it through
    `eth_getTransactionReceipt`, and asserts the expected created address,
    `null` recipient, status, transaction hash, and block hash.
    Remaining work: external-style typed receipt vectors for legacy,
    EIP-2930, EIP-1559, and EIP-4844, plus import-path assertions for
    cumulative gas monotonicity, log order, logs bloom membership, CREATE2
    receipt behavior where applicable, and explicit pre-Byzantium exclusion.
  - Progress: extended the Engine-imported log-producing forkchoice fixture to
    assert receipt bloom membership from the RPC receipt itself. After the
    logging branch is selected as canonical, the test reads
    `eth_getTransactionReceipt`, builds a bloom from the returned
    `logsBloom`, and verifies that both the emitting contract address and
    emitted topic are present. Remaining work: external-style typed receipt
    vectors, cumulative gas/order checks from imported multi-transaction
    blocks, CREATE2 coverage where applicable, and explicit pre-Byzantium
    exclusion.
  - Progress: broadened the same Engine-imported logging fixture to two
    same-block transactions. The canonical branch now returns two ordered
    logs through `eth_getLogs`, two ordered receipts through
    `eth_getBlockReceipts`, monotonic `cumulativeGasUsed`, per-transaction
    `gasUsed` derived from the previous cumulative value, and block-level gas
    used matching the final receipt cumulative gas. Remaining work:
    external-style typed receipt vectors, CREATE2 coverage where applicable,
    and explicit pre-Byzantium exclusion.
  - Progress: added an Engine-imported EIP-1559 typed receipt smoke. A real
    signed dynamic-fee transaction now imports through `engine_newPayloadV2`;
    the test reads the stored receipts and RPC receipt, verifies `type` is
    `0x2`, effective gas price follows the block base fee, and the imported
    block's receipts root matches `transaction-receipt-list-root` while
    differing from the legacy-only `receipt-list-root`. Remaining work:
    external-style typed receipt vectors for legacy, EIP-2930, and EIP-4844,
    CREATE2 coverage where applicable, and explicit pre-Byzantium exclusion.
  - Progress: added the matching Engine-imported EIP-2930 typed receipt
    smoke. A real signed access-list transaction now imports with Berlin and
    London active; the test verifies RPC receipt `type` is `0x1`, effective
    gas price reflects the legacy gas price/base-fee path, and the imported
    receipts root uses typed transaction receipt encoding rather than the
    legacy-only receipt list root. Remaining work: external-style typed
    receipt vectors for legacy and EIP-4844, CREATE2 coverage where
    applicable, and explicit pre-Byzantium exclusion.
  - Progress: tightened the existing Engine-imported legacy one-transaction
    smoke with explicit receipt-root checks. The imported block now asserts
    that legacy receipts match both `receipt-list-root` and
    `transaction-receipt-list-root`, and that the RPC receipt reports
    `type` `0x0` with post-Byzantium `status`. Remaining work:
    external-style typed receipt vectors, EIP-4844 import-path coverage,
    CREATE2 coverage where applicable, and explicit pre-Byzantium exclusion.
  - Progress: added a config-aware receipt fork-semantics gate to
    `validate-block-execution-roots`. When a chain config is supplied, block
    execution receipt validation now rejects blocks before Byzantium as
    outside Phase A scope; tests cover a pre-Byzantium post-state receipt
    rejection and the same receipt shape passing once Byzantium is active.
    Remaining work: external-style typed receipt vectors, EIP-4844
    import-path coverage, and CREATE2 coverage where applicable.
  - Progress: added the Engine-imported EIP-4844 blob typed receipt smoke. A
    real signed blob transaction now imports through `engine_newPayloadV3`
    with versioned hashes and Cancun header fields; the test verifies RPC
    receipt `type` is `0x3`, effective gas price follows the block base fee,
    and the imported block's receipts root uses typed transaction receipt
    encoding rather than the legacy-only receipt list root. Remaining work:
    external-style typed receipt vectors and CREATE2 coverage where
    applicable.
  - Progress: added the first external-style receipt-root fixture vectors. The
    new fixture drives legacy, EIP-2930, EIP-1559, and EIP-4844 transaction
    envelopes with post-Byzantium receipts, asserting typed receipt encoding
    prefixes, encoded lengths, the mixed typed receipt trie root, and the
    legacy-only root for contrast.
  - Progress: added pinned-source metadata, wrapper/vector field whitelists,
    reference-client metadata validation, and a named seed-vector gate to the
    receipt-root fixture loader, so receipt vectors now fail early on wrapper
    drift before replaying typed receipt encodings.
    Remaining work: CREATE2 coverage where applicable.
  - Result: added an Engine-imported internal CREATE2 receipt boundary. The
    test imports a signed transaction that calls an existing contract whose
    code performs CREATE2, verifies the internally-created runtime code is
    committed to the imported state, and asserts the RPC receipt still reports
    `contractAddress` as `null` with `to` set to the called contract. With the
    external-style typed receipt vectors, import-path cumulative gas/log/bloom
    checks, top-level CREATE contract-address derivation, and pre-Byzantium
    exclusion already covered, the Phase A receipt-derivation invariant task is
    complete.

## P0: EVM Correctness Gaps

- [x] Add an EVM state-test fixture runner.
  - Milestone: 4 / 8
  - References: Ethereum execution-spec-tests, geth state tests, Nethermind EVM
    test runners, Reth/revm fixtures.
  - Acceptance: at least one external-style EVM state fixture can drive the
    Common Lisp EVM and compare post-state/root/logs.
  - Validation: `sbcl --script tests/run-tests.lisp`.
  - Result: added `tests/fixtures/execution-spec-tests/evm-state.json`, an
    external-style London EVM state fixture with pinned EEST source metadata.
    The new fixture runner builds pre-state accounts/code/storage, executes a
    legacy message call, and asserts post-state root, account balances, nonce,
    code, storage, receipt status, cumulative gas, logs bloom, and emitted log
    address/topic/data. Shape validation locks the wrapper, env, pre/post
    account, transaction, receipt, and coverage-tag fields. A named seed-case
    gate now locks the fixture-backed CALL/revert/static/value/delegated-code
    and access-list cases so the London state-test seed set cannot silently
    shrink while retaining generic tag coverage.

- [ ] Expand CALL-family semantics toward spec completeness.
  - Milestone: 4
  - References: geth `core/vm`, Nethermind EVM, revm behavior.
  - Acceptance: nested value transfer, returndata, gas, access-list, static
    context, revert, and code-resolution cases are fixture-backed beyond the
    current hand-written tests.
  - Validation: targeted CALL fixtures plus `sbcl --script tests/run-tests.lisp`.
  - Slice: added a fixture-backed London nested `CALL` revert/returndata case.
    The fixture asserts that child `SSTORE` changes roll back on `REVERT`, the
    parent can copy reverted returndata and persist it, post-state storage is
    exact for expected accounts, and the transaction receipt remains successful.
  - Slice: added a fixture-backed London `STATICCALL` read-only case. The child
    attempts `SSTORE`, fails under the static context, leaves callee storage
    empty, and the parent continues to persist its own success marker.
  - Slice: added a fixture-backed London nested value-transfer case. The parent
    contract receives transaction value, forwards part of it with `CALL`, keeps
    the remainder, persists the child success flag, and the callee balance is
    asserted in post-state.
  - Slice: added a fixture-backed delegated-code resolution case. A parent
    `CALL`s an account containing a delegation designator, executes target code,
    and asserts that storage writes happen at the delegated callee rather than
    the target account.
  - Slice: extended the EVM state fixture runner to support type-1 access-list
    transactions and added a fixture-backed `CALL` case that prewarms the callee
    address plus parent storage slot through the transaction access list.
  - Slice: added a fixture-backed London `CALL` gas-forwarding case. The parent
    forwards an explicit stack gas value to a child that returns `GAS`, then
    persists both the call success flag and returned child gas in storage.
  - Slice: added a fixture-backed London value-transfer stipend case. The parent
    supplies zero stack gas with non-zero call value, asserts the stipend lets
    the child return `GAS`, and checks both value movement and persisted gas.

- [ ] Complete non-empty BN254 pairing precompile coverage.
  - Milestone: 4
  - References: geth `crypto/bn256`, EVM precompile tests, Nethermind
    precompiles.
  - Acceptance: valid non-empty pairing vectors and invalid subgroup/curve
    vectors are covered.
  - Validation: `sbcl --script tests/run-tests.lisp`.
  - Slice: expanded BN254 pairing precompile failure coverage with non-zero G1
    invalid coordinate and off-curve vectors, complementing existing malformed
    size, zero-element, and invalid G2 checks.

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

- [~] Add sender/nonce keyed txpool indexing.
  - Milestone: 7
  - Dependencies: extracted txpool state.
  - Acceptance: pending transactions are indexed by hash and sender/nonce, and
    txpool content APIs no longer rebuild all groupings from scratch.
  - Validation: add duplicate sender/nonce tests and run
    `sbcl --script tests/run-tests.lisp`.
  - Progress: added a sender/nonce index to the existing memory-store-backed
    pending transaction pool. Pending insertion, duplicate hash handling,
    mined-transaction removal, atomic store snapshots, and `txpool_content`,
    `txpool_contentFrom`, and `txpool_inspect` now use the index while the
    txpool object extraction remains a follow-up.

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
