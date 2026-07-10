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
  (let* ((store (node-store-require-memory-state store))
         (snapshot (engine-payload-store-snapshot store)))
    (handler-case
        (funcall thunk)
      (error (condition)
        (engine-payload-store-restore store snapshot)
        (error condition)))))
