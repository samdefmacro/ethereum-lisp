(in-package #:ethereum-lisp.test)

(defun new-payload-persistence-test-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun new-payload-persistence-test-request (id block &key (version 2))
  (let ((payload
          (execution-payload-envelope-execution-payload
           (block-to-executable-data block))))
    (list (cons "jsonrpc" "2.0")
          (cons "id" id)
          (cons "method" (format nil "engine_newPayloadV~D" version))
          (cons "params"
                (list (engine-rpc-executable-data-object payload))))))

(defun new-payload-persistence-test-fixture ()
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
    (chain-store-set-canonical-head
     store
     (block-hash parent-block)
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config)
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash parent-block)
      :safe-block-hash (block-hash parent-block)
      :finalized-block-hash (block-hash parent-block)))
    (values store config parent-block child-block)))

(defun new-payload-persistence-test-status (response)
  (new-payload-persistence-test-field response "result"))

(deftest engine-rpc-new-payload-persistence-runs-after-valid-candidate-publication
  (multiple-value-bind (store config parent-block child-block)
      (new-payload-persistence-test-fixture)
    (let ((calls 0)
          observed-block-hash
          observed-known-p
          observed-state-available-p
          observed-canonical-hash
          observed-head-hash)
      (let* ((response
               (engine-rpc-handle-request
                (new-payload-persistence-test-request 61 child-block)
                store
                config
                :import-function #'execute-and-commit-engine-payload
                :new-payload-persistence-function
                (lambda (current-store candidate)
                  (incf calls)
                  (setf observed-block-hash (block-hash candidate)
                        observed-known-p
                        (not (null
                              (engine-payload-store-known-block
                               current-store (block-hash candidate))))
                        observed-state-available-p
                        (chain-store-state-available-p
                         current-store (block-hash candidate))
                        observed-canonical-hash
                        (chain-store-canonical-hash current-store 1)
                        observed-head-hash
                        (block-hash
                         (chain-store-head-block current-store))))))
             (status (new-payload-persistence-test-status response)))
        (is (string= +payload-status-valid+
                     (new-payload-persistence-test-field status "status")))
        (is (= 1 calls))
        (is (bytes= (hash32-bytes observed-block-hash)
                    (hash32-bytes (block-hash child-block))))
        (is observed-known-p)
        (is observed-state-available-p)
        (is (null observed-canonical-hash))
        (is (bytes= (hash32-bytes observed-head-hash)
                    (hash32-bytes (block-hash parent-block))))
        (is (engine-payload-store-known-block
             store (block-hash child-block)))
        (is (chain-store-state-available-p store (block-hash child-block)))
        (is (null (chain-store-canonical-hash store 1)))
        (is (bytes= (hash32-bytes
                     (block-hash (chain-store-head-block store)))
                    (hash32-bytes (block-hash parent-block))))))))

(deftest engine-rpc-new-payload-persistence-failure-rolls-back-candidate
  (multiple-value-bind (store config parent-block child-block)
      (new-payload-persistence-test-fixture)
    (let ((calls 0)
          observed-known-p
          observed-state-available-p)
      (let* ((response
               (engine-rpc-handle-request
                (new-payload-persistence-test-request 62 child-block)
                store
                config
                :import-function #'execute-and-commit-engine-payload
                :new-payload-persistence-function
                (lambda (current-store candidate)
                  (incf calls)
                  (setf observed-known-p
                        (not (null
                              (engine-payload-store-known-block
                               current-store (block-hash candidate))))
                        observed-state-available-p
                        (chain-store-state-available-p
                         current-store (block-hash candidate)))
                  (error "simulated candidate persistence failure"))))
             (rpc-error
               (new-payload-persistence-test-field response "error")))
        (is (= 62 (new-payload-persistence-test-field response "id")))
        (is (= -32603
               (new-payload-persistence-test-field rpc-error "code")))
        (is (string= "Internal error"
                     (new-payload-persistence-test-field rpc-error
                                                         "message")))
        (is (null (new-payload-persistence-test-field response "result")))
        (is (= 1 calls))
        (is observed-known-p)
        (is observed-state-available-p)
        (is (null
             (engine-payload-store-known-block store (block-hash child-block))))
        (is (not
             (chain-store-state-available-p store (block-hash child-block))))
        (is (null
             (engine-payload-store-invalid-block store (block-hash child-block))))
        (is (null (chain-store-canonical-hash store 1)))
        (is (bytes= (hash32-bytes
                     (block-hash (chain-store-head-block store)))
                    (hash32-bytes (block-hash parent-block))))))))

(deftest engine-rpc-new-payload-persistence-skips-syncing-and-invalid
  (let* ((config (make-chain-config :london-block 0))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (parent-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 41
             :gas-limit 50000
             :gas-used 25000
             :timestamp 98
             :base-fee-per-gas 100)))
         (invalid-child-block
           (make-block
            :header
            (make-block-header
             :parent-hash (block-hash parent-block)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 42
             :gas-limit 50000
             :gas-used 0
             :timestamp 98
             :base-fee-per-gas 100)))
         (unknown-parent
           (hash32-from-hex
            "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (syncing-block
           (make-block
            :header
            (make-block-header
             :parent-hash unknown-parent
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 42
             :gas-limit 50000
             :gas-used 0
             :timestamp 99
             :base-fee-per-gas 100)))
         (store (make-engine-payload-memory-store))
         (calls 0)
         (callback
           (lambda (current-store candidate)
             (declare (ignore current-store candidate))
             (incf calls))))
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (let* ((syncing-response
             (engine-rpc-handle-request
              (new-payload-persistence-test-request
               63 syncing-block :version 1)
              store config
              :new-payload-persistence-function callback))
           (syncing-status
             (new-payload-persistence-test-status syncing-response)))
      (is (string= +payload-status-syncing+
                   (new-payload-persistence-test-field syncing-status
                                                       "status")))
      (is (= 0 calls)))
    (let* ((invalid-response
             (engine-rpc-handle-request
              (new-payload-persistence-test-request
               64 invalid-child-block :version 1)
              store config
              :new-payload-persistence-function callback))
           (invalid-status
             (new-payload-persistence-test-status invalid-response)))
      (is (string= +payload-status-invalid+
                   (new-payload-persistence-test-field invalid-status
                                                       "status")))
      (is (= 0 calls)))))

(deftest engine-rpc-new-payload-persistence-runs-for-known-valid-replay
  (multiple-value-bind (store config parent-block child-block)
      (new-payload-persistence-test-fixture)
    (declare (ignore parent-block))
    (let ((calls 0)
          (observed-hashes '()))
      (let ((callback
              (lambda (current-store candidate)
                (declare (ignore current-store))
                (incf calls)
                (push (block-hash candidate) observed-hashes))))
        (dolist (id '(65 66))
          (let* ((response
                   (engine-rpc-handle-request
                    (new-payload-persistence-test-request id child-block)
                    store
                    config
                    :import-function #'execute-and-commit-engine-payload
                    :new-payload-persistence-function callback))
                 (status (new-payload-persistence-test-status response)))
            (is (string= +payload-status-valid+
                         (new-payload-persistence-test-field status "status")))))
        (is (= 2 calls))
        (is (= 2 (length observed-hashes)))
        (dolist (observed-hash observed-hashes)
          (is (bytes= (hash32-bytes observed-hash)
                      (hash32-bytes (block-hash child-block)))))))))

(deftest rpc-context-rejects-non-function-new-payload-persistence-callback
  (signals block-validation-error
    (ethereum-lisp.rpc:make-rpc-context
     (make-engine-payload-memory-store)
     (make-chain-config)
     :new-payload-persistence-function 17)))
