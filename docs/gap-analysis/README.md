# Gap analysis — index and remediation plan

Six audits of this client ran in parallel on 2026-07-28, each covering one area,
each comparing our code against two pinned reference clients. This document is
the entry point to those six and the plan of record derived from them: one
ranked table of every finding, the priority tiers that order them, a
deduplicated work programme, sequenced phases, and the decisions that belong to
the project owner rather than to an auditor.

`PROJECT.md` warns against manufacturing status snapshots, roadmaps, and phase
records as a side effect of feature work. This document is not that. It is a
directly requested deliverable: the user asked for a prioritized cross-cutting
remediation plan over the six completed audits, and this is it. It is also not a
changelog — nothing described below has been implemented, and no statement here
should be read as a claim that a fix is in the tree.

## The six areas

| Area | Document | Finding prefix | Findings |
| --- | --- | --- | --- |
| EVM, precompiles, gas, fork activation | [evm-and-gas.md](evm-and-gas.md) | `EVM-nn` | 18 |
| Domain types, validation, block execution | [block-execution-and-types.md](block-execution-and-types.md) | `EXEC-nn` | 16 |
| State, trie, storage | [state-trie-storage.md](state-trie-storage.md) | `STORE-nn` | 24 |
| JSON-RPC and Engine API | [rpc-and-engine.md](rpc-and-engine.md) | `RPC-nn` | 40 |
| Networking, discovery, sync | [networking-and-sync.md](networking-and-sync.md) | `NET-nn` | 24 |
| Txpool, block building, node operations | [txpool-building-and-ops.md](txpool-building-and-ops.md) | `POOL-nn`, `BUILD-nn`, `OPS-nn` | 34 |

156 identifiers in total. Five of them (`EVM-17`, `RPC-13`, `RPC-14`, `RPC-27`,
`RPC-40`) record something that is *not* a gap, deliberately, so a later pass
does not rediscover it or "fix" it into a divergence. That leaves 151 gaps.

`docs/gas-parity.md` is a seventh, earlier audit of gas arithmetic specifically.
It is not folded into the table below because it uses its own numbering and its
strongest results are differential tests this round could not re-run. Three of
its open items are re-attributed here: item 1.3 is resolved by `EXEC-01`, item
3.1 is extended by `EXEC-15`, and item 4.3 is widened by `EVM-08`. Item 5.5 is
corrected by `EVM-03` — the relevant EIP is 7954, not 7907.

## References

| Side | Version | Commit | Read on |
| --- | --- | --- | --- |
| go-ethereum | 1.17.6-unstable | `38271784c2b31926563806da9a2e023b88f5e7a8` | 2026-07-28 |
| Nethermind | 1.40.0 | `e52dc19a56a46f58170a730822580774d403c838` (sparse: `src/Nethermind`) | 2026-07-28 |

Both are local checkouts under `references/`. Both commit hashes were confirmed
on the host for this document. **The checkouts are untracked working-tree
clones, not committed to the repository**, so a fresh clone or a new worktree
has no `references/` directory and cannot re-check any citation below without
fetching them again. Under `PROJECT.md`'s rule that a parity claim must name the
exact version and code path, that makes the two hashes above load-bearing.

Our own side was read at three different working-tree commits, which is worth
recording rather than flattening: the block-execution and RPC audits pin
`28e9912072135bebc3f49bc75226d6fed68dc21f`, the networking audit pins
`c9193bce5292a48e4cdb89b51409d31a8d716d75`, and the EVM, state/storage and
txpool audits say "the working tree of 2026-07-28" without a hash. Function and
constant names are the durable identifiers throughout; prefer them over line
numbers.

## Evidence quality — how much weight each finding carries

This distinction is the most important thing to carry out of this document. The
six audits did not have equal evidence available, and the difference is large.

**Source-read throughout, nothing executed.** The EVM, block-execution,
state/storage and RPC audits each ran with no warm dev image available — all
four record that `scripts/dev.sh status` reported the container and image
absent and that they were not permitted to start it. Not one number in those
four documents came out of a running image. `evm-and-gas.md` states it in its
own words: "Do not carry any finding here into a commit message as verified."
This covers `EVM-01`…`EVM-18`, `EXEC-01`…`EXEC-16`, `STORE-01`…`STORE-24`, and
`RPC-01`…`RPC-40` — 98 of the 156 identifiers.

Structural claims from source reading are conclusive on their own: an opcode
byte that no dispatch branch reaches, a function signature that takes no
`chain-rules` argument, a constant with the wrong value, an exported function
with no caller. Claims about magnitude are not, and the audits mark those
`UNVERIFIED` where the magnitude decides the severity.

**Partly executed.** The networking audit had the warm image for the first part
of its run and lost it to another session partway through. Six of its claims are
executed and it says which: the class precedence list of
`SB-KERNEL::CONTROL-STACK-EXHAUSTED`, the byte cost of nested-list payloads at
depth 20000 and 21700, `+ecies-overhead+` = 113, that `snappy-compress` emits
literal runs only, and that no `discv5` or `snap` symbol exists in the image.
Everything else in that document is source-read, including `NET-11`, which it
flags as the one item a small eval would have settled.

The txpool audit had the image for exactly one claim: the blob-transaction
pooling and selection behaviour behind `POOL-13` and `BUILD-08` was executed —
a signed blob transaction was refused by the pending, queued and basefee
subpools, accepted by the blob subpool, and then absent from
`engine-payload-store-pending-mining-transactions`. Its image then died with
exit 137 (out of memory) and took the shared container down. **Every other claim
in that document is a source reading**, including the discarded-flag count of 56.

**Executed by the coordinator.** Four facts were established by evaluating forms
in the warm image, not by reading, and they outrank any source-only claim they
touch:

1. `rlp-decode` (`src/foundation/rlp.lisp:72`) has no depth limit. Depth 1000
   decodes. Depth 20000 (59,791 bytes of input) and depth 200000 both signal
   `SB-KERNEL::CONTROL-STACK-EXHAUSTED`, which is a `storage-condition` and not
   an `error`; `rg 'storage-condition|serious-condition' src/` returns zero
   hits, so nothing in the tree catches it. The networking audit established —
   also by execution — that this is reachable **before any authentication**
   through the RLPx recipient handshake, that the ECIES plaintext budget inside
   a maximal auth packet is 65,422 bytes while depth 21700 costs 64,888, that
   the attacker needs nothing but our enode because our static public key *is*
   our node id, and that the consequence under `sbcl --script` is **whole-process
   death**, not a dropped session. This settles `EXEC-14`, which the
   block-execution audit could only record as `UNVERIFIED`.
2. `transaction-validation-error` (`src/runtime/execution/contract.lisp:5`)
   derives directly from `error` and not from the `block-validation-error`
   hierarchy: `(subtypep 'transaction-validation-error 'block-validation-error)`
   returns `NIL`. The payload-build handler at
   `src/api/engine/forkchoice.lisp:190` catches only `block-validation-error`,
   so an insufficient-balance or bad-nonce transaction in the selected list
   escapes it entirely. This confirms the second half of `BUILD-01`.
3. `validate-blob-sidecar-fields` and `validate-blob-sidecar-kzg-proofs`
   (`src/protocol/kzg/validation.lisp:87,68`) have no caller anywhere in `src/`
   outside package export lists. This confirms `EXEC-11` and `POOL-14`.
4. The two reference commits above, and that `references/` is untracked.

**No finding in any of the six documents has been confirmed against a reference
client at runtime.** Every reference-side claim is a reading of geth 1.17.6 or
Nethermind 1.40.0 source at the commits named above. Nothing was compared
against a running geth, a running Nethermind, a Hive suite, or an EEST fixture
execution. Where an audit says "both references agree and we differ", that is
two source readings and our source reading — which is strong evidence for a
structural difference and no evidence at all about what either binary does.

## Ranked findings

Every identifier from all six documents, ranked by the priority tiers defined in
the next section rather than by area. Verdict and severity are each audit's own,
abbreviated; where an audit gave a compound severity the dominant term is shown
and the qualifier appears in the statement. **Rank is this document's; severity
is not.** Several findings are ranked above or below their own audit's severity
label because reachability or cost of fix differs across the tree, and where
that happens the tier rationale says so.

Severity tokens: `remote-DoS`, `consensus` (consensus-breaking), `CC-integration`
(breaks consensus-client integration), `blocks-production`
(loses-money-or-blocks-validation), `correctness`, `durability`, `completeness`,
`performance`, `operability`, `cosmetic`, `no gap`.

### Tier 1 — Remote process kill, no credential required

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [NET-01](networking-and-sync.md) | net | DIVERGENT | remote-DoS | One ~64 KB pre-authentication RLPx auth packet exhausts the control stack and exits the whole process. |
| [EXEC-14](block-execution-and-types.md) | exec | UNVERIFIED → confirmed | remote-DoS | The same root cause: `rlp-decode`/`decode-list-payload` recurse per nesting level with no depth limit. |
| [NET-02](networking-and-sync.md) | net | MISSING | remote-DoS | No per-protocol message size cap; any frame up to 16 MB is accepted, which carries NET-01 past the handshake. |
| [NET-17](networking-and-sync.md) | net | MISSING | remote-DoS | Transaction decoders have no item-count cap, so a 16 MB message decodes to millions of objects. |

### Tier 2 — Confident wrong answers

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [EVM-04](evm-and-gas.md) | evm | DIVERGENT | consensus | `engine_newPayloadV5` is enabled at Amsterdam with no Amsterdam EVM, so payloads get a verdict computed under near-Osaka rules. |
| [RPC-02](rpc-and-engine.md) | rpc | DIVERGENT | CC-integration | Engine version-vs-fork violations return `INVALID` instead of an RPC error, so a consensus client permanently blacklists a valid chain. |
| [RPC-01](rpc-and-engine.md) | rpc | MISSING | CC-integration | `eth_syncing` always answers `false`, so the execution-layer upcheck passes while blocks are buffered and unexecuted. |
| [RPC-03](rpc-and-engine.md) | rpc | MISSING | CC-integration | `forkchoiceUpdatedV1`/`V2` do no fork or attribute gating, so a wrong-version call yields a payload built under a ruleset the caller did not ask for. |
| [RPC-12](rpc-and-engine.md) | rpc | DIVERGENT | correctness | The invalid-ancestor cache has no hit eviction, no capacity bound and no pre-merge zeroing, so one spurious `INVALID` is permanent until restart. |
| [EVM-09](evm-and-gas.md) | evm | DIVERGENT | correctness | `POINT_EVALUATION` converts "the KZG backend is absent" into "the proof is invalid", fabricating a verdict. |
| [EVM-16](evm-and-gas.md) | evm | MISSING | completeness | BLS backend availability is not in the Engine gate, so a misbuilt node accepts Prague and then stalls mid-import. |
| [EXEC-11](block-execution-and-types.md) | exec | MISSING | correctness | The KZG blob-proof verifier exists, is capability-gated, and has no caller on any live path; no code we own verifies a blob against its commitment. |
| [RPC-06](rpc-and-engine.md) | rpc | DIVERGENT | CC-integration | `getPayloadV3`+ always returns an empty `blobsBundle` rather than declining the method. |
| [POOL-13](txpool-building-and-ops.md) | pool | MISSING | completeness | A blob transaction is accepted and given a hash, then never mined, never gossiped and never expired. Executed. |
| [OPS-01](txpool-building-and-ops.md) | ops | DIVERGENT | operability | 56 command-line flags are accepted, consumed and discarded, including `--verbosity`, `--syncmode`, the cache family and every chain preset. |
| [RPC-37](rpc-and-engine.md) | rpc | MISSING | completeness | No IPC transport exists and `--ipcpath`/`--ipcapi`/`--ipcdisable` are accepted anyway. |

### Tier 3 — Verification collapse

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [EXEC-15](block-execution-and-types.md) | exec | MISSING (coverage) | correctness | No fixture the harness selects runs a fork later than Shanghai, and `.eest-fixtures` does not exist, so today they select nothing. |

### Tier 4 — Consensus and correctness divergences

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [EXEC-01](block-execution-and-types.md) | exec | DIVERGENT | consensus | EIP-7918 reserve-price comparison uses the parent's blob base-fee update fraction where both references use the child's. |
| [EXEC-03](block-execution-and-types.md) | exec | DIVERGENT | consensus | Post-merge status is inferred from the header's own difficulty, not the chain config, so a PoS-from-genesis chain skips all four PoS header checks. |
| [EXEC-02](block-execution-and-types.md) | exec | MISSING | consensus | Uncles are never validated beyond the ommers hash, yet uncle rewards are paid, so a pre-merge block can mint to fabricated uncles. |
| [STORE-02](state-trie-storage.md) | store | DIVERGENT | consensus | Empty-account deletion is not gated on EIP-158, so pre-Spurious-Dragon replay produces a wrong account trie. Inert post-merge. |
| [POOL-03](txpool-building-and-ops.md) | pool | MISSING | blocks-production | No EIP-7623 floor-data-gas check at admission; the cheapest remote way to poison every subsequent payload build. |
| [POOL-02](txpool-building-and-ops.md) | pool | MISSING | blocks-production | No EIP-3860 initcode-size check at admission; same consequence, slightly costlier to trigger. |
| [BUILD-01](txpool-building-and-ops.md) | build | DIVERGENT | blocks-production | One unexecutable transaction aborts the whole payload build; `transaction-validation-error` escapes every handler and closes the socket with no response. |
| [BUILD-02](txpool-building-and-ops.md) | build | DIVERGENT | blocks-production | The pending list is filtered at the head's base fee and the block is built at the child's, so a rising base fee triggers BUILD-01 with no adversary. |
| [BUILD-03](txpool-building-and-ops.md) | build | MISSING | blocks-production | The payload is built once at `forkchoiceUpdated` and never improved, giving up the whole build window. |
| [STORE-21](state-trie-storage.md) | store | MISSING | durability | A head whose state is gone is a hard startup failure; there is no `SetHead`, no rewind and no repair. |
| [RPC-11](rpc-and-engine.md) | rpc | DIVERGENT | CC-integration | `forkchoiceUpdated` on an unknown head answers `SYNCING` and never goes to fetch it, so a restarted node can sit there indefinitely. |
| [EVM-07](evm-and-gas.md) | evm | DIVERGENT | correctness | EIP-7702 delegation resolution is not fork-gated; we execute a designator's target at every fork where geth resolves only under Prague. |
| [EVM-08](evm-and-gas.md) | evm | DIVERGENT | correctness | `empty-account-p` carries a storage-root term, so `EXTCODEHASH` pushes a hash where both references push zero. |
| [EVM-15](evm-and-gas.md) | evm | DIVERGENT | completeness | `PREVRANDAO` selection is derived from the header rather than the fork schedule; equivalence UNVERIFIED, and call simulation hardcodes post-merge. |
| [EXEC-04](block-execution-and-types.md) | exec | MISSING | correctness | No proof-of-work seal verification and no difficulty formula: any pre-merge header's difficulty is accepted as given. |
| [EXEC-05](block-execution-and-types.md) | exec | MISSING | correctness | The DAO fork is parsed from the chain config and neither the state transition nor the extra-data rule is implemented. |
| [EXEC-08](block-execution-and-types.md) | exec | DIVERGENT | correctness | An EIP-2935 system-call failure is rolled back and swallowed where geth panics. Low reachability. |
| [EXEC-09](block-execution-and-types.md) | exec | DIVERGENT | correctness | Request system calls require code and success; geth accepts a codeless predeploy. Direction undecided — needs execution-specs, not geth. |
| [EXEC-10](block-execution-and-types.md) | exec | DIVERGENT | correctness | Withdrawals are credited before the request system calls; geth's order is the reverse. No observable difference established. |
| [EXEC-13](block-execution-and-types.md) | exec | DIVERGENT | correctness | Header RLP encoding is presence-driven, not positional, so a gapped header silently shifts fields. Latent; the decoder allowlist is load-bearing. |
| [STORE-03](state-trie-storage.md) | store | MISSING | correctness | No touched set and no end-of-transaction finalisation pass; the no-empty-account invariant is held by agreement between mutators. |
| [STORE-10](state-trie-storage.md) | store | DIVERGENT | correctness | Proof verification requires an exactly-sized, correctly-ordered list, so a valid geth or Nethermind proof is rejected as malformed. |
| [RPC-04](rpc-and-engine.md) | rpc | MISSING | correctness | `forkchoiceUpdatedV4` ignores `targetGasLimit` and the third `custodyColumns` parameter. |
| [RPC-07](rpc-and-engine.md) | rpc | DIVERGENT | correctness | `blockValue` in the payload envelope is always zero, so a MEV-Boost proposer always takes the builder's block. |
| [RPC-08](rpc-and-engine.md) | rpc | DIVERGENT | correctness | The payload id is a function of the selected transaction set, so identical calls return different ids and each stores another prepared payload. |
| [RPC-18](rpc-and-engine.md) | rpc | MISSING | correctness | Blob-transaction receipts omit `blobGasUsed` and `blobGasPrice`. |
| [RPC-19](rpc-and-engine.md) | rpc | DIVERGENT | correctness | The header field is named `balHash` where Nethermind's is `BlockAccessListHash`, so a reader silently sees no commitment. |
| [RPC-21](rpc-and-engine.md) | rpc | DIVERGENT | correctness | No gas-price oracle: `eth_maxPriorityFeePerGas` is always `0x0` and `eth_feeHistory`'s rewards inherit the zero. |
| [RPC-22](rpc-and-engine.md) | rpc | UNVERIFIED | correctness | `eth_blobBaseFee` may report the head's fee where geth reports the next block's. One eval settles it. |
| [RPC-24](rpc-and-engine.md) | rpc | DIVERGENT | correctness | `logs` subscriptions never report removed logs and skip logs across a deep reorg, though the filter path does this correctly. |
| [RPC-34](rpc-and-engine.md) | rpc | DIVERGENT | correctness | An unhandled handler condition becomes HTTP 400 with the condition printed into a non-JSON body, discarding a whole batch. |
| [POOL-04](txpool-building-and-ops.md) | pool | DIVERGENT | correctness | The minimum-fee check reads the fee cap, not the effective tip, so a zero-tip transaction passes the price floor. |
| [POOL-05](txpool-building-and-ops.md) | pool | MISSING | correctness | No EIP-7702 authority reservation and no delegated-account in-flight limit. |
| [POOL-06](txpool-building-and-ops.md) | pool | DIVERGENT | correctness | Nonce and balance are not checked at all when head state is unavailable; anything lands straight in the pending list. |
| [POOL-08](txpool-building-and-ops.md) | pool | DIVERGENT | correctness | A full pool rejects the newcomer instead of evicting the cheapest resident, so price stops mattering at the limit. |
| [POOL-12](txpool-building-and-ops.md) | pool | DIVERGENT | correctness | Blob replacement requires no blob-fee-cap bump and uses 10% where geth's blob pool uses 100%. |
| [BUILD-04](txpool-building-and-ops.md) | build | DIVERGENT | correctness | The block gas limit is copied from the parent and `--miner.gaslimit` never reaches the builder, so the limit can never move. |
| [BUILD-07](txpool-building-and-ops.md) | build | MISSING | correctness | Nothing bounds the encoded size of the block being assembled, so we can build past the EIP-7934 cap. |
| [OPS-03](txpool-building-and-ops.md) | ops | MISSING | correctness | The data directory is not locked, so two processes can open the same datadir and interleave writes. |

### Tier 5 — Unauthenticated resource exhaustion and open-by-default exposure

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [NET-15](networking-and-sync.md) | net | MISSING | remote-DoS | No inbound per-IP throttle, no `netrestrict`, no IP-diversity limit; one host can occupy every peer slot and force unlimited ECIES work. |
| [NET-06](networking-and-sync.md) | net | DIVERGENT | correctness | An unsolicited Ping marks a node bonded with its claimed ports, and bonded nodes are relayed — table poisoning and traffic reflection. |
| [RPC-16](rpc-and-engine.md) | rpc | MISSING | performance | No RPC gas cap and no EVM timeout; an unspecified `gas` defaults to `2^64-1`, so one unauthenticated request can pin a core. |
| [RPC-25](rpc-and-engine.md) | rpc | MISSING | performance | No topic-count and no block-range limit on log queries. |
| [RPC-35](rpc-and-engine.md) | rpc | MISSING | performance | No batch item limit and no batch response size limit; a 5 MB body can carry tens of thousands of calls. |
| [RPC-39](rpc-and-engine.md) | rpc | DIVERGENT | correctness | The default public method set includes `debug_` and `txpool_`, so uncapped `debug_traceCall` is reachable on a default-open port. |
| [RPC-38](rpc-and-engine.md) | rpc | DIVERGENT | correctness | Virtual hosts default to allowing any `Host` header, where geth defaults to `localhost` against DNS rebinding. |
| [RPC-23](rpc-and-engine.md) | rpc | DIVERGENT | correctness | Filters never expire and their ids are sequential integers, so any caller can uninstall or drain another's filter. |
| [POOL-07](txpool-building-and-ops.md) | pool | DIVERGENT | operability | Every pool limit defaults to unlimited, so a default-configured node has no bound on pool memory. |
| [POOL-09](txpool-building-and-ops.md) | pool | MISSING | operability | The basefee and blob subpools take no limits at all — the two a remote caller can most easily fill. |
| [POOL-10](txpool-building-and-ops.md) | pool | DIVERGENT | operability | Lifetime eviction runs only when a public JSON-RPC request arrives, so a validator-attached node never expires anything. |
| [POOL-01](txpool-building-and-ops.md) | pool | MISSING | correctness | No transaction size cap; a multi-megabyte calldata transaction is admitted and retained indefinitely. |
| [NET-18](networking-and-sync.md) | net | DIVERGENT | performance | A hash-origin header query with a large skip walks the chain one parent at a time — up to ~10⁶ store lookups per small request. |

### Tier 6 — Capability gaps

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [NET-03](networking-and-sync.md) | net | MISSING | blocks-network-use | No `snap` capability, so state can only be acquired by executing every block from genesis. |
| [NET-04](networking-and-sync.md) | net | DIVERGENT | blocks-network-use | The block download driver is one peer, one request in flight, sequential, capped at 2048 blocks per session. |
| [NET-05](networking-and-sync.md) | net | DIVERGENT | blocks-network-use | Discovery advertises a loopback IP and an ephemeral TCP port, so nobody can ever dial us in. |
| [NET-09](networking-and-sync.md) | net | MISSING | completeness | `Receipts` has an encoder and no decoder, so a receipt-fetching sync mode cannot be built. |
| [NET-11](networking-and-sync.md) | net | DIVERGENT | completeness | Our `eth` message-id block length is 17 where geth's is 18 — latent today, a trap for whoever adds a second capability. |
| [NET-10](networking-and-sync.md) | net | MISSING | completeness | `BlockRangeUpdate` is neither sent nor handled, and the peer's claimed block range is never validated. |
| [NET-12](networking-and-sync.md) | net | MISSING | completeness | We speak eth/68 and eth/69; geth speaks 69 through 72 and has dropped 68, so there is no headroom. |
| [NET-07](networking-and-sync.md) | net | MISSING | completeness | The routing table never evicts, revalidates or refreshes; `discv4-table-note-failure` and `-remove` have no caller. |
| [NET-21](networking-and-sync.md) | net | DIVERGENT | completeness | The served ENR carries no `ip`/`tcp`/`udp` and a hardcoded sequence number of 1, so cached records never update. |
| [NET-08](networking-and-sync.md) | net | MISSING | completeness | discv5 is absent. |
| [NET-22](networking-and-sync.md) | net | MISSING | completeness | No NAT traversal or port mapping; `--nat` is parsed and ignored. |
| [NET-16](networking-and-sync.md) | net | MISSING | completeness | No peer scoring; misbehaviour costs only the current session and eight of twelve disconnect reasons are never sent. |
| [NET-20](networking-and-sync.md) | net | MISSING | completeness | Multi-frame RLPx messages cannot be read, so a Nethermind Hello above 1024 bytes is unreadable. |
| [NET-14](networking-and-sync.md) | net | MISSING | completeness | No block propagation and no fetcher. Correct for a post-merge network; we contribute nothing to propagation. |
| [STORE-07](state-trie-storage.md) | store | MISSING | completeness | No persistent trie node store, so state cannot be loaded lazily, served to a peer, or healed. |
| [STORE-11](state-trie-storage.md) | store | MISSING | completeness | No range-proof verification, so a peer's account or storage range cannot be checked against the state root. |
| [STORE-12](state-trie-storage.md) | store | MISSING | completeness | No node iterator; range enumeration re-scans and re-sorts the whole entry table per call. |
| [EVM-01](evm-and-gas.md) | evm | MISSING | consensus | The four Amsterdam opcodes (`SLOTNUM`, `DUPN`, `SWAPN`, `EXCHANGE`) are not implemented. |
| [EVM-02](evm-and-gas.md) | evm | MISSING | consensus | EIP-8037 state-gas metering and EIP-8038 repricing are absent; our gas budget is a scalar, so the metering dimension does not exist. |
| [EVM-03](evm-and-gas.md) | evm | DIVERGENT | consensus | The Amsterdam contract-code-size limit is 32,768 where both references use 65,536 (EIP-7954), in two independent constants. |
| [EVM-05](evm-and-gas.md) | evm | MISSING | consensus | EIP-7708 ETH-transfer system logs are absent, so every value transfer and `SELFDESTRUCT` payout diverges on logs, bloom and receipts root. |
| [EVM-18](evm-and-gas.md) | evm | mixed | completeness | Amsterdam EIP inventory: EIP-8246's burn removal missing, EIP-7928 interpreter-side touching missing, five EIPs unassessed. |
| [EXEC-06](block-execution-and-types.md) | exec | MISSING | completeness | The block access list is validated when supplied but never derived from execution, so an Amsterdam block without one cannot be validated. |
| [EXEC-07](block-execution-and-types.md) | exec | MISSING | completeness | EIP-7997's irregular state transition and EIP-8282's request types `0x03`/`0x04` are absent from the pipeline. |
| [EVM-06](evm-and-gas.md) | evm | MISSING | completeness | No Bogota, and no fork-order validation at all, so a mistyped genesis yields an impossible ruleset that executes without complaint. |
| [EXEC-12](block-execution-and-types.md) | exec | MISSING | completeness | No built-in chain presets, so mainnet, Sepolia, Holesky and Hoodi genesis state cannot be constructed from the tree. |
| [OPS-02](txpool-building-and-ops.md) | ops | MISSING | completeness | No chain presets means `--genesis` is mandatory, and the preset flags are accepted anyway. |
| [POOL-14](txpool-building-and-ops.md) | pool | MISSING | completeness | Blob sidecars are never verified and the pooled transaction has nowhere to carry them; the 14-field decoder cannot parse the network wrapper. |
| [BUILD-08](txpool-building-and-ops.md) | build | MISSING | completeness | A built payload can never contain a blob transaction, so blob gas is always zero and no blob budget exists in selection. |
| [RPC-15](rpc-and-engine.md) | rpc | MISSING | completeness | No state or block overrides on `eth_call`, `eth_estimateGas` or `eth_createAccessList`. |
| [RPC-17](rpc-and-engine.md) | rpc | MISSING | completeness | `eth_simulateV1` is absent; depends on RPC-15. |
| [RPC-20](rpc-and-engine.md) | rpc | DIVERGENT | completeness | `pending` is an alias for `latest` in state and call paths, so a wallet asking for the pending nonce reuses a pooled nonce. |
| [RPC-28](rpc-and-engine.md) | rpc | MISSING | completeness | The `debug_*` tracing surface is one method with one tracer; no historic tracing of a mined transaction is possible. |
| [RPC-30](rpc-and-engine.md) | rpc | MISSING | completeness | Several `debug_*` state and control methods are absent; `debug_setHead` is the one that matters operationally. |
| [RPC-31](rpc-and-engine.md) | rpc | MISSING | completeness | `admin_*` is three methods and `admin_nodeInfo` omits the per-protocol detail; `admin_removePeer` is the one worth having. |
| [RPC-33](rpc-and-engine.md) | rpc | MISSING | completeness | `eth_config` (EIP-7910) is absent, though everything it reports is already in `chain-config`. |
| [RPC-29](rpc-and-engine.md) | rpc | MISSING | completeness | The Parity-style `trace_*` module is absent. geth does not serve it either, so declining is defensible. |
| [RPC-05](rpc-and-engine.md) | rpc | DIVERGENT | completeness | `getPayload` version mismatch uses `-32602` where the spec and geth use `-38005`. |
| [RPC-09](rpc-and-engine.md) | rpc | MISSING | completeness | `engine_getBlobs*` is not fork-gated, so we answer a method the spec says to refuse. |
| [RPC-10](rpc-and-engine.md) | rpc | MISSING | completeness | `engine_getBlobsV4` and `engine_hasBlobs` are absent, though we advertise `getBlobsV3`. |
| [EVM-13](evm-and-gas.md) | evm | MISSING | completeness | No interpreter-side tracing hooks beyond call boundaries; `CREATE`/`CREATE2` frames are untraced and `DELEGATECALL`/`CALLCODE` are mislabelled. |
| [POOL-11](txpool-building-and-ops.md) | pool | DIVERGENT | completeness | Promotion on a new head ignores the slot limits, so configured limits hold on submission and are exceeded on block arrival. |
| [OPS-05](txpool-building-and-ops.md) | ops | MISSING | operability | No log levels, no structured format, no rotation; the log stream is Lisp plists via `write`. |
| [OPS-08](txpool-building-and-ops.md) | ops | MISSING | operability | No profiling endpoint and no health endpoint; a stuck node cannot be profiled in place. |
| [OPS-10](txpool-building-and-ops.md) | ops | MISSING | completeness | The persisted format has a version and no migration, so the first format change orphans every datadir. |

### Tier 7 — Performance, capacity, and operability

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [STORE-14](state-trie-storage.md) | store | DIVERGENT | durability | `file-key-value-database` subclasses `memory-key-value-database`, so resident size equals total persisted size and open time is O(file bytes). |
| [STORE-08](state-trie-storage.md) | store | DIVERGENT | performance | A root computation rebuilds and re-hashes the whole node tree; nothing is memoized on a node. Cost is linear in total accounts per block. |
| [STORE-01](state-trie-storage.md) | store | DIVERGENT | performance | No journal: snapshot and revert deep-copy the entire world state, once per revertible frame. |
| [STORE-16](state-trie-storage.md) | store | DIVERGENT | performance | Atomic commit snapshots every table in the memory chain store plus the txpool, so per-block cost is linear in all state ever stored. |
| [STORE-06](state-trie-storage.md) | store | DIVERGENT | performance | `mpt` is a flat key/value table, not a trie; nodes exist only as transients. Every node-level capability follows from this. |
| [STORE-17](state-trie-storage.md) | store | MISSING | durability | No trie-node pruning, no state history, no reverse diffs; a full baseline every 128 blocks stores the world state again. |
| [STORE-19](state-trie-storage.md) | store | DIVERGENT | durability | Block, header, receipt and BAL records are append-only by construction, and every block record is materialised into memory at startup. |
| [STORE-18](state-trie-storage.md) | store | DIVERGENT | completeness | Pruning is manual, keyed to an absolute block number, and runs only at export, so retention is a constant rather than a distance. |
| [STORE-15](state-trie-storage.md) | store | DIVERGENT | completeness | The on-disk schema is hash-keyed with no height ordering, no ancients and no state history, so nothing can be iterated or deleted by height. |
| [STORE-20](state-trie-storage.md) | store | MISSING | completeness | No freezer, no flat snapshot layer over a trie, no offline pruning tool; five geth flags are accepted with no subsystem behind them. |
| [STORE-22](state-trie-storage.md) | store | MISSING | completeness | No `SetHead`, no transaction-lookup limit, no reorg-depth limit, no side-chain expiry. Reorg correctness itself is fine. |
| [STORE-23](state-trie-storage.md) | store | DIVERGENT | performance | Every historical-state query materialises the entire world state, so one `eth_call` at a height costs a full state copy. |
| [STORE-05](state-trie-storage.md) | store | DIVERGENT | performance | Code is stored inline on the state object with no content-addressed code store, and the code hash is recomputed on demand. |
| [STORE-24](state-trie-storage.md) | store | DIVERGENT | performance | No bounded cache of any kind — residency substitutes for caching — and the `--cache.*` flags are accepted and inert. |
| [STORE-13](state-trie-storage.md) | store | DIVERGENT | performance | No stack-trie; each derive-sha root builds a full trie per list. Minor. |
| [EVM-12](evm-and-gas.md) | evm | DIVERGENT | performance | Jump-destination validity is recomputed by scanning the contract from offset 0 on every `JUMP`/`JUMPI`. Magnitude UNVERIFIED. |
| [EVM-10](evm-and-gas.md) | evm | DIVERGENT | performance | Memory expansion allocates and copies the whole buffer with no capacity slack, so word-at-a-time growth is quadratic. Magnitude UNVERIFIED. |
| [EVM-11](evm-and-gas.md) | evm | DIVERGENT | performance | The 1024-item stack limit is enforced by taking `length` of a list on every push. Magnitude UNVERIFIED. |
| [EVM-14](evm-and-gas.md) | evm | MISSING | performance | No precompile result cache, which matters more here than in geth because several precompiles are pure Lisp. |
| [BUILD-06](txpool-building-and-ops.md) | build | DIVERGENT | performance | Selection packs against declared gas limits and never reclaims unused gas, so built blocks are systematically under-full. |
| [BUILD-05](txpool-building-and-ops.md) | build | DIVERGENT | performance | Ordering is per-sender by the first transaction's tip with no re-comparison after each inclusion. |
| [BUILD-09](txpool-building-and-ops.md) | build | DIVERGENT | operability | Building runs synchronously inside the `forkchoiceUpdated` request with no deadline of its own. |
| [NET-19](networking-and-sync.md) | net | DIVERGENT | performance | Downloaded bodies are not matched to their headers at the sync layer, so a bad delivery ends the session instead of the delivery. |
| [NET-13](networking-and-sync.md) | net | DIVERGENT | performance | Transaction gossip pushes every transaction in full to every peer and re-sends to the peer it came from. |
| [POOL-15](txpool-building-and-ops.md) | pool | DIVERGENT | performance | Gossip rescans the entire pending list per peer per tick and never offers queued, basefee or blob transactions. |
| [NET-23](networking-and-sync.md) | net | DIVERGENT | performance | `snappy-compress` emits literal runs only, so egress is several times what a peer expects. Documented. |
| [RPC-36](rpc-and-engine.md) | rpc | DIVERGENT | performance | Every HTTP response closes the connection; no keep-alive, chunked encoding or gzip. |
| [OPS-06](txpool-building-and-ops.md) | ops | DIVERGENT | operability | Metrics are event counts only — no pool-size, head-number or peer-count gauge — and no derivative recovers a level. |
| [OPS-04](txpool-building-and-ops.md) | ops | DIVERGENT | operability | `--log-file` truncates the previous run's log, so the restart destroys the record of the crash it follows. |
| [OPS-09](txpool-building-and-ops.md) | ops | MISSING | operability | Unclean shutdown has no repair path: no rewind, no reset, no offline inspection between "it starts" and "delete the datadir". |
| [OPS-07](txpool-building-and-ops.md) | ops | DIVERGENT | operability | Any startup failure prints the whole ~4,000-character usage string after the one line that explains what went wrong. |

### Tier 8 — Cosmetic, informational, and recorded non-gaps

| ID | Area | Verdict | Severity | Statement |
| --- | --- | --- | --- | --- |
| [EXEC-16](block-execution-and-types.md) | exec | DIVERGENT | cosmetic | `receipt-list-root` cannot encode typed receipts; no live path uses it and a test pins the behaviour. Naming hazard only. |
| [STORE-04](state-trie-storage.md) | store | DIVERGENT | cosmetic | Access-list and transient-storage bookkeeping live on the EVM context, not the state database. No observable difference. |
| [STORE-09](state-trie-storage.md) | store | DIVERGENT | cosmetic | No secure-trie layer; callers hash keys themselves and no preimages are kept. |
| [RPC-26](rpc-and-engine.md) | rpc | DIVERGENT | cosmetic | `eth_getLogs` with an unknown `blockHash` returns `[]` where geth returns an error. |
| [RPC-32](rpc-and-engine.md) | rpc | DIVERGENT | cosmetic | `txpool_inspect` uses an ASCII `x` where geth uses `×`, and the method's whole contract is its string format. |
| [NET-24](networking-and-sync.md) | net | informational | cosmetic | Session policy constants are ours, not parity claims; the audit's 33-row table is the correction to `docs/reference-map.md`. |
| [EVM-17](evm-and-gas.md) | evm | not a gap | no gap | EOF is absent from both references and from us. Nothing to close. |
| [RPC-13](rpc-and-engine.md) | rpc | no gap | no gap | Payload-status semantics match geth including `ACCEPTED`-on-missing-state and the absence of `INVALID_BLOCK_HASH`. Do not "fix". |
| [RPC-14](rpc-and-engine.md) | rpc | no gap | no gap | JWT authentication and `iat` freshness are implemented correctly; one operational note about an omitted `now`. |
| [RPC-27](rpc-and-engine.md) | rpc | no gap | no gap | `eth_subscribe syncing` is refused explicitly and subscription ids are 16 random bytes. This is the pattern to copy. |
| [RPC-40](rpc-and-engine.md) | rpc | no gap | no gap | The WebSocket implementation is sound: masking, bounds, control frames and origin checks are all correct. |

### Severity split

Each audit's own severity labels, grouped. The vocabularies differ between
audits and are not normalised away here.

| Severity | Count |
| --- | --- |
| remote-DoS | 5 |
| consensus-breaking | 9 |
| breaks-consensus-client-integration | 5 |
| loses-money-or-blocks-validation | 5 |
| blocks-real-network-use | 3 |
| correctness | 36 |
| durability | 4 |
| completeness | 44 |
| performance | 23 |
| operability | 11 |
| cosmetic / informational | 6 |
| recorded non-gap | 5 |
| **Total** | **156** |

## Priority tiers and why they are ordered this way

The tiers rank by consequence, and the ordering is argued against `PROJECT.md`'s
correctness principles rather than asserted.

**Tier 1 — Remote process kill, no credential required.** `NET-01` outranks
everything in this document. It needs no credential, no prior relationship and
no protocol state: the attacker needs our enode, which is public by
construction because our static public key is our node id. It costs one TCP
connection and one packet under 64 KB. The consequence is not a dropped session
but `(exit 1)` for the whole process — the listener, the accept loop, the RPC
services, the Engine API and the chain store all die together, because
`CONTROL-STACK-EXHAUSTED` is a `storage-condition` and every thread guard in the
tree catches `error`. And it is replayable, so restarting does not help.

Every principle in `PROJECT.md` is conditional on the process being alive.
Atomic import, derived-not-trusted, reorg safety and capability gating all
describe behaviour of a running node; none of them survives a remote kill. This
is also the cheapest item in the plan relative to its impact: a depth counter on
two mutually recursive functions and widening a `handler-case` clause. `EXEC-14`
is the same root cause recorded by another audit, and `NET-02`/`NET-17` are the
multipliers that carry it past the handshake and provide an independent
memory-exhaustion surface, so all four are one tier and one workstream.

**Tier 2 — Confident wrong answers.** These are the failures where the node
returns something it cannot substantiate instead of refusing. A loud failure is
recoverable: a consensus client retries, an operator reads a message, a caller
sees an error code. A silent wrong answer corrupts state or poisons a peer
relationship, and the damage outlives the bug.

The two clearest cases:

- `EVM-04`. `engine_newPayloadV5` and `engine_forkchoiceUpdatedV4` are enabled
  the moment the configured chain reaches Amsterdam, and the only availability
  predicate on Engine dispatch is the KZG one. So a consensus client driving an
  Amsterdam devnet gets a `VALID` or `INVALID` verdict computed with `EVM-01`,
  `EVM-02`, `EVM-03` and `EVM-05` all in force. `PROJECT.md` states the opposite
  requirement in as many words: "Later-fork and KZG-backed Engine methods stay
  gated when their verifier or execution semantics are unavailable, instead of
  silently returning wrong answers." The comparison here is not to geth; it is
  to our own contract.
- `RPC-02`. A version-vs-fork violation is a *caller* error, and we report it as
  `{"status":"INVALID"}` with HTTP 200. A consensus client reads `INVALID` as
  "this block is bad" and records the hash as permanently rejected. So a
  client-side bug during a fork transition — exactly when version confusion
  happens — becomes a permanent rejection of a chain that is in fact valid. The
  same mismatch reported as `-32602` is a retryable protocol error.

The rest of the tier follows the same rule, and most of them are fixed by
refusing rather than by building: `EVM-09` reports "the proof is invalid" when
it means "I cannot check"; `EVM-16` advertises `newPayloadV4` with no BLS
backend and stalls at the first BLS transaction; `EXEC-11` has a real,
capability-gated KZG verifier that no live path calls, which is the sharpest
contradiction of "real cryptography on real paths" in the tree; `POOL-13`
returns an accepted hash for a blob transaction it will never mine or gossip;
`OPS-01` and `RPC-37` accept 56 flags and an IPC path and honour none of them,
so an operator who migrated a geth command line believes their cache sizing,
verbosity, sync mode and gas cap are in effect. `RPC-01` and `RPC-12` are the
two whose fix is not a refusal — an honest answer and a bounded, evictable cache
respectively — but their consequence is the same shape: a wrong statement the
caller cannot see through.

Note what this tier does *not* contain. `EVM-01`, `EVM-02`, `EVM-03` and
`EVM-05` — the Amsterdam semantics themselves — sit in Tier 6. That is the whole
argument for `EVM-04`'s rank: with the gate in place, an unimplemented fork is a
capability gap and the node refuses honestly; without it, the same four findings
are live consensus risks. One small fix moves four consensus-breaking findings
into a tier where they can wait.

**Tier 3 — Verification collapse.** `EXEC-15` sits alone, above every remaining
correctness finding, because it is the reason the rest went unnoticed. See the
next section.

**Tier 4 — Consensus and correctness divergences.** Ordered inside the tier:
consensus-breaking findings reachable on a chain this client can be pointed at
today (`EXEC-01`, `EXEC-03`) first; then the remotely triggerable
block-production failures (`POOL-03`, `POOL-02`, `BUILD-01`, `BUILD-02`,
`BUILD-03`), which come this high because `POOL-03` is the cheapest remote
denial of block production in the tree and `BUILD-02` fires with no adversary at
all on any block where the base fee rises; then consensus-breaking findings
contingent on a scope decision (`EXEC-02`, `STORE-02`); then `STORE-21`, where a
principled fail-stop has no recovery path behind it and a node can be lost; then
the remaining correctness divergences.

**Tier 5 — Unauthenticated resource exhaustion and open-by-default exposure.**
Below correctness because these failures are loud and recoverable, and because
several of them are not reachable at all on the recommended posture of an
authenticated Engine port with no public listener. Above capability gaps because
they need no credential. Three of these items (`RPC-16`, `RPC-25`, `RPC-35`)
carry a `performance` label in their own audit where the networking audit would
have called the same shape `remote-DoS`; that is a difference in vocabulary, not
in evidence, and it is resolved by ranking rather than by re-severitising
another audit's finding.

**Tier 6 — Capability gaps.** Things absent that a stated target needs. Ordered
by which target they block: the sync and discovery items first, because without
`NET-05` nobody can dial us and without `NET-03` state cannot be acquired at
all; then the Amsterdam semantics; then presets, blobs and the RPC breadth.
Nothing here produces a wrong answer once Tier 2's gates are in place.

**Tier 7 — Performance, capacity, and operability.** Correct results,
unacceptable cost. This is where the storage substrate's consequences live, and
three of the EVM items here have `UNVERIFIED` magnitudes, so their relative
order inside the tier is not yet knowable.

**Tier 8 — Cosmetic, informational, and recorded non-gaps.** Included so the
table is complete and so the five non-gaps are visible to anyone tempted to
"fix" them. `RPC-13` in particular records payload-status behaviour that a
well-meaning change would break.

## The test-coverage collapse is a first-class item

`EXEC-15` deserves its own tier and its own section, because it changes the
verification story for nearly every other finding in this document.

What the block-execution audit established, by counting selector files:

| Fixture format | Selectors | Forks selected |
| --- | --- | --- |
| `blockchain_tests_engine` | 362 | `fork_Shanghai` only, 362 of 362 |
| `blockchain_tests` (non-engine) | 0 | none |
| `state_tests` | 94 explicit names plus 21 generator functions | `fork_London` and `fork_Shanghai` only |
| `transaction_tests` | 12 real EEST files plus 30 vectors from a hand-authored sample | the 12 are all `prague/eip7702_set_code_tx/test_invalid_*` |

**No fixture the harness selects executes any fork later than Shanghai.** And
`.eest-fixtures` does not exist on this machine — confirmed again for this
document — so today even the Shanghai selectors select nothing and the tests
skip. The pinned corpus is EEST release `v5.4.0`, `fixtures_stable.tar.gz`,
sha256 `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`, per
`PROJECT.md` and `scripts/fetch-eest-fixtures.sh`.

What that implies, stated plainly: blob gas, `excessBlobGas`, the EIP-7918
branch, the EIP-4788 and EIP-2935 system calls, execution requests, EIP-7702
block execution, the EIP-7623 calldata floor and the EIP-7825 gas cap have no
executing fixture anywhere in the suite. **Most of the consensus findings in
these documents are gaps the fixtures would have caught had they run.** `EXEC-01`
is the clearest case — a Cancun-or-later blockchain fixture set catches a wrong
blob base-fee update fraction immediately — and `EVM-08`, `EVM-07` and
`STORE-02` are all exactly the shape that EEST pre-state sections construct.

This is why restoring the corpus and extending the selectors through the newest
implemented fork is an early, high-leverage item rather than a hygiene task. It
is the only item in the plan whose completion changes how nearly every other
item can be *proved* fixed. Before it, the verification for a consensus fix is a
hand-written unit test asserting the behaviour the fixer believes is correct;
after it, the verification is a fixture family written by people who are not us.
Eight of the work items below (W6, W7, W8, W9, W24, W35, W37, W38) name an EEST
fixture family as their verification, and none of those verifications is
available until this one lands.

Two parts of `EXEC-15` remain unverified and both are settled by the same work:
the exact expansion count of the 21 state-test generators (hand-arithmetic put
it near 950 including the 94 literals), and which `v5.4.0` families exist that
we do not select at all. The fork ceiling — the number that matters — is
established by counting, not inferred.

## Cross-cutting work programme

41 work items covering all 151 gaps. Each identifier appears in exactly one
item; the audits' own remediation lists overlap and those overlaps are
consolidated here. Sizes are relative only: S is a contained change to one or two
functions, M spans a module or several call sites, L needs a design decision or a
new subsystem first. No item carries a duration here, and the three audits that
attached day counts to their own S/M/L used three different scales, so those are
not carried across. Sizes are the audits' own letter where they gave one.

The consolidations worth naming up front, because each of them appears as
several items across the six documents:

- **One decoding-bounds item, not three.** The `rlp-decode` depth limit, the
  message size caps and the decoder item-count caps close `NET-01`, `EXEC-14`,
  `NET-02` and `NET-17` together, and share the thread-guard widening. Splitting
  them leaves the multiplier in place.
- **One error-handling audit, not several.** A `storage-condition` that no guard
  catches (`NET-01`), an `error` subclass outside the hierarchy the guards test
  for (`BUILD-01`, coordinator fact 2), a `handler-case` that converts
  unavailability into a verdict (`EVM-09`, and the same shape in
  `validate-blob-sidecar-kzg-proofs`), and a catch-all that turns an internal
  condition into HTTP 400 (`RPC-34`) are one problem: the condition hierarchy and
  its guards were never designed as a whole.
- **One discarded-flags item.** `OPS-01` is the general case; the flag halves of
  `RPC-16`, `RPC-35` and `RPC-37` are instances of it. The *caps* those RPC
  findings ask for are separate work.
- **One blob slice.** `EXEC-11`, `POOL-12`, `POOL-13`, `POOL-14`, `BUILD-08` and
  `RPC-06` are six faces of one absence. Sequence them as one workstream.
- **Snap sync is blocked, not merely sequenced.** `NET-03` cannot be built until
  `STORE-06`, `STORE-07`, `STORE-11` and `STORE-12` exist, and those in turn want
  the substrate decision settled.

### Phase 1 — Survivability and honesty

Goal: the process cannot be killed by a stranger, and the node never states
something it cannot substantiate.

**W1 — Bound untrusted decoding and widen thread guards. (S)**
Closes `NET-01`, `EXEC-14`, `NET-02`, `NET-17`. Depends on nothing. Add a depth
parameter to `rlp-decode` and `decode-list-payload` with a limit in the low
hundreds and signal `rlp-error` past it; add a 2 KB cap on base-protocol
messages and a 10 MB cap on `eth` messages; add item-count caps to
`decode-eth-transactions` and `decode-eth-new-pooled-transaction-hashes`; widen
every `sb-thread:make-thread` body's guard from `error` to `serious-condition`.
Verification: a `tests/p2p-handshake-tests.lisp` case feeding a depth-25,000
auth body through `rlpx-open-auth` and asserting an ordinary error; per-decoder
cases in `tests/eth-wire-tests.lisp`; frame cases asserting an oversized frame
is refused before decode; and a thread-level test that a `storage-condition`
raised in a session does not exit the process — that last test goes red by
killing the run rather than by reporting a failure, which its comment must say.
Protects: every principle, all of which presuppose a live process.

**W2 — Audit the condition hierarchy and its guards across the tree. (M)**
Closes `EVM-09`, `RPC-34`. Depends on W1 for the thread-guard half and must land
with W12 for the build half. One pass, four outputs: give the KZG module a
distinct unavailability condition so `run-kzg-point-evaluation-precompile` and
`validate-blob-sidecar-kzg-proofs` propagate rather than fabricating a verdict,
following `call-bls12381-backend`; put `transaction-validation-error` under a
class the request handlers actually catch; narrow the HTTP catch-all so an
unexpected condition becomes a `-32603` body at status 200; and write down which
condition classes the guards at each boundary are contractually required to
catch. Verification: a unit test binding `*kzg-verifier*` to `nil` and asserting
the precompile signals rather than returning failure, with the existing
point-evaluation tests confirming real failures still fail; a
`tests/core-http-service-tests.lisp` case forcing an internal condition and
asserting a 200 with a JSON-RPC error object.
Protects: **capability gating**, **atomic import**.

**W3 — Gate Engine methods on execution and verifier availability. (S)**
Closes `EVM-04`, `EVM-16`. Depends on nothing. Add an Amsterdam-execution
availability predicate and a `bls12381-available-p`-style predicate, and mark
`engine_newPayloadV5`, `engine_getPayloadV6`, `engine_forkchoiceUpdatedV4` and
the Prague-and-later methods unavailable accordingly, following the `:kzg-p`
pattern already in `src/api/engine/methods.lisp`. Verification: Engine tests
asserting each gated method is neither advertised by
`engine_exchangeCapabilities` nor dispatched while its predicate is false,
mirroring the existing KZG capability tests.
Protects: **capability gating**. This is the cheapest item in the plan and it
converts four consensus-breaking findings into one honest refusal.

**W4 — Convert Engine version and attribute violations into RPC errors. (M)**
Closes `RPC-02`, `RPC-03`, `RPC-05`, `RPC-09`. Depends on nothing. All four share
one shape: raise `engine-rpc-fail` with `-32602`, `-38003` or `-38005` where the
code currently returns an `INVALID` status or a generic `block-validation-fail`.
Give `forkchoiceUpdatedV1`/`V2` the fork and attribute treatment `V3` already
has, and fork-gate `getBlobs`. Verification: `tests/core-engine-rpc-*.lisp` cases
per method and version, then the Hive `engine-api` suite, which asserts these
codes directly.
Protects: **capability gating**.

**W5 — Report real sync progress. (S)**
Closes `RPC-01`. Depends on nothing; the inputs exist — the head number and the
buffered-block set `devnet-node-sync-targets` already computes. Verification: a
`tests/core-public-rpc-chain-tests.lisp` case asserting the object shape while a
remote block is buffered and `false` when it is not, then a Lighthouse or Prysm
upcheck against a deliberately-behind devnet node.
Protects: honest capability boundaries.

*Exit criterion.* A depth-25,000 nested-list auth body fed to `rlpx-open-auth`
signals an ordinary error and the test process survives; every
`sb-thread:make-thread` body in the tree handles `serious-condition` and a test
proves a `storage-condition` in a session thread does not exit the process;
`engine_exchangeCapabilities` omits every method whose execution or verifier
predicate is false and dispatch refuses it; each version and attribute violation
enumerated in `RPC-02`, `RPC-03`, `RPC-05` and `RPC-09` returns its spec'd error
code with no `payloadStatus`; `eth_syncing` returns an object while a remote
block is buffered.

### Phase 2 — Verification restored

Goal: a consensus fix can be proved by a fixture family somebody else wrote.

**W6 — Restore the pinned EEST corpus and lift the fork ceiling. (L)**
Closes `EXEC-15`, and `docs/gas-parity.md` item 3.1. Depends on nothing. Fetch
`v5.4.0` at the pinned sha256 via `make eest-fixtures`, export
`ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT` in the layered Docker targets, and
replace the hardcoded `'("London" "Shanghai")` fork list in
`tests/fixture-runner-state-selectors.lisp` and the all-Shanghai selector list
in `tests/fixture-runner-blockchain-selectors.lisp` with a parameter that runs
through the newest implemented fork. Verification: non-zero, non-skipped case
counts for `cancun/eip4844_blobs/`,
`prague/eip7002_el_triggerable_withdrawals/`, `prague/eip7251_consolidations/`,
`prague/eip6110_deposits/` and `osaka/eip7918_blob_reserve_price/` in both
`blockchain_tests` and `blockchain_tests_engine`, plus an inventory of the
`v5.4.0` families that exist and are still not selected.
Protects: **derived, not trusted** — nothing below can be shown fixed without
this.

*Exit criterion.* `.eest-fixtures` present at the pinned sha256; the five
families named above report non-zero, non-skipped case counts; the
generator-expansion count and the not-selected family list are recorded as
counted numbers rather than arithmetic.

### Phase 3 — Consensus divergences

Goal: no known divergence remains on a chain this client can be pointed at
today, and each fix is proved by a fixture rather than by a unit test the fixer
wrote.

**W7 — Fix the EIP-7918 reserve-price update fraction. (S)**
Closes `EXEC-01`, resolving `docs/gas-parity.md` item 1.3. Depends on W6 for
proof, not for the change. Pass the child's `update-fraction` as the
reserve-price fraction in `expected-excess-blob-gas` and delete the
`parent-update-fraction` parameter and the parent-schedule resolution in
`validate-block-header-against-config`. Verification:
`osaka/eip7918_blob_reserve_price/` and any BPO transition family in `v5.4.0`; a
differential test against a transcription of `calcExcessBlobGas` over a grid of
parent excess, used and base fee would be stronger.
Protects: the parity rule — a documented deliberate choice that contradicts both
references is still a split.

**W8 — Decide the merge boundary from the chain configuration. (S)**
Closes `EXEC-03`, `EVM-15`. Depends on nothing. Thread a config-derived
`chain-config-post-merge-p` into `validate-block-header-against-config` in place
of `(block-header-post-merge-p header)`, and keep the header-derived predicate
only where it describes an already-validated header — which is the same question
`EVM-15` raises about `PREVRANDAO` selection, including the call-simulation
path's hardcoded `:random-p t`. Verification: a blockchain fixture configured
post-merge from genesis whose block 1 declares nonzero difficulty must be
rejected; a simulation over a pre-merge block must report difficulty, not
`PREVRANDAO`.
Protects: **derived, not trusted**.

**W9 — Account emptiness and an end-of-transaction finalisation pass. (M)**
Closes `EVM-08`, `STORE-02`, `STORE-03`, and `docs/gas-parity.md` item 4.3.
Depends on W6, and composes with W24. One change, three findings: drop the
storage-root term from `empty-account-p`, replace eager per-mutator pruning with
one pass over the touched set at the transaction boundary, and take the EIP-158
rule as a parameter from the chain rules. Confirm
`contract-address-collision-p` keeps its storage term, which is correct per
EIP-7610 and must not be swept up. Verification: a unit test with a code-less,
nonce-zero, balance-zero account carrying one storage slot asserting
`EXTCODEHASH` pushes 0 and that the create-collision predicate still rejects it
as a `CREATE2` target; a test that an account zeroed through
`state-db-set-account` alone is absent from the trie with EIP-158 active and
present without it; EEST state tests for the Spurious Dragon transition.
Protects: **derived, not trusted**.

**W10 — Fork gating in the EVM: delegation resolution and fork order. (S)**
Closes `EVM-07`, `EVM-06`. Depends on nothing. Add a rules parameter to
`evm-resolved-code` and `execution-resolved-code` and return raw code when
Prague is not active; port the shape of geth's `CheckConfigForkOrder` into
`chain-config-from-genesis-config`. Verification: a unit test executing a
delegation designator under Cancun rules asserting the designator bytes execute
and under Prague rules asserting the target runs; unit tests rejecting a config
with `osakaTime` set and `pragueTime` unset and one with `cancunTime` after
`pragueTime`, with a positive test that mainnet's schedule still loads.
Protects: **derived, not trusted**, **capability gating**.

*Exit criterion.* The five EEST families from Phase 2 pass; a post-merge-from-
genesis fixture with a nonzero-difficulty block 1 is rejected; the three unit
tests named above pass; `docs/gas-parity.md` items 1.3 and 4.3 are marked closed
with the fixture family that proves each.

### Phase 4 — Block production a proposer can rely on

Goal: a valid attribute set always yields a payload id and a returnable block,
and every failure path produces a JSON-RPC response.

**W11 — Add the missing admission checks. (S)**
Closes `POOL-01`, `POOL-02`, `POOL-03`. Depends on nothing, and worth doing
before W12 because it removes the cheap remote trigger. Add an encoded-size cap,
the EIP-3860 initcode cap, and the EIP-7623 floor-data-gas check — the last two
by calling the same functions the execution path already uses, so the two
thresholds cannot drift. Verification: three tests asserting
`eth_sendRawTransaction` rejects each shape, plus a test that the pool cannot
hold a transaction `charge-sender-upfront` would refuse.
Protects: **derived, not trusted**.

**W12 — Make a failing transaction skip its sender instead of failing the build. (L)**
Closes `BUILD-01`, `BUILD-02`. Depends on W2 for the condition half; blocks W14
and W16. Introduce a per-transaction commit boundary inside the build path, drop
the offending sender's remaining transactions and continue, keep an
always-returnable empty payload behind every payload id, and filter selection at
`(expected-base-fee-per-gas parent-header)` rather than at the head's base fee.
Verification: a test admitting a transaction whose gas limit is below the
EIP-7623 floor, asserting `forkchoiceUpdated` returns a payload id and
`getPayload` returns a block excluding it; a test asserting a JSON-RPC response
rather than a closed connection when a pending sender's balance is short; a test
with a parent above the gas target and a pending transaction whose cap sits
between the two base fees, asserting the build succeeds and excludes it.
Protects: **atomic import**, **derived, not trusted**.

**W13 — Pool limits, eviction, maintenance, and the EIP-7702 rules. (M)**
Closes `POOL-04`, `POOL-05`, `POOL-06`, `POOL-07`, `POOL-08`, `POOL-09`,
`POOL-10`, `POOL-11`. Depends on nothing for the limits; `POOL-05`'s authority
reservation depends on the same bookkeeping the eviction ordering introduces.
Give every limit a default, extend limits to the basefee and blob subpools,
evict the cheapest resident on overflow unless the newcomer is cheapest, apply
the limits on the new-head promotion path too, compare the effective tip rather
than the fee cap, refuse admission rather than skipping the nonce and balance
checks when head state is unavailable, move lifetime expiry onto the background
worker, and add the delegated-account in-flight limit and authority reservation.
Verification: a test filling the pool and asserting a higher-priced arrival is
admitted and the cheapest resident is gone; a test asserting the basefee subpool
is bounded; a test asserting a queued transaction expires on a node with no
public RPC listener; tests asserting a second in-flight transaction from a
delegated account and a set-code transaction naming a pending authority are both
rejected.
Protects: **reorg safety**, honest capability boundaries.

**W14 — Improve the payload while the consensus client waits, behind a stable id. (L)**
Closes `RPC-08`, `BUILD-03`, `BUILD-09`. Depends on W12 — rebuilding is
pointless while one bad transaction can fail a rebuild. Derive the payload id
from the parent and the attributes alone, build asynchronously under a
slot-length timeout, keep the best result, and return it from `getPayload`.
Verification: a test that two identical `forkchoiceUpdated` calls with a changed
pool return the same id, and that a high-tip transaction admitted after the call
appears in the block `getPayload` returns for that id.
Protects: **derived, not trusted**.

**W15 — Report the block value and target a gas limit. (S)**
Closes `RPC-07`, `BUILD-04`, `RPC-04`. Depends on W12. Sum the fees credited
during the build into `blockValue`; thread `--miner.gaslimit` through
`devnet-cli-make-node` to the builder and apply the 1/1024 hone-toward-target
rule; read `targetGasLimit` from `forkchoiceUpdatedV4` and use it as the ceiling
after Amsterdam. Verification: a test building on a parent with limit L and a
configured ceiling above it asserting the built header's limit is
`L + L/1024 - 1`; a test asserting non-zero `blockValue` for a block containing
a paying transaction; a test asserting `-38003` when `targetGasLimit` is absent
from a V4 call.
Protects: **derived, not trusted**.

**W16 — Selection quality: re-compare senders, reclaim gas, bound block size. (M)**
Closes `BUILD-05`, `BUILD-06`, `BUILD-07`. Depends on W12, because all three
require selection and execution to interleave. Verification: the ordering test
in `txpool-mining-order-tests.lisp` extended with the 100/1-versus-50 case; a
test asserting a second transaction is included once the first's unused gas is
reclaimed; a test asserting selection stops before the EIP-7934 RLP size cap.
Protects: **derived, not trusted**.

**W17 — Bound and make recoverable the invalid-ancestor cache. (M)**
Closes `RPC-12`. Depends on nothing. Port geth's three mechanisms: a hit counter
with eviction, a capacity cap on the tipset map, and `0x0` for a pre-merge last
valid ancestor. Verification: a test that marks a block invalid, replays it past
the eviction threshold, and asserts the node reconsiders — the case that
currently requires a restart.
Protects: **reorg safety**.

**W18 — Pursue the head a `forkchoiceUpdated` names. (M)**
Closes `RPC-11`. Depends on nothing in this phase but touches the sync layer, so
coordinate with W30. Record the unknown head the way `newPayload` records an
unexecutable block and let `devnet-peer-fill-sync-gaps` pick it up.
Verification: restart a devnet node behind a live consensus client and confirm it
leaves `SYNCING`; the Hive `engine-api` sync cases cover the same path.
Protects: **atomic import** (a head we pursue is a head we can substantiate).

*Exit criterion.* With a pending list containing a floor-gas-short transaction, a
balance-short transaction and an oversized-initcode transaction,
`forkchoiceUpdated` returns a payload id, `getPayload` returns a block excluding
all three, and every rejected submission produced a JSON-RPC error rather than a
closed socket; two identical `forkchoiceUpdated` calls return the same id;
`blockValue` is non-zero for a block with a paying transaction; a pool at its
configured limit admits a higher-priced arrival; a previously-`INVALID` block is
reconsidered after the eviction threshold.

### Phase 5 — Exposure, configuration honesty, operability

Goal: an exposed node cannot be exhausted by an unauthenticated caller, an
accepted flag does what it says, and an operator can diagnose a failure.

**W19 — Bound and isolate the public RPC surface. (M)**
Closes `RPC-16`, `RPC-23`, `RPC-24`, `RPC-25`, `RPC-35`, `RPC-38`, `RPC-39`.
Depends on nothing. Wire an RPC gas cap and EVM timeout; give filters random
16-byte ids and a deadline reset on poll; route the reorg notification
`canonical-chain.lisp` already sends to filters into the subscription poll and
make the `newHeads` walk report the replacing branch; add `maxTopics`,
`maxSubTopics` and a block-range cap; add batch item and response-size limits;
default virtual hosts to `localhost`; drop `debug_` from the default public
method set. Verification: a case per limit asserting the error; expiry and
unknown-id cases in the filter tests; a `tests/websocket-tests.lisp` case
inducing a reorg and asserting both the `removed: true` logs and the replacement
logs arrive; the `rpc-compat` suite to confirm nothing legitimate was cut off.
Protects: **capability gating**, and the node's ability to stay up.

**W20 — Stop accepting flags we ignore. (M)**
Closes `OPS-01`, `RPC-37`. Depends on W19 so that only genuinely unimplemented
flags remain. Largely a decision rather than a construction: for each of the 56
discarded flags, implement it, reject it at parse time with a message naming what
is unsupported, or accept it while emitting a startup warning that names it. Make
the TOML loader error on an unknown key. Verification: one test enumerating both
accepted-option lists and asserting every entry is either consumed into the
options plist or produces a warning or rejection — one test covering both this
item's and `RPC-37`'s subset.
Protects: **capability gating** — an unimplemented flag should be refused, not
silently honoured.

**W21 — Operability baseline. (M)**
Closes `OPS-03`, `OPS-04`, `OPS-05`, `OPS-06`, `OPS-07`, `OPS-08`, `OPS-10`.
Depends on nothing. Take an exclusive lock on the datadir; append to the log
rather than truncating; add levels, a structured renderer and rotation; add a
gauge kind to the telemetry sink and expose pool counts, head/safe/finalized
numbers and peer count; print usage only for a usage error; add a health
endpoint and a profiling surface; add a migration path for the persisted format
version. Verification: a test that a second node on the same datadir fails with
a distinct error while the first runs; a test asserting a second run's log still
contains the first run's records; a scrape test asserting a `# TYPE ... gauge`
line for pool size whose value tracks an admitted transaction; a test asserting a
startup failure's stderr does not contain the usage string.
Protects: **atomic import** (the datadir lock), honest operator surfaces.

**W22 — Chain presets. (M)**
Closes `EXEC-12`, `OPS-02`. Depends on nothing, and it is the precondition for
any Hive or public devnet run — which is how most of this plan gets exercised end
to end. Embed the mainnet, Sepolia, Holesky and Hoodi configurations,
allocations and bootnode lists, and select them from the preset flags W20 would
otherwise reject. Verification: a test asserting the genesis block hash computed
from each preset equals the published hash for that network.
Protects: nothing in the correctness list directly; it unblocks external
verification.

*Exit criterion.* Each of the seven RPC bounds returns its error and
`rpc-compat` still passes; default vhosts are `localhost` and `debug_` is absent
from the default public set; the flag-enumeration test passes with zero silently
discarded flags; a second process on one datadir fails immediately; the metrics
endpoint exposes at least one gauge whose value tracks a pool insertion; each
of the four presets reproduces its published genesis hash.

### Phase 6 — State and storage

Goal: per-block cost stops scaling with total state, retention is bounded, and a
node with a missing head state can be recovered — then decide the substrate.

**W23 — Memoize node encodings and hashes; hash only dirty paths. (M)**
Closes `STORE-08`, `STORE-13`. Depends on nothing, and the state audit calls it
the highest value-to-risk item in its area. Verification:
`tests/state-account-trie-cache-tests.lisp` and
`tests/trie-fixture-vector-tests.lisp` pass unchanged with
`*verify-incremental-root*` bound true throughout — that differential oracle is
exactly the right guard here — plus a test asserting the number of node
encodings for a one-account change is independent of total account count.
Protects: **state-root memoization**, **derived, not trusted**.

**W24 — Journal state mutations and revert by replaying entries backwards. (L)**
Closes `STORE-01`, `STORE-04`, `STORE-05`. Depends on coordination with the
EVM/gas area, which owns access-list and transient-storage semantics; composes
with W9. Introduce a change journal with one entry type per mutation, make
snapshots integer marks, fold in the EVM context's access-list and
transient-storage bookkeeping so one mark covers all revertible state, and add a
content-addressed code store so a clone shares bytes. Verification: every
existing state and EVM test plus the EEST state fixtures pass unchanged —
reverts are currently exact, so any behavioural difference is a regression by
definition — and a differential test running a nested revert sequence under both
the journal and a retained deep-copy path asserting byte-identical state roots.
This is the item where a differential oracle is not optional.
Protects: **derived, not trusted**, **atomic import**.

**W25 — Resolve proofs by node hash. (S)**
Closes `STORE-10`. Depends on nothing. Accept a node set keyed by Keccak hash in
addition to the ordered list and drop the unconsumed-nodes rejection for that
path. Verification: `tests/trie-basic-tests.lisp` extended with a shuffled and
padded proof set that must verify while
`trie-proof-rejects-tampered-referenced-node` still passes; ideally a fixture
proof captured from geth 1.17.6 at a known root, which makes it an
interoperability test rather than a self-consistency one.
Protects: **derived, not trusted**, the parity rule.

**W26 — Commit and read state without copying the world. (M)**
Closes `STORE-16`, `STORE-23`. Depends on W24 for the journal. Reduce
`chain-store-atomic-commit` to the tables the block touched, and give
`chain-store-state-db` a lazy reader that resolves an account through the diff
chain on first access. Verification: existing `src/api/public/state/` tests
return identical results, plus a test asserting a single-account query does not
enumerate the account set; a test asserting per-block commit work does not grow
with retained block count.
Protects: **layering**, **atomic import**.

**W27 — Height-ordered keys and bounded retention. (M)**
Closes `STORE-15`, `STORE-17`, `STORE-18`, `STORE-19`, `STORE-20`, `STORE-22`.
Depends on the W29 decision to avoid designing a schema twice. Prefix block,
header and receipt keys with the big-endian number ahead of the hash; reserve
namespaces for trie nodes, code and state history; derive the prune bound from
the head number and a configured depth and run it on commit; extend expiry to
block, header, receipt and side-chain records; add a transaction-lookup limit and
a reorg-depth bound; include a versioned migration. Verification:
`tests/database-tests.lisp` round-trips per kind plus a migration test producing
identical logical content from a pre-change file; a range-delete test proving
heights below a bound are removable without a full-keyspace scan; a test running
N blocks past the retention depth asserting bounded snapshot count and that the
head's state survives every prune.
Protects: **atomic import** (migration must be all-or-nothing), **reorg safety**
(retention must not drop what a reorg could need).

**W28 — Head rewind and operator repair tooling. (M)**
Closes `STORE-21`, `OPS-09`, `RPC-30`. Depends on W27, because pruning must
never remove the state rewind would target. Walk back from the persisted head to
the newest ancestor with available state and set the head there, logging the
rewind explicitly; keep the fail-stop when *no* ancestor has state; add
`debug_setHead` and the missing `debug_*` state getters; add an offline
inspection subcommand. Verification: `tests/core-node-store-*` extended with a
database whose head state record is removed, asserting startup succeeds at the
highest block with state and that head, safe and finalized stay mutually
consistent, plus the still-fail-stop case for a database with no state at all.
Protects: **reorg safety**, **derived, not trusted**.

**W29 — Direction-level decision: the storage substrate. (L)**
Covers `STORE-14`, `STORE-24`. Not schedulable work — see decision **D1**. It
gates W27's schema design and W36 entirely.

*Exit criterion.* Node encodings for a one-account change are independent of
total account count; the nested-revert differential test passes with
byte-identical roots; a single-account historical query does not enumerate the
account set; a padded, shuffled geth-generated proof verifies; retained snapshot
count is bounded after N blocks past the configured depth and a range delete
below a height needs no full scan; a database whose head state record is removed
starts at the highest block with state; **D1** is recorded with a date and a
rationale.

### Phase 7 — Networking beyond survival

Goal: we can be dialed, our routing table reflects reality, sync survives one
bad peer, and gossip costs what it should.

**W30 — Validate deliveries, then make the download multi-peer. (L)**
Closes `NET-04`, `NET-09`, `NET-19`. Depends on W31 for the receipt decoder's
version handling. First check header contiguity and match bodies against
`TxHash`/`UncleHash`/`WithdrawalsHash` before assembling, and drop the delivery
rather than the session; then add a delivery queue, more than one request in
flight, and peer selection. Verification: `tests/eth-sync-tests.lisp` asserting a
mismatched body is rejected without ending the session, and a download against
multiple scripted peers; a Hive `ethereum/sync` run.
Protects: **derived, not trusted**, **atomic import**.

**W31 — Bring the wire protocol current. (M)**
Closes `NET-10`, `NET-11`, `NET-12`, `NET-14`, `NET-20`. Depends on nothing, and
the message-id block length correction to 18 **must land before any second
capability is negotiated** — otherwise `snap` lands at offset 33 where geth
places it at 34 and every message on both subprotocols is misrouted. Add
`decode-eth-receipts` for both encodings, the `BlockRangeUpdate` codec and
handler, block-range validation on the peer's Status, multi-frame reads, and
decide whether eth/70–72 are wanted. Verification: `tests/eth-wire-tests.lisp`
round trips for both receipt encodings; a negotiation test asserting the offsets
assigned for `eth` plus a hypothetical second capability match geth's.
Protects: honest capability boundaries.

**W32 — Discovery: endpoint, bonding, table maintenance, ENR. (M)**
Closes `NET-05`, `NET-06`, `NET-07`, `NET-08`, `NET-21`, `NET-22`. Depends on
nothing for the endpoint fix; the bonding change depends on the crawl and
responder sharing a socket. Run the crawl on the responder's socket or at
minimum set the `from` endpoint's TCP port to the real p2p port; ping back before
marking a node bonded and add a relay-address check; call
`discv4-table-note-failure` and `discv4-table-remove` from the crawl and dialer
and add a revalidation tick; add `ip`/`tcp`/`udp` to the served ENR and derive
its sequence number from something that changes; add NAT traversal; add discv5
last. Verification: a loopback two-node test asserting the endpoint a recipient
derives from our Ping equals our listener; a test asserting a Ping alone does not
put a node in a Neighbors reply; a test asserting a repeatedly-failing entry is
evicted; an interop check against geth 1.17.6 confirming it dials us back after a
bond.
Protects: honest capability boundaries.

**W33 — Inbound admission and peer accounting. (M)**
Closes `NET-15`, `NET-16`, `NET-18`. Depends on nothing. Add per-IP inbound
throttling and subnet limits, implement or reject `--netrestrict` and `--nat`
(coordinating with W20), record peer misbehaviour across sessions and send the
typed disconnect reasons, and shortcut the hash-origin header walk through the
canonical number index. Verification:
`tests/cli-devnet-peer-manager-tests.lisp` asserting a second connection from one
address inside the window is refused; a test asserting a skip-walk header query
costs one lookup per returned header.
Protects: the node's ability to stay up.

**W34 — Transaction gossip. (M)**
Closes `NET-13`, `POOL-15`, `NET-23`. Depends on W1 for the item-count caps.
Track hashes received from a peer as known to that peer, apply a 4096-byte
full-broadcast threshold and announce above it, offer queued transactions, drive
from a change set rather than a full rescan per peer per tick, and add
back-reference matching to `snappy-compress`. Verification:
`tests/eth-gossip-tests.lisp` asserting a transaction received from a peer is not
sent back to it and that a large transaction is announced rather than pushed.
Protects: nothing in the correctness list; it is what keeps peers from throttling
us.

*Exit criterion.* geth 1.17.6 dials us back after a bond; a mismatched body ends
the delivery and not the session; a download completes against three scripted
peers with more than one request in flight; a repeatedly-failing table entry is
evicted; a transaction received from a peer is never sent back to it; the `eth`
message-id block length is 18 and the negotiation test agrees with geth's
offsets for two capabilities.

### Phase 8 — Capability slices, contingent on the direction decisions

Each of these is one vertical slice. Partial work in any of them yields nothing
shippable, so none should be started before its decision is taken.

**W35 — Blob support as one slice. (L)**
Closes `EXEC-11`, `POOL-12`, `POOL-13`, `POOL-14`, `BUILD-08`, `RPC-06`; `RPC-10`
and `RPC-18` ride along cheaply. Depends on **D5**, and on W12 and W13. The slice
is: slots on the `blob-transaction` struct for blobs, commitments and proofs; a
decoder for the four-element EIP-4844 network wrapper alongside the existing
14-field canonical form, with the EIP-7594 version byte; pool admission that
calls `validate-blob-sidecar-fields` and `validate-blob-sidecar-kzg-proofs`
under the existing capability gate; blob-aware replacement with a blob-fee-cap
bump at 100%; blob-aware selection with a per-block blob budget; sidecar
retention through the build; and a real `blobsBundle` from `getPayload`. **State
plainly what the audits establish: partial work here yields nothing shippable.**
A network-wrapper codec with no pool admission accepts nothing; pool admission
with no selection stores transactions that are never mined, which is exactly
`POOL-13` today; selection with no bundle emits a payload whose commitments the
consensus client cannot publish. Verification: `cancun/eip4844_blobs/` fixtures;
a test asserting a sidecar with a mismatched proof is rejected when the backend
is present and that an absent backend refuses rather than accepts; a devnet slot
containing a blob transaction that a consensus client publishes.
Protects: **real cryptography on real paths** — the principle this most directly
contradicts today, since the verifier is present, correct-looking, and never
runs.

**W36 — Trie node store, range proofs, iterators, then snap. (L)**
Closes `STORE-06`, `STORE-07`, `STORE-11`, `STORE-12`, `NET-03`. Depends on
**D1**, **D2**, W23, W27 and W30. Snap sync is *blocked* by the storage
substrate, not merely sequenced after it: there is no trie to write downloaded
ranges into, no way to check a range against a state root, and no resumable
iterator to serve one. Build the node store first, then range-proof verification
and a resumable iterator, then `snap/1` — and only then a multi-peer snap sync.
Verification: range proofs against fixture vectors from geth 1.17.6; iterator
tests asserting resumption from an arbitrary start key returns each leaf exactly
once; the Hive `ethereum/sync` snap suite; a real sync against geth 1.17.6 on a
small public testnet.
Protects: **derived, not trusted** — synced state must be proved, not accepted.

**W37 — Amsterdam execution semantics. (L)**
Closes `EVM-01`, `EVM-02`, `EVM-03`, `EVM-05`, `EVM-18`, `EXEC-06`, `EXEC-07`,
`RPC-19`. Depends on **D3**, on W3 (which makes the wait safe), and on W6. Order
inside the slice: correct the two code-size constants (S); implement the four
opcodes (M); implement EIP-7708 transfer logs (M); derive the block access list
during execution (L); add the EIP-7997 transition and the EIP-8282 request types
(M); implement EIP-8037/8038 last (L), because it turns a scalar gas budget into
a two-dimensional one and touches the pricing of instructions that are correct
today. Do not attempt the last item without a fork-matrix gas test extended with
an Amsterdam column. Confirm the `balHash` spelling against `execution-apis`
before changing it. Verification: the `amsterdam/` EEST families —
`eip7928_block_access_lists/`, `eip7997_*`, `eip8282_*` — plus the fork-matrix
table; unit tests per opcode for stack effect, gas and pre-Amsterdam refusal.
Protects: **derived, not trusted**.

**W38 — Pre-merge scope: validate or remove. (M)**
Closes `EXEC-02`, `EXEC-04`, `EXEC-05`. Depends entirely on **D4**. If pre-merge
chains are in scope: implement geth's `VerifyUncles` — count cap, seven-ancestor
walk, duplicate and ancestor rejection, full header verification of each uncle —
plus the difficulty formula, seal verification, and the DAO drain-list transfer
and extra-data rule. If they are not: reject any non-empty ommer list
unconditionally, remove `apply-block-ommer-rewards`, stop parsing `daoForkBlock`
as though it were honoured, and write the scope decision into
`docs/validation.md`. Verification: the legacy `blockchain_tests` uncle families
if in scope, or a `tests/core-block-body-validation-tests.lisp` case asserting
rejection if not.
Protects: **derived, not trusted**, and honesty about what the client validates.

*Exit criterion.* Per slice, and only for the slices whose decision said build.
Blobs: a consensus client publishes a slot whose payload we built containing a
blob transaction, and a sidecar with a mismatched proof is rejected while an
absent backend refuses rather than accepts. Snap: a sync against geth 1.17.6
reaches the head from an empty datadir without executing every block, and range
proofs verify against geth-generated fixture vectors. Amsterdam: the `amsterdam/`
EEST families report non-zero, non-skipped counts and the fork-matrix gas test
has an Amsterdam column. Pre-merge: either the uncle families pass, or a
non-empty ommer list is rejected and the scope decision is written into
`docs/validation.md`. For each slice not built, the corresponding Engine method
or transaction type is refused rather than answered, which is W3's and W20's
criterion applied here.

### Phase 9 — Breadth, performance, hygiene

Goal: the remaining gaps, in the order their measurements justify.

**W39 — RPC breadth. (L)**
Closes `RPC-15`, `RPC-17`, `RPC-20`, `RPC-21`, `RPC-28`, `RPC-29`, `RPC-31`,
`RPC-33`, `RPC-36`, `EVM-13`. Order: `eth_config` first, because it is the
cheapest high-value method and everything it reports is already in
`chain-config`; then a gas-price oracle shared with `eth_feeHistory`; then state
and block overrides, then `eth_simulateV1` on top of them; then HTTP keep-alive;
then the tracing surface — `EVM-13`'s frame-type labelling first because it is
cheap and purely additive, then historic tracing, which needs the ability to
re-execute a mined block against its parent state; then a real pending block,
which is the largest wallet-facing item and the most entangled with block
building; `admin_removePeer`; and `trace_*` only if the D6 answer says to build
it. Verification: `execution-apis` override and EIP-7910 vectors; the
`rpc-compat` suite; call-tracer tests asserting the frame type for each of the
five call kinds.
Protects: nothing in the correctness list; this is breadth.

**W40 — EVM performance, after measurement. (M)**
Closes `EVM-10`, `EVM-11`, `EVM-12`, `EVM-14`. Depends on the benchmarks in the
follow-up list: all three magnitudes are `UNVERIFIED` and the ordering among
them depends on the answer. Then: geometric memory growth (S), a constant-time
stack depth (S), a jump-destination bitmap cached by code hash and scoped so it
cannot leak across blocks (M), and a precompile result cache (M). Every one of
these must not change a single gas number. Verification: unit tests asserting
`MSIZE` and memory gas are byte-identical before and after across a range of
expansion sequences; a test asserting a jump-heavy contract's gas is unchanged; a
test asserting identical gas and output for a repeated precompile call with the
cache on and off; benchmarks recorded outside the test suite.
Protects: liveness, which is a precondition for every correctness principle.

**W41 — Hygiene and recorded decisions. (S)**
Closes `EXEC-08`, `EXEC-09`, `EXEC-10`, `EXEC-13`, `EXEC-16`, `STORE-09`,
`RPC-22`, `RPC-26`, `RPC-32`, `NET-24`. Depends on nothing. Make the header RLP
encoder positional; give `receipt` a type field or unexport `receipt-list-root`;
resolve `EXEC-09` against `ethereum/execution-specs` and record the answer in a
comment; record `EXEC-08`'s and `EXEC-10`'s deliberate asymmetries; settle
`RPC-22` with one eval; return an error for an unknown `blockHash`; use `×` in
`txpool_inspect`; and update `docs/reference-map.md` per the note at the end of
this document. Verification: a case per change; `rpc-compat` for the two RPC
items.
Protects: honesty about what is deliberate.

*Exit criterion.* `eth_config` returns the EIP-7910 shape for a configured chain
and `eth_maxPriorityFeePerGas` is non-zero on a chain carrying paying
transactions; `rpc-compat` reports no method-not-found for anything this document
records as present; each EVM performance change carries a test asserting
byte-identical gas before and after, and follow-up 1's benchmarks are recorded
with both numbers; every Tier 8 finding is either closed or carries a source
comment recording that the behaviour is deliberate; `docs/reference-map.md` no
longer states that no reference checkout exists.

## Direction-level decisions

These are the project owner's to make, not an auditor's. Each is presented with
the evidence, and with the consequence of each answer. No answer is chosen here.

### D1 — Replace the storage substrate, or keep it and stay within its limits?

`PROJECT.md` reserves replacing a major storage substrate as a direction-level
decision, so `STORE-14` is evidence rather than a proposal.

*The evidence.* `file-key-value-database` is declared as
`(defclass file-key-value-database (memory-key-value-database) ...)`, so it
inherits the single in-memory `entries` hash table. Resident size therefore
equals total persisted size, open time is `O(file bytes)` with no index, and
compaction rewrites the whole file. No parameter changes any of this; the limit
is structural. Both references use an on-disk engine with a bounded working set —
Pebble or LevelDB plus freezer tables in geth, RocksDB in Nethermind.

*What the current engine gets right, and would be a shame to lose.* One
`fsync`ed CRC-framed record per batch, ordered before the in-memory mutation,
torn-tail detection with truncation deferred to the first write, fail-stop on
mid-log corruption, pure reads on open, handle poisoning after a partial append,
and v1 migration — covered by 27 tests. The durability engineering is sound. The
problem is capacity, not correctness.

*If the answer is "replace":* the work is L and gates W27's schema design and
W36 entirely, and the entire `tests/database-tests.lisp` durability suite must
pass against the new engine, plus a crash-injection test that kills the process
mid-batch and asserts the reopened database contains either all of it or none.

*If the answer is "keep":* the state audit is explicit that a devnet or a small
private chain is served correctly and durably by what exists today, and that
W23, W24, W25, W26, W27 and W28 — items 1 through 6 of its own plan — deliver
most of the practical benefit at a fraction of the cost. `STORE-24` resolves
with this decision either way, and the inert `--cache.*` flags should be
rejected per W20 rather than left to imply that cache sizing works.

### D2 — What is the target: a devnet, a public testnet, or mainnet?

This single choice reorders most of the plan, and no document in the tree states
it. `PROJECT.md` says the project "does not claim production mainnet readiness"
and that the client should "synchronize with peers and interoperate with real
consensus and execution clients", which bounds the answer without fixing it.

*Follow a devnet driven by a real consensus client.* Then Phases 1 through 5 are
the whole plan, plus W22's presets for Hive. `NET-03` (snap), `NET-04`
(multi-peer download), `STORE-17`/`STORE-19` (retention) and D1's replacement
are all out of scope, because a devnet's state fits in RAM and its chain is
short. `NET-05` still matters, because a consensus client's execution peer must
be reachable. This is the cheapest target and the one the existing code was
built for.

*Sync a public testnet.* Then D1 tips toward "replace", `NET-03` and `NET-04`
become required rather than optional, W27's retention work becomes required, and
W36 becomes the largest item in the plan. The state audit's
quantification is the relevant number: a full baseline every 128 blocks stores
the world state again, so retaining 1000 blocks of a 10-million-entry state costs
roughly 78 million entries, all resident.

*Mainnet.* Then everything above plus `EXEC-05` and `EXEC-02` (D4 answered
"in scope", for replay from genesis), `RPC-20`'s real pending block, W39's full
tracing surface, and a performance programme informed by W40's measurements. The
state audit's estimate for mainnet state is "on the order of 250 million accounts
and slots; at even 100 bytes of Lisp object overhead per entry that is tens of
gigabytes before block bodies", against a ceiling that is RAM rather than disk.

### D3 — Keep Amsterdam scheduled while its semantics are unimplemented, or deschedule it?

*The evidence.* Our `chain-config` accepts `amsterdam-time`, and
`engine_newPayloadV5` and `engine_forkchoiceUpdatedV4` are dispatched whenever
the configured chain reaches Amsterdam. Behind that surface, four opcodes are
absent (`EVM-01`), the EIP-8037/8038 metering dimension does not exist in our
design (`EVM-02`), the code-size constant is half what it should be in two
places (`EVM-03`), EIP-7708 transfer logs are absent (`EVM-05`), the block access
list has no producer (`EXEC-06`), and EIP-7997 and EIP-8282 are absent
(`EXEC-07`). geth leaves `AmsterdamTime` unset for mainnet at this commit, so the
only reachable target today is a devnet.

*If Amsterdam stays scheduled:* W3 must land first so the node refuses rather
than answering, and W37 is a large slice — the EIP-8037/8038 half alone requires
turning a scalar gas budget into a two-dimensional one across every charge site,
and it should not start before an Amsterdam column exists in the fork-matrix gas
test.

*If Amsterdam is descheduled until the EVM catches up:* `chain-config` should
reject `amsterdamTime` rather than accept it, the Amsterdam Engine methods
should be absent rather than gated, `EVM-18`'s five unassessed EIPs need no
assessment yet, and eight findings leave the active plan. The cost is that the
first Amsterdam devnet the ecosystem stands up is one we cannot join at all,
rather than one we join and then refuse to validate.

### D4 — Are the pre-merge and proof-of-work paths in scope?

*The evidence.* We pay uncle rewards and validate no uncle beyond the ommers
hash (`EXEC-02`), we verify no proof-of-work seal and compute no expected
difficulty (`EXEC-04`), and we parse `daoForkBlock` without implementing either
the drain-list transfer or the extra-data rule (`EXEC-05`). `STORE-02`'s
non-fork-gated empty-account deletion is inert post-merge and consensus-breaking
below block 2,675,000. The block-execution audit searched `PROJECT.md`,
`docs/validation.md` and `docs/architecture.md` for "proof-of-work", "ethash",
"pre-merge" and "PoW" and found no match, so the omission is **undocumented
rather than stated**.

*If they are in scope:* W38 implements `VerifyUncles`, the difficulty formula,
seal verification and the DAO transition, and `STORE-02` becomes a required fix
rather than an inert one. The audit notes that `ommer-block-reward` can go
negative for an uncle far below the block and that what the state database does
in that case is unverified.

*If they are not:* reject any non-empty ommer list, delete
`apply-block-ommer-rewards`, stop parsing `daoForkBlock`, and write the scope
decision into `docs/validation.md`. Four findings leave the plan and one
(`STORE-02`) is downgraded to a documented limitation. Note that this is the
cheaper answer and the one the code already behaves as though were true — it is
just not written down anywhere, which is the actual defect.

### D5 — Carry blob sidecars, or decline type-3 transactions at admission?

The txpool audit frames this as "a design decision before it is work", and the
two answers differ by an order of magnitude in cost.

*The evidence.* The `blob-transaction` struct has `blob-versioned-hashes` and no
blobs, commitments or proofs; `blob-transaction-from-rlp` requires exactly 14
fields, so the four-element network wrapper a real sender submits does not decode
at all; `validate-blob-sidecar-fields` and `validate-blob-sidecar-kzg-proofs`
have no caller (coordinator fact 3); a pooled blob transaction is accepted,
never selected, never gossiped and never expired (`POOL-13`, executed).

*Carry them:* W35, an L slice as described, and what a mainnet client needs.

*Decline them:* reject type-3 at admission with a message naming the limitation,
and decline `getPayloadV3` and later rather than returning an empty
`blobsBundle` — the position `PROJECT.md`'s capability-gating principle suggests.
Small and honest. The txpool audit's proposed verification for this path is a
test asserting `eth_sendRawTransaction` of a type-3 transaction is refused with a
message naming the limitation and that `txpool_status` never reports a blob
transaction. Note that a Cancun-or-later chain with real blob traffic is not
followable either way until the sidecar verification exists, because `EXEC-11`
means nothing we own ever checks a blob against its commitment.

### D6 — How wide should the tracing surface be?

Smaller than the four above, but it is a decline-or-build question and the audits
raise it twice. `EVM-13` argues in the source that a per-opcode hook costs
something on every step and deliberately provides only call boundaries; `RPC-28`
records that `structLog`, `prestateTracer`, `4byteTracer` and every per-opcode
tracer are therefore unimplementable on the current surface, and `RPC-29` notes
that geth does not serve `trace_*` at all, so declining it is defensible. The
decision is whether to add the interpreter hook, and if not, to say plainly in
the RPC documentation which tracers can never be served. The frame-type
mislabelling — `CREATE`/`CREATE2` untraced, `DELEGATECALL`/`CALLCODE` reported
as `CALL` — is worth fixing either way and is in W39.

## Follow-ups: converting UNVERIFIED findings into verified ones

The warm image is available again, so the items below are now cheap. Ordered by
whether the answer could change a severity. All are grounding tasks, not
remediation.

| # | Finding | What to run | What changes if it goes the other way |
| --- | --- | --- | --- |
| 1 | `EVM-10`, `EVM-11`, `EVM-12` | Benchmark memory growth one word at a time to ~10⁵ words, pushes to the 1024 limit, and a tight jump loop at the end of a 24,576-byte contract, at a 30,000,000-gas budget | **Severity and ordering both.** One of these could be the single largest practical problem in the EVM, or a non-issue at realistic gas limits. W40 should not be scheduled before this |
| 2 | `STORE-03` | Search for a transaction sequence that routes an all-zero account through `state-db-set-account` without a non-zero nonce or non-empty code hash | **Severity.** Latent structural divergence today; a reachable trigger makes it consensus-breaking |
| 3 | `EVM-15` | Compare `block-header-post-merge-p` against geth's `IsMerge` on every header the import path can construct, including a terminal-block header, and check what call simulation's hardcoded `:random-p t` does for a pre-merge block | **Severity.** Completeness today; a disagreement makes `0x44` push a wrong value |
| 4 | `RPC-22` | One eval: does `block-header-blob-base-fee` apply the update fraction to the header's own excess gas or to its successor's? | **Verdict.** Becomes a correctness finding or a recorded non-gap |
| 5 | `RPC-08` | Inspect whether `src/storage/chain-store/service/cache.lisp` bounds the number of stored prepared payloads | **Severity.** A stated risk becomes a memory-exhaustion fact reachable by a busy pool |
| 6 | `NET-11` | Evaluate `rlpx-negotiate-capabilities` against geth's and Nethermind's real advertised version sets | Confirms the latent trap before W31 or W36 touches capability negotiation. Must be settled *before* a second capability is added, not after |
| 7 | `NET-01` | Feed a depth-21700 body through an `eth`-wire decoder end to end, not only through the handshake budget arithmetic | Nothing in the trace suggests it would not fire; this closes the last gap in the demonstration |
| 8 | `BUILD-01`, `BUILD-02` | Build a payload with a poisoned pending list and observe what `forkchoiceUpdated` returns in each of the two failure classes; admit a transaction inside the base-fee window and attempt a build | Converts the two highest-severity building findings from source-read to executed. Coordinator fact 2 already confirms the condition-hierarchy half |
| 9 | `POOL-07` | Inspect a node's `txpool-admission-policy` struct after startup with no `--txpool.*` flags | Confirms the `NIL`-default reading that `POOL-07`, `POOL-09` and `POOL-10` all rest on |
| 10 | `STORE-16` | Enumerate every caller to establish whether any configuration splits one logical export across multiple `kv-apply-batch` calls | **Durability claim.** The end-to-end atomicity argument holds for the two entry points read; it is not established for all callers |
| 11 | `EXEC-15` | Settle the state-test generator expansion count and the list of `v5.4.0` families not selected | Both are settled as a side effect of W6 |
| 12 | `EXEC-02` | Determine whether `ommer-block-reward` can go negative for an uncle more than eight blocks below the header, and what `state-db` does | Adds a failure mode to `EXEC-02` if pre-merge stays in scope |
| 13 | `EXEC-10` | Determine whether the withdrawals-before-requests ordering is observable for any predeploy other than the canonical EIP-7002 and EIP-7251 bytecode | **Verdict.** A structural difference becomes a divergence or is closed |
| 14 | `EXEC-09` | Read `ethereum/execution-specs` on whether a checked request system call must fail the block | Settles a direction, not a magnitude. Record the answer in a comment either way |
| 15 | `OPS-03` | Two processes on one datadir on a real filesystem — not an eval | Establishes whether concurrent writes corrupt or whether the generation check catches it. Does not change the need for the lock |
| 16 | `OPS-01` | Re-derive the 56-flag count mechanically rather than by comparing lists by hand | The count may be slightly high if a flag is consumed in `init.lisp`'s separate parser. Five spot checks already confirmed |
| 17 | `RPC-15` and neighbours | Compare the result shapes of `eth_getProof`, `eth_createAccessList`, `eth_getRawTransactionByHash` and the `debug_getRaw*` family byte for byte against geth's | Could turn three "presence confirmed" cells into divergences |
| 18 | `STORE-14` | Real crash behaviour: kill a process mid-`fsync` | The code path is right by inspection, which is not the same as verified. Required for D1 either way |

Two items the six documents list as unverified are already **settled**, and should
not be re-run:

- Whether a blob transaction can reach the pending list (`RPC-06`, which the RPC
  audit called the most important of its unverified items). It cannot —
  `POOL-13`'s executed evidence shows `validate-store-transaction` refuses a
  `blob-transaction` in every non-blob subpool, and
  `engine-payload-store-pending-mining-transactions` reads the pending subpool
  alone. So the always-empty `blobsBundle` is a missing capability, not an
  internal inconsistency.
- Whether a crafted RLP input escapes the handlers (`EXEC-14`). It does —
  coordinator fact 1.

One category cannot be converted by an eval at all and should be planned as
separate work: **nothing in these documents has been checked against a running
reference client.** Converting the consensus findings from "both references' source
disagrees with ours" to "both references' binaries disagree with ours" needs W6's
fixtures and, for the Engine findings, a Hive run. W22's presets are the
precondition for the latter.

## `docs/reference-map.md` is out of date

That file states, twice, that no `references/` checkout exists on this machine —
in its "devp2p and peering" section and again under "Upstream versions actually
fetched and read". Both statements were true when written and are now false: both
checkouts are present at the commits named at the top of this document, and both
hashes were confirmed on the host.

The peering section goes further and draws a conclusion from the absence: that
"the peering work therefore makes NO parity claim" and that every peering
constant is documented as our policy rather than as matching another client.
That conclusion is now superseded. The networking audit produced a 33-row
peering-constant parity table comparing our constants against geth 1.17.6 and
Nethermind 1.40.0 constant by constant, with three exact matches called out as
things not to change casually (`+eth-pump-ping-interval-seconds+`,
`+devnet-peer-handshake-timeout-seconds+`, `+devnet-dial-ratio+`) and several
deliberate differences recorded as such.

Recommended correction, to be made by whoever owns that file — **this document
does not edit it**:

1. Delete the "**No `references/` checkout exists on this machine.**" paragraph
   from the "devp2p and peering" section and replace it with a pointer to the
   peering-constant parity table in
   [networking-and-sync.md](networking-and-sync.md), naming the two commits, and
   with the note that individual docstrings still describe their constants as our
   policy and should be updated where the table now supports a parity claim.
2. In "Upstream versions actually fetched and read", replace the
   scratch-space paragraph with the two pinned commits and their read date,
   keeping the existing per-version record for `docs/gas-parity.md` — whose pins
   really are spread across three geth and three Nethermind versions, which is a
   recorded limitation there and should stay recorded.
3. Add the caveat this document opens with: `references/` is an untracked
   working-tree clone, so a fresh clone or a new worktree has neither checkout,
   and any parity claim re-checked there must re-fetch the exact commits.

## Where the audits disagree, and how it is resolved

Preserving each audit's verdict means not averaging them. Five genuine conflicts
and three stale cross-references.

**1. Is the empty `blobsBundle` an inconsistency?** `rpc-and-engine.md` records
`RPC-06` as `DIVERGENT` and lists "whether a blob transaction can reach the
pending list" as the most important of its unverified items, noting that if one
can, the node would emit a payload whose blob commitments have no matching
bundle — "worse than emitting neither".
`txpool-building-and-ops.md` answers it by execution: it cannot.
**Resolution: the executed evidence wins.** `POOL-13`'s eval shows the blob
subpool is the only one that accepts a `blob-transaction` and that
`engine-payload-store-pending-mining-transactions` never reads it, so `BUILD-08`
settles `RPC-06` as a missing capability rather than an inconsistency. Both
verdicts stand; the severity qualifier "on a chain with blob traffic" is what
carries `RPC-06`'s weight, not an internal contradiction.

**2. Is `engine_newPayloadV5` gated?** `rpc-and-engine.md`'s Engine inventory
marks `newPayloadV5` as "gated | KZG-backed; requires the c-kzg shim", while
`evm-and-gas.md`'s `EVM-04` says it is enabled at Amsterdam with no Amsterdam
EVM. **Both are correct and the reading conflict matters.** The method is gated
on KZG availability and on nothing else; `EVM-04` establishes that the gate does
not cover execution semantics, so a node with a working c-kzg shim advertises
and dispatches it. A reader taking the inventory's "gated" cell as adequate would
miss the finding entirely. The stronger evidence is `EVM-04`'s, which cites the
registry and the single availability predicate directly.

**3. Does the blob situation satisfy or contradict "real cryptography on real
paths"?** `POOL-14` argues the principle "is satisfied in the negative here — we
do not fake a verification, we decline the transaction shape". `EXEC-11` calls
the same absence "the clearest place the tree does not meet it".
**Resolution: they are describing different code paths and both are right.**
`POOL-14` is about the pool, where nothing is faked because nothing with a
sidecar is ever accepted. `EXEC-11` is about the Engine `getBlobs`/`newPayload`
bundle path and the key-value import path, where a sidecar *does* arrive and the
verifier that exists is never called — confirmed by coordinator fact 3. The
sharper statement for a live path is `EXEC-11`'s. Both verdicts are preserved and
both are closed by W35.

**4. `EXEC-14` versus `NET-01` on severity.** The block-execution audit records
`UNVERIFIED`, "correctness if confirmed", explicitly because it could not run a
deep decode. The networking audit records `DIVERGENT`, `remote-DoS`, whole-process
death. This is not a disagreement about facts but a difference in the evidence
available, and coordinator fact 1 resolves it in the networking audit's favour.
`EXEC-14`'s `UNVERIFIED` is superseded; the finding is confirmed and ranks in
Tier 1.

**5. Two vocabularies for unbounded remote input.** The networking audit calls an
unauthenticated caller consuming unbounded resources `remote-DoS` (`NET-02`,
`NET-15`, `NET-17`); the RPC audit calls the same shape `performance (denial of
service)` (`RPC-16`, `RPC-35`) and plain `performance` (`RPC-25`).
**Resolution: this is vocabulary, not evidence, and it is resolved by rank
rather than by re-labelling another audit's finding.** Tier 5 exists for exactly
this class. The one substantive difference behind the labels is reachability: the
networking surface is exposed by definition, while the RPC items are only
reachable when a public listener is enabled, which the recommended posture does
not do.

**Three stale cross-references, resolved by content.** `txpool-building-and-ops.md`
cites "RPC-38" twice for the ignored-flags pattern, but `RPC-38` in
`rpc-and-engine.md` is the virtual-hosts default; the ignored-flags finding there
is `RPC-37`. The same document cites "RPC-01" twice for the payload-id
derivation, which is `RPC-08`; `RPC-01` is `eth_syncing`. This document uses the
content-correct ids throughout: `OPS-01` subsumes the flag halves of `RPC-16`,
`RPC-35` and `RPC-37`, and the payload-id question is `RPC-08`.

**One difference of scope that is not a conflict.** `state-trie-storage.md` calls
`STORE-21` "the highest-risk gap" and puts `STORE-14` first in its executive
summary. Neither appears near the top of the ranking here: `STORE-21` sits in
Tier 4 and `STORE-14` in Tier 7. Both area judgements are right within their
area — a node that will not start is the worst thing that can happen to the
storage layer — and both are outranked across the tree by a remote process kill
and by wrong answers a caller cannot see through. `STORE-14` in particular is
ranked low because it is not schedulable work at all; it is decision **D1**.
