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
        (format *error-output*
                "allocation-profile-begin seconds=~D max-functions=50~%"
                seconds)
        (sb-sprof:report
         :type :flat :max 50 :stream *error-output* :show-progress nil)
        (format *error-output* "allocation-profile-end~%")
        (finish-output *error-output*))
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
