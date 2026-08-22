# Networking, discovery, and sync — gap analysis

This document records a read-only audit of one area of this client: the devp2p
transport (RLPx and the base protocol), node discovery, the `eth` wire protocol,
peer management, and chain synchronization. It is a gap analysis, not a
changelog. Nothing described below has been implemented as part of this audit,
and no statement here should be read as a claim that a fix is in the tree.

Findings are a snapshot of the working tree at commit
`c9193bce5292a48e4cdb89b51409d31a8d716d75`. Line numbers are relative to that
snapshot; function and constant names are the durable identifier, so prefer them
when a line has moved.

Per `PROJECT.md`, feature count is not the metric. The audit is weighted by what
it takes to join a real network, stay on it, and not be taken down by a peer.
Several absences below are recorded as low-severity completeness gaps rather than
defects, and where this client differs on purpose and says so in a docstring that
is noted — a documented limitation is not a bug. Three findings (NET-01, NET-02,
NET-17) are not in that category: they are reachable by an unauthenticated
stranger.

## Sources read

| Side | Version | Commit | Date |
| --- | --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` | 2026-07-28 |
| this client | — | `c9193bce5292a48e4cdb89b51409d31a8d716d75` | 2026-07-28 |

The Nethermind checkout is sparse and contains `src/Nethermind` only. It was used
mainly to establish whether a behaviour is a geth idiosyncrasy or a shared
expectation; where only one reference is cited for a claim, only one was read for
it.

Ours, read in full or near-full: `src/protocol/p2p/` (`identity.lisp`,
`ecies.lisp`, `handshake.lisp`, `frame.lisp`, `connection.lisp`, `protocol.lisp`,
`session.lisp`, `discv4.lisp`, `discovery.lisp`, `enr.lisp`, `node-table.lisp`),
`src/protocol/eth-wire/` (`messages.lisp`, `fork-id.lisp`),
`src/networking/eth-sync/` (`peer.lisp`, `pump.lisp`, `fetch.lisp`, `serve.lisp`,
`sync.lisp`, `backfill.lisp`, `gossip.lisp`, `node.lisp`, `listener.lisp`),
`src/foundation/snappy.lisp`, `src/foundation/rlp.lisp`, and the peering half of
`src/app/cli/devnet/` (`peer-manager.lisp`, `peer-table.lisp`,
`dial-schedule.lisp`, `peer-sync.lisp`, `background.lisp`).

Theirs: geth `p2p/` (`server.go`, `dial.go`, `peer.go`, `transport.go`,
`rlpx/rlpx.go`, `discover/v4_udp.go`, `discover/table.go`), `rlp/decode.go`,
`eth/protocols/eth/` (`protocol.go`, `handshake.go`, `handler.go`, `peer.go`,
`discovery.go`), `eth/protocols/snap/protocol.go`, `eth/downloader/`,
`eth/handler.go`, `node/defaults.go`; Nethermind `Nethermind.Network/`
(`Rlpx/`, `P2P/`, `Config/NetworkConfig.cs`, `DefaultP2PCapabilityResolver.cs`,
`SnapP2PCapabilityResolver.cs`), `Nethermind.Merge.Plugin/`
`MergeP2PCapabilityResolver.cs`, `Nethermind.Network.Stats/`,
`Nethermind.Synchronization/`.

### Executed versus source-read

The warm image was available for the first part of this audit and was stopped by
another session partway through. Claims below are source-read unless marked
otherwise. The following were **executed** in the warm image and outrank any
source reading:

- `SB-KERNEL::CONTROL-STACK-EXHAUSTED` is a `STORAGE-CONDITION` and a
  `SERIOUS-CONDITION`, and is **not** an `ERROR`. Confirmed by inspecting its
  class precedence list. This is the fact NET-01 turns on.
- The RLP depth crash itself was executed by the audit requester, not by this
  audit: depth 20000 (59,791 bytes of input) exhausts the control stack; depth
  1000 decodes fine. Attributed to that verification throughout.
- The byte cost of a nested-list payload: depth 20000 costs 59,788 bytes, depth
  21700 costs 64,888 bytes. This is what establishes that the crash fits inside
  the RLPx auth packet's 65,535-byte ceiling (NET-01).
- `+ecies-overhead+` evaluates to 113, giving 65,422 bytes of attacker-chosen
  plaintext inside a maximal auth packet.
- `snappy-compress` emits literal runs only (NET-23).
- No symbol matching `discv5` or a `snap` capability exists in the image
  (`apropos`), consistent with the source (NET-03, NET-08).

One item that a small eval would have settled is left source-read because the
image went away: the message-id offsets `rlpx-negotiate-capabilities` assigns
against geth's and Nethermind's advertised version sets (NET-11). The reasoning
there is from reading a short pure function, and the finding says so.

No connection was opened to any public node.

## Executive summary

The eight gaps that matter most, ordered by how directly they block joining and
following a real network — except the first, which is listed first because it is
the only one a stranger can use to kill the process.

1. **An unauthenticated stranger can crash the whole node with one 64 KB TCP
   packet** (NET-01). `rlp-decode` recurses per nesting level with no depth
   limit, and the first thing the RLPx recipient handshake does with a decrypted
   auth body is `rlp-decode` it — before any authentication, before Hello, before
   the fork-id check. The resulting `CONTROL-STACK-EXHAUSTED` is a
   `storage-condition`, so the session thread's `handler-case (error ...)` does
   not catch it, and under `sbcl --script` an unhandled condition in any thread
   exits the entire process. Fix by adding a depth limit to `rlp-decode` and a
   `storage-condition` guard on every session thread.
2. **There is no `snap` capability at all** (NET-03), so there is no way to
   acquire state other than executing every block from genesis. Combined with the
   state-trie audit's findings that the key-value engine is a RAM-resident hash
   table (STORE-14, STORE-19) and that there is no trie to write ranges into
   (STORE-06), initial sync of any public network is not merely slow but
   impossible; snap sync is the prerequisite that makes it feasible at all.
3. **The block download driver is one peer, one request in flight, sequential,
   and capped at 2048 blocks per session** (NET-04). There is no skeleton or
   beacon header chain, no pivot, no state healing, no parallel body fetch, and no
   receipt download at all. At 192 headers plus 192 bodies per round trip against
   a single peer, mainnet is out of reach by orders of magnitude.
4. **Nothing we advertise through discovery is dialable** (NET-05). The crawl
   pings bootnodes from an ephemeral UDP socket and hardcodes its `from` endpoint
   to `127.0.0.1`; geth learns a peer's TCP port from exactly that claimed field
   (`p2p/discover/v4_udp.go:701`). Every node we bond with therefore records a
   wrong TCP port and a dead UDP port for us, so we can dial out but no one can
   ever dial in through discovery.
5. **No message has a size cap and no decoder has an item-count cap** (NET-02,
   NET-17). geth caps base-protocol messages at 2 KB and `eth` messages at 10 MB,
   and caps transaction announcements at 5000; we accept any frame up to the 24-bit
   RLPx maximum of 16 MB and decode however many items it contains. This is both
   the vehicle for NET-01 past the handshake and an independent memory-exhaustion
   surface.
6. **We can serve receipts but never consume them** (NET-09). `encode-eth-receipts`
   exists; there is no `decode-eth-receipts`. A receipt-fetching sync mode cannot
   be built on the current wire layer without adding the decoder first.
7. **A node is recorded as bonded on the strength of an unsolicited Ping**
   (NET-06), with the UDP and TCP ports taken from the packet's claimed `from`
   field, and is then handed out in Neighbors. geth requires a pong it received
   itself before a node is `isValidatedLive`, refuses to relay LAN addresses to
   internet peers, and refuses inbound adds while the table initializes. Ours is a
   table-poisoning and traffic-reflection vector.
8. **The routing table never forgets anything** (NET-07). `discv4-table-note-failure`
   and `discv4-table-remove` are defined and exported but have no caller anywhere
   in `src/`, and there is no refresh or revalidation loop, so the table only
   accumulates and dead entries are served to other nodes forever.

## Findings

### NET-01 — `rlp-decode` has no depth limit, and the crash kills the process

**Verdict:** DIVERGENT (both references bound this; we do not).
**Severity:** remote-DoS.

**Ours.** `rlp-decode` (`src/foundation/rlp.lisp:72`) and `decode-list-payload`
(`src/foundation/rlp.lisp:58`) are mutually recursive with one Lisp frame per
nesting level and no depth argument, limit, or counter. The audit requester
verified in the warm image that a nested-list payload of depth 20000 — 59,791
bytes of input — exhausts the control stack and signals
`SB-KERNEL::CONTROL-STACK-EXHAUSTED`, and that depth 1000 decodes fine.

Reachability, traced for this audit:

- **Pre-authentication.** `rlpx-read-handshake-packet`
  (`src/protocol/p2p/connection.lisp:18-22`) reads a 2-byte big-endian length and
  then that many bytes, so a handshake packet may be up to 65,535 bytes with no
  further check. `rlpx-open-auth` (`src/protocol/p2p/handshake.lisp:59-69`) ECIES-
  decrypts the body and `rlpx-decode-auth-body`
  (`src/protocol/p2p/handshake.lisp:30`) calls `rlp-decode` on the plaintext at
  line 37. `+ecies-overhead+` is 113 (executed), so up to 65,422 bytes of
  attacker-chosen plaintext reach `rlp-decode`. Depth 21700 costs 64,888 bytes
  (executed), which fits. ECIES encrypts to *our* static public key, which is our
  node id and is public by construction, so producing a well-formed auth packet
  requires no secret and no prior relationship: **the attacker only needs to know
  our enode**.
- **Post-handshake, pre-Hello.** `decode-devp2p-hello`
  (`src/protocol/p2p/protocol.lisp:66-69`) calls `rlp-decode` on the Hello body,
  which arrives in an uncompressed frame of up to 16 MB (NET-02).
- **Post-Hello.** Every `eth` decoder calls `rlp-decode` on peer bytes
  (`src/protocol/eth-wire/messages.lisp` lines 92, 120, 176, 199, 245, 266, 286,
  311, 332, 348, 373), reached from `eth-peer-gossip-message`
  (`src/networking/eth-sync/gossip.lisp:160`) and `eth-peer-serve-message`
  (`src/networking/eth-sync/serve.lisp:196`).

Blast radius. The session thread's guard is
`handler-case ... (error (condition) ...)` at
`src/app/cli/devnet/peer-manager.lisp:264-276`. `CONTROL-STACK-EXHAUSTED` is a
`STORAGE-CONDITION` and not an `ERROR` (executed), so that clause does not run.
The comment immediately above it, at
`src/app/cli/devnet/peer-manager.lisp:254-263`, states the consequence in the
repo's own words: under `sbcl --script` — which is how the node runs, confirmed at
`tests/cli-script-serve-tests.lisp:35-37` — the disabled debugger turns an
unhandled condition in any thread into `(exit 1)` for the whole process. `rg
'storage-condition|serious-condition' src/` returns zero hits (requester's
verification), so no guard anywhere in the tree catches it. **The listener thread,
the accept loop, the RPC services, the Engine API and the chain store all die
with it.**

**Reference.** geth's RLP decoder keeps list nesting on a heap slice
(`rlp/decode.go:809-826`), not the call stack, and decoding is type-directed: the
auth body is decoded into a fixed `authMsgV4` struct via `s.Decode(msg)`
(`p2p/rlpx/rlpx.go:622-625`), so excess nesting produces an ordinary error rather
than recursion. `rlp.NewStream(r, inputLimit)` additionally bounds the input
(`rlp/decode.go:616`). Nethermind decodes each message with a per-message
serializer over `Rlp.ValueDecoderContext` that reads a fixed field shape; there is
no generic recursive decode of arbitrary nesting on the message path.

**Consequence.** One TCP connection and one ~64 KB packet, sent by anyone who
knows our enode and holds no credential, terminates the process. Restarting does
not help; the packet can be replayed.

### NET-02 — No per-protocol message size cap

**Verdict:** MISSING.
**Severity:** remote-DoS.

**Ours.** `rlpx-read-frame-header` (`src/protocol/p2p/frame.lisp:152-170`) reads
the 24-bit frame size and returns it with no ceiling other than the 24 bits
themselves, and `rlpx-read-frame-from-stream`
(`src/protocol/p2p/connection.lisp:33-39`) allocates and reads that many bytes.
`rlpx-read-message` (`src/protocol/p2p/protocol.lisp:126-129`) applies no cap
either before or after Snappy. There is no equivalent of a base-protocol cap: a
Hello, Disconnect, Ping or Pong may be 16 MB.

**Reference.** geth caps base-protocol messages at
`baseProtocolMaxMsgSize = 2 * 1024` (`p2p/peer.go:44`), enforced on the Hello read
at `p2p/transport.go:159`, and caps `eth` and `snap` messages at
`maxMessageSize = 10 * 1024 * 1024` (`eth/protocols/eth/protocol.go:52`,
`eth/protocols/snap/protocol.go:48`), enforced at
`eth/protocols/eth/handler.go:262` and `eth/protocols/eth/handshake.go:105`.
Nethermind rejects anything over `SnappyParameters.MaxSnappyLength` (16 MiB) both
before and after decompression, and additionally rejects a compressed payload
larger than a quarter of that as a compression bomb
(`Nethermind.Network/P2P/ProtocolHandlers/ZeroNettyP2PHandler.cs:37,47,53`).

**Non-gap worth recording.** Our Snappy decoder does check the declared
uncompressed length against `+snappy-max-decoded-length+` (16 MB) *before*
allocating the output buffer (`src/foundation/snappy.lisp:33-37`), which is the
same ordering geth uses (`snappy.DecodedLen` then `growslice`,
`p2p/rlpx/rlpx.go:149-156`). The decompression bomb is handled; the message size
is not.

**Consequence.** A peer costs us a 16 MB allocation per message at will, and a
60 KB nested-RLP body passes unremarked at every layer — which is what makes
NET-01 reachable from Hello and from every `eth` message, not only from the
handshake.

### NET-03 — No `snap` capability

**Verdict:** MISSING.
**Severity:** blocks-real-network-use.

**Ours.** `+devp2p-capability-message-counts+`
(`src/protocol/p2p/session.lisp:16-17`) contains `("eth" . 17)` and its docstring
says "Only eth is implemented". `rg '"snap"' src` returns nothing, and the warm
image had no matching symbol (executed).

**Reference.** geth implements `snap/1` and `snap/2` with eight and ten messages
(`eth/protocols/snap/protocol.go:41,48`) and gates `snap/2` behind a feature flag;
`GetAccountRange`/`AccountRange`, `GetStorageRanges`/`StorageRanges`,
`GetByteCodes`/`ByteCodes`, `GetTrieNodes`/`TrieNodes` are `0x00`–`0x07`
(`eth/protocols/snap/protocol.go:51-58`). Nethermind advertises `snap/1`
conditionally (`Nethermind.Network/SnapP2PCapabilityResolver.cs:24,46`) and has a
whole `Nethermind.Synchronization/SnapSync` subsystem.

**Consequence.** State can only be obtained by executing every block from
genesis. This compounds with STORE-14 and STORE-19 from the state-trie audit (the
key-value engine is RAM-resident and is replayed in full at startup, so mainnet
state cannot be held at all) and with STORE-06 (there is no trie, so there is no
node store to write downloaded ranges into). Implementing `snap` is therefore
blocked on that area, not merely sequenced after it.

### NET-04 — The sync driver is single-peer, sequential, and capped

**Verdict:** DIVERGENT.
**Severity:** blocks-real-network-use.

**Ours.** `eth-sync-download-blocks` (`src/networking/eth-sync/sync.lisp:26-67`)
loops: request up to `+eth-sync-default-batch-size+` (192,
`src/networking/eth-sync/sync.lisp:11`) headers from one peer by number, request
their bodies from the same peer, assemble, import each, advance. One request is in
flight at a time by design — `src/networking/eth-sync/pump.lisp` documents "one
request in flight per peer" as a contract — and there is no second peer, no queue,
no pipelining. `+devnet-session-catchup-block-limit+` bounds one session's initial
catch-up to 2048 blocks (`src/app/cli/devnet/peer-sync.lisp:223`), and
`devnet-node-claim-sync` (`:237`) lets only one session sync at a time — the
latter with a documented rationale at `:240-245` (peers are interchangeable, so a
second parallel catch-up re-downloads and re-executes what the first is importing
while doubling store-guard contention). That reasoning is sound for a single-peer
downloader; it is the *downloader* that needs replacing, not the claim.
`backfill.lisp`
adds a backwards walk by parent hash for gaps
(`+eth-backfill-batch-size+` 192, `+eth-backfill-max-headers+` 100000,
`src/networking/eth-sync/backfill.lisp:24,27`). There is no pivot selection, no
state download or healing, no receipt download, no skeleton, and no mid-sync
reorg handling beyond whatever the import callback rejects.

**Reference.** geth has full and snap modes managed by `syncModer`
(`eth/downloader/syncmode.go:31-60`), a beacon-driven skeleton header chain
(`eth/downloader/skeleton.go`, `beaconsync.go`), concurrent body and receipt
fetchers (`eth/downloader/fetchers_concurrent_bodies.go`,
`fetchers_concurrent_receipts.go`), a delivery queue that validates and reorders
across peers (`eth/downloader/queue.go`), and separate state sync
(`eth/downloader/statesync.go`). Nethermind has `FastSync`, `SnapSync`,
`FastBlocks`, `StateSync`, `ParallelSync` and an `IPivot`
(`Nethermind.Synchronization/`).

**Consequence.** Throughput is one round trip per 192 blocks against one peer,
with a 2048-block ceiling per session. Progress on a public network would be
measured in blocks per second at best, against chains of 10^7 blocks. Sync
progress is also not reported: see the RPC audit's finding that `eth_syncing`
always answers `false`.

### NET-05 — Discovery advertises an endpoint nobody can reach

**Verdict:** DIVERGENT.
**Severity:** blocks-real-network-use.

**Ours.** The crawl worker calls `discv4-lookup`
(`src/protocol/p2p/discovery.lisp:228-253`) without a `local-port`, so it defaults
to 0 and `discv4-make-socket` (`src/protocol/p2p/discovery.lisp:48`) binds an
ephemeral port. The `from` endpoint in the Ping it sends is built as
`(discv4-endpoint-for-host "127.0.0.1" local-udp local-udp)`
(`src/protocol/p2p/discovery.lisp:113` for the bond-and-ask path,
`:255` for the lookup path) — a loopback IP and, for the TCP port, the ephemeral
UDP port of a socket that closes when the crawl ends. The responder is a
*different* socket bound to the real p2p port
(`src/app/cli/devnet/background.lisp`, `devnet-start-discovery-server-thread`),
so the two never share an endpoint.

**Reference.** geth's `handlePing` builds the peer's record as
`enode.NewV4(h.senderKey, fromIP, int(req.From.TCP), int(from.Port()))`
(`p2p/discover/v4_udp.go:701`): the IP is the observed source, the UDP port is the
observed source port, and **the TCP port is taken from the claimed `From.TCP`
field**. It also feeds `req.To` into the endpoint predictor
(`p2p/discover/v4_udp.go:712-713`).

**Consequence.** Every node that bonds with us records a TCP port that is not our
listener and a UDP port that dies with the crawl. We are outbound-only in
practice: dialing works, being dialed through discovery cannot. Note that this is
not the same defect as advertising a private IP — geth ignores the claimed IP —
but the claimed TCP port is load-bearing and ours is wrong.

### NET-06 — A Ping alone marks a node bonded, and bonded nodes are relayed

**Verdict:** DIVERGENT.
**Severity:** correctness (with a reflection/poisoning DoS consequence).

**Ours.** `discv4-serve-ping` (`src/protocol/p2p/discovery.lisp:520-539`) records
the sender with `:bonded t` using the *claimed* `from` UDP and TCP ports, on
receipt of the Ping, before any Pong of ours has been answered. The docstring
("it answered from the address it claimed") describes an endpoint proof that has
not happened: a Ping is unsolicited. `discv4-serve-find-node` then returns bonded
entries to any bonded asker. We never ping back to establish the bond ourselves.

**Reference.** geth adds a ping sender via `addInboundNode`
(`p2p/discover/table.go:381`), which does not set `isValidatedLive`, and whose
doc comment states the reason explicitly: "if the table is still initializing the
node is not added. This prevents an attack where the table could be filled by
just sending ping repeatedly" (`p2p/discover/table.go:373-379`). `handleFindnode`
asks for live nodes first (`preferLive`, `p2p/discover/v4_udp.go:758-759`), and
`findnodeByID` returns only `isValidatedLive` entries when any exist
(`p2p/discover/table.go:301-312`). Liveness is set from a pong geth *received*,
recorded in `db.LastPongReceived`. geth also filters each relayed address through
`netutil.CheckRelayAddr` before putting it in a Neighbors reply
(`p2p/discover/v4_udp.go:766`).

**Consequence.** An attacker with a freshly generated key and a spoofed source IP
gets an arbitrary (victim IP, attacker-chosen ports) entry marked bonded in our
table, which we then advertise to everyone who asks. We have no relay-address
check, so we will relay loopback and private addresses to internet peers, and no
initialization guard, so the table can be filled with Pings.

### NET-07 — The routing table never evicts, revalidates, or refreshes

**Verdict:** MISSING.
**Severity:** completeness / performance.

**Ours.** `discv4-table-note-failure` (`src/protocol/p2p/node-table.lisp:137`) and
`discv4-table-remove` (`:149`) exist and are exported
(`src/packages/p2p.lisp:99-100`, `src/packages/facade.lisp:474-475`) but have no
caller anywhere in `src/` — only the definitions and the exports match. There is
no periodic bucket revalidation and no table refresh loop; the crawl re-runs from
the bootnodes each cycle (`+devnet-discovery-crawl-seconds+` 8,
`src/app/cli/devnet/background.lisp:71`) and only ever adds. Bond lifetime is 12
hours (`+discv4-bond-lifetime-seconds+` 43200,
`src/protocol/p2p/node-table.lisp:34`), so an entry stays servable for that long
regardless of whether the node still exists.

**Reference.** geth runs a table loop with revalidation and refresh, tracks
per-node liveness and failures (`p2p/discover/table.go`, `trackRequest` at
`:391`), and keeps a replacements list per bucket so a dead entry is displaced
rather than kept.

**Consequence.** Our Neighbors replies degrade toward a list of nodes that were
reachable once. Combined with NET-06 there is no mechanism at all by which a bad
entry leaves the table.

### NET-08 — discv5 is absent

**Verdict:** MISSING.
**Severity:** interop / completeness.

**Ours.** `rg -i 'discv5|v5wire|talkreq' src` returns nothing; the warm image had
no matching symbol (executed). Only discv4 exists
(`src/protocol/p2p/discv4.lisp`, `discovery.lisp`).

**Reference.** geth runs both, with v5 in `p2p/discover/v5_udp.go` and the
`p2p/discover/v5wire` codec. Nethermind has `Nethermind.Network.Discovery` with
v5 support.

**Consequence.** We cannot participate in v5-only topologies and cannot be found
by consensus-layer-adjacent tooling that speaks only v5. On networks where v4 is
still widely served this is a completeness gap rather than a blocker, which is why
it ranks below NET-05.

### NET-09 — `Receipts` has an encoder but no decoder

**Verdict:** MISSING.
**Severity:** completeness (blocks receipt sync).

**Ours.** `encode-eth-receipts` is defined at
`src/protocol/eth-wire/messages.lisp:409`; there is no `decode-eth-receipts` — the
full list of codecs in that file is 25 functions and the receipts decoder is not
among them. `eth-serve-message` answers `GetReceipts`
(`src/networking/eth-sync/serve.lisp:210-214`) with
`+eth-max-receipts-serve+` 1024, so we serve them correctly; nothing consumes an
inbound `Receipts`, and no code sends `GetReceipts` outside tests.

**Reference.** geth decodes `ReceiptsMsg` per protocol version (eth/69 changed the
encoding to drop the bloom) and delivers them through
`eth/downloader/fetchers_concurrent_receipts.go`. Nethermind has a
`Nethermind.Synchronization/Receipts` feed.

**Consequence.** A receipts-downloading sync mode cannot be built on the current
wire layer. This is a prerequisite for any fast/snap-style sync that skips
re-execution.

### NET-10 — `BlockRangeUpdate` is neither sent nor handled, and the peer's range is not validated

**Verdict:** MISSING (send and handle); DIVERGENT (validation).
**Severity:** interop.

**Ours.** `+eth-message-block-range-update+` is defined as `#x11`
(`src/protocol/eth-wire/messages.lisp:34`) but has no encoder, no decoder, and no
dispatch arm; an inbound `0x11` falls through `eth-peer-handle-message`
(`src/networking/eth-sync/fetch.lisp:18-23`) and is silently dropped, since both
`eth-peer-serve-message` and `eth-peer-gossip-message` return `NIL` for an
unrecognised id. We decode the eth/69 Status block range correctly
(`decode-eth-status-69`, `src/protocol/eth-wire/messages.lisp:118-130`) but
`eth-validate-peer-status` (`src/networking/eth-sync/peer.lisp:203-225`) checks
version, network id, genesis and fork id only — not the range.

**Reference.** geth's `readStatus` validates the initial range with
`initRange.Validate()`, rejecting `earliest > latest` and a zero latest hash
(`eth/protocols/eth/handshake.go:84-91`, `:155-163`), stores it, and updates it
from `BlockRangeUpdateMsg` thereafter. An unknown message code is an error for
geth, not something to ignore.

**Consequence.** Peers learn our range once, at handshake, and it goes stale.
Being lenient about the unknown code is safe for us; not validating theirs means
we will treat a peer claiming an impossible range as normal. Two mitigating
facts: our `encode-eth-status-69` falls back to the genesis hash when the latest
hash is missing (`src/protocol/eth-wire/messages.lisp:115-116`), so we never send
the zero hash geth rejects, and we do set the negotiated version into the Status
we send (`src/networking/eth-sync/peer.lisp:237`), which geth also checks
(`eth/protocols/eth/handshake.go:74-76`).

### NET-11 — Our `eth` message-id block length is 17 where geth's is 18

**Verdict:** DIVERGENT (latent).
**Severity:** interop (latent — no observable effect today).

**Ours.** `+devp2p-capability-message-counts+` maps `"eth"` to 17
(`src/protocol/p2p/session.lisp:16-17`), and
`rlpx-negotiate-capabilities` (`:40-69`) lays out shared capabilities in
name order starting at offset 16, advancing by that count.

**Reference.** geth's `protocolLengths` is `{ETH69: 18, ETH70: 18, ETH71: 20,
ETH72: 22}` (`eth/protocols/eth/protocol.go:49`) — eth/69 occupies `0x00`–`0x11`,
which is 18 ids, because `BlockRangeUpdateMsg` is `0x11`
(`eth/protocols/eth/protocol.go:70`).

**Consequence.** None today: `eth` is our only capability, so the shared set has
one entry and both sides compute offset 16 regardless of the count. The moment a
second capability is negotiated — `snap` sorts after `eth` — we would place it at
33 while geth places it at 34, and every message on both subprotocols would be
misrouted. This is a trap laid for whoever implements NET-03. (Source-read: the
image was down when this was reached, and the negotiation function is short and
pure enough to read with confidence, but it was not executed.)

### NET-12 — We speak eth/68 and eth/69; geth speaks 69 through 72 and has dropped 68

**Verdict:** MISSING (70, 71, 72).
**Severity:** interop / completeness.

**Ours.** `+eth-supported-protocol-versions+` is `'(69 68)`
(`src/protocol/eth-wire/messages.lisp:15`).

**Reference.** geth's `ProtocolVersions` is `{ETH72, ETH71, ETH70, ETH69}`
(`eth/protocols/eth/protocol.go:45`) — eth/68 is gone. eth/71 adds
`GetBlockAccessLists`/`BlockAccessLists` (`0x12`/`0x13`) and eth/72 adds
`GetCells`/`Cells` (`0x14`/`0x15`) (`eth/protocols/eth/protocol.go:71-74`).
Nethermind advertises `eth/68` always
(`Nethermind.Network/DefaultP2PCapabilityResolver.cs:22`) plus `eth/69`, `eth/70`
and `eth/71` once post-merge
(`Nethermind.Merge.Plugin/MergeP2PCapabilityResolver.cs:37-39`), and has handler
directories through `V71`.

**Consequence.** Negotiation with geth 1.17.6-unstable settles on eth/69, the
lowest it offers and the highest we offer, so we still interoperate — but with no
headroom. When geth drops eth/69 we lose the ability to peer with it entirely.
Our eth/68 support is only useful against Nethermind and older clients.

The message-by-message position for eth/69, the newest version we support:

| Code | Message | Sender | Handler |
| --- | --- | --- | --- |
| `0x00` | Status | yes (`messages.lisp:103`) | yes (`peer.lisp:240`) |
| `0x01` | NewBlockHashes | no | no |
| `0x02` | Transactions | yes (`gossip.lisp:45`) | yes (`gossip.lisp:165`) |
| `0x03` | GetBlockHeaders | yes (`fetch.lisp:73`) | yes (`serve.lisp:196`) |
| `0x04` | BlockHeaders | yes (`serve.lisp:198`) | yes (`fetch.lisp:80`) |
| `0x05` | GetBlockBodies | yes (`fetch.lisp:86`) | yes (`serve.lisp:203`) |
| `0x06` | BlockBodies | yes (`serve.lisp:206`) | yes (`fetch.lisp:88`) |
| `0x07` | NewBlock | no | no |
| `0x08` | NewPooledTransactionHashes | yes (`gossip.lisp:53`) | yes (`gossip.lisp:168`) |
| `0x09` | GetPooledTransactions | yes (`gossip.lisp:153`) | yes (`gossip.lisp:176`) |
| `0x0a` | PooledTransactions | yes (`gossip.lisp:179`) | yes (`gossip.lisp:184`) |
| `0x0f` | GetReceipts | codec only | yes (`serve.lisp:210`) |
| `0x10` | Receipts | yes (`serve.lisp:214`) | **no decoder** (NET-09) |
| `0x11` | BlockRangeUpdate | **no** | **no** (NET-10) |

`0x01` and `0x07` are correctly absent for eth/69, which removed them; they are a
real gap only for the eth/68 we also advertise, and post-merge no one sends them.
`0x0f` is listed as codec-only because `encode-eth-get-receipts` exists
(`messages.lisp:364`) but nothing in production calls it.

### NET-13 — Transaction gossip broadcasts everything to everyone, and re-sends to the sender

**Verdict:** DIVERGENT.
**Severity:** performance / interop.

**Ours.** `devnet-peer-pending-broadcast`
(`src/app/cli/devnet/peer-sync.lisp:84-119`) polls the pool under the store guard,
diffs against a per-session `known` table, and the session loop pushes the result
through `eth-peer-broadcast-transactions`
(`src/networking/eth-sync/gossip.lisp:38-47`), which sends every qualifying
transaction **in full to every peer** with no size threshold.
`eth-peer-announce-transactions` (`:49-55`) exists and is correct but has no
production caller — only tests — so we never announce by hash. The `known` table
is populated only by what we send; nothing marks a transaction known when a peer
sends it to us (`eth-accept-transactions`, `:59-72`, records nothing per-peer), so
the next poll re-broadcasts it straight back to the peer we got it from.

**Reference.** geth's `BroadcastTransactions`
(`eth/handler.go:533-568`) skips any peer for which `KnownTransaction` is true
(`:548`), sends the full transaction only to a deterministic subset chosen per
sender (`choice.choosePeers`, `:544`), announces by hash to everyone else
(`:556`), and never broadcasts a blob transaction or one larger than
`txMaxBroadcastSize = 4096` (`eth/handler.go:63`, `:536-539`). Receipt-side
knowledge is tracked in `knownTxs` (`eth/protocols/eth/peer.go:72`,
`markTransaction` at `:152`). Nethermind caps one `Transactions` message at
`TransactionsMessage.MaxPacketSize = 102400`
(`Nethermind.Network/P2P/Subprotocols/Eth/V62/Messages/TransactionsMessage.cs:14`)
and splits accordingly
(`Nethermind.Network/P2P/Subprotocols/Eth/V68/Eth68ProtocolHandler.cs:153-196`).

**Documented, deliberate parts.** Blob transactions are excluded from every
announcement, broadcast and reply, with the reason written out at
`src/networking/eth-sync/gossip.lisp:15-21` — that matches geth's behaviour and is
not a gap. The poll-and-diff design and the reason it does not consume the
txpool's dirty-key set are documented at
`src/app/cli/devnet/peer-sync.lisp:91-95`, and the single-writer rule that forces
the closure shape at `:100-102`. Those are honest, reasoned choices.

**Consequence.** Bandwidth scales as transactions × peers with no hash-announce
relief, large transactions are pushed whole to every peer, and each transaction we
receive is echoed to its sender. On a network with real transaction volume this
is the behaviour peers throttle or drop for.

### NET-14 — No block propagation and no fetcher

**Verdict:** MISSING.
**Severity:** completeness.

**Ours.** No `NewBlock` or `NewBlockHashes` codec exists
(`src/protocol/eth-wire/messages.lisp` has no constant for `0x07` and none for
handling `0x01`), and there is nothing resembling geth's `eth/fetcher`: blocks
arrive only by the pull-based download in `sync.lisp` and `backfill.lisp`.

**Reference.** geth keeps `eth/fetcher/block_fetcher.go` for the announcement-driven
path and `eth/fetcher/tx_fetcher.go` for announced transactions.

**Consequence.** Correct for a post-merge network, where blocks arrive through the
Engine API and `NewBlock` is not used — so this is a low-severity completeness gap
rather than a defect. It does mean we contribute nothing to block propagation and
have no low-latency path to a head we did not get from our consensus client. Our
announced-transaction fetcher does exist
(`eth-peer-fetch-announced-transactions`, `src/networking/eth-sync/fetch.lisp`,
with `+eth-max-announced-transaction-hashes+` 4096 bounding the queue,
`src/networking/eth-sync/gossip.lisp:27`), and fetches in announcement order,
ignoring the type and size columns — documented at `gossip.lisp:171-173`.

### NET-15 — No inbound IP throttle, no netrestrict, no IP-diversity limits

**Verdict:** MISSING.
**Severity:** remote-DoS / completeness.

**Ours.** The accept loop (`src/app/cli/devnet/peer-manager.lisp:230-291`) checks
one thing before spawning a session thread: whether a slot is free
(`devnet-peer-table-slot-verdict`, `src/app/cli/devnet/peer-table.lisp:75-87`).
There is no per-IP history, no subnet accounting, and no address filter; `rg -in
'subnet|/24|ip-limit|bogon|is-lan' src` returns nothing. `--nat MODE` and
`--netrestrict CIDRS` are accepted as value-taking CLI options
(`src/app/cli/options/definitions.lisp:18,20`) and appear in the usage string
(`src/app/cli/output.lisp:5`), but nothing consumes either.

**Reference.** geth's `checkInboundConn` (`p2p/server.go:852-868`) rejects
addresses outside `NetRestrict`, and rejects any non-LAN address that appears in
`inboundHistory` within `inboundThrottleTime = 30 * time.Second`
(`p2p/server.go:53`). `netutil` additionally enforces per-subnet limits on the
discovery table and `CheckRelayAddr` on relayed addresses.

**Consequence.** One host can occupy every peer slot and force a fresh RLPx
handshake — including the ECIES scalar multiplication — as fast as it can open
connections. Two CLI flags silently do nothing, which is worse than rejecting
them, since an operator who passes `--netrestrict` will believe it applied.

### NET-16 — No peer scoring, and misbehaviour costs only the current session

**Verdict:** MISSING.
**Severity:** completeness.

**Ours.** A session that errors is logged and its socket closed
(`src/app/cli/devnet/peer-manager.lisp:272-276`); nothing records that this peer
misbehaved. Of the twelve devp2p disconnect reasons defined
(`src/protocol/p2p/protocol.lisp:21-33`) only four are ever sent — `:self`,
`:already-connected`, `:too-many-peers` at
`src/app/cli/devnet/peer-manager.lisp:42-44` and `requested` at
`src/app/cli/devnet/peer-sync.lisp:220`. `+devp2p-disconnect-subprotocol-error+`
and `useless-peer` are never used. The only memory is the dial registry's failure
backoff (`+devnet-dial-backoff-ceiling-seconds+` 300 with at most four doublings
and `+devnet-dial-dynamic-forget-failures+` 3,
`src/app/cli/devnet/dial-schedule.lisp:41,45,61`), which applies to dials we
initiate, not to peers that dial us.

**Reference.** geth drops peers on protocol violations with a typed
`p2p.DiscProtocolError` and the downloader/fetcher call `dropPeer` on bad
deliveries. Nethermind maintains a full reputation subsystem
(`Nethermind.Network.Stats/NodeStatsManager.cs`, `NodeStatsLight.cs`,
`StatsParameters.cs`) and per-client sync limits
(`Nethermind.Network.Stats/SyncLimits/`).

**Consequence.** A peer that sends garbage reconnects immediately and is treated
as new. A peer that is merely useless holds a slot until it goes idle.

### NET-17 — Decoders have no item-count caps

**Verdict:** MISSING.
**Severity:** remote-DoS.

**Ours.** `decode-eth-transactions` (`src/protocol/eth-wire/messages.lisp:284`)
and `decode-eth-new-pooled-transaction-hashes` (`:306`) decode however many items
the message contains. The announce queue is bounded after the fact by
`+eth-max-announced-transaction-hashes+` 4096
(`src/networking/eth-sync/gossip.lisp:27`), but the decode has already allocated
the full list. Combined with NET-02's 16 MB frame ceiling this is a large
multiplier: a 16 MB message of minimal RLP items decodes to millions of objects.

Our *serving* limits, by contrast, are present and are at or below geth's:
`+eth-max-headers-serve+` 1024 and `+eth-max-receipts-serve+` 1024 equal geth's
`maxHeadersServe` and `maxReceiptsServe` (`eth/protocols/eth/handler.go:45,56`),
`+eth-soft-response-limit+` 2 MB equals `softResponseLimit` (`:37`), and
`+eth-max-bodies-serve+` 256 is stricter than geth's `maxBodiesServe` of 1024
(`:50`) — stricter is safe here, and it matches Nethermind's own 256
(`Nethermind.Network.Stats/SyncLimits/NethermindSyncLimits.cs:9`).
`+eth-max-pooled-transactions-serve+` 256
(`src/networking/eth-sync/gossip.lisp:23`) is a bound geth does not have on the
serving side at all — geth's `GetPooledTransactions` handler stops only at
`softResponseLimit` (`eth/protocols/eth/handlers.go:624`) — so the docstring's
attribution to "go-ethereum's soft limit on the asking side" is about the
requesting side, not the answer. `+eth-max-skipped-messages+` 256
(`src/networking/eth-sync/fetch.lisp:40`) bounds how much unrelated work a peer
can make us do while we wait for a reply, and its docstring reasons about exactly
that.

**Reference.** geth caps `maxTransactionAnnouncements = 5000`
(`eth/protocols/eth/protocol.go:55`) on top of the 10 MB message cap.
Nethermind's `TransactionsMessage.MaxPacketSize` is 102400
(`.../Eth/V62/Messages/TransactionsMessage.cs:14`).

**Consequence.** Memory exhaustion driven by one peer, with no per-peer accounting
to attribute it.

### NET-18 — Hash-origin header queries with a skip walk the chain one parent at a time

**Verdict:** DIVERGENT.
**Severity:** performance (remote-DoS-adjacent).

**Ours.** `eth-serve-ancestor-hash` (`src/networking/eth-sync/serve.lisp`) walks
backwards by parent hash one block at a time to satisfy a skip. A
`GetBlockHeaders` with a hash origin, `amount` up to 1024 and a large `skip`
therefore costs `amount × skip` store lookups, all driven by one small request.

**Reference.** geth's header handler shortcuts through the canonical number index
when the walk stays on the canonical chain, so the cost is one lookup per returned
header rather than one per skipped block
(`eth/protocols/eth/handlers.go`, the `GetBlockHeaders` path).

**Consequence.** A request of a few dozen bytes buys a peer up to ~10^6 store
lookups. Our store is RAM-resident today (see STORE-14), so this is CPU rather
than I/O, which is why it is rated performance rather than remote-DoS — it becomes
the latter as soon as the store is on disk.

### NET-19 — Downloaded bodies are not matched to their headers at the sync layer

**Verdict:** DIVERGENT.
**Severity:** performance / robustness (not correctness — see below).

**Ours.** `eth-sync-download-blocks`
(`src/networking/eth-sync/sync.lisp:48-67`) checks only that the body *count*
equals the header count (`:55-57`) and pairs them positionally. It does not check
that the returned headers begin at the requested number, are contiguous, or chain
by parent hash, and `eth-sync-assemble-block` deliberately trusts the header's
committed roots rather than recomputing them, with the reason stated at
`src/networking/eth-sync/sync.lisp:16-18`. `next` then advances by the number of
headers returned (`:64`), which assumes the peer answered the question asked.

**Not a correctness gap, and this was checked.** The import path does recompute
the commitments: `validate-block-body-commitments-before-execution`
(`src/runtime/execution/block-body-validation.lisp:42`) compares the header's
transactions root, ommers hash and withdrawals root against the supplied body
(`:55-70`) and is called from `src/runtime/execution/block-execution.lisp:76`. A
mismatched body is rejected before execution. (The `:expected-block-hash` check in
`execute-and-commit-engine-payload`, `src/application/services/execution.lisp:174`,
is *not* what catches it: for an assembled block that hash is derived from the
same header, so the check is self-referential here.)

**Reference.** geth validates each body against the header before accepting the
delivery — `hashes.TransactionRoots[index] != header.TxHash`,
`UncleHashes`, and the withdrawals present/absent rule
(`eth/downloader/queue.go:569-588`) — and on failure drops that delivery and the
peer, keeping the download alive.

**Consequence.** A peer that returns wrong bodies, or headers from a different
range, ends our session with an error rather than costing itself one rejected
delivery. Sync is therefore fragile against a single misbehaving or merely
out-of-sync peer, and there is no retry against another peer because there is only
ever one (NET-04).

### NET-20 — Multi-frame (chunked) RLPx messages cannot be read

**Verdict:** MISSING.
**Severity:** interop (low).

**Ours.** `rlpx-read-frame-from-stream`
(`src/protocol/p2p/connection.lisp:33-39`) treats one frame as one whole message;
the header's chunked-frame fields (context id, total packet size) are neither
written nor read, and `+rlpx-header-data+`
(`src/protocol/p2p/frame.lisp:54`) is a fixed constant.

**Reference.** geth also reads only single frames (`p2p/rlpx/rlpx.go:162-179`), so
this is not a divergence from geth. Nethermind, however, *splits* outgoing packets
at `Frame.DefaultMaxFrameSize = BlockSize * 64` — 1024 bytes
(`Nethermind.Network/Rlpx/Frame.cs:16`,
`Nethermind.Network/Rlpx/ZeroPacketSplitter.cs:18-33`) — and only disables
splitting when it enables Snappy, which happens right after Hello
(`Nethermind.Network/P2P/Session.cs:143`).

**Consequence.** A Nethermind Hello larger than 1024 bytes would be split across
frames and would be unreadable by us. Hellos are ordinarily a few hundred bytes,
so this is latent; a peer with many capabilities or a long client id would trip
it.

### NET-21 — ENR carries no endpoint and a hardcoded sequence number

**Verdict:** DIVERGENT.
**Severity:** interop.

**Ours.** ENR encoding and decoding are otherwise good: `encode-enr`
(`src/protocol/p2p/enr.lisp:58-81`) sorts keys, sets `id`/`secp256k1`, signs
keccak of the content, and enforces the 300-byte cap; `decode-enr` (`:83-118`)
enforces the cap, rejects unsorted or duplicate keys, checks the identity scheme,
and verifies the signature. But the only entries we ever add are the chain
entries from `devnet-node-record-pairs`
(`src/app/cli/devnet/background.lisp:115-123`), which is the `eth` fork-id entry
alone — no `ip`, `tcp`, or `udp` — and the sequence number is the literal `1` at
every call site (`src/protocol/p2p/discovery.lisp:610`).

**Reference.** geth's `enode.LocalNode` maintains `ip`/`tcp`/`udp` in the record
and bumps `Seq` on every change; `StartENRUpdater`
(`eth/protocols/eth/discovery.go:41-58`) re-sets the `eth` entry on every chain
head event so the advertised fork id follows the head.

**Consequence.** A client that reads our record cannot derive an endpoint from it,
and a client that caches records by sequence number will never see an update,
because ours is always 1 — even though the fork-id value inside it changes. Note
that the *fork-id entry itself* is correct: see the non-gap below.

**Non-gap worth recording.** `eth-fork-id-enr-entry`
(`src/protocol/eth-wire/fork-id.lisp:61-69`) produces `[[fork_hash, fork_next]]`,
matching geth's `enrEntry` struct with its `rlp:"tail"` field
(`eth/protocols/eth/discovery.go:27-32`), and the docstring at
`src/protocol/eth-wire/fork-id.lisp:71-83` explains why the extra nesting level is
load-bearing. `eth-chain-context-record-compatible-p`, used by
`devnet-discovery-record-filter`
(`src/app/cli/devnet/background.lisp:125-139`), returns false when the entry is
absent, which is exactly geth's `NewNodeFilter` semantics
(`eth/protocols/eth/discovery.go:71-81`). The decision to turn filtering *off*
rather than reject everybody when our own chain context cannot be read is
documented at `background.lisp:132-134`, and the reason the fork id is read
without taking the store guard is documented at length at `background.lisp:81-93`.
This part of the recent fork-id filtering work is sound.

### NET-22 — No NAT traversal or port mapping

**Verdict:** MISSING.
**Severity:** completeness.

**Ours.** `rg -in 'upnp|pmp|natpmp|extip' src` returns nothing. `--nat` is parsed
and ignored (NET-15).

**Reference.** geth's `p2p/nat` supports UPnP, NAT-PMP, explicit external IP and
`any`, and the server maps its listen port.

**Consequence.** Behind a NAT we are outbound-only regardless of NET-05.

### NET-23 — Snappy compression emits literal runs only

**Verdict:** DIVERGENT (documented).
**Severity:** performance.

**Ours.** `snappy-compress` produces valid Snappy that any decoder accepts but
performs no back-reference matching, so payloads go out at essentially their
uncompressed size plus a varint. Verified in the warm image (executed). The
docstring at `src/foundation/snappy.lisp:5-8` states this plainly and says
correctness and interop came first — a documented limitation, not a bug.
Decompression is complete.

**Reference.** geth compresses with the full `golang/snappy` encoder
(`p2p/rlpx/rlpx.go`, write path).

**Consequence.** Our egress bandwidth is several times what a peer expects for the
same content. It costs us, not the network, and it is honest about it.

### NET-24 — Session policy constants are ours, not parity claims

**Verdict:** informational.
**Severity:** cosmetic.

Several of our constants happen to match geth exactly, several deliberately do
not, and `docs/reference-map.md` currently says no reference existed to compare
against. The table in the next section is the correction. The three exact matches
worth knowing about, because they should not be changed casually:
`+eth-pump-ping-interval-seconds+` 15 equals geth's `pingInterval`,
`+devnet-peer-handshake-timeout-seconds+` 5 equals geth's `handshakeTimeout` and
its `eth` handshake timeout, and `+devnet-dial-ratio+` 3 equals geth's
`defaultDialRatio`. `+devnet-dial-cooldown-seconds+` 35 equals geth's
`dialHistoryExpiration`, which is itself `inboundThrottleTime + 5s` — a coincidence
of value, since we have no inbound throttle at all (NET-15).

## Peering-constant parity table

Ours, geth 1.17.6-unstable (`38271784c2b31926563806da9a2e023b88f5e7a8`), and
Nethermind 1.40.0 (`e52dc19a56a46f58170a730822580774d403c838`). "No equivalent"
means the reference has no constant serving that purpose, not that it lacks the
behaviour.

| Purpose | Ours | geth | Nethermind |
| --- | --- | --- | --- |
| Peer limit (default) | 50 (`+devnet-default-max-peers+`, `devnet/peer-table.lisp:27`) | 50 (`node/defaults.go:74`) | 50 (`MaxActivePeers`, `Network/Config/NetworkConfig.cs:22`) |
| Dial ratio (outbound share) | 3 (`+devnet-dial-ratio+`, `devnet/dial-schedule.lisp:52`) | 3 (`defaultDialRatio`, `p2p/server.go:50`; applied `:557`) | no equivalent constant |
| Max concurrent dials | 8 (`+devnet-max-active-dials+`, `devnet/dial-schedule.lisp:48`) | 50 (`defaultMaxPendingPeers`, `p2p/server.go:49`; `dial.go:153`) | 20/sec (`MaxOutgoingConnectPerSec`, `NetworkConfig.cs:40`) |
| Dial timeout | 15s (`+eth-sync-dial-timeout-seconds+`, `eth-sync/node.lisp:13`) | 15s (`defaultDialTimeout`, `p2p/server.go:46`) | 2000ms (`ConnectTimeoutMs`, `NetworkConfig.cs:41`) |
| Redial cooldown / dial history | 35s (`+devnet-dial-cooldown-seconds+`, `devnet/dial-schedule.lisp:34`) | 35s (`dialHistoryExpiration = inboundThrottleTime + 5s`, `p2p/dial.go:43`) | no equivalent constant |
| Dial backoff ceiling | 300s, ≤4 doublings (`devnet/dial-schedule.lisp:41,45`) | no equivalent (geth relies on dial history) | no equivalent |
| Inbound per-IP throttle | **none** (NET-15) | 30s (`inboundThrottleTime`, `p2p/server.go:53`) | not read |
| RLPx handshake budget | 5s (`+devnet-peer-handshake-timeout-seconds+`, `devnet/peer-manager.lisp:23`) | 5s (`handshakeTimeout`, `p2p/transport.go:39`) | not read |
| `eth` handshake budget | none separately; covered by the above | 5s (`handshakeTimeout`, `eth/protocols/eth/handshake.go:33`) | not read |
| Keepalive ping interval | 15s (`+eth-pump-ping-interval-seconds+`, `eth-sync/pump.lisp:41`) | 15s (`pingInterval`, `p2p/peer.go:48`) | 10s (`P2PPingInterval`, `NetworkConfig.cs:26`) |
| Idle / read timeout | 60s idle (`+eth-pump-idle-timeout-seconds+`, `eth-sync/pump.lisp:45`) | 30s frame read (`frameReadTimeout`, `p2p/server.go:57`) | not read |
| Accept tick | 1s (`+devnet-peer-accept-tick-seconds+`, `devnet/peer-manager.lisp:28`) | no equivalent (blocking accept) | no equivalent |
| Base protocol version | 5 (`+devp2p-version+`, `p2p/protocol.lisp:10`) | 5 (`baseProtocolVersion`, `p2p/peer.go:42`) | matches (Snappy from p2p/5) |
| Base protocol id block | 16 (`+devp2p-base-protocol-length+`, `p2p/session.lisp:12`) | 16 (`baseProtocolLength`, `p2p/peer.go:43`) | 16 |
| Base protocol max message | **none** (NET-02) | 2048 (`baseProtocolMaxMsgSize`, `p2p/peer.go:44`) | 16 MiB (`SnappyParameters.MaxSnappyLength`) |
| `eth` max message | **none** (NET-02) | 10 MiB (`eth/protocols/eth/protocol.go:52`) | 16 MiB, plus 4 MiB compressed (`ZeroNettyP2PHandler.cs:37,53`) |
| Max frame size (read) | 16 MiB (24-bit, `p2p/frame.lisp:152-170`) | 16 MiB (`maxUint24`, `p2p/rlpx/rlpx.go:236`) | 16 MiB read; writes split at 1024 (`Rlpx/Frame.cs:16`) |
| Snappy decoded cap | 16 MiB (`+snappy-max-decoded-length+`, `foundation/snappy.lisp:10`) | 16 MiB (`maxUint24`, `p2p/rlpx/rlpx.go:153`) | 16 MiB (`Rlpx/SnappyParameters.cs:10`) |
| `eth` message-id block | 17 (`p2p/session.lisp:17`) — see NET-11 | 18 for eth/69–70, 20 for 71, 22 for 72 (`eth/protocols/eth/protocol.go:49`) | per-version handlers |
| Headers served per request | 1024 (`+eth-max-headers-serve+`, `eth-sync/serve.lisp:21`) | 1024 (`maxHeadersServe`) | 512 own / 192 assumed for geth (`Stats/SyncLimits/`) |
| Bodies served per request | 256 (`+eth-max-bodies-serve+`, `eth-sync/serve.lisp:22`) | **1024** (`maxBodiesServe`, `eth/protocols/eth/handler.go:50`) | 256 own, 128 assumed for geth |
| Receipts served per request | 1024 (`+eth-max-receipts-serve+`, `eth-sync/serve.lisp:23`) | 1024 (`maxReceiptsServe`, `eth/protocols/eth/handler.go:56`) | 256 (`NethermindSyncLimits.MaxReceiptFetch`) |
| Soft response limit | 2 MiB (`+eth-soft-response-limit+`, `eth-sync/serve.lisp:24`) | 2 MiB (`softResponseLimit`, `eth/protocols/eth/handler.go:37`) | not read |
| Pooled txs served | 256 (`+eth-max-pooled-transactions-serve+`, `eth-sync/gossip.lisp:23`) | no count cap; bounded by `softResponseLimit` only (`eth/protocols/eth/handlers.go:624`) | 256 |
| Neighbors per packet | 4 (`discv4-neighbors-packets`, `p2p/discovery.lisp:548`) | 12 (`MaxNeighbors`, `p2p/discover/v4wire/v4wire.go:107`) | not read |
| Tx announcements accepted | **none** (NET-17); queue capped at 4096 (`eth-sync/gossip.lisp:27`) | 5000 (`maxTransactionAnnouncements`, `eth/protocols/eth/protocol.go:55`) | 102400 bytes per message (`TransactionsMessage.cs:14`) |
| Full-broadcast size threshold | **none** (NET-13) | 4096 bytes (`txMaxBroadcastSize`, `eth/handler.go:63`) | 102400 per packet |
| Header download batch | 192 (`+eth-sync-default-batch-size+`, `eth-sync/sync.lisp:11`) | 192 (`MaxHeaderFetch`) | 512 (`NethermindSyncLimits.MaxHeaderFetch`) |
| Backfill batch / ceiling | 192 / 100000 (`eth-sync/backfill.lisp:24,27`) | no direct equivalent (skeleton-driven) | no direct equivalent |
| discv4 packet size | 1280 (`+discv4-max-packet-size+`, `p2p/discv4.lisp:16`) | 1280 (`maxPacketSize`, `p2p/discover/v4_udp.go:64`) | 1280 |
| Kademlia bucket size / count | 16 / 256 (`p2p/node-table.lisp:28,31`) | 16 (`bucketSize`, `p2p/discover/table.go:46`) / 17 buckets (`nBuckets`, `:52`) | 16 |
| Bond lifetime | 12h (`+discv4-bond-lifetime-seconds+`, `p2p/node-table.lisp:34`) | 24h (`bondExpiration`, `p2p/discover/v4_udp.go:54`) | not read |
| ENR max size | 300 (`+enr-max-size+`, `p2p/enr.lisp:14`) | 300 (`SizeLimit`, `p2p/enr/enr.go:46`) | 300 |

`docs/reference-map.md`'s "devp2p and peering" section should be updated to point
at this table instead of stating that no reference checkout exists.

## Remediation plan

Ordered by what unblocks the most, with the RLP fix first because it is the only
item that is exploitable today.

1. **Bound RLP recursion and guard threads against `storage-condition`.** (S,
   no dependencies.) Add a depth parameter to `rlp-decode`/`decode-list-payload`
   with a limit in the low hundreds, and widen the session-thread guards from
   `error` to `serious-condition` at
   `src/app/cli/devnet/peer-manager.lisp:264` and every other
   `sb-thread:make-thread` body. *Verification:* a new test in
   `tests/p2p-handshake-tests.lisp` feeding a depth-20000 auth body through
   `rlpx-open-auth` and asserting an ordinary error, plus one in
   `tests/eth-wire-tests.lisp` per decoder; a thread-level test that a
   `storage-condition` in a session does not exit the process. Note the trap in
   `CLAUDE.md`: a regression test for the thread guard goes red by killing the run
   rather than by reporting a failure, so it must say so in a comment.
2. **Add message size caps.** (S, no dependencies.) A 2 KB cap on base-protocol
   messages in `rlpx-read-message` and a 10 MB cap on `eth` messages in
   `eth-wire-read`, matching `p2p/peer.go:44` and
   `eth/protocols/eth/protocol.go:52`. *Verification:* `tests/p2p-frame-tests.lisp`
   and `tests/eth-pump-tests.lisp` cases asserting an oversized frame is refused
   before decode.
3. **Add item-count caps to the transaction decoders.** (S, depends on 2 for the
   limit constants to sit alongside.) 5000 announcements, and a bound on
   `decode-eth-transactions`. *Verification:* `tests/eth-gossip-tests.lisp`.
4. **Fix the discovery endpoint.** (S, no dependencies.) Run the crawl on the
   same socket as the responder, or at minimum set the `from` endpoint's TCP port
   to the real p2p port. Add `ip`/`tcp`/`udp` to the served ENR and derive the
   sequence number from something that changes. *Verification:* a loopback
   two-node test in `tests/p2p-discv4-tests.lisp` asserting the endpoint a
   recipient derives from our Ping equals our listener; an interop check against
   geth 1.17.6-unstable confirming it dials us back after a bond.
5. **Require our own endpoint proof before marking a node bonded, and add a
   relay-address check.** (M, depends on 4 sharing a socket.) Ping back on an
   unsolicited Ping and set bonded only on the Pong, per
   `p2p/discover/v4_udp.go:699-708`; refuse to relay loopback and private
   addresses. *Verification:* `tests/p2p-discv4-tests.lisp` asserting a Ping alone
   does not make a node appear in a Neighbors reply.
6. **Wire up table maintenance.** (M, depends on 5.) Call
   `discv4-table-note-failure` and `discv4-table-remove` from the crawl and the
   dialer, and add a revalidation tick. *Verification:*
   `tests/p2p-node-table-tests.lisp` asserting an entry that fails repeatedly is
   evicted.
7. **Add inbound per-IP throttling, and either implement or reject
   `--netrestrict`/`--nat`.** (M, no dependencies.) *Verification:*
   `tests/cli-devnet-peer-manager-tests.lisp` asserting a second connection from
   the same address inside the window is refused; a CLI test asserting an
   unimplemented flag is rejected rather than ignored.
8. **Add `decode-eth-receipts` and the `BlockRangeUpdate` codec, validate the
   peer's block range, and correct the `eth` message-id block length to 18.**
   (M, no dependencies; the length correction must land before any second
   capability — see NET-11.) *Verification:* `tests/eth-wire-tests.lisp` round
   trips for both versions of the receipts encoding; a negotiation test asserting
   the offsets assigned for `eth` + a hypothetical second capability match geth's.
9. **Rework transaction gossip to announce-or-broadcast with per-peer knowledge.**
   (M, depends on 3.) Track hashes received from a peer as known to that peer,
   apply a 4096-byte full-broadcast threshold, and call
   `eth-peer-announce-transactions` from the pump for everything above it.
   *Verification:* `tests/eth-gossip-tests.lisp` asserting a transaction received
   from a peer is not sent back to it, and that a large transaction is announced
   rather than pushed.
10. **Validate deliveries at the sync layer and drop the delivery rather than the
    session.** (M, depends on 8 for the receipt path.) Check header contiguity
    and match bodies to `TxHash`/`UncleHash`/`WithdrawalsHash` before assembling,
    per `eth/downloader/queue.go:569-588`. *Verification:* `tests/eth-sync-tests.lisp`
    asserting a mismatched body is rejected without ending the session.
11. **Multi-peer, pipelined download.** (L, depends on 10.) A delivery queue, more
    than one request in flight, and peer selection. This is the prerequisite for
    any realistic sync speed and should precede snap. *Verification:*
    `tests/eth-sync-tests.lisp` against multiple scripted peers; a Hive
    `ethereum/sync` run.
12. **`snap/1`.** (L, depends on 8, 11, and on the state-trie audit's node store —
    without a trie there is nothing to write ranges into.) *Verification:* Hive
    `ethereum/sync` snap suite and a real sync against geth 1.17.6-unstable on a
    small public testnet.
13. **discv5.** (L, depends on 4 and 6.) *Verification:* interop against geth
    1.17.6-unstable with v4 disabled.

Items 1 through 3 are the ones that should not wait: they are small, independent,
and they close a remote process kill.

## Overlaps with the other four audits

Recorded so these can be deduplicated rather than counted twice.

| Ours | Theirs | Relationship |
| --- | --- | --- |
| NET-01 (`rlp-decode` depth) | none | New. `rlp.lisp` is foundation code no sibling audit owned, and this is the only finding that names it. Fixing it is a foundation change with a networking consequence, so the work item may belong to whoever owns `src/foundation/`. |
| NET-03 (no `snap`) | STORE-06, STORE-14, STORE-19 | Blocked by, not duplicative of. Their findings are about the substrate; ours is that the protocol to fill it is absent. Both must be fixed. |
| NET-04 (sync driver) | RPC-01 (`eth_syncing` always `false`) | Adjacent. They found the reporting is wrong; we found there is little progress to report. Neither supersedes the other. |
| NET-18 (skip walk cost) | STORE-14 | Severity depends on theirs. Rated performance because the store is in RAM; it becomes remote-DoS once the store is on disk. |
| NET-19 (unvalidated deliveries) | EXEC-02 (uncles validated no further than the ommers hash) | Sequential, not duplicative. The import-path check that keeps NET-19 out of the correctness bucket is the same ommers-hash comparison EXEC-02 identifies as the *only* uncle check: a downloaded body's uncle list is proven to be the one the header committed to, and nothing beyond that is verified about the uncle headers themselves. Read together they say a peer cannot substitute a different uncle list, but a pre-merge block producer can commit to a fabricated one. |
| NET-14 (no block propagation) | none | Ours alone, and low severity precisely because the Engine API path the RPC audit covers is how post-merge blocks arrive. |

## Explicitly out of scope

- **Transaction pool semantics** (pricing, replacement, eviction, per-account
  slots). Only the gossip seam into and out of the pool was audited.
- **Block execution, header validation, and body validation rules.** NET-19
  touches the boundary and cites the import-path check it relies on, but the rules
  themselves belong to `block-execution-and-types.md`.
- **The storage substrate.** NET-03, NET-04 and NET-18 all depend on it, and it is
  audited in `state-trie-storage.md`.
- **`eth_syncing` and sync progress reporting**, audited in `rpc-and-engine.md`.
- **Engine API driven block delivery.** Our post-merge block path is the Engine
  API, not `NewBlock`; that path is `rpc-and-engine.md`.
- **`les`, `wit`, and other historical subprotocols.** geth 1.17.6-unstable has
  removed `les` entirely — `eth/protocols/` contains only `eth` and `snap`, and
  there is no top-level `les` directory — so there is nothing upstream to be
  behind on. Nethermind exposes a `nodedata` protocol we do not; it is not
  required to follow a chain.

## Left unverified

- **The message-id offsets `rlpx-negotiate-capabilities` assigns** against geth's
  and Nethermind's real advertised version sets (NET-11). The warm image was
  stopped by another session before this eval ran. The finding is source-read from
  a short pure function and its consequence is stated as latent, not observed.
- **Whether NET-01 also fires from the eth-wire decoders in practice**, as
  opposed to from the handshake. The path is traced and every decoder calls
  `rlp-decode` on peer bytes, but the end-to-end demonstration was only carried
  out for the handshake budget arithmetic. Nothing in the trace suggests it would
  not; it simply was not executed.
- **Nethermind's inbound connection throttling and its RLPx handshake budget.**
  Its `NetworkConfig` defaults were read, but the throttling path was not, so the
  parity table says "not read" rather than "none".
- **geth's exact `GetBlockHeaders` skip shortcut.** NET-18 states the behavioural
  difference from the handler's structure; the specific canonical-number-index
  fast path was not read line by line, so the citation is to the file rather than
  a line.
- **discv4 expiry handling under clock skew.** `discv4-expired-p` is applied on
  every serve path, but no test of skew was run and geth's 20-second expiration
  window was not compared.
- **Whether any test in the tree exercises the RLPx recipient path with a
  hostile auth body.** `tests/p2p-handshake-tests.lisp` exists and was read for
  what it covers, but no test was run — the image was down, and the brief forbids
  running the full suite.
