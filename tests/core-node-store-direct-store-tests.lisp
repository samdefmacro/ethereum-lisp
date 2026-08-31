(in-package #:ethereum-lisp.test)

(defclass direct-store-test-database (memory-key-value-database)
  ((get-count :initform 0 :accessor direct-store-test-database-get-count)
   (last-operations
    :initform nil
    :accessor direct-store-test-database-last-operations)
   (applied-operation-batches
    :initform nil
    :accessor direct-store-test-database-applied-operation-batches)
   (forbid-iteration-p
    :initform nil
    :accessor direct-store-test-database-forbid-iteration-p)))

(defclass direct-store-failing-test-database (direct-store-test-database)
  ((fail-next-apply-p
    :initform nil
    :accessor direct-store-failing-test-database-fail-next-apply-p)
   (apply-attempts
    :initform 0
    :accessor direct-store-failing-test-database-apply-attempts)))

(defmethod kv-apply-batch :around
    ((database direct-store-test-database) (batch kv-write-batch))
  (let ((operations
          (copy-list
           (ethereum-lisp.database::kv-write-batch-operations batch))))
    (setf (direct-store-test-database-last-operations database) operations)
    (prog1 (call-next-method)
      ;; Record only successfully applied batches.  The failing subclass still
      ;; leaves LAST-OPERATIONS as a crash-attempt witness without counting an
      ;; atomic commit that did not happen.
      (push operations
            (direct-store-test-database-applied-operation-batches database)))))

(defmethod kv-apply-batch :around
    ((database direct-store-failing-test-database) (batch kv-write-batch))
  (incf (direct-store-failing-test-database-apply-attempts database))
  (if (direct-store-failing-test-database-fail-next-apply-p database)
      (progn
        (setf (direct-store-test-database-last-operations database)
              (copy-list
               (ethereum-lisp.database::kv-write-batch-operations batch))
              (direct-store-failing-test-database-fail-next-apply-p database)
              nil)
        (error "Injected direct-store batch crash"))
      (call-next-method)))

(defmethod kv-get :around
    ((database direct-store-test-database) key &optional default)
  (declare (ignore key default))
  (incf (direct-store-test-database-get-count database))
  (call-next-method))

(defmethod kv-iterator :around
    ((database direct-store-test-database) &key start end reverse-p)
  (declare (ignore start end reverse-p))
  (when (direct-store-test-database-forbid-iteration-p database)
    (error "Direct store attempted a database range scan"))
  (call-next-method))

(defun direct-store-test-reset-applied-batches (database)
  (setf (direct-store-test-database-last-operations database) nil
        (direct-store-test-database-applied-operation-batches database) nil))

(defun direct-store-test-operation-kind-p (operation kind)
  (let ((key (second operation)))
    (and (member (first operation) '(:put :delete))
         (plusp (length key))
         (= (aref key 0)
            (ethereum-lisp.database::kv-chain-record-kind-prefix kind)))))

(defun direct-store-test-chain (count)
  (let ((store (make-engine-payload-memory-store))
        (blocks nil)
        (parent-hash (zero-hash32))
        (state (make-state-db)))
    (dotimes (number count)
      (let ((block
              (make-block
               :header
               (make-block-header
                :number number
                :parent-hash parent-hash
                :state-root (state-db-root state)
                :timestamp number
                :gas-limit 30000000))))
        (chain-store-put-block store block :state-available-p t)
        (commit-state-db-to-chain-store store (block-hash block) state)
        (push block blocks)
        (setf parent-hash (block-hash block))))
    (let ((ordered (nreverse blocks)))
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash (car (last ordered)))
        :safe-block-hash (block-hash (first ordered))
        :finalized-block-hash (block-hash (first ordered))))
      (values store ordered))))

(deftest database-chain-store-construction-does-not-hydrate-history
  (multiple-value-bind (source blocks) (direct-store-test-chain 64)
    (let ((database (make-memory-key-value-database)))
      (node-store-export-to-kv source database)
      (let* ((direct (make-database-engine-payload-store database))
             (chain
               (ethereum-lisp.chain-store.state:chain-store-component direct))
             (initial-cache-size
               (hash-table-count
                (ethereum-lisp.chain-store.state:memory-chain-store-blocks
                 chain))))
        (is (database-engine-payload-store-p direct))
        ;; Construction point-reads head/safe/finalized. Safe and finalized
        ;; are the same genesis block, so history remains overwhelmingly on
        ;; disk rather than being imported into the overlay.
        (is (<= initial-cache-size 2))
        (is (= 63 (chain-store-head-number direct)))
        (let ((middle (chain-store-block-by-number direct 32)))
          (is middle)
          (when middle
            (is (ethereum-lisp.types:hash32=
                 (block-hash middle)
                 (block-hash (nth 32 blocks)))))
          (is (<=
               (hash-table-count
                (ethereum-lisp.chain-store.state:memory-chain-store-blocks
                 chain))
               (1+ initial-cache-size))))))))

(deftest database-chain-store-refuses-an-unknown-schema-before-reading
  (let ((database (make-memory-key-value-database)))
    (kv-put-chain-schema-version database (1+ +kv-chain-schema-version+))
    (signals block-validation-error
      (make-database-engine-payload-store database))))

(deftest database-chain-store-refuses-an-unmigrated-schema
  (let ((database (make-memory-key-value-database)))
    (kv-put-chain-schema-version database 3)
    (signals block-validation-error
      (make-database-engine-payload-store database))))

(deftest database-chain-store-classifies-corrupt-checkpoint-as-storage
  (multiple-value-bind (source blocks) (direct-store-test-chain 2)
    (declare (ignore blocks))
    (let ((database (make-memory-key-value-database)))
      (node-store-export-to-kv source database)
      (kv-put-chain-checkpoint database :safe #(1))
      (signals ethereum-lisp.validation:storage-error
        (make-database-engine-payload-store database)))))

(deftest database-chain-store-opens-and-reads-state-without-iteration
  (let* ((source (make-engine-payload-memory-store))
         (database (make-instance 'direct-store-test-database))
         (state (make-state-db))
         (target (state-diff-test-address 73))
         (slot (state-diff-test-slot 9))
         (code #(#x60 #x09 #x60 #x00 #x55)))
    ;; Enough accounts to distinguish one secure-trie path from hydration.
    (dotimes (index 128)
      (let ((address (state-diff-test-address (1+ index))))
        (state-db-set-account
         state address
         (make-state-account :nonce index :balance (+ 1000 index)))))
    (state-db-set-code state target code)
    (state-db-set-storage state target slot 987654)
    (let* ((root (state-db-root state))
           (block
             (make-block
              :header
              (make-block-header
               :number 0
               :parent-hash (zero-hash32)
               :state-root root
               :timestamp 0
               :gas-limit 30000000))))
      (chain-store-put-block source block :state-available-p t)
      (commit-state-db-to-chain-store source (block-hash block) state)
      (chain-store-update-forkchoice-checkpoints
       source
       (make-forkchoice-state
        :head-block-hash (block-hash block)
        :safe-block-hash (block-hash block)
        :finalized-block-hash (block-hash block)))
      (node-store-export-to-kv source database)
      (is (plusp (length (kv-chain-record-entries database :trie-node))))
      (multiple-value-bind (persisted-root present-p)
          (kv-get-chain-record
           database :state-history (hash32-bytes (block-hash block)))
        (is present-p)
        (is (bytes= persisted-root (hash32-bytes root))))
      (setf (direct-store-test-database-get-count database) 0
            (direct-store-test-database-forbid-iteration-p database) t)
      (let ((direct (make-database-engine-payload-store database)))
        ;; Generic chain-store reads are used by txpool admission/revalidation
        ;; and public RPC. They must resolve the secure trie too, rather than
        ;; silently falling back to empty legacy flat tables after restart.
        (multiple-value-bind (balance present-p)
            (chain-store-account-balance direct (block-hash block) target)
          (is present-p)
          (is (= 1072 balance)))
        (let ((reads-after-first-account
                (direct-store-test-database-get-count database)))
          (multiple-value-bind (balance present-p)
              (chain-store-account-balance direct (block-hash block) target)
            (is present-p)
            (is (= 1072 balance)))
          ;; A block hash identifies immutable state.  Repeated public RPC and
          ;; txpool reads must reuse its decoded account instead of traversing
          ;; the persisted secure trie again.
          (is (= reads-after-first-account
                 (direct-store-test-database-get-count database))))
        (multiple-value-bind (nonce present-p)
            (chain-store-account-nonce direct (block-hash block) target)
          (is present-p)
          (is (= 72 nonce)))
        (is (bytes=
             code
             (chain-store-account-code direct (block-hash block) target)))
        (multiple-value-bind (value present-p)
            (chain-store-account-storage
             direct (block-hash block) target slot)
          (is present-p)
          (is (= 987654 value)))
        (let ((opened (chain-store-state-db direct (block-hash block))))
          (is opened)
          (is (= 1072
                 (state-account-balance
                  (state-db-get-account opened target))))
          (is (bytes= code (state-db-get-code opened target)))
          (is (= 987654 (state-db-get-storage opened target slot)))
          ;; The full-rebuild oracle cannot enumerate secure address hashes.
          ;; Enabling it must still terminate and preserve the persisted root
          ;; rather than recursively asking the direct trie to rebuild itself.
          (let ((ethereum-lisp.state::*verify-incremental-root* t))
            (is (ethereum-lisp.types:hash32=
                 root (state-db-root opened)))))
        ;; Construction plus the generic reads and one lazy state view remain
        ;; bounded point reads; the iterator method above fails immediately if
        ;; startup or access tries to hydrate history.
        (is (< (direct-store-test-database-get-count database) 80))))))

(deftest database-chain-store-account-cache-keeps-two-bounded-generations
  (let* ((database (make-memory-key-value-database))
         (store
           (ethereum-lisp.node-store.persistence::make-empty-database-chain-store
            database))
         (limit
           ethereum-lisp.node-store.persistence::+node-store-direct-account-cache-generation-limit+))
    (dotimes (index (+ (* 2 limit) 3))
      (ethereum-lisp.node-store.persistence::node-store-direct-account-cache-put
       store
       (write-to-string index)
       nil))
    (let ((current
            (ethereum-lisp.node-store.persistence::database-chain-store-account-cache
             store))
          (previous
            (ethereum-lisp.node-store.persistence::database-chain-store-previous-account-cache
             store)))
      (is (<= (hash-table-count current) limit))
      (is (<= (hash-table-count previous) limit))
      (is (<= (+ (hash-table-count current)
                 (hash-table-count previous))
              (* 2 limit))))))

(deftest direct-account-point-reads-see-pending-and-persisted-tries
  (let* ((bootstrap (make-engine-payload-memory-store))
         (database (make-instance 'direct-store-test-database))
         (genesis-state (make-state-db))
         (target (state-diff-test-address 151))
         (slot (state-diff-test-slot 23))
         (code #(#x60 #x17 #x60 #x00 #x55))
         (legacy-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to (state-diff-test-address 152)
             :value 3)
            3
            1))
         (surviving-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 21000
             :to (state-diff-test-address 154)
             :value 4)
            5
            1))
         (surviving-sender
           (transaction-sender
            surviving-transaction :expected-chain-id 1))
         (commitment (make-byte-vector 48 :initial-element #x31))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (blob-transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 0
             :max-priority-fee-per-gas 2
             :max-fee-per-gas 20
             :gas-limit 21000
             :to (state-diff-test-address 153)
             :max-fee-per-blob-gas 20
             :blob-versioned-hashes (list versioned-hash))
            4))
         (sidecar
           (make-blob-sidecar
            :blobs (list (make-byte-vector +blob-byte-size+))
            :commitments (list commitment)
            :proofs (list (make-byte-vector 48 :initial-element #x41)))))
    (let ((genesis
            (make-block
             :header
             (make-block-header
              :number 0
              :parent-hash (zero-hash32)
              :state-root (state-db-root genesis-state)
              :timestamp 0
              :gas-limit 30000000))))
      (chain-store-put-block bootstrap genesis :state-available-p t)
      (commit-state-db-to-chain-store
       bootstrap (block-hash genesis) genesis-state)
      (chain-store-update-forkchoice-checkpoints
       bootstrap
       (make-forkchoice-state
        :head-block-hash (block-hash genesis)
        :safe-block-hash (block-hash genesis)
        :finalized-block-hash (block-hash genesis)))
      ;; Persist one pooled transaction so the later canonical block produces
      ;; a real :TXPOOL deletion in its atomic forkchoice batch.
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       bootstrap legacy-transaction)
      (node-store-export-to-kv bootstrap database)
      (let* ((direct (make-database-engine-payload-store database))
             (child-state
               (chain-store-state-db direct (block-hash genesis))))
        (node-store-import-txpool-records-from-kv
         direct database :expected-chain-id 1)
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         direct)
        (state-db-set-account
         child-state target (make-state-account :nonce 7 :balance 777))
        (state-db-set-code child-state target code)
        (state-db-set-storage child-state target slot 123456)
        (state-db-set-account
         child-state surviving-sender
         (make-state-account :nonce 0 :balance 1000000))
        (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
         direct surviving-transaction)
        (let* ((child
                 (make-block
                  :header
                  (make-block-header
                   :number 1
                   :parent-hash (block-hash genesis)
                   :state-root (state-db-root child-state)
                   :timestamp 1
                   :gas-limit 30000000)
                  :transactions
                  (list legacy-transaction blob-transaction)
                  :receipts
                  (list
                   (make-receipt :status 1 :cumulative-gas-used 21000)
                   (make-receipt :status 1 :cumulative-gas-used 42000))))
               (child-hash (block-hash child))
               (code-hash (keccak-256-hash code)))
          (labels ((assert-point-reads (store)
                     (multiple-value-bind (balance present-p)
                         (chain-store-account-balance store child-hash target)
                       (is present-p)
                       (is (= 777 balance)))
                     (multiple-value-bind (nonce present-p)
                         (chain-store-account-nonce store child-hash target)
                       (is present-p)
                       (is (= 7 nonce)))
                     (is (bytes=
                          code
                          (chain-store-account-code
                           store child-hash target)))
                     (multiple-value-bind (value present-p)
                         (chain-store-account-storage
                          store child-hash target slot)
                       (is present-p)
                       (is (= 123456 value)))))
            (engine-payload-store-put-block
             direct child :state-available-p t :canonicalize-p nil)
            (commit-state-db-to-chain-store direct child-hash child-state)
            (let ((*kzg-blob-proof-verifier*
                    (lambda (blob actual-commitment proof)
                      (declare (ignore blob actual-commitment proof))
                      t)))
              (engine-payload-store-put-blob-sidecar direct sidecar))
            ;; Neither the state root nor the new code body is durable yet.
            ;; Successful reads therefore prove the transaction-local dirty
            ;; trie/code overlay is the source, not an accidental DB fallback.
            (is (not (nth-value
                      1
                      (kv-get-chain-record
                       database :state-history (hash32-bytes child-hash)))))
            (is (not (nth-value
                      1
                      (kv-get-chain-record
                       database :code (hash32-bytes code-hash)))))
            (assert-point-reads direct)
            (chain-store-update-forkchoice-checkpoints
             direct
             (make-forkchoice-state
              :head-block-hash child-hash
              :safe-block-hash (block-hash genesis)
              :finalized-block-hash (block-hash genesis)))
            (multiple-value-bind (head transition)
                (chain-store-set-canonical-head direct child-hash)
              (declare (ignore head))
              (direct-store-test-reset-applied-batches database)
              (node-store-export-forkchoice-to-kv
               direct transition database))
            ;; All durable effects of the canonical block crossed the database
            ;; in exactly one successful batch.  This is an integrated witness,
            ;; not a collection of per-namespace batch tests.
            (let ((batches
                    (direct-store-test-database-applied-operation-batches
                     database)))
              (is (= 1 (length batches)))
              (when (= 1 (length batches))
                (let ((operations (first batches)))
                  (dolist (kind
                            '(:block :header :receipt
                              :state-history :ordered-state-history
                              :trie-node :code
                              :canonical-hash :checkpoint
                              :transaction-location :txpool :blob-sidecar))
                    (is (find-if
                         (lambda (operation)
                           (direct-store-test-operation-kind-p
                            operation kind))
                         operations)))
                  (is (find-if
                       (lambda (operation)
                         (and (eq :delete (first operation))
                              (direct-store-test-operation-kind-p
                               operation :txpool)))
                       operations))
                  (is (find-if
                       (lambda (operation)
                         (and (eq :put (first operation))
                              (direct-store-test-operation-kind-p
                               operation :txpool)))
                       operations)))))
            (is (nth-value
                 1
                 (kv-get-chain-record
                  database :state-history (hash32-bytes child-hash))))
            (is (nth-value
                 1
                 (kv-get-chain-record
                  database :code (hash32-bytes code-hash))))
            (is (not (nth-value
                      1
                      (kv-get-chain-record
                       database
                       :txpool
                       (hash32-bytes
                        (transaction-hash legacy-transaction))))))
            (is (nth-value
                 1
                 (kv-get-chain-record
                  database
                  :txpool
                  (hash32-bytes
                   (transaction-hash surviving-transaction)))))
            (assert-point-reads
             (make-database-engine-payload-store database))))))))

(deftest chain-schema-v4-migrates-flat-history-to-direct-tries-resumably
  (let* ((source (make-engine-payload-memory-store))
         (database (make-instance 'direct-store-test-database))
         (target (state-diff-test-address 41))
         (parent-state (make-state-db)))
    (state-db-set-account
     parent-state target (make-state-account :nonce 1 :balance 100))
    (let* ((parent
             (make-block
              :header
              (make-block-header
               :number 0
               :parent-hash (zero-hash32)
               :state-root (state-db-root parent-state)
               :timestamp 0
               :gas-limit 30000000)))
           (child-state (state-db-copy parent-state)))
      (chain-store-put-block source parent :state-available-p t)
      (commit-state-db-to-chain-store
       source (block-hash parent) parent-state)
      (state-db-set-account
       child-state target (make-state-account :nonce 2 :balance 222))
      (let ((child
              (make-block
               :header
               (make-block-header
                :number 1
                :parent-hash (block-hash parent)
                :state-root (state-db-root child-state)
                :timestamp 1
                :gas-limit 30000000))))
        (chain-store-put-block source child :state-available-p t)
        (commit-state-db-to-chain-store
         source (block-hash child) child-state)
        (chain-store-update-forkchoice-checkpoints
         source
         (make-forkchoice-state
          :head-block-hash (block-hash child)
          :safe-block-hash (block-hash parent)
          :finalized-block-hash (block-hash parent)))
        (node-store-export-to-kv source database)
        ;; Recreate the actual v3 representation: content-addressed code and
        ;; ordered blocks exist, but no secure trie nodes/history do.
        (dolist (kind '(:state-history :ordered-state-history :trie-node))
          (dolist (entry (kv-chain-record-entries database kind))
            (kv-delete-chain-record database kind (car entry))))
        (kv-put-chain-schema-version database 3)
        (let ((batch-count 0))
          (multiple-value-bind (version migrated-p)
              (node-store-migrate-chain-schema
               database
               :batch-size 1
               :after-batch
               (lambda (progress)
                 (declare (ignore progress))
                 (incf batch-count)))
            (is migrated-p)
            (is (= +kv-chain-schema-version+ version))
            ;; Start marker + two ordered states + exhausted-step cursor +
            ;; final marker. This positive count proves the trie step ran.
            (is (>= batch-count 5))))
        (dolist (block (list parent child))
          (multiple-value-bind (root present-p)
              (kv-get-chain-record
               database :state-history (hash32-bytes (block-hash block)))
            (is present-p)
            (is (bytes= root
                        (hash32-bytes
                         (block-header-state-root (block-header block)))))
            (is (nth-value
                 1
                 (kv-get-chain-record
                  database
                  :ordered-state-history
                  (ethereum-lisp.database:kv-chain-height-hash-identifier
                   (block-header-number (block-header block))
                   (hash32-bytes (block-hash block))))))))
        (setf (direct-store-test-database-forbid-iteration-p database) t)
        (let* ((direct (make-database-engine-payload-store database))
               (state (chain-store-state-db direct (block-hash child))))
          (is (= 222
                 (state-account-balance
                  (state-db-get-account state target)))))))))

(defun direct-store-test-persist-child
    (store database parent number target balance safe finalized)
  (let ((state (chain-store-state-db store (block-hash parent))))
    (state-db-set-account
     state target (make-state-account :nonce number :balance balance))
    (let ((child
            (make-block
             :header
             (make-block-header
              :number number
              :parent-hash (block-hash parent)
              :state-root (state-db-root state)
              :timestamp number
              :gas-limit 30000000))))
      (engine-payload-store-put-block
       store child :state-available-p t :canonicalize-p nil)
      (commit-state-db-to-chain-store store (block-hash child) state)
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash child)
        :safe-block-hash (block-hash safe)
        :finalized-block-hash (block-hash finalized)))
      (multiple-value-bind (head transition)
          (chain-store-set-canonical-head store (block-hash child))
        (declare (ignore head))
        (node-store-export-forkchoice-to-kv store transition database))
      child)))

(deftest direct-state-retention-keeps-finality-anchors-in-the-live-batch
  (let* ((database (make-instance 'direct-store-test-database))
         (bootstrap (make-engine-payload-memory-store))
         (target (state-diff-test-address 57))
         (state (make-state-db)))
    (state-db-set-account
     state target (make-state-account :nonce 0 :balance 10))
    (let ((genesis
            (make-block
             :header
             (make-block-header
              :number 0
              :parent-hash (zero-hash32)
              :state-root (state-db-root state)
              :timestamp 0
              :gas-limit 30000000))))
      (chain-store-put-block bootstrap genesis :state-available-p t)
      (commit-state-db-to-chain-store bootstrap (block-hash genesis) state)
      (chain-store-update-forkchoice-checkpoints
       bootstrap
       (make-forkchoice-state
        :head-block-hash (block-hash genesis)
        :safe-block-hash (block-hash genesis)
        :finalized-block-hash (block-hash genesis)))
      (node-store-export-to-kv bootstrap database)
      (let* ((direct (make-database-engine-payload-store database))
             (chain
               (ethereum-lisp.chain-store.state:chain-store-component direct))
             (block-1 nil)
             (block-2 nil)
             (block-3 nil)
             (abandoned-candidate nil))
        (setf (ethereum-lisp.chain-store.state:memory-chain-store-state-retention-depth
               chain)
              2)
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         direct)
        (let ((candidate-state
                (chain-store-state-db direct (block-hash genesis))))
          (state-db-set-account
           candidate-state target
           (make-state-account :nonce 1 :balance 999))
          (setf abandoned-candidate
                (make-block
                 :header
                 (make-block-header
                  :number 1
                  :parent-hash (block-hash genesis)
                  :state-root (state-db-root candidate-state)
                  :timestamp 101
                  :gas-limit 30000000)))
          (engine-payload-store-put-block
           direct abandoned-candidate
           :state-available-p t :canonicalize-p nil)
          (commit-state-db-to-chain-store
           direct (block-hash abandoned-candidate) candidate-state)
          (node-store-export-payload-candidate-to-kv
           direct abandoned-candidate database))
        (is (nth-value
             1
             (kv-get-chain-record
              database :ordered-state-history
              (ethereum-lisp.database:kv-chain-height-hash-identifier
               1 (hash32-bytes (block-hash abandoned-candidate))))))
        (setf block-1
              (direct-store-test-persist-child
               direct database genesis 1 target 11 genesis genesis)
              block-2
              (direct-store-test-persist-child
               direct database block-1 2 target 12 genesis genesis)
              block-3
              (direct-store-test-persist-child
               direct database block-2 3 target 13 genesis genesis))
        ;; At head 3 with depth 2, height 1 has expired while genesis remains
        ;; protected as both safe and finalized.
        (is (not (nth-value
                  1
                  (kv-get-chain-record
                   database :state-history
                   (hash32-bytes (block-hash block-1))))))
        (is (not (nth-value
                  1
                  (kv-get-chain-record
                   database :ordered-state-history
                   (ethereum-lisp.database:kv-chain-height-hash-identifier
                    1 (hash32-bytes (block-hash block-1)))))))
        (is (not (nth-value
                  1
                  (kv-get-chain-record
                   database :state-history
                   (hash32-bytes (block-hash abandoned-candidate))))))
        (is (not (nth-value
                  1
                  (kv-get-chain-record
                   database :ordered-state-history
                   (ethereum-lisp.database:kv-chain-height-hash-identifier
                    1
                    (hash32-bytes (block-hash abandoned-candidate)))))))
        (is (nth-value
             1
             (kv-get-chain-record
              database :state-history
              (hash32-bytes (block-hash genesis)))))
        (let ((block-4
                (direct-store-test-persist-child
                 direct database block-3 4 target 14 block-2 block-2)))
          (declare (ignore block-4))
          ;; Moving finality to height 2 releases the old genesis anchor; the
          ;; new finalized state survives although it is at the boundary.
          (is (not (nth-value
                    1
                    (kv-get-chain-record
                     database :state-history
                     (hash32-bytes (block-hash genesis))))))
          (is (not (nth-value
                    1
                    (kv-get-chain-record
                     database :ordered-state-history
                     (ethereum-lisp.database:kv-chain-height-hash-identifier
                      0 (hash32-bytes (block-hash genesis)))))))
          (is (nth-value
               1
               (kv-get-chain-record
                database :state-history
                (hash32-bytes (block-hash block-2))))))))))

(defun direct-store-test-trie-put-count (operations)
  (count-if
   (lambda (operation)
     (and (eq (first operation) :put)
          (let ((key (second operation)))
            (and (plusp (length key))
                 (= (aref key 0)
                    (ethereum-lisp.database::kv-chain-record-kind-prefix
                     :trie-node))))))
   operations))

(deftest txpool-snapshot-commits-and-restores-blob-sidecars-in-one-batch
  (let* ((source (make-engine-payload-memory-store))
         (database (make-instance 'direct-store-test-database))
         (commitment (make-byte-vector 48 :initial-element #x31))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 0
             :max-priority-fee-per-gas 2
             :max-fee-per-gas 20
             :gas-limit 21000
             :to (zero-address)
             :max-fee-per-blob-gas 20
             :blob-versioned-hashes (list versioned-hash))
            1))
         (sidecar
           (make-blob-sidecar
            :blobs (list (make-byte-vector +blob-byte-size+))
            :commitments (list commitment)
            :proofs (list (make-byte-vector 48 :initial-element #x41)))))
    (ethereum-lisp.txpool:engine-payload-store-put-blob-transaction
     source transaction)
    (let ((*kzg-blob-proof-verifier*
            (lambda (blob actual-commitment proof)
              (declare (ignore blob actual-commitment proof))
              t)))
      (engine-payload-store-put-blob-sidecar source sidecar)
      (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
       source database)
      (let ((operations
              (direct-store-test-database-last-operations database)))
        (is (find-if
             (lambda (operation)
               (direct-store-test-operation-kind-p operation :txpool))
             operations))
        (is (find-if
             (lambda (operation)
               (direct-store-test-operation-kind-p operation :blob-sidecar))
             operations)))
      (let ((restored (make-engine-payload-memory-store)))
        (node-store-import-txpool-records-from-kv restored database)
        (node-store-import-txpool-blob-sidecars-from-kv restored database)
        (let ((blob-and-proofs
                (engine-payload-store-blob-and-proofs-v1
                 restored versioned-hash)))
          (is blob-and-proofs)
          (when blob-and-proofs
            (is (bytes=
                 commitment
                 (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                  blob-and-proofs)))))))))

(deftest txpool-snapshot-preserves-shared-canonical-sidecars
  (let* ((source (make-engine-payload-memory-store))
         (database (make-instance 'direct-store-test-database))
         (sidecar-identifier
           (make-byte-vector 32 :initial-element #x51))
         (sidecar-record #(#xc0))
         (stale-transaction-identifier
           (make-byte-vector 32 :initial-element #x61)))
    ;; The sidecar namespace is shared by pooled and canonical transactions.
    ;; Seed one canonical witness and one stale txpool record, then prove the
    ;; bounded snapshot removes only what it owns.
    (kv-put-chain-record
     database :blob-sidecar sidecar-identifier sidecar-record)
    (kv-put-chain-record
     database :txpool stale-transaction-identifier #(#xc0))
    (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
     source database)
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :blob-sidecar sidecar-identifier)
      (is present-p)
      (when present-p
        (is (bytes= sidecar-record record))))
    (is (not (nth-value
              1
              (kv-get-chain-record
               database :txpool stale-transaction-identifier))))))

(deftest direct-state-batch-crash-retries-dirty-paths-atomically
  (let* ((database (make-instance 'direct-store-failing-test-database))
         (bootstrap (make-engine-payload-memory-store))
         (parent-state (make-state-db))
         (target (state-diff-test-address 117)))
    (dotimes (index 192)
      (state-db-set-account
       parent-state
       (state-diff-test-address (1+ index))
       (make-state-account :nonce index :balance (+ 10000 index))))
    (let* ((parent
             (make-block
              :header
              (make-block-header
               :number 0
               :parent-hash (zero-hash32)
               :state-root (state-db-root parent-state)
               :timestamp 0
               :gas-limit 30000000))))
      (chain-store-put-block bootstrap parent :state-available-p t)
      (commit-state-db-to-chain-store
       bootstrap (block-hash parent) parent-state)
      (chain-store-update-forkchoice-checkpoints
       bootstrap
       (make-forkchoice-state
        :head-block-hash (block-hash parent)
        :safe-block-hash (block-hash parent)
        :finalized-block-hash (block-hash parent)))
      (node-store-export-to-kv bootstrap database)
      (let* ((direct (make-database-engine-payload-store database))
             (child-state
               (chain-store-state-db direct (block-hash parent))))
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         direct)
        (state-db-set-account
         child-state target
         (make-state-account :nonce 116 :balance 424242))
        (let ((child
                (make-block
                 :header
                 (make-block-header
                  :number 1
                  :parent-hash (block-hash parent)
                  :state-root (state-db-root child-state)
                  :timestamp 1
                  :gas-limit 30000000))))
          (engine-payload-store-put-block
           direct child :state-available-p t :canonicalize-p nil)
          (commit-state-db-to-chain-store
           direct (block-hash child) child-state)
          (multiple-value-bind (head transition)
              (chain-store-set-canonical-head direct (block-hash child))
            (declare (ignore head))
            (setf (direct-store-failing-test-database-fail-next-apply-p
                   database)
                  t)
            (signals error
              (node-store-export-forkchoice-to-kv
               direct transition database))
            (is (not (nth-value
                      1
                      (kv-get-chain-record
                       database :state-history
                       (hash32-bytes (block-hash child))))))
            ;; The failed batch contains only one changed secure-trie path,
            ;; independent of the 192 accounts retained behind it.
            (is (< (direct-store-test-trie-put-count
                    (direct-store-test-database-last-operations database))
                   32))
            (node-store-export-forkchoice-to-kv direct transition database)
            (is (nth-value
                 1
                 (kv-get-chain-record
                  database :state-history (hash32-bytes (block-hash child)))))
            (let* ((restarted
                     (make-database-engine-payload-store database))
                   (state
                     (chain-store-state-db restarted (block-hash child))))
              (is (= 424242
                     (state-account-balance
                      (state-db-get-account state target)))))))))))
