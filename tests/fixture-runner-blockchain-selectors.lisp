(in-package #:ethereum-lisp.test)

(defconstant +phase-a-eest-blockchain-replay-selectors-env+
  "ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS")

(defconstant +phase-a-eest-blockchain-replay-auto-selector+ "auto")

(defconstant +phase-a-eest-blockchain-replay-pinned-selector+
  "pinned-v5.4.0")

(defparameter +phase-a-eest-blockchain-replay-materialization-kind-names+
  '("engineNewPayloadV2" "blockRlp"))

(defparameter +phase-a-eest-blockchain-replay-materialization-kinds+
  '(("shanghai/phase-a-access-list-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-contract-creation-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-dynamic-fee-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-empty-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-empty-standard.json" . "blockRlp")
    ("shanghai/phase-a-internal-create2-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-log-contract-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-transfer-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-two-legacy-transfers-engine.json" . "engineNewPayloadV2")))

(defparameter +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+
  '(("berlin/eip2930_access_list/test_eip2930_tx_validity.json/tests/berlin/eip2930_access_list/test_tx_type.py::test_eip2930_tx_validity[fork_Shanghai-valid-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_repeated_address_acl.json/tests/berlin/eip2930_access_list/test_acl.py::test_repeated_address_acl[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-blockchain_test_engine_from_state_test-account_warm_True-storage_key_warm_True]"
     . "engineNewPayloadV2")
    ("berlin/eip2929_gas_cost_increases/test_call_insufficient_balance.json/tests/berlin/eip2929_gas_cost_increases/test_call.py::test_call_insufficient_balance[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("constantinople/eip145_bitwise_shift/test_combinations.json/tests/constantinople/eip145_bitwise_shift/test_shift_combinations.py::test_combinations[fork_Shanghai-blockchain_test_engine_from_state_test-sar]"
     . "engineNewPayloadV2")
    ("constantinople/eip145_bitwise_shift/test_combinations.json/tests/constantinople/eip145_bitwise_shift/test_shift_combinations.py::test_combinations[fork_Shanghai-blockchain_test_engine_from_state_test-shl]"
     . "engineNewPayloadV2")
    ("constantinople/eip145_bitwise_shift/test_combinations.json/tests/constantinople/eip145_bitwise_shift/test_shift_combinations.py::test_combinations[fork_Shanghai-blockchain_test_engine_from_state_test-shr]"
     . "engineNewPayloadV2")
    ("frontier/precompiles/test_precompile_absence.json/tests/frontier/precompiles/test_precompile_absence.py::test_precompile_absence[fork_Shanghai-blockchain_test_engine_from_state_test-31_bytes]"
     . "engineNewPayloadV2")
    ("frontier/precompiles/test_precompile_absence.json/tests/frontier/precompiles/test_precompile_absence.py::test_precompile_absence[fork_Shanghai-blockchain_test_engine_from_state_test-32_bytes]"
     . "engineNewPayloadV2")
    ("frontier/precompiles/test_precompile_absence.json/tests/frontier/precompiles/test_precompile_absence.py::test_precompile_absence[fork_Shanghai-blockchain_test_engine_from_state_test-empty_calldata]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_buffer_modify.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_buffer_modify[fork_Shanghai-call_opcode_CALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_buffer_modify.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_buffer_modify[fork_Shanghai-call_opcode_CALLCODE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_buffer_modify.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_buffer_modify[fork_Shanghai-call_opcode_DELEGATECALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_buffer_modify.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_buffer_modify[fork_Shanghai-call_opcode_STATICCALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_overwrite.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_overwrite[fork_Shanghai-call_opcode_CALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_overwrite.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_overwrite[fork_Shanghai-call_opcode_CALLCODE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_overwrite.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_overwrite[fork_Shanghai-call_opcode_DELEGATECALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/identity_precompile/test_identity_return_overwrite.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_overwrite[fork_Shanghai-call_opcode_STATICCALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_large_args_offset_size_zero.json/tests/frontier/opcodes/test_call.py::test_call_large_args_offset_size_zero[fork_Shanghai-call_opcode_CALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_large_args_offset_size_zero.json/tests/frontier/opcodes/test_call.py::test_call_large_args_offset_size_zero[fork_Shanghai-call_opcode_CALLCODE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_large_args_offset_size_zero.json/tests/frontier/opcodes/test_call.py::test_call_large_args_offset_size_zero[fork_Shanghai-call_opcode_DELEGATECALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_large_args_offset_size_zero.json/tests/frontier/opcodes/test_call.py::test_call_large_args_offset_size_zero[fork_Shanghai-call_opcode_STATICCALL-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_large_offset_mstore.json/tests/frontier/opcodes/test_call.py::test_call_large_offset_mstore[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 0 0]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 1 0]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 1 1]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 1 2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 neg6 9]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-cdc 0 neg6 ff]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-sec]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy[fork_Shanghai-blockchain_test_engine_from_state_test-underflow]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-34_bytes]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-two_bytes]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-word_n_byte]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-34_bytes]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-two_bytes]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-word_n_byte]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-args_size_0]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-args_size_16]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-args_size_257]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-args_size_2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_contract-args_size_33]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-args_size_0]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-args_size_16]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-args_size_257]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-args_size_2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize[fork_Shanghai-blockchain_test_engine_from_state_test-calldata_source_tx-args_size_33]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP1]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP3]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP4]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP5]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP6]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP7]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP8]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP9]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP10]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP11]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP12]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP13]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP14]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP15]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP16]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP1]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP3]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP4]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP5]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP6]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP7]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP8]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP9]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP10]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP11]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP12]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP13]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP14]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP15]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap[fork_Shanghai-blockchain_test_engine_from_state_test-SWAP16]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_all_opcodes.json/tests/frontier/opcodes/test_all_opcodes.py::test_all_opcodes[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("homestead/coverage/test_coverage.json/tests/homestead/coverage/test_coverage.py::test_coverage[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE-transaction_create_False]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE-transaction_create_True]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE_TO_ITSELF-transaction_create_False]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE_TO_ITSELF-transaction_create_True]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE2-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE-transaction_create_False]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create[fork_Shanghai-create_opcode_CREATE2-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-operation_Operation.SUICIDE_TO_ITSELF-transaction_create_False]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_deposit_oog.json/tests/frontier/create/test_create_deposit_oog.py::test_create_deposit_oog[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_deposit_oog.json/tests/frontier/create/test_create_deposit_oog.py::test_create_deposit_oog[fork_Shanghai-create_opcode_CREATE2-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_one_byte.json/tests/frontier/create/test_create_one_byte.py::test_create_one_byte[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_one_byte.json/tests/frontier/create/test_create_one_byte.py::test_create_one_byte[fork_Shanghai-create_opcode_CREATE2-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_store.json/tests/frontier/create/test_create_suicide_store.py::test_create_suicide_store[fork_Shanghai-create_opcode_CREATE-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/create/test_create_suicide_store.json/tests/frontier/create/test_create_suicide_store.py::test_create_suicide_store[fork_Shanghai-create_opcode_CREATE2-evm_code_type_LEGACY-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/validation/test_gas_limit_below_minimum.json/tests/frontier/validation/test_header.py::test_gas_limit_below_minimum[fork_Shanghai-blockchain_test_engine-gas_limit_5000]"
     . "engineNewPayloadV2")
    ("frontier/validation/test_sender_balance.json/tests/frontier/validation/test_transaction.py::test_sender_balance[fork_Shanghai-blockchain_test_engine-balance_diff_0-expected_exception_None]"
     . "engineNewPayloadV2")
    ("frontier/validation/test_sender_balance.json/tests/frontier/validation/test_transaction.py::test_sender_balance[fork_Shanghai-blockchain_test_engine-balance_diff_1-expected_exception_None]"
     . "engineNewPayloadV2")
    ("frontier/validation/test_tx_nonce.json/tests/frontier/validation/test_transaction.py::test_tx_nonce[fork_Shanghai-blockchain_test_engine-nonce_diff_0-expected_exception_None]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-blockchain_test_engine_from_state_test-account_warm_False-storage_key_warm_False]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-blockchain_test_engine_from_state_test-account_warm_True-storage_key_warm_False]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-empty_access_list]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-multiple_addresses_first_address_no_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-multiple_addresses_first_address_single_storage_key]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-multiple_addresses_second_address_multiple_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-multiple_addresses_second_address_no_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-multiple_addresses_second_address_single_storage_key]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-repeated_address_multiple_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-repeated_address_no_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-repeated_address_single_storage_key]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-single_address_multiple_no_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-single_address_multiple_storage_keys]"
     . "engineNewPayloadV2")
    ("berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas-single_address_single_storage_key]"
     . "engineNewPayloadV2")
    ("byzantium/eip196_ec_add_mul/test_gas_costs.json/tests/byzantium/eip196_ec_add_mul/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_False-ecadd]"
     . "engineNewPayloadV2")
    ("byzantium/eip196_ec_add_mul/test_gas_costs.json/tests/byzantium/eip196_ec_add_mul/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_False-ecmul]"
     . "engineNewPayloadV2")
    ("byzantium/eip196_ec_add_mul/test_gas_costs.json/tests/byzantium/eip196_ec_add_mul/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_True-ecadd]"
     . "engineNewPayloadV2")
    ("byzantium/eip196_ec_add_mul/test_gas_costs.json/tests/byzantium/eip196_ec_add_mul/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_True-ecmul]"
     . "engineNewPayloadV2")
    ("byzantium/eip197_ec_pairing/test_gas_costs.json/tests/byzantium/eip197_ec_pairing/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_False-ecpairing]"
     . "engineNewPayloadV2")
    ("byzantium/eip197_ec_pairing/test_gas_costs.json/tests/byzantium/eip197_ec_pairing/test_gas.py::test_gas_costs[fork_Shanghai-blockchain_test_engine_from_state_test-enough_gas_True-ecpairing]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE2-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE2-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_RETURN-create_type_CREATE2-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE2-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE2-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_RETURN-return_type_REVERT-create_type_CREATE2-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE2-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE2-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_RETURN-create_type_CREATE2-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE-call_return_size_35]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE2-call_return_size_0]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE2-call_return_size_32]"
     . "engineNewPayloadV2")
    ("constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_Shanghai-blockchain_test_engine_from_state_test-return_type_in_create_REVERT-return_type_REVERT-create_type_CREATE2-call_return_size_35]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2_precompile_delegatecall.json/tests/istanbul/eip152_blake2/test_blake2_delegatecall.py::test_blake2_precompile_delegatecall[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-EIP-152-RFC-7693-zero-input-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-empty-input-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-invalid-final-block-flag-value-0x02-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-oog-rounds-4294967295-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-invalid-rounds-length-long-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-invalid-rounds-length-short-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-different-message-offset-0x05-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-false-final-block-flag-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-0-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-1-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-1024-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-1024-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-12-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-128-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-128-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-16-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-16-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-16-offset-0x78-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-256-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-256-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-32-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-32-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-32-offset-0x78-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-512-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-512-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-64-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-64-offset-0x10-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b[fork_Shanghai-blockchain_test_engine_from_state_test-valid-rounds-64-offset-0x78-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case0-data0-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case0-data0-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data1-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data1-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data2-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data2-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data3-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case2-data3-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case9-data10-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-case9-data10-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-modified-case8-data9-large-gas-limit-call_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit[fork_Shanghai-gas_limit_0x07270e00-blockchain_test_engine_from_state_test-EIP-152-modified-case8-data9-large-gas-limit-call_opcode_CALL]"
     . "engineNewPayloadV2")
    ("istanbul/eip1344_chainid/test_chainid.json/tests/istanbul/eip1344_chainid/test_chainid.py::test_chainid[fork_Shanghai-typed_transaction_0-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("istanbul/eip1344_chainid/test_chainid.json/tests/istanbul/eip1344_chainid/test_chainid.py::test_chainid[fork_Shanghai-typed_transaction_1-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("istanbul/eip1344_chainid/test_chainid.json/tests/istanbul/eip1344_chainid/test_chainid.py::test_chainid[fork_Shanghai-typed_transaction_2-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("london/eip1559_fee_market_change/test_eip1559_tx_validity.json/tests/london/eip1559_fee_market_change/test_tx_type.py::test_eip1559_tx_validity[fork_Shanghai-valid-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-balance-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-balance-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-balance-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-balance-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-balance-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-balance-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-balance-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-balance-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-balance-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-balance-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-balance-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-balance-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-balance-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-balance-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-balance-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-code-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-code-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-code-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-nonce-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-nonce-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE-non-empty-nonce-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-code-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-code-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-code-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-nonce-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-nonce-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode[fork_Shanghai-blockchain_test_engine_from_state_test-opcode_CREATE2-non-empty-nonce-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-code-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-code-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-code-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-nonce-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-nonce-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_0-blockchain_test_engine_from_state_test-non-empty-nonce-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-code-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-code-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-code-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-nonce-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-nonce-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_1-blockchain_test_engine_from_state_test-non-empty-nonce-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-code-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-code-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-code-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-nonce-correct-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-nonce-oog-initcode]"
     . "engineNewPayloadV2")
    ("paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx[fork_Shanghai-tx_type_2-blockchain_test_engine_from_state_test-non-empty-nonce-revert-initcode]"
     . "engineNewPayloadV2")
    ("paris/security/test_tx_selfdestruct_balance_bug.json/tests/paris/security/test_selfdestruct_balance_bug.py::test_tx_selfdestruct_balance_bug[fork_Shanghai-blockchain_test_engine]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_call_memory_expands_on_early_revert.json/tests/frontier/opcodes/test_call.py::test_call_memory_expands_on_early_revert[fork_Shanghai-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_0-callee_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_0-callee_opcode_CALL]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_0-callee_opcode_DELEGATECALL]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_0-callee_opcode_STATICCALL]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_1-callee_opcode_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_1-callee_opcode_CALL]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_1-callee_opcode_DELEGATECALL]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation[fork_Shanghai-blockchain_test_engine_from_state_test-gas_shortage_1-callee_opcode_STATICCALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_0-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_0-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1_nonzerovalue-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1_nonzerovalue-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1_nonzerovalue_insufficient_balance-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_1_nonzerovalue_insufficient_balance-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_2-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_2-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_3-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_3-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4_exact_gas-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4_exact_gas-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4_insufficient_gas-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile[fork_Shanghai-blockchain_test_engine_from_state_test-identity_4_insufficient_gas-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile_large_params.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile_large_params[fork_Shanghai-blockchain_test_engine_from_state_test-tx_gas_limit_10000000-identity_5-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile_large_params.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile_large_params[fork_Shanghai-blockchain_test_engine_from_state_test-tx_gas_limit_10000000-identity_5-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile_large_params.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile_large_params[fork_Shanghai-blockchain_test_engine_from_state_test-tx_gas_limit_10000000-identity_6-call_type_CALLCODE]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_call_identity_precompile_large_params.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile_large_params[fork_Shanghai-blockchain_test_engine_from_state_test-tx_gas_limit_10000000-identity_6-call_type_CALL]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_identity_precompile_returndata.json/tests/frontier/identity_precompile/test_identity_returndatasize.py::test_identity_precompile_returndata[fork_Shanghai-blockchain_test_engine_from_state_test-output_size_greater_than_input]"
     . "engineNewPayloadV2")
    ("frontier/identity_precompile/test_identity_precompile_returndata.json/tests/frontier/identity_precompile/test_identity_returndatasize.py::test_identity_precompile_returndata[fork_Shanghai-blockchain_test_engine_from_state_test-output_size_less_than_input]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH1]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH3]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH4]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH5]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH6]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH7]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH8]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH9]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH10]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH11]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH12]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH13]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH14]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH15]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH16]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH17]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH18]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH19]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH20]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH21]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH22]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH23]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH24]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH25]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH26]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH27]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH28]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH29]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH30]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH31]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push[fork_Shanghai-blockchain_test_engine_from_state_test-PUSH32]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP1]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP2]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP3]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP4]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP5]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP6]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP7]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP8]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP9]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP10]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP11]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP12]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP13]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP14]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP15]"
     . "engineNewPayloadV2")
    ("frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup[fork_Shanghai-evm_code_type_LEGACY-blockchain_test_engine_from_state_test-DUP16]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-gas_cost]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-storage_overwrite]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-before_jumpdest]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-fill_stack]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-key_sstore]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-blockchain_test_engine_from_state_test-stack_overflow]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-blockchain_test_engine_from_state_test-call]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-blockchain_test_engine_from_state_test-callcode]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-blockchain_test_engine_from_state_test-delegatecall]"
     . "engineNewPayloadV2")
    ("shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-blockchain_test_engine_from_state_test-staticcall]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-BALANCE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-CALL]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-CALLCODE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-DELEGATECALL]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-EXTCODECOPY]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-EXTCODEHASH]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-EXTCODESIZE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-blockchain_test_engine_from_state_test-STATICCALL]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-CALL-insufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-CALL-sufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-CALLCODE-insufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-CALLCODE-sufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-DELEGATECALL-insufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-DELEGATECALL-sufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-STATICCALL-insufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-blockchain_test_engine_from_state_test-STATICCALL-sufficient_gas]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_contract_creating_tx.json/tests/shanghai/eip3860_initcode/test_initcode.py::test_contract_creating_tx[fork_Shanghai-blockchain_test_engine_from_state_test-max_size_ones]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_contract_creating_tx.json/tests/shanghai/eip3860_initcode/test_initcode.py::test_contract_creating_tx[fork_Shanghai-blockchain_test_engine_from_state_test-max_size_zeros]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-empty_code-opcode_CREATE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-empty_code-opcode_CREATE2]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-empty_initcode-opcode_CREATE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-empty_initcode-opcode_CREATE2]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-max_code-opcode_CREATE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-max_code-opcode_CREATE2]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-max_initcode-opcode_CREATE]"
     . "engineNewPayloadV2")
    ("shanghai/eip3860_initcode/test_legacy_create_edge_code_size.json/tests/shanghai/eip3860_initcode/test_with_eof.py::test_legacy_create_edge_code_size[fork_Shanghai-blockchain_test_engine_from_state_test-max_initcode-opcode_CREATE2]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_large_amount.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_large_amount[fork_Shanghai-blockchain_test_engine]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_many_withdrawals.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_many_withdrawals[fork_Shanghai-blockchain_test_engine]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_multiple_withdrawals_same_address.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::TestMultipleWithdrawalsSameAddress::test_multiple_withdrawals_same_address[fork_Shanghai-blockchain_test_engine-test_case_single_block]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_newly_created_contract.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_newly_created_contract[fork_Shanghai-blockchain_test_engine-with_tx_value]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_newly_created_contract.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_newly_created_contract[fork_Shanghai-blockchain_test_engine-without_tx_value]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_self_destructing_account.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_self_destructing_account[fork_Shanghai-blockchain_test_engine]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_withdrawals_root.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_withdrawals_root[fork_Shanghai-blockchain_test_engine-n_withdrawals_0-valid_True]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_withdrawals_root.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_withdrawals_root[fork_Shanghai-blockchain_test_engine-n_withdrawals_1-valid_True]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_withdrawals_root.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_withdrawals_root[fork_Shanghai-blockchain_test_engine-n_withdrawals_16-valid_True]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_zero_amount.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_zero_amount[fork_Shanghai-blockchain_test_engine-two_withdrawals_no_value]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_zero_amount.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_zero_amount[fork_Shanghai-blockchain_test_engine-three_withdrawals_one_with_value]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_zero_amount.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_zero_amount[fork_Shanghai-blockchain_test_engine-four_withdrawals_one_with_value_one_with_max]"
     . "engineNewPayloadV2")
    ("shanghai/eip4895_withdrawals/test_zero_amount.json/tests/shanghai/eip4895_withdrawals/test_withdrawals.py::test_zero_amount[fork_Shanghai-blockchain_test_engine-four_withdrawals_one_with_value_one_with_max_reversed_order]"
     . "engineNewPayloadV2")))

(defparameter +phase-a-eest-blockchain-replay-discovery-feature-directories+
  '("frontier" "homestead" "eip150" "eip158" "byzantium"
    "constantinople" "constantinoplefix" "istanbul" "berlin" "london"
    "paris" "shanghai"))

(defconstant +phase-a-eest-blockchain-replay-discovery-max-file-bytes+
  (* 2 1024 1024))

