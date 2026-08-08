(in-package #:ethereum-lisp.test)

;;;; Content-addressed contract code (chain schema v3+): deduplication, the
;;;; round trip through :STATE and :STATE-DIFF records, the refusal of a
;;;; reference with no body, and the forward migration from the pre-v3 layout
;;;; that inlined the body in every account record.

(defparameter *code-store-test-contract-a* #(#x60 #x00 #x60 #x00 #xf3))
(defparameter *code-store-test-contract-b* #(#x60 #x01 #x60 #x01 #xf3))

(defun code-store-test-code-record-count (database)
  (length (kv-chain-record-entries database :code)))

(defun code-store-test-code-body (database code)
  "The stored body under CODE's content address, or NIL."
  (multiple-value-bind (body present-p)
      (kv-get-chain-record
       database :code (hash32-bytes (keccak-256-hash code)))
    (and present-p body)))

(defun code-store-test-state (accounts)
  (let ((state (make-state-db)))
    (dolist (entry accounts state)
      (destructuring-bind
          (address balance nonce code storage-entries)
          entry
        (state-db-set-account
         state address (make-state-account :nonce nonce :balance balance))
        (state-db-set-code state address code)
        (dolist (storage-entry storage-entries)
          (state-db-set-storage
           state address (car storage-entry) (cdr storage-entry)))))))

(defun code-store-test-chain (store)
  "Put three chained blocks and commit a post-state to each.

Two accounts share CONTRACT-A so deduplication has something to collapse, one
carries CONTRACT-B, and one has no code at all. Block 0 becomes a baseline and
the later blocks become diffs, so both record kinds are exercised."
  (let ((contract-a (state-diff-test-address 1))
        (contract-b (state-diff-test-address 2))
        (twin (state-diff-test-address 3))
        (plain (state-diff-test-address 4))
        (slot (state-diff-test-slot 1))
        (parent-hash (zero-hash32))
        (blocks nil))
    (dolist
        (accounts
          (list
           (list (list contract-a 10 1 *code-store-test-contract-a*
                       (list (cons slot 5)))
                 (list contract-b 20 2 *code-store-test-contract-b* '())
                 (list twin 30 3 *code-store-test-contract-a* '())
                 (list plain 40 4 #() '()))
           ;; A diff that leaves code untouched, then one that installs code
           ;; on the account that had none.
           (list (list contract-a 11 1 *code-store-test-contract-a*
                       (list (cons slot 5)))
                 (list contract-b 20 2 *code-store-test-contract-b* '())
                 (list twin 30 3 *code-store-test-contract-a* '())
                 (list plain 41 4 #() '()))
           (list (list contract-a 11 1 *code-store-test-contract-a*
                       (list (cons slot 5)))
                 (list contract-b 20 2 *code-store-test-contract-b* '())
                 (list twin 30 3 *code-store-test-contract-a* '())
                 (list plain 41 5 *code-store-test-contract-b* '()))))
      (let* ((state (code-store-test-state accounts))
             (number (length blocks))
             (block
               (make-block
                :header
                (make-block-header
                 :number number
                 :parent-hash parent-hash
                 :state-root (state-db-root state)
                 :timestamp (1+ number)
                 :gas-limit 30000000))))
        (chain-store-put-block store block :state-available-p t)
        (commit-state-db-to-chain-store store (block-hash block) state)
        (push block blocks)
        (setf parent-hash (block-hash block))))
    (nreverse blocks)))

(defun code-store-test-database-entries (database)
  "Every key/value pair in DATABASE as an alist keyed by key hex."
  (let ((iterator (kv-iterator database))
        (entries '()))
    (loop
      (multiple-value-bind (key value present-p) (funcall iterator)
        (unless present-p
          (return (nreverse entries)))
        (push (cons (bytes-to-hex key) (copy-seq value)) entries)))))

(defun code-store-test-databases-equal-p (left right)
  (let ((left-entries (code-store-test-database-entries left))
        (right-entries (code-store-test-database-entries right)))
    (and (= (length left-entries) (length right-entries))
         (every
          (lambda (entry)
            (let ((other (assoc (car entry) right-entries :test #'string=)))
              (and other (bytes= (cdr entry) (cdr other)))))
          left-entries))))

(defun code-store-test-downgrade-to-inline-code (store database)
  "Rewrite DATABASE's state records into the pre-v3 layout.

The inline bodies come from the very encoders the pre-v3 client used -- the
same functions, with no code sink -- so the migration is tested against
records in the shape it must actually read rather than a hand-built
approximation."
  (let ((memory-store
          (ethereum-lisp.chain-store.state:chain-store-require-memory-store
           store)))
    (dolist (entry (kv-chain-record-entries database :state))
      (kv-put-chain-record
       database :state (car entry)
       (ethereum-lisp.node-store.persistence::chain-store-state-record-rlp
        memory-store (make-hash32 (car entry)))))
    (dolist (entry (kv-chain-record-entries database :state-diff))
      (kv-put-chain-record
       database :state-diff (car entry)
       (ethereum-lisp.node-store.persistence::chain-store-state-diff-record-rlp
        memory-store (bytes-to-hex (car entry))))))
  (dolist (entry (kv-chain-record-entries database :code))
    (kv-delete-chain-record database :code (car entry)))
  ;; Schema v2 had no persisted secure tries.  Removing both namespaces makes
  ;; this a real migration fixture rather than a v2 marker pasted onto v4 data.
  (dolist (kind '(:state-history :ordered-state-history :trie-node))
    (dolist (entry (kv-chain-record-entries database kind))
      (kv-delete-chain-record database kind (car entry))))
  (kv-put-chain-schema-version database 2)
  database)

(defun code-store-test-downgrade-to-v1 (store database)
  "Rewrite DATABASE to the complete pre-v2/pre-v3 shape."
  (code-store-test-downgrade-to-inline-code store database)
  (dolist (kind '(:ordered-block :ordered-header :ordered-receipt))
    (dolist (entry (kv-chain-record-entries database kind))
      (kv-delete-chain-record database kind (car entry))))
  (kv-put-chain-schema-version database 1)
  database)

(deftest node-store-code-store-writes-each-contract-body-once
  (let* ((store (make-engine-payload-memory-store))
         (database (make-memory-key-value-database)))
    (code-store-test-chain store)
    (chain-store-export-state-records-to-kv store database)
    ;; Two distinct bodies across four accounts and three blocks.
    (is (= 2 (code-store-test-code-record-count database)))
    (is (bytes= *code-store-test-contract-a*
                (code-store-test-code-body
                 database *code-store-test-contract-a*)))
    (is (bytes= *code-store-test-contract-b*
                (code-store-test-code-body
                 database *code-store-test-contract-b*)))
    ;; No account record embeds a body any more: every code field is either
    ;; empty or exactly the 32-byte content address.
    (dolist (entry (kv-chain-record-entries database :state))
      (dolist (account (rlp-list-items (rlp-decode-one (cdr entry))))
        (let ((code (fourth (rlp-list-items account))))
          (is (member (length code) '(0 32))))))))

(deftest node-store-content-addressed-code-round-trips-through-kv
  (let* ((store (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (database (make-memory-key-value-database)))
    (chain-store-export-state-records-to-kv store database)
    (is (= +kv-chain-schema-version+
           (ethereum-lisp.node-store.persistence:node-store-chain-schema-version
            database)))
    (dolist (block blocks)
      (chain-store-put-block restored block :state-available-p nil))
    (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
     restored database)
    (dolist (block blocks)
      (let ((hash (block-hash block)))
        (is (equalp (state-diff-test-collect-accounts store block)
                  (state-diff-test-collect-accounts restored block)))
        ;; The state root is the consensus-visible commitment: it must be
        ;; identical, not merely consistent with itself.
        (is (bytes=
             (hash32-bytes
              (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
               store hash))
             (hash32-bytes
              (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
               restored hash))))))))

(deftest node-store-import-refuses-a-code-reference-with-no-body
  (let* ((store (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (restored (make-engine-payload-memory-store))
         (database (make-memory-key-value-database)))
    (chain-store-export-state-records-to-kv store database)
    (dolist (entry (kv-chain-record-entries database :code))
      (kv-delete-chain-record database :code (car entry)))
    (dolist (block blocks)
      (chain-store-put-block restored block :state-available-p nil))
    ;; A missing body must fail the read outright. Treating it as an account
    ;; without code would silently change EXTCODEHASH and the state root.
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
       restored database))))

(deftest node-store-import-refuses-a-code-body-that-does-not-match-its-address
  (let* ((store (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (restored (make-engine-payload-memory-store))
         (database (make-memory-key-value-database)))
    (chain-store-export-state-records-to-kv store database)
    (dolist (entry (kv-chain-record-entries database :code))
      (kv-put-chain-record database :code (car entry) #(#xfe)))
    (dolist (block blocks)
      (chain-store-put-block restored block :state-available-p nil))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
       restored database))))

(deftest node-store-chain-schema-migration-rewrites-inline-code-forward
  (let* ((store (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (current (make-memory-key-value-database))
         (legacy (make-memory-key-value-database)))
    (declare (ignore blocks))
    (node-store-export-to-kv store current)
    (node-store-export-to-kv store legacy)
    (code-store-test-downgrade-to-inline-code store legacy)
    (is (= 2 (ethereum-lisp.node-store.persistence:node-store-chain-schema-version
              legacy)))
    (is (zerop (code-store-test-code-record-count legacy)))
    (is (not (code-store-test-databases-equal-p current legacy)))
    (multiple-value-bind (version migrated-p)
        (ethereum-lisp.node-store.persistence:node-store-migrate-chain-schema
         legacy)
      (is (= +kv-chain-schema-version+ version))
      (is migrated-p))
    ;; The migrated database is byte-for-byte what a current client would have
    ;; written from the same store, marker and code records included.
    (is (code-store-test-databases-equal-p current legacy))
    ;; Migrating again is a no-op that reports it did nothing.
    (multiple-value-bind (version migrated-p)
        (ethereum-lisp.node-store.persistence:node-store-migrate-chain-schema
         legacy)
      (is (= +kv-chain-schema-version+ version))
      (is (not migrated-p)))
    (is (code-store-test-databases-equal-p current legacy))))

(deftest node-store-chain-schema-migration-resumes-after-a-durable-chunk
  (let* ((store (make-engine-payload-memory-store))
         (current (make-memory-key-value-database))
         (legacy (make-memory-key-value-database))
         (batch-count 0))
    (code-store-test-chain store)
    (node-store-export-to-kv store current)
    (node-store-export-to-kv store legacy)
    (code-store-test-downgrade-to-v1 store legacy)
    ;; The first callback records the progress marker; the second follows the
    ;; first rewritten record. Signalling there models a process that vanished
    ;; after RocksDB made that batch durable but before migration continued.
    (signals error
      (ethereum-lisp.node-store.persistence:node-store-migrate-chain-schema
       legacy
       :batch-size 1
       :after-batch
       (lambda (progress)
         (declare (ignore progress))
         (incf batch-count)
         (when (= batch-count 2)
           (error "injected migration interruption")))))
    (is (= 2 batch-count))
    (multiple-value-bind (version present-p)
        (kv-get-chain-schema-version legacy)
      (is present-p)
      (is (= 1 version)))
    ;; Mixed old/new records are never interpreted under the old marker.
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-chain-schema-version
       legacy))
    (multiple-value-bind (version migrated-p)
        (ethereum-lisp.node-store.persistence:node-store-migrate-chain-schema
         legacy :batch-size 1)
      (is migrated-p)
      (is (= +kv-chain-schema-version+ version)))
    ;; Resumption filled both the v2 height mirrors and the v3 code store, and
    ;; removed the private progress record in the final marker batch.
    (is (code-store-test-databases-equal-p current legacy))
    (multiple-value-bind (progress present-p)
        (kv-get-chain-record legacy :metadata "schema-migration")
      (declare (ignore progress))
      (is (not present-p)))))

(deftest node-store-chain-schema-migration-preserves-state-roots
  (let* ((store (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (restored (make-engine-payload-memory-store))
         (legacy (make-memory-key-value-database)))
    (node-store-export-to-kv store legacy)
    (code-store-test-downgrade-to-inline-code store legacy)
    (ethereum-lisp.node-store.persistence:node-store-migrate-chain-schema legacy)
    (dolist (block blocks)
      (chain-store-put-block restored block :state-available-p nil))
    (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
     restored legacy)
    (dolist (block blocks)
      (is (equalp (state-diff-test-collect-accounts store block)
                  (state-diff-test-collect-accounts restored block)))
      (is (bytes=
           (hash32-bytes
            (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
             store (block-hash block)))
           (hash32-bytes
            (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
             restored (block-hash block))))))))

(deftest node-store-reads-legacy-inline-code-without-migrating-it
  (let* ((store (make-engine-payload-memory-store))
         (blocks (code-store-test-chain store))
         (restored (make-engine-payload-memory-store))
         (legacy (make-memory-key-value-database)))
    (chain-store-export-state-records-to-kv store legacy)
    (code-store-test-downgrade-to-inline-code store legacy)
    (dolist (block blocks)
      (chain-store-put-block restored block :state-available-p nil))
    ;; The marker, not the record shape, decides the layout: a pre-v3 database
    ;; still reads correctly in place.
    (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
     restored legacy)
    (dolist (block blocks)
      (is (equalp (state-diff-test-collect-accounts store block)
                  (state-diff-test-collect-accounts restored block))))))

(deftest node-store-import-from-kv-migrates-a-legacy-inline-code-database
  (let* ((store (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (contract
           (address-from-hex "0x0000000000000000000000000000000000000011"))
         (twin
           (address-from-hex "0x0000000000000000000000000000000000000012"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (database (make-memory-key-value-database)))
    (let ((state (make-state-db)))
      (state-db-set-account
       state contract (make-state-account :nonce 7 :balance 11))
      (state-db-set-code state contract *code-store-test-contract-a*)
      (state-db-set-storage state contract slot 22)
      (state-db-set-account
       state twin (make-state-account :nonce 1 :balance 3))
      (state-db-set-code state twin *code-store-test-contract-a*)
      (setf (block-header-state-root (block-header head))
            (state-db-root state)))
    (dolist (block (list genesis head))
      (chain-store-put-block store block :state-available-p t))
    (dolist (entry (list (list contract 11 7 *code-store-test-contract-a*)
                         (list twin 3 1 *code-store-test-contract-a*)))
      (destructuring-bind (address balance nonce code) entry
        (chain-store-put-account-balance
         store (block-hash head) address balance)
        (chain-store-put-account-nonce
         store (block-hash head) address nonce)
        (chain-store-put-account-code
         store (block-hash head) address code)))
    (chain-store-put-account-storage
     store (block-hash head) contract slot 22)
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash head)
      :safe-block-hash (block-hash genesis)
      :finalized-block-hash (block-hash genesis)))
    (node-store-export-to-kv store database)
    (code-store-test-downgrade-to-inline-code store database)
    (is (= 2 (ethereum-lisp.node-store.persistence:node-store-chain-schema-version
              database)))
    ;; Adopting the datadir brings it forward, and the imported state -- whose
    ;; root the import itself checks against the header -- is unchanged.
    (node-store-import-from-kv restored database)
    (is (= +kv-chain-schema-version+
           (ethereum-lisp.node-store.persistence:node-store-chain-schema-version
            database)))
    (is (= 1 (code-store-test-code-record-count database)))
    (is (bytes= *code-store-test-contract-a*
                (chain-store-account-code
                 restored (block-hash head) contract)))
    (is (bytes= *code-store-test-contract-a*
                (chain-store-account-code
                 restored (block-hash head) twin)))
    (is (= 22 (chain-store-account-storage
               restored (block-hash head) contract slot)))))
