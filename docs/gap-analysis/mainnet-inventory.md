# Mainnet (pre-Merge) path inventory

Readiness plan section 9 ("Complete the mainnet path after Hoodi readiness")
asks for cumulative total difficulty, an exact terminal PoW block / first PoS
child rule, correct pre-EIP-158 account creation, pre-Berlin/EIP-150 gas
gating, ommer execution and rewards, the DAO transition and historical receipt
behaviour, checked against Frontier-through-Merge official fixtures and Hive
transition tests. This document is the inventory for the first slice
(`mainnet-merge-transition`, 2026-09-29): which pre-Merge rules the tree has,
where, the go-ethereum v1.17.6 function each follows, the fixtures that cover
it, and the measured pass counts before and after the slice. The second slice
(`premerge-parity`, 2026-09-30, base `7cef5a67`) closed the three signer and
code-size gaps, read the Spurious Dragon rules cumulatively, put the head's
total difficulty into eth/68 Status, created the DAO drain's absent accounts,
and checked ommers and the DAO transition against legacy ethereum/tests
fixtures.

Mainnet stays explicitly experimental (PROJECT.md). Nothing here changes a
configuration whose Merge is fixed (Hoodi's netsplit block 0, a TTD of zero or
passed, no TTD at all) or any rule from EIP-158 (Spurious Dragon) on; the
current-fork gates are byte-identical (`docs/evidence/gates.md`).

## Pinned inputs

| Input | Identity |
| --- | --- |
| Legacy corpus | EEST `v5.4.0`, `fixtures_stable.tar.gz`, SHA-256 `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909` (`legacy-v5.4.0` in `scripts/fetch-eest-fixtures.sh`, re-hashed before extraction) |
| Stable corpus | `tests@v20.0.2`, `fixtures.tar.gz`, SHA-256 `1280540950a4c3470a421416b6f35458a9b635827265c29e5aef1ae839ae1788` |
| Reference client | go-ethereum 1.17.6-unstable `38271784c2b31926563806da9a2e023b88f5e7a8` (`references/go-ethereum`) |
| Legacy ethereum/tests | tag `v6.0.0-beta.3`, commit `725dbc73a54649e22a00330bd0f4d6699a5060e5`: `BlockchainTests/bcUncleTest/{oneUncle,twoUncle}.json` and the four `BlockchainTests/TransitionTests/bcHomesteadToDao/*.json`, vendored verbatim under `tests/fixtures/ethereum-tests-v6.0.0-beta.3/` (each SHA-256 is checked by `tests/fixture-premerge-legacy-tests.lisp` before it is read) |
| Base revision | `3c0cfeab`; second slice `7cef5a67` |
| Measured revisions | `b6c095a1` (total difficulty), `6e405bf9` (pre-Spurious-Dragon rules), `7ad834c7` (runner walks both corpora), `d06f4002` and `5168e4e2` (signers, EIP-170, cumulative rules, Status, DAO accounts), `820956d7` (the CALL-level stack budget the base had overrun; gate row in `docs/evidence/gates.md`), `b60833fe` and `e8511de7` (RPC senders under the block's signer, cumulative London, Shanghai and envelope-type predicates; gate row e8511de7) |

## How to run the burn-down

`OPTIONAL-LEGACY-EEST-PRE-MERGE-BLOCKCHAIN-BURN-DOWN`
(`tests/fixture-runner-pre-merge.lisp`, integration layer) replays every
Frontier-through-Paris case of either corpus layout the way go-ethereum
v1.17.6 `tests/block_test_util.go` `BlockTest.Run` does: geth's
`tests/init.go` `Forks` configuration for the network (TTD `MaxInt64` when it
names none; `TangerineWhistle` and `SpuriousDragon` are its aliases for
`EIP150` and `EIP158`), no seal check (`NoProof`, geth's `ethash.NewFaker`),
each block admitted through `import-block-candidate` and made the head, a
block with `expectException` refused with a verdict, then `lastblockhash` and
`postState`. It prints one `PRE-MERGE-EEST` line per directory with a pass
count per network, the first failures, and a total.

```sh
scripts/dev.sh eest-fixtures legacy-v5.4.0 .eest-fixtures-legacy
ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=$PWD/.eest-fixtures-legacy/v5.4.0 \
ETHEREUM_LISP_PRE_MERGE_EEST_REQUIRED=frontier/precompiles,frontier/create,frontier/examples,frontier/opcodes,frontier/touch \
  cl-workbench validation run cold-integration \
  --match OPTIONAL-LEGACY-EEST-PRE-MERGE-BLOCKCHAIN-BURN-DOWN > pre-merge.log 2>&1
echo "EXIT=$?"; grep -E '^PRE-MERGE-EEST (blockchain|total)|^(not )?ok' pre-merge.log

# The stable corpus's pre-Merge network trees (about four minutes):
ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=$PWD/.eest-fixtures-sec5-REV/tests-v20.0.2 \
  cl-workbench validation run cold-integration \
  --match OPTIONAL-LEGACY-EEST-PRE-MERGE-BLOCKCHAIN-BURN-DOWN > pre-merge-v20.log 2>&1
```

`ETHEREUM_LISP_PRE_MERGE_EEST_DIRECTORIES` (`fork/dir` or
`for_network/tree/dir`) and `ETHEREUM_LISP_PRE_MERGE_EEST_NETWORKS` narrow the
walk; `ETHEREUM_LISP_PRE_MERGE_EEST_REQUIRED` fails the test unless each named
directory has cases and no failure. Files over 48 MB are counted
(`oversizeFilesSkipped`), not parsed. Without a root holding either layout the
test is a counted skip.

## Measured counts

Cold runs; cases passed / cases.

### Legacy v5.4.0 (26 directories, Frontier through Paris)

| Directory | `3c0cfeab` (40 MB bound) | `b6c095a1` (48 MB bound) | `6e405bf9` |
| --- | --- | --- | --- |
| frontier/precompiles | 399 / 515 | 399 / 515 | 515 / 515 |
| frontier/create | 74 / 81 | 74 / 81 | 81 / 81 |
| frontier/opcodes | 1498 / 1500 (1 file skipped) | 3050 / 3052 | 3052 / 3052 |
| frontier/touch | 4 / 6 | 4 / 6 | 6 / 6 |
| frontier/examples | 1 / 2 | 1 / 2 | 2 / 2 |
| the other 21 directories | 1810 / 1810 | 1810 / 1810 | 1810 / 1810 |
| **Total** | 3786 / 3914 | 5338 / 5466 | 5466 / 5466 |

Per network at `6e405bf9`: Frontier 380, Homestead 390, Byzantium 469,
ConstantinopleFix 481, Istanbul 626, Berlin 1015, London 1019, Paris 1086
(all passing; Frontier 314 and Homestead 328 at `b6c095a1`). Two files over
48 MB stay unmeasured: `berlin/eip2930_access_list/test_tx_intrinsic_gas.json`
(51 MB) and `frontier/scenarios/test_scenarios.json` (90 MB, the whole
directory). v5.4.0 has no TTD, DAO or `...At5` transition network, and no
`TangerineWhistle` or `SpuriousDragon` network.

### tests@v20.0.2 network trees (298 directories)

`blockchain_tests/for_<network>/<tree>/<directory>/`, `ported_static`
(the legacy GeneralStateTests filled as blockchain tests) included; no file
exceeds 48 MB.

| Network | `3c0cfeab` | `6e405bf9` |
| --- | --- | --- |
| Frontier | 477 / 626 | 626 / 626 |
| Homestead | 530 / 641 | 641 / 641 |
| TangerineWhistle | 648 / 842 | 842 / 842 |
| SpuriousDragon | 851 / 851 | 851 / 851 |
| Byzantium | 2288 / 2288 | 2288 / 2288 |
| ConstantinopleFix | 2422 / 2422 | 2422 / 2422 |
| Istanbul | 2566 / 2566 | 2566 / 2566 |
| Berlin | 3482 / 3482 | 3482 / 3482 |
| London | 3760 / 3760 | 3760 / 3760 |
| Paris | 3782 / 3782 | 3782 / 3782 |
| **Total** | 20806 / 21260 | 21260 / 21260 |

The 454 failures at the base were all pre-Spurious-Dragon, in
`frontier/precompiles` (201), `frontier/scenarios` (102),
`tangerine_whistle/eip150_operation_gas_costs` (80),
`ported_static/stStackTests` (32), `frontier/create` (16),
`frontier/opcodes` (9), `frontier/touch` (6), `eip2681_limit_account_nonce`
(4), `ported_static/stCallCodes` (3) and `frontier/examples` (1). The 454
cleared with the legacy directories' fixes; none needed a rule of its own.

### Legacy ethereum/tests v6.0.0-beta.3 (ommers and the DAO transition)

Neither pinned corpus has a block with an ommer or a `HomesteadToDaoAt5`
network, so six files of the last ethereum/tests release that filled those
networks are vendored (see Pinned inputs) and replayed by
`PREMERGE-LEGACY-OMMER-AND-DAO-FIXTURES-REPLAY` through the same
`pre-merge-eest-run-case` as the burn-down, which now also reads the legacy
`expectExceptionALL` key:

```sh
cl-workbench validation run cold-integration --match PREMERGE-LEGACY
```

| File | Networks | `7cef5a67` | `5168e4e2` and `820956d7` |
| --- | --- | --- | --- |
| bcUncleTest/oneUncle | Frontier, Homestead, EIP150, EIP158, Byzantium, Constantinople | 6 / 6 | 6 / 6 |
| bcUncleTest/twoUncle | the same six | 6 / 6 | 6 / 6 |
| bcHomesteadToDao/DaoTransactions (24 blocks, a fork across block 5) | HomesteadToDaoAt5 | 1 / 1 | 1 / 1 |
| bcHomesteadToDao/DaoTransactions_EmptyTransactionAndForkBlocksAhead | HomesteadToDaoAt5 | 1 / 1 | 1 / 1 |
| bcHomesteadToDao/DaoTransactions_UncleExtradata | HomesteadToDaoAt5 | 1 / 1 | 1 / 1 |
| bcHomesteadToDao/DaoTransactions_XBlockm1 | HomesteadToDaoAt5 | 1 / 1 | 1 / 1 |

Every file passed at the base as well: the rewards and the drain were already
right for these inputs (all 116 drain accounts are funded there, so the absent
account rule below is not exercised by them). Mutation controls: an ommer
reward of `(U + 9 - N) R / 8` fails all six oneUncle cases, and a drain that
moves nothing fails DaoTransactions at block 5 ("Gas used mismatch").

## Inventory of pre-Merge rules

Status: **exact** means implemented and exercised by a passing fixture
directory above; **implemented** means present but not exercised by a pinned
fixture; **gap** means missing or looser than geth.

| Rule | Status | Our code | go-ethereum v1.17.6 | Fixture coverage |
| --- | --- | --- | --- | --- |
| Total difficulty per block | exact (unit) | `src/storage/chain-store/service/memory-blocks.lisp` `memory-chain-store-record-total-difficulty`; `memory.lisp` `chain-store-block-total-difficulty`; `:total-difficulty` record (`src/foundation/database/chain-keys.lisp`, export `export/blocks.lisp`, `export/orchestrator.lisp`, direct read `direct-store.lisp`, import `import/core.lisp`) | none: v1.17.6 no longer keeps it (`core/rawdb/schema.go` `headerTDSuffix` "deprecated") | `tests/core-merge-transition-tests.lisp` (`TOTAL-DIFFICULTY-SURVIVES-EXPORT-REOPEN-AND-DIRECT-READS`); every pre-Paris legacy case validates through it |
| Terminal PoW block / first PoS child (EIP-3675) | exact (unit) | `src/protocol/chain-config/forks.lisp` `chain-config-merge-by-total-difficulty-p`; `src/protocol/consensus/block-validation/forks.lisp` `block-header-merge-rules-p`, `block-header-post-merge-block-p` | `consensus/beacon/consensus.go` `VerifyHeader` (difficulty sign and no revert only; the TD rule is EIP-3675's) | `MERGE-TRANSITION-*`, `PUBLIC-PRESET-POST-MERGE-HEADERS-VALIDATE-AS-PROOF-OF-STAKE`, `POST-MERGE-AUTHORITY-READS-THE-BLOCK-UNDER-A-TTD-CONFIGURATION`; no pinned corpus has a TTD transition network |
| Ethash difficulty (Frontier, Homestead, Byzantium, the bomb delays through Gray Glacier) | exact below the bombs | `src/protocol/consensus/block-validation/pow.lisp` `expected-ethash-difficulty` | `consensus/ethash/consensus.go` `CalcDifficulty`, `makeDifficultyCalculator`; `difficulty.go` | every pre-Paris block of both corpora; the bomb terms at mainnet heights only by unit tests |
| Ethash seal | implemented (light, slow) | `pow.lisp` `verify-ethash-seal-light` | geth v1.17.6 verifies no seal (`ethash.NewFaker` only) | `ETHASH-LIGHT-HASHIMOTO-MATCHES-OFFICIAL-VECTOR` (ethereum/tests `c67e485f`); the corpora are `NoProof` |
| Ommers: count, depth, ancestry, duplicates, header validity | exact | `src/protocol/consensus/block-validation/body.lisp` `validate-block-ommers-against-config` | `consensus/ethash/consensus.go` `VerifyUncles` | legacy v6.0.0-beta.3 `bcUncleTest/oneUncle`, `twoUncle` (12 cases, six networks) and `DaoTransactions_UncleExtradata`; unit `PROOF-OF-WORK-OMMER-VALIDATION-REQUIRES-RECENT-ANCESTRY` and the synthetic chain of `PREMERGE-OMMER-REWARDS-FOLLOW-ACCUMULATE-REWARDS`; neither pinned corpus has an ommer |
| Block rewards (5 / 3 / 2 ETH) | exact | `src/runtime/execution/rewards.lisp` `apply-block-rewards-for-header` | `consensus/ethash/consensus.go` `accumulateRewards` | every pre-Paris block of both corpora |
| Ommer rewards | exact | same | same | the same legacy files; `PREMERGE-OMMER-REWARDS-FOLLOW-ACCUMULATE-REWARDS` imports a one-ommer and a two-ommer block (ommers at depth 1 and 2) under Frontier, Byzantium and Constantinople and checks every beneficiary against geth's formula |
| DAO fork extra data and drain | exact since `d06f4002` | `src/protocol/consensus/block-validation/forks.lisp` `validate-block-dao-extra-data`; `src/runtime/execution/dao.lisp` `apply-dao-hard-fork` | `consensus/misc/dao.go` `VerifyDAOHeaderExtraData`, `ApplyDAOHardFork` (with `core/state/statedb.go` `getOrNewStateObject`) | legacy v6.0.0-beta.3 `bcHomesteadToDao` (four files, `HomesteadToDaoAt5`); `PREMERGE-DAO-FORK-BLOCK-DRAINS-INTO-THE-REFUND-CONTRACT`. Before `d06f4002` an absent refund contract or drain account was not created, where geth creates it and, before EIP-158, keeps it empty in the state root |
| Pre-Byzantium receipts (intermediate state root) | exact | `src/protocol/receipts/receipts.lisp` (post-state); RPC `root` in `src/api/public/transactions/receipts.lisp` | `core/state_processor.go` `MakeReceipt` | every Frontier-through-SpuriousDragon case (`frontier/touch` pins a zero-fee coinbase in it) |
| Contract creation intrinsic gas (53000 from Homestead) | exact since `6e405bf9` | `src/runtime/execution/gas.lisp` `transaction-intrinsic-gas`, `transaction-homestead-active-p` | `core/state_transition.go` `IntrinsicGas` | `frontier/examples`, `frontier/opcodes` `double_kill` |
| Frontier code deposit out of gas keeps the contract | exact since `6e405bf9` | `src/runtime/evm/interpreter/create.lisp` `execute-contract-creation`; `src/runtime/execution/apply-contract.lisp` | `core/vm/evm.go` `create` (`ErrCodeStoreOutOfGas` before Homestead), `opCreate` | `frontier/create` `test_create_deposit_oog` |
| New contract nonce 0 before EIP-158 | exact since `6e405bf9` (CREATE opcode; the transaction path had it) | `create.lisp`; `apply-contract.lisp` | `core/vm/evm.go` `create` (`SetNonce(address, 1)` under `IsEIP158`) | `frontier/create` `test_create_one_byte` |
| CALL new-account gas by existence before EIP-158 | exact since `6e405bf9` | `src/runtime/evm/state.lisp` `call-value-extra-gas` | `core/vm/gas_table.go` `gasCallIntrinsic` | `frontier/precompiles` (116 legacy cases) |
| SELFDESTRUCT new-account gas by existence (EIP-150 to EIP-158) | exact since `6e405bf9` | `state.lisp` `selfdestruct-extra-gas` | `core/vm/gas_table.go` `gasSelfdestruct` | v20 `tangerine_whistle/eip150_operation_gas_costs` |
| Absent callee, beneficiary and coinbase become empty accounts before EIP-158 | exact since `6e405bf9` | `call.lisp` `execute-message-call-child` (`create-callee-p`); `state.lisp` `selfdestruct-account` (`create-beneficiary-p`); `src/runtime/execution/apply-message.lisp` `create-message-recipient-before-eip158`; `src/runtime/execution/accounting.lisp` `pay-priority-fee` | `core/vm/evm.go` `Call`; `core/vm/instructions.go` `opSelfdestruct` (`AddBalance`); `core/state_transition.go` (coinbase `AddBalance`) | `frontier/precompiles`, `frontier/create` `suicide_store`, `frontier/opcodes` `double_kill`, `frontier/touch` |
| EIP-161 state clearing (touched empty accounts) | exact | `src/runtime/state/db.lisp` `state-db-touch-account` and the transaction finalization | `core/state/statedb.go` `Finalise(deleteEmptyObjects)` | SpuriousDragon onward, both corpora |
| EIP-150 costs and 63/64 | exact | `src/runtime/evm/context.lisp` `context-eip150-p`; `call.lisp` `child-call-gas-limit` | `core/vm/gas_table.go`, `operations_acl.go`, `callGas` | v20 `eip150_operation_gas_costs` (842 TangerineWhistle cases) |
| Byzantium through London opcodes, refunds, EIP-1559, EIP-2929/2930 | exact | per-opcode fork gates in `src/runtime/evm/` | `core/vm/jump_table.go` and friends | all legacy and v20 Byzantium-through-Paris cases |
| Frontier signatures with a high s | implemented since `d06f4002`; public RPC and tracing since `b60833fe` | `src/protocol/transactions/transactions.lisp` `transaction-sender-for-rules`, called by execution (`src/runtime/execution/signatures.lisp`), candidate admission (`engine-new-payload-require-transaction-senders`) and, with the block's rules (`eth-rpc-signer-rules`), every public view of a stored transaction: objects, raw, receipts, the gas price oracle and the call tracer | `core/types/transaction_signing.go` `MakeSigner`, `FrontierSigner.Sender` (`recoverPlain` with homestead false); `internal/ethapi/api.go` `newRPCTransaction`, `GetBlockReceipts`; `eth/tracers/api.go`; `eth/gasprice` `getBlockValues` | unit `PREMERGE-FRONTIER-SIGNER-ACCEPTS-A-HIGH-S-SIGNATURE` (imported under Frontier, refused under Homestead) and `PREMERGE-RPC-RECOVERS-A-FRONTIER-HIGH-S-SENDER-WITH-THE-BLOCK-SIGNER` (seven RPC lookups, refused under a Homestead configuration); no fixture |
| EIP-155 protected signatures before activation | implemented since `d06f4002` | same | `HomesteadSigner.Sender` / `FrontierSigner.Sender`: `recoverPlain` accepts V 27 and 28 only | unit `PREMERGE-PROTECTED-SIGNATURE-IS-REFUSED-BEFORE-EIP155` (the same block imports with EIP-155 and is refused without it); no fixture |
| EIP-170 code size before EIP-158 | implemented since `d06f4002` | `src/protocol/chain-config/rules.lisp` `chain-rules-code-size-limited-p`, read by `src/runtime/evm/create.lisp` `invalid-created-runtime-code-p` and `src/runtime/execution/gas.lisp` `invalid-contract-runtime-code-p` | `core/vm/common.go` `CheckMaxCodeSize` (nothing before `IsEIP158`), `core/vm/evm.go` `initNewContract` | unit `PREMERGE-EIP170-CODE-SIZE-LIMIT-STARTS-AT-SPURIOUS-DRAGON` (24,577 bytes by a creation transaction and by CREATE); no fixture |
| Spurious Dragon rules under a single-flag rule set | implemented since `d06f4002` | `chain-rules-fork-level` moved to `src/protocol/chain-config/rules.lisp`; `chain-rules-eip158-active-p` for the created-contract nonce (`apply-contract.lisp`), the EIP-161 finalization (`apply-message.lisp`, `call-simulation.lisp`) and EXP's EIP-160 price (`src/runtime/evm/opcodes.lisp`) | geth builds `params.Rules` cumulatively (`ChainConfig.Rules`) | unit `PREMERGE-SINGLE-FLAG-RULES-IMPLY-SPURIOUS-DRAGON`; production rules (`chain-config-rules`) were always cumulative, so no chain was affected |
| London, Shanghai and envelope types under a single-flag rule set | implemented since `e8511de7` | `src/protocol/chain-config/rules.lisp` `chain-rules-london-active-p` (EIP-3541 prefix) and `chain-rules-shanghai-active-p` (EIP-3860 initcode); `src/protocol/transactions/transactions.lisp` `chain-rules-signer-fork-level` (envelope types); `src/protocol/chain-config/forks.lisp` `chain-rules-expanded-blob-schedule-p` (Prague or later, for a rule set without a schedule) | `params/config.go` `IsLondon`, `IsShanghai` (both mandatory in `CheckConfigForkOrder`); `MakeSigner`'s latest-first switch; `consensus/misc/eip4844` `latestBlobConfig` | unit `PREMERGE-FORK-PREDICATES-ARE-CUMULATIVE-OVER-THE-MAINNET-ORDER` (single flag, cumulative set and `chain-config-rules` agree fork by fork); no public network's rules change |
| eth/68 Status total difficulty | the head's total where total difficulty decides the Merge, since `5168e4e2` | `src/app/cli/devnet/peer-sync.lisp` `devnet-peer-status-total-difficulty`; the head's total read with the Status view (`peer-table.lisp` `devnet-node-read-status-head`) | go-ethereum v1.14.13 `eth/handler.go` `runEthPeer` (`GetTd` of the current header); v1.15.0 through v1.16.x send 0; v1.17.6 speaks no eth/68 | unit `PREMERGE-ETH-STATUS-ADVERTISES-THE-HEAD-TOTAL-DIFFICULTY`; a configuration that fixes the Merge (Hoodi), or a store without totals, still advertises the TTD |

## The Merge transition

A configuration fixes the Merge where `chain-config-post-merge-p` says so: at
or after a netsplit block, or with a TTD of zero, none, or declared passed.
Elsewhere `chain-config-merge-by-total-difficulty-p` leaves it to the chain,
and `block-header-merge-rules-p` applies EIP-3675 with the parent's total
difficulty, which candidate admission and Engine newPayload read from the
chain store:

- parent total below the TTD: the child is proof-of-work; a zero difficulty is
  refused ("Proof-of-stake header before the terminal total difficulty");
- at or above: the parent must be the terminal block (a proof-of-stake block,
  or a proof-of-work block whose own parent was still below), and the child is
  held to the proof-of-stake field rules, so a positive difficulty is refused.

Without a total (a chain entered at a snap or checkpoint pivot) a
proof-of-stake parent makes the child proof-of-stake, go-ethereum v1.17.6's
`VerifyHeader` rule; a zero-difficulty child of a proof-of-work parent is
refused, since its terminal block cannot be verified. Before this slice the
configuration alone decided, so every mainnet proof-of-stake header, and
Sepolia's below its netsplit block, was held to the Ethash rules and refused;
the record is `docs/evidence/sec9-merge-by-total-difficulty.txt`.

The chain store records a block's total when it is put (genesis: its own
difficulty; otherwise the parent's plus its own) and every export writes it as
an immutable `:total-difficulty` record (prefix `0x1f`, the RLP of the
integer). The direct RocksDB provider point-reads it; a full import restores
the records and derives any missing total in height order. A snap-synced node
has no totals, and that is the intended mainnet join.

## Mainnet join

The plan's mainnet path is the same verified snap/checkpoint bootstrap Hoodi
uses, with exact historical replay kept as a validation mode; operators do not
replay proof-of-work history to join. This slice does not add or change
proof-of-work seal verification: the in-tree light Ethash verifier predates it
and is correct against the official vector but costs an epoch cache per
30,000 blocks, which is why it is not a join path.

## Not covered

- No Hive run: neither the pinned Engine simulators' TTD transition cases nor
  any `ethereum/eels` consume run against the pre-Merge corpora.
- No block in either pinned corpus carries an ommer; ommers and the DAO
  transition are checked against six vendored legacy ethereum/tests files
  (v6.0.0-beta.3, networks up to Constantinople), not against EEST.
- No fixture exercises the TTD transition itself, the other `...At5` fork
  transitions, or Ethash seals; geth's `tests/init.go` names the
  `ArrowGlacierToParisAtDiffC0000` network, and neither pinned corpus fills it.
- The DAO rule that creates absent accounts rests on the synthetic test: every
  vendored DAO fixture funds all 116 drain accounts. A DAO block at or after
  EIP-158 (no public network has one) is not tested.
- The Frontier high-s and pre-EIP-155 signer rules rest on synthetic tests.
  Pooled transactions are still rendered with the latest signer, the one the
  pool admits them with; geth renders them with the head's and lists one it
  cannot recover with a zero `from`. The two differ only under a
  pre-EIP-155 head.
- eth/68 Status sends the head's total only when the store has it; a node
  entered at a pivot advertises the TTD, as geth v1.14 could not (it always
  had totals) and geth v1.15 and later do not try (they send 0).
- No historical-range comparison with a reference client and no mainnet live
  run. The mainnet preset's total-difficulty rule is pinned by unit tests on a
  synthetic chain and by header pairs at mainnet and Sepolia heights.
- Two legacy files over 48 MB are not parsed.
- ethereum/tests `BlockchainTests` and `DifficultyTests` are not pinned here.
