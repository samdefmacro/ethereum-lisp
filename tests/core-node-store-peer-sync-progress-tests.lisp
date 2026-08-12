(in-package #:ethereum-lisp.test)

(defun peer-sync-progress-test-peer-id (&optional (seed 1))
  (let ((peer-id (make-byte-vector 64)))
    (dotimes (index (length peer-id) peer-id)
      (setf (aref peer-id index) (mod (+ seed index) 256)))))

(defun peer-sync-progress-test-authority-id ()
  (make-hash32 (make-byte-vector 32 :initial-element 77)))

(defun peer-sync-progress-test-install-metadata
    (database chain-id genesis-hash authority-id)
  (let ((batch (make-kv-write-batch)))
    (ethereum-lisp.node-store.persistence::node-store-populate-persistence-metadata-batch
     batch
     (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
      :role :database
      :generation 1
      :chain-id chain-id
      :genesis-hash genesis-hash
      :authority-id authority-id
      :base-chain-generation 1))
    (kv-apply-batch database batch))
  database)

(defun peer-sync-progress-test-progress
    (peer-id chain-id genesis-hash authority-id block)
  (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
   :peer-id peer-id
   :authority-id authority-id
   :chain-id chain-id
   :genesis-hash genesis-hash
   :last-number (block-header-number (block-header block))
   :last-hash (block-hash block)))

(defun peer-sync-progress-test-put-raw
    (database peer-id record)
  (kv-put-chain-record database :peer-sync-progress peer-id record))

(deftest node-store-peer-sync-progress-roundtrips-by-peer-id
  (let* ((database (make-memory-key-value-database))
         (peer-id (peer-sync-progress-test-peer-id))
         (other-peer-id (peer-sync-progress-test-peer-id 2))
         (chain-id 11155111)
         (genesis-hash
           (make-hash32 (make-byte-vector 32 :initial-element 11)))
         (authority-id (peer-sync-progress-test-authority-id))
         (last-hash
           (make-hash32 (make-byte-vector 32 :initial-element 22)))
         (progress
           (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
            :peer-id peer-id
            :authority-id authority-id
            :chain-id chain-id
            :genesis-hash genesis-hash
            :last-number 42
            :last-hash last-hash))
         (batch (make-kv-write-batch)))
    (peer-sync-progress-test-install-metadata
     database chain-id genesis-hash authority-id)
    (is
     (ethereum-lisp.node-store.persistence:node-store-populate-peer-sync-progress-batch
      database batch progress))
    (kv-apply-batch database batch)
    (multiple-value-bind (restored present-p)
        (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
         database peer-id)
      (is present-p)
      (when restored
        (is (bytes=
             peer-id
             (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-peer-id
              restored)))
        (is (hash32=
             authority-id
             (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-authority-id
              restored)))
        (is (= chain-id
               (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-chain-id
                restored)))
        (is (hash32=
             genesis-hash
             (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-genesis-hash
              restored)))
        (is (= 42
               (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-number
                restored)))
        (is (hash32= last-hash
                     (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-hash
                      restored)))))
    (multiple-value-bind (missing present-p)
        (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
         database other-peer-id)
      (is (null missing))
      (is (not present-p)))))

(deftest node-store-peer-sync-progress-obsolete-cursor-deletes-atomically
  (let* ((database (make-memory-key-value-database))
         (peer-id (peer-sync-progress-test-peer-id))
         (chain-id 1)
         (genesis-hash
           (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (authority-id (peer-sync-progress-test-authority-id))
         (progress
           (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
            :peer-id peer-id
            :authority-id authority-id
            :chain-id chain-id
            :genesis-hash genesis-hash
            :last-number 9
            :last-hash
            (make-hash32 (make-byte-vector 32 :initial-element 4))))
         (batch (make-kv-write-batch)))
    (peer-sync-progress-test-install-metadata
     database chain-id genesis-hash authority-id)
    (ethereum-lisp.node-store.persistence:node-store-populate-peer-sync-progress-batch
     database batch progress)
    (kv-apply-batch database batch)
    (is
     (ethereum-lisp.node-store.persistence:node-store-delete-peer-sync-progress
      database peer-id))
    (multiple-value-bind (missing present-p)
        (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
         database peer-id)
      (is (null missing))
      (is (not present-p)))
    (is (not
         (ethereum-lisp.node-store.persistence:node-store-delete-peer-sync-progress
          database peer-id)))))

(deftest node-store-peer-sync-progress-rejects-regression-and-same-height-reorg
  (let* ((database (make-memory-key-value-database))
         (peer-id (peer-sync-progress-test-peer-id))
         (chain-id 1)
         (genesis-hash
           (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (authority-id (peer-sync-progress-test-authority-id))
         (old-hash
           (make-hash32 (make-byte-vector 32 :initial-element 4))))
    (peer-sync-progress-test-install-metadata
     database chain-id genesis-hash authority-id)
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.node-store.persistence:node-store-populate-peer-sync-progress-batch
       database batch
       (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
        :peer-id peer-id :authority-id authority-id :chain-id chain-id
        :genesis-hash genesis-hash :last-number 10 :last-hash old-hash))
      (kv-apply-batch database batch))
    (dolist (attempt
             (list
              (list 9 (make-hash32
                       (make-byte-vector 32 :initial-element 5)))
              (list 10 (make-hash32
                        (make-byte-vector 32 :initial-element 6)))))
      (signals block-validation-error
        (ethereum-lisp.node-store.persistence:node-store-populate-peer-sync-progress-batch
         database (make-kv-write-batch)
         (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
          :peer-id peer-id :authority-id authority-id :chain-id chain-id
          :genesis-hash genesis-hash
          :last-number (first attempt) :last-hash (second attempt)))))
    (multiple-value-bind (restored present-p)
        (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
         database peer-id)
      (is present-p)
      (when restored
        (is (= 10
               (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-number
                restored)))
        (is (hash32=
             old-hash
             (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-hash
              restored)))))))

(deftest node-store-peer-sync-progress-rejects-malformed-and-wrong-identity
  (let* ((database (make-memory-key-value-database))
         (peer-id (peer-sync-progress-test-peer-id))
         (wrong-peer-id (peer-sync-progress-test-peer-id 9))
         (chain-id 1)
         (genesis-hash
           (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (authority-id (peer-sync-progress-test-authority-id))
         (last-hash
           (make-hash32 (make-byte-vector 32 :initial-element 4))))
    (peer-sync-progress-test-install-metadata
     database chain-id genesis-hash authority-id)
    (peer-sync-progress-test-put-raw
     database peer-id
     (rlp-encode
      (make-rlp-list
       2 peer-id (hash32-bytes authority-id) chain-id
       (hash32-bytes genesis-hash) 3 (hash32-bytes last-hash))))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
       database peer-id))
    (peer-sync-progress-test-put-raw
     database peer-id
     (rlp-encode
      (make-rlp-list
       1 wrong-peer-id (hash32-bytes authority-id) chain-id
       (hash32-bytes genesis-hash) 3 (hash32-bytes last-hash))))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
       database peer-id))
    (peer-sync-progress-test-put-raw
     database peer-id
     (rlp-encode
      (make-rlp-list
       1 peer-id (hash32-bytes authority-id) (1+ chain-id)
       (hash32-bytes genesis-hash) 3 (hash32-bytes last-hash))))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
       database peer-id))
    (peer-sync-progress-test-put-raw
     database peer-id
     (rlp-encode
      (make-rlp-list
       1 peer-id (hash32-bytes authority-id) chain-id
       (make-byte-vector 32) 3 (hash32-bytes last-hash))))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
       database peer-id))
    (peer-sync-progress-test-put-raw
     database peer-id
     (rlp-encode
      (make-rlp-list
       1 peer-id (hash32-bytes authority-id) chain-id
       (hash32-bytes genesis-hash) 3 (make-byte-vector 31))))
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
       database peer-id))))

(deftest node-store-payload-candidate-and-peer-progress-are-one-batch
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore parent transaction recipient))
    (let* ((database
             (make-instance 'forkchoice-delta-failing-test-database))
           (peer-id (peer-sync-progress-test-peer-id))
           (chain-id 1)
           (genesis-hash (block-hash genesis))
           (authority-id (peer-sync-progress-test-authority-id))
           (progress
             (peer-sync-progress-test-progress
              peer-id chain-id genesis-hash authority-id candidate))
           (candidate-id (hash32-bytes (block-hash candidate))))
      (peer-sync-progress-test-install-metadata
       database chain-id genesis-hash authority-id)
      (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
            (forkchoice-delta-failing-test-database-fail-next-apply-p database)
            t)
      (signals error
        (node-store-export-payload-candidate-to-kv
         store candidate database :peer-sync-progress progress))
      (is (= 1
             (forkchoice-delta-failing-test-database-apply-attempts
              database)))
      (dolist (kind '(:block :header :receipt :state))
        (multiple-value-bind (record present-p)
            (kv-get-chain-record database kind candidate-id)
          (declare (ignore record))
          (is (not present-p))))
      (multiple-value-bind (restored present-p)
          (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
           database peer-id)
        (is (null restored))
        (is (not present-p)))
      (is (eq database
              (node-store-export-payload-candidate-to-kv
               store candidate database :peer-sync-progress progress)))
      (is (= 2
             (forkchoice-delta-failing-test-database-apply-attempts
              database)))
      (dolist (kind '(:block :header :receipt :state))
        (multiple-value-bind (record present-p)
            (kv-get-chain-record database kind candidate-id)
          (is present-p)
          (when present-p
            (is (plusp (length record))))))
      (multiple-value-bind (restored present-p)
          (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
           database peer-id)
        (is present-p)
        (when restored
          (is (hash32=
               (block-hash candidate)
               (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-hash
                restored)))))
      (is (null
           (kv-chain-record-entries database :canonical-hash))))))

(deftest node-store-payload-candidate-adds-progress-after-idempotent-export
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore parent transaction recipient))
    (let* ((database (make-memory-key-value-database))
           (peer-id (peer-sync-progress-test-peer-id))
           (chain-id 1)
           (genesis-hash (block-hash genesis))
           (authority-id (peer-sync-progress-test-authority-id))
           (progress
             (peer-sync-progress-test-progress
              peer-id chain-id genesis-hash authority-id candidate)))
      (peer-sync-progress-test-install-metadata
       database chain-id genesis-hash authority-id)
      (node-store-export-payload-candidate-to-kv store candidate database)
      (multiple-value-bind (missing present-p)
          (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
           database peer-id)
        (is (null missing))
        (is (not present-p)))
      (node-store-export-payload-candidate-to-kv
       store candidate database :peer-sync-progress progress)
      (multiple-value-bind (restored present-p)
          (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
           database peer-id)
        (is present-p)
        (when restored
          (is (= (block-header-number (block-header candidate))
                 (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-number
                  restored))))))))

(deftest node-store-payload-candidate-rejects-mismatched-peer-progress
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore parent transaction recipient))
    (let* ((database (make-memory-key-value-database))
           (peer-id (peer-sync-progress-test-peer-id))
           (chain-id 1)
           (genesis-hash (block-hash genesis))
           (authority-id (peer-sync-progress-test-authority-id))
           (progress
             (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
              :peer-id peer-id
              :authority-id authority-id
              :chain-id chain-id
              :genesis-hash genesis-hash
              :last-number
              (1- (block-header-number (block-header candidate)))
              :last-hash (block-hash candidate))))
      (peer-sync-progress-test-install-metadata
       database chain-id genesis-hash authority-id)
      (signals block-validation-error
        (node-store-export-payload-candidate-to-kv
         store candidate database :peer-sync-progress progress))
      (is (null (kv-chain-record-entries database :block)))
      (is (null
           (kv-chain-record-entries database :peer-sync-progress))))))

(deftest node-store-payload-candidate-removes-buffered-record-atomically
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore genesis parent transaction recipient))
    (let* ((database
             (make-instance 'forkchoice-delta-failing-test-database))
           (identifier (hash32-bytes (block-hash candidate)))
           (remote-record
             (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
              candidate)))
      (kv-put-chain-record database :remote-block identifier remote-record)
      (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
            (forkchoice-delta-failing-test-database-fail-next-apply-p database)
            t)
      (signals error
        (node-store-export-payload-candidate-to-kv
         store candidate database))
      (is (= 1
             (forkchoice-delta-failing-test-database-apply-attempts
              database)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :remote-block identifier)
        (is present-p)
        (is (bytes= remote-record record)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :block identifier)
        (declare (ignore record))
        (is (not present-p)))
      (node-store-export-payload-candidate-to-kv
       store candidate database)
      (is (= 2
             (forkchoice-delta-failing-test-database-apply-attempts
              database)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :remote-block identifier)
        (declare (ignore record))
        (is (not present-p)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :block identifier)
        (is present-p)
        (is (plusp (length record)))))))

(deftest node-store-buffered-candidate-export-is-atomic-and-cache-bound
  (let* ((database
           (make-instance 'forkchoice-delta-failing-test-database))
         (store (make-engine-payload-memory-store))
         (buffered (chain-store-bal-persistence-test-block 7 41 :bal-p t))
         (identifier (hash32-bytes (block-hash buffered))))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store buffered)
    (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
          (forkchoice-delta-failing-test-database-fail-next-apply-p database)
          t)
    (signals error
      (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
       store buffered database))
    (is (= 1
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (dolist (kind '(:remote-block :block-access-list))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database kind identifier)
        (declare (ignore record))
        (is (not present-p))))
    (is (eq database
            (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
             store buffered database)))
    (is (= 2
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :remote-block identifier)
      (is present-p)
      (is (bytes=
           (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
            buffered)
           record)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :block-access-list identifier)
      (is present-p)
      (is (bytes= (block-encoded-block-access-list buffered) record)))
    ;; An exact replay is a true changed-key no-op: no third WAL batch.
    (node-store-export-buffered-candidate-to-kv store buffered database)
    (is (= 2
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (chain-store-put-block store buffered :state-available-p nil)
    (signals block-validation-error
      (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
       store buffered database))))

(deftest node-store-buffered-blob-sidecar-candidate-persists-in-the-same-batch
  (let* ((database
           (make-instance 'forkchoice-delta-failing-test-database))
         (store (make-engine-payload-memory-store))
         (sidecar (cache-bounds-test-sidecar 73))
         (versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
         (transaction
           (make-blob-transaction
            :chain-id 1
            :nonce 0
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to (zero-address)
            :max-fee-per-blob-gas 10
            :blob-versioned-hashes (list versioned-hash)))
         (buffered
           (make-block
            :header
            (make-block-header
             :number 7
             :timestamp 41
             :gas-limit 30000000
             :transactions-root (transaction-list-root (list transaction)))
            :transactions (list transaction)))
         (block-identifier (hash32-bytes (block-hash buffered)))
         (sidecar-identifier (hash32-bytes versioned-hash)))
    ;; Establish the current schema before the admission batch so the final
    ;; assertion exercises the same direct point-read used after restart.
    (node-store-export-to-kv store database)
    (let ((*kzg-blob-proof-verifier*
            (lambda (blob commitment proof)
              (declare (ignore blob commitment proof))
              t)))
      ;; Persistence observes the transaction's already-admitted cache view;
      ;; it must not replace this deterministic clock with wall time.
      (engine-payload-store-put-blob-sidecar
       store sidecar :block-number 7 :now 10))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store buffered)
    (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
          (forkchoice-delta-failing-test-database-fail-next-apply-p database)
          t)
    (signals error
      (node-store-export-buffered-candidate-to-kv
       store buffered database))
    (is (= 1
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (dolist (entry (list (cons :remote-block block-identifier)
                         (cons :blob-sidecar sidecar-identifier)))
      (is (not (nth-value
                1
                (kv-get-chain-record
                 database (car entry) (cdr entry))))))
    (node-store-export-buffered-candidate-to-kv store buffered database)
    (is (= 2
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (dolist (entry (list (cons :remote-block block-identifier)
                         (cons :blob-sidecar sidecar-identifier)))
      (is (nth-value
           1
           (kv-get-chain-record database (car entry) (cdr entry)))))
    (let ((proof-checks 0))
      (let* ((*kzg-blob-proof-verifier*
               (lambda (blob commitment proof)
                 (declare (ignore blob commitment proof))
                 (incf proof-checks)
                 t))
             (direct (make-database-engine-payload-store database))
             (restored
               (engine-payload-store-blob-and-proofs-v1
                direct versioned-hash)))
        (is restored)
        (is (= 1 proof-checks))
        (is (zerop
             (hash-table-count
              (ethereum-lisp.chain-store.state:memory-chain-store-blob-sidecars
               (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                direct)))))
        (when restored
          (is (bytes= (first (blob-sidecar-blobs sidecar))
                      (engine-blob-and-proofs-blob restored))))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (blob commitment proof)
              (declare (ignore blob commitment proof))
              nil)))
      (signals ethereum-lisp.validation:storage-error
        (engine-payload-store-blob-and-proofs-v1
         (make-database-engine-payload-store database)
         versioned-hash)))
    (let ((ethereum-lisp.kzg:*kzg-verifier* nil)
          (*kzg-blob-proof-verifier* nil))
      (signals ethereum-lisp.kzg:kzg-unavailable-error
        (engine-payload-store-blob-and-proofs-v1
         (make-database-engine-payload-store database)
         versioned-hash)))))

(deftest chain-store-cache-payload-candidate-export-drains-both-tombstones
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore genesis parent transaction recipient))
    (let* ((database (make-forkchoice-delta-test-database))
           (old-remote
             (chain-store-bal-persistence-test-block 91 91 :bal-p t))
           (old-invalid
             (chain-store-bal-persistence-test-block 92 92 :bal-p t))
           (remote-id (hash32-bytes (block-hash old-remote)))
           (invalid-id (hash32-bytes (block-hash old-invalid)))
           (chain
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store)))
      ;; Establish two durable owners before evicting them independently. The
      ;; next durable operation is an executed candidate, so that exporter must
      ;; consume both namespaces rather than waiting for forkchoice.
      (setf (forkchoice-delta-test-database-forbid-iteration-p database) t)
      (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
       store old-remote :now 10)
      (node-store-export-buffered-candidate-to-kv
       store old-remote database)
      (engine-payload-store-mark-invalid store old-invalid :now 10)
      (node-store-export-invalid-candidate-to-kv
       store old-invalid database)
      (ethereum-lisp.chain-store:engine-payload-store-remove-remote-block
       store (block-hash old-remote))
      (engine-payload-store-invalid-block
       store (block-hash old-invalid)
       :now (+ 10
               ethereum-lisp.chain-store:+engine-invalid-tipsets-max-age-seconds+))
      (is (= 1
             (hash-table-count
              (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
               chain))))
      (is (= 1
             (hash-table-count
              (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
               chain))))
      (node-store-export-payload-candidate-to-kv
       store candidate database)
      (dolist (entry (list (cons :remote-block remote-id)
                           (cons :invalid-tipset invalid-id)
                           (cons :block-access-list remote-id)
                           (cons :block-access-list invalid-id)))
        (is (not
             (nth-value
              1 (kv-get-chain-record database (car entry) (cdr entry))))))
      (is (zerop
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
             chain))))
      (is (zerop
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
             chain)))))))

(deftest node-store-invalid-verdict-atomically-replaces-buffered-record
  (let* ((database
           (make-instance 'forkchoice-delta-failing-test-database))
         (store (make-engine-payload-memory-store))
         (candidate (chain-store-bal-persistence-test-block 8 42 :bal-p t))
         (identifier (hash32-bytes (block-hash candidate))))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store candidate)
    (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
     store candidate database)
    (engine-payload-store-mark-invalid store candidate)
    (setf (forkchoice-delta-failing-test-database-fail-next-apply-p database)
          t)
    (signals error
      (ethereum-lisp.node-store.persistence:node-store-export-invalid-candidate-to-kv
       store candidate database))
    ;; A failed WAL apply preserves the complete old buffered view.
    (is (nth-value 1
                   (kv-get-chain-record database :remote-block identifier)))
    (is (not (nth-value
              1 (kv-get-chain-record database :invalid-tipset identifier))))
    (ethereum-lisp.node-store.persistence:node-store-export-invalid-candidate-to-kv
     store candidate database)
    (is (not (nth-value
              1 (kv-get-chain-record database :remote-block identifier))))
    (is (nth-value 1
                   (kv-get-chain-record database :invalid-tipset identifier)))
    ;; The invalid record now owns the same private BAL side data, so incremental
    ;; remote cleanup must retain it even though the old remote owner vanished.
    (is (nth-value 1
                   (kv-get-chain-record
                    database :block-access-list identifier)))))

(deftest node-store-invalid-descendant-removes-buffered-bal-without-false-owner
  (let* ((database (make-memory-key-value-database))
         (store (make-engine-payload-memory-store))
         (invalid-root
           (chain-store-bal-persistence-test-block 9 60 :bal-p nil))
         (descendant
           (chain-store-bal-persistence-test-block 10 61 :bal-p t))
         (root-id (hash32-bytes (block-hash invalid-root)))
         (descendant-id (hash32-bytes (block-hash descendant))))
    (engine-payload-store-mark-invalid store invalid-root)
    (node-store-export-invalid-candidate-to-kv
     store invalid-root database)
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store descendant)
    (node-store-export-buffered-candidate-to-kv
     store descendant database)
    (is (nth-value
         1 (kv-get-chain-record database :block-access-list descendant-id)))
    (engine-payload-store-mark-invalid
     store invalid-root :head-hash (block-hash descendant))
    (node-store-export-invalid-candidate-to-kv
     store descendant database)
    (is (nth-value
         1 (kv-get-chain-record database :invalid-tipset root-id)))
    ;; Descendant mappings are process-local acceleration only. They never own
    ;; a durable block body or keep the removed remote block's BAL alive.
    (dolist (kind '(:remote-block :invalid-tipset :block-access-list))
      (is (not
           (nth-value
            1 (kv-get-chain-record database kind descendant-id)))))))

(deftest node-store-invalid-eviction-cleans-orphan-bal-and-keeps-shared-owner
  (let* ((database (make-memory-key-value-database))
         (store (make-engine-payload-memory-store))
         (shared (chain-store-bal-persistence-test-block 1 1 :bal-p t))
         (orphan (chain-store-bal-persistence-test-block 2 2 :bal-p t))
         (shared-id (hash32-bytes (block-hash shared)))
         (orphan-id (hash32-bytes (block-hash orphan))))
    ;; A staged body is an independent owner of the same immutable BAL.
    (kv-put-chain-record
     database :staged-block shared-id
     (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
      shared))
    (loop for number from 1 to 514
          for block =
            (cond
              ((= number 1) shared)
              ((= number 2) orphan)
              (t (chain-store-bal-persistence-test-block
                  number (mod number 256) :bal-p t)))
          do (engine-payload-store-mark-invalid store block :now number)
             (node-store-export-invalid-candidate-to-kv
              store block database))
    (dolist (identifier (list shared-id orphan-id))
      (is (not
           (nth-value
            1
            (kv-get-chain-record
             database :invalid-tipset identifier)))))
    (is (nth-value
         1 (kv-get-chain-record database :block-access-list shared-id)))
    (is (not
         (nth-value
          1 (kv-get-chain-record database :block-access-list orphan-id))))
    (let ((chain
            (ethereum-lisp.chain-store.state:chain-store-require-memory-store
             store)))
      (is (zerop
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
             chain)))))))

(deftest node-store-buffered-candidate-export-sweeps-durable-evictions
  (let ((database (make-memory-key-value-database))
        (store (make-engine-payload-memory-store)))
    (loop for marker from 1 to 97
          for block =
            (chain-store-bal-persistence-test-block
             marker (+ 100 marker) :bal-p nil)
          do (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
              store block :now 500)
             (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
              store block database))
    (let* ((chain
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store))
           (remote
             (ethereum-lisp.chain-store.state:memory-chain-store-remote-blocks
              chain))
           (durable (kv-chain-record-entries database :remote-block)))
      (is (= ethereum-lisp.chain-store:+engine-remote-block-cache-count-limit+
             (hash-table-count remote)))
      (is (= (hash-table-count remote) (length durable)))
      (is (zerop
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
             chain))))
      (dolist (entry durable)
        (is (nth-value
             1
             (gethash
              (bytes-to-hex (car entry))
              remote)))))))

(deftest chain-store-cache-buffered-eviction-tombstone-retries-atomically
  (let* ((database
           (make-instance 'forkchoice-delta-failing-test-database))
         (store (make-engine-payload-memory-store))
         (chain
           (ethereum-lisp.chain-store.state:chain-store-require-memory-store
            store))
         (invalid
           (chain-store-bal-persistence-test-block 600 98 :bal-p nil))
         (invalid-id (hash32-bytes (block-hash invalid)))
         (latest nil))
    (engine-payload-store-enable-durable-cache-change-tracking store)
    (loop for marker from 1 to 96
          for block =
            (chain-store-bal-persistence-test-block
             marker (mod (+ 500 marker) 256) :bal-p nil)
          do (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
              store block :now marker)
             (node-store-export-buffered-candidate-to-kv
              store block database))
    (engine-payload-store-mark-invalid store invalid :now 100)
    (node-store-export-invalid-candidate-to-kv store invalid database)
    (engine-payload-store-invalid-block
     store (block-hash invalid)
     :now (+ 100
             ethereum-lisp.chain-store:+engine-invalid-tipsets-max-age-seconds+))
    (setf latest
          (chain-store-bal-persistence-test-block
           97 (mod 597 256) :bal-p nil))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store latest :now 97)
    (is (= 1
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
             chain))))
    (is (= 1
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
             chain))))
    (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
          (forkchoice-delta-failing-test-database-fail-next-apply-p database)
          t)
    (signals error
      (node-store-export-buffered-candidate-to-kv
       store latest database))
    (is (= 1
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (is (= 1
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
             chain))))
    (is (= 1
           (hash-table-count
            (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
             chain))))
    (is (nth-value
         1 (kv-get-chain-record database :invalid-tipset invalid-id)))
    (is (= 96 (length (kv-chain-record-entries database :remote-block))))
    (node-store-export-buffered-candidate-to-kv store latest database)
    (is (= 2
           (forkchoice-delta-failing-test-database-apply-attempts database)))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
           chain))))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
           chain))))
    (is (not
         (nth-value
          1 (kv-get-chain-record database :invalid-tipset invalid-id))))
    (is (= 96 (length (kv-chain-record-entries database :remote-block))))))

(defun snap-skeleton-test-progress
    (authority-id chain-id genesis-hash anchor target)
  (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
   :authority-id authority-id :chain-id chain-id
   :genesis-hash genesis-hash
   :target-number (block-header-number (block-header target))
   :target-hash (block-hash target)
   :anchor-number (block-header-number (block-header anchor))
   :anchor-hash (block-hash anchor)
   :pivot-number (block-header-number (block-header target))
   :pivot-hash (block-hash target)
   :last-number (block-header-number (block-header target))
   :last-hash (block-hash target)))

(deftest node-store-snap-skeleton-blocks-and-cursor-are-one-batch
  (:layer :integration :module :persistence)
  (multiple-value-bind
      (store genesis anchor target transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore store transaction recipient))
    (let* ((database
             (make-instance 'forkchoice-delta-failing-test-database))
           (chain-id 1)
           (authority-id (peer-sync-progress-test-authority-id))
           (progress
             (snap-skeleton-test-progress
              authority-id chain-id (block-hash genesis) anchor target))
           (identifier (hash32-bytes (block-hash target))))
      (peer-sync-progress-test-install-metadata
       database chain-id (block-hash genesis) authority-id)
      (setf (forkchoice-delta-failing-test-database-apply-attempts database) 0
            (forkchoice-delta-failing-test-database-fail-next-apply-p database)
            t)
      (signals error
        (ethereum-lisp.node-store.persistence:node-store-export-snap-skeleton-batch-to-kv
         database (list target) progress))
      (is (= 1
             (forkchoice-delta-failing-test-database-apply-attempts database)))
      (dolist (kind '(:block :header :receipt))
        (is (not (nth-value
                  1 (kv-get-chain-record database kind identifier)))))
      (is (not
           (nth-value
            1
            (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
             database))))
      (ethereum-lisp.node-store.persistence:node-store-export-snap-skeleton-batch-to-kv
       database (list target) progress)
      (is (= 2
             (forkchoice-delta-failing-test-database-apply-attempts database)))
      (dolist (kind '(:block :header :receipt))
        (is (nth-value 1 (kv-get-chain-record database kind identifier))))
      ;; Skeleton download never publishes a canonical index.
      (is (null (kv-chain-record-entries database :canonical-hash)))
      (multiple-value-bind (restored present-p)
          (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
           database)
        (is present-p)
        (is (= (block-header-number (block-header target))
               (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-number
                restored)))
        (is (hash32=
             (block-hash target)
             (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-hash
              restored)))))))

(deftest node-store-snap-skeleton-progress-survives-a-file-reopen
  (:layer :integration :module :persistence)
  (multiple-value-bind
      (store genesis anchor target transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore store transaction recipient))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-snap-skeleton-~A" (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (chain-id 1)
           (authority-id (peer-sync-progress-test-authority-id))
           (target-id (hash32-bytes (block-hash target)))
           (progress
             (snap-skeleton-test-progress
              authority-id chain-id (block-hash genesis) anchor target)))
      (unwind-protect
           (progn
             (let ((database (make-file-key-value-database path)))
               (peer-sync-progress-test-install-metadata
                database chain-id (block-hash genesis) authority-id)
               (ethereum-lisp.node-store.persistence:node-store-export-snap-skeleton-batch-to-kv
                database (list target) progress))
             (let ((reopened (make-file-key-value-database path)))
               (is (nth-value
                    1 (kv-get-chain-record reopened :block target-id)))
               (multiple-value-bind (restored present-p)
                   (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
                    reopened)
                 (is present-p)
                 (is (hash32=
                      (block-hash target)
                      (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-hash
                       restored))))))
        (ignore-errors (delete-file path))))))

(deftest node-store-snap-skeleton-progress-rejects-codec-and-target-drift
  (:layer :integration :module :persistence)
  (multiple-value-bind
      (store genesis anchor target transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore store transaction recipient))
    (let* ((database (make-memory-key-value-database))
           (chain-id 1)
           (authority-id (peer-sync-progress-test-authority-id))
           (progress
             (snap-skeleton-test-progress
              authority-id chain-id (block-hash genesis) anchor target)))
      (peer-sync-progress-test-install-metadata
       database chain-id (block-hash genesis) authority-id)
      (let ((batch (make-kv-write-batch)))
        (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
         database batch progress)
        (kv-apply-batch database batch))
      (let ((drifted
              (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
               :authority-id authority-id :chain-id chain-id
               :genesis-hash (block-hash genesis)
               :target-number (block-header-number (block-header target))
               :target-hash (make-hash32 (make-byte-vector 32 :initial-element 9))
               :anchor-number (block-header-number (block-header anchor))
               :anchor-hash (block-hash anchor)
               :pivot-number (block-header-number (block-header target))
               :pivot-hash (block-hash target)
               :last-number (block-header-number (block-header target))
               :last-hash (block-hash target))))
        (signals block-validation-error
          (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
           database (make-kv-write-batch) drifted)))
      (kv-put-chain-record
       database :metadata "snap-skeleton"
       (rlp-encode (make-rlp-list 99)))
      (signals block-validation-error
        (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
         database)))))
