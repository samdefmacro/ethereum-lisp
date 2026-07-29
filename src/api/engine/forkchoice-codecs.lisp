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
                 withdrawals-field-required-p
                 (withdrawals-field-forbidden-p t)
                 (parent-beacon-root-field-forbidden-p t))
  (unless (json-object-p object)
    (block-validation-fail
     "~A payloadAttributes must be an object or null" method))
  (when (and withdrawals-field-required-p
             (not (json-object-field-present-p object "withdrawals")))
    (block-validation-fail "~A payloadAttributes withdrawals is missing" method))
  (when (and withdrawals-field-forbidden-p
             (json-object-field-present-p object "withdrawals"))
    (block-validation-fail
     "~A payloadAttributes withdrawals is unsupported" method))
  (when (and parent-beacon-root-field-forbidden-p
             (json-object-field-present-p object "parentBeaconBlockRoot"))
    (block-validation-fail
     "~A payloadAttributes parentBeaconBlockRoot is unsupported" method))
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
   object
   :method "engine_forkchoiceUpdatedV2"
   :withdrawals-field-forbidden-p nil))

(defun engine-rpc-validate-payload-attributes-v3
    (object &key (method "engine_forkchoiceUpdatedV3"))
  (let ((attributes
          (engine-rpc-validate-payload-attributes-v1
           object
           :method method
           :withdrawals-field-required-p t
           :withdrawals-field-forbidden-p nil
           :parent-beacon-root-field-forbidden-p nil)))
    (unless (json-object-field-present-p object "parentBeaconBlockRoot")
      (block-validation-fail
       "~A payloadAttributes parentBeaconBlockRoot is missing" method))
    (setf (payload-attributes-v1-parent-beacon-root attributes)
          (json-rpc-required-hash32-field object "parentBeaconBlockRoot")
          (payload-attributes-v1-parent-beacon-root-present-p attributes)
          t)
    attributes))

(defun engine-rpc-validate-payload-attributes-v4 (object)
  (let ((attributes
          (engine-rpc-validate-payload-attributes-v3
           object :method "engine_forkchoiceUpdatedV4")))
    (unless (json-object-field-present-p object "slotNumber")
      (block-validation-fail
       "engine_forkchoiceUpdatedV4 payloadAttributes slotNumber is missing"))
    (setf (payload-attributes-v1-slot-number attributes)
          (json-rpc-required-quantity-field object "slotNumber")
          (payload-attributes-v1-slot-number-present-p attributes)
          t)
    (unless (json-object-field-present-p object "targetGasLimit")
      (block-validation-fail
       "engine_forkchoiceUpdatedV4 payloadAttributes targetGasLimit is missing"))
    (let ((target-gas-limit
            (json-rpc-required-quantity-field object "targetGasLimit")))
      (unless (plusp target-gas-limit)
        (block-validation-fail
         "engine_forkchoiceUpdatedV4 payloadAttributes targetGasLimit must be positive"))
      (setf (payload-attributes-v1-target-gas-limit attributes) target-gas-limit
            (payload-attributes-v1-target-gas-limit-present-p attributes) t))
    attributes))

(defun engine-rpc-forkchoice-response-object (status &key payload-id)
  (list (cons "payloadStatus" (engine-rpc-payload-status-object status))
        (cons "payloadId" (when payload-id
                            (engine-payload-id-to-hex payload-id)))))
