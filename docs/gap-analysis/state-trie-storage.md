# State, trie, and storage — gap analysis

This document records a read-only audit of one area of this client: state
management, the Merkle-Patricia trie, and the storage layer (key-value
substrate, chain store, reorg handling, pruning, and crash recovery). It
compares that area against two reference clients and lists what is missing,
what diverges, and what could not be established.

Nothing here has been implemented. Every remediation item describes work that
remains to be done. No statement below should be read as a claim that a fix is
in the tree.

## Sources read

Audit date: 2026-07-28.

| Side | Version | Commit |
| --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` (sparse checkout, `src/Nethermind` only) |

Our side was read at the working tree of 2026-07-28. Line numbers cited for our
code are relative to that tree; function and file names are the durable
identifiers, so prefer them when a line has moved.

Ours, read in full or in the parts that matter:
`src/runtime/state/{types,db,roots,proofs,ranges}.lisp`,
`src/foundation/trie/{types,nodes,encoding,store,proofs}.lisp`,
`src/foundation/database/{types,memory,batch,file,chain-keys,chain-records}.lisp`,
`src/storage/chain-store/**` (model, service, state),
`src/storage/node-store/{snapshots.lisp,persistence/**}`,
`src/runtime/evm/{snapshots,transient-storage,selfdestructs,state}.lisp`,
`src/application/services/execution.lisp`, `src/api/public/state/**`,
`src/app/cli/devnet/runtime.lisp`, plus `PROJECT.md`, `CLAUDE.md`,
`docs/architecture.md`, `docs/validation.md`, `docs/reference-map.md`,
`docs/gas-parity.md`.

Theirs: geth `core/state/{statedb,journal,state_object}.go`,
`core/state/snapshot/`, `trie/{trie,hasher,proof,stacktrie,iterator}.go`,
`triedb/pathdb/`, `triedb/hashdb/`, `core/rawdb/{schema,ancient_scheme}.go`
and the freezer files, `core/blockchain.go`; Nethermind
`Nethermind.State/{StateProvider.cs,Snap/,SnapServer/,Proofs/,Healing/}`,
`Nethermind.Trie/Pruning/TrieStore.cs`, `Nethermind.Db.Rocks/`.

### A note on method

The findings below come from reading source. No Lisp was executed: the shared
warm dev container was absent at audit time (`scripts/dev.sh status` reported
`Dev container ethereum-lisp-dev: absent`) and the audit brief forbade starting
it, so no symbol existence was confirmed by `describe` or `apropos` and no test
was run. Every claim about our behavior is therefore traced to a specific form
in a specific file. Asymptotic claims follow from code structure and are
reliable; there are no measured timings in this document, and the one
performance measurement quoted (`docs/architecture.md:139-146`) is a
pre-existing repo claim, not something reproduced here.

## Executive summary

The ten most consequential gaps, ordered by risk to correctness and to running
a real node.

1. **The storage substrate is a RAM-resident hash table with a durability
   log, not a database.** `file-key-value-database` subclasses
   `memory-key-value-database`, so every key and value the node has ever
   written is in the heap, and opening the file replays it in full. The client
   cannot hold mainnet state at any point in its life. This is the
   direction-level decision `PROJECT.md` reserves, and the evidence for making
   it is now in hand (STORE-14, STORE-19).
2. **There is no trie.** `mpt` is a flat `key → value` hash table; nodes are
   built transiently on each root computation and thrown away. There is no
   node store, no node-by-hash lookup, no reference counting, no path layout,
   and consequently no pruning problem and no ability to load state from disk
   (STORE-06, STORE-07).
3. **A root computation rebuilds the whole node tree.** The recent
   "keep the account trie across flushes and update only dirty leaves" change
   makes the *entry table* incremental but not the hashing:
   `flush-account-trie` still ends in `mpt-root-hash`, which calls
   `build-node` over every account. Per-block cost stays linear in total
   accounts (STORE-08).
4. **Snapshot and revert copy the world.** There is no journal anywhere in
   `src/runtime/state`; `state-db-copy` clones every account and every storage
   table, and `capture-execution-snapshot` calls it per revertible frame. A
   block with many calls costs `frames × total state` (STORE-01).
5. **Block commit copies the whole chain store.** `chain-store-atomic-commit`
   snapshots every table in the memory chain store plus the txpool before each
   commit, so per-block cost is linear in all state ever stored, not in the
   state the block touched (STORE-16).
6. **A crash that leaves a head without state is unrecoverable.** Import
   fails hard with "KV head checkpoint state is not available"; geth walks the
   head back to the newest ancestor whose state it still has. There is no
   `SetHead`, no rewind, no repair (STORE-21).
7. **Snap sync cannot be served or consumed.** No range-proof verification,
   no node iterator, and no trie node store; range enumeration re-scans and
   re-sorts the entire entry table per call (STORE-11, STORE-12).
8. **Nothing is ever deleted.** Block, header, receipt and BAL records are
   append-only by construction, there is no freezer or ancient store, no
   transaction-lookup limit, and startup loads every block record into memory
   (STORE-19, STORE-22).
9. **Empty-account deletion is not fork-gated and is applied at different
   points by different mutators.** `prune-empty-state-object` runs eagerly
   from `state-db-set-code` and `state-db-set-storage` but never from
   `state-db-set-account`, and no caller passes fork rules, while the chain
   config models `eip158Block` (STORE-02, STORE-03).
10. **Proof verification only accepts proofs we generated.** `mpt-verify-proof`
    rejects a proof with unconsumed nodes, so it is order- and length-sensitive
    and cannot check a node set from a peer or another client (STORE-10).

### What is already right

Worth stating plainly, because several of these look like gaps and are not.

The log-structured file backend is carefully built and well tested: a write
batch becomes one length-and-CRC-framed record that is `fsync`ed before the
in-memory table changes, a torn tail is detected and truncated, mid-log
corruption fail-stops rather than silently truncating, opens are pure reads,
and a failed append poisons the handle. `tests/database-tests.lisp` covers all
of that in 27 tests including `log-file-key-value-database-write-batches-are-atomic-on-disk`,
`log-file-key-value-database-recovers-from-a-torn-tail`, and
`log-file-key-value-database-fsyncs-before-the-table-changes`.

Canonical index maintenance across a reorg is real and tested, including the
cases that are easy to get wrong: a side-chain block duplicating a canonical
transaction, and displaced canonical transactions being returned to the pool
(`tests/core-execution-canonical-reorg-tests.lisp`). The diff/baseline state
model handles account destruction, resurrection, explicit zero fields, zeroed
slot resurrection, independent branches, and cycle guarding
(`tests/core-chain-store-state-diff-tests.lisp`, 15 tests).

`docs/architecture.md:147-172` already documents the full-file replay, the
non-serialized concurrent handles, the diff/baseline policy, and the
`O(blocks²)` reopen hazard. Several findings below are quantifications of
limitations this repo already states honestly rather than discoveries.

EIP-6780 is implemented, with same-transaction creation tracked on the EVM
context and rolled back by frame and execution snapshots
(`src/runtime/evm/selfdestructs.lisp:31-63`). Transient storage exists and is
snapshot-scoped. The account-root memo is guarded by a differential oracle
(`*verify-incremental-root*`, `src/runtime/state/roots.lisp:22-27`) that
compares the memoized root against a cold full rebuild under test — that is a
better safety net than either reference client has for the same hazard.

## Findings

### StateDB semantics

#### STORE-01 — No journal; snapshot and revert deep-copy the entire world state

**Verdict:** DIVERGENT. **Severity:** performance (with a correctness-adjacent
consequence noted below).

**Ours.** The string `journal` does not appear anywhere in
`src/runtime/state/` or `src/runtime/evm/`. Reverting is a whole-state restore:
`state-db-copy` (`src/runtime/state/db.lisp:166-181`) walks every entry of
`state-db-objects` and calls `clone-state-object`
(`src/runtime/state/db.lisp:155-164`), which copies the account struct, copies
the code with `subseq`, and copies the whole storage hash table.
`capture-execution-snapshot` (`src/runtime/evm/snapshots.lisp:81-89`) calls
`state-db-copy` and is the snapshot taken for a revertible frame;
`restore-execution-snapshot` (`:96-115`) puts it back via `state-db-restore`
(`src/runtime/state/db.lisp:183`).

**Theirs.** geth keeps an append-only list of typed change entries and reverts
by replaying them backwards: `journal` struct at `core/state/journal.go:188`,
`revert` at `:252-256`, `snapshot`/`revertToSnapshot` reached from
`StateDB.Snapshot` and `StateDB.RevertToSnapshot`
(`core/state/statedb.go:754`, `:759`). There is one entry type per mutation
kind — `balanceChange`, `nonceChange`, `storageChange`, `codeChange`,
`createObjectChange`, `selfDestructChange`, `touchChange`,
`transientStorageChange`, `refundChange`, `addLogChange`,
`accessListAddAccountChange`, `accessListAddSlotChange` — each with its own
`revert` (`core/state/journal.go:466-669`). Nethermind does the same with a
flat `_changes` list and integer snapshots: `TakeSnapshot` returns
`_changes.Count - 1` and `Restore(int)` walks back to it
(`Nethermind.State/StateProvider.cs:355`, `:376-428`).

**Consequence.** Reverts are *exact* — a full copy cannot be imprecise — so
this is not a correctness bug. The cost is the problem. Each revertible frame
costs `O(accounts + total storage slots)` rather than `O(1)`, so a block with
`k` such frames costs `k × world state`. Combined with STORE-16 this makes
block processing superlinear in accumulated state; at mainnet scale a single
block does not complete. The correctness-adjacent risk is that the deep copy
is the *only* thing keeping reverts exact, so any future attempt to make
snapshots cheaper by sharing structure has to introduce journaling correctly on
the first try, with no incremental path.

#### STORE-02 — Empty-account deletion is not gated on EIP-158

**Verdict:** DIVERGENT. **Severity:** consensus-breaking for pre-Spurious-Dragon
chains; inert on post-Merge chains.

**Ours.** `prune-empty-state-object` (`src/runtime/state/db.lisp:33-37`) takes
`(state key object)` and removes the object whenever `empty-state-object-p`
holds. It has no fork-rules parameter and neither call site
(`src/runtime/state/db.lisp:125`, `:221`) has one to pass. The configuration
surface, however, models the fork: `chain-config-eip158-block` and
`chain-rules-eip158-p` exist and are consulted elsewhere in the runtime
(`src/runtime/evm/opcodes.lisp:22`).

**Theirs.** geth threads the gate through as a parameter:
`Finalise(deleteEmptyObjects bool)` deletes an object when
`obj.selfDestructed || (deleteEmptyObjects && obj.empty())`
(`core/state/statedb.go:771`, `:790`; the Amsterdam variant at `:844`, `:881`),
and every caller derives the flag from the chain rules. Nethermind gates the
same way through the `IReleaseSpec` passed to
`Commit(IReleaseSpec, IWorldStateTracer, bool, bool)`
(`Nethermind.State/StateProvider.cs:502`).

**Consequence.** Replaying mainnet history below block 2675000, or any chain
configured with a non-zero `eip158Block`, deletes accounts that the references
retain, producing a different account trie and therefore a wrong state root at
the first block where a touched account is empty. Post-Merge chains set
`eip158Block` to 0, so the divergence is unreachable there.

#### STORE-03 — No touched-account set and no end-of-transaction finalisation pass

**Verdict:** MISSING. **Severity:** correctness (latent; no reachable trigger
established).

**Ours.** Pruning is eager and per-mutation, and the mutators disagree about
whether to do it. `state-db-set-code` prunes (`src/runtime/state/db.lisp:125`)
and the zeroing branch of `state-db-set-storage` prunes (`:221`), but
`state-db-set-account` (`:51-59`) creates the object if absent, writes the
account, marks it dirty, and returns — with no prune. Since
`state-db-state-trie` (`src/runtime/state/roots.lisp:3-10`) emits a leaf for
every entry in `state-db-objects`, an object left holding an all-zero account
becomes an empty-account leaf and changes the root. There is no touched set: no
symbol resembling `touched` appears in `src/runtime/state/`, and no
transaction-boundary sweep exists — the only finalisation in the execution path
is `finalize-evm-selfdestructs` (`src/runtime/evm/selfdestructs.lisp:24-29`),
which clears self-destructed accounts and nothing else.

**Theirs.** geth defers the decision to a single sweep over
`journal.dirties` at the end of the transaction, so the mutation sites do not
need to agree: `Finalise` at `core/state/statedb.go:771-790`, reached from
`IntermediateRoot` (`:916-918`). EIP-161 touches are journaled as their own
entry type (`touchChange`, `core/state/journal.go:513`) precisely so a touched
empty account is visible to that sweep. Nethermind reaches the same place from
`Commit` (`Nethermind.State/StateProvider.cs:502`) and tracks `Touch` as a
distinct `ChangeType` (`:840`).

**Consequence.** In principle a mutation routed through `state-db-set-account`
can leave an empty account in the trie where the references would remove it,
which is a wrong state root. I could not construct a reachable trigger: the two
obvious candidates are closed off, because `state-db-transfer-value` skips
zero-value transfers (`src/runtime/state/db.lisp:75`) so an EIP-161 touch never
creates an object, and `selfdestruct-account`
(`src/runtime/evm/state.lisp:82-92`) only zeroes accounts that necessarily have
code. Every path I traced to an all-zero result also had a non-zero nonce or a
non-empty code hash. The finding is therefore recorded as a latent structural
divergence — the invariant "no empty account survives a transaction" is
maintained by agreement between mutators rather than by a pass that enforces
it, so it is one new mutator away from breaking, and no test would catch that.
Establishing reachability needs execution, which this audit could not do.

#### STORE-04 — Access-list and transient-storage bookkeeping live on the EVM context, not the state database

**Verdict:** DIVERGENT. **Severity:** cosmetic (layering).

**Ours.** EIP-2929 warm/cold sets and EIP-1153 transient storage are fields of
the EVM context, captured and restored by the frame and execution snapshots:
`accessed-storage`, `accessed-addresses`, `transient-storage` and
`storage-clears` in `evm-frame-snapshot` and `evm-execution-snapshot`
(`src/runtime/evm/snapshots.lisp:3-26`, captured at `:52-59` and `:81-89`,
restored at `:61-79` and `:96-115`). Nothing in `src/runtime/state/` knows
about them.

**Theirs.** geth puts both on `StateDB` and journals them:
`AddAddressToAccessList` and `SlotInAccessList`
(`core/state/statedb.go:1512`, `:1539`), `SetTransientState` and
`GetTransientState` (`:550`, `:566`), with
`accessListAddAccountChange`/`accessListAddSlotChange`/`transientStorageChange`
journal entries (`core/state/journal.go:638`, `:661`, `:588`).

**Consequence.** No observable difference today: our two snapshot structures
are always captured and restored together, so the context-side and state-side
data cannot desynchronise. It is recorded because it makes the state database
un-reusable on its own — anything that wants EIP-2929 semantics has to also
carry an EVM context — and because it means the eventual journal (STORE-01) has
to span two objects rather than one. **Overlaps the EVM/gas area**; that audit
owns whether the warm/cold and transient semantics are themselves correct.

#### STORE-05 — Code is stored inline on the state object with no content-addressed code store

**Verdict:** DIVERGENT. **Severity:** performance.

**Ours.** `state-object` holds `code` as a byte vector directly
(`src/runtime/state/types.lisp:5-20`), and every clone copies the bytes:
`clone-state-object` does `(subseq (state-object-code object) 0)`
(`src/runtime/state/db.lisp:158`). The code hash is recomputed from the bytes on
demand rather than cached: `state-object-code-hash` calls `keccak-256-hash` on
the full code whenever the account's commitments are rebuilt
(`src/runtime/state/db.lisp:39-42`, called from
`state-account-with-object-commitments` at `:44-49`).

**Theirs.** geth stores code once per code hash in a dedicated namespace
(`codePrefix` in `core/rawdb/schema.go`, accessors in
`core/rawdb/accessors_state.go`) and caches code and code size on the state
object and in a shared cache, so a copy shares the bytes.

**Consequence.** Contract code is duplicated once per state-db copy, i.e. once
per revertible frame (STORE-01) and once per chain-store snapshot (STORE-16),
and again in every baseline snapshot written by the chain store. The Keccak
recomputation means a state root over `n` accounts with code re-hashes all of
that code, on top of the trie rebuild in STORE-08.

### Trie

#### STORE-06 — `mpt` is a flat key/value table, not a trie

**Verdict:** DIVERGENT. **Severity:** performance, and completeness for
everything that needs node-level access.

**Ours.** The `mpt` structure is a hash table of hex-encoded key to value
(`src/foundation/trie/types.lisp`), and the mutators are hash-table operations:
`mpt-put` is `(setf (gethash (trie-key-id key) (mpt-entries trie)) value)`,
`mpt-delete` is `remhash`, `mpt-get` is `gethash`
(`src/foundation/trie/store.lisp:8-20`). Node structures exist only as
transients: `mpt-root-node` calls `build-node` over
`(hash-table-entries (mpt-entries trie))` and returns a fresh tree
(`src/foundation/trie/nodes.lisp:98-99`, `:37-70`) which is discarded when the
caller finishes with it.

**Theirs.** geth's `Trie` holds a live `root node` and mutates it in place;
`insert` and `delete` walk and rewrite only the affected path
(`trie/trie.go:405`, `:603`), tracking `unhashed` and `uncommitted` counters
(`:51-55`) so `Hash` and `Commit` (`:806`, `:816`) can skip clean subtrees.
Nethermind's `TrieStore` keeps sharded dirty-node caches keyed by path and hash
(`Nethermind.Trie/Pruning/TrieStore.cs:43`, `:110-116`).

**Consequence.** The correctness of the roots is not in question — the fixture
vectors in `tests/trie-fixture-vector-tests.lisp` exercise the official EEST
trie tests against this implementation, and insertion-order independence and
delete-to-empty collapse are tested
(`tests/trie-basic-tests.lisp:14`, `:72`). Node collapse after a delete is
correct for a structural reason worth noting: because the tree is rebuilt from
the surviving entries, there is no stale-node state to collapse, so the class
of bug geth's `delete` has to handle explicitly cannot arise here. What is lost
is everything node-level: no node can be addressed, cached, persisted,
reference-counted, streamed to a syncing peer, or healed. Every downstream
finding in this section follows from this one.

#### STORE-07 — No persistent trie node store

**Verdict:** MISSING. **Severity:** completeness (blocks sync and historical
state), durability.

**Ours.** No trie-node namespace exists in the on-disk schema: the record kinds
are enumerated exhaustively in `+kv-chain-record-kind-prefixes+`
(`src/foundation/database/chain-keys.lisp:3-24`) and there is no node, no
preimage, and no state-history kind. State is instead persisted as flat
per-block account tables and diffs, and rehydrated by re-deriving the trie:
`chain-store-state-db` (`src/application/services/execution.lisp:65-79`)
materialises a fresh `state-db` from `chain-store-for-each-account` and the root
is then recomputed from scratch.

**Theirs.** geth has two full node-store schemes — `triedb/hashdb/`
(hash-keyed nodes with reference counting) and `triedb/pathdb/`
(path-keyed nodes with a disk layer, diff layers, and state history), plus
`core/rawdb/schema.go:130-135` for the state-history index namespaces
(`StateHistoryIndexPrefix`, account and storage metadata and block prefixes).
Nethermind persists nodes through `INodeStorage` with an optional path-based
layout and prunes them in `Nethermind.Trie/Pruning/TrieStore.cs` (`Prune` at
`:554`, `PruneCache` at `:911`, reorg-boundary tracking at `:69`, `:495`).

**Consequence.** There is no obsolete-node problem because there are no
persisted nodes, which sounds like a simplification and is actually the reason
several node capabilities are unreachable: state cannot be loaded lazily (the
whole account set must be materialised, STORE-23), a peer cannot be served trie
nodes, missing state cannot be healed, and reference counting or path-based
pruning has nothing to operate on. Any future snap sync or historical-state
work has to build this layer first.

#### STORE-08 — Root computation rebuilds and re-hashes the whole tree; node hashes are not memoized

**Verdict:** DIVERGENT. **Severity:** performance.

**Ours.** This is the limit of the "keep the account trie across flushes and
update only dirty leaves" change. `flush-account-trie`
(`src/runtime/state/roots.lisp:49-71`) does avoid rebuilding the *entry table*:
with a trie in hand it calls `state-db-apply-dirty-accounts` (`:29-47`), which
touches only dirty addresses. But those calls land in `mpt-put`/`mpt-delete`,
which are hash-table writes (STORE-06), and the flush then calls
`(mpt-root-hash trie)` at `:62` — which is `build-node` over every entry
followed by a full recursive encode (`src/foundation/trie/nodes.lisp:111-115`).
Nothing is memoized on a node: `node-reference` re-encodes its argument
(`:92-96`), `node-rlp-object` calls `node-reference` for each branch child
(`:82-87`) so each node is encoded up to twice, and `node-reference-hashed-p`
(`:106-109`) encodes a third time.

So the change removed the per-account storage-trie rebuild (that is the memo
described in `docs/architecture.md:139-146`, worth the quoted ~93% there) and
the per-account RLP re-serialisation, but not the account-trie hashing. Cost per
root remains `O(total accounts)` in node construction and Keccak, regardless of
how few accounts the block touched.

**Theirs.** geth memoizes the hash on the node and skips clean subtrees:
`hasher.hash` returns the cached `hashNode` when present and only descends into
dirty children (`trie/hasher.go:59`), driven by the `unhashed` counter
(`trie/trie.go:52`, `:806`). Per-block hashing cost is proportional to the
touched paths, not to the state size.

**Consequence.** Per-block state-root cost is linear in total accounts, with a
Keccak over each reconstructed node. This is the single largest fixed cost in
block processing after the copies in STORE-01 and STORE-16, and it is the one
whose fix is most localised: memoizing encodings and hashes on retained nodes
does not require changing the storage substrate.

#### STORE-09 — No secure-trie layer; key hashing is the caller's job and no preimages are kept

**Verdict:** DIVERGENT. **Severity:** cosmetic, with one completeness
consequence.

**Ours.** There is no hashed-key wrapper. Callers hash addresses and slots
themselves before calling the trie: `state-db-state-trie` computes
`(keccak-256 (address-bytes ...))` inline (`src/runtime/state/roots.lisp:6`),
`state-db-account-proof-key` does the same (`:12-13`), and
`state-db-apply-dirty-accounts` repeats it per dirty account (`:39`). No
preimage is retained anywhere.

**Theirs.** geth has a distinct hashed-key trie type (`trie/state_trie.go`,
historically `secure_trie.go`) that owns the hashing and a `secKeyCache` of
preimages. Nethermind separates `StateTree`/`StorageTree` from `PatriciaTree`
for the same reason.

**Consequence.** The hashing itself is correct, so no root diverges. Two
smaller costs: the Keccak of each dirty address is recomputed on every flush
rather than cached with the account, and because no preimage is stored, any API
that has to go from a hashed trie key back to an address or slot — snap-sync
account ranges keyed by hash, some debug and tracing endpoints — has no source
for it. Our `state-account-range-entry` sidesteps this by carrying the address
alongside the proof key (`src/runtime/state/types.lisp:68-75`), which works
because the range comes from our own in-memory tables rather than from a trie
walk.

#### STORE-10 — Proof verification requires an exactly-sized, correctly-ordered proof list

**Verdict:** DIVERGENT. **Severity:** correctness (interoperability).

**Ours.** `mpt-verify-proof` takes `proof` as a list, treats
`(first proof)` as the root node, threads the remainder positionally through
`mpt-proof-node-value`, and then rejects anything left over:
`(when remaining-proof (error "MPT proof has unconsumed nodes"))`
(`src/foundation/trie/proofs.lisp:97-118`, the rejection at `:116-117`). The
list must therefore be exactly the nodes on the path, in root-to-leaf order,
with no extras — which is what our own `mpt-get-proof` produces
(`:31-38`) and essentially nothing else does.

**Theirs.** geth's `VerifyProof` takes an `ethdb.KeyValueReader` keyed by node
hash, so the proof is an unordered set and extra nodes are simply never looked
up (`trie/proof.go:111`); `Trie.Prove` writes into the same shape
(`:37`). Nethermind's `ProofVerifier` likewise resolves nodes by hash
(`Nethermind.State/Proofs/ProofVerifier.cs`).

**Consequence.** We can verify our own proofs and no one else's. An
`eth_getProof` response from geth or Nethermind, or a proof set arriving over
snap, is rejected as malformed or as having unconsumed nodes even when it is
valid — the failure looks like a proof error rather than a format mismatch,
which makes it easy to misdiagnose. Generation is unaffected: our proofs are
valid node lists and a hash-keyed verifier accepts them, so the
incompatibility is one-directional.

#### STORE-11 — No range-proof verification

**Verdict:** MISSING. **Severity:** completeness (blocks snap sync).

**Ours.** `src/foundation/trie/proofs.lisp` provides single-key generation and
verification only. `src/runtime/state/ranges.lisp` produces
`state-account-range-entry` and `state-storage-range-entry` values with proof
keys, but nothing verifies a bounded range of leaves against a root, and no
symbol resembling a range proof exists in the trie package.

**Theirs.** geth `VerifyRangeProof(rootHash, firstKey, keys, values, proof)`
at `trie/proof.go:478`, which is what makes snap account and storage ranges
trustable. Nethermind has the corresponding server and client halves in
`Nethermind.State/SnapServer/SnapServer.cs` and `Nethermind.State/Snap/`
(`AccountRange.cs`, `StorageRange.cs`, `AccountsAndProofs.cs`).

**Consequence.** Snap sync cannot be implemented as a consumer: a peer's
account or storage range cannot be checked against the state root, so it can
only be trusted or discarded. Combined with STORE-12 it also cannot be served.
**Overlaps the networking/sync area**, which owns the wire protocol itself.

#### STORE-12 — No node iterator; range enumeration re-scans and re-sorts the whole table

**Verdict:** MISSING (iterator) and DIVERGENT (range enumeration).
**Severity:** performance, completeness.

**Ours.** `mpt-entry-range` maphashes the entire entry table, filters, then
sorts the survivors, on every call (`src/foundation/trie/store.lisp:31-44`);
`mpt-entry-pairs` does the same without bounds (`:22-29`). There is no
position-preserving cursor and no way to resume, so serving successive ranges
is `O(total entries · log n)` per range rather than `O(range)`.

**Theirs.** geth exposes `NodeIterator`, `NodeIteratorWithPrefix` and
`NodeIteratorWithRange` (`trie/trie.go:129`, `:145`, `:157`; interface at
`trie/iterator.go:75`), which descend to the start key and walk forward,
plus fast and binary iterators over snapshot layers
(`core/state/snapshot/iterator_fast.go`, `iterator_binary.go`).

**Consequence.** Serving a snap-sync peer paging through state would re-scan
the entire account set per page. Independently, `eth_getProof` and any bounded
state query pay a full scan and sort.

#### STORE-13 — No stack-trie; derive-sha roots build a full trie per list

**Verdict:** DIVERGENT. **Severity:** performance (minor).

**Ours.** `derive-list-root` creates a fresh `mpt`, `mpt-put`s each
RLP-indexed item, and takes the root
(`src/protocol/receipts/receipts.lisp:126-131`); `transaction-list-root`,
`receipt-list-root`, `transaction-receipt-list-root` and
`withdrawal-list-root` all route through it (`:133-146`).

**Theirs.** geth uses a stack trie, a single-pass streaming builder that
retains only the nodes on the current right-hand spine and emits the rest:
`NewStackTrie` and `Update` at `trie/stacktrie.go:58`, `:82`, `Hash` at
`:440`; `types.DeriveSha` drives it.

**Consequence.** Correct roots, higher constant factor: a hash table plus a
full `build-node` per list instead of a streaming build. At a few hundred
transactions per block this is small, and it is listed for completeness rather
than as a priority.

### Storage substrate and layout

#### STORE-14 — The key-value engine is a RAM-resident hash table with an append-only durability log

**Verdict:** DIVERGENT. **Severity:** durability and performance; this is the
direction-level finding.

**Ours.** The decisive line is the class hierarchy:
`file-key-value-database` is `(defclass file-key-value-database
(memory-key-value-database) ...)` (`src/foundation/database/types.lisp:15`),
and `memory-key-value-database` holds one `entries` hash table
(`:5-7`). The file is a durability log over that table, not a place data lives:
`kv-log-write-durable-set` encodes the batch as one frame, appends and syncs
it, then applies it to the in-memory table
(`src/foundation/database/file.lisp:280-299`). Opening replays the entire file
(`kv-log-replay`, `:407`; `kv-load-file-database`, `:488`). Compaction rewrites
the whole file into a temp file and renames it (`kv-log-write-compact-file`,
`:312`; `kv-log-rewrite-file`, `:341`), triggered once the log exceeds a
multiple of live bytes (`:358`, defaults at `types.lisp:9-13`). The format is a
private one, magic `ELKVLOG2` (`file.lisp:31`).

To be clear about what this design gets right, because it is a lot: one
`fsync`ed CRC-framed record per batch, ordered `fsync` before the table
mutation, torn-tail detection with truncation deferred to the first write,
fail-stop on mid-log corruption, pure reads on open, handle poisoning after a
partial append, and v1 migration. The durability engineering is sound. The
problem is capacity, not correctness.

**Theirs.** geth uses Pebble or LevelDB (`ethdb/pebble/`, `ethdb/leveldb/`) —
an LSM tree with a write-ahead log, block cache, bloom filters, compaction, and
a working set that does not have to fit in RAM — plus append-only freezer
tables for cold data (`core/rawdb/freezer.go`, `freezer_table.go`).
Nethermind uses RocksDB (`Nethermind.Db.Rocks/DbOnTheRocks.cs`) with column
families and a configurable block cache.

**Consequence, quantified.** Three hard limits, all of them capacity limits
rather than bugs.

- *Heap*. Every persisted key and value is resident. Mainnet state is on the
  order of 250 million accounts and slots; at even 100 bytes of Lisp object
  overhead per entry that is tens of gigabytes before block bodies. The client
  cannot hold mainnet state, and the ceiling is RAM, not disk.
- *Startup*. Opening is `O(file bytes)` with no index, so restart time grows
  linearly with everything ever written.
- *Write amplification*. Compaction rewrites the entire file. With the default
  ratio of 2, steady-state writes are rewritten whole once per doubling of the
  log against live size, so total bytes written grows with `O(n²/live)` over the
  life of the file. `docs/architecture.md:167-172` already documents the
  related reopen hazard and the dev handle cache that mitigates it.

**Direction-level framing.** `PROJECT.md` reserves replacing the storage
substrate as a direction-level decision, so this finding is evidence, not a
proposal. What it establishes: the current engine cannot be tuned into one that
holds mainnet state, because the limit is the in-memory `entries` table that
`file-key-value-database` inherits, not a parameter. What it does not
establish: which replacement, or whether the project's goals require mainnet
scale at all. A devnet or a small private chain is served correctly and durably
by what exists today. See the remediation section for the decision this needs.

#### STORE-15 — On-disk schema is hash-keyed with no ordering, no ancients, and no state history

**Verdict:** DIVERGENT. **Severity:** completeness.

**Ours.** Twenty-one record kinds, each a one-byte prefix followed by an
identifier (`+kv-chain-record-kind-prefixes+`,
`src/foundation/database/chain-keys.lisp:3-24`; key construction at `:84-87`).
Blocks, headers and receipts are keyed by block hash alone; only
`:canonical-hash` is keyed by number. There is no total-difficulty record, no
body/header split for cold storage, no code namespace, no trie-node namespace,
no state-history namespace, and no snapshot namespace.

**Theirs.** geth prefixes with the number first so that height-ordered
iteration and range deletion are possible:
`headerPrefix + num + hash`, `blockBodyPrefix + num + hash`,
`blockReceiptsPrefix + num + hash`, with `headerPrefix + num + 'n'` for the
canonical hash (`core/rawdb/schema.go:108-115`, key builders at `:188-215`);
`txLookupPrefix + hash` for lookups (`:117`); named head pointers
`LastHeader`, `LastBlock`, `LastFinalized` (`:35`, `:38`, `:44`);
`SnapshotRootKey` (`:59`); state-history index prefixes (`:130-135`); and
freezer tables `headers`, `bodies`, `receipts`
(`core/rawdb/ancient_scheme.go:27-37`).

**Consequence.** Nothing can be iterated or deleted by height. Pruning old
blocks, moving cold data to a freezer, enforcing a transaction-lookup limit, or
walking the chain backwards all require a full-keyspace scan under the current
layout, which is why STORE-19 and STORE-22 are shaped the way they are. Our
checkpoint labels do carry head, safe and finalized
(`chain-keys.lisp:26-29`), so the forkchoice pointers themselves are not
missing.

#### STORE-16 — Atomic commit is a whole-store deep copy; durability is a separate, later step

**Verdict:** DIVERGENT. **Severity:** performance; durability window.

**Ours.** Two mechanisms with a gap between them.

In memory, `chain-store-atomic-commit` takes a snapshot before running the
commit thunk and restores it on any error
(`src/storage/node-store/snapshots.lisp:25-32`). The snapshot is
`engine-payload-store-snapshot` (`:8-14`), which calls
`copy-memory-chain-store` — a fresh table for *every* table in the store,
including `blocks`, `canonical-hashes`, `transaction-locations`,
`account-balances`, `account-nonces`, `account-codes`, `account-storage`,
`state-blocks` and `state-diffs`
(`src/storage/chain-store/service/copy/state.lisp:3-48`) — plus a copy of the
whole txpool. `execute-atomic-block-commit` wraps that around a
`state-db-copy` as well (`src/application/services/execution.lisp:81-90`), so a
block commit takes two whole-world copies.

On disk, the forkchoice export builds one `kv-write-batch` covering canonical
hashes, checkpoints, block/header/receipt records, state records, transaction
locations and txpool records, and applies it in a single `kv-apply-batch` at
the end (`src/storage/node-store/persistence/export/orchestrator.lisp:333-428`,
the single apply at `:424-425`). Given STORE-14's framing that is genuinely
atomic: one CRC-framed `fsync`ed record, all-or-nothing on replay.

**Theirs.** geth commits the block, its receipts, its lookups and the head
pointer in one `ethdb.Batch` inside `writeBlockAndSetHead`
(`core/blockchain.go:1776`), and the state trie flush is ordered against it by
the trie database rather than by copying anything.

**Consequence.** The `PROJECT.md` atomic-import principle holds in both halves,
but at a cost and with a caveat.

The cost: per-block work is `O(all state ever stored in the chain store)`,
because the snapshot copies the block-prefixed account tables for every
retained block, not just the block being committed. This is independent of, and
additive to, the per-frame copies in STORE-01.

The caveat: the in-memory commit and the durable export are separate steps, so
the atomicity is per-step rather than end-to-end. A crash after the in-memory
commit and before the export loses the block — which is safe, since replay
resumes from the persisted head — but a crash *during* an export that spans
several batches would not be covered by the single-batch argument above. The
forkchoice path is a single batch and is safe. `node-store-export-to-kv`
(`orchestrator.lisp:467-495`) is also a single batch, but it is built by
scanning every in-memory table, so its batch grows with the whole store; I did
not establish whether any configuration splits an export across multiple
`kv-apply-batch` calls, and record that as unverified.

### State growth management

#### STORE-17 — No trie-node pruning, no state history, no reverse diffs

**Verdict:** MISSING. **Severity:** durability (the node cannot be run
long-term).

**Ours.** State history is whole snapshots plus forward diffs, all resident.
`chain-store-commit-post-state` writes a diff while the chain to the nearest
baseline stays under the store's baseline interval and a full baseline
otherwise (`src/storage/chain-store/service/state-commit.lisp:116`), with the
interval defaulting to 128
(`+chain-store-default-state-baseline-interval+`,
`src/storage/chain-store/state/memory.lisp:3`). Resolution walks the diff chain
to the nearest baseline (`src/storage/chain-store/service/state-diffs.lisp`).
There is no reverse diff, so history cannot be replayed backwards, and there
are no trie nodes to prune (STORE-07).

**Theirs.** geth `triedb/pathdb/` maintains a disk layer, in-memory diff
layers, and a bounded state history with reverse diffs plus an index and a
pruner (`history.go`, `history_index.go`, `history_index_pruner.go`,
`disklayer.go`, `difflayer.go`); `triedb/hashdb/` reference-counts nodes
instead. Nethermind prunes dirty nodes against a reorg boundary
(`Nethermind.Trie/Pruning/TrieStore.cs`: `Prune` at `:554`, `PruneCache` at
`:911`, `ReorgBoundaryReached` at `:495`).

**Consequence, quantified.** A full baseline every 128 blocks stores the entire
world state again. At `A` accounts and `S` slots, retaining `N` blocks costs
about `(N/128) × (A + S)` entries — for a state of 10 million entries that is
roughly 78 million entries per 1000 blocks retained, all in the heap
(STORE-14). Growth is unbounded in both memory and disk until an operator
prunes manually (STORE-18). This is the finding that, together with STORE-14,
sets a hard ceiling on how long the node can run.

#### STORE-18 — Pruning is manual, absolute-numbered, and only runs at export

**Verdict:** DIVERGENT. **Severity:** completeness.

**Ours.** `chain-store-prune-state-before` takes an absolute block number and
drops state snapshots below it, promoting a kept diff whose parent is being
dropped to a baseline first so descendants are not stranded
(`src/storage/chain-store/service/state-diffs.lisp:279-336`; the promotion at
`:311-333`). The logic is careful and is tested
(`chain-store-prune-promotes-boundary-diffs-to-baselines`,
`chain-store-prune-promotes-side-chain-boundaries`). But it is only reachable
from a CLI-supplied fixed number: `--prune-state-before NUMBER`
(`src/app/cli/options/options.lisp:161`) flows to
`devnet-node-prune-state-before` and to `devnet-node-export-database`, which
prunes only when that option is set
(`src/app/cli/devnet/runtime.lisp:3-11`, `:260-268`). No caller derives the
bound from the head, so the retention window is not a distance — it is a
constant chosen before the node started.

**Theirs.** geth prunes continuously against a distance from head with a
configurable limit (`triedb/pathdb` `StateHistory` config, `--history.state`)
and offers offline pruning (`core/state/pruner/`). Nethermind prunes against
the reorg boundary automatically as blocks arrive.

**Consequence.** An operator who sets `--prune-state-before 1000` and runs to
block 500000 retains 499000 blocks of state. Keeping a fixed window requires
restarting with a new number, so in practice the node grows without bound
(STORE-17). Note also that this prunes *state* only: block, header and receipt
records are untouched (STORE-19).

#### STORE-19 — Blocks, headers, receipts and BAL records are append-only and all are loaded at startup

**Verdict:** DIVERGENT. **Severity:** durability.

**Ours.** Immutability is enforced by construction, not policy:
`node-store-put-immutable-record` writes when absent, no-ops when the bytes
match, and fails when they differ
(`src/storage/node-store/persistence/export/orchestrator.lisp:32-45`), and
`node-store-put-immutable-block-records` routes `:block`, `:header` and
`:receipt` through it (`:47-62`). No code path deletes any of those three
kinds. Only `:block-access-list` records are ever swept, and only against a
live set that includes every persisted block
(`node-store-block-access-list-live-identifiers`, `:430-454`), so the sweep
collects nothing while the blocks remain. On startup,
`chain-store-import-block-records-from-kv` iterates *all* `:block` entries and
puts each into the memory store
(`src/storage/node-store/persistence/import/core.lisp:82-99`).

**Theirs.** geth migrates cold headers, bodies and receipts out of the KV store
into freezer tables (`core/rawdb/chain_freezer.go`,
`core/rawdb/ancient_scheme.go:27-37`) and bounds transaction lookups by
`--txlookuplimit`, deleting older entries (`core/rawdb/chain_iterator.go`).

**Consequence.** Disk grows monotonically with chain length and can never be
reclaimed, and — worse, given STORE-14 — the heap grows the same way, because
every block record is materialised into memory at startup. Restart time and
resident size both grow linearly with total blocks ever seen, including
side-chain blocks, which are also retained. Retaining side-chain data is the
correct reorg-safety choice (`PROJECT.md` reorg safety); having no way to
expire it is the gap.

#### STORE-20 — No ancient/freezer store, no flat snapshot layer, no offline pruning tool

**Verdict:** MISSING. **Severity:** completeness.

**Ours.** No freezer, no ancient directory, and no offline pruning entry point;
the CLI accepts `--datadir.ancient`, `--gcmode`, `--state.scheme`,
`--cache.trie` and `--txlookuplimit` for geth flag compatibility
(`src/app/cli/output.lisp:5`) but there is no corresponding subsystem behind
them. A flat state layer does exist in a sense — the block-prefixed
`account-balances`, `account-nonces`, `account-codes` and `account-storage`
tables are exactly a flat non-trie view — but it is the primary
representation rather than an accelerator over a trie, and it is per-block
rather than layered.

**Theirs.** geth `core/state/snapshot/` (disk layer, diff layers, journal,
generation) sits over the trie so account and storage reads avoid trie descent;
`core/rawdb/freezer*.go` holds cold chain data; `core/state/pruner/` prunes
offline.

**Consequence.** Cold data cannot be moved off the hot path, and there is no
offline recovery path for an oversized database — the only remedies are
`--prune-state-before` at export (STORE-18) or discarding the file. The absence
of a snapshot layer is not itself a read-performance gap here, because flat
tables already are the representation; it becomes one only if a real trie node
store is introduced.

### Reorg and rewind

#### STORE-21 — No rewind or repair; a head without state is a hard startup failure

**Verdict:** MISSING. **Severity:** durability. This is the highest-risk gap.

**Ours.** `chain-store-import-checkpoints-from-kv` validates the persisted head
and fails outright if its state is gone:
`(when (and head-hash (not (engine-payload-store-state-available-p store
head-hash))) (block-validation-fail "KV head checkpoint state is not
available"))` (`src/storage/node-store/persistence/import/core.lisp:166-169`).
The surrounding checks are equally strict — head must match the canonical head
at its height (`:170-179`), safe and finalized must be ancestors of head
(`:180-189`), safe must not be older than finalized (`:196-200`). There is no
`SetHead`, no rewind, and no repair: `node-store-database-head-number` reads
the head checkpoint and fails if its block record is missing
(`orchestrator.lisp:134-150`) rather than searching for a usable ancestor.

**Theirs.** geth treats exactly this situation as recoverable.
`loadLastState` (`core/blockchain.go:631`) detects a head whose state is
unavailable and calls into `setHeadBeyondRoot(head, time, root, repair)`
(`:1007`), which uses `rewindHead` (`:988`) to walk back to the newest ancestor
whose state exists — `rewindHashHead` (`:832`) or `rewindPathHead` (`:908`)
depending on scheme — and resumes from there. `SetHead` (`:772`) exposes the
same machinery.

**Consequence.** A crash or kill between the state export and the checkpoint
export, an incomplete state record, or a manual prune that removed the head's
state, all produce a node that refuses to start. There is no operator recovery
short of editing or discarding the database — no rewind flag, no repair mode,
and no automatic fallback to the last block with state. The strictness is
principled (`PROJECT.md` derived-not-trusted: refuse rather than serve a head
you cannot substantiate) which is why this is classified MISSING rather than
DIVERGENT: the fail-stop is a deliberate and defensible choice, and what is
absent is the recovery path that should follow it.

#### STORE-22 — No `SetHead`, no transaction-lookup limit, no reorg-depth limit, no side-chain expiry

**Verdict:** MISSING. **Severity:** completeness.

**Ours.** Canonical index maintenance across a reorg is present and correct.
`node-store-canonical-difference` walks back from the current head to the first
matching persisted canonical ancestor, collecting installed and displaced
blocks without a full-store scan
(`orchestrator.lisp:169-223`); the forkchoice export then rewrites canonical
hashes, checkpoints and transaction locations for the affected heights, and
deletes a transaction location when the transaction is no longer on the
canonical chain (`node-store-sync-chain-record` deletes on a nil desired value,
`:64-78`; the location is nil unless its block is canonical, `:401-415`). This
is covered by `tests/core-execution-canonical-reorg-tests.lisp`, including the
duplicate-transaction and displaced-transaction cases. What is missing is
bounding: no operator-facing `SetHead`, no `--txlookuplimit` enforcement, no
maximum reorg depth, and no policy that ever expires side-chain blocks
(STORE-19).

**Theirs.** geth `SetHead` (`core/blockchain.go:772`),
`SetFinalized`/`SetSafe` (`:810`, `:822`), `reorg` (`:2561`), and lookup
trimming in `core/rawdb/chain_iterator.go`.

**Consequence.** Reorg correctness is not at risk; capacity and operability
are. Side-chain retention is unbounded, and an operator cannot move the head
without external surgery.

### Historical state access

#### STORE-23 — Historical state works, but each query materialises the entire world state

**Verdict:** DIVERGENT. **Severity:** performance.

**Ours.** State at a past block is reachable, subject to retention:
`chain-store-state-available-p` gates it, and `chain-store-state-db` builds it
by allocating a fresh `state-db` and walking every account through
`chain-store-for-each-account`, setting each account, its code, and every
storage entry (`src/application/services/execution.lisp:65-79`). The three
consumers are `eth_call`-style simulation
(`src/api/public/state/call-simulation.lisp:57`), proofs
(`src/api/public/state/proofs.lisp:22`), and forkchoice
(`src/api/engine/forkchoice.lisp:41`). Depth is whatever has not been pruned,
which by default is everything (STORE-18) — so the client is archival by
accident rather than by design, and becomes non-archival the moment an operator
passes `--prune-state-before`.

**Theirs.** geth opens a reader at a root and resolves accounts lazily through
the snapshot or trie (`core/state/reader.go`, `core/state/database.go`), so cost
is proportional to what the query touches. Nethermind scopes a world state to a
root through its scope provider.

**Consequence.** Every `eth_call` at a height, every `eth_getProof`, and every
trace pays `O(world state)` to build a state it will mostly not read, plus a
second `O(world state)` when the first root is computed (STORE-08). One RPC
call has the cost profile of a full state copy. **Overlaps the RPC/Engine
area**, which owns whether the endpoints' semantics are right.

### Performance shape

#### STORE-24 — No cache layers of the reference kind; residency substitutes for caching

**Verdict:** DIVERGENT. **Severity:** performance.

**Ours.** The caches that exist are two memoizations, both sound and both
guarded: `cached-storage-root` per state object
(`src/runtime/state/types.lisp:11-20`, invalidated only by
`state-db-set-storage`, dropped with the object on deletion) and
`cached-root` for the account trie, trustworthy exactly while `dirty` is empty
(`src/runtime/state/types.lisp:45-46`, enforced in `flush-account-trie`,
`src/runtime/state/roots.lisp:49-71`). Both are differentially tested
(`tests/state-storage-root-cache-tests.lisp`,
`tests/state-account-trie-cache-tests.lisp`). What does not exist is any
bounded cache: no account LRU, no storage LRU, no trie-node cache, no code
cache, and no cache sizing, because everything is resident (STORE-14) and so
nothing needs to be cached against a slower tier. The `--cache`,
`--cache.database`, `--cache.gc` and `--cache.trie` flags are accepted and
inert (`src/app/cli/output.lisp:5`).

**Theirs.** geth sizes account, storage, code and trie-node caches explicitly
(`core/state/database.go`, `triedb/pathdb/database.go`, and the `--cache.*`
flags); Nethermind sizes RocksDB block caches and the dirty-node cache
(`Nethermind.Db.Rocks/DbOnTheRocks.cs`,
`Nethermind.Trie/Pruning/TrieStore.cs`).

**Consequence.** No tuning surface and no memory ceiling: resident size is
whatever the data is. This finding is a corollary of STORE-14 and resolves with
it; it is listed separately because the inert flags invite the assumption that
cache sizing works.

## Remediation plan for this area

Ordered by what unblocks the most, with the `PROJECT.md` principle each item
protects. Sizes are S (under a day of focused work), M (a few days), L (a week
or more, or a design document first).

### 1. Memoize node encodings and hashes; hash only dirty paths — M

Retain the constructed node tree alongside the entry table and cache each
node's RLP encoding and hash, invalidating along the path from a changed leaf
to the root, so `flush-account-trie` re-hashes touched paths instead of
rebuilding. Fixes STORE-08 and most of STORE-13's constant factor.

*Dependencies:* none. This is the highest value-to-risk item in the plan and
does not depend on the storage decision.
*Verification:* `tests/state-account-trie-cache-tests.lisp` and
`tests/trie-fixture-vector-tests.lisp` must pass unchanged, with
`*verify-incremental-root*` bound true throughout — that oracle is exactly the
right guard for this change. Add a test that asserts the number of node
encodings performed for a one-account change is independent of total account
count, so the optimisation cannot silently regress.
*Protects:* state-root memoization; derived-not-trusted (the root stays derived,
just not re-derived wholesale).

### 2. Journal state mutations and revert by replaying entries backwards — L

Introduce a change journal in `src/runtime/state/` with one entry type per
mutation, make snapshots integer marks into it, and reduce `state-db-copy` to
the cases that genuinely need a copy. Fold in the EVM context's access-list and
transient-storage bookkeeping (STORE-04) so one mark covers all revertible
state. Fixes STORE-01.

*Dependencies:* coordinate with the EVM/gas area, which owns the access-list and
transient-storage semantics.
*Verification:* every existing state and EVM test, plus the EEST state-test
fixtures, must pass unchanged — reverts are currently exact, so any behavioral
difference is a regression by definition. Add a differential test that runs a
nested revert sequence under both the journal and a retained deep-copy path and
asserts byte-identical state roots. This is the item where a differential
oracle is not optional.
*Protects:* derived-not-trusted; atomic import.

### 3. Add an end-of-transaction finalisation pass with a touched set, fork-gated — M

Replace eager per-mutator pruning with one pass over the dirty (or touched) set
at the transaction boundary, taking the EIP-158 rule as a parameter from the
chain rules. Fixes STORE-02 and STORE-03; naturally follows item 2, which
supplies the dirty set.

*Dependencies:* item 2 for the touched set, though a dirty-set-based version can
land first.
*Verification:* EEST state tests for the Spurious Dragon transition; add a unit
test that an account zeroed through `state-db-set-account` alone is absent from
the trie with EIP-158 active and present without it. That second assertion is
the one no current test makes.
*Protects:* derived-not-trusted; the `PROJECT.md` rule that fork behavior is
gated by configuration rather than assumed.

### 4. Make proof verification resolve nodes by hash — S

Accept a node set keyed by Keccak hash in addition to the ordered list, and
drop the unconsumed-nodes rejection for that path. Fixes STORE-10.

*Dependencies:* none.
*Verification:* extend `tests/trie-basic-tests.lisp` with a shuffled and
padded proof set that must verify, keeping
`trie-proof-rejects-tampered-referenced-node` passing. Ideally add a fixture
proof captured from geth 1.17.6 at a known root, which turns this into a real
interoperability test rather than a self-consistency one.
*Protects:* derived-not-trusted; the parity rule (a proof from a named client
version either verifies or the divergence is documented).

### 5. Bound retention automatically: prune by distance from head — M

Derive the prune bound from the head number and a configured depth, run it on
commit rather than only at export, and extend it to block, header and receipt
records once the schema can express height ordering. Addresses STORE-18 and
part of STORE-19.

*Dependencies:* pruning blocks and receipts needs item 6 (schema) to avoid a
full-keyspace scan. The state-only half can land first.
*Verification:* `tests/core-chain-store-state-diff-tests.lisp` already covers
the promotion logic; add a test that runs N blocks past the depth and asserts
retained snapshot count is bounded, and one asserting the head's state survives
every prune.
*Protects:* reorg safety (retention must not drop anything a reorg could need);
atomic import.

### 6. Add height-ordered keys and a cold-data namespace to the schema — M

Prefix block, header and receipt keys with the big-endian number ahead of the
hash, mirroring `core/rawdb/schema.go:108-115`, and reserve namespaces for
trie nodes, code, and state history. Include a versioned migration, since the
existing metadata record already provides the hook. Fixes STORE-15 and unblocks
STORE-19 and STORE-22.

*Dependencies:* none technically, but sequencing it after the item 7 decision
avoids designing a schema twice.
*Verification:* `tests/database-tests.lisp` round-trip tests per kind, plus a
migration test that reads a pre-change file and produces identical logical
content. Add a range-delete test proving heights below a bound can be removed
without scanning the whole keyspace.
*Protects:* atomic import (migration must be all-or-nothing).

### 7. **Direction-level decision:** replace the storage substrate — L

This is the item `PROJECT.md` reserves as a direction-level decision, so it is
stated as a decision to be taken rather than work to be scheduled.

*The evidence.* `file-key-value-database` inherits its `entries` hash table
from `memory-key-value-database`
(`src/foundation/database/types.lisp:5-15`), so resident size equals total
persisted size and open time is `O(file bytes)`
(`kv-log-replay`, `src/foundation/database/file.lisp:407`). No parameter
changes that; the limit is structural. Both references use an on-disk engine
with a bounded working set — Pebble/LevelDB plus freezer tables in geth,
RocksDB in Nethermind. Consequences are quantified in STORE-14 and STORE-17.

*What would justify taking it.* A stated goal that requires state larger than
RAM: syncing a public testnet, serving historical state at mainnet scale, or
running longer than the retention window a single machine's memory allows. If
the project's target stays devnet-scale and short-lived chains, the current
engine is adequate and correct, and items 1 through 6 deliver most of the
practical benefit at a fraction of the cost.

*What it would not require.* Abandoning the log-structured backend as a format.
Its durability engineering — one `fsync`ed CRC-framed record per batch, ordered
before the table mutation, torn-tail recovery, fail-stop on corruption — is
sound and worth preserving as the write path or as a reference implementation
for testing a replacement against.

*Verification if taken:* the entire `tests/database-tests.lisp` durability suite
must pass against the new engine, including
`log-file-key-value-database-write-batches-are-atomic-on-disk` and the torn-tail
recovery tests, plus a crash-injection test that kills the process mid-batch and
asserts the reopened database contains either all or none of it.
*Protects:* atomic import; durability.

### 8. Implement head rewind on startup when the head state is unavailable — M

Walk back from the persisted head to the newest ancestor with available state,
mirroring `rewindHead` (`core/blockchain.go:988`), and set the head there
instead of failing. Keep the current fail-stop as the outcome when *no*
ancestor has state, and log the rewind explicitly rather than silently. Fixes
STORE-21.

*Dependencies:* item 5 interacts with it — pruning must never remove the state
that rewind would target, which is why `chain-store-prune-state-before` already
protects the head (`state-diffs.lisp:286-297`).
*Verification:* extend `tests/core-node-store-*` with a database whose head
state record is removed, asserting startup succeeds at the highest block with
state and that the resulting head, safe and finalized pointers stay mutually
consistent. Also assert the still-fail-stop case for a database with no state
at all.
*Protects:* reorg safety; derived-not-trusted (rewind must land on a block whose
state we can actually substantiate, not merely claim).

### 9. Resolve historical state lazily instead of materialising it — M

Give `chain-store-state-db` a lazy reader that resolves an account through the
diff chain on first access, so an `eth_call` touching three accounts costs three
resolutions. Fixes STORE-23.

*Dependencies:* none, though it composes with item 1.
*Verification:* existing `src/api/public/state/` tests must return identical
results; add a test asserting that a single-account query does not enumerate the
account set.
*Protects:* layering (the API layer should not pay for the storage layer's
representation).

### 10. Build a trie node store, then range proofs and iterators — L

The prerequisite for snap sync in either direction and for state healing:
persist nodes addressably, then add `VerifyRangeProof`-equivalent verification
(STORE-11) and a resumable node iterator (STORE-12). Fixes STORE-07, STORE-11,
STORE-12 and the remainder of STORE-20.

*Dependencies:* items 1, 6 and 7 — this is the item that most needs the storage
decision settled first, since a node store on a RAM-resident substrate would
have to be rebuilt.
*Verification:* range proofs against fixture vectors from geth 1.17.6; iterator
tests asserting resumption from an arbitrary start key returns each leaf exactly
once.
*Protects:* derived-not-trusted (synced state must be proved, not accepted).
*Coordinate with the networking/sync area*, which owns the wire protocol.

## Explicitly out of scope / left unverified

**Not executed.** No Lisp ran during this audit. The shared warm container was
absent (`scripts/dev.sh status`: `Dev container ethereum-lisp-dev: absent`) and
the brief forbade starting it, so nothing here is confirmed by `describe`,
`apropos`, or a test run. Every claim is traced to a form in a file, and
asymptotic claims follow from code structure — but no behavior was observed, and
a reader should treat "I could not construct a trigger" as exactly that rather
than as evidence of absence.

**Left unverified, specifically.**

- Whether the latent empty-account divergence in STORE-03 is reachable by any
  transaction sequence. I traced every path to `state-db-set-account` I could
  find and each carried a non-zero nonce or non-empty code hash, but this needs
  execution to settle.
- Whether any configuration causes a single logical export to span more than one
  `kv-apply-batch` call (STORE-16). Both export entry points I read use exactly
  one, so the end-to-end atomicity argument holds for them; I did not enumerate
  every caller.
- Real crash behavior. `tests/database-tests.lisp` simulates torn tails by
  constructing files; no test kills a process mid-`fsync`. The code path is
  right by inspection, and that is not the same as verified.
- Concurrency. `docs/architecture.md:153` states that concurrent handles on one
  path are not serialized. I did not test what two writers do to one file, and
  the consequences are not characterised in this document.
- Absolute performance. No timing was measured. The one figure quoted
  (1769ms → 149ms per block at 400 accounts × 16 slots) is from
  `docs/architecture.md:139-146` and was not reproduced.
- The staged-import path (`:staged-*` record kinds,
  `docs/architecture.md:161-166`) was read only far enough to confirm it is a
  separate offline pipeline that does not publish canonical indexes or
  checkpoints. Its own atomicity and unwind semantics deserve their own audit.
- Verkle. geth has no verkle trie at this commit and neither do we, so there is
  nothing to compare.

**Owned by other areas, flagged for dedupe.**

| Finding | Also touches | What that area owns |
| --- | --- | --- |
| STORE-04 | EVM/gas | Whether EIP-2929 warm/cold and EIP-1153 transient semantics are correct; we only note where the data lives |
| STORE-02, STORE-03 | EVM/gas, block execution | Fork gating of gas-visible empty-account behavior and the EIP-158/161 transition |
| STORE-11, STORE-12 | networking/sync | The snap wire protocol; we only note that the trie cannot supply or check its payloads |
| STORE-23 | RPC/Engine | Whether `eth_call`, `eth_getProof` and tracing semantics are right; we only note their state-access cost |
| STORE-16, STORE-22 | block execution, txpool | Forkchoice transition construction and txpool reinsertion on reorg; the chain-store snapshot copies the txpool too |
| STORE-05 | EVM/gas | Code-size and code-hash opcode semantics (`EXTCODESIZE`, `EXTCODEHASH`) |

**Deliberate, documented limitations, not bugs.** `docs/architecture.md`
already records the full-file replay on open (`:147-153`), the non-serialized
concurrent handles (`:153`), the diff/baseline policy and its 128-block
interval (`:154-160`), and the `O(blocks²)` reopen hazard with its dev handle
cache (`:167-172`). The findings above quantify those rather than reveal them.
The strict fail-stop in STORE-21 is likewise a principled reading of
derived-not-trusted; what is missing is the recovery path after the refusal,
not the refusal.
