# Storage substrate decision

Status: accepted design; dependency integration is intentionally deferred.

## Decision

Public-network operation is a project goal, so the RAM-resident log database is
not the production substrate. The production adapter will use RocksDB through
its stable C API and CFFI. The existing memory and CRC-framed log backends remain
as deterministic reference implementations and durability-test oracles.

The first implementation target is RocksDB 11.1.2 (`v11.1.2`, released
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

## Migration and rollout

1. Land the backend-neutral protocol without changing the default.
2. Build pinned RocksDB and a minimal C shim in the Docker image, then add the
   CFFI adapter and run the database contract against memory, log, and RocksDB.
3. Add a versioned, resumable copy migration from `ELKVLOG2`; write a completion
   marker only in the same durable batch that publishes migrated metadata.
4. Make RocksDB the public-network default only after crash injection proves a
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
