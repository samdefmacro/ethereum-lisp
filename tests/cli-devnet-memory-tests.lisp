(in-package #:ethereum-lisp.test)

;;;; The node's memory budget option and its native-memory maintenance.

(defun cli-devnet-memory-test-event (sink name)
  (find name (ethereum-lisp.telemetry:telemetry-events sink)
        :key #'ethereum-lisp.telemetry:telemetry-event-name
        :test #'string=))

(defun cli-devnet-memory-test-field (event name)
  (cdr (assoc name (ethereum-lisp.telemetry:telemetry-event-fields event)
              :test #'string=)))

(deftest devnet-cli-memory-budget-option-is-mebibytes
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "devnet" "--memory.budget" "12288" "--no-serve"))))
    (is (= 12288 (getf options :memory-budget-mebibytes)))
    (is (= (* 12288 1024 1024)
           (ethereum-lisp.cli::devnet-cli-memory-budget-bytes options))))
  ;; Absent, the budget is the Hoodi gate's 7 GiB.
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "devnet" "--no-serve"))))
    (is (null (getf options :memory-budget-mebibytes)))
    (is (= ethereum-lisp.database:+rocksdb-default-memory-budget-bytes+
           (ethereum-lisp.cli::devnet-cli-memory-budget-bytes options))))
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     (list "devnet" "--memory.budget" "0" "--no-serve")))
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     (list "devnet" "--memory.budget" "7GiB" "--no-serve"))))

(deftest devnet-cli-memory-budget-sizes-rocksdb-for-the-run-and-logs-it
  (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
        (before ethereum-lisp.database:*rocksdb-memory-profile*)
        (inside nil))
    (ethereum-lisp.cli::call-with-devnet-cli-memory-budget
     (list :memory-budget-mebibytes 12288)
     (lambda ()
       (setf inside ethereum-lisp.database:*rocksdb-memory-profile*)
       ;; What a serving node logs when its maintenance worker starts.  The
       ;; wrapper itself logs nothing: stdout can be the --json summary
       ;; (ETHEREUM-LISP-SCRIPT-DISPATCHES-DEVNET-NO-SERVE-JSON parses it).
       (ethereum-lisp.cli::devnet-log-memory-budget sink)))
    ;; Assigned for the run (visible to every thread), restored after it.
    (is (= (* 438 1024 1024)
           (ethereum-lisp.database:rocksdb-memory-profile-block-cache-bytes
            inside)))
    (is (eq before ethereum-lisp.database:*rocksdb-memory-profile*))
    (let ((event (cli-devnet-memory-test-event sink "node.memory.budget")))
      (is event)
      (is (= 12288 (cli-devnet-memory-test-field event "budgetMb")))
      (is (= 438 (cli-devnet-memory-test-field event "rocksdbBlockCacheMb")))
      (is (= 987 (cli-devnet-memory-test-field event "rocksdbMemtableLimitMb")))
      #+sbcl
      (is (= (round (sb-ext:dynamic-space-size) (* 1024 1024))
             (cli-devnet-memory-test-field event "lispDynamicSpaceMb")))
      ;; On glibc the start-up pins malloc's mmap threshold at its default.
      (when (ethereum-lisp.telemetry:native-malloc-available-p)
        (is (= ethereum-lisp.telemetry:+native-malloc-default-mmap-threshold-bytes+
               (cli-devnet-memory-test-field
                event "mallocMmapThresholdBytes")))))))

(deftest devnet-memory-maintenance-releases-and-samples-on-its-cadence
  (:layer :integration :module :native-memory)
  (unless (ethereum-lisp.telemetry:native-malloc-available-p)
    (skip-test "glibc malloc_trim/malloc_info are unavailable"))
  (let ((ethereum-lisp.cli::*devnet-memory-release-interval-seconds* 2)
        (ethereum-lisp.cli::*devnet-memory-sample-interval-seconds* 4))
    ;; Off-cadence ticks log nothing; tick 4 releases and samples.
    (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink)))
      (ethereum-lisp.cli::devnet-memory-maintenance-tick sink 1)
      (ethereum-lisp.cli::devnet-memory-maintenance-tick sink 3)
      (is (null (ethereum-lisp.telemetry:telemetry-events sink)))
      (ethereum-lisp.cli::devnet-memory-maintenance-tick sink 4)
      (let ((sample (cli-devnet-memory-test-event sink "node.memory.sample")))
        (is sample)
        (dolist (field '("releasedMb" "releaseMs" "rssAnonMb" "heapMb"
                         "lispResidentMb" "nativeResidentMb" "mallocInUseMb"
                         "mallocFreeMb" "mallocHeaps"))
          (is (integerp (cli-devnet-memory-test-field sample field))))
        ;; The split adds up (to rounding): native is what the Lisp heap's
        ;; resident pages do not explain.
        (is (<= (abs (- (cli-devnet-memory-test-field sample "rssAnonMb")
                        (+ (cli-devnet-memory-test-field sample "lispResidentMb")
                           (cli-devnet-memory-test-field
                            sample "nativeResidentMb"))))
                1))))
    ;; A release tick between samples that returns a lot is logged at once,
    ;; naming the release; one that returns little stays quiet.
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (pins (native-memory-test-fragment 1536 (* 64 1024))))
      (unwind-protect
           (ethereum-lisp.cli::devnet-memory-maintenance-tick sink 2)
        (mapc #'cffi:foreign-free pins))
      (let ((release (cli-devnet-memory-test-event sink "node.memory.release")))
        (is release)
        (is (string= "periodic"
                     (cli-devnet-memory-test-field release "reason")))
        (is (<= 64 (cli-devnet-memory-test-field release "releasedMb")))))
    (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink)))
      (ethereum-lisp.cli::devnet-memory-maintenance-tick sink 2)
      (is (null (ethereum-lisp.telemetry:telemetry-events sink))))))

(deftest devnet-release-native-memory-logs-the-reason-it-was-asked-for
  (:layer :integration :module :native-memory)
  (unless (ethereum-lisp.telemetry:native-malloc-available-p)
    (skip-test "glibc malloc_trim/malloc_info are unavailable"))
  (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink)))
    (is (integerp (ethereum-lisp.cli::devnet-release-native-memory-and-log
                   sink "snap-target-completed")))
    (let ((release (cli-devnet-memory-test-event sink "node.memory.release")))
      (is release)
      (is (string= "snap-target-completed"
                   (cli-devnet-memory-test-field release "reason")))
      (is (integerp (cli-devnet-memory-test-field release "lispResidentMb"))))))
