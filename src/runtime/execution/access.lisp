(in-package #:ethereum-lisp.execution)

(defun execution-storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun execution-account-access-key (address)
  (address-bytes address))

(defun prewarm-execution-address (accessed-addresses address)
  (when address
    (setf (gethash (execution-account-access-key address)
                   accessed-addresses)
          t)))

(defun transaction-accessed-addresses-table
    (tx &key sender destination coinbase chain-rules)
  (let ((accessed-addresses (make-hash-table :test 'equalp)))
    (prewarm-precompile-addresses accessed-addresses chain-rules)
    (prewarm-execution-address accessed-addresses sender)
    (prewarm-execution-address accessed-addresses destination)
    (when (or (null chain-rules)
              (chain-rules-shanghai-p chain-rules))
      (prewarm-execution-address accessed-addresses coinbase))
    (dolist (entry (transaction-access-list tx))
      (prewarm-execution-address accessed-addresses
                                 (access-list-entry-address entry)))
    ;; EIP-7702: each recoverable authorization authority is warmed, even when
    ;; the tuple is later found invalid.
    (when (typep tx 'set-code-transaction)
      (dolist (authorization (transaction-authorization-list tx))
        (prewarm-execution-address
         accessed-addresses
         (set-code-authorization-authority authorization))))
    accessed-addresses))

(defun transaction-accessed-storage-table (tx)
  (let ((accessed-storage (make-hash-table :test 'equalp)))
    (dolist (entry (transaction-access-list tx))
      (dolist (slot (access-list-entry-storage-keys entry))
        (setf (gethash (execution-storage-access-key
                        (access-list-entry-address entry)
                        slot)
                       accessed-storage)
              t)))
    accessed-storage))
