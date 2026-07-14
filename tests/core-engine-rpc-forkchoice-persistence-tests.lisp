(in-package #:ethereum-lisp.test)

(defun forkchoice-persistence-test-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun forkchoice-persistence-test-state-object
    (head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (list (cons "headBlockHash" (hash32-to-hex head))
        (cons "safeBlockHash" (hash32-to-hex safe))
        (cons "finalizedBlockHash" (hash32-to-hex finalized))))

(defun forkchoice-persistence-test-request
    (id head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_forkchoiceUpdatedV1")
        (cons "params"
              (list (forkchoice-persistence-test-state-object
                     head :safe safe :finalized finalized)))))

(defun forkchoice-persistence-test-block (parent number)
  (make-block
   :header
   (make-block-header
    :parent-hash (if parent (block-hash parent) (zero-hash32))
    :number number
    :timestamp number
    :gas-limit 30000000)))

(deftest engine-rpc-forkchoice-persistence-runs-after-live-state-publication
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config))
         (genesis (forkchoice-persistence-test-block nil 0))
         (head (forkchoice-persistence-test-block genesis 1))
         (calls 0)
         observed-head
         observed-safe
         observed-finalized)
    (engine-payload-store-put-block store genesis :state-available-p t)
    (engine-payload-store-put-block store head :state-available-p t)
    (let* ((response
             (engine-rpc-handle-request
              (forkchoice-persistence-test-request
               51 (block-hash head)
               :safe (block-hash genesis)
               :finalized (block-hash genesis))
              store
              config
              :forkchoice-persistence-function
              (lambda (current-store)
                (incf calls)
                (setf observed-head
                      (block-hash (chain-store-head-block current-store))
                      observed-safe
                      (block-hash (chain-store-safe-block current-store))
                      observed-finalized
                      (block-hash
                       (chain-store-finalized-block current-store))))))
           (result (forkchoice-persistence-test-field response "result"))
           (payload-status
             (forkchoice-persistence-test-field result "payloadStatus")))
      (is (= 51 (forkchoice-persistence-test-field response "id")))
      (is (string= +payload-status-valid+
                   (forkchoice-persistence-test-field payload-status "status")))
      (is (= 1 calls))
      (is (bytes= (hash32-bytes observed-head)
                  (hash32-bytes (block-hash head))))
      (is (bytes= (hash32-bytes observed-safe)
                  (hash32-bytes (block-hash genesis))))
      (is (bytes= (hash32-bytes observed-finalized)
                  (hash32-bytes (block-hash genesis))))
      (is (bytes= (hash32-bytes (chain-store-canonical-hash store 1))
                  (hash32-bytes (block-hash head))))
      (let* ((unknown-hash
               (hash32-from-hex
                "0x1111111111111111111111111111111111111111111111111111111111111111"))
             (syncing-response
               (engine-rpc-handle-request
                (forkchoice-persistence-test-request 54 unknown-hash)
                store
                config
                :forkchoice-persistence-function
                (lambda (current-store)
                  (declare (ignore current-store))
                  (incf calls))))
             (syncing-status
               (forkchoice-persistence-test-field
                (forkchoice-persistence-test-field syncing-response "result")
                "payloadStatus")))
        (is (string= +payload-status-syncing+
                     (forkchoice-persistence-test-field syncing-status
                                                        "status")))
        (is (= 1 calls))))))

(deftest engine-rpc-forkchoice-persistence-failure-rolls-back-and-is-internal
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config))
         (genesis (forkchoice-persistence-test-block nil 0))
         (old-head (forkchoice-persistence-test-block genesis 1))
         (new-head (forkchoice-persistence-test-block old-head 2))
         observed-head
         observed-safe)
    (engine-payload-store-put-block store genesis :state-available-p t)
    (engine-payload-store-put-block store old-head :state-available-p t)
    (engine-payload-store-put-block store new-head :state-available-p t)
    (engine-rpc-handle-request
     (forkchoice-persistence-test-request
      52 (block-hash old-head)
      :safe (block-hash genesis)
      :finalized (block-hash genesis))
     store config)
    (let* ((response
             (engine-rpc-handle-request
              (forkchoice-persistence-test-request
               53 (block-hash new-head)
               :safe (block-hash old-head)
               :finalized (block-hash genesis))
              store
              config
              :forkchoice-persistence-function
              (lambda (current-store)
                (setf observed-head
                      (block-hash (chain-store-head-block current-store))
                      observed-safe
                      (block-hash (chain-store-safe-block current-store)))
                (error "simulated database failure"))))
           (rpc-error (forkchoice-persistence-test-field response "error")))
      (is (= 53 (forkchoice-persistence-test-field response "id")))
      (is (= -32603
             (forkchoice-persistence-test-field rpc-error "code")))
      (is (string= "Internal error"
                   (forkchoice-persistence-test-field rpc-error "message")))
      (is (not (forkchoice-persistence-test-field response "result")))
      (is (bytes= (hash32-bytes observed-head)
                  (hash32-bytes (block-hash new-head))))
      (is (bytes= (hash32-bytes observed-safe)
                  (hash32-bytes (block-hash old-head))))
      (is (bytes= (hash32-bytes (block-hash
                                 (chain-store-head-block store)))
                  (hash32-bytes (block-hash old-head))))
      (is (bytes= (hash32-bytes (block-hash
                                 (chain-store-safe-block store)))
                  (hash32-bytes (block-hash genesis))))
      (is (bytes= (hash32-bytes (block-hash
                                 (chain-store-finalized-block store)))
                  (hash32-bytes (block-hash genesis))))
      (is (bytes= (hash32-bytes (chain-store-canonical-hash store 1))
                  (hash32-bytes (block-hash old-head))))
      (is (not (chain-store-canonical-hash store 2))))))

(deftest engine-rpc-new-payload-remains-noncanonical-when-live-persistence-fails
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
         (parent-block
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
         (child-block
           (execute-signed-block
            child-state
            '()
            :expected-chain-id 1
            :header
            (make-block-header
             :parent-hash (block-hash parent-block)
             :beneficiary (zero-address)
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 30000000
             :timestamp 1
             :base-fee-per-gas 875000000)
            :chain-config config
            :withdrawals '())))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash parent-block) parent-state)
    (engine-rpc-handle-request
     (forkchoice-persistence-test-request
      55 (block-hash parent-block)
      :safe (block-hash parent-block)
      :finalized (block-hash parent-block))
     store config)
    (let* ((new-payload-response
             (engine-rpc-handle-request
              (engine-fixture-payload-request
               56
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
              store
              config
              :import-function #'execute-and-commit-engine-payload))
           (new-payload-status
             (forkchoice-persistence-test-field
              new-payload-response "result")))
      (is (string= +payload-status-valid+
                   (forkchoice-persistence-test-field new-payload-status
                                                      "status"))))
    (is (engine-payload-store-known-block store (block-hash child-block)))
    (is (chain-store-state-available-p store (block-hash child-block)))
    (is (not (chain-store-canonical-hash store 1)))
    (is (bytes= (hash32-bytes (block-hash
                               (chain-store-head-block store)))
                (hash32-bytes (block-hash parent-block))))
    (let* ((forkchoice-response
             (engine-rpc-handle-request
              (forkchoice-persistence-test-request
               57 (block-hash child-block)
               :safe (block-hash parent-block)
               :finalized (block-hash parent-block))
              store
              config
              :forkchoice-persistence-function
              (lambda (current-store)
                (declare (ignore current-store))
                (error "simulated database failure"))))
           (rpc-error
             (forkchoice-persistence-test-field forkchoice-response "error")))
      (is (= -32603
             (forkchoice-persistence-test-field rpc-error "code")))
      (is (not (forkchoice-persistence-test-field forkchoice-response
                                                  "result"))))
    (is (not (chain-store-canonical-hash store 1)))
    (is (bytes= (hash32-bytes (block-hash
                               (chain-store-head-block store)))
                (hash32-bytes (block-hash parent-block))))
    (is (bytes= (hash32-bytes (block-hash
                               (chain-store-safe-block store)))
                (hash32-bytes (block-hash parent-block))))
    (is (bytes= (hash32-bytes (block-hash
                               (chain-store-finalized-block store)))
                (hash32-bytes (block-hash parent-block))))
    (is (engine-payload-store-known-block store (block-hash child-block)))
    (is (chain-store-state-available-p store (block-hash child-block)))))

(deftest rpc-context-rejects-non-function-store-callbacks
  (signals block-validation-error
    (ethereum-lisp.rpc:make-rpc-context
     (make-engine-payload-memory-store)
     (make-chain-config)
     :forkchoice-persistence-function 17))
  (signals block-validation-error
    (ethereum-lisp.rpc:make-rpc-context
     (make-engine-payload-memory-store)
     (make-chain-config)
     :request-guard-function 17)))
