(in-package #:ethereum-lisp.chain-store)

;;;; Public chain-store protocol with a memory-component fallback.

(defgeneric chain-store-put-block
    (store block &key state-available-p))

(defmethod chain-store-put-block
    ((store t) block &key (state-available-p nil))
  (memory-chain-store-put-block
   (chain-store-require-memory-store store)
   block
   :state-available-p state-available-p))

(defgeneric chain-store-known-block (store hash))

(defmethod chain-store-known-block ((store t) hash)
  (engine-payload-store-known-block
   (chain-store-require-memory-store store)
   hash))

(defgeneric chain-store-block-by-number (store number))

(defmethod chain-store-block-by-number ((store t) number)
  (engine-payload-store-block-by-number
   (chain-store-require-memory-store store)
   number))

(defgeneric chain-store-canonical-hash (store number))

(defmethod chain-store-canonical-hash ((store t) number)
  (engine-payload-store-canonical-hash
   (chain-store-require-memory-store store)
   number))

(defgeneric chain-store-canonical-block-p (store block))

(defmethod chain-store-canonical-block-p ((store t) block)
  (engine-payload-store-canonical-block-p
   (chain-store-require-memory-store store)
   block))

(defgeneric chain-store-head-number (store))

(defmethod chain-store-head-number ((store t))
  (engine-payload-store-head-number
   (chain-store-require-memory-store store)))

(defgeneric chain-store-block-tag-number (store tag))

(defmethod chain-store-block-tag-number ((store t) tag)
  (engine-payload-store-block-tag-number
   (chain-store-require-memory-store store)
   tag))

(defgeneric chain-store-latest-block (store))

(defmethod chain-store-latest-block ((store t))
  (chain-store-block-by-number
   store
   (chain-store-head-number store)))

(defgeneric chain-store-transaction-location (store hash))

(defmethod chain-store-transaction-location ((store t) hash)
  (engine-payload-store-transaction-location
   (chain-store-require-memory-store store)
   hash))

(defgeneric chain-store-block-receipts (store hash))

(defmethod chain-store-block-receipts ((store t) hash)
  (let ((block (chain-store-known-block store hash)))
    (when block
      (mapcar #'engine-payload-store-copy-receipt
              (block-receipts block)))))

(defgeneric chain-store-update-forkchoice-checkpoints (store state))

(defmethod chain-store-update-forkchoice-checkpoints ((store t) state)
  (engine-payload-store-update-forkchoice-checkpoints
   (chain-store-require-memory-store store)
   state)
  store)

(defgeneric chain-store-head-checkpoint (store))

(defmethod chain-store-head-checkpoint ((store t))
  (memory-chain-store-head-checkpoint
   (chain-store-require-memory-store store)))

(defgeneric chain-store-safe-checkpoint (store))

(defmethod chain-store-safe-checkpoint ((store t))
  (memory-chain-store-safe-checkpoint
   (chain-store-require-memory-store store)))

(defgeneric chain-store-finalized-checkpoint (store))

(defmethod chain-store-finalized-checkpoint ((store t))
  (memory-chain-store-finalized-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-checkpoint-block (store checkpoint)
  (let ((hash (and checkpoint
                   (chain-store-checkpoint-block-hash checkpoint))))
    (when hash
      (chain-store-known-block store hash))))

(defgeneric chain-store-head-block (store))

(defmethod chain-store-head-block ((store t))
  (chain-store-checkpoint-block
   store
   (chain-store-head-checkpoint store)))

(defgeneric chain-store-safe-block (store))

(defmethod chain-store-safe-block ((store t))
  (chain-store-checkpoint-block
   store
   (chain-store-safe-checkpoint store)))

(defgeneric chain-store-finalized-block (store))

(defmethod chain-store-finalized-block ((store t))
  (chain-store-checkpoint-block
   store
   (chain-store-finalized-checkpoint store)))
