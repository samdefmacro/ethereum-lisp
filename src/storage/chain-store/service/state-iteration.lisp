(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-account-storage-entries
    (memory-store block-hash address)
  (setf memory-store (chain-store-require-memory-store memory-store))
  (multiple-value-bind (balances nonces codes storage)
      (engine-payload-store-collect-state-view
       memory-store (engine-payload-store-key block-hash))
    (declare (ignore nonces codes))
    (if balances
        (engine-payload-store-state-view-storage-entries
         storage (address-to-hex address))
        '())))

(defun chain-store-for-each-account (store block-hash function)
  "Call FUNCTION with (ADDRESS BALANCE NONCE CODE STORAGE-ENTRIES) for every
account of BLOCK-HASH's state, addresses sorted by hex. The state is
resolved through the diff chain to its baseline; an unresolvable chain
behaves like unavailable state."
  (let ((memory-store (chain-store-require-memory-store store)))
    (when (chain-store-state-available-p store block-hash)
      (multiple-value-bind (balances nonces codes storage)
          (engine-payload-store-collect-state-view
           memory-store (engine-payload-store-key block-hash))
        (when balances
          (dolist (address-hex (engine-payload-store-state-view-addresses
                                balances nonces codes storage))
            (let ((address (address-from-hex address-hex))
                  (code (gethash address-hex codes)))
              (funcall
               function
               address
               (gethash address-hex balances 0)
               (gethash address-hex nonces 0)
               (if code
                   (copy-seq code)
                   (make-byte-vector 0))
               (engine-payload-store-state-view-storage-entries
                storage address-hex))))
          store)))))
