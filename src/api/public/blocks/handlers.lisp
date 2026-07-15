(in-package #:ethereum-lisp.public-api)

(defun engine-rpc-handle-eth-get-block-by-number (params store config)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByNumber"))
         (expected-chain-id (chain-config-chain-id config)))
    (if (eth-rpc-pending-block-tag-p (first params))
        (let ((base-block (chain-store-latest-block store)))
          (when base-block
            (eth-rpc-pending-block-object
             base-block
             (eth-rpc-visible-pending-transactions store expected-chain-id)
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
      (quantity-to-hex
       (length
        (eth-rpc-visible-pending-transactions
         store
         (chain-config-chain-id config))))
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
