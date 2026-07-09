(in-package #:ethereum-lisp.test)

(defun devnet-cli-assert-connection-contract (report case-count)
  (let ((contract (fixture-object-field report "connectionContract")))
    (is contract)
    (is (= case-count (fixture-object-field contract "caseCount")))
    (is (= (* 5 case-count)
           (fixture-object-field contract "engineBoundaryConnections")))
    (is (= (* 18 case-count)
           (fixture-object-field contract "engineWorkflowConnections")))
    (is (= (* 23 case-count)
           (fixture-object-field contract "publicCanonicalReadConnections")))
    (is (= (* 3 case-count)
           (fixture-object-field contract "publicBoundaryConnections")))
    (is (= (* 28 case-count)
           (fixture-object-field contract "publicTxpoolConnections")))
    (is (= (fixture-object-field report "engineConnections")
           (fixture-object-field contract "expectedEngineConnections")))
    (is (= (fixture-object-field report "publicConnections")
           (fixture-object-field contract "expectedPublicConnections")))
    (is (= (fixture-object-field report "totalConnections")
           (fixture-object-field contract "expectedTotalConnections")))))

(defun devnet-cli-assert-engine-only-connection-contract (report)
  (let ((contract (fixture-object-field report "connectionContract")))
    (is contract)
    (is (= (fixture-object-field report "engineConnections")
           (fixture-object-field contract "expectedEngineConnections")))
    (is (= (fixture-object-field report "publicConnections")
           (fixture-object-field contract "expectedPublicConnections")))
    (is (= (fixture-object-field report "totalConnections")
           (fixture-object-field contract "expectedTotalConnections")))))

(defun devnet-cli-assert-engine-client-version (report)
  (is (string= "CL"
               (fixture-object-field report "engineClientVersionCode")))
  (is (string= "ethereum-lisp"
               (fixture-object-field report "engineClientVersionName")))
  (is (string= "0.1.0"
               (fixture-object-field report "engineClientVersionVersion")))
  (is (string= "0x00000000"
               (fixture-object-field report "engineClientVersionCommit"))))

(defun devnet-cli-assert-engine-transition-configuration
    (report &key
       (terminal-total-difficulty "0x0")
       (terminal-block-hash (hash32-to-hex (zero-hash32)))
       (terminal-block-number "0x0"))
  (is (string= terminal-total-difficulty
               (fixture-object-field
                report "engineTransitionTerminalTotalDifficulty")))
  (is (string= terminal-block-hash
               (fixture-object-field
                report "engineTransitionTerminalBlockHash")))
  (is (string= terminal-block-number
               (fixture-object-field
                report "engineTransitionTerminalBlockNumber")))
  (is (= -32602
         (fixture-object-field
          report "engineTransitionMismatchErrorCode")))
  (is (search "terminalTotalDifficulty mismatch"
              (fixture-object-field
               report "engineTransitionMismatchErrorMessage"))))

(defun devnet-cli-assert-engine-capability-list (capabilities)
  (dolist (method '("engine_newPayloadV1"
                    "engine_forkchoiceUpdatedV1"
                    "engine_getPayloadV1"
                    "engine_newPayloadV2"
                    "engine_forkchoiceUpdatedV2"
                    "engine_getPayloadV2"
                    "engine_getPayloadBodiesByHashV1"
                    "engine_getPayloadBodiesByRangeV1"))
    (is (member method capabilities :test #'string=)))
  (dolist (method '("engine_newPayloadV3"
                    "engine_getBlobsV1"
                    "engine_getBlobsV2"
                    "engine_getBlobsV3"
                    "engine_getPayloadBodiesByHashV2"
                    "engine_getPayloadBodiesByRangeV2"))
    (is (not (member method capabilities :test #'string=)))))

(defun devnet-cli-assert-kzg-backed-engine-capability-list (capabilities)
  (dolist (method '("engine_newPayloadV1"
                    "engine_forkchoiceUpdatedV1"
                    "engine_getPayloadV1"
                    "engine_newPayloadV2"
                    "engine_forkchoiceUpdatedV2"
                    "engine_getPayloadV2"
                    "engine_getPayloadBodiesByHashV1"
                    "engine_getPayloadBodiesByRangeV1"
                    "engine_forkchoiceUpdatedV3"
                    "engine_forkchoiceUpdatedV4"
                    "engine_getPayloadBodiesByHashV2"
                    "engine_getPayloadBodiesByRangeV2"
                    "engine_getPayloadV3"
                    "engine_getPayloadV4"
                    "engine_getPayloadV5"
                    "engine_getPayloadV6"
                    "engine_getBlobsV1"
                    "engine_getBlobsV2"
                    "engine_getBlobsV3"
                    "engine_newPayloadV3"
                    "engine_newPayloadV4"
                    "engine_newPayloadV5"))
    (is (member method capabilities :test #'string=))))

(defun devnet-cli-assert-engine-capability-report (report)
  (is (plusp (fixture-object-field report "engineCapabilityCount")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasNewPayloadV1")))
  (is (eq t
          (fixture-object-field
           report
           "engineCapabilityHasForkchoiceUpdatedV1")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetPayloadV1")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasNewPayloadV2")))
  (is (eq t
          (fixture-object-field
           report
           "engineCapabilityHasForkchoiceUpdatedV2")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetPayloadV2")))
  (is (eq nil
          (fixture-object-field report "engineCapabilityHasNewPayloadV3")))
  (is (eq nil
          (fixture-object-field report "engineCapabilityHasGetBlobsV1")))
  (is (eq nil
          (fixture-object-field report "engineCapabilityHasGetBlobsV2")))
  (is (eq nil
          (fixture-object-field report "engineCapabilityHasPayloadBodiesV2"))))

(defun devnet-cli-assert-kzg-opt-in-smoke-report (report)
  (is (string= "ok" (fixture-object-field report "status")))
  (is (string= "devnet-engine-only-kzg-opt-in"
               (fixture-object-field report "mode")))
  (is (not (fixture-object-field report "publicRpcEnabled")))
  (is (not (fixture-object-field report "rpcEndpoint")))
  (is (search "http://127.0.0.1:"
              (fixture-object-field report "engineEndpoint")))
  (is (search "ethereum-lisp-smoke-kzg-command"
              (fixture-object-field report "kzgVerifierCommand")))
  (is (string= "--kzg.verifier-command"
               (fixture-object-field report "kzgVerifierCommandOption")))
  (is (= 2 (fixture-object-field report "kzgVerifierTimeoutSeconds")))
  (is (string= "--kzg.verifier-timeout"
               (fixture-object-field report "kzgVerifierTimeoutOption")))
  (is (eq t
          (fixture-object-field report "kzgProofVerificationAvailable")))
  (is (plusp (fixture-object-field report "engineCapabilityCount")))
  (is (eq t
          (fixture-object-field
           report
           "engineCapabilityHasForkchoiceUpdatedV3")))
  (is (eq t
          (fixture-object-field
           report
           "engineCapabilityHasForkchoiceUpdatedV4")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetPayloadV3")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetPayloadV4")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetPayloadV6")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasNewPayloadV3")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetBlobsV1")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasGetBlobsV2")))
  (is (eq t
          (fixture-object-field report "engineCapabilityHasPayloadBodiesV2")))
  (is (stringp (fixture-object-field report "preparedPayloadV3Id")))
  (is (string= "03"
               (subseq (fixture-object-field report "preparedPayloadV3Id")
                       2
                       4)))
  (is (stringp (fixture-object-field report "preparedPayloadV3ParentHash")))
  (is (string= "0x1"
               (fixture-object-field report "preparedPayloadV3BlockNumber")))
  (is (eq nil
          (fixture-object-field
           report
           "preparedPayloadV3ShouldOverrideBuilder")))
  (is (= 0 (fixture-object-field report "preparedPayloadV3BlobCount")))
  (is (stringp (fixture-object-field report "preparedPayloadV4Id")))
  (is (string= "04"
               (subseq (fixture-object-field report "preparedPayloadV4Id")
                       2
                       4)))
  (is (stringp (fixture-object-field report "preparedPayloadV4ParentHash")))
  (is (string= "0x1"
               (fixture-object-field report "preparedPayloadV4BlockNumber")))
  (is (string= "0x2a"
               (fixture-object-field report "preparedPayloadV4SlotNumber")))
  (is (eq nil
          (fixture-object-field
           report
           "preparedPayloadV4ShouldOverrideBuilder")))
  (is (= 0 (fixture-object-field report "preparedPayloadV4BlobCount")))
  (is (stringp (fixture-object-field report "preparedPayloadV5Id")))
  (is (string= "05"
               (subseq (fixture-object-field report "preparedPayloadV5Id")
                       2
                       4)))
  (is (string= "0x9"
               (fixture-object-field report "preparedPayloadV5BlockNumber")))
  (is (string= "0x03dd000000000000"
               (fixture-object-field report "preparedPayloadV5BlobPrefix")))
  (is (= 1 (fixture-object-field report "preparedPayloadV5BlobCount")))
  (let ((commitment
          (fixture-object-field report "preparedPayloadV5Commitment")))
    (is (= (+ 2 (* 2 +kzg-commitment-size+))
           (length commitment)))
    (is (string= "0x04ee"
                 (subseq commitment 0 6)))
    (is (string=
         (concatenate
          'string
          "0x04ee"
          (make-string (- (+ 2 (* 2 +kzg-commitment-size+)) 6)
                       :initial-element #\0))
         commitment)))
  (is (= +cell-proofs-per-blob+
         (fixture-object-field report "preparedPayloadV5ProofCount")))
  (is (stringp (fixture-object-field report "preparedPayloadV6Id")))
  (is (string= "06"
               (subseq (fixture-object-field report "preparedPayloadV6Id")
                       2
                       4)))
  (is (stringp (fixture-object-field report "preparedPayloadV6BlockHash")))
  (is (string= "0xa"
               (fixture-object-field report "preparedPayloadV6BlockNumber")))
  (is (string= "0x2a"
               (fixture-object-field report "preparedPayloadV6SlotNumber")))
  (is (= 1
         (fixture-object-field report
                               "preparedPayloadV6ExecutionRequestCount")))
  (is (string= "0x8206aa"
               (fixture-object-field report
                                     "preparedPayloadV6FirstExecutionRequest")))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (expected-block-access-list
           (bytes-to-hex (block-access-list-rlp (list account)))))
    (is (string= expected-block-access-list
                 (fixture-object-field report
                                       "preparedPayloadV6BlockAccessList")))
    (is (string= (subseq expected-block-access-list
                         0
                         (min (length expected-block-access-list) 18))
                 (fixture-object-field report
                                       "preparedPayloadV6BlockAccessListPrefix"))))
  (is (string= "0x03dd000000000000"
               (fixture-object-field report "preparedPayloadV6BlobPrefix")))
  (is (= 1 (fixture-object-field report "preparedPayloadV6BlobCount")))
  (let ((commitment
          (fixture-object-field report "preparedPayloadV6Commitment")))
    (is (= (+ 2 (* 2 +kzg-commitment-size+))
           (length commitment)))
    (is (string= "0x04ee"
                 (subseq commitment 0 6))))
  (is (= +cell-proofs-per-blob+
         (fixture-object-field report "preparedPayloadV6ProofCount")))
  (is (= 1
         (fixture-object-field report "preparedPayloadBodiesByHashV2Count")))
  (is (= 0
         (fixture-object-field
          report
          "preparedPayloadBodiesByHashV2TransactionCount")))
  (is (= 0
         (fixture-object-field
          report
          "preparedPayloadBodiesByHashV2WithdrawalCount")))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (expected-block-access-list
           (bytes-to-hex (block-access-list-rlp (list account)))))
    (is (string= expected-block-access-list
                 (fixture-object-field
                  report
                  "preparedPayloadBodiesByHashV2BlockAccessList"))))
  (is (string= "0x9"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2StartBlockNumber")))
  (is (= 2
         (fixture-object-field report "preparedPayloadBodiesByRangeV2Count")))
  (is (eq t
          (fixture-object-field
           report
           "preparedPayloadBodiesByRangeV2LeadingNull")))
  (is (= 1
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2HitIndex")))
  (is (= 0
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2TransactionCount")))
  (is (= 0
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2WithdrawalCount")))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (expected-block-access-list
           (bytes-to-hex (block-access-list-rlp (list account)))))
    (is (string= expected-block-access-list
                 (fixture-object-field
                  report
                  "preparedPayloadBodiesByRangeV2BlockAccessList"))))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2ZeroStartErrorCode")))
  (is (string= "start and count must be positive numbers"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2ZeroStartErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2ZeroCountErrorCode")))
  (is (string= "start and count must be positive numbers"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2ZeroCountErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2MalformedStartErrorCode")))
  (is (string= "start must be a non-negative quantity"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2MalformedStartErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2MalformedCountErrorCode")))
  (is (string= "count must be a non-negative quantity"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2MalformedCountErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorCode")))
  (is (string=
       "engine_getPayloadBodiesByRangeV2 param count is missing"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorMessage")))
  (is (= -32600
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2InvalidRequestErrorCode")))
  (is (string=
       "Invalid Request"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2InvalidRequestErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2NullParamsErrorCode")))
  (is (string=
       "engine_getPayloadBodiesByRangeV2 params must include start and count"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2NullParamsErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2ObjectParamsErrorCode")))
  (is (string=
       "start must be a non-negative quantity"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2ObjectParamsErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorCode")))
  (is (string=
       "start must be a non-negative quantity"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorCode")))
  (is (string=
       "start must be a non-negative quantity"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorCode")))
  (is (string=
       "start must be a non-negative quantity"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorMessage")))
  (is (= -32602
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorCode")))
  (is (string=
       "engine_getPayloadBodiesByRangeV2 params must include start and count"
       (fixture-object-field
        report
        "preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorMessage")))
  (is (= -38004
         (fixture-object-field
          report
          "preparedPayloadBodiesByRangeV2OversizedErrorCode")))
  (is (string= "The number of requested bodies must not exceed 1024"
               (fixture-object-field
                report
                "preparedPayloadBodiesByRangeV2OversizedErrorMessage")))
  (let* ((commitment
           (fixture-object-field report "preparedPayloadV5Commitment"))
         (versioned-hash
           (fixture-object-field report "directBlobLookupVersionedHash"))
         (expected-versioned-hash
           (hash32-to-hex
            (kzg-commitment-to-versioned-hash
             (hex-to-bytes commitment)))))
    (is (stringp versioned-hash))
    (is (= 66 (length versioned-hash)))
    (is (string= expected-versioned-hash versioned-hash)))
  (is (= 2 (fixture-object-field report "directBlobLookupCount")))
  (is (string= "0x03dd000000000000"
               (fixture-object-field report "directBlobLookupBlobPrefix")))
  (is (= (+ 2 (* 2 +blob-byte-size+))
         (fixture-object-field report "directBlobLookupBlobHexLength")))
  (let ((proof (fixture-object-field report "directBlobLookupProof")))
    (is (= (+ 2 (* 2 +kzg-proof-size+))
           (length proof)))
    (is (string=
         (concatenate
          'string
          "0x05ff"
          (make-string (- (+ 2 (* 2 +kzg-proof-size+)) 6)
                       :initial-element #\0))
         proof)))
  (is (string= "0x05ff000000000000"
               (fixture-object-field report "directBlobLookupProofPrefix")))
  (is (= (+ 2 (* 2 +kzg-proof-size+))
         (fixture-object-field report "directBlobLookupProofHexLength")))
  (is (= 1 (fixture-object-field report "directCellProofLookupV2Count")))
  (is (= 2 (fixture-object-field report "directCellProofLookupV3Count")))
  (is (= +cell-proofs-per-blob+
         (fixture-object-field report "directCellProofLookupProofCount")))
  (let ((first-proof
          (fixture-object-field report "directCellProofLookupFirstProof"))
        (last-proof
          (fixture-object-field report "directCellProofLookupLastProof")))
    (is (= (+ 2 (* 2 +kzg-proof-size+)) (length first-proof)))
    (is (= (+ 2 (* 2 +kzg-proof-size+)) (length last-proof)))
    (is (string=
         (concatenate
          'string
          "0x05ff"
          (make-string (- (+ 2 (* 2 +kzg-proof-size+)) 6)
                       :initial-element #\0))
         first-proof))
    (is (string=
         (concatenate
          'string
          "0x84ff"
          (make-string (- (+ 2 (* 2 +kzg-proof-size+)) 6)
                       :initial-element #\0))
         last-proof)))
  (is (string= "0x05ff000000000000"
               (fixture-object-field
                report
                "directCellProofLookupFirstProofPrefix")))
  (is (string= "0x84ff000000000000"
               (fixture-object-field
                report
                "directCellProofLookupLastProofPrefix")))
  (is (= 26 (fixture-object-field report "engineConnections")))
  (is (= 0 (fixture-object-field report "publicConnections")))
  (is (= 26 (fixture-object-field report "totalConnections"))))

