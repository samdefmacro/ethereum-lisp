(in-package #:ethereum-lisp.node-state)

(defstruct (engine-payload-memory-store
            (:constructor make-engine-payload-memory-store
                (&key (chain-store (make-memory-chain-store))
                      (txpool (make-engine-pending-txpool)))))
  (chain-store (make-memory-chain-store) :type memory-chain-store)
  (txpool (make-engine-pending-txpool) :type engine-pending-txpool))

(defmacro define-node-chain-store-accessor (node-accessor chain-accessor)
  `(progn
     (defun ,node-accessor (state)
       (,chain-accessor (engine-payload-memory-store-chain-store state)))
     (defun (setf ,node-accessor) (value state)
       (setf (,chain-accessor
              (engine-payload-memory-store-chain-store state))
             value))))

(define-node-chain-store-accessor
  engine-payload-memory-store-blocks memory-chain-store-blocks)
(define-node-chain-store-accessor
  engine-payload-memory-store-number-blocks memory-chain-store-number-blocks)
(define-node-chain-store-accessor
  engine-payload-memory-store-canonical-hashes
  memory-chain-store-canonical-hashes)
(define-node-chain-store-accessor
  engine-payload-memory-store-transaction-locations
  memory-chain-store-transaction-locations)
(define-node-chain-store-accessor
  engine-payload-memory-store-account-balances
  memory-chain-store-account-balances)
(define-node-chain-store-accessor
  engine-payload-memory-store-account-nonces memory-chain-store-account-nonces)
(define-node-chain-store-accessor
  engine-payload-memory-store-account-codes memory-chain-store-account-codes)
(define-node-chain-store-accessor
  engine-payload-memory-store-account-storage
  memory-chain-store-account-storage)
(define-node-chain-store-accessor
  engine-payload-memory-store-head-number memory-chain-store-head-number)
(define-node-chain-store-accessor
  engine-payload-memory-store-state-blocks memory-chain-store-state-blocks)
(define-node-chain-store-accessor
  engine-payload-memory-store-remote-blocks memory-chain-store-remote-blocks)
(define-node-chain-store-accessor
  engine-payload-memory-store-invalid-tipsets memory-chain-store-invalid-tipsets)
(define-node-chain-store-accessor
  engine-payload-memory-store-prepared-payloads
  memory-chain-store-prepared-payloads)
(define-node-chain-store-accessor
  engine-payload-memory-store-blob-sidecars memory-chain-store-blob-sidecars)
(define-node-chain-store-accessor
  engine-payload-memory-store-log-filters memory-chain-store-log-filters)
(define-node-chain-store-accessor
  engine-payload-memory-store-next-log-filter-id
  memory-chain-store-next-log-filter-id)
(define-node-chain-store-accessor
  engine-payload-memory-store-head-checkpoint
  memory-chain-store-head-checkpoint)
(define-node-chain-store-accessor
  engine-payload-memory-store-safe-checkpoint
  memory-chain-store-safe-checkpoint)
(define-node-chain-store-accessor
  engine-payload-memory-store-finalized-checkpoint
  memory-chain-store-finalized-checkpoint)
