(in-package #:ethereum-lisp.test)

(defclass forkchoice-delta-test-database (memory-key-value-database)
  ((applied-operation-batches
     :initform nil
     :accessor forkchoice-delta-test-database-applied-operation-batches)
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
        nil))

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
        (forkchoice-delta-test-export-without-iteration
         restored transition database))
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
