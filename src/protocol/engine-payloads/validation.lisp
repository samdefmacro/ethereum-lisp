(in-package #:ethereum-lisp.engine-payloads)

(defun engine-new-payload-params-status
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (handler-case
      (let ((block
              (if requests-supplied-p
                  (executable-data-to-block
                   payload
                   :parent-beacon-root parent-beacon-root
                   :versioned-hashes versioned-hashes
                   :requests requests)
                  (executable-data-to-block
                   payload
                   :parent-beacon-root parent-beacon-root
                   :versioned-hashes versioned-hashes))))
        (values
         (make-payload-status :status +payload-status-valid+
                              :latest-valid-hash (block-hash block))
         block))
    (block-validation-error (condition)
      (values
       (make-payload-status
        :status +payload-status-invalid+
        :validation-error (block-validation-error-message condition))
       nil))))

(defun invalid-payload-status (message)
  (make-payload-status :status +payload-status-invalid+
                       :validation-error message))

(defun forkchoice-state-zero-head-status ()
  (invalid-payload-status "forkchoice head block hash is zero"))

(defun engine-block-access-list-envelope-p (bytes)
  "Whether BYTES is exactly one RLP list: a list prefix, canonical in the long
form, whose declared length covers BYTES to the end.  Only the envelope is
checked; the entries are decoded with the block."
  (let ((size (length bytes)))
    (and (plusp size)
         (let ((prefix (aref bytes 0)))
           (cond
             ((< prefix #xc0) nil)
             ((<= prefix #xf7) (= size (1+ (- prefix #xc0))))
             (t
              (let ((length-size (- prefix #xf7)))
                (and (> size length-size)
                     (plusp (aref bytes 1))
                     (let ((content-size
                             (loop with value = 0
                                   for index from 1 to length-size
                                   do (setf value (+ (* value 256)
                                                     (aref bytes index)))
                                   finally (return value))))
                       (and (> content-size 55)
                            (= size (+ 1 length-size content-size))))))))))))

(defun engine-new-payload-version-invalid-p
    (version payload config versioned-hashes-supplied-p
             parent-beacon-root-supplied-p requests-supplied-p)
  (let* ((number (executable-data-number payload))
         (timestamp (executable-data-timestamp payload))
         (withdrawals (executable-data-withdrawals payload))
         (withdrawals-present-p
           (or (executable-data-withdrawals-present-p payload)
               (not (null withdrawals))))
         (shanghai-p (chain-config-shanghai-p config number timestamp))
         (cancun-p (chain-config-cancun-p config number timestamp))
         (prague-p (chain-config-prague-p config number timestamp))
         (osaka-p (chain-config-osaka-p config number timestamp))
         (amsterdam-p (chain-config-amsterdam-p config number timestamp)))
    (cond
      ((= version 1)
       (when withdrawals-present-p
         "withdrawals not supported in newPayloadV1"))
      ((= version 2)
       (cond
         (cancun-p "newPayloadV2 cannot be used after Cancun")
         ((and shanghai-p (not withdrawals-present-p))
          "withdrawals required after Shanghai")
         ((and (not shanghai-p) withdrawals-present-p)
          "withdrawals not supported before Shanghai")
         ((executable-data-excess-blob-gas payload)
          "excessBlobGas not supported before Cancun")
         ((executable-data-blob-gas-used payload)
          "blobGasUsed not supported before Cancun")))
      ((= version 3)
       (cond
         ((or prague-p osaka-p amsterdam-p)
          "newPayloadV3 is unsupported after Cancun")
         ((not cancun-p)
          "newPayloadV3 requires Cancun")
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")))
      ((= version 4)
       (cond
         (amsterdam-p
          "newPayloadV4 is unsupported at Amsterdam")
         ((not (or prague-p osaka-p))
          "newPayloadV4 requires Prague or Osaka")
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")
         ((not requests-supplied-p)
          "executionRequests required after Prague")
         ;; A block access list belongs to newPayloadV5 only
         ;; (tests-glamsterdam-devnet v7.2.1
         ;; bal_invalid_engine_payload_field_before_fork: -32602).  Empty
         ;; bytes are left to block reconstruction, whose header then commits
         ;; to a list the fork has no field for: an INVALID block hash
         ;; (invalid_pre_fork_block_with_bal_hash_field; Nethermind
         ;; ExecutionPayloadParams.ValidateParams isEmptyPreForkV4).
         ((plusp (length (or (executable-data-block-access-list payload)
                             #())))
          "blockAccessList not supported before Amsterdam")))
      ((= version 5)
       (cond
         ((not amsterdam-p)
          "newPayloadV5 requires Amsterdam")
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")
         ((not requests-supplied-p)
          "executionRequests required after Prague")
         ((null (executable-data-slot-number payload))
          "slotNumber required after Amsterdam")
         ((null (executable-data-block-access-list payload))
          "blockAccessList required after Amsterdam")
         ;; Bytes that are not one whole RLP list are a malformed
         ;; parameter; a list whose entries do not decode is an INVALID
         ;; block (Nethermind ExecutionPayloadParams.ValidateParams;
         ;; tests-glamsterdam-devnet v7.2.1 bal_invalid_engine_payload_encoding).
         ((not (engine-block-access-list-envelope-p
                (executable-data-block-access-list payload)))
          "blockAccessList must be one complete RLP list")))
      (t "unsupported newPayload version"))))

(defun engine-new-payload-version-status
    (version payload config
     &key (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p))
  (unless (typep payload 'executable-data)
    (return-from engine-new-payload-version-status
      (values (invalid-payload-status
               "newPayload execution payload must be executable-data")
              nil)))
  (unless (typep config 'chain-config)
    (return-from engine-new-payload-version-status
      (values (invalid-payload-status
               "newPayload chain config must be chain-config")
              nil)))
  (let ((invalid-message
          (engine-new-payload-version-invalid-p
           version payload config
           versioned-hashes-supplied-p
           parent-beacon-root-supplied-p
           requests-supplied-p)))
    (when invalid-message
      (return-from engine-new-payload-version-status
        (values (invalid-payload-status invalid-message) nil))))
  (if requests-supplied-p
      (engine-new-payload-params-status
       payload
       :parent-beacon-root parent-beacon-root
       :versioned-hashes versioned-hashes
       :requests requests)
      (engine-new-payload-params-status
       payload
       :parent-beacon-root parent-beacon-root
       :versioned-hashes versioned-hashes)))
