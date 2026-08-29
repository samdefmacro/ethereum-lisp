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

When a CI runner or supervisor cannot retain the attached `docker run` output,
set `COLD_TEST_CONTAINER` to a name beginning with `ethereum-lisp-cold-`. The
cold broker then retains that one otherwise identical restricted container so
its exit code and logs can be collected; callers must remove it after collecting
the evidence. The default remains `--rm`.

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
cl-workbench validation run cold-unit --match DEVNET-SNAP-HEAL-ESTIMATE
cl-workbench validation run cold-unit --match TRIE-ORDERED-RANGE-BUILDER
cl-workbench validation run cold-unit \
  --match TRIE-DIRECT-NODE-ENCODING-BOUNDS-RANGE-ALLOCATION
cl-workbench validation run cold-unit --match DEVNET-CLI-PUBLIC-PRESETS
cl-workbench validation run cold-unit \
  --match DEVNET-DISCOVERY-HAS-A-GENESIS-FORK-FILTER
cl-workbench validation run cold-unit --match EIP1459
cl-workbench validation run cold-unit --match DNS-TXT-DECODER
cl-workbench validation run cold-unit --match DISCV4-

# Persistent CLI identity/discovery behavior, verified snap client/server, durable
# pivot progress, bounded multi-peer failover, sole-writer request queues, and
# eth+snap multiplexing over one RLPx socket.
cl-workbench validation run cold-integration --match DEVNET-DATADIR-PERSISTS
cl-workbench validation run cold-integration \
  --match DISCV4-LOOKUP-CRAWLS-A-BOOTNODE-AND-DISCOVERS-A-PEER
cl-workbench validation run cold-integration \
  --match DEVNET-DISCOVERY-SERVER-ANSWERS-A-REAL-CLIENT
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
  --match DEVNET-SNAP-TIMEOUT-REVERTS-ONLY-THE-REQUEST
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-MULTI-RETRIES-A-REQUEST-TIMEOUT
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-RETRIES-A-REQUEST-TIMEOUT
cl-workbench validation run cold-unit --match DEVNET-SNAP-REQUEST-CAPACITY
cl-workbench validation run cold-unit --match DEVNET-SNAP-SOURCE-APPLIES
cl-workbench validation run cold-unit --match DEVNET-SNAP-SOURCE-POOL
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-SOURCE-POOL-YIELDS-A-STALE-PRUNED-PIVOT
cl-workbench validation run cold-integration \
  --match DEVNET-SNAP-SOURCE-POOL-VALIDATES-STORAGE-BEFORE-RELEASE-AND-MATERIALIZES-AFTER
cl-workbench validation run cold-integration \
  --match SNAP-LARGE-STORAGE-RANGE-VERIFIES-BEFORE-SOURCE-RELEASE
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-BYTECODE-ASSIGNMENT-LEARNS-ITEM-CAPACITY
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-BYTECODE-CAPACITY-ESCAPES-TARGET-TIME-MINIMUM
cl-workbench validation run cold-unit \
  --match DEVNET-DIAL-SNAP-DEMAND-REPLACES-DEGRADED-CAPACITY
cl-workbench validation run cold-unit \
  --match SNAP-MULTI-BYTECODES-USE-ONE-FIXED-GLOBAL-WORKER-POOL
cl-workbench validation run cold-unit \
  --match SNAP-ACCOUNT-CURSORS-SHARE-ONE-DURABLE-PUBLICATION-BATCH
cl-workbench validation run cold-unit \
  --match SNAP-RANGE-PROOFS-CLEAR-STALE-INCOMPLETE-MARKERS
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-FINISHES-BYTE-CAPPED-STORAGE-BEFORE-ACCOUNT-CURSOR
cl-workbench validation run cold-unit \
  --match SNAP-LEGACY-STORAGE-CURSORS-NEVER-PROMOTE-ROOT-CLOSURE
cl-workbench validation run cold-unit \
  --match SNAP-STATE-HEALER-FEEDBACK-BOUNDS-THE-GLOBAL-MISSING-QUEUE
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
  --match SNAP-STATE-HEALER-FINDS-RANGE-PROOF-INSIDE-COARSER-MISS
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-USES-GETH-COMPLETE-NODE-DIFFERENCE-FRONTIER
cl-workbench validation run cold-unit \
  --match SNAP-COMPLETE-NODE-SCHEME-NEVER-TRUSTS-A-LEGACY-TRIE-STORE
cl-workbench validation run cold-unit \
  --match SNAP-PROGRESS-REVOKES-EPOCH-TWO-COMPLETION-ATOMICALLY
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-NEVER-CONFUSES-ACCOUNT-PRESENCE-WITH-DEPENDENCY-CLOSURE
cl-workbench validation run cold-integration \
  --match DEVNET-LIVE-PERSISTENCE-ROUND-TRIPS-ON-ROCKSDB
cl-workbench validation run cold-integration \
  --match ETH-SYNCING-REPORTS-THE-DURABLE-SNAP-SKELETON-TARGET
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-BATCHES-DEFERRED-STORAGE-ROOTS
cl-workbench validation run cold-integration \
  --match SNAP-HEALED-SUBTREE-PUBLICATION-FAILS-CLOSED
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-DRAINS-OVERSIZED-OVERDUE-FRONTIER
cl-workbench validation run cold-integration \
  --match SNAP-STATE-HEALER-ADDS-SOURCES-THAT-ARRIVE-AFTER-HEALING-STARTS
cl-workbench validation run cold-unit \
  --match SNAP-STATE-HEALER-KEEPS-SOURCES-BUSY-WITHIN-GETH-LOOKUP-CAP
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-STALLED-LONG-HEAL-YIELDS-TO-A-STALE-CONSENSUS-TARGET
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-COLLAPSED-SOURCE-POOL-YIELDS-AFTER-LOW-TOTAL-THROUGHPUT
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-UNDERFILLED-HEAL-WAITS-FOR-LOW-TOTAL-THROUGHPUT
cl-workbench validation run cold-unit \
  --match DEVNET-SNAP-EXHAUSTED-SOURCE-GENERATION-YIELDS-TO-A-STALE-CONSENSUS-TARGET
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-MULTI-YIELDS-A-STALE-RANGE-PIVOT-AFTER-DURABILITY
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-MULTI-PROPAGATES-A-STALE-DEPENDENCY-YIELD
cl-workbench validation run cold-integration \
  --match SNAP-GLOBAL-STORAGE-LANE-PROPAGATES-A-STALE-PIVOT-YIELD
cl-workbench validation run cold-integration \
  --match SNAP-STATE-IMPORT-MULTI-NEVER-PUBLISHES-AFTER-A-GLOBAL-STORAGE-YIELD
cl-workbench validation run cold-integration \
  --match SNAP-TRIE-NODE-SERVER-CAPS-DISK-LOOKUPS
```

The snap tests reconstruct and verify account/storage roots, return the
authenticated reconstructed page for direct content-addressed persistence,
reject altered compact proofs, and prove that verified trie records and
hash-matched bytecodes perform no database reads while authenticated puts
repair planted corrupt local values. Productive range imports retain their
exact authenticated pivot so the complete same-root proof set can use the
zero-TrieNodes completion path. If every live source explicitly rejects that
state, its last verified cursor remains durable for the next coordinator pass
to rebase onto a serviceable fresher root. They derive complete coarse
subtrees from the verified range, batch code-existence probes before requesting
a page's missing bytecodes, reject
proof-edge nodes, and buffer the subtree hash with its account content and
external dependencies before a separate synchronous cursor batch publishes the
whole WAL prefix. The failure regression permits that idempotent content to
survive while proving the cursor stays behind a failed seam and a retry
completes. Fresh empty stores also classify every reconstructed record under a
progress-version-five, closure-epoch-three geth-style complete-node contract:
proof-edge or otherwise open
nodes carry a negative marker in the same content batch, while fully closed
interior groups require no positive record per node. The migration control
plants legacy trie nodes under both the old epoch-one and epoch-two scheme
markers, proving that their content remains available but hash presence remains
conservative;
malformed scheme and incomplete markers fail closed. A live-failure regression
also plants old range-plan and subtree-proof namespaces around a root with one
missing child, then requires the current healer to ignore every shortcut,
fetch that child, and only then publish state history. If
a later account or StorageRanges page proves closure for a node that an earlier
partial page marked open, the proof/record/cursor batch deletes that exact stale
negative. The focused marker-lifecycle regression plants both account and
storage negatives, proves only the closed nodes, and requires the open markers
to remain while the superseded markers disappear.
StorageRanges pages publish equivalent
storage-subtree proofs with their node and cursor batch. Completing the final
partition does not publish a whole-root proof: durable cursors establish range
coverage, while the final healer remains the descendant-closure trust boundary.
After a full post-order walk, or an equivalent versioned complete-node proof,
the healer publishes a separately namespaced storage-root record. Account roots
retain the coarse-depth dependency boundary. The integration regressions
observe both kinds before final TrieNodes traversal. Legacy account plans
promote only buckets whose dependencies are actually closed. A legacy cursor
set without a whole-root proof remains conservative; the storage-promotion
control retires the short-lived cursor-derived root-shaped proof and refuses to
manufacture shallow completion records from cursors alone. Fully healed roots
use the separate root namespace and remain reusable across changed pivots. An
incomplete legacy large-storage plan excludes only its account prefix bucket,
rather than forcing a full account-tree rescan, and cannot publish the final
promotion marker until its cursors finish. New range pages instead persist a
bounded dependency proof for such a bucket. A healer regression rejects a
direct read of that account-subtree node, observes the proof skip, and still
requests the listed storage paths; malformed, duplicate, empty-root, or
over-limit dependency values fail closed. The public depth regression fixes the
first lookup and coarse range-publication boundary at four nibbles and the
bounded nested publication layer at five. The layered changed-bucket regression
changes one of sixteen children across pivots, requires the other fifteen to be
skipped, and requires fewer than half as many processed nodes as a coarse-only
index. Older still-finer proofs remain consumable below a changed bucket.
They batch complete small storage tries with each account cursor and
prove that the range-only proven-absent insertion produces the
same root as the ordinary checked insertion and rejects empty values,
prebuffer every proof-authenticated account trie record before dependency
resolution while leaving the durable cursor absent, retain only record hashes
in the pending page, and require the later metadata-only cursor batch to follow
that WAL prefix,
persist the authenticated prefix of byte-capped large storage, record those
roots with each durable page, and atomically publish the complete plan only
when the rebuilt account root equals the authorized state root. Sixteen
restart-safe StorageRanges cursors, seeded atomically after the last slot of
the initial authenticated nil-bound prefix, immediately finish each large trie
through 512 KiB-capped pages before the owning account cursor advances. The
byte-capped-storage regression observes that production call site, models a
public hash-scheme peer which rejects an explicit replay of that initial
prefix, and requires the first bounded origin to be strictly greater than its
last authenticated slot. It then proves
the final closure walk never returns to the account root and repairs compact
storage-proof boundaries in fewer than sixteen TrieNodes requests. Removing the
pre-cursor storage callback is the mutation control and fails its durable-task
witness. A
second regression interrupts StorageRanges after one page and proves a fresh
source resumes the exact durable cursor. A concurrency regression blocks one
source and proves a faster source receives its next partition without waiting
for a global wave. The dynamic-source regression additionally holds the first
account result behind an unfinished dependency while the initial provider
snapshot contains only that source. A timed range-coordinator wake must admit
two later sources and give both range work before the blocked page can publish
its cursor; waiting only for account progress deadlocks the mutation control.
A focused scheduler control broadcasts storage-shaped worker notifications
every five milliseconds across the same wait queue and still requires the
absolute source-refresh deadline to fire in fifty milliseconds. Replacing that
deadline with a fresh relative timeout after every wake leaves the waiter live
past the bounded join and turns the control red.
The production peer-queue regression puts two account jobs
ahead of a storage job and proves the storage request bypasses the occupied
account response slot, then routes out-of-order typed replies to the correct
workers. A pump regression separately proves that a SNAP response reaches that
router instead of being rejected as unsolicited. Rate controls prove the first
peer starts account and storage ranges at 64 KiB, a fast sequence grows at
most twofold per response toward 512 KiB, a slow sequence falls back without
crossing the lower bound, and the production source applies the learned
per-type cap to its outgoing packet and limits StorageRanges account hashes to
geth's `capacity / 1024` estimate. ByteCodes learns in returned-code units
from 1 through the 84-hash protocol cap; a response taking the entire capacity
target still advances 1 to 2 through geth's explicit plus-one ceiling instead
of becoming trapped at the minimum. A shared-pool control then proves a churned
peer inherits the live mean range and ByteCodes capacities instead of restarting
at 64 KiB and one item. Concurrent pages prove that their
batches never exceed the fixed thirty-two-worker import-wide pool. Ready
account results prove sixteen successor cursors share one durable publication
write, while the existing injected-failure controls keep all of those cursors
behind an unsuccessful seam. A changed-root rebase installs
a non-empty, non-root range witness; legacy, rebased, oversized, or incomplete
dependency plans retain the fail-closed full-root traversal. The tests also
inject a failed database batch to prove progress never outruns verified account
state. Only the complete same-root range/dependency proof set or the final
traversal can install the completion marker. The final
healer tests prove every request remains within geth's 1,024-path cap and the
processing-rate feedback bounds the aggregate missing queue. Event-loop
controls block one source, integrate a faster source's response independently,
discover child work from it, and require that same fast source to receive the
child before the slow response returns. A direct shared-queue control retires a
failed source and requires its exact work and condition to return to the
coordinator. Another dispatches two 1,024-work requests and requires frontier
accounting to report 2,048 in-flight works rather than two requests. Capacity
controls retain the isolated-source learner as a fallback, while the production
control exposes the request queue's live TrieNodes item capacity, divides 800
and 200-item peer capacities by the same local throttle into 200 and 50-work
assignments, and overrides stale healer-local values before capacity ordering.
The maximum initial throttle also preserves geth's one-item cold probe. These
controls reject the former production double-controller in which the shared
0.1 message-rate EWMA learned a value the healer never consumed. They also
prove a second source actually serves TrieNodes. A late-admission control starts healing
with one source, exposes a second source through the live provider after work
has begun, and proves that the new source serves TrieNodes before completion.
The request encoder still sorts the whole slice, groups every storage path for
one account into a shared wire path set, and maps partial replies back to exact
DFS order. A boundary regression
pins the production completion-proof depth at four nibbles and proves work on
either side of that threshold is classified correctly, keeping rebases granular
without expanding toward a six-nibble proof index. Local traversal proves
that more than one trie hash crosses the ordered
multi-get seam in a batch, while the database integration control proves one
generic RocksDB batch reaches exactly one native call and preserves
duplicate-key order and per-key absence. A healer-specific RocksDB control
proves that one 4,096-key local batch reaches eight bounded read workers,
performs present-value decoding on all eight workers, rejoins values,
presence bits, and decoded objects in exact input order, and propagates an
injected worker failure. Switching the production dispatch back to serial makes
its eight-call and eight-decoder-thread witnesses fail. The frontier limiter
also proves that the soft durable region continues to reserve worst-case
sixteen-way expansion room while a 10,000-work transient frontier may use the
full 4,096-key database batch, avoiding one reader-thread lifecycle per 512
nodes. The oversized-overdue-frontier integration control forces checkpoint
eligibility while an 8,192-work restart frontier expands past the durable cap;
the production path now maintains the exact DFS count on every push/pop, so
that hot inner-loop decision is constant-time rather than repeatedly taking
the linear length of the whole list. Generic controls
enforce the 4,096-key
and 4 MiB key-byte bounds. The RocksDB construction regressions witness the
exact 256 MiB block-cache and 384 MiB level-compaction preset budgets for the
shared 16 GiB EL/CL profile, ten-bit full Bloom policy, production
table-factory call site, the four-way large-compaction subtask bound, and an
enabled `ReadOptions.async_io` on the live adapter handle. Removing either
native setter, changing the subcompaction bound, or changing async I/O to zero
makes its corresponding configuration/readback witness fail. Async I/O here
does not imply the separate coroutine build needed for cross-level MultiGet
scheduling.
The bounded healer-code regression places one duplicate code hash on opposite
sides of a two-item flush: it requires a second durable MultiGet lookup but no
second peer fetch, proving traversal-wide code-hash heap is released safely.
The native-transfer regression intercepts a real RocksDB write and requires its
key/value pointers to name the exact pinned Lisp vectors, then requires one-key
MultiGet to use exactly two native bulk copies: one into the contiguous key
buffer and one out of the returned value. It also covers the zero-length pinned
field case. Falling back to per-record foreign allocation or per-octet CFFI
access makes those witnesses fail while all synchronous durability checks stay
unchanged. The fetched-node cache control additionally requires remote trie
nodes to use a buffered healer batch, then consumes them without a redundant
point read or second MultiGet before the synchronous completion seam. A
separate adapter regression observes the buffered write-options
followed by the ordinary synchronous options. Its SIGKILL child writes an
unsynced content-addressed prerequisite batch, then a synced cursor batch; the
parent kills it without closing RocksDB and requires both batches after reopen.
This proves the optimized prefix is covered by the cursor's durable seam rather
than merely surviving a clean close.
The reviewed image builds additionally fail
unless the pinned native library links `liburing.so.2`, and the runtime layer
checks that the dependency resolves before its client smoke. The vendored
compatibility patch is applied with fuzz disabled so source drift fails the
image build. They persist a bounded checksummed work frontier only after the
buffered node prefix is flushed and every in-flight response has been
integrated. Abrupt source loss then resumes the exact queued work without
rereading the root; corrupt, stale, empty, or oversized checkpoints fail
closed, and
rebase/completion failure injection proves that checkpoint invalidation remains
atomic. A large-frontier control round-trips a 5,000-item live checkpoint and
proves that its bounded record stays below the byte cap. A live-shape control
resumes an 8,192-work frontier, expands its first branch to 8,207 at an overdue
checkpoint, and proves that the independently bounded live frontier sends a
full 1,024-path request while the prior durable record remains authoritative;
the next checkpoint is published only after work drains back to 8,192. The same
control keeps pending missing work in the exact frontier accounting. Restoring
the old checkpoint-dependent refill produces thousands of requests and makes
the full-width plus total-request witnesses fail. A separate count regression
proves that
three sources raise total concurrent capacity to 3,072 while every request
remains at the pinned geth 1,024-lookup cap. The serving regression sends 1,041 valid
root paths and proves only 1,024 disk lookups are returned; raising the
production cap makes it fail. Restoring the old immediate checkpoint stop
makes the live-shape control fail with the observed public-node error. Separate
controls prove that account traversal defers storage roots into multi-path
requests, that the version-four checkpoint round-trips its node-completion
sentinel while versions one through three fail closed as cache misses, and that
content-addressed
account and contract-storage
subtrees
proved under one pivot reduce the decoded work under the next pivot. The
checkpoint codec round-trips armed storage-subtree and node-completion sentinels,
and a namespace
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
The exact-difference-frontier control places the same complete old storage trie
under a new root in two databases. The closure-epoch-three run skips locally
complete storage hashes, fetches the same changed nodes as the legacy run,
clears every negative marker, and processes less than one eighth as many nodes.
Removing the storage hash-presence branch or prematurely trusting a marked node
makes the focused test fail. A separate mutation control plants a complete
local account trie whose leaf names an absent non-empty storage root. It
requires the healer to traverse the account node, fetch the storage dependency,
and make it durable before state-history publication; restoring the epoch-two
account-node shortcut makes that test fail. The epoch-two completion-migration
control begins with completed progress and state-history, then requires one
atomic load-time migration to revoke both publication authorities while
preserving completed range cursors and reusable trie content.
Restoring immediate storage descent or removing the coarse subtree cache-hit
branch makes its corresponding focused test fail.
A coordinator control proves that
a valid identity-matched healer checkpoint pins its CL target for the first
actual post-restart Snap attempt across the ordinary stale-pivot window, that
waiting without a Snap peer does not consume that opportunity, and that
starting an attempt restores the rebase escape for the next pass. Removing the
production pin makes the focused restart decision regression fail, while an
explicit rebase still deletes the frontier. Four stale-heal controls require
the successor to be a known Engine forkchoice target beyond geth's exact
pivot-relative 120-block window, pass a 30-second-throttled yield predicate
through the production multi-source importer, and turn its typed safe-boundary
condition into a truthy scheduling result so the same pass cannot fall into
unbounded forward gap filling. The call-site control also advances a real healing
snapshot immediately before the five-minute silence boundary and proves that
productive local or peer progress keeps the exact frontier; only five full
minutes without a later snapshot permits the stale yield. Removing the
production predicate wiring makes the exact call-site test fail. A collapsed
pool additionally measures processed-plus-fetched work over a five-minute
wall-clock window: useful individual responses cannot pin an old root when the
surviving pool's aggregate throughput falls below 131,072 work units, while a
high-throughput collapsed pool remains on its exact authenticated frontier.
The range tests prove that sixty-four durable account ranges feed one AccountRange
dispatcher per source and bounded global dependency schedulers, while no more
than sixteen decoded account pages remain claimed across the dependency
pipeline.
The GC-watermark control requires the in-phase full-collection interval to be
disabled even after one million durable cursor publications. The separate
moving-pivot control still witnesses exactly one collection after every worker
has joined and unreachable queues have been discarded. Together these
distinguish partition granularity from the memory bound exercised by the 6 GiB
embedded heap and 7 GiB remote container limit while matching geth's sixteen
account chunks. The range-proof
marker control additionally retains the page
result after publication and requires both closure hash sets and the expanded
records to be empty. The production page-log control requires non-negative
`dynamicUsageBytes`, `bytesConsed`, and `gcRunMs` fields, with an exact
internal-time-to-milliseconds unit control, so a remote run can
separate live Lisp heap from RSS retained by SBCL or RocksDB.
The allocation-profile duration control accepts only zero (disabled) or one
through 300 seconds; malformed, negative, or wider requests fail before any
profiler thread starts. The reviewed gate applies the same numeric boundary
before forwarding the duration as a container environment value. A report
projection control proves that only the flat function table survives and that
sampled-thread return values cannot enter the fixed-prefix evidence lines.
The production pivot-import control also wraps the real importer and records
the profiler start seam. It requires exactly one start before the importer is
entered, so a live range/dependency stall remains profileable even when it has
not published a first page. Moving the start back into the page callback
reverses that witness and fails the control.
The inbound-transaction freshness control supplies malformed payloads for
Transactions, NewPooledTransactionHashes, and PooledTransactions while the
backend gate is closed. All three message ids must be handled without invoking
a decoder or admission callback, proving the gate occupies pinned geth's
pre-decode seam. A CLI wiring control then acquires the real sync claim and
requires that backend predicate to change from true to false and back to true
after release. Mutating the protocol predicate to allow traffic unconditionally
makes the malformed-payload control fail in the RLP decoder.
Three
sole-writer request queues overlap independent response types with geth's
adaptive 64--512 KiB snap byte limits. A production-call-site control observes
the density-selected partition count, uses a second lane only when the plan has
one, and proves a one-chunk plan never manufactures concurrency by timing out
and double-claiming its cursor. It also proves that one account page uses the
fixed import-wide StorageRanges worker set before its cursor advances. A
density control reproduces geth v1.17.4's remaining-slot
estimate, requires a quarter-space 8,192-slot prefix to select two active
chunks, and retains sixteen durable records by completing the unused sentinels;
restoring the fixed sixteen-way plan makes that witness fail. A two-root control
loads an advanced version-three cursor set, migrates it at its authenticated
pivot, and requires a second state root with the same account/storage-root pair
to observe the exact successor while a changed storage root starts fresh.
Putting the state root back into the version-four key makes that witness fail.
A two-root concurrency control
then holds one partition open, requires the
second root to start before that request is released, and proves maximum live
requests equal the fixed source count. Replacing the rotating claim with a
queue-head-only mutation makes that witness fail. Another control queues two
independently verified partition results behind the commit coordinator and
requires exactly one buffered database batch; replacing it with a synchronous
write or reducing the storage cursor batch limit to one makes that positive
witness fail. A production-mode companion leaves that commit consumer paused,
then requires one source worker to issue and queue at least two consecutive
StorageRanges results without any database write; restoring the per-source
commit call makes the second request unreachable. The RocksDB SIGKILL
durability oracle above proves a following
synchronous account cursor flushes this preceding WAL prefix. A separate
same-datadir reverse-order Hoodi A/B on 2026-08-26 rejected a deeper
request/materializer handoff. Revision `196b3e30` completed 82 account pages,
587,492 accounts, 52,574 storage accounts, and 1,195 StorageRanges samples in
781 seconds: 6.30 pages, 45,134 accounts, 4,039 storage accounts, and 91.81
StorageRanges samples per minute. The immediately following control on
`1d49fa75` completed 251 pages, 2,336,962 accounts, 208,746 storage accounts,
and 1,972 StorageRanges samples in 758 seconds: 19.87 pages, 184,984 accounts,
16,523 storage accounts, and 156.09 StorageRanges samples per minute. Both
runs rebased their pivot once on the same host and preserved the same benchmark
datadir. The deeper handoff was therefore removed: proof validation still
releases the actual pooled peer before local materialization, but each fixed
lane integrates its authenticated page before claiming another, matching
geth's delivery-then-next-assignment runloop cadence. A separate
corrective run of the resulting `a982521d` revision on the same advancing
datadir completed 95 pages, 532,139 accounts, 47,741 storage accounts, and 656
StorageRanges samples in 753 seconds. It received 883 MB, versus 1.11 GB in the
preceding `1d49fa75` control, but account count fell by more than fourfold because
the cursor had entered a denser contract/code region and the run rebased again.
The cross-cursor account/page rates are therefore retained as historical
diagnostics, not a causal speed verdict; future same-host comparisons must use
wire bytes, dependency latency, peer failures, and a reproducible snapshot or
fresh empty datadir. The corrective profile exposed the next actionable gap:
40 of 95 pages spent at least 60 seconds in storage dependencies, 25 spent at
least 120 seconds, and logs repeatedly consumed the fixed 30-second request
deadline before failover.

The request-timeout control creates sixteen cold trackers at Geth's
twenty-second RTT, supplies each first synthetic live response with the exact
ten-percent EWMA impact, and requires the production queue call site to retain
the cached RTT until its tuning interval. The forced tuning oracle checks
geth's zero-based `floor(sqrt(N))` sample, two--twenty-second clamp, 0.25 cache
impact, connection-driven confidence detuning, threefold confidence-scaled
timeout, and sixty-second ceiling. Closing five queues removes their RTT and
throughput snapshots without rewriting the cache early. A message-specific
control first collapses that pool baseline to six seconds and only then creates
the first StorageRanges rate. It requires the unobserved type to retain the
cold sixty-second deadline, then requires the storage assignment and its
reported telemetry deadline to follow the larger threefold per-message EWMA
under the same sixty-second cap; a zero delivery may reset throughput but must
not inflate or erase that observation. Fifty successful full-size deliveries
then decay the RTT while saturating the 512 KiB cap: the request must retain a
thirty-second decode allowance without increasing capacity. Removing that
allowance makes the control fail. Recording its timeout resets throughput, so
the following 64 KiB probe must return to the six-second pool deadline instead
of pinning a dead peer for thirty seconds. Replacing the production maximum
with the pool baseline makes the earlier cold-type control fail. The capacity controls
use geth's 0.1 units-per-second EWMA and
`ceil(1 + 1.01 * throughput * live-timeout)` directly: a fast first range or
ByteCodes response can reach the protocol cap, a zero delivery returns to the
minimum without changing RTT, and a new peer inherits mean throughputs rather
than a timeout-specific capacity. TrieNodes uses that same tracker in returned-
node units and exposes its live 1--1,024 capacity to the healer. These controls
reject the former 0.2 EWMA,
immediate-median timeout, and double/half step limiter. A peer-range verdict
control requires durable `ACCEPTED` to return normally while deterministic
`INVALID` still raises the validation failure; this protects the ordinary
pre-pivot block buffer from being mistaken for an executable-state failure.
The request-lifetime controls additionally allocate distinct non-zero wire ids,
restore the caller's logical id on a matched response, expire one job without
closing its session, absorb a late response without completing its replacement,
retry an AccountRange timeout on the same source identity, and keep a pooled
dependency peer out of the whole-peer cooldown table after the same typed
timeout. Restoring the old session-fatal deadline or reusing logical id `1` on
the wire makes these controls fail.

The StorageRanges direct-decoder controls retain canonical single-byte and
trailing-data rejection, exact two-field storage records, the geth-compatible
large-response allowance, and the 131,072-item per-list ceiling. On the pinned
SBCL, decoding one 8,192-slot response through the production message dispatch
allocates about 1.05 MB and must remain below 1.3 MB; routing `#x03` back through
the generic RLP tree allocates about 2.2 MB and makes the control fail. A
separate 32,769-slot container microbenchmark measured 5 ms and 4.19 MB for the
direct cursor versus 11 ms and 8.88 MB for the generic tree. This is a bounded
decoder-path comparison, not by itself a public-sync throughput claim.

The exact `dd2a14f2` same-datadir Hoodi run started at
`2026-08-27T06:55:34Z`. In its first roughly fifteen-minute sample it completed
133 pages and 1,194,404 accounts while its source pool grew from three to
fourteen. In the following roughly fifteen minutes it completed another 203
pages and 1,890,571 accounts, the pool reached nineteen (twenty high-water),
and request-timeout growth fell from 414 to 93. Session-closed dependency
failures remained cumulative at 37 rather than collapsing the pool. This proves
the request-local timeout lifetime, but not geth throughput parity: the second
window was about 127,700 accounts/minute, roughly 35% of the pinned same-host
geth account rate. The container remained below its 7 GiB limit, but its second
endpoint used 4.504 GiB RSS and reported 77.6/126 GB cumulative block I/O.
A five-second process sample used 3.40 of eight CPUs, read 62.9 MiB/s, wrote
70.7 MiB/s, and spent only 0.2% in I/O wait; a simultaneous device sample kept
SSD await near one to two milliseconds and utilization near one third. The next
controlled candidate therefore raises only RocksDB background job parallelism
from four to eight while retaining the fixed 512 MiB memtable budget, then
measures the same preserved datadir again.

That `cd5fd0be` candidate started at `2026-08-27T07:39:28Z`. Its first roughly
fifteen-minute window completed 137 pages and 1,168,316 accounts at 4.046 GiB
RSS; the second completed another 118 pages and 1,096,588 accounts at 4.931 GiB
RSS. Completed-page dependency latency improved: cumulative means fell from
47.4 seconds in the first window to about 33.0 seconds in the second, while
storage fell from 35.0 to about 25.2 seconds and code from 21.1 to about 8.2
seconds. Aggregate throughput did not improve because the refreshed source pool
remained at twelve to fifteen rather than the preceding candidate's nineteen to
twenty. The local RocksDB change is therefore retained as a bounded phase
latency improvement, not presented as a geth-parity result.

The next transport audit found that every compressed devp2p payload still used
the byte-at-a-time pure Lisp Snappy COPY loop even though the reviewed runtime
already ships `libsnappy.so.1`. The native control cross-decodes native and pure
outputs in both directions over empty, literal, repetitive, and 512-KiB inputs,
and both paths reject the same invalid back-reference. Go decode vectors and
corrupt-input controls remain unchanged. In the isolated Workbench container,
a 4-MiB repetitive payload decompressed in about 3 ms through libsnappy versus
41 ms through the oracle, and compressed in about 3 ms versus 172 ms. Seventeen
RLPx unit controls and all sixty-nine SNAP integration controls pass with the
native production path.

A later healer timeout audit found one remaining policy mismatch above that
transport: AccountRange workers already requeued a typed request timeout, but
the TrieNodes result coordinator still retired its source.  The healer now
returns the exact immutable work to its shared queue while leaving that peer
idle and available; the transport has already reset TrieNodes capacity and
will discard a delayed response by its expired wire id.  The production-entry
control makes one source time out once and then answer the retry, proving both
completion and a zero source-error callback count.  Removing the classification
turns that control red with typed healing-source exhaustion.  After restoration,
all eighty-five SNAP unit controls and all seventy SNAP integration controls
pass through the cold Workbench entrypoints.

The exact `f72afc7f` image exposed both controls on the formal Hoodi datadir. It
started at `2026-08-26T12:28:47Z` and exited at `12:34:48Z` without OOM. Before
exit it logged twelve six-second request expiries, fifteen import failures, and
no completed account page: the first tiny response had collapsed the raw pool
sample directly to the six-second floor. The terminal condition was a forward
range candidate whose normal durable verdict was `ACCEPTED`; the old caller
misclassified that pre-state result as a fatal non-executable block. The prior
`a982521d` container was restored on the unchanged datadir at `12:41:43Z` and
immediately resumed Engine `eth_syncing`. The cold-RTT inheritance and buffered
verdict regressions above are therefore production-derived, not speculative
tuning.

The exact successor `5bdd9aae` image was uploaded with archive SHA-256
`676259397a4f3f4bae14fae7662661a2cc6de7970c0a78adb68c26ef402cfe8c`
and upgraded onto that unchanged datadir at `2026-08-26T13:07:56Z`. At the
`13:20:57Z` endpoint it had run for thirteen minutes without restart, OOM,
request timeout, or peer-range fatal; it held thirteen peers at 171.79% CPU and
3.888 GiB RSS. The retained range state entered healing instead of replaying
pages. From `13:10:28Z` through `13:21:28Z`, healer progress advanced from zero
to 2,062,336 processed nodes: 2,059,651 were locally reused and 2,681 fetched in
18 requests. The live frontier simultaneously expanded to 27,474 works, so this
is evidence that the two `f72afc7f` failures are fixed and productive healing
resumed; it is not a completion percentage or a fixed healer ETA.

A separate
failover control
retires one lane after a transport error and requires another lane to finish
the exact released partition. A post-verification buffered database failure is
also required to reach the caller unchanged instead of being misclassified as
remote source exhaustion. The source-pool controls prove that
learned capacity wins an idle tie, bytecode reservations remain independent of
storage load, an ordinary failed dependency peer enters cooldown while the same
request succeeds elsewhere, and a generation with only cooled but otherwise
live transports waits until one is eligible instead of returning an empty
source set. A separate production-boundary control resolves the CL target from
the full live ETH pool and leaves the later pivot-state probe SNAP-only;
restoring the old target resolver's SNAP filter makes its positive ETH-source
witness fail. The positive empty-pool control still returns immediately. An
explicit state-unavailable response cannot
be readmitted by expiring that cooldown or be misattributed to the unrelated
account-page source. The stale-pruned source-pool control proves that one such
response immediately consults the CL-authorized stale-target predicate and
raises a scheduling yield even while a changing peer generation remains
nonempty. Its account-dependency and global large-storage companions require
that yield to stop the worker generation and reach the coordinator without an
`on-source-error` callback, storage-source error, or fatal database
classification. The end-to-end large-root cancellation control additionally
requires that the owning account page never enter content publication after
its global storage job stops. Temporarily converting that typed cancellation
back to a false empty result makes the control observe a publication and fail.
Temporarily disabling either response-boundary predicate or the dependency
scheduler's typed handler makes its focused control fail.
ByteCodes and StorageRanges integration controls return an
invalid but transport-successful response from the first peer, require client
verification to retire that exact peer before its reservation is released, and
then complete the unchanged dependency request through a second peer. The
small- and partitioned-storage timing controls additionally require proof
verification to produce only an authenticated carrier while reserved, release
the actual StorageRanges slot, and materialize records/subtree metadata
afterward. Moving large-storage materialization back into the verified callback
makes
`SNAP-LARGE-STORAGE-RANGE-VERIFIES-BEFORE-SOURCE-RELEASE-AND-MATERIALIZES-AFTER`
fail. The ordered-range trie controls pin the reconstructed root against
ordinary insertion and cap the 5,000-key byte-key builder below 0.9 MB on the
pinned SBCL; expanding every secure key into a temporary nibble vector exceeds
that bound. Concurrent
rejection writers retain every stable peer id.
The discv4 unit controls retain only UDP-bonded public routing seeds, the CLI
seed merge always retains configured bootnodes while bounding process-local
Kademlia hops at 256, and the socket integration controls keep fork-ID
mismatches excluded from TCP while advertising the stable responder UDP port.
Completed
ranges are not replayed after restart, thirty-two-range cursors expand without
replay, and a failed source's claimed range is reassigned. SNAP demand raises
the quality requirement from generic outbound sessions to sixteen capable SNAP
sessions while retaining the absolute fifty-peer bound. ETH-only outbound
admission cannot fill the protected capacity until the non-degraded SNAP pool
reaches that same workload target; a per-response-type failure removes one from
the quality count and opens a replacement slot, while success in another type
cannot conceal the failure. A dial-registry control fills all 1,024 bounded
dynamic candidate slots, rejects the next candidate, and leaves the independent
fifty-peer and fifty-active-dial controls unchanged. A
finite source generation may exhaust without stopping the node: the coordinator logs
that typed availability result, refreshes live sessions on its next pass, and
resumes without replaying the page committed by the retired generation. A peer
which rejected the active pivot is remembered by stable node id across those
passes, so it is not probed or fanned out every second; selecting a genuinely
different pivot clears that process-local set. A
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
completion. The event also reports `frontierWorks`, `deferredStorageWorks`, and
`remoteWorks` for the currently discovered queue, plus
`knownIncompleteNodes` for conservative durable negative markers observed by
the active traversal. Production restart never hydrates the complete marker
namespace; bounded ordered marker MultiGets preserve exact fail-closed
classification as references enter the DFS. The frontier can grow when a
decoded parent reveals children, including a small bounded DFS overshoot above
the 131,072-work remote-admission target, and unvisited retained markers do not
inflate this active count. A
live pipeline examines at most 4,096 local works in one refill before returning
to completed peer events, so a mostly reusable trie cannot leave remote slots
idle while the coordinator tries to discover enough misses to fill the entire
admission window. None of these fields is an authoritative final-work
denominator or completion percentage. The
production call-site control moves a returned node from in-flight work to the
local stack without double-counting it and requires every live-frontier field
to reach zero on completion. Source-pool controls also prove that dependency
work adopts a newly connected live SNAP transport immediately when every
previously registered transport is cooling, without waiting for an account
page to finish and refresh the pool. Its focused controls are
`SNAP-STATE-HEALER` and `SNAP-HEAL-CHECKPOINT`; both are also included by the
broader `SNAP-` selectors above. The fetched-node hot-path control plants
positive witnesses for both single-key and batch trie reads, then proves that a
one-node remote heal performs only the initial missing-root MultiGet: the
content-hash-matched response is decoded once and consumed from the bounded
response cache, with no per-node point Get and no write-then-reread MultiGet.
Restoring either redundant production read
makes `SNAP-STATE-HEALER-PROCESSES-FETCHED-NODES-WITHOUT-REREADING-THEM` fail.
`SNAP-STATE-HEALER-NEVER-HYDRATES-GLOBAL-INCOMPLETE-MARKER-SET` guards the
restart boundary with a mutation control: the production healer must not call
the full marker loader, while the loader remains available as an explicit
test/operator integrity oracle. `SNAP-INCOMPLETE-NODE-PRESENCE-IS-ORDERED-AND-FAIL-CLOSED`
checks exact batch order, absence, and malformed-record rejection. The
companion `SNAP-STATE-HEALER-NEVER-REBUILDS-GLOBAL-PROOF-BLOOM` control proves
restart also avoids enumerating retained subtree proofs; exact bounded metadata
MultiGets retain their cross-pivot reuse. The
RocksDB iterator control
`ROCKSDB-KEY-VALUE-DATABASE-ITERATOR-COMPARES-RAW-KEYS` proves range bounds no
longer allocate a hex rendering for each visited key and includes a direct
wrapper invocation as its mutation control.
`SNAP-STATE-IMPORT-MULTI-YIELDS-A-STALE-RANGE-PIVOT-AFTER-DURABILITY`
also replaces the collection hook with a positive witness and proves that a
durable moving-pivot yield releases the joined range scheduler exactly once
before the stale-pivot condition escapes to the coordinator.
The discovery genesis-filter control forces the store's nonblocking guard probe
to fail, then proves the node still caches an EIP-2124 context identical to its
known genesis and enables its ENR record predicate. This keeps a fresh SNAP
import from disabling cross-chain filtering while it owns persistence.
The public syncing regression removes every in-memory remote block, persists a
CL-authorized skeleton target in the direct RocksDB provider, and requires
`eth_syncing.highestBlock` to retain that target throughout AccountRange and
healer work while another thread continuously owns the node store guard.
Deleting the skeleton restores `false`; mutating the production snapshot to
ignore the direct, authority-validating point-read overlay makes the positive
assertion fail. The older store-guard contention control remains green, so this
point read does not make Engine health checks wait behind a long state write.

Dial-scheduler controls keep geth's default `maxPeers / 3` outbound target at
sixteen sessions for the default fifty-peer table while SNAP demand is active.
They additionally prove ETH-only or response-degraded sessions do not satisfy
that target, so discovery still replaces missing state capacity without raising
the transport target to the CPU-expensive former half-table value.

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
`no-new-privileges`, use that profile, and set both Docker memory and memory-swap
to exactly 7 GiB around the runtime's 6 GiB SBCL heap. `status` and `restart`
fail closed unless both limits remain present, so a host-wide Docker default
cannot silently replace the documented whole-process boundary. This lets
RocksDB issue concurrent random reads without replacing Docker's syscall
allowlist with an unconfined container. Before touching an existing execution
client, the broker starts the exact candidate image under the same memory limit
in a read-only, networkless, capability-free one-shot and requires its bundled
probe to create RocksDB's exact 256-entry ring. Linux 5.15 must report the
compatibility retry; any kernel, memory-lock, or seccomp failure leaves the
previous client running.

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

When a live stall needs the bounded allocation profiler but the exact runtime
image must remain unchanged, the broker permits one same-revision diagnostic
replacement only when all ordinary `upgrade` ownership and rollback checks
still pass, the replacement container has a new name, and both the diagnostic
allowance and a non-zero one-to-300-second profile duration are explicit:

```sh
HOODI_GATE_ALLOW_MUTATION=1 \
HOODI_GATE_ALLOW_SAME_REVISION_PROFILE=1 \
HOODI_GATE_ALLOC_PROFILE_SECONDS=120 \
HOODI_GATE_CONTAINER=hoodi-el-sec5-revision-profile \
HOODI_GATE_PREVIOUS_CONTAINER=hoodi-el-sec5-revision \
HOODI_GATE_PREVIOUS_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_GATE_DATADIR=/data/hoodi-sec5-example/datadir-revision \
scripts/hoodi-live-gate.sh upgrade
```

Without that explicit allowance, `upgrade` continues to require a different
runtime revision. `status` reports and sizes the authoritative `/data` bind
mount from the inspected container, so a retained datadir whose name predates
the current revision is not mistaken for the revision-derived default. It also
reports one bounded Docker CPU, memory, block-I/O, and process-count snapshot.

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
the failed gate container and restores the rehearsal EL. `restart` verifies the
same container's revision, datadir, and memory ownership, records its
running/exit/OOM state, then stops it when necessary and starts it again. A
crash-stopped container reports its unavailable before-RPC values instead of
preventing recovery. The broker prints the remaining before/after RPC and
datadir evidence needed to assess durable progress; a restart is not by itself
proof that progress advanced.

The same-host fresh benchmark broker may also use a previously started,
explicitly broker-owned benchmark as its rollback source. This permits a new
revision and genuinely empty datadir to take over the fixed Lighthouse alias
and bounded P2P port without attaching two ELs to that alias concurrently. It
continues to reject every other source identity and restores the source if the
candidate fails its RPC-readiness check.
Restoring a multi-gigabyte live SNAP database can take several minutes. The
broker re-resolves Docker's loopback-only ephemeral RPC port after the restart,
waits up to 600 wall-clock seconds for public RPC by default, fails early if
the container exits, and accepts a bounded 30--1800 second override through
`HOODI_GATE_RESTART_READY_TIMEOUT`.

`logs` never prints a raw peer event. In addition to event counts and the
schema-bounded allocation-profiler rows, it extracts only decimal fields from
the latest identity-free `peer.snap.storage_profile` event and latest numeric
SNAP source-refresh event. Stale-pivot evidence is reduced to counts for the
four production reason labels (`progress-stalled`, `source-throughput-low`,
`response-throughput-low`, and `sources-unavailable`) plus an `unknown` count;
it never exposes the accompanying target hashes or peer identities. The latest
discv4 crawl is reduced to its latest and bounded-window offered/routing-seed
counts plus the chain-filter flag, while connected-session evidence reports
only counts for `eth/72`,
`snap/1`, and their intersection. No enode, IP address, client string, or peer
identifier crosses the broker. The latest identity-free healer event is
projected to its numeric work/frontier/rate fields and fixed ETA status,
confidence, and completion enums; hashes and source identities remain absent.
It also
sums page, slot, and phase-millisecond
fields across the bounded recent log window and reports each maximum. `totalPages`,
`totalSlots`, and `totalLogicalBytes` are cumulative for the current pivot
import; `logicalBytes`, `trieRecords`, and `batchOperations` describe its most
recent buffered commit; `requestMs`, `proofMs`, `materializeMs`, and `commitMs`
separate network, verification, local trie expansion, and database time.
`batchBuildMs` sums page-batch construction performed concurrently by source
workers. `prepareMs` covers the single writer's validation, zero-copy merge,
and statistics pass before RocksDB, while
`writerIdleMs` records how long that writer waited for verified input since its
previous commit. Use a
pair of these samples with Docker's block-I/O delta to calculate backend write
amplification instead of comparing physical writes directly with wire bytes.

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

To measure a new ethereum-lisp revision from an empty datadir without
discarding the current live gate's recovery point, use the matching same-host
broker. It verifies the exact amd64 runtime revision and io_uring seccomp
profile, stops only the exact owned live-gate source, and starts the candidate
with the same Lighthouse alias, JWT, networks, public P2P port, and 50-peer
limit. A failed cutover restarts the source. `restore` verifies both ownership
chains before reversing the cutover, and neither action removes a container,
image, or datadir. Because `restore` never starts the historical candidate
image, it also accepts an exact older benchmark revision after runtime code has
advanced; candidate-starting actions retain the runtime-drift refusal by
default:

```sh
HOODI_LISP_BENCH_RUNTIME_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_LISP_BENCH_SOURCE_CONTAINER=hoodi-el-sec5-01234567 \
scripts/hoodi-lisp-benchmark-gate.sh status

HOODI_LISP_BENCH_ALLOW_MUTATION=1 \
HOODI_LISP_BENCH_RUNTIME_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_LISP_BENCH_SOURCE_CONTAINER=hoodi-el-sec5-01234567 \
scripts/hoodi-lisp-benchmark-gate.sh start

HOODI_LISP_BENCH_ALLOW_MUTATION=1 \
HOODI_LISP_BENCH_RUNTIME_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_LISP_BENCH_SOURCE_CONTAINER=hoodi-el-sec5-01234567 \
scripts/hoodi-lisp-benchmark-gate.sh restart

HOODI_LISP_BENCH_ALLOW_MUTATION=1 \
HOODI_LISP_BENCH_RUNTIME_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_LISP_BENCH_SOURCE_CONTAINER=hoodi-el-sec5-01234567 \
scripts/hoodi-lisp-benchmark-gate.sh restore
```

For a reverse-order A/B on one already-populated benchmark datadir, `resume`
may deliberately start an exact ancestor image from the current checkout when
`HOODI_LISP_BENCH_ALLOW_HISTORICAL_RUNTIME=1` is explicit. The broker still
requires that ancestor relationship, an exact image revision, an exact stopped
owned predecessor on the same datadir, and a clean checkout. Set
`HOODI_LISP_BENCH_SOURCE_REVISION` to the separately verified revision of the
current live-gate rollback target; it defaults to the candidate revision for
ordinary forward comparisons. This exception applies only to `resume` and
does not weaken `start` or `restart`:

```sh
HOODI_LISP_BENCH_ALLOW_MUTATION=1 \
HOODI_LISP_BENCH_ALLOW_HISTORICAL_RUNTIME=1 \
HOODI_LISP_BENCH_RUNTIME_REVISION=0123456789abcdef0123456789abcdef01234567 \
HOODI_LISP_BENCH_SOURCE_REVISION=89abcdef0123456789abcdef0123456789abcdef \
HOODI_LISP_BENCH_PREVIOUS_REVISION=89abcdef0123456789abcdef0123456789abcdef \
scripts/hoodi-lisp-benchmark-gate.sh resume
```

`restart` verifies the exact benchmark ownership, runtime image id, revision,
and `/data` mount before stopping anything. It keeps the source EL stopped,
restarts the same candidate container, waits for its loopback-only RPC, and
prints before/after block, syncing, start-time, and datadir-byte evidence.

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
