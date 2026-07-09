(in-package #:ethereum-lisp.core)

;;;; Executable-data block field decoding and validation helpers.

(defun executable-data-decoded-transactions (payload)
  (unless (typep payload 'executable-data)
    (block-validation-fail "Executable data payload must be executable-data"))
  (let ((transactions (executable-data-transactions payload)))
    (unless (listp transactions)
      (block-validation-fail "Executable data transactions must be a list"))
    (loop for encoded in transactions
          for index from 0
          collect
          (handler-case
              (transaction-from-encoding
               (validate-byte-sequence-field
                encoded
                (format nil "Executable data transaction ~D" index)))
            (block-validation-error (condition)
              (block-validation-fail
               "Invalid executable data transaction ~D: ~A"
               index condition))))))

(defun executable-data-blob-versioned-hashes (transactions)
  (loop for transaction in transactions
        append (coerce (transaction-blob-versioned-hashes transaction)
                       'list)))

(defun engine-new-payload-require-transaction-senders (block config)
  (let ((chain-id (chain-config-chain-id config)))
    (loop for transaction in (block-transactions block)
          for index from 0
          unless (transaction-sender transaction
                                     :expected-chain-id chain-id)
            do (block-validation-fail
                "Invalid executable data transaction ~D sender"
                index)))
  t)

(defun validate-executable-data-versioned-hashes
    (transactions versioned-hashes)
  (unless (listp versioned-hashes)
    (block-validation-fail "Executable data versioned hashes must be a list"))
  (let ((blob-hashes (executable-data-blob-versioned-hashes transactions)))
    (unless (= (length blob-hashes) (length versioned-hashes))
      (block-validation-fail
       "Executable data versioned hash count mismatch"))
    (loop for blob-hash in blob-hashes
          for versioned-hash in versioned-hashes
          for index from 0
          do (unless (hash32-p versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D must be a hash32"
                index))
             (unless (hash32= blob-hash versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D mismatch"
                index))))
  t)

(defun executable-data-required-hash32 (value label)
  (unless (hash32-p value)
    (block-validation-fail "~A must be a hash32" label))
  value)

(defun executable-data-required-address (value label)
  (unless (address-p value)
    (block-validation-fail "~A must be an address" label))
  value)

(defun executable-data-required-uint256 (value label)
  (unless (uint256-p value)
    (block-validation-fail "~A must be uint256" label))
  value)
