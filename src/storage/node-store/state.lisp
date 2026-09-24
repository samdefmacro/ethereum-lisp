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

(defmethod chain-store-blob-sidecar-pinned-p
    ((state engine-payload-memory-store) blob-key)
  ;; The txpool and the chain store are sibling domains; the node store that
  ;; composes them is where "a pooled transaction still needs this blob" can be
  ;; asked of the bounded blob cache.
  (engine-pending-txpool-blob-hash-owned-p
   (engine-payload-memory-store-txpool state) blob-key))
