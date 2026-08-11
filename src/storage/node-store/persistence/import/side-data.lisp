(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-import-invalid-tipset-from-kv
    (store database tipset-identifier record &key now)
  (setf store (chain-store-require-memory-store store))
  (handler-case
      (let ((tipset-hash (make-hash32 tipset-identifier))
            (invalid-block
              (chain-store-block-from-persisted-record
               database tipset-identifier record "KV invalid-tipset record"
               :allow-missing-committed-p t)))
        (unless (hash32= tipset-hash (block-hash invalid-block))
          (block-validation-fail
           "KV invalid-tipset record key does not match encoded block hash"))
        (when (chain-store-known-block store tipset-hash)
          (block-validation-fail
           "KV invalid-tipset record duplicates a known block"))
        (if now
            (engine-payload-store-mark-invalid
             store invalid-block :now now)
            (engine-payload-store-mark-invalid store invalid-block)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV invalid-tipset record RLP: ~A" condition))))

(defun chain-store-import-invalid-tipsets-from-kv (store database)
  (let ((now (unix-time)))
    (dolist (entry (kv-chain-record-entries database :invalid-tipset))
      (chain-store-import-invalid-tipset-from-kv
       store database (car entry) (cdr entry) :now now))))

(defun chain-store-import-remote-block-from-kv
    (store database block-identifier record &key now finalized-number)
  (setf store (chain-store-require-memory-store store))
  (handler-case
      (let* ((block-hash (make-hash32 block-identifier))
             (block
               (chain-store-block-from-persisted-record
                database block-identifier record "KV remote-block record"
                :allow-missing-committed-p t)))
        (unless (hash32= block-hash (block-hash block))
          (block-validation-fail
           "KV remote-block record key does not match encoded block hash"))
        (multiple-value-bind (invalid-record invalid-present-p)
            (kv-get-chain-record
             database :invalid-tipset block-identifier)
          ;; A direct provider deliberately does not hydrate the complete
          ;; invalid cache here. Validate any point-conflicting owner before it
          ;; suppresses a remote target; mere key presence must not let corrupt
          ;; bytes silently erase an otherwise valid candidate.
          (when invalid-present-p
            (let ((invalid-block
                    (chain-store-block-from-persisted-record
                     database block-identifier invalid-record
                     "KV invalid-tipset owner record"
                     :allow-missing-committed-p t)))
              (unless (hash32= block-hash (block-hash invalid-block))
                (block-validation-fail
                 "KV invalid-tipset owner key does not match its block"))))
          (unless (or (chain-store-known-block store block-hash)
                      ;; INVALID was already admitted under this recovery
                      ;; operation's captured NOW. A persistence importer must
                      ;; not invoke the public getter's default wall clock and
                      ;; age-prune that deterministic snapshot a second time.
                      (gethash
                       (engine-payload-store-key block-hash)
                       (memory-chain-store-invalid-tipsets store))
                      invalid-present-p)
          (if now
              (engine-payload-store-put-remote-block
               store block :now now)
              (engine-payload-store-put-remote-block store block))
          (when finalized-number
            (engine-payload-store-prune-caches
             store :now (or now (unix-time))
             :finalized-number finalized-number)))))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV remote-block record RLP: ~A" condition))))

(defun chain-store-import-remote-blocks-from-kv (store database)
  (let* ((now (unix-time))
         (finalized (chain-store-finalized-block store))
         (finalized-number
           (and finalized
                (block-header-number (block-header finalized)))))
    (dolist (entry (kv-chain-record-entries database :remote-block))
      (chain-store-import-remote-block-from-kv
       store database (car entry) (cdr entry)
       :now now :finalized-number finalized-number))))

(defun node-store-remote-block-retained-p (store identifier)
  (nth-value
   1
   (gethash
    (bytes-to-hex identifier)
    (memory-chain-store-remote-blocks
     (chain-store-require-memory-store store)))))

(defun node-store-invalid-tipset-retained-p (store identifier)
  (nth-value
   1
   (gethash
    (bytes-to-hex identifier)
    (memory-chain-store-invalid-tipsets
     (chain-store-require-memory-store store)))))

(defconstant +node-store-remote-recovery-cleanup-batch-size+ 256
  "Maximum durable remote records examined by one startup cleanup batch.")

(defun node-store-bounded-remote-recovery-cleanup-chunk
    (store database cursor)
  "Return evicted identifiers in one bounded page strictly after CURSOR.

The returned second value is the last raw database key examined and the third
value says the remote prefix was exhausted. The iterator is always closed
before the caller mutates DATABASE."
  (let ((identifiers '())
        (last-key cursor)
        (examined 0)
        (exhausted-p nil))
    (multiple-value-bind (iterator closer)
        (kv-iterator
         database
         :start (or cursor (kv-chain-record-kind-start-key :remote-block))
         :end (kv-chain-record-kind-end-key :remote-block))
      (unwind-protect
           (loop while (< examined
                          +node-store-remote-recovery-cleanup-batch-size+)
                 do (multiple-value-bind (key record present-p)
                        (funcall iterator)
                      (declare (ignore record))
                      (unless present-p
                        (setf exhausted-p t)
                        (return))
                      ;; START is inclusive. CURSOR names the last key handled
                      ;; by the preceding page and must not be counted twice.
                      (unless (and cursor (bytes= key cursor))
                        (incf examined)
                        (setf last-key (copy-seq key))
                        (let ((identifier
                                (kv-chain-record-key-identifier
                                 :remote-block key)))
                          (unless (node-store-remote-block-retained-p
                                   store identifier)
                            (push identifier identifiers))))))
        (funcall closer)))
    (values (nreverse identifiers) last-key exhausted-p)))

(defun node-store-clean-bounded-remote-recovery-records (store database)
  "Delete rejected remote records in bounded, hash-owner-atomic batches."
  (loop with cursor = nil
        do (multiple-value-bind (identifiers next-cursor exhausted-p)
               (node-store-bounded-remote-recovery-cleanup-chunk
                store database cursor)
             (when identifiers
               (let ((batch (make-kv-write-batch)))
                 (dolist (identifier identifiers)
                   (kv-batch-delete-chain-record
                    batch :remote-block identifier))
                 (node-store-populate-evicted-remote-bal-cleanup-batch
                  store database batch identifiers
                  :deleted-remote-identifiers identifiers)
                 (kv-apply-batch database batch)))
             (when exhausted-p
               (return))
             (unless next-cursor
               (storage-fail
                "Bounded remote recovery cleanup made no progress"))
             (setf cursor next-cursor))))

(defun node-store-bounded-invalid-recovery-cleanup-chunk
    (store database cursor)
  "Return rejected invalid identifiers in one bounded page after CURSOR."
  (let ((identifiers '())
        (last-key cursor)
        (examined 0)
        (exhausted-p nil))
    (multiple-value-bind (iterator closer)
        (kv-iterator
         database
         :start (or cursor (kv-chain-record-kind-start-key :invalid-tipset))
         :end (kv-chain-record-kind-end-key :invalid-tipset))
      (unwind-protect
           (loop while (< examined
                          +node-store-remote-recovery-cleanup-batch-size+)
                 do (multiple-value-bind (key record present-p)
                        (funcall iterator)
                      (declare (ignore record))
                      (unless present-p
                        (setf exhausted-p t)
                        (return))
                      (unless (and cursor (bytes= key cursor))
                        (incf examined)
                        (setf last-key (copy-seq key))
                        (let ((identifier
                                (kv-chain-record-key-identifier
                                 :invalid-tipset key)))
                          (unless (node-store-invalid-tipset-retained-p
                                   store identifier)
                            (push identifier identifiers))))))
        (funcall closer)))
    (values (nreverse identifiers) last-key exhausted-p)))

(defun node-store-clean-bounded-invalid-recovery-records (store database)
  "Delete rejected invalid records in bounded, BAL-owner-atomic batches."
  (loop with cursor = nil
        do (multiple-value-bind (identifiers next-cursor exhausted-p)
               (node-store-bounded-invalid-recovery-cleanup-chunk
                store database cursor)
             (when identifiers
               (let ((batch (make-kv-write-batch)))
                 (dolist (identifier identifiers)
                   (kv-batch-delete-chain-record
                    batch :invalid-tipset identifier))
                 (node-store-populate-evicted-remote-bal-cleanup-batch
                  store database batch identifiers
                  :deleted-invalid-identifiers identifiers)
                 (kv-apply-batch database batch)))
             (when exhausted-p
               (return))
             (unless next-cursor
               (storage-fail
                "Bounded invalid recovery cleanup made no progress"))
             (setf cursor next-cursor))))

(defun node-store-import-bounded-invalid-tipsets-from-kv
    (store database &key (now (unix-time)) finalized-number)
  "Restore deterministic invalid verdicts without unbounded hydration."
  (setf store (chain-store-require-memory-store store))
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Bounded invalid-tipset import requires a key-value database"))
  (let ((*engine-payload-store-track-durable-cache-deletions-p* nil)
        (ethereum-lisp.chain-store::*engine-payload-store-suppress-durable-cache-deletions-p*
          t))
    (multiple-value-bind (iterator closer)
        (kv-iterator
         database
         :start (kv-chain-record-kind-start-key :invalid-tipset)
         :end (kv-chain-record-kind-end-key :invalid-tipset))
      (unwind-protect
           (loop
             (multiple-value-bind (key record present-p)
                 (funcall iterator)
               (unless present-p
                 (return))
               (chain-store-import-invalid-tipset-from-kv
                store database
                (kv-chain-record-key-identifier :invalid-tipset key)
                record :now now)
               (engine-payload-store-prune-caches
                store :now now :finalized-number finalized-number)))
        (funcall closer))))
  (node-store-clean-bounded-invalid-recovery-records store database)
  store)

(defun node-store-import-bounded-remote-blocks-from-kv
    (store database &key (now (unix-time)) finalized-number)
  "Restore durable remote candidates without hydrating an unbounded table.

Records are decoded and admitted one at a time.  Each admission immediately
enforces the production count/byte/age policy, so the in-memory table never
exceeds its configured bounds.  A second prefix-only pass removes evicted
durable records in bounded pages; within each page, every remote record and its
unowned BAL side data are deleted in the same atomic write batch.  If validation
or any cleanup batch fails, startup fails before STORE is published."
  (setf store (chain-store-require-memory-store store))
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Bounded remote-block import requires a key-value database"))
  (let ((*engine-payload-store-track-durable-cache-deletions-p* nil)
        (ethereum-lisp.chain-store::*engine-payload-store-suppress-durable-cache-deletions-p*
          t))
    (multiple-value-bind (iterator closer)
        (kv-iterator
         database
         :start (kv-chain-record-kind-start-key :remote-block)
         :end (kv-chain-record-kind-end-key :remote-block))
      (unwind-protect
           (loop
             (multiple-value-bind (key record present-p)
                 (funcall iterator)
               (unless present-p
                 (return))
               (chain-store-import-remote-block-from-kv
                store
                database
                (kv-chain-record-key-identifier :remote-block key)
                record
                :now now
                :finalized-number finalized-number)))
        (funcall closer)))
    ;; Direct startup already installed finalized checkpoint state. Apply that
    ;; semantic bound before the durable cleanup pages decide the retained set.
    (engine-payload-store-prune-caches
     store :now now :finalized-number finalized-number))
  (node-store-clean-bounded-remote-recovery-records store database)
  store)
