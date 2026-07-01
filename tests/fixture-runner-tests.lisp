(in-package #:ethereum-lisp.test)

(defparameter +minimal-blockchain-fixture-path+
  "tests/fixtures/execution-spec-tests/minimal-blockchain.json")

(defparameter +eest-blockchain-engine-fixture-fields+
  '("fixture-format" "network" "blocks" "engineNewPayloadV2"))

(defparameter +eest-blockchain-engine-newpayload-v2-fields+
  '("chainId" "config" "parent" "payload" "expect"))

(defparameter +eest-blockchain-engine-newpayloads-fixture-fields+
  '("network" "lastblockhash" "config" "pre" "postState"
    "genesisBlockHeader" "engineNewPayloads" "_info"))

(defparameter +eest-blockchain-engine-newpayloads-entry-fields+
  '("params" "newPayloadVersion" "forkchoiceUpdatedVersion"))

(defparameter +eest-blockchain-rpc-payload-v2-fields+
  '("parentHash" "feeRecipient" "stateRoot" "receiptsRoot" "logsBloom"
    "blockNumber" "gasLimit" "gasUsed" "timestamp" "extraData"
    "prevRandao" "baseFeePerGas" "blockHash" "transactions" "withdrawals"))

(defparameter +eest-blockchain-standard-fixture-fields+
  '("network" "genesisBlockHeader" "pre" "postState" "lastblockhash"
    "sealEngine" "blocks"))

(defparameter +eest-blockchain-standard-block-fields+
  '("rlp" "blockHeader" "expectException" "uncleHeaders"))

(defparameter +eest-state-test-case-fields+
  '("env" "pre" "transaction" "post" "config" "_info"))

(defparameter +eest-state-test-transaction-fields+
  '("data" "gasLimit" "gasPrice" "nonce" "to" "value" "secretKey"
    "sender" "accessLists" "maxFeePerGas" "maxPriorityFeePerGas"))

(defconstant +phase-a-eest-state-test-selectors-env+
  "ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS")

(defconstant +phase-a-eest-state-test-auto-selector+ "auto")

(defparameter +phase-a-eest-state-test-case-names+
  '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
    "london/phase-a-state-sample.json/phase_a_london_dynamic_fee_state_sample"
    "london/phase-a-state-sample.json/phase_a_london_state_sample"
    "shanghai/phase-a-state-sample.json"))

(defparameter +phase-a-eest-state-test-supported-forks+
  '("London" "Shanghai"))

(defparameter +phase-a-eest-state-test-discovery-feature-directories+
  '("frontier" "homestead" "eip150" "eip158" "byzantium"
    "constantinople" "constantinoplefix" "istanbul" "berlin" "london"
    "paris" "shanghai"))

(defconstant +phase-a-eest-state-test-discovery-max-file-bytes+
  (* 2 1024 1024))

(defun phase-a-eest-create2-returndata-state-test-v5.4.0-case-names ()
  (loop for fork in '("London" "Shanghai")
        nconc
        (loop for return-type-in-create in '("RETURN" "REVERT")
              nconc
              (loop for return-type in '("RETURN" "REVERT")
                    nconc
                    (loop for create-type in '("CREATE" "CREATE2")
                          nconc
                          (loop for call-return-size in '(0 32 35)
                                collect
                                (format nil
                                        "constantinople/eip1014_create2/test_create2_return_data.json/tests/constantinople/eip1014_create2/test_create_returndata.py::test_create2_return_data[fork_~A-state_test-return_type_in_create_~A-return_type_~A-create_type_~A-call_return_size_~D]"
                                        fork
                                        return-type-in-create
                                        return-type
                                        create-type
                                        call-return-size)))))))

(defun phase-a-eest-call-large-offset-state-test-v5.4.0-case-names ()
  (append
   (loop for fork in '("London" "Shanghai")
         nconc
         (loop for call-opcode in '("CALL" "CALLCODE" "DELEGATECALL" "STATICCALL")
               collect
               (format nil
                       "frontier/opcodes/test_call_large_args_offset_size_zero.json/tests/frontier/opcodes/test_call.py::test_call_large_args_offset_size_zero[fork_~A-call_opcode_~A-evm_code_type_LEGACY-state_test]"
                       fork
                       call-opcode)))
   (loop for fork in '("London" "Shanghai")
         collect
         (format nil
                 "frontier/opcodes/test_call_large_offset_mstore.json/tests/frontier/opcodes/test_call.py::test_call_large_offset_mstore[fork_~A-state_test]"
                 fork))))

(defun phase-a-eest-modexp-state-test-v5.4.0-case-names ()
  (let ((prefix
          "byzantium/eip198_modexp_precompile/test_modexp.json/tests/byzantium/eip198_modexp_precompile/test_modexp.py::test_modexp"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (append
           (loop for declared-length in '(128 256 512 64)
                 collect
                 (format nil
                         "~A[fork_~A-state_test-EIP-198-case1-mod-even-declared-length-~D-bytes]"
                         prefix
                         fork
                         declared-length))
           (loop for declared-length in '(128 256 512 64)
                 collect
                 (format nil
                         "~A[fork_~A-state_test-EIP-198-case1-mod-power2-declared-length-~D-bytes]"
                         prefix
                         fork
                         declared-length))
           (loop for name in '("EIP-198-case1"
                               "EIP-198-case2"
                               "EIP-198-case3-raw-input-out-of-gas"
                               "EIP-198-case4-extra-data_07"
                               "EIP-198-case5-raw-input")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-~A]"
                         prefix
                         fork
                         name))
           (loop for name in '("ModExpInput_base_0x-exponent_0x-modulus_0x-ModExpOutput_returned_data_0x"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x-declared_exponent_length_4294967296-declared_modulus_length_1-ModExpOutput_call_success_False-returned_data_0x00"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x00-ModExpOutput_returned_data_0x00"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x0001-ModExpOutput_returned_data_0x0000"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x0002-ModExpOutput_returned_data_0x0001"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x01-ModExpOutput_returned_data_0x00"
                               "ModExpInput_base_0x-exponent_0x-modulus_0x02-ModExpOutput_returned_data_0x01"
                               "ModExpInput_base_0x-exponent_0x01-modulus_0x02-ModExpOutput_returned_data_0x00"
                               "ModExpInput_base_0x00-exponent_0x00-modulus_0x02-ModExpOutput_returned_data_0x01"
                               "ModExpInput_base_0x01-exponent_0x01-modulus_0x02-ModExpOutput_returned_data_0x01"
                               "ModExpInput_base_0x02-exponent_0x01-modulus_0x03-ModExpOutput_returned_data_0x02"
                               "ModExpInput_base_0x02-exponent_0x02-modulus_0x05-ModExpOutput_returned_data_0x04")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-~A]"
                         prefix
                         fork
                         name))
           (loop for length in '("0x10000000" "0x20000000"
                                 "0x40000000" "0x80000000")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-large-exponent-length-~A-out-of-gas]"
                         prefix
                         fork
                         length))
           (loop for length in '("0x20000020" "0x40000020"
                                 "0x80000020" "0xffffffff")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-large-modulus-length-~A-out-of-gas]"
                         prefix
                         fork
                         length))
           (loop for (modulus-length ctz)
                   in '((136 40) (16 8) (24 16) (264 48) (40 24) (72 32))
                 collect
                 (format nil
                         "~A[fork_~A-state_test-mod-~D-even-ctz-~D]"
                         prefix
                         fork
                         modulus-length
                         ctz))))))

(defun phase-a-eest-bn254-gas-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "byzantium/eip196_ec_add_mul/test_gas_costs.json/tests/byzantium/eip196_ec_add_mul/test_gas.py::test_gas_costs"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for precompile in '("ecadd" "ecmul")
                 nconc
                 (loop for enough-gas in '("False" "True")
                       collect
                       (format nil
                               "~A[fork_~A-state_test-enough_gas_~A-~A]"
                               prefix
                               fork
                               enough-gas
                               precompile)))))
   (let ((prefix
           "byzantium/eip197_ec_pairing/test_gas_costs.json/tests/byzantium/eip197_ec_pairing/test_gas.py::test_gas_costs"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for enough-gas in '("False" "True")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-enough_gas_~A-ecpairing]"
                         prefix
                         fork
                         enough-gas))))))

(defun phase-a-eest-blake2f-state-test-v5.4.0-case-names ()
  (let ((base-prefix
          "istanbul/eip152_blake2/test_blake2b.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b")
        (gas-prefix
          "istanbul/eip152_blake2/test_blake2b_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_gas_limit")
        (invalid-gas-prefix
          "istanbul/eip152_blake2/test_blake2b_invalid_gas.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_invalid_gas")
        (large-gas-prefix
          "istanbul/eip152_blake2/test_blake2b_large_gas_limit.json/tests/istanbul/eip152_blake2/test_blake2.py::test_blake2b_large_gas_limit"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (append
           (list
            (format nil
                    "istanbul/eip152_blake2/test_blake2_precompile_delegatecall.json/tests/istanbul/eip152_blake2/test_blake2_delegatecall.py::test_blake2_precompile_delegatecall[fork_~A-state_test]"
                    fork))
           (loop for name in '("EIP-152-RFC-7693-zero-input"
                               "empty-input"
                               "invalid-final-block-flag-value-0x02"
                               "invalid-rounds-length-long"
                               "invalid-rounds-length-short"
                               "oog-rounds-4294967295"
                               "valid-different-message-offset-0x05"
                               "valid-false-final-block-flag"
                               "valid-rounds-0"
                               "valid-rounds-1"
                               "valid-rounds-1024"
                               "valid-rounds-1024-offset-0x10"
                               "valid-rounds-12"
                               "valid-rounds-128"
                               "valid-rounds-128-offset-0x10"
                               "valid-rounds-16"
                               "valid-rounds-16-offset-0x10"
                               "valid-rounds-16-offset-0x78"
                               "valid-rounds-256"
                               "valid-rounds-256-offset-0x10"
                               "valid-rounds-32"
                               "valid-rounds-32-offset-0x10"
                               "valid-rounds-32-offset-0x78"
                               "valid-rounds-512"
                               "valid-rounds-512-offset-0x10"
                               "valid-rounds-64"
                               "valid-rounds-64-offset-0x10"
                               "valid-rounds-64-offset-0x78")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-~A-call_opcode_CALL]"
                         base-prefix
                         fork
                         name))
           (loop for gas-limit in '("0x07270e00" "110000" "200000" "90000")
                 nconc
                 (loop for name in '("EIP-152-case3-data4-gas-limit"
                                     "EIP-152-case4-data5-gas-limit"
                                     "EIP-152-case5-data6-gas-limit"
                                     "EIP-152-case6-data7-gas-limit"
                                     "EIP-152-case7-data8-gas-limit")
                       nconc
                       (loop for call-opcode in '("CALLCODE" "CALL")
                             collect
                             (format nil
                                     "~A[fork_~A-gas_limit_~A-state_test-~A-call_opcode_~A]"
                                     gas-prefix
                                     fork
                                     gas-limit
                                     name
                                     call-opcode))))
           (loop for data in '("data0" "data1" "data10" "data2" "data3" "data9")
                 nconc
                 (loop for gas-limit in '("110000" "200000" "90000")
                       nconc
                       (loop for call-opcode in '("CALLCODE" "CALL")
                             collect
                             (format nil
                                     "~A[fork_~A-state_test-EIP-152-case1-~A-invalid-low-gas-gas_limit_~A-call_opcode_~A]"
                                     invalid-gas-prefix
                                     fork
                                     data
                                     gas-limit
                                     call-opcode))))
           (loop for name in '("EIP-152-case0-data0-large-gas-limit"
                               "EIP-152-case2-data1-large-gas-limit"
                               "EIP-152-case2-data2-large-gas-limit"
                               "EIP-152-case2-data3-large-gas-limit"
                               "EIP-152-case9-data10-large-gas-limit"
                               "EIP-152-modified-case8-data9-large-gas-limit")
                 nconc
                 (loop for call-opcode in '("CALLCODE" "CALL")
                       collect
                       (format nil
                               "~A[fork_~A-gas_limit_0x07270e00-state_test-~A-call_opcode_~A]"
                               large-gas-prefix
                               fork
                               name
                               call-opcode)))))))

(defun phase-a-eest-identity-precompile-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "frontier/identity_precompile/test_call_identity_precompile.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for identity in '("identity_0"
                                   "identity_1"
                                   "identity_1_nonzerovalue"
                                   "identity_1_nonzerovalue_insufficient_balance"
                                   "identity_2"
                                   "identity_3"
                                   "identity_4"
                                   "identity_4_exact_gas"
                                   "identity_4_insufficient_gas")
                 nconc
                 (loop for call-type in '("CALLCODE" "CALL")
                       collect
                       (format nil
                               "~A[fork_~A-state_test-~A-call_type_~A]"
                               prefix
                               fork
                               identity
                               call-type)))))
   (let ((prefix
           "frontier/identity_precompile/test_call_identity_precompile_large_params.json/tests/frontier/identity_precompile/test_identity.py::test_call_identity_precompile_large_params"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for identity in '("identity_5" "identity_6")
                 nconc
                 (loop for call-type in '("CALLCODE" "CALL")
                       collect
                       (format nil
                               "~A[fork_~A-state_test-tx_gas_limit_10000000-~A-call_type_~A]"
                               prefix
                               fork
                               identity
                               call-type)))))
   (let ((prefix
           "frontier/identity_precompile/test_identity_precompile_returndata.json/tests/frontier/identity_precompile/test_identity_returndatasize.py::test_identity_precompile_returndata"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for output-size in '("output_size_greater_than_input"
                                      "output_size_less_than_input")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-~A]"
                         prefix
                         fork
                         output-size))))))

(defun phase-a-eest-identity-return-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "homestead/identity_precompile/test_identity_return_buffer_modify.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_buffer_modify"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for call-opcode in '("CALL"
                                      "CALLCODE"
                                      "DELEGATECALL"
                                      "STATICCALL")
                 collect
                 (format nil
                         "~A[fork_~A-call_opcode_~A-evm_code_type_LEGACY-state_test]"
                         prefix
                         fork
                         call-opcode))))
   (let ((prefix
           "homestead/identity_precompile/test_identity_return_overwrite.json/tests/homestead/identity_precompile/test_identity.py::test_identity_return_overwrite"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for call-opcode in '("CALL"
                                      "CALLCODE"
                                      "DELEGATECALL"
                                      "STATICCALL")
                 collect
                 (format nil
                         "~A[fork_~A-call_opcode_~A-evm_code_type_LEGACY-state_test]"
                         prefix
                         fork
                         call-opcode))))))

(defun phase-a-eest-create-boundary-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "frontier/create/test_create_deposit_oog.json/tests/frontier/create/test_create_deposit_oog.py::test_create_deposit_oog"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for create-opcode in '("CREATE" "CREATE2")
                 collect
                 (format nil
                         "~A[fork_~A-create_opcode_~A-evm_code_type_LEGACY-state_test]"
                         prefix
                         fork
                         create-opcode))))
   (let ((prefix
           "frontier/create/test_create_suicide_during_transaction_create.json/tests/frontier/create/test_create_suicide_during_init.py::test_create_suicide_during_transaction_create"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (append
            (loop for operation in '("Operation.SUICIDE"
                                     "Operation.SUICIDE_TO_ITSELF")
                  nconc
                  (loop for transaction-create in '("False" "True")
                        collect
                        (format nil
                                "~A[fork_~A-create_opcode_CREATE-evm_code_type_LEGACY-state_test-operation_~A-transaction_create_~A]"
                                prefix
                                fork
                                operation
                                transaction-create)))
            (loop for operation in '("Operation.SUICIDE"
                                     "Operation.SUICIDE_TO_ITSELF")
                  collect
                  (format nil
                          "~A[fork_~A-create_opcode_CREATE2-evm_code_type_LEGACY-state_test-operation_~A-transaction_create_False]"
                          prefix
                          fork
                          operation)))))
   (let ((prefix
           "frontier/create/test_create_suicide_store.json/tests/frontier/create/test_create_suicide_store.py::test_create_suicide_store"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for create-opcode in '("CREATE" "CREATE2")
                 collect
                 (format nil
                         "~A[fork_~A-create_opcode_~A-evm_code_type_LEGACY-state_test]"
                         prefix
                         fork
                         create-opcode))))))

(defun phase-a-eest-create-collision-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "paris/eip7610_create_collision/test_init_collision_create_opcode.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_opcode"))
     (loop for opcode in '("CREATE" "CREATE2")
           nconc
           (loop for collision in '("non-empty-balance"
                                    "non-empty-code"
                                    "non-empty-nonce")
                 nconc
                 (loop for initcode in '("correct-initcode"
                                         "oog-initcode"
                                         "revert-initcode")
                       collect
                       (format nil
                               "~A[fork_Shanghai-state_test-opcode_~A-~A-~A]"
                               prefix
                               opcode
                               collision
                               initcode)))))
   (let ((prefix
           "paris/eip7610_create_collision/test_init_collision_create_tx.json/tests/paris/eip7610_create_collision/test_initcollision.py::test_init_collision_create_tx"))
     (loop for tx-type in '("0" "1" "2")
           nconc
           (loop for collision in '("non-empty-balance"
                                    "non-empty-code"
                                    "non-empty-nonce")
                 nconc
                 (loop for initcode in '("correct-initcode"
                                         "oog-initcode"
                                         "revert-initcode")
                       collect
                       (format nil
                               "~A[fork_Shanghai-tx_type_~A-state_test-~A-~A]"
                               prefix
                               tx-type
                               collision
                               initcode)))))))

(defun phase-a-eest-core-boundary-state-test-v5.4.0-case-names ()
  (append
   (let ((prefix
           "berlin/eip2929_gas_cost_increases/test_call_insufficient_balance.json/tests/berlin/eip2929_gas_cost_increases/test_call.py::test_call_insufficient_balance"))
     (loop for fork in '("London" "Shanghai")
           collect
           (format nil
                   "~A[fork_~A-state_test]"
                   prefix
                   fork)))
   (let ((prefix
           "constantinople/eip145_bitwise_shift/test_combinations.json/tests/constantinople/eip145_bitwise_shift/test_shift_combinations.py::test_combinations"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for opcode in '("sar" "shl" "shr")
                 collect
                 (format nil
                         "~A[fork_~A-state_test-~A]"
                         prefix
                         fork
                         opcode))))
   (let ((prefix
           "frontier/opcodes/test_call_memory_expands_on_early_revert.json/tests/frontier/opcodes/test_call.py::test_call_memory_expands_on_early_revert"))
     (loop for fork in '("London" "Shanghai")
           collect
           (format nil
                   "~A[fork_~A-state_test]"
                   prefix
                   fork)))
   (let ((prefix
           "istanbul/eip1344_chainid/test_chainid.json/tests/istanbul/eip1344_chainid/test_chainid.py::test_chainid"))
     (loop for fork in '("London" "Shanghai")
           nconc
           (loop for tx-type in '("0" "1" "2")
                 collect
                 (format nil
                         "~A[fork_~A-typed_transaction_~A-state_test]"
                         prefix
                         fork
                         tx-type))))))

(defun phase-a-eest-value-transfer-gas-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_value_transfer_gas_calculation.json/tests/frontier/opcodes/test_call_and_callcode_gas_calculation.py::test_value_transfer_gas_calculation"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for gas-shortage in '("0" "1")
                nconc
                (loop for callee-opcode in '("CALLCODE"
                                             "CALL"
                                             "DELEGATECALL"
                                             "STATICCALL")
                      collect
                      (format nil
                              "~A[fork_~A-state_test-gas_shortage_~A-callee_opcode_~A]"
                              prefix
                              fork
                              gas-shortage
                              callee-opcode))))))

(defun phase-a-eest-calldatacopy-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_calldatacopy.json/tests/frontier/opcodes/test_calldatacopy.py::test_calldatacopy"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for case in '("cdc 0 0 0"
                              "cdc 0 1 0"
                              "cdc 0 1 1"
                              "cdc 0 1 2"
                              "cdc 0 neg6 9"
                              "cdc 0 neg6 ff"
                              "sec"
                              "underflow")
                collect
                (format nil
                        "~A[fork_~A-state_test-~A]"
                        prefix
                        fork
                        case)))))

(defun phase-a-eest-calldataload-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_calldataload.json/tests/frontier/opcodes/test_calldataload.py::test_calldataload"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for source in '("contract" "tx")
                nconc
                (loop for case in '("34_bytes" "two_bytes" "word_n_byte")
                      collect
                      (format nil
                              "~A[fork_~A-state_test-calldata_source_~A-~A]"
                              prefix
                              fork
                              source
                              case))))))

(defun phase-a-eest-calldatasize-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_calldatasize.json/tests/frontier/opcodes/test_calldatasize.py::test_calldatasize"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for source in '("contract" "tx")
                nconc
                (loop for size in '("0" "16" "257" "2" "33")
                      collect
                      (format nil
                              "~A[fork_~A-state_test-calldata_source_~A-args_size_~A]"
                              prefix
                              fork
                              source
                              size))))))

(defparameter +phase-a-eest-state-test-v5.4.0-case-names+
  (append
   '("berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_London-state_test-account_warm_False-storage_key_warm_False]"
    "berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_London-state_test-account_warm_True-storage_key_warm_False]"
    "berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_London-state_test-account_warm_True-storage_key_warm_True]"
    "berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-state_test-account_warm_False-storage_key_warm_False]"
    "berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-state_test-account_warm_True-storage_key_warm_False]"
    "berlin/eip2930_access_list/test_account_storage_warm_cold_state.json/tests/berlin/eip2930_access_list/test_acl.py::test_account_storage_warm_cold_state[fork_Shanghai-state_test-account_warm_True-storage_key_warm_True]"
    "berlin/eip2930_access_list/test_eip2930_tx_validity.json/tests/berlin/eip2930_access_list/test_tx_type.py::test_eip2930_tx_validity[fork_London-valid-state_test]"
    "berlin/eip2930_access_list/test_eip2930_tx_validity.json/tests/berlin/eip2930_access_list/test_tx_type.py::test_eip2930_tx_validity[fork_Shanghai-valid-state_test]"
    "berlin/eip2930_access_list/test_repeated_address_acl.json/tests/berlin/eip2930_access_list/test_acl.py::test_repeated_address_acl[fork_London-state_test]"
    "berlin/eip2930_access_list/test_repeated_address_acl.json/tests/berlin/eip2930_access_list/test_acl.py::test_repeated_address_acl[fork_Shanghai-state_test]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-empty_access_list]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-multiple_addresses_first_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-multiple_addresses_first_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-multiple_addresses_second_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-multiple_addresses_second_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-multiple_addresses_second_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-repeated_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-repeated_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-repeated_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-single_address_multiple_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-single_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-enough_gas-single_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-empty_access_list]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-multiple_addresses_first_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-multiple_addresses_first_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-multiple_addresses_second_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-multiple_addresses_second_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-multiple_addresses_second_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-repeated_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-repeated_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-repeated_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-single_address_multiple_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-single_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_London-state_test-not_enough_gas-single_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-empty_access_list]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-multiple_addresses_first_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-multiple_addresses_first_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-multiple_addresses_second_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-multiple_addresses_second_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-multiple_addresses_second_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-repeated_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-repeated_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-repeated_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-single_address_multiple_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-single_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-enough_gas-single_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-empty_access_list]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-multiple_addresses_first_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-multiple_addresses_first_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-multiple_addresses_second_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-multiple_addresses_second_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-multiple_addresses_second_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-repeated_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-repeated_address_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-repeated_address_single_storage_key]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-single_address_multiple_no_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-single_address_multiple_storage_keys]"
    "berlin/eip2930_access_list/test_transaction_intrinsic_gas_cost.json/tests/berlin/eip2930_access_list/test_acl.py::test_transaction_intrinsic_gas_cost[fork_Shanghai-state_test-not_enough_gas-single_address_single_storage_key]"
    "london/eip1559_fee_market_change/test_eip1559_tx_validity.json/tests/london/eip1559_fee_market_change/test_tx_type.py::test_eip1559_tx_validity[fork_London-valid-state_test]"
    "london/eip1559_fee_market_change/test_eip1559_tx_validity.json/tests/london/eip1559_fee_market_change/test_tx_type.py::test_eip1559_tx_validity[fork_Shanghai-valid-state_test]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-CALL-insufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-CALL-sufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-CALLCODE-insufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-CALLCODE-sufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-DELEGATECALL-insufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-DELEGATECALL-sufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-STATICCALL-insufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_call_out_of_gas.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_call_out_of_gas[fork_Shanghai-state_test-STATICCALL-sufficient_gas]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-EXTCODECOPY]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-EXTCODEHASH]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-EXTCODESIZE]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-gas_cost]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-storage_overwrite]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-before_jumpdest]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-fill_stack]"
    "shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-state_test-call]"
    "shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-state_test-callcode]"
    "shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-state_test-delegatecall]"
    "shanghai/eip3855_push0/test_push0_contract_during_call_contexts.json/tests/shanghai/eip3855_push0/test_push0.py::TestPush0CallContext::test_push0_contract_during_call_contexts[fork_Shanghai-state_test-staticcall]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-key_sstore]"
    "shanghai/eip3855_push0/test_push0_contracts.json/tests/shanghai/eip3855_push0/test_push0.py::test_push0_contracts[fork_Shanghai-state_test-stack_overflow]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-BALANCE]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-CALL]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-CALLCODE]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-DELEGATECALL]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-EXTCODECOPY]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-EXTCODEHASH]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-EXTCODESIZE]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_London-state_test-STATICCALL]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-BALANCE]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-CALL]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-CALLCODE]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-DELEGATECALL]"
    "shanghai/eip3651_warm_coinbase/test_warm_coinbase_gas_usage.json/tests/shanghai/eip3651_warm_coinbase/test_warm_coinbase.py::test_warm_coinbase_gas_usage[fork_Shanghai-state_test-STATICCALL]")
   (phase-a-eest-create2-returndata-state-test-v5.4.0-case-names)
   (phase-a-eest-call-large-offset-state-test-v5.4.0-case-names)
   (phase-a-eest-modexp-state-test-v5.4.0-case-names)
   (phase-a-eest-bn254-gas-state-test-v5.4.0-case-names)
   (phase-a-eest-blake2f-state-test-v5.4.0-case-names)
   (phase-a-eest-identity-precompile-state-test-v5.4.0-case-names)
   (phase-a-eest-identity-return-state-test-v5.4.0-case-names)
   (phase-a-eest-create-boundary-state-test-v5.4.0-case-names)
   (phase-a-eest-create-collision-state-test-v5.4.0-case-names)
   (phase-a-eest-core-boundary-state-test-v5.4.0-case-names)
   (phase-a-eest-value-transfer-gas-state-test-v5.4.0-case-names)
   (phase-a-eest-calldatacopy-state-test-v5.4.0-case-names)
   (phase-a-eest-calldataload-state-test-v5.4.0-case-names)
   (phase-a-eest-calldatasize-state-test-v5.4.0-case-names)))

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

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

(defun eest-state-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST state test"))

(defun eest-state-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST state test"))

(defun validate-eest-blockchain-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST blockchain test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST blockchain test case name in ~A must be a string"
                 source))
        (when (blank-string-p name)
          (error "EEST blockchain test case name in ~A must be present"
                 source))
        (when (gethash name seen)
          (error "EEST blockchain test file ~A has duplicate case name ~A"
                 source name))
        (unless (listp case)
          (error "EEST blockchain test case ~A must be a JSON object"
                 name))
        (setf (gethash name seen) t)))))

(defun validate-eest-state-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST state test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST state test case name in ~A must be a string" source))
        (when (blank-string-p name)
          (error "EEST state test case name in ~A must be present" source))
        (when (gethash name seen)
          (error "EEST state test file ~A has duplicate case name ~A"
                 source
                 name))
        (unless (listp case)
          (error "EEST state test case ~A must be a JSON object" name))
        (validate-fixture-object-fields
         case
         +eest-state-test-case-fields+
         (format nil "EEST state test case ~A" name))
        (dolist (field '("env" "pre" "transaction" "post"))
          (fixture-required-field case field))
        (setf (gethash name seen) t)))))

(defun normalize-eest-blockchain-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun normalize-eest-state-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun eest-blockchain-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun eest-state-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun load-eest-blockchain-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-blockchain-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-blockchain-root-case-name
                  root
                  path
                  (car entry)
                  singleton-p)))
           (unless (eest-blockchain-selector-source-style-p source-name)
             (error "EEST blockchain source name ~A must be source-style"
                    source-name))
           (normalize-eest-blockchain-test-case source-name (cdr entry))))
       entries))))

(defun load-eest-state-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-state-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-state-root-case-name root path (car entry) singleton-p)))
           (unless (eest-state-selector-source-style-p source-name)
             (error "EEST state source name ~A must be source-style"
                    source-name))
           (normalize-eest-state-test-case source-name (cdr entry))))
       entries))))

(defun eest-selector-relative-json-path (name label)
  (let ((json-position (search ".json" name :test #'char-equal)))
    (unless json-position
      (error "~A selector ~A must include a JSON file" label name))
    (subseq name 0 (+ json-position 5))))

(defun eest-selector-root-paths (root names label)
  (let ((seen (make-hash-table :test 'equal))
        (paths nil))
    (dolist (name names (nreverse paths))
      (let* ((relative (eest-selector-relative-json-path name label))
             (path (merge-pathnames relative root)))
        (unless (probe-file path)
          (error "~A selector ~A references missing fixture file ~A"
                 label name relative))
        (unless (gethash relative seen)
          (setf (gethash relative seen) t)
          (push path paths))))))

(defun validate-eest-blockchain-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST blockchain"
   :allow-nested-case-name t))

(defun validate-eest-state-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST state"
   :allow-nested-case-name t))

(defun eest-blockchain-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun eest-state-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun load-eest-blockchain-test-root-cases (root &key names)
  (when names
    (validate-eest-blockchain-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (if names
                         (eest-selector-root-paths
                          root names "EEST blockchain test")
                         (eest-blockchain-test-root-json-paths root))
         append (load-eest-blockchain-test-root-file-cases root path))
   names
   "EEST blockchain test"))

(defun load-eest-state-test-root-cases (root &key names)
  (when names
    (validate-eest-state-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (if names
                         (eest-selector-root-paths root names "EEST state test")
                         (eest-state-test-root-json-paths root))
         append (load-eest-state-test-root-file-cases root path))
   names
   "EEST state test"))

(defun execution-spec-tests-discovery-path-p
    (root path feature-directories max-file-bytes)
  (let* ((relative (enough-namestring (truename path) (truename root)))
         (slash (position #\/ relative))
         (feature-directory (if slash
                                (subseq relative 0 slash)
                                relative)))
    (and (member (string-downcase feature-directory)
                 feature-directories
                 :test #'string=)
         (<= (eest-fixture-file-byte-size path) max-file-bytes))))

(defun phase-a-eest-blockchain-replay-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   +phase-a-eest-blockchain-replay-discovery-feature-directories+
   +phase-a-eest-blockchain-replay-discovery-max-file-bytes+))

(defun phase-a-eest-state-test-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   +phase-a-eest-state-test-discovery-feature-directories+
   +phase-a-eest-state-test-discovery-max-file-bytes+))

(defun eest-fixture-file-byte-size (path)
  (with-open-file (stream path :direction :input
                               :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun load-phase-a-eest-blockchain-discovery-cases (root)
  (loop for path in (eest-blockchain-test-root-json-paths root)
        when (phase-a-eest-blockchain-replay-discovery-path-p root path)
          append (load-eest-blockchain-test-root-file-cases root path)))

(defun load-phase-a-eest-state-discovery-cases (root)
  (loop for path in (eest-state-test-root-json-paths root)
        when (phase-a-eest-state-test-discovery-path-p root path)
          append (load-eest-state-test-root-file-cases root path)))

(defun eest-state-test-case-fork-names (case)
  (let ((post (fixture-required-field
               (fixture-required-field case "fixture")
               "post")))
    (unless (listp post)
      (error "EEST state test case ~A post must be a JSON object"
             (fixture-required-field case "name")))
    (sort (mapcar #'car post) #'string<)))

(defun eest-state-test-transaction-combination-count (case)
  (let ((transaction (fixture-required-field
                      (fixture-required-field case "fixture")
                      "transaction")))
    (validate-fixture-object-fields
     transaction
     +eest-state-test-transaction-fields+
     (format nil "EEST state test case ~A transaction"
             (fixture-required-field case "name")))
    (dolist (field '("data" "gasLimit" "value"))
      (let ((values (fixture-required-field transaction field)))
        (unless (and (listp values) values)
          (error "EEST state test case ~A transaction ~A must be a non-empty JSON array"
                 (fixture-required-field case "name")
                 field))))
    (let ((access-lists (fixture-object-field transaction "accessLists")))
      (when (fixture-field-present-p transaction "accessLists")
        (unless (and (listp access-lists) access-lists)
          (error "EEST state test case ~A transaction accessLists must be a non-empty JSON array"
                 (fixture-required-field case "name"))))
      (* (length (fixture-required-field transaction "data"))
         (length (fixture-required-field transaction "gasLimit"))
         (length (fixture-required-field transaction "value"))
         (if (fixture-field-present-p transaction "accessLists")
             (length access-lists)
             1)))))

(defun phase-a-eest-state-materializable-case-p (case)
  (handler-case
      (and (intersection +phase-a-eest-state-test-supported-forks+
                         (eest-state-test-case-fork-names case)
                         :test #'string=)
           (plusp (eest-state-test-transaction-combination-count case)))
    (error () nil)))

(defun discover-phase-a-eest-state-test-selectors (root)
  (loop for case in (load-phase-a-eest-state-discovery-cases root)
        when (phase-a-eest-state-materializable-case-p case)
          collect (fixture-required-field case "name")))

(defun eest-state-test-root-summary (cases)
  (let ((fork-counts (make-hash-table :test 'equal))
        (combination-count 0))
    (dolist (case cases)
      (dolist (fork (eest-state-test-case-fork-names case))
        (incf (gethash fork fork-counts 0)))
      (incf combination-count
            (eest-state-test-transaction-combination-count case)))
    (list
     (cons "count" (length cases))
     (cons "names" (mapcar (lambda (case)
                             (fixture-required-field case "name"))
                           cases))
     (cons "forkCounts"
           (sort
            (loop for key being the hash-keys of fork-counts
                  using (hash-value count)
                  collect (cons key count))
            #'string<
            :key #'car))
     (cons "transactionCombinationCount" combination-count))))

(defun report-eest-state-test-root-case (case)
  (list (cons "name" (fixture-required-field case "name"))
        (cons "forks" (eest-state-test-case-fork-names case))
        (cons "transactionCombinations"
              (eest-state-test-transaction-combination-count case))))

(defun eest-fixture-trim-string (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(defun eest-fixture-split-string (value delimiter)
  (let ((parts '())
        (start 0))
    (loop
      for position = (position delimiter value :start start)
      do (push (subseq value start position) parts)
      if position
        do (setf start (1+ position))
      else
        do (return (nreverse parts)))))

(defun parse-phase-a-eest-state-test-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST state test selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-state-test-selectors nil))
  (let ((selectors
          (mapcar #'eest-fixture-trim-string
                  (eest-fixture-split-string value #\,))))
    (validate-eest-state-selector-list selectors)
    selectors))

(defun phase-a-eest-state-test-env-selectors (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-state-test-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string" +phase-a-eest-state-test-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-state-test-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST state_tests root"
                +phase-a-eest-state-test-selectors-env+))
       (let ((selectors (discover-phase-a-eest-state-test-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A state_tests selectors"
                  +phase-a-eest-state-test-selectors-env+))
         selectors))
      (t
       (parse-phase-a-eest-state-test-selectors value)))))

(defun phase-a-eest-state-test-selector-string (selectors &key limit)
  (validate-eest-state-selector-list selectors)
  (let ((bounded-selectors
          (if (and limit (> (length selectors) limit))
              (subseq selectors 0 limit)
              selectors)))
    (format nil "~{~A~^,~}" bounded-selectors)))

(defun validate-phase-a-eest-state-test-summary
    (cases &key (expected-names +phase-a-eest-state-test-case-names+))
  (validate-eest-state-selector-list expected-names)
  (unless (and (listp cases) cases)
    (error "Phase A EEST state_tests cases must be a non-empty list"))
  (let* ((summary (eest-state-test-root-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (combination-count
           (fixture-required-field summary "transactionCombinationCount")))
    (unless (= count (length expected-names))
      (error "Phase A EEST state_tests selector count ~A loaded ~A cases"
             (length expected-names)
             count))
    (unless (equal names expected-names)
      (error "Phase A EEST state_tests names ~S do not match selectors ~S"
             names
             expected-names))
    (dolist (case cases)
      (unless (intersection +phase-a-eest-state-test-supported-forks+
                            (eest-state-test-case-fork-names case)
                            :test #'string=)
        (error "Phase A EEST state_tests case ~A has no supported fork"
               (fixture-required-field case "name"))))
    (unless (plusp combination-count)
      (error "Phase A EEST state_tests replay must include transaction combinations"))
    summary))

(defun load-phase-a-eest-state-test-root-cases
    (root &key (expected-names +phase-a-eest-state-test-case-names+))
  (let ((cases (load-eest-state-test-root-cases
                root
                :names expected-names)))
    (validate-phase-a-eest-state-test-summary
     cases
     :expected-names expected-names)
    cases))

(defun load-optional-phase-a-eest-state-test-root-cases ()
  (with-execution-spec-tests-state-test-root (root)
    (let ((expected-names (phase-a-eest-state-test-env-selectors root)))
      (unless expected-names
        (let ((candidates (discover-phase-a-eest-state-test-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to auto or comma-separated selectors such as ~A to run Phase A state_tests replay against this external root"
                       +phase-a-eest-state-test-selectors-env+
                       (phase-a-eest-state-test-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selectors to run Phase A state_tests replay against an external root"
                       +phase-a-eest-state-test-selectors-env+)))))
      (load-phase-a-eest-state-test-root-cases
       root
       :expected-names expected-names))))

(defun parse-phase-a-eest-blockchain-replay-selector (value)
  (let* ((selector (eest-fixture-trim-string value))
         (separator (position #\= selector)))
    (unless separator
      (error "Phase A EEST blockchain replay selector ~A must use name=kind"
             selector))
    (let ((name (eest-fixture-trim-string
                 (subseq selector 0 separator)))
          (kind (eest-fixture-trim-string
                 (subseq selector (1+ separator)))))
      (validate-eest-blockchain-selector-list (list name))
      (unless (member kind
                      +phase-a-eest-blockchain-replay-materialization-kind-names+
                      :test #'string=)
        (error "Phase A EEST blockchain replay selector ~A has unsupported materialization kind ~A"
               name
               kind))
      (cons name kind))))

(defun parse-phase-a-eest-blockchain-replay-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST blockchain replay selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-blockchain-replay-selectors nil))
  (let ((selectors
          (mapcar #'parse-phase-a-eest-blockchain-replay-selector
                  (eest-fixture-split-string value #\,))))
    (validate-eest-blockchain-selector-list (mapcar #'car selectors))
    selectors))

(defun phase-a-eest-blockchain-replay-env-materialization-kinds
    (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-blockchain-replay-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string"
              +phase-a-eest-blockchain-replay-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-blockchain-replay-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+))
       (let ((selectors
               (discover-phase-a-eest-blockchain-replay-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A blockchain replay selectors"
                  +phase-a-eest-blockchain-replay-selectors-env+))
         selectors))
      ((string= +phase-a-eest-blockchain-replay-pinned-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=~A requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+
                +phase-a-eest-blockchain-replay-pinned-selector+))
       (phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
        root))
      (t
       (parse-phase-a-eest-blockchain-replay-selectors value)))))

(defun phase-a-eest-blockchain-replay-selector-string
    (selectors &key limit)
  (validate-eest-blockchain-selector-list (mapcar #'car selectors))
  (let* ((bounded-selectors
           (if (and limit (> (length selectors) limit))
               (subseq selectors 0 limit)
               selectors))
         (entries
           (mapcar (lambda (selector)
                     (format nil "~A=~A" (car selector) (cdr selector)))
                   bounded-selectors)))
    (format nil "~{~A~^,~}" entries)))

(defun eest-blockchain-replay-materialization-kind (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (cond
      ((fixture-field-present-p fixture "engineNewPayloadV2")
       "engineNewPayloadV2")
      ((and (fixture-field-present-p fixture "engineNewPayloads")
            (eest-blockchain-engine-newpayloads-v2-entry case))
       "engineNewPayloadV2")
      ((let ((blocks (fixture-object-field fixture "blocks")))
         (and (listp blocks)
              blocks
              (fixture-field-present-p (first blocks) "rlp")))
       "blockRlp")
      (t
       "unsupported"))))

(defun phase-a-eest-blockchain-replay-materializable-kind (case)
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (kind (eest-blockchain-replay-materialization-kind case)))
        (when (and (stringp network)
                   (string= "Shanghai" network))
          (cond
            ((string= "engineNewPayloadV2" kind)
             (if (fixture-field-present-p fixture "engineNewPayloadV2")
                 (validate-eest-blockchain-engine-newpayload-v2-case case)
                 (validate-eest-blockchain-engine-newpayloads-v2-case case))
             kind)
            ((string= "blockRlp" kind)
             (validate-eest-blockchain-standard-newpayload-v2-case case)
             kind)
            (t nil))))
    (error () nil)))

(defun discover-phase-a-eest-blockchain-replay-selectors (root)
  (loop for case in (load-phase-a-eest-blockchain-discovery-cases root)
        for kind = (phase-a-eest-blockchain-replay-materializable-kind case)
        when kind
          collect (cons (fixture-required-field case "name") kind)))

(defun validate-phase-a-eest-blockchain-discovered-replay-selectors
    (root expected-kinds)
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (let ((discovered (discover-phase-a-eest-blockchain-replay-selectors root)))
    (unless (equal discovered expected-kinds)
      (error "Discovered Phase A EEST blockchain replay selectors ~S do not match pinned selectors ~S"
             discovered
             expected-kinds))
    discovered))

(defun phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
    (root)
  (declare (ignore root))
  (validate-eest-blockchain-selector-list
   (mapcar #'car +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+))
  +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+)

(defun eest-blockchain-count-by-string (values)
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (value values)
      (unless (stringp value)
        (error "EEST blockchain replay summary value must be a string"))
      (incf (gethash value counts 0)))
    (sort
     (loop for key being the hash-keys of counts
           using (hash-value count)
           collect (cons key count))
     #'string<
     :key #'car)))

(defun eest-blockchain-replay-block-count (case)
  (let ((blocks (fixture-object-field
                 (fixture-required-field case "fixture")
                 "blocks")))
    (unless (or (null blocks) (listp blocks))
      (error "EEST blockchain replay case ~A blocks must be a JSON array"
             (fixture-required-field case "name")))
    (length blocks)))

(defun eest-blockchain-replay-case-summary (cases)
  (list (cons "count" (length cases))
        (cons "names" (mapcar (lambda (case)
                                (fixture-required-field case "name"))
                              cases))
        (cons "networkCounts"
              (eest-blockchain-count-by-string
               (mapcar (lambda (case)
                         (fixture-required-field
                          (fixture-required-field case "fixture")
                          "network"))
                       cases)))
        (cons "materializationKindCounts"
              (eest-blockchain-count-by-string
               (mapcar #'eest-blockchain-replay-materialization-kind cases)))
        (cons "blockCount"
              (loop for case in cases
                    sum (eest-blockchain-replay-block-count case)))))

(defun validate-phase-a-eest-blockchain-replay-summary
    (cases &key
           (expected-kinds
            +phase-a-eest-blockchain-replay-materialization-kinds+))
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (unless (and (listp cases) cases)
    (error "Phase A EEST blockchain replay cases must be a non-empty list"))
  (let* ((summary (eest-blockchain-replay-case-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (network-counts (fixture-required-field summary "networkCounts"))
         (kind-counts
           (fixture-required-field summary "materializationKindCounts"))
         (block-count (fixture-required-field summary "blockCount")))
    (unless (= count (length expected-kinds))
      (error "Phase A EEST blockchain replay selector count ~A loaded ~A cases"
             (length expected-kinds)
             count))
    (unless (equal names (mapcar #'car expected-kinds))
      (error "Phase A EEST blockchain replay names ~S do not match selectors ~S"
             names
             (mapcar #'car expected-kinds)))
    (dolist (expected expected-kinds)
      (let* ((name (car expected))
             (kind (cdr expected))
             (case (find name cases
                         :key (lambda (entry)
                                (fixture-required-field entry "name"))
                         :test #'string=)))
        (unless case
          (error "Phase A EEST blockchain replay selector ~A was not loaded"
                 name))
        (unless (string= kind (eest-blockchain-replay-materialization-kind case))
          (error "Phase A EEST blockchain replay selector ~A expected ~A but found ~A"
                 name
                 kind
                 (eest-blockchain-replay-materialization-kind case)))))
    (unless (= count (or (fixture-object-field network-counts "Shanghai") 0))
      (error "Phase A EEST blockchain replay must load only Shanghai cases"))
    (unless (plusp (or (fixture-object-field kind-counts "engineNewPayloadV2")
                       0))
      (error "Phase A EEST blockchain replay is missing embedded Engine coverage"))
    (when (find "blockRlp" expected-kinds :key #'cdr :test #'string=)
      (unless (plusp (or (fixture-object-field kind-counts "blockRlp") 0))
        (error "Phase A EEST blockchain replay is missing standard block RLP coverage"))
      (unless (plusp block-count)
        (error "Phase A EEST blockchain replay is missing decoded block coverage")))
    summary))

(defun load-phase-a-eest-blockchain-replay-cases
    (root &key
          (expected-kinds
           +phase-a-eest-blockchain-replay-materialization-kinds+))
  (let ((cases (load-eest-blockchain-test-root-cases
                root
                :names (mapcar #'car expected-kinds))))
    (validate-phase-a-eest-blockchain-replay-summary
     cases
     :expected-kinds expected-kinds)
    cases))

(defun load-optional-phase-a-eest-blockchain-replay-cases ()
  (with-execution-spec-tests-blockchain-test-root (root)
    (let ((expected-kinds
            (phase-a-eest-blockchain-replay-env-materialization-kinds
             root)))
      (unless expected-kinds
        (let ((candidates
                (discover-phase-a-eest-blockchain-replay-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to ~A, auto, or comma-separated selector=kind pairs such as ~A to run Phase A blockchain replay against this external root"
                       +phase-a-eest-blockchain-replay-selectors-env+
                       +phase-a-eest-blockchain-replay-pinned-selector+
                       (phase-a-eest-blockchain-replay-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selector=kind pairs to run Phase A blockchain replay against an external root"
                       +phase-a-eest-blockchain-replay-selectors-env+)))))
      (load-phase-a-eest-blockchain-replay-cases
       root
       :expected-kinds expected-kinds))))

(defun report-eest-blockchain-test-root-case (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "format"
                (or (fixture-object-field fixture "fixture-format")
                    "blockchain_test"))
          (cons "network" (fixture-object-field fixture "network"))
          (cons "blocks" (length (fixture-object-field fixture "blocks"))))))

(defun validate-eest-blockchain-json-array-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (listp value)
      (error "~A ~A must be a JSON array" label field))
    value))

(defun validate-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (unless (fixture-field-present-p fixture "engineNewPayloadV2")
      (error "~A does not carry an embedded engineNewPayloadV2 case"
             label))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-engine-fixture-fields+
     label)
    (unless (string= "blockchain_test"
                     (fixture-required-field fixture "fixture-format"))
      (error "~A fixture-format must be blockchain_test" label))
    (validate-eest-blockchain-json-array-field fixture "blocks" label)
    (when (plusp (length (fixture-object-field fixture "blocks")))
      (error "~A replay materializer expects an embedded engineNewPayloadV2 case"
             label))
    (let ((engine (fixture-required-field fixture "engineNewPayloadV2")))
      (validate-fixture-object-fields
       engine
       +eest-blockchain-engine-newpayload-v2-fields+
       (format nil "~A engineNewPayloadV2" label))
      (dolist (field +eest-blockchain-engine-newpayload-v2-fields+)
        (fixture-required-field engine field))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "parent")
       "accounts"
       (format nil "~A parent" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "transactions"
       (format nil "~A payload" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "withdrawals"
       (format nil "~A payload" label))
      engine)))

(defun eest-blockchain-engine-newpayloads-v2-entry (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (entries (fixture-object-field fixture "engineNewPayloads")))
    (when (listp entries)
      (find "2" entries
            :key (lambda (entry)
                   (and (listp entry)
                        (fixture-object-field entry "newPayloadVersion")))
            :test #'string=))))

(defun validate-eest-blockchain-engine-newpayloads-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-engine-newpayloads-fixture-fields+
     label)
    (unless (string= "Shanghai" (fixture-required-field fixture "network"))
      (error "~A engineNewPayloads materializer currently supports Shanghai V2"
             label))
    (let ((entries (fixture-required-field fixture "engineNewPayloads")))
      (unless (and (listp entries) entries)
        (error "~A engineNewPayloads must be a non-empty JSON array" label))
      (let ((entry (eest-blockchain-engine-newpayloads-v2-entry case)))
        (unless entry
          (error "~A does not carry an engineNewPayloads V2 entry" label))
        (validate-fixture-object-fields
         entry
         +eest-blockchain-engine-newpayloads-entry-fields+
         (format nil "~A engineNewPayloads entry" label))
        (unless (string= "2" (fixture-required-field entry "newPayloadVersion"))
          (error "~A engineNewPayloads entry must be V2" label))
        (unless (string= "2" (fixture-required-field entry "forkchoiceUpdatedVersion"))
          (error "~A forkchoiceUpdatedVersion must be V2" label))
        (let ((params (fixture-required-field entry "params")))
          (unless (and (listp params) (= 1 (length params)))
            (error "~A engineNewPayloads V2 params must contain one payload"
                   label))
          (let ((payload (first params)))
            (unless (listp payload)
              (error "~A engineNewPayloads V2 payload must be a JSON object"
                     label))
            (validate-fixture-object-fields
             payload
             +eest-blockchain-rpc-payload-v2-fields+
             (format nil "~A engineNewPayloads V2 payload" label))
            (dolist (field '("parentHash" "stateRoot" "receiptsRoot"
                             "prevRandao" "blockHash"))
              (validate-eest-blockchain-hash-string
               (fixture-required-field payload field)
               (format nil "~A payload ~A" label field)))
            (validate-eest-blockchain-address-string
             (fixture-required-field payload "feeRecipient")
             (format nil "~A payload feeRecipient" label))
            (dolist (field '("blockNumber" "gasLimit" "gasUsed" "timestamp"
                             "baseFeePerGas"))
              (validate-eest-blockchain-quantity-string
               (fixture-required-field payload field)
               (format nil "~A payload ~A" label field)))
            (validate-eest-blockchain-hex-string
             (fixture-required-field payload "extraData")
             (format nil "~A payload extraData" label))
            (validate-eest-blockchain-json-array-field
             payload
             "transactions"
             (format nil "~A payload" label))
            (validate-eest-blockchain-json-array-field
             payload
             "withdrawals"
             (format nil "~A payload" label))
            (let ((last-block-hash
                    (fixture-required-field fixture "lastblockhash"))
                  (block-hash (fixture-required-field payload "blockHash")))
              (validate-eest-blockchain-hash-string
               last-block-hash
               (format nil "~A lastblockhash" label))
              (unless (string= last-block-hash block-hash)
                (error "~A lastblockhash does not match engine payload blockHash"
                       label)))
            payload))))))

(defun validate-eest-blockchain-hex-string (value label)
  (unless (stringp value)
    (error "~A must be a 0x-prefixed hex string" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (string= value (bytes-to-hex bytes))
          (error "~A must be canonical lowercase 0x-prefixed hex" label))
        value)
    (error (condition)
      (error "~A must be hex bytes: ~A" label condition))))

(defun validate-eest-blockchain-hash-string (value label)
  (validate-eest-blockchain-hex-string value label)
  (handler-case
      (hash32-from-hex value)
    (error (condition)
      (error "~A must be a 32-byte hash: ~A" label condition))))

(defun validate-eest-blockchain-address-string (value label)
  (validate-eest-blockchain-hex-string value label)
  (handler-case
      (address-from-hex value)
    (error (condition)
      (error "~A must be a 20-byte address: ~A" label condition))))

(defun validate-eest-blockchain-quantity-string (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (handler-case
      (hex-to-quantity value)
    (error (condition)
      (error "~A must be a hex quantity: ~A" label condition))))

(defun eest-blockchain-standard-required-header-field (header field label)
  (let ((value (fixture-required-field header field)))
    (validate-eest-blockchain-quantity-string
     value
     (format nil "~A ~A" label field))
    value))

(defun eest-blockchain-standard-required-address-field (header field label)
  (let ((value (fixture-required-field header field)))
    (validate-eest-blockchain-address-string
     value
     (format nil "~A ~A" label field))
    value))

(defun eest-blockchain-standard-account-entry (entry label)
  (let ((address (car entry))
        (account (cdr entry)))
    (validate-eest-blockchain-address-string
     address
     (format nil "~A pre account address" label))
    (unless (listp account)
      (error "~A pre account ~A must be a JSON object" label address))
    (let ((storage (or (fixture-object-field account "storage") '())))
      (unless (listp storage)
        (error "~A pre account ~A storage must be a JSON object"
               label address))
      (list
       (cons "address" address)
       (cons "nonce"
             (quantity-to-hex
              (hex-to-quantity
               (or (fixture-object-field account "nonce") "0x0"))))
       (cons "balance"
             (quantity-to-hex
              (hex-to-quantity
               (or (fixture-object-field account "balance") "0x0"))))
       (cons "code"
             (or (fixture-object-field account "code") "0x"))
       (cons "storage"
             (mapcar (lambda (storage-entry)
                       (cons
                        (eest-blockchain-normalized-storage-slot
                         (car storage-entry)
                         (format nil "~A pre account ~A storage key"
                                 label
                                 address))
                        (quantity-to-hex
                         (hex-to-quantity (cdr storage-entry)))))
                     storage))))))

(defun eest-blockchain-normalized-storage-slot (value label)
  (unless (stringp value)
    (error "~A must be a hex storage key" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (when (> (length bytes) 32)
          (error "~A must be at most 32 bytes" label))
        (let ((padded (make-byte-vector 32)))
          (replace padded bytes :start1 (- 32 (length bytes)))
          (hash32-to-hex (make-hash32 padded))))
    (error (condition)
      (error "~A must be hex storage key bytes: ~A" label condition))))

(defun eest-blockchain-standard-parent (fixture label)
  (let ((header (fixture-required-field fixture "genesisBlockHeader")))
    (unless (listp header)
      (error "~A genesisBlockHeader must be a JSON object" label))
    (list
     (cons "number"
           (eest-blockchain-standard-required-header-field
            header "number" label))
     (cons "gasLimit"
           (eest-blockchain-standard-required-header-field
            header "gasLimit" label))
     (cons "gasUsed"
           (eest-blockchain-standard-required-header-field
            header "gasUsed" label))
     (cons "timestamp"
           (eest-blockchain-standard-required-header-field
            header "timestamp" label))
     (cons "baseFeePerGas"
           (eest-blockchain-standard-required-header-field
            header "baseFeePerGas" label))
     (cons "feeRecipient"
           (eest-blockchain-standard-required-address-field
            header "coinbase" label))
     (cons "accounts"
           (mapcar
            (lambda (entry)
              (eest-blockchain-standard-account-entry entry label))
            (sort (copy-list (fixture-required-field fixture "pre"))
                  #'string<
                  :key #'car))))))

(defun eest-blockchain-standard-withdrawal (withdrawal)
  (list (cons "index" (quantity-to-hex (withdrawal-index withdrawal)))
        (cons "validatorIndex"
              (quantity-to-hex (withdrawal-validator-index withdrawal)))
        (cons "address" (address-to-hex (withdrawal-address withdrawal)))
        (cons "amount" (quantity-to-hex (withdrawal-amount withdrawal)))))

(defun eest-blockchain-standard-payload (block)
  (let ((header (block-header block)))
    (list
     (cons "number" (quantity-to-hex (block-header-number header)))
     (cons "gasLimit" (quantity-to-hex (block-header-gas-limit header)))
     (cons "timestamp" (quantity-to-hex (block-header-timestamp header)))
     (cons "baseFeePerGas"
           (quantity-to-hex (or (block-header-base-fee-per-gas header) 0)))
     (cons "transactions"
           (mapcar (lambda (transaction)
                     (bytes-to-hex (transaction-encoding transaction)))
                   (block-transactions block)))
     (cons "withdrawals"
           (mapcar #'eest-blockchain-standard-withdrawal
                   (or (block-withdrawals block) '()))))))

(defun eest-blockchain-standard-expect (block)
  (let ((header (block-header block)))
    (list (cons "status" "VALID")
          (cons "stateRoot" (hash32-to-hex (block-header-state-root header)))
          (cons "receiptsRoot"
                (hash32-to-hex (block-header-receipts-root header)))
          (cons "gasUsed" (quantity-to-hex (block-header-gas-used header))))))

(defun validate-eest-blockchain-standard-newpayload-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-standard-fixture-fields+
     label)
    (unless (string= "Shanghai" (fixture-required-field fixture "network"))
      (error "~A standard replay materializer currently supports Shanghai"
             label))
    (let ((blocks (validate-eest-blockchain-json-array-field
                   fixture
                   "blocks"
                   label)))
      (unless (= 1 (length blocks))
        (error "~A standard replay materializer expects exactly one block"
               label))
      (let ((block-case (first blocks)))
        (validate-fixture-object-fields
         block-case
         +eest-blockchain-standard-block-fields+
         (format nil "~A block" label))
        (when (fixture-field-present-p block-case "expectException")
          (error "~A standard replay materializer expects a valid block"
                 label))
        (validate-eest-blockchain-hex-string
         (fixture-required-field block-case "rlp")
         (format nil "~A block rlp" label))
        (let* ((block (block-from-rlp
                       (hex-to-bytes
                        (fixture-required-field block-case "rlp"))))
               (block-hash (hash32-to-hex (block-hash block)))
               (last-block-hash
                 (fixture-required-field fixture "lastblockhash")))
          (validate-eest-blockchain-hash-string
           last-block-hash
           (format nil "~A lastblockhash" label))
          (unless (string= last-block-hash block-hash)
            (error "~A lastblockhash does not match decoded block hash"
                   label))
          (when (fixture-field-present-p block-case "blockHeader")
            (let ((header-hash
                    (fixture-object-field
                     (fixture-object-field block-case "blockHeader")
                     "hash")))
              (when header-hash
                (validate-eest-blockchain-hash-string
                 header-hash
                 (format nil "~A blockHeader hash" label))
                (unless (string= header-hash block-hash)
                  (error "~A blockHeader hash does not match decoded block"
                         label)))))
          block)))))

(defun materialize-eest-blockchain-standard-newpayload-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (block (validate-eest-blockchain-standard-newpayload-v2-case case)))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "network" (fixture-required-field fixture "network"))
          (cons "chainId" "0x1")
          (cons "config"
                '(("berlinBlock" . "0x0")
                  ("londonBlock" . "0x0")
                  ("shanghaiTime" . "0x0")))
          (cons "parent"
                (eest-blockchain-standard-parent
                 fixture
                 (format nil "EEST blockchain case ~A"
                         (fixture-required-field case "name"))))
          (cons "payload" (eest-blockchain-standard-payload block))
          (cons "expect" (eest-blockchain-standard-expect block)))))

(defun materialize-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture")))
    (if (fixture-field-present-p fixture "engineNewPayloadV2")
        (let ((engine (validate-eest-blockchain-engine-newpayload-v2-case
                       case)))
          (list (cons "name" (fixture-required-field case "name"))
                (cons "network" (fixture-required-field fixture "network"))
                (cons "chainId" (fixture-required-field engine "chainId"))
                (cons "config" (fixture-required-field engine "config"))
                (cons "parent" (fixture-required-field engine "parent"))
                (cons "payload" (fixture-required-field engine "payload"))
                (cons "expect" (fixture-required-field engine "expect"))))
        (if (fixture-field-present-p fixture "engineNewPayloads")
            (materialize-eest-blockchain-engine-newpayloads-v2-case case)
            (materialize-eest-blockchain-standard-newpayload-v2-case case)))))

(defun materialize-eest-blockchain-engine-newpayloads-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (payload
           (validate-eest-blockchain-engine-newpayloads-v2-case case)))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "network" (fixture-required-field fixture "network"))
          (cons "chainId"
                (quantity-to-hex
                 (hex-to-quantity
                  (or (fixture-object-field
                       (fixture-object-field fixture "config")
                       "chainid")
                      "0x1"))))
          (cons "config"
                '(("berlinBlock" . "0x0")
                  ("londonBlock" . "0x0")
                  ("shanghaiTime" . "0x0")))
          (cons "parent"
                (mapcar
                 (lambda (entry)
                   (if (string= "feeRecipient" (car entry))
                       (cons "feeRecipient"
                             (fixture-required-field payload "feeRecipient"))
                       entry))
                 (eest-blockchain-standard-parent
                  fixture
                  (format nil "EEST blockchain case ~A"
                          (fixture-required-field case "name")))))
          (cons "payload"
                (list
                 (cons "number"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "blockNumber"))))
                 (cons "gasLimit"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "gasLimit"))))
                 (cons "timestamp"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "timestamp"))))
                 (cons "baseFeePerGas"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "baseFeePerGas"))))
                 (cons "transactions"
                       (fixture-required-field payload "transactions"))
                 (cons "withdrawals"
                       (fixture-required-field payload "withdrawals"))))
          (cons "expect"
                (list
                 (cons "status" "VALID")
                 (cons "stateRoot"
                       (fixture-required-field payload "stateRoot"))
                 (cons "receiptsRoot"
                       (fixture-required-field payload "receiptsRoot"))
                 (cons "gasUsed"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "gasUsed")))))))))

(defun load-handwritten-fixture-file (path)
  (parse-json (fixture-file-string path)))

(defun handwritten-fixture-cases (fixture)
  (let ((cases (fixture-object-field fixture "cases")))
    (unless (listp cases)
      (error "Fixture cases must be a JSON array"))
    cases))

(defun select-handwritten-fixture-case (fixture name)
  (find name (handwritten-fixture-cases fixture)
        :key (lambda (case)
               (fixture-object-field case "name"))
        :test #'string=))

(defun report-handwritten-fixture-case (fixture case path)
  (list (cons "format" (fixture-object-field fixture "format"))
        (cons "name" (fixture-object-field case "name"))
        (cons "network" (fixture-object-field case "network"))
        (cons "source" path)
        (cons "blocks" (length (fixture-object-field case "blocks")))
        (cons "status"
              (fixture-object-field
               (fixture-object-field case "expect")
               "status"))))

(defun run-handwritten-fixture-case (path name)
  (let* ((fixture (load-handwritten-fixture-file path))
         (case (select-handwritten-fixture-case fixture name)))
    (unless case
      (error "Fixture case not found: ~A" name))
    (report-handwritten-fixture-case fixture case path)))

(deftest handwritten-fixture-runner-selects-and-reports-case
  (let ((report
          (run-handwritten-fixture-case
           +minimal-blockchain-fixture-path+
           "empty-shanghai-blockchain-smoke")))
    (is (string= "ethereum-lisp/minimal-blockchain-fixture-v1"
                 (fixture-object-field report "format")))
    (is (string= "empty-shanghai-blockchain-smoke"
                 (fixture-object-field report "name")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (is (string= "valid" (fixture-object-field report "status")))))

(deftest handwritten-fixture-runner-rejects-missing-case
  (signals error
    (run-handwritten-fixture-case
     +minimal-blockchain-fixture-path+
     "missing-case")))

(deftest eest-blockchain-test-root-json-discovery
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-blockchain-test-root-json-paths root)))
    (is (= 9 (length paths)))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-contract-creation-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-internal-create2-engine.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json"
                 "shanghai/phase-a-two-legacy-transfers-engine.json")
               (eest-blockchain-test-root-file-names root)))))

(deftest eest-blockchain-test-root-skips-empty-preferred-layout
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-fixture-root-~A/" (gensym))
            #P"/private/tmp/"))
         (engine-root
           (merge-pathnames "blockchain_tests_engine/" root))
         (generic-root
           (merge-pathnames "blockchain_tests/" root))
         (json-path
           (merge-pathnames "shanghai/test.json" generic-root)))
    (ensure-directories-exist engine-root)
    (ensure-directories-exist json-path)
    (with-open-file (stream json-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "{}" stream))
    (let ((selected-root (execution-spec-tests-blockchain-test-root root)))
      (is (string= (namestring (truename generic-root))
                   (namestring (truename selected-root))))
      (is (equal '("shanghai/test.json")
                 (eest-blockchain-test-root-file-names selected-root))))))

(deftest eest-blockchain-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-blockchain-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-blockchain-test-root-json-paths root))))

(deftest phase-a-eest-blockchain-discovery-skips-unsupported-fork-roots
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-blockchain-discovery-root-~A/" (gensym))
            #P"/private/tmp/"))
         (shanghai-path
           (merge-pathnames "shanghai/phase-a-empty-engine.json" root))
         (cancun-path
           (merge-pathnames "cancun/eip4844_blobs/invalid.json" root)))
    (labels ((file-string (path)
               (with-open-file (stream path :direction :input)
                 (let ((string (make-string (file-length stream))))
                   (read-sequence string stream)
                   string)))
             (write-file (path contents)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (write-string contents stream))))
      (write-file
       shanghai-path
       (file-string
        "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/shanghai/phase-a-empty-engine.json"))
      (write-file cancun-path "{")
      (is (equal
           '(("shanghai/phase-a-empty-engine.json" . "engineNewPayloadV2"))
           (discover-phase-a-eest-blockchain-replay-selectors root))))))

(deftest eest-state-test-root-json-discovery
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-state-test-root-json-paths root)))
    (is (= 2 (length paths)))
    (is (equal '("london/phase-a-state-sample.json"
                 "shanghai/phase-a-state-sample.json")
               (eest-state-test-root-file-names root)))))

(deftest eest-state-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-state-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-state-test-root-json-paths root))))

(deftest eest-state-test-file-entries-accept-optional-config
  (is (null
       (validate-eest-state-test-file-entries
        '(("case_with_config"
           ("env")
           ("pre")
           ("transaction")
           ("post")
           ("config" ("chainid" . "0x01"))))
        "state_tests/sample.json")))
  (signals error
    (validate-eest-state-test-file-entries
     '(("case_with_unknown_field"
        ("env")
        ("pre")
        ("transaction")
        ("post")
        ("unexpected")))
     "state_tests/sample.json")))

(deftest eest-state-test-root-case-loading-honors-selector-files
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-state-test-root-cases
                 root
                 :names '("london/phase-a-state-sample.json/phase_a_london_state_sample"))))
    (is (= 1 (length cases)))
    (is (equal '("london/phase-a-state-sample.json/phase_a_london_state_sample")
               (mapcar (lambda (case)
                         (fixture-required-field case "name"))
                       cases))))
  (let ((root (execution-spec-tests-state-test-root
               "tests/fixtures/execution-spec-tests-root/")))
    (signals error
      (load-eest-state-test-root-cases
       root
       :names '("london/missing-state-sample.json/missing_case")))))

(deftest eest-state-test-root-case-loading
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-state-test-root-cases root))
         (selectors (discover-phase-a-eest-state-test-selectors root))
         (phase-a-cases (load-phase-a-eest-state-test-root-cases root))
         (selected (load-eest-state-test-root-cases
                    root
                    :names '("london/phase-a-state-sample.json/phase_a_london_state_sample")))
         (phase-a-summary
           (validate-phase-a-eest-state-test-summary phase-a-cases))
         (summary (eest-state-test-root-summary cases))
         (report (report-eest-state-test-root-case (first selected))))
    (is (= 5 (length cases)))
    (is (equal +phase-a-eest-state-test-case-names+ selectors))
    (is (equal +phase-a-eest-state-test-case-names+
               (fixture-object-field phase-a-summary "names")))
    (is (= 5 (fixture-object-field summary "count")))
    (is (= 3 (fixture-object-field
              (fixture-object-field summary "forkCounts")
              "London")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "forkCounts")
              "Shanghai")))
    (is (= 8 (fixture-object-field summary "transactionCombinationCount")))
    (is (equal '("London") (fixture-object-field report "forks")))
    (is (= 4 (fixture-object-field report "transactionCombinations")))
    (signals error
      (load-eest-state-test-root-cases
       root
       :names '("london/phase-a-state-sample.json/missing_case")))
    (signals error
      (load-eest-state-test-root-file-cases
       "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/"
       "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/shanghai/phase-a-empty-engine.json"))))

(deftest phase-a-eest-state-discovery-skips-unsupported-and-oversized-roots
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-state-discovery-root-~A/" (gensym))
            #P"/private/tmp/"))
         (london-path
           (merge-pathnames "london/phase-a-state-sample.json" root))
         (cancun-path
           (merge-pathnames "cancun/eip4844_blobs/invalid.json" root))
         (oversized-shanghai-path
           (merge-pathnames "shanghai/eip3860_initcode/test_gas_usage.json"
                            root)))
    (labels ((file-string (path)
               (with-open-file (stream path :direction :input)
                 (let ((string (make-string (file-length stream))))
                   (read-sequence string stream)
                   string)))
             (write-file (path contents)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (write-string contents stream)))
             (write-oversized-file (path)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (loop repeat (1+ +phase-a-eest-state-test-discovery-max-file-bytes+)
                       do (write-char #\{ stream)))))
      (write-file
       london-path
       (file-string
        "tests/fixtures/execution-spec-tests-root/fixtures/state_tests/london/phase-a-state-sample.json"))
      (write-file cancun-path "{")
      (write-oversized-file oversized-shanghai-path)
      (is (equal
           '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
             "london/phase-a-state-sample.json/phase_a_london_dynamic_fee_state_sample"
             "london/phase-a-state-sample.json/phase_a_london_state_sample")
           (discover-phase-a-eest-state-test-selectors root))))))

(deftest phase-a-eest-state-test-selector-workflow
  (let ((selectors
          (parse-phase-a-eest-state-test-selectors
           "london/phase-a-state-sample.json/phase_a_london_access_list_state_sample, london/phase-a-state-sample.json/phase_a_london_state_sample")))
    (is (equal '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
                 "london/phase-a-state-sample.json/phase_a_london_state_sample")
               selectors))
    (is (string= "london/phase-a-state-sample.json/phase_a_london_access_list_state_sample,london/phase-a-state-sample.json/phase_a_london_state_sample"
                 (phase-a-eest-state-test-selector-string selectors))))
  (signals error
    (parse-phase-a-eest-state-test-selectors
     "london/phase-a-state-sample.json"))
  (signals error
    (parse-phase-a-eest-state-test-selectors
     "london/phase-a-state-sample.json/phase_a_london_state_sample, london/phase-a-state-sample.json/phase_a_london_state_sample"))
  (let* ((*fixture-root-environment-reader*
           (lambda (name)
             (when (string= name +phase-a-eest-state-test-selectors-env+)
               "auto")))
         (root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/")))
    (is (equal +phase-a-eest-state-test-case-names+
               (phase-a-eest-state-test-env-selectors root))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (when (string= name +phase-a-eest-state-test-selectors-env+)
              (phase-a-eest-state-test-selector-string
               +phase-a-eest-state-test-case-names+)))))
    (is (equal +phase-a-eest-state-test-case-names+
               (phase-a-eest-state-test-env-selectors)))))

(deftest phase-a-eest-blockchain-replay-selector-parsing
  (let ((selectors
          (parse-phase-a-eest-blockchain-replay-selectors
           "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2, shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2, shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-standard.json=blockRlp, shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2, shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2, shanghai/phase-a-transfer-engine.json=engineNewPayloadV2, shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2")))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               selectors)))
  (let ((selectors
          (parse-phase-a-eest-blockchain-replay-selectors
           "shanghai/test.json/tests/shanghai/test_payload.py::test_case[fork_Shanghai]=engineNewPayloadV2")))
    (is (equal '(("shanghai/test.json/tests/shanghai/test_payload.py::test_case[fork_Shanghai]" . "engineNewPayloadV2"))
               selectors)))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json"))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json=unsupported"))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=blockRlp"))
  (signals error
    (let ((*fixture-root-environment-reader*
            (lambda (name)
              (declare (ignore name))
              42)))
      (phase-a-eest-blockchain-replay-env-materialization-kinds))))

(deftest eest-blockchain-test-root-case-loading
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-blockchain-test-root-cases root))
         (phase-a-cases (load-phase-a-eest-blockchain-replay-cases root))
         (summary
           (validate-phase-a-eest-blockchain-replay-summary phase-a-cases))
         (selectors (discover-phase-a-eest-blockchain-replay-selectors root))
         (selected (load-eest-blockchain-test-root-cases
                    root
                    :names '("shanghai/phase-a-empty-engine.json")))
         (standard (first
                    (load-eest-blockchain-test-root-cases
                     root
                     :names '("shanghai/phase-a-empty-standard.json"))))
         (report (report-eest-blockchain-test-root-case (first selected))))
    (is (= 9 (length cases)))
    (is (= 9 (length phase-a-cases)))
    (is (= 9 (fixture-object-field summary "count")))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-contract-creation-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-internal-create2-engine.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json"
                 "shanghai/phase-a-two-legacy-transfers-engine.json")
               (fixture-object-field summary "names")))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               selectors))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               (validate-phase-a-eest-blockchain-discovered-replay-selectors
                root
                +phase-a-eest-blockchain-replay-materialization-kinds+)))
    (signals error
      (validate-phase-a-eest-blockchain-discovered-replay-selectors
       root
       (list (cons "shanghai/phase-a-empty-engine.json"
                   "engineNewPayloadV2"))))
    (is (string=
         "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2,shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2"
         (phase-a-eest-blockchain-replay-selector-string selectors)))
    (is (= 8 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "blockRlp")))
    (is (= 9 (fixture-object-field
              (fixture-object-field summary "networkCounts")
              "Shanghai")))
    (is (= 1 (fixture-object-field summary "blockCount")))
    (is (= 1 (length selected)))
    (is (string= "shanghai/phase-a-empty-engine.json"
                 (fixture-object-field report "name")))
    (is (string= "blockchain_test" (fixture-object-field report "format")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (let ((materialized
            (materialize-eest-blockchain-engine-newpayload-v2-case
             (first selected))))
      (is (string= "shanghai/phase-a-empty-engine.json"
                   (fixture-object-field materialized "name")))
      (is (string= "VALID"
                   (fixture-object-field
                    (fixture-object-field materialized "expect")
                    "status"))))
    (let ((materialized
            (materialize-eest-blockchain-engine-newpayload-v2-case
             standard)))
      (is (string= "shanghai/phase-a-empty-standard.json"
                   (fixture-object-field materialized "name")))
      (is (= 0 (length (fixture-object-field
                        (fixture-object-field materialized "payload")
                        "transactions"))))
      (is (string= "0x2a"
                   (fixture-object-field
                    (fixture-object-field materialized "payload")
                    "number")))
      (is (string= "VALID"
                   (fixture-object-field
                    (fixture-object-field materialized "expect")
                    "status"))))
    (signals error
      (load-eest-blockchain-test-root-cases
       root
       :names '("missing.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("shanghai/phase-a-empty-engine.json"
         "shanghai/phase-a-empty-engine.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("phase-a-empty-engine/case/extra")))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary nil))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       (list (first phase-a-cases))))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       phase-a-cases
       :expected-kinds
       '(("shanghai/phase-a-empty-engine.json" . "blockRlp")
         ("shanghai/phase-a-empty-standard.json" . "engineNewPayloadV2"))))
    (let* ((bad-case (copy-tree (first phase-a-cases)))
           (bad-fixture (fixture-required-field bad-case "fixture")))
      (setf (cdr (assoc "network" bad-fixture :test #'string=)) "Cancun")
      (is (null (phase-a-eest-blockchain-replay-materializable-kind
                 bad-case)))
      (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       (list bad-case (second phase-a-cases)))))))

(deftest eest-blockchain-engine-newpayloads-v2-materialization
  (let* ((source-name
           "berlin/eip2930_access_list/test.json/tests/berlin/test_tx_type.py::test_case[fork_Shanghai]")
         (case
           (list
            (cons "name" source-name)
            (cons "fixture"
                  (list
                   (cons "network" "Shanghai")
                   (cons "lastblockhash"
                         "0x2222222222222222222222222222222222222222222222222222222222222222")
                   (cons "config" '(("chainid" . "0x01")))
                   (cons "genesisBlockHeader"
                         '(("coinbase" . "0x0000000000000000000000000000000000000000")
                           ("number" . "0x00")
                           ("gasLimit" . "0x07270e00")
                           ("gasUsed" . "0x00")
                           ("timestamp" . "0x00")
                           ("baseFeePerGas" . "0x07")))
                   (cons "pre"
                         '(("0x0000000000000000000000000000000000001001"
                            ("nonce" . "0x00")
                            ("balance" . "0x10")
                            ("code" . "0x")
                            ("storage" ("0x00" . "0x01")))))
                   (cons "postState" '())
                   (cons "engineNewPayloads"
                         (list
                          (list
                           (cons "newPayloadVersion" "2")
                           (cons "forkchoiceUpdatedVersion" "2")
                           (cons "params"
                                 (list
                                  (list
                                   (cons "parentHash"
                                         "0x1111111111111111111111111111111111111111111111111111111111111111")
                                   (cons "feeRecipient"
                                         "0x0000000000000000000000000000000000000000")
                                   (cons "stateRoot"
                                         "0x3333333333333333333333333333333333333333333333333333333333333333")
                                   (cons "receiptsRoot"
                                         "0x4444444444444444444444444444444444444444444444444444444444444444")
                                   (cons "logsBloom"
                                         "0x")
                                   (cons "blockNumber" "0x1")
                                   (cons "gasLimit" "0x7270e00")
                                   (cons "gasUsed" "0x0")
                                   (cons "timestamp" "0x3e8")
                                   (cons "extraData" "0x00")
                                   (cons "prevRandao"
                                         "0x0000000000000000000000000000000000000000000000000000000000000000")
                                   (cons "baseFeePerGas" "0x7")
                                   (cons "blockHash"
                                         "0x2222222222222222222222222222222222222222222222222222222222222222")
                                   (cons "transactions" '())
                                   (cons "withdrawals" '())))))))
                   (cons "_info" '()))))))
    (is (string= "engineNewPayloadV2"
                 (eest-blockchain-replay-materialization-kind case)))
    (is (string= "engineNewPayloadV2"
                 (phase-a-eest-blockchain-replay-materializable-kind case)))
    (let* ((summary
             (validate-phase-a-eest-blockchain-replay-summary
              (list case)
              :expected-kinds (list (cons source-name "engineNewPayloadV2"))))
           (materialized
             (materialize-eest-blockchain-engine-newpayload-v2-case case))
           (parent (fixture-required-field materialized "parent"))
           (account (first (fixture-required-field parent "accounts")))
           (payload (fixture-required-field materialized "payload"))
           (expect (fixture-required-field materialized "expect")))
      (is (= 1 (fixture-required-field summary "count")))
      (is (= 0 (fixture-required-field summary "blockCount")))
      (is (string= "0x1" (fixture-required-field materialized "chainId")))
      (is (string= "0x1" (fixture-required-field payload "number")))
      (is (string= "0x3333333333333333333333333333333333333333333333333333333333333333"
                   (fixture-required-field expect "stateRoot")))
      (is (equal '(("0x0000000000000000000000000000000000000000000000000000000000000000"
                    . "0x1"))
                 (fixture-required-field account "storage"))))))

(deftest optional-phase-a-eest-blockchain-replay-cases
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2,shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2")
              (t nil)))))
    (let ((cases (load-optional-phase-a-eest-blockchain-replay-cases)))
      (is (= 9 (length cases)))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "pinned-v5.4.0")
              (t nil)))))
    (signals error
      (load-optional-phase-a-eest-blockchain-replay-cases)))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "auto")
              (t nil)))))
    (let ((cases (load-optional-phase-a-eest-blockchain-replay-cases)))
      (is (= 9 (length cases)))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               nil)
              (t nil)))))
    (signals test-skipped
      (load-optional-phase-a-eest-blockchain-replay-cases))))
