# Operator runbook

How to run, stop and read an ethereum-lisp execution node paired with a
consensus client. Every number here comes from a recorded run or test; the
source is named next to it. When the code changes, check these against the
source before trusting them.

The evidence behind this page:
`docs/evidence/sec5-d203fee6-hoodi-complete.txt` (the first complete Hoodi
fresh-datadir run), the 8e95b990 run (`docs/evidence/gates.md`, row 8e95b990), `sec5-aac5f762-hoodi-run.txt`,
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

Not yet exported: pruning progress, RocksDB block-cache hit rates, txpool blob
bytes (the pool keeps only a count), and the P2P forward importer's own block
latency; use the log for those. The series added for Section 10 are listed
under Observability below.

## Observability

Everything here is served by the metrics endpoint (`--metrics
--metrics.addr 127.0.0.1 --metrics.port N`), never by the Engine port and not
by the public RPC port. The endpoint is off unless both `--metrics` and a port
are given, so health probes need the same two flags. Nothing it answers takes
the node store guard: a scrape or probe answers in milliseconds while an
import or a SNAP phase holds the store (the integration test holds the guard
for 4 s and requires all three endpoints to answer in under a second).
Responses carry fixed names and integers only: no hashes, addresses, peer ids
or request payloads.

### Health checks

`GET /health/live` and `GET /health/ready` (HEAD works too) answer `200` when
every check passes and `503` otherwise. The JSON body lists every check with
its value and limit, and names the failed ones:

```
{"status":"fail","failed":["storeGuard"],"checks":[
 {"name":"shutdown","ok":true,"value":0,"limit":0},
 {"name":"peers","ok":true,"value":1,"limit":1},
 {"name":"sync","ok":true,"value":0,"limit":2},
 {"name":"storeGuard","ok":false,"value":1508,"limit":1000},
 {"name":"engine","ok":true,"value":1503,"limit":60000}]}
```

(one line in practice; the values are illustrative, shaped like the
integration test's, which lowers the store-guard limit to 1 s).

| check | endpoint | passes when | what to do when it fails |
|---|---|---|---|
| `shutdown` | live, ready | no shutdown is in progress | nothing: the node is stopping. If it never exits, see Stop |
| `peers` | ready | at least 1 connected peer (`*devnet-health-ready-min-peers*`) | check outbound connectivity and the P2P port (`--nat extip`, firewall); `ethereum_lisp_peer_session_failures_total` and `_peer_refusals_total` say why sessions end. A fresh start takes a minute or two |
| `sync` | ready | `eth_syncing` is false, or the head is within 2 blocks of the highest known target (`*devnet-health-ready-max-lag-blocks*`, the shadow gate's lag limit) | expected during SNAP or catch-up; watch `ethereum_lisp_sync_lag_blocks` fall and the `ethereum_lisp_snap_heal_*` gauges move. If lag grows after the node was at head, look for long Engine requests (`ethereum_lisp_rpc_handler_ms`) and long guard holds |
| `storeGuard` | ready | no single store-guard hold is older than 8,000 ms (`*devnet-health-ready-max-guard-hold-ms*`, the Engine API timeout for newPayload and forkchoiceUpdated) | a long import or SNAP step is blocking the Engine API. `ethereum_lisp_store_guard_long_holds_total{holder=...}` names the holder class, and the log's `node.store_guard.long_hold` line has the exact holder. Short spikes during SNAP are normal; at head it is not |
| `engine` | ready | an Engine request arrived within the last 60,000 ms (`*devnet-health-ready-max-engine-idle-ms*`, five slots) | the consensus client is not calling: check it is running, that it reaches the Engine port, and that both use the same JWT secret. Fails with `"value":null` until the first Engine request after a start |

Liveness deliberately ignores peers, sync and the guard: a node in a long SNAP
phase is busy, not dead, and restarting it throws its work away. Point a
restart policy only at `/health/live`; use `/health/ready` for load balancing
and alerting. "Last Engine request" is the last request on the Engine port
that asked for the store (every Engine method except `eth_syncing` and
`engine_getBlobsV3`); an unauthenticated request never counts.

### Metrics added for Section 10

All histograms use the buckets 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000,
8000 (the Engine API timeout), 10000 and 30000 (the HTTP request deadline) ms,
plus `+Inf`, and export `_bucket`, `_sum` and `_count`.

| metric | meaning |
|---|---|
| `ethereum_lisp_engine_requests_total{method}` | answered Engine requests by method; only names the Engine API defines (a made-up name, a batch, a non-200 answer or a -32601 refusal is not counted) |
| `ethereum_lisp_rpc_handler_ms{family}` | handler time histogram per family (`engine_new_payload`, `engine_forkchoice_updated`, `engine_get_payload`, `engine_other`, `rpc`, `rpc_batch`), guard wait included |
| `ethereum_lisp_engine_guard_wait_ms` | store-guard wait per answered Engine request, 0 when it did not wait |
| `ethereum_lisp_import_execute_ms`, `_import_persist_ms` | newPayload block execution and durable persistence time |
| `ethereum_lisp_rpc_request_timeouts_total` | HTTP requests (Engine or public port) that hit the 30 s request deadline |
| `ethereum_lisp_store_guard_hold_age_ms` | how long the current store-guard hold has lasted (0 when free) |
| `ethereum_lisp_store_guard_engine_waiting` | 1 while an Engine request waits for the guard |
| `ethereum_lisp_engine_last_request_age_ms` | age of the last Engine request; absent before the first |
| `ethereum_lisp_store_guard_long_holds_total{holder}`, `_store_guard_long_hold_ms` | holds of at least 1 s, by holder class (`sync-gap-fill`, `forward-batch-import`, fixed thread names, Engine methods by name, `rpc` for public methods, `other`), and their length |
| `ethereum_lisp_peer_session_failures_total{reason}` | peer sessions that ended in a condition, by condition class |
| `ethereum_lisp_peer_refusals_total{reason}` | handshaken peers refused, by verdict (`too-many-peers`, `already-connected`, ...) |
| `ethereum_lisp_snap_heal_pivot_number`, `_processed_nodes`, `_fetched_nodes`, `_frontier_works`, `_known_incomplete_nodes`, `_completed` | the latest `peer.snap.heal_progress` report |
| `ethereum_lisp_reorgs_total`, `ethereum_lisp_reorg_depth_blocks` | Engine forkchoice reorgs and a histogram of displaced canonical blocks (buckets 1, 2, 3, 4, 8, 16, 32, 64, 128) |
| `ethereum_lisp_rocksdb_compaction_pending`, `_rocksdb_pending_compaction_bytes`, `_rocksdb_running_compactions`, `_rocksdb_background_errors_total` | RocksDB's own counters (RocksDB datadirs only) |
| `ethereum_lisp_process_threads`, `ethereum_lisp_heap_limit_bytes` | Lisp thread count and the SBCL dynamic-space size the heap gauges sit under |

Labelled series are bounded: every label comes from a fixed vocabulary, and a
labelled counter folds new values into `other` after 64 distinct ones.

Alert on: `/health/ready` failing for more than a few minutes after the node
reached head; `rpc_request_timeouts_total` rising; the
`engine_forkchoice_updated` or `engine_new_payload` handler histogram putting
requests in the 8000 ms bucket or above (the consensus client has given up on
them); `rocksdb_background_errors_total` above 0 (a flush or compaction
failed; a hard error stops all further writes, so check the RocksDB `LOG` and
the disk, keep the log and the datadir, then restart);
`rocksdb_pending_compaction_bytes` growing without bound (disk too slow for the
write rate); `heap_used_bytes` staying near `heap_limit_bytes` (each
collection then escalates; see
`docs/evidence/sec5-newpayload-six-second-quantum.txt`); any reorg deeper than
a couple of blocks.

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
cl-workbench validation run cold-integration --match DEVNET-HEALTH-AND-METRICS
cl-workbench validation run cold-unit --match DEVNET-HEALTH --match DEVNET-OBSERVABILITY
```

Probe a running node (read-only, from wherever the metrics address is
reachable):

```
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$METRICS_PORT/health/live
curl -s http://127.0.0.1:$METRICS_PORT/health/ready
```

Against the live gate (read-only unless noted; see scripts/hoodi-live-gate.sh):

```
scripts/hoodi-live-gate.sh status     # container state, eth_syncing, eth_blockNumber, peers, disk
scripts/hoodi-live-gate.sh logs       # recent log window with the snap/engine/guard signals
scripts/hoodi-fleet-status.sh         # live, Hive and shadow gates, host memory and /data, in one call
scripts/hoodi-live-gate.sh complete   # the Section 5 completion check; exit 0 = complete
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-live-gate.sh restart
```

`complete` checks: `peer.snap.target_completed` present, the healer's last
report completed=T with frontier 0, `eth_syncing` false, and
`eth_blockNumber` at or past the CL-authorised target (d203fee6: target
3680599, head 3680709). When `eth_syncing` is not false it still fails, and
prints one `completion-why=` line: current and highest block and their gap,
the Docker timestamp, age and status of the last newPayload, and the store
guard's last observable release. A hold is logged only when it ends, so an
open hold shows up as `guard=no-release-logged-since:<ts>` once the last
release (long_hold, newPayload or forkchoiceUpdated line) is at least the
30 s Engine deadline old, next to the last long_hold's holder and length.
For example, from b5161312 on 2026-09-24T02:24Z:

```
completion-why=syncing current=3684026 highest=3684118 gap=92 last-new-payload=2026-09-24T01:50:27.243535660Z age=2066s np-status=SYNCING guard=no-release-logged-since:2026-09-24T01:50:27.391393628Z guard-release-age=2066s last-long-hold=ethereum-lisp-devnet-dial-session:110731ms@2026-09-24T01:50:17.789708979Z
```

`logs` reduces the Engine and store-guard telemetry of the last 10,000 log
lines (the fields are described in
`docs/evidence/sec5-newpayload-six-second-quantum.txt`) to key=value lines:

| line | what it says |
|---|---|
| `el-engine-requests method=M count=N`, `el-engine-requests-total` | requests per `rpcMethods` |
| `el-engine-latency series=handlerMs\|npExecuteMs method=M samples= min= p50= p90= max=` | nearest-rank distribution per method |
| `el-engine-np-cpu-gc samples= npExecuteCpuMs-sum= npExecuteGcMs-sum=` | newPayload execution: own CPU against collector time |
| `el-engine-guard-wait samples= maxMs=` | the longest `guardWaitMs` |
| `el-engine-last-new-payload timestamp= method= status=` | Docker's receive time of the last newPayload (`none-in-window` if older) |
| `el-guard-long-hold holder=H count= maxMs=`, `-total`, `-last` | `node.store_guard.long_hold` by holder |
| `el-connection-error port=P class=C count=`, `-total` | `engine.rpc.http.connection.error` by listener port and class `request-deadline-Ns`, `idle-deadline-Ns` or `other`; the event carries no method, because a request that hits its deadline writes no request line |

Only numbers, method names, holder labels and the error class leave the host.

`scripts/hoodi-fleet-status.sh` (read-only, no variables needed) prints host
memory and `/data` usage, then live-gate `status` and `logs` for every
running live-gate container, Hive `status` for the newest run of each suite
and shadow-gate `status`, each discovered from container labels. It strips
every mutation allowance from the brokers it calls, retries a dropped ssh
session up to three times, and exits non-zero if any section failed.

A `stop` action for the live gate (SIGTERM with a parameterised grace,
default 120 s, then the exit code, OOMKilled, the RocksDB `Shutdown
complete` line and runtime faults) is written but not yet in the broker; see
`docs/evidence/sec5-gate-tooling.txt`. Until it lands, stop with `docker stop
--time 120` and read the store's `chaindata/LOG` tail for `Shutdown
complete`.

## Release verification

A runtime release is five files that travel together, plus the signer's
public key, which travels separately (from the signer, never from next to the
archive):

| file | what it is |
|---|---|
| `ethereum-lisp-runtime-REV-amd64.tar` | `docker image save` of the non-root runtime image |
| `….tar.sbom.cdx.json` | CycloneDX 1.5 SBOM: the image (revision, image ID), its 95 Debian packages, the 14 files dpkg does not own (client executable, RocksDB, libethckzg, libethbls, io_uring probe, KZG setup, genesis allocations) with SHA-256, and every pinned build input from `tools/build-inputs/inputs.lock` |
| `….tar.provenance.json` | in-toto v1 statement, SLSA v1 provenance predicate: subject = the archive's SHA-256; source commit; inputs.lock SHA-256; base image digest; builder; the SBOM's SHA-256 |
| `….tar.SHA256SUMS` | SHA-256 of the three files above |
| `….tar.SHA256SUMS.sig` | cosign signature over `SHA256SUMS` |

Verify before loading an archive anywhere (Docker on the control plane; the
digest-pinned cosign and CycloneDX validator images are pulled once, then run
with no network; no JSON tool is needed):

```
scripts/release-verify.sh /private/tmp/ethereum-lisp-runtime-REV-amd64.tar cosign.pub
```

It exits 0 and ends with `release-verify: PASS …` only when all of these hold:
the signature verifies with that key; `SHA256SUMS` names exactly the archive,
SBOM and provenance and every digest matches; every blob in the archive hashes
to its name, the SBOM's image ID is the archive's index entry and reaches the
image config, and the config's revision label is the recorded revision; the
provenance subject, commit, inputs.lock digest, invocation and SBOM byproduct
agree; the SBOM is valid CycloneDX 1.5; and, when your checkout holds that
commit, `tools/build-inputs/inputs.lock` there hashes to the recorded digest.
Any other outcome is exit 1 with one `release-verify: FAIL:` line naming what
differed. `scripts/release-verify.sh --self-test` shows it refusing six kinds
of tampering (another key, a changed archive, a changed SBOM with rewritten
checksums, and three re-signed but inconsistent releases).

Producing a release (see docs/validation.md, "Supply-chain pins and release
artifacts"): `scripts/dev.sh runtime-build` then `runtime-export` write the
first four files; `COSIGN_KEY=/path/outside/the/checkout/cosign.key
COSIGN_PASSWORD=… scripts/dev.sh runtime-sign ARTIFACT` writes the signature.
The key never enters the repository: a key path inside the checkout is refused,
the password reaches the cosign container only through the environment, and
nothing is uploaded to a transparency log. `scripts/release-artifacts.sh
generate-key DIR` makes an encrypted key pair for a local signer.

What a PASS does not mean:

- The builder is self-attested: the provenance records who built it and from
  what, from a developer machine (SLSA Build L1), not a hosted, isolated
  builder.
- Bit-for-bit reproducibility of the SBCL executable has not been measured;
  the SBOM is reproducible (the same image gives the same SBOM bytes).
- The runtime stage's Debian shared libraries are installed from bookworm by
  name, not by version: they are listed with versions in the SBOM, but not
  pinned in `inputs.lock` (SBCL, RocksDB, c-kzg-4844, blst and the Quicklisp
  systems are).

Evidence: `docs/evidence/sec10-packaging.txt`.
