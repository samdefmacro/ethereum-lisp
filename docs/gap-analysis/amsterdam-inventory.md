# Amsterdam feature-fixture inventory

Readiness plan section 8 ("Rebase Amsterdam on the current feature fixtures")
asks for the complete `tests-glamsterdam-devnet@v7.2.1` inventory to be
implemented and tested before `amsterdam-execution-available-p` is reopened.
This document is that inventory: every EIP directory the corpus names, its
fixture counts, what this tree implements, where, the reference it follows,
and the measured pass counts before and after the first burn-down branch
(`amsterdam-inventory`, 2026-09-29) and the second (`amsterdam-slice-2`,
2026-09-29), after which every case of both executed families passes.

Amsterdam stays gated. `amsterdam-execution-available-p`
(`src/runtime/evm/base.lisp`) still returns NIL, so the Engine router refuses
`engine_newPayloadV5`, `engine_getPayloadV6` and `engine_forkchoiceUpdatedV4`.
The numbers below come from a test runner that calls the newPayload handler
below that router; they measure execution, not an Engine capability.

## Pinned inputs

| Input | Identity |
| --- | --- |
| Corpus | `tests-glamsterdam-devnet@v7.2.1`, commit `882909a2c88751a31fa99a65176563a16c527893` |
| Archive | `fixtures_glamsterdam-devnet.tar.gz`, SHA-256 `02e3eca2ede5b424f4dbf2461caf592e6b43b56d55bbd64213dd01f63af9a583` (re-hashed after the fetch, 2026-09-29) |
| Reference client | go-ethereum 1.17.6-unstable `38271784c2b31926563806da9a2e023b88f5e7a8` (`references/go-ethereum`) |
| Baseline revision | `1a7b9059` plus the runner (`024bde16`), no execution change |
| Measured revision, first branch | `c072361d7a5a86fa7b811f240b532238d120c0a8` (execution identical to `ac7d692d`) |
| Measured revision, second branch | `a69c6621b6e79bfa3d4940682e2f9beaefed250c` (`amsterdam-slice-2` on `c677bdf0`) |

The corpus was already a pinned baseline (`amsterdam-v7.2.1` in
`scripts/fetch-eest-fixtures.sh` and `scripts/dev.sh eest-fixtures`), so the
fetch path needed no change:

```sh
scripts/dev.sh eest-fixtures amsterdam-v7.2.1 .eest-fixtures-amsterdam
```

The fetch container verifies the pinned digest before extracting to
`.eest-fixtures-amsterdam/tests-glamsterdam-devnet-v7.2.1/`.

## How to run the burn-down

`OPTIONAL-AMSTERDAM-EEST-FEATURE-BURN-DOWN` (`tests/fixture-runner-amsterdam.lisp`,
integration layer) walks `<family>/for_amsterdam/amsterdam/eipNNNN_*/` one
fixture file at a time, scores every case instead of stopping at the first
failure, and prints one line per family and EIP directory with its first three
failure messages:

```sh
ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=$PWD/.eest-fixtures-amsterdam/tests-glamsterdam-devnet-v7.2.1 \
  cl-workbench validation run cold-integration \
  --match OPTIONAL-AMSTERDAM-EEST-FEATURE-BURN-DOWN > amsterdam.log 2>&1
echo "EXIT=$?"; grep -E '^AMSTERDAM-EEST [sb]|^(not )?ok' amsterdam.log
```

```text
AMSTERDAM-EEST state_tests eip7976_increase_calldata_floor_cost: cases=525 passed=525 failed=0
```

- **state_tests** run through `assert-eest-state-test-post-entry`, the
  assertion the current-fork state gate uses, under Amsterdam chain rules
  (BPO1/BPO2 on, BPO2's blob schedule, the environment's `slotNumber`).
- **blockchain_tests_engine** replay every `engineNewPayloads` entry in order
  through `engine-rpc-handle-new-payload`, then check `lastblockhash` and
  `postState`. A VALID entry must answer VALID with its own block hash, an
  entry with `validationError` must answer INVALID, and one with `errorCode`
  must answer that JSON-RPC code.
- **blockchain_tests_engine@BPO2ToAmsterdamAtTime15k** is the same family on
  the transition network, so the activation block itself is measured.
- `blockchain_tests` holds the same test ids in block-RLP form and is not run a
  second time.

Selectors (all optional, comma-separated, forwarded by the cold broker):
`ETHEREUM_LISP_AMSTERDAM_EEST_DIRECTORIES` runs only the named directories;
`ETHEREUM_LISP_AMSTERDAM_EEST_REQUIRED` fails the test unless each named
directory passed in full in every family; `ETHEREUM_LISP_AMSTERDAM_EEST_TREES`
walks other feature trees (`all` is every tree; a directory outside
`amsterdam/` is named `TREE/DIRECTORY`). Without the root, or with a root that
has no `for_amsterdam` tree (the stable `tests@v20.0.2` corpus), the test is a
counted skip. Files over 40 MB are counted as `oversizeFilesSkipped`, not
parsed.

Every directory passes since `a69c6621`, so the regression gate names all
fourteen and walks every re-filled tree as well (the burn-down still prints
one line per directory; a failure outside the required set shows there):

```sh
ETHEREUM_LISP_AMSTERDAM_EEST_TREES=all \
ETHEREUM_LISP_AMSTERDAM_EEST_REQUIRED=eip2780_reduce_intrinsic_tx_gas,eip7708_eth_transfer_logs,eip7778_block_gas_accounting_without_refunds,eip7843_slotnum,eip7928_block_level_access_lists,eip7954_increase_max_contract_size,eip7976_increase_calldata_floor_cost,eip7981_increase_access_list_cost,eip7997_deterministic_factory_predeploy,eip8024_dupn_swapn_exchange,eip8037_state_creation_gas_cost_increase,eip8038_state_access_gas_cost_increase,eip8246_selfdestruct_no_burn,eip8282_builder_execution_requests \
ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=... \
  cl-workbench validation run cold-integration --match OPTIONAL-AMSTERDAM-EEST-FEATURE-BURN-DOWN
```

## Inventory

Counts are test cases (top-level fixture keys) under
`<family>/for_amsterdam/amsterdam/`; RLP is `blockchain_tests`. Pass counts are
state and engine at the baseline, after the first branch (`c072361d`) and after
the second (`a69c6621`); the transition network is listed separately below.

| EIP | Directory | State / RLP / Engine cases | State passed (base -> c072361d -> a69c6621) | Engine passed (base -> c072361d -> a69c6621) | Status |
| --- | --- | --- | --- | --- | --- |
| 2780 Reduce intrinsic transaction gas | `eip2780_reduce_intrinsic_tx_gas` | 185 / 189 / 189 | 54 -> 176 -> 185 | 17 -> 175 -> 189 | passes |
| 7708 ETH transfers emit a log | `eip7708_eth_transfer_logs` | 69 / 72 / 72 | 40 -> 67 -> 69 | 0 -> 69 -> 72 | passes |
| 7778 Block gas accounting without refunds | `eip7778_block_gas_accounting_without_refunds` | 0 / 26 / 26 | - | 8 -> 26 -> 26 | passes |
| 7843 SLOTNUM | `eip7843_slotnum` | 8 / 9 / 9 | 0 -> 8 -> 8 | 0 -> 9 -> 9 | passes |
| 7928 Block-level access lists | `eip7928_block_level_access_lists` | 14 / 1004 / 1007 | 4 -> 14 -> 14 | 62 -> 932 -> 1007 | passes |
| 7954 Increase maximum contract size | `eip7954_increase_max_contract_size` | 30 / 30 / 30 | 7 -> 30 -> 30 | 3 -> 30 -> 30 | passes |
| 7976 Increase calldata floor cost | `eip7976_increase_calldata_floor_cost` | 525 / 525 / 525 | 114 -> 525 -> 525 | 158 -> 524 -> 525 | passes |
| 7981 Increase access-list cost | `eip7981_increase_access_list_cost` | 113 / 113 / 113 | 9 -> 113 -> 113 | 24 -> 113 -> 113 | passes |
| 7997 Deterministic factory predeploy | `eip7997_deterministic_factory_predeploy` | 16 / 16 / 16 | 0 -> 16 -> 16 | 0 -> 16 -> 16 | passes |
| 8024 DUPN, SWAPN, EXCHANGE | `eip8024_dupn_swapn_exchange` | 248 / 248 / 248 | 157 -> 248 -> 248 | 0 -> 248 -> 248 | passes |
| 8037 State creation gas cost increase | `eip8037_state_creation_gas_cost_increase` | 346 / 605 / 605 | 22 -> 316 -> 346 | 51 -> 560 -> 605 | passes |
| 8038 State-access gas cost increase | `eip8038_state_access_gas_cost_increase` | 192 / 192 / 192 | 9 -> 192 -> 192 | 9 -> 189 -> 192 | passes |
| 8246 SELFDESTRUCT no burn | `eip8246_selfdestruct_no_burn` | 2 / 650 / 650 | 0 -> 2 -> 2 | 0 -> 294 -> 650 | passes |
| 8282 Builder execution requests | `eip8282_builder_execution_requests` | 0 / 47 / 47 | - | 6 -> 47 -> 47 | passes |
| **Total** | | 1748 / 3726 / 3729 | 416 -> 1707 -> 1748 | 338 -> 3232 -> 3729 | |

"Passes" means every case of the directory passes in every family that has
it. The corpus has no directory of its own for the protocol-system-call state
reservoir (EIP-8037 `SYSTEM_MAX_SSTORES_PER_CALL`); it is exercised by
eip8282's `system_contract_reaches_gas_limit` and is listed under 8037 below.

### Where each EIP lives

| EIP | Our code | Reference (geth 1.17.6) |
| --- | --- | --- |
| 2780 | `src/runtime/execution/gas.lisp` `transaction-base-gas-eip2780`, `transaction-intrinsic-gas-amsterdam`; `src/runtime/execution/set-code.lisp` `apply-set-code-authorizations-amsterdam`; `src/runtime/execution/apply-message.lisp` `charge-amsterdam-call-recipient`, `apply-amsterdam-call-runtime-charges` | `core/state_transition.go` `IntrinsicGas`, `intrinsicBaseGasEIP2780`, `executeCall`, `executeCreate`, `applyAuthorization`, `chargeCallRecipientEIP2780` |
| 7708 | `src/protocol/receipts/receipts.lisp` `make-eth-transfer-log-entry`; `src/runtime/evm/state.lisp` `selfdestruct-account`; `src/runtime/execution/state.lisp` `transfer-value` | `core/types/log.go` `EthTransferLog`; `core/evm.go` `Transfer`; `core/vm/instructions.go` `opSelfdestruct6780` |
| 7778 | `src/runtime/execution/message-lists.lisp` (cumulative regular and state gas), `src/runtime/execution/block-execution.lisp` (header `gasUsed` is their maximum) | `core/gaspool.go` `ChargeGasAmsterdam`; `core/state_transition.go` `settleGas` |
| 7843 | `src/runtime/evm/opcodes/environment.lisp` (0x4b); `src/protocol/consensus/block-validation/forks.lisp` `validate-block-amsterdam-fields` | `core/vm/eips.go` `opSlotNum`; `consensus/beacon/consensus.go` `verifyHeader` |
| 7928 | `src/runtime/execution/access.lisp` (block-access phase and construction); `src/runtime/execution/block-body-validation.lisp` `validate-derived-block-access-list`; `src/protocol/block-access-lists/` | `core/types/bal/`; `core/state_processor.go` `PreExecution`, `PostExecution`; `core/block_validator.go` |
| 7954 | `src/protocol/chain-config/types.lisp` `+amsterdam-max-contract-code-size+`; `src/runtime/execution/contract.lisp` | `params/protocol_params.go` `MaxCodeSizeAmsterdam`; `core/vm/common.go` |
| 7976 | `src/runtime/execution/gas.lisp` `transaction-floor-data-gas-eip7976`, `transaction-effective-floor-gas` | `core/state_transition.go` `FloorDataGas` |
| 7981 | `src/runtime/execution/gas.lisp` `transaction-access-list-tokens-eip7981`, `transaction-access-list-data-gas-eip7981` | `core/state_transition.go` `IntrinsicGas`, `FloorDataGas` |
| 7997 | `src/runtime/execution/system-calls.lisp` `apply-eip7997-transition`, `apply-amsterdam-activation-transition` | `consensus/misc/eip7997.go` `ApplyEIP7997`; `core/state_processor.go` `PreExecution` |
| 8024 | `src/runtime/evm/opcodes/stack-log.lisp` (0xe6..0xe8); `src/runtime/evm/opcodes.lisp` `decode-eip8024-single`, `decode-eip8024-pair`, `jump-destination-bitmap` | `core/vm/instructions.go` `opDupN`, `opSwapN`, `opExchange`; `core/vm/analysis_legacy.go` `codeBitmap` |
| 8037 | `src/runtime/evm/gas.lisp` (two-dimensional budget; `evm-gas-budget-forward`, `-exit-revert`, `-exit-halt`, `-absorb`, `-drain-regular`), `src/runtime/evm/opcodes/state-memory.lisp` (SSTORE), `src/runtime/evm/interpreter/create.lisp` `execute-contract-creation-amsterdam`, `call.lisp` `execute-evm-message-call-amsterdam`; `src/runtime/execution/gas.lisp` `transaction-runtime-gas-budget`; `src/runtime/execution/apply-message.lisp` `apply-amsterdam-message-call`, `settle-amsterdam-transaction`; `src/runtime/execution/apply-contract.lisp` `apply-amsterdam-contract-creation`; `src/runtime/execution/system-calls.lisp` `protocol-system-call-gas-budget` | `core/vm/gascosts.go` `GasBudget`; `core/vm/gas_table.go`; `core/vm/operations_acl.go` `makeCallVariantGasCallEIP8037`; `core/vm/instructions.go` `opCall`, `opCreate`; `core/vm/evm.go` `create`; `core/state_transition.go` `executeCall`, `executeCreate`, `settleGas`; `core/state_processor.go` `systemCallGasBudget` |
| 8038 | `src/runtime/evm/types.lisp` (Amsterdam access constants) and the opcode gas functions | `params/protocol_params.go`; `core/vm/operations_acl.go`, `gas_table.go` |
| 8246 | `src/runtime/evm/opcodes/system.lisp` (SELFDESTRUCT), `src/runtime/evm/state.lisp` `selfdestruct-account` | `core/vm/instructions.go` `opSelfdestruct6780` |
| 8282 | `src/runtime/execution/prague-requests.lisp` `derive-prague-execution-requests` (Amsterdam branch) | `core/state_processor.go` `PostExecution`, `ProcessBuilderDepositQueue`, `ProcessBuilderExitQueue` |

## What the first branch changed

Each change is behind an Amsterdam check unless stated, and each has a unit
test that failed first (the commit messages record the RED control):

| Commit | Change | Unlocked |
| --- | --- | --- |
| `29c4cace` | An Amsterdam header needs a slot number, not one larger than its parent's (`validate-block-amsterdam-slot-number` removed; geth only checks presence). | payload 0 of nearly every engine fixture |
| `1cbb6a98` | EIP-2780 intrinsic base, EIP-8037 per-authorization floor (7816), EIP-7981 access-list surcharge, EIP-7976 floor. | eip7976, eip7981, most of eip2780 |
| `5029383e` | JUMPDEST analysis skips PUSH data only; DUPN/SWAPN/EXCHANGE immediates stay jump targets. **Not Amsterdam-only**, see below. | eip8024, eip7954 |
| `38ab8068` | A zero-tip coinbase is listed in the block access list. | eip7843 engine, most engine fixtures |
| `2ed808e1` | Amsterdam protocol calls get a state reservoir of 16 new slots. | eip8282 |
| `e1761197` | No EIP-7708 burn log for a self-destruct to self (EIP-8246 removed the burn). | eip8246 state, one eip8038 case |
| `8e460d49` | Authorization runtime charges (ACCOUNT_WRITE, new account, delegation indicator; no refund), the value-to-empty-recipient charge after the authorizations, the delegated-recipient target access; exceptional halts spend at most the gas limit. | eip7981, eip7976, eip8038, eip7928 state, eip7997 |
| `ac7d692d` | The activation block leaves an already-installed factory out of the access list. | the BPO2-to-Amsterdam transition network |

Why these first: the baseline failures clustered on the sender's balance,
which every Amsterdam fixture checks, and on two whole-corpus engine blockers
(the slot-number rule and the zero-tip coinbase). The intrinsic and floor
formulas are small, pure functions with an exact geth counterpart, and the
remaining fixes were each one function with one fixture-backed observable, so
they moved whole directories for little code. The interpreter-level EIP-8037
refill work that the remaining failures need was left alone: it is larger, and
the interpreter is being changed concurrently for an Osaka gas bug.

**The JUMPDEST change touches every fork.** The skip of the byte after
0xe6..0xe8 was added with the EIP-8024 opcodes (`e225c1aa`) for all forks, so
since then an Osaka or Prague jump to a 0x5b that follows an undefined
0xe6..0xe8 byte was refused where geth accepts it. Removing the skip restores
the pre-`e225c1aa` analysis for earlier forks; the stable `tests@v20.0.2` gates
pass with byte-identical manifests at `c072361d` (see `docs/evidence/gates.md`).

## What the second branch changed

`amsterdam-slice-2` (on `c677bdf0`) took the failures the first branch left,
largest first. Again each change is behind an Amsterdam check unless stated,
and each has a unit test the commit message records failing first:

| Commit | Change | Unlocked |
| --- | --- | --- |
| `462c6d34` | Amsterdam frames hand gas off as geth's `GasBudget` does: the caller pays the regular gas it forwards and hands the child its whole reservoir (`Forward`); the child ends in its success, revert (`ExitRevert`) or halt (`ExitHalt`) leftover, which the caller absorbs (`Absorb`). CALL caps 63/64 of the regular gas left *after* the value and new-account charges (`makeCallVariantGasCallEIP8037`); CREATE/CREATE2 and the top frame of a call or creation settle as `opCreate`, `executeCall`, `executeCreate` and `settleGas` do; SSTORE refills a restored slot before its regular charge. | the negative `GAS-USED` TYPE-ERROR (eip2780 `authorization_oog`, eip8037 `state_gas_sstore`, `state_gas_reservoir`, `state_gas_set_code`, `state_gas_create`); eip8246 `oog-*` (the 7,875 gas: 63/64 of 8,000 more); eip7708 `call_to_self_no_log` |
| `87183c60` | A paid SELFDESTRUCT asks whether its beneficiary is empty before reading the balance, so it always lists the beneficiary; a destructed account holding a balance at transaction end stays balance-only (`finaliseAmsterdam`); SLOAD and an Amsterdam SSTORE pay the slot access before reading the slot (the SLOAD reorder is **every fork**; before Amsterdam nothing observes it); a zero-amount withdrawal loads its account (every fork; invisible before Amsterdam). | eip8246 `success-*`, eip8038 `selfdestruct_*`, eip7928 `bal_*_and_oog`, `bal_zero_withdrawal`, `bal_selfdestruct_to_system_address_zero_balance` |
| `bd9a8f2e` | The calldata floor bounds the regular dimension even when state gas lifts the total past the floor (`settleGas` `txRegularGas`); an over-cap intrinsic is named so the runner classifies it `INTRINSIC_GAS_TOO_LOW` (no verdict change). | eip8037 `calldata_floor_not_discounted_by_state_gas`, `intrinsic_regular_gas_exceeds_cap*`; eip7976 `authorization_list_intrinsic_gas` |
| `bb3bda10` | Engine parameters: a newPayloadV5 `blockAccessList` that is not one whole RLP list, and a non-empty one on newPayloadV4, are -32602 (Nethermind `ExecutionPayloadParams.ValidateParams`; geth answers INVALID). Empty V4 bytes still reach reconstruction (INVALID). | eip7928 `bal_invalid_engine_payload_encoding`, transition `bal_invalid_engine_payload_field_before_fork` |
| `a69c6621` | Test harness only: the state runner passes `currentRandom` as PREVRANDAO, refuses a gas limit above the environment's at Amsterdam as the block path does, and classifies an empty blob-transaction recipient as `TYPE_3_TX_CONTRACT_CREATION`. | 19 `ported_static` state cases whose engine twins already passed |

The EIP-8037 hand-off was the bulk: one mechanism behind the negative
`GAS-USED`, the refill accounting and the 7,875-gas eip8246 cases. Every
cluster listed for the re-filled earlier trees at `c072361d` below also passes
at `a69c6621`; `istanbul/eip2200_net_gas_metering` and
`ported_static/stSStoreTest` failed with the same `GAS-USED` TYPE-ERROR, while
the engine-only clusters (`eip150_operation_gas_costs`, `eip2537`,
`eip6780_selfdestruct`, `eip7702_set_code_tx`, `eip4895_withdrawals`) were not
traced one by one: they were measured passing after these commits. The stable `tests@v20.0.2` gates pass with
manifest lines byte-identical to `b5161312` at `a69c6621`, and the Hoodi
differential replay is unchanged (320 match, 0 diverge, the same two witness
gaps); both are in `docs/evidence/gates.md`.

### BPO2-to-Amsterdam transition network

`blockchain_tests_engine/for_bpo2toamsterdamattime15k/amsterdam/` (activation
at timestamp 15000; measured from `4fb5df04`, the first revision that runs it):

| Directory | Cases | Passed before `ac7d692d` | Passed at `c072361d` | Passed at `a69c6621` |
| --- | --- | --- | --- | --- |
| eip2780 | 4 | 0 | 4 | 4 |
| eip7708 | 1 | 0 | 1 | 1 |
| eip7843 | 1 | 0 | 1 | 1 |
| eip7928 | 6 | 3 | 5 | 6 |
| eip7954 | 8 | 0 | 8 | 8 |
| eip7997 | 3 | 3 | 3 | 3 |
| eip8037 | 4 | 0 | 4 | 4 |
| eip8038 | 7 | 0 | 7 | 7 |
| eip8282 | 12 | 8 | 12 | 12 |
| **Total** | 46 | 14 | 45 | 46 |

The transition network also has `berlin/eip2929_gas_cost_increases`
(`precompile_warming`), which the default `amsterdam` tree selection does not
walk.

## What still fails

Nothing in the executed families at `a69c6621`: every Amsterdam directory,
every re-filled earlier tree and both transition trees pass (cold run below).
Three engine fixture files over 40 MB are counted, not run. For the record,
the failures the first branch left at `c072361d`, each cleared by the second
branch's commit named in the table above:

| Directory | Family | Failing | Mechanism (from the failure messages) |
| --- | --- | --- | --- |
| eip2780 | state 9, engine 14 | `authorization_oog/*`, `value_moving_transactions/value_contract_creation_tx` | A reverted or halted frame's state-gas refill drives the interpreter's `gas-used` negative (`TYPE-ERROR ... GAS-USED`); a halt after authorization state charges spends the whole gas limit where geth returns the reservoir. geth: `GasBudget.ExitRevert`, `ExitHalt`, `RefundState`, and `executeCreate`'s refill of the creation charge. |
| eip8037 | state 30, engine 45 | `state_gas_sstore/sstore_restoration_*`, `state_gas_reservoir/*`, `state_gas_set_code/*`, `state_gas_create/failed_create_tx_refills_top_frame_new_account`, `state_gas_pricing/intrinsic_regular_gas_exceeds_cap*` | Same refill accounting; SSTORE restoration refunds must credit the local reservoir; the two `intrinsic_regular_gas_exceeds_cap` cases expect `INTRINSIC_GAS_TOO_LOW` when the regular part alone exceeds 2^24. |
| eip7708 | state 2, engine 3 | `call_to_self_no_log` (CALL, CALLCODE), `zero_value_operations_no_log` (selfdestruct) | Sender balance and access list differ for a value call to self (the CALL cap, `462c6d34`; the SELFDESTRUCT beneficiary read, `87183c60`). |
| eip7928 | engine 75 | e.g. `bal_net_zero_balance_transfer`, `bal_zero_withdrawal`, `bal_call_7702_delegation_and_oog`, `bal_invalid_engine_payload_encoding` | Access-list content for net-zero balance changes, zero-amount withdrawals and delegated calls that run out of gas; a malformed BAL field must be -32602. |
| eip8246 | engine 356 | `selfdestructing_initcode_preserves_balance` (`oog-*` variants) | Transaction 1 is charged 7,875 gas too much when an initcode that self-destructs runs out of gas: the CALL cap was 63/64 of a balance 8,000 gas larger (`462c6d34`); the `success-*` variants then needed the beneficiary read and the balance-only account (`87183c60`). |
| eip8038 | engine 3 | `selfdestruct_self_or_precompile_beneficiary`, `selfdestruct_zero_balance_no_account_write` | Access-list content for those self-destructs. |
| eip7976 | engine 1 | `additional_coverage/authorization_list_intrinsic_gas` | Header `gasUsed` 47000 vs our 38816: the block's regular dimension for a floor-bound authorization transaction. |
| eip7928 (transition) | engine 1 | `bal_invalid_engine_payload_field_before_fork` | A pre-Amsterdam newPayloadV4 carrying `blockAccessList` must be -32602; we answer INVALID. This is Prague/Osaka Engine parameter validation. |

## Earlier features at Amsterdam

The `for_amsterdam` network also re-fills the earlier forks' feature trees
under Amsterdam rules. With `ETHEREUM_LISP_AMSTERDAM_EEST_TREES=all` (cases
passed / cases; three engine files over 40 MB counted, not run) at `c072361d`
and at `a69c6621`:

| Tree | State (`c072361d`) | Engine (`c072361d`) | State (`a69c6621`) | Engine (`a69c6621`) |
| --- | --- | --- | --- | --- |
| amsterdam | 1707 / 1748 | 3232 / 3729 | 1748 / 1748 | 3729 / 3729 |
| berlin | 541 / 541 | 541 / 541 | 541 / 541 | 541 / 541 |
| byzantium | 600 / 600 | 600 / 600 | 600 / 600 | 600 / 600 |
| cancun | 1459 / 1464 | 3993 / 4044 (1 file skipped) | 1464 / 1464 | 4044 / 4044 (1 file skipped) |
| constantinople | 114 / 114 | 109 / 115 | 114 / 114 | 115 / 115 |
| frontier | 782 / 784 | 819 / 826 | 784 / 784 | 826 / 826 |
| homestead | 9 / 9 | 9 / 9 | 9 / 9 | 9 / 9 |
| istanbul | 474 / 852 | 84 / 84 (1 file skipped) | 852 / 852 | 84 / 84 (1 file skipped) |
| london | 6 / 6 | 7 / 7 | 6 / 6 | 7 / 7 |
| osaka | 1194 / 1196 | 1350 / 1350 (2 files skipped) | 1196 / 1196 | 1350 / 1350 (2 files skipped) |
| paris | 50 / 50 | 51 / 51 | 50 / 50 | 51 / 51 |
| ported_static | 6204 / 6286 | 6191 / 6286 | 6286 / 6286 | 6286 / 6286 |
| prague | 1889 / 1925 | 2364 / 2543 | 1925 / 1925 | 2543 / 2543 |
| shanghai | 52 / 52 | 87 / 110 | 52 / 52 | 110 / 110 |
| tangerine_whistle | - | 594 / 772 | - | 772 / 772 |
| **Total** | 15081 / 15627 | 20031 / 21067 | 15627 / 15627 | 21067 / 21067 |

The transition network's two trees add 95 / 96 engine cases at `c072361d`
and 96 / 96 at `a69c6621` (`amsterdam` 46 / 46, `berlin` 50 / 50). The
`a69c6621` column is one cold run (the regression-gate command above, all
fourteen directories required, EXIT=0).

At `c072361d` the largest clusters there were the same EIP-8037 refill defect
(`istanbul/eip2200_net_gas_metering` 378 state failures, all
`TYPE-ERROR ... GAS-USED` on `sstore_combinations_initial`;
`ported_static/stSStoreTest` 37), EIP-150 operation costs at Amsterdam
(`tangerine_whistle/eip150_operation_gas_costs`, 178 engine),
`prague/eip2537_bls_12_381_precompiles` (138 engine),
`cancun/eip6780_selfdestruct` (42 engine), `prague/eip7702_set_code_tx`
(36 state, 41 engine) and `shanghai/eip4895_withdrawals` (23 engine). Two
vectors exhaust the heap instead of failing:
`ported_static/stSpecialTest/sha3_deja` asks for a 1 TiB allocation and
`ported_static/stRandom2/random_statetest524` for 1.9 GB, in both families.
`sha3_deja` runs `SHA3` with size 0 at offset 2^40-1. The SHA3 handler
(`src/runtime/evm/opcodes/arithmetic.lisp`, opcode 0x20) charges no expansion
for a zero size, as it should, but then calls `ensure-memory-size` with
`offset + size` anyway. This is not Amsterdam-specific: a probe under Osaka
rules reads `MSIZE` = 1,048,576 after `SHA3(offset=2^20, size=0)` where the
EVM leaves memory empty. The stable gates never see it because their discovery
excludes `ported_static`. It is reported for a separate fix rather than changed
here, since it moves Prague and Osaka behaviour. Both vectors pass at
`a69c6621`: the base `c677bdf0` already carries the memory-region audit merge
(`f8c882bc`), and the second branch did not touch SHA3.

## Not covered

- `amsterdam-execution-available-p` stays NIL. Every count above now passes,
  but reopening it also needs the pinned Hive Engine suites and the
  resource-budget check the plan names; neither is claimed here.
- The engine -32602 split for a malformed `blockAccessList` follows
  Nethermind and the EEST fixtures; geth v1.17.6 answers INVALID for the same
  payloads (its `ExecutableDataToBlock` fails inside `newPayload`).
- No Hive run, no Engine getPayload/forkchoice test at Amsterdam, no payload
  building against this corpus, and no negative capability tests for the
  KZG and BLS facilities.
- `blockchain_tests` (block RLP), `blockchain_tests_engine_x`,
  `blockchain_tests_sync` and `transaction_tests` are not run.
- The burn-down counts are a baseline, not a gate, except for the directories
  named in `ETHEREUM_LISP_AMSTERDAM_EEST_REQUIRED`; the re-filled earlier
  trees are not required directories, so a regression there prints a failing
  line but does not fail the test.
- A self-transfer is priced exactly only where the sender is known
  (`apply-message`); pool admission and RPC estimates price it as a transfer
  to another account, and the block-level pre-check uses the self-transfer
  lower bound.
- The stable `tests@v20.0.2` corpus is the guard that Prague and Osaka did not
  move; it does not cover the JUMPDEST case above, nor the two every-fork
  reorders of `87183c60` (the SLOAD read after its charge, the zero-amount
  withdrawal read), which change no pre-Amsterdam state or gas.
