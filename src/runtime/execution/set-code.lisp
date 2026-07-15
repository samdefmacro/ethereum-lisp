(in-package #:ethereum-lisp.execution)

(defun valid-set-code-authorization-chain-p (authorization chain-id)
  (let ((authorization-chain-id
          (set-code-authorization-chain-id authorization)))
    (or (zerop authorization-chain-id)
        (= authorization-chain-id chain-id))))

(defun set-code-authorization-nonce-incrementable-p (authorization)
  (< (set-code-authorization-nonce authorization) +max-account-nonce+))

(defun set-code-authority-code-valid-p (state authority)
  (let ((code (state-db-get-code state authority)))
    (or (zerop (length code))
        (set-code-delegation-target code))))

(defun apply-set-code-authorization (state authorization chain-id)
  (when (and (valid-set-code-authorization-chain-p authorization chain-id)
             (set-code-authorization-nonce-incrementable-p authorization))
    (let ((authority (set-code-authorization-authority authorization)))
      (when (and authority
                 (set-code-authority-code-valid-p state authority))
        (let* ((existing-account-p (state-db-get-account state authority))
               (account (or existing-account-p (make-state-account)))
               (authorization-nonce
                 (set-code-authorization-nonce authorization)))
          (when (= authorization-nonce (state-account-nonce account))
            (put-execution-account-values
             state
             authority
             (1+ authorization-nonce)
             (state-account-balance account)
             (state-account-code-hash account))
            (state-db-set-code
             state
             authority
             (if (equalp (address-bytes
                          (set-code-authorization-address authorization))
                         (address-bytes (zero-address)))
                 (make-byte-vector 0)
                 (set-code-delegation-code
                  (set-code-authorization-address authorization))))
            (if existing-account-p +set-code-existing-account-refund+ 0)))))))

(defun apply-set-code-authorizations (state tx chain-id)
  (let ((refund-counter 0))
    (when (typep tx 'set-code-transaction)
      (dolist (authorization (transaction-authorization-list tx))
        (incf refund-counter
              (or (apply-set-code-authorization state authorization chain-id)
                  0))))
    refund-counter))
