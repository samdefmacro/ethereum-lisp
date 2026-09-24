# Operator runbook

How to run, stop and read an ethereum-lisp execution node paired with a
consensus client. Every number here comes from a recorded run or test; the
source is named next to it. When the code changes, check these against the
source before trusting them.

The evidence behind this page:
`docs/evidence/sec5-d203fee6-hoodi-complete.txt` (the first complete Hoodi
fresh-datadir run), `sec5-8e95b990-hoodi-run.txt`, `sec5-aac5f762-hoodi-run.txt`,
`sec5-sigterm-during-heal.txt` and `sec5-ops-recovery.txt` (stop and kill
behaviour, metrics).

## Start

The node is one container. The Section 5 gate starts it like this (see
`scripts/hoodi-live-gate.sh`, action `start`):

```
docker run ... --read-only --cap-drop ALL --security-opt no-new-privileges \
  --memory 12g --memory-swap 12g \
  --mount type=bind,source=$DATADIR,target=/data \
  --mount type=bind,source=$JWT_DIR,target=/jwt,readonly \
  $IMAGE --hoodi --datadir /data --port 30303 --nat extip:$PUBLIC_IP \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.api eth,net,web3,txpool,admin --http.vhosts '*' \
  --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
  --authrpc.jwtsecret /jwt/jwt.hex --authrpc.vhosts '*' --maxpeers 50
```

Add `--metrics --metrics.addr 127.0.0.1 --metrics.port 6060` for the metrics
endpoint (below). It is off unless both `--metrics` and a port are given.

- Memory: 12 GiB was enough for a whole fresh Hoodi sync at d203fee6 (peak
  10.32 GiB). 7 GiB was not: the cgroup OOM killer ended a long import. At
  b5161312, 12 GiB was not enough either (OOM-killed at the head); see Memory
  below for why, and what `--memory.budget` changes.
- Discovery uses the preset bootnodes; no static enode is needed.
- The consensus client must reach the Engine port with the same JWT secret.
  While the EL is down the CL falls behind; after a start expect a burst of
  `peer.snap.pivot_unavailable` until it catches up (below).

## Memory

Source: `docs/evidence/sec5-resident-memory.txt`.

The resident set has two owners, and only one of them is the Lisp heap:

| owner | bounded by | b5161312 Hoodi, 2026-09-24 02:19Z |
|---|---|---|
| SBCL dynamic space (the Lisp heap) | the executable's 6 GiB dynamic space; SBCL returns pages to the kernel when the collection that frees them runs, so its resident size follows the live heap | 3,767 MiB resident, `heapMb` 3,3xx-3,5xx |
| glibc malloc arenas: RocksDB block cache and memtables, compaction and write-batch buffers, KZG/BLS | the RocksDB sizes below, plus the allocator's retention of freed memory | 7,935 MiB resident in 146 arena heaps, against RocksDB's own accounting of 245 MiB block cache and at most 576 MiB of memtables |
| thread stacks, GC tables, libraries | thread count | about 130 MiB |

The arena figure was the fault: freed C memory stayed resident. Since the
resident-memory change (after b5161312), the node

- pins glibc's mmap threshold at its 128 KiB default at start-up, so blocks of
  128 KiB and more (RocksDB's 1 MiB memtable blocks, batch and compaction
  buffers) are mmapped and go back to the kernel when freed, instead of
  staying in an arena once the threshold has climbed;
- returns free arena pages to the kernel once a minute (`malloc_trim`), and at
  once when a SNAP target completes;
- sizes RocksDB from one number, `--memory.budget MIB` (default 7168, the gate's
  7 GiB ceiling): block cache budget/28 and a write-buffer budget of 3/56 of
  it, so memtables stay under 3/2 of that. At 7 GiB: 256 MiB cache, 576 MiB of
  memtables at most, 832 MiB in all. WAL and fsync behaviour do not depend on
  the budget.

The budget does not bound the Lisp heap: the dynamic space is fixed in the
executable at 6 GiB. So a 7 GiB container holds the node only while the live
heap stays under about 5.5 GiB (7 GiB less RocksDB's 832 MiB, stacks and
allocator slack). The live heap peaked at 2,601 MiB before 01:50 on the
b5161312 run (2,769 MiB in `peer.snap.page_profile`); from 01:50 it grew to
3,949 MiB while one peer session held the store guard (see the evidence
record). Keep 12 GiB until a 7 GiB run has passed.

What the node logs:

- `node.memory.budget` once, when the node starts serving: `budgetMb`,
  `rocksdbBlockCacheMb`, `rocksdbWriteBufferBudgetMb`,
  `rocksdbMemtableLimitMb`, `lispDynamicSpaceMb`, `headroomMb` (budget less
  RocksDB's share and the whole dynamic space; negative means the budget does
  not bound the Lisp heap), and `mallocMmapThresholdBytes` (131072 when
  pinned; NIL off glibc).
- `node.memory.sample` every five minutes: `rssMb`, `rssAnonMb`, `rssPeakMb`,
  `heapMb`, `lispResidentMb` (dynamic space resident), `nativeResidentMb`
  (`rssAnonMb` less `lispResidentMb`), `mallocInUseMb` (handed out and not
  freed), `mallocFreeMb` (free chunks malloc holds; still counted after a
  release, whose pages are gone), `mallocMmapMb`, `mallocHeaps`, and the
  release that preceded it (`releasedMb`, `releaseMs`).
- `node.memory.release` with `reason` `snap-target-completed`, or `periodic`
  for a minute's release that returned 64 MiB or more.

Reading them: `nativeResidentMb` far above `mallocInUseMb` means freed memory
is still resident (the b5161312 fault); `mallocInUseMb` itself growing means
something native holds more (a leak or a larger cache); `lispResidentMb`
following `heapMb` up means the Lisp heap is what grew.

## Stop

Stop with SIGTERM and a grace period of at least 30 s:
`docker stop --time 30 $CONTAINER`. The gate uses exactly this.

What the node does with SIGTERM, in order, and the budgets involved:

1. The signal handler only requests shutdown; it closes the listening sockets
   and every registered peer socket.
2. In-flight HTTP requests get 5 s to finish
   (`*engine-rpc-http-shutdown-drain-seconds*`); a connection still busy after
   that is abandoned and its socket closed. The request itself keeps running
   until it returns or reaches its own 30 s deadline
   (`*engine-rpc-http-request-timeout-seconds*`).
3. Every worker (sync coordinator, dialer, discovery, peers, metrics,
   WebSocket) is joined against ONE shared 12 s budget
   (`*devnet-shutdown-join-budget-seconds*`); a worker past it is terminated and
   abandoned. SNAP loops notice the stop at their batch boundaries.
4. The shutdown export (txpool snapshot) takes the node store guard, then
   RocksDB is closed. A clean stop leaves exactly one `Shutdown complete` line
   in the datadir's RocksDB `LOG`.
5. Exit status 0.

Measured stop-to-exit (sec5-ops-recovery.txt):

| in flight at SIGTERM | stop-to-exit | exit |
|---|---|---|
| a keep-alive client, busy or idle | < 20 s (asserted) | 0 |
| a local heal walk | < 5 s | 0 |
| a payload build holding the guard 8 s | 8.0 s | 0 |
| a reorg's canonical rewrite holding the guard 8 s | 8.0 s, store on the new branch | 0 |
| a payload build holding the guard 30 s | 30.0 s (cut by the request deadline) | 0 inside the node, 137 under `--time 30` |

So the stop takes about as long as the longest Engine request in flight, up to
that request's 30 s deadline. Under `docker stop --time 30` a request that runs
to its deadline makes the stop miss the grace period. Normal Engine requests on
Hoodi took 1.8-29 s before the Engine-priority guard (8e95b990) and are well
under a second after it; if you see `engine.rpc.http.request` handlerMs near
30,000 in the log, give the stop more time (`--time 60`) rather than letting it
be killed.

A SIGKILL (or a stop that ran out of grace) does not corrupt the store: every
durable step is one atomic RocksDB batch and the node resumes from its cursors
(sec5-ops-recovery.txt covers kills during the SNAP range phase, the healer,
a forward batch import, a payload build and a reorg). It does cost the work
since the last durable batch, and the next start opens RocksDB without a clean
close.

## Restart

Restart on the same datadir (`scripts/hoodi-live-gate.sh restart`, or
`docker start`). What to expect, from 8e95b990:

- `eth_syncing` answers at once with `currentBlock` = the installed pivot or
  the last canonical head.
- If a SNAP session was in progress, the healer confirms the retained state in
  one step, then the post-pivot tail executes forward (about 3 s per block on
  Hoodi) with `peer.snap.pivot_rebased` / `peer.snap.target_completed` pairs.
- A forward download resumes from its durable peer cursor; a payload build or
  a reorg that was cut is simply redone when the CL repeats forkchoiceUpdated.

## What a healthy sync looks like

From the d203fee6 fresh-datadir run (2026-09-23, Hoodi, 8 vCPU, 15 GiB host,
12 GiB container):

- Range phase: 2 h 29 min; 4,291 account pages (`peer.snap.progress` /
  `peer.snap.page_profile`), 20,583 `peer.snap.storage_profile` events, 3,390
  `peer.snap.storage_closure` attempts; 16 pivot rebases; 0 `import_failed`,
  0 `storage_failed`.
- Healer: `peer.snap.heal_progress` every 30 s. Start at the pivot with one
  fetched node; 30 s later processed 25,874 / fetched 26,050 / skipped 262,065
  with a frontier of 35,179; 35 s after the start processed 36,676, fetched
  36,620, frontier 0, knownIncompleteNodes 0, completed=T. A healthy walk has a
  frontier that goes to zero and knownIncompleteNodes that follows it.
- `peer.snap.target_completed` about 3.5 min after the heal (pivot 3680492,
  target 3680556). Later pivots whose root is already present complete
  instantly; six target_completed in total is normal.
- Head following: the first `engine_newPayloadV4` answered VALID 2.5 min after
  that; then every newPayload is VALID (402 in the next 32 min, 0 INVALID).
  Before completion the CL's calls answer SYNCING or ACCEPTED (1,524 of them),
  which is expected.
- `eth_syncing` turns `false` once the head reaches the CL target;
  `eth_blockNumber` then moves with the chain.

## Failure signatures met so far

| signature | meaning | action |
|---|---|---|
| a burst of `peer.snap.pivot_unavailable` right after a start (12 in the first minutes at d203fee6, 244 over three minutes at 8e95b990) | the CL fell behind while the EL was down and authorised pivots that peers have already pruned | none; it stops once the CL catches up |
| `peer.snap.dependency_failed` "Snap peer does not have the requested storage-range state", dozens per run (80 at d203fee6, 71 at 8e95b990) | the pivot expired on the serving peers mid-range | none; handled by a pivot rebase. Worry only if `import_failed` or `storage_failed` also rise |
| exit 1 whose last line is `couldn't read from #<SB-SYS:FD-STREAM for "socket ...">: Connection reset by peer` | a peer hanging up reached the coordinator's fatal handler | fixed at 6e09dd40 (merge bdc2b3de); on a newer build this is a bug to report |
| exit 1 with `Persisted trie node 0x... is missing` after a forward batch | the batch importer's overlay bug | fixed at aaeb549c (merge 8e95b990) |
| every Engine request over its 30 s deadline during forward sync | the batch importer held the store guard for a whole response | fixed at 9f84d312 (merge c831c9a6) |
| `eth_syncing` stuck on an old snapshot while `eth_blockNumber` moves | the view was only refreshed when the guard was free | fixed at f514145f (merge d203fee6) |
| exit 137 with OOMKilled=false after `docker stop` | the stop outlasted the grace period (SIGKILL); the RocksDB `LOG` has no `Shutdown complete` | look for a long Engine request or join in the last log lines; see Stop. The store recovers on restart |
| exit 137 with OOMKilled=true | the container memory limit (b5161312 at 02:25:29Z: 7.9 GiB of retained arena pages plus a Lisp heap growing at the head) | read the last `node.memory.sample` lines (see Memory) to tell native retention from Lisp heap growth; raise the limit (12 GiB is the tested value) |
| `CORRUPTION WARNING` or `Memory fault` on stderr, even with exit 0 | a memory fault; SBCL can exit 0 after one | treat as a failure and keep the log |

## Metrics

`GET http://$METRICS_ADDR:$METRICS_PORT/metrics` (also served at geth's
`/debug/metrics/prometheus`). Every value is read without the store guard, so
a scrape answers even while an import holds it. What to watch:

| metric | meaning |
|---|---|
| `ethereum_lisp_events_total{event="..."}` | every telemetry event by name, e.g. `peer.snap.heal_progress`, `peer.snap.dependency_failed`, `engine.rpc.http.request` |
| `ethereum_lisp_sync_head_number`, `_sync_target_number`, `_sync_lag_blocks` | the canonical head, the highest CL-supplied or SNAP target, and the difference |
| `ethereum_lisp_snap_pivot_number`, `_snap_state_complete` | the durable SNAP session's pivot and whether its state is complete (0 when there is none) |
| `ethereum_lisp_chain_head_number`, `_safe_number`, `_finalized_number` | forkchoice checkpoints |
| `ethereum_lisp_peer_count`, `_peers_inbound`, `_peers_outbound`, `_peers_eth`, `_peers_snap` | connected peers by direction and capability |
| `ethereum_lisp_engine_new_payload_{last_ms,max_ms,ms_total,requests_total}` and the same for `engine_forkchoice_updated`, `engine_get_payload`, `engine_other`, `rpc`, `rpc_batch` | request handler time (guard wait included) by method family |
| `ethereum_lisp_database_bytes` | the datadir's database on disk |
| `ethereum_lisp_process_resident_bytes`, `_heap_used_bytes`, `_heap_allocated_bytes_total`, `_gc_ms_total` | RSS, Lisp heap in use, total allocation, total GC time |
| `ethereum_lisp_txpool_{pending,queued,basefee,blob}` | txpool levels |

Alert on: `sync_lag_blocks` growing after `eth_syncing` went false;
`engine_new_payload_max_ms` approaching 30,000 (the request deadline, and
the stop budget above); `process_resident_bytes` approaching the container
limit; `database_bytes` approaching the disk (below).

Not yet exported: reorg depth/count, pruning progress, RocksDB internal error
counts and cache/compaction pressure; use the log for those.

## Disk

A Hoodi datadir was 56,154,459,335 bytes (about 57 GB) at the head after a
fresh SNAP sync at d203fee6. Plan for at least twice that per datadir: a
forensic copy of a datadir is the same size again (/data reached 95% with two
copies during the aac5f762 investigation), and the store grows with the chain.

## Acceptance commands

On the development machine (container only; see docs/validation.md):

```
cl-workbench doctor --strict
cl-workbench validation run cold-all
cl-workbench validation run cold-e2e --match OPS-SIG     # kill and stop recovery
cl-workbench validation run cold-integration --match OPS-METRICS
```

Against the live gate (read-only unless noted; see scripts/hoodi-live-gate.sh):

```
scripts/hoodi-live-gate.sh status     # container state, eth_syncing, eth_blockNumber, peers, disk
scripts/hoodi-live-gate.sh logs       # recent log window with the snap/engine signals
scripts/hoodi-live-gate.sh complete   # the Section 5 completion check; exit 0 = complete
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh restart
```

`complete` checks: `peer.snap.target_completed` present, the healer's last
report completed=T with frontier 0, `eth_syncing` false, and
`eth_blockNumber` at or past the CL-authorised target (d203fee6: target
3680599, head 3680709).
