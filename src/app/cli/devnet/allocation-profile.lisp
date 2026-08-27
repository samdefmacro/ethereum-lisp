#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-sprof))

(in-package #:ethereum-lisp.cli)

;;;; Opt-in, bounded production allocation diagnosis.

(defparameter +devnet-allocation-profile-environment+
  "ETHEREUM_LISP_ALLOC_PROFILE_SECONDS")

(defun devnet-parse-allocation-profile-seconds (raw)
  "Parse a disabled or one-to-300-second allocation profile request."
  (when (and raw (plusp (length raw)))
    (let ((seconds
            (handler-case
                (parse-integer raw :junk-allowed nil)
              (error () nil))))
      (unless (and seconds (<= 0 seconds 300))
        (error "~A must be an integer from zero through 300"
               +devnet-allocation-profile-environment+))
      (and (plusp seconds) seconds))))

#+sbcl
(defvar *devnet-allocation-profile-lock*
  (sb-thread:make-mutex :name "devnet-allocation-profile"))

#+sbcl
(defvar *devnet-allocation-profile-started-p* nil)

#+sbcl
(defun devnet-allocation-profile-flat-table (report)
  "Return only REPORT's bounded flat function table, never its thread dump."
  (let* ((header-marker "Self        Total        Cumul")
         (separator (format nil "~%------------------------------------------------------------------------"))
         (header (search header-marker report)))
    (unless header
      (error "SB-SPROF report did not contain a flat-table header"))
    (let* ((start (1+ (or (position #\Newline report
                                    :end header :from-end t)
                          -1)))
           (first-separator (search separator report :start2 header))
           (second-separator
             (and first-separator
                  (search separator report
                          :start2 (+ first-separator (length separator)))))
           (end (and second-separator
                     (+ second-separator (length separator)))))
      (unless end
        (error "SB-SPROF report did not contain a complete flat table"))
      (subseq report start end))))

#+sbcl
(defun devnet-write-allocation-profile-table (table seconds)
  "Write TABLE as independently filterable, payload-free diagnostic lines."
  (format *error-output*
          "allocation-profile-begin seconds=~D max-functions=50~%"
          seconds)
  (with-input-from-string (stream table)
    (loop for line = (read-line stream nil nil)
          while line
          do (format *error-output* "allocation-profile-row ~A~%" line)))
  (format *error-output* "allocation-profile-end~%")
  (finish-output *error-output*))

#+sbcl
(defun devnet-run-allocation-profile (seconds)
  "Sample allocation stacks for SECONDS and print one bounded flat report."
  (handler-case
      (progn
        (sb-sprof:reset)
        (sb-sprof:start-profiling
         :mode :alloc :max-samples 20000 :threads :all)
        (unwind-protect
             (sleep seconds)
          (sb-sprof:stop-profiling))
        ;; SB-SPROF's preamble prints sampled thread objects. A finished thread
        ;; retains and prints its return value, which can include peer or RPC
        ;; payloads. Capture the report privately and publish only the flat
        ;; function table with a prefix that evidence collectors can filter.
        (let* ((report
                 (with-output-to-string (stream)
                   (sb-sprof:report
                    :type :flat :max 50 :stream stream
                    :show-progress nil)))
               (table (devnet-allocation-profile-flat-table report)))
          (devnet-write-allocation-profile-table table seconds)))
    (serious-condition (condition)
      (ignore-errors (sb-sprof:stop-profiling))
      (format *error-output* "allocation-profile-error type=~A~%"
              (type-of condition))
      (finish-output *error-output*))))

(defun devnet-maybe-start-allocation-profile ()
  "Start the explicitly requested allocation profile at most once."
  #+sbcl
  (let ((seconds
          (devnet-parse-allocation-profile-seconds
           (uiop:getenv +devnet-allocation-profile-environment+))))
    (when seconds
      (sb-thread:with-mutex (*devnet-allocation-profile-lock*)
        (unless *devnet-allocation-profile-started-p*
          (setf *devnet-allocation-profile-started-p* t)
          (sb-thread:make-thread
           (lambda () (devnet-run-allocation-profile seconds))
           :name "devnet-allocation-profile")))))
  #-sbcl nil)
