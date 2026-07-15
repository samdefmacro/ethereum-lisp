(in-package #:ethereum-lisp.execution)

(defun transaction-declared-chain-id (tx)
  (typecase tx
    (legacy-transaction
     (legacy-transaction-chain-id tx))
    (access-list-transaction
     (access-list-transaction-chain-id tx))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-chain-id tx))
    (blob-transaction
     (blob-transaction-chain-id tx))
    (set-code-transaction
     (set-code-transaction-chain-id tx))
    (t 0)))

(defun transaction-context-chain-id (tx expected-chain-id)
  (or expected-chain-id
      (transaction-declared-chain-id tx)
      0))

(defun signed-transaction-sender-or-error (tx expected-chain-id)
  (or (transaction-sender tx :expected-chain-id expected-chain-id)
      (error 'transaction-validation-error
             :message "Invalid transaction signature")))

(defun signed-transaction-senders-or-error (transactions expected-chain-id)
  (mapcar (lambda (tx)
            (signed-transaction-sender-or-error tx expected-chain-id))
          transactions))
