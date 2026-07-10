(in-package #:ethereum-lisp.chain-store)

;;;; In-memory block storage and forkchoice checkpoint updates.

(defun memory-chain-store-put-block
    (store block &key (state-available-p nil))
  (setf store (chain-store-require-memory-store store))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Chain store block must be a block"))
  (let ((stored-block (engine-payload-store-copy-block block))
        (key (engine-payload-store-key (block-hash block)))
        (canonicalized-p nil)
        (notify-head-p nil))
    (remhash key (memory-chain-store-remote-blocks store))
    (setf (gethash key (memory-chain-store-blocks store)) stored-block)
    (engine-payload-store-prune-prepared-payloads-for-block store key)
    (let ((number (block-header-number (block-header stored-block))))
      (when (and (integerp number) (not (minusp number)))
        (setf (gethash number
                       (memory-chain-store-number-blocks store))
              stored-block)
        (when (and (not (gethash
                         number
                         (memory-chain-store-canonical-hashes store)))
                   (engine-payload-store-canonical-parent-p
                    store stored-block))
          (setf (gethash number
                         (memory-chain-store-canonical-hashes store))
                key
                canonicalized-p t))
        (when (and canonicalized-p
                   (> number (memory-chain-store-head-number store)))
          (setf notify-head-p t
                (memory-chain-store-head-number store) number))))
    (loop with receipts = (block-receipts stored-block)
          with log-index-start = 0
          for transaction in (block-transactions stored-block)
          for index from 0
          for receipt = (nth index receipts)
          do (engine-payload-store-put-transaction-location
              store stored-block index transaction receipt log-index-start)
             (when receipt
               (incf log-index-start (length (receipt-logs receipt)))))
    (if state-available-p
        (setf (gethash key (memory-chain-store-state-blocks store)) t)
        (remhash key (memory-chain-store-state-blocks store)))
    (when notify-head-p
      (engine-payload-store-notify-block-filters store stored-block))
    block))

(defun engine-payload-store-known-block
    (store hash)
  (setf store (chain-store-require-memory-store store))
  (gethash (engine-payload-store-key hash)
           (memory-chain-store-blocks store)))

(defun engine-payload-store-checkpoint-number
    (store checkpoint &key label fallback-to-head-p)
  (setf store (chain-store-require-memory-store store))
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (block (and hash (engine-payload-store-known-block store hash))))
    (cond
      (block
       (block-header-number (block-header block)))
      (fallback-to-head-p
       (memory-chain-store-head-number store))
      (t
       (block-validation-fail "~A block not found" label)))))

(defun engine-payload-store-head-number (store)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-checkpoint-number
   store
   (memory-chain-store-head-checkpoint store)
   :label "head"
   :fallback-to-head-p t))

(defun engine-payload-store-block-tag-number (store tag)
  (setf store (chain-store-require-memory-store store))
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (engine-payload-store-head-number store))
    ((string= tag "safe")
     (engine-payload-store-checkpoint-number
      store
      (memory-chain-store-safe-checkpoint store)
      :label "safe"))
    ((string= tag "finalized")
     (engine-payload-store-checkpoint-number
      store
      (memory-chain-store-finalized-checkpoint store)
      :label "finalized"))))

(defun engine-payload-store-forkchoice-checkpoint-hash (hash)
  (unless (hash32= hash (zero-hash32))
    hash))

(defun engine-payload-store-update-forkchoice-checkpoints (store state)
  (setf store (chain-store-require-memory-store store))
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
  (setf (memory-chain-store-head-checkpoint store)
        (make-chain-store-checkpoint
         :label :head
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-head-block-hash state)))
        (memory-chain-store-safe-checkpoint store)
        (make-chain-store-checkpoint
         :label :safe
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-safe-block-hash state)))
        (memory-chain-store-finalized-checkpoint store)
        (make-chain-store-checkpoint
         :label :finalized
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-finalized-block-hash state))))
  store)
