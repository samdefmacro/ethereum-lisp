(in-package #:ethereum-lisp.node-store)

(defun node-store-validate-included-transaction-senders (txpool block)
  (unless (engine-pending-txpool-empty-p txpool)
    (dolist (transaction (block-transactions block))
      (engine-pending-txpool-sender transaction))))

(defun engine-payload-store-put-block
    (store block &key (state-available-p nil))
  (setf store (node-store-require-memory-state store))
  (let ((chain-store (chain-store-require-memory-store store))
        (txpool (txpool-component store)))
    (node-store-validate-included-transaction-senders txpool block)
    (memory-chain-store-put-block
     chain-store block :state-available-p state-available-p)
    (when (engine-payload-store-canonical-block-p chain-store block)
      (engine-payload-store-remove-included-block-transactions txpool block))
    block))
