# Validation Commands

These commands are available when a change needs verification. During feature
development, run the smallest check that directly covers the changed behavior.
The full suite is for an explicit user request, release/CI work, or a genuinely
broad high-risk change; it is not a routine prerequisite for implementing a
feature.

All application toolchains run inside Docker on macOS and native Linux control
planes so compiler caches, temporary artifacts, child processes, and loopback
listeners remain isolated. Direct `make test-*` and inner runner invocation
fail outside the project image; there is no host fallback.

## Session preflight

For every substantive session that will execute application tooling, run the
following command from the physical repository root before the first build,
eval, test, documentation verification, generated-code step, dependency
operation, or deployable process:

```sh
cl-workbench doctor --strict
```

Treat a failure as a hard stop and report it; do not switch to a host
interpreter/compiler or a portable fallback. A task limited to reading or
editing files does not need this preflight. The doctor validates the declared
Workbench capabilities, project adapter, Docker availability, and execution
boundary; it does not start the warm REPL. Start the REPL only when the task
needs warm evals or tests.

Run the preflight again after changing checkout identity, Workbench or project
configuration, image build inputs, or after recovering Docker from a failure.

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
cl-workbench validation run cold-unit
cl-workbench validation run cold-integration
cl-workbench validation run cold-e2e
cl-workbench validation run cold-all
```

- `unit` covers process-free domain behavior.
- `integration` covers persistence, sockets, fixture adapters, and the KZG CFFI
  verifier.
- `e2e` covers standalone CLI, restart, signals, and devnet processes.
- `all` composes every layer and is intentionally the most expensive option.

Focused selection is exposed by the broker, for example:

```sh
cl-workbench validation run cold-unit --match TRANSACTION
```

These Workbench profiles delegate direct argv to the existing
`scripts/dev.sh cold-test` broker. `cold-docs` and `cold-scale` similarly map to
the existing cold documentation and production-store gates; `runtime-smoke
IMAGE` maps to the reviewed runtime-image smoke broker. Workbench records one
payload-free `validation.<profile>` outcome per invocation; direct
`scripts/dev.sh` calls remain low-level compatibility routes and do not create
that Workbench event. Each profile reports one aggregate gate and zero adapter
retries; exact test and fixture counts remain in the runner output and archived
conformance reports.

## Unified import, authority, and recovery checks

Section 4 of the public-testnet plan has a focused acceptance surface. Run it
through the same container broker as every other application check:

```sh
# Candidate admission, Engine persistence, publication authority, private
# building, and the post-Merge debug rewind refusal.
cl-workbench validation run cold-unit --match BLOCK-IMPORT
cl-workbench validation run cold-unit --match NEW-PAYLOAD-PERSISTENCE
cl-workbench validation run cold-unit --match FORKCHOICE
cl-workbench validation run cold-unit --match DEBUG-SET-HEAD
cl-workbench validation run cold-unit --match ETH-SYNC-RESUME-ANCHOR

# Durable exporters, staged execution, cache policies, file/RocksDB restart,
# and the explicitly authorized local dev-period publisher.
cl-workbench validation run cold-integration --match CHAIN-STORE-CACHE
cl-workbench validation run cold-integration --match INVALID-TIPSET
cl-workbench validation run cold-integration --match REMOTE-BLOCK
cl-workbench validation run cold-integration --match BLOB-SIDECAR
cl-workbench validation run cold-integration --match PREPARED-PAYLOAD
cl-workbench validation run cold-integration --match PEER-SYNC-PROGRESS
cl-workbench validation run cold-integration --match STAGED-EXECUTION-UNIFIED
cl-workbench validation run cold-integration --match DEVNET-PEER-SYNC
cl-workbench validation run cold-integration --match DEV-PERIOD

# Kill a writer after candidate+cursor batches return but before clean close,
# then reopen RocksDB and verify candidate state, cursor, and canonical view.
cl-workbench validation run cold-e2e \
  --match ROCKSDB-DURABLE-SEAM-FLUSHES-PRIOR-BUFFERED-BATCHES-ACROSS-SIGKILL
cl-workbench validation run cold-e2e \
  --match ROCKSDB-PEER-SYNC-CANDIDATE-PROGRESS-SURVIVES-SIGKILL
cl-workbench validation run cold-e2e \
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

## Public bootstrap and continuous sync checks

Section 5 has a focused container-only surface in addition to the complete cold
layers:

```sh
# Canonical preset seeds, bounded decoders, negotiated ranges, geth-pinned
# eth/72 custody, and lossless transaction burst cursors.
cl-workbench validation run cold-unit --match BUILT-IN-PUBLIC-NETWORK-PRESETS
cl-workbench validation run cold-unit --match RLP-ENFORCES
cl-workbench validation run cold-unit --match BLOCK-ACCESS-LIST-RLP-REJECTS
cl-workbench validation run cold-unit --match RLPX-MESSAGE-CODES
cl-workbench validation run cold-unit --match ETH-72
cl-workbench validation run cold-unit --match ETH-GOSSIP-NOTIFIES
cl-workbench validation run cold-unit --match DEVNET-BROADCAST
cl-workbench validation run cold-unit --match DEVNET-SNAP-HEAL-PROGRESS
cl-workbench validation run cold-unit --match DEVNET-CLI-PUBLIC-PRESETS
cl-workbench validation run cold-unit --match EIP1459
cl-workbench validation run cold-unit --match DNS-TXT-DECODER

# Persistent CLI identity/discovery behavior, verified snap client/server, durable
# pivot progress, bounded multi-peer failover, sole-writer request queues, and
# eth+snap multiplexing over one RLPx socket.
cl-workbench validation run cold-integration --match DEVNET-DATADIR-PERSISTS
cl-workbench validation run cold-integration --match DEVNET-CLI-WIRES-AUTHENTICATED-DNS
cl-workbench validation run cold-integration --match SNAP-
cl-workbench validation run cold-integration --match NODE-STORE-SNAP-SKELETON
cl-workbench validation run cold-unit --match SNAP-PIVOT
cl-workbench validation run cold-integration --match SNAP-PIVOT
cl-workbench validation run cold-unit --match TRIE-PROVEN-ABSENT
cl-workbench validation run cold-integration --match BOUNDED-PIVOT
cl-workbench validation run cold-integration --match ETH-SYNC-MULTI-PEER
cl-workbench validation run cold-integration --match ETH-SYNC-THREE-SCRIPTED
cl-workbench validation run cold-integration --match DEVNET-PEER-REQUEST-QUEUE
cl-workbench validation run cold-integration \
  --match DEVNET-RANGE-ANNOUNCEMENT-WAKES
cl-workbench validation run cold-integration \
  --match ETH-SYNC-MULTIPLEXES-ETH-72-AND-SNAP-1-OVER-ONE-SOCKET
cl-workbench validation run cold-unit --match GET-MANY
cl-workbench validation run cold-unit --match BATCHES-LOCAL
cl-workbench validation run cold-integration --match NATIVE-MULTI-GET
cl-workbench validation run cold-integration \
  --match SNAP-HEAL-ROCKSDB-LOCAL-READ-BATCH-USES-BOUNDED-WORKERS
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-REUSES-PROVED-SUBTREES
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-BATCHES-DEFERRED-STORAGE-ROOTS
cl-workbench validation run cold-integration \
  --match SNAP-HEALED-SUBTREE-PUBLICATION-FAILS-CLOSED
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-DRAINS-OVERSIZED-OVERDUE-FRONTIER
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-ADDS-SOURCES-THAT-ARRIVE-AFTER-HEALING-STARTS
cl-workbench validation run cold-unit \
  --match SNAP-STATE-HEALER-FILLS-EACH-SOURCE-WITHIN-GETH-LOOKUP-CAP
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-STALLED-LONG-HEAL-YIELDS-TO-A-STALE-CONSENSUS-TARGET
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-MULTI-YIELDS-A-STALE-RANGE-PIVOT-AFTER-DURABILITY
cl-workbench validation run cold-integration \
  --match SNAP-TRIE-NODE-SERVER-CAPS-DISK-LOOKUPS
```

The snap tests reconstruct and verify account/storage roots, return the
authenticated reconstructed page for direct content-addressed persistence,
reject altered compact proofs, and prove that verified trie records and
hash-matched bytecodes perform no database reads while authenticated puts
repair planted corrupt local values. They also stop a moving range pivot only
after its latest verified page is durable, preserving that exact cursor for the
atomic rebase onto a fresher consensus root. They derive complete coarse subtrees from
the verified range, batch code-existence probes before requesting a page's
missing bytecodes, reject
proof-edge nodes, and publish the subtree hash in the same batch as its account
cursor and external dependencies. StorageRanges pages publish equivalent
storage-subtree proofs with their node and cursor batch. The integration
regressions observe both kinds before final TrieNodes traversal, then promote
legacy account and completed-storage plans through shallow trie walks. An
incomplete large-storage plan excludes only its account prefix bucket, rather
than forcing a full account-tree rescan, and cannot publish the final promotion
marker until its cursors finish. The public depth regression fixes the legacy
proof lookup boundary at four nibbles and the finer publication boundary at
five, preserving existing proofs while limiting rebase invalidation.
They batch complete small storage tries with each account cursor and
prove that the range-only proven-absent insertion produces the
same root as the ordinary checked insertion and rejects empty values,
persist the authenticated prefix of byte-capped large storage, record those
roots with each durable page, and atomically publish the complete plan only
when the rebuilt account root equals the authorized state root. Sixteen
restart-safe StorageRanges cursors then finish each large trie through
512 KiB-capped pages. The byte-capped-storage regression proves that an
un-rebased import atomically publishes the state from its complete account,
code, and storage range proofs with zero TrieNodes requests; a
second regression interrupts StorageRanges after one page and proves a fresh
source resumes the exact durable cursor. A concurrency regression blocks one
source and proves a faster source receives its next partition without waiting
for a global wave. The production peer-queue regression puts two account jobs
ahead of a storage job and proves the storage request bypasses the occupied
account response slot, then routes out-of-order typed replies to the correct
workers. A pump regression separately proves that a SNAP response reaches that
router instead of being rejected as unsolicited. A changed-root rebase installs
a non-empty, non-root range witness; legacy, rebased, oversized, or incomplete
dependency plans retain the fail-closed full-root traversal. The tests also
inject a failed database batch to prove progress never outruns verified account
state. Only the complete same-root range/dependency proof set or the final
traversal can install the completion marker. The final
healer tests partition one missing frontier, prove every request remains
within geth's 1,024-path cap, target approximately 512 paths per request, sort
the whole request slice and group all storage paths for one account into a
shared wire path set while mapping partial replies back to exact DFS order, and block one source until a
faster source has
claimed multiple chunks. They also prove a second source actually serves
TrieNodes and consecutive rounds rotate the first source so retained work is
not pinned to one partially pruned peer. A late-admission control starts
healing with one source, exposes a second
source through the live provider only after the first request round, and proves
that the new source serves TrieNodes before completion. A boundary regression
pins the production completion-proof depth at four nibbles and proves work on
either side of that threshold is classified correctly, keeping rebases granular
without expanding toward a six-nibble proof index. Local traversal proves
that more than one trie hash crosses the ordered
multi-get seam in a batch, while the database integration control proves one
generic RocksDB batch reaches exactly one native call and preserves
duplicate-key order and per-key absence. A healer-specific RocksDB control
proves that one 512-key local batch reaches eight bounded read workers, performs
present-value decoding on all eight workers, rejoins values, presence bits, and
decoded objects in exact input order, and propagates an injected worker
failure. Switching the production dispatch back to serial makes its eight-call
and eight-decoder-thread witnesses fail. Generic controls enforce the 4,096-key
and 4 MiB key-byte bounds. The RocksDB construction regressions witness the
exact 2 GiB block-cache budget, ten-bit full Bloom policy, production
table-factory call site, and an enabled `ReadOptions.async_io` on the live
adapter handle. Removing that setter or changing its value to zero makes the
native readback witness fail; this witnesses asynchronous read configuration,
not the separate coroutine build needed for cross-level MultiGet scheduling.
The native-transfer regression intercepts a real RocksDB write and requires its
key/value pointers to name the exact pinned Lisp vectors, then requires one-key
MultiGet to use exactly two native bulk copies: one into the contiguous key
buffer and one out of the returned value. It also covers the zero-length pinned
field case. Falling back to per-record foreign allocation or per-octet CFFI
access makes those witnesses fail while all synchronous durability checks stay
unchanged. A separate adapter regression observes the buffered write-options
followed by the ordinary synchronous options. Its SIGKILL child writes an
unsynced content-addressed prerequisite batch, then a synced cursor batch; the
parent kills it without closing RocksDB and requires both batches after reopen.
This proves the optimized prefix is covered by the cursor's durable seam rather
than merely surviving a clean close.
The reviewed image builds additionally fail
unless the pinned native library links `liburing.so.2`, and the runtime layer
checks that the dependency resolves before its client smoke. The vendored
compatibility patch is applied with fuzz disabled so source drift fails the
image build. They
persist a bounded checksummed work frontier in the
same batch as newly accepted nodes. Abrupt source loss then resumes without
rereading the root; corrupt, stale, empty, or oversized checkpoints fail
closed, and
rebase/completion failure injection proves that checkpoint invalidation remains
atomic. A large-frontier control round-trips a 5,000-item live checkpoint and
proves that its bounded record stays below the byte cap. A live-shape control
resumes an 8,192-work frontier, expands its first branch to 8,207 at an overdue
checkpoint, and proves that single-work traversal drains it back to the hard
cap before the next record is published. The same control keeps pending missing
work in the exact frontier accounting while coalescing 1,024 paths into one
single-source request; restoring the old frontier-dependent one-path limit
makes the request-width witness fail. A separate count regression proves that
three sources raise total round capacity to 3,072 while every request remains
at the pinned geth 1,024-lookup cap. The serving regression sends 1,041 valid
root paths and proves only 1,024 disk lookups are returned; raising the
production cap makes it fail. Restoring the old immediate checkpoint stop
makes the live-shape control fail with the observed public-node error. Separate
controls prove that account traversal defers storage roots into multi-path
requests, that the version-two completion sentinel is backward compatible with
version-one checkpoints, and that content-addressed account and contract-storage
subtrees
proved under one pivot reduce the decoded work under the next pivot. The
checkpoint codec round-trips an armed storage-subtree sentinel, and a namespace
control proves that identical account and storage node hashes cannot share one
proof key. The same regression counts proof batch
identity: more than one independent proof must share a durable batch and no
batch may exceed 2,048 proofs. Proof publication failure leaves neither the
cache record nor state completion. The RocksDB read regression also proves that
large healed-subtree metadata probes use eight bounded native multi-get workers,
retain exact input presence order, and reject an unknown proof version. A
production-call-site witness counts metadata batches during cross-pivot reuse;
replacing it with the old per-reference lookup makes that witness fail.
An empty-target first-heal control also requires proof publication while
observing zero exact metadata reads: restoring the unfiltered production batch
call makes that witness fail. Positive filter results remain covered by the
cross-pivot exact-version and storage-namespace checks.
Restoring immediate storage descent or removing the subtree cache-hit branch
makes the corresponding focused test fail.
A coordinator control proves that
a valid identity-matched healer checkpoint pins its CL target for the first
actual post-restart Snap attempt across the ordinary stale-pivot window, that
waiting without a Snap peer does not consume that opportunity, and that
starting an attempt restores the rebase escape for the next pass. Removing the
production pin makes the focused restart decision regression fail, while an
explicit rebase still deletes the frontier. Three stale-heal controls require
the successor to be a known Engine forkchoice target beyond the exact
120-block window, pass a 30-second-throttled yield predicate through the
production multi-source importer, and turn its typed safe-boundary condition
into a truthy scheduling result so the same pass cannot fall into unbounded
forward gap filling. The call-site control also advances a real healing
snapshot immediately before the five-minute silence boundary and proves that
productive local or peer progress keeps the exact frontier; only five full
minutes without a later snapshot permits the stale yield. Removing the
production predicate wiring makes the exact call-site test fail. The range
tests prove that thirty-two durable account ranges are fetched with two bounded
workers per source, including six simultaneous workers through three
sole-writer request queues, with geth's 512 KiB snap byte limit. Completed
ranges are not replayed after restart, and a failed source's claimed range is reassigned. A
finite source generation may exhaust without stopping the node: the coordinator logs
that typed availability result, refreshes live sessions on its next pass, and
resumes without replaying the page committed by the retired generation. A
local database failure is the fail-closed control and still escapes the
coordinator. The pivot tests also prove that an empty RocksDB node requests only
the 65-block pivot tail,
publishes only the target-bound sparse checkpoint, restarts from it, and leaves
the CL target noncanonical until ordinary Engine forkchoice publication. The
multi-peer tests use stalled and failing peers to require deadline failover and
a delivery window independent of target height; soft-limited non-empty
body/receipt prefixes resume without replay, and a divergent CL target is
rejected before the import callback. CLI tests prove persistent identity/ENR
sequencing, two-directional `--nodiscover`, little-endian custody and flat cell
groups, and the session-owned writer queue.

The RLP regressions charge every nested object before descending into it, cap
string payloads before copying them, and prove that an oversized encoded block
access list is rejected before its object decoder runs. The announcement
regressions prove that only a fresh validated block hash or changed served range
sets the node's single coalesced wake bit, that an update racing an active sync
pass is not lost, and that shutdown wakes a coordinator waiting on its condition
variable. A one-second periodic pass remains as a bounded fallback. Final
TrieNodes healing reports monotonic processed/reused/fetched/request/byte
counters plus the number of whole durable subtrees skipped through
`peer.snap.heal_progress`, throttled to the first event, every 30 seconds, and
completion. Its focused controls are
`SNAP-STATE-HEALER` and `SNAP-HEAL-CHECKPOINT`; both are also included by the
broader `SNAP-` selectors above. The fetched-node hot-path control plants
positive witnesses for both single-key and batch trie reads, then proves that a
one-node remote heal performs only the initial missing-root MultiGet: the
content-hash-matched response is decoded once and consumed from the bounded
response cache, with no per-node point Get and no write-then-reread MultiGet.
Restoring either redundant production read
makes `SNAP-STATE-HEALER-PROCESSES-FETCHED-NODES-WITHOUT-REREADING-THEM` fail.

These selectors do not prove public reachability. Section 5 also requires an
ephemeral Hoodi run from an empty datadir, using the reviewed container runtime,
to record preset discovery, RLPx/eth+snap negotiation, a consensus-authorized
target, durable progress across restart, and continued head following. Keep its
command, image/revision, timestamps, peer/target evidence, and restart result in
the readiness-plan completion record. Never substitute peer-head-only download
or a manually injected static enode for that gate.

`scripts/hoodi-live-gate.sh` is the reviewed control-plane broker for that
remote run. It derives the image, container, and fresh datadir names from the
full checked-out revision; refuses a dirty checkout, a non-amd64 or
revision-mismatched image, paths outside `/data/hoodi-sec5-*`, a non-running
Lighthouse, and an unexpectedly owned rehearsal container. Read-only inspection
is separate from every mutation, and the broker never removes an image,
container, datadir, or evidence artifact:

```sh
cl-workbench doctor --strict
scripts/hoodi-live-gate.sh inspect

# Only after the runtime-only amd64 archive has been explicitly authorized for
# transfer to the named test host:
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh upload
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh load
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh start

scripts/hoodi-live-gate.sh status
scripts/hoodi-live-gate.sh logs
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh restart
```

`upload` transfers both the checksummed runtime archive and the pinned
`tools/runtime/docker-26.1.4-io-uring-seccomp.json`. The latter is Docker
26.1.4's official default profile with only the three io_uring syscalls added;
the broker refuses another daemon version or profile checksum. `start` and
`upgrade` retain a non-root/read-only container, drop every capability, set
`no-new-privileges`, and use that profile. This lets RocksDB issue concurrent
random reads without replacing Docker's syscall allowlist with an unconfined
container. Before touching an existing execution client, the broker starts the
exact candidate image in a read-only, networkless, capability-free one-shot and
requires its bundled probe to create RocksDB's exact 256-entry ring. Linux 5.15
must report the compatibility retry; any kernel, memory-lock, or seccomp failure
leaves the previous client running.

`HOODI_GATE_P2P_PORT` selects the same explicit TCP/UDP port inside and outside
the container when the default 30303 is already reserved. If a live run exposes
a runtime-only fix after its fresh datadir has accumulated durable progress,
the broker can replace that exact owned container without copying or deleting
the datadir:

```sh
HOODI_GATE_ALLOW_MUTATION=1 \
HOODI_GATE_PREVIOUS_CONTAINER=hoodi-el-sec5-previous \
HOODI_GATE_PREVIOUS_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_GATE_DATADIR=/data/hoodi-sec5-example/datadir-previous \
HOODI_GATE_CL_ALIAS=hoodi-el-public-example \
HOODI_GATE_P2P_PORT=30304 \
scripts/hoodi-live-gate.sh upgrade
```

`upgrade` requires the previous container to be owned by this gate,
read-only-root, explicitly non-root, labelled with the supplied exact revision,
and mounted on that same non-empty datadir. If an interrupted control-plane
operation left that exact container stopped, the broker starts it and waits for
public-RPC readiness before collecting the before evidence and continuing. It
preserves the previous container stopped on success. A previous-readiness,
new-container, network-attachment, exit, or replacement-readiness failure stops
the attempted process where applicable and restores the previous container;
neither path removes a container, image, artifact, or datadir.

The broker's default consensus-network alias is
`hoodi-el-public-36a22e47`, matching the persisted Lighthouse execution
endpoint on the dedicated gate. Override `HOODI_GATE_CL_ALIAS` only when the
paired consensus client was explicitly configured with another stable name.

After a live run has started, completion evidence or broker-only repairs may
move the checkout past the runtime image revision. Set
`HOODI_GATE_RUNTIME_REVISION` to that full ancestor revision when inspecting or
restarting the existing gate. The broker permits this override only when every
intervening change is below `docs/` or is one of the two reviewed Hoodi gate
scripts; any runtime-sensitive change keeps the exact-revision check
fail-closed.

`start` stops only the specifically labelled Section 5 rehearsal EL, preserves
that stopped container and its datadir, and connects the exact-revision EL to
the already-running Lighthouse alias. It uses the SSH user's non-root uid/gid,
a read-only container root, an empty revision-named bind-mounted datadir, preset
bootnodes, and no manual enode. If launch or network attachment fails, it stops
the failed gate container and restores the rehearsal EL. `restart` stops and
starts the same container, verifies its revision/datadir ownership first, and
prints the before/after RPC and datadir evidence needed to assess durable
progress; it is not by itself proof that progress advanced.
Restoring a multi-gigabyte live SNAP database can take several minutes. The
broker re-resolves Docker's loopback-only ephemeral RPC port after the restart,
waits up to 600 wall-clock seconds for public RPC by default, fails early if
the container exits, and accepts a bounded 30--1800 second override through
`HOODI_GATE_RESTART_READY_TIMEOUT`.

When a performance claim needs a same-host geth control, use the separate
`scripts/hoodi-geth-benchmark-gate.sh`. Its defaults pin the already-installed
geth v1.17.4 amd64 image by image ID and give geth the same Lighthouse, JWT,
networks, public P2P port, 50-peer limit, 4 GiB cache budget, and fresh SSD
datadir. The benchmark process is explicitly non-root with a read-only root
filesystem, all capabilities dropped, and `no-new-privileges`; Docker pulls are
disabled. `start` first verifies the exact owned ethereum-lisp source, empty
geth datadir, and networkless geth binary, then performs a rollback-protected
alias cutover. `restore` verifies both ownership chains before restoring the
preserved ethereum-lisp container. Neither action removes a container, image,
or datadir:

```sh
scripts/hoodi-geth-benchmark-gate.sh status
HOODI_GETH_ALLOW_MUTATION=1 scripts/hoodi-geth-benchmark-gate.sh start
# Collect equivalent time, RPC, peer, byte, CPU, and block-I/O samples.
HOODI_GETH_ALLOW_MUTATION=1 scripts/hoodi-geth-benchmark-gate.sh restore
```

The reviewed runtime image must also pass
`cl-workbench validation run runtime-smoke IMAGE`: this delegates to the
reviewed runtime smoke broker and checks non-root/read-only Hoodi startup,
direct RocksDB loading, public RPC, JWT rejection/acceptance, Engine
capabilities, and `eth_syncing`. It complements rather than replaces the remote
empty-datadir run.

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
cl-workbench validation run cold-scale
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
cl-workbench validation run cold-docs # cold, same container shape as test layers
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
cl-workbench validation run cold-integration > run.log 2>&1
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
