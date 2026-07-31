(in-package #:ethereum-lisp.test)

;;;; Non-vacuity guard for EEST conformance.
;;;;
;;;; The failure this file exists to catch is silent: a run mounts the corpus,
;;;; discovers zero materializable cases for a fork it CLAIMS to cover, reports
;;;; every case skipped, and goes green -- indistinguishable, in CI, from having
;;;; verified something. A skip is the right answer when no corpus is present;
;;;; it is the WRONG answer when the corpus is right there and simply was not
;;;; exercised. So the guards below run only when the corpus is mounted (they
;;;; skip otherwise, exactly like the replay tests) and then FAIL if the
;;;; executed count for any fork/network the run is configured to cover is zero.
;;;;
;;;; "Configured to cover" is the supported set the selectors already key on:
;;;; PHASE-A-EEST-STATE-TEST-SUPPORTED-FORKS for state_tests and
;;;; PHASE-A-EEST-BLOCKCHAIN-REPLAY-SUPPORTED-NETWORKS for replay. With the
;;;; defaults that is London/Shanghai and Shanghai, so the existing blocking
;;;; gate asserts those are non-empty. When CI widens the set to the late forks
;;;; (Cancun/Prague/Osaka) the guard extends to them too -- which is why that
;;;; job is non-blocking until plan Phase 7 lands their execution.

(defun phase-a-eest-state-conformance-counts (root)
  "Return (VALUES selected executed skipped) for state_tests under ROOT.
SELECTED is the number of materializable cases discovered; EXECUTED is an alist
mapping each supported fork to the number of those cases whose post map carries
it (the fork combinations OPTIONAL-PHASE-A-EEST-STATE-TEST-ROOT-VECTORS-EXECUTE
runs); SKIPPED is the discovered-but-not-materializable remainder."
  (let* ((supported (phase-a-eest-state-test-supported-forks))
         (discovered (load-phase-a-eest-state-discovery-cases root))
         (materializable
           (remove-if-not #'phase-a-eest-state-materializable-case-p
                          discovered))
         (executed
           (mapcar
            (lambda (fork)
              (cons fork
                    (count-if
                     (lambda (case)
                       (member fork (eest-state-test-case-fork-names case)
                               :test #'string=))
                     materializable)))
            supported)))
    (values (length materializable)
            executed
            (- (length discovered) (length materializable)))))

(defun phase-a-eest-blockchain-conformance-counts (root)
  "Return (VALUES selected executed skipped) for blockchain replay under ROOT.
SELECTED is the number of materializable cases; EXECUTED is an alist mapping
each supported network to the number of those cases carrying it; SKIPPED is the
discovered-but-not-materializable remainder (e.g. late-fork engine payloads not
yet understood, which is a real coverage gap the manifest makes visible rather
than a green skip that hides it)."
  (let* ((supported (phase-a-eest-blockchain-replay-supported-networks))
         (discovered (load-phase-a-eest-blockchain-discovery-cases root))
         (materializable
           (remove-if-not #'phase-a-eest-blockchain-replay-materializable-kind
                          discovered))
         (executed
           (mapcar
            (lambda (network)
              (cons network
                    (count-if
                     (lambda (case)
                       (string= network
                                (fixture-object-field
                                 (fixture-required-field case "fixture")
                                 "network")))
                     materializable)))
            supported)))
    (values (length materializable)
            executed
            (- (length discovered) (length materializable)))))

(defun phase-a-eest-report-conformance-family
    (family selected executed skipped &optional (stream *standard-output*))
  "Emit one manifest line for FAMILY so the CI log records what actually ran."
  (format stream
          "~&EEST-CONFORMANCE ~A: selected=~D skipped=~D executed=[~{~A~^ ~}]~%"
          family selected skipped
          (mapcar (lambda (entry) (format nil "~A:~D" (car entry) (cdr entry)))
                  executed)))

(defun phase-a-eest-assert-family-non-vacuous (family executed)
  "Signal an error naming every fork/network in EXECUTED whose count is zero.
Returns NIL when all are positive. Kept separate from the corpus-mounted tests
so its logic is exercised without a corpus."
  (let ((vacuous (remove-if #'plusp executed :key #'cdr)))
    (when vacuous
      (error "~A conformance is vacuous: the corpus is mounted but executed ~
              zero cases for ~{~A~^, ~}; a green skip would have hidden this"
             family (mapcar #'car vacuous)))))

(deftest phase-a-eest-non-vacuity-guard-rejects-zero-executed
  ;; The guard's entire value is failing LOUD when a required family ran
  ;; nothing. Prove it fires on a zero and stays quiet when every family ran at
  ;; least one case -- this needs no corpus, so it runs on every build and keeps
  ;; the check honest even where the fixtures are absent.
  (signals error
    (phase-a-eest-assert-family-non-vacuous
     "state_tests" '(("London" . 3) ("Shanghai" . 0))))
  (is (null (phase-a-eest-assert-family-non-vacuous
             "state_tests" '(("London" . 3) ("Shanghai" . 1))))))

(deftest phase-a-eest-state-conformance-is-non-vacuous
  (with-execution-spec-tests-state-test-root (root)
    (multiple-value-bind (selected executed skipped)
        (phase-a-eest-state-conformance-counts root)
      (phase-a-eest-report-conformance-family
       "state_tests" selected executed skipped)
      (phase-a-eest-assert-family-non-vacuous "state_tests" executed))))

(deftest phase-a-eest-blockchain-conformance-is-non-vacuous
  (with-execution-spec-tests-blockchain-test-root (root)
    (multiple-value-bind (selected executed skipped)
        (phase-a-eest-blockchain-conformance-counts root)
      (phase-a-eest-report-conformance-family
       "blockchain_replay" selected executed skipped)
      (phase-a-eest-assert-family-non-vacuous "blockchain_replay" executed))))
