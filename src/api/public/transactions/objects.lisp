(in-package #:ethereum-lisp.public-api)

;;;; Transaction JSON object assembly and pending-transaction lookup helpers.

(defun eth-rpc-visible-pending-transactions (store expected-chain-id)
  (loop for transaction in (engine-payload-store-pending-transactions store)
        when (transaction-sender
              transaction
              :expected-chain-id expected-chain-id)
          collect transaction))

(defun eth-rpc-pending-transaction-by-index
    (store index &key expected-chain-id)
  (let ((transactions
          (eth-rpc-visible-pending-transactions store expected-chain-id)))
    (when (< index (length transactions))
      (nth index transactions))))

(defun eth-rpc-transaction-object
    (transaction block index &key expected-chain-id)
  (let ((header (when block
                  (block-header block))))
    (multiple-value-bind (nonce gas-limit to value data v r s)
        (eth-rpc-transaction-core-fields transaction)
      (append
       (list
        (cons "blockHash" (when block
                            (hash32-to-hex (block-hash block))))
        (cons "blockNumber"
              (when header
                (quantity-to-hex (block-header-number header))))
        (cons "blockTimestamp"
              (when header
                (quantity-to-hex (block-header-timestamp header))))
        (cons "from"
              (address-to-hex
               (eth-rpc-transaction-sender
                transaction
                :expected-chain-id expected-chain-id)))
        (cons "gas" (quantity-to-hex gas-limit))
        (cons "gasPrice"
              (quantity-to-hex
               (eth-rpc-transaction-gas-price transaction header)))
        (cons "hash" (hash32-to-hex (transaction-hash transaction)))
        (cons "input" (bytes-to-hex data))
        (cons "nonce" (quantity-to-hex nonce))
        (cons "to" (eth-rpc-address-or-null to))
        (cons "transactionIndex" (when index
                                   (quantity-to-hex index)))
        (cons "value" (quantity-to-hex value))
        (cons "type" (quantity-to-hex (transaction-type transaction))))
       (eth-rpc-transaction-type-fields transaction)
       (list
        (cons "v" (quantity-to-hex v))
        (cons "r" (quantity-to-hex r))
        (cons "s" (quantity-to-hex s)))))))

(defun eth-rpc-transaction-by-index (block index &key expected-chain-id)
  (when (and block (< index (length (block-transactions block))))
    (eth-rpc-transaction-object
     (nth index (block-transactions block)) block index
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-transaction-from-location (location &key expected-chain-id)
  (when location
    (eth-rpc-transaction-object
     (engine-transaction-location-transaction location)
     (engine-transaction-location-block location)
     (engine-transaction-location-index location)
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-pending-transaction-object (transaction &key expected-chain-id)
  (when transaction
    (eth-rpc-transaction-object
     transaction nil nil
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-json-array (items)
  (if items
      items
      (make-array 0)))

(defun eth-rpc-pending-transaction-objects
    (transactions &key expected-chain-id)
  (eth-rpc-json-array
   (loop for transaction in transactions
         when (transaction-sender
               transaction
               :expected-chain-id expected-chain-id)
           collect (eth-rpc-pending-transaction-object
                    transaction
                    :expected-chain-id expected-chain-id))))
