(in-package #:ethereum-lisp.test)

(defun test-runner-fixture-pass ()
  t)

(defun test-runner-fixture-skip ()
  (skip-test "fixture skip"))

(defun test-runner-fixture-fail ()
  (error "fixture failure"))

(deftest test-runner-registers-and-selects-layer-metadata
  (:layer :unit :module :test-runner)
  (let ((*tests* '())
        (*test-metadata* (make-hash-table :test #'eq)))
    (register-test 'test-runner-fixture-pass
                   :layer :unit
                   :module :fixture)
    (register-test 'test-runner-fixture-skip
                   :layer :integration
                   :module :fixture
                   :requires-local-sockets t)
    (is (equal '(test-runner-fixture-pass)
               (selected-tests :layer :unit)))
    (is (equal '(test-runner-fixture-skip)
               (selected-tests :layer "integration")))
    (is (equal '(test-runner-fixture-pass test-runner-fixture-skip)
               (selected-tests :layer :all)))
    (let ((metadata (metadata-for-test 'test-runner-fixture-skip)))
      (is (eq :integration (test-metadata-layer metadata)))
      (is (eq :fixture (test-metadata-module metadata)))
      (is (test-metadata-requires-local-sockets-p metadata)))))

(deftest test-runner-retains-pass-skip-and-failure-timings
  (:layer :unit :module :test-runner)
  (let ((*tests* '())
        (*test-metadata* (make-hash-table :test #'eq))
        (*last-test-results* '())
        (output (make-string-output-stream)))
    (register-test 'test-runner-fixture-pass :layer :unit)
    (register-test 'test-runner-fixture-skip :layer :unit)
    (register-test 'test-runner-fixture-fail :layer :unit)
    (signals test-run-failed
      (run-tests :layer :all :stream output :timing t))
    (is (equal '(:passed :skipped :failed)
               (mapcar #'test-result-status *last-test-results*)))
    (is (every (lambda (result)
                 (not (minusp (test-result-elapsed-seconds result))))
               *last-test-results*))
    (is (search "Execution time:" (get-output-stream-string output)))))

(deftest test-runner-listing-and-summary-shapes-are-deterministic
  (:layer :unit :module :test-runner)
  (let ((*tests* '())
        (*test-metadata* (make-hash-table :test #'eq)))
    (register-test 'test-runner-fixture-pass
                   :layer :unit
                   :module :fixture
                   :launches-processes t)
    (let ((output (make-string-output-stream)))
      (list-tests :layer :all :verbose t :stream output)
      (is (string=
           (format nil
                   "TEST-RUNNER-FIXTURE-PASS [unit module=FIXTURE process]~%")
           (get-output-stream-string output))))
    (let* ((output (make-string-output-stream))
           (results
             (list
              (make-test-result :name 'slow :layer :integration
                                :status :passed :elapsed-seconds 2d0)
              (make-test-result :name 'fast :layer :unit
                                :status :skipped :elapsed-seconds 0.25d0))))
      (report-test-timings results output 1 0.5d0)
      (let ((summary (get-output-stream-string output)))
        (is (search "unit=0.250s" summary))
        (is (search "integration=2.000s" summary))
        (is (search "2.000s passed SLOW [integration]" summary))
        (is (not (search "FAST [unit]" summary)))))))

(deftest test-runner-metadata-covers-every-registered-test
  (:layer :unit :module :test-runner)
  (is (= (length *tests*)
         (hash-table-count *test-metadata*)))
  (dolist (test *tests*)
    (is (member (test-metadata-layer (metadata-for-test test))
                +test-layers+))))
