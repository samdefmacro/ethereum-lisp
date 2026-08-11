# Validation Commands

These commands are available when a change needs verification. During feature
development, run the smallest check that directly covers the changed behavior.
The full suite is for an explicit user request, release/CI work, or a genuinely
broad high-risk change; it is not a routine prerequisite for implementing a
feature.

All application toolchains run inside Docker on macOS so compiler caches,
temporary artifacts, child processes, and loopback listeners remain isolated.
Direct `make test-*` and inner runner invocation fail outside the project image;
there is no host fallback.

For the warm development loop, use the managed Workbench contract:

```sh
cl-workbench doctor --strict
cl-workbench repl start
cl-workbench repl eval '(+ 1 2)'
cl-workbench test TEST-NAME     # omit TEST-NAME for the full warm suite
cl-workbench docs verify
cl-workbench repl stop
```

## Test Layers

```sh
scripts/dev.sh cold-test unit
scripts/dev.sh cold-test integration
scripts/dev.sh cold-test e2e
scripts/dev.sh cold-test all
```

- `unit` covers process-free domain behavior.
- `integration` covers persistence, sockets, fixture adapters, and the KZG CFFI
  verifier.
- `e2e` covers standalone CLI, restart, signals, and devnet processes.
- `all` composes every layer and is intentionally the most expensive option.

Focused selection is exposed by the broker, for example:

```sh
scripts/dev.sh cold-test unit --match TRANSACTION
```

## Unified import, authority, and recovery checks

Section 4 of the public-testnet plan has a focused acceptance surface. Run it
through the same container broker as every other application check:

```sh
# Candidate admission, Engine persistence, publication authority, private
# building, and the post-Merge debug rewind refusal.
scripts/dev.sh cold-test unit --match BLOCK-IMPORT
scripts/dev.sh cold-test unit --match NEW-PAYLOAD-PERSISTENCE
scripts/dev.sh cold-test unit --match FORKCHOICE
scripts/dev.sh cold-test unit --match DEBUG-SET-HEAD
scripts/dev.sh cold-test unit --match ETH-SYNC-RESUME-ANCHOR

# Durable exporters, staged execution, cache policies, file/RocksDB restart,
# and the explicitly authorized local dev-period publisher.
scripts/dev.sh cold-test integration --match CHAIN-STORE-CACHE
scripts/dev.sh cold-test integration --match INVALID-TIPSET
scripts/dev.sh cold-test integration --match REMOTE-BLOCK
scripts/dev.sh cold-test integration --match BLOB-SIDECAR
scripts/dev.sh cold-test integration --match PREPARED-PAYLOAD
scripts/dev.sh cold-test integration --match PEER-SYNC-PROGRESS
scripts/dev.sh cold-test integration --match STAGED-EXECUTION-UNIFIED
scripts/dev.sh cold-test integration --match DEVNET-PEER-SYNC
scripts/dev.sh cold-test integration --match DEV-PERIOD

# Kill a writer after candidate+cursor batches return but before clean close,
# then reopen RocksDB and verify candidate state, cursor, and canonical view.
scripts/dev.sh cold-test e2e \
  --match ROCKSDB-PEER-SYNC-CANDIDATE-PROGRESS-SURVIVES-SIGKILL
scripts/dev.sh cold-test e2e \
  --match DEV-PERIOD-SEAL-SURVIVES-SIGKILL
```

The block-import tests require invalid input and durability failures to leave no
candidate or canonical residue, require known replays to validate without
re-execution, and require prepared private builds to remain detached. They also
exercise typed P2P admission: fork/version and `block-to-executable-data`
mapping remains observable, but an eth BlockBodies value is not reconstructed
from an Engine envelope that cannot carry derived Prague requests or an
Amsterdam block access list.

Engine and dev-period selectors exercise the only two post-Merge publication
authorities: Engine forkchoice, and explicit local `--dev` mode. They also
require a positive dev period to be rejected without `--dev`, require local
Amsterdam building to derive rather than pre-supply the block access list, and
require `debug_setHead` to refuse both a post-Merge target and a rewind from a
post-Merge current view.

The cache tests apply count, exact encoded-byte, process-local age, and finality
pressure to all five caches and assert deterministic eviction. Public direct
startup re-admits the durable invalid and remote namespaces with a new
process-local timestamp; it does not claim to retain their pre-restart
wall-clock age. The invalid/remote tests additionally stream legacy over-limit
namespaces into the direct provider and assert startup count/byte/finality
bounds, replay rejection without re-execution, paged durable eviction, and
unowned BAL cleanup. Sidecars use bounded, lazy immutable content-addressed
point reads without eager hydration or retaining point-read results in memory;
prepared payloads and forkchoice targets are process-private and are not
claimed as restart state.

The peer-progress tests bind a cursor to peer, database authority, chain ID, and
genesis; they reject regression and same-height hash changes. The file and
RocksDB restart cases prove that a resumed downloader starts after the last
durable executed candidate and supplies its hash as the next batch's parent
anchor. When the peer has reorged away from that cursor, the downloader deletes
it durably and retries once from the local canonical anchor; a second mismatch
escapes instead of looping. The candidate e2e case uses a child process and
SIGKILL, then proves that both executed candidates and the last cursor survived
while neither peer candidate became canonical. The dev-period SIGKILL case pins
the explicit local authority's public-visibility-before-return durability
contract across restart.

These selectors are focused regression evidence, not a public-testnet readiness
claim. A broad Section 4 change still requires the cold `unit`, `integration`,
and `e2e` layers above; external fixture, Hive, bootstrap, and soak gates remain
separate release criteria.

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
scripts/dev.sh cold-scale
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
scripts/dev.sh cold-docs    # cold, same container shape as the test layers
cl-workbench docs verify    # warm image, for the edit loop
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
job in `.github/workflows/test.yml` invokes the underlying
`docker-docs-check` Make target, so a drifted transcript now blocks a merge
instead of being visible only to whoever happened to run the check locally.

## Archived Conformance Reports

A conformance run prints one count manifest per family, and those counts are the
only record of what it actually measured:

```text
EEST-CONFORMANCE state_tests: selected=12 skipped=3 executed=[London:7 Shanghai:5]
```

`scripts/conformance-report.sh` copies those lines verbatim into a report that
also names the corpus that produced them and the revision under test. Capture
the run through the host-safe broker, then execute the report step inside the
marked project image or the reviewed release job:

```sh
scripts/dev.sh cold-test integration > run.log 2>&1
# Inside the marked project image or reviewed release job:
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
