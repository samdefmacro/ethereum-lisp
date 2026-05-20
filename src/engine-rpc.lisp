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

(defconstant +engine-rpc-error-unknown-payload+ -38001)
(defconstant +engine-rpc-error-invalid-forkchoice-state+ -38002)
(defconstant +engine-rpc-error-invalid-payload-attributes+ -38003)
(defconstant +engine-rpc-error-too-large-request+ -38004)

(define-condition engine-rpc-error (error)
  ((code :initarg :code :reader engine-rpc-error-code)
   (message :initarg :message :reader engine-rpc-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (engine-rpc-error-message condition)))))

(defun engine-rpc-fail (code message)
  (error 'engine-rpc-error :code code :message message))

(defun engine-rpc-payload-id-from-value (value)
  (unless (stringp value)
    (block-validation-fail "engine_getPayload payload id must be a hex string"))
  (let ((payload-id
          (handler-case
              (hex-to-bytes value)
            (error ()
              (block-validation-fail
               "engine_getPayload payload id must be hex bytes")))))
    (unless (= 8 (length payload-id))
      (block-validation-fail "engine_getPayload payload id must be 8 bytes"))
    payload-id))

(defun engine-rpc-prepared-payload (params store method)
  (unless (and (listp params) params)
    (block-validation-fail "~A params must include payload id" method))
  (let* ((payload-id
           (engine-rpc-payload-id-from-value
            (engine-rpc-required-param
             params 0 "payloadId" method)))
         (prepared-payload
           (chain-store-prepared-payload store payload-id)))
    (unless prepared-payload
      (engine-rpc-fail +engine-rpc-error-unknown-payload+
                       "Unknown payload"))
    prepared-payload))

(defun engine-rpc-prepared-payload-envelope (prepared-payload)
  (block-to-executable-data
   (engine-prepared-payload-block prepared-payload)
   :blobs-bundle (engine-prepared-payload-blobs-bundle prepared-payload)))

(defun engine-rpc-handle-get-payload-v1 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV1")))
    (unless (= 1 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV1"))
    (engine-rpc-executable-data-object
     (execution-payload-envelope-execution-payload
      (engine-rpc-prepared-payload-envelope prepared-payload)))))

(defun engine-rpc-handle-get-payload-v2 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV2")))
    (unless (member (engine-prepared-payload-version prepared-payload)
                    '(1 2))
      (block-validation-fail "payload id is not for engine_getPayloadV2"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload))))

(defun engine-rpc-handle-get-payload-v3 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV3")))
    (unless (= 3 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV3"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v4 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV4")))
    (unless (= 4 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV4"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v5 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV5")))
    (unless (= 5 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV5"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v6 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV6")))
    (unless (= 6 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV6"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defconstant +engine-rpc-max-payload-bodies-request+ 1024)
(defconstant +engine-rpc-max-get-blobs-request+ 128)

(defun engine-rpc-get-blob-hashes-param (params method)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include blob versioned hashes" method))
  (engine-rpc-hash32-list
   (engine-rpc-required-param
    params 0 "blobVersionedHashes" method)
   "blobVersionedHashes"))

(defun engine-rpc-validate-get-blobs-request-size (hashes)
  (when (> (length hashes) +engine-rpc-max-get-blobs-request+)
    (engine-rpc-fail
     +engine-rpc-error-too-large-request+
     "The number of requested blobs must not exceed 128")))

(defun engine-rpc-handle-get-blobs-v1 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV1")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v1
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v1-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-blobs-v2 (params store)
  (let* ((hashes
           (engine-rpc-get-blob-hashes-param
            params "engine_getBlobsV2"))
         (blobs
           (progn
             (engine-rpc-validate-get-blobs-request-size hashes)
             (mapcar (lambda (versioned-hash)
                       (engine-payload-store-blob-and-proofs-v2
                        store versioned-hash))
                     hashes))))
    (if (some #'null blobs)
        nil
        (mapcar #'engine-rpc-blob-and-proof-v2-object blobs))))

(defun engine-rpc-handle-get-blobs-v3 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV3")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v2
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v2-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include block hashes" method))
  (let ((hashes
          (engine-rpc-hash32-list
           (engine-rpc-required-param
            params 0 "blockHashes" method)
           "blockHashes")))
    (when (> (length hashes) +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (mapcar (lambda (hash)
              (let ((block (chain-store-known-block store hash)))
                (when block
                  (funcall body-object-function block))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV2"
   #'engine-rpc-payload-body-v2-object))

(defun engine-rpc-quantity-param (params index label method)
  (parse-genesis-quantity
   (engine-rpc-required-param params index label method)
   label
   :required-p t))

(defun engine-rpc-handle-get-payload-bodies-by-range
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include start and count" method))
  (let ((start (engine-rpc-quantity-param
                params 0 "start" method))
        (count (engine-rpc-quantity-param
                params 1 "count" method)))
    (unless (and (plusp start) (plusp count))
      (block-validation-fail "start and count must be positive numbers"))
    (when (> count +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (let* ((head (chain-store-head-number store))
           (last (min (+ start count -1) head)))
      (if (< last start)
          '()
          (loop for number from start to last
                collect
                (let ((block (chain-store-block-by-number store number)))
                  (when block
                    (funcall body-object-function block))))))))

(defun engine-rpc-handle-get-payload-bodies-by-range-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-range-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV2"
   #'engine-rpc-payload-body-v2-object))

(defun engine-rpc-handle-forkchoice-updated
    (params store method payload-version payload-attributes-parser)
  (unless (and (listp params) params)
    (block-validation-fail "~A params must include forkchoice state" method))
  (let ((state
          (engine-rpc-forkchoice-state-from-object
           (engine-rpc-required-param
            params 0 "forkchoiceState" method)))
        (payload-attributes
          (when (< 1 (length params))
            (second params))))
    (setf payload-attributes
          (when payload-attributes
            (funcall payload-attributes-parser payload-attributes)))
    (let ((status (engine-forkchoice-memory-status store state))
          (payload-id nil))
      (when (string= +payload-status-valid+
                     (payload-status-status status))
        (let ((checkpoint-error
                (or
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-finalized-block-hash state)
                  "finalized"
                  :head-hash (forkchoice-state-head-block-hash state))
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-safe-block-hash state)
                  "safe"
                  :head-hash (forkchoice-state-head-block-hash state)))))
          (when checkpoint-error
            (engine-rpc-fail
             +engine-rpc-error-invalid-forkchoice-state+
             checkpoint-error)))
        (chain-store-update-forkchoice-checkpoints store state)
        (chain-store-set-canonical-head
         store
         (forkchoice-state-head-block-hash state)))
      (when (and payload-attributes
                 (string= +payload-status-valid+
                          (payload-status-status status)))
        (let* ((head-hash (forkchoice-state-head-block-hash state))
               (parent-block
                 (chain-store-known-block store head-hash))
               (candidate-id
                 (engine-payload-id
                  payload-version head-hash payload-attributes)))
          (unless (chain-store-prepared-payload
                   store candidate-id)
            (chain-store-put-prepared-payload
             store
             (make-engine-prepared-payload
              :payload-id candidate-id
              :version payload-version
              :block
              (handler-case
                  (engine-build-empty-payload parent-block payload-attributes)
                (block-validation-error (condition)
                  (engine-rpc-fail
                   +engine-rpc-error-invalid-payload-attributes+
                   (block-validation-error-message condition)))))))
          (setf payload-id candidate-id)))
      (engine-rpc-forkchoice-response-object
       status
       :payload-id payload-id))))

(defun engine-rpc-handle-forkchoice-updated-v1 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV1" 1
   (lambda (payload-attributes)
     (engine-rpc-validate-payload-attributes-v1
      payload-attributes :method "engine_forkchoiceUpdatedV1"))))

(defun engine-rpc-handle-forkchoice-updated-v2 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV2" 2
   #'engine-rpc-validate-payload-attributes-v2))

(defun engine-rpc-handle-forkchoice-updated-v3 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV3" 3
   #'engine-rpc-validate-payload-attributes-v3))

(defun engine-rpc-handle-forkchoice-updated-v4 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV4" 4
   #'engine-rpc-validate-payload-attributes-v4))

(defun engine-rpc-handle-engine-method
    (id method params store config &key import-function)
  (let ((version (engine-rpc-new-payload-version method)))
    (cond
      (version
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-new-payload
         version params store config
         :import-function import-function)))
      ((string= method "engine_exchangeCapabilities")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-capabilities params)))
      ((string= method "engine_forkchoiceUpdatedV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v1 params store)))
      ((string= method "engine_forkchoiceUpdatedV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v2 params store)))
      ((string= method "engine_forkchoiceUpdatedV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v3 params store)))
      ((string= method "engine_forkchoiceUpdatedV4")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v4 params store)))
      ((string= method "engine_getPayloadV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v1 params store)))
      ((string= method "engine_getPayloadV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v2 params store)))
      ((string= method "engine_getPayloadV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v3 params store)))
      ((string= method "engine_getPayloadV4")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v4 params store)))
      ((string= method "engine_getPayloadV5")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v5 params store)))
      ((string= method "engine_getPayloadV6")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v6 params store)))
      ((string= method "engine_getPayloadBodiesByHashV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByHashV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v2
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v2
         params store)))
      ((string= method "engine_getBlobsV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v1 params store)))
      ((string= method "engine_getBlobsV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v2 params store)))
      ((string= method "engine_getBlobsV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v3 params store)))
      ((string= method "engine_getClientVersionV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-client-version params)))
      ((string= method "engine_exchangeTransitionConfigurationV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-transition-configuration
         params config))))))
