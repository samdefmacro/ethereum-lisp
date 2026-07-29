(in-package #:ethereum-lisp.engine-api)

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
            (json-rpc-required-param
             params 0 "payloadId" method)))
         (prepared-payload
           (chain-store-prepared-payload store payload-id)))
    (unless prepared-payload
      (engine-rpc-fail +engine-rpc-error-unknown-payload+
                       "Unknown payload"))
    prepared-payload))

(defun engine-rpc-prepared-payload-envelope (prepared-payload)
  (let* ((block (engine-prepared-payload-block prepared-payload))
         (base-fee (or (block-header-base-fee-per-gas (block-header block)) 0))
         (previous-cumulative-gas 0)
         (block-value
           (loop for transaction in (block-transactions block)
                 for receipt in (block-receipts block)
                 for cumulative-gas = (receipt-cumulative-gas-used receipt)
                 for gas-used = (- cumulative-gas previous-cumulative-gas)
                 sum (* gas-used
                        (transaction-priority-fee-per-gas
                         transaction :base-fee base-fee))
                 do (setf previous-cumulative-gas cumulative-gas))))
    (block-to-executable-data
     block
     :block-value block-value
     :blobs-bundle (engine-prepared-payload-blobs-bundle prepared-payload))))

(defun engine-rpc-require-prepared-payload-version
    (prepared-payload supported-versions method)
  (unless (member (engine-prepared-payload-version prepared-payload)
                  supported-versions)
    (engine-rpc-fail
     +engine-rpc-error-unsupported-fork+
     (format nil "payload id is not for ~A" method))))

(defun engine-rpc-handle-get-payload-v1 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV1")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(1) "engine_getPayloadV1")
    (engine-rpc-executable-data-object
     (execution-payload-envelope-execution-payload
      (engine-rpc-prepared-payload-envelope prepared-payload)))))

(defun engine-rpc-handle-get-payload-v2 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV2")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(1 2) "engine_getPayloadV2")
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload))))

(defun engine-rpc-handle-get-payload-v3 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV3")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(3) "engine_getPayloadV3")
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v4 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV4")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(4) "engine_getPayloadV4")
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t
     :include-requests-p t)))

(defun engine-rpc-handle-get-payload-v5 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV5")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(5) "engine_getPayloadV5")
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t
     :include-requests-p t)))

(defun engine-rpc-handle-get-payload-v6 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV6")))
    (engine-rpc-require-prepared-payload-version
     prepared-payload '(6) "engine_getPayloadV6")
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t
     :include-requests-p t)))
