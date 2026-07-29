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
    (let ((optional-fields
            (list
             (and (block-header-base-fee-per-gas header)
                  (ensure-uint256 (block-header-base-fee-per-gas header)
                                  "Header base fee"))
             (and (block-header-withdrawals-root header)
                  (hash32-bytes (block-header-withdrawals-root header)))
             (and (block-header-blob-gas-used header)
                  (ensure-uint256 (block-header-blob-gas-used header)
                                  "Header blob gas used"))
             (and (block-header-excess-blob-gas header)
                  (ensure-uint256 (block-header-excess-blob-gas header)
                                  "Header excess blob gas"))
             (and (block-header-parent-beacon-root header)
                  (hash32-bytes (block-header-parent-beacon-root header)))
             (and (block-header-requests-hash header)
                  (hash32-bytes (block-header-requests-hash header)))
             (and (block-header-block-access-list-hash header)
                  (hash32-bytes
                   (block-header-block-access-list-hash header)))
             (and (block-header-slot-number header)
                  (ensure-uint256 (block-header-slot-number header)
                                  "Header slot number")))))
      (loop with gap-seen-p = nil
            for value in optional-fields
            do (if value
                   (if gap-seen-p
                       (error "Header optional fields must form a contiguous prefix")
                       (setf fields (append fields (list value))))
                   (setf gap-seen-p t))))
    fields))

(defun block-header-rlp-object (header)
  (apply #'make-rlp-list (header-fields header)))

(defun block-header-rlp (header)
  (rlp-encode (block-header-rlp-object header)))

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
