# docs/evidence

This directory is the audit trail for exact-revision claims. PROJECT.md
requires every parity or conformance claim to name exact versions and commits.
A claim such as "Hive rpc-compat 234/234" or "the healer converged on Hoodi"
counts only when a record here names the revision, the pinned inputs, the
commands and their exit codes.

The directory holds two kinds of record.

1. **Gate results**, one row per revision in [gates.md](gates.md). A row covers
   the amd64 runtime artifact and its smoke, the current-fork EEST v20.0.2
   gates, the pinned Hive rpc-compat / engine / devp2p suites, and the Hoodi
   live run. Until 2026-09-24 each gate result was its own file
   (`sec5-<rev8>-amd64-runtime.txt`, `-eest-v20.0.2.txt`, `-hive-*.txt`,
   `-hoodi-*.txt`). Files for the milestone revisions (aac5f762, d203fee6,
   b5161312, 591f700e) are still here, as is
   `sec5-8e95b990-hoodi-complete.txt`, the completion skeleton that
   `sec5-8e95b990-acceptance-plan.txt` tells the coordinator to fill.
   `gates.md` lists each row's source files and marks the ones deleted in
   `f0136810` (†) and `f9100e98` (‡). Read a deleted one with
   `git show <commit>^:docs/evidence/<file>`. Other documents cite a gate
   result as "`docs/evidence/gates.md`, row <rev8>".
2. **Root-cause records** (`sec5-<topic>.txt`, `sec5-<rev8>-<topic>.txt`,
   `sec10-<topic>.txt`). Each covers one defect or one question: mechanism,
   reproduction, fix, verification of record, and what is not verified. The
   index below lists every one of them.

## Rule for new records

- A gate result is **one row in gates.md**: revision, UTC date, runtime tar
  sha256 (first 12 hex) and smoke, EEST, Hive x3, Hoodi outcome in one phrase,
  and a notes clause. Put the full 40-hex revision and the name of any source
  record in the second table. Do not create a new file for a gate result.
- Write a new `.txt` only for a **root-cause analysis**: mechanism,
  reproduction (RED before GREEN), fix commit(s), verification of record
  (exact commands, test names, counts, exit codes), and "Not verified". Add it
  to the index below in the same commit.
- Keep exact claims exact. Write the 8-hex short form in prose and give the
  full revision where it first appears.

## Index of root-cause records

Format: problem → record → fix commit(s). The fix commits are the ones the
record names in its Status or Revision section. "(test)" marks a commit that
pins behaviour with a test and changes no production code. "—" means the
record names no fix.

### Section 5: SNAP range phase, healing and live convergence

- Healer finished its frontier, then the node died on a missing account trie node: prebuffered account records had no incomplete markers → [sec5-03263d2f-account-closure-failure.txt](sec5-03263d2f-account-closure-failure.txt) → —
- The same death on the storage side: marker-only storage closure was trusted → [sec5-b23c7d57-storage-closure-failure.txt](sec5-b23c7d57-storage-closure-failure.txt) → —
- r2 Hoodi run stalled because every probed pivot root was rejected as unavailable → [sec5-b23c7d57-hoodi-r2-stall-20260909.txt](sec5-b23c7d57-hoodi-r2-stall-20260909.txt) → —
- Completion barrier published before descendants settled; fresh live rerun → [sec5-0c6b51bf-completion-barrier-live-start.txt](sec5-0c6b51bf-completion-barrier-live-start.txt) → 0c6b51bf
- Runtime artifact of the productive local-healer expansion repair → [sec5-21a41c04-productive-healer-runtime.txt](sec5-21a41c04-productive-healer-runtime.txt) → 9f697ec6 (functional), 21a41c04
- Hoodi EL OOM-killed: SNAP storage results were buffered without a memory bound → [sec5-7f03aed4-snap-memory-bound.txt](sec5-7f03aed4-snap-memory-bound.txt) → — (the record names only its base, 7f03aed4; git shows it was added by e27db183 "Bound SNAP memory under Hoodi cgroup")
- Completing SNAP needs an executable target tail → [sec5-40be2940-snap-tail-completion.txt](sec5-40be2940-snap-tail-completion.txt) → 40be2940
- Continuous-sync gap queue closed a peer queue and never retried it → [sec5-616709b5-gap-queue-lifecycle.txt](sec5-616709b5-gap-queue-lifecycle.txt) → 616709b5
- Forkchoice target dropped before publication → [sec5-ade47e78-forkchoice-publication.txt](sec5-ade47e78-forkchoice-publication.txt) → ade47e78
- A completed durable SNAP target was scheduled again → [sec5-bb9cf83d-completed-snap-scheduling.txt](sec5-bb9cf83d-completed-snap-scheduling.txt) → bb9cf83d
- The live SNAP pipeline refilled without a frontier bound → [sec5-fcf458ca-snap-live-frontier.txt](sec5-fcf458ca-snap-live-frontier.txt) → fcf458ca
- Different SNAP request kinds used different pool deadlines → [sec5-83c5e3ce-pool-deadline.txt](sec5-83c5e3ce-pool-deadline.txt) → 83c5e3ce
- Healer deferred proved subtrees only inside the frontier → [sec5-c0cce53d-heal-deferral-frontier.txt](sec5-c0cce53d-heal-deferral-frontier.txt) → c0cce53d
- Is the range-download stall ours or the peers'? Same-host geth v1.17.4 control → [sec5-fb4cb6f3-geth-control-baseline.txt](sec5-fb4cb6f3-geth-control-baseline.txt) → — (baseline)
- Healing did not converge after the first complete range download; an attempted fix was reverted → [sec5-healing-completeness-audit.txt](sec5-healing-completeness-audit.txt) → —
- Healer re-walked closed storage subtrees → [sec5-5c8a39c0-storage-closure-epoch.txt](sec5-5c8a39c0-storage-closure-epoch.txt) → 5c8a39c0
- Where the healer's remaining marked work comes from; storage plans need segmentation → [sec5-heal-stale-marker-trace.txt](sec5-heal-stale-marker-trace.txt) → —
- A restart inside a segmented storage plan published completion over the unhealed remainder → [sec5-c4e9ec34-storage-plan-segments.txt](sec5-c4e9ec34-storage-plan-segments.txt) → c4e9ec34
- Range-plan promotion returned 0 for any plan wider than 8,192 works → [sec5-519e4c9b-range-plan-promotion-stream.txt](sec5-519e4c9b-range-plan-promotion-stream.txt) → 519e4c9b
- 3305307d heal stalled for days: promotion is unreachable live because a mid-range rebase replaces the partial root → [sec5-3305307d-hoodi-stall.txt](sec5-3305307d-hoodi-stall.txt) → —
- Offline reproduction of the mid-range pivot rebase that zeroes promotion → [sec5-mid-range-rebase-reproduction.txt](sec5-mid-range-rebase-reproduction.txt) → —
- Account-side closure: persist an account node only when its closure is durable → [sec5-account-closure-epoch7.txt](sec5-account-closure-epoch7.txt) → b785afeb, ef70708c, 619acead, 6e5c7a73 (epoch bump merged as 5605c936)
- Withheld fraction of the closed account writer at page density and after a rebase → [sec5-closure-density-measurement.txt](sec5-closure-density-measurement.txt) → 200e102b (measurement)
- The snap/1 server wrote the state it served; cross-thread crash seams untested → [sec5-snap-server-closure.txt](sec5-snap-server-closure.txt) → 00cf8da4, 4271833b, b2b36ac4
- The local heal walk's per-node cost, and its read width collapsing to one → [sec5-heal-walk-throughput.txt](sec5-heal-walk-throughput.txt) → 67039a6e, 7e9d8cab
- Stale incomplete markers left by StorageRanges partitions of byte-capped contracts → [sec5-marker-population.txt](sec5-marker-population.txt) → c8501639
- Post-order sentinels closed heal read batches, and checkpoint room held the width at one → [sec5-heal-sentinel-width.txt](sec5-heal-sentinel-width.txt) → daa95d7f, e62f647f, 3e7cbd65
- Hunting a false completion behind "Persisted trie node ... is missing": the cause is the forward batch importer's storage overlay → [sec5-false-completion-hunt.txt](sec5-false-completion-hunt.txt) → branch pending-storage-overlay (merged at 8e95b990)
- Acceptance plan for the 8e95b990 live run (a plan, prepared and not run) → [sec5-8e95b990-acceptance-plan.txt](sec5-8e95b990-acceptance-plan.txt) → —

### Section 5: Engine API, forward sync and head following

- Engine HTTP keep-alive shared the request deadline → [sec5-0cffbcb4-engine-http-idle.txt](sec5-0cffbcb4-engine-http-idle.txt) → 0cffbcb4
- Engine JWT clock was sampled before request intake → [sec5-277ffb52-engine-jwt-clock.txt](sec5-277ffb52-engine-jwt-clock.txt) → 277ffb52
- Payload status JSON carried a nonstandard `witness:null` → [sec5-a565a5b4-engine-witness-fix.txt](sec5-a565a5b4-engine-witness-fix.txt) → a565a5b4
- Hive engine-cancun blob ordering regression → [sec5-694667f9-hive-blob-order.txt](sec5-694667f9-hive-blob-order.txt) → 694667f9
- Local RPC/Engine compatibility: newPayload parameter arity → [sec5-7b86ca24-rpc-engine-compat.txt](sec5-7b86ca24-rpc-engine-compat.txt) → 30ad66d1, 7b86ca24
- Engine requests timed out while the forward batch importer held the store guard → [sec5-engine-timeouts-forward-sync.txt](sec5-engine-timeouts-forward-sync.txt) → — (merged as c831c9a6, per sec5-d203fee6-amd64-runtime.txt)
- A peer hanging up during a gap fill shut the node down → [sec5-forward-sync-peer-errors.txt](sec5-forward-sync-peer-errors.txt) → 6e09dd40
- eth_syncing froze at the pivot while the store guard was busy → [sec5-eth-syncing-live-head.txt](sec5-eth-syncing-live-head.txt) → f514145f
- Two Hive Engine failures at d203fee6: the gossip gate read a stale sync view (client), and Missing Ancestor is hive#1351 (harness) → [sec5-engine-regressions-d203fee6.txt](sec5-engine-regressions-d203fee6.txt) → — (merged as 747ca812, per sec5-engine-regressions-aee866f7.txt)
- Two Hive Engine failures at aee866f7: blob propagation between two clients (client), and Missing Ancestor is hive#1351 (harness) → [sec5-engine-regressions-aee866f7.txt](sec5-engine-regressions-aee866f7.txt) → — (merged as b5161312, per sec5-b5161312-amd64-runtime.txt)
- A restarted node a few hundred blocks behind re-entered SNAP and died on a known block → [sec5-restart-behind-resnap.txt](sec5-restart-behind-resnap.txt) → 6b37b097
- newPayload latency at the head: the parent's rewritten trie nodes were re-read → [sec5-newpayload-latency.txt](sec5-newpayload-latency.txt) → 9a9b872f, 52d0aa46
- The six-second newPayload quantum; background guard takers jumped ahead of waiting Engine requests → [sec5-newpayload-six-second-quantum.txt](sec5-newpayload-six-second-quantum.txt) → 82b217e6, 6fe683b0
- The six seconds are EVM interpreter throughput on Hoodi gas-burner blocks → [sec5-newpayload-six-second-cpu.txt](sec5-newpayload-six-second-cpu.txt) → 43be69c5
- Engine requests timed out behind long store-guard holds (R4) → [sec5-engine-availability.txt](sec5-engine-availability.txt) → 1b84073c, 28721a06
- Peer-session holds of 20-134 s and heap growth: snap serving enumerated whole tries → [sec5-peer-session-holds.txt](sec5-peer-session-holds.txt) → 6dae34ea
- forkchoiceUpdated's growing CPU cost was the txpool reconciliation → [sec5-fcu-canonical-cost.txt](sec5-fcu-canonical-cost.txt) → 80da9d7c
- 11.5 GB anonymous RSS with a 0.5-4 GB Lisp heap: freed C-heap memory stayed resident → [sec5-resident-memory.txt](sec5-resident-memory.txt) → a910eeea, 35c4453b

### Section 5: shutdown and exit

- SBCL memory fault on a clean operator stop, traced to glibc free at exit with the store open → [sec5-shutdown-memory-fault-trace.txt](sec5-shutdown-memory-fault-trace.txt) → —
- Static audit of foreign frees at exit (negative), and why a graceful stop outlasts 30 s → [sec5-shutdown-provenance-audit.txt](sec5-shutdown-provenance-audit.txt) → — (HTTP stop fix on the audit branch, commit not named)
- The node reached exit(3) with RocksDB open and its pools populated → [sec5-exit-fault-store-close.txt](sec5-exit-fault-store-close.txt) → 68c244b7, ad6ed0c3, 736ce3ac, 2781311a
- SIGTERM during an active heal walk never reached the store close → [sec5-sigterm-during-heal.txt](sec5-sigterm-during-heal.txt) → 4ed38c80

### Section 5: devp2p, Hive adapter and pinned geth regressions

- Hive discovery cases start the client without /genesis.json → [sec5-0ba3a950-hive-discovery-genesis.txt](sec5-0ba3a950-hive-discovery-genesis.txt) → — (repair on base 0ba3a950)
- Hive devp2p cloned geth master; pin the source it really used → [sec5-f19ee8d5-hive-devp2p-geth-pin.txt](sec5-f19ee8d5-hive-devp2p-geth-pin.txt) → — (repair on base f19ee8d5)
- First complete Hive devp2p discovery run: failure inventory and fork-ID adapter repair → [sec5-b7bdb6da-hive-devp2p-discovery.txt](sec5-b7bdb6da-hive-devp2p-discovery.txt) → b7bdb6da
- LargeTxRequest regression → [sec5-8b92d05e-hive-large-tx-regression.txt](sec5-8b92d05e-hive-large-tx-regression.txt) → 8b92d05e (test)
- NewPooledTxs regression → [sec5-7ee257f2-hive-new-pooled-regression.txt](sec5-7ee257f2-hive-new-pooled-regression.txt) → 7ee257f2 (test)
- TestTransaction propagation → [sec5-acecf50e-hive-transaction-propagation.txt](sec5-acecf50e-hive-transaction-propagation.txt) → acecf50e (test)
- TestInvalidTxs propagation → [sec5-9b5ec2a6-hive-invalid-transactions.txt](sec5-9b5ec2a6-hive-invalid-transactions.txt) → 9b5ec2a6 (test)
- BlobViolations: pooled transaction announcements not validated → [sec5-8286eb7f-hive-blob-violations.txt](sec5-8286eb7f-hive-blob-violations.txt) → 8286eb7f
- Malformed blob peers were not disconnected → [sec5-233756d8-hive-bad-blob-peers.txt](sec5-233756d8-hive-bad-blob-peers.txt) → 233756d8
- Invalid Cells → [sec5-6c23ab8a-hive-invalid-cells.txt](sec5-6c23ab8a-hive-invalid-cells.txt) → 6c23ab8a (test)
- Full-custody blob fetch → [sec5-2db4c38f-hive-blob-availability.txt](sec5-2db4c38f-hive-blob-availability.txt) → 2db4c38f (test)
- GetCells production handoff → [sec5-085d03c3-hive-get-cells.txt](sec5-085d03c3-hive-get-cells.txt) → 085d03c3 (test)
- Zero-blob eth/72 responses failed the availability check → [sec5-1a9898a3-hive-zero-blob-availability.txt](sec5-1a9898a3-hive-zero-blob-availability.txt) → 1a9898a3
- Empty SNAP TrieNodes request → [sec5-1ade9726-hive-snap-empty-request.txt](sec5-1ade9726-hive-snap-empty-request.txt) → 1ade9726 (test)
- Malformed (empty-path) SNAP TrieNodes request → [sec5-56f0cc8b-hive-snap-empty-path.txt](sec5-56f0cc8b-hive-snap-empty-path.txt) → 56f0cc8b (test)
- Long SNAP TrieNodes path → [sec5-ce21fecf-hive-snap-long-path.txt](sec5-ce21fecf-hive-snap-long-path.txt) → ce21fecf (test)
- SNAP trie-root response → [sec5-7c1e379c-hive-snap-trie-root.txt](sec5-7c1e379c-hive-snap-trie-root.txt) → 7c1e379c (test)
- SNAP storage-root response → [sec5-48d5a505-hive-snap-storage-root.txt](sec5-48d5a505-hive-snap-storage-root.txt) → 48d5a505 (test)
- Multiple SNAP storage nodes → [sec5-5da70c3a-hive-snap-multiple-storage-nodes.txt](sec5-5da70c3a-hive-snap-multiple-storage-nodes.txt) → 5da70c3a (test)
- Unsorted SNAP account paths → [sec5-677a8308-hive-snap-unsorted-account-paths.txt](sec5-677a8308-hive-snap-unsorted-account-paths.txt) → 677a8308 (test)
- Known SNAP account paths → [sec5-7449e766-hive-snap-known-account-paths.txt](sec5-7449e766-hive-snap-known-account-paths.txt) → 7449e766 (test)
- Empty code hash in GetByteCodes → [sec5-b20d83b4-hive-snap-empty-code-hash.txt](sec5-b20d83b4-hive-snap-empty-code-hash.txt) → b20d83b4 (test)
- Duplicate empty code hashes → [sec5-5fda6c27-hive-snap-duplicate-empty-code-hash.txt](sec5-5fda6c27-hive-snap-duplicate-empty-code-hash.txt) → 5fda6c27 (test)
- All requested bytecodes served → [sec5-18911a11-hive-snap-all-bytecodes.txt](sec5-18911a11-hive-snap-all-bytecodes.txt) → 18911a11 (test)
- Duplicate non-empty code hashes → [sec5-06e53af5-hive-snap-duplicate-code-hash.txt](sec5-06e53af5-hive-snap-duplicate-code-hash.txt) → 06e53af5 (test)
- GetByteCodes soft byte limit → [sec5-553f9f53-hive-snap-soft-byte-limit.txt](sec5-553f9f53-hive-snap-soft-byte-limit.txt) → 553f9f53 (test)
- Unknown code hashes omitted → [sec5-3140e224-hive-snap-unknown-code-hashes.txt](sec5-3140e224-hive-snap-unknown-code-hashes.txt) → 3140e224 (test)
- Unavailable SNAP account roots → [sec5-c29749c1-snap-unavailable-account-roots.txt](sec5-c29749c1-snap-unavailable-account-roots.txt) → c29749c1 (test)
- Storage-range boundaries → [sec5-3d4cac04-snap-storage-range-boundaries.txt](sec5-3d4cac04-snap-storage-range-boundaries.txt) → 3d4cac04 (test)
- Retained SNAP account root → [sec5-922f8413-snap-retained-account-root.txt](sec5-922f8413-snap-retained-account-root.txt) → 922f8413 (test)
- Storage root presented as a state root → [sec5-ab52d10d-snap-storage-root-as-state-root.txt](sec5-ab52d10d-snap-storage-root-as-state-root.txt) → ab52d10d (test)
- Inverted account ranges → [sec5-92acbc20-snap-inverted-account-ranges.txt](sec5-92acbc20-snap-inverted-account-ranges.txt) → 92acbc20 (test)
- Account soft limits → [sec5-99b9bad3-snap-account-soft-limits.txt](sec5-99b9bad3-snap-account-soft-limits.txt) → 99b9bad3 (test)
- Account range boundaries → [sec5-981112ac-snap-account-range-boundaries.txt](sec5-981112ac-snap-account-range-boundaries.txt) → 981112ac (test)
- Cumulative account byte targets → [sec5-306e5f4f-snap-account-byte-targets.txt](sec5-306e5f4f-snap-account-byte-targets.txt) → 306e5f4f (test)
- Inbound RLPx session failures on Hoodi: whose they are; admission defects fixed → [sec5-rlpx-inbound-auth.txt](sec5-rlpx-inbound-auth.txt) → 6fa17eb7, 479c1e5b

### Section 5: public RPC and eth_simulateV1

- eth_config fork ID missed the Merge netsplit block → [sec5-63408ce2-rpc-config-fork-id.txt](sec5-63408ce2-rpc-config-fork-id.txt) → 63408ce2
- Gas-oracle recommendations were not persisted → [sec5-67a4eb42-gas-oracle-state.txt](sec5-67a4eb42-gas-oracle-state.txt) → 67a4eb42
- eth_simulateV1 call-count limits → [sec5-8a0223e8-simulate-call-limits.txt](sec5-8a0223e8-simulate-call-limits.txt) → 1e2aa178 (committed with the record; 8a0223e8 is the go-ethereum comparator)
- Sender nonces → [sec5-99329e9b-simulate-nonce.txt](sec5-99329e9b-simulate-nonce.txt) → abf3da5d (committed with the record; base 99329e9b)
- Insufficient-funds admission → [sec5-abf3da5d-simulate-funds.txt](sec5-abf3da5d-simulate-funds.txt) → f8894386 (committed with the record; base abf3da5d)
- Gas-fee settlement → [sec5-f8894386-simulate-fees.txt](sec5-f8894386-simulate-fees.txt) → aeb31626 (committed with the record; base f8894386)
- Missing `error` object on reverted calls → [sec5-936aab2b-simulate-revert-error.txt](sec5-936aab2b-simulate-revert-error.txt) → 936aab2b
- EVM logs dropped on the simulate path → [sec5-simulate-evm-logs.txt](sec5-simulate-evm-logs.txt) → — (the record names only its base, 1e2aa178; git shows it was added by fa6d2dc3 "feat(rpc): thread EVM logs through eth_simulateV1")
- Empty synthetic block identity → [sec5-f3601eab-simulate-empty-block-identity.txt](sec5-f3601eab-simulate-empty-block-identity.txt) → f3601eab
- Non-empty hash-only block identity → [sec5-2c43b9dc-simulate-nonempty-identity.txt](sec5-2c43b9dc-simulate-nonempty-identity.txt) → 2c43b9dc
- Log metadata on simulated logs → [sec5-3664def7-simulate-log-metadata.txt](sec5-3664def7-simulate-log-metadata.txt) → 3664def7
- Empty simulation input → [sec5-7144b014-simulate-empty-input.txt](sec5-7144b014-simulate-empty-input.txt) → 7144b014
- returnFullTransactions ignored → [sec5-87fe39c7-simulate-full-transactions.txt](sec5-87fe39c7-simulate-full-transactions.txt) → 87fe39c7
- Header overrides → [sec5-de66bf7b-simulate-header-overrides.txt](sec5-de66bf7b-simulate-header-overrides.txt) → de66bf7b
- Transfer traces differed from geth → [sec5-abfe6da3-simulate-transfer-traces.txt](sec5-abfe6da3-simulate-transfer-traces.txt) → abfe6da3

### Section 5: operations on the Hoodi host

- Lighthouse recovery: the existing beacon container restarted in place → [sec5-2b84a86a-lighthouse-recovery.txt](sec5-2b84a86a-lighthouse-recovery.txt) → — (operational)
- An obsolete EELS consume-engine run was stopped; its later cases lost a single client revision → [sec5-6b972561-obsolete-eels-stop.txt](sec5-6b972561-obsolete-eels-stop.txt) → — (operational)
- Control-plane broker debt: live-gate logs/complete, hive-gate upload, fleet status → [sec5-gate-tooling.txt](sec5-gate-tooling.txt) → 68fbc985, c6b61cd8, 77c1f2e1, e81b5ba8

### Section 6: payload building and txpool

- Payload building was unbounded and could miss the proposer window → [sec5-payload-building.txt](sec5-payload-building.txt) → f35bc82c
- Non-atomic pooled-blob admission; no EIP-7702 authority index → [sec5-txpool-section6.txt](sec5-txpool-section6.txt) → bd7906c3

### Section 7: public RPC hardening

- Public reads under the store guard, no response work budgets, WebSocket limits unenforced → [sec5-rpc-hardening.txt](sec5-rpc-hardening.txt) → 6043c88b, 75a07323, 6d0dbad7, 0ec0eb5c

### Section 10: operations, observability and packaging

- SIGKILL recovery, SIGTERM deadlines for build and reorg, operator metrics, runbook → [sec5-ops-recovery.txt](sec5-ops-recovery.txt) → a560644b, ef6f5e94, 81439281
- Health endpoints and operator metrics → [sec10-observability.txt](sec10-observability.txt) → 2f29e23c, 096a3fc0, b22aa1e3
- Pinned inputs, SBOM, provenance and a signed runtime release → [sec10-packaging.txt](sec10-packaging.txt) → 7a2ea963, 85e453e2, ed61958d, 38b1abbe, 709616fc
