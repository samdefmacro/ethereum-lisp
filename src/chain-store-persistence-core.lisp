(in-package #:ethereum-lisp.chain-store.persistence)

(defun chain-store-clear-readable-tables (store)
  (setf (engine-payload-memory-store-blocks store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-number-blocks store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-transaction-locations store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-balances store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-nonces store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-codes store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-storage store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-state-blocks store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-head-number store)
        0
        (engine-payload-memory-store-head-checkpoint store)
        (make-chain-store-checkpoint :label :head)
        (engine-payload-memory-store-safe-checkpoint store)
        (make-chain-store-checkpoint :label :safe)
        (engine-payload-memory-store-finalized-checkpoint store)
        (make-chain-store-checkpoint :label :finalized))
  store)

(defun chain-store-publish-readable-tables (store source)
  (setf (engine-payload-memory-store-blocks store)
        (engine-payload-memory-store-blocks source)
        (engine-payload-memory-store-number-blocks store)
        (engine-payload-memory-store-number-blocks source)
        (engine-payload-memory-store-canonical-hashes store)
        (engine-payload-memory-store-canonical-hashes source)
        (engine-payload-memory-store-transaction-locations store)
        (engine-payload-memory-store-transaction-locations source)
        (engine-payload-memory-store-account-balances store)
        (engine-payload-memory-store-account-balances source)
        (engine-payload-memory-store-account-nonces store)
        (engine-payload-memory-store-account-nonces source)
        (engine-payload-memory-store-account-codes store)
        (engine-payload-memory-store-account-codes source)
        (engine-payload-memory-store-account-storage store)
        (engine-payload-memory-store-account-storage source)
        (engine-payload-memory-store-state-blocks store)
        (engine-payload-memory-store-state-blocks source)
        (engine-payload-memory-store-head-number store)
        (engine-payload-memory-store-head-number source)
        (engine-payload-memory-store-head-checkpoint store)
        (engine-payload-memory-store-head-checkpoint source)
        (engine-payload-memory-store-safe-checkpoint store)
        (engine-payload-memory-store-safe-checkpoint source)
        (engine-payload-memory-store-finalized-checkpoint store)
        (engine-payload-memory-store-finalized-checkpoint source)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool source)
        (engine-payload-memory-store-invalid-tipsets store)
        (engine-payload-memory-store-invalid-tipsets source)
        (engine-payload-memory-store-remote-blocks store)
        (engine-payload-memory-store-remote-blocks source)
        (engine-payload-memory-store-blob-sidecars store)
        (engine-payload-memory-store-blob-sidecars source)
        (engine-payload-memory-store-prepared-payloads store)
        (engine-payload-memory-store-prepared-payloads source))
  store)

(defun chain-store-import-block-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :block))
    (let* ((identifier (car entry))
           (block (block-from-rlp (cdr entry)))
           (actual (hash32-bytes (block-hash block))))
      (unless (bytes= identifier actual)
        (block-validation-fail
         "KV block record key does not match encoded block hash"))
      (chain-store-put-block store block)))
  (setf (engine-payload-memory-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-number-blocks store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-transaction-locations store)
        (make-hash-table :test 'equal)))

(defun chain-store-import-header-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :header))
    (let* ((identifier (car entry))
           (hash (make-hash32 identifier))
           (block (chain-store-known-block store hash)))
      (unless block
        (block-validation-fail
         "KV header record references an unknown block"))
      (unless (bytes= (cdr entry)
                      (block-header-rlp (block-header block)))
        (block-validation-fail
         "KV header record does not match block header")))))

(defun chain-store-import-canonical-indexes-from-kv (store database)
  (let ((head-number 0))
    (dolist (entry (kv-chain-canonical-hashes database))
      (let* ((number (car entry))
             (hash (make-hash32 (cdr entry)))
             (key (engine-payload-store-key hash))
             (block (chain-store-known-block store hash)))
        (unless block
          (block-validation-fail
           "KV canonical hash references an unknown block"))
        (setf (gethash number
                       (engine-payload-memory-store-canonical-hashes store))
              key
              (gethash number
                       (engine-payload-memory-store-number-blocks store))
              block)
        (setf head-number (max head-number number))))
    (maphash
     (lambda (number block)
       (let ((header (block-header block)))
         (unless (= number (block-header-number header))
           (block-validation-fail
            "KV canonical height does not match block number"))
         (when (plusp number)
           (let ((parent
                   (chain-store-block-by-number store (1- number))))
             (unless (or (not parent)
                         (hash32=
                          (block-header-parent-hash header)
                          (block-hash parent)))
               (block-validation-fail
                "KV canonical chain is not parent-linked"))))))
     (engine-payload-memory-store-number-blocks store))
    (setf (engine-payload-memory-store-head-number store) head-number)))

(defun chain-store-import-checkpoints-from-kv (store database)
  (let (head-hash safe-hash finalized-hash)
    (dolist (entry (kv-chain-checkpoints database))
      (let ((label (car entry))
            (hash (make-hash32 (cdr entry))))
        (unless (chain-store-known-block store hash)
          (block-validation-fail
           "KV checkpoint references an unknown block"))
        (ecase label
          (:head (setf head-hash hash))
          (:safe (setf safe-hash hash))
          (:finalized (setf finalized-hash hash)))))
    (when (and (or safe-hash finalized-hash) (not head-hash))
      (block-validation-fail
       "KV safe/finalized checkpoint requires a head checkpoint"))
    (when (and head-hash
               (not (engine-payload-store-state-available-p
                     store head-hash)))
      (block-validation-fail "KV head checkpoint state is not available"))
    (when head-hash
      (let* ((head-block (engine-payload-store-known-block store head-hash))
             (head-number (block-header-number (block-header head-block)))
             (canonical-head (chain-store-canonical-hash store head-number)))
        (unless (and canonical-head
                     (hash32= canonical-head head-hash)
                     (= head-number
                        (engine-payload-memory-store-head-number store)))
          (block-validation-fail
           "KV head checkpoint does not match canonical head"))))
    (when (and head-hash safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "KV safe checkpoint is not an ancestor of head"))
    (when (and head-hash finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "KV finalized checkpoint is not an ancestor of head"))
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
         "KV safe checkpoint is older than finalized checkpoint")))
    (setf (engine-payload-memory-store-head-checkpoint store)
          (make-chain-store-checkpoint :label :head :block-hash head-hash)
          (engine-payload-memory-store-safe-checkpoint store)
          (make-chain-store-checkpoint :label :safe :block-hash safe-hash)
          (engine-payload-memory-store-finalized-checkpoint store)
          (make-chain-store-checkpoint
           :label :finalized :block-hash finalized-hash))))
