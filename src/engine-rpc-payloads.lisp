(in-package #:ethereum-lisp.core)

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
