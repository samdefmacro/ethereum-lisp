(in-package #:ethereum-lisp.consensus)

;;;; Fork-specific block header field presence and merge transition checks.

(defparameter +dao-fork-extra-data+
  (ethereum-lisp.hex:hex-to-bytes
   "0x64616f2d686172642d666f726b"))
(defconstant +dao-fork-extra-range+ 10)

(defun validate-block-dao-extra-data (header config)
  (let ((fork-block (chain-config-dao-fork-block config)))
    (when (and fork-block
               (<= fork-block (block-header-number header))
               (< (block-header-number header)
                  (+ fork-block +dao-fork-extra-range+)))
      (let ((matches-p
              (bytes= (ensure-byte-vector (block-header-extra-data header))
                      +dao-fork-extra-data+)))
        (if (chain-config-dao-fork-support config)
            (unless matches-p
              (block-validation-fail
               "DAO-supporting header is missing dao-hard-fork extra data"))
            (when matches-p
              (block-validation-fail
               "DAO-opposing header contains dao-hard-fork extra data"))))))
  t)

(defun block-header-cancun-fields-present-p (header)
  (or (block-header-blob-gas-used header)
      (block-header-excess-blob-gas header)))

(defun validate-block-cancun-fields
    (header &key (cancun-enabled-p
                  (block-header-cancun-fields-present-p header)))
  (if cancun-enabled-p
      (unless (block-header-parent-beacon-root header)
        (block-validation-fail "Header is missing parent beacon root"))
      (when (block-header-parent-beacon-root header)
        (block-validation-fail "Parent beacon root present before Cancun")))
  t)

(defun validate-block-withdrawals-field
    (header &key (withdrawals-enabled-p (block-header-withdrawals-root header)))
  (if withdrawals-enabled-p
      (unless (block-header-withdrawals-root header)
        (block-validation-fail "Header is missing withdrawals root"))
      (when (block-header-withdrawals-root header)
        (block-validation-fail "Withdrawals root present before Shanghai")))
  t)

(defun validate-block-requests-hash-field
    (header &key (requests-enabled-p (block-header-requests-hash header)))
  (if requests-enabled-p
      (unless (block-header-requests-hash header)
        (block-validation-fail "Header is missing requests hash"))
      (when (block-header-requests-hash header)
        (block-validation-fail "Requests hash present before Prague")))
  t)

(defun block-header-amsterdam-fields-present-p (header)
  (or (block-header-block-access-list-hash header)
      (block-header-slot-number header)))

(defun validate-block-amsterdam-fields
    (header &key (amsterdam-enabled-p
                  (block-header-amsterdam-fields-present-p header)))
  (if amsterdam-enabled-p
      (progn
        (unless (block-header-block-access-list-hash header)
          (block-validation-fail
           "Header is missing block access list hash"))
        (unless (block-header-slot-number header)
          (block-validation-fail "Header is missing slot number")))
      (progn
        (when (block-header-block-access-list-hash header)
          (block-validation-fail
           "Block access list hash present before Amsterdam"))
        (when (block-header-slot-number header)
          (block-validation-fail "Slot number present before Amsterdam"))))
  t)

(defun validate-block-amsterdam-slot-number (parent-header header)
  (let ((parent-slot-number (block-header-slot-number parent-header))
        (slot-number (block-header-slot-number header)))
    (when (and parent-slot-number
               slot-number
               (<= slot-number parent-slot-number))
      (block-validation-fail
       "Amsterdam header slot number must exceed parent slot number")))
  t)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun block-header-zero-nonce-p (header)
  (let ((nonce (block-header-nonce header)))
    (or (null nonce)
        (let ((bytes (ensure-byte-vector nonce)))
          (and (= 8 (length bytes))
               (every #'zerop bytes))))))

(defun validate-block-merge-transition (parent-header header)
  (when (and (block-header-post-merge-p parent-header)
             (plusp (block-header-difficulty header)))
    (block-validation-fail "Cannot revert from post-Merge to PoW difficulty"))
  t)

(defun validate-block-merge-fields
    (header &key (post-merge-p (block-header-post-merge-p header)))
  (when post-merge-p
    (unless (zerop (block-header-difficulty header))
      (block-validation-fail "Post-Merge header difficulty must be zero"))
    (unless (block-header-zero-nonce-p header)
      (block-validation-fail "Post-Merge header nonce must be zero"))
    (unless (hash32= (or (block-header-ommers-hash header) +empty-ommers-hash+)
                     +empty-ommers-hash+)
      (block-validation-fail "Post-Merge header ommers hash must be empty"))
    (when (> (block-header-gas-limit header) +max-header-gas-limit+)
      (block-validation-fail "Post-Merge header gas limit exceeds maximum")))
  t)
