(in-package #:ethereum-lisp.engine-api)

;;;; Engine API payload, blob, body, and status response rendering.

(defun engine-rpc-withdrawal-object (withdrawal)
  (list (cons "index" (quantity-to-hex (withdrawal-index withdrawal)))
        (cons "validatorIndex"
              (quantity-to-hex (withdrawal-validator-index withdrawal)))
        (cons "address" (address-to-hex (withdrawal-address withdrawal)))
        (cons "amount" (quantity-to-hex (withdrawal-amount withdrawal)))))

(defun engine-rpc-executable-data-object (payload)
  (unless (typep payload 'executable-data)
    (block-validation-fail "Engine RPC payload must be executable-data"))
  (append
   (list
    (cons "parentHash"
          (hash32-to-hex (executable-data-parent-hash payload)))
    (cons "feeRecipient"
          (address-to-hex (executable-data-fee-recipient payload)))
    (cons "stateRoot"
          (hash32-to-hex (executable-data-state-root payload)))
    (cons "receiptsRoot"
          (hash32-to-hex (executable-data-receipts-root payload)))
    (cons "logsBloom"
          (bytes-to-hex (executable-data-logs-bloom payload)))
    (cons "prevRandao"
          (hash32-to-hex (executable-data-random payload)))
    (cons "blockNumber"
          (quantity-to-hex (executable-data-number payload)))
    (cons "gasLimit"
          (quantity-to-hex (executable-data-gas-limit payload)))
    (cons "gasUsed"
          (quantity-to-hex (executable-data-gas-used payload)))
    (cons "timestamp"
          (quantity-to-hex (executable-data-timestamp payload)))
    (cons "extraData"
          (bytes-to-hex (executable-data-extra-data payload)))
    (cons "baseFeePerGas"
          (quantity-to-hex (executable-data-base-fee-per-gas payload)))
    (cons "blockHash"
          (hash32-to-hex (executable-data-block-hash payload)))
    (cons "transactions"
          (mapcar #'bytes-to-hex (executable-data-transactions payload))))
   (when (or (executable-data-withdrawals-present-p payload)
             (executable-data-withdrawals payload))
     (list (cons "withdrawals"
                 (mapcar #'engine-rpc-withdrawal-object
                         (or (executable-data-withdrawals payload) '())))))
   (when (executable-data-blob-gas-used payload)
     (list
      (cons "blobGasUsed"
            (quantity-to-hex (executable-data-blob-gas-used payload)))
      (cons "excessBlobGas"
            (quantity-to-hex (executable-data-excess-blob-gas payload)))))
   (when (executable-data-slot-number payload)
     (list
      (cons "slotNumber"
            (quantity-to-hex (executable-data-slot-number payload)))))
   (when (executable-data-block-access-list payload)
     (list
      (cons "blockAccessList"
            (bytes-to-hex
             (executable-data-block-access-list payload)))))))

(defun engine-rpc-blobs-bundle-object (bundle)
  (let ((sidecar (or bundle (make-blob-sidecar))))
    (unless (typep sidecar 'blob-sidecar)
      (block-validation-fail
       "Engine RPC blobs bundle must be a blob sidecar"))
    (list
     (cons "commitments"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-commitments sidecar)))
     (cons "proofs"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-proofs sidecar)))
     (cons "blobs"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-blobs sidecar))))))

(defun engine-rpc-blob-and-proof-v1-object (blob-and-proofs)
  (unless (typep blob-and-proofs 'engine-blob-and-proofs)
    (block-validation-fail
     "Engine RPC blob response must be an engine-blob-and-proofs"))
  (list
   (cons "blob"
         (bytes-to-hex
          (engine-blob-and-proofs-blob blob-and-proofs)))
   (cons "proof"
         (bytes-to-hex
          (engine-blob-and-proofs-proof blob-and-proofs)))))

(defun engine-rpc-blob-and-proof-v2-object (blob-and-proofs)
  (unless (typep blob-and-proofs 'engine-blob-and-proofs)
    (block-validation-fail
     "Engine RPC blob response must be an engine-blob-and-proofs"))
  (let ((cell-proofs
          (engine-blob-and-proofs-cell-proofs blob-and-proofs)))
    (unless (= +cell-proofs-per-blob+ (length cell-proofs))
      (block-validation-fail
       "Engine RPC V2 blob response must have 128 cell proofs"))
    (list
     (cons "blob"
           (bytes-to-hex
            (engine-blob-and-proofs-blob blob-and-proofs)))
     (cons "proofs"
           (mapcar #'bytes-to-hex cell-proofs)))))

(defun engine-rpc-execution-payload-envelope-object
    (envelope &key include-blobs-bundle-p include-override-p)
  (unless (typep envelope 'execution-payload-envelope)
    (block-validation-fail
     "Engine RPC payload envelope must be execution-payload-envelope"))
  (append
   (list
    (cons "executionPayload"
          (engine-rpc-executable-data-object
           (execution-payload-envelope-execution-payload envelope)))
    (cons "blockValue"
          (quantity-to-hex (execution-payload-envelope-block-value envelope))))
   (when (execution-payload-envelope-requests envelope)
     (list
      (cons "executionRequests"
            (mapcar #'bytes-to-hex
                    (execution-payload-envelope-requests envelope)))))
   (when include-blobs-bundle-p
     (list
      (cons "blobsBundle"
            (engine-rpc-blobs-bundle-object
             (execution-payload-envelope-blobs-bundle envelope)))))
   (when (or include-override-p
             (execution-payload-envelope-override-p envelope))
     (list
      (cons "shouldOverrideBuilder"
            (if (execution-payload-envelope-override-p envelope)
                t
                :false))))))

(defun engine-rpc-payload-body-v1-object (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine RPC payload body block must be a block"))
  (append
   (list
    (cons "transactions"
          (mapcar (lambda (transaction)
                    (bytes-to-hex (transaction-encoding transaction)))
                  (block-transactions block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun engine-rpc-payload-body-v2-object (block)
  (append
   (engine-rpc-payload-body-v1-object block)
   (when (block-block-access-list-present-p block)
     (list (cons "blockAccessList"
                 (bytes-to-hex (block-encoded-block-access-list block)))))))

(defun engine-rpc-payload-status-object (status)
  (list (cons "status" (payload-status-status status))
        (cons "latestValidHash"
              (when (payload-status-latest-valid-hash status)
                (hash32-to-hex (payload-status-latest-valid-hash status))))
        (cons "validationError" (payload-status-validation-error status))
        (cons "witness" (payload-status-witness status))))
