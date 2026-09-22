# Account-side closure in snap sync

Why the healer could not trust a present account node, what invariant lets it,
and how the range phase establishes that invariant at write time.

Status: in force as closure epoch seven (`#(7)`). The closed writer and the
healer's account presence skip are switched together by
`*SNAP-SYNC-ACCOUNT-CLOSURE-WRITES*`; an epoch-six datadir is recognized,
never trusted, and resyncs. Measurements and RED controls are in
`docs/evidence/sec5-account-closure-epoch7.txt`, "Phase two: the epoch".

Reference client: go-ethereum `38271784c2b31926563806da9a2e023b88f5e7a8`,
version `1.17.6-unstable`, vendored under `references/go-ethereum`. The syncer
this design ports is snap/1 (`eth/protocols/snap/sync.go`), not snap/2.

## 1. The problem

The MPT store is a flat, content-addressed table: a node is a `:trie-node`
chain record keyed by its keccak hash. There is no path in the key, no root
scoping and no deletion, so nodes accumulate across pivots forever and presence
of a hash means only "some node with that content exists". This is geth's
legacy hash scheme.

Under closure epoch six the healer skips a present, unmarked *storage* node
without descending, and never skips an *account* node. That asymmetry is
correct: a storage leaf's value is a slot value and names nothing outside the
trie, while an account leaf names a code hash and a storage root, so trie
closure does not imply closure.

A pivot rebase then makes the account side unbounded. Range tasks and their
cursors survive a rebase verbatim, so the account trie on disk is a patchwork
of ranges proved against different roots — geth's is too, and that is not the
problem. The problem is that our healer must re-walk every present account node
because nothing tells it the subtree below is complete. On Hoodi this never
converges: `knownIncompleteNodes / processedNodes` sits at 0.99 and the frontier
grows twice as fast as it drains, while the pinned geth control healed 65,631
trie nodes in a 78-minute total sync.

## 2. The invariant

**I1.** An account-path `:trie-node` record implies that every descendant trie
node is durable, and that every non-empty code hash and every non-empty storage
root named by every leaf below it is durable.

I1 mentions no state root. That is the point. A claim that mentions a root is
void the moment the pivot moves; a per-node-hash claim survives any number of
rebases, because a changed account changes its leaf RLP — the storage root and
code hash are *inside* the leaf — hence the leaf hash and every ancestor up to
the divergence point. Those ancestor hashes are absent, so they are fetched and
descended, and the old closed nodes remain durable and unreachable.

## 3. Establishing it at write time

geth establishes the same property in `forwardAccountTask`
(`sync.go:2453-2476`): an account whose code or storage is not yet downloaded
stops the generated trie, an account whose storage was chunked is *deleted*
from it, and the stack trie never emits an unfinished boundary
(`gentrie.go:316-321`). Neither geth nor Nethermind reconstructs closure after
the fact; both arrange for it to be true when the node is written.

The range phase therefore persists **only** the maximal reconstructed subtrees
that satisfy all of:

- the subtree's whole key range lies inside the delivered, proved page;
- every node in it was newly reconstructed by this range (no clean proof edge);
- it is hash-addressed;
- every leaf beneath it is *closed*.

Everything else is simply not written: the account spine, the boundary proof
nodes, the range-straddling regions, and the path to every open account. A
withheld node is absent, so healing fetches it and descends. That is the
fail-closed direction. A present node whose dependencies are absent is a false
completion, which is consensus-grade.

### 3.1 Granularity

Closure is judged per **maximal closed subtree at any depth**, not per
fixed-depth bucket. `MPT-PROVED-RANGE-CLOSED-SUBTREES` keeps descending when a
node fails and publishes the clean children of a poisoned parent, so one
account with undelivered storage withholds its own path rather than the ~850
accounts that would share its depth-four bucket on a live chain. Because this
design does not *write* a withheld node, a coarse exclusion is not merely
slower — it converts a local walk into a wire download, which would be worse
than the stall it replaces. The 64-dependency bound no longer influences the
write decision at all.

This is output-equivalent to what geth's stack trie emits between two
exclusions.

### 3.2 The closure predicate

A leaf is closed only by a real durability check, never by inference:

- a non-empty **code hash** must name a durable `:code` record;
- a non-empty **storage root** must carry this client's own whole-root closure
  proof (`snap-healed-storage-root-v3:`).

Absence from the page's deferred-storage list is *not* accepted as evidence.
Completed partition cursors prove authenticated key-space coverage, not that
every node was materialized; this codebase already says so at the two sites
that demand the root proof (`SNAP-SYNC-RANGE-PLAN-FULLY-DURABLE-P` and
`SNAP-SYNC-PROMOTE-COMPLETE-RANGE-PLAN`), and only a complete single-response
group or the healer's post-order sentinel publishes one. A chunked contract
therefore stays open until the healer publishes its root, which is geth
clearing `needHeal` only when the reassembled root both matches and is present
(`sync.go:2272-2282`).

## 4. Why the ordering holds

Not "codes ride in the same batch" — on the production path they do not. The
guarantee is: one RocksDB handle, no column families, one WAL, atomic write
batches whatever their sync flag, suffix-only crash loss, and a happens-before
edge on every dependency:

- inline storage is applied on the page's own thread before the account batch;
- chunked storage is applied by the committer thread, and the runtime mutex
  orders it before the page observes completion;
- code is written by the code worker's own batch, and the page observes it by
  re-reading the store;
- the range cursor is published by the synchronous apply, which fsyncs the
  whole preceding WAL prefix.

The writer does not depend on any of this being remembered correctly: it
re-reads the code table and the storage-root proofs at classification time, so
an account whose dependency is not durable is simply open.

## 5. Kind-blindness

The flat table holds account and storage nodes in one content-addressed space,
so a kind-blind presence rule needs the two node sets to be disjoint. They are:

- a leaf node is `RLP([compact-path, value])`, so equal leaf encodings have
  equal values;
- the shortest account leaf value is 70 bytes
  (`RLP([0, 0, emptyRoot(32), emptyCodeHash(32)])`), the longest storage leaf
  value is 33 bytes, and that ceiling is *enforced* on peer input by
  `SNAP-SYNC-STORAGE-TRIE-VALUE` rather than assumed from the protocol;
- no account-trie node is ever inlined — an account leaf is ≥ 70 bytes, a
  branch with two hash children ≥ 66, an extension with a 32-byte child ≥ 34 —
  so account nodes are always hash-addressed. Without this lemma the
  branch/extension induction does not close, because a storage branch may carry
  an embedded child where an account branch carries a hash.

## 6. What the invariant replaces

Three mechanisms exist only to reconstruct closure after the fact, and all
three open a persisted MPT on the state root and walk a spine that a
closed-subtree store deliberately does not have: the deferred-storage plan
marker, range-plan promotion, and the walk-free completion. They are disabled
for such a store and kept for legacy stores.

A fourth, the account incomplete-marker namespace, disappears from the range
phase entirely: a subtree owing storage is withheld rather than marked.

## 7. Other writers

Under a presence-based account rule, every writer of an account-path
`:trie-node` record is part of the contract. Exactly two functions put such
records: `MPT-POPULATE-DIRTY-BATCH` (block and genesis state export, the
schema-v4 migration, and the snap/1 server, which is live while we sync) and
`SNAP-SYNC-POPULATE-VERIFIED-TRIE-RECORDS-BATCH`. The first writes one atomic
batch of children-before-parents nodes for a trie fully materialized in memory,
with code in the same batch, so it upholds I1 for a complete state.
`SNAP-ACCOUNT-TRIE-NODE-WRITERS-ARE-ALL-CLASSIFIED` pins that list so a new
writer breaks a test rather than a live sync, and
`SNAP-EPOCH-SEVEN-DOES-NOT-TRUST-ACCOUNT-NODES-WRITTEN-BY-BLOCK-IMPORT` audits
the genesis export and block commits batch by batch into an epoch-seven store.
The snap/1 server's `SNAP-SYNC-ROOT-TRIE` persists the account trie alone,
without its storage tries or code, and is not covered by that argument.

There is a third writer, which the list above missed and the snap-server-closure
change found (`fc0bb2ea`): the healer's own fetched-node flush in
`%SNAP-SYNC-HEAL-STATE`. It writes fetched nodes top-down, a parent in a batch
before its children, each with its incomplete marker in the same batch, and
only the node's post-order `:node-complete` sentinel deletes the marker. So the
presence rule is "present AND unmarked", exactly as the epoch-six storage rule
was: the healer processes a marked node before it considers the skip.
`SNAP-EPOCH-SEVEN-HEALER-DESCENDS-A-MARKED-ACCOUNT-NODE-AFTER-A-CRASH` pins that
across a crash.

## 8. Rejected alternatives

**Rebase-tolerant range plan or promotion.** Fatal. After a mid-range rebase
the task set is a mosaic. Promotion walks the spine without resolving
descendants, so a depth-four bucket whose spine node was written under R1 but
whose contents were only downloaded under R2 would be published as closed. If
R2 leaves that bucket unchanged the hash matches, the healer skips it, and the
subtree is missing — the `03263d2f` signature. The sticky rebase witness exists
to make this impossible.

**Explicit positive closure witnesses** (`snap-account-closed-node-v1:<hash>`).
Sound, and the correct fallback: it keeps the whole trie on disk, so a poor
qualification rate costs metadata keys rather than a download. It needs one
metadata key per account trie node and does not need the kind-disjointness
lemma. Strictly worse than establishing the invariant at write time, which gets
the same skip for zero extra keys.

**Path-scoped account nodes** (geth's path scheme). Makes "stale at a path"
representable and kind-scoping structural, and removes the need for any closure
marker. It is an XL storage rewrite and is the long-term direction, not the fix
for this stall.
