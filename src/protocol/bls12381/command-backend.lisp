(in-package #:ethereum-lisp.bls12381)

;;;; A persistent external process backend for the EIP-2537 operations.
;;;;
;;;; The helper serves newline-delimited requests, so one process handles many
;;;; precompile calls. This keeps the process boundary of the KZG verifier
;;;; without paying process startup on every call:
;;;;
;;;;   <operation> <hex-input>\n   ->   ok <hex-output>\n
;;;;                                    err <message>\n

(defparameter *bls12381-backend-timeout-seconds* 10
  "Maximum wall-clock seconds to wait for one backend response.")

(defparameter +bls12381-operation-names+
  '((:g1-add . "g1add")
    (:g1-msm . "g1msm")
    (:g2-add . "g2add")
    (:g2-msm . "g2msm")
    (:pairing-check . "pairing")
    (:map-fp-to-g1 . "mapfptog1")
    (:map-fp2-to-g2 . "mapfp2tog2"))
  "Wire names for each backend operation.")

(defstruct (bls12381-command-backend
            (:constructor %make-bls12381-command-backend (command)))
  command
  (process nil)
  (lock (sb-thread:make-mutex :name "ethereum-lisp-bls12381-backend")))

(defun bls12381-operation-name (operation)
  (or (cdr (assoc operation +bls12381-operation-names+))
      (error "Unknown BLS12-381 operation: ~S" operation)))

(defun normalize-bls12381-command (command)
  (labels ((valid-command-string-p (value)
             (and (stringp value)
                  (plusp (length value))
                  (notevery (lambda (char)
                              (find char '(#\Space #\Tab #\Newline #\Return)))
                            value)
                  t)))
    (cond
      ((and (stringp command) (plusp (length (string-trim '(#\Space #\Tab) command))))
       (list command))
      ((and (listp command)
            command
            (every (lambda (value) (and (stringp value) (plusp (length value))))
                   command))
       (copy-list command))
      (t
       (error "BLS12-381 backend command must be a non-empty string or list of strings")))))

(defun bls12381-backend-process-alive-p (backend)
  (let ((process (bls12381-command-backend-process backend)))
    (and process (uiop:process-alive-p process))))

(defun stop-bls12381-backend-process (backend)
  (let ((process (bls12381-command-backend-process backend)))
    (setf (bls12381-command-backend-process backend) nil)
    (when process
      (ignore-errors (uiop:terminate-process process))
      (ignore-errors (uiop:wait-process process)))
    nil))

(defun bls12381-backend-deadline ()
  (+ (get-internal-real-time)
     (* *bls12381-backend-timeout-seconds* internal-time-units-per-second)))

(defun read-bls12381-response-line (stream deadline)
  "Read one newline-terminated response from STREAM, honouring DEADLINE.

Polls rather than blocking so a wedged backend surfaces as a timeout instead of
stalling the calling thread forever."
  (let ((line (make-string-output-stream)))
    (loop
      (loop until (listen stream)
            do (when (>= (get-internal-real-time) deadline)
                 (error "BLS12-381 backend timed out after ~D seconds"
                        *bls12381-backend-timeout-seconds*))
               (sleep 0.001))
      (let ((char (read-char stream nil nil)))
        (cond
          ((null char)
           (error "BLS12-381 backend closed its output stream"))
          ((char= char #\Newline)
           (return (get-output-stream-string line)))
          ((char= char #\Return))
          (t (write-char char line)))))))

(defun parse-bls12381-response (line)
  "Return the output bytes carried by a backend response LINE."
  (let* ((trimmed (string-trim '(#\Space #\Tab) line))
         (space (position #\Space trimmed))
         (status (subseq trimmed 0 (or space (length trimmed))))
         (payload (if space (string-trim '(#\Space) (subseq trimmed space)) "")))
    (cond
      ((string= status "ok")
       (hex-to-bytes (if (zerop (length payload)) "0x" payload)))
      ((string= status "err")
       (error "BLS12-381 backend rejected the input: ~A" payload))
      (t
       (error "Malformed BLS12-381 backend response: ~A" trimmed)))))

(defun start-bls12381-backend-process (backend)
  "Launch the helper and confirm it speaks the expected protocol."
  (let ((process (handler-case
                     (uiop:launch-program (bls12381-command-backend-command backend)
                                          :input :stream
                                          :output :stream
                                          :error-output nil)
                   (error (condition)
                     (error "BLS12-381 backend failed to start: ~A" condition)))))
    (setf (bls12381-command-backend-process backend) process)
    (handler-case
        (let ((input (uiop:process-info-input process))
              (output (uiop:process-info-output process)))
          (write-string "ping" input)
          (write-char #\Newline input)
          (finish-output input)
          (let ((line (read-bls12381-response-line output (bls12381-backend-deadline))))
            (unless (and (>= (length line) 2) (string= "ok" (subseq line 0 2)))
              (error "BLS12-381 backend did not answer the handshake: ~A" line))))
      (error (condition)
        (stop-bls12381-backend-process backend)
        (error "~A" condition)))
    process))

(defun ensure-bls12381-backend-process (backend)
  (if (bls12381-backend-process-alive-p backend)
      (bls12381-command-backend-process backend)
      (progn
        (stop-bls12381-backend-process backend)
        (start-bls12381-backend-process backend))))

(defun bls12381-backend-exchange (backend operation input)
  "Send one request and return the response bytes, without retrying."
  (let* ((process (ensure-bls12381-backend-process backend))
         (stdin (uiop:process-info-input process))
         (stdout (uiop:process-info-output process)))
    (write-string (bls12381-operation-name operation) stdin)
    (write-char #\Space stdin)
    (write-string (bytes-to-hex input) stdin)
    (write-char #\Newline stdin)
    (finish-output stdin)
    (parse-bls12381-response
     (read-bls12381-response-line stdout (bls12381-backend-deadline)))))

(defun bls12381-input-rejected-p (condition)
  "True when CONDITION reports an input the backend refused, not a transport fault."
  (let ((text (princ-to-string condition)))
    (search "rejected the input" text)))

(defun bls12381-command-request (backend operation input)
  "Evaluate OPERATION over INPUT, restarting the helper once if it has died.

The operations are pure functions of their input, so replaying a request that
failed in transport cannot double-apply an effect. A rejection by the backend
is a verdict about the input and is never retried."
  (sb-thread:with-mutex ((bls12381-command-backend-lock backend))
    (handler-case
        (bls12381-backend-exchange backend operation input)
      (error (condition)
        (when (bls12381-input-rejected-p condition)
          (error "~A" condition))
        (stop-bls12381-backend-process backend)
        (bls12381-backend-exchange backend operation input)))))

(defun make-bls12381-command-backend (command)
  "Return a backend function backed by a persistent COMMAND process.

COMMAND is an executable name/path or a list of executable plus fixed
arguments. The process is started on first use and reused thereafter."
  (let ((backend (%make-bls12381-command-backend
                  (normalize-bls12381-command command))))
    (values (lambda (operation input)
              (bls12381-command-request backend operation input))
            backend)))

(defun configure-bls12381-command-backend (command)
  "Install a persistent COMMAND-backed backend for the EIP-2537 operations."
  (setf *bls12381-backend* (make-bls12381-command-backend command))
  t)

(defun shutdown-bls12381-command-backend (backend)
  "Terminate the helper process owned by BACKEND."
  (sb-thread:with-mutex ((bls12381-command-backend-lock backend))
    (stop-bls12381-backend-process backend)))
