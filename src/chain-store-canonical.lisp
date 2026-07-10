(in-package #:ethereum-lisp.core)

(defun chain-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (engine-payload-store-set-canonical-head
   (chain-store-require-memory-store store)
   hash
   :expected-chain-id expected-chain-id
   :chain-config chain-config))
