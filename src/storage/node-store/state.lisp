(in-package #:ethereum-lisp.node-state)

(defstruct (engine-payload-memory-store
            (:constructor make-engine-payload-memory-store
                (&key (chain-store (make-memory-chain-store))
                      (txpool (make-engine-pending-txpool)))))
  (chain-store (make-memory-chain-store) :type memory-chain-store)
  (txpool (make-engine-pending-txpool) :type engine-pending-txpool))

(defmethod chain-store-component ((state engine-payload-memory-store))
  (engine-payload-memory-store-chain-store state))

(defmethod txpool-component ((state engine-payload-memory-store))
  (engine-payload-memory-store-txpool state))
