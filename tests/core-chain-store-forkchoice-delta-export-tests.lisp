(in-package #:ethereum-lisp.test)

(defclass forkchoice-delta-test-database (memory-key-value-database)
  ((applied-operation-batches
     :initform nil
     :accessor forkchoice-delta-test-database-applied-operation-batches)
   (buffered-apply-attempts
     :initform 0
     :accessor forkchoice-delta-test-database-buffered-apply-attempts)
   (forbid-iteration-p
     :initform nil
     :accessor forkchoice-delta-test-database-forbid-iteration-p)))

(defclass forkchoice-delta-failing-test-database
    (forkchoice-delta-test-database)
  ((fail-next-apply-p
     :initform nil
     :accessor forkchoice-delta-failing-test-database-fail-next-apply-p)
   (apply-attempts
     :initform 0
     :accessor forkchoice-delta-failing-test-database-apply-attempts)))

(defmethod kv-apply-batch :around
    ((database forkchoice-delta-failing-test-database)
     (batch kv-write-batch))
  (incf (forkchoice-delta-failing-test-database-apply-attempts database))
  (if (forkchoice-delta-failing-test-database-fail-next-apply-p database)
      (progn
        (setf (forkchoice-delta-failing-test-database-fail-next-apply-p
               database)
              nil)
        (error "Simulated forkchoice delta batch failure"))
      (call-next-method)))

(defmethod kv-apply-batch :around
    ((database forkchoice-delta-test-database) (batch kv-write-batch))
  (push
   (loop for operation in
           (reverse
            (ethereum-lisp.database::kv-write-batch-operations batch))
         collect
         (loop for field in operation
               collect (if (vectorp field) (copy-seq field) field)))
   (forkchoice-delta-test-database-applied-operation-batches database))
  (call-next-method))

(defmethod kv-apply-batch-buffered :around
    ((database forkchoice-delta-test-database) (batch kv-write-batch))
  (incf (forkchoice-delta-test-database-buffered-apply-attempts database))
  (call-next-method))

(defmethod kv-buffered-batch-supported-p
    ((database forkchoice-delta-test-database))
  (declare (ignore database))
  t)

(defmethod kv-iterator :around
    ((database forkchoice-delta-test-database)
     &key start end reverse-p)
  (declare (ignore start end reverse-p))
  (when (forkchoice-delta-test-database-forbid-iteration-p database)
    (error "Forkchoice delta export must not iterate the database"))
  (call-next-method))

(defun make-forkchoice-delta-test-database ()
  (make-instance 'forkchoice-delta-test-database))

(defun forkchoice-delta-test-reset-operations (database)
  (setf (forkchoice-delta-test-database-applied-operation-batches database)
        nil
        (forkchoice-delta-test-database-buffered-apply-attempts database)
        0))

(defun forkchoice-delta-test-call-with-function-overrides (bindings thunk)
  "Call THUNK with global function BINDINGS, restoring every definition."
  (let ((originals
          (mapcar (lambda (binding)
                    (cons (car binding) (fdefinition (car binding))))
                  bindings)))
    (unwind-protect
         (progn
           (dolist (binding bindings)
             (setf (fdefinition (car binding)) (cdr binding)))
           (funcall thunk))
      (dolist (binding originals)
        (setf (fdefinition (car binding)) (cdr binding))))))

(defun forkchoice-delta-test-operation-signatures (database)
  (sort
   (loop for batch in
           (reverse
            (forkchoice-delta-test-database-applied-operation-batches
             database))
         append
         (loop for operation in batch
               collect
               (format nil "~(~A~):~A"
                       (first operation)
                       (bytes-to-hex (second operation)))))
   #'string<))

(defun forkchoice-delta-test-expected-operation (operation kind identifier)
  (format nil "~(~A~):~A"
          operation
          (bytes-to-hex (kv-chain-record-key kind identifier))))

(defun forkchoice-delta-test-export-without-iteration
    (store transition database)
  (unwind-protect
       (progn
         (setf (forkchoice-delta-test-database-forbid-iteration-p database)
               t)
         (ethereum-lisp.node-store.persistence:node-store-export-forkchoice-to-kv
          store transition database))
    (setf (forkchoice-delta-test-database-forbid-iteration-p database)
          nil)))

(defun forkchoice-delta-test-transaction ()
  (fixture-sign-legacy-transaction
   (make-legacy-transaction
    :nonce 0
    :gas-price 2
    :gas-limit 21000
    :to
    (address-from-hex
     "0x00000000000000000000000000000000000000aa")
    :value 3)
   1
   1))

(defun forkchoice-delta-test-unrelated-transaction ()
  (fixture-sign-legacy-transaction
   (make-legacy-transaction
    :nonce 0
    :gas-price 3
    :gas-limit 21000
    :to
    (address-from-hex
     "0x00000000000000000000000000000000000000bb")
    :value 4)
   2
   1))

(defun forkchoice-delta-test-block
    (parent number marker &key transaction)
  (make-block
   :header
   (make-block-header
    :number number
    :parent-hash (if parent (block-hash parent) (zero-hash32))
    :timestamp number
    :gas-limit 30000000
    :extra-data (vector marker))
   :transactions (if transaction (list transaction) nil)
   :receipts
   (if transaction
       (list (make-receipt :status 1 :cumulative-gas-used 21000))
       nil)))

(defun forkchoice-delta-test-set-checkpoints
    (store head safe finalized)
  (chain-store-update-forkchoice-checkpoints
   store
   (make-forkchoice-state
    :head-block-hash (block-hash head)
    :safe-block-hash (block-hash safe)
    :finalized-block-hash (block-hash finalized))))

(defun forkchoice-delta-test-select-head
    (store config head safe finalized)
  (forkchoice-delta-test-set-checkpoints store head safe finalized)
  (nth-value
   1
   (chain-store-set-canonical-head
    store
    (block-hash head)
    :expected-chain-id (chain-config-chain-id config)
    :chain-config config)))

(defun forkchoice-delta-test-extension-fixture
    (&key (database (make-forkchoice-delta-test-database)))
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (transaction (forkchoice-delta-test-transaction))
         (unrelated-transaction
           (forkchoice-delta-test-unrelated-transaction))
         (unrelated-sender
           (transaction-sender unrelated-transaction :expected-chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (parent (forkchoice-delta-test-block genesis 1 1))
         (candidate
           (forkchoice-delta-test-block parent 2 2
                                        :transaction transaction))
         (side (forkchoice-delta-test-block parent 2 99)))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store parent :state-available-p t)
    (engine-payload-store-put-block
     store candidate :state-available-p t :canonicalize-p nil)
    (engine-payload-store-put-block
     store side :state-available-p t :canonicalize-p nil)
    (chain-store-put-account-nonce
     store (block-hash candidate) unrelated-sender 0)
    (chain-store-put-account-balance
     store (block-hash candidate) unrelated-sender 1000000)
    (forkchoice-delta-test-set-checkpoints store parent genesis genesis)
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store transaction)
    (node-store-export-to-kv store database)
    (forkchoice-delta-test-reset-operations database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    ;; This admission occurs after the last database export and is not in the
    ;; selected block.  The transition must carry the node-store dirty hash so
    ;; the FCU batch also makes this pending transaction durable.
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store unrelated-transaction)
    (values store config database genesis parent candidate side transaction
            unrelated-transaction)))

(defun forkchoice-delta-test-delete-block-records (database block)
  (let ((identifier (hash32-bytes (block-hash block))))
    (dolist (kind '(:block :header :receipt :state))
      (kv-delete-chain-record database kind identifier))))

(defun forkchoice-delta-test-one-hash-p (hashes expected)
  (and (= 1 (length hashes))
       (ethereum-lisp.types:hash32= (first hashes) expected)))

(defun forkchoice-delta-test-hash-set-matches-p (hashes expected)
  (and (= (length hashes) (length expected))
       (every
        (lambda (expected-hash)
          (find expected-hash hashes :test #'ethereum-lisp.types:hash32=))
        expected)))

(defun forkchoice-delta-test-block-list-matches-p (blocks expected)
  (and (= (length blocks) (length expected))
       (loop for block in blocks
             for expected-block in expected
             always (ethereum-lisp.types:hash32=
                     (block-hash block)
                     (block-hash expected-block)))))

(deftest node-store-forkchoice-delta-extension-is-record-scoped-and-idempotent
  (multiple-value-bind
      (store config database genesis parent candidate side transaction
       unrelated-transaction)
      (forkchoice-delta-test-extension-fixture)
    (declare (ignore parent))
    (forkchoice-delta-test-delete-block-records database candidate)
    (is (forkchoice-delta-test-one-hash-p
         (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
          store)
         (transaction-hash unrelated-transaction)))
    (let* ((transition
             (forkchoice-delta-test-select-head
              store config candidate genesis genesis))
           (candidate-id (hash32-bytes (block-hash candidate)))
           (side-id (hash32-bytes (block-hash side)))
           (transaction-id (hash32-bytes (transaction-hash transaction)))
           (unrelated-transaction-id
             (hash32-bytes (transaction-hash unrelated-transaction)))
           (expected
             (sort
              (list
               (forkchoice-delta-test-expected-operation
                :put :block candidate-id)
               (forkchoice-delta-test-expected-operation
                :put :header candidate-id)
               (forkchoice-delta-test-expected-operation
                :put :receipt candidate-id)
               (forkchoice-delta-test-expected-operation
                :put :state candidate-id)
               (forkchoice-delta-test-expected-operation
                :put :canonical-hash 2)
               (forkchoice-delta-test-expected-operation
                :put :checkpoint "head")
               (forkchoice-delta-test-expected-operation
                :put :transaction-location transaction-id)
               (forkchoice-delta-test-expected-operation
                :delete :txpool transaction-id)
               (forkchoice-delta-test-expected-operation
                :put :txpool unrelated-transaction-id))
              #'string<)))
      (is (= 1
             (length
              (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
               transition))))
      (is (ethereum-lisp.types:hash32=
           (block-hash
            (first
             (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
              transition)))
           (block-hash candidate)))
      (is (null
           (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
            transition)))
      (is (forkchoice-delta-test-hash-set-matches-p
           (ethereum-lisp.canonical-chain:canonical-chain-transition-changed-txpool-hashes
            transition)
           (list (transaction-hash transaction)
                 (transaction-hash unrelated-transaction))))
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (= 1
             (length
              (forkchoice-delta-test-database-applied-operation-batches
               database))))
      (is (equal expected
                 (forkchoice-delta-test-operation-signatures database)))
      (is (null
           (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
            store)))
      (payload-candidate-export-assert-record
       database :block candidate-id (block-rlp candidate))
      (payload-candidate-export-assert-record
       database :header candidate-id
       (block-header-rlp (block-header candidate)))
      (payload-candidate-export-assert-record
       database :receipt candidate-id
       (payload-candidate-export-expected-receipt-record candidate))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :state candidate-id)
        (is present-p)
        (is (plusp (length value))))
      (payload-candidate-export-assert-record
       database :block side-id (block-rlp side))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :txpool transaction-id :missing)
        (is (eq :missing value))
        (is (not present-p)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :txpool unrelated-transaction-id)
        (is present-p)
        (is (plusp (length value))))
      (forkchoice-delta-test-reset-operations database)
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (null (forkchoice-delta-test-operation-signatures database)))
      (is (null
           (forkchoice-delta-test-database-applied-operation-batches
            database))))))

(deftest node-store-forkchoice-delta-noop-does-not-write-metadata-only-batch
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (database (make-forkchoice-delta-test-database))
         (authority-id (peer-sync-progress-test-authority-id))
         (metadata-1
           (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
            :role :database :generation 1 :chain-id 1
            :genesis-hash (block-hash genesis)
            :authority-id authority-id :base-chain-generation 1))
         (metadata-2
           (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
            :role :database :generation 2 :chain-id 1
            :genesis-hash (block-hash genesis)
            :authority-id authority-id :base-chain-generation 2)))
    (engine-payload-store-put-block
     store genesis :state-available-p t :canonicalize-p t)
    (forkchoice-delta-test-set-checkpoints
     store genesis genesis genesis)
    (node-store-export-to-kv
     store database :persistence-metadata metadata-1)
    (forkchoice-delta-test-reset-operations database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    (multiple-value-bind (head transition)
        (chain-store-set-canonical-head
         store (block-hash genesis)
         :expected-chain-id (chain-config-chain-id config)
         :chain-config config
         :reconcile-unchanged-head-p nil)
      (declare (ignore head))
      (multiple-value-bind (result written-p)
          (node-store-export-forkchoice-to-kv
           store transition database :persistence-metadata metadata-2)
        (is (eq result database))
        (is (null written-p))))
    (is (null
         (forkchoice-delta-test-database-applied-operation-batches database)))
    (multiple-value-bind (metadata present-p)
        (ethereum-lisp.node-store.persistence:node-store-read-persistence-metadata
         database)
      (is present-p)
      (is (= 1
             (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
              metadata))))))

(deftest node-store-forkchoice-delta-skips-staged-installed-payload-records
  (:layer :integration :module :storage)
  (let* ((source (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (state (make-state-db))
         (genesis
           (make-block
            :header
            (make-block-header
             :number 0 :parent-hash (zero-hash32)
             :state-root (state-db-root state)
             :timestamp 0 :gas-limit 30000000 :extra-data (vector 0))))
         (candidate
           (make-block
            :header
            (make-block-header
             :number 1 :parent-hash (block-hash genesis)
             :state-root (state-db-root state)
             :timestamp 1 :gas-limit 30000000 :extra-data (vector 1))))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block source genesis :state-available-p t)
    (commit-state-db-to-chain-store source (block-hash genesis) state)
    (engine-payload-store-put-block
     source candidate :state-available-p t :canonicalize-p nil)
    (commit-state-db-to-chain-store source (block-hash candidate) state)
    (forkchoice-delta-test-set-checkpoints source genesis genesis genesis)
    (node-store-export-to-kv source database)
    (let ((store (make-database-engine-payload-store database)))
      (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
       store)
      (let* ((immutable-symbol
               'ethereum-lisp.node-store.persistence::node-store-put-immutable-block-records)
             (state-symbol
               'ethereum-lisp.node-store.persistence::node-store-put-state-record)
             (immutable-original (fdefinition immutable-symbol))
             (state-original (fdefinition state-symbol))
             (immutable-calls 0)
             (state-calls 0))
        ;; A direct-provider read with no dirty overlay also describes SNAP
        ;; pivot publication, so absence alone must never authorize the skip.
        (is (not
             (ethereum-lisp.node-store.persistence::node-store-installed-block-records-staged-p
              (ethereum-lisp.chain-store.state:chain-store-require-memory-store
               store)
              candidate)))
        (is (not
             (ethereum-lisp.node-store.persistence::node-store-installed-state-record-staged-p
              (ethereum-lisp.chain-store.state:chain-store-require-memory-store
               store)
              candidate)))
        (node-store-export-payload-candidate-to-kv
         store candidate database)
        (is (not
             (ethereum-lisp.node-store.persistence::node-store-installed-block-records-staged-p
              (ethereum-lisp.chain-store.state:chain-store-require-memory-store
               store)
              candidate)))
        (node-store-export-payload-candidate-to-kv
         store candidate database :buffer-for-forkchoice-p t)
        (is (ethereum-lisp.node-store.persistence::node-store-installed-block-records-staged-p
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store)
             candidate))
        (is (ethereum-lisp.node-store.persistence::node-store-installed-state-record-staged-p
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store)
             candidate))
        (let ((transition
                (forkchoice-delta-test-select-head
                 store config candidate genesis genesis)))
          (forkchoice-delta-test-call-with-function-overrides
           (list
            (cons immutable-symbol
                  (lambda (&rest arguments)
                    (incf immutable-calls)
                    (apply immutable-original arguments)))
            (cons state-symbol
                  (lambda (&rest arguments)
                    (incf state-calls)
                    (apply state-original arguments))))
           (lambda ()
             (node-store-export-forkchoice-to-kv
              store transition database)))
          (is (= 0 immutable-calls))
          (is (= 0 state-calls))
          (is (null
               (ethereum-lisp.chain-store.state:memory-chain-store-buffered-engine-payload-hash
                (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                 store))))
          (is (hash32=
               (block-hash candidate)
               (chain-store-canonical-hash store 1)))
          (multiple-value-bind (persisted present-p)
              (kv-get-chain-canonical-hash database 1)
            (is present-p)
            (is (bytes= persisted
                        (hash32-bytes (block-hash candidate))))))))))

(deftest node-store-engine-candidate-buffers-until-canonical-forkchoice
  (:layer :integration :module :storage)
  (labels
      ((make-fixture ()
         (let* ((source (make-engine-payload-memory-store))
                (state (make-state-db))
                (root (state-db-root state))
                (genesis
                  (make-block
                   :header
                   (make-block-header
                    :number 0 :parent-hash (zero-hash32)
                    :state-root root :timestamp 0 :gas-limit 30000000)))
                (candidate
                  (make-block
                   :header
                   (make-block-header
                    :number 1 :parent-hash (block-hash genesis)
                    :state-root root :timestamp 1 :gas-limit 30000000)))
                (database (make-forkchoice-delta-test-database)))
           (chain-store-put-block source genesis :state-available-p t)
           (commit-state-db-to-chain-store source (block-hash genesis) state)
           (forkchoice-delta-test-set-checkpoints
            source genesis genesis genesis)
           (node-store-export-to-kv source database)
           (forkchoice-delta-test-reset-operations database)
           (let ((store (make-database-engine-payload-store database)))
             (engine-payload-store-put-block
              store candidate :state-available-p t :canonicalize-p nil)
             (commit-state-db-to-chain-store
              store (block-hash candidate) state)
             (values store genesis candidate database)))))
    (multiple-value-bind (store genesis candidate database)
        (make-fixture)
      (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
       store)
      (node-store-export-payload-candidate-to-kv
       store candidate database :buffer-for-forkchoice-p t)
      (is (= 1
             (forkchoice-delta-test-database-buffered-apply-attempts
              database)))
      (is
       (ethereum-lisp.node-store.persistence::node-store-installed-block-records-staged-p
        (ethereum-lisp.chain-store.state:chain-store-require-memory-store store)
        candidate))
      (let ((transition
              (forkchoice-delta-test-select-head
               store (make-chain-config :chain-id 1)
               candidate genesis genesis)))
        (multiple-value-bind (result durable-written-p changed-p)
            (node-store-export-forkchoice-to-kv
             store transition database)
          (is (eq result database))
          (is durable-written-p)
          (is changed-p)))
      (is (null
           (ethereum-lisp.chain-store.state:memory-chain-store-buffered-engine-payload-hash
            (ethereum-lisp.chain-store.state:chain-store-require-memory-store
             store)))))
    (multiple-value-bind (store genesis candidate database)
        (make-fixture)
      (declare (ignore genesis))
      (node-store-export-payload-candidate-to-kv
       store candidate database)
      (is (= 0
             (forkchoice-delta-test-database-buffered-apply-attempts
              database)))
      (is (not
           (ethereum-lisp.node-store.persistence::node-store-installed-block-records-staged-p
            (ethereum-lisp.chain-store.state:chain-store-require-memory-store
             store)
            candidate))))))

(deftest node-store-forkchoice-delta-checkpoint-only-is-scoped-and-idempotent
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (safe (forkchoice-delta-test-block genesis 1 1))
         (head (forkchoice-delta-test-block safe 2 2))
         (database (make-forkchoice-delta-test-database)))
    (dolist (block (list genesis safe head))
      (chain-store-put-block store block :state-available-p t))
    (forkchoice-delta-test-set-checkpoints store head genesis genesis)
    (node-store-export-to-kv store database)
    (forkchoice-delta-test-reset-operations database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    (let ((transition
            (forkchoice-delta-test-select-head
             store config head safe genesis)))
      (is (null
           (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
            transition)))
      (is (null
           (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
            transition)))
      (is (null
           (ethereum-lisp.canonical-chain:canonical-chain-transition-changed-txpool-hashes
            transition)))
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (equal
           (list
            (forkchoice-delta-test-expected-operation
             :put :checkpoint "safe"))
           (forkchoice-delta-test-operation-signatures database))))
    (forkchoice-delta-test-reset-operations database)
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash head)
      :safe-block-hash (zero-hash32)
      :finalized-block-hash (zero-hash32)))
    (let ((transition
            (nth-value
             1
             (chain-store-set-canonical-head
              store
              (block-hash head)
              :expected-chain-id (chain-config-chain-id config)
              :chain-config config))))
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (equal
           (sort
            (list
             (forkchoice-delta-test-expected-operation
              :delete :checkpoint "safe")
             (forkchoice-delta-test-expected-operation
              :delete :checkpoint "finalized"))
            #'string<)
           (forkchoice-delta-test-operation-signatures database))))
    (forkchoice-delta-test-reset-operations database)
    (let ((transition
            (nth-value
             1
             (chain-store-set-canonical-head
              store
              (block-hash head)
              :expected-chain-id (chain-config-chain-id config)
              :chain-config config))))
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (null (forkchoice-delta-test-operation-signatures database)))
      (is (null
           (forkchoice-delta-test-database-applied-operation-batches
            database))))))

(deftest node-store-forkchoice-delta-persists-startup-txpool-normalization
  (let* ((source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (transaction (forkchoice-delta-test-transaction))
         (transaction-hash (transaction-hash transaction))
         (transaction-id (hash32-bytes transaction-hash))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (state (make-state-db))
         (database (make-forkchoice-delta-test-database)))
    (state-db-set-account
     state sender (make-state-account :balance 1000000 :nonce 0))
    (let ((head
            (make-block
             :header
             (make-block-header
              :number 0
              :parent-hash (zero-hash32)
              :state-root (state-db-root state)
              :timestamp 0
              :gas-limit 30000000))))
      (chain-store-put-block source head :state-available-p t)
      (commit-state-db-to-chain-store source (block-hash head) state)
      (forkchoice-delta-test-set-checkpoints source head head head)
      (ethereum-lisp.txpool:engine-payload-store-put-queued-transaction
       source transaction)
      (node-store-export-to-kv source database)
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :txpool transaction-id)
        (is present-p)
        (is (string= "queued"
                     (bytes-to-ascii
                      (first
                       (rlp-list-items (rlp-decode-one record)))))))
      (forkchoice-delta-test-reset-operations database)
      (node-store-import-from-kv
       restored
       database
       :expected-chain-id 1
       :chain-config config
       :track-txpool-database-changes-p t)
      (is (ethereum-lisp.txpool:engine-payload-store-txpool-database-change-tracking-enabled-p
           restored))
      (is (null
           (ethereum-lisp.txpool:engine-payload-store-queued-transaction
            restored transaction-hash)))
      (is (ethereum-lisp.txpool:engine-payload-store-pending-transaction
           restored transaction-hash))
      (is (forkchoice-delta-test-one-hash-p
           (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
            restored)
           transaction-hash))
      (let ((transition
              (nth-value
               1
               (chain-store-set-canonical-head
                restored
                (block-hash head)
                :expected-chain-id 1
                :chain-config config))))
        (is (null
             (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
              transition)))
        (is (null
             (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
              transition)))
        (is (forkchoice-delta-test-one-hash-p
             (ethereum-lisp.canonical-chain:canonical-chain-transition-changed-txpool-hashes
              transition)
             transaction-hash))
        (multiple-value-bind (result durable-written-p changed-p)
            (forkchoice-delta-test-export-without-iteration
             restored transition database)
          (is (eq result database))
          (is (null durable-written-p))
          (is changed-p)))
      (is (= 1
             (forkchoice-delta-test-database-buffered-apply-attempts
              database)))
      (is (equal
           (list
            (forkchoice-delta-test-expected-operation
             :put :txpool transaction-id))
           (forkchoice-delta-test-operation-signatures database)))
      (is (null
           (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
            restored)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :txpool transaction-id)
        (is present-p)
        (is (string= "pending"
                     (bytes-to-ascii
                      (first
                       (rlp-list-items (rlp-decode-one record)))))))
      (forkchoice-delta-test-reset-operations database)
      (let ((transition
              (nth-value
               1
               (chain-store-set-canonical-head
                restored
                (block-hash head)
                :expected-chain-id 1
                :chain-config config))))
        (forkchoice-delta-test-export-without-iteration
         restored transition database))
      (is (null (forkchoice-delta-test-operation-signatures database)))
      (is (null
           (forkchoice-delta-test-database-applied-operation-batches
            database)))
      (is (= 0
             (forkchoice-delta-test-database-buffered-apply-attempts
              database))))))

(deftest node-store-forkchoice-delta-requires-persisted-chain-baseline
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block store genesis :state-available-p t)
    (forkchoice-delta-test-set-checkpoints store genesis genesis genesis)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    (let ((transition
            (forkchoice-delta-test-select-head
             store config genesis genesis genesis)))
      (signals block-validation-error
        (forkchoice-delta-test-export-without-iteration
         store transition database)))
    (is (null (forkchoice-delta-test-operation-signatures database)))
    (is (null
         (forkchoice-delta-test-database-applied-operation-batches
          database)))))

(deftest node-store-full-export-bounds-indexed-baseline-with-head-checkpoint
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (head (forkchoice-delta-test-block genesis 1 1))
         (database (make-forkchoice-delta-test-database)))
    ;; A fresh full export must provide the explicit upper bound required by
    ;; direct-key live reconciliation even before the first FCU.
    (chain-store-put-block store genesis :state-available-p t)
    (node-store-export-to-kv store database)
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 0)
      (declare (ignore value))
      (is present-p))
    (multiple-value-bind (value present-p)
        (kv-get-chain-checkpoint database :head)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash genesis)) value)))
    (forkchoice-delta-test-reset-operations database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    (chain-store-put-block store head :state-available-p t)
    (let ((transition
            (forkchoice-delta-test-select-head
             store config head genesis genesis)))
      (is (null
           (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
            transition)))
      (forkchoice-delta-test-export-without-iteration
       store transition database))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 1)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash head)) value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-checkpoint database :head)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash head)) value)))))

(deftest node-store-forkchoice-delta-rejects-headless-sparse-index-baseline
  (let* ((config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (head (forkchoice-delta-test-block genesis 1 1))
         (sparse-head (forkchoice-delta-test-block nil 10 10))
         (persisted-store (make-engine-payload-memory-store))
         (current-store (make-engine-payload-memory-store))
         (database (make-forkchoice-delta-test-database)))
    (dolist (block (list genesis head sparse-head))
      (chain-store-put-block
       persisted-store block :state-available-p t))
    (node-store-export-to-kv persisted-store database)
    (kv-delete-chain-checkpoint database :head)
    (forkchoice-delta-test-reset-operations database)
    (dolist (block (list genesis head))
      (chain-store-put-block current-store block :state-available-p t))
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     current-store)
    (let ((transition
            (forkchoice-delta-test-select-head
             current-store config head genesis genesis)))
      (signals block-validation-error
        (forkchoice-delta-test-export-without-iteration
         current-store transition database)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 10)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash sparse-head)) value)))
    (is (null (forkchoice-delta-test-operation-signatures database)))
    (is (null
         (forkchoice-delta-test-database-applied-operation-batches
          database)))))

(deftest node-store-forkchoice-delta-supports-sparse-canonical-root
  (let* ((store (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (sparse-head (forkchoice-delta-test-block nil 10 10))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block store genesis :state-available-p t)
    (node-store-export-to-kv store database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    ;; Mirror the KZG smoke fixture: establish the ordinary genesis FCU first,
    ;; then select an intentionally isolated test payload at height ten.
    (let ((transition
            (forkchoice-delta-test-select-head
             store config genesis genesis genesis)))
      (forkchoice-delta-test-export-without-iteration
       store transition database))
    (forkchoice-delta-test-reset-operations database)
    (engine-payload-store-put-block
     store sparse-head :state-available-p t :canonicalize-p nil)
    (let ((transition
            (forkchoice-delta-test-select-head
             store config sparse-head sparse-head sparse-head)))
      (is (forkchoice-delta-test-block-list-matches-p
           (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
            transition)
           (list sparse-head)))
      (forkchoice-delta-test-export-without-iteration
       store transition database))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 0)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash genesis)) value)))
    (loop for number from 1 below 10
          do (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database number :missing)
               (is (eq :missing value))
               (is (not present-p))))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 10)
      (is present-p)
      (is (bytes= (hash32-bytes (block-hash sparse-head)) value)))
    (is (eq restored
            (node-store-import-from-kv
             restored database
             :expected-chain-id 1
             :chain-config config)))
    (is (= 10 (chain-store-head-number restored)))
    (is (ethereum-lisp.types:hash32=
         (block-hash sparse-head)
         (chain-store-canonical-hash restored 10)))
    (loop for number from 1 below 10
          do (is (not (chain-store-canonical-hash restored number))))))

(defun forkchoice-delta-test-reorg-fixture ()
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1))
         (transaction (forkchoice-delta-test-transaction))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (old-child (forkchoice-delta-test-block genesis 1 1))
         (old-head
           (forkchoice-delta-test-block old-child 2 2
                                        :transaction transaction))
         (new-head (forkchoice-delta-test-block genesis 1 11))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-child :state-available-p t)
    (chain-store-put-block store old-head :state-available-p t)
    (engine-payload-store-put-block
     store new-head :state-available-p t :canonicalize-p nil)
    (chain-store-put-account-nonce store (block-hash new-head) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-head) sender 1000000)
    (forkchoice-delta-test-set-checkpoints store old-head genesis genesis)
    (node-store-export-to-kv store database)
    (forkchoice-delta-test-reset-operations database)
    (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
     store)
    (values store config database genesis old-child old-head new-head
            transaction)))

(deftest node-store-forkchoice-delta-short-reorg-deletes-obsolete-indexes
  (multiple-value-bind
      (store config database genesis old-child old-head new-head transaction)
      (forkchoice-delta-test-reorg-fixture)
    (let* ((transition
             (forkchoice-delta-test-select-head
              store config new-head genesis genesis))
           (transaction-id (hash32-bytes (transaction-hash transaction)))
           (old-head-id (hash32-bytes (block-hash old-head)))
           (expected
             (sort
              (list
               (forkchoice-delta-test-expected-operation
                :put :canonical-hash 1)
               (forkchoice-delta-test-expected-operation
                :delete :canonical-hash 2)
               (forkchoice-delta-test-expected-operation
                :put :checkpoint "head")
               (forkchoice-delta-test-expected-operation
                :delete :transaction-location transaction-id)
               (forkchoice-delta-test-expected-operation
                :put :txpool transaction-id))
              #'string<)))
      (is (= 1
             (length
              (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
               transition))))
      (is (ethereum-lisp.types:hash32=
           (block-hash
            (first
             (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
              transition)))
           (block-hash new-head)))
      (is (forkchoice-delta-test-block-list-matches-p
           (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
            transition)
           (list old-child old-head)))
      (is (forkchoice-delta-test-one-hash-p
           (ethereum-lisp.canonical-chain:canonical-chain-transition-changed-txpool-hashes
            transition)
           (transaction-hash transaction)))
      (is (ethereum-lisp.txpool:engine-payload-store-pending-transaction
           store (transaction-hash transaction)))
      (forkchoice-delta-test-export-without-iteration
       store transition database)
      (is (equal expected
                 (forkchoice-delta-test-operation-signatures database)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-canonical-hash database 1)
        (is present-p)
        (is (bytes= (hash32-bytes (block-hash new-head)) value)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-canonical-hash database 2 :missing)
        (is (eq :missing value))
        (is (not present-p)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record
           database :transaction-location transaction-id :missing)
        (is (eq :missing value))
        (is (not present-p)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :txpool transaction-id)
        (is present-p)
        (is (plusp (length value))))
      (payload-candidate-export-assert-record
       database :block old-head-id (block-rlp old-head)))))

(deftest node-store-direct-forkchoice-reorg-deletes-stale-transaction-location
  (:layer :integration :module :storage)
  (let* ((config
           (make-chain-config
            :chain-id 1 :homestead-block 0 :eip150-block 0 :eip155-block 0
            :eip158-block 0 :byzantium-block 0 :constantinople-block 0
            :petersburg-block 0 :istanbul-block 0 :berlin-block 0
            :london-block 0))
         (transaction (forkchoice-delta-test-transaction))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (genesis-state (make-state-db))
         (beneficiary (zero-address)))
    (state-db-set-account
     genesis-state sender (make-state-account :nonce 0 :balance 1000000000))
    (let* ((genesis
             (make-block
              :header
              (make-block-header
               :number 0 :parent-hash (zero-hash32)
               :beneficiary beneficiary :state-root (state-db-root genesis-state)
               :mix-hash (zero-hash32) :timestamp 0 :gas-limit 30000000
               :base-fee-per-gas 1)))
           (old-child-state (state-db-copy genesis-state))
           (old-child
             (execute-signed-block
              old-child-state '() :expected-chain-id 1
              :header
              (make-block-header
               :number 1 :parent-hash (block-hash genesis)
               :beneficiary beneficiary :mix-hash (zero-hash32)
               :timestamp 1 :gas-limit 30000000 :base-fee-per-gas 1)
              :chain-config config))
           (old-head-state (state-db-copy old-child-state))
           (old-head
             (execute-signed-block
              old-head-state (list transaction) :expected-chain-id 1
              :header
              (make-block-header
               :number 2 :parent-hash (block-hash old-child)
               :beneficiary beneficiary :mix-hash (zero-hash32)
               :timestamp 2 :gas-limit 30000000 :base-fee-per-gas 1)
              :chain-config config))
           (new-head-state (state-db-copy genesis-state))
           (new-head
             (execute-signed-block
              new-head-state '() :expected-chain-id 1
              :header
              (make-block-header
               :number 1 :parent-hash (block-hash genesis)
               :beneficiary beneficiary :mix-hash (zero-hash32)
               :timestamp 11 :gas-limit 30000000 :base-fee-per-gas 1)
              :chain-config config))
           (source (make-engine-payload-memory-store))
           (database (make-forkchoice-delta-test-database)))
      (dolist (entry
               (list (cons genesis genesis-state)
                     (cons old-child old-child-state)
                     (cons old-head old-head-state)))
        (chain-store-put-block source (car entry) :state-available-p t)
        (commit-state-db-to-chain-store
         source (block-hash (car entry)) (cdr entry)))
      (engine-payload-store-put-block
       source new-head :state-available-p t :canonicalize-p nil)
      (commit-state-db-to-chain-store source (block-hash new-head) new-head-state)
      (forkchoice-delta-test-set-checkpoints source old-head genesis genesis)
      (node-store-export-to-kv source database)
      (let* ((store (make-database-engine-payload-store database))
           (transaction-id (hash32-bytes (transaction-hash transaction))))
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         store)
        (let ((transition
                (forkchoice-delta-test-select-head
                 store config new-head genesis genesis)))
          ;; The direct provider still contains the old durable location until
          ;; the forkchoice WAL batch commits.  Export must treat the missing
          ;; post-transition overlay entry as authoritative, rather than reading
          ;; and rejecting that intentionally stale record.
          (is
           (null
            (gethash
             (hash32-to-hex (transaction-hash transaction))
             (ethereum-lisp.chain-store.state:memory-chain-store-transaction-locations
              (ethereum-lisp.chain-store.state:chain-store-component
               store)))))
          ;; A public lookup at this pre-WAL seam must compare the durable
          ;; location with the new overlay and report it as displaced.  The
          ;; durable decoder still validates RECORD against the old durable
          ;; canonical index instead of rejecting the transaction mid-FCU.
          (is (null (chain-store-transaction-location
                     store (transaction-hash transaction))))
          (node-store-export-forkchoice-to-kv store transition database)
          (multiple-value-bind (value present-p)
              (kv-get-chain-record
               database :transaction-location transaction-id :missing)
            (is (eq :missing value))
            (is (not present-p))))))))

(deftest node-store-direct-same-height-reorg-reinserts-displaced-transaction
  (:layer :integration :module :storage)
  (let* ((config
           (make-chain-config
            :chain-id 1 :homestead-block 0 :eip150-block 0 :eip155-block 0
            :eip158-block 0 :byzantium-block 0 :constantinople-block 0
            :petersburg-block 0 :istanbul-block 0 :berlin-block 0
            :london-block 0))
         (transaction (forkchoice-delta-test-transaction))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (genesis-state (make-state-db))
         (beneficiary (zero-address)))
    (state-db-set-account
     genesis-state sender (make-state-account :nonce 0 :balance 1000000000))
    (let* ((genesis
             (make-block
              :header
              (make-block-header
               :number 0 :parent-hash (zero-hash32)
               :beneficiary beneficiary :state-root (state-db-root genesis-state)
               :mix-hash (zero-hash32) :timestamp 0 :gas-limit 30000000
               :base-fee-per-gas 1)))
           (old-head-state (state-db-copy genesis-state))
           (old-head
             (execute-signed-block
              old-head-state (list transaction) :expected-chain-id 1
              :header
              (make-block-header
               :number 1 :parent-hash (block-hash genesis)
               :beneficiary beneficiary :mix-hash (zero-hash32)
               :timestamp 1 :gas-limit 30000000 :base-fee-per-gas 1)
              :chain-config config))
           (new-head-state (state-db-copy genesis-state))
           (new-head
             (execute-signed-block
              new-head-state '() :expected-chain-id 1
              :header
              (make-block-header
               :number 1 :parent-hash (block-hash genesis)
               :beneficiary beneficiary :mix-hash (zero-hash32)
               :timestamp 11 :gas-limit 30000000 :base-fee-per-gas 1)
              :chain-config config))
           (source (make-engine-payload-memory-store))
           (database (make-forkchoice-delta-test-database)))
      (dolist (entry
               (list (cons genesis genesis-state)
                     (cons old-head old-head-state)))
        (chain-store-put-block source (car entry) :state-available-p t)
        (commit-state-db-to-chain-store
         source (block-hash (car entry)) (cdr entry)))
      (engine-payload-store-put-block
       source new-head :state-available-p t :canonicalize-p nil)
      (commit-state-db-to-chain-store source (block-hash new-head) new-head-state)
      (forkchoice-delta-test-set-checkpoints source old-head genesis genesis)
      (node-store-export-to-kv source database)
      (let ((store (make-database-engine-payload-store database)))
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         store)
        ;; The durable location still belongs to OLD-HEAD until the FCU batch
        ;; commits.  Selecting NEW-HEAD must hide that location through the
        ;; overlay and reinsert the displaced transaction instead of rejecting
        ;; the otherwise valid durable snapshot as non-canonical.
        (let ((transition
                (forkchoice-delta-test-select-head
                 store config new-head genesis genesis)))
          (is (ethereum-lisp.txpool:engine-payload-store-pending-transaction
               store (transaction-hash transaction)))
          (is (null (chain-store-transaction-location
                     store (transaction-hash transaction))))
          (node-store-export-forkchoice-to-kv store transition database)
          (is (null (chain-store-transaction-location
                     store (transaction-hash transaction)))))))))

(deftest node-store-forkchoice-delta-conflict-does-not-partially-apply
  (multiple-value-bind
      (store config database genesis parent candidate side transaction
       unrelated-transaction)
      (forkchoice-delta-test-extension-fixture)
    (declare (ignore parent side))
    (let ((candidate-id (hash32-bytes (block-hash candidate))))
      (forkchoice-delta-test-delete-block-records database candidate)
      (kv-put-chain-record database :block candidate-id #(222))
      (let* ((before (payload-candidate-export-database-snapshot database))
             (transition
               (forkchoice-delta-test-select-head
                store config candidate genesis genesis)))
        (signals block-validation-error
          (forkchoice-delta-test-export-without-iteration
           store transition database))
        (is (null (forkchoice-delta-test-operation-signatures database)))
        (is (null
             (forkchoice-delta-test-database-applied-operation-batches
              database)))
        (is (forkchoice-delta-test-hash-set-matches-p
             (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
              store)
             (list (transaction-hash transaction)
                   (transaction-hash unrelated-transaction))))
        (is (equalp before
                    (payload-candidate-export-database-snapshot database)))))))

(defun forkchoice-reconciliation-test-export-baseline
    (store database head genesis)
  (forkchoice-delta-test-set-checkpoints store head genesis genesis)
  (node-store-export-to-kv store database)
  (forkchoice-delta-test-reset-operations database)
  database)

(defun forkchoice-reconciliation-test-empty-transition
    (store config head genesis)
  (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
   store)
  (let ((transition
          (forkchoice-delta-test-select-head
           store config head genesis genesis)))
    (is (null
         (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
          transition)))
    (is (null
         (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
          transition)))
    transition))

(deftest node-store-forkchoice-reconciliation-deletes-same-height-old-location
  (let* ((config (make-chain-config :chain-id 1))
         (transaction (forkchoice-delta-test-transaction))
         (transaction-hash (transaction-hash transaction))
         (transaction-id (hash32-bytes transaction-hash))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (persisted-head
           (forkchoice-delta-test-block
            genesis 1 1 :transaction transaction))
         (current-head (forkchoice-delta-test-block genesis 1 11))
         (persisted-store (make-engine-payload-memory-store))
         (current-store (make-engine-payload-memory-store))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block persisted-store genesis :state-available-p t)
    (chain-store-put-block
     persisted-store persisted-head :state-available-p t)
    (forkchoice-reconciliation-test-export-baseline
     persisted-store database persisted-head genesis)
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :transaction-location transaction-id)
      (declare (ignore value))
      (is present-p))
    (chain-store-put-block current-store genesis :state-available-p t)
    (chain-store-put-block current-store current-head :state-available-p t)
    (let* ((transition
             (forkchoice-reconciliation-test-empty-transition
              current-store config current-head genesis))
           (delete-location-operation
             (forkchoice-delta-test-expected-operation
              :delete :transaction-location transaction-id)))
      (forkchoice-delta-test-export-without-iteration
       current-store transition database)
      (is (find delete-location-operation
                (forkchoice-delta-test-operation-signatures database)
                :test #'string=)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record
         database :transaction-location transaction-id :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (let ((persisted-id (hash32-bytes (block-hash persisted-head)))
          (current-id (hash32-bytes (block-hash current-head))))
      (payload-candidate-export-assert-record
       database :block persisted-id (block-rlp persisted-head))
      (payload-candidate-export-assert-record
       database :block current-id (block-rlp current-head)))
    (let ((restored (make-engine-payload-memory-store)))
      (is (eq restored
              (node-store-import-from-kv
               restored database
               :expected-chain-id 1
               :chain-config config)))
      (is (= 1 (chain-store-head-number restored)))
      (is (bytes=
           (hash32-bytes (block-hash current-head))
           (hash32-bytes (chain-store-canonical-hash restored 1))))
      (is (chain-store-known-block restored (block-hash persisted-head)))
      (is (not (chain-store-transaction-location
                restored transaction-hash))))))

(deftest node-store-forkchoice-reconciliation-deletes-ahead-old-location
  (let* ((config (make-chain-config :chain-id 1))
         (transaction (forkchoice-delta-test-transaction))
         (transaction-hash (transaction-hash transaction))
         (transaction-id (hash32-bytes transaction-hash))
         (genesis (forkchoice-delta-test-block nil 0 0))
         (persisted-child (forkchoice-delta-test-block genesis 1 1))
         (persisted-head
           (forkchoice-delta-test-block
            persisted-child 2 2 :transaction transaction))
         (current-head (forkchoice-delta-test-block genesis 1 11))
         (persisted-store (make-engine-payload-memory-store))
         (current-store (make-engine-payload-memory-store))
         (database (make-forkchoice-delta-test-database)))
    (chain-store-put-block persisted-store genesis :state-available-p t)
    (chain-store-put-block
     persisted-store persisted-child :state-available-p t)
    (chain-store-put-block
     persisted-store persisted-head :state-available-p t)
    (forkchoice-reconciliation-test-export-baseline
     persisted-store database persisted-head genesis)
    (chain-store-put-block current-store genesis :state-available-p t)
    (chain-store-put-block current-store current-head :state-available-p t)
    (let* ((transition
             (forkchoice-reconciliation-test-empty-transition
              current-store config current-head genesis))
           (operations nil)
           (delete-canonical-operation
             (forkchoice-delta-test-expected-operation
              :delete :canonical-hash 2))
           (delete-location-operation
             (forkchoice-delta-test-expected-operation
              :delete :transaction-location transaction-id)))
      (forkchoice-delta-test-export-without-iteration
       current-store transition database)
      (setf operations
            (forkchoice-delta-test-operation-signatures database))
      (is (find delete-canonical-operation operations :test #'string=))
      (is (find delete-location-operation operations :test #'string=)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 2 :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record
         database :transaction-location transaction-id :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (let ((persisted-head-id
            (hash32-bytes (block-hash persisted-head))))
      (payload-candidate-export-assert-record
       database :block persisted-head-id (block-rlp persisted-head)))
    (let ((restored (make-engine-payload-memory-store)))
      (is (eq restored
              (node-store-import-from-kv
               restored database
               :expected-chain-id 1
               :chain-config config)))
      (is (= 1 (chain-store-head-number restored)))
      (is (bytes=
           (hash32-bytes (block-hash current-head))
           (hash32-bytes (chain-store-canonical-hash restored 1))))
      (is (not (chain-store-canonical-hash restored 2)))
      (is (chain-store-known-block restored (block-hash persisted-head)))
      (is (not (chain-store-transaction-location
                restored transaction-hash))))))

(deftest node-store-snap-pivot-export-is-a-bounded-restartable-delta
  (:layer :integration :module :persistence)
  (multiple-value-bind (source config parent pivot)
      (block-import-test-fixture)
    (import-block-candidate source pivot config)
    (let* ((pivot-hash (block-hash pivot))
           (target
             (execute-signed-block
              (chain-store-state-db source pivot-hash)
              '()
              :expected-chain-id 1
              :header
              (make-block-header
               :parent-hash pivot-hash
               :beneficiary (zero-address)
               :mix-hash (zero-hash32)
               :number 2
               :gas-limit 30000000
               :timestamp 2
               :base-fee-per-gas
               (expected-base-fee-per-gas (block-header pivot)))
              :chain-config config
              :withdrawals '()))
           (target-hash (block-hash target))
           (database (make-forkchoice-delta-test-database))
           (authority-id (peer-sync-progress-test-authority-id))
           (metadata
             (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
              :role :database :generation 1 :chain-id 1
              :genesis-hash (block-hash parent)
              :authority-id authority-id :base-chain-generation 1)))
      (engine-payload-store-put-block
       source target :state-available-p nil :canonicalize-p nil)
      (node-store-export-to-kv
       source database :persistence-metadata metadata)
      (ethereum-lisp.node-store.persistence:node-store-export-snap-skeleton-batch-to-kv
       database (list pivot target)
       (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
        :authority-id authority-id :chain-id 1
        :genesis-hash (block-hash parent)
        :target-number 2 :target-hash target-hash
        :anchor-number 0 :anchor-hash (block-hash parent)
        :pivot-number 1 :pivot-hash pivot-hash
        :last-number 2 :last-hash target-hash))
      (let ((direct (make-database-engine-payload-store database)))
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         direct)
        (unwind-protect
             (progn
               ;; The sparse pivot path must not scan every skipped height or
               ;; any database prefix on its hot publication boundary.
               (setf (forkchoice-delta-test-database-forbid-iteration-p
                      database)
                     t)
               (install-forkchoice-sync-pivot
                direct pivot-hash target-hash config
                :consensus-authorized-p t
                :durability-function
                (lambda (callback-store transition
                         &key sync-pivot-target-hash)
                  (node-store-export-forkchoice-to-kv
                   callback-store transition database
                   :persistence-metadata
                   (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
                    :role :database :generation 2 :chain-id 1
                    :genesis-hash (block-hash parent)
                    :authority-id authority-id :base-chain-generation 2)
                   :sync-pivot-target-hash sync-pivot-target-hash))))
          (setf (forkchoice-delta-test-database-forbid-iteration-p database)
                nil)))
      (let ((restored (make-database-engine-payload-store database)))
        (is (= 1 (chain-store-head-number restored)))
        (is (hash32= pivot-hash (chain-store-canonical-hash restored 1)))
        (is (null (chain-store-canonical-hash restored 2)))
        (is (chain-store-state-available-p restored pivot-hash))
        (is (chain-store-known-block restored target-hash))
        (is (not (chain-store-state-available-p restored target-hash)))))))
