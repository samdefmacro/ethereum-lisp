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
  chain, genesis, and database authority. Fresh imports split the account
  keyspace into sixty-four durable ranges. One AccountRange dispatcher uses
  each available snap peer and hands its verified pages to a bounded global
  dependency queue. The session thread remains the only RLPx writer, but it
  may pipeline one account, storage, bytecode, and trie-node request at once;
  decoded replies are matched by response type and request id before waking the
  worker. Synchronous eth jobs wait for an empty SNAP response seam, so they
  cannot consume a pipelined reply. The next range can therefore use the
  connection while an earlier page resolves storage, bytecode, or RocksDB
  work through the global queue; older
  sixteen-range progress remains resumable and thirty-two-range progress is
  expanded at its exact durable cursors. During range import the dial scheduler
  seeks SNAP-capable outbound sessions up to half of `--maxpeers`, returning to
  the ordinary one-third target afterwards. A productive account-range import
  stays on its exact authenticated pivot even when the live consensus head
  advances. Moving that root on a wall-clock window would invalidate the
  complete same-root range witness and force a redundant full state-tree walk.
  If every live source explicitly rejects the retained state, the importer
  preserves its durable cursors and the next coordinator pass atomically
  rebases them to a serviceable newer pivot. Account and
  storage requests start at geth's 64 KiB lower cap. Each peer and response
  type learns an EWMA of delivered capacity and round-trip time, grows or
  shrinks toward a two-second request target, and stays within the protocol's
  native units: 64--512 KiB for ranges, 1--84 returned code items for
  ByteCodes, and 1--1,024 returned nodes for TrieNodes. This prevents a slow
  peer from holding a fixed maximum response until the session's wall-clock
  deadline while allowing fast peers to refill the full page in bounded steps.
  Fetch workers construct and atomically append verified content batches in
  parallel. One coordinator folds up to sixteen ready successor cursors into
  one synchronous publication batch, so a visible cursor still flushes the
  complete preceding WAL prefix without a per-page fsync. Storage and bytecode
  dependencies are scheduled independently of the peer that returned their
  account page. ByteCodes jobs from every page share sixteen import-wide workers;
  each assignment considers only idle sessions, chooses the largest learned
  item capacity, and uses measured RTT to break ties. This matches geth's
  central capacity-sorted assignment without multiplying worker count by the
  number of account pages. An ordinary dependency transport
  failure enters a thirty-second cooldown and the
  already authenticated account page's remaining work retries elsewhere
  instead of being discarded. A peer which explicitly rejects the pivot state
  is excluded for that import, while its exact stable node id (including when
  it served a pooled dependency rather than the account page) is remembered
  across finite coordinator passes for the lifetime of the same pivot. A failed
  account peer releases only its claimed range for another worker. If every
  peer in that finite source snapshot fails, the CLI keeps the node and Engine
  API alive at the same durable per-range cursors. Inside geth's pivot-retention
  window it waits for genuinely new sources and does not re-probe rejected
  sessions or churn roots every second. Aggregate explicit state-unavailable
  from the whole generation normally yields when a newer CL-authorized target
  is known, even for an intrinsically small pool; peer heads still cannot
  authorize the replacement. If that generation produced an efficient bounded
  TrieNodes response window during the preceding five minutes, however, its
  exhaustion is treated as transient churn and the exact pivot waits for a new
  source. This evidence survives finite coordinator passes. Once it expires,
  pivot selection performs the same stale-target yield even when the rejection
  set filters every source before another importer can start. The process-local
  rejection set and response evidence clear when that successor selects a
  genuinely new pivot and are never a peer score or permanent ban. During final
  healing, a pool that reached at
  least eight live sources also yields a CL-stale target when more than half
  that observed capacity remains unavailable for five minutes, even if the few
  residual sources still return small productive batches. A collapsed pool
  must recover for thirty continuous seconds before it clears that window, so
  short-lived public-session churn cannot pin an obsolete root. A numerically
  stable pool has
  an independent bounded-yield check: after one healthy response window, at
  least sixty-four later TrieNodes requests averaging fewer than eight fetched
  nodes each start the same five-minute stale-target escape. Productive local
  work cannot conceal that remote serving collapse. A stable intrinsically
  small but efficient pool does not satisfy either policy. This keeps content-
  addressed progress moving across public state-retention windows instead of
  pinning a doomed old root. While an import is active, the dialer retains at
  least sixteen live non-degraded SNAP sessions when the configured peer limit
  permits it.
  A failed capability is recorded by response type; success in unrelated SNAP
  traffic cannot hide it, and the still-useful ETH transport no longer counts
  toward the SNAP target while discovery seeks a replacement. Its dedicated
  process-local lock permits dependency workers
  to record exact rejections concurrently with coordinator callbacks without
  entering the peer-table or database lock orders.
- Public discv4 discovery retains a bounded process-local set of at most 256
  endpoint-proven public routing hops between crawls. Cross-chain ENRs may help
  traverse the shared Kademlia graph but still cannot become TCP candidates;
  the chain fork-ID filter remains the only admission path. This follows the
  persistent-routing-table shape used by production clients without making
  discovery state durable or unbounded. The responder owns one long-lived UDP
  socket for both outbound crawls and inbound service, matching geth's unified
  discv4 endpoint. The Ping's claimed UDP port and its observed source port are
  therefore the same stable P2P port, and the socket continues to answer after
  each bounded crawl completes.
  Local persistence and trie-merge failures remain fatal and are not converted
  into retries. Account and storage ranges carry compact boundary proofs, trie
  nodes are served by path set, and every page is verified before its dependency
  worker buffers account nodes, complete small storage tries, and proof
  metadata. Each geth-sized ByteCodes response is hash-verified and buffered
  immediately before its individual global flights are released. Pages sharing
  that contract code can therefore recheck RocksDB and advance without waiting
  for an unrelated tail batch owned by the same page. These authenticated,
  content-addressed intermediate RocksDB batches
  keep WAL enabled without forcing a separate sync. No progress is published at
  that point; the following account page's synchronous cursor batch flushes the
  complete earlier WAL prefix. A
  crash before that seam only repeats the page, while a visible cursor still
  implies durable prerequisites. Range reconstruction uses a dedicated
  proven-absent MPT insertion:
  the verified gap-free page and its monotonic durable successor cursor already
  prove that these keys are new, so proof reconstruction omits `mpt-put`'s
  redundant defensive point traversal. The verifier returns that reconstructed
  page instead of discarding it: its new nodes plus authenticated boundary
  proof nodes are deduplicated and persisted by content hash in the worker's
  buffered transaction. Their keys are derived from the exact encoded nodes
  only after
  proof verification, so blind puts are idempotent for healthy state and repair
  a corrupt same-key local value without a RocksDB read for every reconstructed
  node. This matches geth's hash-scheme range ingestion and removes the former
  second global MPT rebuild and its per-node RocksDB point reads. Inside proof
  verification, the strictly ordered flat key/value range is consumed once by
  a canonical sequential trie builder and merged with the trimmed boundary
  graph. This transient flat staging is deliberately not retained as a second
  on-disk state copy: it removes repeated copy-on-write ancestor construction
  while keeping the content-addressed trie as the sole durable authority.
  Ordinary state transitions retain checked `mpt-put`. Complete coarse buckets strictly inside
  each authenticated range contain only newly reconstructed nodes. After that
  page's small storage and code become buffered prerequisites, their root
  hashes share the same WAL prefix as the pivot-independent subtree proofs used by the
  healer. A later pivot therefore traverses only changed and boundary buckets,
  rather than rereading every range-ingested node once before it can build the
  proof index. A bucket containing at most 64 deferred storage roots publishes
  a distinct account-completion proof whose bounded value lists those exact
  `(account hash, storage root)` dependencies. A later pivot can skip the
  unchanged account trie and its already durable code while placing every
  listed storage root into the ordinary checkpointed healer frontier. A wider
  dependency set remains unproved and takes the fail-closed account walk.
  Fresh empty stores additionally adopt geth's exact hash-scheme completion
  invariant from commit `38271784c2b31926563806da9a2e023b88f5e7a8`, specifically
  `trie/sync.go` `AddSubTrie`, `children`, `hasNode`, and `commitNodeRequest`:
  presence of a hash means its descendant trie nodes and leaf-triggered code or
  storage dependencies were durable before its parent became complete. Range
  proof-edge nodes and other authenticated-but-open records are written with a
  hash-keyed negative `incomplete` marker in the same batch. Fully reconstructed
  interior groups need no per-node positive metadata. A fetched TrieNodes record
  is likewise written with its negative marker; a depth-first completion
  sentinel deletes that marker only after descendants, bytecode, and deferred
  storage are durable. Marker deletion is buffered in batches of 2,048 and is
  flushed before a checkpoint, subtree proof, yield, or final completion. A
  crash before the delete merely repeats safe traversal. Progress version five
  records whether this contract is active, while versions two through four
  remain conservative. A database-level scheme marker is created only when the
  trie-node namespace is empty, so an upgraded or rolled-back legacy datadir can
  never turn old unclassified hash presence into a completeness proof.
  StorageRanges pages apply the complete-proof rule directly
  to their reconstructed storage trie, publishing coarse storage-subtree proofs
  atomically with their node records and successor cursor. Pre-optimization
  range plans are upgraded lazily with depth-bounded walks over only the account
  and completed storage tries' shallow spines. Legacy account buckets containing
  an incomplete large-storage cursor set remain excluded while every other
  bucket is immediately reusable; completed storage roots receive their own
  reusable proofs. New proofs use five-nibble buckets so a later pivot can still reuse
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
  bound also fall back to that path. TrieNodes healing follows the response-
  driven event loop in geth `38271784c2b31926563806da9a2e023b88f5e7a8`:
  every live source owns at most one request, all sources draw from one exact
  retry queue, and the coordinator validates and integrates each individual
  response as soon as it arrives. A fast source can therefore receive child
  work discovered from its prior response while an unrelated slow source is
  still in flight; there is no global request-round join barrier. Every new
  source starts at the protocol maximum of 1,024 paths. A source-local EWMA
  learns the useful delivered width against a two-second request target and a
  second EWMA learns RTT; idle sources are assigned in descending learned
  capacity and then ascending RTT order. Partial responses requeue only their
  unmatched exact paths, while a failed source is retired and all of its exact
  assigned paths return to the same queue. Late handshake completions join the
  running event loop without restarting it, and a retired identity cannot
  re-enter the same healing attempt.

  Each request slice is sorted by account and compact path, then all storage
  paths for the same account share one wire path set, matching geth's grouping
  and avoiding a repeated remote account-trie lookup per storage node. A
  response-order index maps partial replies back to the exact DFS continuation.
  Pending, in-flight, locally exposed, and deferred work are counted in work
  units rather than request units against a 131,072-work remote-admission
  target; the serving side independently applies the same 1,024-lookup
  ceiling. A local depth-first step is still allowed to expose the immediate
  children of the work it popped, so the observed frontier can briefly cross
  that target by a bounded branch continuation. While it is above the target,
  the coordinator admits no net-new remote work and the DFS drains back below
  it. The
  observational healer snapshot exposes that currently discovered frontier as
  `frontierWorks`, with `deferredStorageWorks` and `remoteWorks` as subsets.
  These values are queue pressure, not a completion denominator: decoding one
  trie node may discover more child or storage work. `knownIncompleteNodes`
  separately counts conservative durable negative markers, including retained
  content that an older pivot wrote but the current root may never reach.
  Completion percentage is therefore unavailable until the authorized root has
  actually been traversed; `completed=T` remains the only terminal authority.
  The
  smaller 8,192-work durable checkpoint remains the restart contract. A legal
  checkpoint restored at that exact cap can therefore fill every idle peer
  instead of shrinking to one path merely to reserve worst-case branch room;
  checkpoint publication waits until the transient frontier drains back into
  its separately bounded record. The
  local processing-rate feedback still bounds how quickly traversal exposes
  new remote work, but no global rate setting truncates an individual peer's
  learned capacity. The public-node peer default is 50, matching geth
  `38271784c2b31926563806da9a2e023b88f5e7a8` and Nethermind
  `e52dc19a56a46f58170a730822580774d403c838`; the one-request-per-source rule
  remains stricter than either implementation's process-wide worker pool and
  preserves this client's sole-writer session boundary. Account traversal
  defers up to 2,048 discovered storage roots instead
  of descending into each contract immediately. The deferred roots become part
  of the bounded work frontier before any checkpoint or remote request, so one
  authenticated TrieNodes round can fill many contracts without weakening
  restart safety. A subtree-completion sentinel also drains its deferred storage
  before it can publish proof of completion.

  Local content-addressed references are read in batches of at most 512 keys.
  Below the ordinary 4,096-work checkpoint target, width still shrinks so a
  worst-case 16-way expansion remains immediately encodable in the 8,192-work
  record. Larger transient frontiers instead shrink against the independent
  131,072-work in-memory cap. A restart may begin at the
  legal 8,192-work durable cap, where its next branch can transiently expand
  the exact DFS frontier above one checkpoint record. If a
  checkpoint becomes due in that state, the prior durable record remains
  authoritative while batched local reads and full peer flights drain the
  excess; fetched nodes may still be committed by content hash, but no partial
  frontier is published. The next
  checkpoint is written only after the complete frontier is back within 8,192,
  so allocation remains explicitly bounded without turning a temporary shape
  into a fatal node exit. On SBCL, production RocksDB batches of at least 128
  keys are divided into at most eight contiguous native multi-get slices on the
  supported eight-core public-node profile. This
  path uses a 1 GiB sharded block cache on the supported shared 16 GiB EL/CL
  public-node profile instead of RocksDB 11's 32 MiB fallback. At the
  flat-range-to-healer boundary, joined range-worker garbage is collected once.
  A moving-pivot yield first joins every worker, drops the stopped scheduler's
  uncommitted page queues, and performs the same collection before rebasing;
  successive live-head windows therefore cannot retain old page graphs until
  the final healer on the shared host. At either boundary,
  healer code-hash deduplication is exact within each 2,048-item batch and then
  released because the next batch rechecks durable code with MultiGet. Ten-bit
  full Bloom filters
  keep absent whole-key probes out of newly written SST data blocks, while
  index/filter blocks receive high cache priority and L0 pinning. These table
  settings alter neither verified values nor synchronous cursor batches. The
  CFFI adapter pins specialized Lisp key/value vectors for the bounded native
  call that copies them, bulk-copies returned values with native `memcpy`, and
  likewise bulk-copies MultiGet keys into its one contiguous request buffer.
  This removes per-record foreign allocations and per-octet foreign accesses
  without changing ownership, ordering, WAL sync, or the durable cursor seam. The
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
  the same ordered generic fallback. Under the version-five complete-node
  contract, a locally present hash without an `incomplete` marker is hash-
  checked and closes that exact DFS branch without RLP decoding; marked and
  legacy nodes retain the ordered decode and descendant walk. A content-hash-
  and path-matched remote
  response is decoded in full before any of its entries are staged, then its
  decoded nodes are retained in a bounded in-memory response cache alongside
  the pending write batch. The normal coordinator traversal consumes the cached
  object without either a per-node point Get or a write-then-reread MultiGet.
  This adopts geth's `ProcessNode` response locality; Nethermind's `TreeSync`
  likewise routes responses directly into its processing/store pipeline rather
  than rediscovering them as pending disk reads. A restart after the next
  durable seam reads already-written content-addressed nodes normally; a crash
  before that seam resumes the older exact checkpoint and may safely request
  the same hashes again. Proof values are version-checked after the
  ordered join, so an unknown value remains local storage corruption rather
  than a cache miss. This bounded read/decode concurrency uses otherwise idle
  CPU and I/O capacity without making frontier mutation or checkpoint
  publication concurrent. The
  database API rejects more than 4,096 keys or 4 MiB of key bytes before native
  allocation. Validated fetched nodes accumulate in a geth-sized 100 KiB write
  batch and remain available from their decoded response cache while that batch
  is pending. No completion proof or durable frontier may cross that prefix:
  crossing the threshold, publishing a proof, checkpointing, yielding, or
  completing first flushes the node batch. When a checkpoint becomes due, the
  event loop stops new assignment, integrates every in-flight response, and
  reconstitutes the exact shared queue into one bounded checkpoint. That
  checksummed checkpoint is tied to
  the pivot, target, chain, genesis, and database authority, and is ignored if
  corrupt or stale. After process restart, any identity-matched unfinished Snap
  session pins that exact CL target for one actual attempt even after the
  ordinary pivot-relative 120-block stale window. An exact checkpoint resumes its
  frontier; without one, the retained range cursors and completed-subtree proofs
  still prevent a routine deploy from changing pivot before a peer is tried.
  Waiting for a Snap peer does not consume that process-local opportunity. Once
  a finite source generation has actually been attempted, ordinary stale-target
  rebase is available again. A long-running healer cannot defer that decision
  merely by receiving small partial TrieNodes responses forever: at a boundary with no
  request worker or uncommitted database batch, it checks the current Engine
  forkchoice target at most every 30 seconds. A typed scheduling condition
  yields to the coordinator only when that CL-authorized target is more than
  120 blocks beyond the active pivot (56 blocks beyond its conventional target)
  and either fewer than 2,048 cumulative processed/fetched nodes have arrived
  for five minutes or bounded 64-request windows have averaged fewer than eight
  fetched nodes per request for five minutes. Losing over half of a formerly
  useful source pool corroborates that inefficient-response decision but never
  discards a root by peer count alone. This matches the healer's durable
  checkpoint/reporting granularity: productive local reuse and efficient remote
  batches retain their exact DFS frontier, while a trickle of tiny partial
  responses cannot keep a publicly pruned root alive indefinitely. The same
  stale decision is evaluated while the remote
  event loop is live: the first positive decision is latched, stops assigning
  new work, integrates every response already in flight, flushes the
  fetched-node and subtree batches, and then reaches the ordinary coordinator
  yield seam. Predicate throttling between those responses cannot re-open
  assignment, and the positive edge is carried through that durable seam
  without re-evaluating the throttled predicate. Sparse responses therefore
  cannot keep the pipeline non-quiescent and postpone the decision.
  Peer-advertised heads never enter this decision. The next pass atomically
  rebases the skeleton and state cursor, while already durable
  content-addressed nodes and completed-subtree proofs remain reusable.
  Missing, corrupt, or identity-mismatched checkpoints never suppress rebase,
  and an explicit authority-driven rebase still invalidates the frontier in
  the same batch as both progress records.
  Checkpoint version three records armed, descendant, subtree-completion, and
  node-completion sentinel work while continuing to decode version-one and
  version-two restart records. At a four-nibble
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
  candidate reaches the dial registry. If SNAP persistence owns the store guard
  before discovery's first head snapshot, the known genesis hash, timestamp,
  and fork schedule supply the initial EIP-2124 context; state download can
  therefore never turn a fresh process's shared-DHT crawl into an unfiltered
  cross-chain dial storm. The accepted sequence is atomically
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
