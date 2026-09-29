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

(defun signed-transaction-sender-or-error
    (tx expected-chain-id &optional chain-rules)
  "TX's sender under the signer CHAIN-RULES select (TRANSACTION-SENDER-FOR-RULES;
NIL is the latest fork), or a TRANSACTION-VALIDATION-ERROR."
  (let ((declared-chain-id (transaction-declared-chain-id tx)))
    ;; Preserve a chain-domain mismatch separately from malformed V/R/S.  Both
    ;; make sender recovery return NIL, but callers need the distinction for
    ;; stable transaction-admission diagnostics and canonical fixture results.
    ;; A legacy transaction without EIP-155 protection reports chain ID zero.
    ;; Zero is not a declared EIP-155 domain and remains valid on a chain whose
    ;; execution context has a positive ID.  Before EIP-155 a protected V
    ;; names no chain domain at all: it is an invalid signature.
    (when (and expected-chain-id declared-chain-id (plusp declared-chain-id)
               (/= expected-chain-id declared-chain-id)
               (chain-rules-eip155-active-p chain-rules))
      (error 'transaction-validation-error
             :message "Transaction chain ID does not match expected chain ID"))
    (or (transaction-sender-for-rules tx chain-rules
                                      :expected-chain-id expected-chain-id)
        (error 'transaction-validation-error
               :message "Invalid transaction signature"))))

(defun signed-transaction-senders-or-error
    (transactions expected-chain-id &optional chain-rules)
  (mapcar (lambda (tx)
            (signed-transaction-sender-or-error tx expected-chain-id
                                                chain-rules))
          transactions))
