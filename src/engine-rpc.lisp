(in-package #:ethereum-lisp.core)

(defun engine-rpc-required-field (object name)
  (unless (genesis-object-field-present-p object name)
    (block-validation-fail "Engine RPC field ~A is missing" name))
  (genesis-object-field object name))

(defun engine-rpc-optional-quantity-field (object name)
  (when (genesis-object-field-present-p object name)
    (parse-genesis-field object name :label name)))

(defun engine-rpc-required-quantity-field (object name)
  (parse-genesis-field object name :label name :required-p t))

(defun engine-rpc-hash32 (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex hash" label))
  (handler-case
      (hash32-from-hex value)
    (error ()
      (block-validation-fail "~A must be a hash32" label))))

(defun engine-rpc-address (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (block-validation-fail "~A must be an address" label))))

(defun engine-rpc-bytes (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex byte string" label))
  (handler-case
      (hex-to-bytes value)
    (error ()
      (block-validation-fail "~A must be a hex byte string" label))))

(defun engine-rpc-required-hash32-field (object name)
  (engine-rpc-hash32 (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-hash32-value (value label)
  (when value
    (engine-rpc-hash32 value label)))

(defun engine-rpc-required-address-field (object name)
  (engine-rpc-address (engine-rpc-required-field object name) name))

(defun engine-rpc-required-bytes-field (object name)
  (engine-rpc-bytes (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-bytes-field (object name)
  (when (genesis-object-field-present-p object name)
    (engine-rpc-bytes (genesis-object-field object name) name)))

(defun engine-rpc-byte-list (values label)
  (unless (listp values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in values
        for index from 0
        collect (engine-rpc-bytes value (format nil "~A ~D" label index))))

(defun engine-rpc-hash32-list (values label)
  (unless (listp values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in values
        for index from 0
        collect (engine-rpc-hash32 value (format nil "~A ~D" label index))))

(defun engine-rpc-withdrawal-from-object (object)
  (make-withdrawal
   :index (engine-rpc-required-quantity-field object "index")
   :validator-index
   (engine-rpc-required-quantity-field object "validatorIndex")
   :address (engine-rpc-required-address-field object "address")
   :amount (engine-rpc-required-quantity-field object "amount")))

(defun engine-rpc-withdrawals-field (object)
  (when (genesis-object-field-present-p object "withdrawals")
    (let ((withdrawals (genesis-object-field object "withdrawals")))
      (unless (listp withdrawals)
        (block-validation-fail "withdrawals must be a list"))
      (loop for withdrawal in withdrawals
            collect (engine-rpc-withdrawal-from-object withdrawal)))))

(defun engine-rpc-withdrawal-object (withdrawal)
  (list (cons "index" (quantity-to-hex (withdrawal-index withdrawal)))
        (cons "validatorIndex"
              (quantity-to-hex (withdrawal-validator-index withdrawal)))
        (cons "address" (address-to-hex (withdrawal-address withdrawal)))
        (cons "amount" (quantity-to-hex (withdrawal-amount withdrawal)))))

(defun engine-rpc-executable-data-from-object (object)
  (unless (listp object)
    (block-validation-fail "Engine RPC payload must be an object"))
  (make-executable-data
   :parent-hash (engine-rpc-required-hash32-field object "parentHash")
   :fee-recipient (engine-rpc-required-address-field object "feeRecipient")
   :state-root (engine-rpc-required-hash32-field object "stateRoot")
   :receipts-root (engine-rpc-required-hash32-field object "receiptsRoot")
   :logs-bloom (engine-rpc-required-bytes-field object "logsBloom")
   :random (engine-rpc-required-hash32-field object "prevRandao")
   :number (engine-rpc-required-quantity-field object "blockNumber")
   :gas-limit (engine-rpc-required-quantity-field object "gasLimit")
   :gas-used (engine-rpc-required-quantity-field object "gasUsed")
   :timestamp (engine-rpc-required-quantity-field object "timestamp")
   :extra-data (engine-rpc-required-bytes-field object "extraData")
   :base-fee-per-gas
   (engine-rpc-required-quantity-field object "baseFeePerGas")
   :block-hash (engine-rpc-required-hash32-field object "blockHash")
   :transactions
   (engine-rpc-byte-list
    (engine-rpc-required-field object "transactions")
    "transactions")
   :withdrawals (engine-rpc-withdrawals-field object)
   :blob-gas-used (engine-rpc-optional-quantity-field object "blobGasUsed")
   :excess-blob-gas
   (engine-rpc-optional-quantity-field object "excessBlobGas")
   :slot-number (engine-rpc-optional-quantity-field object "slotNumber")
   :block-access-list
   (engine-rpc-optional-bytes-field object "blockAccessList")))

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
   (when (executable-data-withdrawals payload)
     (list (cons "withdrawals"
                 (mapcar #'engine-rpc-withdrawal-object
                         (executable-data-withdrawals payload)))))
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

(defun engine-rpc-forkchoice-state-from-object (object)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_forkchoiceUpdated params must contain forkchoice state object"))
  (make-forkchoice-state
   :head-block-hash
   (engine-rpc-required-hash32-field object "headBlockHash")
   :safe-block-hash
   (engine-rpc-required-hash32-field object "safeBlockHash")
   :finalized-block-hash
   (engine-rpc-required-hash32-field object "finalizedBlockHash")))

(defun engine-rpc-validate-payload-attributes-v1
    (object &key (method "engine_forkchoiceUpdatedV1")
                 withdrawals-field-required-p)
  (unless (json-object-p object)
    (block-validation-fail
     "~A payloadAttributes must be an object or null" method))
  (when (and withdrawals-field-required-p
             (not (genesis-object-field-present-p object "withdrawals")))
    (block-validation-fail "~A payloadAttributes withdrawals is missing" method))
  (make-payload-attributes-v1
   :timestamp (engine-rpc-required-quantity-field object "timestamp")
   :prev-randao (engine-rpc-required-hash32-field object "prevRandao")
   :suggested-fee-recipient
   (engine-rpc-required-address-field object "suggestedFeeRecipient")
   :withdrawals (engine-rpc-withdrawals-field object)
   :withdrawals-present-p
   (genesis-object-field-present-p object "withdrawals")))

(defun engine-rpc-validate-payload-attributes-v2 (object)
  (engine-rpc-validate-payload-attributes-v1
   object :method "engine_forkchoiceUpdatedV2"))

(defun engine-rpc-validate-payload-attributes-v3 (object)
  (let ((attributes
          (engine-rpc-validate-payload-attributes-v1
           object
           :method "engine_forkchoiceUpdatedV3"
           :withdrawals-field-required-p t)))
    (unless (genesis-object-field-present-p object "parentBeaconBlockRoot")
      (block-validation-fail
       "engine_forkchoiceUpdatedV3 payloadAttributes parentBeaconBlockRoot is missing"))
    (setf (payload-attributes-v1-parent-beacon-root attributes)
          (engine-rpc-required-hash32-field object "parentBeaconBlockRoot")
          (payload-attributes-v1-parent-beacon-root-present-p attributes)
          t)
    attributes))

(defun engine-rpc-validate-payload-attributes-v4 (object)
  (let ((attributes (engine-rpc-validate-payload-attributes-v3 object)))
    (unless (genesis-object-field-present-p object "slotNumber")
      (block-validation-fail
       "engine_forkchoiceUpdatedV4 payloadAttributes slotNumber is missing"))
    (setf (payload-attributes-v1-slot-number attributes)
          (engine-rpc-required-quantity-field object "slotNumber")
          (payload-attributes-v1-slot-number-present-p attributes)
          t)
    attributes))

(defun engine-rpc-forkchoice-response-object (status &key payload-id)
  (list (cons "payloadStatus" (engine-rpc-payload-status-object status))
        (cons "payloadId" (when payload-id
                            (engine-payload-id-to-hex payload-id)))))

(defparameter +engine-rpc-capabilities+
  '("engine_exchangeTransitionConfigurationV1"
    "engine_forkchoiceUpdatedV1"
    "engine_forkchoiceUpdatedV2"
    "engine_forkchoiceUpdatedV3"
    "engine_forkchoiceUpdatedV4"
    "engine_getPayloadBodiesByHashV1"
    "engine_getPayloadBodiesByHashV2"
    "engine_getPayloadBodiesByRangeV1"
    "engine_getPayloadBodiesByRangeV2"
    "engine_getPayloadV1"
    "engine_getPayloadV2"
    "engine_getPayloadV3"
    "engine_getPayloadV4"
    "engine_getPayloadV5"
    "engine_getPayloadV6"
    "engine_getBlobsV1"
    "engine_getBlobsV2"
    "engine_getBlobsV3"
    "engine_getClientVersionV1"
    "engine_newPayloadV1"
    "engine_newPayloadV2"
    "engine_newPayloadV3"
    "engine_newPayloadV4"
    "engine_newPayloadV5"))

(defun engine-rpc-capabilities ()
  (copy-list +engine-rpc-capabilities+))

(defparameter +engine-rpc-client-version+
  '(("code" . "CL")
    ("name" . "ethereum-lisp")
    ("version" . "0.1.0")
    ("commit" . "0x00000000")))

(defun engine-rpc-client-version ()
  (copy-tree +engine-rpc-client-version+))

(defun engine-rpc-transition-configuration-object (config)
  (unless (typep config 'chain-config)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 config must be chain-config"))
  (list (cons "terminalTotalDifficulty"
              (quantity-to-hex
               (or (chain-config-terminal-total-difficulty config) 0)))
        (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
        (cons "terminalBlockNumber" (quantity-to-hex 0))))

(defun engine-rpc-new-payload-version (method)
  (cond
    ((string= method "engine_newPayloadV1") 1)
    ((string= method "engine_newPayloadV2") 2)
    ((string= method "engine_newPayloadV3") 3)
    ((string= method "engine_newPayloadV4") 4)
    ((string= method "engine_newPayloadV5") 5)
    (t nil)))

(defun engine-rpc-required-param
    (params index label &optional (method "engine_newPayload"))
  (unless (< index (length params))
    (block-validation-fail "~A param ~A is missing" method label))
  (nth index params))

(defun engine-rpc-handle-new-payload
    (version params store config &key import-function)
  (unless (and (listp params) params)
    (block-validation-fail "engine_newPayload params must include payload"))
  (let* ((payload
           (engine-rpc-executable-data-from-object
            (engine-rpc-required-param params 0 "payload")))
         (versioned-hashes
           (when (>= version 3)
             (engine-rpc-hash32-list
              (engine-rpc-required-param params 1 "versionedHashes")
              "versionedHashes")))
         (parent-beacon-root
           (when (>= version 3)
             (engine-rpc-optional-hash32-value
              (engine-rpc-required-param params 2 "parentBeaconBlockRoot")
              "parentBeaconBlockRoot")))
         (requests
           (when (>= version 4)
             (engine-rpc-byte-list
              (engine-rpc-required-param params 3 "executionRequests")
              "executionRequests"))))
    (multiple-value-bind (status block)
        (cond
          ((<= version 2)
           (engine-new-payload-memory-status
            store version payload config
            :import-function import-function))
          ((= version 3)
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :import-function import-function))
          (t
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :requests requests
            :import-function import-function)))
      (declare (ignore block))
      (engine-rpc-payload-status-object status))))

(defun engine-rpc-handle-exchange-capabilities (params)
  (when params
    (let ((remote (first params)))
      (unless (and (listp remote)
                   (every #'stringp remote))
        (block-validation-fail
         "engine_exchangeCapabilities params must contain a string list"))))
  (engine-rpc-capabilities))

(defun engine-rpc-handle-get-client-version (params)
  (when params
    (let ((caller (first params)))
      (unless (json-object-p caller)
        (block-validation-fail
         "engine_getClientVersionV1 params must contain a client version object"))
      (dolist (field '("code" "name" "version" "commit"))
        (let ((value (engine-rpc-required-field caller field)))
          (unless (stringp value)
            (block-validation-fail
             "engine_getClientVersionV1 client version fields must be strings"))))))
  (list (engine-rpc-client-version)))

(defun engine-rpc-validate-transition-configuration (object)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must contain transition configuration object"))
  (engine-rpc-required-quantity-field object "terminalTotalDifficulty")
  (engine-rpc-required-hash32-field object "terminalBlockHash")
  (engine-rpc-required-quantity-field object "terminalBlockNumber")
  t)

(defun engine-rpc-handle-exchange-transition-configuration (params config)
  (unless params
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must include transition configuration"))
  (engine-rpc-validate-transition-configuration (first params))
  (engine-rpc-transition-configuration-object config))
