(defun smoke-gate-state-summary (suite-root required-p &key pinned-p)
  (let ((root (smoke-gate-call "execution-spec-tests-state-test-root"
                               suite-root)))
    (cond
      (root
       (smoke-gate-reject-empty-selected-root root "state_tests")
       (let* ((selectors
                (if pinned-p
                    (smoke-gate-variable
                     "+phase-a-eest-state-test-v5.4.0-case-names+")
                    (or (smoke-gate-call
                         "phase-a-eest-state-test-env-selectors"
                         root)
                        (smoke-gate-call
                         "discover-phase-a-eest-state-test-selectors"
                         root))))
              (cases
                (smoke-gate-call
                 "load-eest-state-test-root-cases"
                 root
                 :names selectors))
              (summary
                (smoke-gate-call
                 "validate-phase-a-eest-state-test-summary"
                 cases
                 :expected-names selectors))
              (executed (smoke-gate-execute-state-cases cases)))
         (smoke-gate-require-positive-field
          summary "count" "Phase A state_tests count")
         (smoke-gate-require-positive-field
          summary
          "transactionCombinationCount"
          "Phase A state_tests transaction-combination count")
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" (smoke-gate-field summary "count"))
          (cons "executedCount" executed)
          (cons "transactionCombinationCount"
                (smoke-gate-field summary "transactionCombinationCount"))
          (cons "selectorString"
                (smoke-gate-call
                 "phase-a-eest-state-test-selector-string"
                 selectors)))))
      (required-p
       (error "Phase A smoke gate requires an EEST state_tests root under ~A"
              suite-root))
      (t
       (list
        (cons "status" "missing")
        (cons "root" nil)
        (cons "count" 0)
        (cons "executedCount" 0)
        (cons "transactionCombinationCount" 0)
        (cons "selectorString" ""))))))

(defun smoke-gate-transaction-summary (suite-root required-p &key pinned-p)
  (let ((root (smoke-gate-call
               "execution-spec-tests-transaction-test-root"
               suite-root)))
    (cond
      ((and root pinned-p)
       (smoke-gate-reject-empty-selected-root root "transaction_tests")
       (let* ((cases
                (smoke-gate-call
                 "load-eest-transaction-test-root-invalid-cases"
                 root))
              (summary
                (smoke-gate-call
                 "eest-invalid-transaction-rejection-summary"
                 cases))
              (count (length cases)))
         (unless (plusp count)
           (error "Pinned EEST transaction_tests invalid-case count must be positive"))
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" count)
          (cons "executedCount" count)
          (cons "types" nil)
          (cons "invalidSummary" summary)
          (cons "selectorString" "pinned-v5.4.0-invalid"))))
      (root
       (smoke-gate-reject-empty-selected-root root "transaction_tests")
       (let* ((vectors
                (smoke-gate-call
                 "load-phase-a-eest-transaction-test-root-vectors"
                 root))
              (summary
                (smoke-gate-call
                 "validate-phase-a-eest-transaction-vector-summary"
                 vectors))
              (executed
                (smoke-gate-execute-transaction-vectors vectors))
              (selectors
                (smoke-gate-variable
                 "+phase-a-eest-transaction-test-case-names+")))
         (smoke-gate-require-positive-field
          summary "count" "Phase A transaction_tests count")
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" (smoke-gate-field summary "count"))
          (cons "executedCount" executed)
          (cons "types" (smoke-gate-field summary "types"))
          (cons "selectorString"
                (smoke-gate-call
                 "phase-a-eest-transaction-test-selector-string"
                 selectors)))))
      (required-p
       (error "Phase A smoke gate requires an EEST transaction_tests root under ~A"
              suite-root))
      (t
       (list
        (cons "status" "missing")
        (cons "root" nil)
        (cons "count" 0)
        (cons "executedCount" 0)
        (cons "types" nil)
        (cons "selectorString" ""))))))

(defun smoke-gate-blockchain-summary (suite-root pinned-p)
  (let ((root (smoke-gate-call
               "execution-spec-tests-blockchain-test-root"
               suite-root)))
    (unless root
      (error "Phase A smoke gate requires an EEST blockchain root under ~A"
             suite-root))
    (smoke-gate-reject-empty-selected-root root "blockchain")
    (let* ((kinds
             (if pinned-p
                 (smoke-gate-call
                  "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
                  root)
                 (smoke-gate-call
                  "discover-phase-a-eest-blockchain-replay-selectors"
                  root)))
           (cases
             (smoke-gate-call
              "load-phase-a-eest-blockchain-replay-cases"
              root
              :expected-kinds kinds))
           (summary
             (smoke-gate-call
              "validate-phase-a-eest-blockchain-replay-summary"
              cases
              :expected-kinds kinds))
           (executed (smoke-gate-execute-blockchain-cases cases)))
      (smoke-gate-require-positive-field
       summary "count" "Phase A blockchain replay count")
      (when (and (not pinned-p)
                 (zerop (smoke-gate-kind-count summary "blockRlp")))
        (error "Phase A in-repo blockchain replay must include blockRlp coverage"))
      (when (zerop (smoke-gate-kind-count summary "engineNewPayloadV2"))
        (error "Phase A blockchain replay must include engineNewPayloadV2 coverage"))
      (list
       (cons "status" "ok")
       (cons "root" (namestring root))
       (cons "count" (smoke-gate-field summary "count"))
       (cons "executedCount" executed)
       (cons "blockCount" (smoke-gate-field summary "blockCount"))
       (cons "kindCounts"
             (smoke-gate-field summary "materializationKindCounts"))
       (cons "selectorString"
             (smoke-gate-call
              "phase-a-eest-blockchain-replay-selector-string"
             kinds))))))

