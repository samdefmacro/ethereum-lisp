(in-package #:ethereum-lisp.chain-store)

;; Defined later in the serial storage-core module.  This provider hook is
;; compiled first, so state the runtime call contract explicitly.
(declaim (ftype (function (t t) t) chain-store-journal-remhash))

;;;; Public chain-store protocol with a memory-component fallback.

;;;; A production adapter may retain only the records touched by the current
;;;; request in its inherited MEMORY-CHAIN-STORE tables.  These read-through
;;;; hooks keep the storage-core package independent of any database or record
;;;; codec; the persistence adapter supplies the typed point reads.  Memory and
;;;; file-oracle stores use the default absent methods and therefore keep their
;;;; existing behaviour.

(defgeneric chain-store-backing-block (store hash)
  (:documentation
   "Return (VALUES BLOCK PRESENT-P) for HASH from STORE's durable backing."))

(defmethod chain-store-backing-block ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-backing-canonical-hash (store number)
  (:documentation
   "Return (VALUES HASH PRESENT-P) for canonical NUMBER from durable backing."))

(defmethod chain-store-backing-canonical-hash ((store t) number)
  (declare (ignore store number))
  (values nil nil))

(defgeneric chain-store-backing-transaction-location (store hash)
  (:documentation
   "Return (VALUES LOCATION PRESENT-P) for HASH from durable backing."))

(defmethod chain-store-backing-transaction-location ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-backing-state-root (store hash)
  (:documentation
   "Return (VALUES ROOT PRESENT-P) for HASH's durable account state trie."))

(defmethod chain-store-backing-state-root ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-backing-account-state (store block-hash address)
  (:documentation
   "Return an account from STORE's trie-backed state without materializing it.

The values are BALANCE, NONCE, CODE-HASH, STORAGE-ROOT, ACCOUNT-PRESENT-P, and
STATE-PRESENT-P.  The distinct state presence value lets a provider report an
absent account in an existing trie without falling back to an oracle's legacy
flat tables."))

(defmethod chain-store-backing-account-state ((store t) block-hash address)
  (declare (ignore store block-hash address))
  (values 0 0 nil nil nil nil))

(defgeneric chain-store-backing-account-storage
    (store block-hash address slot)
  (:documentation
   "Return (VALUES VALUE PRESENT-P STATE-PRESENT-P) for one storage slot.

STATE-PRESENT-P distinguishes an absent slot in a trie-backed state from a
provider that has no trie state for the requested block."))

(defmethod chain-store-backing-account-storage
    ((store t) block-hash address slot)
  (declare (ignore store block-hash address slot))
  (values 0 nil nil))

(defgeneric chain-store-backing-trie-node (store hash)
  (:documentation
   "Return (VALUES ENCODED PRESENT-P) for a content-addressed trie node."))

(defmethod chain-store-backing-trie-node ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-backing-code (store hash)
  (:documentation
   "Return (VALUES CODE PRESENT-P) for a content-addressed bytecode hash."))

(defmethod chain-store-backing-code ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-backing-blob-sidecar (store hash)
  (:documentation
   "Return (VALUES BLOB-AND-PROOFS PRESENT-P) for a versioned HASH."))

(defmethod chain-store-backing-blob-sidecar ((store t) hash)
  (declare (ignore store hash))
  (values nil nil))

(defgeneric chain-store-durable-state-provider-p (store)
  (:documentation
   "True when STORE can resolve account/storage tries and code durably."))

(defmethod chain-store-durable-state-provider-p ((store t))
  (declare (ignore store))
  nil)

(defgeneric chain-store-cache-backing-read-p (store)
  (:documentation
   "True when immutable records point-read from STORE should remain cached."))

(defmethod chain-store-cache-backing-read-p ((store t))
  (declare (ignore store))
  t)

(defun chain-store-release-durable-block-overlay (store block)
  "Drop BLOCK's immutable cache entries once the durable batch owns them."
  (setf store (chain-store-require-memory-store store))
  (when (and (chain-store-durable-state-provider-p store)
             (typep block 'ethereum-block))
    (let* ((hash (block-hash block))
           (key (engine-payload-store-key hash))
           (number (block-header-number (block-header block)))
           (number-block
             (gethash number (memory-chain-store-number-blocks store)))
           (canonical-key
             (gethash number (memory-chain-store-canonical-hashes store))))
      (chain-store-journal-remhash (memory-chain-store-blocks store) key)
      (when (and number-block (hash32= hash (block-hash number-block)))
        (chain-store-journal-remhash
         (memory-chain-store-number-blocks store) number))
      (when (and canonical-key (string= canonical-key key))
        (chain-store-journal-remhash
         (memory-chain-store-canonical-hashes store) number))
      (dolist (transaction (block-transactions block))
        (let* ((transaction-key
                 (engine-payload-store-key (transaction-hash transaction)))
               (location
                 (gethash transaction-key
                          (memory-chain-store-transaction-locations store))))
          (when (and location
                     (hash32=
                      hash
                      (block-hash
                       (engine-transaction-location-block location))))
            (chain-store-journal-remhash
             (memory-chain-store-transaction-locations store)
             transaction-key))))))
  store)

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
