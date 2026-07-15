(in-package #:ethereum-lisp.public-api)

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
