(in-package #:ethereum-lisp.transactions)

;;;; Cross-type transaction accessors.

(defmacro define-transaction-reader (name &body methods)
  `(progn
     (defgeneric ,name (transaction))
     ,@(loop for (type form) in methods
             collect `(defmethod ,name ((transaction ,type)) ,form))))

(define-transaction-reader transaction-nonce
  (legacy-transaction (legacy-transaction-nonce transaction))
  (access-list-transaction (access-list-transaction-nonce transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-nonce transaction))
  (blob-transaction (blob-transaction-nonce transaction))
  (set-code-transaction (set-code-transaction-nonce transaction)))

(define-transaction-reader transaction-gas-limit
  (legacy-transaction (legacy-transaction-gas-limit transaction))
  (access-list-transaction (access-list-transaction-gas-limit transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-gas-limit transaction))
  (blob-transaction (blob-transaction-gas-limit transaction))
  (set-code-transaction (set-code-transaction-gas-limit transaction)))

(define-transaction-reader transaction-to
  (legacy-transaction (legacy-transaction-to transaction))
  (access-list-transaction (access-list-transaction-to transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-to transaction))
  (blob-transaction (blob-transaction-to transaction))
  (set-code-transaction (set-code-transaction-to transaction)))

(define-transaction-reader transaction-value
  (legacy-transaction (legacy-transaction-value transaction))
  (access-list-transaction (access-list-transaction-value transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-value transaction))
  (blob-transaction (blob-transaction-value transaction))
  (set-code-transaction (set-code-transaction-value transaction)))

(define-transaction-reader transaction-data
  (legacy-transaction (legacy-transaction-data transaction))
  (access-list-transaction (access-list-transaction-data transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-data transaction))
  (blob-transaction (blob-transaction-data transaction))
  (set-code-transaction (set-code-transaction-data transaction)))

(define-transaction-reader transaction-access-list
  (legacy-transaction '())
  (access-list-transaction (access-list-transaction-access-list transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-access-list transaction))
  (blob-transaction (blob-transaction-access-list transaction))
  (set-code-transaction (set-code-transaction-access-list transaction)))

(define-transaction-reader transaction-authorization-list
  (legacy-transaction '())
  (access-list-transaction '())
  (dynamic-fee-transaction '())
  (blob-transaction '())
  (set-code-transaction
   (set-code-transaction-authorization-list transaction)))

(define-transaction-reader transaction-type
  (legacy-transaction 0)
  (access-list-transaction 1)
  (dynamic-fee-transaction 2)
  (blob-transaction 3)
  (set-code-transaction 4))

(define-transaction-reader transaction-blob-versioned-hashes
  (legacy-transaction #())
  (access-list-transaction #())
  (dynamic-fee-transaction #())
  (set-code-transaction #())
  (blob-transaction
   (coerce (blob-transaction-blob-versioned-hashes transaction) 'vector)))

(defun transaction-blob-gas-used (transaction)
  (* (length (transaction-blob-versioned-hashes transaction))
     +blob-gas-per-blob+))

(defun access-list-storage-key-count (access-list)
  (loop for entry in access-list
        sum (length (access-list-entry-storage-keys entry))))
