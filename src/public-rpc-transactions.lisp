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

(defun eth-rpc-transaction-index-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and transaction index" method))
  (engine-rpc-quantity-param params 1 "transaction index" method))

(defun eth-rpc-raw-transaction-by-index
    (block index &key expected-chain-id)
  (when (and block (< index (length (block-transactions block))))
    (eth-rpc-raw-transaction
     (nth index (block-transactions block))
     :expected-chain-id expected-chain-id)))

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

(defun eth-rpc-hash-table-object (table)
  (if (zerop (hash-table-count table))
      +json-empty-object+
      (loop for key in (sort (loop for key being the hash-keys of table
                                   collect key)
                             #'string<)
            collect (cons key (gethash key table)))))

(defun txpool-rpc-nonce-key< (left right)
  (< (parse-integer left :junk-allowed nil)
     (parse-integer right :junk-allowed nil)))

(defun txpool-rpc-indexed-nonce-transactions
    (sender-transactions value-function)
  (let ((entries
          (unless (or (null sender-transactions)
                      (zerop (hash-table-count sender-transactions)))
            (loop for nonce in (sort (loop for nonce being the hash-keys
                                             of sender-transactions
                                           collect nonce)
                                     #'txpool-rpc-nonce-key<)
                  for value = (funcall value-function
                                       (gethash nonce sender-transactions))
                  when value
                    collect (cons nonce value)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-nonce-transactions-from-sender-indexes
    (address value-function &rest sender-indexes)
  (let ((sender-key (address-to-hex address))
        (merged-transactions (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (let ((sender-transactions (gethash sender-key sender-index)))
        (when sender-transactions
          (maphash
           (lambda (nonce transaction)
             (setf (gethash nonce merged-transactions) transaction))
           sender-transactions))))
    (txpool-rpc-indexed-nonce-transactions
     merged-transactions
     value-function)))

(defun txpool-rpc-indexed-sender-transactions
    (sender-index value-function)
  (let ((entries
          (unless (zerop (hash-table-count sender-index))
            (loop for sender in (sort (loop for sender being the hash-keys
                                              of sender-index
                                            collect sender)
                                      #'string<)
                  for transactions =
                    (txpool-rpc-indexed-nonce-transactions
                     (gethash sender sender-index)
                     value-function)
                  unless (json-empty-object-p transactions)
                    collect (cons sender transactions)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-sender-transactions-from-indexes
    (value-function &rest sender-indexes)
  (let ((merged-senders (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (maphash
       (lambda (sender sender-transactions)
         (let ((merged-transactions
                 (or (gethash sender merged-senders)
                     (setf (gethash sender merged-senders)
                           (make-hash-table :test 'equal)))))
           (maphash
            (lambda (nonce transaction)
              (setf (gethash nonce merged-transactions) transaction))
            sender-transactions)))
       sender-index))
    (txpool-rpc-indexed-sender-transactions
     merged-senders
     value-function)))

(defun txpool-rpc-transaction-summary (transaction &key expected-chain-id)
  (when (transaction-sender
         transaction
         :expected-chain-id expected-chain-id)
    (let ((to (transaction-to transaction)))
      (format nil "~A: ~D wei + ~D gas x ~D wei"
              (if to
                  (address-to-hex to)
                  "contract creation")
              (transaction-value transaction)
              (transaction-gas-limit transaction)
              (transaction-max-fee-per-gas transaction)))))

(defun txpool-rpc-indexed-content-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (when (transaction-sender
            transaction
            :expected-chain-id expected-chain-id)
       (eth-rpc-pending-transaction-object
        transaction
        :expected-chain-id expected-chain-id)))))

(defun txpool-rpc-indexed-inspect-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (txpool-rpc-transaction-summary
      transaction
      :expected-chain-id expected-chain-id))))

(defun eth-rpc-raw-transaction-from-location
    (location &key expected-chain-id)
  (when location
    (eth-rpc-raw-transaction
     (engine-transaction-location-transaction location)
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-raw-transaction (transaction &key expected-chain-id)
  (when (and transaction
             (or (null expected-chain-id)
                 (transaction-sender
                  transaction
                  :expected-chain-id expected-chain-id)))
    (bytes-to-hex (transaction-encoding transaction))))

(defun eth-rpc-pooled-raw-transaction (transaction expected-chain-id)
  (eth-rpc-raw-transaction
   transaction
   :expected-chain-id expected-chain-id))

(defun eth-rpc-contract-creation-address (transaction sender)
  (when (and (null (transaction-to transaction)) sender)
    (let* ((hash (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender)
                                  (transaction-nonce transaction)))))
           (bytes (make-byte-vector 20)))
      (replace bytes hash :start2 12)
      (make-address bytes))))

(defun eth-rpc-validate-set-code-authorization-signatures (transaction)
  (validate-set-code-authorization-signatures transaction))

(defun eth-rpc-txpool-admission-head-context (store)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (values head
            (if header (block-header-number header) 0)
            (if header (block-header-timestamp header) 0))))

(defun eth-rpc-validate-txpool-sender-code (store head sender)
  (when head
    (let ((code (chain-store-account-code store (block-hash head) sender)))
      (when (and (plusp (length code))
                 (not (set-code-delegation-target code)))
        (block-validation-fail
         "eth_sendRawTransaction sender has non-delegation code"))))
  t)

(defun eth-rpc-txpool-upfront-cost (transaction)
  (engine-payload-store-txpool-upfront-cost transaction))

(defun eth-rpc-txpool-sender-admission-expenditure
    (store sender transaction)
  (engine-payload-store-sender-admission-expenditure
   store sender transaction))

(defun eth-rpc-validate-txpool-sender-state (store head sender transaction)
  (when (and head
             (chain-store-state-available-p store (block-hash head)))
    (let* ((block-hash (block-hash head))
           (state-nonce (chain-store-account-nonce store block-hash sender))
           (state-balance
             (chain-store-account-balance store block-hash sender)))
      (when (< (transaction-nonce transaction) state-nonce)
        (block-validation-fail "eth_sendRawTransaction nonce too low"))
      (when (< state-balance
               (eth-rpc-txpool-sender-admission-expenditure
                store
                sender
                transaction))
        (block-validation-fail
         "eth_sendRawTransaction insufficient sender balance"))))
  t)

(defun eth-rpc-txpool-queued-nonce-gap-p
    (store sender transaction &key expected-chain-id)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (and head
         (chain-store-state-available-p store (block-hash head))
         (> (transaction-nonce transaction)
            (engine-payload-store-pending-contiguous-nonce
             store
             sender
             (chain-store-account-nonce
              store
              (block-hash head)
              sender)
             :expected-chain-id expected-chain-id)))))

(defun eth-rpc-txpool-basefee-ineligible-p (store transaction)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (let* ((header (and head (block-header head)))
           (base-fee (and header
                          (block-header-base-fee-per-gas header))))
      (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee)))))

(defun eth-rpc-validate-txpool-admission
    (transaction sender store config)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (let ((rules (chain-config-rules config block-number timestamp)))
      (validate-transaction-type-for-config
       transaction config block-number timestamp)
      (validate-transaction-data-field transaction)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction))
      (engine-payload-store-validate-txpool-blob-fee-cap
       store
       transaction
       :chain-config config
       :label "eth_sendRawTransaction")
      (let ((intrinsic-gas
              (ethereum-lisp.state:transaction-intrinsic-gas
               transaction
               :eip3860-p (or (null rules)
                               (chain-rules-shanghai-p rules)))))
        (when (< (transaction-gas-limit transaction) intrinsic-gas)
          (block-validation-fail
           "eth_sendRawTransaction gas limit below intrinsic gas")))
      (when (and head
                 (> (transaction-gas-limit transaction)
                    (block-header-gas-limit (block-header head))))
        (block-validation-fail
         "eth_sendRawTransaction gas limit exceeds block gas limit"))
      (eth-rpc-validate-txpool-sender-state
       store head sender transaction)
      (eth-rpc-validate-txpool-sender-code store head sender)))
  t)

(defun eth-rpc-receipt-gas-used (receipt previous-receipt)
  (- (receipt-cumulative-gas-used receipt)
     (if previous-receipt
         (receipt-cumulative-gas-used previous-receipt)
         0)))

(defun eth-rpc-log-object
    (log block transaction transaction-index log-index &key removed-p)
  (let ((header (block-header block)))
    (list
     (cons "address" (address-to-hex (log-entry-address log)))
     (cons "topics" (mapcar #'hash32-to-hex
                            (log-entry-topics log)))
     (cons "data" (bytes-to-hex (log-entry-data log)))
     (cons "blockHash" (hash32-to-hex (block-hash block)))
     (cons "blockNumber"
           (quantity-to-hex (block-header-number header)))
     (cons "transactionHash"
           (hash32-to-hex (transaction-hash transaction)))
     (cons "transactionIndex" (quantity-to-hex transaction-index))
     (cons "logIndex" (quantity-to-hex log-index))
     (cons "removed" (if removed-p t :false)))))

(defun eth-rpc-receipt-object (location &key expected-chain-id)
  (let* ((receipt (engine-transaction-location-receipt location))
         (block (engine-transaction-location-block location))
         (transaction (engine-transaction-location-transaction location))
         (index (engine-transaction-location-index location)))
    (when receipt
      (let* ((header (block-header block))
             (previous-receipt
               (when (plusp index)
                 (nth (1- index) (block-receipts block))))
             (from (eth-rpc-transaction-sender
                    transaction
                    :expected-chain-id expected-chain-id))
             (logs
               (loop for log in (receipt-logs receipt)
                     for log-index
                       from (engine-transaction-location-log-index-start
                             location)
                     collect (eth-rpc-log-object
                              log block transaction index log-index))))
        (append
         (list
          (cons "transactionHash"
                (hash32-to-hex (transaction-hash transaction)))
          (cons "transactionIndex" (quantity-to-hex index))
          (cons "blockHash" (hash32-to-hex (block-hash block)))
          (cons "blockNumber"
                (quantity-to-hex (block-header-number header)))
          (cons "from" (address-to-hex from))
          (cons "to"
                (eth-rpc-address-or-null
                 (nth-value 3
                            (eth-rpc-transaction-core-fields
                             transaction))))
          (cons "cumulativeGasUsed"
                (quantity-to-hex
                 (receipt-cumulative-gas-used receipt)))
          (cons "gasUsed"
                (quantity-to-hex
                 (eth-rpc-receipt-gas-used receipt previous-receipt)))
          (cons "contractAddress"
                (eth-rpc-address-or-null
                 (eth-rpc-contract-creation-address transaction from)))
          (cons "logs" logs)
          (cons "logsBloom"
                (bytes-to-hex
                 (bloom-bytes
                  (receipt-bloom (receipt-logs receipt)))))
          (cons "type" (quantity-to-hex (transaction-type transaction)))
          (cons "effectiveGasPrice"
                (quantity-to-hex
                 (eth-rpc-transaction-gas-price transaction header))))
         (if (receipt-post-state receipt)
             (list (cons "root"
                         (bytes-to-hex (receipt-post-state receipt))))
             (list (cons "status"
                         (quantity-to-hex (receipt-status receipt))))))))))

(defun eth-rpc-block-receipts-object (block &key expected-chain-id)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block))))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for index from 0
          for location = (make-engine-transaction-location
                          :block block
                          :index index
                          :transaction transaction
                          :receipt receipt
                          :log-index-start log-index-start)
          collect (prog1 (eth-rpc-receipt-object
                          location
                          :expected-chain-id expected-chain-id)
                    (incf log-index-start
                          (length (receipt-logs receipt)))))))

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
           :expected-chain-id chain-id)))))

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
     :expected-chain-id (chain-config-chain-id config))))

(defun engine-rpc-handle-eth-get-raw-transaction-by-hash
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getRawTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-raw-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config))
        (eth-rpc-pooled-raw-transaction
         (engine-payload-store-pooled-transaction store hash)
         (chain-config-chain-id config)))))

(defun eth-rpc-unprotected-transaction-p (transaction)
  (and (typep transaction 'legacy-transaction)
       (not (legacy-transaction-protected-p transaction))))

(defun eth-rpc-validate-unprotected-transaction-policy
    (transaction allow-unprotected-transactions-p)
  (when (and (eth-rpc-unprotected-transaction-p transaction)
             (not allow-unprotected-transactions-p))
    (block-validation-fail
     "eth_sendRawTransaction unprotected legacy transaction rejected"))
  t)

(defun eth-rpc-validate-txpool-price-limit
    (transaction txpool-price-limit local-transaction-p)
  (when (and txpool-price-limit
             (not local-transaction-p)
             (plusp txpool-price-limit)
             (< (transaction-max-fee-per-gas transaction)
                txpool-price-limit))
    (block-validation-fail
     "eth_sendRawTransaction gas price below txpool price limit"))
  t)

(defun eth-rpc-local-transaction-p
    (sender txpool-local-addresses txpool-no-local-exemptions-p)
  (and (not txpool-no-local-exemptions-p)
       (some (lambda (local-address)
               (string= (address-to-hex sender)
                        (address-to-hex local-address)))
             txpool-local-addresses)))

(defun eth-rpc-local-transaction-predicate
    (config txpool-local-addresses txpool-no-local-exemptions-p)
  (lambda (transaction)
    (let ((sender
            (transaction-sender
             transaction
             :expected-chain-id (chain-config-chain-id config))))
      (and sender
           (eth-rpc-local-transaction-p
            sender
            txpool-local-addresses
            txpool-no-local-exemptions-p)))))

(defun eth-rpc-remove-expired-txpool-transactions
    (store config txpool-lifetime-seconds txpool-now
     txpool-local-addresses txpool-no-local-exemptions-p)
  (when txpool-lifetime-seconds
    (engine-payload-store-remove-expired-txpool-queued-view-transactions
     store
     txpool-lifetime-seconds
     txpool-now
     :local-transaction-predicate
     (eth-rpc-local-transaction-predicate
      config txpool-local-addresses txpool-no-local-exemptions-p))))

(defun engine-rpc-handle-eth-send-raw-transaction
    (params store config &key allow-unprotected-transactions-p
                              txpool-price-limit
                              txpool-price-bump-percent
                              txpool-account-slot-limit
                              txpool-global-slot-limit
                              txpool-account-queue-limit
                              txpool-global-queue-limit
                              txpool-local-addresses
                              txpool-no-local-exemptions-p
                              txpool-now)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_sendRawTransaction params must contain exactly one transaction"))
  (let* ((raw-bytes
            (engine-rpc-bytes
             (first params)
             "eth_sendRawTransaction transaction"))
         (transaction (transaction-from-encoding raw-bytes))
         (hash (transaction-hash transaction)))
    (validate-set-code-transaction-fields transaction)
    (eth-rpc-validate-set-code-authorization-signatures transaction)
    (let ((sender
            (or (transaction-sender
                 transaction
                 :expected-chain-id (chain-config-chain-id config))
                (block-validation-fail
                 "eth_sendRawTransaction transaction sender recovery failed"))))
      (let ((local-transaction-p
              (eth-rpc-local-transaction-p
               sender txpool-local-addresses txpool-no-local-exemptions-p)))
        (unless (or (chain-store-transaction-location store hash)
                    (engine-payload-store-pooled-transaction store hash))
          (eth-rpc-validate-unprotected-transaction-policy
           transaction
           allow-unprotected-transactions-p)
          (eth-rpc-validate-txpool-price-limit
           transaction
           txpool-price-limit
           local-transaction-p)
          (eth-rpc-validate-txpool-admission transaction sender store config)
          (cond
            ((typep transaction 'blob-transaction)
             (engine-payload-store-put-blob-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now))
            ((eth-rpc-txpool-basefee-ineligible-p store transaction)
             (engine-payload-store-put-basefee-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now))
            ((eth-rpc-txpool-queued-nonce-gap-p
              store
              sender
              transaction
              :expected-chain-id (chain-config-chain-id config))
             (engine-payload-store-put-queued-transaction
             store
             transaction
             :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now
              :account-queue-limit
              (unless local-transaction-p txpool-account-queue-limit)
              :global-queue-limit
              (unless local-transaction-p txpool-global-queue-limit)))
            (t
             (engine-payload-store-put-pending-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now
              :account-slot-limit
              (unless local-transaction-p txpool-account-slot-limit)
              :global-slot-limit
              (unless local-transaction-p txpool-global-slot-limit))
             (engine-payload-store-promote-queued-transactions
              store sender
              :expected-chain-id (chain-config-chain-id config)
              :account-slot-limit txpool-account-slot-limit
              :global-slot-limit txpool-global-slot-limit
              :local-transaction-predicate
              (lambda (transaction)
                (let ((sender
                        (transaction-sender
                         transaction
                         :expected-chain-id (chain-config-chain-id config))))
                  (and sender
                       (eth-rpc-local-transaction-p
                        sender
                        txpool-local-addresses
                        txpool-no-local-exemptions-p)))))
             (engine-payload-store-promote-basefee-and-queued-transactions
              store
              :expected-chain-id (chain-config-chain-id config)
              :account-slot-limit txpool-account-slot-limit
              :global-slot-limit txpool-global-slot-limit
              :local-transaction-predicate
              (lambda (transaction)
                (let ((sender
                        (transaction-sender
                         transaction
                         :expected-chain-id (chain-config-chain-id config))))
                  (and sender
                       (eth-rpc-local-transaction-p
                        sender
                        txpool-local-addresses
                        txpool-no-local-exemptions-p))))))))))
    (hash32-to-hex hash)))

(defun eth-rpc-txpool-queued-view-transactions (store)
  (append (engine-payload-store-queued-transactions store)
          (engine-payload-store-basefee-transactions store)
          (engine-payload-store-blob-transactions store)))

(defun eth-rpc-txpool-visible-transaction-count
    (transactions expected-chain-id)
  (count-if
   (lambda (transaction)
     (transaction-sender
      transaction
      :expected-chain-id expected-chain-id))
   transactions))

(defun eth-rpc-txpool-pending-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (engine-payload-store-pending-transactions store)
   expected-chain-id))

(defun eth-rpc-txpool-queued-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (eth-rpc-txpool-queued-view-transactions store)
   expected-chain-id))

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
           :expected-chain-id chain-id)))))

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
     :expected-chain-id (chain-config-chain-id config))))

(defun engine-rpc-handle-eth-get-transaction-by-hash (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config))
        (eth-rpc-pending-transaction-object
         (engine-payload-store-pooled-transaction store hash)
         :expected-chain-id (chain-config-chain-id config)))))
(defun engine-rpc-handle-eth-get-transaction-receipt (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionReceipt" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (when location
      (eth-rpc-receipt-object
       location
       :expected-chain-id (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-block-receipts (params store config)
  (if (eth-rpc-pending-block-id-param-p params "eth_getBlockReceipts")
      nil
      (let ((block (eth-rpc-block-param params store "eth_getBlockReceipts")))
        (eth-rpc-block-receipts-object
         block
         :expected-chain-id (chain-config-chain-id config)))))
