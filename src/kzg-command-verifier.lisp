(in-package #:ethereum-lisp.kzg)

(defparameter *kzg-verifier-command-timeout-seconds* 5
  "Maximum wall-clock seconds to wait for an external KZG verifier command.")

(defun normalize-kzg-verifier-command (command)
  (labels ((valid-command-string-p (value)
             (and (stringp value)
                  (plusp (length value))
                  (not (every (lambda (char)
                                (find char '(#\Space #\Tab #\Newline #\Return)))
                              value)))))
    (cond
      ((valid-command-string-p command)
       (list command))
      ((and (listp command)
            command
            (every #'valid-command-string-p command))
       (copy-list command))
      (t
       (error "KZG verifier command must be a non-empty string or list of non-empty strings")))))

(defun kzg-verifier-command-executable-file-p (path)
  (let ((file (uiop:file-exists-p path)))
    (when file
      #+sbcl
      (handler-case
          (progn
            (require :sb-posix)
            (let* ((package (find-package "SB-POSIX"))
                   (access (and package (find-symbol "ACCESS" package)))
                   (x-ok (and package (find-symbol "X-OK" package))))
              (and access
                   x-ok
                   (zerop (funcall access
                                   (namestring file)
                                   (symbol-value x-ok))))))
        (error () nil))
      #-sbcl
      t)))

(defun kzg-verifier-command-program-executable-p (program)
  (labels ((blank-string-p (value)
             (or (null value)
                 (zerop (length
                         (string-trim '(#\Space #\Tab #\Newline #\Return)
                                      value)))))
           (candidate (directory)
             (format nil "~A/~A"
                     (if (blank-string-p directory) "." directory)
                     program)))
    (if (find #\/ program)
        (kzg-verifier-command-executable-file-p program)
        (loop for directory in (uiop:split-string
                                (or (uiop:getenv "PATH") "")
                                :separator ":")
              thereis (kzg-verifier-command-executable-file-p
                       (candidate directory))))))

(defun validate-kzg-verifier-command (command)
  (let* ((normalized (normalize-kzg-verifier-command command))
         (program (first normalized)))
    (unless (kzg-verifier-command-program-executable-p program)
      (error "KZG verifier command is not executable: ~A" program))
    normalized))

(defun kzg-verifier-command-accepted-output-p (output)
  (let ((token (string-downcase
                (string-trim '(#\Space #\Tab #\Newline #\Return)
                             output))))
    (member token '("1" "ok" "true" "valid") :test #'string=)))

(defun read-kzg-verifier-command-stream (stream)
  (if stream
      (with-output-to-string (output)
        (loop for char = (read-char stream nil nil)
              while char
              do (write-char char output)))
      ""))

(defun wait-kzg-verifier-command (process timeout-seconds)
  (let* ((timeout-units (* timeout-seconds internal-time-units-per-second))
         (deadline (+ (get-internal-real-time) timeout-units)))
    (loop while (uiop:process-alive-p process)
          do (when (>= (get-internal-real-time) deadline)
               (uiop:terminate-process process)
               (ignore-errors (uiop:wait-process process))
               (error "KZG verifier command timed out after ~D seconds"
                      timeout-seconds))
             (sleep 0.01))
    (uiop:wait-process process)))

(defun call-with-kzg-blob-file-argument (blob thunk)
  "Call THUNK with an @PATH argument containing the hex-encoded BLOB.

Linux limits each argv entry to 128 KiB, while an encoded EIP-4844 blob is
slightly over 256 KiB. A response-file-style argument avoids platform argv
limits while retaining the external verifier process boundary."
  (uiop:with-temporary-file
      (:stream stream :pathname pathname
       :prefix "ethereum-lisp-kzg-blob-" :suffix ".hex"
       :direction :output :external-format :utf-8)
    (write-string (bytes-to-hex blob) stream)
    (finish-output stream)
    (funcall thunk (format nil "@~A" (namestring pathname)))))

(defun run-kzg-verifier-argv (argv)
    (let ((process nil))
      (unwind-protect
           (progn
             (setf process
                   (handler-case
                       (uiop:launch-program argv
                                            :output :stream
                                            :error-output nil)
                     (error (condition)
                       (error "KZG verifier command failed to start: ~A"
                              condition))))
             (let ((status
                     (wait-kzg-verifier-command
                      process
                      *kzg-verifier-command-timeout-seconds*))
                   (stdout
                     (read-kzg-verifier-command-stream
                      (uiop:process-info-output process))))
               (and (numberp status)
                    (= 0 status)
                    (kzg-verifier-command-accepted-output-p stdout))))
        (when (and process (uiop:process-alive-p process))
          (ignore-errors (uiop:terminate-process process))))))

(defun run-kzg-verifier-command (command mode byte-arguments)
  (labels ((run-with-arguments (arguments)
             (run-kzg-verifier-argv
              (append command (list mode) arguments))))
    (if (string= mode "blob")
        (call-with-kzg-blob-file-argument
         (first byte-arguments)
         (lambda (blob-file-argument)
           (run-with-arguments
            (cons blob-file-argument
                  (mapcar #'bytes-to-hex (rest byte-arguments))))))
        (run-with-arguments (mapcar #'bytes-to-hex byte-arguments)))))

(defun make-kzg-point-proof-command-verifier (command)
  "Return a point-proof verifier backed by COMMAND.

COMMAND is a string executable name/path or a list of executable plus fixed
arguments. The command is invoked as:

  COMMAND point COMMITMENT_HEX Z_HEX Y_HEX PROOF_HEX

It must exit 0 and print one of true, ok, valid, or 1 to stdout when the proof
is valid."
  (let ((command (validate-kzg-verifier-command command)))
    (lambda (commitment z y proof)
      (run-kzg-verifier-command command
                                "point"
                                (list commitment z y proof)))))

(defun make-kzg-blob-proof-command-verifier (command)
  "Return a blob-proof verifier backed by COMMAND.

COMMAND is a string executable name/path or a list of executable plus fixed
arguments. The command is invoked as:

  COMMAND blob @BLOB_HEX_FILE COMMITMENT_HEX PROOF_HEX

It must exit 0 and print one of true, ok, valid, or 1 to stdout when the proof
is valid. BLOB_HEX_FILE contains the hex-encoded blob and is deleted after the
command exits."
  (let ((command (validate-kzg-verifier-command command)))
    (lambda (blob commitment proof)
      (run-kzg-verifier-command command
                                "blob"
                                (list blob commitment proof)))))

(defun configure-kzg-proof-command-verifiers (command)
  "Install COMMAND-backed point and blob proof verifiers.

This wires the existing KZG verification hooks to an external verifier process
without changing consensus behavior when no verifier is configured."
  (setf *kzg-point-proof-verifier*
        (make-kzg-point-proof-command-verifier command)
        *kzg-blob-proof-verifier*
        (make-kzg-blob-proof-command-verifier command))
  t)

(defun make-kzg-command-verifier (command)
  "Create a verifier object backed by COMMAND without mutating global hooks."
  (make-kzg-verifier
   :point-proof-function (make-kzg-point-proof-command-verifier command)
   :blob-proof-function (make-kzg-blob-proof-command-verifier command)))
