(in-package #:ethereum-lisp.public-api)

(defun engine-rpc-handle-eth-pending-transactions (params store config)
  (when params
    (block-validation-fail "eth_pendingTransactions params must be empty"))
  (eth-rpc-pending-transaction-objects
   (engine-payload-store-pending-transactions store)
   :expected-chain-id (chain-config-chain-id config)))

(defun engine-rpc-handle-txpool-status (params store config)
  (when params
    (block-validation-fail "txpool_status params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (quantity-to-hex
            (eth-rpc-txpool-pending-view-count store chain-id)))
     (cons "queued"
           (quantity-to-hex
            (eth-rpc-txpool-queued-view-count store chain-id))))))

(defun engine-rpc-handle-txpool-content (params store config)
  (when params
    (block-validation-fail "txpool_content params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-content-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-txpool-content-from (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "txpool_contentFrom params must contain exactly one address"))
  (let ((address (eth-rpc-address-param
                  (first params) "txpool_contentFrom" "address"))
        (chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-nonce-transactions
            (gethash
             (address-to-hex address)
             (engine-payload-store-pending-transactions-by-sender store))
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))))
     (cons "queued"
           (txpool-rpc-indexed-nonce-transactions-from-sender-indexes
            address
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-txpool-inspect (params store config)
  (when params
    (block-validation-fail "txpool_inspect params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-inspect-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (txpool-rpc-transaction-summary
               transaction
               :expected-chain-id chain-id))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))
