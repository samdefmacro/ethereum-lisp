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
