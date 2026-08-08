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
- `integration` covers persistence, sockets, fixture adapters, and the KZG CFFI
  verifier.
- `e2e` covers standalone CLI, restart, signals, and devnet processes.
- `all` composes every layer and is intentionally the most expensive option.

Focused selection is available through `DOCKER_TEST_ARGS`, for example:

```sh
make docker-test-unit DOCKER_TEST_ARGS="--match TRANSACTION"
```

Optional official fixtures use `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`. A
missing optional fixture root produces a skip and is not evidence that external
fixture validation passed.

The root alone selects nothing. The state-test and blockchain-replay cases also
need `ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS` and
`ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS` (`auto` takes every case the
classifier finds), and without them they report the same skip they report with no
corpus at all — so a run can mount the whole corpus, execute zero vectors, and
still look like a pass. The Docker targets bind-mount the root and forward all
three when they are set. State-test auto-discovery defaults to London and
Shanghai; set `ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS` to a comma-separated
fork list such as `Cancun,Prague,Osaka` to opt into later-fork vectors.

What the pinned corpus cannot cover: EEST `v5.4.0` contains no `amsterdam/`
directory, and its Osaka vectors predate Amsterdam activation, so they carry
Prague post-state rules. Amsterdam execution is therefore pinned only by the
in-tree fork matrix and unit tests, not by fixtures anyone else wrote. Nothing
in this tree has been checked against a running reference client either; every
parity claim rests on source comparison against the versions named in
`docs/reference-map.md`.

`DOCKER_TEST_IMAGE_PREBUILT=1` runs the layers against an existing image instead
of rebuilding it. CI sets it because it builds the image with buildx against a
shared layer cache that a plain `docker build` would not reuse.

Verification should not expand into unrelated coverage work, documentation
maintenance, repeated baselines, or a second development objective. Report an
unrelated failure separately and continue the requested feature when it is safe
to do so.

## Production-store scale gate

```sh
make docker-direct-store-scale
```

This Docker-only acceptance gate writes a checkpointed canonical block and
account trie plus 512 MiB of distinct, hash-addressed code records into RocksDB
while the container is limited to 384 MiB. A fresh SBCL process opens the
current-schema database through the direct provider and point-reads the
persisted account, code, and storage before measuring. It fails unless restart
RSS stays below 256 MiB and whole-process restart time stays below 30 seconds;
the wrapper also requires RocksDB's physical on-disk size to exceed 384 MiB.
An unconstrained preparation container first cold-compiles the current source
into an ephemeral cache volume, so the 384 MiB limit measures datastore runtime
rather than compiler peak memory. The limited seeding process is intentionally
separate from the measured restart process, so allocator state from constructing
the dataset cannot make a memory-mirrored restart look bounded.

## Documentation Transcripts

```sh
make docker-docs-check      # cold, same container shape as the test layers
scripts/dev.sh docs-check   # warm image, for the edit loop
```

The `cl-transcript` examples in `docs/*.lisp` are re-executed and compared
against the values they record, so a transcript that has drifted from the code
is a failing build rather than stale prose. Both commands run
`scripts/docs-check.lisp`, which prints `docs-check PASSED` only when two gates
both hold:

- **GREEN** — every section in `*CHECKED-SECTIONS*` documents cleanly. A
  recorded value that no longer matches reality signals a transcription
  consistency error and fails the run.
- **RED** — `@DOCS-CHECK-SELFTEST` in `docs/rlp-manual.lisp` is deliberately
  wrong and must FAIL. Were it ever to pass, transcript checking would have
  silently switched off, and the run fails on that alone. Do not "fix" that
  section.

Adding a manual means adding its section to `*CHECKED-SECTIONS*`; the authoring
rules for transcripts are in the header of `docs/rlp-manual.lisp`. The `docs`
job in `.github/workflows/test.yml` runs `make docker-docs-check`, so a drifted
transcript now blocks a merge instead of being visible only to whoever happened
to run the check locally.

## Archived Conformance Reports

A conformance run prints one count manifest per family, and those counts are the
only record of what it actually measured:

```text
EEST-CONFORMANCE state_tests: selected=12 skipped=3 executed=[London:7 Shanghai:5]
```

`scripts/conformance-report.sh` copies those lines verbatim into a report that
also names the corpus that produced them and the revision under test:

```sh
# pipefail matters: without it the pipeline reports tee's status, and a failed
# run reads as a passing one.
set -o pipefail
make docker-test-integration 2>&1 | tee run.log
scripts/conformance-report.sh \
  --log run.log \
  --fixture-root "$ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" \
  --output eest-conformance-report.txt
```

Release, archive name and pinned SHA-256 are read out of
`scripts/fetch-eest-fixtures.sh` rather than restated, the baseline is derived
from the fixture root that was really mounted, and the archive on disk is
re-hashed — so the report describes the corpus that was measured rather than one
the caller asserts. The upstream commit is keyed by archive digest, so bumping a
pin can never leave the previous commit attached to the new corpus.

Exit 1 means the report was written but is not trustworthy as evidence: the
corpus could not be identified, the archive digest disagrees with the pin, or
`--require-manifest` was given and the run emitted no counts at all. Missing
metadata that still leaves the report usable is recorded as `report-gaps` and
exits 0.

CI archives one report per conformance job with `actions/upload-artifact`:
`eest-conformance-report` from the blocking job (the `legacy-v5.4.0` corpus) and
`eest-conformance-report-late-forks` from the non-blocking late-fork job
(`tests@v20.0.1`). Both steps run under `if: always()`, because a run that
failed is when its counts are worth the most, and both are echoed into the job
summary.

## Historical proof-of-work scope

Pre-Merge blocks are validated rather than refused. The Merge boundary is taken
from the chain configuration instead of from a header's difficulty field, so a
header below that boundary is checked against the fork-specific
Frontier-through-Gray-Glacier difficulty formula and its Ethash seal is
verified. Ommer lists are checked against the two-ommer cap, the six-block depth
window, duplicate and canonical-ancestor rejection, and full header validation
of each ommer against the supplied recent ancestry; block and ommer rewards are
paid. The DAO fork's ten-block extra-data rule and its drain-list balance
transition are applied.

Seal verification runs through `*ethash-seal-verifier*`, which defaults to an
in-tree light backend: it reconstructs the dataset items a header touches from
an epoch cache rather than materializing the multi-gigabyte DAG. Keccak-512 and
Hashimoto are pinned against the official `ethereum/tests` proof-of-work vector
at commit `c67e485ff8b5be9abc8ad15345ec21aa22e290d9`. The hook is replaceable by
an accelerated backend, and validation fails closed when no backend is
configured rather than accepting an unverified seal. Verifying a long pre-Merge
range is slow in proportion to the epochs it spans, and there is no mining or
full-DAG path.

Genesis parsing retains historical fork fields because they are part of public
network configurations and the EIP-2124 fork-id schedule.
