(in-package #:ethereum-lisp.chain-store)

;;;; In-memory block storage and forkchoice checkpoint updates.

(defun engine-payload-store-put-block
    (store block &key (state-available-p nil))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine payload store block must be a block"))
  (let ((txpool (engine-payload-memory-store-txpool store)))
    (unless (engine-pending-txpool-empty-p txpool)
      (dolist (transaction (block-transactions block))
        (engine-pending-txpool-sender transaction))))
  (let ((stored-block (engine-payload-store-copy-block block))
        (key (engine-payload-store-key (block-hash block)))
        (canonicalized-p nil)
        (notify-head-p nil))
    (remhash key (engine-payload-memory-store-remote-blocks store))
    (setf (gethash key (engine-payload-memory-store-blocks store))
          stored-block)
    (engine-payload-store-prune-prepared-payloads-for-block store key)
    (let ((number (block-header-number (block-header stored-block))))
      (when (and (integerp number) (not (minusp number)))
        (setf (gethash number
                       (engine-payload-memory-store-number-blocks store))
              stored-block)
        (when (and (not (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store)))
                   (engine-payload-store-canonical-parent-p store stored-block))
          (setf (gethash number
                         (engine-payload-memory-store-canonical-hashes store))
                key
                canonicalized-p t))
        (when (and canonicalized-p
                   (> number (engine-payload-memory-store-head-number store)))
          (setf notify-head-p t)
          (setf (engine-payload-memory-store-head-number store) number))))
    (loop with receipts = (block-receipts stored-block)
          with log-index-start = 0
          for transaction in (block-transactions stored-block)
          for index from 0
          for receipt = (nth index receipts)
          do (progn
               (engine-payload-store-put-transaction-location
                store
                stored-block
                index
                transaction
                receipt
                log-index-start)
               (when receipt
                 (incf log-index-start
                       (length (receipt-logs receipt))))))
    (when (engine-payload-store-canonical-block-p store stored-block)
      (engine-payload-store-remove-included-block-transactions store stored-block))
    (if state-available-p
        (setf (gethash key
                       (engine-payload-memory-store-state-blocks store))
              t)
        (remhash key (engine-payload-memory-store-state-blocks store)))
    (when notify-head-p
      (engine-payload-store-notify-block-filters store stored-block))
    block))

(defun engine-payload-store-known-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-blocks store)))

(defun engine-payload-store-checkpoint-number
    (store checkpoint &key label fallback-to-head-p)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (block (and hash (engine-payload-store-known-block store hash))))
    (cond
      (block
       (block-header-number (block-header block)))
      (fallback-to-head-p
       (engine-payload-memory-store-head-number store))
      (t
       (block-validation-fail "~A block not found" label)))))

(defun engine-payload-store-head-number (store)
  (engine-payload-store-checkpoint-number
   store
   (engine-payload-memory-store-head-checkpoint store)
   :label "head"
   :fallback-to-head-p t))

(defun engine-payload-store-block-tag-number (store tag)
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (engine-payload-store-head-number store))
    ((string= tag "safe")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-safe-checkpoint store)
      :label "safe"))
    ((string= tag "finalized")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-finalized-checkpoint store)
      :label "finalized"))))

(defun engine-payload-store-forkchoice-checkpoint-hash (hash)
  (unless (hash32= hash (zero-hash32))
    hash))

(defun engine-payload-store-update-forkchoice-checkpoints (store state)
  (let* ((head-hash (forkchoice-state-head-block-hash state))
         (head-block (engine-payload-store-known-block store head-hash))
         (safe-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-safe-block-hash state)))
         (finalized-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-finalized-block-hash state))))
    (unless head-block
      (block-validation-fail "forkchoice head block is not available"))
    (unless (engine-payload-store-state-available-p store head-hash)
      (block-validation-fail "forkchoice head block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-known-block store safe-hash)))
      (block-validation-fail "forkchoice safe block is not available"))
    (when (and safe-hash
               (not (engine-payload-store-state-available-p
                     store safe-hash)))
      (block-validation-fail "forkchoice safe block state is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-known-block store finalized-hash)))
      (block-validation-fail "forkchoice finalized block is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-state-available-p
                     store finalized-hash)))
      (block-validation-fail
       "forkchoice finalized block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "forkchoice safe block is not an ancestor of head"))
    (when (and finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "forkchoice finalized block is not an ancestor of head"))
    (let ((safe-block
            (and safe-hash
                 (engine-payload-store-known-block store safe-hash)))
          (finalized-block
            (and finalized-hash
                 (engine-payload-store-known-block store finalized-hash))))
      (when (and safe-block finalized-block
                 (< (block-header-number (block-header safe-block))
                    (block-header-number (block-header finalized-block))))
        (block-validation-fail
         "forkchoice safe block is older than finalized block"))))
  (setf (engine-payload-memory-store-head-checkpoint store)
        (make-chain-store-checkpoint
         :label :head
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-head-block-hash state)))
        (engine-payload-memory-store-safe-checkpoint store)
        (make-chain-store-checkpoint
         :label :safe
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-safe-block-hash state)))
        (engine-payload-memory-store-finalized-checkpoint store)
        (make-chain-store-checkpoint
         :label :finalized
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-finalized-block-hash state))))
  store)
