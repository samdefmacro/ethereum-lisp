(defun smoke-gate-devnet-script-json (arguments)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (append
        (list "sbcl"
              "--script"
              (namestring
               (smoke-gate-reference-path
                "scripts/devnet-smoke-gate.lisp"))
              "--"
              "--json")
        arguments)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (error "Devnet smoke gate failed with status ~D: ~A" status stderr))
    (smoke-gate-json-decode stdout)))

(defun smoke-gate-devnet-summary ()
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet"
                                 "pid")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--all-fixtures"
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file
                   "--database"
                   database-file
                   "--prune-state-before"
                   (write-to-string
                    +smoke-gate-devnet-prune-state-before+))))
           (smoke-gate-validate-devnet-summary
            report
            ready-file
            log-file
            pid-file
            database-file))
      (when report
        (dolist (field '("readyFile" "logFile" "pidFile" "databaseFile"))
          (dolist (path (smoke-gate-devnet-case-files report field))
            (smoke-gate-delete-file-if-present path))))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-devnet-engine-only-summary ()
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only"
                                 "pid")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--engine-only-serve"
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file
                   "--database"
                   database-file)))
           (smoke-gate-validate-devnet-engine-only-summary
            report
            ready-file
            log-file
            pid-file
            database-file))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-validate-devnet-side-reorg-case-summary
    (report fixture-case ready-file log-file pid-file database-file)
  (unless (string= "ok" (smoke-gate-field report "status"))
    (error "Devnet side-reorg smoke gate returned non-ok status: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "mode" "devnet-listener-boundary")
  (smoke-gate-devnet-require-field
   report "fixtureCase" fixture-case)
  (smoke-gate-devnet-require-field report "readyFile" ready-file)
  (smoke-gate-devnet-require-field report "logFile" log-file)
  (smoke-gate-devnet-require-field report "pidFile" pid-file)
  (smoke-gate-devnet-require-field report "databaseFile" database-file)
  (smoke-gate-devnet-case-require-false
   report "databasePruneStateBefore")
  (let ((side-reorg-count
          (smoke-gate-devnet-validate-side-reorg-case report)))
    (unless (= 1 side-reorg-count)
      (error "Devnet side-reorg smoke gate must cover one case, got ~D"
             side-reorg-count))
    (append
     report
     (list (cons "readyCaseCount" 1)
           (cons "logCaseCount" 1)
           (cons "pidCaseCount" 1)
           (cons "databaseCaseCount" 1)
           (cons "sideReorgCaseCount" side-reorg-count)))))

(defun smoke-gate-devnet-side-reorg-case-summary (fixture-case)
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg"
                                 "pid")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--fixture-case"
                   fixture-case
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file
                   "--database"
                   database-file)))
           (smoke-gate-validate-devnet-side-reorg-case-summary
            report
            fixture-case
            ready-file
            log-file
            pid-file
            database-file))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-devnet-side-reorg-summary ()
  (let* ((reports
           (mapcar #'smoke-gate-devnet-side-reorg-case-summary
                   +smoke-gate-devnet-side-reorg-fixture-cases+))
         (case-count (length reports)))
    (list
     (cons "status" "ok")
     (cons "mode" "devnet-side-reorg-suite")
     (cons "caseCount" case-count)
     (cons "fixtureCases" +smoke-gate-devnet-side-reorg-fixture-cases+)
     (cons "cases" reports)
     (cons "readyCaseCount" case-count)
     (cons "logCaseCount" case-count)
     (cons "pidCaseCount" case-count)
     (cons "databaseCaseCount" case-count)
     (cons "sideReorgCaseCount"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "sideReorgCaseCount"))
                   :initial-value 0))
     (cons "engineConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSideEngineConnections"))
                   :initial-value 0))
     (cons "publicConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSidePublicConnections"))
                   :initial-value 0))
     (cons "restoredPublicConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report
                           "databaseRpcSideRestoredPublicConnections"))
                   :initial-value 0))
     (cons "totalConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSideTotalConnections"))
                   :initial-value 0)))))

