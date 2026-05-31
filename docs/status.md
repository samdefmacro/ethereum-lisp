# Status Log

This file preserves detailed historical implementation notes that were moved out
of `docs/roadmap.md`. The roadmap should stay strategic; this file can retain
long-form implementation history when it is still useful for orientation.

## Section 7: Engine API and JSON-RPC

Status: initial local Engine payload projection is present. Blocks can be
converted into geth-shaped `ExecutableData` payload envelopes, including
header fields, encoded transactions, optional withdrawals, optional execution
requests, blob gas counters, and Amsterdam slot numbers. The reverse raw-transaction path has begun
with legacy, EIP-2930 access-list, EIP-1559 dynamic-fee, EIP-4844 blob, and
EIP-7702 set-code transaction RLP decoding, so Engine payload transaction bytes
can start feeding back into local transaction/root validation; `ExecutableData`
now has a helper that decodes its transaction byte list back into local
transaction envelopes and a first no-hash conversion path back into local block
headers/bodies, plus a hash-checking wrapper for the normal `newPayload`
payload import path. The reverse Engine import path also checks supplied
blob `versionedHashes` against decoded blob transactions, and has a first
stateless `newPayload` parameter-status wrapper that maps local validation
errors into Engine-style payload status objects. Version-specific `newPayload`
parameter gates now cover V1 through V5 fork requirements before block import,
including Amsterdam `slotNumber` and `blockAccessList` requirements for
`engine_newPayloadV5`.
A small in-memory Engine payload store now models known-block, missing-parent,
missing-parent-state, and invalid-ancestor status branches for the future
database-backed import path. It can also iterate retained account projections
for state-available blocks so execution can rebuild a parent `state-db` from
balance, nonce, code, and storage indexes before importing a child payload.
The execution layer now has a narrow Engine payload import helper that runs
ready-parent payload blocks through the signed block atomic commit path, and
the memory `newPayload` status path can inject that importer and translate
post-execution commitment failures into Engine `INVALID` status without
storing the bad block; tests cover state-root, receipts-root, logs-bloom, and
gas-used mismatches with `latestValidHash` pointing at the known parent. That
import hook is now threaded through parsed
JSON-RPC objects, request strings, HTTP request strings, stream handling, and
the HTTP service configuration, so configured services can execute
ready-parent `engine_newPayload` imports. The production Engine HTTP service
constructor now selects that executable importer by default when the execution
package is loaded, while direct request helpers can still run the compatibility
store-only path by omitting an importer. A parsed JSON-RPC object dispatcher
can now route `engine_newPayloadV1` through `engine_newPayloadV5` calls into
that store and
return Engine-style payload status result objects. The same core can now encode
single and batch JSON-RPC response strings for request-string entry points,
and advertises the currently implemented `engine_newPayloadV1` through
`engine_newPayloadV5` plus `engine_forkchoiceUpdatedV1`,
`engine_forkchoiceUpdatedV2`,
`engine_forkchoiceUpdatedV3`,
`engine_forkchoiceUpdatedV4`,
`engine_getClientVersionV1`, and
`engine_exchangeTransitionConfigurationV1` methods through
`engine_exchangeCapabilities`; `engine_getClientVersionV1` now returns the
local Common Lisp client identity, and
`engine_exchangeTransitionConfigurationV1` returns the local terminal
difficulty with zero terminal-block defaults. `engine_forkchoiceUpdatedV1` now
parses forkchoice state and V1 payload attributes, maps known memory-store
heads to `VALID`, unknown heads to `SYNCING`, and zero heads or cached invalid
tipsets to `INVALID`; nonzero safe/finalized checkpoint hashes are also checked
against the local memory store and rejected with the Engine API `Invalid
forkchoice state` error code `-38002` when unavailable, and valid
head/safe/finalized checkpoints are retained for public block-tag resolution. It can
prepare a deterministic in-memory empty child payload when V1 payload
attributes are supplied for a valid head. The prepared payload is keyed by an 8-byte
Engine-style payload id and can be fetched through `engine_getPayloadV1`, which
returns the execution payload object for the prepared block and reports missing
ids with the Engine API `Unknown payload` error code `-38001`.
`engine_forkchoiceUpdatedV2` now reuses the same forkchoice status machinery,
prepares deterministic V2 child payloads, and carries PayloadAttributesV2
withdrawals into the prepared block. `engine_forkchoiceUpdatedV3` extends that
prepared-payload path with required PayloadAttributesV3
`parentBeaconBlockRoot`, retaining it on the prepared Cancun header and
initializing zero blob-gas fields for `engine_getPayloadV3`.
`engine_forkchoiceUpdatedV4` now adds required PayloadAttributesV4
`slotNumber`, carries it into the prepared Amsterdam header, and exposes it
through the prepared-payload `engine_getPayloadV4` path. The first
`engine_getPayloadV2` path is
also wired through the same prepared-payload
store and returns a geth/Nethermind-shaped payload envelope with
`executionPayload` and `blockValue`; `engine_getPayloadV3` now returns the
Cancun envelope shape with an empty V1 `blobsBundle` and explicit
`shouldOverrideBuilder` false marker for locally prepared payloads, and
`engine_getPayloadV4` carries Prague `executionRequests` through the same
envelope path. Prepared payloads can now retain blob sidecar bundles for
`engine_getPayloadV5`, which returns the Osaka envelope with serialized
V2 `blobsBundle` data and execution requests. `engine_getPayloadV6` now exposes
Amsterdam payload fields, including `slotNumber` and retained encoded
`blockAccessList` RLP, alongside the same V2 blob bundle envelope.
`engine_getPayloadBodiesByHashV1` can now
serve transaction/withdrawal bodies from the same memory store, preserving
request order, returning `null` for unknown hashes, and rejecting over-1024
body requests with Engine `Too large request` error code `-38004`.
`engine_getPayloadBodiesByHashV2` reuses that path and includes retained
encoded Amsterdam block-access-list RLP as `blockAccessList` when present.
`engine_getPayloadBodiesByRangeV1` is also present with a first memory-store
block-number index, positive start/count validation, head-number clipping, and
the same 1024-body limit; `engine_getPayloadBodiesByRangeV2` now follows that
same indexed range path while surfacing retained block-access-list RLP. Payload build
requests with semantically invalid V1 attributes, such as a timestamp not
greater than the parent head, now report Engine API `Invalid payload attributes`
with error code `-38003`. `engine_getBlobsV1` now has a first memory-store
blob sidecar index keyed by KZG versioned hash, returns V1 `blob`/`proof`
objects in request order, preserves `null` for missing blob data, advertises
the capability, and rejects over-128 blob requests with Engine `Too large
request` error code `-38004`. The same memory index now also accepts Osaka
cell-proof sidecars with 128 proofs per blob and serves
`engine_getBlobsV2`/`engine_getBlobsV3`: V2 returns a full ordered
`blob`/`proofs` list only when every requested blob is available and otherwise
returns `null`, while V3 keeps request order and allows per-item `null`
partial responses. The first public `eth_*` read methods are now wired through
the same JSON-RPC dispatcher: `web3_clientVersion` returns the local client
identity string, `web3_sha3` computes Keccak-256 over supplied hex bytes,
`net_version` returns the configured network id as a decimal string, and
`net_listening`/`net_peerCount` report the current non-networked local node
state as JSON `false` and `0x0`,
`eth_chainId` returns the configured EIP-155
chain id, `eth_blockNumber` returns the current forkchoice head number with a
memory-store maximum fallback,
`eth_protocolVersion` reports the current highest supported devp2p `eth`
protocol as `0x46`/ETH70,
`eth_syncing` returns JSON `false` for the current local non-networked
memory-store execution node, `eth_accounts` returns an empty local-wallet
account list until wallet support exists, `eth_coinbase` returns the zero
address for the current non-mining local node, `eth_mining` reports JSON
`false` and `eth_hashrate` reports `0x0` for that non-mining mode,
`eth_baseFee` estimates the
next block's EIP-1559 base fee from the current memory-store head,
`eth_maxPriorityFeePerGas` exposes the current deterministic local tip
suggestion, and `eth_gasPrice` combines that tip with the current head base fee
when present for legacy transaction callers;
`eth_blobBaseFee` exposes the current head blob base fee when Cancun blob-gas
fields are present, and `eth_feeHistory` now returns a first memory-store fee
history window with base fee progression, gas-used ratios, optional blob fee
history, retained forkchoice `latest`/`pending` head-tag resolution plus
`safe`/`finalized` checkpoints, and zero-filled reward percentile placeholders
until transaction reward accounting is indexed,
`eth_getBalance` can read retained per-block account balance snapshots by
block tag, number, or hash while returning `null` when the block or retained
state is unavailable, `eth_getTransactionCount` does the same for retained
account nonce snapshots and now folds local pending txpool transactions into
the `"pending"` nonce result, `eth_getCode` returns retained account bytecode
snapshots with empty code for missing accounts, `eth_getStorageAt` reads
retained account storage slot snapshots as 32-byte words with zero words for
missing accounts/slots, `eth_call` executes a first legacy-style call object
against retained block state, returning EVM output/revert data while discarding
state writes, `eth_estimateGas` reuses that retained-state simulation to cap
estimates by the block/request gas limit, reject reverting calls, and
binary-search a first simple transfer/contract-call gas result,
`eth_createAccessList` surfaces touched accounts/storage keys from the same
simulation as a first geth-shaped `accessList`/`gasUsed` result, and
`eth_getHeaderByNumber`/`eth_getHeaderByHash` can return canonical memory-store
headers for `latest`, `pending`, `safe`, `finalized`, `earliest`, hex block
quantities, or block hashes, with `safe`/`finalized` following retained
forkchoice checkpoints when present, using the geth-style header object shape while
returning JSON `null` for unknown blocks. `eth_getBlockByNumber`/`eth_getBlockByHash` now handle both the
transaction-hash form (`fullTx=false`) and full mined transaction object form
(`fullTx=true`) for memory-store blocks, adding block size, ommer hashes, and
Shanghai withdrawals while returning `null` for unknown block ids. The matching
`eth_getBlockTransactionCountByNumber` and
`eth_getBlockTransactionCountByHash` read endpoints now return transaction
counts for canonical memory-store blocks and JSON `null` for unknown blocks.
`eth_getUncleCountByBlockNumber` and `eth_getUncleCountByBlockHash` likewise
return ommer counts from the in-memory block body with the same unknown-block
`null` behavior. `eth_getUncleByBlockNumberAndIndex` and
`eth_getUncleByBlockHashAndIndex` can now return header-only ommer block
objects from memory-store blocks, with JSON `null` for unknown blocks and
out-of-range ommer indexes. Raw transaction lookup by block id and index is now present
for both `eth_getRawTransactionByBlockNumberAndIndex` and
`eth_getRawTransactionByBlockHashAndIndex`, returning consensus transaction
bytes or JSON `null` for unknown blocks and out-of-range indexes. The
structured companions `eth_getTransactionByBlockNumberAndIndex` and
`eth_getTransactionByBlockHashAndIndex` now return mined transaction RPC
objects with block location metadata, effective gas price, typed transaction
fee/access-list fields, and the same unknown/out-of-range `null` behavior.
The in-memory payload store now also indexes transactions by hash as blocks are
inserted, enabling `eth_getTransactionByHash` and `eth_getRawTransactionByHash`
for known canonical memory-store transactions with JSON `null` for unknown
hashes. Receipts supplied with memory-store blocks are retained alongside that
transaction index, enabling `eth_getTransactionReceipt` with mined receipt
metadata, gas accounting, logs, logs bloom, typed transaction status, and
effective gas price. `eth_getBlockReceipts` now exposes the same retained
receipt objects by block tag, number, or hash for known memory-store blocks;
`eth_getLogs` can scan retained memory-store receipts by block range or
`blockHash`, address filter, and positional topic filters, returning canonical
log objects and empty JSON arrays for no matches. The first stateful log
filter methods are also present: `eth_newFilter` registers memory-store log
criteria, `eth_getFilterLogs` replays the matching retained logs,
`eth_getFilterChanges` advances a per-filter log cursor for polling retained
block logs, `eth_newBlockFilter` registers a head cursor for polling newly
retained block hashes through the same changes endpoint, and
`eth_newPendingTransactionFilter` registers a pending transaction hash queue
for locally submitted pending transactions. `eth_uninstallFilter` removes
registered filters while returning false for unknown ids. `eth_sendRawTransaction` now
decodes raw transaction bytes, records the decoded transaction in a local
pending-transaction placeholder, and returns the transaction hash; locally
submitted pending raw bytes are also visible through
`eth_getRawTransactionByHash`, while `eth_getTransactionByHash` now returns a
geth-style pending transaction object with null block location metadata for
those locally submitted transactions; duplicate submissions of the same
pending hash are idempotent and do not emit duplicate pending-filter changes,
while a later retained block containing the same transaction hash removes the
local pending placeholder so mined lookup metadata takes over, and resubmitting
that mined raw transaction returns its hash without re-adding it to the pending
pool. `eth_pendingTransactions` exposes the
same local pending placeholder as a deterministic hash-sorted array of pending
transaction objects, and `txpool_status` reports the local pending count with
zero queued transactions until a queued pool exists. `txpool_content` now
exposes the same local pending transactions grouped by sender address and
decimal nonce, with an empty queued object placeholder; `txpool_contentFrom`
returns the same nonce-keyed pending/queued shape filtered to one sender
address, and `txpool_inspect` exposes a matching sender/nonce grouping with
geth-style human-readable transaction summaries. Full txpool admission rules
remain a later networking/txpool slice, but raw local submissions now run a
basic admission preflight for fork transaction type support, scalar/fee/nonce
shapes, intrinsic gas, access-list/blob/set-code field shapes, and
non-delegation sender code before entering pending. When the latest head has
retained account state, raw submissions also reject transactions below the
retained sender nonce and insufficient retained sender balance for the
maximum upfront execution/blob gas plus value. Same-sender same-nonce pending
replacements now follow a geth-style 10% fee bump policy, replacing the
indexed transaction only when both fee cap and priority fee clear the bump
threshold. The txpool object now also has queued, basefee, and blob placeholder
subpools, and `txpool_*` RPC views read queued data from the queued subpool
instead of hard-coded empty placeholders. Public JSON-RPC and txpool
placeholder handlers have also been split out of `src/core.lisp` into
`src/public-rpc.lisp` behind a dedicated public method dispatcher, leaving the
core RPC path focused on the generic JSON-RPC envelope, Engine/Public dispatch
delegation, and HTTP serving shell.
Filter lifecycle scope is intentionally polling-only for now. The current
filter ids belong to the JSON-RPC polling methods (`eth_newFilter`,
`eth_newBlockFilter`, `eth_newPendingTransactionFilter`,
`eth_getFilterChanges`, `eth_getFilterLogs`, and `eth_uninstallFilter`) and
represent in-memory cursors or pending hash queues. Future WebSocket
subscriptions should use a separate subscription registry and transport-owned
lifetime: subscription ids are created by `eth_subscribe`, removed by
`eth_unsubscribe` or connection close, and should stream events without
advancing polling filter cursors. Before subscriptions land, the polling
filter store should gain explicit timeout/cleanup policy compatible with
geth-style filter expiry, while keeping `eth_uninstallFilter` idempotent for
unknown or expired polling ids.
A first HTTP POST adapter now
validates request method and JSON content type before handing the body to the
shared JSON-RPC dispatcher. The HTTP adapter can also enforce Engine-style JWT
Bearer authentication with HS256 signatures, 32-byte secrets, `iat` freshness,
and optional `exp` rejection. A single-connection stream adapter now reads one
HTTP request from an input stream and writes the response to an output stream,
and an Engine HTTP service configuration object now bundles the authenticated
endpoint defaults, payload store, chain config, JWT secret, and clock provider,
while a small listener/connection accept loop can now serve repeated stream
connections and close them deterministically. The outer local transport shell is
now present for SBCL: a `sb-bsd-sockets` TCP listener adapts localhost socket
connections into the same stream service and is covered by an end-to-end
JSON-RPC socket test.

Networking, discovery, and txpool sophistication are intentionally later than
deterministic execution correctness.

Future node shell and network work should start from a narrow architecture
slice rather than a full peer-to-peer client. The first devp2p milestone is to
model identities and advertised capabilities: local node key, ENR fields,
listening endpoints, fork id, supported `eth`/`snap` protocol versions, and
chain identity. Discovery should come next as an isolated table/update path
that can parse and persist candidate ENRs before any RLPx session is trusted.
Only after that should RLPx handshakes, `eth` status exchange, block/header
requests, transaction propagation, `snap` state range requests, and peer
scoring be wired into sync or txpool code. Peer scoring should begin with
small deterministic penalties for bad status, invalid responses, timeout, and
duplicate useless data, leaving reputation persistence and DoS policy for a
later production-storage slice.

The first sync design should follow a staged pipeline with explicit unwind
boundaries. A minimal full/snap-compatible plan is: header download and
validation; canonical header selection; body download; sender recovery;
execution into an isolated state batch; receipt/log derivation; canonical
transaction/receipt/log indexes; and final forkchoice checkpoint publication.
Each stage needs a persisted progress marker and an unwind function that can
roll back to a parent block when forkchoice changes or execution fails. Snap
sync can later replace the early execution-state population with account and
storage range ingestion, but it should still feed the same execution,
receipt, and index stages once state is available.

Hive compatibility should be treated as a runner contract around the local
node shell. The client needs a command that loads a supplied genesis, starts
authenticated Engine API and public JSON-RPC listeners on requested ports,
prints machine-readable endpoint/JWT/log locations, and shuts down cleanly on
process termination. Hive-facing logs should include startup config, fork
activation, Engine payload status, JSON-RPC method errors, and final shutdown
state without requiring interactive REPL access.

History retention should be explicit before any pruning implementation. Archive
mode keeps all historical state, receipts, bodies, logs, and indexes. Full mode
keeps all canonical block bodies and receipts but may keep only recent state
snapshots plus enough trie/storage history for configured reorg depth. Pruned
mode may drop historical state and old receipts/log indexes beyond a retention
window, but public RPC methods that depend on dropped data must return the same
class of missing-data/null/error responses consistently. `eth_getProof`,
historical `eth_call`, historical balance/storage/code reads, log scans,
receipts, and transaction lookups must each declare which retention modes they
support before pruning is enabled.
