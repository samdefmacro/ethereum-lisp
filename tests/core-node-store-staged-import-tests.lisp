(in-package #:ethereum-lisp.test)

(defparameter +staged-import-test-record-kinds+
  '(:block :header :receipt :canonical-hash :checkpoint :state
    :transaction-location :txpool :invalid-tipset :remote-block :blob-sidecar
    :prepared-payload :metadata :staged-header :staged-block :staged-state
    :staged-receipt :staged-transaction-index :stage-progress))

(defun staged-import-test-database-snapshot (database)
  (loop for kind in +staged-import-test-record-kinds+
        collect
        (cons kind
              (loop for entry in (kv-chain-record-entries database kind)
                    collect
                    (cons (copy-seq (car entry))
                          (copy-seq (cdr entry)))))))

(defun staged-import-test-chain-config (&key (cancun-time 100))
  (make-chain-config
   :chain-id 1
   :homestead-block 0
   :eip150-block 0
   :eip155-block 0
   :eip158-block 0
   :byzantium-block 0
   :constantinople-block 0
   :petersburg-block 0
   :istanbul-block 0
   :berlin-block 0
   :london-block 0
   :shanghai-time 0
   :cancun-time cancun-time))

(defun staged-import-test-prepare (database)
  (let* ((config (staged-import-test-chain-config))
         (branch-a-transaction (forkchoice-delta-test-transaction))
         (branch-b-transaction
           (forkchoice-delta-test-unrelated-transaction))
         (branch-a-sender
           (transaction-sender branch-a-transaction :expected-chain-id 1))
         (branch-b-sender
           (transaction-sender branch-b-transaction :expected-chain-id 1))
         (anchor-state
           (let ((state (make-state-db)))
             (state-db-set-account
              state branch-a-sender
              (make-state-account :nonce 0 :balance 1000000000))
             (state-db-set-account
              state branch-b-sender
              (make-state-account :nonce 0 :balance 1000000000))
             state))
         (source (make-engine-payload-memory-store))
         (anchor-store (make-engine-payload-memory-store))
         (beneficiary (zero-address))
         (anchor
            (make-block
             :header
             (make-block-header
              :number 0
              :parent-hash (zero-hash32)
              :beneficiary beneficiary
              :state-root (state-db-root anchor-state)
              :mix-hash (zero-hash32)
              :timestamp 0
              :gas-limit 30000000
              :base-fee-per-gas 1
              :extra-data #(0))
             :withdrawals '()))
         (branch-a-state (state-db-copy anchor-state))
         (branch-a
           (execute-signed-block
            branch-a-state
            (list branch-a-transaction)
            :expected-chain-id 1
            :header
            (make-block-header
             :number 1
             :parent-hash (block-hash anchor)
             :beneficiary beneficiary
             :mix-hash (zero-hash32)
             :timestamp 1
             :gas-limit 30000000
             :base-fee-per-gas 1
             :extra-data #(1))
            :chain-config config
            :withdrawals '()))
         (branch-b-state (state-db-copy anchor-state))
         (branch-b
           (execute-signed-block
            branch-b-state
            (list branch-b-transaction)
            :expected-chain-id 1
            :header
            (make-block-header
             :number 1
             :parent-hash (block-hash anchor)
             :beneficiary beneficiary
             :mix-hash (zero-hash32)
             :timestamp 2
             :gas-limit 30000000
             :base-fee-per-gas 1
             :extra-data #(2))
            :chain-config config
            :withdrawals '())))
    (chain-store-put-block anchor-store anchor :state-available-p t)
    (commit-state-db-to-chain-store
     anchor-store (block-hash anchor) anchor-state)
    (chain-store-update-forkchoice-checkpoints
     anchor-store
     (make-forkchoice-state
      :head-block-hash (block-hash anchor)
      :safe-block-hash (block-hash anchor)
      :finalized-block-hash (block-hash anchor)))
    (node-store-export-to-kv
     anchor-store database
     :persistence-metadata
     (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
      :role :database
      :generation 0
      :base-chain-generation 0
      :chain-id 1
      :genesis-hash (block-hash anchor)
      :authority-id (zero-hash32)))
    (chain-store-put-block source anchor :state-available-p t)
    (commit-state-db-to-chain-store source (block-hash anchor) anchor-state)
    (chain-store-put-block source branch-a :state-available-p t)
    (commit-state-db-to-chain-store
     source (block-hash branch-a) branch-a-state)
    (engine-payload-store-put-block
     source branch-b :state-available-p t :canonicalize-p nil)
    (commit-state-db-to-chain-store
     source (block-hash branch-b) branch-b-state)
    (multiple-value-bind (state status)
        (node-store-begin-staged-import
         database anchor :chain-config config)
      (is (node-store-staged-import-state-p state))
      (is (eq :initialized status)))
    (values source config anchor branch-a branch-b
            branch-a-transaction branch-b-transaction)))

(defun staged-import-test-progress-at-block-p (progress block)
  (and (= (node-store-stage-progress-number progress)
          (block-header-number (block-header block)))
       (ethereum-lisp.types:hash32=
        (node-store-stage-progress-block-hash progress)
        (block-hash block))))

(defun staged-import-test-state-stage-at-block-p (state stage block)
  (staged-import-test-progress-at-block-p
   (node-store-staged-import-stage-progress state stage)
   block))

(defun staged-import-test-forward-stages
    (source config database block stages)
  (let (state)
    (dolist (stage stages state)
      (multiple-value-bind (new-state status)
          (node-store-forward-staged-import-block
           source database block :stage stage :chain-config config)
        (is (eq :advanced status))
        (is (staged-import-test-state-stage-at-block-p
             new-state stage block))
        (setf state new-state)))))

(defun staged-import-test-record-present-p (database kind identifier)
  (nth-value 1 (kv-get-chain-record database kind identifier)))

(defun staged-import-test-staged-index-identifier (block)
  (ethereum-lisp.node-store.persistence::node-store-staged-transaction-index-identifier
   (block-hash block) 0))

(defun staged-import-test-assert-private-block (database block)
  (let ((identifier (hash32-bytes (block-hash block))))
    (dolist (kind '(:staged-header :staged-block :staged-state
                    :staged-receipt))
      (is (staged-import-test-record-present-p
           database kind identifier)))
    (is (staged-import-test-record-present-p
         database
         :staged-transaction-index
         (staged-import-test-staged-index-identifier block)))))

(defun staged-import-test-assert-public-anchor-only
    (database anchor &rest transactions)
  (multiple-value-bind (hash present-p)
      (kv-get-chain-canonical-hash database 0)
    (is present-p)
    (is (bytes= hash (hash32-bytes (block-hash anchor)))))
  (multiple-value-bind (value present-p)
      (kv-get-chain-canonical-hash database 1 :missing)
    (is (eq :missing value))
    (is (not present-p)))
  (multiple-value-bind (hash present-p)
      (kv-get-chain-checkpoint database :head)
    (is present-p)
    (is (bytes= hash (hash32-bytes (block-hash anchor)))))
  (dolist (checkpoint '(:safe :finalized))
    (multiple-value-bind (hash present-p)
        (kv-get-chain-checkpoint database checkpoint)
      (is present-p)
      (is (bytes= hash (hash32-bytes (block-hash anchor))))))
  (dolist (transaction transactions)
    (multiple-value-bind (value present-p)
        (kv-get-chain-record
         database :transaction-location
         (hash32-bytes (transaction-hash transaction))
         :missing)
      (is (eq :missing value))
      (is (not present-p)))))

(defun staged-import-test-assert-hydrated
    (store anchor block transaction)
  (let ((hydrated (chain-store-known-block store (block-hash block))))
    (is hydrated)
    (is (bytes= (block-rlp hydrated) (block-rlp block)))
    (is (= 1 (length (ethereum-lisp.blocks:block-receipts hydrated))))
    (is (bytes=
         (receipt-rlp
          (first (ethereum-lisp.blocks:block-receipts hydrated)))
         (receipt-rlp
          (first (ethereum-lisp.blocks:block-receipts block))))))
  (is (chain-store-state-available-p store (block-hash block)))
  (is (= 0 (chain-store-head-number store)))
  (is (ethereum-lisp.types:hash32=
       (chain-store-canonical-hash store 0)
       (block-hash anchor)))
  (is (not (chain-store-canonical-hash store 1)))
  (is (not (chain-store-transaction-location
            store (transaction-hash transaction)))))

(defun staged-import-test-batch-has-key-p (batch kind identifier)
  (let ((expected (kv-chain-record-key kind identifier)))
    (find-if
     (lambda (operation)
       (and (eq :put (first operation))
            (bytes= expected (second operation))))
     batch)))

(defun staged-import-test-stage-output-identifiers (stage block)
  (let ((block-identifier (hash32-bytes (block-hash block))))
    (ecase stage
      (:headers
       (list (cons :staged-header block-identifier)))
      (:bodies
       (list (cons :staged-block block-identifier)))
      (:execution
       (list (cons :staged-state block-identifier)
             (cons :staged-receipt block-identifier)))
      (:receipts nil)
      (:transaction-index
       (list
        (cons :staged-transaction-index
              (staged-import-test-staged-index-identifier block)))))))

(defun staged-import-test-assert-stage-batch (batch stage block)
  (let ((outputs (staged-import-test-stage-output-identifiers stage block)))
    (is (= (length batch) (1+ (length outputs))))
    (is (staged-import-test-batch-has-key-p
         batch :stage-progress "local"))
    (dolist (output outputs)
      (is (staged-import-test-batch-has-key-p
           batch (car output) (cdr output))))))

(defun staged-import-test-control-with-version (record version)
  (let ((fields
          (copy-list (rlp-list-items (rlp-decode-one record)))))
    (setf (first fields) version)
    (rlp-encode (apply #'make-rlp-list fields))))

(defun staged-import-test-control-with-empty-progresses (record)
  (let ((fields
          (copy-list (rlp-list-items (rlp-decode-one record)))))
    (setf (nth (1- (length fields)) fields) (make-rlp-list))
    (rlp-encode (apply #'make-rlp-list fields))))

(defun staged-import-test-control-with-stage-hash (record stage block)
  (let* ((fields
           (copy-list (rlp-list-items (rlp-decode-one record))))
         (progress-index (1- (length fields)))
         (progresses
           (copy-list (rlp-list-items (nth progress-index fields))))
         (stage-index
           (position stage (node-store-staged-import-stages)))
         (stage-fields
           (copy-list
            (rlp-list-items (nth stage-index progresses)))))
    (setf (third stage-fields) (hash32-bytes (block-hash block))
          (nth stage-index progresses)
          (apply #'make-rlp-list stage-fields)
          (nth progress-index fields)
          (apply #'make-rlp-list progresses))
    (rlp-encode (apply #'make-rlp-list fields))))

(deftest node-store-staged-import-file-restart-resumes-receipts-and-hydrates
  (:layer :integration :module :persistence)
  (let ((path
          (merge-pathnames
           (make-pathname
            :name (format nil "ethereum-lisp-staged-import-restart-~A"
                          (gensym))
            :type "sexp")
           #P"/private/tmp/")))
    (unwind-protect
         (let ((database (make-file-key-value-database path)))
           (multiple-value-bind
               (source config anchor branch-a branch-b
                transaction-a transaction-b)
               (staged-import-test-prepare database)
             (declare (ignore branch-b transaction-b))
             (staged-import-test-forward-stages
              source config database branch-a
              '(:headers :bodies))
             (let ((state (node-store-validate-staged-import database)))
               (is (eq :forward
                       (node-store-staged-import-state-mode state)))
               (is (staged-import-test-state-stage-at-block-p
                    state :bodies branch-a))
               (is (staged-import-test-state-stage-at-block-p
                    state :execution anchor)))
             ;; The first restart discards both external inputs.  Execution
             ;; must reconstruct the target body and its parent state entirely
             ;; from durable staged records.
             (setf database nil
                   source nil)
             (let ((body-reopened (make-file-key-value-database path)))
               (multiple-value-bind (action stage target)
                   (node-store-staged-import-next-action body-reopened)
                 (is (eq :forward action))
                 (is (eq :execution stage))
                 (is (staged-import-test-progress-at-block-p
                      target branch-a)))
               (multiple-value-bind (state status)
                   (node-store-forward-staged-import-block
                    nil body-reopened nil
                    :stage :execution
                    :chain-config config)
                 (is (eq :advanced status))
                 (is (staged-import-test-state-stage-at-block-p
                      state :execution branch-a)))
               ;; Reopen again after execution.  Receipts must be the next
               ;; durable action, and a fresh hydrated store becomes the only
               ;; remaining block source for the finishing stages.
               (setf body-reopened nil)
               (let ((reopened (make-file-key-value-database path)))
                 (multiple-value-bind (action stage target)
                     (node-store-staged-import-next-action reopened)
                   (is (eq :forward action))
                   (is (eq :receipts stage))
                   (is (staged-import-test-progress-at-block-p
                        target branch-a)))
                 (let ((execution-store (make-engine-payload-memory-store)))
                   (is (eq execution-store
                           (node-store-hydrate-staged-import
                            execution-store reopened
                            :stage :execution
                            :expected-chain-id 1
                            :chain-config config)))
                   (staged-import-test-assert-hydrated
                    execution-store anchor branch-a transaction-a)
                   (let ((resumed-block
                           (chain-store-known-block
                            execution-store (block-hash branch-a))))
                     (multiple-value-bind (state status)
                         (node-store-forward-staged-import-block
                          execution-store reopened resumed-block
                          :stage :receipts
                          :chain-config config)
                       (is (eq :advanced status))
                       (is (staged-import-test-state-stage-at-block-p
                            state :receipts branch-a)))
                     (multiple-value-bind (action stage target)
                         (node-store-staged-import-next-action reopened)
                       (is (eq :forward action))
                       (is (eq :transaction-index stage))
                       (is (staged-import-test-progress-at-block-p
                            target branch-a)))
                     (multiple-value-bind (state status)
                         (node-store-forward-staged-import-block
                          execution-store reopened resumed-block
                          :stage :transaction-index
                          :chain-config config)
                       (is (eq :advanced status))
                       (is (staged-import-test-state-stage-at-block-p
                            state :transaction-index branch-a)))))
                 (let ((receipt-store (make-engine-payload-memory-store)))
                   (is (eq receipt-store
                           (node-store-hydrate-staged-import
                            receipt-store reopened
                            :stage :receipts
                            :expected-chain-id 1
                            :chain-config config)))
                   (staged-import-test-assert-hydrated
                    receipt-store anchor branch-a transaction-a))
                 (staged-import-test-assert-public-anchor-only
                  reopened anchor transaction-a)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest node-store-staged-import-stage-batch-failure-rolls-back-and-retries
  (:layer :integration :module :persistence)
  (let ((stages (node-store-staged-import-stages)))
    (dolist (stage stages)
      (let ((database
              (make-instance 'forkchoice-delta-failing-test-database)))
        (multiple-value-bind
            (source config anchor branch-a branch-b
             transaction-a transaction-b)
            (staged-import-test-prepare database)
          (declare (ignore anchor branch-b transaction-a transaction-b))
          (staged-import-test-forward-stages
           source config database branch-a
           (subseq stages 0 (position stage stages)))
          (forkchoice-delta-test-reset-operations database)
          (setf
           (forkchoice-delta-failing-test-database-apply-attempts database)
           0
           (forkchoice-delta-failing-test-database-fail-next-apply-p database)
           t)
          (let ((before (staged-import-test-database-snapshot database)))
            (signals error
              (node-store-forward-staged-import-block
               source database branch-a
               :stage stage :chain-config config))
            (is (= 1
                   (forkchoice-delta-failing-test-database-apply-attempts
                    database)))
            (is (null
                 (forkchoice-delta-test-database-applied-operation-batches
                  database)))
            (is (equalp before
                        (staged-import-test-database-snapshot database))))
          (multiple-value-bind (state status)
              (node-store-forward-staged-import-block
               source database branch-a
               :stage stage :chain-config config)
            (is (eq :advanced status))
            (is (staged-import-test-state-stage-at-block-p
                 state stage branch-a)))
          (is (= 2
                 (forkchoice-delta-failing-test-database-apply-attempts
                  database)))
          (let ((batches
                  (forkchoice-delta-test-database-applied-operation-batches
                   database)))
            (is (= 1 (length batches)))
            (staged-import-test-assert-stage-batch
             (first batches) stage branch-a))
          (let ((after-retry
                  (staged-import-test-database-snapshot database)))
            (multiple-value-bind (state status)
                (node-store-forward-staged-import-block
                 source database branch-a
                 :stage stage :chain-config config)
              (is (node-store-staged-import-state-p state))
              (is (eq :already-complete status)))
            (is (= 2
                   (forkchoice-delta-failing-test-database-apply-attempts
                    database)))
            (is (= 1
                   (length
                    (forkchoice-delta-test-database-applied-operation-batches
                     database))))
            (is (equalp after-retry
                        (staged-import-test-database-snapshot database)))))))))

(deftest node-store-staged-import-same-height-reorg-unwinds-in-reverse
  (:layer :integration :module :persistence)
  (let ((database (make-forkchoice-delta-test-database)))
    (multiple-value-bind
        (source config anchor branch-a branch-b
         transaction-a transaction-b)
        (staged-import-test-prepare database)
      (staged-import-test-forward-stages
       source config database branch-a (node-store-staged-import-stages))
      (kv-put-chain-record
       database :metadata "staged-import-test-sentinel" #(9 8 7))
      (staged-import-test-assert-private-block database branch-a)
      (staged-import-test-assert-public-anchor-only
       database anchor transaction-a transaction-b)
      (multiple-value-bind (state status)
          (node-store-begin-staged-unwind database anchor)
        (is (node-store-staged-import-state-p state))
        (is (eq :unwind-started status)))
      (forkchoice-delta-test-reset-operations database)
      (let ((expected
              '(:transaction-index :receipts :execution :bodies :headers))
            (observed nil))
        (dolist (expected-stage expected)
          (multiple-value-bind (action stage target)
              (node-store-staged-import-next-action database)
            (is (eq :unwind action))
            (is (eq expected-stage stage))
            (is (staged-import-test-progress-at-block-p target anchor)))
          (multiple-value-bind (state stage)
              (node-store-unwind-staged-import-step database)
            (is (node-store-staged-import-state-p state))
            (is (eq expected-stage stage))
            (push stage observed)))
        (is (equal expected (nreverse observed))))
      (let ((state (node-store-validate-staged-import database)))
        (is (eq :ready (node-store-staged-import-state-mode state)))
        (dolist (stage (node-store-staged-import-stages))
          (is (staged-import-test-state-stage-at-block-p
               state stage anchor))))
      (let ((batches
              (reverse
               (forkchoice-delta-test-database-applied-operation-batches
                database))))
        (is (= 5 (length batches)))
        (dolist (batch batches)
          (is (= 1 (length batch)))
          (is (staged-import-test-batch-has-key-p
               batch :stage-progress "local"))))
      ;; Unwind changes only durable progress.  Hash-addressed materialization
      ;; remains a private side cache and public canonical state is untouched.
      (staged-import-test-assert-private-block database branch-a)
      (is (= 1 (length (kv-chain-record-entries
                        database :staged-transaction-index))))
      (staged-import-test-assert-public-anchor-only
       database anchor transaction-a transaction-b)
      (multiple-value-bind (sentinel present-p)
          (kv-get-chain-record
           database :metadata "staged-import-test-sentinel")
        (is present-p)
        (is (bytes= #(9 8 7) sentinel)))
      (forkchoice-delta-test-reset-operations database)
      (staged-import-test-forward-stages
       source config database branch-b (node-store-staged-import-stages))
      (let ((state (node-store-validate-staged-import database)))
        (is (eq :ready (node-store-staged-import-state-mode state)))
        (is (staged-import-test-progress-at-block-p
             (node-store-staged-import-state-target state) branch-b))
        (dolist (stage (node-store-staged-import-stages))
          (is (staged-import-test-state-stage-at-block-p
               state stage branch-b))))
      (staged-import-test-assert-private-block database branch-a)
      (staged-import-test-assert-private-block database branch-b)
      (dolist (kind '(:staged-header :staged-block :staged-state
                      :staged-receipt))
        (is (= 3 (length (kv-chain-record-entries database kind)))))
      (is (= 2 (length (kv-chain-record-entries
                        database :staged-transaction-index))))
      (staged-import-test-assert-public-anchor-only
       database anchor transaction-a transaction-b)
      (multiple-value-bind (sentinel present-p)
          (kv-get-chain-record
           database :metadata "staged-import-test-sentinel")
        (is present-p)
        (is (bytes= #(9 8 7) sentinel))))))

(deftest node-store-staged-import-rejects-chain-config-drift
  (:layer :integration :module :persistence)
  (let ((database (make-forkchoice-delta-test-database)))
    (multiple-value-bind
        (source config anchor branch-a branch-b
         transaction-a transaction-b)
        (staged-import-test-prepare database)
      (declare (ignore branch-b transaction-a transaction-b))
      (let ((different-config
              (staged-import-test-chain-config :cancun-time 200)))
        (is (= (chain-config-chain-id config)
               (chain-config-chain-id different-config)))
        (let ((before (staged-import-test-database-snapshot database)))
          (signals block-validation-error
            (node-store-forward-staged-import-block
             source database branch-a
             :stage :headers :chain-config different-config))
          (is (equalp before
                      (staged-import-test-database-snapshot database))))
        (staged-import-test-forward-stages
         source config database branch-a
         (node-store-staged-import-stages))
        (let ((target (make-engine-payload-memory-store))
              (before (staged-import-test-database-snapshot database)))
          (signals block-validation-error
            (node-store-hydrate-staged-import
             target database
             :expected-chain-id 1
             :chain-config different-config))
          (is (equalp before
                      (staged-import-test-database-snapshot database)))
          (is (not (chain-store-known-block target (block-hash anchor))))
          (is (= 0 (chain-store-head-number target)))
          (is (not (chain-store-canonical-hash target 0)))
          (is (null
               (ethereum-lisp.txpool:engine-payload-store-pooled-transactions
                target))))))))

(deftest node-store-staged-import-rejects-nonfresh-hydration-target
  (:layer :integration :module :persistence)
  (let ((database (make-forkchoice-delta-test-database)))
    (multiple-value-bind
        (source config anchor branch-a branch-b
         transaction-a transaction-b)
        (staged-import-test-prepare database)
      (declare (ignore transaction-a transaction-b))
      (staged-import-test-forward-stages
       source config database branch-a
       (node-store-staged-import-stages))
      (let ((target (make-engine-payload-memory-store)))
        (engine-payload-store-put-block
         target branch-b :state-available-p t :canonicalize-p nil)
        (let ((before (staged-import-test-database-snapshot database)))
          (signals block-validation-error
            (node-store-hydrate-staged-import
             target database
             :expected-chain-id 1
             :chain-config config))
          (is (equalp before
                      (staged-import-test-database-snapshot database))))
        (let ((sentinel
                (chain-store-known-block target (block-hash branch-b))))
          (is sentinel)
          (is (bytes= (block-rlp sentinel) (block-rlp branch-b))))
        (is (chain-store-state-available-p target (block-hash branch-b)))
        (is (not (chain-store-known-block target (block-hash anchor))))
        (is (= 0 (chain-store-head-number target)))
        (is (not (chain-store-canonical-hash target 0)))
        (is (null
             (ethereum-lisp.txpool:engine-payload-store-pooled-transactions
              target)))))))

(deftest node-store-staged-import-header-cannot-skip-grandparent
  (:layer :integration :module :persistence)
  (let ((database (make-forkchoice-delta-test-database)))
    (multiple-value-bind
        (source config anchor branch-a branch-b
         transaction-a transaction-b)
        (staged-import-test-prepare database)
      (declare (ignore branch-b transaction-a transaction-b))
      (let* ((grandchild-state
               (chain-store-state-db source (block-hash branch-a)))
             (grandchild
               (execute-signed-block
                grandchild-state
                '()
                :expected-chain-id 1
                :header
                (make-block-header
                 :number 2
                 :parent-hash (block-hash branch-a)
                 :beneficiary (zero-address)
                 :mix-hash (zero-hash32)
                 :timestamp 3
                 :gas-limit 30000000
                 :base-fee-per-gas 1
                 :extra-data #(3))
                :chain-config config
                :withdrawals '())))
        (engine-payload-store-put-block
         source grandchild :state-available-p t :canonicalize-p nil)
        (commit-state-db-to-chain-store
         source (block-hash grandchild) grandchild-state)
        (let ((before (staged-import-test-database-snapshot database)))
          (signals block-validation-error
            (node-store-forward-staged-import-block
             source database grandchild
             :stage :headers :chain-config config))
          (is (equalp before
                      (staged-import-test-database-snapshot database))))
        (is (not
             (staged-import-test-record-present-p
              database :staged-header
              (hash32-bytes (block-hash grandchild)))))
        (let ((state (node-store-validate-staged-import database)))
          (is (staged-import-test-progress-at-block-p
               (node-store-staged-import-state-target state)
               anchor)))))))

(deftest node-store-staged-import-malformed-control-fails-closed
  (:layer :integration :module :persistence)
  (dolist (mutator
           (list
            (lambda (record branch-b)
              (declare (ignore record branch-b))
              #(#xff))
            (lambda (record branch-b)
              (declare (ignore branch-b))
              (staged-import-test-control-with-version record 2))
            (lambda (record branch-b)
              (declare (ignore branch-b))
              (staged-import-test-control-with-empty-progresses record))
            (lambda (record branch-b)
              (staged-import-test-control-with-stage-hash
               record :bodies branch-b))))
    (let ((database (make-forkchoice-delta-test-database)))
      (multiple-value-bind
          (source config anchor branch-a branch-b
           transaction-a transaction-b)
          (staged-import-test-prepare database)
        (staged-import-test-forward-stages
         source config database branch-a (node-store-staged-import-stages))
        (let ((valid-record
                (kv-get-chain-record database :stage-progress "local")))
          (kv-put-chain-record
           database :stage-progress "local"
           (funcall mutator valid-record branch-b)))
        (forkchoice-delta-test-reset-operations database)
        (let ((before (staged-import-test-database-snapshot database)))
          (signals block-validation-error
            (node-store-staged-import-next-action database))
          (is (null
               (forkchoice-delta-test-database-applied-operation-batches
                database)))
          (is (equalp before
                      (staged-import-test-database-snapshot database))))
        (staged-import-test-assert-public-anchor-only
         database anchor transaction-a transaction-b)))))
