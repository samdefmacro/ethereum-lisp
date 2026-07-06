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
  (is (= 18 (fixture-object-field report "engineConnections")))
  (is (= 0 (fixture-object-field report "publicConnections")))
  (is (= 18 (fixture-object-field report "totalConnections"))))

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

(deftest devnet-node-loads-genesis-summary
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (head (ethereum-lisp.cli:devnet-node-genesis-block node))
         (head-hash (block-hash head))
         (funded (address-from-hex "0x0000000000000000000000000000000000001001")))
    (is (= 1337 (getf summary :chain-id)))
    (is (= 0 (getf summary :head-number)))
    (is (string= "127.0.0.1:0" (getf summary :engine-endpoint)))
    (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
    (is (string= "/" (getf summary :engine-rpc-prefix)))
    (is (string= "/" (getf summary :public-rpc-prefix)))
    (is (equal (devnet-cli-current-process-id) (getf summary :process-id)))
    (is (string= (hash32-to-hex head-hash) (getf summary :head-hash)))
    (is (null (getf summary :safe-number)))
    (is (null (getf summary :safe-hash)))
    (is (null (getf summary :finalized-number)))
    (is (null (getf summary :finalized-hash)))
    (is (getf summary :state-available-p))
    (is (not (getf summary :auth-required-p)))
    (is (not (getf summary :jwt-secret-path)))
    (is (null (getf summary :public-api-modules)))
    (is (string= "/"
                 (engine-rpc-http-service-rpc-prefix
                  (ethereum-lisp.cli:devnet-node-service node))))
    (is (string= "/"
                 (engine-rpc-http-service-rpc-prefix
                  (ethereum-lisp.cli:devnet-node-public-service node))))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-service node))
                 "engine_exchangeCapabilities"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-service node))
                      "eth_chainId")))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-public-service node))
                 "eth_chainId"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-public-service node))
                      "engine_exchangeCapabilities")))
    (is (= #xde0b6b3a7640000
           (chain-store-account-balance store head-hash funded)))))

(deftest devnet-node-splits-engine-and-public-rpc-methods
  (let* ((coinbase
           (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545
                :network-id 7331
                :coinbase coinbase))
         (engine-service (ethereum-lisp.cli:devnet-node-service node))
         (public-service (ethereum-lisp.cli:devnet-node-public-service node))
         (engine-store (engine-rpc-http-service-store engine-service))
         (engine-config (engine-rpc-http-service-config engine-service))
         (public-filter (engine-rpc-http-service-allowed-method-p
                         public-service))
         (engine-filter (engine-rpc-http-service-allowed-method-p
                         engine-service)))
    (let ((engine-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
         (public-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}"
              engine-store
              engine-config
              :allowed-method-p public-filter)))
          (engine-rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"rpc_modules\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
          (public-rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"rpc_modules\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.core::engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (public-coinbase-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"eth_coinbase\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.core::engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (network-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"net_version\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter))))
      (is (string= (address-to-hex coinbase)
                   (getf (ethereum-lisp.cli:devnet-node-summary node)
                         :coinbase)))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.core::engine-rpc-http-service-coinbase
                    engine-service))))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.core::engine-rpc-http-service-coinbase
                    public-service))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field public-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-rpc-modules-response "error")
              "code")))
      (let ((modules
              (fixture-object-field public-rpc-modules-response "result")))
        (is (string= "1.0" (fixture-object-field modules "eth")))
        (is (string= "1.0" (fixture-object-field modules "net")))
        (is (string= "1.0" (fixture-object-field modules "rpc")))
        (is (string= "1.0" (fixture-object-field modules "txpool")))
        (is (string= "1.0" (fixture-object-field modules "web3"))))
      (is (string= "0x539"
                   (fixture-object-field chain-id-response "result")))
      (is (string= (address-to-hex coinbase)
                   (fixture-object-field public-coinbase-response
                                         "result")))
      (is (string= "7331"
                   (fixture-object-field network-response "result"))))))

(deftest devnet-node-public-http-api-filter-limits-modules
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--http.api" "eth,net")))
         (http-api-modules (getf options :http-api-modules))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :public-allowed-method-p
                (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                 http-api-modules)
                :public-api-modules http-api-modules))
         (public-service (ethereum-lisp.cli:devnet-node-public-service node))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (summary-json
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (store (engine-rpc-http-service-store public-service))
         (config (engine-rpc-http-service-config public-service))
         (public-filter (engine-rpc-http-service-allowed-method-p
                         public-service)))
    (is (equal '("eth" "net") http-api-modules))
    (is (equal '("eth" "net") (getf summary :public-api-modules)))
    (is (equal '("eth" "net")
               (cdr (assoc "publicApiModules" summary-json :test #'string=))))
    (is (funcall public-filter "eth_chainId"))
    (is (funcall public-filter "net_version"))
    (is (funcall public-filter "rpc_modules"))
    (is (not (funcall public-filter "web3_clientVersion")))
    (is (not (funcall public-filter "txpool_status")))
    (is (not (funcall public-filter "engine_exchangeCapabilities")))
    (let ((chain-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (web3-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"web3_clientVersion\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"rpc_modules\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (txpool-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter))))
      (is (string= "0x539"
                   (fixture-object-field chain-response "result")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field web3-response "error")
              "code")))
      (let ((modules
              (fixture-object-field rpc-modules-response "result")))
        (is (string= "1.0" (fixture-object-field modules "eth")))
        (is (string= "1.0" (fixture-object-field modules "net")))
        (is (string= "1.0" (fixture-object-field modules "rpc")))
        (is (not (fixture-object-field modules "txpool")))
        (is (not (fixture-object-field modules "web3"))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field txpool-response "error")
              "code"))))))

(deftest devnet-node-start-serves-engine-and-public-listeners
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-accepted-p nil)
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "engine"
             :accept-function
             (lambda ()
               (unless engine-accepted-p
                 (setf engine-accepted-p t)
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                  :output-stream (make-string-output-stream)
                  :close-function (lambda () nil))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "public"
             :accept-function
             (lambda ()
               (loop until engine-accepted-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                :output-stream (make-string-output-stream)
                :close-function (lambda () nil)))
             :close-function (lambda () nil))
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 1 (getf summary :public-connections)))
    (is (= 2 (getf summary :total-connections)))))

(deftest devnet-node-start-serves-engine-only-when-public-listener-is-disabled
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-devnet-cli-one-shot-listener "engine")
            nil
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 0 (getf summary :public-connections)))
    (is (= 1 (getf summary :total-connections)))))

(deftest devnet-node-split-listeners-serve-authenticated-engine-and-public-rpc
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)
                         :engine-rpc-prefix "/engine"
                         :public-rpc-prefix "/rpc"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":11,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (public-body
                    "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"eth_chainId\",\"params\":[]}")
                  (engine-output (make-string-output-stream))
                  (public-output (make-string-output-stream))
                  (engine-accepted-p nil)
                  (engine-closed-p nil)
                  (public-closed-p nil)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine"
                      :accept-function
                      (lambda ()
                        (unless engine-accepted-p
                          (setf engine-accepted-p t)
                          (make-engine-rpc-http-connection
                           :input-stream
                           (make-string-input-stream
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine"))
                           :output-stream engine-output
                           :close-function
                           (lambda () (setf engine-closed-p t)))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public"
                      :accept-function
                      (lambda ()
                        (loop until engine-accepted-p
                              do (sleep 0.001))
                        (make-engine-rpc-http-connection
                         :input-stream
                         (make-string-input-stream
                          (devnet-cli-json-rpc-http-request
                           public-body
                           :target "/rpc"))
                         :output-stream public-output
                         :close-function
                         (lambda () (setf public-closed-p t))))
                      :close-function (lambda () nil))
                     :max-connections 1)))
             (is (= 1 (getf summary :engine-connections)))
             (is (= 1 (getf summary :public-connections)))
             (is (= 2 (getf summary :total-connections)))
             (is engine-closed-p)
             (is public-closed-p)
             (let* ((engine-response (get-output-stream-string engine-output))
                    (public-response (get-output-stream-string public-output))
                    (engine-rpc (parse-json
                                 (devnet-cli-http-body engine-response)))
                    (public-rpc (parse-json
                                 (devnet-cli-http-body public-response)))
                    (local-client
                      (first (fixture-object-field engine-rpc "result"))))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 11 (fixture-object-field engine-rpc "id")))
               (is (string= "ethereum-lisp"
                            (fixture-object-field local-client "name")))
               (is (= 12 (fixture-object-field public-rpc "id")))
               (is (string= "0x539"
                            (fixture-object-field public-rpc "result"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-split-listeners-import-payload-and-serve-public-state
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((case
                    (select-engine-newpayload-v2-fixture-case
                     +engine-newpayload-v2-fixture-path+
                     "shanghai-one-transfer-with-withdrawal"))
                  (node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)))
                  (store (make-engine-payload-memory-store))
                  (config (engine-fixture-chain-config case))
                  (parent (fixture-object-field case "parent"))
                  (payload-case (fixture-object-field case "payload"))
                  (expect (fixture-object-field case "expect"))
                  (parent-state (engine-fixture-parent-state parent))
                  (fee-recipient (fixture-address-field parent "feeRecipient"))
                  (transactions
                    (mapcar (lambda (raw)
                              (transaction-from-encoding (hex-to-bytes raw)))
                            (fixture-object-field payload-case
                                                  "transactions")))
                  (withdrawals
                    (mapcar #'engine-fixture-withdrawal
                            (fixture-object-field payload-case
                                                  "withdrawals")))
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
                     :base-fee-per-gas
                     (fixture-quantity-field parent "baseFeePerGas")
                     :withdrawals-root (withdrawal-list-root '())))
                  (parent-block (make-block :header parent-header))
                  (child-state (state-db-copy parent-state))
                  (child-header
                    (make-block-header
                     :parent-hash (block-hash parent-block)
                     :beneficiary fee-recipient
                     :mix-hash (zero-hash32)
                     :number (fixture-quantity-field payload-case "number")
                     :gas-limit (fixture-quantity-field payload-case
                                                        "gasLimit")
                     :gas-used 0
                     :timestamp (fixture-quantity-field payload-case
                                                        "timestamp")
                     :base-fee-per-gas
                     (fixture-quantity-field payload-case "baseFeePerGas")))
                  (child-block
                    (execute-signed-block
                     child-state
                     transactions
                     :expected-chain-id (chain-config-chain-id config)
                     :header child-header
                     :chain-config config
                     :withdrawals withdrawals))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (recipient (fixture-address-field expect "recipient"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 21 payload))
                      new-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        22 (block-hash child-block)
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                     forkchoice-output)))
                  (public-requests
                    (list
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 31)
                             (cons "method" "eth_blockNumber")
                             (cons "params" '())))
                      block-number-output)
                     (cons
                      (json-encode
                       (engine-fixture-balance-request 32 recipient))
                      balance-output)))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (public-served-count 0))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint "engine"
                       :accept-function
                       (lambda ()
                         (when engine-requests
                           (destructuring-bind (body . output)
                               (pop engine-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request
                                body :token token))
                              :output-stream output
                              :close-function
                              (lambda ()
                                (incf engine-served-count)
                                (when (= engine-served-count 2)
                                  (setf engine-done-p t)))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint "public"
                       :accept-function
                       (lambda ()
                         (loop until engine-done-p
                               do (sleep 0.001))
                         (when public-requests
                           (destructuring-bind (body . output)
                               (pop public-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request body))
                              :output-stream output
                              :close-function
                              (lambda () (incf public-served-count))))))
                       :close-function (lambda () nil))
                      :max-connections 2)))
               (is (= 2 (getf summary :engine-connections)))
               (is (= 2 (getf summary :public-connections)))
               (is (= 4 (getf summary :total-connections)))
               (is (= 2 engine-served-count))
               (is (= 2 public-served-count))
               (let* ((new-payload-response
                        (get-output-stream-string new-payload-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status balance-response)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-start-closes-engine-listener-on-public-error
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function (lambda () (error "public listener failed"))
            :close-function (lambda () nil))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 1))
    (is engine-closed-p)))

(deftest devnet-node-start-closes-public-listener-on-engine-error
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function (lambda () (error "engine listener failed"))
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function
            (lambda ()
              (loop until public-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf public-closed-p t)))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 1))
    (is engine-closed-p)
    (is public-closed-p)))

(deftest devnet-shutdown-controller-stops-split-listeners
  #-sbcl
  (skip-test "Devnet split listener shutdown requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (controller
           (ethereum-lisp.cli:make-devnet-shutdown-controller))
         (engine-accepting-p nil)
         (public-accepting-p nil)
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (setf engine-accepting-p t)
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function
            (lambda ()
              (setf public-accepting-p t)
              (loop until public-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf public-closed-p t))))
         (summary nil))
    (let ((serve-thread
            (sb-thread:make-thread
             (lambda ()
               (setf summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      engine-listener
                      public-listener
                      :shutdown-controller controller)))
             :name "ethereum-lisp-devnet-shutdown-test")))
      (loop repeat 1000
            until (and engine-accepting-p public-accepting-p)
            do (sleep 0.001))
      (is engine-accepting-p)
      (is public-accepting-p)
      (is (not (ethereum-lisp.cli:devnet-shutdown-requested-p controller)))
      (is (ethereum-lisp.cli:devnet-shutdown-request controller))
      (sb-thread:join-thread serve-thread)
      (is (ethereum-lisp.cli:devnet-shutdown-requested-p controller))
      (is engine-closed-p)
      (is public-closed-p)
      (is (= 0 (getf summary :engine-connections)))
      (is (= 0 (getf summary :public-connections)))
      (is (= 0 (getf summary :total-connections))))))

(deftest devnet-listener-ready-callback-reports-bound-endpoints
  #-sbcl
  (skip-test "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((ready-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-bound-ready" "json"))
         (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0
                :public-port 0
                :telemetry-sink sink))
         (callback-called-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18551"
            :accept-function (lambda () nil)
            :close-function (lambda () nil)))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18545"
            :accept-function (lambda () nil)
            :close-function (lambda () nil))))
    (unwind-protect
         (let ((summary
                 (ethereum-lisp.cli:start-devnet-node-listeners
                  node
                  engine-listener
                  public-listener
                  :max-connections 0
                  :on-listeners-ready
                  (lambda (engine public)
                    (setf callback-called-p t)
                    (ethereum-lisp.cli::devnet-cli-write-ready-file
                     node
                     ready-path
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))
                    (ethereum-lisp.cli::devnet-cli-log-event
                     node
                     "devnet.ready"
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))))))
           (is callback-called-p)
           (is (= 0 (getf summary :engine-connections)))
           (is (= 0 (getf summary :public-connections)))
           (ethereum-lisp.cli::devnet-cli-log-event
            node
            "devnet.shutdown"
            :engine-endpoint
            (engine-rpc-http-listener-endpoint engine-listener)
            :rpc-endpoint
            (engine-rpc-http-listener-endpoint public-listener)
            :connection-summary summary)
           (let ((ready-summary
                   (parse-json (devnet-cli-file-string ready-path))))
             (is (string= "127.0.0.1:18551"
                          (fixture-object-field ready-summary
                                                "engineEndpoint")))
             (is (string= "127.0.0.1:18545"
                          (fixture-object-field ready-summary
                                                "rpcEndpoint")))
             (is (equal (devnet-cli-current-process-id)
                        (fixture-object-field ready-summary
                                              "processId"))))
           (let ((events
                   (remove-if-not
                    (lambda (event)
                      (member
                       (ethereum-lisp.telemetry:telemetry-event-name event)
                       '("devnet.ready" "devnet.shutdown")
                       :test #'string=))
                    (ethereum-lisp.telemetry:telemetry-events sink))))
             (is (= 2 (length events)))
             (dolist (event events)
               (let ((fields
                       (ethereum-lisp.telemetry:telemetry-event-fields
                        event)))
                 (is (string= "127.0.0.1:18551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:18545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (ethereum-lisp.telemetry:telemetry-event-name
                                             event))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path)))))

(deftest devnet-listener-ready-callback-error-closes-listeners
  #-sbcl
  (skip-test "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function (lambda () nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function (lambda () nil)
            :close-function (lambda () (setf public-closed-p t)))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 0
       :on-listeners-ready
       (lambda (engine public)
         (declare (ignore engine public))
         (error "listener ready callback failed"))))
    (is engine-closed-p)
    (is public-closed-p)))

(deftest devnet-node-loads-jwt-secret-file
  (let ((path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            path
            (format nil "0x~A~%" +devnet-cli-jwt-secret+))
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :jwt-secret-path (namestring path)))
                  (summary (ethereum-lisp.cli:devnet-node-summary node))
                  (service (ethereum-lisp.cli:devnet-node-service node)))
             (is (getf summary :auth-required-p))
             (is (string= (namestring path)
                          (getf summary :jwt-secret-path)))
             (is (= 32 (length (engine-rpc-http-service-jwt-secret service))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest devnet-cli-main-no-serve-prints-summary
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "0"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (read-from-string (get-output-stream-string output))))
      (is (= 1337 (getf summary :chain-id)))
      (is (= 0 (getf summary :head-number)))
      (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
      (is (getf summary :state-available-p)))))

(deftest devnet-cli-main-kzg-verifier-command-scopes-hooks
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (missing-output (make-string-output-stream))
        (missing-errors (make-string-output-stream))
        (non-executable-output (make-string-output-stream))
        (non-executable-errors (make-string-output-stream))
        (kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-scoped" "sh"))
        (missing-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-missing" "sh"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-non-executable" "sh"))
        (old-point-verifier *kzg-point-proof-verifier*)
        (old-blob-verifier *kzg-blob-proof-verifier*))
    (unwind-protect
         (progn
           (setf *kzg-point-proof-verifier* nil
                 *kzg-blob-proof-verifier* nil)
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command" (namestring kzg-command)
                         "--kzg-verifier-timeout" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= (namestring kzg-command)
                          (fixture-object-field
                           summary "kzgVerifierCommand")))
             (is (= 2 (fixture-object-field
                       summary "kzgVerifierTimeoutSeconds")))
             (is (fixture-object-field
                  summary "kzgProofVerificationAvailable")))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring missing-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream missing-output
                   :error-stream missing-errors)))
           (is (string= "" (get-output-stream-string missing-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string missing-errors)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring non-executable-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream non-executable-output
                   :error-stream non-executable-errors)))
           (is (string= ""
                        (get-output-stream-string non-executable-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string non-executable-errors)))
           (is (not (kzg-proof-verification-available-p))))
      (setf *kzg-point-proof-verifier* old-point-verifier
            *kzg-blob-proof-verifier* old-blob-verifier)
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file missing-kzg-command)
        (delete-file missing-kzg-command))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command)))))

(deftest ethereum-lisp-script-engine-only-kzg-verifier-advertises-blob-capabilities
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (kzg-command
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-command" "sh"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-ready" "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--kzg.verifier-command"
                        (namestring kzg-command)
                        "--kzg.verifier-timeout"
                        "2"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "1"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (capabilities-body
                      "{\"jsonrpc\":\"2.0\",\"id\":715,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    capabilities-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= (namestring kzg-command)
                            (fixture-object-field ready-summary
                                                  "kzgVerifierCommand")))
               (is (= 2 (fixture-object-field
                         ready-summary "kzgVerifierTimeoutSeconds")))
               (is (fixture-object-field
                    ready-summary "kzgProofVerificationAvailable"))
               (handler-case
                   (setf capabilities-response
                         (devnet-cli-http-endpoint-request
                          engine-endpoint
                          (devnet-cli-json-rpc-http-request
                           capabilities-body)))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result")))
                 (is (= 715 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-kzg-backed-engine-capability-list
                  capabilities-result))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name)))))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= (namestring kzg-command)
                                      (fixture-object-field
                                       summary "kzgVerifierCommand")))
                         (is (= 2 (fixture-object-field
                                   summary
                                   "kzgVerifierTimeoutSeconds")))
                         (is (fixture-object-field
                              summary
                              "kzgProofVerificationAvailable")))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= (namestring kzg-command)
                                        (cdr (assoc "kzgVerifierCommand"
                                                    fields
                                                    :test #'string=))))
                           (is (string= "2"
                                        (cdr (assoc
                                              "kzgVerifierTimeoutSeconds"
                                              fields
                                              :test #'string=))))
                           (is (string= "true"
                                        (cdr (assoc
                                              "kzgProofVerificationAvailable"
                                              fields
                                              :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "1"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "1"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest devnet-cli-main-database-restores-and-exports-chain-store
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (genesis
                    (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001"))
                  (child
                    (make-block
                     :header
                     (make-block-header
                      :number 1
                      :parent-hash (block-hash genesis)
                      :timestamp 1
                      :gas-limit 30000000))))
             (let ((state (make-state-db)))
               (state-db-set-account
                state funded (make-state-account :balance 42))
               (setf (block-header-state-root (block-header child))
                     (state-db-root state)))
             (chain-store-put-block seed-store child :state-available-p t)
             (chain-store-put-account-balance
              seed-store (block-hash child) funded 42)
             (chain-store-set-canonical-head seed-store (block-hash child))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary
                    (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head
                    (chain-store-latest-block restored-store))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001")))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries
                               database :canonical-hash))))
             (is (= 1 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash head) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-datadir-defaults-database-path
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-datadir"))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (datadir-geth-jwt-path
           (merge-pathnames "geth/jwtsecret" datadir))
         (explicit-database-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-chain" "sexp"))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-jwt" "hex"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream))
         (override-output (make-string-output-stream))
         (override-errors (make-string-output-stream))
         (explicit-jwt-output (make-string-output-stream))
         (explicit-jwt-errors (make-string-output-stream))
         (geth-jwt-output (make-string-output-stream))
         (geth-jwt-errors (make-string-output-stream))
         (precommand-output (make-string-output-stream))
         (precommand-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file datadir-jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database datadir-database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring datadir-database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head (chain-store-latest-block restored-store)))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state))))
             (is (= 0 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--database" (namestring explicit-database-path)
                         "--json"
                         "--no-serve")
                   :output-stream override-output
                   :error-stream override-errors)))
           (is (string= "" (get-output-stream-string override-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string override-output))))
             (is (string= (namestring explicit-database-path)
                          (fixture-object-field summary "databasePath"))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--jwt-secret" (namestring explicit-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-jwt-output
                   :error-stream explicit-jwt-errors)))
           (is (string= "" (get-output-stream-string explicit-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-jwt-output))))
             (is (string= (namestring explicit-jwt-path)
                          (fixture-object-field summary "jwtSecretPath"))))
           (ensure-directories-exist datadir-geth-jwt-path)
           (devnet-cli-write-temp-file datadir-geth-jwt-path
                                       +devnet-cli-jwt-secret+)
           (delete-file datadir-jwt-path)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream geth-jwt-output
                   :error-stream geth-jwt-errors)))
           (is (string= "" (get-output-stream-string geth-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string geth-jwt-output))))
             (is (string= (namestring datadir-geth-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "--identity" "init"
                         "--datadir" (namestring datadir)
                         "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream precommand-output
                   :error-stream precommand-errors)))
           (is (string= "" (get-output-stream-string precommand-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string precommand-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file datadir-geth-jwt-path)
        (delete-file datadir-geth-jwt-path))
      (when (probe-file explicit-database-path)
        (delete-file explicit-database-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path)))))

(deftest devnet-cli-main-init-datadir-seeds-genesis-and-database
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-init-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-init-explicit-jwt"
                                 "hex"))
         (init-output (make-string-output-stream))
         (init-errors (make-string-output-stream))
         (devnet-output (make-string-output-stream))
         (devnet-errors (make-string-output-stream))
         (explicit-init-output (make-string-output-stream))
         (explicit-init-errors (make-string-output-stream))
         (explicit-devnet-output (make-string-output-stream))
         (explicit-devnet-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream init-output
                   :error-stream init-errors)))
           (is (string= "" (get-output-stream-string init-errors)))
           (let* ((init-summary
                    (parse-json (get-output-stream-string init-output)))
                  (database
                    (make-file-key-value-database datadir-database-path)))
             (is (= 1337 (fixture-object-field init-summary "chainId")))
             (is (= 0 (fixture-object-field init-summary "headNumber")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field init-summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field init-summary "jwtSecretPath")))
             (is (fixture-object-field init-summary "authRequired"))
             (is (probe-file datadir-genesis-path))
             (is (probe-file datadir-jwt-path))
             (is (= 32
                    (length
                     (hex-to-bytes
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (devnet-cli-file-string
                                    datadir-jwt-path))))))
             (is (string= (devnet-cli-file-string
                           +devnet-cli-genesis-fixture+)
                          (devnet-cli-file-string datadir-genesis-path)))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream devnet-output
                   :error-stream devnet-errors)))
           (is (string= "" (get-output-stream-string devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string devnet-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 0 (fixture-object-field summary "headNumber")))
             (is (string= (namestring (truename datadir-genesis-path))
                          (fixture-object-field summary "genesisPath")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--authrpc.jwtsecret" (namestring explicit-jwt-path)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream explicit-init-output
                   :error-stream explicit-init-errors)))
           (is (string= "" (get-output-stream-string explicit-init-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-init-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (string= +devnet-cli-jwt-secret+
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (devnet-cli-file-string datadir-jwt-path)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-devnet-output
                   :error-stream explicit-devnet-errors)))
           (is (string= "" (get-output-stream-string explicit-devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-devnet-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))))
      (when (probe-file datadir-genesis-path)
        (delete-file datadir-genesis-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path)))))

(deftest devnet-cli-main-dev-mode-uses-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet" "--dev" "--json" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 1337 (fixture-object-field summary "chainId")))
      (is (= 0 (fixture-object-field summary "headNumber")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))
      (is (fixture-field-present-p summary "genesisPath"))
      (is (null (fixture-object-field summary "genesisPath")))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (eq t (fixture-object-field summary "stateAvailable"))))))

(deftest devnet-cli-main-dev-gaslimit-shapes-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 31000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-gaslimit-shapes-embedded-dev-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 32000000
             (fixture-object-field summary "headGasLimit")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--dev.gaslimit"
                  "33000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 33000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-etherbase-shapes-dev-coinbase
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cb"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cc"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  "0x00000000000000000000000000000000000000cb"
                  "--etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase"))))))

(deftest devnet-cli-main-treats-empty-database-as-new-chain
  (labels ((write-empty-kv-database (path)
             (with-open-file (stream path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (let ((*print-readably* t)
                     (*print-pretty* nil))
                 (write '(:ethereum-lisp-kv-v1 nil) :stream stream)
                 (terpri stream)))))
    (dolist (mode '(:empty-file :empty-kv))
      (let ((database-path
              (devnet-cli-temp-path "ethereum-lisp-devnet-empty-chain"
                                     "sexp"))
            (output (make-string-output-stream))
            (errors (make-string-output-stream)))
        (unwind-protect
             (progn
               (ecase mode
                 (:empty-file
                  (devnet-cli-write-temp-file database-path ""))
                 (:empty-kv
                  (write-empty-kv-database database-path)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (list "devnet"
                             "--genesis" +devnet-cli-genesis-fixture+
                             "--port" "0"
                             "--database" (namestring database-path)
                             "--json"
                             "--no-serve")
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (let* ((summary
                        (parse-json (get-output-stream-string output)))
                      (database (make-file-key-value-database database-path))
                      (restored-node
                        (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :database-path (namestring database-path)))
                      (restored-store
                        (ethereum-lisp.cli:devnet-node-store restored-node))
                      (head (chain-store-latest-block restored-store)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (= 0 (fixture-object-field summary "headNumber")))
                 (is (eq t (fixture-object-field summary "stateAvailable")))
                 (is (< 0 (length (kv-chain-record-entries database :block))))
                 (is (< 0 (length (kv-chain-record-entries
                                   database :canonical-hash))))
                 (is (< 0 (length (kv-chain-record-entries database :state))))
                 (is (= 0 (block-header-number (block-header head))))
                 (is (chain-store-state-available-p restored-store
                                                    (block-hash head)))))
          (when (probe-file database-path)
            (delete-file database-path)))))))

(deftest devnet-cli-main-rejects-database-genesis-mismatch
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-mismatched-chain"
                                "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (state (make-state-db))
                  (mismatched-genesis
                    (make-block
                     :header
                     (make-block-header
                      :number 0
                      :timestamp 99
                      :gas-limit 30000000
                      :state-root (state-db-root state)))))
             (chain-store-put-block seed-store
                                    mismatched-genesis
                                    :state-available-p t)
             (commit-state-db-to-chain-store
              seed-store (block-hash mismatched-genesis) state)
             (chain-store-set-canonical-head seed-store
                                             (block-hash mismatched-genesis))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "Devnet database genesis does not match genesis file"
                       (get-output-stream-string errors))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-prunes-state-before-database-export
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-pruned-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0))
                (seed-store
                  (ethereum-lisp.cli:devnet-node-store seed-node))
                (genesis
                  (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                (funded
                  (address-from-hex
                   "0x0000000000000000000000000000000000001001"))
                (child
                  (make-block
                   :header
                   (make-block-header
                    :number 1
                    :parent-hash (block-hash genesis)
                    :timestamp 1
                    :gas-limit 30000000)))
                (genesis-id (hash32-bytes (block-hash genesis)))
                child-id)
           (let ((state (make-state-db)))
             (state-db-set-account
              state funded (make-state-account :balance 42))
             (setf (block-header-state-root (block-header child))
                   (state-db-root state)
                   child-id (hash32-bytes (block-hash child))))
           (chain-store-put-block seed-store child :state-available-p t)
           (chain-store-put-account-balance
            seed-store (block-hash child) funded 42)
           (chain-store-set-canonical-head seed-store (block-hash child))
           (chain-store-export-to-kv
            seed-store
            (make-file-key-value-database database-path))
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--prune-state-before" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node)))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (eq t (fixture-object-field summary "stateAvailable")))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state child-id)
               (declare (ignore value))
               (is present-p))
             (is (chain-store-known-block restored-store (block-hash genesis)))
             (is (not (chain-store-state-available-p
                       restored-store (block-hash genesis))))
             (is (chain-store-state-available-p
                  restored-store (block-hash child)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash child) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-txpool-journal-persists-pending-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path (namestring genesis-path)
                   :port 0
                   :txpool-journal-path (namestring journal-path)))
                (seed-store (ethereum-lisp.cli:devnet-node-store seed-node))
                (transaction
                  (devnet-cli-txpool-transaction
                   (ethereum-lisp.cli:devnet-node-config seed-node)
                   0
                   +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction)))
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            seed-store
            transaction)
           (ethereum-lisp.cli::devnet-node-export-database seed-node)
           (let ((journal (make-file-key-value-database journal-path)))
             (is (= 1 (length (kv-chain-record-entries journal :txpool)))))
           (let* ((restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (summary
                    (ethereum-lisp.cli:devnet-node-summary restored-node))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     restored-node)))
             (is (string= (namestring journal-path)
                          (getf summary :txpool-journal-path)))
             (is (string= (namestring journal-path)
                          (cdr (assoc "txpoolJournalPath"
                                      summary-json
                                      :test #'string=))))
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding
                          (ethereum-lisp.core::engine-payload-store-pending-transaction
                           restored-store
                           transaction-hash)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-journal-coexists-with-database-restore
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-database" "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config seed-node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction)))
             (ethereum-lisp.core::engine-payload-store-put-pending-transaction
              seed-store
              transaction)
             (ethereum-lisp.cli::devnet-node-export-database seed-node)
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database database-path)
                      :txpool))))
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database journal-path)
                      :txpool))))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :port 0
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (bytes= (transaction-encoding transaction)
                           (transaction-encoding
                            (ethereum-lisp.core::engine-payload-store-pending-transaction
                             restored-store
                             transaction-hash)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-refreshes-live-journal
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-rejournal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json"))
        (now 100))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)
                     :txpool-rejournal-seconds 10))
                  (state
                    (ethereum-lisp.cli::make-devnet-rejournal-state
                     node
                     10
                     :now-function (lambda () now)))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
             (is (string= "10"
                          (cdr (assoc "txpoolRejournalSeconds"
                                      telemetry-fields
                                      :test #'string=))))
             (ethereum-lisp.core::engine-payload-store-put-pending-transaction
              (ethereum-lisp.cli:devnet-node-store node)
              transaction)
             (setf now 109)
             (is (eq nil
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (is (not (probe-file journal-path)))
             (setf now 110)
             (is (eq t
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (let ((journal (make-file-key-value-database journal-path)))
               (is (= 1
                      (length
                       (kv-chain-record-entries journal :txpool)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-without-journal-is-noop
  (let ((unused-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-unused-rejournal"
                                "sexp"))
        (now 0))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0
                   :txpool-rejournal-seconds 1))
                (state
                  (ethereum-lisp.cli::make-devnet-rejournal-state
                   node
                   1
                   :now-function (lambda () now))))
           (setf now 1)
           (is (eq nil
                   (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
           (is (not (probe-file unused-path))))
      (when (probe-file unused-path)
        (delete-file unused-path)))))

(deftest devnet-cli-dev-period-parses-and-reports-duration
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--dev"
                  "--dev.period=2m"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :port 0
            :dev-mode-p (getf options :dev-mode-p)
            :dev-period-seconds (getf options :dev-period-seconds)))
         (summary
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (telemetry-fields
           (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
    (is (= 120 (getf options :dev-period-seconds)))
    (is (= 120 (fixture-object-field summary "devPeriodSeconds")))
    (is (string= "120"
                 (cdr (assoc "devPeriodSeconds"
                             telemetry-fields
                             :test #'string=))))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=-1" "--no-serve")))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=bad" "--no-serve")))))

(deftest devnet-cli-dev-period-tick-seals-public-txpool-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (raw-transaction (devnet-cli-transaction-raw transaction))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now)))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":1,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              node)))
      (is (string= transaction-hash (field send-response "result")))
      (is (eq nil (ethereum-lisp.cli::devnet-dev-period-state-tick state)))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (block-number-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_blockNumber\",\"params\":[]}"
                node))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (receipt-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field lookup-response "result"))
             (receipt (field receipt-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (string= (quantity-to-hex 1)
                     (field block-number-response "result")))
        (is (string= transaction-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field mined-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= transaction-hash
                     (field receipt "transactionHash")))
        (is (string= sealed-hash (field receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field receipt "transactionIndex")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-bounds-transactions-by-gas-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 21000))
           (second-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 30000))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex
                         (transaction-hash second-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction (list first-transaction second-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (first-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-hash "\"]}")
                node))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field first-lookup "result"))
             (leftover-transaction (field second-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (= 1 (length (block-transactions sealed-block))))
        (is (string= first-hash
                     (hash32-to-hex
                      (transaction-hash
                       (first (block-transactions sealed-block))))))
        (is (string= first-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= second-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= second-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-selects-fitting-second-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (first-private-key 2)
           (second-private-key +devnet-cli-txpool-private-key+)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000
                             :private-keys (list first-private-key
                                                 second-private-key))
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 21000))
           (first-sender-non-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 30000))
           (second-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key second-private-key
              :gas-limit 21000))
           (first-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-fitting-transaction)))
           (first-non-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-non-fitting-transaction)))
           (second-fitting-hash
             (hash32-to-hex
              (transaction-hash second-sender-fitting-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction
               (list first-sender-fitting-transaction
                     first-sender-non-fitting-transaction
                     second-sender-fitting-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (mined-hashes
               (mapcar
                (lambda (transaction)
                  (hash32-to-hex (transaction-hash transaction)))
                (block-transactions sealed-block)))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (second-receipt
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (leftover-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-non-fitting-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (second-mined-transaction (field second-lookup "result"))
             (second-mined-receipt (field second-receipt "result"))
             (leftover-transaction (field leftover-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (equal (list first-fitting-hash second-fitting-hash)
                   mined-hashes))
        (is (string= second-fitting-hash
                     (field second-mined-transaction "hash")))
        (is (string= sealed-hash
                     (field second-mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-transaction "transactionIndex")))
        (is (string= second-fitting-hash
                     (field second-mined-receipt "transactionHash")))
        (is (string= sealed-hash
                     (field second-mined-receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-receipt "transactionIndex")))
        (is (string= first-non-fitting-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= first-non-fitting-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-carries-active-fork-bodies
  (let* ((now 0)
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json
            (devnet-cli-funded-txpool-genesis-json
             :config-fields
             (list (cons "cancunTime" "0x0")
                   (cons "pragueTime" "0x0")
                   (cons "amsterdamTime" "0x0")))
            :port 0
            :dev-mode-p t
            :dev-period-seconds 1))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transaction
           (devnet-cli-txpool-transaction
            config
            0
            +devnet-cli-txpool-pending-gas-price+))
         (state
           (ethereum-lisp.cli::make-devnet-dev-period-state
            node
            1
            :now-function (lambda () now))))
    (engine-rpc-handle-request-json
     (concatenate
      'string
      "{\"jsonrpc\":\"2.0\",\"id\":1,"
      "\"method\":\"eth_sendRawTransaction\","
      "\"params\":[\"" (devnet-cli-transaction-raw transaction) "\"]}")
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf now 1)
    (let* ((block
             (ethereum-lisp.cli::devnet-dev-period-state-tick state))
           (header (block-header block)))
      (is (typep block 'ethereum-block))
      (is (= 1 (length (block-transactions block))))
      (is (= 0 (block-header-blob-gas-used header)))
      (is (= 0 (block-header-excess-blob-gas header)))
      (is (string= (hash32-to-hex (zero-hash32))
                   (hash32-to-hex
                    (block-header-parent-beacon-root header))))
      (is (block-requests-present-p block))
      (is (null (block-requests block)))
      (is (string= (hash32-to-hex (execution-requests-hash '()))
                   (hash32-to-hex
                    (block-header-requests-hash header))))
      (is (block-block-access-list-present-p block))
      (is (null (block-block-access-list block)))
      (is (string= (hash32-to-hex (block-access-list-hash '()))
                   (hash32-to-hex
                    (block-header-block-access-list-hash header)))))))

(deftest devnet-cli-txpool-journal-rejects-wrong-chain-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-bad-chain"
                                "sexp")))
    (unwind-protect
         (let* ((config
                  (chain-config-from-genesis-json-file
                   +devnet-cli-genesis-fixture+))
                (transaction
                  (fixture-sign-legacy-transaction
                   (make-legacy-transaction
                    :nonce 0
                    :gas-price +devnet-cli-txpool-gas-price+
                    :gas-limit +devnet-cli-txpool-gas-limit+
                    :to (address-from-hex +devnet-cli-txpool-recipient+)
                    :value +devnet-cli-txpool-value+)
                   +devnet-cli-txpool-private-key+
                   (1+ (chain-config-chain-id config))))
                (journal (make-file-key-value-database journal-path)))
           (kv-put-chain-record
            journal
            :txpool
            (hash32-bytes (transaction-hash transaction))
            (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
             :pending
             transaction))
           (signals block-validation-error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path +devnet-cli-genesis-fixture+
              :port 0
              :txpool-journal-path (namestring journal-path))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

(deftest devnet-cli-main-json-summary-and-ready-file
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file ready-path "stale readiness")
           (devnet-cli-write-temp-file pid-path "0")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--public-port" "8546"
                         "--jwt-secret" (namestring jwt-path)
                         "--txpool.rejournal" "2m"
                         "--ready-file" (namestring ready-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (= 1337 (fixture-object-field summary "chainId")))
               (is (= 0 (fixture-object-field summary "headNumber")))
               (is (null (fixture-object-field summary "safeNumber")))
               (is (null (fixture-object-field summary "safeHash")))
               (is (null (fixture-object-field summary "finalizedNumber")))
               (is (null (fixture-object-field summary "finalizedHash")))
               (is (string= "127.0.0.1:0"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "127.0.0.1:8546"
                            (fixture-object-field summary "rpcEndpoint")))
               (is (equal (devnet-cli-current-process-id)
                          (fixture-object-field summary "processId")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (= 120
                      (fixture-object-field summary "txpoolRejournalSeconds")))
               (is (eq t (fixture-object-field summary "stateAvailable")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-creates-artifact-parent-directories
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-artifact-parents"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= (namestring log-path)
                            (fixture-object-field summary "logPath")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath"))))
             (is (= 2 (length log-records)))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-accepts-explicit-engine-endpoint-options
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-host" "192.0.2.10"
                         "--engine-port" "9551"
                         "--public-host" "192.0.2.11"
                         "--public-port" "9545"
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.10:9551"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "192.0.2.11:9545"
                            (fixture-object-field summary "rpcEndpoint"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "192.0.2.10:9551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "192.0.2.11:9545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-accepts-geth-style-runner-aliases
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (config-path (devnet-cli-temp-path "ethereum-lisp-devnet-geth" "toml"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string
             "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
             stream))
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for alias coverage\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--config=~A" (namestring config-path))
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--authrpc.addr=192.0.2.30"
                         "--authrpc.port=9651"
                         (format nil "--authrpc.jwtsecret=~A"
                                 (namestring jwt-path))
                         "--authrpc.rpcprefix=/engine"
                         "--authrpc.vhosts=engine.runner,localhost"
                         "--authrpc.corsdomain=https://engine.runner"
                         "--http=false"
                         "--http.addr=192.0.2.31"
                         "--http.port=9645"
                         "--http.api=eth,net,web3,txpool"
                         "--http.rpcprefix=/rpc"
                         "--http.vhosts=public.runner,localhost"
                         "--http.corsdomain=https://runner.example,*"
                         "--ws=false"
                         "--ws.addr=192.0.2.32"
                         "--ws.port=9646"
                         "--ws.api=eth,net"
                         "--ws.origins=*"
                         "--ws.rpcprefix=/ws"
                         "--ipcapi=eth,net,web3"
                         "--graphql=false"
                         "--graphql.addr=192.0.2.33"
                         "--graphql.port=9647"
                         "--graphql.vhosts=*"
                         "--graphql.corsdomain=*"
                         "--networkid=7331"
                         "--mainnet=false"
                         "--sepolia=false"
                         "--holesky=false"
                         "--hoodi=false"
                         "--goerli=false"
                         "--syncmode=full"
                         "--nodiscover=false"
                         "--ipcdisable=true"
                         "--verbosity=3"
                         "--maxpeers=0"
                         "--nat=none"
                         "--netrestrict=127.0.0.0/8"
                         "--identity=ethereum-lisp-devnet"
                         "--nodekey=/tmp/ethereum-lisp-nodekey"
                         "--nodekeyhex=010203"
                         "--discovery.port=30303"
                         "--discovery.dns="
                         "--ipcpath=/tmp/ethereum-lisp.ipc"
                         "--allow-insecure-unlock=false"
                         (format nil "--ready-file=~A"
                                 (namestring ready-path))
                         (format nil "--log-file=~A"
                                 (namestring log-path))
                         "--json=true"
                         "--no-serve=1")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.30:9651"
                            (fixture-object-field summary "engineEndpoint")))
               (is (not (fixture-object-field summary "rpcEndpoint")))
               (is (not (fixture-object-field summary "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field summary
                                                  "publicRpcPrefix")))
               (is (= 7331 (fixture-object-field summary "networkId")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath")))
               (is (equal '("eth" "net" "web3" "txpool")
                          (fixture-object-field summary
                                                "publicApiModules")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field summary
                                                "engineCorsOrigins")))
               (is (equal '("https://runner.example" "*")
                          (fixture-object-field summary
                                                "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field summary "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field summary "publicVhosts"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "0x1ca3"
                              (cdr (assoc "networkId" fields
                                          :test #'string=))))
                 (is (string= "/engine"
                              (cdr (assoc "engineRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= "/rpc"
                              (cdr (assoc "publicRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= ""
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= "false"
                              (cdr (assoc "publicRpcEnabled" fields
                                          :test #'string=))))
                 (is (string= "eth,net,web3,txpool"
                              (cdr (assoc "publicApiModules" fields
                                          :test #'string=))))
                 (is (string= "https://engine.runner"
                              (cdr (assoc "engineCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "https://runner.example,*"
                              (cdr (assoc "publicCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "engine.runner,localhost"
                              (cdr (assoc "engineVhosts" fields
                                          :test #'string=))))
                 (is (string= "public.runner,localhost"
                              (cdr (assoc "publicVhosts" fields
                                          :test #'string=))))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-applies-geth-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config"))
         (datadir (merge-pathnames "datadir/" root))
         (database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (jwt-path (merge-pathnames "jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (journal-path (merge-pathnames "txpool-journal.sexp" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist datadir)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Journal = ~S~%~
                     Rejournal = \"45m\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\", ~
                     \"0x0000000000000000000000000000000000000002\"]~%~
                     NoLocals = true~%~
                     [Node]~%DataDir = ~S~%~
                     HTTPHost = \"192.0.2.41\"~%HTTPPort = 1945~%~
                     HTTPModules = [\"eth\", \"net\"]~%~
                     HTTPCors = [\"https://public.example\", \"*\"]~%~
                     HTTPVirtualHosts = [\"public.example\", \"localhost\"]~%~
                     HTTPPathPrefix = \"/rpc\"~%~
                     AuthAddr = \"192.0.2.42\"~%AuthPort = 1951~%~
                     AuthVirtualHosts = [\"engine.example\", \"localhost\"]~%~
                     JWTSecret = ~S~%"
                    (namestring journal-path)
                    (namestring datadir)
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.41:1945"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 4242 (fixture-object-field summary "networkId")))
             (is (= 7 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 25 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 3 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 4 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 9 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 12 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (= 2700
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000001"
                          "0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq t (fixture-object-field summary "txpoolNoLocals")))
             (is (string= "/rpc"
                          (fixture-object-field summary "publicRpcPrefix")))
             (is (string= (namestring jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (eq t (fixture-object-field summary "authRequired")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (equal '("eth" "net")
                        (fixture-object-field summary "publicApiModules")))
             (is (equal '("https://public.example" "*")
                        (fixture-object-field summary "publicCorsOrigins")))
             (is (equal '("public.example" "localhost")
                        (fixture-object-field summary "publicVhosts")))
             (is (equal '("engine.example" "localhost")
                        (fixture-object-field summary "engineVhosts")))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-options-override-geth-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-override"))
         (jwt-path (merge-pathnames "config-jwt.hex" root))
         (override-jwt-path (merge-pathnames "override-jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            override-jwt-path
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Rejournal = \"3h0m0s\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\"]~%~
                     NoLocals = true~%~
                     [Node]~%HTTPHost = \"192.0.2.50\"~%HTTPPort = 1950~%~
                     AuthAddr = \"192.0.2.51\"~%AuthPort = 1951~%~
                     JWTSecret = ~S~%"
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--authrpc.addr" "192.0.2.60"
                         "--authrpc.port" "1960"
                         "--http.addr" "192.0.2.61"
                         "--http.port" "1961"
                         "--networkid" "7331"
                         "--txpool.pricelimit" "11"
                         "--txpool.pricebump" "40"
                         "--txpool.accountslots" "5"
                         "--txpool.globalslots" "6"
                         "--txpool.accountqueue" "10"
                         "--txpool.globalqueue" "20"
                         "--txpool.lifetime" "1h2m3s"
                         "--txpool.rejournal" "10m"
                         "--txpool.locals"
                         "0x0000000000000000000000000000000000000002"
                         "--txpool.nolocals" "false"
                         "--authrpc.jwtsecret" (namestring override-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.60:1960"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.61:1961"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 7331 (fixture-object-field summary "networkId")))
             (is (= 11 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 40 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 5 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 6 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 10 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 20 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 3723
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (string= (namestring override-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file override-jwt-path)
        (delete-file override-jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-applies-geth-miner-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 34000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-dev-gaslimit-overrides-geth-miner-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config-override"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--dev.gaslimit"
                         "35000000"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 35000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-empty-geth-http-host-disables-public-rpc
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-disabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
AuthAddr = \"192.0.2.42\"
AuthPort = 1951
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq nil (fixture-object-field summary "publicRpcEnabled")))
             (is (eq nil (fixture-object-field summary "rpcEndpoint")))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-http-reenables-empty-geth-http-host
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-reenabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--http"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "publicRpcEnabled")))
             (is (string= "127.0.0.1:1945"
                          (fixture-object-field summary "rpcEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-geth-p2p-port-does-not-override-engine-port
  (labels ((run-summary (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (append (list "devnet"
                                     "--genesis"
                                     +devnet-cli-genesis-fixture+)
                               args
                               (list "--json" "--no-serve"))
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (parse-json (get-output-stream-string output)))))
    (let ((p2p-after-authrpc
            (run-summary
             (list "--authrpc.port=9651"
                   "--port=30303"
                   "--http.port=9645")))
          (p2p-before-authrpc
            (run-summary
             (list "--port=30303"
                   "--authrpc.port=9652"
                   "--http.port=9646")))
          (p2p-without-authrpc
            (run-summary
             (list "--port=30303"
                   "--http.port=9647"))))
      (is (string= "127.0.0.1:9651"
                   (fixture-object-field p2p-after-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9652"
                   (fixture-object-field p2p-before-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field p2p-without-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9645"
                   (fixture-object-field p2p-after-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9646"
                   (fixture-object-field p2p-before-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9647"
                   (fixture-object-field p2p-without-authrpc
                                         "rpcEndpoint"))))))

(deftest devnet-cli-main-accepts-geth-style-txpool-and-database-flags
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-geth-txpool" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--db.engine=pebble"
                         "--state.scheme=hash"
                         "--datadir.ancient=/tmp/ethereum-lisp-ancient"
                         "--rpc.allow-unprotected-txs=true"
                         "--txpool.locals=0x0000000000000000000000000000000000000001"
                         "--txpool.nolocals=false"
                         (format nil "--txpool.journal=~A"
                                 (namestring journal-path))
                         "--txpool.rejournal=1h"
                         "--txpool.pricelimit=1"
                         "--txpool.pricebump=10"
                         "--txpool.accountslots=16"
                         "--txpool.globalslots=5120"
                         "--txpool.accountqueue=64"
                         "--txpool.globalqueue=1024"
                         "--txpool.lifetime=3h0m0s"
                         "--txpool.blobpool.datacap=2684354560"
                         "--txpool.blobpool.pricebump=100"
                         "--dev=false"
                         "--nousb=true"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "127.0.0.1:8551"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "127.0.0.1:8545"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (eq t (fixture-object-field summary
                                              "allowUnprotectedTransactions")))
             (is (= 1 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 10 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 16 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 5120 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 64 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 1024 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 3600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (equal '("0x0000000000000000000000000000000000000001")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (eq nil (fixture-object-field summary "authRequired")))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

(deftest devnet-cli-main-accepts-geth-style-dev-mode-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--dev=true"
                  "--dev.period=1"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint")))
      (is (= 1
             (fixture-object-field summary "devPeriodSeconds")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))))
  (let ((init-options
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init"
                 "--dev=true"
                 "--dev.period=1"
                 "--dev.gaslimit"
                 "30000000"
                 "--json=false"))))
    (is (eq :sexp (getf init-options :summary-format)))))

(deftest devnet-cli-main-accepts-geth-style-rpc-limit-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--rpc.gascap=50000000"
                  "--rpc.evmtimeout=5s"
                  "--rpc.txfeecap=0"
                  "--rpc.batch-request-limit=1000"
                  "--rpc.batch-response-max-size=25000000"
                  "--http.maxclients=128"
                  "--http.readtimeout=30s"
                  "--http.writetimeout"
                  "30s"
                  "--http.idletimeout=2m"
                  "--override.terminaltotaldifficulty=0"
                  "--override.terminaltotaldifficultypassed=true"
                  "--override.terminalblockhash=0x0000000000000000000000000000000000000000000000000000000000000000"
                  "--override.terminalblocknumber=0"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-merge-overrides-configure-transition-handshake
  (let* ((terminal-block-hash-hex
           "0x2222222222222222222222222222222222222222222222222222222222222222")
         (options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--override.terminaltotaldifficulty=0x3039"
                  "--override.terminaltotaldifficultypassed=false"
                  "--override.terminalblockhash" terminal-block-hash-hex
                  "--override.terminalblocknumber" "66"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :terminal-total-difficulty
            (getf options :terminal-total-difficulty)
            :terminal-total-difficulty-passed
            (getf options :terminal-total-difficulty-passed)
            :terminal-total-difficulty-passed-specified-p
            (getf options :terminal-total-difficulty-passed-specified-p)
            :terminal-block-hash
            (getf options :terminal-block-hash)
            :terminal-block-number
            (getf options :terminal-block-number)))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transition
           (ethereum-lisp.core::engine-rpc-transition-configuration-object
            config)))
    (is (= 12345 (chain-config-terminal-total-difficulty config)))
    (is (not (chain-config-terminal-total-difficulty-passed config)))
    (is (string= terminal-block-hash-hex
                 (hash32-to-hex
                  (chain-config-terminal-block-hash config))))
    (is (= 66 (chain-config-terminal-block-number config)))
    (is (string= "0x3039"
                 (fixture-object-field transition
                                       "terminalTotalDifficulty")))
    (is (string= terminal-block-hash-hex
                 (fixture-object-field transition "terminalBlockHash")))
    (is (string= "0x42"
                 (fixture-object-field transition "terminalBlockNumber")))))

(deftest devnet-cli-main-engine-host-does-not-rewrite-public-default
  (let ((engine-output (make-string-output-stream))
        (engine-errors (make-string-output-stream))
        (host-output (make-string-output-stream))
        (host-errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--engine-host" "192.0.2.10"
                  "--engine-port" "9551"
                  "--json"
                  "--no-serve")
            :output-stream engine-output
            :error-stream engine-errors)))
    (is (string= "" (get-output-stream-string engine-errors)))
    (let ((summary (parse-json (get-output-stream-string engine-output))))
      (is (string= "192.0.2.10:9551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--host" "192.0.2.20"
                  "--port" "9552"
                  "--json"
                  "--no-serve")
            :output-stream host-output
            :error-stream host-errors)))
    (is (string= "" (get-output-stream-string host-errors)))
    (let ((summary (parse-json (get-output-stream-string host-output))))
      (is (string= "192.0.2.20:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "192.0.2.20:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-main-log-file-records-ready-event
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let ((log-path-string (namestring log-path)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "devnet"
                           "--genesis" +devnet-cli-genesis-fixture+
                           "--engine-port" "0"
                           "--public-port" "8546"
                           "--ready-file" (namestring ready-path)
                           "--log-file" log-path-string
                           "--pid-file" (namestring pid-path)
                           "--json"
                           "--no-serve")
                     :output-stream output
                     :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path))
                  (log-names
                    (mapcar (lambda (record) (getf record :name))
                            log-records)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= log-path-string
                            (fixture-object-field summary "logPath"))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (is (member "devnet.ready" log-names :test #'string=))
             (is (member "devnet.shutdown" log-names :test #'string=))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (eq :log (getf log-record :kind)))
                 (is (eq :info (getf log-record :value)))
                 (is (string= "127.0.0.1:0"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:8546"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (getf log-record :name))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))
                 (is (string= "0x539"
                              (cdr (assoc "chainId" fields :test #'string=))))
                 (is (string= "0x0"
                              (cdr (assoc "headNumber" fields
                                          :test #'string=))))
                 (is (stringp
                      (cdr (assoc "headHash" fields :test #'string=))))
                 (is (string= "true"
                              (cdr (assoc "stateAvailable" fields
                                          :test #'string=))))
                 (is (string= log-path-string
                              (cdr (assoc "logPath" fields
                                          :test #'string=))))
                 (is (string= (namestring pid-path)
                              (cdr (assoc "pidFilePath" fields
                                          :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-log-file-records-error-event
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-error-artifacts"))
         (log-path (merge-pathnames "errors/nested/devnet-error.log" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--log-file" log-path-string
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--genesis is required"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--genesis is required"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-invalid-error-log-path-still-reports-error
  (let* ((log-directory
           (devnet-cli-temp-directory
            "ethereum-lisp-devnet-error-log-directory"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--log-file" (namestring log-directory)
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--genesis is required" stderr))
      (is (search "Usage: ethereum-lisp devnet" stderr)))))

(deftest devnet-cli-main-log-file-records-option-parse-error-event
  (let ((log-path (devnet-cli-temp-path "ethereum-lisp-devnet-parse-error"
                                        "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--http"
                         "false"
                         "--ws.api"
                         "eth,net"
                         "--txpool.blobpool.pricebump"
                         "100"
                         (format nil "--log-file=~A" log-path-string)
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--public-port=not-a-port"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--public-port requires an integer value"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--public-port requires an integer value"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(defun phase-a-smoke-gate-reference-client
    (reference-clients name)
  (find name reference-clients
        :key (lambda (client)
               (fixture-object-field client "name"))
        :test #'string=))

(defun phase-a-smoke-gate-reference-commit-p (commit)
  (and (stringp commit)
       (= 40 (length commit))
       (every (lambda (char)
                (or (and (char<= #\0 char) (char<= char #\9))
                    (and (char<= #\a char) (char<= char #\f))))
              commit)))

(defun phase-a-smoke-gate-assert-reference-client (reference-clients name)
  (let* ((client
           (phase-a-smoke-gate-reference-client reference-clients name))
         (status (and client
                      (fixture-object-field client "status")))
         (commit (and client
                      (fixture-object-field client "commit"))))
    (is client)
    (is (member status '("ok" "missing" "unavailable") :test #'string=))
    (if (string= "ok" status)
        (is (phase-a-smoke-gate-reference-commit-p commit))
        (is (null commit)))))

(defun phase-a-smoke-gate-assert-reference-client-path
    (reference-clients name expected-path)
  (let ((client
          (phase-a-smoke-gate-reference-client reference-clients name)))
    (is client)
    (is (string= expected-path
                 (fixture-object-field client "path")))))

(defun phase-a-smoke-gate-assert-execution-spec-tests-source (report)
  (let ((source (fixture-object-field report "executionSpecTests")))
    (is source)
    (is (string= "ethereum/execution-spec-tests"
                 (fixture-object-field source "repository")))
    (is (string= "v5.4.0"
                 (fixture-object-field source "release")))
    (is (string= "88e9fb8"
                 (fixture-object-field source "tagTarget")))
    (is (string= "fixtures_stable.tar.gz"
                 (fixture-object-field source "archive")))))

(defun phase-a-smoke-gate-section-count (section field)
  (or (fixture-object-field section field) 0))

(defun phase-a-smoke-gate-assert-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (devnet (fixture-object-field report "devnet"))
         (devnet-side-reorg
           (fixture-object-field report "devnetSideReorg"))
         (devnet-engine-only
           (fixture-object-field report "devnetEngineOnly"))
         (fixture-case-count
           (+ (phase-a-smoke-gate-section-count state "count")
              (phase-a-smoke-gate-section-count transaction "count")
              (phase-a-smoke-gate-section-count blockchain "count")))
         (fixture-executed-count
           (+ (phase-a-smoke-gate-section-count state "executedCount")
              (phase-a-smoke-gate-section-count transaction "executedCount")
              (phase-a-smoke-gate-section-count blockchain "executedCount")))
         (devnet-case-count
           (if devnet
               (phase-a-smoke-gate-section-count devnet "caseCount")
               0))
         (devnet-side-reorg-case-count
           (if devnet-side-reorg
               (phase-a-smoke-gate-section-count
                devnet-side-reorg "sideReorgCaseCount")
               0))
         (devnet-engine-only-case-count
           (if devnet-engine-only
               (phase-a-smoke-gate-section-count
                devnet-engine-only "caseCount")
               0)))
    (is (= fixture-case-count
           (fixture-object-field report "fixtureCaseCount")))
    (is (= fixture-executed-count
           (fixture-object-field report "fixtureExecutedCount")))
    (is (= (+ fixture-case-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)
           (fixture-object-field report "totalCaseCount")))
    (is (= (+ fixture-executed-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)
           (fixture-object-field report "totalExecutedCount")))))

(defun phase-a-smoke-gate-assert-in-repo-fixture-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (kind-counts (fixture-object-field blockchain "kindCounts")))
    (is (= 4 (fixture-object-field state "count")))
    (is (= 4 (fixture-object-field state "executedCount")))
    (is (= 25 (fixture-object-field transaction "count")))
    (is (= 25 (fixture-object-field transaction "executedCount")))
    (is (= 9 (fixture-object-field blockchain "count")))
    (is (= 9 (fixture-object-field blockchain "executedCount")))
    (is (= 1 (fixture-object-field blockchain "blockCount")))
    (is (= 8 (fixture-object-field kind-counts "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field kind-counts "blockRlp")))
    (is (= 38 (fixture-object-field report "fixtureCaseCount")))
    (is (= 38 (fixture-object-field report "fixtureExecutedCount")))))

(defun devnet-smoke-gate-case-files (report field)
  (loop for case-report in (or (fixture-object-field report "cases") nil)
        for path = (fixture-object-field case-report field)
        when (stringp path)
          collect path))

(defun devnet-smoke-gate-case-database-files (report)
  (devnet-smoke-gate-case-files report "databaseFile"))

(defun devnet-cli-read-stream-string (stream)
  (with-output-to-string (output)
    (let ((buffer (make-string 8192)))
      (loop for count = (read-sequence buffer stream)
            until (zerop count)
            do (write-string buffer output :end count)))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

#+sbcl
(defun devnet-cli-open-loopback-socket (&key (port 0))
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind
           socket
           (sb-bsd-sockets:make-inet-address "127.0.0.1")
           port)
          (sb-bsd-sockets:socket-listen socket 1)
          (multiple-value-bind (address bound-port)
              (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (values socket bound-port)))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

#+sbcl
(defun devnet-cli-http-endpoint-host-port (endpoint)
  (let* ((prefix "http://")
         (start (if (and (<= (length prefix) (length endpoint))
                         (string= prefix endpoint :end2 (length prefix)))
                    (length prefix)
                    0))
         (colon (position #\: endpoint :start start :from-end t)))
    (unless colon
      (error "HTTP endpoint lacks a port: ~A" endpoint))
    (values (subseq endpoint start colon)
            (parse-integer endpoint :start (1+ colon)))))

#+sbcl
(defun devnet-cli-connect-stream (host port)
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (sb-bsd-sockets:socket-connect
     socket
     (sb-bsd-sockets:make-inet-address host)
     port)
    (sb-bsd-sockets:socket-make-stream
     socket
     :input t
     :output t
     :element-type 'character
     :external-format :utf-8
     :buffering :none)))

#+sbcl
(defun devnet-cli-unused-loopback-port ()
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (unwind-protect
         (progn
           (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
           (sb-bsd-sockets:socket-bind
            socket
            (sb-bsd-sockets:make-inet-address "127.0.0.1")
            0)
           (multiple-value-bind (address port)
               (sb-bsd-sockets:socket-name socket)
             (declare (ignore address))
             port))
      (ignore-errors
        (sb-bsd-sockets:socket-close socket)))))

#+sbcl
(defun devnet-cli-http-endpoint-connectable-p (endpoint)
  (multiple-value-bind (host port)
      (devnet-cli-http-endpoint-host-port endpoint)
    (let ((stream nil))
      (handler-case
          (progn
            (setf stream (devnet-cli-connect-stream host port))
            t)
        (sb-bsd-sockets:operation-not-permitted-error ()
          (error "Local socket connect is not permitted in this sandbox"))
        (error ()
          nil))
      (when stream
        (close stream)))))

#+sbcl
(defun devnet-cli-http-endpoint-request (endpoint request)
  (multiple-value-bind (host port)
      (devnet-cli-http-endpoint-host-port endpoint)
    (let ((stream (devnet-cli-connect-stream host port)))
      (unwind-protect
           (progn
             (write-string request stream)
             (finish-output stream)
             (devnet-cli-read-stream-string stream))
        (close stream)))))

(deftest engine-rpc-http-socket-listener-advertises-loopback-for-wildcard-host
  #-sbcl
  (skip-test "Devnet wildcard socket endpoint test requires SBCL sockets")
  #+sbcl
  (let ((listener nil))
    (handler-case
        (unwind-protect
             (progn
               (setf listener
                     (make-engine-rpc-http-socket-listener
                      (make-engine-rpc-http-service
                       :host "0.0.0.0"
                       :port 0)))
               (let ((endpoint
                       (engine-rpc-http-listener-endpoint listener)))
                 (is (search "127.0.0.1:" endpoint))
                 (is (not (search "0.0.0.0:" endpoint)))))
          (when listener
            (ignore-errors
              (engine-rpc-http-listener-close listener))))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest devnet-node-start-closes-engine-socket-on-public-bind-error
  #-sbcl
  (skip-test "Devnet socket bind cleanup requires SBCL sockets")
  #+sbcl
  (let ((engine-probe nil)
        (public-socket nil)
        (rebound-socket nil)
        (engine-port nil)
        (public-port nil)
        (rebound-port nil))
    (handler-case
        (unwind-protect
             (progn
               (multiple-value-setq (engine-probe engine-port)
                 (devnet-cli-open-loopback-socket))
               (sb-bsd-sockets:socket-close engine-probe)
               (setf engine-probe nil)
               (multiple-value-setq (public-socket public-port)
                 (devnet-cli-open-loopback-socket))
               (let ((node (ethereum-lisp.cli:make-devnet-node
                            :genesis-path +devnet-cli-genesis-fixture+
                            :port engine-port
                            :public-port public-port)))
                 (signals error
                   (ethereum-lisp.cli:start-devnet-node
                    node
                    :max-connections 0)))
               (multiple-value-setq (rebound-socket rebound-port)
                 (devnet-cli-open-loopback-socket :port engine-port))
               (is (= engine-port rebound-port)))
          (when engine-probe
            (ignore-errors (sb-bsd-sockets:socket-close engine-probe)))
          (when public-socket
            (ignore-errors (sb-bsd-sockets:socket-close public-socket)))
          (when rebound-socket
            (ignore-errors (sb-bsd-sockets:socket-close rebound-socket))))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest ethereum-lisp-script-public-bind-error-reports-error-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL sockets")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (public-socket nil)
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-bind-error-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-bind-error" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-bind-error" "pid")))
    (handler-case
        (unwind-protect
             (progn
               (multiple-value-setq (public-socket public-port)
                 (devnet-cli-open-loopback-socket))
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          genesis
                          "--engine-port"
                          "0"
                          "--public-port"
                          (write-to-string public-port)
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (when (search "Operation not permitted" stderr)
                   (skip-test
                    "Local socket bind is not permitted in this sandbox"))
                 (is (= 1 status))
                 (is (string= "" stdout))
                 (is (search "Usage: ethereum-lisp devnet" stderr))
                 (is (not (probe-file ready-path)))
                 (is (probe-file pid-path))
                 (let* ((log-records (devnet-cli-file-forms log-path))
                        (record (first log-records))
                        (fields (getf record :fields))
                        (log-names
                          (mapcar (lambda (entry) (getf entry :name))
                                  log-records))
                        (process-id
                          (parse-integer
                           (cdr (assoc "processId" fields :test #'string=))
                           :junk-allowed nil)))
                   (is (= 1 (length log-records)))
                   (is (eq :log (getf record :kind)))
                   (is (eq :error (getf record :value)))
                   (is (string= "devnet.error" (getf record :name)))
                   (is (not (member "devnet.ready"
                                    log-names
                                    :test #'string=)))
                   (is (not (member "devnet.shutdown"
                                    log-names
                                    :test #'string=)))
                   (is (string= "error"
                                (cdr (assoc "lifecyclePhase"
                                            fields
                                            :test #'string=))))
                   (is (string= "1"
                                (cdr (assoc "exitCode"
                                            fields
                                            :test #'string=))))
                   (is (plusp process-id))
                   (is (not (= (devnet-cli-current-process-id) process-id)))
                   (is (search "bind"
                               (string-downcase
                                (cdr (assoc "errorMessage"
                                            fields
                                            :test #'string=)))))
                   (is (string= (namestring log-path)
                                (cdr (assoc "logPath"
                                            fields
                                            :test #'string=))))
                   (is (= process-id
                          (devnet-cli-pid-file-process-id pid-path))))))
          (when public-socket
            (ignore-errors (sb-bsd-sockets:socket-close public-socket)))
          (when (probe-file ready-path)
            (delete-file ready-path))
          (when (probe-file log-path)
            (delete-file log-path))
          (when (probe-file pid-path)
            (delete-file pid-path)))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest ethereum-lisp-script-ready-file-error-reports-error-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL sockets")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-directory
          (devnet-cli-temp-directory
           "ethereum-lisp-script-ready-file-error"))
        (log-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-ready-file-error" "log"))
        (pid-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-ready-file-error" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    script
                    "--"
                    "devnet"
                    "--genesis"
                    genesis
                    "--engine-port"
                    "0"
                    "--public-port"
                    "0"
                    "--ready-file"
                    (namestring ready-directory)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--json"
                    "--max-connections"
                    "0")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (search "Operation not permitted" stderr)
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 1 status))
           (is (string= "" stdout))
           (is (search "Expected a file pathname" stderr))
           (is (search "Usage: ethereum-lisp devnet" stderr))
           (is (probe-file pid-path))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields))
                  (log-names
                    (mapcar (lambda (entry) (getf entry :name))
                            log-records))
                  (process-id
                    (parse-integer
                     (cdr (assoc "processId" fields :test #'string=))
                     :junk-allowed nil)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (not (member "devnet.ready" log-names :test #'string=)))
             (is (not (member "devnet.shutdown" log-names :test #'string=)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (plusp process-id))
             (is (not (= (devnet-cli-current-process-id) process-id)))
             (is (search "Expected a file pathname"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= (namestring log-path)
                          (cdr (assoc "logPath" fields :test #'string=))))
             (is (= process-id
                    (devnet-cli-pid-file-process-id pid-path)))))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file ready-directory)
        (ignore-errors
          (uiop:delete-directory-tree ready-directory :validate t))))))

(defun devnet-smoke-gate-launch-json-process ()
  (uiop:launch-program
   (list "sbcl"
         "--script"
         "scripts/devnet-smoke-gate.lisp"
         "--"
         "--json")
   :output :stream
   :error-output :stream))

(defun devnet-smoke-gate-finish-json-process (process)
  (let ((status (uiop:wait-process process))
        (stdout
          (devnet-cli-read-stream-string (uiop:process-info-output process)))
        (stderr
          (devnet-cli-read-stream-string
           (uiop:process-info-error-output process))))
    (values stdout stderr status)))

(deftest devnet-smoke-gate-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/devnet-smoke-gate.lisp"
                stdout))
    (is (search "--all-fixtures" stdout))
    (is (search "--engine-only-serve" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--log-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--database PATH" stdout))
    (is (search "--prune-state-before NUMBER" stdout))
    (is (search "--override.terminaltotaldifficulty TTD" stdout))
    (is (search "--override.terminaltotaldifficultypassed" stdout))
    (is (search "--override.terminalblockhash HASH" stdout))
    (is (search "--override.terminalblocknumber NUMBER" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest devnet-smoke-gate-script-engine-only-serve-mode
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let* ((artifact-root
           (devnet-cli-temp-directory
            "ethereum-lisp-devnet-engine-only-smoke"))
         (ready-path
           (merge-pathnames "ready/engine-only.json" artifact-root))
         (log-path
           (merge-pathnames "logs/engine-only.log" artifact-root))
         (pid-path
           (merge-pathnames "pid/engine-only.pid" artifact-root))
         (database-path
           (merge-pathnames "db/engine-only.sexp" artifact-root)))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--engine-only-serve"
                    "--json"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--database"
                    (namestring database-path))
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (and (not (= 0 status))
                      (search "Operation not permitted" stderr))
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (ready-record
                      (find "devnet.ready" log-records
                            :test #'string=
                            :key (lambda (record)
                                   (getf record :name))))
                    (shutdown-record
                      (find "devnet.shutdown" log-records
                            :test #'string=
                            :key (lambda (record)
                                   (getf record :name))))
                    (shutdown-fields
                      (getf shutdown-record :fields))
                    (engine-endpoint
                      (fixture-object-field report "engineEndpoint")))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-engine-only-serve"
                            (fixture-object-field report "mode")))
               (is (search "http://127.0.0.1:" engine-endpoint))
               (is (not (fixture-object-field report "publicRpcEnabled")))
               (is (not (fixture-object-field report "rpcEndpoint")))
               (is (string= "/engine"
                            (fixture-object-field report "engineRpcPrefix")))
               (is (= 200 (fixture-object-field report
                                                 "engineRpcPrefixStatus")))
               (is (= 404 (fixture-object-field
                            report
                            "engineRpcPrefixBlockedStatus")))
               (devnet-cli-assert-engine-only-http-shaping-report report)
               (devnet-cli-assert-engine-capability-report report)
               (devnet-cli-assert-kzg-opt-in-smoke-report
                (fixture-object-field report "kzgOptIn"))
               (devnet-cli-assert-engine-client-version report)
               (devnet-cli-assert-engine-transition-configuration report)
               (devnet-cli-assert-engine-only-payload-report report)
               (is (search "http://127.0.0.1:"
                           (fixture-object-field report
                                                 "configuredPublicEndpoint")))
               (is (not (fixture-object-field report
                                               "publicEndpointConnectable")))
               (is (= 7 (fixture-object-field report "engineConnections")))
               (is (= 0 (fixture-object-field report "publicConnections")))
               (is (= 7 (fixture-object-field report "totalConnections")))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (probe-file database-path))
               (is (= (fixture-quantity-field report "forkchoiceHeadNumber")
                      (fixture-object-field report "databaseHeadNumber")))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadHash")
                            (fixture-object-field report
                                                  "databaseHeadHash")))
               (is (fixture-object-field report "databaseStateAvailable"))
               (is (string= "ethereum-lisp"
                            (fixture-object-field report
                                                  "engineClientVersionName")))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= engine-endpoint
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (equal '("https://engine-runner.example"
                            "https://engine-observer.example")
                          (fixture-object-field ready-summary
                                                "engineCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "engineVhosts")))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                              "publicRpcEnabled")))
               (is ready-record)
               (is shutdown-record)
               (is (string= "7"
                            (cdr (assoc "engineConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "0"
                            (cdr (assoc "publicConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "7"
                            (cdr (assoc "totalConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "https://engine-runner.example,https://engine-observer.example"
                            (cdr (assoc "engineCorsOrigins"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "engine.runner,localhost"
                            (cdr (assoc "engineVhosts"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadNumber")
                            (cdr (assoc "headNumber"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadHash")
                            (cdr (assoc "headHash"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= ""
                            (cdr (assoc "rpcEndpoint"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "false"
                            (cdr (assoc "publicRpcEnabled"
                                        shutdown-fields
                                        :test #'string=)))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-writes-ready-and-log-files
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let* ((artifact-root
           (devnet-cli-temp-directory "ethereum-lisp-devnet-smoke-artifacts"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" artifact-root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" artifact-root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" artifact-root))
         (database-path
           (merge-pathnames "database/nested/devnet-chain.sexp" artifact-root))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (reference-token
           (format nil "~A-~A" (sb-unix:unix-getpid) (gensym))))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "env"
                    (format nil "ETHEREUM_LISP_GETH_ROOT=/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_RETH_ROOT=/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                            reference-token)
                    "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json=true"
                    "--all-fixtures=false"
                    (format nil "--ready-file=~A" (namestring ready-path))
                    (format nil "--log-file=~A" (namestring log-path))
                    (format nil "--pid-file=~A" (namestring pid-path))
                    (format nil "--database=~A" (namestring database-path))
                    "--prune-state-before=42"
                    "--override.terminaltotaldifficulty=0x3039"
                    "--override.terminaltotaldifficultypassed=true"
                    (format nil "--override.terminalblockhash=~A"
                            terminal-block-hash)
                    "--override.terminalblocknumber=66")
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (is (search "\"txpoolPendingFilterEmptyChanges\":[]" stdout))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (database
                      (make-file-key-value-database database-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "geth"
                (format nil "/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "nethermind"
                (format nil "/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "reth"
                (format nil "/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                        reference-token))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field report "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field report "rpcEndpoint")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineUnauthenticatedStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineInvalidAuthStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineDuplicateAuthStatus")))
               (is (= 404
                      (fixture-object-field
                       report
                       "engineRootWrongPathStatus")))
               (devnet-cli-assert-engine-capability-report report)
               (devnet-cli-assert-engine-client-version report)
               (devnet-cli-assert-engine-transition-configuration
                report
                :terminal-total-difficulty "0x3039"
                :terminal-block-hash terminal-block-hash
                :terminal-block-number "0x42")
               (devnet-cli-assert-engine-payload-bodies report)
               (devnet-cli-assert-engine-get-payload-v2 report)
               (is (= -32601
                      (fixture-object-field
                       report
                       "enginePublicNamespaceErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicEngineNamespaceErrorCode")))
               (is (= -32700
                      (fixture-object-field
                       report
                       "publicMalformedJsonErrorCode")))
               (is (= 404
                      (fixture-object-field
                       report
                       "publicRootWrongPathStatus")))
               (is (equal '("eth" "net")
                          (fixture-object-field report
                                                "publicApiAllowlist")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           report
                           "publicApiAllowlistReportedModules")))
               (is (string= "eth,net"
                            (fixture-object-field
                             report
                             "publicApiAllowlistTelemetryModules")))
               (is (= 0
                      (fixture-object-field
                       report
                       "publicApiAllowlistEngineConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistPublicConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistTotalConnections")))
               (is (string= "0x539"
                            (fixture-object-field
                             report
                             "publicApiAllowlistChainId")))
               (is (string= "7331"
                            (fixture-object-field
                             report
                             "publicApiAllowlistNetworkVersion")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedWeb3ErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedTxpoolErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedEngineErrorCode")))
               (devnet-cli-assert-public-cors-smoke-report report)
               (devnet-cli-assert-engine-cors-smoke-report report)
               (devnet-cli-assert-http-shaping-smoke-report report)
               (devnet-cli-assert-vhost-smoke-report report)
               (devnet-cli-assert-rpc-prefix-smoke-report report)
               (devnet-cli-assert-connection-contract report 1)
               (is (= (fixture-object-field ready-summary "processId")
                      (devnet-cli-pid-file-process-id pid-path)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= 42 (fixture-object-field
                          report "databasePruneStateBefore")))
               (is (eq nil
                       (fixture-object-field
                        report "databasePrunedStateAvailable")))
               (is (string= "eth_getBalance state is not available"
                            (fixture-object-field
                             report "databaseRpcPrunedStateError")))
               (let ((errors
                       (fixture-object-field
                        report "databaseRpcPrunedStateErrors")))
                 (is (= 8 (length errors)))
                 (dolist (message (devnet-cli-pruned-state-error-messages))
                   (is (member message errors :test #'string=))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database
                    :state
                    (hash32-bytes
                     (hash32-from-hex
                      (fixture-object-field report "safeBlockHash")))
                    :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field report
                                                  "databaseHeadNumber")))
               (is (string= (fixture-object-field report "blockGasLimit")
                            (fixture-object-field report
                                                  "databaseHeadGasLimit")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field report
                                                  "databaseSafeNumber")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field report "databaseSafeHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseFinalizedNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseFinalizedHash")))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field
                             report "databaseRpcBlockNumber")))
               (is (string= (fixture-object-field report "checkedBalance")
                            (fixture-object-field
                             report "databaseRpcBalance")))
               (is (string= (fixture-object-field report "checkedNonce")
                            (fixture-object-field report "databaseRpcNonce")))
               (is (string= (fixture-object-field report "checkedCode")
                            (fixture-object-field report "databaseRpcCode")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcStorage")))
               (is (string= (fixture-object-field
                              report "checkedStorageAddress")
                            (fixture-object-field
                             report "databaseRpcProofAddress")))
               (is (string= (fixture-object-field
                              report "checkedProofCodeHash")
                            (fixture-object-field
                             report "databaseRpcProofCodeHash")))
               (is (string= (fixture-object-field report "checkedStorageKey")
                            (fixture-object-field
                             report "databaseRpcProofStorageKey")))
               (is (string= (fixture-object-field
                              report "checkedProofStorageValue")
                            (fixture-object-field
                             report "databaseRpcProofStorageValue")))
               (is (= 1 (fixture-object-field
                         report "databaseRpcProofStorageCount")))
               (is (<= 0 (fixture-object-field
                          report "databaseRpcProofAccountProofCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByHashNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberNumber")
                            (fixture-object-field report "blockNumber")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberHash")
                            (fixture-object-field
                             report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcTransactionBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field
                       report "databaseRpcBlockReceiptsCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcBlockReceiptBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field report
                                            "databaseRpcTransactionCount")))
               (devnet-cli-assert-restored-full-block-transactions report)
               (is (= (fixture-object-field report "checkedBalanceCount")
                      (fixture-object-field report
                                            "databaseRpcBalanceCount")))
               (is (= (fixture-object-field report "checkedLogCount")
                      (fixture-object-field report
                                            "databaseRpcLogCount")))
               (devnet-cli-assert-restored-log-filters report)
               (devnet-cli-assert-restored-block-filter report)
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByHash")))
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByNumber")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report "databaseRpcCanonicalHashBalance")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report
                             "databaseRpcCanonicalHashRequireBalance")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByBlockHashAndIndex")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockNumberAndIndex")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByHash")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockHashAndIndex")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexIndex")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexIndex")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field
                             report "databaseRpcSafeBlockHash")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field
                             report "databaseRpcSafeBlockNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockNumber")))
               (is (= (fixture-object-field report "checkedSimulationCount")
                      (fixture-object-field report
                                            "databaseRpcSimulationCount")))
               (is (string= "0x"
                            (fixture-object-field
                             report "databaseRpcCallResult")))
               (is (<= 21000
                       (hex-to-quantity
                        (fixture-object-field
                         report "databaseRpcEstimateGas"))))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcAccessListGasUsed")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcPostCallStorage")))
               (is (= (devnet-cli-restored-public-connections report)
                      (fixture-object-field
                       report "databaseRpcPublicConnections")))
               (is (string= (fixture-object-field report "preparedPayloadId")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadId")))
               (is (string= (fixture-object-field
                              report "preparedPayloadParentHash")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadParentHash")))
               (is (string= (fixture-object-field
                              report "preparedPayloadBlockNumber")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadBlockNumber")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field report "remoteBlockStatus")))
               (is (string= (fixture-object-field report "remoteBlockHash")
                            (fixture-object-field
                             report "databaseRemoteBlockHash")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field
                             report "databaseRpcRemoteBlockStatus")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field report
                                                  "invalidTipsetStatus")))
               (is (string= "Timestamp is not greater than parent timestamp"
                            (fixture-object-field
                             report "invalidTipsetValidationError")))
               (is (string= (fixture-object-field
                              report "invalidTipsetBlockHash")
                            (fixture-object-field
                             report "databaseInvalidTipsetBlockHash")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field
                             report "databaseRpcInvalidTipsetStatus")))
               (is (string= "links to previously rejected block"
                            (fixture-object-field
                             report
                             "databaseRpcInvalidTipsetValidationError")))
               (devnet-cli-assert-txpool-subpool-persistence report)
               (devnet-cli-assert-side-reorg-persistence report)
               (is (< 0 (length (kv-chain-record-entries database :block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :prepared-payload))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :remote-block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :invalid-tipset))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :txpool))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :canonical-hash))))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (integerp (fixture-object-field ready-summary
                                                    "processId")))
               (is (< 0 (fixture-object-field ready-summary "processId")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (eq t (fixture-object-field ready-summary
                                                "stateAvailable")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headNumber"))))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field ready-summary
                                                  "headHash")))
               (is (string= (fixture-object-field report "safeBlockGasLimit")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headGasLimit"))))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let* ((fields (getf log-record :fields))
                          (ready-p (string= "devnet.ready"
                                            (getf log-record :name)))
	                          (expected-head-number
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockNumber"
	                                 "txpoolImportBlockNumber")))
	                          (expected-head-hash
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockHash"
	                                 "txpoolImportBlockHash")))
                          (expected-head-gas-limit
                            (fixture-object-field
                             report
                             (if ready-p
                                 "safeBlockGasLimit"
                                 "blockGasLimit"))))
                     (is (string= expected-head-number
                                  (cdr (assoc "headNumber" fields
                                              :test #'string=))))
                     (is (string= expected-head-hash
                                  (cdr (assoc "headHash" fields
                                              :test #'string=))))
                     (is (string= expected-head-gas-limit
                                  (cdr (assoc "headGasLimit" fields
                                              :test #'string=))))
                     (is (string= (if ready-p "ready" "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report
                                                        "engineEndpoint")
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report "rpcEndpoint")
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (write-to-string
                                    (fixture-object-field ready-summary
                                                          "processId"))
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))
                     (is (string= "true"
                                  (cdr (assoc "stateAvailable" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

(deftest devnet-smoke-gate-script-runs-all-pinned-fixtures
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((ready-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "pid"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-chain"
                                "sexp"))
        (prune-boundary 42)
        (ready-files nil)
        (log-files nil)
        (pid-files nil)
        (database-files nil))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json"
                    "--all-fixtures"
                    "--ready-file" (namestring ready-path)
                    "--log-file" (namestring log-path)
                    "--pid-file" (namestring pid-path)
                    "--database" (namestring database-path)
                    "--prune-state-before"
                    (write-to-string prune-boundary))
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (cases (fixture-object-field report "cases"))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (case-names
                      (mapcar (lambda (case)
                                (fixture-object-field case "fixtureCase"))
                              cases)))
               (setf database-files
                     (devnet-smoke-gate-case-database-files report)
                     ready-files
                     (devnet-smoke-gate-case-files report "readyFile")
                     log-files
                     (devnet-smoke-gate-case-files report "logFile")
                     pid-files
                     (devnet-smoke-gate-case-files report "pidFile"))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary-suite"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "caseCount")))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "readyCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length ready-files)))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "logCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length log-files)))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "pidCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length pid-files)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "databaseCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length database-files)))
               (devnet-cli-assert-pruned-state-suite
                report cases prune-boundary)
               (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "engineConnections")))
               (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "publicConnections")))
               (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "totalConnections")))
               (devnet-cli-assert-connection-contract
                report
                (length +engine-newpayload-v2-smoke-case-names+))
               (is (equal +engine-newpayload-v2-smoke-case-names+ case-names))
               (dolist (case cases)
                 (let ((expected-block-number
                         (devnet-cli-engine-fixture-payload-number
                          (fixture-object-field case "fixtureCase"))))
                   (is (string= "ok" (fixture-object-field case "status")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "newPayloadStatus")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "forkchoiceStatus")))
                   (is (= 23 (fixture-object-field case "engineConnections")))
                   (is (= 54 (fixture-object-field case "publicConnections")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineUnauthenticatedStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineInvalidAuthStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineDuplicateAuthStatus")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "engineRootWrongPathStatus")))
                   (devnet-cli-assert-engine-capability-report case)
                   (devnet-cli-assert-engine-client-version case)
                   (devnet-cli-assert-engine-transition-configuration case)
                   (devnet-cli-assert-public-readiness case)
                   (devnet-cli-assert-engine-payload-bodies case)
                   (devnet-cli-assert-engine-get-payload-v2 case)
                   (is (= -32601
                          (fixture-object-field
                           case
                           "enginePublicNamespaceErrorCode")))
                   (is (= -32601
                          (fixture-object-field
                           case
                           "publicEngineNamespaceErrorCode")))
                   (is (= -32700
                          (fixture-object-field
                           case
                           "publicMalformedJsonErrorCode")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "publicRootWrongPathStatus")))
                   (devnet-cli-assert-public-cors-smoke-report case)
                   (devnet-cli-assert-engine-cors-smoke-report case)
                   (devnet-cli-assert-http-shaping-smoke-report case)
                   (devnet-cli-assert-vhost-smoke-report case)
                   (devnet-cli-assert-rpc-prefix-smoke-report case)
                   (is (string= expected-block-number
                                 (fixture-object-field case "blockNumber"))))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseHeadNumber")))
                 (is (string= (fixture-object-field case "blockGasLimit")
                              (fixture-object-field
                               case "databaseHeadGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseSafeNumber")))
                 (is (stringp (fixture-object-field
                                case "safeBlockGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseSafeHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseFinalizedNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseFinalizedHash")))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseRpcBlockNumber")))
                 (is (string= (fixture-object-field case "checkedBalance")
                              (fixture-object-field
                               case "databaseRpcBalance")))
                 (is (string= (fixture-object-field case "checkedNonce")
                              (fixture-object-field
                               case "databaseRpcNonce")))
                 (is (string= (fixture-object-field case "checkedCode")
                              (fixture-object-field
                               case "databaseRpcCode")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcStorage")))
                 (is (string= (fixture-object-field
                                case "checkedStorageAddress")
                              (fixture-object-field
                               case "databaseRpcProofAddress")))
                 (is (string= (fixture-object-field
                                case "checkedProofCodeHash")
                              (fixture-object-field
                               case "databaseRpcProofCodeHash")))
                 (is (string= (fixture-object-field case "checkedStorageKey")
                              (fixture-object-field
                               case "databaseRpcProofStorageKey")))
                 (is (string= (fixture-object-field
                                case "checkedProofStorageValue")
                              (fixture-object-field
                               case "databaseRpcProofStorageValue")))
                 (is (= 1 (fixture-object-field
                           case "databaseRpcProofStorageCount")))
                 (is (<= 0 (fixture-object-field
                            case "databaseRpcProofAccountProofCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByHashNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberHash")
                              (fixture-object-field
                               case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcTransactionBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field
                         case "databaseRpcBlockReceiptsCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcBlockReceiptBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field case
                                              "databaseRpcTransactionCount")))
                 (devnet-cli-assert-restored-full-block-transactions case)
                 (is (= (fixture-object-field case "checkedBalanceCount")
                        (fixture-object-field case "databaseRpcBalanceCount")))
                 (is (= (fixture-object-field case "checkedLogCount")
                        (fixture-object-field case "databaseRpcLogCount")))
                 (devnet-cli-assert-restored-log-filters case)
                 (devnet-cli-assert-restored-block-filter case)
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByHash")))
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByNumber")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case "databaseRpcCanonicalHashBalance")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case
                               "databaseRpcCanonicalHashRequireBalance")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByBlockHashAndIndex")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockNumberAndIndex")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByHash")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockHashAndIndex")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexIndex")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexIndex")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseRpcSafeBlockHash")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseRpcSafeBlockNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockNumber")))
                 (is (= (fixture-object-field case "checkedSimulationCount")
                        (fixture-object-field
                         case "databaseRpcSimulationCount")))
                 (is (string= "0x"
                              (fixture-object-field
                               case "databaseRpcCallResult")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field
                           case "databaseRpcEstimateGas"))))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcAccessListGasUsed")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcPostCallStorage")))
                 (is (= (devnet-cli-restored-public-connections case)
                        (fixture-object-field
                         case "databaseRpcPublicConnections")))
                 (is (string= (fixture-object-field case "preparedPayloadId")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadId")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadParentHash")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadParentHash")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadBlockNumber")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadBlockNumber")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field case "remoteBlockStatus")))
                 (is (string= (fixture-object-field case "remoteBlockHash")
                              (fixture-object-field
                               case "databaseRemoteBlockHash")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field
                               case "databaseRpcRemoteBlockStatus")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field case
                                                    "invalidTipsetStatus")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field
                               case "invalidTipsetValidationError")))
                 (is (string= (fixture-object-field
                                case "invalidTipsetBlockHash")
                              (fixture-object-field
                               case "databaseInvalidTipsetBlockHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field
                               case "databaseRpcInvalidTipsetStatus")))
                 (is (string= "links to previously rejected block"
                              (fixture-object-field
                               case
                               "databaseRpcInvalidTipsetValidationError")))
                 (devnet-cli-assert-txpool-subpool-persistence case)
                 (devnet-cli-assert-side-reorg-persistence case)
                 (is (probe-file
                      (fixture-object-field case "readyFile")))
                 (is (probe-file
                      (fixture-object-field case "logFile")))
                 (is (probe-file
                      (fixture-object-field case "databaseFile")))))))
      (dolist (path (append ready-files log-files pid-files database-files))
        (when (probe-file path)
          (delete-file path)))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-runs-concurrently
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((first-process (devnet-smoke-gate-launch-json-process))
        (second-process (devnet-smoke-gate-launch-json-process)))
    (multiple-value-bind (first-stdout first-stderr first-status)
        (devnet-smoke-gate-finish-json-process first-process)
      (multiple-value-bind (second-stdout second-stderr second-status)
          (devnet-smoke-gate-finish-json-process second-process)
        (is (= 0 first-status))
        (is (= 0 second-status))
        (is (string= "" first-stderr))
        (is (string= "" second-stderr))
        (when (and (= 0 first-status) (= 0 second-status))
          (dolist (report (list (parse-json first-stdout)
                                (parse-json second-stdout)))
            (is (string= "ok" (fixture-object-field report "status")))
            (is (string= "devnet-listener-boundary"
                         (fixture-object-field report "mode")))
            (phase-a-smoke-gate-assert-execution-spec-tests-source report)
            (is (= 3 (length (fixture-object-field report
                                                   "referenceClients"))))))))))

(deftest phase-a-fixture-report-includes-reference-client-pins
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--json"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (reference-clients
               (fixture-object-field report "referenceClients")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")))))

(deftest phase-a-report-scripts-honor-reference-client-root-env
  #-sbcl
  (skip-test "Phase A report scripts require SBCL")
  #+sbcl
  (let* ((token (format nil "~A-~A" (sb-unix:unix-getpid) (gensym)))
         (geth-root
           (format nil "/private/tmp/ethereum-lisp-geth-root-~A/" token))
         (nethermind-root
           (format nil "/private/tmp/ethereum-lisp-nethermind-root-~A/"
                   token))
         (reth-root
           (format nil "/private/tmp/ethereum-lisp-reth-root-~A/" token))
         (environment
           (list
            (format nil "ETHEREUM_LISP_GETH_ROOT=~A" geth-root)
            (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=~A"
                    nethermind-root)
            (format nil "ETHEREUM_LISP_RETH_ROOT=~A" reth-root))))
    (labels ((run-report (script &rest extra-args)
               (uiop:run-program
                (append
                 (list "env")
                 environment
                 (list "sbcl" "--script" script "--")
                 extra-args)
                :output :string
                :error-output :string
                :ignore-error-status t))
             (assert-reference-roots (report)
               (let ((reference-clients
                       (fixture-object-field report "referenceClients")))
                 (is (= 3 (length reference-clients)))
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "geth" geth-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "nethermind" nethermind-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "reth" reth-root)
                 (dolist (name '("geth" "nethermind" "reth"))
                   (phase-a-smoke-gate-assert-reference-client
                    reference-clients name)))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-fixture-report.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-smoke-gate.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout)))))))

(deftest phase-a-fixture-report-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-fixture-report.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--json" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-help-prints-reference-root-env
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-smoke-gate.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--devnet" stdout))
    (is (search "--drift-map" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-script-accepts-geth-style-option-values
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-phase-a-smoke-equals-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               "-u"
               "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json=true"
               "--devnet=false"
               "--drift-map=false"
               "--pinned-v5.4.0=false"
               (format nil "--root=~A" root-string))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST state_tests root under"
                  stderr))
      (is (not (search "Unsupported smoke gate option" stderr))))))

(deftest phase-a-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--devnet=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--devnet boolean value must be true or false" stderr))))

(deftest phase-a-fixture-report-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A fixture report requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-fixture-report-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-report-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-fixture-report.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A fixture report root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest phase-a-selector-scripts-accept-root-option
  #-sbcl
  (skip-test "Phase A selector scripts require SBCL")
  #+sbcl
  (labels ((run-selector-script (script)
             (multiple-value-bind (stdout stderr status)
                 (uiop:run-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--json"
                        "--root"
                        "tests/fixtures/execution-spec-tests-root/")
                  :output :string
                  :error-output :string
                  :ignore-error-status t)
               (is (= 0 status))
               (is (string= "" stderr))
               (when (= 0 status)
                 (let ((report (parse-json stdout)))
                   (is (search "tests/fixtures/execution-spec-tests-root/"
                               (fixture-object-field report "root")))
                   (is (plusp (fixture-object-field report "count"))))))))
    (run-selector-script "scripts/list-state-test-selectors.lisp")
    (run-selector-script "scripts/list-transaction-test-selectors.lisp")
    (run-selector-script "scripts/list-blockchain-replay-selectors.lisp")))

(deftest phase-a-fixture-sync-scripts-reject-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((env-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-env-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (env-root-string (namestring env-root))
         (explicit-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-explicit-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (explicit-root-string (namestring explicit-root)))
    (labels ((run-script-with-missing-env-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          (format nil
                                  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                                  env-root-string)
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json")
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search env-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                             stderr))))
             (run-script-with-missing-explicit-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          explicit-root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search explicit-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "--root" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-missing-env-root script)
        (run-script-with-missing-explicit-root script)))))

(deftest phase-a-fixture-sync-scripts-reject-empty-suite-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-fixture-sync-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (subdir '("state_tests/"
                      "transaction_tests/"
                      "blockchain_tests_engine/"))
      (ensure-directories-exist (merge-pathnames subdir root)))
    (labels ((run-script-with-empty-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search root-string stderr))
                 (is (search "contains no JSON files" stderr))
                 (is (search "Configured EEST" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/phase-a-smoke-gate.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-empty-root script)))))

(deftest phase-a-smoke-gate-script-can-include-devnet-suite
  #-sbcl
  (skip-test "Phase A smoke gate devnet mode requires SBCL")
  #+sbcl
  (let ((prune-boundary 42))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json"
               "--devnet")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (reference-clients
                 (fixture-object-field report "referenceClients"))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly"))
               (cases (fixture-object-field devnet "cases")))
        (is (string= "ok" (fixture-object-field report "status")))
        (is (string= "in-repo" (fixture-object-field report "mode")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (phase-a-smoke-gate-assert-counts report)
        (phase-a-smoke-gate-assert-in-repo-fixture-counts report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")
        (is (string= "ok" (fixture-object-field devnet "status")))
        (is (string= "devnet-listener-boundary-suite"
                     (fixture-object-field devnet "mode")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "caseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "readyCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "readyFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "logCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "logFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "pidCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "pidFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "databaseCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-database-files devnet))))
        (devnet-cli-assert-pruned-state-suite
         devnet cases prune-boundary)
        (is (= 0 (fixture-object-field devnet "sideReorgCaseCount")))
        (is (string= "ok"
                     (fixture-object-field
                      devnet-engine-only "status")))
        (is (string= "devnet-engine-only-serve"
                     (fixture-object-field
                      devnet-engine-only "mode")))
        (is (= 1 (fixture-object-field
                  devnet-engine-only "caseCount")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicRpcEnabled")))
        (is (not (fixture-object-field
                  devnet-engine-only "rpcEndpoint")))
        (is (string= "/engine"
                     (fixture-object-field
                      devnet-engine-only "engineRpcPrefix")))
        (is (= 200 (fixture-object-field
                    devnet-engine-only "engineRpcPrefixStatus")))
        (is (= 404 (fixture-object-field
                    devnet-engine-only
                    "engineRpcPrefixBlockedStatus")))
        (devnet-cli-assert-engine-only-http-shaping-report
         devnet-engine-only)
        (devnet-cli-assert-engine-capability-report
         devnet-engine-only)
        (devnet-cli-assert-engine-client-version
         devnet-engine-only)
        (devnet-cli-assert-engine-transition-configuration
         devnet-engine-only)
        (devnet-cli-assert-engine-only-payload-report
         devnet-engine-only)
        (devnet-cli-assert-engine-only-database-report
         devnet-engine-only)
        (is (search "http://127.0.0.1:"
                    (fixture-object-field
                     devnet-engine-only "configuredPublicEndpoint")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicEndpointConnectable")))
        (is (= 7 (fixture-object-field
                  devnet-engine-only "engineConnections")))
        (is (= 0 (fixture-object-field
                  devnet-engine-only "publicConnections")))
        (is (= 7 (fixture-object-field
                  devnet-engine-only "totalConnections")))
        (let ((side-reorg-cases
                (fixture-object-field devnet-side-reorg "cases")))
          (is (string= "ok"
                       (fixture-object-field devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field devnet-side-reorg "mode")))
          (is (equal +devnet-side-reorg-smoke-case-names+
                     (fixture-object-field
                      devnet-side-reorg "fixtureCases")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field devnet-side-reorg "caseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (length side-reorg-cases)))
          (dolist (case side-reorg-cases)
            (devnet-cli-assert-side-reorg-persistence case))
          (let ((log-case
                  (find "shanghai-log-contract-call-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is log-case)
            (when log-case
              (is (= 1 (fixture-object-field log-case "checkedLogCount")))
              (is (= 1 (fixture-object-field
                        log-case "databaseRpcLogCount")))
              (devnet-cli-assert-restored-log-filters log-case)
              (devnet-cli-assert-restored-block-filter log-case)))
          (let ((two-transfer-case
                  (find "shanghai-two-legacy-transfers-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is two-transfer-case)
            (when two-transfer-case
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideHiddenReceiptCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredHiddenReceiptCount")))
              (is (= 2 (length
                        (fixture-object-field
                         two-transfer-case
                         "databaseRpcSideReinsertedTransactionHashes")))))))
        (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "engineConnections")))
        (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "publicConnections")))
        (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "totalConnections")))
        (dolist (case cases)
          (devnet-cli-assert-public-readiness case)
          (is (string= (fixture-object-field case "txpoolImportBlockNumber")
                       (fixture-object-field
                        case "databaseRpcBlockNumber")))
          (is (string= (fixture-object-field case "safeBlockNumber")
                       (fixture-object-field
                        case "databaseSafeNumber")))
          (is (string= (fixture-object-field case "safeBlockHash")
                       (fixture-object-field case "databaseSafeHash")))
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseFinalizedNumber")))
          (is (string= (fixture-object-field case "finalizedBlockHash")
                       (fixture-object-field
                        case "databaseFinalizedHash")))
          (is (string= (fixture-object-field case "checkedBalance")
                       (fixture-object-field
                        case "databaseRpcBalance")))
          (is (string= (fixture-object-field case "checkedNonce")
                       (fixture-object-field
                        case "databaseRpcNonce")))
          (is (string= (fixture-object-field case "checkedCode")
                       (fixture-object-field
                        case "databaseRpcCode")))
          (is (string= (fixture-object-field case "checkedStorage")
                       (fixture-object-field
                        case "databaseRpcStorage")))
          (is (string= (fixture-object-field case "checkedStorageAddress")
                       (fixture-object-field
                        case "databaseRpcProofAddress")))
          (is (string= (fixture-object-field case "checkedProofCodeHash")
                       (fixture-object-field
                        case "databaseRpcProofCodeHash")))
          (is (string= (fixture-object-field case "checkedStorageKey")
                       (fixture-object-field
                        case "databaseRpcProofStorageKey")))
          (is (string= (fixture-object-field case "checkedProofStorageValue")
                       (fixture-object-field
                        case "databaseRpcProofStorageValue")))
          (is (= 1 (fixture-object-field
                    case "databaseRpcProofStorageCount")))
          (is (<= 0 (fixture-object-field
                     case "databaseRpcProofAccountProofCount")))
          (is (string= (fixture-object-field
                        case "databaseRpcReceiptBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByHashNumber")
                       (fixture-object-field case "blockNumber")))
          (is (stringp
               (fixture-object-field case "databaseRpcBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberNumber")
                       (fixture-object-field case "blockNumber")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberHash")
                       (fixture-object-field
                        case "databaseRpcBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcTransactionBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcTransactionBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (= (fixture-object-field case "transactionCount")
                 (fixture-object-field
                  case "databaseRpcBlockReceiptsCount")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockReceiptTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcBlockReceiptBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockReceiptBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (= (fixture-object-field case "transactionCount")
                 (fixture-object-field case
                                       "databaseRpcTransactionCount")))
          (devnet-cli-assert-restored-full-block-transactions case)
          (is (= (fixture-object-field case "checkedBalanceCount")
                 (fixture-object-field case "databaseRpcBalanceCount")))
          (is (= (fixture-object-field case "checkedLogCount")
                 (fixture-object-field case "databaseRpcLogCount")))
          (devnet-cli-assert-restored-log-filters case)
          (devnet-cli-assert-restored-block-filter case)
          (is (string= (quantity-to-hex
                         (fixture-object-field case "transactionCount"))
                       (fixture-object-field
                        case
                        "databaseRpcBlockTransactionCountByHash")))
          (is (string= (quantity-to-hex
                         (fixture-object-field case "transactionCount"))
                       (fixture-object-field
                        case
                        "databaseRpcBlockTransactionCountByNumber")))
          (is (string= (fixture-object-field case "databaseRpcBalance")
                       (fixture-object-field
                        case "databaseRpcCanonicalHashBalance")))
          (is (string= (fixture-object-field case "databaseRpcBalance")
                       (fixture-object-field
                        case
                        "databaseRpcCanonicalHashRequireBalance")))
          (is (string= (fixture-object-field
                         case
                         "databaseRpcRawTransactionByBlockHashAndIndex")
                       (fixture-object-field
                        case
                        "databaseRpcRawTransactionByBlockNumberAndIndex")))
          (is (string= (fixture-object-field
                         case
                         "databaseRpcRawTransactionByHash")
                       (fixture-object-field
                        case
                        "databaseRpcRawTransactionByBlockHashAndIndex")))
          (is (string= (fixture-object-field
                         case "databaseRpcReceiptTransactionHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcReceiptTransactionHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcBlockHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcBlockHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
          (is (string= (fixture-object-field case "blockNumber")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
          (is (string= (fixture-object-field case "blockNumber")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
          (is (string= "0x0"
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexIndex")))
          (is (string= "0x0"
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexIndex")))
          (is (string= (fixture-object-field case "safeBlockHash")
                       (fixture-object-field
                        case "databaseRpcSafeBlockHash")))
          (is (string= (fixture-object-field case "safeBlockNumber")
                       (fixture-object-field
                        case "databaseRpcSafeBlockNumber")))
          (is (string= (fixture-object-field case "finalizedBlockHash")
                       (fixture-object-field
                        case "databaseRpcFinalizedBlockHash")))
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseRpcFinalizedBlockNumber")))
          (is (= (fixture-object-field case "checkedSimulationCount")
                 (fixture-object-field case "databaseRpcSimulationCount")))
          (is (string= "0x"
                       (fixture-object-field
                        case "databaseRpcCallResult")))
          (is (<= 21000
                  (hex-to-quantity
                   (fixture-object-field
                    case "databaseRpcEstimateGas"))))
          (is (stringp
               (fixture-object-field
                case "databaseRpcAccessListGasUsed")))
          (is (string= (fixture-object-field case "checkedStorage")
                       (fixture-object-field
                        case "databaseRpcPostCallStorage")))
          (is (= (devnet-cli-restored-public-connections case)
                 (fixture-object-field
                  case "databaseRpcPublicConnections")))
          (is (string= (fixture-object-field case "preparedPayloadId")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadId")))
          (is (string= (fixture-object-field
                         case "preparedPayloadParentHash")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadParentHash")))
          (is (string= (fixture-object-field
                         case "preparedPayloadBlockNumber")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadBlockNumber")))
          (devnet-cli-assert-engine-get-payload-v2 case)
          (is (string= +payload-status-syncing+
                       (fixture-object-field case "remoteBlockStatus")))
          (is (string= (fixture-object-field case "remoteBlockHash")
                       (fixture-object-field
                        case "databaseRemoteBlockHash")))
          (is (string= +payload-status-syncing+
                       (fixture-object-field
                        case "databaseRpcRemoteBlockStatus")))
          (is (string= +payload-status-invalid+
                       (fixture-object-field case "invalidTipsetStatus")))
          (is (string= "Timestamp is not greater than parent timestamp"
                       (fixture-object-field
                        case "invalidTipsetValidationError")))
          (is (string= (fixture-object-field case "invalidTipsetBlockHash")
                       (fixture-object-field
                        case "databaseInvalidTipsetBlockHash")))
          (is (string= +payload-status-invalid+
                       (fixture-object-field
                        case "databaseRpcInvalidTipsetStatus")))
          (is (string= "links to previously rejected block"
                       (fixture-object-field
                        case
                        "databaseRpcInvalidTipsetValidationError")))
          (devnet-cli-assert-txpool-subpool-persistence case)
          (devnet-cli-assert-side-reorg-persistence case)))))))

(deftest phase-a-smoke-gate-devnet-mode-is-cwd-independent
  #-sbcl
  (skip-test "Phase A smoke gate cwd-independent devnet mode requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/phase-a-smoke-gate.lisp")))
        (root (namestring
               (truename "tests/fixtures/execution-spec-tests-root/"))))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               script
               "--"
               "--json"
               "--devnet"
               "--root"
               root)
         :directory #P"/private/tmp/"
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly")))
          (is (string= "ok" (fixture-object-field report "status")))
          (phase-a-smoke-gate-assert-counts report)
          (is (string= "ok" (fixture-object-field devnet "status")))
          (is (string= "devnet-listener-boundary-suite"
                       (fixture-object-field devnet "mode")))
          (is (= 0 (fixture-object-field
                    devnet "sideReorgCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field
                        devnet-side-reorg "mode")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-engine-only "status")))
          (is (string= "devnet-engine-only-serve"
                       (fixture-object-field
                        devnet-engine-only "mode")))
          (is (= 1 (fixture-object-field
                    devnet-engine-only "caseCount")))
          (is (string= "/engine"
                       (fixture-object-field
                        devnet-engine-only "engineRpcPrefix")))
          (is (= 200 (fixture-object-field
                      devnet-engine-only "engineRpcPrefixStatus")))
          (is (= 404 (fixture-object-field
                      devnet-engine-only
                      "engineRpcPrefixBlockedStatus")))
          (devnet-cli-assert-engine-only-http-shaping-report
           devnet-engine-only)
          (devnet-cli-assert-engine-capability-report
           devnet-engine-only)
          (devnet-cli-assert-engine-client-version
           devnet-engine-only)
          (devnet-cli-assert-engine-transition-configuration
           devnet-engine-only)
          (devnet-cli-assert-engine-only-payload-report
           devnet-engine-only)
          (devnet-cli-assert-engine-only-database-report
           devnet-engine-only)
          (is (search "http://127.0.0.1:"
                      (fixture-object-field
                       devnet-engine-only "configuredPublicEndpoint")))
          (is (not (fixture-object-field
                    devnet-engine-only "publicEndpointConnectable")))
          (is (= 7 (fixture-object-field
                    devnet-engine-only "engineConnections")))
          (is (= 0 (fixture-object-field
                    devnet-engine-only "publicConnections"))))))))

(deftest phase-a-smoke-gate-text-output-includes-aggregate-counts
  #-sbcl
  (skip-test "Phase A smoke gate text output test requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "fixtureCaseCount=" stdout))
    (is (search "fixtureExecutedCount=" stdout))
    (is (search "totalCaseCount=" stdout))
    (is (search "totalExecutedCount=" stdout))
    (is (search "blockchainCount=9" stdout))
    (is (search "blockchainExecuted=9" stdout))
    (is (search "(\"engineNewPayloadV2\" . 8)" stdout))
    (is (search "(\"blockRlp\" . 1)" stdout))
    (is (search "fixtureCaseCount=38" stdout))
    (is (search "fixtureExecutedCount=38" stdout))))

(deftest phase-a-smoke-gate-drift-map-fails-on-materializable-gaps
  #-sbcl
  (skip-test "Phase A smoke gate drift map failure requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--drift-map"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Phase A drift map found materializable selector gaps"
                stderr))
    (is (search "implementationBugCandidates=1" stderr))))

(deftest phase-a-smoke-gate-pinned-mode-defaults-to-eest-root-env
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (devnet-cli-temp-directory
            "ethereum-lisp-pinned-smoke-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST blockchain root"
                  stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A smoke gate requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-smoke-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A smoke gate root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest blockchain-replay-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-blockchain-replay-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest blockchain-replay-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-blockchain-replay-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest blockchain-replay-classifier-script-json-filters-passing-results
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest transaction-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-transaction-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest transaction-test-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "phase-a-sample.json"
             "--limit"
             "2"
             "--include-pinned"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest transaction-test-classifier-script-json-classifies-prague-out-of-scope
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "prague/eip7702_set_code_tx/test_empty_authorization_list.json"
             "--limit"
             "1"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families"))
             (result (first results)))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 1 (fixture-object-field report "classifiedCount")))
        (is (= 0 (fixture-object-field report "passingCount")))
        (is (= 1 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 1 (fixture-object-field
                  report
                  "outOfScopeForkFeatureCount")))
        (is (= 1 (length families)))
        (is (string= "out-of-scope-fork-feature"
                     (fixture-object-field result "classification")))
        (is (search "Prague/EIP-7702"
                    (fixture-object-field result "error")))))))

(deftest state-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-state-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest state-test-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-state-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest state-test-classifier-script-json-filters-passing-results
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest classifier-scripts-accept-assigned-options
  #-sbcl
  (skip-test "Fixture classifier scripts require SBCL")
  #+sbcl
  (labels ((run-classifier (script prefix &key include-pinned)
             (let ((args
                     (append
                      (list "sbcl"
                            "--script"
                            script
                            "--"
                            "--root=tests/fixtures/execution-spec-tests-root/"
                            (format nil "--prefix=~A" prefix)
                            "--limit=1"
                            "--json=true"
                            "--failures-only=false")
                      (when include-pinned
                        (list "--include-pinned=true")))))
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    args
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 status))
                 (is (string= "" stderr))
                 (when (= 0 status)
                   (let ((report (parse-json stdout)))
                     (is (= 1 (fixture-object-field report "classifiedCount")))
                     (is (= 1 (fixture-object-field report "candidateCount")))
                     (is (= 1 (fixture-object-field report "passingCount")))
                     (is (= 0 (fixture-object-field report "failingCount")))
                     (is (not (fixture-object-field report "failuresOnly")))
                     (is (string= prefix
                                  (fixture-object-field report "prefix")))
                     report))))))
    (run-classifier
     "scripts/classify-blockchain-replay-selectors.lisp"
     "shanghai/phase-a")
    (let ((transaction-report
            (run-classifier
             "scripts/classify-transaction-test-selectors.lisp"
             "phase-a-sample.json"
             :include-pinned t)))
      (is (eq t (fixture-object-field transaction-report "includePinned"))))
    (run-classifier
     "scripts/classify-state-test-selectors.lisp"
     "london/phase-a")))

(deftest phase-a-drift-map-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-drift-map.lisp"
                stdout))
    (is (search "--suite SUITE" stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--state-prefix PREFIX" stdout))
    (is (search "--transaction-prefix PREFIX" stdout))
    (is (search "--blockchain-prefix PREFIX" stdout))
    (is (search "--state-limit NUMBER" stdout))
    (is (search "--transaction-limit NUMBER" stdout))
    (is (search "--blockchain-limit NUMBER" stdout))
    (is (search "--summary-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "out-of-scope-fork-feature" stdout))))

(deftest phase-a-drift-map-script-json-summarizes-suites
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--limit"
             "1"
             "--failures-only"
             "--summary-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites")))
        (is (string= "phase-a-drift-map"
                     (fixture-object-field report "mode")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (eq t (fixture-object-field report "summaryOnly")))
        (is (= 3 (length suites)))
        (is (= 3 (fixture-object-field overall "suiteCount")))
        (is (= 3 (fixture-object-field overall "candidateCount")))
        (is (= 3 (fixture-object-field overall "classifiedCount")))
        (is (= 0
               (fixture-object-field
                overall
                "knownImplementationDriftCount")))
        (is (= 0
               (fixture-object-field
                overall
                "fixtureHarnessErrorCount")))
        (is (eq t (fixture-object-field
                   overall
                   "phaseAMaterializableClear")))
        (dolist (suite suites)
          (is (member (fixture-object-field suite "suite")
                      '("state" "transaction" "blockchain")
                      :test #'string=))
          (is (string= "" (fixture-object-field suite "prefix")))
          (is (= 1 (fixture-object-field suite "candidateCount")))
          (is (= 1 (fixture-object-field suite "classifiedCount")))
          (is (= 0 (fixture-object-field
                    suite
                    "knownImplementationDriftCount")))
          (is (fixture-object-field suite "families"))
          (is (null (fixture-object-field suite "results"))))
        (let* ((transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-family
                 (first (fixture-object-field transaction-suite "families"))))
          (is (= 1
                 (fixture-object-field transaction-family
                                       "outOfScopeForkFeatureCount")))
          (is (null (fixture-object-field transaction-family
                                          "outOfScopeCount"))))))))

(deftest phase-a-drift-map-script-json-filters-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--suite"
             "transaction"
             "--limit"
             "1"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites"))
             (suite (first suites)))
        (is (string= "transaction" (fixture-object-field report "suite")))
        (is (= 1 (length suites)))
        (is (= 1 (fixture-object-field overall "suiteCount")))
        (is (= 1 (fixture-object-field overall "candidateCount")))
        (is (= 1 (fixture-object-field overall "classifiedCount")))
        (is (string= "transaction"
                     (fixture-object-field suite "suite")))
        (is (= 1 (fixture-object-field suite "candidateCount")))
        (is (= 1 (fixture-object-field suite "classifiedCount")))))))

(deftest phase-a-drift-map-script-accepts-assigned-options
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (let ((root "tests/fixtures/execution-spec-tests-root/"))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-drift-map.lisp"
               "--"
               (format nil "--root=~A" root)
               "--limit=1"
               "--state-prefix=london/phase-a-state-sample.json/phase_a_london_access_list"
               "--transaction-prefix=prague/eip7702_set_code_tx/test_empty_authorization_list"
               "--blockchain-prefix=shanghai/phase-a-empty-engine"
               "--failures-only=true"
               "--summary-only=true"
               "--json=1")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (overall (fixture-object-field report "overall"))
               (suites (fixture-object-field report "suites"))
               (state-suite
                 (find "state" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (blockchain-suite
                 (find "blockchain" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=)))
          (is (string= "phase-a-drift-map"
                       (fixture-object-field report "mode")))
          (is (string= root (fixture-object-field report "root")))
          (is (eq t (fixture-object-field report "failuresOnly")))
          (is (eq t (fixture-object-field report "summaryOnly")))
          (is (string= "london/phase-a-state-sample.json/phase_a_london_access_list"
                       (fixture-object-field state-suite "prefix")))
          (is (string= "prague/eip7702_set_code_tx/test_empty_authorization_list"
                       (fixture-object-field transaction-suite "prefix")))
          (is (string= "shanghai/phase-a-empty-engine"
                       (fixture-object-field blockchain-suite "prefix")))
          (is (= 3 (fixture-object-field overall "classifiedCount"))))))))

(deftest phase-a-drift-map-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

(deftest phase-a-drift-map-script-rejects-unknown-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--suite=receipts"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--suite requires state, transaction, or blockchain" stderr))))

(deftest ethereum-lisp-script-dispatches-devnet-help
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/ethereum-lisp.lisp"
             "--"
             "devnet"
             "--help")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: ethereum-lisp devnet" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--authrpc.jwtsecret PATH" stdout))
    (is (search "--http.port PORT" stdout))
    (is (search "--http.api LIST" stdout))
    (is (search "--datadir PATH" stdout))
    (is (search "--networkid ID" stdout))
    (is (search "--mainnet" stdout))
    (is (search "--sepolia" stdout))
    (is (search "--holesky" stdout))
    (is (search "--hoodi" stdout))
    (is (search "--syncmode MODE" stdout))
    (is (search "--ws.api LIST" stdout))
    (is (search "--ws.origins ORIGINS" stdout))
    (is (search "--ws.rpcprefix PATH" stdout))
    (is (search "--graphql" stdout))
    (is (search "--graphql.addr HOST" stdout))
    (is (search "--graphql.port PORT" stdout))
    (is (search "--nodiscover" stdout))
    (is (search "--ipcdisable" stdout))
    (is (search "--ipcapi LIST" stdout))
    (is (search "--verbosity LEVEL" stdout))
    (is (search "--log.file PATH" stdout))
    (is (search "--log.compress" stdout))
    (is (search "--maxpeers N" stdout))
    (is (search "--nat MODE" stdout))
    (is (search "--identity NAME" stdout))
    (is (search "--gcmode MODE" stdout))
    (is (search "--mine" stdout))
    (is (search "--miner.etherbase ADDRESS" stdout))
    (is (search "--metrics" stdout))
    (is (search "--pprof" stdout))
    (is (search "--snapshot" stdout))
    (is (search "--override.terminaltotaldifficulty TTD" stdout))
    (is (search "--override.terminaltotaldifficultypassed" stdout))
    (is (search "--override.terminalblockhash HASH" stdout))
    (is (search "--override.terminalblocknumber NUMBER" stdout))
    (is (search "--allow-insecure-unlock" stdout))
    (is (search "--http.maxclients N" stdout))
    (is (search "--http.readtimeout DURATION" stdout))
    (is (search "--http.writetimeout DURATION" stdout))
    (is (search "--http.idletimeout DURATION" stdout))
    (is (search "--kzg.verifier-command PATH" stdout))
    (is (search "--kzg.verifier-timeout SECONDS" stdout))
    (is (search "--authrpc.vhosts HOSTS" stdout))))

(deftest ethereum-lisp-script-dispatches-top-level-help-and-version
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp"))))
    (labels ((run-script (&rest args)
               (uiop:run-program
                (append (list "sbcl" "--script" script "--") args)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)))
      (multiple-value-bind (stdout stderr status)
          (run-script)
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp COMMAND" stdout))
        (is (search "init" stdout))
        (is (search "devnet" stdout))
        (is (search "version" stdout))
        (is (search "ethereum-lisp init --help" stdout))
        (is (search "ethereum-lisp devnet --help" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "--help")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp COMMAND" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "init" "--help")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp init" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "version")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (string= "ethereum-lisp/0.1.0/0x00000000"
                     (string-trim '(#\Newline #\Return) stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-script "--version")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (string= "ethereum-lisp/0.1.0/0x00000000"
                     (string-trim '(#\Newline #\Return) stdout)))))))

(deftest ethereum-lisp-script-dispatches-init-datadir-and-devnet-json
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory "ethereum-lisp-script-init-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-script-init-datadir-jwt"
                                 "hex"))
         (config-path
           (merge-pathnames "geth.toml" datadir))
         (ready-path
           (merge-pathnames "runner/ready.json" datadir))
         (log-path
           (merge-pathnames "runner/devnet.log" datadir))
         (pid-path
           (merge-pathnames "runner/devnet.pid" datadir)))
    (labels ((run-script (&rest args)
               (uiop:run-program
                (append (list "sbcl" "--script" script "--") args)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)))
      (unwind-protect
           (progn
             (devnet-cli-write-temp-file explicit-jwt-path
                                         +devnet-cli-jwt-secret+)
             (devnet-cli-write-temp-file config-path
                                         (format nil
                                                 "[Eth]~%NetworkId = 7331~%~
                                                  [Node]~%DataDir = ~S~%~
                                                  JWTSecret = ~S~%"
                                                 (namestring datadir)
                                                 (namestring
                                                  explicit-jwt-path)))
             (multiple-value-bind (stdout stderr status)
                 (run-script "--config" (namestring config-path)
                             "--cache" "128"
                             "--cache.database=64"
                             "--gcmode" "archive"
                             "--state.scheme=hash"
                             "--db.engine=pebble"
                             "--snapshot=false"
                             "--networkid" "7331"
                             "--sepolia=false"
                             "--holesky=false"
                             "--authrpc.addr=127.0.0.1"
                             "--authrpc.port" "0"
                             "--authrpc.rpcprefix=/engine"
                             "--authrpc.vhosts" "engine.runner,localhost"
                             "--authrpc.corsdomain" "https://engine.example"
                             "--http"
                             "--http.addr=127.0.0.1"
                             "--http.port" "0"
                             "--http.rpcprefix=/rpc"
                             "--http.api" "eth,net"
                             "--http.vhosts" "public.runner,localhost"
                             "--http.corsdomain" "https://public.example"
                             "--ws"
                             "--ws.addr=127.0.0.1"
                             "--ws.port" "0"
                             "--ws.rpcprefix=/ws"
                             "--ipcapi=eth,net,web3"
                             "--graphql=false"
                             "--override.terminaltotaldifficulty" "0"
                             "--override.terminaltotaldifficultypassed=false"
                             "--override.terminalblockhash=0x0000000000000000000000000000000000000000000000000000000000000000"
                             "--override.terminalblocknumber" "0"
                             "--ready-file" (namestring ready-path)
                             "--log-file" (namestring log-path)
                             "--pid-file" (namestring pid-path)
                             "--max-connections" "0"
                             "--prune-state-before" "0"
                             "--no-serve"
                             "init"
                             "--json"
                             genesis)
               (is (= 0 status))
               (is (string= "" stderr))
               (let* ((summary (parse-json stdout))
                      (ready-summary
                        (parse-json (devnet-cli-file-string ready-path)))
                      (pid (devnet-cli-pid-file-process-id pid-path))
                      (log-records (devnet-cli-file-forms log-path))
                      (ready-record (first log-records))
                      (shutdown-record (second log-records))
                      (ready-fields (getf ready-record :fields))
                      (shutdown-fields (getf shutdown-record :fields)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field summary "authRequired")))
                 (is (probe-file ready-path))
                 (is (probe-file log-path))
                 (is (probe-file pid-path))
                 (is (= 2 (length log-records)))
                 (is (= pid (fixture-object-field summary "processId")))
                 (is (= pid (fixture-object-field ready-summary
                                                  "processId")))
                 (is (string= genesis
                              (fixture-object-field summary "genesisPath")))
                 (is (string= genesis
                              (fixture-object-field ready-summary
                                                    "genesisPath")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field ready-summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field ready-summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field ready-summary
                                                  "authRequired")))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring log-path)
                              (fixture-object-field ready-summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary
                                                    "pidFilePath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field ready-summary
                                                    "pidFilePath")))
                 (is (eq :log (getf ready-record :kind)))
                 (is (eq :info (getf ready-record :value)))
                 (is (string= "init.ready" (getf ready-record :name)))
                 (is (string= "ready"
                              (cdr (assoc "lifecyclePhase"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (write-to-string pid)
                              (cdr (assoc "processId"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring log-path)
                              (cdr (assoc "logPath"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring pid-path)
                              (cdr (assoc "pidFilePath"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring datadir-database-path)
                              (cdr (assoc "databasePath"
                                          ready-fields
                                          :test #'string=))))
                 (is (eq :log (getf shutdown-record :kind)))
                 (is (eq :info (getf shutdown-record :value)))
                 (is (string= "init.shutdown"
                              (getf shutdown-record :name)))
                 (is (string= "shutdown"
                              (cdr (assoc "lifecyclePhase"
                                          shutdown-fields
                                          :test #'string=))))
                 (is (string= (write-to-string pid)
                             (cdr (assoc "processId"
                                          shutdown-fields
                                          :test #'string=))))))
             (is (probe-file datadir-genesis-path))
             (is (probe-file datadir-database-path))
             (is (probe-file datadir-jwt-path))
             (is (string= +devnet-cli-jwt-secret+
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (devnet-cli-file-string datadir-jwt-path))))
             (multiple-value-bind (stdout stderr status)
                 (run-script "--identity" "init"
                             "--config" (namestring config-path)
                             "--hoodi=false"
                             "devnet"
                             "--json"
                             "--no-serve")
               (is (= 0 status))
               (is (string= "" stderr))
               (let ((summary (parse-json stdout)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (string= (namestring (truename datadir-genesis-path))
                              (fixture-object-field summary "genesisPath")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath"))))))
        (when (probe-file datadir-genesis-path)
          (delete-file datadir-genesis-path))
        (when (probe-file datadir-database-path)
          (delete-file datadir-database-path))
        (when (probe-file datadir-jwt-path)
          (delete-file datadir-jwt-path))
        (when (probe-file explicit-jwt-path)
          (delete-file explicit-jwt-path))
        (when (probe-file config-path)
          (delete-file config-path))
        (when (probe-file ready-path)
          (delete-file ready-path))
        (when (probe-file log-path)
          (delete-file log-path))
        (when (probe-file pid-path)
          (delete-file pid-path))))))

(deftest ethereum-lisp-script-dispatches-devnet-no-serve-json
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/ethereum-lisp.lisp"
             "--"
             "devnet"
             "--genesis"
             +devnet-cli-genesis-fixture+
             "--json"
             "--no-serve")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let ((summary (parse-json stdout)))
        (is (string= +devnet-cli-genesis-fixture+
                     (fixture-object-field summary "genesisPath")))
        (is (string= "127.0.0.1:8551"
                     (fixture-object-field summary "engineEndpoint")))
        (is (string= "127.0.0.1:8545"
                     (fixture-object-field summary "rpcEndpoint")))
        (is (eq nil (fixture-object-field summary "authRequired")))
        (is (eq t (fixture-object-field summary "stateAvailable")))))))

(deftest ethereum-lisp-script-serve-mode-boots-initialized-datadir
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory "ethereum-lisp-script-serve-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-serve-datadir-explicit-jwt"
            "hex"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir-ready"
                                 "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      genesis)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field summary
                                                  "authRequired"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (is (string= +devnet-cli-jwt-secret+
                        (string-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (devnet-cli-file-string datadir-jwt-path))))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "devnet"
                        "--json"
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "2")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":701,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"datadir-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":702,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":703,\"method\":\"net_version\",\"params\":[]}")
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    engine-unauthenticated-response
                    engine-response
                    public-response
                    public-net-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (handler-case
                   (progn
                     (setf engine-unauthenticated-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request engine-body)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request public-body)))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                             (devnet-cli-json-rpc-http-request
                              public-net-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status engine-unauthenticated-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 701 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 702 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 703 (fixture-object-field public-net-json "id")))
                 (is (string= "1337"
                              (fixture-object-field public-net-json
                                                    "result"))))
               (let ((status (devnet-cli-wait-process-exit process 30)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= (namestring
                                     (truename datadir-genesis-path))
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= (namestring datadir-database-path)
                                    (fixture-object-field stdout-summary
                                                          "databasePath")))
                       (is (eq t (fixture-object-field stdout-summary
                                                       "authRequired")))
                       (is (string= (namestring datadir-jwt-path)
                                    (fixture-object-field stdout-summary
                                                          "jwtSecretPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (is shutdown-record)
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-boots-initialized-datadir
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-explicit-jwt"
            "hex"))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 713)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 714)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x0")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 715)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x1")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-ready" "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      genesis)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "--json"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "6")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":711,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"no-command-datadir\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":712,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":716,\"method\":\"net_version\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":717,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":718,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-syncing-body
                      "{\"jsonrpc\":\"2.0\",\"id\":719,\"method\":\"eth_syncing\",\"params\":[]}")
                    (public-engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":720,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    engine-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    public-response
                    public-net-version-response
                    public-client-version-response
                    public-rpc-modules-response
                    public-syncing-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :token token)))
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :target "/engine"
                             :token token)))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :target "/engine"
                             :token token)))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :target "/engine"
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-body
                             :target "/rpc")))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body
                             :target "/rpc")))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body
                             :target "/rpc")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc")))
                     (setf public-syncing-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-syncing-body
                             :target "/rpc")))
                     (setf public-engine-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-engine-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (dolist (response
                        (list capabilities-response
                              transition-configuration-response
                              transition-configuration-mismatch-response
                              public-response
                              public-net-version-response
                              public-client-version-response
                              public-rpc-modules-response
                              public-syncing-response
                              public-engine-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 711 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 712 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error"))
                      (public-net-version-rpc
                        (parse-json
                         (devnet-cli-http-body public-net-version-response)))
                      (public-client-version-rpc
                        (parse-json
                         (devnet-cli-http-body
                          public-client-version-response)))
                      (public-rpc-modules-rpc
                        (parse-json
                         (devnet-cli-http-body public-rpc-modules-response)))
                      (public-syncing-rpc
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-engine-rpc
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (public-engine-error
                        (fixture-object-field public-engine-rpc "error")))
                 (is (= 713 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 714
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= (hash32-to-hex (zero-hash32))
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 715
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message")))
                 (is (= 716
                        (fixture-object-field public-net-version-rpc "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-net-version-rpc "result")))
                 (is (= 717
                        (fixture-object-field
                         public-client-version-rpc "id")))
                 (is (search "ethereum-lisp/"
                             (fixture-object-field
                              public-client-version-rpc "result")))
                 (is (= 718
                        (fixture-object-field public-rpc-modules-rpc "id")))
                 (is (fixture-object-field
                      (fixture-object-field
                       public-rpc-modules-rpc "result")
                      "eth"))
                 (is (= 719
                        (fixture-object-field public-syncing-rpc "id")))
                 (is (not (fixture-object-field public-syncing-rpc
                                                "result")))
                 (is (= 720
                        (fixture-object-field public-engine-rpc "id")))
                 (is (= -32601
                        (fixture-object-field public-engine-error "code"))))
               (let ((status (devnet-cli-wait-process-exit process 30)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (is (string= (namestring datadir-database-path)
                                    (fixture-object-field stdout-summary
                                                          "databasePath")))
                       (is (eq t (fixture-object-field stdout-summary
                                                       "authRequired")))
                       (is shutdown-record)
                       (is (string= "6"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "6"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "12"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-datadir-imports-payload
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (case
           (select-engine-newpayload-v2-fixture-case
            +engine-newpayload-v2-fixture-path+
            "shanghai-one-transfer-with-withdrawal"))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
         (child-block (devnet-cli-engine-fixture-child-block case))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (payload-case (fixture-object-field case "payload"))
         (expect (fixture-object-field case "expect"))
         (recipient (fixture-address-field expect "recipient"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (init-genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-genesis"
            "json"))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-import"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-explicit-jwt"
            "hex"))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import" "pid"))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 731 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             732
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (block-number-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 733)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 734 recipient)))
         (public-syncing-body
           "{\"jsonrpc\":\"2.0\",\"id\":735,\"method\":\"eth_syncing\",\"params\":[]}")
         (public-engine-body
           "{\"jsonrpc\":\"2.0\",\"id\":736,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            init-genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      (namestring init-genesis-path))
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "--json"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "4")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    public-syncing-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :target "/engine"
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body
                             :target "/rpc")))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body
                             :target "/rpc")))
                     (setf public-syncing-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-syncing-body
                             :target "/rpc")))
                     (setf public-engine-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-engine-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (dolist (response (list new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       public-syncing-response
                                       public-engine-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (public-syncing-rpc
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-engine-rpc
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (public-engine-error
                        (fixture-object-field public-engine-rpc "error")))
                 (is (= 731 (fixture-object-field new-payload-rpc "id")))
                 (is (= 732 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 733 (fixture-object-field block-number-rpc "id")))
                 (is (= 734 (fixture-object-field balance-rpc "id")))
                 (is (= 735 (fixture-object-field public-syncing-rpc "id")))
                 (is (= 736 (fixture-object-field public-engine-rpc "id")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc "result")))
                 (is (not (fixture-object-field public-syncing-rpc
                                                "result")))
                 (is (= -32601
                        (fixture-object-field public-engine-error "code"))))
               (let ((status (devnet-cli-wait-process-exit process 30)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= engine-endpoint
                                      (fixture-object-field summary
                                                            "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field summary
                                                            "rpcEndpoint")))
                         (is (string= (namestring datadir-database-path)
                                      (fixture-object-field summary
                                                            "databasePath"))))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "8"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (probe-file datadir-database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--datadir"
                                  (namestring datadir)
                                  "--authrpc.rpcprefix"
                                  "/engine"
                                  "--http"
                                  "--http.rpcprefix"
                                  "/rpc"
                                  "--no-serve"
                                  "--json")
                            :directory #P"/private/tmp/"
                            :output :string
                            :error-output :string
                            :ignore-error-status t)
                         (is (= 0 restore-status))
                         (is (string= "" restore-stderr))
                         (when (= 0 restore-status)
                           (let ((restore-summary
                                   (parse-json restore-stdout)))
                             (is (string= (namestring datadir-database-path)
                                          (fixture-object-field
                                           restore-summary
                                           "databasePath")))
                             (is (= (fixture-quantity-field
                                     payload-case "number")
                                    (fixture-object-field
                                     restore-summary "headNumber")))
                             (is (string= block-hash-hex
                                          (fixture-object-field
                                           restore-summary "headHash")))
                             (is (fixture-object-field
                                  restore-summary "stateAvailable"))
                             (is (fixture-object-field
                                  restore-summary "publicRpcEnabled"))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))
                             (is (string= "/rpc"
                                          (fixture-object-field
                                           restore-summary
                                           "publicRpcPrefix")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list init-genesis-path
                          datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-datadir-engine-only-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-engine-only"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-explicit-jwt"
            "hex"))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 714)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 715)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x0")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 716)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x1")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (public-port nil)
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      genesis)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "--json"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "7")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":713,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"no-command-datadir-engine-only\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    blocked-engine-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 713 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 714 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 715
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= (hash32-to-hex (zero-hash32))
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 716
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
               (let ((status (devnet-cli-wait-process-exit process 30)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary
                                                      "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field summary
                                                            "engineEndpoint")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= (namestring datadir-database-path)
                                      (fixture-object-field summary
                                                            "databasePath")))
                         (is (eq t (fixture-object-field summary
                                                          "authRequired")))
                         (is (string= "/engine"
                                      (fixture-object-field summary
                                                            "engineRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= ""
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "false"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-datadir-engine-only-imports-payload
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (case
           (select-engine-newpayload-v2-fixture-case
            +engine-newpayload-v2-fixture-path+
            "shanghai-one-transfer-with-withdrawal"))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
         (child-block (devnet-cli-engine-fixture-child-block case))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (payload-case (fixture-object-field case "payload"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (init-genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-genesis"
            "json"))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-engine-only-import"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-explicit-jwt"
            "hex"))
         (public-port nil)
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import" "pid"))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 741 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             742
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            init-genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      (namestring init-genesis-path))
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "--json"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "4")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    new-payload-response
                    forkchoice-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :target "/engine"
                             :token token))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 741 (fixture-object-field new-payload-rpc "id")))
                 (is (= 742 (fixture-object-field forkchoice-rpc "id")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
               (let ((status (devnet-cli-wait-process-exit process 30)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= engine-endpoint
                                      (fixture-object-field summary
                                                            "engineEndpoint")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= (namestring datadir-database-path)
                                      (fixture-object-field summary
                                                            "databasePath"))))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (probe-file datadir-database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--datadir"
                                  (namestring datadir)
                                  "--authrpc.rpcprefix"
                                  "/engine"
                                  "--http=false"
                                  "--no-serve"
                                  "--json")
                            :directory #P"/private/tmp/"
                            :output :string
                            :error-output :string
                            :ignore-error-status t)
                         (is (= 0 restore-status))
                         (is (string= "" restore-stderr))
                         (when (= 0 restore-status)
                           (let ((restore-summary
                                   (parse-json restore-stdout)))
                             (is (string= (namestring datadir-database-path)
                                          (fixture-object-field
                                           restore-summary
                                           "databasePath")))
                             (is (= (fixture-quantity-field
                                     payload-case "number")
                                    (fixture-object-field
                                     restore-summary "headNumber")))
                             (is (string= block-hash-hex
                                          (fixture-object-field
                                           restore-summary "headHash")))
                             (is (fixture-object-field
                                  restore-summary "stateAvailable"))
                             (is (not (fixture-object-field
                                       restore-summary
                                       "publicRpcEnabled")))
                             (is (not (fixture-object-field
                                       restore-summary
                                       "rpcEndpoint")))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list init-genesis-path
                          datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-is-cwd-independent-for-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    script
                    "--"
                    "devnet"
                    "--genesis"
                    genesis
                    "--engine-port"
                    "0"
                    "--public-port"
                    "8546"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--json"
                    "--no-serve")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= genesis
                              (fixture-object-field summary "genesisPath")))
                 (is (= pid (fixture-object-field summary "processId")))
                 (is (string= "127.0.0.1:0"
                              (fixture-object-field summary
                                                    "engineEndpoint")))
                 (is (string= "127.0.0.1:8546"
                              (fixture-object-field summary "rpcEndpoint")))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (let ((fields (getf log-record :fields)))
                   (is (string= "127.0.0.1:0"
                                (cdr (assoc "engineEndpoint" fields
                                            :test #'string=))))
                   (is (string= "127.0.0.1:8546"
                                (cdr (assoc "rpcEndpoint" fields
                                            :test #'string=))))
                   (is (string= (if (string= "devnet.ready"
                                              (getf log-record :name))
                                     "ready"
                                     "shutdown")
                                (cdr (assoc "lifecyclePhase" fields
                                            :test #'string=))))
                   (is (string= (write-to-string pid)
                                (cdr (assoc "processId" fields
                                            :test #'string=))))
                   (is (string= (namestring log-path)
                                (cdr (assoc "logPath" fields
                                            :test #'string=))))
                   (is (string= (namestring pid-path)
                                (cdr (assoc "pidFilePath" fields
                                            :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-writes-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    script
                    "--"
                    "devnet"
                    "--genesis"
                    genesis
                    "--engine-port"
                    "0"
                    "--public-port"
                    "0"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--max-connections"
                    "0"
                    "--json")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (and (not (= 0 status))
                      (search "Operation not permitted" stderr))
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records))
                    (engine-endpoint
                      (fixture-object-field stdout-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field stdout-summary "rpcEndpoint")))
               (is (string= genesis
                            (fixture-object-field stdout-summary
                                                  "genesisPath")))
               (is (= pid (fixture-object-field stdout-summary "processId")))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= engine-endpoint
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= rpc-endpoint
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (not (string= "127.0.0.1:0" engine-endpoint)))
               (is (not (string= "127.0.0.1:0" rpc-endpoint)))
               (is (search "127.0.0.1:" engine-endpoint))
               (is (search "127.0.0.1:" rpc-endpoint))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let ((fields (getf log-record :fields)))
                     (is (string= engine-endpoint
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= rpc-endpoint
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (if (string= "devnet.ready"
                                                (getf log-record :name))
                                       "ready"
                                       "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "engineConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "publicConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "totalConnections" fields
                                              :test #'string=))))
                     (is (string= (write-to-string pid)
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(defun devnet-cli-wait-for-file (path timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        when (probe-file path)
          return t
        do (sleep 0.05)
        finally (return nil)))

(defun devnet-cli-wait-process-exit (process timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        unless (uiop:process-alive-p process)
          return (uiop:wait-process process)
        do (sleep 0.05)
        finally (return :timeout)))

(deftest ethereum-lisp-script-serve-mode-serves-engine-and-public-rpc
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "jwt"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "0.0.0.0"
                        "--engine-port"
                        "0"
                        "--http.addr"
                        "0.0.0.0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "24"
                        "--override.terminaltotaldifficulty"
                        "12345"
                        "--override.terminaltotaldifficultypassed"
                        "true"
                        "--override.terminalblockhash"
                        "0x3333333333333333333333333333333333333333333333333333333333333333"
                        "--override.terminalblocknumber"
                        "66"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":501,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"rpc-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (engine-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"id\":513,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"rpc-batch-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]},{\"jsonrpc\":\"2.0\",\"id\":514,\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\",\"engine_forkchoiceUpdatedV1\",\"engine_getPayloadV1\",\"engine_newPayloadV2\",\"engine_forkchoiceUpdatedV2\",\"engine_getPayloadV2\",\"engine_getPayloadBodiesByHashV1\",\"engine_getPayloadBodiesByRangeV1\",\"engine_newPayloadV3\",\"engine_getBlobsV1\",\"engine_getPayloadBodiesByHashV2\"]]}]")
                    (engine-notification-body
                      "{\"jsonrpc\":\"2.0\",\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (engine-transition-body
                      "{\"jsonrpc\":\"2.0\",\"id\":515,\"method\":\"engine_exchangeTransitionConfigurationV1\",\"params\":[{\"terminalTotalDifficulty\":\"0x3039\",\"terminalBlockHash\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"terminalBlockNumber\":\"0x42\"}]}")
                    (engine-transition-mismatch-body
                      "{\"jsonrpc\":\"2.0\",\"id\":530,\"method\":\"engine_exchangeTransitionConfigurationV1\",\"params\":[{\"terminalTotalDifficulty\":\"0x3038\",\"terminalBlockHash\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"terminalBlockNumber\":\"0x42\"}]}")
                    (engine-public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":507,\"method\":\"eth_chainId\",\"params\":[]}")
                    (engine-capabilities-body
                      "{\"jsonrpc\":\"2.0\",\"id\":508,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (engine-wrong-path-body
                      "{\"jsonrpc\":\"2.0\",\"id\":531,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"wrong-path\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":502,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":503,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":504,\"method\":\"net_version\",\"params\":[]}")
                    (public-net-listening-body
                      "{\"jsonrpc\":\"2.0\",\"id\":505,\"method\":\"net_listening\",\"params\":[]}")
                    (public-syncing-body
                      "{\"jsonrpc\":\"2.0\",\"id\":506,\"method\":\"eth_syncing\",\"params\":[]}")
                    (public-net-peer-count-body
                      "{\"jsonrpc\":\"2.0\",\"id\":516,\"method\":\"net_peerCount\",\"params\":[]}")
                    (public-accounts-body
                      "{\"jsonrpc\":\"2.0\",\"id\":517,\"method\":\"eth_accounts\",\"params\":[]}")
                    (public-coinbase-body
                      "{\"jsonrpc\":\"2.0\",\"id\":518,\"method\":\"eth_coinbase\",\"params\":[]}")
                    (public-mining-body
                      "{\"jsonrpc\":\"2.0\",\"id\":519,\"method\":\"eth_mining\",\"params\":[]}")
                    (public-hashrate-body
                      "{\"jsonrpc\":\"2.0\",\"id\":520,\"method\":\"eth_hashrate\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":521,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-protocol-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":522,\"method\":\"eth_protocolVersion\",\"params\":[]}")
                    (public-web3-sha3-body
                      "{\"jsonrpc\":\"2.0\",\"id\":523,\"method\":\"web3_sha3\",\"params\":[\"0x68656c6c6f\"]}")
                    (public-gas-price-body
                      "{\"jsonrpc\":\"2.0\",\"id\":524,\"method\":\"eth_gasPrice\",\"params\":[]}")
                    (public-priority-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":525,\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]}")
                    (public-base-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":526,\"method\":\"eth_baseFee\",\"params\":[]}")
                    (public-blob-base-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":527,\"method\":\"eth_blobBaseFee\",\"params\":[]}")
                    (public-fee-history-body
                      "{\"jsonrpc\":\"2.0\",\"id\":528,\"method\":\"eth_feeHistory\",\"params\":[\"0x1\",\"latest\",[]]}")
                    (public-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"id\":510,\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":511,\"method\":\"net_version\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":512,\"method\":\"web3_clientVersion\",\"params\":[]}]")
                    (public-notification-body
                      "{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-mixed-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":529,\"method\":\"net_version\",\"params\":[]}]")
                    (public-notifications-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[]}]")
                    (public-wrong-path-body
                      "{\"jsonrpc\":\"2.0\",\"id\":532,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":509,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    engine-response
                    engine-batch-response
                    engine-notification-response
                    engine-transition-response
                    engine-transition-mismatch-response
                    engine-public-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    duplicate-auth-engine-response
                    engine-wrong-path-response
                    public-response
                    public-client-version-response
                    public-net-version-response
                    public-net-listening-response
                    public-syncing-response
                    public-net-peer-count-response
                    public-accounts-response
                    public-coinbase-response
                    public-mining-response
                    public-hashrate-response
                    public-rpc-modules-response
                    public-protocol-version-response
                    public-web3-sha3-response
                    public-gas-price-response
                    public-priority-fee-response
                    public-base-fee-response
                    public-blob-base-fee-response
                    public-fee-history-response
                    public-batch-response
                    public-notification-response
                    public-mixed-batch-response
                    public-notifications-batch-response
                    public-wrong-path-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (search "127.0.0.1:" engine-endpoint))
               (is (not (search "0.0.0.0" engine-endpoint)))
               (is (search "127.0.0.1:" rpc-endpoint))
               (is (not (search "0.0.0.0" rpc-endpoint)))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf engine-batch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-batch-body
                             :token token)))
                     (setf engine-notification-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-notification-body
                             :token token)))
                     (setf engine-transition-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-transition-body
                             :token token)))
                     (setf engine-transition-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-transition-mismatch-body
                             :token token)))
                     (setf engine-public-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-public-body
                             :token token)))
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-capabilities-body)))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-capabilities-body
                             :token wrong-token)))
                     (setf duplicate-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-duplicate-auth-http-request
                             engine-capabilities-body
                             token
                             wrong-token)))
                     (setf engine-wrong-path-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-wrong-path-body
                             :target "/unexpected"
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request public-body)))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body)))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body)))
                     (setf public-net-listening-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-listening-body)))
                     (setf public-syncing-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-syncing-body)))
                     (setf public-net-peer-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-peer-count-body)))
                     (setf public-accounts-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-accounts-body)))
                     (setf public-coinbase-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-coinbase-body)))
                     (setf public-mining-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-mining-body)))
                     (setf public-hashrate-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-hashrate-body)))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body)))
                     (setf public-protocol-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-protocol-version-body)))
                     (setf public-web3-sha3-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-web3-sha3-body)))
                     (setf public-gas-price-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-gas-price-body)))
                     (setf public-priority-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-priority-fee-body)))
                     (setf public-base-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-base-fee-body)))
                     (setf public-blob-base-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-blob-base-fee-body)))
                     (setf public-fee-history-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-fee-history-body)))
                     (setf public-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-batch-body)))
                     (setf public-notification-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-notification-body)))
                     (setf public-mixed-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-mixed-batch-body)))
                     (setf public-notifications-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-notifications-batch-body)))
                     (setf public-wrong-path-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-wrong-path-body
                             :target "/unexpected")))
                     (setf public-engine-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-engine-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status engine-batch-response)))
               (is (= 200 (devnet-cli-http-status
                            engine-notification-response)))
               (is (= 200 (devnet-cli-http-status engine-transition-response)))
               (is (= 200 (devnet-cli-http-status
                            engine-transition-mismatch-response)))
               (is (= 200 (devnet-cli-http-status engine-public-response)))
               (is (= 401
                      (devnet-cli-http-status unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 401
                      (devnet-cli-http-status duplicate-auth-engine-response)))
               (is (= 404 (devnet-cli-http-status engine-wrong-path-response)))
               (is (search "not found"
                           (devnet-cli-http-body
                            engine-wrong-path-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-client-version-response)))
               (is (= 200 (devnet-cli-http-status public-net-version-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-net-listening-response)))
               (is (= 200 (devnet-cli-http-status public-syncing-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-net-peer-count-response)))
               (is (= 200 (devnet-cli-http-status public-accounts-response)))
               (is (= 200 (devnet-cli-http-status public-coinbase-response)))
               (is (= 200 (devnet-cli-http-status public-mining-response)))
               (is (= 200 (devnet-cli-http-status public-hashrate-response)))
               (is (= 200
                      (devnet-cli-http-status public-rpc-modules-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-protocol-version-response)))
               (is (= 200
                      (devnet-cli-http-status public-web3-sha3-response)))
               (is (= 200
                      (devnet-cli-http-status public-gas-price-response)))
               (is (= 200
                      (devnet-cli-http-status public-priority-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-base-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-blob-base-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-fee-history-response)))
               (is (= 200 (devnet-cli-http-status public-batch-response)))
               (is (= 200
                      (devnet-cli-http-status public-notification-response)))
               (is (= 200
                      (devnet-cli-http-status public-mixed-batch-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-notifications-batch-response)))
               (is (= 404 (devnet-cli-http-status public-wrong-path-response)))
               (is (search "not found"
                           (devnet-cli-http-body
                            public-wrong-path-response)))
               (is (= 200 (devnet-cli-http-status public-engine-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-public-json
                        (parse-json
                         (devnet-cli-http-body engine-public-response)))
                      (engine-batch-json
                        (parse-json
                         (devnet-cli-http-body engine-batch-response)))
                      (engine-batch-client-version-json
                        (first engine-batch-json))
                      (engine-batch-capabilities-json
                        (second engine-batch-json))
                      (engine-transition-json
                        (parse-json
                         (devnet-cli-http-body engine-transition-response)))
                      (engine-transition-result
                        (fixture-object-field engine-transition-json
                                              "result"))
                      (engine-transition-mismatch-json
                        (parse-json
                         (devnet-cli-http-body
                          engine-transition-mismatch-response)))
                      (engine-transition-mismatch-error
                        (fixture-object-field engine-transition-mismatch-json
                                              "error"))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (public-client-version-json
                        (parse-json
                         (devnet-cli-http-body
                          public-client-version-response)))
                      (public-net-version-json
                        (parse-json
                         (devnet-cli-http-body public-net-version-response)))
                      (public-net-listening-json
                        (parse-json
                         (devnet-cli-http-body
                          public-net-listening-response)))
                      (public-syncing-json
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-net-peer-count-json
                        (parse-json
                         (devnet-cli-http-body
                          public-net-peer-count-response)))
                      (public-accounts-json
                        (parse-json
                         (devnet-cli-http-body public-accounts-response)))
                      (public-coinbase-json
                        (parse-json
                         (devnet-cli-http-body public-coinbase-response)))
                      (public-mining-json
                        (parse-json
                         (devnet-cli-http-body public-mining-response)))
                      (public-hashrate-json
                        (parse-json
                         (devnet-cli-http-body public-hashrate-response)))
                      (public-rpc-modules-json
                        (parse-json
                         (devnet-cli-http-body public-rpc-modules-response)))
                      (public-rpc-modules
                        (fixture-object-field public-rpc-modules-json
                                              "result"))
                      (public-protocol-version-json
                        (parse-json
                         (devnet-cli-http-body
                          public-protocol-version-response)))
                      (public-web3-sha3-json
                        (parse-json
                         (devnet-cli-http-body public-web3-sha3-response)))
                      (public-gas-price-json
                        (parse-json
                         (devnet-cli-http-body public-gas-price-response)))
                      (public-priority-fee-json
                        (parse-json
                         (devnet-cli-http-body public-priority-fee-response)))
                      (public-base-fee-json
                        (parse-json
                         (devnet-cli-http-body public-base-fee-response)))
                      (public-blob-base-fee-json
                        (parse-json
                         (devnet-cli-http-body
                          public-blob-base-fee-response)))
                      (public-fee-history-json
                        (parse-json
                         (devnet-cli-http-body public-fee-history-response)))
                      (public-fee-history
                        (fixture-object-field public-fee-history-json
                                              "result"))
                      (public-batch-json
                        (parse-json
                         (devnet-cli-http-body public-batch-response)))
                      (public-batch-chain-id-json
                        (first public-batch-json))
                      (public-batch-net-version-json
                        (second public-batch-json))
                      (public-batch-client-version-json
                        (third public-batch-json))
                      (public-mixed-batch-json
                        (parse-json
                         (devnet-cli-http-body
                          public-mixed-batch-response)))
                      (public-mixed-batch-net-version-json
                        (first public-mixed-batch-json))
                      (public-engine-json
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 501 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 2 (length engine-batch-json)))
                 (is (= 513
                        (fixture-object-field
                         engine-batch-client-version-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field
                               (first
                                (fixture-object-field
                                 engine-batch-client-version-json "result"))
                               "name")))
                 (is (= 514
                        (fixture-object-field
                         engine-batch-capabilities-json "id")))
                 (devnet-cli-assert-engine-capability-list
                  (fixture-object-field
                   engine-batch-capabilities-json "result"))
                 (is (string= ""
                              (devnet-cli-http-body
                               engine-notification-response)))
                 (is (= 515 (fixture-object-field engine-transition-json "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               engine-transition-result
                               "terminalTotalDifficulty")))
                 (is (string= "0x3333333333333333333333333333333333333333333333333333333333333333"
                              (fixture-object-field
                               engine-transition-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               engine-transition-result
                               "terminalBlockNumber")))
                 (is (= 530
                        (fixture-object-field
                         engine-transition-mismatch-json "id")))
                 (is (= -32602
                        (fixture-object-field
                         engine-transition-mismatch-error "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              engine-transition-mismatch-error "message")))
                 (is (= 507 (fixture-object-field engine-public-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field engine-public-json "error")
                         "code")))
                 (is (= 502 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 503
                        (fixture-object-field public-client-version-json "id")))
                 (is (search "ethereum-lisp"
                             (fixture-object-field
                              public-client-version-json "result")))
                 (is (= 504 (fixture-object-field public-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-net-version-json "result")))
                 (is (= 505
                        (fixture-object-field public-net-listening-json "id")))
                 (is (null (fixture-object-field
                            public-net-listening-json "result")))
                 (is (= 506 (fixture-object-field public-syncing-json "id")))
                 (is (null (fixture-object-field
                            public-syncing-json "result")))
                 (is (= 516
                        (fixture-object-field
                         public-net-peer-count-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-net-peer-count-json "result")))
                 (is (= 517 (fixture-object-field public-accounts-json "id")))
                 (is (null (fixture-object-field
                            public-accounts-json "result")))
                 (is (= 518 (fixture-object-field public-coinbase-json "id")))
                 (is (string= (address-to-hex (zero-address))
                              (fixture-object-field
                               public-coinbase-json "result")))
                 (is (= 519 (fixture-object-field public-mining-json "id")))
                 (is (null (fixture-object-field public-mining-json "result")))
                 (is (= 520 (fixture-object-field public-hashrate-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-hashrate-json "result")))
                 (is (= 521
                        (fixture-object-field public-rpc-modules-json "id")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "eth")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "net")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "rpc")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules
                                                    "txpool")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules
                                                    "web3")))
                 (is (= 522
                        (fixture-object-field
                         public-protocol-version-json "id")))
                 (is (string= (quantity-to-hex
                               ethereum-lisp.core::+eth-protocol-version+)
                              (fixture-object-field
                               public-protocol-version-json "result")))
                 (is (= 523
                        (fixture-object-field public-web3-sha3-json "id")))
                 (is (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                              (fixture-object-field
                               public-web3-sha3-json "result")))
                 (is (= 524
                        (fixture-object-field public-gas-price-json "id")))
                 (is (string= "0x3b9aca00"
                              (fixture-object-field
                               public-gas-price-json "result")))
                 (is (= 525
                        (fixture-object-field public-priority-fee-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-priority-fee-json "result")))
                 (is (= 526
                        (fixture-object-field public-base-fee-json "id")))
                 (is (string= "0x342770c0"
                              (fixture-object-field
                               public-base-fee-json "result")))
                 (is (= 527
                        (fixture-object-field public-blob-base-fee-json "id")))
                 (is (null (fixture-object-field
                            public-blob-base-fee-json "result")))
                 (is (= 528
                        (fixture-object-field public-fee-history-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field public-fee-history
                                                    "oldestBlock")))
                 (let ((base-fees
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas"))
                       (gas-ratios
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                   (is (= 2 (length base-fees)))
                   (is (string= "0x3b9aca00" (first base-fees)))
                   (is (string= "0x342770c0" (second base-fees)))
                   (is (= 1 (length gas-ratios)))
                   (is (= 0 (first gas-ratios))))
                 (is (= 3 (length public-batch-json)))
                 (is (= 510
                        (fixture-object-field
                         public-batch-chain-id-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field
                               public-batch-chain-id-json "result")))
                 (is (= 511
                        (fixture-object-field
                         public-batch-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-batch-net-version-json "result")))
                 (is (= 512
                        (fixture-object-field
                         public-batch-client-version-json "id")))
                 (is (search "ethereum-lisp"
                             (fixture-object-field
                              public-batch-client-version-json "result")))
                 (is (string= ""
                              (devnet-cli-http-body
                               public-notification-response)))
                 (is (= 1 (length public-mixed-batch-json)))
                 (is (= 529
                        (fixture-object-field
                         public-mixed-batch-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-mixed-batch-net-version-json "result")))
                 (is (string= ""
                              (devnet-cli-http-body
                               public-notifications-batch-response)))
                 (is (= 509 (fixture-object-field public-engine-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-engine-json "error")
                         "code"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name)))))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= engine-endpoint
                                        (cdr (assoc "engineEndpoint" fields
                                                    :test #'string=))))
                           (is (string= rpc-endpoint
                                        (cdr (assoc "rpcEndpoint" fields
                                                    :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "10"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "24"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "34"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-admits-public-txpool-transactions
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal")))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-with-txpool-account
              case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (config (ethereum-lisp.cli:devnet-node-config node))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (latest-block-hash-hex
                    (hash32-to-hex (block-hash script-genesis)))
                  (expected-pending-block-number
                    (quantity-to-hex
                     (1+ (block-header-number
                          (block-header script-genesis)))))
                  (sender (devnet-cli-txpool-sender-address))
                  (sender-hex (address-to-hex sender))
                  (pending-transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-gas-price+))
                  (basefee-transaction
                    (devnet-cli-txpool-transaction
                     config 1 +devnet-cli-txpool-basefee-gas-price+))
                  (queued-transaction
                    (devnet-cli-txpool-transaction
                     config 2 +devnet-cli-txpool-gas-price+))
                  (pending-hash
                    (hash32-to-hex (transaction-hash pending-transaction)))
                  (basefee-hash
                    (hash32-to-hex (transaction-hash basefee-transaction)))
                  (queued-hash
                    (hash32-to-hex (transaction-hash queued-transaction)))
                  (pending-raw
                    (devnet-cli-transaction-raw pending-transaction))
                  (basefee-raw
                    (devnet-cli-transaction-raw basefee-transaction))
                  (queued-raw
                    (devnet-cli-transaction-raw queued-transaction))
                  (pending-nonce
                    (devnet-cli-transaction-nonce-key pending-transaction))
                  (expected-pending-sender-nonce
                    (quantity-to-hex
                     (1+ (transaction-nonce pending-transaction))))
                  (basefee-nonce
                    (devnet-cli-transaction-nonce-key basefee-transaction))
                  (queued-nonce
                    (devnet-cli-transaction-nonce-key queued-transaction))
                  (pending-summary
                    (devnet-cli-transaction-summary pending-transaction))
                  (basefee-summary
                    (devnet-cli-transaction-summary basefee-transaction))
                  (queued-summary
                    (devnet-cli-transaction-summary queued-transaction))
                  (send-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 701)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list pending-raw)))))
                  (send-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 702)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list basefee-raw)))))
                  (send-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 703)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list queued-raw)))))
                  (raw-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list pending-hash)))))
                  (raw-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list basefee-hash)))))
                  (raw-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list queued-hash)))))
                  (pending-transactions-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "eth_pendingTransactions")
                           (cons "params" '()))))
                  (new-pending-filter-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 717)
                           (cons "method" "eth_newPendingTransactionFilter")
                           (cons "params" '()))))
                  (pending-block-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 711)
                           (cons "method"
                                 "eth_getBlockTransactionCountByNumber")
                           (cons "params" (list "pending")))))
                  (pending-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 712)
                           (cons "method"
                                 "eth_getTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-raw-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 713)
                           (cons "method"
                                 "eth_getRawTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 714)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "pending" t)))))
                  (pending-header-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 715)
                           (cons "method" "eth_getHeaderByNumber")
                           (cons "params" (list "pending")))))
                  (pending-fee-history-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 722)
                           (cons "method" "eth_feeHistory")
                           (cons "params" (list "0x1" "latest" '())))))
                  (pending-sender-nonce-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 723)
                           (cons "method" "eth_getTransactionCount")
                           (cons "params" (list sender-hex "pending")))))
                  (pending-block-receipts-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 724)
                           (cons "method" "eth_getBlockReceipts")
                           (cons "params" (list "pending")))))
                  (pending-uncle-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 725)
                           (cons "method" "eth_getUncleCountByBlockNumber")
                           (cons "params" (list "pending")))))
                  (pending-logs-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 726)
                           (cons "method" "eth_getLogs")
                           (cons "params"
                                 (list
                                  (list
                                   (cons "fromBlock" "pending")
                                   (cons "toBlock" "pending")))))))
                  (txpool-status-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "txpool_status")
                           (cons "params" '()))))
                  (txpool-content-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 716)
                           (cons "method" "txpool_content")
                           (cons "params" '()))))
                  (txpool-content-from-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 709)
                           (cons "method" "txpool_contentFrom")
                           (cons "params" (list sender-hex)))))
                  (txpool-inspect-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 710)
                           (cons "method" "txpool_inspect")
                           (cons "params" '())))))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--max-connections"
                          "26"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file ready-path 10)
               (when (uiop:process-alive-p process)
                 (uiop:terminate-process process)
                 (devnet-cli-wait-process-exit process 5))
               (let ((stdout
                       (devnet-cli-read-stream-string
                        (uiop:process-info-output process)))
                     (stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (when (search "Operation not permitted" stderr)
                   (skip-test
                    "Local socket bind is not permitted in this sandbox"))
                 (is (probe-file ready-path))
                 (is (string= "" stdout))
                 (is (string= "" stderr))))
             (when (probe-file ready-path)
               (let* ((ready-summary
                        (parse-json (devnet-cli-file-string ready-path)))
                      (pid (devnet-cli-pid-file-process-id pid-path))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      send-pending-response
                      send-basefee-response
                      send-queued-response
                      raw-pending-response
                      raw-basefee-response
                      raw-queued-response
                      new-pending-filter-response
                      pending-filter-changes-response
                      empty-pending-filter-changes-response
                      uninstall-pending-filter-response
                      removed-pending-filter-changes-response
                      pending-transactions-response
                      pending-block-count-response
                      pending-transaction-by-index-response
                      pending-raw-transaction-by-index-response
                      pending-block-response
                      pending-header-response
                      pending-fee-history-response
                      pending-sender-nonce-response
                      pending-block-receipts-response
                      pending-uncle-count-response
                      pending-logs-response
                      txpool-status-response
                      txpool-content-response
                      txpool-content-from-response
                      txpool-inspect-response)
                 (is (= pid (fixture-object-field ready-summary "processId")))
                 (handler-case
                     (progn
                       (setf new-pending-filter-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               new-pending-filter-body)))
                       (setf send-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-pending-body)))
                       (setf send-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-basefee-body)))
                       (setf send-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-queued-body)))
                       (setf raw-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-pending-body)))
                       (setf raw-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-basefee-body)))
                       (setf raw-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-queued-body)))
                       (let* ((new-pending-filter-rpc
                                (parse-json
                                 (devnet-cli-http-body
                                  new-pending-filter-response)))
                              (pending-filter-id
                                (fixture-object-field
                                 new-pending-filter-rpc "result"))
                              (pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 718)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (empty-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 719)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (uninstall-pending-filter-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 720)
                                  (cons "method" "eth_uninstallFilter")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (removed-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 721)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id))))))
                         (setf pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 pending-filter-changes-body)))
                         (setf empty-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 empty-pending-filter-changes-body)))
                         (setf uninstall-pending-filter-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 uninstall-pending-filter-body)))
                         (setf removed-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 removed-pending-filter-changes-body))))
                       (setf pending-transactions-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transactions-body)))
                       (setf pending-block-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-count-body)))
                       (setf pending-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transaction-by-index-body)))
                       (setf pending-raw-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-raw-transaction-by-index-body)))
                       (setf pending-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-body)))
                       (setf pending-header-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-header-body)))
                       (setf pending-fee-history-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-fee-history-body)))
                       (setf pending-sender-nonce-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-sender-nonce-body)))
                       (setf pending-block-receipts-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-receipts-body)))
                       (setf pending-uncle-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-uncle-count-body)))
                       (setf pending-logs-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-logs-body)))
                       (setf txpool-status-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-status-body)))
                       (setf txpool-content-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-body)))
                       (setf txpool-content-from-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-from-body)))
                       (setf txpool-inspect-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-inspect-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response
                          (list send-pending-response
                                send-basefee-response
                                send-queued-response
                                raw-pending-response
                                raw-basefee-response
                                raw-queued-response
                                new-pending-filter-response
                                pending-filter-changes-response
                                empty-pending-filter-changes-response
                                uninstall-pending-filter-response
                                removed-pending-filter-changes-response
                                pending-transactions-response
                                pending-block-count-response
                                pending-transaction-by-index-response
                                pending-raw-transaction-by-index-response
                                pending-block-response
                                pending-header-response
                                pending-fee-history-response
                                pending-sender-nonce-response
                                pending-block-receipts-response
                                pending-uncle-count-response
                                pending-logs-response
                                txpool-status-response
                                txpool-content-response
                                txpool-content-from-response
                                txpool-inspect-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((send-pending-rpc
                          (parse-json
                           (devnet-cli-http-body send-pending-response)))
                        (send-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body send-basefee-response)))
                        (send-queued-rpc
                          (parse-json
                           (devnet-cli-http-body send-queued-response)))
                        (raw-pending-rpc
                          (parse-json
                           (devnet-cli-http-body raw-pending-response)))
                        (raw-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body raw-basefee-response)))
                        (raw-queued-rpc
                          (parse-json
                           (devnet-cli-http-body raw-queued-response)))
                        (new-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            new-pending-filter-response)))
                        (pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-filter-changes-response)))
                        (empty-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            empty-pending-filter-changes-response)
                           :preserve-empty-arrays t))
                        (uninstall-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            uninstall-pending-filter-response)))
                        (removed-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            removed-pending-filter-changes-response)))
                        (pending-transactions-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transactions-response)))
                        (pending-block-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-count-response)))
                        (pending-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transaction-by-index-response)))
                        (pending-raw-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-raw-transaction-by-index-response)))
                        (pending-block-rpc
                          (parse-json
                           (devnet-cli-http-body pending-block-response)))
                        (pending-header-rpc
                          (parse-json
                           (devnet-cli-http-body pending-header-response)))
                        (pending-fee-history-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-fee-history-response)))
                        (pending-sender-nonce-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-sender-nonce-response)))
                        (pending-block-receipts-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-receipts-response)))
                        (pending-uncle-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-uncle-count-response)))
                        (pending-logs-rpc
                          (parse-json
                           (devnet-cli-http-body pending-logs-response)
                           :preserve-empty-arrays t))
                        (txpool-status-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-status-response)))
                        (txpool-content-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-content-response)))
                        (txpool-content-from-rpc
                          (parse-json
                           (devnet-cli-http-body
                            txpool-content-from-response)))
                        (txpool-inspect-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-inspect-response)))
                        (pending-transactions
                          (fixture-object-field
                           pending-transactions-rpc "result"))
                        (pending-filter-changes
                          (fixture-object-field
                           pending-filter-changes-rpc "result"))
                        (empty-pending-filter-changes
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "result"))
                        (removed-pending-filter-error
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "error"))
                        (pending-object (first pending-transactions))
                        (pending-block-count
                          (fixture-object-field pending-block-count-rpc
                                                "result"))
                        (pending-transaction-by-index
                          (fixture-object-field
                           pending-transaction-by-index-rpc "result"))
                        (pending-raw-transaction-by-index
                          (fixture-object-field
                           pending-raw-transaction-by-index-rpc "result"))
                        (pending-block
                          (fixture-object-field pending-block-rpc "result"))
                        (pending-header
                          (fixture-object-field pending-header-rpc "result"))
                        (pending-fee-history
                          (fixture-object-field pending-fee-history-rpc
                                                "result"))
                        (pending-sender-nonce
                          (fixture-object-field pending-sender-nonce-rpc
                                                "result"))
                        (pending-logs
                          (fixture-object-field pending-logs-rpc "result"))
                        (pending-fee-history-base-fees
                          (fixture-object-field pending-fee-history
                                                "baseFeePerGas"))
                        (pending-fee-history-next-base-fee
                          (second pending-fee-history-base-fees))
                        (pending-block-transactions
                          (fixture-object-field pending-block "transactions"))
                        (pending-block-transaction
                          (first pending-block-transactions))
                        (txpool-status
                          (fixture-object-field txpool-status-rpc "result"))
                        (txpool-content
                          (fixture-object-field txpool-content-rpc "result"))
                        (content-pending
                          (fixture-object-field txpool-content "pending"))
                        (content-queued
                          (fixture-object-field txpool-content "queued"))
                        (content-pending-sender
                          (fixture-object-field content-pending sender-hex))
                        (content-queued-sender
                          (fixture-object-field content-queued sender-hex))
                        (content-pending-transaction
                          (fixture-object-field content-pending-sender
                                                pending-nonce))
                        (content-basefee-transaction
                          (fixture-object-field content-queued-sender
                                                basefee-nonce))
                        (content-queued-transaction
                          (fixture-object-field content-queued-sender
                                                queued-nonce))
                        (txpool-content-from
                          (fixture-object-field
                           txpool-content-from-rpc "result"))
                        (content-from-pending
                          (fixture-object-field txpool-content-from "pending"))
                        (content-from-queued
                          (fixture-object-field txpool-content-from "queued"))
                        (content-from-pending-transaction
                          (fixture-object-field
                           content-from-pending pending-nonce))
                        (content-from-basefee-transaction
                          (fixture-object-field
                           content-from-queued basefee-nonce))
                        (content-from-queued-transaction
                          (fixture-object-field
                           content-from-queued queued-nonce))
                        (txpool-inspect
                          (fixture-object-field txpool-inspect-rpc "result"))
                        (inspect-pending
                          (fixture-object-field txpool-inspect "pending"))
                        (inspect-queued
                          (fixture-object-field txpool-inspect "queued"))
                        (inspect-pending-sender
                          (fixture-object-field inspect-pending sender-hex))
                        (inspect-queued-sender
                          (fixture-object-field inspect-queued sender-hex)))
                   (is (= 701 (fixture-object-field send-pending-rpc "id")))
                   (is (= 702 (fixture-object-field send-basefee-rpc "id")))
                   (is (= 703 (fixture-object-field send-queued-rpc "id")))
                   (is (= 717
                          (fixture-object-field new-pending-filter-rpc "id")))
                   (is (= 718
                          (fixture-object-field pending-filter-changes-rpc
                                                "id")))
                   (is (= 719
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "id")))
                   (is (= 720
                          (fixture-object-field
                           uninstall-pending-filter-rpc "id")))
                   (is (= 721
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "id")))
                   (is (= 711 (fixture-object-field pending-block-count-rpc
                                                    "id")))
                   (is (= 712 (fixture-object-field
                               pending-transaction-by-index-rpc "id")))
                   (is (= 713 (fixture-object-field
                               pending-raw-transaction-by-index-rpc "id")))
                   (is (= 714 (fixture-object-field pending-block-rpc "id")))
                   (is (= 715 (fixture-object-field pending-header-rpc "id")))
                   (is (= 722
                          (fixture-object-field pending-fee-history-rpc "id")))
                   (is (= 723
                          (fixture-object-field pending-sender-nonce-rpc "id")))
                   (is (= 724
                          (fixture-object-field
                           pending-block-receipts-rpc "id")))
                   (is (= 725
                          (fixture-object-field pending-uncle-count-rpc "id")))
                   (is (= 726 (fixture-object-field pending-logs-rpc "id")))
                   (is (= 716 (fixture-object-field txpool-content-rpc "id")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 send-pending-rpc "result")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 send-basefee-rpc "result")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 send-queued-rpc "result")))
                   (is (string= pending-raw
                                (fixture-object-field
                                 raw-pending-rpc "result")))
                   (is (string= basefee-raw
                                (fixture-object-field
                                 raw-basefee-rpc "result")))
                   (is (string= queued-raw
                                (fixture-object-field
                                 raw-queued-rpc "result")))
                   (is (string= "0x1"
                                (fixture-object-field
                                 new-pending-filter-rpc "result")))
                   (is (= 1 (length pending-filter-changes)))
                   (is (string= pending-hash
                                (first pending-filter-changes)))
                   (is (devnet-cli-empty-json-array-p
                        empty-pending-filter-changes))
                   (is (eq t (fixture-object-field
                              uninstall-pending-filter-rpc "result")))
                   (is (= -32602
                          (fixture-object-field
                           removed-pending-filter-error "code")))
                   (is (= 1 (length pending-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field pending-object "hash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockNumber")))
                   (is (null (fixture-object-field pending-object
                                                   "transactionIndex")))
                   (is (string= "0x1" pending-block-count))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-transaction-by-index "hash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockHash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockNumber")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index
                              "transactionIndex")))
                   (is (string= pending-raw pending-raw-transaction-by-index))
                   (is (null (fixture-object-field pending-block "hash")))
                   (is (null (fixture-object-field pending-block "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-block "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-block
                                                      "parentHash")))
                   (is (= 1 (length pending-block-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-block-transaction "hash")))
                   (is (null (fixture-object-field pending-block-transaction
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-header "hash")))
                   (is (null (fixture-object-field pending-header "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-header
                                                      "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-header
                                                      "parentHash")))
                   (is (= 2 (length pending-fee-history-base-fees)))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-block
                                                      "baseFeePerGas")))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-header
                                                      "baseFeePerGas")))
                   (is (string= expected-pending-sender-nonce
                                pending-sender-nonce))
                   (is (null (fixture-object-field
                              pending-block-receipts-rpc "result")))
                   (is (string= "0x0"
                                (fixture-object-field
                                 pending-uncle-count-rpc "result")))
                   (is (devnet-cli-empty-json-array-p pending-logs))
                   (is (string= "0x1"
                                (fixture-object-field txpool-status
                                                      "pending")))
                   (is (string= "0x2"
                                (fixture-object-field txpool-status
                                                      "queued")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-queued-transaction "hash")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-from-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-from-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-from-queued-transaction "hash")))
                   (is (string= pending-summary
                                (fixture-object-field inspect-pending-sender
                                                      pending-nonce)))
                   (is (string= basefee-summary
                                (fixture-object-field inspect-queued-sender
                                                      basefee-nonce)))
                   (is (string= queued-summary
                                (fixture-object-field inspect-queued-sender
                                                      queued-nonce))))
                 (let ((status (devnet-cli-wait-process-exit process 30)))
                   (when (eq status :timeout)
                     (uiop:terminate-process process))
                   (is (not (eq status :timeout)))
                   (is (and (numberp status) (= 0 status)))
                   (let ((stdout
                           (devnet-cli-read-stream-string
                            (uiop:process-info-output process)))
                         (stderr
                           (devnet-cli-read-stream-string
                            (uiop:process-info-error-output process))))
                     (is (string= "" stderr))
                     (when (and (numberp status) (= 0 status))
                       (let* ((stdout-summary (parse-json stdout))
                              (log-records (devnet-cli-file-forms log-path))
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))

(deftest ethereum-lisp-script-serve-mode-serves-engine-v1-workflow
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-genesis"
                                "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode (devnet-cli-pre-shanghai-genesis-object)))
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (genesis-block
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (payload-attributes
                    (make-payload-attributes-v1
                     :timestamp
                     (1+ (block-header-timestamp
                          (block-header genesis-block)))
                     :prev-randao (zero-hash32)
                     :suggested-fee-recipient (zero-address)))
                  (child-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     genesis-block
                     payload-attributes))
                  (prepared-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     child-block
                     (make-payload-attributes-v1
                      :timestamp
                      (1+ (block-header-timestamp
                           (block-header child-block)))
                      :prev-randao (zero-hash32)
                      :suggested-fee-recipient (zero-address))))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (child-hash (block-hash child-block))
                  (child-hash-hex (hash32-to-hex child-hash))
                  (prepared-block-number
                    (quantity-to-hex
                     (block-header-number (block-header prepared-block))))
                  (prepare-payload-attributes
                    (devnet-cli-payload-attributes-v1 child-block
                                                      (zero-address)))
                  (new-payload-body
                    (json-encode
                     (devnet-cli-engine-new-payload-v1-request 701
                                                               payload)))
                  (forkchoice-body
                    (json-encode
                     (engine-fixture-forkchoice-request
                      702 child-hash
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (prepare-body
                    (json-encode
                     (devnet-cli-engine-forkchoice-v1-payload-attributes-request
                      703 child-hash prepare-payload-attributes
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (block-number-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_blockNumber")
                           (cons "params" '()))))
                  (latest-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "latest" :false)))))
                  (chain-id-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_chainId")
                           (cons "params" '()))))
                  (net-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "net_version")
                           (cons "params" '()))))
                  (client-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "web3_clientVersion")
                           (cons "params" '())))))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--authrpc.jwtsecret"
                          (namestring jwt-path)
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--max-connections"
                          "5"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file ready-path 10)
               (when (uiop:process-alive-p process)
                 (uiop:terminate-process process)
                 (devnet-cli-wait-process-exit process 5))
               (let ((stdout
                       (devnet-cli-read-stream-string
                        (uiop:process-info-output process)))
                     (stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (when (search "Operation not permitted" stderr)
                   (skip-test
                    "Local socket bind is not permitted in this sandbox"))
                 (is (probe-file ready-path))
                 (is (string= "" stdout))
                 (is (string= "" stderr))))
             (when (probe-file ready-path)
               (let* ((ready-summary
                        (parse-json (devnet-cli-file-string ready-path)))
                      (pid (devnet-cli-pid-file-process-id pid-path))
                      (engine-endpoint
                        (fixture-object-field ready-summary
                                              "engineEndpoint"))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                      (token (engine-rpc-make-jwt-token jwt-secret 0))
                      new-payload-response
                      forkchoice-response
                      prepare-response
                      get-payload-v1-response
                      get-payload-v2-response
                      block-number-response
                      latest-block-response
                      chain-id-response
                      net-version-response
                      client-version-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
                 (handler-case
                     (progn
                       (setf new-payload-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               new-payload-body
                               :token token)))
                       (setf forkchoice-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               forkchoice-body
                               :token token)))
                       (setf prepare-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               prepare-body
                               :token token)))
                       (let* ((prepare-json
                                (parse-json
                                 (devnet-cli-http-body prepare-response)))
                              (payload-id
                                (fixture-object-field
                                 (fixture-object-field prepare-json "result")
                                 "payloadId"))
                              (get-payload-v1-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 709)
                                       (cons "method" "engine_getPayloadV1")
                                       (cons "params" (list payload-id)))))
                              (get-payload-v2-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 710)
                                       (cons "method" "engine_getPayloadV2")
                                       (cons "params" (list payload-id))))))
                         (setf get-payload-v1-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v1-body
                                 :token token)))
                         (setf get-payload-v2-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v2-body
                                 :token token))))
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf latest-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-block-body)))
                       (setf chain-id-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               chain-id-body)))
                       (setf net-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               net-version-body)))
                       (setf client-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               client-version-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status prepare-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v1-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v2-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status latest-block-response)))
                 (is (= 200 (devnet-cli-http-status chain-id-response)))
                 (is (= 200 (devnet-cli-http-status net-version-response)))
                 (is (= 200 (devnet-cli-http-status
                              client-version-response)))
                 (let* ((new-payload-json
                          (parse-json
                           (devnet-cli-http-body new-payload-response)))
                        (new-payload-result
                          (fixture-object-field new-payload-json "result"))
                        (forkchoice-json
                          (parse-json
                           (devnet-cli-http-body forkchoice-response)))
                        (forkchoice-result
                          (fixture-object-field forkchoice-json "result"))
                        (forkchoice-status
                          (fixture-object-field forkchoice-result
                                                "payloadStatus"))
                        (prepare-json
                          (parse-json
                           (devnet-cli-http-body prepare-response)))
                        (prepare-result
                          (fixture-object-field prepare-json "result"))
                        (prepare-status
                          (fixture-object-field prepare-result
                                                "payloadStatus"))
                        (payload-id
                          (fixture-object-field prepare-result
                                                "payloadId"))
                        (get-payload-v1-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v1-response)))
                        (get-payload-v1-result
                          (fixture-object-field get-payload-v1-json
                                                "result"))
                        (get-payload-v2-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v2-response)))
                        (get-payload-v2-result
                          (fixture-object-field get-payload-v2-json
                                                "result"))
                        (get-payload-v2-payload
                          (fixture-object-field get-payload-v2-result
                                                "executionPayload"))
                        (block-number-json
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (latest-block-json
                          (parse-json
                           (devnet-cli-http-body latest-block-response)))
                        (latest-block
                          (fixture-object-field latest-block-json
                                                "result"))
                        (chain-id-json
                          (parse-json
                           (devnet-cli-http-body chain-id-response)))
                        (net-version-json
                          (parse-json
                           (devnet-cli-http-body net-version-response)))
                        (client-version-json
                          (parse-json
                           (devnet-cli-http-body client-version-response))))
                   (is (= 701 (fixture-object-field new-payload-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field new-payload-result
                                                      "status")))
                   (is (string= child-hash-hex
                                (fixture-object-field new-payload-result
                                                      "latestValidHash")))
                   (is (= 702 (fixture-object-field forkchoice-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field forkchoice-status
                                                      "status")))
                   (is (null (fixture-object-field forkchoice-result
                                                   "payloadId")))
                   (is (= 703 (fixture-object-field prepare-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field prepare-status
                                                      "status")))
                   (is (stringp payload-id))
                   (is (= 18 (length payload-id)))
                   (is (= 709 (fixture-object-field get-payload-v1-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v1-result
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v1-result
                                                      "blockNumber")))
                   (is (= 0 (length (fixture-object-field
                                     get-payload-v1-result
                                     "transactions"))))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "withdrawals")))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "executionPayload")))
                   (is (= 710 (fixture-object-field get-payload-v2-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v2-payload
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v2-payload
                                                      "blockNumber")))
                   (is (string= "0x1"
                                (fixture-object-field block-number-json
                                                      "result")))
                   (is (string= child-hash-hex
                                (fixture-object-field latest-block "hash")))
                   (is (string= "0x1"
                                (fixture-object-field latest-block
                                                      "number")))
                   (is (string= "0x539"
                                (fixture-object-field chain-id-json
                                                      "result")))
                   (is (string= "1337"
                                (fixture-object-field net-version-json
                                                      "result")))
                   (is (search "ethereum-lisp"
                               (fixture-object-field client-version-json
                                                     "result"))))
                 (let ((status (devnet-cli-wait-process-exit process 10)))
                   (when (eq status :timeout)
                     (uiop:terminate-process process))
                   (is (not (eq status :timeout)))
                   (is (and (numberp status) (= 0 status)))
                   (let ((stdout
                           (devnet-cli-read-stream-string
                            (uiop:process-info-output process)))
                         (stderr
                           (devnet-cli-read-stream-string
                            (uiop:process-info-error-output process))))
                     (is (string= "" stderr))
                     (when (and (numberp status) (= 0 status))
                       (let* ((stdout-summary (parse-json stdout))
                              (log-records (devnet-cli-file-forms log-path))
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field stdout-summary
                                                            "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "5"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "5"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "10"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))

(deftest ethereum-lisp-script-serve-mode-imports-payload-and-serves-public-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (side-sibling-block
                  (devnet-cli-engine-fixture-side-sibling-block
                   case parent-block))
                (remote-block (devnet-cli-remote-block child-block))
                (invalid-block (devnet-cli-invalid-child-block child-block))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (side-sibling-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data side-sibling-block)))
                (remote-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data remote-block)))
                (invalid-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data invalid-block)))
                (parent (fixture-object-field case "parent"))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (sender (fixture-address-field expect "sender"))
                (code-address (fixture-address-field expect "codeAddress"))
                (storage-address
                  (fixture-address-field expect "storageAddress"))
                (transaction
                  (first (block-transactions child-block)))
                (block-hash-hex
                  (hash32-to-hex (block-hash child-block)))
                (side-sibling-block-hash-hex
                  (hash32-to-hex (block-hash side-sibling-block)))
                (transaction-hash-hex
                  (hash32-to-hex
                   (transaction-hash transaction)))
                (raw-transaction-hex
                  (devnet-cli-transaction-raw transaction))
                (expected-transaction-count-hex
                  (quantity-to-hex (length (block-transactions child-block))))
                (simulation-call-object
                  (list (cons "from" (address-to-hex sender))
                        (cons "to" (address-to-hex code-address))
                        (cons "gas" "0x186a0")
                        (cons "gasPrice" "0x64")
                        (cons "data" "0x")))
                (prepare-payload-attributes
                  (devnet-cli-payload-attributes-v2
                   child-block
                   (block-header-beneficiary (block-header child-block))))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 601 payload)))
                (remote-payload-body
                  (json-encode
                   (engine-fixture-payload-request 613 remote-payload)))
                (invalid-payload-body
                  (json-encode
                   (engine-fixture-payload-request 614 invalid-payload)))
                (side-sibling-payload-body
                  (json-encode
                   (engine-fixture-payload-request 647
                                                   side-sibling-payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    602 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (side-sibling-forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    648 (block-hash side-sibling-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (payload-bodies-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 609)
                         (cons "method" "engine_getPayloadBodiesByHashV1")
                         (cons "params"
                               (list
                                (list
                                 (hash32-to-hex
                                  (block-hash child-block))))))))
                (payload-bodies-by-range-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 610)
                         (cons "method" "engine_getPayloadBodiesByRangeV1")
                         (cons "params"
                               (list
                                (fixture-object-field payload-case "number")
                                "0x1")))))
                (prepare-payload-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-payload-attributes-request
                    605
                    (block-hash child-block)
                    prepare-payload-attributes
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 603)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (post-status-block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 615)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                604 recipient)))
                (safe-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 622)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient) "safe")))))
                (finalized-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 623)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient)
                                     "finalized")))))
                (proof-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 633)
                         (cons "method" "eth_getProof")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (list (fixture-object-field expect
                                                                 "storageKey"))
                                     "latest")))))
                (block-hash-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 634)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)))))))
                (require-canonical-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 635)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)
                                      (cons "requireCanonical" t)))))))
                (transaction-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 607)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "latest")))))
                (block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 608)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 624)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (full-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 640)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" t)))))
                (full-block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 641)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex t)))))
                (block-transaction-count-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 625)
                         (cons "method"
                               "eth_getBlockTransactionCountByHash")
                         (cons "params" (list block-hash-hex)))))
                (block-transaction-count-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 626)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number"))))))
                (transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 627)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 628)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 629)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (raw-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 630)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (raw-transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 631)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (raw-transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 632)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (safe-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 620)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "safe" :false)))))
                (finalized-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 621)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "finalized" :false)))))
                (post-status-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 616)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (code-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 611)
                         (cons "method" "eth_getCode")
                         (cons "params"
                               (list (address-to-hex code-address)
                                     "latest")))))
                (storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 612)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (call-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 636)
                         (cons "method" "eth_call")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (estimate-gas-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 637)
                         (cons "method" "eth_estimateGas")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (create-access-list-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 638)
                         (cons "method" "eth_createAccessList")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (post-call-storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 639)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 617)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (block-receipts-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 618)
                         (cons "method" "eth_getBlockReceipts")
                         (cons "params" (list "latest")))))
                (logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 619)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (logs-by-block-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 642)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash" block-hash-hex)
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-log-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 645)
                         (cons "method" "eth_newFilter")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-block-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 643)
                         (cons "method" "eth_newBlockFilter")
                         (cons "params" '()))))
                (post-reorg-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 651)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (post-reorg-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 652)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 653)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 654)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (post-reorg-pending-block-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 655)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 656)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-raw-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 657)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-block-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 658)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "pending" t)))))
                (post-reorg-pending-header-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 659)
                         (cons "method" "eth_getHeaderByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-sender-nonce-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 660)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "pending"))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node)))
             (is (string= (hash32-to-hex (block-hash parent-block))
                          (hash32-to-hex (block-hash script-genesis))))
             (is (= (fixture-quantity-field payload-case "number")
                    (1+ (block-header-number
                         (block-header script-genesis))))))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "50"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    new-block-filter-response
                    new-log-filter-response
                    new-payload-response
                    forkchoice-response
                    payload-bodies-by-hash-response
                    payload-bodies-by-range-response
                    prepare-payload-response
                    get-payload-response
                    remote-payload-response
                    invalid-payload-response
                    side-sibling-payload-response
                    side-sibling-forkchoice-response
                    block-number-response
                    post-status-block-number-response
                    balance-response
                    safe-balance-response
                    finalized-balance-response
                    proof-response
                    block-hash-balance-response
                    require-canonical-balance-response
                    transaction-count-response
                    block-by-number-response
                    block-by-hash-response
                    full-block-by-number-response
                    full-block-by-hash-response
                    block-transaction-count-by-hash-response
                    block-transaction-count-by-number-response
                    transaction-by-hash-response
                    transaction-by-block-hash-and-index-response
                    transaction-by-block-number-and-index-response
                    raw-transaction-by-hash-response
                    raw-transaction-by-block-hash-and-index-response
                    raw-transaction-by-block-number-and-index-response
                    safe-block-by-number-response
                    finalized-block-by-number-response
                    post-status-block-by-number-response
                    code-response
                    storage-response
                    call-response
                    estimate-gas-response
                    create-access-list-response
                    post-call-storage-response
                    receipt-response
                    block-receipts-response
                    logs-response
                    logs-by-block-hash-response
                    block-filter-changes-response
                    log-filter-changes-response
                    post-reorg-block-filter-changes-response
                    post-reorg-log-filter-changes-response
                    post-reorg-block-by-number-response
                    post-reorg-transaction-by-hash-response
                    post-reorg-receipt-response
                    post-reorg-logs-response
                    post-reorg-pending-block-count-response
                    post-reorg-pending-transaction-by-index-response
                    post-reorg-pending-raw-transaction-by-index-response
                    post-reorg-pending-block-response
                    post-reorg-pending-header-response
                    post-reorg-pending-sender-nonce-response
                    block-filter-id
                    log-filter-id)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (handler-case
                   (progn
                     (setf new-block-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-block-filter-body)))
                     (setf new-log-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-log-filter-body)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token)))
                     (setf payload-bodies-by-hash-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-hash-body
                             :token token)))
                     (setf payload-bodies-by-range-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-range-body
                             :token token)))
                     (setf prepare-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             prepare-payload-body
                             :token token)))
                     (let* ((prepare-payload-rpc
                              (parse-json
                               (devnet-cli-http-body
                                prepare-payload-response)))
                            (prepare-payload-result
                              (fixture-object-field
                               prepare-payload-rpc "result"))
                            (prepared-payload-id
                              (fixture-object-field
                               prepare-payload-result "payloadId"))
                            (get-payload-body
                              (json-encode
                               (list
                                (cons "jsonrpc" "2.0")
                                (cons "id" 606)
                                (cons "method" "engine_getPayloadV2")
                                (cons "params"
                                      (list prepared-payload-id))))))
                       (setf get-payload-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               get-payload-body
                               :token token))))
                     (setf remote-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             remote-payload-body
                             :token token)))
                     (setf invalid-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             invalid-payload-body
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body)))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body)))
                     (setf safe-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-balance-body)))
                     (setf finalized-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-balance-body)))
                     (setf proof-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             proof-body)))
                     (setf block-hash-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-hash-balance-body)))
                     (setf require-canonical-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             require-canonical-balance-body)))
                     (setf transaction-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-count-body)))
                     (setf block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-number-body)))
                     (setf block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-hash-body)))
                     (setf full-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-number-body)))
                     (setf full-block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-hash-body)))
                     (setf block-transaction-count-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-hash-body)))
                     (setf block-transaction-count-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-number-body)))
                     (setf transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-hash-body)))
                     (setf transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-hash-and-index-body)))
                     (setf transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-number-and-index-body)))
                     (setf raw-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-hash-body)))
                     (setf raw-transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-hash-and-index-body)))
                     (setf raw-transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-number-and-index-body)))
                     (setf safe-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-block-by-number-body)))
                     (setf finalized-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-block-by-number-body)))
                     (setf code-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             code-body)))
                     (setf storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             storage-body)))
                     (setf call-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             call-body)))
                     (setf estimate-gas-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             estimate-gas-body)))
                     (setf create-access-list-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             create-access-list-body)))
                     (setf post-call-storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-call-storage-body)))
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body)))
                     (setf block-receipts-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-receipts-body)))
                     (setf logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-body)))
                     (setf logs-by-block-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-by-block-hash-body)))
                     (let* ((new-block-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-block-filter-response))))
                       (setf block-filter-id
                             (fixture-object-field
                              new-block-filter-rpc "result"))
                       (let ((block-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 644)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list block-filter-id))))))
                       (setf block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-filter-changes-body)))))
                     (let* ((new-log-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-log-filter-response))))
                       (setf log-filter-id
                             (fixture-object-field
                              new-log-filter-rpc "result"))
                       (let ((log-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 646)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list log-filter-id))))))
                       (setf log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               log-filter-changes-body)))))
                     (setf post-status-block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-number-body)))
                     (setf post-status-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-by-number-body)))
                     (setf side-sibling-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-payload-body
                             :token token)))
                     (setf side-sibling-forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-forkchoice-body
                             :token token)))
                     (setf post-reorg-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-block-by-number-body)))
                     (setf post-reorg-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-transaction-by-hash-body)))
                     (setf post-reorg-receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-receipt-body)))
                     (setf post-reorg-logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-logs-body)))
                     (setf post-reorg-pending-block-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-count-body)))
                     (setf post-reorg-pending-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-transaction-by-index-body)))
                     (setf post-reorg-pending-raw-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-raw-transaction-by-index-body)))
                     (setf post-reorg-pending-block-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-body)))
                     (setf post-reorg-pending-header-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-header-body)))
                     (setf post-reorg-pending-sender-nonce-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-sender-nonce-body)))
                     (let ((post-reorg-block-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 649)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list block-filter-id))))))
                       (setf post-reorg-block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-block-filter-changes-body))))
                     (let ((post-reorg-log-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 650)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list log-filter-id))))))
                       (setf post-reorg-log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-log-filter-changes-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                               "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status new-block-filter-response)))
               (is (= 200 (devnet-cli-http-status new-log-filter-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-range-response)))
               (is (= 200 (devnet-cli-http-status prepare-payload-response)))
               (is (= 200 (devnet-cli-http-status get-payload-response)))
               (is (= 200 (devnet-cli-http-status remote-payload-response)))
               (is (= 200 (devnet-cli-http-status invalid-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-receipt-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-logs-response)))
               (is (= 200 (devnet-cli-http-status block-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-number-response)))
               (is (= 200 (devnet-cli-http-status balance-response)))
               (is (= 200 (devnet-cli-http-status safe-balance-response)))
               (is (= 200 (devnet-cli-http-status finalized-balance-response)))
               (is (= 200 (devnet-cli-http-status proof-response)))
               (is (= 200 (devnet-cli-http-status
                            block-hash-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            require-canonical-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-count-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            safe-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            finalized-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status code-response)))
               (is (= 200 (devnet-cli-http-status storage-response)))
               (is (= 200 (devnet-cli-http-status call-response)))
               (is (= 200 (devnet-cli-http-status estimate-gas-response)))
               (is (= 200 (devnet-cli-http-status
                            create-access-list-response)))
               (is (= 200 (devnet-cli-http-status
                            post-call-storage-response)))
               (is (= 200 (devnet-cli-http-status receipt-response)))
               (is (= 200 (devnet-cli-http-status block-receipts-response)))
               (is (= 200 (devnet-cli-http-status logs-response)))
               (is (= 200 (devnet-cli-http-status
                            logs-by-block-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-count-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-raw-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-header-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-sender-nonce-response)))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-block-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-block-filter-response)))
                      (new-log-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-log-filter-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (payload-bodies-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-hash-response)))
                      (payload-bodies-by-range-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-range-response)))
                      (prepare-payload-rpc
                        (parse-json
                         (devnet-cli-http-body prepare-payload-response)))
                      (get-payload-rpc
                        (parse-json
                         (devnet-cli-http-body get-payload-response)))
                      (remote-payload-rpc
                        (parse-json
                         (devnet-cli-http-body remote-payload-response)))
                      (invalid-payload-rpc
                        (parse-json
                         (devnet-cli-http-body invalid-payload-response)))
                      (side-sibling-payload-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-payload-response)))
                      (side-sibling-forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-forkchoice-response)))
                      (post-reorg-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-by-number-response)))
                      (post-reorg-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-transaction-by-hash-response)))
                      (post-reorg-receipt-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-receipt-response)))
                      (post-reorg-logs-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-logs-response)))
                      (post-reorg-pending-block-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-count-response)))
                      (post-reorg-pending-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-transaction-by-index-response)))
                      (post-reorg-pending-raw-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-raw-transaction-by-index-response)))
                      (post-reorg-pending-block-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-response)))
                      (post-reorg-pending-header-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-header-response)))
                      (post-reorg-pending-sender-nonce-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-sender-nonce-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (post-status-block-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (safe-balance-rpc
                        (parse-json
                         (devnet-cli-http-body safe-balance-response)))
                      (finalized-balance-rpc
                        (parse-json
                         (devnet-cli-http-body finalized-balance-response)))
                      (proof-rpc
                        (parse-json
                         (devnet-cli-http-body proof-response)))
                      (block-hash-balance-rpc
                        (parse-json
                         (devnet-cli-http-body block-hash-balance-response)))
                      (require-canonical-balance-rpc
                        (parse-json
                         (devnet-cli-http-body
                          require-canonical-balance-response)))
                      (transaction-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-count-response)))
                      (block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-number-response)))
                      (block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-hash-response)))
                      (full-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-number-response)))
                      (full-block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-hash-response)))
                      (block-transaction-count-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-hash-response)))
                      (block-transaction-count-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-number-response)))
                      (transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-hash-response)))
                      (transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-hash-and-index-response)))
                      (transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-number-and-index-response)))
                      (raw-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-hash-response)))
                      (raw-transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-hash-and-index-response)))
                      (raw-transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-number-and-index-response)))
                      (safe-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          safe-block-by-number-response)))
                      (finalized-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          finalized-block-by-number-response)))
                      (post-status-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-by-number-response)))
                      (code-rpc
                        (parse-json
                         (devnet-cli-http-body code-response)))
                      (storage-rpc
                        (parse-json
                         (devnet-cli-http-body storage-response)))
                      (call-rpc
                        (parse-json
                         (devnet-cli-http-body call-response)))
                      (estimate-gas-rpc
                        (parse-json
                         (devnet-cli-http-body estimate-gas-response)))
                      (create-access-list-rpc
                        (parse-json
                         (devnet-cli-http-body
                          create-access-list-response)))
                      (post-call-storage-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-call-storage-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (block-receipts-rpc
                        (parse-json
                         (devnet-cli-http-body block-receipts-response)))
                      (logs-rpc
                        (parse-json
                         (devnet-cli-http-body logs-response)))
                      (logs-by-block-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          logs-by-block-hash-response)))
                      (block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-filter-changes-response)))
                      (block-filter-changes
                        (fixture-object-field block-filter-changes-rpc
                                              "result"))
                      (log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          log-filter-changes-response)))
                      (log-filter-changes
                        (fixture-object-field log-filter-changes-rpc
                                              "result"))
                      (log-filter-change-log (first log-filter-changes))
                      (post-reorg-block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-filter-changes-response)))
                      (post-reorg-block-filter-changes
                        (fixture-object-field
                         post-reorg-block-filter-changes-rpc
                         "result"))
                      (post-reorg-log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-log-filter-changes-response)))
                      (post-reorg-log-filter-changes
                        (fixture-object-field
                         post-reorg-log-filter-changes-rpc
                         "result"))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (side-sibling-payload-result
                        (fixture-object-field
                         side-sibling-payload-rpc "result"))
                      (side-sibling-forkchoice-status
                        (fixture-object-field
                         (fixture-object-field
                          side-sibling-forkchoice-rpc "result")
                         "payloadStatus"))
                      (post-reorg-block-by-number-result
                        (fixture-object-field
                         post-reorg-block-by-number-rpc "result"))
                      (post-reorg-transaction-by-hash-result
                        (fixture-object-field
                         post-reorg-transaction-by-hash-rpc "result"))
                      (post-reorg-logs
                        (fixture-object-field post-reorg-logs-rpc "result"))
                      (post-reorg-pending-block-count
                        (fixture-object-field
                         post-reorg-pending-block-count-rpc "result"))
                      (post-reorg-pending-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-raw-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-block
                        (fixture-object-field
                         post-reorg-pending-block-rpc "result"))
                      (post-reorg-pending-header
                        (fixture-object-field
                         post-reorg-pending-header-rpc "result"))
                      (post-reorg-pending-sender-nonce
                        (fixture-object-field
                         post-reorg-pending-sender-nonce-rpc "result"))
                      (post-reorg-pending-block-transactions
                        (fixture-object-field
                         post-reorg-pending-block "transactions"))
                      (post-reorg-pending-block-transaction
                        (first post-reorg-pending-block-transactions))
                      (payload-bodies-by-hash-result
                        (fixture-object-field
                         payload-bodies-by-hash-rpc "result"))
                      (payload-bodies-by-range-result
                        (fixture-object-field
                         payload-bodies-by-range-rpc "result"))
                      (payload-body-by-hash-transactions
                        (fixture-object-field
                         (first payload-bodies-by-hash-result)
                         "transactions"))
                      (payload-body-by-range-transactions
                        (fixture-object-field
                         (first payload-bodies-by-range-result)
                         "transactions"))
                      (expected-payload-body-transaction-count
                        (length (block-transactions child-block)))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result "payloadId"))
                      (get-payload-result
                        (fixture-object-field get-payload-rpc "result"))
                      (get-payload-execution-payload
                        (fixture-object-field
                         get-payload-result
                         "executionPayload"))
                      (get-payload-transactions
                        (fixture-object-field
                         get-payload-execution-payload
                         "transactions"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (block-by-number-result
                        (fixture-object-field block-by-number-rpc "result"))
                      (block-by-hash-result
                        (fixture-object-field block-by-hash-rpc "result"))
                      (full-block-by-number-result
                        (fixture-object-field full-block-by-number-rpc
                                              "result"))
                      (full-block-by-hash-result
                        (fixture-object-field full-block-by-hash-rpc
                                              "result"))
                      (full-block-by-number-transactions
                        (fixture-object-field full-block-by-number-result
                                              "transactions"))
                      (full-block-by-hash-transactions
                        (fixture-object-field full-block-by-hash-result
                                              "transactions"))
                      (full-block-by-number-transaction
                        (first full-block-by-number-transactions))
                      (full-block-by-hash-transaction
                        (first full-block-by-hash-transactions))
                      (transaction-by-hash-result
                        (fixture-object-field transaction-by-hash-rpc
                                              "result"))
                      (transaction-by-block-hash-and-index-result
                        (fixture-object-field
                         transaction-by-block-hash-and-index-rpc "result"))
                      (transaction-by-block-number-and-index-result
                        (fixture-object-field
                         transaction-by-block-number-and-index-rpc "result"))
                      (proof-result
                        (fixture-object-field proof-rpc "result"))
                      (proof-storage
                        (first (fixture-object-field proof-result
                                                     "storageProof")))
                      (create-access-list-result
                        (fixture-object-field create-access-list-rpc
                                              "result"))
                      (actual-access-list
                        (fixture-object-field create-access-list-result
                                              "accessList"))
                      (actual-access-list-gas-used
                        (fixture-object-field create-access-list-result
                                              "gasUsed"))
                      (actual-access-list-entry
                        (find (address-to-hex storage-address)
                              actual-access-list
                              :test #'string=
                              :key (lambda (entry)
                                     (fixture-object-field entry "address"))))
                      (actual-access-list-storage-keys
                        (and actual-access-list-entry
                             (fixture-object-field actual-access-list-entry
                                                   "storageKeys")))
                      (safe-block-by-number-result
                        (fixture-object-field safe-block-by-number-rpc
                                              "result"))
                      (finalized-block-by-number-result
                        (fixture-object-field finalized-block-by-number-rpc
                                              "result"))
                      (post-status-block-by-number-result
                        (fixture-object-field post-status-block-by-number-rpc
                                              "result"))
                      (receipt
                        (fixture-object-field receipt-rpc "result"))
                      (receipt-logs
                        (fixture-object-field receipt "logs"))
                      (receipt-log (first receipt-logs))
                      (block-receipts
                        (fixture-object-field block-receipts-rpc "result"))
                      (block-receipt (first block-receipts))
                      (block-receipt-logs
                        (fixture-object-field block-receipt "logs"))
                      (block-receipt-log (first block-receipt-logs))
                      (filtered-logs
                        (fixture-object-field logs-rpc "result"))
                      (filtered-log (first filtered-logs))
                      (block-hash-filtered-logs
                        (fixture-object-field logs-by-block-hash-rpc
                                              "result"))
                      (block-hash-filtered-log
                        (first block-hash-filtered-logs))
                      (expected-prepared-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header child-block)))))
                      (expected-post-reorg-pending-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header side-sibling-block))))))
                 (is (= 601 (fixture-object-field new-payload-rpc "id")))
                 (is (= 602 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 603 (fixture-object-field block-number-rpc "id")))
                 (is (= 604 (fixture-object-field balance-rpc "id")))
                 (is (= 605 (fixture-object-field prepare-payload-rpc "id")))
                 (is (= 606 (fixture-object-field get-payload-rpc "id")))
                 (is (= 607 (fixture-object-field
                              transaction-count-rpc "id")))
                 (is (= 608 (fixture-object-field block-by-number-rpc "id")))
                 (is (= 609 (fixture-object-field
                              payload-bodies-by-hash-rpc "id")))
                 (is (= 610 (fixture-object-field
                              payload-bodies-by-range-rpc "id")))
                 (is (= 611 (fixture-object-field code-rpc "id")))
                 (is (= 612 (fixture-object-field storage-rpc "id")))
                 (is (= 613 (fixture-object-field remote-payload-rpc "id")))
                 (is (= 614 (fixture-object-field invalid-payload-rpc "id")))
                 (is (= 647 (fixture-object-field
                              side-sibling-payload-rpc "id")))
                 (is (= 648 (fixture-object-field
                              side-sibling-forkchoice-rpc "id")))
                 (is (= 651 (fixture-object-field
                              post-reorg-block-by-number-rpc "id")))
                 (is (= 652 (fixture-object-field
                              post-reorg-transaction-by-hash-rpc "id")))
                 (is (= 653 (fixture-object-field
                              post-reorg-receipt-rpc "id")))
                 (is (= 654 (fixture-object-field
                              post-reorg-logs-rpc "id")))
                 (is (= 655 (fixture-object-field
                              post-reorg-pending-block-count-rpc "id")))
                 (is (= 656
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc "id")))
                 (is (= 657
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "id")))
                 (is (= 658 (fixture-object-field
                              post-reorg-pending-block-rpc "id")))
                 (is (= 659 (fixture-object-field
                              post-reorg-pending-header-rpc "id")))
                 (is (= 660 (fixture-object-field
                              post-reorg-pending-sender-nonce-rpc "id")))
                 (is (= 615 (fixture-object-field
                              post-status-block-number-rpc "id")))
                 (is (= 616 (fixture-object-field
                              post-status-block-by-number-rpc "id")))
                 (is (= 617 (fixture-object-field receipt-rpc "id")))
                 (is (= 618 (fixture-object-field block-receipts-rpc "id")))
                 (is (= 619 (fixture-object-field logs-rpc "id")))
                 (is (= 620 (fixture-object-field
                              safe-block-by-number-rpc "id")))
                 (is (= 621 (fixture-object-field
                              finalized-block-by-number-rpc "id")))
                 (is (= 622 (fixture-object-field safe-balance-rpc "id")))
                 (is (= 623 (fixture-object-field finalized-balance-rpc "id")))
                 (is (= 624 (fixture-object-field block-by-hash-rpc "id")))
                 (is (= 625 (fixture-object-field
                              block-transaction-count-by-hash-rpc "id")))
                 (is (= 626 (fixture-object-field
                              block-transaction-count-by-number-rpc "id")))
                 (is (= 627 (fixture-object-field
                              transaction-by-hash-rpc "id")))
                 (is (= 628 (fixture-object-field
                              transaction-by-block-hash-and-index-rpc "id")))
                 (is (= 629 (fixture-object-field
                              transaction-by-block-number-and-index-rpc "id")))
                 (is (= 630 (fixture-object-field
                              raw-transaction-by-hash-rpc "id")))
                 (is (= 631 (fixture-object-field
                              raw-transaction-by-block-hash-and-index-rpc
                              "id")))
                 (is (= 632 (fixture-object-field
                              raw-transaction-by-block-number-and-index-rpc
                              "id")))
                 (is (= 633 (fixture-object-field proof-rpc "id")))
                 (is (= 634 (fixture-object-field
                              block-hash-balance-rpc "id")))
                 (is (= 635 (fixture-object-field
                              require-canonical-balance-rpc "id")))
                 (is (= 636 (fixture-object-field call-rpc "id")))
                 (is (= 637 (fixture-object-field estimate-gas-rpc "id")))
                 (is (= 638 (fixture-object-field create-access-list-rpc "id")))
                 (is (= 639 (fixture-object-field post-call-storage-rpc "id")))
                 (is (= 640 (fixture-object-field
                              full-block-by-number-rpc "id")))
                 (is (= 641 (fixture-object-field
                              full-block-by-hash-rpc "id")))
                 (is (= 642 (fixture-object-field
                              logs-by-block-hash-rpc "id")))
                 (is (= 643 (fixture-object-field
                              new-block-filter-rpc "id")))
                 (is (= 644 (fixture-object-field
                              block-filter-changes-rpc "id")))
                 (is (= 645 (fixture-object-field
                              new-log-filter-rpc "id")))
                 (is (= 646 (fixture-object-field
                              log-filter-changes-rpc "id")))
                 (is (= 649 (fixture-object-field
                              post-reorg-block-filter-changes-rpc "id")))
                 (is (= 650 (fixture-object-field
                              post-reorg-log-filter-changes-rpc "id")))
                 (is (string= "0x1"
                              (fixture-object-field
                               new-block-filter-rpc "result")))
                 (is (string= "0x2"
                              (fixture-object-field
                               new-log-filter-rpc "result")))
                 (is (= 1 (length block-filter-changes)))
                 (is (string= block-hash-hex (first block-filter-changes)))
                 (is (= (length receipt-logs) (length log-filter-changes)))
                 (is (= 1 (length post-reorg-block-filter-changes)))
                 (is (string= side-sibling-block-hash-hex
                              (first post-reorg-block-filter-changes)))
                 (is (= (length receipt-logs)
                        (length post-reorg-log-filter-changes)))
                 (dolist (removed-log post-reorg-log-filter-changes)
                   (is (eq t (fixture-object-field removed-log "removed")))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field removed-log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field removed-log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field removed-log "topics")))
                   (is (string= block-hash-hex
                                (fixture-object-field removed-log
                                                      "blockHash"))))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-payload-result "status")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               side-sibling-payload-result
                               "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-forkchoice-status
                               "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "hash")))
                 (is (equal '()
                            (fixture-object-field
                             post-reorg-block-by-number-result
                             "transactions")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-transaction-by-hash-result
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "transactionIndex")))
                 (is (string= "0x1" post-reorg-pending-block-count))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-transaction-by-index
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "transactionIndex")))
                 (is (string= raw-transaction-hex
                              post-reorg-pending-raw-transaction-by-index))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-block "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block "parentHash")))
                 (is (= 1 (length post-reorg-pending-block-transactions)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block-transaction
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "transactionIndex")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-header "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-header "parentHash")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              post-reorg-pending-sender-nonce))
                 (is (null (fixture-object-field
                            post-reorg-receipt-rpc "result")))
                 (is (null post-reorg-logs))
                 (is (= 1 (length payload-bodies-by-hash-result)))
                 (is (= 1 (length payload-bodies-by-range-result)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-hash-transactions)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-range-transactions)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field prepare-payload-status
                                                    "status")))
                 (is (and (stringp prepared-payload-id)
                          (= 18 (length prepared-payload-id))))
                 (is (not (fixture-object-field get-payload-rpc "error")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               get-payload-execution-payload
                               "parentHash")))
                 (is (string= expected-prepared-block-number
                              (fixture-object-field
                               get-payload-execution-payload
                               "blockNumber")))
                 (is (and (listp get-payload-transactions)
                          (null get-payload-transactions)))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field remote-payload-result
                                                    "status")))
                 (is (null (fixture-object-field remote-payload-result
                                                 "latestValidHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field invalid-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field invalid-payload-result
                                                    "latestValidHash")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field invalid-payload-result
                                                    "validationError")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-number-rpc
                               "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field safe-balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field finalized-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field block-hash-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field
                               require-canonical-balance-rpc "result")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              (fixture-object-field transaction-count-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-number-result
                                                    "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field block-by-number-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-number-result
                                                  "transactions")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-hash-result
                                                    "number")))
                 (is (string= block-hash-hex
                              (fixture-object-field block-by-hash-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-hash-result
                                                  "transactions")))
                 (dolist (full-block-result
                          (list full-block-by-number-result
                                full-block-by-hash-result))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-result
                                                      "number")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-result
                                                      "hash"))))
                 (dolist (transactions
                          (list full-block-by-number-transactions
                                full-block-by-hash-transactions))
                   (is (= 1 (length transactions))))
                 (dolist (full-block-transaction
                          (list full-block-by-number-transaction
                                full-block-by-hash-transaction))
                   (is (string= transaction-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-transaction
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field full-block-transaction
                                                      "transactionIndex"))))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-hash-rpc
                               "result")))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-number-rpc
                               "result")))
                 (dolist (transaction-result
                          (list transaction-by-hash-result
                                transaction-by-block-hash-and-index-result
                                transaction-by-block-number-and-index-result))
                   (is (string= transaction-hash-hex
                                (fixture-object-field transaction-result
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field transaction-result
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field transaction-result
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field transaction-result
                                                      "transactionIndex"))))
                 (is (string= raw-transaction-hex
                              (fixture-object-field raw-transaction-by-hash-rpc
                                                    "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-hash-and-index-rpc
                               "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-number-and-index-rpc
                               "result")))
                 (is (string= (address-to-hex storage-address)
                              (fixture-object-field proof-result "address")))
                 (is (listp (fixture-object-field proof-result
                                                  "accountProof")))
                 (is (string= (fixture-object-field expect "storageKey")
                              (fixture-object-field proof-storage "key")))
                 (is (string= (quantity-to-hex
                               (hex-to-quantity
                                (fixture-object-field expect "storageValue")))
                              (fixture-object-field proof-storage "value")))
                 (is (listp (fixture-object-field proof-storage "proof")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               safe-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               safe-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               finalized-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               finalized-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               post-status-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field expect "code")
                              (fixture-object-field code-rpc "result")))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field storage-rpc "result")))
                 (is (not (fixture-object-field call-rpc "error")))
                 (is (string= "0x"
                              (fixture-object-field call-rpc "result")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field estimate-gas-rpc "result"))))
                 (is (stringp actual-access-list-gas-used))
                 (is actual-access-list-entry)
                 (is (member (fixture-object-field expect "storageKey")
                             actual-access-list-storage-keys
                             :test #'string=))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field post-call-storage-rpc
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field receipt "blockNumber")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field receipt "blockHash")))
                 (is (string= (fixture-object-field expect "receiptType")
                              (fixture-object-field receipt "type")))
                 (is (string= (fixture-object-field expect "receiptStatus")
                              (fixture-object-field receipt "status")))
                 (is (= (hex-to-quantity
                         (fixture-object-field expect "logCount"))
                        (length receipt-logs)))
                 (is (= 1 (length block-receipts)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field block-receipt
                                                    "transactionHash")))
                 (is (= (length receipt-logs) (length block-receipt-logs)))
                 (is (= (length receipt-logs) (length filtered-logs)))
                 (is (= (length receipt-logs)
                        (length block-hash-filtered-logs)))
                 (dolist (log (list receipt-log block-receipt-log
                                    filtered-log block-hash-filtered-log
                                    log-filter-change-log))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field log "topics")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field log "transactionHash")))
                   (is (string= (hash32-to-hex (block-hash child-block))
                                (fixture-object-field log "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field log "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field log
                                                      "transactionIndex")))
                   (is (string= "0x0"
                                (fixture-object-field log "logIndex"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (= (fixture-quantity-field parent "number")
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is (string= (hash32-to-hex (block-hash parent-block))
                                    (fixture-object-field stdout-summary
                                                          "headHash")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= side-sibling-block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "10"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "50"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "60"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-restores-imported-database-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-genesis" "json"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-chain" "sexp"))
        (first-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-first-ready" "json"))
        (first-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "log"))
        (first-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "pid"))
        (second-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-second-ready" "json"))
        (second-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "log"))
        (second-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (transaction (first (block-transactions child-block)))
                (block-hash-hex (hash32-to-hex (block-hash child-block)))
                (transaction-hash-hex
                  (hash32-to-hex (transaction-hash transaction)))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 801 payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    802 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 803)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                804 recipient)))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 805)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 806)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--database"
                        (namestring database-path)
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring first-ready-path)
                        "--log-file"
                        (namestring first-log-path)
                        "--pid-file"
                        (namestring first-pid-path)
                        "--max-connections"
                        "100"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file first-ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file first-ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file first-ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string first-ready-path)))
                    (pid (devnet-cli-pid-file-process-id first-pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    receipt-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (handler-case
                   (progn
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body)))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body)))
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       receipt-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (receipt
                        (fixture-object-field receipt-rpc "result")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= block-hash-hex
                              (fixture-object-field receipt
                                                    "blockHash"))))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill" "-TERM" (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (search
                        "Devnet shutdown requested; closing RPC listeners."
                        stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records
                              (devnet-cli-file-forms first-log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (= (block-header-number
                               (block-header parent-block))
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "3"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))
             (is (probe-file database-path))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--database"
                          (namestring database-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--ready-file"
                          (namestring second-ready-path)
                          "--log-file"
                          (namestring second-log-path)
                          "--pid-file"
                          (namestring second-pid-path)
                          "--max-connections"
                          "100"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file second-ready-path 10)
               (when (uiop:process-alive-p process)
                 (uiop:terminate-process process)
                 (devnet-cli-wait-process-exit process 5))
               (let ((stdout
                       (devnet-cli-read-stream-string
                        (uiop:process-info-output process)))
                     (stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (when (search "Operation not permitted" stderr)
                   (skip-test
                    "Local socket bind is not permitted in this sandbox"))
                 (is (probe-file second-ready-path))
                 (is (string= "" stdout))
                 (is (string= "" stderr))))
             (when (probe-file second-ready-path)
               (let* ((ready-summary
                        (parse-json
                         (devnet-cli-file-string second-ready-path)))
                      (pid (devnet-cli-pid-file-process-id second-pid-path))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      block-number-response
                      balance-response
                      block-by-hash-response
                      receipt-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
                 (is (string= (namestring database-path)
                              (fixture-object-field ready-summary
                                                    "databasePath")))
                 (is (= (fixture-quantity-field payload-case "number")
                        (fixture-object-field ready-summary "headNumber")))
                 (is (string= block-hash-hex
                              (fixture-object-field ready-summary
                                                    "headHash")))
                 (handler-case
                     (progn
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               balance-body)))
                       (setf block-by-hash-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-by-hash-body)))
                       (setf receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response (list block-number-response
                                         balance-response
                                         block-by-hash-response
                                         receipt-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (balance-rpc
                          (parse-json
                           (devnet-cli-http-body balance-response)))
                        (block-by-hash-rpc
                          (parse-json
                           (devnet-cli-http-body block-by-hash-response)))
                        (block-by-hash-result
                          (fixture-object-field block-by-hash-rpc "result"))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body receipt-response)))
                        (receipt
                          (fixture-object-field receipt-rpc "result")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field block-number-rpc
                                                      "result")))
                   (is (string= (fixture-object-field expect
                                                      "recipientBalance")
                                (fixture-object-field balance-rpc
                                                      "result")))
                   (is (string= block-hash-hex
                                (fixture-object-field block-by-hash-result
                                                      "hash")))
                   (is (equal (list transaction-hash-hex)
                              (fixture-object-field block-by-hash-result
                                                    "transactions")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field receipt
                                                      "transactionHash")))
                   (is (string= block-hash-hex
                                (fixture-object-field receipt
                                                      "blockHash"))))
                 (multiple-value-bind (kill-stdout kill-stderr kill-status)
                     (uiop:run-program
                      (list "kill" "-TERM" (write-to-string pid))
                      :output :string
                      :error-output :string
                      :ignore-error-status t)
                   (is (= 0 kill-status))
                   (is (string= "" kill-stdout))
                   (is (string= "" kill-stderr)))
                 (let ((status (devnet-cli-wait-process-exit process 10)))
                   (when (eq status :timeout)
                     (uiop:terminate-process process))
                   (is (not (eq status :timeout)))
                   (is (and (numberp status) (= 0 status)))
                   (let ((stdout
                           (devnet-cli-read-stream-string
                            (uiop:process-info-output process)))
                         (stderr
                           (devnet-cli-read-stream-string
                            (uiop:process-info-error-output process))))
                     (is (search
                          "Devnet shutdown requested; closing RPC listeners."
                          stderr))
                     (when (and (numberp status) (= 0 status))
                       (let* ((stdout-summary (parse-json stdout))
                              (log-records
                                (devnet-cli-file-forms second-log-path))
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (= (fixture-quantity-field payload-case
                                                        "number")
                                (fixture-object-field stdout-summary
                                                      "headNumber")))
                         (is (string= block-hash-hex
                                      (fixture-object-field stdout-summary
                                                            "headHash")))
                         (is shutdown-record)
                         (is (string= (fixture-object-field payload-case
                                                            "number")
                                      (cdr (assoc "headNumber"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= block-hash-hex
                                      (cdr (assoc "headHash"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path
                          genesis-path
                          database-path
                          first-ready-path
                          first-log-path
                          first-pid-path
                          second-ready-path
                          second-log-path
                          second-pid-path))
        (when (probe-file path)
          (delete-file path)))))

(deftest ethereum-lisp-script-serve-mode-honors-runner-http-shaping
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "jwt"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-http-shape-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "pid"))
        (coinbase "0x00000000000000000000000000000000000000cb")
        (process nil))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--http.rpcprefix"
                        "/rpc"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--http.vhosts"
                        "public.runner,localhost"
                        "--http.corsdomain"
                        "https://runner.example"
                        "--http.api"
                        "eth,net"
                        "--networkid"
                        "4242"
                        "--miner.etherbase"
                        coinbase
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "11"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":601,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"shape-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-chain-body
                      "{\"jsonrpc\":\"2.0\",\"id\":602,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":603,\"method\":\"net_version\",\"params\":[]}")
                    (public-coinbase-body
                      "{\"jsonrpc\":\"2.0\",\"id\":607,\"method\":\"eth_coinbase\",\"params\":[]}")
                    (public-web3-body
                      "{\"jsonrpc\":\"2.0\",\"id\":604,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":605,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-txpool-body
                      "{\"jsonrpc\":\"2.0\",\"id\":606,\"method\":\"txpool_status\",\"params\":[]}")
                    engine-prefixed-response
                    engine-preflight-response
                    engine-root-response
                    engine-blocked-host-response
                    engine-unsupported-method-response
                    engine-unsupported-content-type-response
                    public-prefixed-response
                    public-net-response
                    public-coinbase-response
                    public-rpc-modules-response
                    public-blocked-host-response
                    public-root-response
                    public-web3-response
                    public-txpool-response
                    public-preflight-response
                    public-unsupported-method-response
                    public-unsupported-content-type-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (dolist (summary-field
                         '(("engineRpcPrefix" . "/engine")
                           ("publicRpcPrefix" . "/rpc")))
                 (is (string= (cdr summary-field)
                              (fixture-object-field
                               ready-summary
                               (car summary-field)))))
               (is (= 4242 (fixture-object-field ready-summary "networkId")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           ready-summary "publicApiModules")))
               (is (string= coinbase
                            (fixture-object-field ready-summary "coinbase")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field
                           ready-summary "engineCorsOrigins")))
               (is (equal '("https://runner.example")
                          (fixture-object-field
                           ready-summary "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "publicVhosts")))
               (handler-case
                   (progn
                     (setf engine-prefixed-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :token token)))
                     (setf engine-preflight-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-options-http-request
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "authorization, content-type")))))
                     (setf engine-root-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/"
                             :host "engine.runner"
                             :token token)))
                     (setf engine-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "blocked.engine"
                             :token token)))
                     (setf engine-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf engine-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf public-prefixed-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example")))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-coinbase-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-coinbase-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "blocked.public")))
                     (setf public-root-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/"
                             :host "public.runner")))
                     (setf public-web3-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-web3-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-txpool-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-txpool-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-preflight-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-options-http-request
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "content-type")))))
                     (setf public-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body))))
                     (setf public-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-prefixed-response))
               (is (= 204 (devnet-cli-http-status engine-preflight-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-preflight-response))
               (is (= 404 (devnet-cli-http-status engine-root-response)))
               (is (= 403
                      (devnet-cli-http-status
                       engine-blocked-host-response)))
               (is (= 405
                      (devnet-cli-http-status
                       engine-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            engine-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       engine-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            engine-unsupported-content-type-response)))
               (is (= 200 (devnet-cli-http-status public-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://runner.example"
                           public-prefixed-response))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (is (= 200 (devnet-cli-http-status public-coinbase-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-rpc-modules-response)))
               (is (= 403
                      (devnet-cli-http-status
                       public-blocked-host-response)))
               (is (= 404 (devnet-cli-http-status public-root-response)))
               (is (= 200 (devnet-cli-http-status public-web3-response)))
               (is (= 200 (devnet-cli-http-status public-txpool-response)))
               (is (= 204 (devnet-cli-http-status public-preflight-response)))
               (is (= 405
                      (devnet-cli-http-status
                       public-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            public-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       public-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            public-unsupported-content-type-response)))
               (let* ((engine-json
                        (parse-json
                         (devnet-cli-http-body engine-prefixed-response)))
                      (public-json
                        (parse-json
                         (devnet-cli-http-body public-prefixed-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (public-coinbase-json
                        (parse-json
                         (devnet-cli-http-body public-coinbase-response)))
                      (public-rpc-modules-json
                        (parse-json
                         (devnet-cli-http-body
                          public-rpc-modules-response)))
                      (public-web3-json
                        (parse-json
                         (devnet-cli-http-body public-web3-response)))
                      (public-txpool-json
                        (parse-json
                         (devnet-cli-http-body public-txpool-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result")))
                      (public-modules
                        (fixture-object-field
                         public-rpc-modules-json "result")))
                 (is (= 601 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 602 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 603 (fixture-object-field public-net-json "id")))
                 (is (string= "4242"
                              (fixture-object-field
                               public-net-json "result")))
                 (is (= 607
                        (fixture-object-field public-coinbase-json "id")))
                 (is (string= coinbase
                              (fixture-object-field
                               public-coinbase-json "result")))
                 (is (= 605
                        (fixture-object-field public-rpc-modules-json "id")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "eth")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "net")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "rpc")))
                 (is (not (fixture-object-field public-modules "txpool")))
                 (is (not (fixture-object-field public-modules "web3")))
                 (is (= 604 (fixture-object-field public-web3-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-web3-json "error")
                         "code")))
                 (is (= 606 (fixture-object-field public-txpool-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-txpool-json "error")
                         "code"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name)))))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (equal '("eth" "net")
                                    (fixture-object-field
                                     summary "publicApiModules")))
                         (is (string= coinbase
                                      (fixture-object-field
                                       summary "coinbase")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("https://runner.example")
                                    (fixture-object-field
                                     summary "publicCorsOrigins"))))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= "/engine"
                                        (cdr (assoc "engineRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "/rpc"
                                        (cdr (assoc "publicRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "eth,net"
                                        (cdr (assoc "publicApiModules" fields
                                                    :test #'string=))))
                           (is (string= coinbase
                                        (cdr (assoc "coinbase" fields
                                                    :test #'string=))))
                           (is (string= "https://engine.runner"
                                        (cdr (assoc "engineCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "https://runner.example"
                                        (cdr (assoc "publicCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "engine.runner,localhost"
                                        (cdr (assoc "engineVhosts" fields
                                                    :test #'string=))))
                           (is (string= "public.runner,localhost"
                                        (cdr (assoc "publicVhosts" fields
                                                    :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "6"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "11"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "17"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-honors-http-false-engine-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (case
          (select-engine-newpayload-v2-fixture-case
           +engine-newpayload-v2-fixture-path+
           "shanghai-one-transfer-with-withdrawal"))
        (parent-block (devnet-cli-engine-fixture-parent-block case))
        (child-block (devnet-cli-engine-fixture-child-block case))
        (payload
          (execution-payload-envelope-execution-payload
           (block-to-executable-data child-block)))
        (payload-case (fixture-object-field case "payload"))
        (block-hash-hex (hash32-to-hex (block-hash child-block)))
        (new-payload-body
          (json-encode (engine-fixture-payload-request 702 payload)))
        (forkchoice-body
          (json-encode
           (devnet-cli-engine-forkchoice-v2-request
            703
            (block-hash child-block)
            :safe (block-hash parent-block)
            :finalized (block-hash parent-block))))
        (capabilities-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 704)
            (cons "method" "engine_exchangeCapabilities")
            (cons "params"
                  (list
                   (list
                    "engine_newPayloadV1"
                    "engine_forkchoiceUpdatedV1"
                    "engine_getPayloadV1"
                    "engine_newPayloadV2"
                    "engine_forkchoiceUpdatedV2"
                    "engine_getPayloadV2"))))))
        (transition-configuration-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 705)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x0")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (transition-configuration-mismatch-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 706)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x1")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-genesis" "json"))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "log"))
	        (pid-path
	          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "pid"))
	        (database-path
	          (devnet-cli-temp-path
	           "ethereum-lisp-script-engine-only-chain" "sexp"))
	        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
	                        "--pid-file"
	                        (namestring pid-path)
	                        "--database"
	                        (namestring database-path)
	                        "--max-connections"
	                        "7"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":701,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"engine-only-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :host "engine.runner"
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :host "engine.runner"
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-response))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc
                         "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc
                         "error"))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 701 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 704 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 705 (fixture-object-field
                              transition-configuration-rpc
                              "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= (hash32-to-hex (zero-hash32))
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 706 (fixture-object-field
                              transition-configuration-mismatch-rpc
                              "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (ready-fields (getf ready-record :fields))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("engine.runner" "localhost")
                                    (fixture-object-field
                                     summary "engineVhosts"))))
                       (is ready-record)
                       (is shutdown-record)
                       (dolist (fields (list ready-fields shutdown-fields))
                         (is (string= engine-endpoint
                                      (cdr (assoc "engineEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "/engine"
                                      (cdr (assoc "engineRpcPrefix"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "https://engine.runner"
                                      (cdr (assoc "engineCorsOrigins"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "engine.runner,localhost"
                                      (cdr (assoc "engineVhosts"
                                                  fields
                                                  :test #'string=))))
                         (is (string= ""
                                      (cdr (assoc "rpcEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "false"
                                      (cdr (assoc "publicRpcEnabled"
                                                  fields
                                                  :test #'string=)))))
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
	                       (is (string= "7"
	                                    (cdr (assoc "totalConnections"
	                                                shutdown-fields
	                                                :test #'string=))))
	                       (multiple-value-bind
	                             (restore-stdout restore-stderr
	                              restore-status)
	                           (uiop:run-program
	                            (list "sbcl"
	                                  "--script"
	                                  script
	                                  "--"
	                                  "devnet"
	                                  "--genesis"
	                                  (namestring genesis-path)
	                                  "--database"
	                                  (namestring database-path)
	                                  "--http=false"
	                                  "--no-serve"
	                                  "--json")
	                            :directory #P"/private/tmp/"
	                            :output :string
	                            :error-output :string
	                            :ignore-error-status t)
	                         (is (= 0 restore-status))
	                         (is (string= "" restore-stderr))
	                         (when (= 0 restore-status)
	                           (let ((restore-summary
	                                   (parse-json restore-stdout)))
	                             (is (string= (namestring database-path)
	                                          (fixture-object-field
	                                           restore-summary
	                                           "databasePath")))
	                             (is (= (fixture-quantity-field
	                                     payload-case "number")
	                                    (fixture-object-field
	                                     restore-summary "headNumber")))
	                             (is (string= block-hash-hex
	                                          (fixture-object-field
	                                           restore-summary "headHash")))
	                             (is (fixture-object-field
	                                  restore-summary "stateAvailable"))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "publicRpcEnabled")))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "rpcEndpoint")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
	      (dolist (path (list genesis-path jwt-path ready-path log-path
	                          pid-path database-path))
	        (when (probe-file path)
	          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-split-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 813)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 814)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 815)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "jwt"))
        (config-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split"
                                "toml"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-split-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file config-path
                                       "# runner config placeholder\n")
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--config"
                        (namestring config-path)
                        "--dev"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "4"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":811,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-split-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":812,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":816,\"method\":\"net_version\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":817,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":818,\"method\":\"rpc_modules\",\"params\":[]}")
                    engine-response
                    public-response
                    public-net-version-response
                    public-client-version-response
                    public-rpc-modules-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-body
                             :target "/rpc")))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body
                             :target "/rpc")))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body
                             :target "/rpc")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (dolist (response (list public-response
                                       public-net-version-response
                                       public-client-version-response
                                       public-rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (public-rpc
                        (parse-json (devnet-cli-http-body public-response))))
                 (is (= 811 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 812 (fixture-object-field public-rpc "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-rpc "result"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 813 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 814
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 815
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= rpc-endpoint
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "true"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "8"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path config-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-split-imports-payload
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x5555555555555555555555555555555555555555555555555555555555555555")
         (case
           (select-engine-newpayload-v2-fixture-case
            +engine-newpayload-v2-fixture-path+
            "shanghai-one-transfer-with-withdrawal"))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
         (child-block (devnet-cli-engine-fixture-child-block case))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (payload-case (fixture-object-field case "payload"))
         (expect (fixture-object-field case "expect"))
         (recipient (fixture-address-field expect "recipient"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 819)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 820)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 825)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 821 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             822
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (block-number-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 823)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 824 recipient)))
         (net-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 826)
                  (cons "method" "net_version")
                  (cons "params" '()))))
         (client-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 827)
                  (cons "method" "web3_clientVersion")
                  (cons "params" '()))))
         (rpc-modules-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 828)
                  (cons "method" "rpc_modules")
                  (cons "params" '()))))
         (genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-genesis" "json"))
         (jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "jwt"))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-ready" "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "pid"))
         (database-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "db"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--database"
                        (namestring database-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "5"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    net-version-response
                    client-version-response
                    rpc-modules-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :target "/engine")))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body
                             :target "/rpc")))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body
                             :target "/rpc")))
                     (setf net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             net-version-body
                             :target "/rpc")))
                     (setf client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             client-version-body
                             :target "/rpc")))
                     (setf rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list capabilities-response
                                       transition-configuration-response
                                       transition-configuration-mismatch-response
                                       new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       net-version-response
                                       client-version-response
                                       rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 819 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 820
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 825
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (net-version-rpc
                        (parse-json
                         (devnet-cli-http-body net-version-response)))
                      (client-version-rpc
                        (parse-json
                         (devnet-cli-http-body client-version-response)))
                      (rpc-modules-rpc
                        (parse-json
                         (devnet-cli-http-body rpc-modules-response))))
                 (is (= 821 (fixture-object-field new-payload-rpc "id")))
                 (is (= 822 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 823 (fixture-object-field block-number-rpc "id")))
                 (is (= 824 (fixture-object-field balance-rpc "id")))
                 (is (= 826 (fixture-object-field net-version-rpc "id")))
                 (is (= 827 (fixture-object-field client-version-rpc "id")))
                 (is (= 828 (fixture-object-field rpc-modules-rpc "id")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc "result")))
                 (is (string= "1"
                              (fixture-object-field net-version-rpc "result")))
                 (is (search "ethereum-lisp/"
                             (fixture-object-field
                              client-version-rpc "result")))
                 (is (fixture-object-field
                      (fixture-object-field rpc-modules-rpc "result")
                      "eth")))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (string= (namestring database-path)
                                      (fixture-object-field
                                       summary "databasePath"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "10"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (probe-file database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--genesis"
                                  (namestring genesis-path)
                                  "--database"
                                  (namestring database-path)
                                  "--authrpc.rpcprefix"
                                  "/engine"
                                  "--http"
                                  "--http.rpcprefix"
                                  "/rpc"
                                  "--no-serve"
                                  "--json")
                            :directory #P"/private/tmp/"
                            :output :string
                            :error-output :string
                            :ignore-error-status t)
                         (is (= 0 restore-status))
                         (is (string= "" restore-stderr))
                         (when (= 0 restore-status)
                           (let ((restore-summary
                                   (parse-json restore-stdout)))
                             (is (string= (namestring database-path)
                                          (fixture-object-field
                                           restore-summary
                                           "databasePath")))
                             (is (= (fixture-quantity-field
                                     payload-case "number")
                                    (fixture-object-field
                                     restore-summary "headNumber")))
                             (is (string= block-hash-hex
                                          (fixture-object-field
                                           restore-summary "headHash")))
                             (is (fixture-object-field
                                  restore-summary "stateAvailable"))
                             (is (fixture-object-field
                                  restore-summary "publicRpcEnabled"))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))
                             (is (string= "/rpc"
                                          (fixture-object-field
                                           restore-summary
                                           "publicRpcPrefix")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list genesis-path jwt-path ready-path log-path pid-path
                          database-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-engine-only-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x3333333333333333333333333333333333333333333333333333333333333333")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 802)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 803)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 804)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--dev"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "5"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":801,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result"))))
                 (is (= 801 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 802 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 803
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 804
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= ""
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "false"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

(defun devnet-cli-assert-script-signal-shutdown
    (signal-name temp-name &key engine-only-p)
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A-ready" temp-name)
           "json"))
        (log-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "log"))
        (pid-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "pid"))
        (process nil))
    (unwind-protect
         (progn
           (setf process
                 (uiop:launch-program
                  (append
                   (list "sbcl"
                         "--script"
                         script
                         "--"
                         "devnet"
                         "--genesis"
                         genesis
                         "--engine-port"
                         "0"
                         "--public-port"
                         "0")
                   (when engine-only-p
                     (list "--http=false"))
                   (list "--ready-file"
                         (namestring ready-path)
                         "--log-file"
                         (namestring log-path)
                         "--pid-file"
                         (namestring pid-path)
                         "--json"))
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path)))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill"
                          (format nil "-~A" signal-name)
                          (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                   (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (search "Devnet shutdown requested; closing RPC listeners."
                               stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (log-names
                              (mapcar (lambda (record) (getf record :name))
                                      log-records))
                            (engine-endpoint
                              (fixture-object-field stdout-summary
                                                    "engineEndpoint"))
                            (rpc-endpoint
                              (fixture-object-field stdout-summary
                                                    "rpcEndpoint")))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= genesis
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field ready-summary
                                                          "engineEndpoint")))
                       (if engine-only-p
                           (progn
                             (is (not rpc-endpoint))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "rpcEndpoint")))
                             (is (not (fixture-object-field
                                       stdout-summary
                                       "publicRpcEnabled")))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "publicRpcEnabled"))))
                           (progn
                             (is (string= rpc-endpoint
                                          (fixture-object-field ready-summary
                                                                "rpcEndpoint")))
                             (is (fixture-object-field
                                  stdout-summary
                                  "publicRpcEnabled"))
                             (is (fixture-object-field
                                  ready-summary
                                  "publicRpcEnabled"))))
                       (is (not (string= "127.0.0.1:0" engine-endpoint)))
                       (unless engine-only-p
                         (is (not (string= "127.0.0.1:0" rpc-endpoint))))
                       (is (member "devnet.ready" log-names :test #'string=))
                       (is (member "devnet.shutdown" log-names :test #'string=))
                       (dolist (log-record log-records)
                         (when (member (getf log-record :name)
                                       '("devnet.ready" "devnet.shutdown")
                                       :test #'string=)
                           (let ((fields (getf log-record :fields)))
                             (is (string= engine-endpoint
                                          (cdr (assoc "engineEndpoint"
                                                      fields
                                                      :test #'string=))))
                             (if engine-only-p
                                 (progn
                                   (is (string= ""
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "false"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=)))))
                                 (progn
                                   (is (string= rpc-endpoint
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "true"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=))))))
                             (is (string= (if (string= "devnet.ready"
                                                        (getf log-record :name))
                                               "ready"
                                               "shutdown")
                                          (cdr (assoc "lifecyclePhase"
                                                      fields
                                                      :test #'string=))))
                             (is (string= (write-to-string pid)
                                          (cdr (assoc "processId"
                                                      fields
                                                      :test #'string=))))
                             (is (string= "0"
                                          (cdr (assoc "totalConnections"
                                                      fields
                                                      :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest ethereum-lisp-script-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "TERM" "sigterm"))

(deftest ethereum-lisp-script-serve-mode-handles-sigint-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "INT" "sigint"))

(deftest ethereum-lisp-script-engine-only-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown
   "TERM"
   "engine-only-sigterm"
   :engine-only-p t))

(defun devnet-cli-assert-script-error-telemetry
    (args error-substring &key
          (event-name "devnet.error")
          (usage-substring "Usage: ethereum-lisp devnet"))
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-error" "log")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (append (list "sbcl" "--script" script "--")
                      args
                      (list "--log-file" (namestring log-path)))
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 1 status))
           (is (string= "" stdout))
           (is (search error-substring stderr))
           (is (search usage-substring stderr))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields))
                  (process-id
                    (parse-integer
                     (cdr (assoc "processId" fields :test #'string=))
                     :junk-allowed nil)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= event-name (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (plusp process-id))
             (is (not (= (devnet-cli-current-process-id) process-id)))
             (is (search error-substring
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= (namestring log-path)
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest ethereum-lisp-script-records-runner-error-telemetry
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (init-datadir
          (devnet-cli-temp-directory
           "ethereum-lisp-script-init-jwt-error-datadir"))
        (bad-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-bad-jwt" "hex"))
        (missing-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-missing-jwt" "hex"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-script-kzg-error" "sh")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file bad-jwt-path "not-hex")
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet" "--json" "--no-serve")
            "--genesis is required")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port"
                  "not-a-port"
                  "--no-serve")
            "--public-port requires an integer value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port")
            "--public-port requires a value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--kzg.verifier-command"
                  (namestring non-executable-kzg-command)
                  "--no-serve")
            "KZG verifier command is not executable")
           (devnet-cli-assert-script-error-telemetry
            (list "init" "--json")
            "init requires a genesis file"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init")
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init")
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init"))
      (when (probe-file bad-jwt-path)
        (delete-file bad-jwt-path))
      (when (probe-file missing-jwt-path)
        (delete-file missing-jwt-path))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command))
      (when (probe-file init-datadir)
        (ignore-errors
          (uiop:delete-directory-tree init-datadir :validate t))))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))

(deftest devnet-cli-boolean-flag-values-affect-semantic-flags
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=false"
                 "--no-serve=0"
                 "--http=true"
                 "--graphql=0"
                 "--nodiscover=0"
                 "--ipcdisable=1"
                 "--mine=false"
                 "--dev=false"
                 "--metrics=0"
                 "--pprof=false"
                 "--snapshot"
                 "false")))
         (enabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=1"
                 "--no-serve=true"
                 "--http=false"
                 "--dev"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (getf disabled :serve-p))
    (is (getf disabled :public-rpc-enabled-p))
    (is (not (getf disabled :dev-mode-p)))
    (is (eq :json (getf enabled :summary-format)))
    (is (not (getf enabled :serve-p)))
    (is (not (getf enabled :public-rpc-enabled-p)))
    (is (getf enabled :dev-mode-p))))

(deftest devnet-cli-init-json-boolean-values-affect-summary-format
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json=false")))
        (enabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json" "1"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (eq :json (getf enabled :summary-format)))))

(deftest devnet-cli-init-rejects-malformed-json-boolean-before-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "init" "--json=maybe")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--json boolean value must be true or false" stderr))
      (is (search "Usage: ethereum-lisp init" stderr)))))

(deftest devnet-cli-accepts-geth-style-mining-archive-and-metrics-flags
  (let ((config-path
          (devnet-cli-temp-path "ethereum-lisp-geth" "toml")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for flag coverage\n")
           (let ((options
                   (ethereum-lisp.cli::devnet-cli-options
                    (list "devnet"
                          "--config"
                          (namestring config-path)
                          "--gcmode=archive"
                          "--cache"
                          "256"
                          "--cache.database=64"
                          "--cache.gc"
                          "32"
                          "--cache.trie=160"
                          "--txlookuplimit=0"
                          "--history.transactions"
                          "0"
                          "--bootnodes="
                          "--netrestrict=127.0.0.0/8"
                          "--nodekey=/tmp/ethereum-lisp-nodekey"
                          "--nodekeyhex"
                          "010203"
                          "--discovery.port=30303"
                          "--discovery.dns="
                          "--ipcpath=/tmp/ethereum-lisp.ipc"
                          "--mine=true"
                          "--miner.etherbase"
                          "0x0000000000000000000000000000000000000000"
                          "--etherbase=0x0000000000000000000000000000000000000000"
                          "--miner.gaslimit"
                          "30000000"
                          "--miner.gasprice=0"
                          "--unlock"
                          "0"
                          "--password=/tmp/password"
                          "--allow-insecure-unlock=true"
                          "--metrics=true"
                          "--metrics.addr"
                          "127.0.0.1"
                          "--metrics.port=6060"
                          "--pprof=false"
                          "--pprof.addr"
                          "127.0.0.1"
                          "--pprof.port=6061"
                          "--snapshot=false"
                          "--json"
                          "--no-serve"))))
             (is (eq :json (getf options :summary-format)))
             (is (not (getf options :serve-p)))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-accepts-geth-style-logging-flags
  (let ((options
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--log.file=/tmp/geth.log"
                 "--log.format"
                 "json"
                 "--log.maxsize=64"
                 "--log.maxbackups"
                 "3"
                 "--log.maxage=7"
                 "--log.compress=false"
                 "--log-file=/tmp/ethereum-lisp-events.jsonl"
                 "--json"
                 "--no-serve"))))
    (is (eq :json (getf options :summary-format)))
    (is (not (getf options :serve-p)))
    (is (string= "/tmp/ethereum-lisp-events.jsonl"
                 (getf options :log-file)))))

(deftest devnet-cli-rejects-malformed-options-before-loading-genesis
  (labels ((run-error (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 1
                      (ethereum-lisp.cli:main
                       args
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string output)))
               (get-output-stream-string errors))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port" "abc" "--no-serve"))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port=abc" "--no-serve"))))
    (is (search "--port must be between 0 and 65535"
                (run-error (list "devnet" "--port" "70000" "--no-serve"))))
    (is (search "--public-port requires an integer value"
                (run-error (list "devnet"
                                 "--public-port"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--public-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--public-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "engine"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix=engine"
                                 "--no-serve"))))
    (is (search "--http boolean value must be true or false"
                (run-error (list "devnet"
                                 "--http=maybe"
                                 "--no-serve"))))
    (is (search "--nodiscover boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nodiscover"
                                 "maybe"
                                 "--no-serve"))))
    (is (search "--ws boolean value must be true or false"
                (run-error (list "devnet"
                                 "--ws=maybe"
                                 "--no-serve"))))
    (is (search "--graphql boolean value must be true or false"
                (run-error (list "devnet"
                                 "--graphql=maybe"
                                 "--no-serve"))))
    (is (search "--allow-insecure-unlock boolean value must be true or false"
                (run-error (list "devnet"
                                 "--allow-insecure-unlock=maybe"
                                 "--no-serve"))))
    (is (search "--mine boolean value must be true or false"
                (run-error (list "devnet"
                                 "--mine=maybe"
                                 "--no-serve"))))
    (is (search "--metrics boolean value must be true or false"
                (run-error (list "devnet"
                                 "--metrics=maybe"
                                 "--no-serve"))))
    (is (search "--pprof boolean value must be true or false"
                (run-error (list "devnet"
                                 "--pprof=maybe"
                                 "--no-serve"))))
    (is (search "--snapshot boolean value must be true or false"
                (run-error (list "devnet"
                                 "--snapshot=maybe"
                                 "--no-serve"))))
    (is (search "--log.compress boolean value must be true or false"
                (run-error (list "devnet"
                                 "--log.compress=maybe"
                                 "--no-serve"))))
    (is (search "--rpc.allow-unprotected-txs boolean value must be true or false"
                (run-error (list "devnet"
                                 "--rpc.allow-unprotected-txs=maybe"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficultypassed boolean value must be true or false"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficultypassed=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.nolocals boolean value must be true or false"
                (run-error (list "devnet"
                                 "--txpool.nolocals=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a value"
                (run-error (list "devnet"
                                 "--txpool.locals"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires at least one 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=,"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=not-an-address"
                                 "--no-serve"))))
    (is (search "--dev boolean value must be true or false"
                (run-error (list "devnet"
                                 "--dev=maybe"
                                 "--no-serve"))))
    (is (search "--nousb boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nousb=maybe"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "rpc"
                                 "--no-serve"))))
    (is (search "--max-connections must be non-negative"
                (run-error (list "devnet"
                                 "--max-connections"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--kzg.verifier-timeout requires an integer value"
                (run-error (list "devnet"
                                 "--kzg.verifier-timeout"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--kzg-verifier-timeout must be positive"
                (run-error (list "devnet"
                                 "--kzg-verifier-timeout"
                                 "0"
                                 "--no-serve"))))
    (is (search "--prune-state-before requires an integer value"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--prune-state-before must be non-negative"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis" "--no-serve"))))
    (is (search "--config requires a value"
                (run-error (list "devnet" "--config" "--no-serve"))))
    (is (search "--host requires a value"
                (run-error (list "devnet" "--host" "--no-serve"))))
    (is (search "--engine-host requires a value"
                (run-error (list "devnet" "--engine-host" "--no-serve"))))
    (is (search "--public-host requires a value"
                (run-error (list "devnet" "--public-host" "--no-serve"))))
    (is (search "--port requires a value"
                (run-error (list "devnet" "--port" "--no-serve"))))
    (is (search "--engine-port requires a value"
                (run-error (list "devnet" "--engine-port" "--no-serve"))))
    (is (search "--engine-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--engine-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--public-port requires a value"
                (run-error (list "devnet" "--public-port" "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "--no-serve"))))
    (is (search "--graphql.addr requires a value"
                (run-error (list "devnet"
                                 "--graphql.addr"
                                 "--no-serve"))))
    (is (search "--ws.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--ws.rpcprefix"
                                 "--no-serve"))))
    (is (search "--ipcapi requires a value"
                (run-error (list "devnet"
                                 "--ipcapi"
                                 "--no-serve"))))
    (is (search "--nodekeyhex requires a value"
                (run-error (list "devnet"
                                 "--nodekeyhex"
                                 "--no-serve"))))
    (is (search "--discovery.port requires a value"
                (run-error (list "devnet"
                                 "--discovery.port"
                                 "--no-serve"))))
    (is (search "--ipcpath requires a value"
                (run-error (list "devnet"
                                 "--ipcpath"
                                 "--no-serve"))))
    (is (search "--log.file requires a value"
                (run-error (list "devnet"
                                 "--log.file"
                                 "--no-serve"))))
    (is (search "--http.maxclients requires a value"
                (run-error (list "devnet"
                                 "--http.maxclients"
                                 "--no-serve"))))
    (is (search "--http.readtimeout requires a value"
                (run-error (list "devnet"
                                 "--http.readtimeout"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires a value"
                (run-error (list "devnet"
                                 "--txpool.pricebump"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountslots"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalslots"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime requires a value"
                (run-error (list "devnet"
                                 "--txpool.lifetime"
                                 "--no-serve"))))
    (is (search "--txpool.pricelimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--txpool.pricelimit=abc"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.pricebump=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime duration unit must be one of s, m, h, or d"
                (run-error (list "devnet"
                                 "--txpool.lifetime=1fortnight"
                                 "--no-serve"))))
    (is (search "--dev.period requires a value"
                (run-error (list "devnet"
                                 "--dev.period"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a value"
                (run-error (list "devnet"
                                 "--dev.gaslimit"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--dev.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--miner.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--miner.etherbase=0x1234"
                                 "--no-serve"))))
    (is (search "--sepolia boolean value must be true or false"
                (run-error (list "devnet"
                                 "--sepolia=maybe"
                                 "--no-serve"))))
    (is (search "--etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--etherbase=not-address"
                                 "--no-serve"))))
    (is (search "--db.engine requires a value"
                (run-error (list "devnet"
                                 "--db.engine"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficulty requires a value"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficulty"
                                 "--no-serve"))))
    (is (search "--database requires a value"
                (run-error (list "devnet" "--database"))))
    (is (search "--prune-state-before requires a value"
                (run-error (list "devnet" "--prune-state-before"))))
    (is (search "--log-file requires a value"
                (run-error (list "devnet" "--log-file"))))
    (is (search "--pid-file requires a value"
                (run-error (list "devnet" "--pid-file"))))
    (is (search "Unknown option --wat"
                (run-error (list "devnet" "--wat"))))))
