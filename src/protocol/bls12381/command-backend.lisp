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

Uses READ-CHAR-NO-HANG so a closed stream is detected immediately as EOF rather
than masquerading as \"no data yet\" until the deadline — a helper that dies
mid-request then errors at once instead of costing a full timeout."
  (let ((line (make-string-output-stream)))
    (loop
      (let ((char (read-char-no-hang stream nil :eof)))
        (cond
          ((eq char :eof)
           (bls12381-unavailable-error
            "BLS12-381 backend closed its output stream"))
          ((null char)
           (when (>= (get-internal-real-time) deadline)
             (bls12381-unavailable-error
              "BLS12-381 backend timed out after ~D seconds"
              *bls12381-backend-timeout-seconds*))
           (sleep 0.001))
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
       ;; A non-hex OK body is a backend defect, not an input verdict.
       (handler-case (hex-to-bytes (if (zerop (length payload)) "0x" payload))
         (error ()
           (bls12381-unavailable-error
            "BLS12-381 backend returned a non-hex output"))))
      ((string= status "err")
       (bls12381-input-error "BLS12-381 backend rejected the input: ~A" payload))
      (t
       (bls12381-unavailable-error
        "Malformed BLS12-381 backend response: ~A" trimmed)))))

(defun start-bls12381-backend-process (backend)
  "Launch the helper and confirm it speaks the expected protocol."
  (let ((process (handler-case
                     (uiop:launch-program (bls12381-command-backend-command backend)
                                          :input :stream
                                          :output :stream
                                          :error-output nil)
                   (error (condition)
                     (bls12381-unavailable-error
                      "BLS12-381 backend failed to start: ~A" condition)))))
    (setf (bls12381-command-backend-process backend) process)
    (handler-case
        (let ((input (uiop:process-info-input process))
              (output (uiop:process-info-output process)))
          (write-string "ping" input)
          (write-char #\Newline input)
          (finish-output input)
          (let ((line (read-bls12381-response-line output (bls12381-backend-deadline))))
            (unless (and (>= (length line) 2) (string= "ok" (subseq line 0 2)))
              (bls12381-unavailable-error
               "BLS12-381 backend did not answer the handshake: ~A" line))))
      (error (condition)
        (stop-bls12381-backend-process backend)
        (error condition)))
    process))

(defun ensure-bls12381-backend-process (backend)
  (if (bls12381-backend-process-alive-p backend)
      (bls12381-command-backend-process backend)
      (progn
        (stop-bls12381-backend-process backend)
        (start-bls12381-backend-process backend))))

(defun bls12381-backend-exchange (backend operation input)
  "Send one request and return the response bytes, without retrying.

Any failure to complete the send-and-receive kills the helper, because a
half-read response would desynchronise every later request and there is no way
to resynchronise a shared pipe. This holds for a non-ERROR unwind too — a
deadline reached in the caller, say — so the guard is UNWIND-PROTECT, not a
handler. The response is parsed AFTER the exchange, so a clean rejection reply
does not kill a healthy helper."
  (let ((line nil)
        (received nil))
    (unwind-protect
         (let* ((process (ensure-bls12381-backend-process backend))
                (stdin (uiop:process-info-input process))
                (stdout (uiop:process-info-output process)))
           (write-string (bls12381-operation-name operation) stdin)
           (write-char #\Space stdin)
           (write-string (bytes-to-hex input) stdin)
           (write-char #\Newline stdin)
           (finish-output stdin)
           (setf line (read-bls12381-response-line stdout
                                                   (bls12381-backend-deadline)))
           (setf received t))
      (unless received
        (stop-bls12381-backend-process backend)))
    (parse-bls12381-response line)))

(defun bls12381-command-request (backend operation input)
  "Evaluate OPERATION over INPUT, restarting the helper once if it has died.

The operations are pure functions of their input, so replaying a request that
failed in transport cannot double-apply an effect. An input verdict is never
retried; a transport fault is retried once against a fresh helper, which the
exchange has already restarted by killing the dead one."
  (sb-thread:with-mutex ((bls12381-command-backend-lock backend))
    (handler-case
        (bls12381-backend-exchange backend operation input)
      (bls12381-unavailable-error ()
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
