(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-genesis-fixture+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defconstant +devnet-cli-jwt-secret+
  "1111111111111111111111111111111111111111111111111111111111111111")

(defconstant +devnet-cli-txpool-private-key+ 1)
(defconstant +devnet-cli-txpool-balance+ 1000000000000000000)
(defconstant +devnet-cli-txpool-gas-price+ 200)
(defconstant +devnet-cli-txpool-pending-gas-price+ 1000000000)
(defconstant +devnet-cli-txpool-basefee-gas-price+ 0)
(defconstant +devnet-cli-txpool-gas-limit+ 21000)
(defconstant +devnet-cli-txpool-value+ 1)
(defconstant +devnet-cli-txpool-recipient+
  "0x0000000000000000000000000000000000003001")

(defparameter +devnet-side-reorg-smoke-case-names+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"))

(defvar *devnet-cli-temp-counter* 0)

(defun devnet-cli-current-process-id ()
  #+sbcl
  (sb-unix:unix-getpid)
  #-sbcl
  nil)

(defun devnet-cli-current-process-id-string ()
  (let ((process-id (devnet-cli-current-process-id)))
    (if process-id
        (write-to-string process-id)
        "")))

(defun devnet-cli-txpool-sender-address ()
  (fixture-private-key-address +devnet-cli-txpool-private-key+))

(defun devnet-cli-txpool-transaction
    (config nonce gas-price &key
       (private-key +devnet-cli-txpool-private-key+)
       (gas-limit +devnet-cli-txpool-gas-limit+))
  (fixture-sign-legacy-transaction
   (make-legacy-transaction
    :nonce nonce
    :gas-price gas-price
    :gas-limit gas-limit
    :to (address-from-hex +devnet-cli-txpool-recipient+)
    :value +devnet-cli-txpool-value+)
   private-key
   (chain-config-chain-id config)))

(defun devnet-cli-transaction-raw (transaction)
  (bytes-to-hex (transaction-encoding transaction)))

(defun devnet-cli-transaction-nonce-key (transaction)
  (format nil "~D" (transaction-nonce transaction)))

(defun devnet-cli-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun devnet-cli-empty-json-array-p (value)
  (and (vectorp value)
       (zerop (length value))))

(defun devnet-cli-empty-json-array-or-lossy-null-p (value)
  (or (null value)
      (devnet-cli-empty-json-array-p value)))

(defun devnet-cli-temp-token ()
  (format nil "~A-~D-~A"
          (or (devnet-cli-current-process-id) "nopid")
          (incf *devnet-cli-temp-counter*)
          (gensym)))

(defun devnet-cli-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (devnet-cli-temp-token))
                  :type type)
   #P"/private/tmp/"))

(defun devnet-cli-write-temp-file (path contents)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string contents stream)))

(defun devnet-cli-make-executable (path)
  (uiop:run-program (list "chmod" "755" (namestring path))
                    :output nil
                    :error-output nil)
  path)

(defun devnet-cli-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-cli-funded-txpool-genesis-json
    (&key config-fields gas-limit
       (private-keys (list +devnet-cli-txpool-private-key+)))
  (let* ((genesis (parse-json
                   (devnet-cli-file-string +devnet-cli-genesis-fixture+)))
         (state (state-db-from-genesis-json-file
                 +devnet-cli-genesis-fixture+))
         (config (fixture-object-field genesis "config"))
         (alloc (fixture-object-field genesis "alloc"))
         (accounts nil))
    (dolist (private-key private-keys)
      (let ((sender (fixture-private-key-address private-key))
            (account
              (list (cons "balance"
                          (quantity-to-hex +devnet-cli-txpool-balance+))
                    (cons "nonce" "0x0"))))
        (state-db-set-account
         state
         sender
         (make-state-account :nonce 0
                             :balance +devnet-cli-txpool-balance+))
        (push (cons (address-to-hex sender) account) accounts)))
    (setf (cdr (assoc "stateRoot" genesis :test #'string=))
          (hash32-to-hex (state-db-root state)))
    (dolist (field config-fields)
      (let ((cell (assoc (car field) config :test #'string=)))
        (if cell
            (setf (cdr cell) (cdr field))
            (setf config (append config (list field))))))
    (when gas-limit
      (setf (cdr (assoc "gasLimit" genesis :test #'string=))
            (quantity-to-hex gas-limit)))
    (setf (cdr (assoc "config" genesis :test #'string=)) config)
    (setf (cdr (assoc "alloc" genesis :test #'string=))
          (append alloc (nreverse accounts)))
    (json-encode genesis)))

(defun devnet-cli-pid-file-process-id (path)
  (parse-integer
   (string-trim '(#\Space #\Tab #\Newline #\Return)
                (devnet-cli-file-string path))
   :junk-allowed nil))

(defun devnet-cli-file-forms (path)
  (with-open-file (stream path :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          collect form)))

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

(defun devnet-cli-assert-public-readiness (report)
  (is (search "ethereum-lisp"
              (fixture-object-field report "publicClientVersion")))
  (is (every #'digit-char-p
             (fixture-object-field report "publicNetVersion")))
  (is (null (fixture-object-field report "publicNetListening")))
  (is (null (fixture-object-field report "publicSyncing")))
  (is (string= "0x0" (fixture-object-field report "publicNetPeerCount")))
  (is (= 0 (fixture-object-field report "publicAccountCount")))
  (is (string= (address-to-hex (zero-address))
               (fixture-object-field report "publicCoinbase")))
  (is (null (fixture-object-field report "publicMining")))
  (is (string= "0x0" (fixture-object-field report "publicHashrate")))
  (is (= 3 (fixture-object-field report "publicBatchResponseCount")))
  (is (string= (fixture-object-field report "publicBatchChainId")
               (fixture-object-field report "chainId")))
  (is (string= (fixture-object-field report "publicBatchNetVersion")
               (fixture-object-field report "publicNetVersion")))
  (is (search "ethereum-lisp"
              (fixture-object-field report "publicBatchClientVersion"))))

(defun devnet-cli-assert-engine-payload-bodies (report)
  (is (= 1 (fixture-object-field report "enginePayloadBodiesByHashCount")))
  (is (= 1 (fixture-object-field report "enginePayloadBodiesByRangeCount")))
  (is (integerp
       (fixture-object-field
        report "enginePayloadBodiesByHashTransactionCount")))
  (is (integerp
       (fixture-object-field
        report "enginePayloadBodiesByRangeTransactionCount")))
  (is (= (fixture-object-field
          report "enginePayloadBodiesByHashTransactionCount")
         (fixture-object-field
          report "enginePayloadBodiesByRangeTransactionCount"))))

(defun devnet-cli-assert-engine-get-payload-v2 (report)
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2ParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2BlockNumber")))
  (is (integerp
       (fixture-object-field
        report
        "engineGetPayloadV2TransactionCount")))
  (is (stringp
       (fixture-object-field report "preparedTxpoolPayloadId")))
  (is (not (string= (fixture-object-field report "preparedPayloadId")
                    (fixture-object-field report "preparedTxpoolPayloadId"))))
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolBlockNumber")))
  (is (= 1
         (fixture-object-field
          report
          "engineGetPayloadV2TxpoolTransactionCount")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionRaw")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedTransactionRaw")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedTransactionHash")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued")))
  (is (stringp
       (fixture-object-field report "preparedReplacementTxpoolPayloadId")))
  (is (not (string= (fixture-object-field report "preparedTxpoolPayloadId")
                    (fixture-object-field
                     report
                     "preparedReplacementTxpoolPayloadId"))))
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementBlockNumber")))
  (is (= 1
         (fixture-object-field
          report
          "engineGetPayloadV2TxpoolReplacementTransactionCount")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionRaw")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementTransactionRaw")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementTransactionHash")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementNonSelectedQueuedStillQueued")))
  (is (string= +payload-status-valid+
               (fixture-object-field
                report
                "engineNewPayloadV2TxpoolImportStatus")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field
                report
                "engineNewPayloadV2TxpoolImportLatestValidHash")))
  (is (string= +payload-status-valid+
               (fixture-object-field
                report
                "engineForkchoiceUpdatedV2TxpoolImportStatus")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field report "txpoolImportBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field report "txpoolImportTransactionHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field
                report
                "txpoolImportTransactionBlockHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockNumber")
               (fixture-object-field
                report
                "txpoolImportTransactionBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "txpoolImportReceiptTransactionHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field report "txpoolImportReceiptBlockHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockNumber")
               (fixture-object-field
                report
                "txpoolImportReceiptBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionRaw")
               (fixture-object-field report "txpoolImportRawTransaction")))
  (is (= 1
         (fixture-object-field report "txpoolImportBlockTransactionCount")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "txpoolImportBlockTransactionHash")))
  (is (string= "0x0"
               (fixture-object-field
                report
                "txpoolImportTxpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field
                report
                "txpoolImportTxpoolStatusQueued")))
  (is (not (fixture-object-field report "txpoolImportSelectedStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "txpoolImportNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "txpoolImportNonSelectedQueuedStillQueued"))))

(defun devnet-cli-assert-public-cors-smoke-report (report)
  (is (equal '("https://runner.example" "https://observer.example")
             (fixture-object-field report "publicCorsOrigins")))
  (is (equal '("https://runner.example" "https://observer.example")
             (fixture-object-field report "publicCorsReportedOrigins")))
  (is (string= "https://runner.example,https://observer.example"
               (fixture-object-field report "publicCorsTelemetryOrigins")))
  (is (= 204 (fixture-object-field report "publicCorsPreflightStatus")))
  (is (= 200 (fixture-object-field report "publicCorsRpcStatus")))
  (is (= 403 (fixture-object-field report "publicCorsBlockedStatus")))
  (is (= 0 (fixture-object-field report "publicCorsEngineConnections")))
  (is (= 3 (fixture-object-field report "publicCorsPublicConnections")))
  (is (= 3 (fixture-object-field report "publicCorsTotalConnections"))))

(defun devnet-cli-assert-engine-cors-smoke-report (report)
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsOrigins")))
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsReportedOrigins")))
  (is (string= "https://engine-runner.example,https://engine-observer.example"
               (fixture-object-field report "engineCorsTelemetryOrigins")))
  (is (= 204 (fixture-object-field report "engineCorsPreflightStatus")))
  (is (= 200 (fixture-object-field report "engineCorsRpcStatus")))
  (is (= 403 (fixture-object-field report "engineCorsBlockedStatus")))
  (is (= 3 (fixture-object-field report "engineCorsEngineConnections")))
  (is (= 0 (fixture-object-field report "engineCorsPublicConnections")))
  (is (= 3 (fixture-object-field report "engineCorsTotalConnections"))))

(defun devnet-cli-assert-http-shaping-smoke-report (report)
  (is (= 405 (fixture-object-field report "engineHttpMethodStatus")))
  (is (= 415 (fixture-object-field report "engineHttpContentTypeStatus")))
  (is (= 405 (fixture-object-field report "publicHttpMethodStatus")))
  (is (= 415 (fixture-object-field report "publicHttpContentTypeStatus")))
  (is (= 2 (fixture-object-field report "httpShapingEngineConnections")))
  (is (= 2 (fixture-object-field report "httpShapingPublicConnections")))
  (is (= 4 (fixture-object-field report "httpShapingTotalConnections"))))

(defun devnet-cli-assert-vhost-smoke-report (report)
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhosts")))
  (is (equal '("public.runner" "localhost")
             (fixture-object-field report "publicVhosts")))
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhostsReported")))
  (is (equal '("public.runner" "localhost")
             (fixture-object-field report "publicVhostsReported")))
  (is (string= "engine.runner,localhost"
               (fixture-object-field report "engineVhostsTelemetry")))
  (is (string= "public.runner,localhost"
               (fixture-object-field report "publicVhostsTelemetry")))
  (is (= 200 (fixture-object-field report "engineVhostAllowedStatus")))
  (is (= 403 (fixture-object-field report "engineVhostBlockedStatus")))
  (is (= 200 (fixture-object-field report "publicVhostAllowedStatus")))
  (is (= 403 (fixture-object-field report "publicVhostBlockedStatus")))
  (is (= 2 (fixture-object-field report "vhostEngineConnections")))
  (is (= 2 (fixture-object-field report "vhostPublicConnections")))
  (is (= 4 (fixture-object-field report "vhostTotalConnections"))))

(defun devnet-cli-assert-rpc-prefix-smoke-report (report)
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefix")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefix")))
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefixReported")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefixReported")))
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefixTelemetry")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefixTelemetry")))
  (is (= 200 (fixture-object-field report "engineRpcPrefixStatus")))
  (is (= 404 (fixture-object-field report "engineRpcPrefixBlockedStatus")))
  (is (= 200 (fixture-object-field report "publicRpcPrefixStatus")))
  (is (= 404 (fixture-object-field report "publicRpcPrefixBlockedStatus")))
  (is (= 2 (fixture-object-field report "rpcPrefixEngineConnections")))
  (is (= 2 (fixture-object-field report "rpcPrefixPublicConnections")))
  (is (= 4 (fixture-object-field report "rpcPrefixTotalConnections"))))

(defun devnet-cli-assert-engine-only-http-shaping-report (report)
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsOrigins")))
  (is (string= "https://engine-runner.example"
               (fixture-object-field report "engineCorsHeader")))
  (is (string= "Origin"
               (fixture-object-field report "engineCorsVaryHeader")))
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhosts"))))

(defun devnet-cli-assert-engine-only-payload-report (report)
  (is (string= "shanghai-one-transfer-with-withdrawal"
               (fixture-object-field report "fixtureCase")))
  (is (string= +payload-status-valid+
               (fixture-object-field report "newPayloadStatus")))
  (is (string= +payload-status-valid+
               (fixture-object-field report "forkchoiceStatus")))
  (is (string= (fixture-object-field report "latestValidHash")
               (fixture-object-field report "forkchoiceHeadHash")))
  (is (stringp (fixture-object-field report "forkchoiceHeadNumber"))))

(defun devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report (report)
  (is (= 200
         (fixture-object-field report "hiddenBlobsV1Status")))
  (is (= -32601
         (fixture-object-field report "hiddenBlobsV1ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field report "hiddenBlobsV1ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenBlobsV2Status")))
  (is (= -32601
         (fixture-object-field report "hiddenBlobsV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field report "hiddenBlobsV2ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenPayloadBodiesByRangeV2Status")))
  (is (= -32601
         (fixture-object-field
          report
          "hiddenPayloadBodiesByRangeV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field
                report
                "hiddenPayloadBodiesByRangeV2ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenPayloadBodiesByHashV2Status")))
  (is (= -32601
         (fixture-object-field
          report
          "hiddenPayloadBodiesByHashV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field
                report
                "hiddenPayloadBodiesByHashV2ErrorMessage"))))

(defun devnet-cli-assert-engine-only-database-report (report)
  (is (stringp (fixture-object-field report "databaseFile")))
  (is (= (fixture-quantity-field report "forkchoiceHeadNumber")
         (fixture-object-field report "databaseHeadNumber")))
  (is (string= (fixture-object-field report "forkchoiceHeadHash")
               (fixture-object-field report "databaseHeadHash")))
  (is (fixture-object-field report "databaseStateAvailable")))

(defun devnet-cli-temp-directory (name)
  (let ((path
          (merge-pathnames
           (format nil "~A-~A/" name (devnet-cli-temp-token))
           #P"/private/tmp/")))
    (ensure-directories-exist path)
    path))

(defun devnet-cli-restored-public-connections (report)
  (+ 29
     (1- (fixture-object-field report "checkedBalanceCount"))
     (* 7 (1- (fixture-object-field report "transactionCount")))
     (* 6 (fixture-object-field report "checkedLogFilterCount"))
     (fixture-object-field report "checkedSimulationCount")
     (let ((errors
             (fixture-object-field report "databaseRpcPrunedStateErrors")))
       (if errors
           (length errors)
           0))))

(defun devnet-cli-assert-restored-full-block-transactions (report)
  (is (= (fixture-object-field report "transactionCount")
         (fixture-object-field
          report "databaseRpcFullBlockTransactionCount")))
  (is (= (fixture-object-field report "transactionCount")
         (fixture-object-field
          report "databaseRpcFullBlockByNumberTransactionCount")))
  (is (string= (fixture-object-field
                report "databaseRpcReceiptTransactionHash")
               (fixture-object-field
                report "databaseRpcFullBlockTransactionHash")))
  (is (string= (fixture-object-field
                report "databaseRpcReceiptTransactionHash")
               (fixture-object-field
                report "databaseRpcFullBlockByNumberTransactionHash")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcFullBlockTransactionIndex")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcFullBlockByNumberTransactionIndex"))))

(defun devnet-cli-assert-restored-log-filters (report)
  (let ((checked-log-count
          (fixture-object-field report "checkedLogCount"))
        (checked-filter-count
          (fixture-object-field report "checkedLogFilterCount")))
    (is (= checked-filter-count
           (fixture-object-field report "databaseRpcLogFilterCount")))
    (is (= checked-log-count
           (fixture-object-field
            report "databaseRpcLogFilterLogCount")))
    (is (= checked-filter-count
           (fixture-object-field
            report "databaseRpcLogFilterUninstallCount")))
    (let ((missing-error-codes
            (fixture-object-field
             report "databaseRpcLogFilterMissingErrorCodes")))
      (is (= checked-filter-count (length missing-error-codes)))
      (is (every (lambda (code)
                   (= -32602 code))
                 missing-error-codes)))))

(defun devnet-cli-assert-restored-block-filter (report)
  (is (string= (quantity-to-hex
                (1+ (fixture-object-field report "checkedLogFilterCount")))
               (fixture-object-field report "databaseRpcBlockFilterId")))
  (is (= 0
         (fixture-object-field
          report "databaseRpcBlockFilterChangeCount")))
  (is (= -32602
         (fixture-object-field
          report "databaseRpcBlockFilterGetLogsErrorCode")))
  (is (fixture-object-field
       report "databaseRpcBlockFilterUninstallResult"))
  (is (= -32602
         (fixture-object-field
          report "databaseRpcBlockFilterMissingErrorCode"))))

(defun devnet-cli-assert-txpool-subpool-persistence (report)
  (is (string= "0x1"
               (fixture-object-field report "txpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "txpoolStatusQueued")))
  (is (string= (fixture-object-field report "txpoolImportTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolPendingHash")))
  (is (string= (fixture-object-field report "txpoolImportRawTransaction")
               (fixture-object-field report "databaseRpcTxpoolRawTransaction")))
  (is (string= (fixture-object-field report "txpoolPendingSender")
               (fixture-object-field report "databaseRpcTxpoolSender")))
  (is (string= (fixture-object-field report "txpoolPendingNonce")
               (fixture-object-field report "databaseRpcTxpoolNonce")))
  (is (= (1+ (parse-integer
              (fixture-object-field report "txpoolPendingNonce")))
         (hex-to-quantity
          (fixture-object-field report "txpoolPendingSenderNonce"))))
  (is (string= (fixture-object-field report "txpoolPendingSenderNonce")
               (fixture-object-field
                report "databaseRpcTxpoolPendingSenderNonce")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolInspectSummary")))
  (is (string= "0x1"
               (fixture-object-field report "txpoolPendingFilterId")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report "txpoolPendingFilterHash")))
  (let ((filter-changes
          (fixture-object-field report "txpoolPendingFilterChanges")))
    (is (= 1 (length filter-changes)))
    (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
                 (first filter-changes))))
  (is (devnet-cli-empty-json-array-or-lossy-null-p
       (fixture-object-field report "txpoolPendingFilterEmptyChanges")))
  (is (eq t (fixture-object-field
             report "txpoolPendingFilterUninstallResult")))
  (is (= -32602
         (fixture-object-field
          report "txpoolPendingFilterMissingErrorCode")))
  (is (= 1
         (fixture-object-field report "txpoolRejournalSeconds")))
  (is (eq t
          (fixture-object-field
           report "txpoolRejournalObservedBeforeShutdown")))
  (is (= 3
         (fixture-object-field report "txpoolRejournalRecordCount")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report
                                     "txpoolRejournalTransactionHash")))
  (is (string= "pending"
               (fixture-object-field report "txpoolRejournalSubpool")))
  (is (= 1
         (fixture-object-field report "devPeriodSeconds")))
  (is (stringp
       (fixture-object-field report "devPeriodTransactionHash")))
  (is (string= (fixture-object-field report "devPeriodBlockNumber")
               (fixture-object-field
                report "devPeriodReceiptBlockNumber")))
  (is (string= (fixture-object-field report "devPeriodBlockHash")
               (fixture-object-field report "devPeriodReceiptBlockHash")))
  (is (string= "0x0"
               (fixture-object-field report "devPeriodTransactionIndex")))
  (is (string= "0x0"
               (fixture-object-field
                report "devPeriodTxpoolStatusPending")))
  (is (string= "0x0"
               (fixture-object-field
                report "devPeriodTxpoolStatusQueued")))
  (is (= 0
         (fixture-object-field
          report "devPeriodPendingTransactionCount")))
  (is (= 0
         (fixture-object-field report "devPeriodEngineConnections")))
  (is (= 7
         (fixture-object-field report "devPeriodPublicConnections")))
  (is (= 7
         (fixture-object-field report "devPeriodTotalConnections")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolBasefeeHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionRaw")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeRawTransaction")))
  (is (string= (fixture-object-field report "txpoolBasefeeNonce")
               (fixture-object-field report "databaseRpcTxpoolBasefeeNonce")))
  (is (string= (fixture-object-field report "txpoolBasefeeInspectSummary")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeInspectSummary")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolQueuedHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionRaw")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedRawTransaction")))
  (is (string= (fixture-object-field report "txpoolQueuedNonce")
               (fixture-object-field report "databaseRpcTxpoolQueuedNonce")))
  (is (string= (fixture-object-field report "txpoolQueuedInspectSummary")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedInspectSummary")))
  (is (string= "0x0"
               (fixture-object-field report "databaseRpcTxpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "databaseRpcTxpoolStatusQueued")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcTxpoolPendingBlockCount")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockHash")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingBlockBaseFee")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderNumber")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderParentHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingHeaderHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingHeaderNonce")))
  (is (string= (fixture-object-field
                report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee")
               (fixture-object-field
                report "databaseRpcTxpoolPendingBlockBaseFee")))
  (is (string= (fixture-object-field
                report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee")
               (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderBaseFee")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockTransactionHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockTransactionBlockHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingIndexHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingIndexBlockHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingRawByIndex")))
  (is (null (fixture-object-field report "databaseRpcTxpoolContentHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolContentFromHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeContentHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeContentFromHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedContentHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedContentFromHash")))
  (is (= 15
         (fixture-object-field report "databaseRpcTxpoolPublicConnections"))))

(defun devnet-cli-assert-side-reorg-persistence (report)
  (when (fixture-object-field report "databaseFile")
    (if (fixture-object-field report "databasePruneStateBefore")
        (dolist (field '("databaseRpcSideBlockHash"
                         "databaseRpcSideForkchoiceStatus"
                         "databaseRpcSideRejectedCheckpointError"
                         "databaseRpcSideBlockNumber"
                         "databaseRpcSideLatestBlockHash"
                         "databaseRpcSideTransactionReinserted"
                         "databaseRpcSideTransactionByHash"
                         "databaseRpcSideRawTransaction"
                         "databaseRpcSidePendingTransaction"
                         "databaseRpcSideReinsertedTransactionCount"
                         "databaseRpcSideReinsertedTransactionHashes"
                         "databaseRpcSideReceipt"
                         "databaseRpcSideHiddenReceiptCount"
                         "databaseRpcSideChildBlockHash"
                         "databaseRpcSideBlockReceiptsCount"
                         "databaseRpcSideLogCount"
                         "databaseRpcSideRestoredHeadNumber"
                         "databaseRpcSideRestoredHeadHash"
                         "databaseRpcSideRestoredRpcBlockNumber"
                         "databaseRpcSideRestoredRpcLatestBlockHash"
                         "databaseRpcSideRestoredSafeNumber"
                         "databaseRpcSideRestoredSafeHash"
                         "databaseRpcSideRestoredFinalizedNumber"
                         "databaseRpcSideRestoredFinalizedHash"
                         "databaseRpcSideRestoredRpcSafeNumber"
                         "databaseRpcSideRestoredRpcSafeHash"
                         "databaseRpcSideRestoredRpcFinalizedNumber"
                         "databaseRpcSideRestoredRpcFinalizedHash"
                         "databaseRpcSideRestoredSafeBalance"
                         "databaseRpcSideRestoredFinalizedBalance"
                         "databaseRpcSideRestoredRawTransaction"
                         "databaseRpcSideRestoredPendingTransaction"
                         "databaseRpcSideRestoredReinsertedTransactionCount"
                         "databaseRpcSideRestoredReinsertedTransactionHashes"
                         "databaseRpcSideRestoredReceipt"
                         "databaseRpcSideRestoredHiddenReceiptCount"
                         "databaseRpcSideRestoredChildBlockHash"
                         "databaseRpcSideRestoredChildRequireCanonicalError"
                         "databaseRpcSideRestoredChildRequireCanonicalErrors"
                         "databaseRpcSideRestoredBlockReceiptsCount"
                         "databaseRpcSideRestoredLogCount"
                         "databaseRpcSideRestoredPublicConnections"
                         "databaseRpcSideTotalConnections"
                         "databaseRpcSideEngineConnections"
                         "databaseRpcSidePublicConnections"))
          (is (eq nil (fixture-object-field report field))))
        (progn
          (is (string= "VALID"
                       (fixture-object-field
                        report "databaseRpcSideForkchoiceStatus")))
          (is (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field
                        report "databaseRpcSideRejectedCheckpointError")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideBlockNumber")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideLatestBlockHash")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredHeadHash")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredHeadNumber")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcBlockNumber")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcLatestBlockHash")))
          (is (string= (fixture-object-field report "safeBlockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeNumber")))
          (is (string= (fixture-object-field report "safeBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeHash")))
          (is (string= (fixture-object-field report "finalizedBlockNumber")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredFinalizedNumber")))
          (is (string= (fixture-object-field report "finalizedBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredFinalizedHash")))
          (is (string= (fixture-object-field report "safeBlockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcSafeNumber")))
          (is (string= (fixture-object-field report "safeBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcSafeHash")))
          (is (string= (fixture-object-field report "finalizedBlockNumber")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredRpcFinalizedNumber")))
          (is (string= (fixture-object-field report "finalizedBlockHash")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredRpcFinalizedHash")))
          (is (string= (fixture-object-field
                        report "checkedCheckpointBalance")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeBalance")))
          (is (string= (fixture-object-field
                        report "checkedCheckpointBalance")
                       (fixture-object-field
                        report "databaseRpcSideRestoredFinalizedBalance")))
          (is (not (string= (fixture-object-field
                             report "databaseRpcBlockHash")
                            (fixture-object-field
                             report "databaseRpcSideBlockHash"))))
          (is (string= (fixture-object-field report "databaseRpcBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideChildBlockHash")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideBlockReceiptsCount")))
          (is (= 0
                 (fixture-object-field report "databaseRpcSideLogCount")))
          (if (fixture-object-field report
                                    "databaseRpcSideTransactionReinserted")
              (progn
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report "databaseRpcSideTransactionByHash")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "transactionIndex")))
                (is (string= (fixture-object-field
                              report "databaseRpcRawTransactionByHash")
                             (fixture-object-field
                              report "databaseRpcSideRawTransaction")))
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report "databaseRpcSidePendingTransaction")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "transactionIndex")))
                (is (string= (fixture-object-field
                              report "databaseRpcRawTransactionByHash")
                             (fixture-object-field
                              report
                              "databaseRpcSideRestoredRawTransaction")))
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report
                               "databaseRpcSideRestoredPendingTransaction")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "transactionIndex"))))
              (progn
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideTransactionByHash")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideRawTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSidePendingTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideRestoredRawTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report
                         "databaseRpcSideRestoredPendingTransaction")))))
          (when (fixture-object-field report
                                      "databaseRpcSideTransactionReinserted")
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report "databaseRpcSideReinsertedTransactionCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredReinsertedTransactionCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report "databaseRpcSideHiddenReceiptCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredHiddenReceiptCount")))
            (is (equal (fixture-object-field
                        report "databaseRpcSideReinsertedTransactionHashes")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredReinsertedTransactionHashes")))
            (is (member (fixture-object-field
                         report "databaseRpcReceiptTransactionHash")
                        (fixture-object-field
                         report
                         "databaseRpcSideReinsertedTransactionHashes")
                        :test #'string=)))
          (is (eq nil
                  (fixture-object-field report "databaseRpcSideReceipt")))
          (is (eq nil
                  (fixture-object-field
                   report "databaseRpcSideRestoredReceipt")))
          (is (string= (fixture-object-field report "databaseRpcBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredChildBlockHash")))
          (is (string= "eth_getBalance block hash is not canonical"
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredChildRequireCanonicalError")))
          (is (equal (devnet-cli-noncanonical-state-error-messages)
                     (fixture-object-field
                      report
                      "databaseRpcSideRestoredChildRequireCanonicalErrors")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideRestoredBlockReceiptsCount")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideRestoredLogCount")))
          (let* ((transaction-count
                   (fixture-object-field report "databaseRpcTransactionCount"))
                 (extra-transaction-count (max 0 (1- transaction-count)))
                 (side-public-connections (+ 9 extra-transaction-count))
                 (restored-public-connections
                   (+ 20 extra-transaction-count)))
            (is (= 3
                   (fixture-object-field
                    report "databaseRpcSideEngineConnections")))
            (is (= side-public-connections
                   (fixture-object-field
                    report "databaseRpcSidePublicConnections")))
            (is (= restored-public-connections
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredPublicConnections")))
            (is (= (+ 3 side-public-connections
                      restored-public-connections)
                   (fixture-object-field
                    report "databaseRpcSideTotalConnections"))))))))

(defun devnet-cli-pruned-state-error-messages ()
  '("eth_getBalance state is not available"
    "eth_getTransactionCount state is not available"
    "eth_getCode state is not available"
    "eth_getStorageAt state is not available"
    "eth_getProof state is not available"
    "eth_call state is not available"
    "eth_estimateGas state is not available"
    "eth_createAccessList state is not available"))

(defun devnet-cli-noncanonical-state-error-messages ()
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun devnet-cli-pruned-state-covered-p (report prune-boundary)
  (< (hex-to-quantity (fixture-object-field report "safeBlockNumber"))
     prune-boundary))

(defun devnet-cli-assert-pruned-state-case
    (case prune-boundary)
  (if (devnet-cli-pruned-state-covered-p case prune-boundary)
      (progn
        (is (eq nil
                (fixture-object-field
                 case "databasePrunedStateAvailable")))
        (is (string= "eth_getBalance state is not available"
                     (fixture-object-field
                      case "databaseRpcPrunedStateError")))
        (is (equal (devnet-cli-pruned-state-error-messages)
                   (fixture-object-field
                    case "databaseRpcPrunedStateErrors"))))
      (progn
        (is (eq t
                (fixture-object-field
                 case "databasePrunedStateAvailable")))
        (is (eq nil
                (fixture-object-field
                 case "databaseRpcPrunedStateError")))
        (is (eq nil
                (fixture-object-field
                 case "databaseRpcPrunedStateErrors"))))))

(defun devnet-cli-assert-pruned-state-suite
    (report cases prune-boundary)
  (let ((pruned-case-count
          (count-if
           (lambda (case)
             (devnet-cli-pruned-state-covered-p case prune-boundary))
           cases)))
    (is (< 0 pruned-case-count))
    (is (< pruned-case-count (length cases)))
    (is (= prune-boundary
           (fixture-object-field report "databasePruneStateBefore")))
    (is (= pruned-case-count
           (fixture-object-field
            report "databasePrunedStateCaseCount")))
    (is (= pruned-case-count
           (fixture-object-field
            report "databaseRpcPrunedStateErrorCaseCount")))
    (dolist (case cases)
      (devnet-cli-assert-pruned-state-case case prune-boundary))))

(defun devnet-cli-engine-fixture-payload-number (case-name)
  (let* ((case (select-engine-newpayload-v2-fixture-case
                +engine-newpayload-v2-fixture-path+
                case-name))
         (payload (fixture-object-field case "payload")))
    (fixture-object-field payload "number")))

(defun devnet-cli-engine-fixture-parent-genesis-config (case)
  (let ((config (fixture-object-field case "config")))
    (list
     (cons "chainId" (fixture-object-field case "chainId"))
     (cons "terminalTotalDifficulty" "0x0")
     (cons "homesteadBlock" "0x0")
     (cons "eip150Block" "0x0")
     (cons "eip155Block" "0x0")
     (cons "eip158Block" "0x0")
     (cons "byzantiumBlock" "0x0")
     (cons "constantinopleBlock" "0x0")
     (cons "petersburgBlock" "0x0")
     (cons "istanbulBlock" "0x0")
     (cons "berlinBlock" (fixture-object-field config "berlinBlock"))
     (cons "londonBlock" (fixture-object-field config "londonBlock"))
     (cons "shanghaiTime" (fixture-object-field config "shanghaiTime")))))

(defun devnet-cli-engine-fixture-genesis-account (account)
  (let ((fields
          (list (cons "balance" (fixture-object-field account "balance"))
                (cons "nonce" (fixture-object-field account "nonce")))))
    (when (fixture-object-field account "code")
      (setf fields (append fields
                           (list (cons "code"
                                       (fixture-object-field account
                                                             "code"))))))
    (when (fixture-object-field account "storage")
      (setf fields (append fields
                           (list (cons "storage"
                                       (fixture-object-field account
                                                             "storage"))))))
    (cons (fixture-object-field account "address") fields)))

(defun devnet-cli-engine-fixture-parent-genesis-object (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent)))
    (list
     (cons "format" "ethereum-lisp/engine-fixture-parent-genesis-v1")
     (cons "config" (devnet-cli-engine-fixture-parent-genesis-config case))
     (cons "parentHash"
           "0x0000000000000000000000000000000000000000000000000000000000000000")
     (cons "number" (fixture-object-field parent "number"))
     (cons "nonce" "0x0")
     (cons "timestamp" (fixture-object-field parent "timestamp"))
     (cons "extraData" "0x")
     (cons "gasLimit" (fixture-object-field parent "gasLimit"))
     (cons "gasUsed" (fixture-object-field parent "gasUsed"))
     (cons "difficulty" "0x0")
     (cons "mixHash"
           "0x0000000000000000000000000000000000000000000000000000000000000000")
     (cons "coinbase" (fixture-object-field parent "feeRecipient"))
     (cons "baseFeePerGas" (fixture-object-field parent "baseFeePerGas"))
     (cons "stateRoot" (hash32-to-hex (state-db-root parent-state)))
     (cons "alloc"
           (mapcar #'devnet-cli-engine-fixture-genesis-account
                   (fixture-object-field parent "accounts"))))))

(defun devnet-cli-engine-fixture-parent-genesis-with-txpool-account (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent))
         (sender (devnet-cli-txpool-sender-address))
         (genesis (devnet-cli-engine-fixture-parent-genesis-object case))
         (alloc (fixture-object-field genesis "alloc"))
         (account
           (list (cons "balance"
                       (quantity-to-hex +devnet-cli-txpool-balance+))
                 (cons "nonce" "0x0"))))
    (state-db-set-account
     parent-state
     sender
     (make-state-account :nonce 0 :balance +devnet-cli-txpool-balance+))
    (setf (cdr (assoc "stateRoot" genesis :test #'string=))
          (hash32-to-hex (state-db-root parent-state)))
    (setf (cdr (assoc "alloc" genesis :test #'string=))
          (append alloc (list (cons (address-to-hex sender) account))))
    genesis))

(defun devnet-cli-engine-fixture-parent-block (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (parent-header
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary fee-recipient
            :state-root (state-db-root parent-state)
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field parent "number")
            :gas-limit (fixture-quantity-field parent "gasLimit")
            :gas-used (fixture-quantity-field parent "gasUsed")
            :timestamp (fixture-quantity-field parent "timestamp")
            :base-fee-per-gas (fixture-quantity-field parent "baseFeePerGas")
            :withdrawals-root (withdrawal-list-root '()))))
    (make-block :header parent-header)))

(defun devnet-cli-engine-fixture-child-block (case)
  (let* ((config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (transactions
           (mapcar (lambda (raw)
                     (transaction-from-encoding (hex-to-bytes raw)))
                   (fixture-object-field payload-case "transactions")))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
         (child-state (state-db-copy parent-state))
         (child-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (fixture-quantity-field payload-case "timestamp")
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     child-state
     transactions
     :expected-chain-id (chain-config-chain-id config)
     :header child-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-cli-engine-fixture-side-sibling-block (case parent-block)
  (let* ((config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (side-state (state-db-copy parent-state))
         (side-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash
            (hash32-from-hex
             "0x0300000000000000000000000000000000000000000000000000000000000000")
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (1+ (fixture-quantity-field payload-case "timestamp"))
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     side-state
     '()
     :expected-chain-id (chain-config-chain-id config)
     :header side-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-cli-remote-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash
      (hash32-from-hex
       "0x9999999999999999999999999999999999999999999999999999999999999999")
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp parent-header))
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-cli-invalid-child-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash parent-block)
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (block-header-timestamp parent-header)
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-cli-http-body (response)
  (let ((boundary (search (format nil "~C~C~C~C"
                                  #\Return #\Newline
                                  #\Return #\Newline)
                          response)))
    (subseq response (+ boundary 4))))

(defun devnet-cli-http-status (response)
  (let* ((line-end (position #\Return response))
         (status-line (subseq response 0 line-end)))
    (parse-integer status-line :start 9 :end 12)))

(defun devnet-cli-json-rpc-http-request
    (body &key token (target "/") (host "localhost") origin)
  (with-output-to-string (stream)
    (format stream "POST ~A HTTP/1.1~%Host: ~A~%" target host)
    (format stream "Content-Type: application/json~%")
    (when origin
      (format stream "Origin: ~A~%" origin))
    (when token
      (format stream "Authorization: Bearer ~A~%" token))
    (format stream "Content-Length: ~D~%~%~A" (length body) body)))

(defun devnet-cli-json-rpc-duplicate-auth-http-request
    (body first-token second-token &key (target "/") (host "localhost")
       origin)
  (with-output-to-string (stream)
    (format stream "POST ~A HTTP/1.1~%Host: ~A~%" target host)
    (format stream "Content-Type: application/json~%")
    (when origin
      (format stream "Origin: ~A~%" origin))
    (format stream "Authorization: Bearer ~A~%" first-token)
    (format stream "Authorization: Bearer ~A~%" second-token)
    (format stream "Content-Length: ~D~%~%~A" (length body) body)))

(defun devnet-cli-options-http-request
    (&key (target "/") (host "localhost") origin
       (request-method "POST") request-headers)
  (with-output-to-string (stream)
    (format stream "~A ~A HTTP/1.1~%Host: ~A~%"
            request-method target host)
    (when origin
      (format stream "Origin: ~A~%" origin))
    (dolist (header request-headers)
      (format stream "~A: ~A~%" (car header) (cdr header)))
    (format stream "Content-Length: 0~%~%")))

(defun devnet-cli-set-node-store-config (node store config)
  (let* ((old-config (ethereum-lisp.cli:devnet-node-config node))
         (old-network-id (ethereum-lisp.cli::devnet-node-network-id node))
         (default-network-id-p
           (= old-network-id (chain-config-chain-id old-config)))
         (effective-network-id
           (if default-network-id-p
               (chain-config-chain-id config)
               old-network-id)))
    (setf (ethereum-lisp.cli:devnet-node-store node) store
        (ethereum-lisp.cli:devnet-node-config node) config
        (ethereum-lisp.cli::devnet-node-network-id node)
        effective-network-id
        (engine-rpc-http-service-store
         (ethereum-lisp.cli:devnet-node-service node))
        store
        (engine-rpc-http-service-config
         (ethereum-lisp.cli:devnet-node-service node))
        config
        (ethereum-lisp.core::engine-rpc-http-service-network-id
         (ethereum-lisp.cli:devnet-node-service node))
        effective-network-id
        (engine-rpc-http-service-store
         (ethereum-lisp.cli:devnet-node-public-service node))
        store
        (engine-rpc-http-service-config
         (ethereum-lisp.cli:devnet-node-public-service node))
        config
        (ethereum-lisp.core::engine-rpc-http-service-network-id
         (ethereum-lisp.cli:devnet-node-public-service node))
        effective-network-id))
  node)

(defun devnet-cli-engine-forkchoice-v2-request
    (id head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (engine-fixture-forkchoice-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "method" request :test #'string=))
          "engine_forkchoiceUpdatedV2")
    request))

(defun devnet-cli-payload-attributes-v2
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient))
          (cons "withdrawals" '()))))

(defun devnet-cli-payload-attributes-v1
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient)))))

(defun devnet-cli-pre-shanghai-genesis-object ()
  (let* ((genesis
           (parse-json (devnet-cli-file-string +devnet-cli-genesis-fixture+)))
         (config
           (remove "shanghaiTime"
                   (fixture-object-field genesis "config")
                   :key #'car
                   :test #'string=)))
    (setf (cdr (assoc "format" genesis :test #'string=))
          "ethereum-lisp/pre-shanghai-engine-v1-script-fixture")
    (setf (cdr (assoc "config" genesis :test #'string=)) config)
    genesis))

(defun devnet-cli-engine-new-payload-v1-request (id payload)
  (let ((request (engine-fixture-payload-request id payload)))
    (setf (cdr (assoc "method" request :test #'string=))
          "engine_newPayloadV1")
    request))

(defun devnet-cli-engine-forkchoice-v1-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (engine-fixture-forkchoice-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun devnet-cli-engine-forkchoice-v2-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (devnet-cli-engine-forkchoice-v2-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun make-devnet-cli-one-shot-listener (endpoint)
  (let ((accepted-p nil))
    (make-engine-rpc-http-listener
     :endpoint endpoint
     :accept-function
     (lambda ()
       (unless accepted-p
         (setf accepted-p t)
         (make-engine-rpc-http-connection
          :input-stream
          (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
          :output-stream (make-string-output-stream)
          :close-function (lambda () nil))))
     :close-function (lambda () nil))))

