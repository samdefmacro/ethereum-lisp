(in-package #:ethereum-lisp.evm.internal)

(defun account-balance (state address)
  (let ((account (state-db-get-account state address)))
    (if account (state-account-balance account) 0)))

(defun empty-account-p (state address)
  (let ((account (state-db-get-account state address)))
    (or (null account)
        (and (zerop (state-account-nonce account))
             (zerop (state-account-balance account))
             (bytes= (hash32-bytes (state-account-code-hash account))
                     (hash32-bytes +empty-code-hash+))))))

(defun call-value-extra-gas
    (state callee value &key new-account-p stipend-discount-p)
  (let ((gas 0))
    (when (plusp value)
      (incf gas +call-value-transfer-gas+)
      (when (and new-account-p (empty-account-p state callee))
        (incf gas +call-new-account-gas+))
      (when stipend-discount-p
        (setf gas (max 0 (- gas +call-stipend+)))))
    gas))

(defun selfdestruct-extra-gas (state contract beneficiary)
  (if (and (plusp (account-balance state contract))
           (empty-account-p state beneficiary))
      +call-new-account-gas+
      0))

(defun contract-address-collision-p (state address)
  ;; EIP-7610 / EIP-684: a create target collides when it already has a
  ;; nonzero nonce, non-empty code, or non-empty storage. Balance is not a
  ;; collision (funding a counterfactual address before deployment is legal).
  (let ((account (state-db-get-account state address)))
    (and account
         (or (not (zerop (state-account-nonce account)))
             (not (bytes= (hash32-bytes (state-account-code-hash account))
                          (hash32-bytes +empty-code-hash+)))
             (not (bytes= (hash32-bytes (state-account-storage-root account))
                          (hash32-bytes +empty-trie-hash+)))))))

(defun account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun transfer-call-value (state sender recipient value rules)
  (let ((sender-account (account-or-empty state sender))
        (transfer-p
          (and (plusp value)
               (not (bytes= (address-bytes sender)
                            (address-bytes recipient))))))
    (when (< (state-account-balance sender-account) value)
      (fail "Insufficient balance for CALL value"))
    (when transfer-p
      (let ((recipient-account (account-or-empty state recipient)))
        (put-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (put-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))
    (when (and transfer-p
               rules
               (chain-rules-amsterdam-p rules))
      (make-eth-transfer-log-entry sender recipient value))))

(defun evm-resolved-code (state address rules)
  (let ((code (state-db-get-code state address)))
    (if (or (null rules) (chain-rules-prague-p rules))
        (let ((delegation-target (set-code-delegation-target code)))
          (if delegation-target
              (state-db-get-code state delegation-target)
              code))
        code)))

(defun selfdestruct-account
    (state address beneficiary rules &key clear-self-balance-p)
  (let* ((account (account-or-empty state address))
         (balance (state-account-balance account))
         (transfer-p
           (and (plusp balance)
                (not (bytes= (address-bytes address)
                             (address-bytes beneficiary))))))
    (when transfer-p
      (state-db-add-balance state beneficiary balance)
      (put-account-values
       state
       address
       (state-account-nonce account)
       0
       (state-account-code-hash account)))
    ;; EIP-6780 retains an old account on SELFDESTRUCT, but a contract created
    ;; in this transaction is still deleted.  Its self-beneficiary case must
    ;; therefore consume the balance now; retaining it changes observable
    ;; BALANCE results before the transaction's deferred account deletion.
    (when (and clear-self-balance-p (plusp balance) (not transfer-p))
      (put-account-values
       state
       address
       (state-account-nonce account)
       0
       (state-account-code-hash account)))
    (when (and transfer-p
               rules
               (chain-rules-amsterdam-p rules))
      (make-eth-transfer-log-entry address beneficiary balance))))
