(in-package #:ethereum-lisp.core)

;;;; Engine API payload input decoding from JSON-RPC objects.

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
      (unless (json-array-p withdrawals)
        (block-validation-fail "withdrawals must be a list"))
      (loop for withdrawal in (json-array-values withdrawals)
            collect (engine-rpc-withdrawal-from-object withdrawal)))))

(defun engine-rpc-executable-data-from-object (object)
  (unless (listp object)
    (block-validation-fail "Engine RPC payload must be an object"))
  (let ((withdrawals-present-p
          (genesis-object-field-present-p object "withdrawals")))
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
     :withdrawals-present-p withdrawals-present-p
     :blob-gas-used (engine-rpc-optional-quantity-field object "blobGasUsed")
     :excess-blob-gas
     (engine-rpc-optional-quantity-field object "excessBlobGas")
     :slot-number (engine-rpc-optional-quantity-field object "slotNumber")
     :block-access-list
     (engine-rpc-optional-bytes-field object "blockAccessList"))))
