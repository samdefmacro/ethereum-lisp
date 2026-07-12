# Test Suite Refactoring Plan

Status: planned; execution intentionally deferred.

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

Add dated baseline and phase results here when this plan is activated. Do not
mark a phase complete from estimates or partial test runs.
