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

(defun phase-a-eest-stack-underflow-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_stack_underflow.json/tests/frontier/opcodes/test_swap.py::test_stack_underflow"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for index from 1 to 16
                collect
                (format nil
                        "~A[fork_~A-state_test-SWAP~D]"
                        prefix
                        fork
                        index)))))

(defun phase-a-eest-precompile-absence-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/precompiles/test_precompile_absence.json/tests/frontier/precompiles/test_precompile_absence.py::test_precompile_absence"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for case in '("31_bytes" "32_bytes" "empty_calldata")
                collect
                (format nil
                        "~A[fork_~A-state_test-~A]"
                        prefix
                        fork
                        case)))))

(defun phase-a-eest-homestead-coverage-state-test-v5.4.0-case-names ()
  (let ((prefix
          "homestead/coverage/test_coverage.json/tests/homestead/coverage/test_coverage.py::test_coverage"))
    (loop for fork in '("London" "Shanghai")
          collect
          (format nil
                  "~A[fork_~A-state_test]"
                  prefix
                  fork))))

(defun phase-a-eest-dup-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_dup.json/tests/frontier/opcodes/test_dup.py::test_dup"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for index from 1 to 16
                collect
                (format nil
                        "~A[fork_~A-evm_code_type_LEGACY-state_test-DUP~D]"
                        prefix
                        fork
                        index)))))

(defun phase-a-eest-push-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_push.json/tests/frontier/opcodes/test_push.py::test_push"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for index from 1 to 32
                collect
                (format nil
                        "~A[fork_~A-state_test-PUSH~D]"
                        prefix
                        fork
                        index)))))

(defun phase-a-eest-swap-state-test-v5.4.0-case-names ()
  (let ((prefix
          "frontier/opcodes/test_swap.json/tests/frontier/opcodes/test_swap.py::test_swap"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (loop for index from 1 to 16
                collect
                (format nil
                        "~A[fork_~A-state_test-SWAP~D]"
                        prefix
                        fork
                        index)))))

(defun phase-a-eest-gas-state-test-v5.4.0-case-names ()
  (let ((exp-prefix
          "frontier/opcodes/test_gas.json/tests/frontier/opcodes/test_exp.py::test_gas")
        (log-prefix
          "frontier/opcodes/test_gas.json/tests/frontier/opcodes/test_log.py::test_gas"))
    (loop for fork in '("London" "Shanghai")
          nconc
          (append
           (loop for exponent in '("exponent2to255"
                                   "exponent2to256minus1"
                                   "exponent_0"
                                   "exponent_1"
                                   "exponent_1023"
                                   "exponent_1024"
                                   "exponent_2")
                 nconc
                 (loop for value in '("a2to256minus1" "a_0" "a_1")
                       collect
                       (format nil
                               "~A[fork_~A-state_test-~A-~A]"
                               exp-prefix
                               fork
                               exponent
                               value)))
           (loop for data-size in '(0 1 1023 1024 2)
                 nconc
                 (loop for topic from 0 to 4
                       collect
                       (format nil
                               "~A[fork_~A-state_test-data_size_~D-opcode_LOG~D-topics_~D]"
                               log-prefix
                               fork
                               data-size
                               topic
                               topic)))))))

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
   (phase-a-eest-calldatasize-state-test-v5.4.0-case-names)
   (phase-a-eest-stack-underflow-state-test-v5.4.0-case-names)
   (phase-a-eest-precompile-absence-state-test-v5.4.0-case-names)
   (phase-a-eest-homestead-coverage-state-test-v5.4.0-case-names)
   (phase-a-eest-dup-state-test-v5.4.0-case-names)
   (phase-a-eest-push-state-test-v5.4.0-case-names)
   (phase-a-eest-swap-state-test-v5.4.0-case-names)
   (phase-a-eest-gas-state-test-v5.4.0-case-names)))

