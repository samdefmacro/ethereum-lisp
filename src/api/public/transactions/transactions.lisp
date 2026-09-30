(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-transaction-index-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and transaction index" method))
  (json-rpc-quantity-param params 1 "transaction index" method))

(defun eth-rpc-raw-transaction (transaction &key expected-chain-id rules)
  "TRANSACTION's encoding as hex when its sender recovers under the signer
RULES select for EXPECTED-CHAIN-ID (ETH-RPC-SIGNER-RULES), or NIL."
  (when (and transaction
             (or (null expected-chain-id)
                 (eth-rpc-transaction-sender-or-nil
                  transaction
                  :expected-chain-id expected-chain-id
                  :rules rules)))
    (bytes-to-hex (transaction-encoding transaction))))

(defun eth-rpc-raw-transaction-from-location
    (location &key expected-chain-id config)
  (when location
    (eth-rpc-raw-transaction
     (engine-transaction-location-transaction location)
     :expected-chain-id expected-chain-id
     :rules (eth-rpc-block-signer-rules
             config (engine-transaction-location-block location)))))

(defun eth-rpc-pooled-raw-transaction (transaction expected-chain-id)
  (eth-rpc-raw-transaction
   transaction
   :expected-chain-id expected-chain-id))

(defun eth-rpc-raw-transaction-by-index
    (block index &key expected-chain-id config)
  (when (and block (< index (length (block-transactions block))))
    (eth-rpc-raw-transaction
     (nth index (block-transactions block))
     :expected-chain-id expected-chain-id
     :rules (eth-rpc-block-signer-rules config block))))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
    (params store config)
  (let ((index (eth-rpc-transaction-index-param
                params "eth_getRawTransactionByBlockNumberAndIndex"))
        (chain-id (chain-config-chain-id config)))
    (if (eth-rpc-pending-block-tag-p (first params))
        (eth-rpc-raw-transaction
         (eth-rpc-pending-transaction-by-index
          store index :expected-chain-id chain-id)
         :expected-chain-id chain-id)
        (let* ((number (eth-rpc-block-number-param
                        (list (first params)) store
                        "eth_getRawTransactionByBlockNumberAndIndex"))
               (block (chain-store-block-by-number store number)))
          (eth-rpc-raw-transaction-by-index
           block
           index
           :expected-chain-id chain-id
           :config config)))))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getRawTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getRawTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-raw-transaction-by-index
     block
     index
     :expected-chain-id (chain-config-chain-id config)
     :config config)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-hash
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getRawTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-raw-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config)
         :config config)
        (eth-rpc-pooled-raw-transaction
         (engine-payload-store-pooled-transaction store hash)
         (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-transaction-by-block-number-and-index
    (params store config)
  (let ((index (eth-rpc-transaction-index-param
                params "eth_getTransactionByBlockNumberAndIndex"))
        (chain-id (chain-config-chain-id config)))
    (if (eth-rpc-pending-block-tag-p (first params))
        (eth-rpc-pending-transaction-object
         (eth-rpc-pending-transaction-by-index
          store index :expected-chain-id chain-id)
         :expected-chain-id chain-id)
        (let* ((number (eth-rpc-block-number-param
                        (list (first params)) store
                        "eth_getTransactionByBlockNumberAndIndex"))
               (block (chain-store-block-by-number store number)))
          (eth-rpc-transaction-by-index
           block index
           :expected-chain-id chain-id
           :config config)))))

(defun engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-transaction-by-index
     block index
     :expected-chain-id (chain-config-chain-id config)
     :config config)))

(defun engine-rpc-handle-eth-get-transaction-by-hash (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config)
         :config config)
        (eth-rpc-pending-transaction-object
         (engine-payload-store-pooled-transaction store hash)
         :expected-chain-id (chain-config-chain-id config)))))
