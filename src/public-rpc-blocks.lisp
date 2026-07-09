(in-package #:ethereum-lisp.core)

(defun eth-rpc-header-object (header)
  (unless (block-header-p header)
    (block-validation-fail "eth header result must be a block header"))
  (append
   (list
    (cons "number" (quantity-to-hex (block-header-number header)))
    (cons "hash" (hash32-to-hex (block-header-hash header)))
    (cons "parentHash"
          (hash32-to-hex (or (block-header-parent-hash header)
                             (zero-hash32))))
    (cons "nonce"
          (bytes-to-hex (or (block-header-nonce header)
                            (make-byte-vector 8))))
    (cons "mixHash"
          (hash32-to-hex (or (block-header-mix-hash header)
                             (zero-hash32))))
    (cons "sha3Uncles"
          (hash32-to-hex (or (block-header-ommers-hash header)
                             +empty-ommers-hash+)))
    (cons "logsBloom"
          (bytes-to-hex (or (block-header-logs-bloom header)
                            (make-byte-vector 256))))
    (cons "stateRoot"
          (hash32-to-hex (or (block-header-state-root header)
                             +empty-trie-hash+)))
    (cons "miner"
          (address-to-hex (or (block-header-beneficiary header)
                              (zero-address))))
    (cons "difficulty" (quantity-to-hex (block-header-difficulty header)))
    (cons "extraData" (bytes-to-hex (block-header-extra-data header)))
    (cons "gasLimit" (quantity-to-hex (block-header-gas-limit header)))
    (cons "gasUsed" (quantity-to-hex (block-header-gas-used header)))
    (cons "timestamp" (quantity-to-hex (block-header-timestamp header)))
    (cons "transactionsRoot"
          (hash32-to-hex (or (block-header-transactions-root header)
                             +empty-trie-hash+)))
    (cons "receiptsRoot"
          (hash32-to-hex (or (block-header-receipts-root header)
                             +empty-trie-hash+))))
   (when (block-header-base-fee-per-gas header)
     (list (cons "baseFeePerGas"
                 (quantity-to-hex
                  (block-header-base-fee-per-gas header)))))
   (when (block-header-withdrawals-root header)
     (list (cons "withdrawalsRoot"
                 (hash32-to-hex
                  (block-header-withdrawals-root header)))))
   (when (block-header-blob-gas-used header)
     (list (cons "blobGasUsed"
                 (quantity-to-hex (block-header-blob-gas-used header)))))
   (when (block-header-excess-blob-gas header)
     (list (cons "excessBlobGas"
                 (quantity-to-hex
                  (block-header-excess-blob-gas header)))))
   (when (block-header-parent-beacon-root header)
     (list (cons "parentBeaconBlockRoot"
                 (hash32-to-hex
                  (block-header-parent-beacon-root header)))))
   (when (block-header-requests-hash header)
     (list (cons "requestsHash"
                 (hash32-to-hex (block-header-requests-hash header)))))
   (when (block-header-block-access-list-hash header)
     (list (cons "balHash"
                 (hash32-to-hex
                  (block-header-block-access-list-hash header)))))
   (when (block-header-slot-number header)
     (list (cons "slotNumber"
                 (quantity-to-hex (block-header-slot-number header)))))))

(defun eth-rpc-object-field (object name)
  (assoc name object :test #'string=))

(defun eth-rpc-set-object-field (object name value)
  (let ((field (eth-rpc-object-field object name)))
    (if field
        (progn
          (setf (cdr field) value)
          object)
        (append object (list (cons name value))))))

(defun eth-rpc-pending-base-fee (base-header config)
  (when (or (block-header-base-fee-per-gas base-header)
            (chain-config-london-p
             config
             (1+ (block-header-number base-header))))
    (eth-rpc-fee-history-next-base-fee base-header config)))

(defun eth-rpc-pending-header-object (base-header config)
  (let ((object (eth-rpc-header-object base-header)))
    (eth-rpc-set-object-field
     object
     "number"
     (quantity-to-hex (1+ (block-header-number base-header))))
    (eth-rpc-set-object-field object "parentHash"
                              (hash32-to-hex
                               (block-header-hash base-header)))
    (eth-rpc-set-object-field object "hash" nil)
    (eth-rpc-set-object-field object "nonce" nil)
    (let ((base-fee (eth-rpc-pending-base-fee base-header config)))
      (when base-fee
        (eth-rpc-set-object-field object "baseFeePerGas" base-fee)))
    object))

(defun engine-rpc-handle-eth-get-header-by-number (params store config)
  (if (and (= 1 (length params))
           (eth-rpc-pending-block-tag-p (first params)))
      (let ((block (chain-store-latest-block store)))
        (when block
          (eth-rpc-pending-header-object (block-header block) config)))
      (let* ((number (eth-rpc-block-number-param
                      params store "eth_getHeaderByNumber"))
             (block (chain-store-block-by-number store number)))
        (when block
          (eth-rpc-header-object (block-header block))))))

(defun engine-rpc-handle-eth-get-header-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getHeaderByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-header-object (block-header block)))))

(defun eth-rpc-rlp-length-prefix (offset length)
  (if (<= length 55)
      (ensure-byte-vector (list (+ offset length)))
      (let ((length-bytes (integer-to-minimal-bytes length)))
        (concat-bytes
         (ensure-byte-vector (list (+ offset 55 (length length-bytes))))
         length-bytes))))

(defun eth-rpc-encoded-rlp-list (encoded-items)
  (let ((payload (if encoded-items
                     (apply #'concat-bytes encoded-items)
                     (make-byte-vector 0))))
    (concat-bytes (eth-rpc-rlp-length-prefix #xc0 (length payload))
                  payload)))

(defun eth-rpc-block-rlp (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (let ((items
          (list
           (block-header-rlp (block-header block))
           (eth-rpc-encoded-rlp-list
            (mapcar #'transaction-encoding (block-transactions block)))
           (eth-rpc-encoded-rlp-list
            (mapcar #'block-header-rlp (block-ommers block))))))
    (when (block-withdrawals-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'withdrawal-rlp
                                   (block-withdrawals block)))))))
    (when (block-requests-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'rlp-encode
                                   (block-requests block)))))))
    (when (block-block-access-list-present-p block)
      (setf items
            (append items
                    (list (or (block-encoded-block-access-list block)
                              (block-access-list-rlp
                               (block-block-access-list block)))))))
    (eth-rpc-encoded-rlp-list items)))

(defun eth-rpc-block-full-transactions-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and full transaction flag" method))
  (let ((full-transactions-p (second params)))
    (unless (or (null full-transactions-p)
                (eq full-transactions-p t))
      (block-validation-fail
       "~A full transaction flag must be a boolean" method))
    full-transactions-p))

(defun eth-rpc-block-transactions-object
    (block full-transactions-p &key expected-chain-id)
  (if full-transactions-p
      (loop for transaction in (block-transactions block)
            for index from 0
            collect (eth-rpc-transaction-object
                     transaction block index
                     :expected-chain-id expected-chain-id))
      (mapcar (lambda (transaction)
                (hash32-to-hex (transaction-hash transaction)))
              (block-transactions block))))

(defun eth-rpc-block-object (block full-transactions-p &key expected-chain-id)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (append
   (eth-rpc-header-object (block-header block))
   (list
    (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
    (cons "transactions"
          (eth-rpc-block-transactions-object
           block full-transactions-p
           :expected-chain-id expected-chain-id))
    (cons "uncles"
          (mapcar (lambda (ommer)
                    (hash32-to-hex (block-header-hash ommer)))
                  (block-ommers block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun eth-rpc-pending-block-transactions-object
    (transactions full-transactions-p &key expected-chain-id)
  (eth-rpc-json-array
   (if full-transactions-p
       (loop for transaction in transactions
             collect (eth-rpc-pending-transaction-object
                      transaction
                      :expected-chain-id expected-chain-id))
       (mapcar (lambda (transaction)
                 (hash32-to-hex (transaction-hash transaction)))
               transactions))))

(defun eth-rpc-pending-block-object
    (base-block transactions full-transactions-p config &key expected-chain-id)
  (let ((object
          (eth-rpc-block-object
           base-block full-transactions-p
           :expected-chain-id expected-chain-id)))
    (eth-rpc-set-object-field object "number"
                              (quantity-to-hex
                               (1+ (block-header-number
                                    (block-header base-block)))))
    (eth-rpc-set-object-field object "parentHash"
                              (hash32-to-hex
                               (block-hash base-block)))
    (eth-rpc-set-object-field object "hash" nil)
    (eth-rpc-set-object-field object "nonce" nil)
    (let ((base-fee
            (eth-rpc-pending-base-fee (block-header base-block) config)))
      (when base-fee
        (eth-rpc-set-object-field object "baseFeePerGas" base-fee)))
    (eth-rpc-set-object-field
     object
     "transactions"
     (eth-rpc-pending-block-transactions-object
      transactions full-transactions-p
      :expected-chain-id expected-chain-id))
    object))

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

(defun eth-rpc-block-ommer-count (block)
  (when block
    (quantity-to-hex (length (block-ommers block)))))

(defun eth-rpc-ommer-object (header)
  (when header
    (let ((block (make-block :header header)))
      (append
       (eth-rpc-header-object header)
       (list
        (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
        (cons "uncles" '()))))))

(defun eth-rpc-ommer-by-index (block index)
  (when (and block (< index (length (block-ommers block))))
    (eth-rpc-ommer-object (nth index (block-ommers block)))))

(defun engine-rpc-handle-eth-get-uncle-count-by-number (params store)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_getUncleCountByBlockNumber params must contain exactly one block number"))
  (if (eth-rpc-pending-block-tag-p (first params))
      (quantity-to-hex 0)
      (let* ((number (eth-rpc-block-number-param
                      params store "eth_getUncleCountByBlockNumber"))
             (block (chain-store-block-by-number store number)))
        (eth-rpc-block-ommer-count block))))

(defun engine-rpc-handle-eth-get-uncle-count-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getUncleCountByBlockHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-by-block-number-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockNumberAndIndex params must contain block id and uncle index"))
  (if (eth-rpc-pending-block-tag-p (first params))
      (progn
        (engine-rpc-quantity-param
         params 1 "uncle index" "eth_getUncleByBlockNumberAndIndex")
        nil)
      (let* ((number (eth-rpc-block-number-param
                      (list (first params)) store
                      "eth_getUncleByBlockNumberAndIndex"))
             (index (engine-rpc-quantity-param
                     params 1 "uncle index"
                     "eth_getUncleByBlockNumberAndIndex"))
             (block (chain-store-block-by-number store number)))
        (eth-rpc-ommer-by-index block index))))

(defun engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockHashAndIndex params must contain block id and uncle index"))
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getUncleByBlockHashAndIndex"
                "block hash"))
         (index (engine-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-ommer-by-index block index)))
