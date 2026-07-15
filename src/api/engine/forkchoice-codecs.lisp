(in-package #:ethereum-lisp.engine-api)

(defun engine-rpc-forkchoice-state-from-object (object)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_forkchoiceUpdated params must contain forkchoice state object"))
  (make-forkchoice-state
   :head-block-hash
   (json-rpc-required-hash32-field object "headBlockHash")
   :safe-block-hash
   (json-rpc-required-hash32-field object "safeBlockHash")
   :finalized-block-hash
   (json-rpc-required-hash32-field object "finalizedBlockHash")))

(defun engine-rpc-validate-payload-attributes-v1
    (object &key (method "engine_forkchoiceUpdatedV1")
                 withdrawals-field-required-p)
  (unless (json-object-p object)
    (block-validation-fail
     "~A payloadAttributes must be an object or null" method))
  (when (and withdrawals-field-required-p
             (not (json-object-field-present-p object "withdrawals")))
    (block-validation-fail "~A payloadAttributes withdrawals is missing" method))
  (make-payload-attributes-v1
   :timestamp (json-rpc-required-quantity-field object "timestamp")
   :prev-randao (json-rpc-required-hash32-field object "prevRandao")
   :suggested-fee-recipient
   (json-rpc-required-address-field object "suggestedFeeRecipient")
   :withdrawals (engine-rpc-withdrawals-field object)
   :withdrawals-present-p
   (json-object-field-present-p object "withdrawals")))

(defun engine-rpc-validate-payload-attributes-v2 (object)
  (engine-rpc-validate-payload-attributes-v1
   object :method "engine_forkchoiceUpdatedV2"))

(defun engine-rpc-validate-payload-attributes-v3 (object)
  (let ((attributes
          (engine-rpc-validate-payload-attributes-v1
           object
           :method "engine_forkchoiceUpdatedV3"
           :withdrawals-field-required-p t)))
    (unless (json-object-field-present-p object "parentBeaconBlockRoot")
      (block-validation-fail
       "engine_forkchoiceUpdatedV3 payloadAttributes parentBeaconBlockRoot is missing"))
    (setf (payload-attributes-v1-parent-beacon-root attributes)
          (json-rpc-required-hash32-field object "parentBeaconBlockRoot")
          (payload-attributes-v1-parent-beacon-root-present-p attributes)
          t)
    attributes))

(defun engine-rpc-validate-payload-attributes-v4 (object)
  (let ((attributes (engine-rpc-validate-payload-attributes-v3 object)))
    (unless (json-object-field-present-p object "slotNumber")
      (block-validation-fail
       "engine_forkchoiceUpdatedV4 payloadAttributes slotNumber is missing"))
    (setf (payload-attributes-v1-slot-number attributes)
          (json-rpc-required-quantity-field object "slotNumber")
          (payload-attributes-v1-slot-number-present-p attributes)
          t)
    attributes))

(defun engine-rpc-forkchoice-response-object (status &key payload-id)
  (list (cons "payloadStatus" (engine-rpc-payload-status-object status))
        (cons "payloadId" (when payload-id
                            (engine-payload-id-to-hex payload-id)))))
