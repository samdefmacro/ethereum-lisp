# Storage substrate decision

Status: RocksDB adapter implemented and passing the shared backend contract; NOT
yet the wired production default. The CLI still opens the CRC-framed log (file)
backend, so no node runs on RocksDB today. Making it the default is gated on the
crash-injection and restart proofs in "Migration and rollout" below.

## Decision

Public-network operation is a project goal, so the RAM-resident log database is
not the intended production substrate. The chosen production adapter uses
RocksDB through its stable C API and CFFI; that adapter exists and passes the
backend-neutral contract, but the CLI has not been switched onto it and still
runs on the file/log backend. The existing memory and CRC-framed log backends
remain as deterministic reference implementations and durability-test oracles,
and the log backend is additionally the current production path.

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

The database package will expose the existing `kv-get`, `kv-put`,
`kv-delete`, iteration, and `kv-apply-batch` behavior through a backend-neutral
protocol. A RocksDB batch is committed with WAL sync before success is returned.
Values returned across the C boundary are copied into Lisp-owned byte vectors
and freed exactly once. Database, iterator, snapshot, options, and batch handles
have explicit close operations and unwind-protected ownership.

One process owns one writable database directory. Concurrent read handles are
allowed only after tests establish their lifecycle; the initial adapter uses one
shared handle. Column families are deferred until measured schema pressure
justifies them.

## On-disk schema versioning

The record layout inside a datadir is named by a single `:SCHEMA-VERSION`
marker, written in the same batch as the records it describes. A client refuses
a version it does not understand rather than reinterpreting it, and brings an
older one forward when it adopts the datadir: `node-store-import-from-kv` runs
`node-store-migrate-chain-schema` before reading, so every later write path may
assume the current layout. The migration is one atomic batch — a crash leaves
either the whole old layout under the old marker or the whole new one under the
new marker. It is therefore not resumable, and its batch is proportional to the
retained state.

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

## Migration and rollout

1. The backend-neutral protocol remains unchanged.
2. The Docker image verifies the vendored release archive, builds the shared
   library, and the CFFI adapter runs the database contract with networking
   disabled.
3. Existing `ELKVLOG2` databases remain readable rollback artifacts; operators
   can export through the backend-neutral iterator into a RocksDB directory.
4. Make RocksDB the public-network default after crash injection proves a
   batch reopens as all-or-none and a restart test proves no full-file replay.

The migration is forward-only at the directory level, so it writes a sibling
database and atomically switches a small manifest. The source log is never
modified and remains the rollback artifact.

## Required verification before integration

- Every backend passes the shared key/value and atomic-batch contract.
- Process-kill injection at batch and manifest boundaries reopens to either the
  old complete state or the new complete state.
- Ordered prefix iteration and range deletion are covered before height-ordered
  chain keys depend on them.
- A dataset larger than the configured block cache opens without resident memory
  scaling with total database size.
- The Docker image builds the pinned source once and all test execution succeeds
  with `--network none`.
