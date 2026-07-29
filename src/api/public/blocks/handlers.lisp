(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-build-pending-block (store config)
  "Execute the currently viable txpool contents on top of the canonical head."
  (let ((parent (chain-store-latest-block store)))
    (when parent
      (let* ((parent-header (block-header parent))
             (number (1+ (block-header-number parent-header)))
             (timestamp (1+ (block-header-timestamp parent-header)))
             (cancun-p (chain-config-cancun-p config number timestamp))
             (amsterdam-p
               (chain-config-amsterdam-p config number timestamp))
             (attributes
               (make-payload-attributes-v1
                :timestamp timestamp
                :prev-randao (zero-hash32)
                :suggested-fee-recipient
                (or (block-header-beneficiary parent-header)
                    (zero-address))
                :withdrawals '()
                :withdrawals-present-p
                (chain-config-shanghai-p config number timestamp)
                :parent-beacon-root (and cancun-p (zero-hash32))
                :parent-beacon-root-present-p cancun-p
                :slot-number (and amsterdam-p 0)
                :slot-number-present-p amsterdam-p))
             (transactions
               (engine-rpc-pending-build-transactions
                store config parent-header)))
        (engine-rpc-build-viable-prepared-payload
         store parent attributes config transactions)))))

(defun engine-rpc-handle-eth-get-block-by-number (params store config)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByNumber"))
         (expected-chain-id (chain-config-chain-id config)))
    (if (eth-rpc-pending-block-tag-p (first params))
        (multiple-value-bind (pending-block transactions)
            (eth-rpc-build-pending-block store config)
          (when pending-block
            (eth-rpc-pending-block-object
             pending-block
             transactions
             full-transactions-p
             config
             :expected-chain-id expected-chain-id)))
        (let* ((number (eth-rpc-block-number-param
                        (list (first params)) store "eth_getBlockByNumber"))
               (block (chain-store-block-by-number store number)))
          (when block
            (eth-rpc-block-object
             block full-transactions-p
             :expected-chain-id expected-chain-id))))))

(defun engine-rpc-handle-eth-get-block-by-hash (params store config)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByHash"))
         (hash (eth-rpc-hash-param
                (list (first params)) "eth_getBlockByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-block-object
       block full-transactions-p
       :expected-chain-id (chain-config-chain-id config)))))

(defun eth-rpc-block-transaction-count (block)
  (when block
    (quantity-to-hex (length (block-transactions block)))))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-number
    (params store config)
  (if (and (= 1 (length params))
           (eth-rpc-pending-block-tag-p (first params)))
      (multiple-value-bind (pending-block transactions)
          (eth-rpc-build-pending-block store config)
        (declare (ignore pending-block))
        (quantity-to-hex (length transactions)))
      (let* ((number (eth-rpc-block-number-param
                      params store
                      "eth_getBlockTransactionCountByNumber"))
             (block (chain-store-block-by-number store number)))
        (eth-rpc-block-transaction-count block))))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-hash
    (params store)
  (let* ((hash (eth-rpc-hash-param
                params
                "eth_getBlockTransactionCountByHash"
                "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-transaction-count block)))
