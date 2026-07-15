(in-package #:ethereum-lisp.engine-api)

;;;; Engine API payload input decoding from JSON-RPC objects.

(defun engine-rpc-withdrawal-from-object (object)
  (make-withdrawal
   :index (json-rpc-required-quantity-field object "index")
   :validator-index
   (json-rpc-required-quantity-field object "validatorIndex")
   :address (json-rpc-required-address-field object "address")
   :amount (json-rpc-required-quantity-field object "amount")))

(defun engine-rpc-withdrawals-field (object)
  (when (json-object-field-present-p object "withdrawals")
    (let ((withdrawals (json-object-field object "withdrawals")))
      (unless (json-array-p withdrawals)
        (block-validation-fail "withdrawals must be a list"))
      (loop for withdrawal in (json-array-values withdrawals)
            collect (engine-rpc-withdrawal-from-object withdrawal)))))

(defun engine-rpc-executable-data-from-object (object)
  (unless (listp object)
    (block-validation-fail "Engine RPC payload must be an object"))
  (let ((withdrawals-present-p
          (json-object-field-present-p object "withdrawals")))
    (make-executable-data
     :parent-hash (json-rpc-required-hash32-field object "parentHash")
     :fee-recipient (json-rpc-required-address-field object "feeRecipient")
     :state-root (json-rpc-required-hash32-field object "stateRoot")
     :receipts-root (json-rpc-required-hash32-field object "receiptsRoot")
     :logs-bloom (json-rpc-required-bytes-field object "logsBloom")
     :random (json-rpc-required-hash32-field object "prevRandao")
     :number (json-rpc-required-quantity-field object "blockNumber")
     :gas-limit (json-rpc-required-quantity-field object "gasLimit")
     :gas-used (json-rpc-required-quantity-field object "gasUsed")
     :timestamp (json-rpc-required-quantity-field object "timestamp")
     :extra-data (json-rpc-required-bytes-field object "extraData")
     :base-fee-per-gas
     (json-rpc-required-quantity-field object "baseFeePerGas")
     :block-hash (json-rpc-required-hash32-field object "blockHash")
     :transactions
     (json-rpc-byte-list
      (json-rpc-required-field object "transactions")
      "transactions")
     :withdrawals (engine-rpc-withdrawals-field object)
     :withdrawals-present-p withdrawals-present-p
     :blob-gas-used (json-rpc-optional-quantity-field object "blobGasUsed")
     :excess-blob-gas
     (json-rpc-optional-quantity-field object "excessBlobGas")
     :slot-number (json-rpc-optional-quantity-field object "slotNumber")
     :block-access-list
     (json-rpc-optional-bytes-field object "blockAccessList"))))
