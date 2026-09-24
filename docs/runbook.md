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
  10.32 GiB). 7 GiB was not: the cgroup OOM killer ended a long import.
- Discovery uses the preset bootnodes; no static enode is needed.
- The consensus client must reach the Engine port with the same JWT secret.
  While the EL is down the CL falls behind; after a start expect a burst of
  `peer.snap.pivot_unavailable` until it catches up (below).

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
| exit 137 with OOMKilled=true | the container memory limit | raise the limit (12 GiB is the tested value) |
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
