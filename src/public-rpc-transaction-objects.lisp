(in-package #:ethereum-lisp.core)

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

(defun eth-rpc-address-or-null (address)
  (when address
    (address-to-hex address)))

(defun eth-rpc-access-list-entry-object (entry)
  (list
   (cons "address" (address-to-hex (access-list-entry-address entry)))
   (cons "storageKeys"
         (mapcar #'hash32-to-hex
                 (access-list-entry-storage-keys entry)))))

(defun eth-rpc-access-list-object (access-list)
  (mapcar #'eth-rpc-access-list-entry-object access-list))

(defun eth-rpc-set-code-authorization-object (authorization)
  (list
   (cons "chainId"
         (quantity-to-hex
          (set-code-authorization-chain-id authorization)))
   (cons "address"
         (address-to-hex
          (set-code-authorization-address authorization)))
   (cons "nonce"
         (quantity-to-hex
          (set-code-authorization-nonce authorization)))
   (cons "yParity"
         (quantity-to-hex
          (set-code-authorization-y-parity authorization)))
   (cons "r" (quantity-to-hex (set-code-authorization-r authorization)))
   (cons "s" (quantity-to-hex (set-code-authorization-s authorization)))))

(defun eth-rpc-transaction-core-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (values (legacy-transaction-nonce transaction)
             (legacy-transaction-gas-price transaction)
             (legacy-transaction-gas-limit transaction)
             (legacy-transaction-to transaction)
             (legacy-transaction-value transaction)
             (legacy-transaction-data transaction)
             (legacy-transaction-v transaction)
             (legacy-transaction-r transaction)
             (legacy-transaction-s transaction)))
    (access-list-transaction
     (values (access-list-transaction-nonce transaction)
             (access-list-transaction-gas-price transaction)
             (access-list-transaction-gas-limit transaction)
             (access-list-transaction-to transaction)
             (access-list-transaction-value transaction)
             (access-list-transaction-data transaction)
             (access-list-transaction-y-parity transaction)
             (access-list-transaction-r transaction)
             (access-list-transaction-s transaction)))
    (dynamic-fee-transaction
     (values (dynamic-fee-transaction-nonce transaction)
             (dynamic-fee-transaction-max-fee-per-gas transaction)
             (dynamic-fee-transaction-gas-limit transaction)
             (dynamic-fee-transaction-to transaction)
             (dynamic-fee-transaction-value transaction)
             (dynamic-fee-transaction-data transaction)
             (dynamic-fee-transaction-y-parity transaction)
             (dynamic-fee-transaction-r transaction)
             (dynamic-fee-transaction-s transaction)))
    (blob-transaction
     (values (blob-transaction-nonce transaction)
             (blob-transaction-max-fee-per-gas transaction)
             (blob-transaction-gas-limit transaction)
             (blob-transaction-to transaction)
             (blob-transaction-value transaction)
             (blob-transaction-data transaction)
             (blob-transaction-y-parity transaction)
             (blob-transaction-r transaction)
             (blob-transaction-s transaction)))
    (set-code-transaction
     (values (set-code-transaction-nonce transaction)
             (set-code-transaction-max-fee-per-gas transaction)
             (set-code-transaction-gas-limit transaction)
             (set-code-transaction-to transaction)
             (set-code-transaction-value transaction)
             (set-code-transaction-data transaction)
             (set-code-transaction-y-parity transaction)
             (set-code-transaction-r transaction)
             (set-code-transaction-s transaction)))))

(defun eth-rpc-transaction-gas-price (transaction header)
  (if (or (typep transaction 'legacy-transaction)
          (typep transaction 'access-list-transaction)
          (not header)
          (not (block-header-base-fee-per-gas header)))
      (transaction-max-fee-per-gas transaction)
      (transaction-effective-gas-price
       transaction :base-fee (block-header-base-fee-per-gas header))))

(defun eth-rpc-transaction-sender (transaction &key expected-chain-id)
  (or (transaction-sender transaction
                          :expected-chain-id expected-chain-id)
      (block-validation-fail
       "eth transaction sender recovery failed")))

(defun eth-rpc-transaction-type-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (let ((chain-id (legacy-transaction-chain-id transaction)))
       (when (and chain-id (plusp chain-id))
         (list (cons "chainId" (quantity-to-hex chain-id))))))
    (access-list-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (access-list-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (access-list-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (access-list-transaction-y-parity transaction)))))
    (dynamic-fee-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (dynamic-fee-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (dynamic-fee-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (dynamic-fee-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-priority-fee-per-gas transaction)))))
    (blob-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (blob-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (blob-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (blob-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-priority-fee-per-gas transaction)))
      (cons "maxFeePerBlobGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-blob-gas transaction)))
      (cons "blobVersionedHashes"
            (mapcar #'hash32-to-hex
                    (blob-transaction-blob-versioned-hashes
                     transaction)))))
    (set-code-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (set-code-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (set-code-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (set-code-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-priority-fee-per-gas transaction)))
      (cons "authorizationList"
            (mapcar #'eth-rpc-set-code-authorization-object
                    (set-code-transaction-authorization-list
                     transaction)))))))

(defun eth-rpc-transaction-object
    (transaction block index &key expected-chain-id)
  (let ((header (when block
                  (block-header block))))
    (multiple-value-bind (nonce gas-price gas-limit to value data v r s)
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
