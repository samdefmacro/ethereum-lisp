(in-package #:ethereum-lisp.evm)

(defstruct (evm-execution-snapshot
            (:constructor make-evm-execution-snapshot
                (&key state transient-storage storage-clears accessed-storage
                      accessed-addresses selfdestructed-addresses)))
  state
  transient-storage
  storage-clears
  accessed-storage
  accessed-addresses
  selfdestructed-addresses)

(defun capture-execution-snapshot (state context)
  (make-evm-execution-snapshot
   :state (state-db-copy state)
   :transient-storage (copy-transient-storage context)
   :storage-clears (copy-storage-clears context)
   :accessed-storage (copy-accessed-storage context)
   :accessed-addresses (copy-accessed-addresses context)
   :selfdestructed-addresses (copy-selfdestructed-addresses context)))

(defun refresh-execution-snapshot-accessed-addresses (snapshot context)
  (setf (evm-execution-snapshot-accessed-addresses snapshot)
        (copy-accessed-addresses context))
  snapshot)

(defun restore-execution-snapshot (state context snapshot)
  (state-db-restore state (evm-execution-snapshot-state snapshot))
  (restore-transient-storage
   context
   (evm-execution-snapshot-transient-storage snapshot))
  (restore-storage-clears
   context
   (evm-execution-snapshot-storage-clears snapshot))
  (restore-accessed-storage
   context
   (evm-execution-snapshot-accessed-storage snapshot))
  (restore-accessed-addresses
   context
   (evm-execution-snapshot-accessed-addresses snapshot))
  (restore-selfdestructed-addresses
   context
   (evm-execution-snapshot-selfdestructed-addresses snapshot)))

(defun account-balance (state address)
  (let ((account (state-db-get-account state address)))
    (if account (state-account-balance account) 0)))

(defun empty-account-p (state address)
  (let ((account (state-db-get-account state address)))
    (or (null account)
        (and (zerop (state-account-nonce account))
             (zerop (state-account-balance account))
             (bytes= (hash32-bytes (state-account-storage-root account))
                     (hash32-bytes +empty-trie-hash+))
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
  (not (empty-account-p state address)))

(defun account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun transfer-call-value (state sender recipient value)
  (let ((sender-account (account-or-empty state sender)))
    (when (< (state-account-balance sender-account) value)
      (fail "Insufficient balance for CALL value"))
    (unless (or (zerop value)
                (bytes= (address-bytes sender) (address-bytes recipient)))
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
         (state-account-code-hash recipient-account))))))

(defun evm-resolved-code (state address)
  (let* ((code (state-db-get-code state address))
         (delegation-target (set-code-delegation-target code)))
    (if delegation-target
        (state-db-get-code state delegation-target)
        code)))

(defun selfdestruct-account (state address beneficiary)
  (let* ((account (account-or-empty state address))
         (balance (state-account-balance account)))
    (unless (bytes= (address-bytes address) (address-bytes beneficiary))
      (state-db-add-balance state beneficiary balance)
      (put-account-values
       state
       address
       (state-account-nonce account)
       0
       (state-account-code-hash account)))))
