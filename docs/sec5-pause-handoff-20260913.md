# Section 5 pause and model handoff — 2026-09-13

## Pause boundary

All autonomous `ethereum-lisp` development was paused at
`2026-09-13T15:22:15Z` (`2026-09-13T23:22:15+08:00`) at the user's request.
The user intends to continue with another model because the current Codex quota
is insufficient.

Canonical branch at the pause boundary:

- branch: `sec5-public-bootstrap-sync`
- last already-pushed evidence revision before this handoff:
  `b23b9fac57264b34b71af51803b5cd1ffe1971c6`
- accepted application revision represented by that evidence:
  `13cebe2a06f65fde4bd827a1e280aa1210854c2a`
- repository and all listed worktrees were clean before this handoff was added.

The following clean local development branches were also pushed to matching
`origin` branch names so their exact pointers survive the model handoff:

- `parallel/blob-receipts` — `fe1321129ae0292393f6283c9a8e352a6f3625b9`;
- `parallel/eth-syncing` — `98ebe8b56743c83b42f42236b87620ac440fe545`;
- `parallel/log-limits` — `cc27ecc4909f56d39dc3d6fd8e28fa83c0e3ce9d`;
- `section5/hive-large-tx-regression-cycle974` —
  `8b92d05edb3504c58b0def68dc02c7384051db2f`;
- `section5/hive-new-pooled-cycle975` —
  `bd2c2bad8490e48c6a1e01bc654b8202d9ff776c`;
- `section5/hive-snap-status-cycle986` —
  `dbf02a55bf882de1b15371e0630a23696492fd99`;
- `section5/hive-transaction-cycle975` —
  `765d502e5e826cf7728b79b5739f0a8749c98787`;
- `section5/new-pooled-pump-review-cycle975` —
  `1f04b33a6a395b70990a1acc802629915225a789`;
- `section5/queue-close-lifecycle` —
  `7f56efda7ddabe1c00a8c3c051e2e81539680cea`.

The detached deployment worktree points to `13cebe2a` and has no unique
unreferenced commit; that revision is already retained by the canonical branch.

The Section 5 supervisor process was terminated. Its watchdog and the
`ethereum-lisp` eight-hour progress-report cron job were paused. No local
`ethereum-lisp`, Workbench, Hive, authorization-review, or supervisor process
remained after shutdown.

## Last accepted development slice

Revision `13cebe2a06f65fde4bd827a1e280aa1210854c2a` fixes forkchoice target
publication so that targets superseded during an in-flight publication are
cleared without discarding a genuinely deferred successor. This follows the
accepted live-frontier bound at `fcf458ca45369ad5cf14688bbdc7c15a24d00ac8`
and completed-target handling at `bb9cf83d7c6d482f6aa6bf4afaea63e4f62f0f99`.

Exact-revision validation retained by the stopped supervisor:

- complete cold unit: 1,399 passed, 3 optional skips;
- complete cold integration: 568 passed, 9 optional skips;
- focused publication/local-development/defer regressions: passed after an
  initial malformed-test RED draft was corrected;
- runtime smoke: passed for the exact linux/amd64 runtime;
- runtime archive:
  `/private/tmp/ethereum-lisp-runtime-sec5-13cebe2a-20260913T151042Z.tar`;
- archive size: 72,024,064 bytes;
- archive SHA-256:
  `e696de80af5e65a93dda47493951c309f45f3d75f016ffffff650f0ead32863d`.

The full current-fork EEST prerequisite, pinned Hive rpc-compat and Engine/auth
gates, and required Hive discv4/eth/snap surface were already closed. The Hive
devp2p result is 47/47 for the required discv4/eth/snap surface; unsupported
discv5 remains explicitly refused.

## Remote Hoodi pause state

Immediately before shutdown, the preserved deployment still ran revision
`0c6b51bf6ea4852ddf2baf47147ce0ab24bbf4ae`, not the newer accepted revision.
Its final read-only observation was:

- `net_peerCount`: `0x2e`;
- `eth_syncing.currentBlock`: `0x0`;
- `eth_syncing.highestBlock`: `0x372e19`;
- `eth_blockNumber`: `0x0`;
- healer pivot: 3,616,136;
- processed nodes: 1,726,464;
- frontier works: 670,138;
- known incomplete nodes: 556,185;
- net drain rate: -177;
- status: `dynamic-expansion`, completion not reached.

At `2026-09-13T15:20Z`, `hoodi-lighthouse-public` and then
`hoodi-el-sec5-0c6b51bf-r1` were stopped cleanly. Both exited with status 0,
without OOM or restart. These paths remain intact:

- execution datadir:
  `/data/hoodi-sec5-20260814/datadir-0c6b51bf-r1`;
- Lighthouse datadir: `/data/hoodi-sec5-20260812/lighthouse`;
- JWT directory: `/data/hoodi/jwt`.

Do not interpret the stopped containers as a sync failure. They were stopped by
operator request to create a stable handoff boundary.

## Cancelled pending operation

The supervisor had created deployment request
`20260913T151406Z-sec5-13cebe2a-hoodi-upgrade-r1` to upgrade the preserved
datadir to revision `13cebe2a`. The authorization review was interrupted by the
pause, and no upload, load, upgrade, candidate-container start, or datadir
mutation was executed.

The request has been archived outside the live
`authorization-request.json` path. Its old preconditions assumed running EL and
CL containers and are now stale. A future model must regenerate and
independently review a new request before restarting the old deployment or
performing an upgrade.

## Remaining acceptance gates

Section 5 is not complete. The remaining end-to-end boundary is:

1. resume or upgrade the preserved Hoodi deployment through a newly reviewed
   operational request;
2. prove healer convergence and an empty frontier on the accepted revision;
3. reach canonical execution catch-up and real `eth_syncing=false`;
4. complete the required multi-day shadow comparison;
5. complete the validator soak gate;
6. create `SECTION5_COMPLETE.json` only after every plan criterion is backed by
   primary evidence.

Start continuation by reading `PROJECT.md`, `AGENTS.md`,
`docs/gap-analysis/public-testnet-readiness-plan.md`, this handoff, and the
runtime records under
`/Users/sen/.hermes/runtime/ethereum-lisp-sec5-supervisor/`. Do not resume the
old supervisor or either paused cron job until the user explicitly selects the
replacement model and asks development to continue.
