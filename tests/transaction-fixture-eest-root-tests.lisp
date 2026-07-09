(in-package #:ethereum-lisp.test)

(deftest eest-transaction-test-root-vector-loading
  (let* ((root (execution-spec-tests-transaction-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-transaction-test-json-paths root))
         (cases (load-eest-transaction-test-root-cases root))
         (invalid-cases
           (load-eest-transaction-test-root-invalid-cases root))
         (selected-cases
           (load-eest-transaction-test-root-cases
            root
            :names +phase-a-eest-transaction-test-case-names+))
         (vectors (load-eest-transaction-test-root-vectors root))
         (selected-vectors
           (load-phase-a-eest-transaction-test-root-vectors root))
         (full-vectors
           (load-full-eest-transaction-test-root-vectors root))
         (seed-vectors
           (load-transaction-envelope-vectors
            +transaction-envelope-fixture-path+))
         (legacy-vector
           (find "phase-a-sample.json/legacy-eip155-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (unprotected-vector
           (find "phase-a-sample.json/legacy-unprotected-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (legacy-pinned-blockchain-vector
           (find "phase-a-sample.json/legacy-pinned-blockchain-valid-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (unprotected-contract-vector
           (find "phase-a-sample.json/legacy-unprotected-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (protected-calldata-vector
           (find "phase-a-sample.json/legacy-protected-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (contract-vector
           (find "phase-a-sample.json/legacy-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-vector
           (find "phase-a-sample.json/typed-eip2930-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-pinned-blockchain-vector
           (find "phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-address-only-vector
           (find "phase-a-sample.json/typed-eip2930-address-only-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-calldata-vector
           (find "phase-a-sample.json/typed-eip2930-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-access-list-calldata-vector
           (find "phase-a-sample.json/typed-eip2930-access-list-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-contract-vector
           (find "phase-a-sample.json/typed-eip2930-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-empty-access-list-contract-vector
           (find
            "phase-a-sample.json/typed-eip2930-empty-access-list-contract-creation-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-vector
           (find "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-pinned-blockchain-vector
           (find
            "phase-a-sample.json/typed-eip1559-pinned-blockchain-valid-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-calldata-vector
           (find "phase-a-sample.json/typed-eip1559-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-address-only-access-list-vector
           (find
            "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-vector
           (find "phase-a-sample.json/typed-eip1559-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-duplicate-access-list-vector
           (find
            "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-calldata-vector
           (find "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-contract-vector
           (find "phase-a-sample.json/typed-eip1559-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-contract-vector
           (find
            "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (blob-vector
           (find "phase-a-sample.json/typed-eip4844-blob-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (blob-pinned-blockchain-vector
           (find
            "phase-a-sample.json/typed-eip4844-pinned-blockchain-valid-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (blob-access-list-calldata-vector
           (find
            "phase-a-sample.json/typed-eip4844-blob-access-list-calldata-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (set-code-access-list-calldata-vector
           (find
            "phase-a-sample.json/typed-eip7702-set-code-access-list-calldata-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (set-code-vector
           (find "phase-a-sample.json/typed-eip7702-set-code-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (all-summary (transaction-fixture-vector-summary vectors))
         (full-summary (transaction-fixture-vector-summary full-vectors))
         (summary (transaction-fixture-vector-summary selected-vectors)))
    (is (= 13 (length paths)))
    (is (= 83 (length cases)))
    (is (= 53 (length invalid-cases)))
    (is (= 25 (length selected-cases)))
    (is (= 30 (length vectors)))
    (is (= 25 (length selected-vectors)))
    (is (= 30 (length full-vectors)))
    (validate-transaction-fixture-vector-set vectors :require-required-types t)
    (assert-transaction-fixture-vectors-replay vectors)
    (is (equal +phase-a-eest-transaction-test-case-names+
               (mapcar
                (lambda (case)
                  (fixture-object-field case "name"))
                selected-cases)))
    (is (equal +full-eest-transaction-test-case-names+
               (mapcar
                (lambda (vector)
                  (fixture-object-field vector "name"))
                full-vectors)))
    (is (equal +invalid-eest-transaction-test-file-names+
               (remove-duplicates
                (mapcar #'eest-transaction-case-source-file-name invalid-cases)
                :test #'string=)))
    (let ((invalid-rejection-summary
            (eest-invalid-transaction-rejection-summary invalid-cases)))
      (is (= 38 (fixture-required-field invalid-rejection-summary
                                        "decodeErrorCount")))
      (is (= 13 (fixture-required-field invalid-rejection-summary
                                        "fieldValidationErrorCount")))
      (is (= 2 (fixture-required-field invalid-rejection-summary
                                       "signatureValidationErrorCount")))
      (is (null (fixture-required-field invalid-rejection-summary
                                        "acceptedNames")))
      (is (equal
           '(("prague/eip7702_set_code_tx/test_empty_authorization_list.json" . 1)
             ("prague/eip7702_set_code_tx/test_invalid_auth_signature.json" . 8)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_address.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id_encoding.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_encoded_as_bytes.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_extra_element.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_missing_element.json" . 12)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_as_list.json" . 6)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_encoding.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_rlp_encoding.json" . 4))
           (fixture-required-field invalid-rejection-summary
                                   "sourceFileCounts")))
      (is (equal
           '(("TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST" . 1)
             ("TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE|TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE_S_TOO_HIGH" . 8)
             ("TransactionException.TYPE_4_INVALID_AUTHORIZATION_FORMAT" . 44))
           (fixture-required-field invalid-rejection-summary
                                   "exceptionCounts")))
      (is (equal
           (list
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_empty_authorization_list.json")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 1)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_auth_signature.json")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 6)
              ("signatureValidationErrorCount" . 2)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_address.json")
              ("decodeErrorCount" . 4)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id.json")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 2)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id_encoding.json")
              ("decodeErrorCount" . 4)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_encoded_as_bytes.json")
              ("decodeErrorCount" . 2)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_extra_element.json")
              ("decodeErrorCount" . 4)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_missing_element.json")
              ("decodeErrorCount" . 12)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce.json")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 4)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_as_list.json")
              ("decodeErrorCount" . 6)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_encoding.json")
              ("decodeErrorCount" . 2)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("sourceFile" . "prague/eip7702_set_code_tx/test_invalid_tx_invalid_rlp_encoding.json")
              ("decodeErrorCount" . 4)
              ("fieldValidationErrorCount" . 0)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0)))
           (fixture-required-field invalid-rejection-summary
                                   "sourceFileStageCounts")))
      (is (equal
           (list
            '(("exception" . "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 1)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("exception" . "TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE|TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE_S_TOO_HIGH")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 6)
              ("signatureValidationErrorCount" . 2)
              ("acceptedCount" . 0))
            '(("exception" . "TransactionException.TYPE_4_INVALID_AUTHORIZATION_FORMAT")
              ("decodeErrorCount" . 38)
              ("fieldValidationErrorCount" . 6)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0)))
           (fixture-required-field invalid-rejection-summary
                                   "exceptionStageCounts"))))
    (let* ((invalid-case (first invalid-cases))
           (invalid-result (fixture-required-field invalid-case "result"))
           (prague-result (fixture-required-field invalid-result "Prague"))
           (invalid-transaction
             (transaction-from-encoding
              (hex-to-bytes (fixture-required-field invalid-case "txbytes"))))
           (message
             (handler-case
                 (progn
                   (ethereum-lisp.execution::validate-set-code-transaction-fields
                    invalid-transaction)
                   nil)
               (transaction-validation-error (condition)
                 (format nil "~A" condition)))))
      (is (string= "prague/eip7702_set_code_tx/test_empty_authorization_list.json"
                   (fixture-object-field invalid-case "name")))
      (is (string= "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST"
                   (fixture-required-field prague-result "exception")))
      (is (typep invalid-transaction 'set-code-transaction))
      (is (null (set-code-transaction-authorization-list invalid-transaction)))
      (is message)
      (is (search "authorization list" message)))
    (is legacy-vector)
    (is (string= "phase-a-sample.json/legacy-eip155-sample"
                 (fixture-object-field legacy-vector "name")))
    (is (string= "legacy"
                 (fixture-object-field legacy-vector "type")))
    (is unprotected-vector)
    (is (string= "phase-a-sample.json/legacy-unprotected-sample"
                 (fixture-object-field unprotected-vector "name")))
    (is (string= "legacy"
                 (fixture-object-field unprotected-vector "type")))
    (is (= 0 (fixture-object-field unprotected-vector "chainId")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field unprotected-vector "txbytes")))))
      (is (not (legacy-transaction-protected-p transaction))))
    (is legacy-pinned-blockchain-vector)
    (is (string= "legacy"
                 (fixture-object-field legacy-pinned-blockchain-vector
                                       "type")))
    (is (= 0 (fixture-object-field legacy-pinned-blockchain-vector "chainId")))
    (is (equal
         (list
          (cons "nonce" "0x5")
          (cons "gasLimit" "0x5208")
          (cons "to" "0x239d8f4155ea51080175d6d1cb9d0a8a4f8e27bc")
          (cons "value" "0x0")
          (cons "input" "0x")
          (cons "gasPrice" "0xa"))
         (fixture-object-field legacy-pinned-blockchain-vector "decoded")))
    (is (equal
         (list
          (cons "v" "0x1c")
          (cons "yParity" "0x1")
          (cons "r"
                "0x4cbd4c6a3fdb44020f1b8b90926784069a8fcec1e487065f422182f5c6bee518")
          (cons "s"
                "0x3367b6789a388d40ef567ec3347cc20921e9d4b4416c47137b1bd19132ad6290"))
         (fixture-object-field legacy-pinned-blockchain-vector "signature")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field legacy-pinned-blockchain-vector
                                    "txbytes")))))
      (is (not (legacy-transaction-protected-p transaction))))
    (is (string= "0x5208"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field legacy-pinned-blockchain-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is unprotected-contract-vector)
    (is (string= "legacy"
                 (fixture-object-field unprotected-contract-vector "type")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field unprotected-contract-vector "txbytes")))))
      (is (not (legacy-transaction-protected-p transaction)))
      (is (null (transaction-to transaction))))
    (is (string= "0xd30c8839c1145609e564b986f667b273ddcb8496"
                 (fixture-object-field
                  unprotected-contract-vector
                  "contractAddress")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field unprotected-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is protected-calldata-vector)
    (is (string= "legacy"
                 (fixture-object-field protected-calldata-vector "type")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field protected-calldata-vector "txbytes")))))
      (is (legacy-transaction-protected-p transaction)))
    (is (equal
         (list
          (cons "nonce" "0xb")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0xdeadbeef")
          (cons "gasPrice" "0x1"))
         (fixture-object-field protected-calldata-vector "decoded")))
    (is (string= "0x5248"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field protected-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is contract-vector)
    (is (string= "0x00de48310d77a4d56aa400248b0b1613508f5b73"
                 (fixture-object-field contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field contract-vector "decoded")
                  "input")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x4")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-vector "decoded")))
    (is (equal
         (list
          (cons "yParity" "0x0")
          (cons "r"
                "0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          (cons "s"
                "0x1ed995b55ae531ccce7f7355b76d169c08886a437e3932f6f0e79c9dcc297aed"))
         (fixture-object-field typed-vector "signature")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field typed-vector "accessList")))
    (is typed-pinned-blockchain-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-pinned-blockchain-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x0")
          (cons "gasLimit" "0x186a0")
          (cons "to" "0x31fea89c26d83e9ea40dc184bba2615d70f62e61")
          (cons "value" "0x0")
          (cons "input" "0x")
          (cons "gasPrice" "0xa"))
         (fixture-object-field typed-pinned-blockchain-vector "decoded")))
    (is (not (fixture-field-present-p
              typed-pinned-blockchain-vector
              "accessList")))
    (is (string= "0x5208"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-pinned-blockchain-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-address-only-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-address-only-vector "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys" '())))
         (fixture-object-field typed-address-only-vector "accessList")))
    (is (string= "0x5b68"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-address-only-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-calldata-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x3")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-calldata-vector "decoded")))
    (is (string= "0x5228"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-access-list-calldata-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-access-list-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x7")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-access-list-calldata-vector "decoded")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field typed-access-list-calldata-vector "accessList")))
    (is (string= "0x6a60"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-access-list-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-contract-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-contract-vector "type")))
    (is (string= "0x4a4be0144ae0ef07ca7b8715b1987d7fc7118961"
                 (fixture-object-field typed-contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field typed-contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field typed-contract-vector "decoded")
                  "input")))
    (is (string= "0xe77a"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-empty-access-list-contract-vector)
    (is (string= "access-list"
                 (fixture-object-field
                  typed-empty-access-list-contract-vector
                  "type")))
    (is (string= "0x3430739421c2980e911ddb9f0385fdaaae473144"
                 (fixture-object-field
                  typed-empty-access-list-contract-vector
                  "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field
                typed-empty-access-list-contract-vector
                "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field
                   typed-empty-access-list-contract-vector
                   "decoded")
                  "input")))
    (is (not (fixture-field-present-p
              typed-empty-access-list-contract-vector
              "accessList")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    typed-empty-access-list-contract-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-vector "type")))
    (is dynamic-fee-pinned-blockchain-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-pinned-blockchain-vector
                                       "type")))
    (is (equal
         (list
          (cons "nonce" "0x0")
          (cons "gasLimit" "0x186a0")
          (cons "to" "0xef5d8525b90f834e9b84a59351846383049035d4")
          (cons "value" "0x0")
          (cons "input" "0x")
          (cons "maxPriorityFeePerGas" "0x1")
          (cons "maxFeePerGas" "0x7"))
         (fixture-object-field dynamic-fee-pinned-blockchain-vector
                               "decoded")))
    (is (equal
         (list
          (cons "yParity" "0x0")
          (cons "r"
                "0x50b0296997589bfd424b094c3c7f39a89f518699fbe6f13c4d511ee5abe97438")
          (cons "s"
                "0x6c7e63ab4d87efe9548c65d9c87fb64ac316f0d0e6bc29b3e230e479d9a653f1"))
         (fixture-object-field dynamic-fee-pinned-blockchain-vector
                               "signature")))
    (is (not (fixture-field-present-p
              dynamic-fee-pinned-blockchain-vector
              "accessList")))
    (is (string= "0x5208"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-pinned-blockchain-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-calldata-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x5")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "maxPriorityFeePerGas" "0x1")
          (cons "maxFeePerGas" "0xfa0"))
         (fixture-object-field dynamic-fee-calldata-vector "decoded")))
    (is (string= "0x5228"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-address-only-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field
                  dynamic-fee-address-only-access-list-vector
                  "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys" '())))
         (fixture-object-field
          dynamic-fee-address-only-access-list-vector
          "accessList")))
    (is (string= "0x5b68"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    dynamic-fee-address-only-access-list-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-vector "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-vector "accessList")))
    (is (string= "0x6a40"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-duplicate-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field
                  dynamic-fee-duplicate-access-list-vector
                  "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002")))
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"))))
         (fixture-object-field dynamic-fee-duplicate-access-list-vector
                               "accessList")))
    (is (string= "0x7b0c"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    dynamic-fee-duplicate-access-list-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-calldata-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x8")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "maxPriorityFeePerGas" "0x1")
          (cons "maxFeePerGas" "0xfa0"))
         (fixture-object-field dynamic-fee-access-list-calldata-vector "decoded")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-calldata-vector
                               "accessList")))
    (is (string= "0x6a60"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-calldata-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-contract-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-contract-vector "type")))
    (is (string= "0x91ffbaa0e407b3a8386fb0481ba4cb45693fa082"
                 (fixture-object-field dynamic-fee-contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field dynamic-fee-contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field dynamic-fee-contract-vector "decoded")
                  "input")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-contract-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-contract-vector
                                       "type")))
    (is (string= "0x0db2f2d9790960138f1550ac55d8e5d1e60087ab"
                 (fixture-object-field dynamic-fee-access-list-contract-vector
                                       "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field dynamic-fee-access-list-contract-vector
                                     "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field dynamic-fee-access-list-contract-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-contract-vector
                               "accessList")))
    (is (string= "0xe77a"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-contract-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is blob-vector)
    (is (string= "blob"
                 (fixture-object-field blob-vector "type")))
    (is blob-pinned-blockchain-vector)
    (is (string= "blob"
                 (fixture-object-field blob-pinned-blockchain-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x0")
          (cons "gasLimit" "0x5208")
          (cons "to" "0x93fd8ec9883a18fc285c73bd22eb4c95c6018065")
          (cons "value" "0x1")
          (cons "input" "0x")
          (cons "maxPriorityFeePerGas" "0x0")
          (cons "maxFeePerGas" "0x7")
          (cons "maxFeePerBlobGas" "0x1")
          (cons "blobVersionedHashes"
                '("0x0100000000000000000000000000000000000000000000000000000000000000")))
         (fixture-object-field blob-pinned-blockchain-vector "decoded")))
    (is (not (fixture-field-present-p
              blob-pinned-blockchain-vector
              "accessList")))
    (is (string= "0x5208"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field blob-pinned-blockchain-vector
                                         "result")
                   "Cancun")
                  "intrinsicGas")))
    (is blob-access-list-calldata-vector)
    (is (string= "blob"
                 (fixture-object-field blob-access-list-calldata-vector
                                       "type")))
    (is (string= "0xdeadbeef"
                 (fixture-object-field
                  (fixture-object-field blob-access-list-calldata-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field blob-access-list-calldata-vector
                               "accessList")))
    (is (string= "0x6a80"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field blob-access-list-calldata-vector
                                         "result")
                   "Cancun")
                  "intrinsicGas")))
    (is set-code-access-list-calldata-vector)
    (is (string= "set-code"
                 (fixture-object-field set-code-access-list-calldata-vector
                                       "type")))
    (is (string= "0xdeadbeef"
                 (fixture-object-field
                  (fixture-object-field set-code-access-list-calldata-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field set-code-access-list-calldata-vector
                               "accessList")))
    (is (= 2
           (length
            (fixture-object-field
             (fixture-object-field set-code-access-list-calldata-vector
                                   "decoded")
             "authorizationList"))))
    (is (string= "0x12dd0"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field set-code-access-list-calldata-vector
                                         "result")
                   "Prague")
                  "intrinsicGas")))
    (is set-code-vector)
    (is (string= "set-code"
                 (fixture-object-field set-code-vector "type")))
    (is (= 30 (fixture-object-field all-summary "count")))
    (is (equal '((:legacy . 6)
                 (:access-list . 8)
                 (:dynamic-fee . 11)
                 (:blob . 3)
                 (:set-code . 2))
               (fixture-object-field all-summary "types")))
    (is (= 30 (fixture-object-field all-summary "decodedVectorCount")))
    (is (= 30 (fixture-object-field all-summary "signatureVectorCount")))
    (is (= 12 (fixture-object-field all-summary "accessListVectorCount")))
    (is (= 5 (fixture-object-field all-summary "dynamicFeeAccessListVectorCount")))
    (is (= 2 (fixture-object-field all-summary "duplicateAccessListVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeDuplicateAccessListVectorCount")))
    (is (= 12 (fixture-object-field all-summary "typedEmptyAccessListVectorCount")))
    (is (= 3 (fixture-object-field all-summary "accessListEmptyAccessListVectorCount")))
    (is (= 6 (fixture-object-field all-summary "dynamicFeeEmptyAccessListVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListAddressOnlyVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAddressOnlyAccessListVectorCount")))
    (is (= 14 (fixture-object-field all-summary "accessListAddressCount")))
    (is (= 22 (fixture-object-field all-summary "accessListStorageKeyCount")))
    (is (= 7 (fixture-object-field all-summary "contractCreationVectorCount")))
    (is (= 7 (fixture-object-field all-summary "contractCreationAddressVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field all-summary "dynamicFeeContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAccessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field
              all-summary
              "emptyAccessListContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "accessListEmptyAccessListContractCreationVectorCount")))
    (is (= 2 (fixture-object-field
              all-summary
              "dynamicFeeEmptyAccessListContractCreationVectorCount")))
    (is (= 8 (fixture-object-field all-summary "messageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "legacyMessageCallDataVectorCount")))
    (is (= 6 (fixture-object-field all-summary "typedMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "dynamicFeeMessageCallDataVectorCount")))
    (is (= 4 (fixture-object-field all-summary "accessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAccessListWithCallDataVectorCount")))
    (is (= 2 (fixture-object-field
              all-summary
              "emptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "accessListEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeEqualFeeCapVectorCount")))
    (is (= 3 (fixture-object-field all-summary "blobVersionedHashVectorCount")))
    (is (= 5 (fixture-object-field all-summary "blobVersionedHashCount")))
    (is (= 1 (fixture-object-field all-summary "blobAccessListVectorCount")))
    (is (= 1 (fixture-object-field all-summary "blobMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "setCodeAuthorizationVectorCount")))
    (is (= 4 (fixture-object-field all-summary "setCodeAuthorizationCount")))
    (is (= 1 (fixture-object-field all-summary "setCodeAccessListVectorCount")))
    (is (= 1 (fixture-object-field all-summary "setCodeMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (is (= 3 (fixture-object-field all-summary "protectedLegacyVectorCount")))
    (is (= 3 (fixture-object-field all-summary "unprotectedLegacyVectorCount")))
    (is (= 189 (fixture-object-field all-summary "validResultCount")))
    (is (= 201 (fixture-object-field all-summary "exceptionResultCount")))
    (is (equal '(("Frontier" . 6)
                 ("Homestead" . 6)
                 ("EIP150" . 6)
                 ("EIP158" . 6)
                 ("Byzantium" . 6)
                 ("Constantinople" . 6)
                 ("Istanbul" . 6)
                 ("Berlin" . 14)
                 ("London" . 25)
                 ("Paris" . 25)
                 ("Shanghai" . 25)
                 ("Cancun" . 28)
                 ("Prague" . 30))
               (fixture-object-field all-summary "validForkCounts")))
    (is (equal '(("Frontier" . 24)
                 ("Homestead" . 24)
                 ("EIP150" . 24)
                 ("EIP158" . 24)
                 ("Byzantium" . 24)
                 ("Constantinople" . 24)
                 ("Istanbul" . 24)
                 ("Berlin" . 16)
                 ("London" . 5)
                 ("Paris" . 5)
                 ("Shanghai" . 5)
                 ("Cancun" . 2))
               (fixture-object-field all-summary "exceptionForkCounts")))
    (is (= 25 (fixture-object-field summary "count")))
    (is (equal '((:legacy . 6) (:access-list . 8) (:dynamic-fee . 11))
               (fixture-object-field summary "types")))
    (is (= 25 (fixture-object-field summary "decodedVectorCount")))
    (is (= 25 (fixture-object-field summary "signatureVectorCount")))
    (is (= 10 (fixture-object-field summary "accessListVectorCount")))
    (is (= 5 (fixture-object-field summary "dynamicFeeAccessListVectorCount")))
    (is (= 2 (fixture-object-field summary "duplicateAccessListVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeDuplicateAccessListVectorCount")))
    (is (= 9 (fixture-object-field summary "typedEmptyAccessListVectorCount")))
    (is (= 3 (fixture-object-field summary "accessListEmptyAccessListVectorCount")))
    (is (= 6 (fixture-object-field summary "dynamicFeeEmptyAccessListVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListAddressOnlyVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAddressOnlyAccessListVectorCount")))
    (is (= 12 (fixture-object-field summary "accessListAddressCount")))
    (is (= 18 (fixture-object-field summary "accessListStorageKeyCount")))
    (is (= 7 (fixture-object-field summary "contractCreationVectorCount")))
    (is (= 7 (fixture-object-field summary "contractCreationAddressVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field summary "dynamicFeeContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAccessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field
              summary
              "emptyAccessListContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "accessListEmptyAccessListContractCreationVectorCount")))
    (is (= 2 (fixture-object-field
              summary
              "dynamicFeeEmptyAccessListContractCreationVectorCount")))
    (is (= 6 (fixture-object-field summary "messageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "legacyMessageCallDataVectorCount")))
    (is (= 4 (fixture-object-field summary "typedMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "dynamicFeeMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAccessListWithCallDataVectorCount")))
    (is (= 2 (fixture-object-field
              summary
              "emptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "accessListEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeEqualFeeCapVectorCount")))
    (is (= 0 (fixture-object-field summary "blobVersionedHashVectorCount")))
    (is (= 0 (fixture-object-field summary "blobVersionedHashCount")))
    (is (= 0 (fixture-object-field summary "blobAccessListVectorCount")))
    (is (= 0 (fixture-object-field summary "blobMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field
              summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeAuthorizationVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeAuthorizationCount")))
    (is (= 0 (fixture-object-field summary "setCodeAccessListVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field
              summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (is (= 3 (fixture-object-field summary "protectedLegacyVectorCount")))
    (is (= 3 (fixture-object-field summary "unprotectedLegacyVectorCount")))
    (is (= 181 (fixture-object-field summary "validResultCount")))
    (is (= 144 (fixture-object-field summary "exceptionResultCount")))
    (is (equal '(("Frontier" . 6)
                 ("Homestead" . 6)
                 ("EIP150" . 6)
                 ("EIP158" . 6)
                 ("Byzantium" . 6)
                 ("Constantinople" . 6)
                 ("Istanbul" . 6)
                 ("Berlin" . 14)
                 ("London" . 25)
                 ("Paris" . 25)
                 ("Shanghai" . 25)
                 ("Cancun" . 25)
                 ("Prague" . 25))
               (fixture-object-field summary "validForkCounts")))
    (is (equal '(("Frontier" . 19)
                 ("Homestead" . 19)
                 ("EIP150" . 19)
                 ("EIP158" . 19)
                 ("Byzantium" . 19)
                 ("Constantinople" . 19)
                 ("Istanbul" . 19)
                 ("Berlin" . 11))
               (fixture-object-field summary "exceptionForkCounts")))
    (is (equal '("phase-a-sample.json/legacy-eip155-sample"
                 "phase-a-sample.json/legacy-unprotected-sample"
                 "phase-a-sample.json/legacy-pinned-blockchain-valid-sample"
                 "phase-a-sample.json/legacy-unprotected-contract-creation-sample"
                 "phase-a-sample.json/legacy-protected-calldata-sample"
                 "phase-a-sample.json/legacy-contract-creation-sample"
                 "phase-a-sample.json/typed-eip2930-access-list-sample"
                 "phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample"
                 "phase-a-sample.json/typed-eip2930-address-only-access-list-sample"
                 "phase-a-sample.json/typed-eip2930-duplicate-access-list-sample"
                 "phase-a-sample.json/typed-eip2930-calldata-sample"
                 "phase-a-sample.json/typed-eip2930-access-list-calldata-sample"
                 "phase-a-sample.json/typed-eip2930-contract-creation-sample"
                 "phase-a-sample.json/typed-eip2930-empty-access-list-contract-creation-sample"
                 "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
                 "phase-a-sample.json/typed-eip1559-pinned-blockchain-valid-sample"
                 "phase-a-sample.json/typed-eip1559-equal-fee-caps-sample"
                 "phase-a-sample.json/typed-eip1559-calldata-sample"
                 "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
                 "phase-a-sample.json/typed-eip1559-contract-creation-sample"
                 "phase-a-sample.json/typed-eip1559-empty-access-list-contract-creation-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample")
               (fixture-object-field summary "names")))
    (is (equal summary
               (validate-phase-a-eest-transaction-vector-summary
                selected-vectors)))
    (is (equal full-summary
               (validate-full-eest-transaction-vector-summary
                full-vectors)))
    (is (equal selected-vectors
               (validate-transaction-fixture-required-vector-types
                selected-vectors
                +phase-a-eest-transaction-pinned-valid-case-types+
                "Phase A EEST transaction pinned valid vectors")))
    (is (equal full-vectors
               (validate-transaction-fixture-required-vector-types
                full-vectors
                +full-eest-transaction-pinned-valid-case-types+
                "Full EEST transaction pinned valid vectors")))
    (is (= 3 (fixture-object-field full-summary "blobVersionedHashVectorCount")))
    (is (= 5 (fixture-object-field full-summary "blobVersionedHashCount")))
    (is (= 1 (fixture-object-field full-summary "blobAccessListVectorCount")))
    (is (= 1 (fixture-object-field full-summary "blobMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              full-summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field full-summary "setCodeAuthorizationVectorCount")))
    (is (= 4 (fixture-object-field full-summary "setCodeAuthorizationCount")))
    (is (= 1 (fixture-object-field full-summary "setCodeAccessListVectorCount")))
    (is (= 1 (fixture-object-field full-summary "setCodeMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              full-summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (signals error
      (validate-transaction-fixture-result-count-summary
       selected-vectors
       (cons (cons "validResultCount" 0)
             (remove "validResultCount" summary :key #'car :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-result-count-summary
       full-vectors
       (cons (cons "exceptionForkCounts" nil)
             (remove "exceptionForkCounts"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (list (cons "accessListVectorCount" 0)
             (cons "dynamicFeeAccessListVectorCount" 0)
             (cons "duplicateAccessListVectorCount" 0)
             (cons "dynamicFeeDuplicateAccessListVectorCount" 0)
             (cons "typedEmptyAccessListVectorCount" 0)
             (cons "accessListEmptyAccessListVectorCount" 0)
             (cons "dynamicFeeEmptyAccessListVectorCount" 0)
             (cons "accessListAddressCount" 0)
             (cons "accessListAddressOnlyVectorCount" 0)
             (cons "dynamicFeeAddressOnlyAccessListVectorCount" 0)
             (cons "accessListStorageKeyCount" 0))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "accessListEmptyAccessListVectorCount" 0)
             (remove "accessListEmptyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeEmptyAccessListVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeAddressOnlyAccessListVectorCount" 0)
             (remove "dynamicFeeAddressOnlyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeDuplicateAccessListVectorCount" 0)
             (remove "dynamicFeeDuplicateAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "contractCreationVectorCount" 0)
             (remove "contractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "contractCreationAddressVectorCount" 0)
             (remove "contractCreationAddressVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeContractCreationVectorCount" 0)
             (remove "dynamicFeeContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeAccessListContractCreationVectorCount" 0)
             (remove "dynamicFeeAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "accessListContractCreationVectorCount" 0)
             (remove "accessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "emptyAccessListContractCreationVectorCount" 0)
             (remove "emptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "accessListEmptyAccessListContractCreationVectorCount" 0)
             (remove "accessListEmptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeEmptyAccessListContractCreationVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "typedMessageCallDataVectorCount" 0)
             (remove "typedMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "legacyMessageCallDataVectorCount" 0)
             (remove "legacyMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListMessageCallDataVectorCount" 0)
             (remove "accessListMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeMessageCallDataVectorCount" 0)
             (remove "dynamicFeeMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListWithCallDataVectorCount" 0)
             (remove "accessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeAccessListWithCallDataVectorCount" 0)
             (remove "dynamicFeeAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "emptyAccessListWithCallDataVectorCount" 0)
             (remove "emptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListEmptyAccessListWithCallDataVectorCount" 0)
             (remove "accessListEmptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeEmptyAccessListWithCallDataVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobVersionedHashVectorCount" 0)
             (remove "blobVersionedHashVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobVersionedHashCount" 0)
             (remove "blobVersionedHashCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobAccessListVectorCount" 0)
             (remove "blobAccessListVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobMessageCallDataVectorCount" 0)
             (remove "blobMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobAccessListMessageCallDataVectorCount" 0)
             (remove "blobAccessListMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationVectorCount" 0)
             (remove "setCodeAuthorizationVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationCount" 0)
             (remove "setCodeAuthorizationCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAccessListVectorCount" 0)
             (remove "setCodeAccessListVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeMessageCallDataVectorCount" 0)
             (remove "setCodeMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAccessListMessageCallDataVectorCount" 0)
             (remove "setCodeAccessListMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationCount" 1)
             (cons (cons "setCodeAuthorizationVectorCount" 1)
                   (remove "setCodeAuthorizationCount"
                           (remove "setCodeAuthorizationVectorCount"
                                   full-summary
                                   :key #'car
                                   :test #'string=)
                           :key #'car
                           :test #'string=)))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-legacy-protection-coverage
       (cons (cons "unprotectedLegacyVectorCount" 0)
             (remove "unprotectedLegacyVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-decoded-coverage
       selected-vectors
       (cons (cons "decodedVectorCount" 0)
             (remove "decodedVectorCount" summary :key #'car :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-signature-coverage
       selected-vectors
       (cons (cons "signatureVectorCount" 0)
             (remove "signatureVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (is (equal vectors
               (validate-eest-transaction-seed-alignment
                vectors
                seed-vectors)))
    (is (equal selected-vectors
               (validate-phase-a-eest-transaction-seed-alignment
                selected-vectors
                seed-vectors)))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-vector-field (vectors name field value)
               (mapcar
                (lambda (candidate)
                  (if (string= name (fixture-object-field candidate "name"))
                      (replace-field candidate field value)
                      candidate))
                vectors)))
      (signals error
        (validate-phase-a-eest-transaction-seed-alignment
         selected-vectors
         (replace-vector-field
          seed-vectors
          "eip1559-dynamic-fee"
          "decoded"
          (list (cons "nonce" "0xdead")))))
      (signals error
        (validate-phase-a-eest-transaction-seed-alignment
         selected-vectors
         (replace-vector-field
          seed-vectors
          "eip2930-access-list"
          "signature"
          (list (cons "r" "0xdead")))))
      (signals error
        (validate-eest-transaction-seed-alignment
         vectors
         (replace-vector-field
          seed-vectors
          "eip4844-blob"
          "decoded"
          (list (cons "nonce" "0xdead")))))
      (signals error
        (validate-eest-transaction-seed-alignment
         vectors
         (replace-vector-field
          seed-vectors
          "eip7702-set-code"
          "signature"
          (list (cons "r" "0xdead"))))))
    (signals error
      (transaction-fixture-vector-summary "phase-a-vectors"))
    (signals error
      (transaction-fixture-vector-summary (list "phase-a-vector")))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       (reverse selected-vectors)))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       "phase-a-vectors"))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       (remove dynamic-fee-vector selected-vectors)))
    (signals error
      (validate-transaction-fixture-required-vector-types
       selected-vectors
       '(("phase-a-sample.json/legacy-pinned-blockchain-valid-sample" . :blob))
       "Phase A EEST transaction pinned valid vectors"))
    (signals error
      (validate-transaction-fixture-required-vector-types
       selected-vectors
       '(("phase-a-sample.json/missing-pinned-valid-sample" . :legacy))
       "Phase A EEST transaction pinned valid vectors"))
    (signals error
      (validate-full-eest-transaction-vector-summary
       (remove set-code-vector full-vectors)))
    (signals error
      (validate-full-eest-transaction-vector-summary
       (reverse full-vectors)))
    (signals error
      (validate-phase-a-eest-transaction-target-fork-results
       (list
        (list
         (cons "name" "phase-a-invalid-on-target")
         (cons "result"
               (list
                (cons +phase-a-eest-transaction-target-fork+
                      (list
                       (cons "exception"
                             "TransactionException.TYPE_2_TX_PRE_FORK")))))))))
    (signals error
      (validate-phase-a-eest-transaction-seed-alignment
       selected-vectors
       (remove typed-vector seed-vectors
               :key (lambda (candidate)
                      (fixture-object-field candidate "txbytes"))
               :test #'string=)))
    (signals error
      (validate-eest-transaction-seed-alignment
       vectors
       (remove blob-vector seed-vectors
               :key (lambda (candidate)
                      (fixture-object-field candidate "txbytes"))
               :test #'string=)))
    (signals error
      (validate-eest-transaction-seed-alignment
       "eest-vectors"
       seed-vectors))
    (signals error
      (validate-eest-transaction-seed-alignment
       (append vectors (list (first vectors)))
       seed-vectors))
    (signals error
      (validate-phase-a-eest-transaction-seed-alignment
       "phase-a-vectors"
       seed-vectors))
    (signals error
      (validate-phase-a-eest-transaction-seed-alignment
       (append selected-vectors (list (first selected-vectors)))
       seed-vectors))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:blob . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:set-code . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:unknown . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 0)
         (:dynamic-fee . 1))))
    (is (string= "phase-a-sample.json/alpha"
                 (eest-transaction-root-case-name root
                                                  (first paths)
                                                  "alpha"
                                                  nil)))
    (signals error
      (load-eest-transaction-test-root-file-cases
       "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/"
       (first paths)))
    (signals error
      (validate-transaction-fixture-vector-set
       (append vectors (list legacy-vector))))
    (signals error
      (validate-transaction-fixture-vector-set "phase-a-vectors"))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("missing.json")))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("")))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names "phase-a-sample.json"))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '(42)))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("phase-a-sample.json" "phase-a-sample.json")))
    (signals error
      (filter-eest-transaction-test-root-cases
       (list
        (list (cons "name" "duplicate-source-name"))
        (list (cons "name" "duplicate-source-name")))
       nil))
    (signals error
      (filter-eest-transaction-test-root-cases cases "phase-a-sample.json"))
    (signals error
      (filter-eest-transaction-test-root-cases cases '("bare-case-name")))
    (validate-eest-transaction-selector-list
     +phase-a-eest-transaction-test-case-names+)
    (signals error
      (validate-eest-transaction-selector-list "phase-a-sample.json"))
    (signals error
      (validate-eest-transaction-selector-list nil))
    (signals error
      (validate-eest-transaction-selector-list '(42)))
    (signals error
      (validate-eest-transaction-selector-list '("")))
    (signals error
      (validate-eest-transaction-selector-list '("bare-case-name")))
    (signals error
      (validate-eest-transaction-selector-list '("../escape.json")))
    (signals error
      (validate-eest-transaction-selector-list '("/absolute.json")))
    (signals error
      (validate-eest-transaction-selector-list '("dir//case.json")))
    (signals error
      (validate-eest-transaction-selector-list '(".json/case")))
    (signals error
      (validate-eest-transaction-selector-list '("dir/.json/case")))
    (signals error
      (validate-eest-transaction-selector-list '("case.jsonx/name")))
    (signals error
      (validate-eest-transaction-selector-list '("case.json/")))
    (signals error
      (validate-eest-transaction-selector-list '("case.json//name")))
    (validate-eest-transaction-selector-list
     '("case.json/tests/prague/eip7702_set_code_tx/test_invalid_tx.py::test_case[fork_Prague-transaction_test]"))
    (signals error
      (validate-eest-transaction-selector-list
       '("phase-a-sample.json" "phase-a-sample.json"))))
  (signals error
    (validate-phase-a-eest-transaction-vector-summary nil))
  (signals error
    (load-eest-transaction-test-root-cases
     "tests/fixtures/geth-spec-tests-root/spec-tests/fixtures/transaction_tests/")))

