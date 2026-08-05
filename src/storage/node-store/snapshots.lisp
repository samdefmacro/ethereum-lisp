(in-package #:ethereum-lisp.node-store)

(defun node-store-require-memory-state (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Node store must be an engine payload memory store"))
  store)

(defun engine-payload-store-snapshot (store)
  (setf store (node-store-require-memory-state store))
  (make-engine-payload-memory-store
   :chain-store (copy-memory-chain-store store)
   :txpool
   (engine-pending-txpool-copy
    (engine-payload-memory-store-txpool store))))

(defun engine-payload-store-restore (store snapshot)
  (setf store (node-store-require-memory-state store)
        snapshot (node-store-require-memory-state snapshot))
  (setf (engine-payload-memory-store-chain-store store)
        (engine-payload-memory-store-chain-store snapshot)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool snapshot))
  store)

(defun chain-store-atomic-commit (store thunk)
  "Run THUNK, publishing its chain-store mutations only if it returns normally.

Rather than deep-copying the whole store up front, the growing tables record a
changed-key undo journal while the transaction is active, so a failed commit
rolls back in time proportional to the keys it touched. The small side slots
whose values are mutated in place (or that a journal cannot cheaply protect)
are captured as a bounded wholesale copy, and the txpool keeps its cheap copy."
  (let* ((store (node-store-require-memory-state store))
         (chain-store (chain-store-require-memory-store store))
         (txpool-snapshot
           (engine-pending-txpool-copy
            (engine-payload-memory-store-txpool store)))
         (volatile-snapshot
           (chain-store-capture-volatile-slots chain-store)))
    (call-with-chain-store-transaction
     (lambda (journal)
       (handler-case
           (funcall thunk)
         (error (condition)
           (chain-store-journal-rollback journal)
           (chain-store-restore-volatile-slots chain-store volatile-snapshot)
           (setf (engine-payload-memory-store-txpool store) txpool-snapshot)
           (error condition)))))))
