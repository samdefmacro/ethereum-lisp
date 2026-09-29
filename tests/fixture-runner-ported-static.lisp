(in-package #:ethereum-lisp.test)

;;;; ported_static: the legacy GeneralStateTests ported into EEST, as an
;;;; optional, bounded gate.
;;;;
;;;; The stable tests@v20.0.2 state gate (OPTIONAL-PHASE-A-EEST-STATE-TEST-
;;;; ROOT-VECTORS-EXECUTE) discovers only the feature trees named in
;;;; +PHASE-A-EEST-STATE-TEST-DISCOVERY-FEATURE-DIRECTORIES+, and ported_static
;;;; is not one of them: its manifest counts those files as
;;;; featureTreeNotCovered.  That list stays as it is, so the eight standard
;;;; gates keep their manifest lines byte for byte; this runner walks
;;;; `state_tests/for_<fork>/ported_static/<directory>/' on its own, one
;;;; fixture file at a time, and scores every post entry of every claimed fork
;;;; instead of stopping at the first failure.
;;;;
;;;; Memory is bounded per post entry.  go-ethereum prices memory before it
;;;; allocates it (core/vm/interpreter.go Run charges dynamicGas, memoryGasCost
;;;; included, and resizes afterwards), so the most memory one frame can hold
;;;; is what the transaction's gas pays for: an absurd size is out of gas,
;;;; never an allocation.  Each post entry therefore runs with
;;;; ETHEREUM-LISP.EVM.INTERNAL::*MEMORY-ALLOCATION-CEILING* bound to twice the
;;;; gas-derived bound (the backing vector doubles), capped at
;;;; *PORTED-STATIC-EEST-HARNESS-CEILING-BYTES*.  A refused allocation above
;;;; the gas-derived bound is a FAILURE (allocationBeyondPaidGas: we allocated
;;;; what geth would have refused as out of gas); one within it but above the
;;;; harness cap is a typed SKIP (paidAllocationAboveHarnessCeiling).  Heap and
;;;; stack exhaustion are caught per entry and reported by type as failures.
;;;;
;;;; Selection, all optional and comma-separated:
;;;;   ETHEREUM_LISP_PORTED_STATIC_FORKS        forks to execute (default
;;;;                                            Cancun,Prague,Osaka)
;;;;   ETHEREUM_LISP_PORTED_STATIC_DIRECTORIES  only these ported_static
;;;;                                            directories (e.g. stRandom2)
;;;; Without the fixture root, or with a root that has no ported_static tree
;;;; for any claimed fork, both tests here are counted skips.

(defconstant +ported-static-eest-forks-env+
  "ETHEREUM_LISP_PORTED_STATIC_FORKS")

(defconstant +ported-static-eest-directories-env+
  "ETHEREUM_LISP_PORTED_STATIC_DIRECTORIES")

(defconstant +ported-static-eest-trace-env+
  "ETHEREUM_LISP_PORTED_STATIC_TRACE")

(defparameter +ported-static-eest-default-forks+
  '("Cancun" "Prague" "Osaka"))

(defparameter *ported-static-eest-max-file-bytes* (* 40 1024 1024)
  "Fixture files above this size are counted as fileTooLarge, not parsed.
The largest ported_static state file in tests@v20.0.2 is 36.7 MB
(stRandom/random_statetest36), so at this bound none is skipped.")

(defparameter *ported-static-eest-full-gc-file-bytes* (* 4 1024 1024)
  "After a fixture file above this size the runner collects in full.")

(defparameter *ported-static-eest-harness-ceiling-bytes* (* 256 1024 1024)
  "The most bytes one EVM buffer may allocate under this runner, whatever the
transaction's gas would pay for.")

(defparameter *ported-static-eest-failure-samples* 10
  "How many failure messages each directory reports verbatim.")

(defparameter *ported-static-eest-heap-budget-fraction* 3/8
  "The share of the Lisp dynamic space the heap may fill, after a full
collection, before a paid EVM allocation is refused as
paidMemoryAboveHarnessHeap.  The copying collector needs free space about the
size of what it copies: with 3/4 of the cold image's 1 GiB live, a hash-table
grow in the snapshot journal exhausted the heap inside the collector.")

(defun ported-static-eest-heap-budget ()
  (floor (* *ported-static-eest-heap-budget-fraction*
            (sb-ext:dynamic-space-size))))

(defparameter +ported-static-eest-reviewed-skip-reasons+
  '("fileTooLarge" "paidAllocationAboveHarnessCeiling"
    "paidMemoryAboveHarnessHeap")
  "Skip reasons that do not fail the gate: none claims a vector executed, and
each names a harness resource the vector's own gas legitimately pays past.")

(defun ported-static-eest-env-list (name)
  (let ((value (funcall *fixture-root-environment-reader* name)))
    (unless (blank-string-p value)
      (remove-if #'blank-string-p
                 (mapcar #'eest-fixture-trim-string
                         (eest-fixture-split-string value #\,))))))

(defun ported-static-eest-forks ()
  (let ((forks (ported-static-eest-env-list +ported-static-eest-forks-env+)))
    (dolist (fork forks)
      (unless (member fork '("London" "Shanghai" "Cancun" "Prague" "Osaka")
                      :test #'string=)
        (error "~A names ~A; ported_static runs London through Osaka"
               +ported-static-eest-forks-env+ fork)))
    (or forks (copy-list +ported-static-eest-default-forks+))))

(defun ported-static-eest-fork-directory (state-root fork)
  "STATE-ROOT's `for_<fork>/ported_static/' directory, or NIL."
  (probe-file (merge-pathnames
               (make-pathname
                :directory (list :relative
                                 (format nil "~A~(~A~)"
                                         +eest-fixture-network-directory-prefix+
                                         fork)
                                 "ported_static"))
               (pathname state-root))))

(defun ported-static-eest-directories (fork-directory)
  "The directory names directly under FORK-DIRECTORY, sorted, narrowed by
ETHEREUM_LISP_PORTED_STATIC_DIRECTORIES."
  (let ((wanted (ported-static-eest-env-list
                 +ported-static-eest-directories-env+)))
    (remove-if-not
     (lambda (name)
       (or (null wanted) (member name wanted :test #'string=)))
     (sort (mapcar (lambda (path) (car (last (pathname-directory path))))
                   (directory
                    (merge-pathnames
                     (make-pathname :directory '(:relative :wild))
                     fork-directory)))
           #'string<))))

(defun ported-static-eest-directory-files (fork-directory directory)
  (execution-spec-tests-json-paths
   (merge-pathnames (make-pathname :directory (list :relative directory))
                    fork-directory)))

;;; The allocation ceiling of one post entry

(defun ported-static-eest-entry-gas-limit (case post-entry)
  "The transaction gas limit POST-ENTRY selects, or NIL when it cannot be read
(the entry then runs under the harness ceiling alone)."
  (handler-case
      (let ((transaction (fixture-required-field
                          (fixture-required-field case "fixture")
                          "transaction")))
        (eest-state-test-quantity-string
         (eest-state-test-indexed-transaction-value
          transaction "gasLimit"
          (fixture-required-field post-entry "indexes") "gas")
         "gasLimit"))
    (error () nil)))

(defun ported-static-eest-paid-allocation-bytes (gas-limit)
  "The largest single EVM buffer a transaction with GAS-LIMIT can pay for: the
frame memory its gas buys, doubled for the backing vector's growth (a backing
never exceeds twice the memory it holds)."
  (* 2 (ethereum-lisp.evm.internal::memory-size-payable-with-gas gas-limit)))

(defun ported-static-eest-allocation-ceiling (gas-limit)
  (if gas-limit
      (min (ported-static-eest-paid-allocation-bytes gas-limit)
           *ported-static-eest-harness-ceiling-bytes*)
      *ported-static-eest-harness-ceiling-bytes*))

(defun ported-static-eest-refusal-outcome (condition gas-limit)
  "Classify a refused allocation: (VALUES :failed message) when the request
exceeds what GAS-LIMIT pays for, (VALUES :skipped reason) otherwise."
  (let ((requested (ethereum-lisp.evm.internal::evm-memory-allocation-refused-requested
                    condition)))
    (cond
      ((and gas-limit
            (> requested (ported-static-eest-paid-allocation-bytes gas-limit)))
       (values :failed
               (format nil "allocationBeyondPaidGas: ~D bytes requested, ~
                            gas limit ~D pays for ~D"
                       requested gas-limit
                       (ported-static-eest-paid-allocation-bytes gas-limit))))
      ((eq :heap-budget
           (ethereum-lisp.evm.internal::evm-memory-allocation-refused-reason
            condition))
       (values :skipped "paidMemoryAboveHarnessHeap"))
      (t
       (values :skipped "paidAllocationAboveHarnessCeiling")))))

;;; Scoring

(defstruct (ported-static-eest-tally
            (:constructor make-ported-static-eest-tally (fork directory)))
  fork directory (files 0) (cases 0) (entries 0) (passed 0) (failed 0)
  (skips '()) (samples '()) (skipped-entries '()))

(defun ported-static-eest-tally-skipped (tally)
  (reduce #'+ (ported-static-eest-tally-skips tally) :key #'cdr))

(defun ported-static-eest-count-skip (tally reason)
  (let ((entry (assoc reason (ported-static-eest-tally-skips tally)
                      :test #'string=)))
    (if entry
        (incf (cdr entry))
        (push (cons reason 1) (ported-static-eest-tally-skips tally)))))

(defun ported-static-eest-record-failure (tally message)
  (incf (ported-static-eest-tally-failed tally))
  (when (< (length (ported-static-eest-tally-samples tally))
           *ported-static-eest-failure-samples*)
    (push message (ported-static-eest-tally-samples tally))))

(defun ported-static-eest-run-entry (case post-entry fork)
  "Run one post entry under its allocation ceiling.

Returns (VALUES outcome detail): :PASSED; :FAILED and a one-line message; or
:SKIPPED and a reviewed reason."
  (let* ((gas-limit (ported-static-eest-entry-gas-limit case post-entry))
         (ethereum-lisp.evm.internal::*memory-allocation-ceiling*
           (ported-static-eest-allocation-ceiling gas-limit))
         (ethereum-lisp.evm.internal::*memory-allocation-heap-budget*
           (ported-static-eest-heap-budget))
         (label (let ((*print-pretty* nil))
                  (format nil "~A ~A indexes ~S"
                          (fixture-required-field case "name") fork
                          (fixture-object-field post-entry "indexes")))))
    (when (ported-static-eest-env-list +ported-static-eest-trace-env+)
      (format t "~&PORTED-STATIC-EEST   running ~A heap=~D~%"
              label (sb-kernel:dynamic-usage))
      (finish-output))
    (handler-case
        (progn
          (assert-eest-state-test-post-entry case post-entry :fork fork)
          (values :passed nil))
      (ethereum-lisp.evm.internal::evm-memory-allocation-refused (condition)
        (multiple-value-bind (outcome detail)
            (ported-static-eest-refusal-outcome condition gas-limit)
          (values outcome
                  (if (eq outcome :failed)
                      (format nil "~A: ~A" label detail)
                      detail)
                  label)))
      (storage-condition (condition)
        ;; Heap or control-stack exhaustion: typed, contained, and a failure,
        ;; because a vector that geth executes must not exhaust ours.  The
        ;; entry's data is garbage once the handler has unwound; collect it
        ;; before consing the report, or the report exhausts the heap again.
        (let ((type (type-of condition)))
          (setf condition nil)
          (sb-ext:gc :full t)
          (values :failed (format nil "~A: ~S" label type))))
      (serious-condition (condition)
        (values :failed
                (format nil "~A: ~A" label
                        (amsterdam-eest-condition-summary condition)))))))

(defun ported-static-eest-score-case (tally case fork)
  (incf (ported-static-eest-tally-cases tally))
  (let ((entries (handler-case (eest-state-test-post-entries case fork)
                   (error (condition)
                     (ported-static-eest-record-failure
                      tally
                      (format nil "~A ~A: ~A"
                              (fixture-required-field case "name") fork
                              (amsterdam-eest-condition-summary condition)))
                     nil))))
    (dolist (post-entry entries)
      (incf (ported-static-eest-tally-entries tally))
      (multiple-value-bind (outcome detail label)
          (ported-static-eest-run-entry case post-entry fork)
        (ecase outcome
          (:passed (incf (ported-static-eest-tally-passed tally)))
          (:failed (ported-static-eest-record-failure tally detail))
          (:skipped
           (ported-static-eest-count-skip tally detail)
           (push (format nil "~A ~A" detail label)
                 (ported-static-eest-tally-skipped-entries tally))))))))

(defun ported-static-eest-fixture-forks (case)
  (handler-case (eest-state-test-case-fork-names case)
    (error () '())))

(defun ported-static-eest-collect-after-large-file (bytes)
  "A full collection after a fixture file of BYTES above
*PORTED-STATIC-EEST-FULL-GC-FILE-BYTES*.  Its text and JSON tree (several
hundred MB for the 33 MB stRandom files, at four bytes a character) are
garbage once the file is scored, but the generational collector can leave them
promoted while the next large file is read, which exhausted the 1 GiB cold
heap on the first run."
  (when (> bytes *ported-static-eest-full-gc-file-bytes*)
    (sb-ext:gc :full t)))

(defun ported-static-eest-score-directory (state-root fork-directory fork
                                           directory)
  (let ((tally (make-ported-static-eest-tally fork directory)))
    (dolist (path (ported-static-eest-directory-files fork-directory directory))
      (incf (ported-static-eest-tally-files tally))
      (if (> (eest-fixture-file-byte-size path)
             *ported-static-eest-max-file-bytes*)
          (ported-static-eest-count-skip tally "fileTooLarge")
          (let ((cases (handler-case
                           (load-eest-state-test-root-file-cases state-root path)
                         (error (condition)
                           (ported-static-eest-record-failure
                            tally
                            (format nil "~A: unreadable fixture: ~A"
                                    (enough-namestring path state-root)
                                    (amsterdam-eest-condition-summary
                                     condition)))
                           nil))))
            (dolist (case cases)
              (if (member fork (ported-static-eest-fixture-forks case)
                          :test #'string=)
                  (ported-static-eest-score-case tally case fork)
                  (ported-static-eest-record-failure
                   tally
                   (format nil "~A: a for_~(~A~) fixture without ~A post entries"
                           (fixture-required-field case "name") fork fork))))
            (setf cases nil)
            (ported-static-eest-collect-after-large-file
             (eest-fixture-file-byte-size path)))))
    tally))

(defun ported-static-eest-format-skips (skips)
  (mapcar (lambda (entry) (format nil "~A:~D" (car entry) (cdr entry)))
          (sort (copy-list skips) #'string< :key #'car)))

(defun ported-static-eest-report-line (tally)
  (format nil "PORTED-STATIC-EEST ~A ~A: files=~D cases=~D entries=~D ~
               passed=~D failed=~D skipped=~D~@[ skips=[~{~A~^ ~}]~]"
          (ported-static-eest-tally-fork tally)
          (ported-static-eest-tally-directory tally)
          (ported-static-eest-tally-files tally)
          (ported-static-eest-tally-cases tally)
          (ported-static-eest-tally-entries tally)
          (ported-static-eest-tally-passed tally)
          (ported-static-eest-tally-failed tally)
          (ported-static-eest-tally-skipped tally)
          (ported-static-eest-format-skips
           (ported-static-eest-tally-skips tally))))

(defun ported-static-eest-fork-total (fork tallies)
  (let ((total (make-ported-static-eest-tally fork "total")))
    (dolist (tally tallies total)
      (when (string= fork (ported-static-eest-tally-fork tally))
        (incf (ported-static-eest-tally-files total)
              (ported-static-eest-tally-files tally))
        (incf (ported-static-eest-tally-cases total)
              (ported-static-eest-tally-cases tally))
        (incf (ported-static-eest-tally-entries total)
              (ported-static-eest-tally-entries tally))
        (incf (ported-static-eest-tally-passed total)
              (ported-static-eest-tally-passed tally))
        (incf (ported-static-eest-tally-failed total)
              (ported-static-eest-tally-failed tally))
        (dolist (skip (ported-static-eest-tally-skips tally))
          (loop repeat (cdr skip)
                do (ported-static-eest-count-skip total (car skip))))))))

(defun ported-static-eest-run (state-root forks)
  "Score every selected ported_static directory of every fork in FORKS.

Prints one line per directory, its first failures, and one total per fork;
returns the directory tallies."
  (let ((tallies '()))
    (dolist (fork forks)
      (let ((fork-directory (ported-static-eest-fork-directory state-root fork)))
        (when fork-directory
          (dolist (directory (ported-static-eest-directories fork-directory))
            (let ((tally (ported-static-eest-score-directory
                          state-root fork-directory fork directory)))
              (format t "~&~A~%" (ported-static-eest-report-line tally))
              (dolist (sample (reverse (ported-static-eest-tally-samples tally)))
                (format t "~&PORTED-STATIC-EEST   failure ~A~%" sample))
              ;; Every skipped entry is named: a skip is a claim that the
              ;; harness, not the vector, stopped it.
              (dolist (entry (reverse
                              (ported-static-eest-tally-skipped-entries tally)))
                (format t "~&PORTED-STATIC-EEST   skip ~A~%" entry))
              (finish-output)
              (push tally tallies))))
        (format t "~&~A~%"
                (ported-static-eest-report-line
                 (ported-static-eest-fork-total fork tallies)))
        (finish-output)))
    (nreverse tallies)))

(defun ported-static-eest-gate-failures (tallies forks)
  "Why the gate fails, as strings; NIL when it passes.

It fails for any failed entry, any skip outside the reviewed reasons, and any
claimed fork that passed nothing -- a mounted corpus that executed zero entries
for a fork is the silent pass the manifest guards exist to stop."
  (append
   (loop for fork in forks
         for total = (ported-static-eest-fork-total fork tallies)
         unless (plusp (ported-static-eest-tally-passed total))
           collect (format nil "~A: no ported_static entry passed" fork))
   (loop for tally in tallies
         when (plusp (ported-static-eest-tally-failed tally))
           collect (ported-static-eest-report-line tally))
   (loop for tally in tallies
         for unreviewed = (remove-if
                           (lambda (skip)
                             (member (car skip)
                                     +ported-static-eest-reviewed-skip-reasons+
                                     :test #'string=))
                           (ported-static-eest-tally-skips tally))
         when unreviewed
           collect (format nil "~A: unreviewed skips ~{~A~^ ~}"
                           (ported-static-eest-report-line tally)
                           (ported-static-eest-format-skips unreviewed)))))

(defun ported-static-eest-state-root-or-skip ()
  (let ((state-root (execution-spec-tests-state-test-root)))
    (unless state-root
      (skip-test
       (format nil "Set ~A to an execution-spec-tests fixture root containing state_tests to run ported_static"
               +execution-spec-tests-fixture-root-env+)))
    (unless (some (lambda (fork)
                    (ported-static-eest-fork-directory state-root fork))
                  (ported-static-eest-forks))
      (skip-test "The EEST state_tests root has no for_<fork>/ported_static tree for the claimed forks"))
    state-root))

;;; Manifest: what the mounted corpus offers, without executing it

(defun ported-static-eest-manifest (state-root forks)
  "Per claimed fork: (FORK directories files unopened-too-large cases entries
valid invalid), read one fixture file at a time."
  (loop
    for fork in forks
    for fork-directory = (ported-static-eest-fork-directory state-root fork)
    collect
    (let ((directories 0) (files 0) (too-large 0) (cases 0) (entries 0)
          (valid 0) (invalid 0))
      (when fork-directory
        (dolist (directory (ported-static-eest-directories fork-directory))
          (incf directories)
          (dolist (path (ported-static-eest-directory-files fork-directory
                                                            directory))
            (incf files)
            (if (> (eest-fixture-file-byte-size path)
                   *ported-static-eest-max-file-bytes*)
                (incf too-large)
                (progn
                  (dolist (case (load-eest-state-test-root-file-cases
                                 state-root path))
                    (incf cases)
                    (dolist (post-entry
                             (fixture-object-field
                              (fixture-object-field
                               (fixture-required-field case "fixture") "post")
                              fork))
                      (incf entries)
                      (if (eest-state-test-expected-exception post-entry)
                          (incf invalid)
                          (incf valid))))
                  (ported-static-eest-collect-after-large-file
                   (eest-fixture-file-byte-size path)))))))
      (list fork directories files too-large cases entries valid invalid))))

(defun ported-static-eest-manifest-line (row)
  (destructuring-bind (fork directories files too-large cases entries
                       valid invalid)
      row
    (format nil "PORTED-STATIC-MANIFEST state_tests ~A: directories=~D ~
                 files=~D cases=~D entries=~D validity=[invalid:~D valid:~D] ~
                 unopenedFiles=[fileTooLarge:~D]"
            fork directories files cases entries invalid valid too-large)))

(defun ported-static-eest-manifest-failures (rows)
  "Claimed forks whose mounted tree offers no valid or no invalid entry."
  (loop for (fork nil nil nil nil entries valid invalid) in rows
        unless (and (plusp entries) (plusp valid) (plusp invalid))
          collect (format nil "~A: entries=~D valid=~D invalid=~D"
                          fork entries valid invalid)))

(deftest eest-ported-static-state-manifest-is-non-vacuous
  (:layer :integration :module :eest)
  (let* ((state-root (ported-static-eest-state-root-or-skip))
         (forks (ported-static-eest-forks))
         (rows (ported-static-eest-manifest state-root forks)))
    (dolist (row rows)
      (format t "~&~A~%" (ported-static-eest-manifest-line row)))
    (finish-output)
    (let ((failures (ported-static-eest-manifest-failures rows)))
      (when failures
        (error "ported_static manifest is vacuous for a claimed fork:~{ ~A;~}"
               failures)))
    (is rows)))

(deftest optional-eest-ported-static-state-tests-execute
  (:layer :integration :module :eest)
  (let ((state-root (ported-static-eest-state-root-or-skip))
        (forks (ported-static-eest-forks)))
    (call-with-eest-cryptographic-backends
     (lambda ()
       (let* ((tallies (ported-static-eest-run state-root forks))
              (failures (ported-static-eest-gate-failures tallies forks)))
         (is tallies)
         (when failures
           (error "ported_static state tests did not pass:~{ ~A;~}"
                  failures)))))))

;;; Corpus-free controls: the classification and the gate verdict must be able
;;; to fail, so they are exercised on every build, fixtures or not.

(deftest ported-static-eest-refusal-and-gate-verdicts-can-fail
  (:layer :unit :module :eest)
  (flet ((refusal (requested)
           (make-condition
            'ethereum-lisp.evm.internal::evm-memory-allocation-refused
            :requested requested :ceiling 0)))
    ;; 100,000 gas pays for 205,696 bytes of memory; doubled, 411,392.
    (is (= 411392 (ported-static-eest-paid-allocation-bytes 100000)))
    (is (= 411392 (ported-static-eest-allocation-ceiling 100000)))
    (is (= *ported-static-eest-harness-ceiling-bytes*
           (ported-static-eest-allocation-ceiling (expt 2 60))))
    (is (= *ported-static-eest-harness-ceiling-bytes*
           (ported-static-eest-allocation-ceiling nil)))
    ;; Above what the gas pays for: a failure, named.
    (multiple-value-bind (outcome detail)
        (ported-static-eest-refusal-outcome (refusal 1968156800) 100000)
      (is (eq :failed outcome))
      (is (search "allocationBeyondPaidGas" detail)))
    ;; Paid for, but above the harness cap: a reviewed skip.
    (multiple-value-bind (outcome detail)
        (ported-static-eest-refusal-outcome
         (refusal (1+ *ported-static-eest-harness-ceiling-bytes*))
         (expt 2 60))
      (is (eq :skipped outcome))
      (is (equal "paidAllocationAboveHarnessCeiling" detail)))
    ;; Paid for, but the heap budget is spent: a reviewed skip of its own.
    (multiple-value-bind (outcome detail)
        (ported-static-eest-refusal-outcome
         (make-condition
          'ethereum-lisp.evm.internal::evm-memory-allocation-refused
          :requested 1000000 :ceiling 0 :reason :heap-budget)
         (expt 2 40))
      (is (eq :skipped outcome))
      (is (equal "paidMemoryAboveHarnessHeap" detail)))
    ;; ... but never for more than the gas pays for.
    (is (eq :failed
            (ported-static-eest-refusal-outcome
             (make-condition
              'ethereum-lisp.evm.internal::evm-memory-allocation-refused
              :requested 1000000 :ceiling 0 :reason :heap-budget)
             100000))))
  (flet ((tally (fork passed failed &rest skips)
           (let ((tally (make-ported-static-eest-tally fork "stExample")))
             (setf (ported-static-eest-tally-passed tally) passed
                   (ported-static-eest-tally-failed tally) failed
                   (ported-static-eest-tally-skips tally) skips)
             tally)))
    ;; Positive control: a clean run passes.
    (is (null (ported-static-eest-gate-failures
               (list (tally "Cancun" 3 0) (tally "Osaka" 2 0
                                                 (cons "fileTooLarge" 1)))
               '("Cancun" "Osaka"))))
    ;; A failed entry, an unreviewed skip, a claimed fork that passed nothing.
    (is (= 1 (length (ported-static-eest-gate-failures
                      (list (tally "Cancun" 3 1)) '("Cancun")))))
    (is (= 1 (length (ported-static-eest-gate-failures
                      (list (tally "Cancun" 3 0 (cons "somethingNew" 1)))
                      '("Cancun")))))
    (is (= 1 (length (ported-static-eest-gate-failures
                      (list (tally "Cancun" 3 0)) '("Cancun" "Prague"))))))
  ;; The manifest guard: a claimed fork offering no valid or no invalid entry.
  (is (null (ported-static-eest-manifest-failures
             '(("Cancun" 57 2078 0 2078 9000 8000 1000)))))
  (is (= 2 (length (ported-static-eest-manifest-failures
                    '(("Cancun" 57 2078 0 2078 9000 9000 0)
                      ("Prague" 0 0 0 0 0 0 0)))))))
