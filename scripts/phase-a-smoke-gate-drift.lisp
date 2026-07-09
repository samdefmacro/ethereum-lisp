(defun smoke-gate-numeric-field (object field)
  (or (smoke-gate-field object field) 0))

(defun smoke-gate-report-counts
    (state transaction blockchain devnet devnet-side-reorg
     devnet-engine-only)
  (let* ((fixture-case-count
           (+ (smoke-gate-numeric-field state "count")
              (smoke-gate-numeric-field transaction "count")
              (smoke-gate-numeric-field blockchain "count")))
         (fixture-executed-count
           (+ (smoke-gate-numeric-field state "executedCount")
              (smoke-gate-numeric-field transaction "executedCount")
              (smoke-gate-numeric-field blockchain "executedCount")))
         (devnet-case-count
           (if devnet (smoke-gate-numeric-field devnet "caseCount") 0))
         (devnet-side-reorg-case-count
           (if devnet-side-reorg
               (smoke-gate-numeric-field
                devnet-side-reorg "sideReorgCaseCount")
               0))
         (devnet-engine-only-case-count
           (if devnet-engine-only
               (smoke-gate-numeric-field devnet-engine-only "caseCount")
               0)))
    (list
     (cons "fixtureCaseCount" fixture-case-count)
     (cons "fixtureExecutedCount" fixture-executed-count)
     (cons "totalCaseCount"
           (+ fixture-case-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count))
     (cons "totalExecutedCount"
           (+ fixture-executed-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)))))

(defun smoke-gate-drift-map-command (suite-root)
  (list "sbcl"
        "--script"
        (smoke-gate-script-path "scripts/phase-a-drift-map.lisp")
        "--"
        "--root"
        suite-root
        "--failures-only"
        "--summary-only"
        "--json"))

(defun smoke-gate-run-drift-map (suite-root)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (smoke-gate-drift-map-command suite-root)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (error "Phase A drift map failed with status ~D: ~A"
             status
             stderr))
    (when (plusp (length stderr))
      (error "Phase A drift map wrote unexpected stderr: ~A" stderr))
    (smoke-gate-json-decode stdout)))

(defun smoke-gate-drift-map-summary (suite-root)
  (let* ((report (smoke-gate-run-drift-map suite-root))
         (overall (smoke-gate-field report "overall"))
         (materializable-clear
           (smoke-gate-field overall "phaseAMaterializableClear")))
    (unless (eq t materializable-clear)
      (error "Phase A drift map found materializable selector gaps: knownImplementationDrift=~D implementationBugCandidates=~D fixtureHarnessErrors=~D"
             (or (smoke-gate-field overall "knownImplementationDriftCount") 0)
             (or (smoke-gate-field overall "implementationBugCandidateCount")
                 0)
             (or (smoke-gate-field overall "fixtureHarnessErrorCount") 0)))
    (list
     (cons "status" "ok")
     (cons "mode" (smoke-gate-field report "mode"))
     (cons "root" (smoke-gate-field report "root"))
     (cons "failuresOnly" (smoke-gate-field report "failuresOnly"))
     (cons "summaryOnly" (smoke-gate-field report "summaryOnly"))
     (cons "suiteCount" (smoke-gate-field overall "suiteCount"))
     (cons "candidateCount" (smoke-gate-field overall "candidateCount"))
     (cons "classifiedCount" (smoke-gate-field overall "classifiedCount"))
     (cons "passingCount" (smoke-gate-field overall "passingCount"))
     (cons "knownImplementationDriftCount"
           (smoke-gate-field overall "knownImplementationDriftCount"))
     (cons "outOfScopeForkFeatureCount"
           (smoke-gate-field overall "outOfScopeForkFeatureCount"))
     (cons "implementationBugCandidateCount"
           (smoke-gate-field overall "implementationBugCandidateCount"))
     (cons "fixtureHarnessErrorCount"
           (smoke-gate-field overall "fixtureHarnessErrorCount"))
     (cons "phaseAMaterializableClear" materializable-clear)
     (cons "suites" (smoke-gate-field report "suites")))))

