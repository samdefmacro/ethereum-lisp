(in-package #:ethereum-lisp.execution)

(defun execution-account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun put-execution-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun transfer-value (state sender recipient value)
  (unless (bytes= (address-bytes sender) (address-bytes recipient))
    (when (plusp value)
      (let ((sender-account (execution-account-or-empty state sender))
            (recipient-account (execution-account-or-empty state recipient)))
        (put-execution-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (put-execution-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))))

(defun execution-resolved-code (state address)
  (let* ((code (state-db-get-code state address))
         (delegation-target (set-code-delegation-target code)))
    (if delegation-target
        (state-db-get-code state delegation-target)
        code)))

(defun execution-create-address (creator nonce)
  (let* ((hash (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes creator) nonce))))
         (out (make-byte-vector 20)))
    (replace out hash :start2 12)
    (make-address out)))

(defun execution-contract-address-collision-p (state address)
  ;; EIP-7610 / EIP-684: collision on nonzero nonce, non-empty code, or
  ;; non-empty storage. Balance is irrelevant, so a pre-funded but otherwise
  ;; empty address does not block the creating transaction.
  (let ((account (state-db-get-account state address)))
    (and account
         (not (and (zerop (state-account-nonce account))
                   (bytes= (hash32-bytes (state-account-storage-root account))
                           (hash32-bytes +empty-trie-hash+))
                   (bytes= (hash32-bytes (state-account-code-hash account))
                           (hash32-bytes +empty-code-hash+)))))))
