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

;;;; Amsterdam authorizations (geth v1.17.6 core/state_transition.go
;;;; applyAuthorization under IsAmsterdam). The authority's cold access is in
;;;; the intrinsic 7816; what is charged here depends on state, from the
;;;; transaction's running budget, before the authorization takes effect:
;;;;
;;;; - ACCOUNT_WRITE (8000) regular gas the first time the transaction writes
;;;;   an authority, unless the sender's base cost or tx.to's value cost has
;;;;   already paid for that write;
;;;; - the new account (120 bytes) as state gas when the authority is empty;
;;;; - the delegation indicator (23 bytes) as state gas at most once per
;;;;   authority, and not when the authority was already delegated.
;;;;
;;;; There is no refund for an existing authority.

(defun apply-set-code-authorization-amsterdam
    (state authorization chain-id sender tx tracking budget)
  "Apply one Amsterdam AUTHORIZATION, charging BUDGET first.

TRACKING maps an authority key to (WRITTEN-P . INDICATOR-PAID-P). Returns
:OUT-OF-GAS when BUDGET cannot cover the charges, otherwise NIL."
  (unless (and (valid-set-code-authorization-chain-p authorization chain-id)
               (set-code-authorization-nonce-incrementable-p authorization))
    (return-from apply-set-code-authorization-amsterdam nil))
  (let ((authority (set-code-authorization-authority authorization)))
    (unless (and authority (set-code-authority-code-valid-p state authority))
      (return-from apply-set-code-authorization-amsterdam nil))
    (let ((account (execution-account-or-empty state authority))
          (nonce (set-code-authorization-nonce authorization)))
      (unless (= nonce (state-account-nonce account))
        (return-from apply-set-code-authorization-amsterdam nil))
      (let* ((old-target (set-code-delegation-target
                          (state-db-get-code state authority)))
             (target (set-code-authorization-address authorization))
             (clear-p (bytes= (address-bytes target)
                              (address-bytes (zero-address))))
             (key (address-bytes authority))
             (track (or (gethash key tracking)
                        (setf (gethash key tracking)
                              (cons nil (and old-target t)))))
             (regular 0)
             (state-gas 0))
        (when (and (not (car track))
                   (not (bytes= key (address-bytes sender)))
                   (not (and (transaction-to tx)
                             (bytes= key (address-bytes (transaction-to tx)))
                             (plusp (transaction-value tx)))))
          (incf regular +account-write-amsterdam+)
          (setf (car track) t))
        (when (execution-empty-account-p state authority)
          (incf state-gas +new-account-state-gas+))
        (when (and (not clear-p) (not (cdr track)))
          (incf state-gas +authorization-creation-state-gas+)
          (setf (cdr track) t))
        (unless (evm-gas-budget-charge
                 budget (make-evm-gas-costs :regular regular :state state-gas))
          (return-from apply-set-code-authorization-amsterdam :out-of-gas))
        (put-execution-account-values
         state authority (1+ nonce)
         (state-account-balance account)
         (state-account-code-hash account))
        (cond (clear-p
               (when old-target
                 (state-db-set-code state authority (make-byte-vector 0))))
              ((not (and old-target
                         (bytes= (address-bytes old-target)
                                 (address-bytes target))))
               (state-db-set-code state authority
                                  (set-code-delegation-code target))))
        nil))))

(defun apply-set-code-authorizations-amsterdam
    (state tx chain-id sender budget)
  "Apply TX's authorizations under Amsterdam; NIL when BUDGET ran out."
  (let ((tracking (make-hash-table :test 'equalp)))
    (dolist (authorization (transaction-authorization-list tx) t)
      (when (eq :out-of-gas
                (apply-set-code-authorization-amsterdam
                 state authorization chain-id sender tx tracking budget))
        (return nil)))))

(defun apply-set-code-authorizations (state tx chain-id)
  (let ((refund-counter 0))
    (when (typep tx 'set-code-transaction)
      (dolist (authorization (transaction-authorization-list tx))
        (incf refund-counter
              (or (apply-set-code-authorization state authorization chain-id)
                  0))))
    refund-counter))
