(in-package #:ethereum-lisp.test)

(defclass block-import-read-count-database (memory-key-value-database)
  ((get-count :initform 0 :accessor block-import-read-count-database-get-count)))

(defmethod kv-get :around
    ((database block-import-read-count-database) key &optional default)
  (declare (ignore key default))
  (incf (block-import-read-count-database-get-count database))
  (call-next-method))

(defun block-import-test-fixture ()
  (let* ((store (make-engine-payload-memory-store))
         (config
           (make-chain-config :chain-id 1
                              :byzantium-block 0
                              :constantinople-block 0
                              :petersburg-block 0
                              :berlin-block 0
                              :london-block 0
                              :shanghai-time 0))
         (parent-state (make-state-db))
         (parent
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary (zero-address)
             :state-root (state-db-root parent-state)
             :mix-hash (zero-hash32)
             :number 0
             :gas-limit 30000000
             :timestamp 0
             :base-fee-per-gas 1000000000
             :withdrawals-root (withdrawal-list-root '()))))
         (child-state (state-db-copy parent-state))
         (child
           (execute-signed-block
            child-state
            '()
            :expected-chain-id 1
            :header
            (make-block-header
             :parent-hash (block-hash parent)
             :beneficiary (zero-address)
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 30000000
             :timestamp 1
             :base-fee-per-gas 875000000)
            :chain-config config
            :withdrawals '())))
    (engine-payload-store-put-block store parent :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash parent) parent-state)
    (chain-store-set-canonical-head
     store
     (block-hash parent)
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config)
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash parent)
      :safe-block-hash (block-hash parent)
      :finalized-block-hash (block-hash parent)))
    (values store config parent child)))

(defun block-import-test-payload (block)
  (execution-payload-envelope-execution-payload
   (block-to-executable-data block)))

(deftest block-import-private-candidate-stays-detached
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (multiple-value-bind (candidate receipts)
        (build-private-block-candidate store child config)
      (is (hash32= (block-hash child) (block-hash candidate)))
      (is (null receipts)))
    (is (null (chain-store-known-block store (block-hash child))))
    (is (not (chain-store-state-available-p store (block-hash child))))
    (is (null (chain-store-canonical-hash store 1)))
    (is (hash32= (block-hash parent)
                 (block-hash (chain-store-head-block store))))))

(deftest block-import-private-builder-rolls-back-accidental-publication
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (let ((builder-calls 0))
      (multiple-value-bind (candidate receipts)
          (build-private-block-candidate
           store
           (lambda ()
             (incf builder-calls)
             ;; A trusted builder should be detached.  This intentional
             ;; contract violation proves that the service still cannot leak
             ;; candidate/state/canonical visibility before newPayload.
             (engine-payload-store-put-block
              store child :state-available-p t)
             (is (chain-store-known-block store (block-hash child)))
             (is (chain-store-state-available-p store (block-hash child)))
             (is (chain-store-canonical-hash store 1))
             (values child nil))
           config)
        (is (hash32= (block-hash child) (block-hash candidate)))
        (is (null receipts)))
      (is (= 1 builder-calls)))
    (is (null (chain-store-known-block store (block-hash child))))
    (is (not (chain-store-state-available-p store (block-hash child))))
    (is (null (chain-store-canonical-hash store 1)))
    (is (hash32= (block-hash parent)
                 (block-hash (chain-store-head-block store))))))

(deftest block-import-private-direct-builder-preserves-pending-storage-trie
  (multiple-value-bind (source config parent child)
      (block-import-test-fixture)
    (let* ((database (make-memory-key-value-database))
           (address (make-address (make-byte-vector 20 :initial-element 17)))
           (slot (make-hash32 (make-byte-vector 32 :initial-element 23)))
           (proof-key (ethereum-lisp.state::state-db-storage-proof-key slot))
           (parent-hash (block-hash parent)))
      (node-store-export-to-kv source database)
      (let* ((direct (make-database-engine-payload-store database))
             (pending-state (chain-store-state-db direct parent-hash)))
        (state-db-set-storage pending-state address slot 41)
        (commit-state-db-to-chain-store direct parent-hash pending-state)
        (let* ((pending-tries
                 (ethereum-lisp.chain-store:chain-store-state-persistence-tries
                  direct parent-hash))
               (pending-storage-trie (second pending-tries))
               (root-before (copy-seq (mpt-root-hash pending-storage-trie))))
          (is (= 2 (length pending-tries)))
          (multiple-value-bind (value-before present-before-p)
              (mpt-get pending-storage-trie proof-key)
            (is present-before-p)
            (multiple-value-bind (candidate receipts)
                (build-private-block-candidate
                 direct
                 (lambda ()
                   (let ((private-state
                           (chain-store-state-db direct parent-hash)))
                     (state-db-set-storage private-state address slot 42)
                     ;; Force both the storage and account trie wrappers to
                     ;; incorporate the private write before rollback.
                     (state-db-root private-state))
                   (values child nil))
                 config)
              (is (hash32= (block-hash child) (block-hash candidate)))
              (is (null receipts)))
            (is (bytes= root-before (mpt-root-hash pending-storage-trie)))
            (multiple-value-bind (value-after present-after-p)
                (mpt-get pending-storage-trie proof-key)
              (is present-after-p)
              (is (bytes= value-before value-after)))))))))

(deftest block-import-private-candidate-rejects-invalid-header
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (setf (block-header-timestamp (block-header child)) 0)
    (signals block-validation-error
      (build-private-block-candidate store child config))
    (is (null (chain-store-known-block store (block-hash child))))
    (is (not (chain-store-state-available-p store (block-hash child))))))

(deftest block-import-candidate-validates-executes-and-stays-noncanonical
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (let ((calls 0)
          (callback-saw-complete-candidate-p nil))
      (multiple-value-bind (candidate receipts)
          (import-block-candidate
           store child config
           :source :staged
           :durability-function
           (lambda (callback-store callback-candidate)
             (incf calls)
             (setf callback-saw-complete-candidate-p
                   (and (chain-store-known-block
                         callback-store (block-hash callback-candidate))
                        (chain-store-state-available-p
                         callback-store (block-hash callback-candidate))
                        (null (chain-store-canonical-hash callback-store 1))))))
        (is (hash32= (block-hash child) (block-hash candidate)))
        (is (null receipts)))
      (is (= 1 calls))
      (is callback-saw-complete-candidate-p)
      (is (chain-store-state-available-p store (block-hash child)))
      (is (null (chain-store-canonical-hash store 1)))
      (is (hash32= (block-hash parent)
                   (block-hash (chain-store-head-block store)))))))

(deftest block-import-candidate-rejects-before-mutation
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    ;; Timestamp equality is a deterministic header violation.  The valid
    ;; fixture above is the positive control that this path can import.
    (setf (block-header-timestamp (block-header child)) 0)
    (let ((invalid-hash (block-hash child))
          (calls 0))
      (signals block-validation-error
        (import-block-candidate
         store child config
         :durability-function
         (lambda (callback-store candidate)
           (declare (ignore callback-store candidate))
           (incf calls))))
      (is (= 0 calls))
      (is (null (chain-store-known-block store invalid-hash)))
      (is (not (chain-store-state-available-p store invalid-hash))))))

(deftest block-import-candidate-rejects-sidecar-for-another-block
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proof (make-byte-vector +kzg-proof-size+))
           (sidecar
             (make-blob-sidecar
              :blobs (list blob)
              :commitments (list commitment)
              :proofs (list proof))))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (bytes= proof verified-proof)))))
        (signals block-validation-error
          (import-block-candidate store child config :sidecar sidecar)))
      (is (null (chain-store-known-block store (block-hash child)))))))

(deftest block-import-p2p-bundle-failures-do-not-poison-block-hash
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((wrong-body
             (ethereum-lisp.blocks:make-block-from-parts
              :header (block-header child)
              :transactions (block-transactions child)
              :ommers (block-ommers child)
              :withdrawals
              (list (make-withdrawal
                     :index 0 :validator-index 0
                     :address (zero-address) :amount 1))
              :withdrawals-present-p t))
           (blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proof (make-byte-vector +kzg-proof-size+))
           (wrong-sidecar
             (make-blob-sidecar
              :blobs (list blob)
              :commitments (list commitment)
              :proofs (list proof))))
      ;; Both bundles claim the immutable header hash, but neither is evidence
      ;; that the header itself is invalid. A later honest peer must still be
      ;; able to admit the correct body.
      (signals block-validation-error
        (import-p2p-block-candidate store wrong-body config))
      (is (null (engine-payload-store-invalid-block
                 store (block-hash child))))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (bytes= proof verified-proof)))))
        (signals block-validation-error
          (import-p2p-block-candidate
           store child config :sidecar wrong-sidecar)))
      (is (null (engine-payload-store-invalid-block
                 store (block-hash child))))
      (multiple-value-bind (status candidate receipts)
          (import-p2p-block-candidate store child config)
        (is (string= +payload-status-valid+
                     (payload-status-status status)))
        (is (hash32= (block-hash child) (block-hash candidate)))
        (is (null receipts))))))

(deftest block-import-p2p-request-bundle-mismatch-does-not-poison-header
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent child))
    ;; Exercise the typed P2P service boundary without needing execution: a
    ;; valid Prague block with an unknown parent is accepted into gap-fill.
    (setf (chain-config-prague-time config) 0)
    (let* ((missing-parent
             (make-hash32 (make-byte-vector 32 :initial-element 71)))
           (header
             (make-block-header
              :parent-hash missing-parent
              :beneficiary (zero-address)
              :state-root +empty-trie-hash+
              :mix-hash (zero-hash32)
              :number 2
              :gas-limit 30000000
              :timestamp 2
              :base-fee-per-gas 875000000))
           (correct
             (make-block
              :header header
              :transactions '()
              :receipts '()
              :ommers '()
              :withdrawals '()
              :requests '()))
           (wrong
             (ethereum-lisp.chain-store:engine-payload-store-copy-block
              correct))
           (hash (block-hash correct)))
      (setf (block-requests wrong) (list #(#x01 #xaa)))
      ;; The peer-owned requests side-data is checked before INVALID
      ;; classification. It cannot poison the immutable header it names.
      (signals block-validation-error
        (import-p2p-block-candidate store wrong config))
      (is (null (engine-payload-store-invalid-block store hash)))
      (is (null (engine-payload-store-remote-block store hash)))
      ;; Positive control: the same header with its committed requests passes
      ;; the outer preflight and becomes a durable gap-fill candidate.
      (multiple-value-bind (status candidate receipts)
          (import-p2p-block-candidate store correct config)
        (is (string= +payload-status-syncing+
                     (payload-status-status status)))
        (is (hash32= hash (block-hash candidate)))
        (is (null receipts)))
      (is (engine-payload-store-remote-block store hash)))))

(deftest block-import-p2p-known-snap-skeleton-is-a-buffering-no-op
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    ;; A SNAP pivot installs headers/bodies before the matching state.  A
    ;; duplicate eth delivery must remain SYNCING without trying to export the
    ;; known block as a remote buffered candidate.
    (engine-payload-store-put-block store child :state-available-p nil)
    (let ((durability-calls 0))
      (multiple-value-bind (status candidate receipts)
          (import-p2p-block-candidate
           store child config
           :durability-function
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (incf durability-calls)))
        (is (string= +payload-status-syncing+
                     (payload-status-status status)))
        (is (null candidate))
        (is (null receipts)))
      (is (= 0 durability-calls))
      (is (null (engine-payload-store-remote-block
                 store (block-hash child)))))))

(deftest block-import-p2p-committed-invalid-ommer-is-cached-invalid
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((committed-invalid
             (ethereum-lisp.chain-store:engine-payload-store-copy-block child))
           (ommer
             (make-block-header
              :parent-hash (zero-hash32)
              :beneficiary (zero-address)
              :number 0
              :gas-limit 30000000
              :timestamp 0
              :difficulty 0
              :mix-hash (zero-hash32)))
           (ommers (list ommer)))
      ;; Unlike a real header paired with a wrong downloaded body, this header
      ;; itself commits the non-empty post-Merge ommer list.  The deterministic
      ;; consensus failure therefore belongs to this block hash and is safe to
      ;; cache as INVALID.
      (setf (block-ommers committed-invalid) ommers
            (block-header-ommers-hash (block-header committed-invalid))
            (ommers-hash ommers))
      (let ((invalid-hash (block-hash committed-invalid)))
        (loop repeat 2
              do (multiple-value-bind (status candidate receipts)
                     (import-p2p-block-candidate
                      store committed-invalid config)
                   (is (string= +payload-status-invalid+
                                (payload-status-status status)))
                   (is (null candidate))
                   (is (null receipts))))
        (is (engine-payload-store-invalid-block store invalid-hash))
        (is (null (engine-payload-store-invalid-block
                   store (block-hash child))))))))

(deftest block-import-durability-nonlocal-exit-rolls-back-every-view
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (engine-payload-store-enable-durable-cache-change-tracking store)
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store child :now 10)
    (let* ((chain-store
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store))
           (deletions
             (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
              chain-store))
           (result
             (catch 'abort-import
               (build-import-and-publish-block
                store child config
                :authority :local-dev
                :local-dev-authorized-p t
                :durability-function
                (lambda (callback-store transition)
                  (is (typep transition
                             'ethereum-lisp.canonical-chain:canonical-chain-transition))
                  (is (chain-store-known-block
                       callback-store (block-hash child)))
                  (is (chain-store-state-available-p
                       callback-store (block-hash child)))
                  (is (hash32= (block-hash child)
                               (chain-store-canonical-hash callback-store 1)))
                  (is (hash32= (block-hash child)
                               (block-hash
                                (chain-store-head-block callback-store))))
                  (is (= 1 (hash-table-count deletions)))
                  (throw 'abort-import :aborted)))
               :returned)))
      (is (eq :aborted result))
      (is (null (chain-store-known-block store (block-hash child))))
      (is (not (chain-store-state-available-p store (block-hash child))))
      (is (null (chain-store-canonical-hash store 1)))
      (is (hash32= (block-hash parent)
                   (block-hash (chain-store-head-block store))))
      (is (engine-payload-store-remote-block
           store (block-hash child) :now 10))
      (is (= 0 (hash-table-count deletions))))))

(deftest block-import-durability-failure-rolls-back-without-invalid-verdict
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (signals ethereum-lisp.validation:storage-error
      (import-executable-payload
       store 2 (block-import-test-payload child) config
       :durability-function
       (lambda (callback-store candidate)
         (is (chain-store-state-available-p
              callback-store (block-hash candidate)))
         (error 'ethereum-lisp.validation:storage-error
                :message "Injected candidate durability failure"))))
    (is (null (chain-store-known-block store (block-hash child))))
    (is (not (chain-store-state-available-p store (block-hash child))))
    (is (null (engine-payload-store-invalid-block
               store (block-hash child))))))

(deftest block-import-p2p-local-state-corruption-is-not-an-invalid-verdict
  (multiple-value-bind (store config genesis child)
      (block-import-test-fixture)
    (declare (ignore genesis))
    (import-block-candidate store child config)
    (let* ((child-hash (block-hash child))
           (grandchild
             (execute-signed-block
              (chain-store-state-db store child-hash)
              '()
              :expected-chain-id 1
              :header
              (make-block-header
               :parent-hash child-hash
               :beneficiary (zero-address)
               :mix-hash (zero-hash32)
               :number 2
               :gas-limit 30000000
               :timestamp 2
               :base-fee-per-gas
               (expected-base-fee-per-gas (block-header child)))
              :chain-config config
              :withdrawals '()))
           (database (make-memory-key-value-database)))
      (node-store-export-to-kv store database)
      ;; Keep the parent block but corrupt only its durable state marker. The
      ;; direct provider can start because canonical genesis remains healthy;
      ;; the error is encountered when the peer child asks for parent state.
      (kv-put-chain-record
       database :state-history (hash32-bytes child-hash) #(1))
      (let ((direct (make-database-engine-payload-store database)))
        (signals ethereum-lisp.validation:storage-error
          (import-p2p-block-candidate direct grandchild config))
        (is (null (engine-payload-store-invalid-block
                   direct (block-hash grandchild))))
        (is (null (chain-store-known-block
                   direct (block-hash grandchild))))))))

(deftest block-import-p2p-durable-canonical-index-corruption-is-not-invalid
  (multiple-value-bind (source config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let ((database (make-memory-key-value-database)))
      (node-store-export-to-kv source database)
      (let ((direct (make-database-engine-payload-store database))
            (executor-calls 0))
        ;; Corrupt after construction so startup remains a positive control.
        ;; A real executor may consult canonical history while importing a
        ;; valid candidate; local index corruption must never become a portable
        ;; INVALID verdict for that candidate hash.
        (kv-put-chain-record database :canonical-hash 0 #(1))
        (signals ethereum-lisp.validation:storage-error
          (import-p2p-block-candidate
           direct child config
           :import-function
           (lambda (executor-store block executor-config)
             (incf executor-calls)
             (chain-store-canonical-hash executor-store 0)
             (execute-and-commit-engine-payload
              executor-store block executor-config))))
        (is (= 1 executor-calls))
        (is (null (engine-payload-store-invalid-block
                   direct (block-hash child))))
        (is (null (chain-store-known-block
                   direct (block-hash child))))))))

(deftest block-import-executable-payload-persists-valid-known-replay
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((calls 0)
           (executor-calls 0)
           (payload (block-import-test-payload child))
           (executor
             (lambda (executor-store block executor-config)
               (incf executor-calls)
               (execute-and-commit-engine-payload
                executor-store block executor-config)))
           (durability
             (lambda (callback-store candidate)
               ;; Exactly two arguments proves legacy callback compatibility.
               (incf calls)
               (is (chain-store-state-available-p
                    callback-store (block-hash candidate))))))
      (dotimes (index 2)
        (declare (ignore index))
        (multiple-value-bind (status candidate receipts)
            (import-executable-payload
             store 2 payload config
             :source :engine
             :import-function executor
             :durability-function durability)
          (is (string= +payload-status-valid+
                       (payload-status-status status)))
          (is (hash32= (block-hash child) (block-hash candidate)))
          (is (null receipts))))
      (is (= 2 calls))
      ;; The known/state replay still validates, but does not re-execute.
      (is (= 1 executor-calls)))))

(deftest block-import-known-replay-does-no-store-read-after-durability
  (multiple-value-bind (source config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (import-block-candidate source child config)
    (let ((database (make-instance 'block-import-read-count-database)))
      (node-store-export-to-kv source database)
      (let* ((direct (make-database-engine-payload-store database))
             (payload (block-import-test-payload child))
             (reads-at-durability nil))
        (setf (block-import-read-count-database-get-count database) 0)
        (multiple-value-bind (status candidate receipts)
            (import-executable-payload
             direct 2 payload config
             :durability-function
             (lambda (callback-store callback-candidate)
               (declare (ignore callback-store callback-candidate))
               (setf reads-at-durability
                     (block-import-read-count-database-get-count database))))
          ;; The known replay receipt point-read is part of the candidate
          ;; computation and therefore precedes the final durability callback.
          (is (string= +payload-status-valid+
                       (payload-status-status status)))
          (is (hash32= (block-hash child) (block-hash candidate)))
          (is (null receipts))
          (is reads-at-durability)
          (is (= reads-at-durability
                 (block-import-read-count-database-get-count database))))))))

(deftest block-import-executable-known-replay-does-not-bypass-validation
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    ;; Seed the exact corrupt-store shape that the Engine memory status fast
    ;; path alone would classify VALID: known hash plus a state marker.  The
    ;; unified service must still notice the parent-equal timestamp.
    (setf (block-header-timestamp (block-header child)) 0)
    (engine-payload-store-put-block
     store child :state-available-p t :canonicalize-p nil)
    (signals block-validation-error
      (import-executable-payload
       store 2 (block-import-test-payload child) config))))

(deftest block-import-executable-payload-persists-buffered-progress
  (multiple-value-bind (fixture-store config parent child)
      (block-import-test-fixture)
    (declare (ignore fixture-store parent))
    (let ((store (make-engine-payload-memory-store))
          (buffered-observation nil)
          (extended-observation nil)
          (payload (block-import-test-payload child)))
      (multiple-value-bind (status candidate)
          (import-executable-payload
           store 2 payload config
           :source :p2p
           :durability-function
           (lambda (callback-store callback-candidate
                    &key source candidate-kind payload-status)
             (declare (ignore callback-store callback-candidate))
             (setf buffered-observation
                   (list source candidate-kind
                         (payload-status-status payload-status)))))
        (is (string= +payload-status-syncing+
                     (payload-status-status status)))
        (is (hash32= (block-hash child) (block-hash candidate))))
      (is (equal buffered-observation
                 (list :p2p :buffered +payload-status-syncing+)))
      (is (engine-payload-store-remote-block store (block-hash child)))
      (multiple-value-bind (status candidate)
          (import-executable-payload
           store 2 payload config
           :source :p2p
           :progress '(:next 1)
           :durability-function
           (lambda (callback-store callback-candidate
                    &key source candidate-kind payload-status progress)
             (declare (ignore callback-store callback-candidate))
             (setf extended-observation
                   (list source candidate-kind
                         (payload-status-status payload-status)
                         progress))))
        (declare (ignore candidate))
        (is (string= +payload-status-syncing+
                     (payload-status-status status))))
      (is (equal extended-observation
                 (list :p2p :buffered +payload-status-syncing+ '(:next 1)))))))

(deftest block-import-publication-enforces-authority-and-orders-durability
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (import-block-candidate store child config)
    (signals block-validation-error
      (publish-canonical-block
       store child config :authority :local-dev))
    (is (hash32= (block-hash parent)
                 (block-hash (chain-store-head-block store))))
    (let ((events '())
          (state
            (make-forkchoice-state
             :head-block-hash (block-hash child)
             :safe-block-hash (block-hash parent)
             :finalized-block-hash (block-hash parent))))
      (multiple-value-bind (head transition)
          (publish-canonical-block
           store child config
           :authority :engine-forkchoice
           :forkchoice-state state
           :now 77
           :finality-prune-function
           (lambda (callback-store &key now finalized-number)
             (declare (ignore callback-store))
             (is (= 77 now))
             (is (= 0 finalized-number))
             (push :prune events))
           :durability-function
           (lambda (callback-store callback-transition)
             ;; Exactly two arguments preserves the existing forkchoice adapter.
             (is (hash32= (block-hash child)
                          (block-hash
                           (chain-store-head-block callback-store))))
             (is (typep callback-transition
                        'ethereum-lisp.canonical-chain:canonical-chain-transition))
             (push :persist events)))
        (is (hash32= (block-hash child) (block-hash head)))
        (is (typep transition
                   'ethereum-lisp.canonical-chain:canonical-chain-transition)))
      (is (equal '(:prune :persist) (nreverse events)))
      (is (hash32= (block-hash child)
                   (block-hash (chain-store-head-block store)))))))

(deftest block-import-snap-pivot-is-bounded-authorized-and-nonfinal-target
  (multiple-value-bind (store config parent pivot)
      (block-import-test-fixture)
    (import-block-candidate store pivot config)
    (let* ((pivot-hash (block-hash pivot))
           (target
             (execute-signed-block
              (chain-store-state-db store pivot-hash)
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
           (callback-observation nil))
      (engine-payload-store-put-block
       store target :state-available-p nil :canonicalize-p nil)
      (signals block-validation-error
        (install-forkchoice-sync-pivot
         store pivot-hash target-hash config
         :durability-function
         (lambda (&rest ignored) (declare (ignore ignored)))))
      (is (hash32= (block-hash parent)
                   (chain-store-canonical-hash store 0)))
      (is (null (chain-store-canonical-hash store 1)))
      (multiple-value-bind (head transition)
          (install-forkchoice-sync-pivot
           store pivot-hash target-hash config
           :consensus-authorized-p t
           :durability-function
           (lambda (callback-store callback-transition
                    &key sync-pivot-target-hash)
             (setf callback-observation
                   (list
                    (hash32= pivot-hash
                             (chain-store-canonical-hash callback-store 1))
                    (hash32= target-hash sync-pivot-target-hash)
                    (= 1
                       (length
                        (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
                         callback-transition)))))))
        (is (hash32= pivot-hash (block-hash head)))
        (is (= 1
               (length
                (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
                 transition)))))
      (is (equal '(t t t) callback-observation))
      (is (= 1 (chain-store-head-number store)))
      (is (hash32= pivot-hash (chain-store-canonical-hash store 1)))
      ;; TARGET is only the Engine authorization anchor. A later ordinary
      ;; forkchoiceUpdated call publishes it after the tail is executed.
      (is (null (chain-store-canonical-hash store 2)))
      (is (not (chain-store-state-available-p store target-hash))))))

(deftest block-import-publication-revalidates-forkchoice-checkpoints
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (let* ((side-state (chain-store-state-db store (block-hash parent)))
           (side
             (execute-signed-block
              side-state
              '()
              :expected-chain-id 1
              :header
              (make-block-header
               :parent-hash (block-hash parent)
               :beneficiary (make-address
                             (make-byte-vector 20 :initial-element 1))
               :mix-hash (zero-hash32)
               :number 1
               :gas-limit 30000000
               :timestamp 2
               :base-fee-per-gas 875000000)
              :chain-config config
              :withdrawals '()))
           (stateless
             (ethereum-lisp.chain-store:engine-payload-store-copy-block side))
           (missing
             (make-hash32 (make-byte-vector 32 :initial-element 91))))
      ;; Give the copy its own hash, but deliberately publish no state marker.
      (setf (block-header-extra-data (block-header stateless)) #(9))
      (import-block-candidate store child config)
      (import-block-candidate store side config)
      (engine-payload-store-put-block
       store stateless :state-available-p nil :canonicalize-p nil)
      (flet ((refuse (safe finalized)
               (signals block-validation-error
                 (publish-canonical-block
                  store child config
                  :authority :engine-forkchoice
                  :forkchoice-state
                  (make-forkchoice-state
                   :head-block-hash (block-hash child)
                   :safe-block-hash safe
                   :finalized-block-hash finalized)))
               (is (hash32= (block-hash parent)
                            (block-hash (chain-store-head-block store))))
               (is (hash32= (block-hash parent)
                            (chain-store-checkpoint-block-hash
                             (chain-store-safe-checkpoint store))))
               (is (null (chain-store-canonical-hash store 1)))))
        ;; Availability, ancestry, and safe/finalized ordering are authority
        ;; invariants of the service itself, not assumptions delegated to the
        ;; Engine RPC adapter.
        (refuse missing (block-hash parent))
        (refuse (block-hash stateless) (block-hash parent))
        (refuse (block-hash child) (block-hash stateless))
        (refuse (block-hash side) (block-hash parent))
        (refuse (block-hash parent) (block-hash child))))))

(deftest block-import-publication-durability-failure-rolls-back-view
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (import-block-candidate store child config)
    (let ((state
            (make-forkchoice-state
             :head-block-hash (block-hash child)
             :safe-block-hash (block-hash parent)
             :finalized-block-hash (block-hash parent))))
      (signals ethereum-lisp.validation:storage-error
        (publish-canonical-block
         store child config
         :authority :engine-forkchoice
         :forkchoice-state state
         :durability-function
         (lambda (callback-store transition)
           (declare (ignore callback-store transition))
           (error 'ethereum-lisp.validation:storage-error
                  :message "Injected canonical durability failure")))))
    (is (hash32= (block-hash parent)
                 (block-hash (chain-store-head-block store))))
    (is (hash32= (block-hash parent)
                 (chain-store-checkpoint-block-hash
                  (chain-store-head-checkpoint store))))
    (is (null (chain-store-canonical-hash store 1)))))

(deftest block-import-build-helper-is-one-authorized-rollback-boundary
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((builder-calls 0)
           (durability-calls 0)
           (builder
             (lambda ()
               (incf builder-calls)
               (values child nil))))
      (signals block-validation-error
        (build-import-and-publish-block store builder config))
      (is (= 1 builder-calls))
      (is (null (chain-store-known-block store (block-hash child))))
      (multiple-value-bind (head receipts transition)
          (build-import-and-publish-block
           store builder config
           :local-dev-authorized-p t
           :durability-function
           (lambda (callback-store callback-transition)
             (incf durability-calls)
             (is (hash32= (block-hash child)
                          (block-hash
                           (chain-store-head-block callback-store))))
             (is (typep callback-transition
                        'ethereum-lisp.canonical-chain:canonical-chain-transition))))
        (is (hash32= (block-hash child) (block-hash head)))
        (is (null receipts))
        (is (typep transition
                   'ethereum-lisp.canonical-chain:canonical-chain-transition)))
      (is (= 2 builder-calls))
      (is (= 1 durability-calls))
      (is (chain-store-state-available-p store (block-hash child)))
      (is (hash32= (block-hash child)
                   (block-hash (chain-store-head-block store)))))))

(deftest block-import-p2p-durability-validation-error-rolls-back-candidate
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (signals block-validation-error
      (import-p2p-block-candidate
       store child config
       :durability-function
       (lambda (callback-store candidate &key &allow-other-keys)
         (is (chain-store-state-available-p
              callback-store (block-hash candidate)))
         (ethereum-lisp.validation:block-validation-fail
          "Injected P2P persistence invariant failure"))))
    (is (null (chain-store-known-block store (block-hash child))))
    (is (not (chain-store-state-available-p store (block-hash child))))
    (is (null (engine-payload-store-invalid-block
               store (block-hash child))))))

(deftest block-import-p2p-invalid-cache-skips-repeat-execution-and-descendants
  (multiple-value-bind (store config parent child)
      (block-import-test-fixture)
    (declare (ignore parent))
    (let* ((executor-calls 0)
           (invalid-durability-calls 0)
           (executor
             (lambda (executor-store candidate executor-config)
               (declare (ignore executor-store candidate executor-config))
               (incf executor-calls)
               (error 'ethereum-lisp.execution:transaction-validation-error
                      :message "Injected deterministic transaction failure")))
           (durability
             (lambda (callback-store candidate
                      &key candidate-kind payload-status &allow-other-keys)
               (incf invalid-durability-calls)
               (is (eq :invalid candidate-kind))
               (is (string= +payload-status-invalid+
                            (payload-status-status payload-status)))
               (is (engine-payload-store-invalid-block
                    callback-store (block-hash candidate))))))
      (dotimes (attempt 2)
        (declare (ignore attempt))
        (multiple-value-bind (status candidate receipts)
            (import-p2p-block-candidate
             store child config :import-function executor
             :durability-function durability)
          (is (string= +payload-status-invalid+
                       (payload-status-status status)))
          (is (null candidate))
          (is (null receipts))))
      (is (= 1 executor-calls))
      (let ((descendant
              (make-block
               :header
               (make-block-header
                :parent-hash (block-hash child)
                :beneficiary (zero-address)
                :mix-hash (zero-hash32)
                :number 2
                :gas-limit 30000000
                :timestamp 2
                :base-fee-per-gas 765625000)
               :withdrawals '())))
        (multiple-value-bind (status candidate receipts)
            (import-p2p-block-candidate
             store descendant config :durability-function durability)
          (is (string= +payload-status-invalid+
                       (payload-status-status status)))
          (is (null candidate))
          (is (null receipts)))
        (is (null (engine-payload-store-remote-block
                   store (block-hash descendant))))
        (is (= 3 invalid-durability-calls))))))
