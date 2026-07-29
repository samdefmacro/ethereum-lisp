(in-package #:ethereum-lisp.blocks)

(defun hash-or-zero (hash)
  (hash32-bytes (or hash (zero-hash32))))

(defun address-or-zero (address)
  (address-bytes (or address (zero-address))))

(defun header-fields (header)
  (let ((fields
          (list
           (hash-or-zero (block-header-parent-hash header))
           (hash32-bytes (or (block-header-ommers-hash header) +empty-ommers-hash+))
           (address-or-zero (block-header-beneficiary header))
           (hash32-bytes (or (block-header-state-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-transactions-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-receipts-root header) +empty-trie-hash+))
           (optional-bytes (or (block-header-logs-bloom header) (make-byte-vector 256))
                           256 "Logs bloom")
           (ensure-uint256 (block-header-difficulty header) "Header difficulty")
           (ensure-uint256 (block-header-number header) "Header number")
           (ensure-uint256 (block-header-gas-limit header) "Header gas limit")
           (ensure-uint256 (block-header-gas-used header) "Header gas used")
           (ensure-uint256 (block-header-timestamp header) "Header timestamp")
           (ensure-byte-vector (block-header-extra-data header))
           (hash-or-zero (block-header-mix-hash header))
           (optional-bytes (or (block-header-nonce header) (make-byte-vector 8))
                           8 "Header nonce"))))
    (let* ((presence
             (list (block-header-base-fee-per-gas header)
                   (block-header-withdrawals-root header)
                   (block-header-blob-gas-used header)
                   (block-header-excess-blob-gas header)
                   (block-header-parent-beacon-root header)
                   (block-header-requests-hash header)
                   (block-header-block-access-list-hash header)
                   (block-header-slot-number header)))
           (optional-fields
             (list
              (ensure-uint256
               (or (block-header-base-fee-per-gas header) 0)
               "Header base fee")
              (hash32-bytes
               (or (block-header-withdrawals-root header) (zero-hash32)))
              (ensure-uint256
               (or (block-header-blob-gas-used header) 0)
               "Header blob gas used")
              (ensure-uint256
               (or (block-header-excess-blob-gas header) 0)
               "Header excess blob gas")
              (hash32-bytes
               (or (block-header-parent-beacon-root header) (zero-hash32)))
              (hash32-bytes
               (or (block-header-requests-hash header) (zero-hash32)))
              (hash32-bytes
               (or (block-header-block-access-list-hash header)
                   (zero-hash32)))
              (ensure-uint256
               (or (block-header-slot-number header) 0)
               "Header slot number")))
           (last-present (position-if #'identity presence :from-end t)))
      ;; Never shift a later optional field into an earlier field's position.
      ;; Incomplete local templates receive typed zero placeholders; fork-aware
      ;; validation still rejects those shapes at an import boundary.
      (when last-present
        (setf fields
              (append fields (subseq optional-fields 0 (1+ last-present))))))
    fields))

(defun block-header-rlp-object (header)
  (apply #'make-rlp-list (header-fields header)))

(defun block-header-rlp (header)
  (rlp-encode (block-header-rlp-object header)))

(defun block-header-seal-hash (header)
  "Return the Ethash sealing hash, excluding MIX-HASH and NONCE.
Fork fields after NONCE, notably London's BASE-FEE-PER-GAS, remain covered."
  (let ((fields (header-fields header)))
    (keccak-256-hash
     (rlp-encode
      (apply #'make-rlp-list
             (append (subseq fields 0 13)
                     (subseq fields 15)))))))

(defun block-header-hash (header)
  (keccak-256-hash (block-header-rlp header)))

(defun ommers-hash (ommers)
  (keccak-256-hash
   (rlp-encode
    (mapcar #'block-header-rlp-object ommers))))

(defun receipts-logs-bloom (receipts)
  (receipt-bloom
   (loop for receipt in receipts
         append (receipt-logs receipt))))
