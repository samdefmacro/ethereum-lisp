# Storage substrate decision

Status: RocksDB adapter implemented and selected by default for public-network
presets; local/dev invocations retain the CRC-framed file oracle unless
`--db.engine rocksdb` is explicit. Current-schema RocksDB datadirs open through
the direct point-read chain/state provider rather than hydrating retained
history. The Docker-only `docker-direct-store-scale` acceptance gate constructs
a logical database larger than its container RAM and enforces explicit restart
RSS/time bounds; its measured result remains part of integration evidence.

## Decision

Public-network operation is a project goal, so the RAM-resident log database is
not the intended production substrate. The chosen production adapter uses
RocksDB through its stable C API and CFFI; that adapter exists, passes the
backend-neutral contract, and is the public-preset default. The existing memory
and CRC-framed log backends remain deterministic reference implementations and
durability-test oracles. Backend selection alone is not the production storage
boundary: the production path is the schema-v4 direct provider, while a legacy
file database is intentionally allowed to hydrate only as an oracle and
migration source.

The implementation pins RocksDB 11.1.2 (`v11.1.2`, released
2026-06-25). Integration must pin the source archive and its SHA-256 in the
Docker build; runtime and test containers remain network-disabled. No system
RocksDB and no unversioned package-manager dependency is permitted.

## Why RocksDB

- Its LSM design keeps the working set bounded while supporting state larger
  than RAM.
- Atomic write batches, ordered iteration, prefix scans, snapshots, checksums,
  and range deletion match the chain/state schema work without a second storage
  abstraction.
- The C API has a narrow ownership boundary suitable for CFFI and avoids a
  Common Lisp subprocess or a C++ ABI dependency.
- It is mature in execution clients: Nethermind uses RocksDB, while geth's
  Pebble/LevelDB choices validate the same LSM shape.

LMDB was rejected because its fixed map sizing and single-writer model turn
capacity planning and long write transactions into operator-visible failure
modes. A new private disk format was rejected because compaction, caching,
ordered iteration, and recovery would become consensus-client maintenance work.

## Adapter contract

The database package exposes the existing `kv-get`, `kv-put`,
`kv-delete`, iteration, and `kv-apply-batch` behavior through a backend-neutral
protocol. A RocksDB batch is committed with WAL sync before success is returned.
The adapter also exposes one narrowly scoped buffered-batch operation for
unpublished, content-addressed SNAP prerequisites. It keeps WAL enabled but
does not independently sync that intermediate batch; the following ordinary
cursor batch is synchronous, and RocksDB flushes the complete preceding WAL
prefix before returning. No cursor or completion marker is published between
those calls. A crash before the cursor can therefore lose only retryable work,
while a returned cursor still proves that all of its prerequisites are durable.
Values returned across the C boundary are copied into Lisp-owned byte vectors
with one native `memcpy` and freed exactly once. Keys and values passed into a
bounded RocksDB call use CFFI's pinned specialized-vector view; RocksDB copies
them before the call returns, so no per-record foreign allocation or
octet-by-octet CFFI loop is needed. Database and iterator handles have explicit,
idempotent close operations; options and native batches have unwind-protected
ownership. Iterators close themselves on exhaustion, and callers that stop at a
chunk boundary close them explicitly so a long migration or backup never pins
one native cursor per batch.

The supported 8-vCPU/16-GiB public-node profile applies RocksDB's leveled bulk
write preset with a 384 MiB level-compaction budget, two-way memtable flush
merging, a matching base level, dynamic level sizing, eight bounded background
jobs, at most four key-range subcompactions for one large compaction, and 1 MiB
incremental background-file syncs. WAL remains enabled and each
logical cursor batch remains synchronous. This trades at most 576 MiB of worst-case
memtable residency for lower compaction write amplification; it does not relax
the durable cursor contract above.

Both reviewed images compile the pinned RocksDB archive with `liburing` and
fail their builds unless the resulting shared object records that dependency;
the production image carries the matching runtime library and checks its
resolution before saving the image. RocksDB's POSIX `MultiRead` submits the
disjoint block reads within one SST concurrently through io_uring on supporting
Linux kernels; this path is independent of `ReadOptions.async_io`. The adapter
also enables that disabled-by-default option and reads it back before opening
the database, activating asynchronous iterator prefetch and keeping the read
handle ready for a future coroutine-enabled cross-level MultiGet build. The
current shared library does not compile RocksDB's Folly coroutine branch, so
the option alone is not claimed to parallelize reads across SST levels. RocksDB
retains its built-in serialized-read fallback when a host or container runtime
refuses ring creation. These settings change scheduling only: ordered results,
content verification, and the synchronous durable batch boundary remain
unchanged. A narrow vendored patch retries without the Linux
6.1 `DEFER_TASKRUN` scheduling hint when an older kernel rejects that hint with
`EINVAL`; other setup failures still take the upstream fallback.
The runtime image also carries a tiny probe which creates the same 256-entry
ring. The reviewed remote broker runs it without network or capabilities under
the pinned seccomp profile before replacing a live node, so an unavailable ring
fails the upgrade while the previous client is still running.

One process owns one writable database directory. Concurrent read handles are
allowed only after tests establish their lifecycle; the initial adapter uses one
shared handle. Column families are deferred until measured schema pressure
justifies them.

## On-disk schema versioning

The record layout inside a datadir is named by a single `:SCHEMA-VERSION`
marker. A client refuses a version it does not understand rather than
reinterpreting it, and brings an older one forward when it adopts the datadir:
`node-store-import-from-kv` runs `node-store-migrate-chain-schema` before
reading, so every later write path may assume the current layout.

Migration is bounded and resumable. It rewrites at most 1,024 source records in
one RocksDB write batch and advances a private progress cursor in that same
batch. The public schema marker remains at the source version until the final
batch atomically publishes the target marker and deletes the cursor. If the
process stops between batches, ordinary reads refuse the explicitly mixed
layout and the next migration call resumes after the last durable key. A v1
database is first given its height-ordered v2 block/header/receipt mirrors and
then receives the v3 content-addressed code rewrite and v4 trie-state history;
it cannot skip an intermediate layout merely because the target is newer.

Version 3 made contract code content-addressed. A body is stored once under
`:CODE` keyed by its Keccak hash, and `:STATE`, `:STAGED-STATE` and
`:STATE-DIFF` account records carry the 32-byte reference instead of the body;
an empty reference means the account has no code. Reading a reference re-hashes
the body it names, and a reference with no record fails the read rather than
producing an account without code. `:CODE` records are never deleted: code is
immutable and shared by every block that references it, so no single block's
retention can decide a body is unreachable.

The two layouts are indistinguishable by inspection, since a pre-v3 body can
itself be 32 bytes long. Which one a record uses is decided by the marker alone.

Version 4 makes the persisted account trie the production state authority.
`:STATE-HISTORY` maps every retained block hash to its account root,
`:ORDERED-STATE-HISTORY` mirrors that mapping by height for bounded retention,
and immutable `:TRIE-NODE` records hold hash-addressed account/storage nodes.
The direct provider starts with a lazy hash node at the persisted account root;
account, storage, code, block, canonical-index, sidecar, and transaction-location
reads are point lookups. Startup reads only schema plus the head/safe/finalized
anchors and their blocks/roots.

## Live commits and retention

Block execution opens the persisted parent root as a lazy account-trie wrapper;
copy-on-write updates preserve its immutable hash-addressed node graph instead
of rebuilding the world view. State and chain mutations journal changed-key
before-images. Block validation and the enclosing durable commit use those
journals plus an immutable root-only snapshot; they do not call the full
`state-db-copy` branch-cloning API. Dirty account/storage paths, touched code
bodies, block and receipt records, canonical/transaction indexes, sidecars,
txpool effects, and checkpoint changes join one WAL-synced RocksDB batch.
In-memory block overlays are released after that batch succeeds.

Forkchoice computes the replacement canonical view in the memory overlay before
publishing that batch. At this atomic seam, affected transaction locations are
resolved only from the post-transition overlay: absence means that the old
durable location must be deleted. Falling through to the direct provider would
observe the intentionally stale pre-transition location and reject it as
non-canonical before the replacement batch could commit. Ordinary reads,
startup, and offline audit still decode and fully validate durable locations.

State retention is a distance behind the current head, with head, safe, and
finalized roots protected independently. The ordered state-root index scans
only heights newly crossing the boundary and includes side candidates, while
same-height reorg participants are considered explicitly. Shared trie nodes and
code remain immutable; the offline rebuild workflow is their compaction path.

## Auditing a datadir

`node-store-verify-chain-database` is a read-only audit that reports every
record-level defect it finds instead of stopping at the first, which is what
the import path does. It checks that every record decodes, that hash-keyed
records are filed under the hash they claim, that redundant header/receipt and
height-ordered mirrors agree, that canonical transaction locations are exact,
and that every cross-record reference has a target. For schema v4 it also walks
each retained account root as a bounded-depth stream, finding missing storage
roots or bytecode referenced only from trie leaf payloads after flat snapshots
have been pruned. Namespace scans use point lookups rather than retaining a set
of every block hash, so audit memory does not scale with retained history. It
does not re-execute blocks, recompute state roots, or prove that a diff chain
resolves.

`node-store-rebuild-chain-database` writes a fresh sibling database, validates
each primary block and receipt pair, regenerates header records,
height-ordered mirrors, and canonical transaction locations, then runs the
bounded audit before removing the sibling's refusal marker.
`node-store-repair-chain-database` is the conservative entry point: it first
audits the source and proceeds only when every finding is confined to those
safely derivable records. Damage to blocks, receipts, state, code, canonical
indexes, or checkpoints is refused rather than guessed. Neither operation
modifies the source datadir.

## Backup and restore

`node-store-backup-chain-database` and
`node-store-restore-chain-database` stream raw key/value records between
backend-neutral database handles. They never hydrate chain or state into Lisp
tables. Each write batch contains at most 1,024 source records plus a private
progress cursor committed atomically with them, so an interrupted copy resumes
strictly after its last durable key. Ordinary schema reads refuse the target
until completion.

Before removing that refusal marker, the operation compares source and target
in key order while retaining only one record from each. A source changed behind
the cursor, a damaged target, or a wrong resume source therefore leaves the
target explicitly incomplete instead of publishing it as a backup. The source
must still be offline: the comparison spans two databases and cannot make a
concurrently mutating source into one atomic snapshot. Restore likewise writes
only an empty sibling target; it never overwrites a live datadir in place.
The integration contract materializes a valid RocksDB source, closes and
reopens it before a RocksDB-to-RocksDB backup, then closes and reopens the
backup before restoring to a third fresh RocksDB directory. Raw streaming
equality and the logical database verifier must both pass after that restart.

## Migration and rollout

1. The backend-neutral protocol remains unchanged.
2. The Docker image verifies the vendored release archive, builds the shared
   library, and the CFFI adapter runs the database contract with networking
   disabled.
3. Existing `ELKVLOG2` databases remain readable rollback artifacts; operators
   can export through the backend-neutral iterator into a RocksDB directory.
4. Public-network presets select RocksDB and current-schema restarts select the
   direct provider. The larger-than-RAM Docker scale gate is the integration
   proof that this path remains bounded.

Schema migration is forward-only and resumable in place. Cross-backend moves,
backup, restore, repair, and rebuild instead write an empty target database and
leave the source untouched as the rollback artifact; switching which datadir a
node uses remains an explicit operator action.

## Required verification before integration

- Every backend passes the shared key/value and atomic-batch contract.
- Process-kill injection at batch and manifest boundaries reopens to either the
  old complete state or the new complete state.
- Ordered prefix iteration and range deletion are covered before height-ordered
  chain keys depend on them.
- A dataset larger than the configured block cache opens without resident memory
  scaling with total database size. `make docker-direct-store-scale` strengthens
  this to a checkpointed canonical state plus a 512 MiB logical dataset in a
  384 MiB container, and refuses the fixture unless its physical RocksDB size
  also exceeds 384 MiB. The fresh process point-reads the persisted account,
  code, and storage before enforcing restart RSS below 256 MiB and
  whole-process restart below 30 seconds.
- The Docker image builds the pinned source once, fails unless `librocksdb`
  links and resolves `liburing.so.2`, and all test execution succeeds with
  `--network none`.
