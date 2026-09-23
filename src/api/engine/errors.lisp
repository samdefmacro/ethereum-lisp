(in-package #:ethereum-lisp.engine-api)

(defconstant +engine-rpc-error-unknown-payload+ -38001)
(defconstant +engine-rpc-error-invalid-forkchoice-state+ -38002)
(defconstant +engine-rpc-error-invalid-payload-attributes+ -38003)
(defconstant +engine-rpc-error-too-large-request+ -38004)
(defconstant +engine-rpc-error-unsupported-fork+ -38005)

;; EIP-1474 reserves 3 for a call that reverted; the revert bytes travel in the
;; error object's data member.
(defconstant +engine-rpc-error-execution-reverted+ 3)

(define-condition engine-rpc-error (error)
  ((code :initarg :code :reader engine-rpc-error-code)
   (message :initarg :message :reader engine-rpc-error-message)
   (data :initarg :data :initform nil :reader engine-rpc-error-data))
  (:report (lambda (condition stream)
             (format stream "~A" (engine-rpc-error-message condition)))))

(defun engine-rpc-fail (code message)
  (error 'engine-rpc-error :code code :message message))

(defun engine-rpc-fail-with-data (code message data)
  "Signal an RPC error carrying a data member alongside CODE and MESSAGE."
  (error 'engine-rpc-error :code code :message message :data data))

(defvar *engine-rpc-phase-timings* :disabled
  "Per-request Engine RPC phase timings, or :DISABLED outside HTTP handling.")

(defun engine-rpc-record-phase-duration (name milliseconds)
  (unless (eq *engine-rpc-phase-timings* :disabled)
    (push (cons name milliseconds) *engine-rpc-phase-timings*))
  nil)

(defun engine-rpc-record-phase-timing (name started-at)
  (engine-rpc-record-phase-duration
   name
   (round
    (* 1000 (- (get-internal-real-time) started-at))
    internal-time-units-per-second))
  nil)

(defmacro engine-rpc-with-phase-timing ((name) &body body)
  `(let ((started-at (get-internal-real-time)))
     (multiple-value-prog1
         (progn ,@body)
       (engine-rpc-record-phase-timing ,name started-at))))

(defun engine-rpc-call-with-phase-accounting (prefix thunk)
  "Call THUNK and record where its wall time went, as PREFIXMs (wall),
PREFIXGcMs, PREFIXGcCount and PREFIXCpuMs (TELEMETRY-RUNTIME-FIELDS).

A phase whose wall time is far above both its CPU and its GC time was off the
CPU: waiting on a lock, a peer, a disk or the host scheduler."
  (if (eq *engine-rpc-phase-timings* :disabled)
      (funcall thunk)
      (let ((start (ethereum-lisp.telemetry:telemetry-runtime-sample)))
        (multiple-value-prog1 (funcall thunk)
          (loop for (name . value)
                  in (ethereum-lisp.telemetry:telemetry-runtime-fields
                      prefix start)
                do (engine-rpc-record-phase-duration name value))))))

(defmacro engine-rpc-with-phase-accounting ((prefix) &body body)
  `(engine-rpc-call-with-phase-accounting ,prefix (lambda () ,@body)))

