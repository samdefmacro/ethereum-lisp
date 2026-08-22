# Architecture

`ethereum-lisp` is a small execution-layer client. Package declarations load
before all implementations, and implementation dependencies move in one
direction, from protocol primitives toward node orchestration:

```text
packages (declarations only)
foundation
  -> protocol
       -> runtime core -----------+
       -> storage core -----------+-> application services
                                          |-> networking (devp2p / eth sync)
                                          |-> persistence adapters
                                          +-> API -> HTTP transport
networking + persistence adapters + HTTP transport --------> app / CLI
```

Lower layers must not depend on higher layers. When a higher layer needs a small
helper from a lower layer, move the helper down instead of reaching back through
a broad package dependency. The production ASDF definition follows these layers:
`runtime-core`/`storage-core` are parallel siblings over `protocol`, and
`networking`, `persistence-adapters`, and `api` are parallel siblings over
`application-services`.

## Where the per-file map lives

This document does not catalog every source file, because three authorities
already describe that and stay current on their own:

- **structure and dependency edges** — `ethereum-lisp.asd` (module layout and
  explicit `:depends-on`);
- **each file's responsibility** — its first comment block (`docs/style.md`
  requires one);
- **symbol ownership and the acyclic package graph** — the architecture tests.

What follows is only what those sources do not state: the boundary philosophy,
the non-obvious layer assignments, and the invariants that the code depends on
but does not explain.

## Package boundaries

`ethereum-lisp` is the canonical public API. The legacy `ethereum-lisp.core`
package is generated directly from that API and owns no symbols or
implementation. Only these two provide compatibility re-exports; domain packages
do not re-export higher-layer symbols.

File size and name prefixes are not module boundaries. A refactor must first
identify an owner, its public contract, and the allowed dependency direction,
and split code only when the resulting units have cohesive behavior and
communicate through an explicit API or state object. Files under `src/packages/`
are declaration manifests loaded before all implementations; their grouping
preserves declaration order and does not assign implementation-layer ownership.

The EVM shows the intended shape of a public boundary: `ethereum-lisp.evm` is a
facade that re-exports only the supported context, result, precompile-address,
and execution API, while `ethereum-lisp.evm.internal` owns the runtime,
precompile, and interpreter implementation symbols. Application layers must not
use the internal package.

## Layer bridge points

These packages sit at a layer that is not obvious from their directory. Placing
them by their physical location instead reintroduces dependency cycles:

- **`execution-service`, `block-import`, `canonical-chain`, `genesis-state`**
  are application services, not storage. `execution-service` projects state-db
  and chain-store and derives execution results; `block-import` is the common
  validated admission and publication boundary; `canonical-chain` coordinates
  chain-store, txpool, reorg, and filter notification; `genesis-state` bridges
  genesis input and mutable state. The domains they compose have no dependency
  on each other. `block-import` exposes separate operations for candidate
  admission, detached private building, canonical publication, and the combined
  local build/import/publication transaction. Keeping those operations in one
  service makes the authority transition explicit without making every valid
  candidate canonical.
- **`engine` (payload status)** decides import/cache status using the chain
  store inside the common block-import boundary, so it is an application
  service, not a protocol model. The pure payload values live in
  `engine-payloads` under `protocol`.
- **`txpool.application`** is transaction preflight and admission policy, not
  txpool storage; `eth_sendRawTransaction` delegates to it.
- **`eth-sync`** (the networking layer) drives the eth wire protocol over a live
  RLPx connection, in both directions: accepting inbound connections as well as
  dialing out, downloading blocks, answering a peer's header, body, and receipt
  requests, and gossiping transactions both ways. It depends on application
  services and the `p2p`/`eth-wire` protocol, and stays independent of the chain
  store at every end — blocks are imported through a caller-supplied callback,
  and requests, pool lookups, and transaction admission all go through a
  caller-supplied `eth-serve-backend` of closures. Blob transactions are
  deliberately not gossiped; see the header of `eth-sync/gossip.lisp`.
  The CLI-owned callback submits the typed block to
  `import-p2p-block-candidate`. An eth BlockBodies response omits
  execution-derived Prague requests and the Amsterdam block access list, so it
  must not be round-tripped through an Engine payload and reconstructed with
  those committed fields missing. Fork-to-newPayload V1--V5 selection and
  `block-to-executable-data` conversion remain an explicit, testable adapter
  seam, but typed P2P admission preserves the complete header/body object while
  execution derives and verifies the omitted commitments. The networking layer
  therefore remains store-independent while peer data reaches the same import
  kernel as Engine data.

  Two properties of this layer are load-bearing and easy to break:

  - **A connection has exactly one owning thread.** Ordinary long-lived session
    threads belong to the CLI layer, in `devnet/peer-manager.lisp` (inbound) and
    `devnet/dialer.lisp` (outbound). The bounded multi-peer downloader is the
    exception: it creates one worker for each supplied peer and never shares a
    peer between workers. `eth-sync/pump.lisp` still supplies the ordinary
    session loop whose readiness gate and clock are injected.
  - **Each peer session is single-threaded by construction.** `rlpx-write-frame`
    advances a per-connection cipher and running MAC with no lock, so a second
    thread writing the same connection desynchronizes it. Outbound work reaches
    a session as data, through a closure the loop calls — never by another
    thread sending on the peer. The multi-peer downloader gains parallelism
    across connections, never within one connection.

  A dialed connection becomes a long-lived session on the SAME pump an accepted
  one gets, so both properties above hold identically in both directions.

  Public synchronization is consensus bounded rather than peer-head driven.
  Engine forkchoice or a buffered Engine payload names the target hash; the
  coordinator may use peer announcements and range updates to wake itself, but
  those messages cannot expand the authorized target. A fixed delivery window
  (twice the active peer count), per-request wall-clock deadlines, peer scoring,
  and failover keep memory and stalled-peer work independent of target height.
  Every live connection still owns its cipher and all writes: downloader workers
  submit requests through the session's bounded request queue, where the owning
  pump prioritizes request/response work without starving chain updates. The
  target hash is checked before the final block enters the import callback.
  Header batches may be followed by a shorter, non-empty body or complete
  receipt prefix, as permitted by real eth peers' soft response limits. The
  accepted prefix is imported once and its exact suffix remains in the bounded
  delivery window for retry; empty and overlong responses still fail closed.
  Successful catch-up emits BlockRangeUpdate and NewBlockHashes through the
  same session-owned outbound path.

  `snap/1` is advertised only when both the verified client and the serving
  backend are installed. The public direct RocksDB provider supplies that
  backend; memory/file stores remain test oracles and do not claim production
  snap service. A CL-authorized pivot binds the state download to target hash,
  chain, genesis, and database authority. The account keyspace is split into
  sixteen durable ranges matching pinned geth; one worker per available snap
  peer fetches and verifies a geth-aligned 512 KiB-soft-limited page, while one
  coordinator serializes verified record and progress publication. A failed
  peer releases only its claimed range for another worker. If every peer in
  that finite source snapshot fails, the importer reports a typed remote-source exhaustion result;
  the CLI keeps the node and Engine API alive, takes a fresh live-peer snapshot
  on its next bounded pass, and resumes from the durable per-range cursors.
  Local persistence and trie-merge failures remain fatal and are not converted
  into retries. Account and storage ranges carry compact boundary proofs, trie
  nodes are served by path set, and every page is verified before its account
  nodes, bytecode, complete small storage tries, and per-range cursor become
  durable. Range reconstruction uses a dedicated proven-absent MPT insertion:
  the verified gap-free page and its monotonic durable successor cursor already
  prove that these keys are new, so proof reconstruction omits `mpt-put`'s
  redundant defensive point traversal. The verifier returns that reconstructed
  page instead of discarding it: its new nodes plus authenticated boundary
  proof nodes are deduplicated and persisted by content hash in the cursor
  transaction. Their keys are derived from the exact encoded nodes only after
  proof verification, so blind puts are idempotent for healthy state and repair
  a corrupt same-key local value without a RocksDB read for every reconstructed
  node. This matches geth's hash-scheme range ingestion and removes the former
  second global MPT rebuild and its per-node RocksDB point reads. Ordinary state
  transitions retain checked `mpt-put`. Complete coarse buckets strictly inside
  each authenticated range contain only newly reconstructed nodes. After that
  page's small storage is durable and its code joins the cursor batch, their
  root hashes are published as the same pivot-independent subtree proofs used by the
  healer. A later pivot therefore traverses only changed and boundary buckets,
  rather than rereading every range-ingested node once before it can build the
  proof index. Buckets containing deferred storage are excluded until those
  dependencies are durable. StorageRanges pages apply the same rule directly
  to their reconstructed storage trie, publishing coarse storage-subtree proofs
  atomically with their node records and successor cursor. Pre-optimization
  range plans are upgraded lazily with depth-bounded walks over only the account
  and completed storage tries' shallow spines. Account buckets containing an
  incomplete large-storage cursor set remain excluded while every other bucket
  is immediately reusable; completed storage roots receive their own reusable
  proofs. New proofs use five-nibble buckets so a later pivot can still reuse
  unchanged descendants inside a changed four-nibble bucket; the healer keeps
  consuming older four-nibble proofs for migration compatibility. The records
  are written in 2,048-record batches and versioned idempotency markers follow
  them, so a crash can only repeat safe work.
  The authenticated prefix of byte-capped
  large storage is persisted immediately and its root is recorded beside that page
  in a state-root-scoped durable work set. Independently reconstructing every
  page against the same authorized root maintains a root-valued range-set witness;
  when the final cursor commits, that witness permits the batch to publish a
  versioned plan marker proving the work set is complete. A state-root rebase
  replaces it with a domain-separated non-root witness, permanently preventing
  a mixed-root range set from publishing the plan. Final healing then starts
  directly from those storage roots instead of rereading the already verified
  account trie. An old or rebased partial import has no marker and safely
  retains the full-root traversal. Before final healing, every planned large
  storage root is split into sixteen inclusive hash ranges matching current
  geth. Each live source continuously fetches one 512 KiB-capped page at a
  time and immediately claims another unfinished partition without a global
  wave barrier; the coordinator atomically commits its content-addressed nodes
  and versioned per-range successor cursor. A restart resumes those exact
  cursors. Source exhaustion merely falls back to TrieNodes healing with all
  verified range pages retained. Completed ranges deliberately remain on the
  deferred frontier so final healing can verify or skip their storage roots
  through the durable subtree proofs
  before it can publish completion. Work sets above the 8,192-item checkpoint
  bound also fall back to that path. Each bounded TrieNodes frontier is split
  into approximately 512-path chunks, always below the pinned geth limit of
  1,024 paths and with at least one initial chunk per source. This avoids the
  roughly 186-path requests observed with eleven live peers under fixed four-
  way over-partitioning. Every source retains at most one outstanding request,
  but a fast source immediately claims another disjoint tail chunk instead of
  waiting at a global slowest-peer wave barrier. Initial chunks are assigned
  deterministically across all sources so one fast peer cannot erase peer
  diversity; only the shared tail is work-stealing. The total frontier
  still scales with the source count up to the durable 8,192-work cap. The
  serving side applies the same 1,024-lookup cap even when the structurally
  bounded wire list is larger. A failed source stops claiming new chunks while
  successful results remain durable and unrequested work stays in the exact
  continuation. The public-node peer default is 50, matching geth
  `38271784c2b31926563806da9a2e023b88f5e7a8` and Nethermind
  `e52dc19a56a46f58170a730822580774d403c838`; the one-request-per-source rule
  remains stricter than either implementation's process-wide worker pool and
  preserves this client's sole-writer session boundary.
  Before each remote healing round the CLI refreshes its live session snapshot,
  reuses the existing sole-writer source wrappers, and incrementally admits new
  snap peers that completed their handshake after the long traversal began.
  Retired source identities are not re-admitted during the same attempt.
  Source order rotates between rounds, so a retained path from a partially
  pruned peer reaches another source without duplicating any request inside one
  round. Account traversal defers up to 2,048 discovered storage roots instead
  of descending into each contract immediately. The deferred roots become part
  of the bounded work frontier before any checkpoint or remote request, so one
  authenticated TrieNodes round can fill many contracts without weakening
  restart safety. A subtree-completion sentinel also drains its deferred storage
  before it can publish proof of completion.

  Local content-addressed references are read in batches of at most 512 keys.
  The width shrinks with the live frontier so worst-case 16-way expansion
  remains below the 8,192-work checkpoint cap throughout its soft-target
  region. A restart may begin at the legal hard cap, where its next branch can
  transiently expand the exact DFS frontier above one checkpoint record. If a
  checkpoint becomes due in that state, the prior durable record remains
  authoritative while one-work reads drain the excess; fetched nodes may still
  be committed by content hash, but no partial frontier is published. The next
  checkpoint is written only after the complete frontier is back within 8,192,
  so the allocation bound remains unchanged without turning a temporary shape
  into a fatal node exit. On SBCL, production RocksDB batches of at least 128
  keys are divided into at most eight contiguous native multi-get slices on the
  supported eight-core public-node profile. This
  path uses a 2 GiB sharded block cache on the supported 16 GiB public-node
  profile instead of RocksDB 11's 32 MiB fallback. Ten-bit full Bloom filters
  keep absent whole-key probes out of newly written SST data blocks, while
  index/filter blocks receive high cache priority and L0 pinning. These table
  settings alter neither verified values nor synchronous cursor batches. The
  reviewed images also require RocksDB's Linux io_uring support at link time.
  Its POSIX MultiRead consequently submits disjoint block reads within one SST
  concurrently on a supporting kernel, independent of `ReadOptions.async_io`.
  Adapter construction still enables and reads back that disabled-by-default
  option for asynchronous iterator prefetch. The current shared build does not
  include RocksDB's Folly coroutine branch and therefore does not claim
  cross-level MultiGet parallelism from that option alone. RocksDB's serialized
  fallback remains available if ring creation fails at runtime. Linux 5.15
  retries ring creation without the newer
  `DEFER_TASKRUN` scheduling hint after `EINVAL`; policy failures do not bypass
  the fallback. The result ordering and caller-visible synchronous boundary do
  not change. The
  parallel dispatch applies both to trie-node records and to the versioned
  metadata proofs used
  to skip completed subtrees; proof candidates are collected under the same
  frontier bound and resolved in input order before absent proofs enter the
  trie-node batch. At healer startup, both versioned proof namespaces are
  scanned sequentially into a fixed 16 MiB process-local negative filter. A
  definite absence skips RocksDB entirely, while a possible hit still executes
  the exact version-validating metadata read; newly durable proof batches enter
  the filter only after their write succeeds. Thus first healing avoids an
  extra random metadata miss per candidate without treating a probabilistic
  result as proof, and a cache miss does not serialize one metadata lookup on
  the coordinator before every trie read. For trie-node records, each worker
  also checks the content hash and performs the bounded RLP decode for its
  present slice. The coordinator joins every reader, restores the original
  value/presence/decoded order, and propagates the earliest worker-slice failure
  before mutating the DFS frontier; small batches and memory/file stores retain
  the same ordered generic fallback. A content-hash- and path-matched remote
  response is decoded once before its node batch becomes visible, then retained
  in a bounded in-memory response cache after that batch and the exact fetched
  frontier become durable. The normal coordinator traversal consumes the
  cached object without either a per-node point Get or a write-then-reread
  MultiGet, preserving checkpoint and completion-sentinel ordering across
  crashes. This adopts geth's `ProcessNode` response locality without weakening
  the stronger per-round restart batch; Nethermind's `TreeSync` likewise routes
  responses directly into its processing/store pipeline rather than rediscovering
  them as pending disk reads. A restart merely loses the cache and reads the
  already-durable content-addressed node normally. Proof values are version-checked after the
  ordered join, so an unknown value remains local storage corruption rather
  than a cache miss. This bounded read/decode concurrency uses otherwise idle
  CPU and I/O capacity without making frontier mutation or checkpoint
  publication concurrent. The
  database API rejects more than 4,096 keys or 4 MiB of key bytes before native
  allocation. The fetched nodes and the exact remaining work frontier
  are committed in one batch. That bounded, checksummed checkpoint is tied to
  the pivot, target, chain, genesis, and database authority, and is ignored if
  corrupt or stale. While it remains valid and non-empty, the coordinator pins
  that exact CL target for one actual Snap attempt after process restart even
  after the ordinary 120-block stale-pivot window; otherwise a routine deploy
  would delete the frontier and repeat the root traversal. Waiting for a Snap
  peer does not consume that process-local opportunity. Once a finite source
  generation has actually been attempted, ordinary stale-target rebase is
  available again. A long-running healer cannot defer that decision merely by
  receiving small partial TrieNodes responses forever: at a boundary with no
  request worker or uncommitted database batch, it checks the current Engine
  forkchoice target at most every 30 seconds. A typed scheduling condition
  yields to the coordinator only when that CL-authorized target is more than
  120 blocks beyond the active target and no healer progress snapshot has
  arrived for five minutes. Productive local reuse and accepted partial
  responses therefore retain their exact DFS frontier instead of repeatedly
  restarting as the live head advances. Peer-advertised heads never enter this
  decision. The next pass atomically rebases the skeleton and state cursor,
  while already durable content-addressed nodes and completed-subtree proofs
  remain reusable.
  Missing, corrupt, or identity-mismatched checkpoints never suppress rebase,
  and an explicit authority-driven rebase still invalidates the frontier in
  the same batch as both progress records.
  Checkpoint version two records armed, descendant, and completion-sentinel
  work while continuing to decode version-one restart records. At a four-nibble
  account or storage prefix, a sentinel publishes a trie-kind-domain-separated
  metadata proof keyed by the subtree's content hash. This yields at most
  65,536 boundary regions per secure trie: fine enough that a newer pivot can
  skip the many regions untouched by its recent blocks, without the millions
  of proof records produced by a six-nibble boundary. An account proof becomes
  visible only after all descendant trie nodes, storage roots, and bytecode are
  durable; a storage proof similarly waits for all of its descendant nodes.
  Kind separation prevents a storage proof from bypassing account-leaf semantic
  validation even if an identical node encoding appears in both trie roles.
  Completed proofs are accumulated in input order and published in bounded
  batches of at most 2,048 rather than forcing a synchronous RocksDB transaction
  for every small subtree; checkpoint, missing fetch, and final boundaries flush
  the remaining batch. These optional proofs survive pivot rebase: an unchanged
  account subtree or large contract-storage region at a later authorized root
  can be skipped rather than reread, while a changed content hash is traversed
  normally. An unknown proof
  version is local storage corruption, and a failed proof batch publishes
  neither the proof nor state completion. This cache relies on the current
  append-only trie-node/code stores; a future pruning implementation must remove
  or otherwise invalidate affected proofs before deleting their dependencies.
  Missing references are temporarily moved from the exact DFS frontier into a
  bounded 2,048-path request vector and counted by both expansion and
  checkpoint decisions. Replacing them in the same order after the response
  does not enlarge the frontier, so even a hard-sized frontier can coalesce one
  full network request instead of paying one public-network round trip per
  node. Local node decoding remains frontier-aware and the larger hard record
  cap remains a fail-closed allocation boundary.
  Referenced code is made durable before the frontier advances. This traversal
  reuses nodes across restart and alone installs the completion marker, deleting
  its checkpoint in the same final batch. A crash can repeat content-addressed
  writes but cannot advance any authoritative cursor past unverified account
  state. The pivot skeleton and its cursor use the same rule. Bootstrap
  downloads only the pivot through the CL target (at most 65 blocks), never the
  whole genesis-to-head body history.
  After the pivot state root is reconstructed, a target-bound sparse canonical
  checkpoint is installed in the same rollback boundary as its durable index;
  the Engine target itself remains noncanonical until ordinary typed candidate
  import executes the at-most-64-block tail and forkchoiceUpdated publishes it.

  The wire boundary is bounded before object construction. Every RLP list
  decoder has a context-specific item limit, negotiated message codes must fall
  inside their capability's assigned range, and snap response counts and byte
  budgets are capped. The eth/72 GetCells/Cells shapes and 128-bit custody mask
  follow pinned geth: custody bits are little-endian within each byte, groups are
  flat per transaction, responses must echo the requested mask, and both cell
  count and encoded response bytes are bounded. Transaction gossip advances a
  per-peer pending cursor only for hashes actually offered, so a burst larger
  than one wire batch is retained rather than silently skipped.

  `eth-sync/backfill.lisp` fills a gap the other direction. Forward download
  works from a number we hold; a consensus client instead names a HASH somewhere
  ahead, and the chain may have reorged, so the block at our head plus one is not
  necessarily an ancestor of it. The walk therefore runs BACKWARDS by parent hash
  to common ground and only then executes forward, because execution needs its
  parent's state and so has exactly one possible order. A walk that cannot reach
  common ground is refused rather than partially imported.

  Discovery is likewise two-directional. `p2p/node-table.lisp` is a Kademlia
  routing table — 256 buckets by log distance, pure, `now` as an argument — and
  the responder built on it answers Ping, FindNode and ENRRequest. Two refusals
  in it are load-bearing: a node is only ever handed to a peer once it has proved
  its own endpoint by answering us, and FindNode or ENRRequest from an unbonded
  sender is refused outright, because both replies are far larger than the
  request and a forged one carries any source address the sender likes.

  Public presets carry the canonical pinned discv4 bootnodes; Hoodi also carries
  go-ethereum's canonical `all.hoodi.ethdisco.net` EIP-1459 URL. The DNS client
  asks only system-configured recursive resolvers, caps packet/TXT/section/query,
  tree-depth, branch, and ENR counts, stops successfully once the bounded
  verified-candidate capacity is full, verifies the root secp256k1 signature and
  monotonic sequence, verifies every abbreviated Keccak Merkle label, then
  reuses EIP-778 signature verification and the eth fork-id filter before a
  candidate reaches the dial registry. The accepted sequence is atomically
  persisted by signing-authority URL before candidates are published, so a
  restart cannot replay an older signed root. DNS runs before the cross-chain
  discv4 crawl and refreshes every five minutes, preserving registry capacity
  for authenticated chain-matching candidates.

  A datadir owns a stable node key and monotonically increasing local ENR
  sequence, both created with the same no-follow/exclusive/0600 file discipline
  as other node secrets. `--nodiscover` disables DNS, outbound crawling, and
  discovery serving; an explicitly empty `--bootnodes` replaces preset seeds,
  and an explicitly empty `--discovery.dns` disables the preset DNS tree.
  Automatic NAT modes remain rejected until implemented; they are never
  accepted as no-op claims.

  Peer admission policy (`devnet/peer-table.lisp`) and dial scheduling
  (`devnet/dial-schedule.lisp`) live in the CLI rather than here, because a peer
  limit and a retry policy are operator settings. Both are pure, taking `now` as
  an argument, so their decisions are testable as tables — and neither locks
  anything, because they share one NON-recursive mutex with each other and a
  caller composes them inside a single acquisition. A lock appearing in either
  file would turn a composed decision into a signalled error rather than a wait.
- **persistence adapters** live physically under
  `src/storage/node-store/persistence/` but depend on application services:
  `staged-import` calls the common candidate-import service before
  materialization. They therefore load after application services, not as part
  of `storage-core`.

## Key invariants

Non-obvious properties the implementation relies on:

- **Atomic candidate import.** Engine newPayload, P2P, staged import, and local
  dev-period production enter `block-import` after their transport or disk shape
  is decoded. Engine uses `import-executable-payload`; P2P keeps the eth-wire
  block typed through `import-p2p-block-candidate`; staged and other typed
  callers use `import-block-candidate`. The service validates the parent,
  header, body, senders, and optional sidecar, executes from the parent state,
  verifies derived commitments and receipts, and publishes the hash-addressed
  block, state, receipts, and side data in one rollback frame. Its durability
  callback runs last; validation, execution, or durable-write failure restores
  the complete in-memory view. A known valid replay is validated again but does
  not re-execute. Database write-batch application is atomic — memory swaps a
  shadow table on success; the file backend appends the whole batch as one
  CRC-framed, fsynced log record before the in-memory table changes; RocksDB
  uses one write batch.
- **Candidate and canonical authority are separate.** A successfully executed
  P2P or staged block remains hash-addressed and noncanonical. Post-Merge
  canonical, safe, and finalized views change only through an Engine
  forkchoiceUpdated publication, except that an explicitly configured `--dev`
  node may use the isolated `:local-dev` authority for its dev-period blocks;
  a positive `--dev.period` is rejected unless that mode was explicitly enabled.
  `debug_setHead` is limited to a view whose current and target blocks are both
  pre-Merge, so it cannot escape the rule by targeting an older block from a
  post-Merge head. Canonical publication updates checkpoints, applies the
  canonical/txpool transition, prunes finalized cache entries, and calls
  durability in that order inside one rollback frame.
- **Private payload construction stays detached.** Engine payload preparation
  builds and validates through `build-private-block-candidate`, whose successful
  path deliberately rolls back every store write made while constructing the
  proposal. The detached result may then enter the bounded prepared-payload
  cache, but becomes a block candidate only when a later newPayload admission
  executes it. The private build step itself cannot alter candidate, canonical,
  state, txpool, or checkpoint views.
- **Peer progress names durable candidate state.** A persistent node records a
  peer's identity, persistence authority, chain ID, genesis hash, last completed
  number, and last hash in a strict versioned RLP record. The executed candidate,
  derived state and receipts, and monotonic cursor are committed in the same KV
  batch. A buffered ACCEPTED/SYNCING block is persisted as a remote candidate
  but cannot advance the cursor. On reconnect, the cursor is used only after its
  candidate, state, and ancestry from the current canonical view are verified;
  otherwise an abandoned-branch cursor is deleted durably before resume falls
  back to the canonical boundary, or a corrupt target fails closed. If the
  cursor still descends from the local canonical view but the peer's next header
  proves that the peer reorged, the downloader deletes the cursor and retries
  once from the local canonical anchor. A second mismatch is a peer failure and
  escapes; the retry cannot loop or repeatedly erase progress.
- **Engine/P2P caches are bounded deterministically.** Each retained entry has
  an insertion time, exact protocol-byte count, and a block number when one is
  known. Finalized and expired entries leave first; count or byte pressure then
  removes the oldest `(inserted-at, key)` entry. Replacing an existing key keeps
  its original insertion time, so repeated announcements cannot extend its
  lifetime indefinitely. The production policies are:

  | Cache | Count | Bytes | Maximum process-local age |
  | --- | ---: | ---: | ---: |
  | Remote block | 96 | 64 MiB | 30 minutes |
  | Forkchoice target | 96 | 3,072 B | 30 minutes |
  | Invalid block | 512 | 64 MiB | 1 hour |
  | Prepared payload | 10 | 128 MiB | 5 minutes |
  | Blob sidecar | 512 | 64 MiB | 3 hours |

  Finality pruning applies when the entry carries a block number; it does not
  guess a height for hash-only forkchoice targets or sidecars without
  provenance. Insertion timestamps are process-local cache metadata, not durable
  wall-clock admission history. A namespace restored into memory is re-admitted
  at startup time, so its age begins again in that process; count, exact-byte,
  and known-finality bounds are enforced before the startup store is exposed.
  Public direct-provider startup restores only invalid verdicts and remote
  candidates. Durable blob sidecars remain immutable content served by bounded,
  lazy content-addressed point reads without eager hydration or retaining
  point-read results in memory; prepared payloads and hash-only forkchoice
  targets are process-private and are not restart state.
- **Durable invalid/remote recovery is bounded.** Direct-provider startup
  streams the invalid-tipset prefix first and the remote-block prefix second,
  admitting one record at a time so legacy durable input cannot create an
  unbounded memory table during restart. Once each retained set is known, a
  second prefix-only pass deletes rejected or evicted records in bounded pages.
  Within each page, a body record and its block-access-list side record are
  deleted in the same atomic batch, and the side record is removed only after
  point reads prove that no known, retained-invalid, retained-remote, or staged
  block owns it. Missing-parent candidates that survive the bounds are
  immediately available to normal gap-fill enumeration, while restored invalid
  hashes reject replay without re-execution.
- **State-root memoization.** Each `state-object` memoizes its storage root. A
  state root is taken over every account, but a block touches a handful, and
  rebuilding the untouched accounts' storage tries was ~93% of the cost
  (1769ms → 149ms per block at 400 accounts × 16 slots). `state-db-set-storage`
  is the only writer of a storage table and thus the only place the memo is
  dropped; deleting an account drops the whole object, and a clone keeps the
  memo because its storage is `equal`. A stale memo would be a wrong state root,
  so differential tests compare the memoized root against a cold recomputation.
- **Storage providers.** The file backend is an append-only file of
  CRC-framed records replayed into an in-memory table on open, with
  fsync-per-write durability, torn-tail recovery, threshold-triggered compaction
  via a temp-file rename, and migration of v1 whole-file s-expression databases.
  Opens are pure reads; torn-tail truncation and v1 migration happen on the
  first durable write, so a rejected or read-only artifact is never modified.
  Concurrent handles on one path are not serialized. It remains the local/test
  durability oracle. Public-network presets instead select the RocksDB adapter
  and schema-v4 direct provider described in `docs/storage-substrate.md`; the
  provider retains only a bounded memory overlay and point-reads durable chain,
  trie, code, sidecar, and transaction-location records.
- **State storage: production trie vs oracle diffs.** Schema-v4 RocksDB state is
  authoritative at each retained account-trie root. Execution opens that root
  lazily, resolves hash-addressed account/storage paths on demand, and persists
  only dirty paths plus the touched-account change set. Memory/file oracles keep
  the older flat baseline-or-parent-diff representation for deterministic
  comparison and migration: stored defaults and `:ABSENT` markers tombstone
  zeroed slots and destroyed accounts, while pruning promotes a kept diff to a
  baseline before its ancestors drop.
- **Staged import boundary.** Staged import is a private, versioned, offline,
  block-serial, single-writer path. It binds authority/chain/genesis and the
  full chain configuration, pins a finalized anchor, advances header, body,
  execution, receipt-verification, and transaction-index stages atomically,
  persists reverse-order unwind intent, and hydrates only a fresh startup store.
  Its execution stage uses the same validated candidate-import kernel as live
  ingress, while staged progress and records retain their own batch. It does not
  publish canonical indexes or checkpoints.
- **Dev KV-handle cache.** Opening a log-structured database replays the whole
  file, so reopening one per write makes each persist O(file) and a run
  O(blocks²) in bytes replayed. The devnet CLI optionally caches one open handle
  per canonical output path for the node's lifetime
  (`call-with-devnet-cli-kv-database-cache`, off by default); a poisoned handle
  is dropped so the next caller reopens.

## Dependency Rules

- Consensus data types may use primitives, RLP, crypto, trie, and chain rules.
- devp2p/RLPx and eth-wire codecs are protocol types that use only foundation
  primitives (crypto, AES, HMAC, RLP, snappy) and chain rules; socket and
  datagram I/O live in the connection/discovery drivers and the networking
  layer, not in the codecs.
- State may use account types and trie commitments, but not genesis parsing.
- Genesis-state assembly may bridge genesis input and mutable state.
- Node state may compose chain-store state and txpool index state; neither
  domain may own the other domain's mutable state.
- EVM may use state and consensus types, but not RPC or CLI.
- Execution may use EVM, state, and consensus types, but not chain store.
- Application services may bridge runtime and storage-core APIs.
- Networking, persistence, and RPC/API adapters are sibling layers over
  application services; runtime and storage-core packages must not depend on
  them. The `eth-sync` layer additionally uses the p2p/eth-wire protocol and
  imports blocks through a caller-supplied callback rather than depending on the
  chain store directly.
- Only `ethereum-lisp` and `ethereum-lisp.core` provide compatibility
  re-exports; domain packages do not re-export higher-layer symbols.
- Architecture tests require the project package graph to remain acyclic and
  every non-facade package to own each symbol it exports.
- RPC may use execution and store APIs, but protocol types must not depend on
  RPC JSON shapes.
- HTTP transport may call RPC dispatch, but RPC dispatch should not depend on
  sockets or listener state.
- CLI and devnet lifecycle are top-level orchestration only.
