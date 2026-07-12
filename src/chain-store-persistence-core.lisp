(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-clear-readable-tables (store)
  (setf store (chain-store-require-memory-store store))
  (setf (memory-chain-store-blocks store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-number-blocks store)
        (make-hash-table :test 'eql)
        (memory-chain-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (memory-chain-store-transaction-locations store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-account-balances store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-account-nonces store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-account-codes store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-account-storage store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-state-blocks store)
        (make-hash-table :test 'equalp)
        (memory-chain-store-head-number store)
        0
        (memory-chain-store-head-checkpoint store)
        (make-chain-store-checkpoint :label :head)
        (memory-chain-store-safe-checkpoint store)
        (make-chain-store-checkpoint :label :safe)
        (memory-chain-store-finalized-checkpoint store)
        (make-chain-store-checkpoint :label :finalized))
  store)

(defun chain-store-publish-readable-tables (store source)
  (let ((target-chain (chain-store-require-memory-store store))
        (source-chain (chain-store-require-memory-store source))
        (source-txpool (txpool-component source)))
    (unless (and (txpool-component store) source-txpool)
      (block-validation-fail
       "Publishing node state requires source and target txpools"))
    (setf (memory-chain-store-blocks target-chain)
          (memory-chain-store-blocks source-chain)
          (memory-chain-store-number-blocks target-chain)
          (memory-chain-store-number-blocks source-chain)
          (memory-chain-store-canonical-hashes target-chain)
          (memory-chain-store-canonical-hashes source-chain)
          (memory-chain-store-transaction-locations target-chain)
          (memory-chain-store-transaction-locations source-chain)
          (memory-chain-store-account-balances target-chain)
          (memory-chain-store-account-balances source-chain)
          (memory-chain-store-account-nonces target-chain)
          (memory-chain-store-account-nonces source-chain)
          (memory-chain-store-account-codes target-chain)
          (memory-chain-store-account-codes source-chain)
          (memory-chain-store-account-storage target-chain)
          (memory-chain-store-account-storage source-chain)
          (memory-chain-store-state-blocks target-chain)
          (memory-chain-store-state-blocks source-chain)
          (memory-chain-store-head-number target-chain)
          (memory-chain-store-head-number source-chain)
          (memory-chain-store-head-checkpoint target-chain)
          (memory-chain-store-head-checkpoint source-chain)
          (memory-chain-store-safe-checkpoint target-chain)
          (memory-chain-store-safe-checkpoint source-chain)
          (memory-chain-store-finalized-checkpoint target-chain)
          (memory-chain-store-finalized-checkpoint source-chain)
          (engine-payload-memory-store-txpool store)
          source-txpool
          (memory-chain-store-invalid-tipsets target-chain)
          (memory-chain-store-invalid-tipsets source-chain)
          (memory-chain-store-remote-blocks target-chain)
          (memory-chain-store-remote-blocks source-chain)
          (memory-chain-store-blob-sidecars target-chain)
          (memory-chain-store-blob-sidecars source-chain)
          (memory-chain-store-prepared-payloads target-chain)
          (memory-chain-store-prepared-payloads source-chain)))
  store)

(defun chain-store-import-block-records-from-kv (store database)
  (setf store (chain-store-require-memory-store store))
  (dolist (entry (kv-chain-record-entries database :block))
    (let* ((identifier (car entry))
           (block (block-from-rlp (cdr entry)))
           (actual (hash32-bytes (block-hash block))))
      (unless (bytes= identifier actual)
        (block-validation-fail
         "KV block record key does not match encoded block hash"))
      (chain-store-put-block store block)))
  (setf (memory-chain-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (memory-chain-store-number-blocks store)
        (make-hash-table :test 'eql)
        (memory-chain-store-transaction-locations store)
        (make-hash-table :test 'equalp)))

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
  (setf store (chain-store-require-memory-store store))
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
                       (memory-chain-store-canonical-hashes store))
              key
              (gethash number
                       (memory-chain-store-number-blocks store))
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
     (memory-chain-store-number-blocks store))
    (setf (memory-chain-store-head-number store) head-number)))

(defun chain-store-import-checkpoints-from-kv (store database)
  (setf store (chain-store-require-memory-store store))
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
                        (memory-chain-store-head-number store)))
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
    (setf (memory-chain-store-head-checkpoint store)
          (make-chain-store-checkpoint :label :head :block-hash head-hash)
          (memory-chain-store-safe-checkpoint store)
          (make-chain-store-checkpoint :label :safe :block-hash safe-hash)
          (memory-chain-store-finalized-checkpoint store)
          (make-chain-store-checkpoint
           :label :finalized :block-hash finalized-hash))))
