# JSON-RPC and Engine API — gap analysis

This document records a read-only audit of one area of this client: the public
JSON-RPC surface (`eth_*`, `net_*`, `web3_*`, `debug_*`, `trace_*`, `admin_*`,
`txpool_*`), the Engine API, and the HTTP and WebSocket transports that serve
them. It is a gap analysis, not a changelog. Nothing described below has been
implemented as part of this audit, and no statement here should be read as a
claim that a fix is in the tree.

Findings are a snapshot of the working tree at commit
`28e9912072135bebc3f49bc75226d6fed68dc21f`. Line numbers are relative to that
snapshot; function and constant names are the durable identifier, so prefer them
when a line has moved.

Per `PROJECT.md`, method count is not the metric. The audit is weighted by what a
consensus client, a wallet, and an indexer actually depend on, and several
absences below are deliberately recorded as low-severity completeness gaps rather
than as defects. Where this client differs on purpose and says so in a docstring,
that is noted; a documented limitation is not a bug.

## Sources read

| Side | Version | Commit | Date |
| --- | --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` | 2026-07-28 |
| this client | — | `28e9912072135bebc3f49bc75226d6fed68dc21f` | 2026-07-28 |

The Nethermind checkout is sparse and contains `src/Nethermind` only. Nethermind
was used mainly to establish whether a behaviour is a geth idiosyncrasy or a
shared expectation; where only one reference is cited for a claim, only one was
read for it, and the finding says which.

Ours, read in full or near-full: `src/api/engine/`, `src/api/public/`,
`src/api/rpc/`, `src/api/json-rpc/`, `src/transport/http/`,
`src/transport/websocket/`, `src/application/services/engine-payload-status.lisp`,
`src/protocol/engine-payloads/`, `src/app/cli/options/`,
`src/app/cli/devnet/ws-server.lisp`, `src/app/cli/devnet/dialer.lisp`,
`src/storage/chain-store/service/filters.lisp`,
`src/storage/txpool/service/views.lisp`.

Theirs: `eth/catalyst/api.go`, `beacon/engine/errors.go`, `internal/ethapi/api.go`,
`eth/filters/api.go`, `eth/filters/filter_system.go`, `eth/api_debug.go`,
`eth/tracers/api.go`, `node/api.go`, `node/defaults.go`, `rpc/handler.go`,
`rpc/websocket.go`, `eth/ethconfig/config.go`; Nethermind
`Nethermind.JsonRpc/Modules/**`, `Nethermind.Core/BlockHeader.cs`.

## Executive summary

The ten items that mattered most at audit time, ordered by how directly they
blocked a real caller. Resolved entries remain here as an audit trail.

1. **RESOLVED — `eth_syncing` now reports honest cached progress.** It combines
   the canonical head with buffered remote blocks, retained forkchoice targets,
   known target-header heights, and the durable SNAP skeleton target. A pending
   target therefore remains visible even at genesis or while the store guard is
   contended; only a genuinely idle snapshot returns `false`.
2. **Engine version-vs-fork violations return an `INVALID` payload status
   instead of a JSON-RPC error.** geth returns `-32602`/`-38005` with no result
   for every one of these cases (`eth/catalyst/api.go:171`, `:786`, `:527`); we
   return a `200` with `{"status":"INVALID"}`
   (`src/protocol/engine-payloads/validation.lisp:25`). A consensus client reads
   `INVALID` as "this block is bad, blacklist it" rather than "you called the
   wrong method", which is the difference between a retry and a permanent
   rejection of a valid chain.
3. **`engine_forkchoiceUpdatedV1` and `V2` perform no fork or attribute
   gating at all** (`src/api/engine/forkchoice-codecs.lisp:15-35`,
   `src/api/engine/forkchoice.lisp:74-93`). geth rejects withdrawals and beacon
   roots in V1, rejects post-Shanghai timestamps in V1, and enforces the
   withdrawals-present/absent rule per fork in V2
   (`eth/catalyst/api.go:171-199`). We will happily build a Shanghai payload from
   a V1 call.
4. **The invalid-ancestor cache has no eviction, no capacity bound, and no
   pre-merge zeroing** (`src/application/services/engine-payload-status.lisp:20-33`).
   geth caps the tipset map, evicts a bad hash after repeated hits so a data race
   cannot permanently wedge the node, and returns `0x0` as `latestValidHash` when
   the last valid ancestor is a proof-of-work block
   (`eth/catalyst/api.go:1077-1125`). Without the hit eviction, one spurious
   `INVALID` verdict is unrecoverable without a restart.
5. **`getPayload` never reports a block value and never reports blobs.**
   `engine-rpc-prepared-payload-envelope` passes the prepared payload's
   blobs bundle, and nothing in the build path ever sets one
   (`src/api/engine/forkchoice.lisp:181-193`), while `block-to-executable-data`
   defaults `block-value` to `0` (`src/protocol/engine-payloads/codecs.lisp:26`).
   A consensus client comparing a local payload against a builder bid sees a
   value of zero every time and will always take the builder's block.
6. **The payload ID is a function of the selected transaction set**
   (`src/api/engine/forkchoice.lisp:175-178`, using
   `engine-payload-id-with-transactions`). In geth the ID is derived from the
   parent and the attributes only (`miner/payload_building.go`, called from
   `eth/catalyst/api.go:248`), and the payload behind it is improved in place
   until `getPayload`. Ours means two identical `forkchoiceUpdated` calls return
   different IDs whenever the mempool moved, and the payload is frozen at the
   moment of the call rather than improved over the slot.
7. **`eth_call` and `eth_estimateGas` accept no state or block overrides and
   enforce no gas cap.** The handlers take at most two parameters
   (`src/api/public/state/call-simulation.lisp:82`) and default an unspecified
   `gas` to `2^64-1` (`src/api/public/state/call-objects.lisp:3`), while geth
   caps every call at `RPCGasCap` and applies an EVM timeout
   (`internal/ethapi/api.go:753-859`). Bundlers, simulators, and Tenderly-style
   tooling need the overrides; the missing cap is an unauthenticated way to pin a
   core.
8. **There is no gas-price oracle.** `engine-rpc-suggest-gas-tip-cap` returns a
   literal `0` (`src/api/public/metadata/fees.lisp:3`), so
   `eth_maxPriorityFeePerGas` is always `0x0` and `eth_gasPrice` is the base fee
   alone. geth samples recent blocks (`eth/ethconfig/config.go:44-46`: 20 blocks,
   60th percentile). Every wallet that asks the node for a fee suggestion
   produces a transaction that will not be mined on a contended chain.
9. **Installed filters never expire and their IDs are sequential integers**
   (`src/storage/chain-store/service/filters.lisp:50-78`). geth gives each filter
   a random 16-byte ID and a five-minute deadline
   (`eth/filters/api.go:74`, `:421`). Any client on the port can uninstall
   another's filter by guessing `0x1`, and an abandoned log filter accumulates one
   pending change per block forever.
10. **No IPC transport exists, and the flags that configure one are parsed and
    then discarded** (`src/app/cli/options/definitions.lisp:10-15`). The same is
    true of `--rpc.gascap`, `--rpc.evmtimeout`, `--rpc.batch-request-limit`, and
    `--rpc.batch-response-max-size`. Accepting a flag that changes nothing is the
    opposite of the capability-gating principle in `PROJECT.md`.

## Method inventory

### `engine_*`

Built from `+engine-rpc-method-registry+` (`src/api/engine/methods.lisp:3-28`)
and the dispatch table in `src/api/engine/dispatch.lisp`, not from tests. geth's
column is every exported method on `*ConsensusAPI` in `eth/catalyst/api.go`.
Nethermind's column is `Nethermind.Merge.Plugin/EngineRpcModule*.cs`.

| Method | geth 1.17.6 | Nethermind 1.40.0 | Ours | Note |
| --- | --- | --- | --- | --- |
| `engine_newPayloadV1` | yes | yes | partial | Version gating returns `INVALID`, not `-32602` (RPC-02). |
| `engine_newPayloadV2` | yes | yes | partial | Same; pre/post-Shanghai withdrawals rule not enforced as an RPC error. |
| `engine_newPayloadV3` | yes | yes | gated | KZG-backed; requires the c-kzg shim (`:kzg-p t`). |
| `engine_newPayloadV4` | yes | yes | gated | As above. |
| `engine_newPayloadV5` | yes | yes | gated | As above. |
| `engine_forkchoiceUpdatedV1` | yes | yes | partial | No fork or attribute gating (RPC-03). |
| `engine_forkchoiceUpdatedV2` | yes | yes | partial | As above. |
| `engine_forkchoiceUpdatedV3` | yes | yes | gated | Fork gating present and correct (`forkchoice.lisp:76-87`). |
| `engine_forkchoiceUpdatedV4` | yes | yes | partial | `targetGasLimit` not required and not used (RPC-04); third `custodyColumns` parameter ignored. |
| `engine_getPayloadV1` | yes | yes | partial | Version mismatch yields `-32602`, not `-38005` (RPC-05). |
| `engine_getPayloadV2` | yes | yes | partial | As above. |
| `engine_getPayloadV3` | yes | yes | gated | `blobsBundle` always empty (RPC-06); `blockValue` always `0` (RPC-07). |
| `engine_getPayloadV4` | yes | yes | gated | As above. |
| `engine_getPayloadV5` | yes | yes | gated | As above. |
| `engine_getPayloadV6` | yes | UNVERIFIED | gated | Present on both sides at this commit. |
| `engine_getPayloadBodiesByHashV1` | yes | yes | full | 1024 cap and `-38004` match (`blobs.lisp:72-75`). |
| `engine_getPayloadBodiesByHashV2` | yes | UNVERIFIED | gated | As above. |
| `engine_getPayloadBodiesByRangeV1` | yes | yes | full | Clamps to head, `null` for gaps — matches. |
| `engine_getPayloadBodiesByRangeV2` | yes | UNVERIFIED | gated | As above. |
| `engine_getBlobsV1` | yes | yes | gated | 128 cap and `-38004` match; no fork gating (RPC-09). |
| `engine_getBlobsV2` | yes | UNVERIFIED | gated | Returns `null` on any miss, per spec; no fork gating. |
| `engine_getBlobsV3` | yes | UNVERIFIED | gated | Partial responses, per spec; no fork gating. |
| `engine_getBlobsV4` | yes (`api.go:722`) | UNVERIFIED | missing | Takes a custody bitmap and returns cells; RPC-10. |
| `engine_hasBlobs` | yes (`api.go:778`) | UNVERIFIED | missing | RPC-10. |
| `engine_exchangeCapabilities` | yes | yes | full | Excluded from its own advertised set, which matches geth. |
| `engine_getClientVersionV1` | yes | yes | full | — |
| `engine_exchangeTransitionConfigurationV1` | yes | yes | full | Deprecated on both sides. |

The mandatory `eth_*` methods on the authenticated port
(`+engine-rpc-required-eth-methods+`, `src/api/engine/methods.lisp:58-67`) are
exactly the nine that `execution-apis`' `src/engine/common.md` requires, and the
docstring explains why the list is not wider. That is a correct and deliberately
narrow choice, and it is one of the better-documented decisions in the area.
RPC-01 records the now-resolved reporting gap that used to affect one of the nine.

### `eth_*`

| Method | geth 1.17.6 | Nethermind 1.40.0 | Ours | Note |
| --- | --- | --- | --- | --- |
| `eth_chainId` | yes | yes | full | — |
| `eth_blockNumber` | yes | yes | full | — |
| `eth_syncing` | yes | yes | full | Cached non-blocking progress object from canonical, remote, forkchoice, and SNAP targets; `false` only when idle (RPC-01). |
| `eth_coinbase` | yes | yes | full | — |
| `eth_accounts` | yes | yes | full | Empty array; no key management, by design. |
| `eth_mining` / `eth_hashrate` | yes | yes | full | `false` / `0x0`, as post-merge geth. |
| `eth_protocolVersion` | yes | yes | full | — |
| `eth_gasPrice` | yes | yes | partial | Base fee plus a hardcoded zero tip (RPC-21). |
| `eth_maxPriorityFeePerGas` | yes | yes | partial | Always `0x0` (RPC-21). |
| `eth_blobBaseFee` | yes | yes | partial | Present; whether it reports head or head+1 is UNVERIFIED (RPC-22). |
| `eth_baseFee` | no | yes | full | Nethermind extension. |
| `eth_feeHistory` | yes | yes | partial | `reward` percentiles derive from the zero tip (RPC-21). |
| `eth_getBalance` | yes | yes | full | — |
| `eth_getTransactionCount` | yes | yes | full | Optional block defaults to `latest`; `pending` includes the contiguous pool nonce. |
| `eth_getCode` | yes | yes | full | — |
| `eth_getStorageAt` | yes | yes | full | — |
| `eth_getProof` | yes | yes | UNVERIFIED | Dispatch entry read; result shape not compared. |
| `eth_call` | yes | yes | partial | No overrides, no gas cap, no timeout (RPC-15, RPC-16). |
| `eth_estimateGas` | yes | yes | partial | As above; binary search bounded by the block gas limit. |
| `eth_createAccessList` | yes | yes | partial | No overrides; result shape not compared (UNVERIFIED). |
| `eth_simulateV1` | yes (`internal/ethapi/simulate.go`) | yes | partial | Multi-block execution exists; pinned Hive still exposes unsupported transfer tracing, overrides, validation errors, and block progression (RPC-17). |
| `eth_getBlockByHash` / `ByNumber` | yes | yes | partial | `balHash` field name (RPC-19); pending block is synthetic (RPC-20). |
| `eth_getHeaderByHash` / `ByNumber` | yes | no | full | Same `balHash` note. |
| `eth_getBlockTransactionCountByHash` / `ByNumber` | yes | yes | full | — |
| `eth_getUncleCountByBlockHash` / `ByNumber` | yes | yes | full | Always `0x0` post-merge. |
| `eth_getUncleByBlockHashAndIndex` / `ByNumber...` | yes | yes | full | Always `null`. |
| `eth_getTransactionByHash` | yes | yes | full | — |
| `eth_getTransactionByBlockHashAndIndex` / `ByNumber...` | yes | yes | full | — |
| `eth_getRawTransactionByHash` | yes | yes | UNVERIFIED | Dispatched; encoding not compared. Also the `ByBlock*AndIndex` pair. |
| `eth_getTransactionReceipt` | yes | yes | partial | Type-3 blob gas fields are emitted and regression-covered; pinned Hive typed-receipt cases still fail elsewhere (RPC-18). |
| `eth_getBlockReceipts` | yes | yes | partial | `pending` returns `null`; pinned Hive still has one failing case. |
| `eth_sendRawTransaction` | yes | yes | full | Admission policy is richer than the RPC contract requires. |
| `eth_sendRawTransactionSync` | yes | no | missing | Recent geth addition; low priority. |
| `eth_sendTransaction` / `eth_sign` / `eth_signTransaction` | yes | yes | missing | No key management, by design. |
| `eth_fillTransaction` | yes | no | missing | Completeness only. |
| `eth_getLogs` | yes | yes | partial | Geth topic limits and unknown-`blockHash` error are covered; a local 5,000-block resource cap remains intentionally non-parity (RPC-25, RPC-26). |
| `eth_newFilter` | yes | yes | partial | No deadline, sequential IDs (RPC-23). |
| `eth_newBlockFilter` | yes | yes | partial | As above. |
| `eth_newPendingTransactionFilter` | yes | yes | partial | As above; no full-transaction variant. |
| `eth_getFilterChanges` | yes | yes | full | Reorg-removed logs are recorded (see RPC-24 for the contrast). |
| `eth_getFilterLogs` | yes | yes | full | — |
| `eth_uninstallFilter` | yes | yes | full | — |
| `eth_subscribe` / `eth_unsubscribe` | yes | yes | partial | WebSocket only, handled outside the public dispatch table (`src/app/cli/devnet/ws-server.lisp:143`); `newHeads`, `logs`, `newPendingTransactions`; no `syncing` (documented); no removed logs (RPC-24). |
| `eth_capabilities` | yes | UNVERIFIED | full | Conservative archive ranges plus geth-compatible log retention window; pinned Hive rerun pending. |
| `eth_config` | yes (`internal/ethapi/api.go`) | no | full | EIP-7910 current/next/last fork descriptors; null-future regression covered (RPC-33 resolved). |
| `eth_getStorageValues` | yes | no | full | Multi-account/slot query, 1024-slot cap, optional `latest`; pinned Hive rerun pending. |
| `eth_getBlockAccessList` | yes | UNVERIFIED | missing | Amsterdam-era; completeness only. |
| `eth_pendingTransactions` | no | no | extra | Ours; harmless. |

### Other namespaces

Summarised rather than enumerated, since the long tail is where method count is
least informative.

| Namespace | geth | Nethermind | Ours |
| --- | --- | --- | --- |
| `web3_*` | `clientVersion`, `sha3` | same | both, full |
| `net_*` | `version`, `listening`, `peerCount` | plus `localAddress`, `localEnode` | geth's three, full |
| `rpc_*` | `modules` | n/a | `rpc_modules`, full |
| `txpool_*` | `status`, `content`, `contentFrom`, `inspect` | same | all four; `inspect` formatting differs (RPC-32) |
| `admin_*` | `nodeInfo`, `peers`, `addPeer`, `removePeer`, `addTrustedPeer`, `removeTrustedPeer`, `startHTTP`, `stopHTTP`, `startWS`, `stopWS`, `datadir`, `peerEvents` | comparable | `nodeInfo`, `peers`, `addPeer` only (RPC-31) |
| `debug_*` | ~40 methods across `eth/api_debug.go` and `eth/tracers/api.go` | comparable | `debug_traceCall` and the raw-data getters only (RPC-28, RPC-30) |
| `trace_*` | not served | full Parity module (`Nethermind.JsonRpc/Modules/Trace/ITraceRpcModule.cs`) | missing (RPC-29) |

## Findings

### Engine API

**RPC-01 — `eth_syncing` reports live progress rather than an unconditional stub.**
Verdict RESOLVED. Severity breaks-consensus-client-integration.
Ours now returns a geth-shaped `startingBlock`, `currentBlock`, and
`highestBlock` object whenever the canonical head trails a buffered remote
block, retained forkchoice target, known target-header height, or durable SNAP
skeleton target. The node backend maintains a small guarded snapshot so the
mandatory Engine-port upcheck remains non-blocking; if refresh loses the store
try-lock after an idle snapshot, it conservatively reports progress at the last
known head rather than returning stale `false`. A target whose height is truly
unknown uses the current height until stronger metadata arrives. Focused cold
unit and integration tests cover genesis forkchoice, known state-unavailable
targets, and store-guard contention. This fixes reporting only; it does not
change downloader, import, forkchoice, networking, or SNAP mechanics.

**RPC-02 — Engine version violations are reported as `INVALID`, not as an RPC error.**
Verdict DIVERGENT. Severity breaks-consensus-client-integration.
Ours: `engine-new-payload-version-invalid-p`
(`src/protocol/engine-payloads/validation.lisp:36`) feeds
`invalid-payload-status` (`:25-30`), so a `newPayloadV2` carrying
`excessBlobGas`, or a `newPayloadV1` carrying withdrawals, produces a successful
JSON-RPC result whose `status` is `INVALID`. Reference: geth
`eth/catalyst/api.go:786-830` returns `(invalidStatus, paramsErr(...))`; because
the Go error is non-nil the RPC layer discards the result and emits `-32602`.
Consequence: the two are not interchangeable to a caller. A consensus client that
receives `INVALID` for a block records the block hash as bad and will not offer
it again, so a version mismatch caused by a client-side bug turns into a
permanent rejection of a chain that is in fact valid; the same mismatch reported
as `-32602` is a retryable protocol error. The Hive `engine-api` suite asserts on
the error code directly.

**RPC-03 — `forkchoiceUpdatedV1` and `V2` do no fork or attribute gating.**
Verdict MISSING. Severity breaks-consensus-client-integration.
Ours: `engine-rpc-validate-payload-attributes-v1`
(`src/api/engine/forkchoice-codecs.lisp:15-31`) parses `withdrawals` whenever
present and never rejects it; `engine-rpc-validate-payload-attributes-v2`
(`:33-35`) is V1 with a different method name, so it neither requires withdrawals
post-Shanghai nor rejects them pre-Shanghai nor rejects `parentBeaconBlockRoot`.
`engine-rpc-prepared-payload-version` (`src/api/engine/forkchoice.lisp:74-93`)
gates only versions 3 and 4; versions 1 and 2 fall through the `otherwise`
branch untouched. Reference: geth `eth/catalyst/api.go:171-181` rejects
withdrawals or a beacon root in V1 and rejects a post-Shanghai timestamp;
`:185-202` enforces all three withdrawals rules in V2 and rejects anything
outside Paris/Shanghai with `-38005`. Consequence: a consensus client that calls
the wrong version — during a fork transition, which is exactly when it matters —
gets a built payload instead of a diagnosis, and the payload it gets is built
under a fork ruleset the caller did not ask for. V3 by contrast is correct on
both attributes and fork range, which shows the pattern is understood and simply
was not applied to the older versions.

**RPC-04 — `forkchoiceUpdatedV4` ignores `targetGasLimit`.**
Verdict MISSING. Severity correctness.
Ours: `engine-rpc-validate-payload-attributes-v4`
(`src/api/engine/forkchoice-codecs.lisp:52-61`) requires `slotNumber` and stops
there; a repository-wide search for `targetGasLimit` or `target-gas-limit` in
`src/` returns nothing. Reference: geth `eth/catalyst/api.go:234-236` returns
`-38003` when `params.TargetGasLimit` is nil, and the value feeds gas-limit
selection for the built block. Consequence: on an Amsterdam chain the consensus
client's requested gas limit is silently discarded and the built payload keeps
the parent's limit, so the gas limit never moves in the direction the beacon
chain asked for. Also in this method: the third positional parameter
(`custodyColumns`, geth `api.go:223`) is not read —
`engine-rpc-handle-forkchoice-updated` looks at `params[0]` and `params[1]` only
(`src/api/engine/forkchoice.lisp:100-108`).

**RPC-05 — `getPayload` version mismatch uses `-32602` where the spec and geth use `-38005`.**
Verdict DIVERGENT. Severity completeness.
Ours: each `engine-rpc-handle-get-payload-v*` calls `block-validation-fail` on a
version mismatch (`src/api/engine/payloads.lisp:39-40`, `:59-60`, `:70-71`,
`:82-83`, `:94-95`), which the router maps to `-32602`
(`src/api/rpc/router.lisp:199-206`). Reference: geth
`eth/catalyst/api.go:527-531` returns `engine.UnsupportedFork`, i.e. `-38005`.
geth additionally re-checks the built payload's own timestamp against the
permitted fork set (`:536-538`); we gate at build time instead, which is
equivalent in effect. Consequence: a spec-conformance failure rather than a
functional one — a consensus client treats both as fatal for the request. Listed
because the `execution-apis` vectors assert the code.

**RPC-06 — `getPayloadV3` and later always return an empty `blobsBundle`.**
Verdict DIVERGENT. Severity breaks-consensus-client-integration (on a chain with
blob traffic).
Ours: the prepared payload is constructed with `:payload-id`, `:version` and
`:block` only (`src/api/engine/forkchoice.lisp:181-193`) — no `:blobs-bundle` —
and `engine-rpc-blobs-bundle-object` substitutes a fresh empty `blob-sidecar`
when the bundle is nil (`src/api/engine/payload-codecs.lisp:73-75`), so the
response carries `{"commitments":[],"proofs":[],"blobs":[]}`. The only code that
ever populates the slot is the persistence round-trip
(`src/storage/node-store/persistence/import/prepared-payloads.lisp:130`).
Reference: geth returns the bundle the miner collected while building
(`eth/catalyst/api.go:471-495` via `api.localBlocks.get`). Consequence: a
consensus client cannot construct the `BlobSidecars` it must publish alongside
the block. This interacts with block building: `engine-payload-store-pending-mining-transactions`
draws from the pending list only (`src/storage/txpool/service/views.lisp:111-116`)
while blob transactions are held in a separate list
(`engine-payload-store-blob-transactions`, `:165-167`), so today the empty
bundle is at least self-consistent with a payload that contains no type-3
transactions. Whether any admission path can place a blob transaction into the
pending list is **UNVERIFIED**; if one can, the client would emit a payload whose
blob commitments have no matching bundle, which is worse than emitting neither.
Overlaps txpool/block-building.

**RPC-07 — `blockValue` in the payload envelope is always zero.**
Verdict DIVERGENT. Severity correctness.
Ours: `block-to-executable-data` defaults `:block-value` to `0`
(`src/protocol/engine-payloads/codecs.lisp:26`) and
`engine-rpc-prepared-payload-envelope` never overrides it
(`src/api/engine/payloads.lisp:30-33`). Reference: geth returns the fees credited
to the fee recipient for the built block, carried in
`engine.ExecutionPayloadEnvelope`. Consequence: a consensus client running
MEV-Boost compares the local payload's `blockValue` against the builder's bid; a
value of `0` means the builder always wins, so the node never proposes its own
block. Even without a builder, `blockValue` is what operators read to confirm the
node is including transactions at all.

**RPC-08 — The payload ID depends on the mempool, and the payload is never improved.**
Verdict DIVERGENT. Severity correctness.
Ours: `engine-payload-id-with-transactions`
(`src/protocol/engine-payloads/build.lisp:36`) hashes the selected transactions
into the ID, and `engine-rpc-handle-forkchoice-updated` computes it from a fresh
mempool selection on every call (`src/api/engine/forkchoice.lisp:162-178`), then
builds and stores the payload only if that exact ID is not already present
(`:179-193`). Reference: geth derives the ID from the parent hash and the
attributes alone and keeps improving the payload behind it until `getPayload` is
called (`eth/catalyst/api.go:248` into `miner.BuildPayload`). Consequence: two
identical `forkchoiceUpdated` calls in one slot return different payload IDs
whenever the pool moved, which is not what the spec describes and which defeats
any client-side caching of the ID; and because each new ID stores a new prepared
payload, a busy pool leaves one stored block per call in the prepared-payload
cache for the slot. Whether that cache is bounded is **UNVERIFIED**
(`src/storage/chain-store/service/cache.lisp`). The deeper consequence is that
the payload a proposer publishes reflects the pool as of the `forkchoiceUpdated`
call rather than as of `getPayload`, giving up the whole build window.

**RPC-09 — `engine_getBlobs*` is not fork-gated.**
Verdict MISSING. Severity completeness.
Ours: `engine-rpc-handle-get-blobs-v1/v2/v3`
(`src/api/engine/blobs.lisp:21-60`) validate the request size and nothing else.
Reference: geth rejects `getBlobsV1` once Osaka is active with `-38005`
(`eth/catalyst/api.go:580-583`) and returns `null` from `getBlobsV2`/`V3`
before Osaka (`:631-634`, `:642-645`). Consequence: on a chain past the
relevant fork we answer a method the spec says to refuse. Request-size limits and
`-38004` do match on both `getBlobs` (128) and the payload-bodies methods (1024),
which are the parts a consensus client actually exercises.

**RPC-10 — `engine_getBlobsV4` and `engine_hasBlobs` are absent.**
Verdict MISSING. Severity completeness.
Ours: neither name appears in `+engine-rpc-method-registry+`
(`src/api/engine/methods.lisp:3-28`). Reference: geth
`eth/catalyst/api.go:722` and `:778`. Consequence: a consensus client doing
PeerDAS custody reconstruction cannot use this node as a blob source. Both are
recent and neither is required to follow a chain, so this is genuinely a
completeness item — but note that we do advertise `getBlobsV3`, so a client may
reasonably infer the newer surface is present.

**RPC-11 — `forkchoiceUpdated` on an unknown head does not pursue that head.**
Verdict DIVERGENT. Severity breaks-consensus-client-integration on restart.
Ours: `engine-forkchoice-memory-status`
(`src/application/services/engine-payload-status.lisp:62-82`) returns
`SYNCING` for a head it does not hold and records nothing. Reference: geth
stashes the header in `remoteBlocks` and starts a beacon sync toward it
(`eth/catalyst/api.go:248` onward, and `delayPayloadImport` at `:1029-1046`
for the `newPayload` side). Consequence: after a restart, or on checkpoint sync,
the consensus client's first message is typically a `forkchoiceUpdated` to a head
we have never seen a payload for; we answer `SYNCING` and nothing ever goes to
fetch it, so the node can sit at `SYNCING` indefinitely. The `newPayload` half of
this is implemented and works: an unexecutable payload is buffered via
`engine-payload-store-put-remote-block`
(`src/application/services/engine-payload-status.lisp:134-138`) and the peer
dialer walks back from its parent to fill the gap
(`devnet-peer-fill-sync-gaps`, `src/app/cli/devnet/dialer.lisp:112-140`). Only
the forkchoice-initiated case is missing. Overlaps networking/sync.

**RPC-12 — The invalid-ancestor cache is unbounded and cannot recover.**
Verdict DIVERGENT. Severity correctness.
Ours: `engine-payload-store-invalid-ancestor-status`
(`src/application/services/engine-payload-status.lisp:20-33`) looks the hash up,
marks the new head invalid, and returns `INVALID` with the bad block's parent as
`latestValidHash`. There is no hit counter, no capacity limit, and no special
case for a pre-merge parent. Reference: geth `checkInvalidAncestor`
(`eth/catalyst/api.go:1077-1125`) increments `invalidBlocksHits`, deletes the
entry and all its descendants once `invalidBlockHitEviction` is reached
explicitly so that a data race can be escaped, trims `invalidTipsets` to
`invalidTipsetsCap`, and substitutes `0x0` for `latestValidHash` when the last
valid ancestor has non-zero difficulty. `invalid()` at `:1127-1145` applies the
same proof-of-work zeroing. Consequence: three separate exposures. A single
spurious `INVALID` — from a transient state-unavailability, say — is remembered
forever, so the node rejects the canonical chain until it is restarted, and the
consensus client has no way to make it reconsider. A peer feeding descendants of
a bad block grows the tipset map without bound. And on a chain whose merge block
is in range, `latestValidHash` may name a proof-of-work block where the spec
requires `0x0`.

**RPC-13 — Payload-status semantics otherwise match geth, including the cases that are easy to get wrong.**
Verdict (no gap). Recorded because it is the most consequential thing that is
right, and because a well-meaning change could break it. Ours returns `VALID`
with the block hash for an already-known executed block
(`src/application/services/engine-payload-status.lisp:108-114`), `SYNCING` after
buffering when the parent is absent (`:134-138`), `ACCEPTED` when the parent
block is present but its state is not (`:155-161`), and `INVALID` with the parent
as `latestValidHash` when validation fails against the config (`:139-154`).
geth's `newPayload` does the same four things in the same order
(`eth/catalyst/api.go:952-994`), including the `ACCEPTED`-on-missing-state case
at `:988-991`, which is the only place geth ever emits `ACCEPTED`. Note also
that geth 1.17.6 no longer emits `INVALID_BLOCK_HASH` at all — a decode or hash
failure becomes `api.invalid(err, nil)` (`:947`), i.e. `INVALID` with a null
`latestValidHash`, which is exactly what `invalid-payload-status` produces
(`src/protocol/engine-payloads/validation.lisp:30`). Our not emitting
`INVALID_BLOCK_HASH` is parity with geth at this commit, not a gap.

**RPC-14 — JWT authentication is implemented and `iat` freshness is enforced.**
Verdict (no gap), with one operational note. Ours:
`src/transport/http/auth.lisp` implements base64url decoding, HMAC-SHA256, a
constant-time comparison, and a 60-second `iat` window; the HTTP handler applies
it before dispatch and answers `401` on failure
(`src/transport/http/handler.lisp:44-56`). The authenticated port is separate
from the public one and carries a narrower method predicate
(`src/api/engine/methods.lisp:90-104`). The note: the handler passes `(or now 0)`
as the current time (`handler.lisp:50`), so a caller that omits `now` rejects
every token. The devnet CLI supplies it; a new embedder might not.

### Public `eth_*`

**RPC-15 — No state or block overrides on `eth_call`, `eth_estimateGas`, or `eth_createAccessList`.**
Verdict MISSING. Severity completeness (correctness for the callers that need it).
Ours: `engine-rpc-handle-eth-call` takes `(params store config)` and reads at
most two positional parameters (`src/api/public/state/call-simulation.lisp:82`);
there is no third-parameter override path anywhere in
`src/api/public/state/`. Reference: geth's `Call` takes
`*override.StateOverride` and `*override.BlockOverrides`
(`internal/ethapi/api.go:838-860`), and `EstimateGas` likewise (`:972-980`).
Nethermind serves the same overrides on `eth_call`. Consequence: account
abstraction bundlers, `eth_call`-based simulators, and any tool that needs to
answer "what would this do if the balance were higher" cannot use this node.

**RPC-16 — No RPC gas cap and no EVM timeout.**
Verdict MISSING. Severity performance (denial of service).
Ours: an `eth_call` with no `gas` defaults to `+eth-rpc-default-call-gas-limit+`,
which is `2^64-1` (`src/api/public/state/call-objects.lisp:3`), and a
caller-supplied `gas` is used verbatim; nothing bounds wall-clock time.
Reference: geth caps every call at `b.RPCGasCap()` and passes
`b.RPCEVMTimeout()` (`internal/ethapi/api.go:753-783`, `:859`), defaulting to
50,000,000 gas and 5 seconds. Consequence: one unauthenticated request can occupy
a core for an unbounded period. `eth_estimateGas` is bounded, but by the block
gas limit rather than by a configured cap
(`src/api/public/state/gas.lisp`), so its estimate for a transaction that would
need more than one block's gas differs from geth's. Compounding this: the CLI
already accepts `--rpc.gascap` and `--rpc.evmtimeout` and ignores both
(`src/app/cli/options/definitions.lisp:10-15`), so an operator who thinks they
have configured a cap has not.

**RPC-17 — `eth_simulateV1` remains incomplete.**
Verdict PARTIAL. Severity completeness and correctness.
Ours dispatches multi-block, multi-call simulation from
`src/api/public/state/call-simulation.lisp`. Reference: geth
`internal/ethapi/simulate.go`; Nethermind serves it too. The pinned rpc-compat
baseline still fails 92 simulate cases covering transfer tracing, richer state
and precompile overrides, validation error codes, and exact synthetic-block
progression. The method is therefore implemented but is not yet a conformance
gate; RPC-15's override machinery remains a prerequisite for closing it.

**RPC-18 — Blob-transaction receipts include `blobGasUsed` and `blobGasPrice`.**
Verdict RESOLVED. Severity correctness.
The original finding was stale by the reviewed baseline: type-3 serialization
already derived `blobGasUsed` from each transaction's versioned hashes and
`blobGasPrice` from the containing header's `excessBlobGas` plus the active chain
configuration, while omitting both fields from legacy receipts. Regression
coverage now proves distinct one-blob and two-blob values against a different
three-blob block aggregate, exercises both `eth_getTransactionReceipt` and
`eth_getBlockReceipts`, and checks field absence rather than JSON null for the
legacy transaction. Pinned Hive failures, if any remain, must be attributed to
their specific receipt divergence rather than these fields.

**RPC-19 — The header field is named `balHash` rather than `blockAccessListHash`.**
Verdict DIVERGENT. Severity correctness (silent, for one field).
Ours: `src/api/public/blocks/header-objects.lisp:65`. Reference: Nethermind's
header property is `BlockAccessListHash`
(`src/Nethermind/Nethermind.Core/BlockHeader.cs`). Consequence: a client reading
the Amsterdam block-access-list commitment finds no such field and treats it as
absent. Which spelling is correct at this commit is worth confirming against
`execution-apis` before changing, since the field is new on both sides; the
divergence itself is verified. Overlaps block execution.

**RPC-20 — `pending` is an alias for `latest` in state and call paths.**
Verdict DIVERGENT. Severity completeness.
Ours: `eth-rpc-state-block-param` (`src/api/public/state/queries.lisp:37`)
resolves `pending` to the latest block, so `eth_getTransactionCount(addr,
"pending")` does not count pooled transactions. `eth_getBlockByNumber("pending")`
does better: it synthesises a block from the latest header plus the visible
pending transactions (`src/api/public/blocks/handlers.lisp:7-15`). Reference:
geth builds a real pending block through the miner and answers state queries
against it. Consequence: a wallet that asks for the pending nonce gets the mined
nonce and will reuse a nonce that is already in the pool. This is the single most
commonly hit divergence for ordinary wallet traffic. Overlaps txpool.

**RPC-21 — No gas-price oracle.**
Verdict DIVERGENT. Severity correctness.
Ours: `engine-rpc-suggest-gas-tip-cap` ignores its argument and returns `0`
(`src/api/public/metadata/fees.lisp:3-5`); `eth_maxPriorityFeePerGas` returns it
directly (`:7-10`) and `eth_gasPrice` adds it to the base fee (`:12-21`).
Reference: geth's oracle samples the lowest-priced transactions of the last 20
blocks at the 60th percentile (`eth/ethconfig/config.go:44-46`, implemented in
`eth/gasprice/gasprice.go`). Consequence: every wallet that asks the node what
tip to pay is told zero, producing transactions no builder has reason to include.
`eth_feeHistory`'s `reward` array inherits the same zero
(`src/api/public/metadata/fee-history.lisp`), so the fallback path most wallets
use is equally uninformative.

**RPC-22 — `eth_blobBaseFee` may be off by one block.**
Verdict UNVERIFIED. Severity correctness if real.
Ours: `engine-rpc-handle-eth-blob-base-fee`
(`src/api/public/metadata/fees.lisp:42-56`) computes
`block-header-blob-base-fee` from the head header. geth computes the fee for the
*next* block from the head's `excessBlobGas`. Whether
`block-header-blob-base-fee` applies the update fraction to the header's own
excess gas or to the successor's was not established, so whether the two agree is
unresolved. Cheap to settle with one eval against the warm image; left
unverified rather than asserted.

### Filters and subscriptions

**RPC-23 — Filters never expire and their IDs are guessable.**
Verdict DIVERGENT. Severity correctness (isolation) and performance.
Ours: `engine-payload-store-put-log-filter` and its siblings assign
`memory-chain-store-next-log-filter-id` and increment it
(`src/storage/chain-store/service/filters.lisp:50-78`); the ID is rendered with
`quantity-to-hex` and parsed back with `json-rpc-quantity-param`
(`src/api/public/filters/handlers.lisp:23`, `:49`), so it is a small integer.
Nothing stores a deadline and nothing sweeps. Reference: geth allocates
`rpc.NewID()` — 16 random bytes — and arms a `time.Timer` per filter
(`eth/filters/api.go:74`, `:421`), resetting it on each poll (`:566-571`) and
uninstalling on expiry (`:125`). Consequence: two exposures. Any client on the
port can call `eth_uninstallFilter("0x1")` and destroy another client's filter,
or call `eth_getFilterChanges("0x1")` and consume its notifications. And an
abandoned log filter appends one change entry per block forever
(`engine-log-filter-record-change`, `:13-24`), so a crashed indexer leaks memory
until restart. Both are fixed by the same change.

**RPC-24 — `logs` subscriptions never report removed logs, and skip logs across a deep reorg.**
Verdict DIVERGENT. Severity correctness.
Ours: `eth-rpc-subscription-poll` derives log notifications from the blocks
`eth-rpc-subscription-new-heads` returns
(`src/api/public/subscriptions/subscriptions.lisp:229-237`), and that walk
returns `(list head)` alone whenever the cursor is not found within
`+eth-rpc-subscription-head-catchup-limit+` blocks or lies on a branch that was
reorged away (`:166-171`). `removed` never appears in the subscriptions source.
Reference: geth serves removed logs from a dedicated `RemovedLogsEvent` feed
(`eth/filters/filter_system.go`), so a subscriber sees each reorged-away log
again with `"removed": true`. Consequence: an indexer on `eth_subscribe` keeps
the logs of an orphaned branch permanently and silently misses the logs of the
blocks that replaced them. Notably the *filter* path does this correctly —
`engine-payload-store-notify-log-filters` is called with `:removed-p t` from the
reorg handler (`src/application/services/canonical-chain.lisp:109`) and
`eth-rpc-log-object` renders the flag
(`src/api/public/transactions/receipts.lisp:35`) — so the mechanism exists and
the subscription path simply does not use it.

**RPC-25 — Log topic limits are geth-compatible; range work remains locally bounded.**
Verdict PARTIAL. Severity performance.
`eth_getLogs`, `eth_newFilter`, and log subscriptions share enforcement of
geth's `maxTopics = 4` and `maxSubTopics = 1000`, including exact `-32000`
`exceed max topics` errors. The earlier audit also missed the existing local
5,000-block range-delta guard. That guard remains as a resource-safety policy and
is not claimed as geth parity. Within the bound, range processing is still
synchronous and materializes known blocks; streaming plus request
deadline/cancellation remains the open part of this finding.

**RPC-26 — Unknown log-filter `blockHash` returns an explicit error.**
Verdict RESOLVED. Severity cosmetic.
The shared validation path now returns JSON-RPC `-32000` with message
`unknown block` for both `eth_getLogs` and `eth_newFilter`. Regression tests
distinguish this from a known block with no matching logs.

**RPC-27 — `eth_subscribe syncing` is refused explicitly, and `newPendingTransactions` supports the full-transaction variant.**
Verdict (no gap). Recorded because the refusal is the pattern `PROJECT.md` asks
for: `eth-rpc-subscription-kind-from-name`
(`src/api/public/subscriptions/subscriptions.lisp:57-68`) names `syncing`
separately from an unknown name and says in a comment why. Subscription IDs are
16 random bytes (`:18-20`, `:54-55`), which is the geth width and is notably
better than the filter IDs in RPC-23. Delivery is polled once a second
(`+devnet-ws-poll-interval-seconds+`, `src/app/cli/devnet/ws-server.lisp:33`)
rather than pushed, which is a documented consequence of the node having no
change feed; it adds up to a second of latency to every notification and is worth
recording as a performance item, not a defect.

### debug and trace

**RPC-28 — The `debug_*` tracing surface is one method with one tracer.**
Verdict MISSING. Severity completeness.
Ours: `engine-rpc-handle-debug-trace-call`
(`src/api/public/debug/tracing.lisp:110`) renders call frames in `callTracer`
shape; there is no `debug_traceTransaction`, `debug_traceBlockByHash`,
`debug_traceBlockByNumber`, `debug_traceBlock`, or `debug_traceCallMany`, no
opcode-level struct logger, and no `prestateTracer`, `4byteTracer`,
`flatCallTracer`, `muxTracer`, or JS tracer. `tracerConfig` options such as
`onlyTopCall` and `withLog` are not read, and the rendered frames carry no
`revertReason`. Reference: geth `eth/tracers/api.go` for the methods and
`eth/tracers/native/` plus `eth/tracers/js/` for the tracers. Consequence: no
post-hoc analysis of a mined transaction is possible — `debug_traceCall`
re-simulates against current state, which is not the same thing. This is the
single largest method-count gap in the area and also the one with the least
consensus risk, which is why it is not higher in the summary.

**RPC-29 — The Parity-style `trace_*` module is absent.**
Verdict MISSING. Severity completeness.
Ours: no `trace_` prefix appears in `engine-rpc-public-method-p`
(`src/api/engine/methods.lisp:97-104`) or any dispatch table. Reference:
Nethermind serves the full module
(`src/Nethermind/Nethermind.JsonRpc/Modules/Trace/ITraceRpcModule.cs`:
`trace_call`, `trace_callMany`, `trace_rawTransaction`,
`trace_replayTransaction`, `trace_replayBlockTransactions`, `trace_block`,
`trace_filter`, `trace_get`, `trace_transaction`); geth does not serve it at all.
Consequence: block explorers and accounting tools built against Parity semantics
cannot use this node. Since one reference lacks it entirely, this is a
completeness item and arguably should be declined rather than implemented.

**RPC-30 — Several `debug_*` state and control methods are absent.**
Verdict MISSING. Severity completeness.
Ours: the raw-data getters (`debug_getRawHeader`, `debug_getRawBlock`,
`debug_getRawReceipts`, `debug_getRawTransaction`) are dispatched
(`src/api/public/dispatch/debug.lisp`); `debug_storageRangeAt`,
`debug_accountRange`, `debug_dumpBlock`, `debug_getBadBlocks`, `debug_dbGet`,
`debug_setHead`, and `debug_chainConfig` are not. Reference: geth
`eth/api_debug.go`. Consequence: `debug_setHead` is the one that matters
operationally — it is how an operator rewinds a node without wiping it, and it is
what the Hive suites use to reset state between cases. Overlaps state/storage.

### Operational modules

**RPC-31 — `admin_*` is three methods, and `admin_nodeInfo` is incomplete.**
Verdict MISSING. Severity completeness.
Ours: `admin_nodeInfo`, `admin_peers`, `admin_addPeer`
(`src/api/public/admin/admin.lisp:69` and neighbours), reached only when
`--http.api` names `admin` explicitly — which
`devnet-cli-public-api-method-filter` documents as a deliberate choice
(`src/app/cli/options/parsers.lisp:178-194`). Missing: `admin_removePeer`,
`admin_addTrustedPeer`, `admin_removeTrustedPeer`, `admin_startHTTP`,
`admin_stopHTTP`, `admin_startWS`, `admin_stopWS`, `admin_datadir`,
`admin_peerEvents`. The `nodeInfo` object also omits the per-protocol detail geth
nests under `protocols.eth` (`node/api.go`). Consequence: an operator cannot
disconnect a misbehaving peer over RPC, and tooling that reads
`protocols.eth.config` to learn the chain configuration finds nothing.
`admin_removePeer` is the one worth having. Overlaps networking/node-ops.

**RPC-32 — `txpool_inspect` uses an ASCII `x` where geth uses `×`.**
Verdict DIVERGENT. Severity cosmetic.
Ours: `engine-rpc-handle-txpool-inspect`
(`src/api/public/txpool/handlers.lisp:78` into
`src/api/public/txpool/views.lisp`). Reference: geth formats
`"%s: %v wei + %v gas × %v wei"` (`internal/ethapi/api.go`). Consequence: a
parser matching geth's exact string fails. Included only because the method's
entire contract is its string format.

**RPC-33 — `eth_config` / chain-configuration introspection is implemented.**
Verdict RESOLVED locally; pinned Hive rerun pending.
`engine-rpc-handle-eth-config` returns EIP-7910 current/next/last descriptors
with activation times, blob schedule, active precompiles, system contracts, and
fork ID. The no-future-fork path now emits JSON null rather than an unencodable
Lisp keyword. Focused and full cold unit tests cover both the scheduled and
terminal-fork shapes; the external rpc-compat case remains an explicit gate.

### Transport and JSON-RPC conformance

**RPC-34 — An internal handler error becomes HTTP 400 with a non-JSON body.**
Verdict DIVERGENT. Severity correctness.
Ours: `rpc-http-handle-request` wraps everything in a `handler-case` whose
catch-all returns `400 Bad Request` with the condition printed into the body
(`src/transport/http/handler.lisp:79-82`). The router handles
`engine-rpc-error`, `block-validation-error`, `invalid-parameters-error`,
`state-unavailable-error` and `storage-error` into proper JSON-RPC error objects
(`src/api/rpc/router.lisp:190-226`), so this path is reached only by a condition
outside that set — but any such condition escapes as a transport-level failure.
Reference: geth answers `200` with a JSON-RPC error body for handler errors and
reserves non-2xx for transport-level problems (`rpc/http.go`). Consequence: every
standard JSON-RPC client — ethers, web3.py, a consensus client's Engine
transport — reports "HTTP 400" and cannot surface the actual error, and the
printed condition text leaks internal detail to an unauthenticated caller. In a
batch, one such condition discards the whole batch's responses.

**RPC-35 — No batch item limit and no batch response size limit.**
Verdict MISSING. Severity performance (denial of service).
Ours: `rpc-handle-request-value` iterates the array with no bound
(`src/api/rpc/router.lisp:238-250`). Reference: geth defaults
`BatchRequestLimit` to 1000 and `BatchResponseMaxSize` to 25,000,000 bytes
(`node/defaults.go:68-69`, enforced at `rpc/handler.go:263-266`). Consequence: a
5 MB body — which the parser does allow, matching geth's `HTTPBodyLimit` — can
carry tens of thousands of `eth_getLogs` calls whose combined response is
unbounded. The CLI already accepts `--rpc.batch-request-limit` and
`--rpc.batch-response-max-size` and ignores both. The rest of JSON-RPC 2.0 is
handled correctly: notifications are omitted from batch results and produce an
empty body when alone (`router.lisp:188-189`, `src/api/rpc/json.lisp:12-16`), an
empty array is an invalid request, a non-object batch element yields a per-element
invalid-request object, and the error codes for parse (`-32700`), invalid request
(`-32600`), method not found (`-32601`), invalid params (`-32602`) and internal
(`-32603`) all match.

**RPC-36 — Every HTTP response closes the connection; no keep-alive, chunked encoding, or gzip.**
Verdict DIVERGENT. Severity performance.
Ours: `Connection: close` is written unconditionally
(`src/transport/http/policy.lisp:73`), and the parser reads a single
`Content-Length`-delimited body with no `Transfer-Encoding` or
`Content-Encoding` handling (`src/transport/http/parser.lisp`). Reference: geth
serves keep-alive by default with configurable timeouts
(`rpc.DefaultHTTPTimeouts`, `node/defaults.go:65`) and negotiates gzip.
Consequence: a consensus client driving the Engine API issues several requests
per slot and pays a TCP handshake for each; a caller that sends a chunked body,
which some HTTP libraries do by default, gets a parse failure. The correct
`Content-Length` on responses and the 5 MB body limit are both in place.

**RPC-37 — No IPC transport, but the flags for one are accepted.**
Verdict MISSING. Severity completeness.
Ours: `--ipcpath`, `--ipcapi` and `--ipcdisable` appear in the accepted-option
list (`src/app/cli/options/definitions.lisp:10-15`) and no IPC listener exists
anywhere in `src/transport/`. Reference: geth serves IPC by default on a Unix
socket (`node/node.go`); Nethermind likewise. Consequence: `geth attach`,
`cast --ipc`, and local tooling that prefers a socket over a port cannot connect.
The severity is completeness because HTTP and WebSocket cover the same ground —
but the silently-ignored flags are the real problem, and they are shared with
RPC-16 and RPC-35. Under `PROJECT.md`'s capability-gating principle an
unimplemented flag should be rejected at parse time with a message, not accepted.

**RPC-38 — Virtual hosts default to allowing any `Host` header.**
Verdict DIVERGENT. Severity correctness (security).
Ours: `engine-vhosts` and `http-vhosts` default to nil
(`src/app/cli/options/options.lisp:22-23`) and
`engine-rpc-http-host-allowed-p` allows everything when the list is empty
(`src/transport/http/policy.lisp:50`). Reference: geth defaults
`HTTPVirtualHosts` to `["localhost"]` (`node/defaults.go:64`) specifically to
blunt DNS rebinding. Consequence: a browser page can be induced to resolve an
attacker-controlled name to `127.0.0.1` and reach the RPC port. On the
authenticated Engine port the JWT still holds, so the exposure is the public
port.

**RPC-39 — The default public method set includes `debug_` and `txpool_`.**
Verdict DIVERGENT. Severity correctness (security).
Ours: with no `--http.api`, `devnet-cli-public-api-method-filter` returns
`engine-rpc-public-method-p` unfiltered
(`src/app/cli/options/parsers.lisp:185-186`), and that predicate admits `eth_`,
`net_`, `web3_`, `rpc_`, `txpool_` and `debug_`
(`src/api/engine/methods.lisp:97-104`). Reference: geth's default HTTP and
WebSocket module lists are `["net", "web3"]` (`node/defaults.go:63`, `:67`).
Consequence: `debug_getRawReceipts` and `debug_traceCall` — the latter being an
uncapped EVM execution, per RPC-16 — are reachable on a default-open port. The
same file's docstring explains at length why `admin_` was excluded from that
predicate; the reasoning applies to `debug_` and was not extended to it.

**RPC-40 — The WebSocket implementation is sound.**
Verdict (no gap). Recorded because it is the transport least likely to be
audited again. Masking is enforced asymmetrically and documented as a protocol
error rather than a leniency (`src/transport/websocket/frames.lisp:9-15`),
assembled messages are bounded at 16 MB against a 64-bit length field
(`:50-54`), control-frame payloads are bounded at the RFC's 125 bytes (`:45-48`),
ping, pong and close opcodes are all present (`:38-43`), and origins are checked
at handshake. geth's limit is 32 MB (`rpc/websocket.go:259`); ours being lower is
a policy choice, not a gap.

## Remediation plan

Ordered by what unblocks the most, not by size. Each item names the verification
that would prove it fixed. "Hive" refers to the `ethereum/hive` suites; the
`engine-api` and `engine-auth` suites are the ones that exercise this area, and
`rpc-compat` covers the public surface against `execution-apis` vectors.

1. **DONE — Report real sync progress from `eth_syncing` (S).** RPC-01.
   Cold unit and integration coverage now exercises remote/forkchoice progress,
   known target heights, genesis, and store-guard contention. The live Hoodi
   gate remains the deployment-level proof on its pinned revision.
2. **Convert Engine version and attribute violations to RPC errors (M).**
   RPC-02, RPC-03, RPC-04, RPC-05. No dependencies, and they share one shape:
   raise `engine-rpc-fail` with `-32602`, `-38003` or `-38005` where the code
   currently returns an `INVALID` status or a generic `block-validation-fail`.
   Do RPC-03 by giving V1 and V2 the treatment V3 already has. Verify with
   `tests/core-engine-rpc-*.lisp` cases per method and version, then the Hive
   `engine-api` suite, which asserts these codes directly.
3. **Bound and make recoverable the invalid-ancestor cache (M).** RPC-12.
   No dependencies. Port geth's three mechanisms: a hit counter with eviction,
   a capacity cap on the tipset map, and `0x0` for a pre-merge last-valid
   ancestor. Verify with a test that marks a block invalid, replays it past the
   eviction threshold, and asserts the node reconsiders — this is the case that
   currently requires a restart.
4. **Fetch the head a `forkchoiceUpdated` names (M).** RPC-11. Depends on
   nothing in this area but touches the sync layer, so coordinate with the
   networking audit. Record the unknown head the way `newPayload` records an
   unexecutable block and let `devnet-peer-fill-sync-gaps` pick it up. Verify by
   restarting a devnet node behind a live consensus client and confirming it
   leaves `SYNCING`; the Hive `engine-api` sync cases cover the same path.
5. **Populate `blockValue`, and decide the blob-bundle question (M).** RPC-07,
   RPC-06. `blockValue` is self-contained: sum the fees credited during the
   build. The bundle needs the block-building side to select blob transactions
   and retain their sidecars, so it depends on the txpool/block-building work and
   should be tracked there. Until it is, the honest interim position is to
   decline `getPayloadV3` and later rather than return an empty bundle — which is
   what the capability-gating principle would suggest. Verify with a devnet slot
   that includes a blob transaction and a consensus client that publishes it.
6. **Give filters random IDs and a deadline (S).** RPC-23. No dependencies, but
   changing the ID to a hex string means `eth-rpc-filter-id-param` can no longer
   parse it as a quantity, so the change is not purely additive. Verify with
   cases in `tests/core-public-rpc-log-filter-tests.lisp` and
   `tests/core-public-rpc-block-filter-tests.lisp` for expiry, for a poll
   resetting the deadline, and for an unknown ID.
7. **Emit removed logs to subscribers (M).** RPC-24. Depends on nothing; the
   feed already exists for filters. Route the reorg notification that
   `canonical-chain.lisp:109` sends to filters into the subscription poll as
   well, and make the `newHeads` walk report the replacing branch rather than
   only its tip. Verify with a `tests/websocket-tests.lisp` case that induces a
   reorg and asserts both the `removed: true` logs and the replacement logs
   arrive.
8. **PARTIAL — Cap calls and bound log queries (S).** RPC-16, RPC-25,
   RPC-35. `maxTopics` and `maxSubTopics` now match geth and the pre-existing
   local block-range guard remains covered. Still wire call, batch, and response
   limits, then replace synchronous block-list materialization with streaming
   plus a request deadline/cancellation policy before considering the range
   behavior complete.
9. **Reject flags we do not implement (S).** RPC-37, and the ignored options
   named in RPC-16 and RPC-35 that step 8 does not wire. Depends on step 8, so
    that only genuinely unimplemented flags remain. Verify in
    `tests/cli-phase-a-devnet-argument-tests.lisp`: naming `--ipcpath` should
    fail with a message saying IPC is not implemented.
10. **Return JSON-RPC errors instead of HTTP 400 for handler failures (S).**
    RPC-34. No dependencies. Narrow the catch-all in
    `src/transport/http/handler.lisp:79-82` so an unexpected condition becomes a
    `-32603` body at status 200, and reserve 400 for a malformed request line or
    headers. Verify with a `tests/core-http-service-tests.lisp` case that forces
    an internal condition and asserts a 200 with a JSON-RPC error object.
11. **Default vhosts to localhost, and drop `debug_` from the default module set (S).**
    RPC-38, RPC-39. No dependencies. Both are one-line policy changes with a
    docstring; both will change behaviour for existing devnet invocations, so
    they belong in one change with a note.
12. **Add state and block overrides, then `eth_simulateV1` (L, then M).**
    RPC-15, then RPC-17. The overrides are a prerequisite. Verify against the
    `execution-apis` override vectors and the `rpc-compat` suite.
13. **Serve `eth_config` (S).** RPC-33. No dependencies; everything it reports
    is in `chain-config`. Verify against the EIP-7910 vectors in
    `execution-apis`.
14. **DONE — Verify `blobGasUsed` and `blobGasPrice` on blob receipts (S).**
    RPC-18. The implementation predated this audit revision; focused regression
    coverage now proves both receipt RPCs, transaction-local blob gas, contextual
    blob price, and legacy omission. Keep the broader `rpc-compat` suite as the
    external conformance gate.
15. **Build a real pending block (L).** RPC-20. Depends on the block-building
    path being callable outside the Engine API. This is the largest
    wallet-facing item and the one most entangled with another area, so it is
    late despite mattering to ordinary callers.
16. **Add a gas-price oracle (M).** RPC-21. No dependencies. Sample recent
    blocks at a configurable percentile; `eth_feeHistory` should share the
    sampler. Verify with a devnet chain carrying a spread of tips and an
    assertion that the suggestion falls between the observed minimum and
    maximum.
17. **Extend tracing (L).** RPC-28, then RPC-30, then RPC-29 if at all. Historic
    tracing needs the ability to re-execute a mined block against its parent
    state, which is the real cost. `debug_setHead` (RPC-30) is worth pulling
    forward on its own, because Hive uses it. `trace_*` (RPC-29) should probably
    be declined rather than built, since geth does not serve it.
18. **The remaining completeness items (S each).** RPC-10, RPC-19, RPC-26,
    RPC-31, RPC-32, and the `getBlobs` fork gating in RPC-09. Independent of
    each other; batch them.

Steps 1 through 4 are what a consensus client needs. Steps 6 through 11 are what
a shared or exposed node needs. Everything after that is breadth.

## Out of scope and left unverified

Out of scope for this audit, by area:

- Whether executed blocks are *correct* — gas, state roots, receipts as computed
  rather than as encoded. Covered by `docs/gas-parity.md` and the block-execution
  audit.
- The transaction pool's admission, eviction, and pricing rules. The RPC surface
  over the pool (`txpool_*`, `eth_sendRawTransaction`) was read; the policy
  behind it was not.
- The devp2p and discovery layers, including `admin_*`'s peering backend beyond
  the shape of its RPC responses.
- Storage, pruning, and historical-state availability, except where an RPC error
  path depends on them.
- Metrics, logging, and the telemetry sink.

Left unverified within this area, and named rather than glossed:

- **`eth_getProof`** — the dispatch entry was read; the result shape
  (`accountProof`, `storageProof` nesting, `codeHash` presence) was not compared
  against geth's `AccountResult`.
- **`eth_createAccessList`** result shape, including whether the returned
  `gasUsed` accounts for the list itself as geth's does.
- **`eth_getRawTransactionByHash`** and the `debug_getRaw*` family: presence
  confirmed, encoding not compared byte for byte against geth's.
- **`eth_blobBaseFee`** head-versus-successor question (RPC-22).
- **Prepared-payload cache bounds** (RPC-08): whether
  `src/storage/chain-store/service/cache.lisp` caps the number of stored prepared
  payloads was not established, so the memory consequence of transaction-derived
  payload IDs is stated as a risk rather than a fact.
- **Whether a blob transaction can reach the pending list** (RPC-06). This
  determines whether the always-empty `blobsBundle` is merely a missing
  capability or an inconsistency, and it is the most important of the unverified
  items.
- **Nethermind coverage of the newest Engine methods** — `getPayloadV6`,
  `getPayloadBodiesBy*V2`, `getBlobsV2/V3/V4`, `hasBlobs`. The sparse checkout was
  read for the module interfaces, not exhaustively for version suffixes, so those
  cells are marked UNVERIFIED rather than guessed.
- **Nethermind's Engine payload-status and `latestValidHash` rules.** Every
  Engine semantics finding above cites geth on the reference side. Nethermind was
  read for method presence only, so a claim that a behaviour diverges from *both*
  references is not made for the Engine API — the findings say geth.
- **Runtime confirmation of anything.** This audit read source and did not
  execute the client. No test was run and no warm-image eval was made, so every
  finding rests on code reading rather than on observed behaviour. Where reading
  was not enough to settle a question, the question is listed here rather than
  answered.
