(in-package #:ethereum-lisp.evm)

(defun increment-account-nonce (state address)
  (let ((account (account-or-empty state address)))
    (when (= (state-account-nonce account) +max-account-nonce+)
      (fail "EVM account nonce overflow"))
    (put-account-values
     state
     address
     (1+ (state-account-nonce account))
     (state-account-balance account)
     (state-account-code-hash account))))

(defun account-code-hash-word (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (hash32-to-word (state-account-code-hash account))
        0)))

(defun blockhash-word (context number)
  (let* ((current (evm-context-block-number context))
         (lower (if (< current 257) 0 (- current 256))))
    (if (and (>= number lower) (< number current))
        (let ((hash (gethash number (evm-context-block-hashes context))))
          (if hash (hash32-to-word hash) 0))
        0)))

(defun blobhash-word (context index)
  (let ((hashes (evm-context-blob-hashes context)))
    (if (< index (length hashes))
        (hash32-to-word (elt hashes index))
        0)))
