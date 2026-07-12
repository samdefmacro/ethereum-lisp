# Test Suite Refactoring Plan

Status: complete; phases 0-5 were implemented and validated on 2026-07-12.

## Purpose

Make the test suite fast enough for routine refactoring while preserving the
process, persistence, protocol, and cryptographic coverage required by an
Ethereum execution client.

This is an architecture change, not a request to delete slow tests, weaken
assertions, shorten correctness timeouts blindly, or replace end-to-end checks
with mocks.

## Observed Baseline

A diagnostic run on 2026-07-11 found the following test shape:

- approximately 937 registered tests;
- approximately 314 seconds of measured execution time;
- 81 external process launches in test code;
- 56 process/file wait call sites;
- 18 ready-file waits with a maximum duration of 10 seconds;
- 89 references to standalone Lisp scripts from tests;
- 49 tests taking at least one second in the diagnostic run.

The diagnostic run overlapped unrelated workspace changes and continued after
failures, so its correctness result is not a release signal. Its timing data is
still sufficient to identify repeated SBCL/ASDF cold starts as the dominant
cost. A clean baseline must be captured again before implementation begins.

The largest observed costs were process-oriented tests:

- missing fixture-root validation launched six scripts twice and took 36.7s;
- empty fixture-root validation launched seven scripts and took 25.5s;
- selector script root-option coverage launched three scripts and took 13.4s;
- drift-map script tests took 7-15s each;
- three real KZG verification paths used approximately 15s in total.

## Target Architecture

### Test layers

Define explicit test layers with stable ownership:

1. `unit`: pure domain behavior with no child process, listener, filesystem
   persistence, external verifier, or wall-clock wait.
2. `integration`: database adapters, HTTP/socket services, file persistence,
   KZG command integration, and bounded component interactions.
3. `e2e`: standalone CLI processes, devnet lifecycle, smoke gates, restart
   behavior, signals, and cross-process artifact contracts.

The default developer command should run `unit`. CI and pre-push validation
should compose the layers explicitly rather than relying on one opaque serial
suite.

### Thin script entries

Standalone scripts should contain only process-boundary adaptation:

- obtain argv and environment values;
- construct input/output streams;
- call an application function;
- map the result to a process exit status.

Argument parsing, root resolution, report construction, classification, and
validation must be callable directly in the current Lisp image. Their APIs
should accept explicit argv, environment, output, and error-output values so
tests do not mutate global process state.

Each script keeps a small number of subprocess tests for the real executable
contract. Option matrices and validation branches become in-process tests of
the shared application service.

### Observable test runner

The runner should record for every test:

- layer;
- elapsed monotonic time;
- pass, skip, or failure status;
- optional owning module;
- whether it launches processes or requires local sockets.

The final report should show total time, layer totals, and the slowest tests.
It should support selecting a layer and reporting tests above a configurable
duration without changing test semantics.

## Execution Plan

### Phase 0: Clean baseline

- Start from a stable worktree with no concurrent source rewrites.
- Run the existing suite without behavioral changes.
- Capture load time separately from execution time.
- Record the slowest 50 tests and count child-process launches.
- Store the baseline in a short dated section at the end of this document.

Acceptance:

- the baseline run has a trustworthy pass/fail result;
- timings distinguish system load, unit execution, integration, and e2e work;
- no production or test behavior changes in this phase.

### Phase 1: Timing and metadata

- Add test metadata for `unit`, `integration`, and `e2e`.
- Keep existing `deftest` call sites valid while metadata is introduced.
- Add layer selection and slowest-test reporting to the runner.
- Make skipped and failed tests retain timing information.
- Add tests for runner ordering, selection, summaries, and failure behavior.

Acceptance:

- running all layers is behaviorally equivalent to the old full suite;
- every registered test belongs to exactly one layer;
- the full suite remains green;
- timing output is deterministic in shape and optional in verbosity.

### Phase 2: Shared CLI application services

- Identify duplicated script bootstrapping and option/environment handling.
- Extract shared application functions from fixture report, selector,
  classifier, drift-map, and smoke-gate scripts.
- Pass argv, environment lookup, and streams explicitly.
- Keep script files as thin adapters with unchanged CLI output and exit codes.
- Convert option/error matrices to table-driven in-process tests.
- Retain at least one subprocess contract test per standalone script family.

Start with the two fixture-root validation tests because they currently spend
about one minute launching 19 short-lived SBCL processes.

Acceptance:

- CLI text, JSON, stderr, and exit-status contracts remain unchanged;
- fixture-root validation no longer launches one process per matrix row;
- the affected tests become at least 70% faster;
- subprocess smoke coverage still proves that each public entry point boots.

### Phase 3: Isolated integration fixtures

- Centralize temporary directory, port, process, and cleanup ownership.
- Replace readiness polling with a shared bounded primitive that records the
  observed condition and elapsed wait.
- Use deterministic clocks or explicit ticks for scheduler behavior.
- Keep real waits only where the process boundary itself is under test.
- Ensure every launched process is reaped on success, failure, and timeout.

Acceptance:

- integration tests do not depend on fixed ports or shared artifact paths;
- failures report the awaited condition, child status, stdout, and stderr;
- no background process survives the test runner;
- deterministic scheduler tests contain no wall-clock sleeps.

### Phase 4: Process-level parallelism

- Run only isolated `e2e` cases in bounded worker processes.
- Do not parallelize tests that share special variables or mutable global
  registries until those dependencies are removed.
- Assign unique temporary roots and ports per worker.
- Preserve deterministic result ordering in the final report.

Acceptance:

- serial and parallel e2e runs produce the same results;
- repeated runs do not exhibit port, file, or process interference;
- a worker failure cannot prevent cleanup of other workers;
- parallel execution produces a material wall-clock improvement.

### Phase 5: Commands and CI policy

- Provide stable commands for `unit`, `integration`, `e2e`, and `all`.
- Use `unit` plus focused owning-module tests during implementation.
- Require `all` before publishing a completed architectural round.
- Run KZG and process smoke layers explicitly in CI so they are never omitted
  accidentally by the fast default.
- Document expected duration and environment requirements for each command.

Acceptance targets on the current development machine:

- `unit`: no more than 60 seconds;
- `unit + integration`: no more than 90 seconds;
- `all`: no more than 180 seconds;
- no coverage loss in persistence, KZG, HTTP, CLI, devnet, or restart paths.

## Design Constraints

- Test layering must follow architectural ownership, not filename prefixes.
- Shared helpers may remove setup duplication but must not hide assertions.
- Production code must not gain test-only branches.
- Timeouts remain correctness guards; reduce them only after the awaited event
  is deterministic and diagnostic.
- In-process CLI tests must verify the same values that subprocess tests verify.
- End-to-end tests remain end-to-end; only redundant process launches move to
  lower layers.
- Each implementation phase is a separate green commit and is pushed only
  after its stated acceptance checks pass.

## Expected Result

Most refactoring feedback should arrive from the unit layer in under one
minute. Integration behavior should remain easy to run locally, while the full
suite continues to prove executable entry points, persistence, networking,
cryptography, and devnet lifecycle without making every small edit pay for
dozens of redundant Lisp image startups.

## Execution Record

### 2026-07-12 clean baseline

- Clean worktree, cold `sbcl --script tests/run-tests.lisp` run.
- Result: 906 passed, 33 skipped, 0 failed.
- Wall/user/system time: 918.00s / 704.37s / 23.50s.
- The sandbox prevented local socket binding, so the 33 existing socket and
  optional-fixture skips are recorded limitations rather than coverage claims.
- This legacy runner did not separate ASDF load time from execution time or
  retain per-test timings. Phase 1 adds those measurements for subsequent
  runs; the absence of that split is part of the baseline finding.

### 2026-07-12 phase 1 initial result

- `deftest` remains source-compatible and now registers layer, module,
  child-process, and local-socket metadata for every test.
- The runner selects repeatable `--layer` values, retains monotonic timings for
  pass/skip/failure results, and reports layer totals plus deterministic slowest
  tests.
- Architectural loader boundaries assign fixture adapters, persistence, CLI
  integration, executable scripts, and serve lifecycle tests to their owning
  layers. Real KZG command paths are explicitly integration tests.
- The first measured unit run was 726 passed / 6 skipped in 90.399s. Its timing
  report exposed fixture loading and replay as the dominant misplaced work;
  those owning modules were then moved to integration without changing tests.
- Phase 1 is not marked complete until the final all-layer validation below is
  green.

### 2026-07-12 phase 2 fixture-root result

- Added a shared fixture-root application service with injected environment,
  filesystem probe, JSON discovery, stdout, and stderr dependencies.
- Fixture report, state/transaction classifiers, and the three selector entry
  points delegate missing-root and empty-root validation to that service.
- The two former subprocess matrices now execute in-process in under 0.001s of
  measured test time, versus 36.7s and 25.5s in the diagnostic baseline (more
  than 99% lower). A separate subprocess contract remains for the smoke-gate
  entry point, and the existing script-family boot tests remain in e2e.
- Phase 2 is not marked complete: this round covers the plan's first
  fixture-root target, while report construction, classification, drift-map,
  and remaining option matrices still need extraction.

### 2026-07-12 composed validation after the initial refactor

The three disjoint layer selections cover every registered test and were run
from fresh SBCL processes with socket and process permissions enabled:

- `unit`: 683 passed, 3 optional-fixture skips, 54.290s execution / 58.05s
  wall time;
- `integration`: 180 passed, 2 optional-fixture skips, 65.612s execution /
  69.08s wall time;
- `e2e`: 76 passed, 0 skipped, 583.764s execution / 587.35s wall time.

The composed result is 939 passed, 5 skipped, 0 failed, with 703.666s of
measured execution and 714.48s of summed wall time. The five additional tests
relative to the baseline cover runner behavior and the retained smoke-gate
subprocess contract. All socket tests that were unavailable in the baseline
ran successfully in this validation.

The wall/execution deltas show approximately 3.5-3.8s of system-load overhead
per fresh SBCL layer process. After the full runs, two already-green in-process
socket tests were metadata-corrected from e2e to integration and re-run there;
the current partition is therefore 683/182/74 passing tests across
unit/integration/e2e, with the same 939-test composed result.

The `unit` target is met. The `unit + integration` target is not yet met
(119.902s measured), and the `all` target is not yet met. The slowest e2e cases
are the two devnet smoke workflows at approximately 145s each, followed by the
pinned-fixture workflow at approximately 73s. These measurements leave Phase
3 isolation and Phase 4 bounded process parallelism as required work rather
than treating the initial layering as the end of the refactor.

### 2026-07-12 phase 2 classifier and drift-map result

- State, transaction, and blockchain classifier entry points now accept
  explicit argv, environment lookup, output stream, and test-system loading
  controls. Loading them as application services no longer executes their
  process entry points.
- The aggregate drift-map invokes all three classifier services in the current
  Lisp image and consumes their report objects directly. It no longer launches
  a child SBCL process per suite or round-trips classifier reports through
  JSON.
- Seven classifier matrix tests and five drift-map matrix/error tests now run
  in-process in the integration layer. Their focused measured execution time is
  2.106s total. Separate subprocess help/boot contracts remain for every public
  classifier and drift-map script.
- Test `uiop:run-program` call sites fell from 60 immediately before this slice
  to 48. The full e2e layer fell from 76 tests / 583.764s to 62 tests /
  502.868s because the twelve application-level contracts moved to integration
  and no longer pay repeated Lisp cold starts. This is an 80.896s (13.9%) e2e
  execution-time reduction.
- Fresh validation passed with `unit` 683 passed / 3 optional skips in 55.864s,
  `integration` 194 passed / 2 optional skips in 68.931s, and `e2e` 62 passed
  in 502.868s. The composed result remains 939 passed / 5 skipped / 0 failed in
  627.663s, 76.003s lower than the prior composed measurement.
- At this checkpoint, Phase 2 remained open for fixture-report, selector-list, and smoke-gate
  application services plus their remaining option matrices. The current
  slowest e2e tests remain the two approximately 144s Phase A devnet workflows
  and the approximately 72s pinned-fixture workflow, preserving the case for
  Phase 3 isolation and Phase 4 bounded process parallelism afterward.

### 2026-07-12 phase 2 completion

- Fixture report, selector-list, classifier, drift-map, and smoke-gate entry
  points now expose application functions with explicit argv, environment,
  stdout, stderr, and test-system-loading dependencies. Public script files
  remain guarded adapters, and direct CLI smoke runs preserved their contracts.
- The three selector entry points share `scripts/selector-application.lisp`;
  the drift-map composes classifier report objects without child Lisp images.
- The report, selector, classifier, drift-map, and smoke-gate option/error
  matrices run in-process in the integration layer. Focused validation passed
  18 classifier/drift tests, 3 fixture-report tests, 1 selector matrix, and 2
  smoke-gate option/error tests. Standalone help and boot contracts remain in
  e2e for every public script family.

### 2026-07-12 phase 3 completion

- Test-launched processes are registered with the framework and reaped from an
  unconditional per-test cleanup scope on pass, skip, failure, and timeout.
  Nineteen direct test launch sites now use the owning wrapper.
- File and child-exit polling use one bounded condition primitive with elapsed
  wait and diagnostic support. Its deterministic probe test contains no
  wall-clock delay, and a real integration test proves a live child is reaped.
- E2e workers receive unique temporary roots through
  `ETHEREUM_LISP_TEST_WORKER_ROOT`; CLI artifact and restored-report helpers
  resolve beneath that root. Existing listener tests continue to request
  ephemeral ports rather than sharing fixed endpoints.

### 2026-07-12 phase 4 completion

- `tests/run-tests.lisp --layer e2e --jobs N` launches a bounded set of worker
  Lisp processes. Tests are assigned by a deterministic greedy duration
  balance, retain registration order inside each shard, and are reported in
  worker-number order after buffered execution.
- Each worker owns its temporary root, stdout, stderr, and child processes.
  Parent cleanup terminates and reaps surviving workers and removes every root
  even when a worker fails.
- The serial and four-worker runs both passed the same 56 e2e tests. Serial
  measured execution was 484.528s; the four-worker wall time was 162.71s, a
  66.4% wall-clock reduction with no result loss or interference.

### 2026-07-12 phase 5 completion and final acceptance

- Stable `make test-unit`, `make test-integration`, `make test-e2e`, and
  `make test-all` commands are documented. `test-all` runs the three isolated
  layers concurrently and emits their buffered results in deterministic layer
  order.
- The GitHub Actions matrix runs unit, integration (including real vendored-Go
  KZG verification), and bounded e2e process coverage explicitly.
- A full `make test-all E2E_JOBS=4` passed 941 tests, skipped 5 optional-fixture
  tests, and failed 0 in 177.41s wall time: unit 684/3 skipped, integration
  201/2 skipped, and e2e 56/0 skipped.
- A concurrent `make -j2 test-unit test-integration` repeated the unit and
  integration results in 80.26s wall time. The final standalone unit
  validation passed 684 tests with 3 optional skips in 57.84s wall time. The
  current-machine targets of at most 60s,
  90s, and 180s are therefore all met while persistence, KZG, HTTP, CLI,
  devnet, restart, fixture, and process-boundary coverage remain present.
