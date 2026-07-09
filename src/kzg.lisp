(in-package #:ethereum-lisp.core)

(defvar *kzg-point-proof-verifier* nil
  "Optional verifier for EIP-4844 point proofs.

When non-NIL, the value must be a function of COMMITMENT, Z, Y, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defvar *kzg-blob-proof-verifier* nil
  "Optional verifier for EIP-4844 blob proofs.

When non-NIL, the value must be a function of BLOB, COMMITMENT, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defparameter *kzg-verifier-command-timeout-seconds* 5
  "Maximum wall-clock seconds to wait for an external KZG verifier command.")

(defun kzg-point-proof-verification-available-p ()
  (functionp *kzg-point-proof-verifier*))

(defun kzg-blob-proof-verification-available-p ()
  (functionp *kzg-blob-proof-verifier*))

(defun kzg-proof-verification-available-p ()
  (and (kzg-point-proof-verification-available-p)
       (kzg-blob-proof-verification-available-p)))

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

(defun run-kzg-verifier-command (command mode byte-arguments)
  (let ((argv (append command
                      (list mode)
                      (mapcar (lambda (bytes)
                                (bytes-to-hex bytes))
                              byte-arguments))))
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
          (ignore-errors (uiop:terminate-process process)))))))

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

  COMMAND blob BLOB_HEX COMMITMENT_HEX PROOF_HEX

It must exit 0 and print one of true, ok, valid, or 1 to stdout when the proof
is valid."
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

(defun validate-kzg-field-element (bytes label)
  (let ((bytes (ensure-byte-vector bytes)))
    (unless (= +kzg-field-element-size+ (length bytes))
      (error "~A must be exactly ~D bytes" label +kzg-field-element-size+))
    (unless (< (bytes-to-integer bytes) +kzg-field-modulus+)
      (error "~A must be less than BLS field modulus" label))
    bytes))

(defun validate-kzg-blob-field-elements (blob)
  (let ((blob (ensure-byte-vector blob)))
    (unless (= +blob-byte-size+ (length blob))
      (error "Blob must be exactly ~D bytes" +blob-byte-size+))
    (unless (= +kzg-blob-field-elements-per-blob+
               (/ (length blob) +kzg-field-element-size+))
      (error "Blob must contain exactly ~D field elements"
             +kzg-blob-field-elements-per-blob+))
    (loop for start below (length blob) by +kzg-field-element-size+
          for index from 0
          do (validate-kzg-field-element
              (subseq blob start (+ start +kzg-field-element-size+))
              (format nil "Blob field element ~D" index))))
  t)

(defun verify-kzg-point-proof (commitment z y proof)
  (unless (kzg-point-proof-verification-available-p)
    (error "KZG point proof verification is not available"))
  (let ((commitment (ensure-byte-vector commitment))
        (z (ensure-byte-vector z))
        (y (ensure-byte-vector y))
        (proof (ensure-byte-vector proof)))
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (validate-kzg-field-element z "KZG point z")
    (validate-kzg-field-element y "KZG point y")
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-point-proof-verifier* commitment z y proof)
      (error "KZG point proof verification failed")))
  t)

(defun verify-kzg-blob-proof (blob commitment proof)
  (unless (kzg-blob-proof-verification-available-p)
    (error "KZG blob proof verification is not available"))
  (let ((blob (ensure-byte-vector blob))
        (commitment (ensure-byte-vector commitment))
        (proof (ensure-byte-vector proof)))
    (validate-kzg-blob-field-elements blob)
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-blob-proof-verifier* blob commitment proof)
      (error "KZG blob proof verification failed")))
  t)

(defun validate-blob-sidecar-kzg-proofs (sidecar)
  (unless (kzg-blob-proof-verification-available-p)
    (block-validation-fail
     "KZG proof verification is not available; blob sidecars are shape-checked only"))
  (let ((blobs (blob-sidecar-blobs sidecar))
        (commitments (blob-sidecar-commitments sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length proofs) (length blobs))
      (block-validation-fail
       "KZG cell proof verification is not available; blob proof verification requires one proof per blob"))
    (handler-case
        (loop for blob in blobs
              for commitment in commitments
              for proof in proofs
              do (verify-kzg-blob-proof blob commitment proof))
      (error (condition)
        (block-validation-fail "~A" condition))))
  t)

(defun validate-blob-sidecar-fields
    (sidecar &key transaction require-proof-verification)
  (let* ((blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar))
         (blob-count (length blobs))
         (commitment-count (length commitments))
         (proof-count (length proofs)))
    (unless (= blob-count commitment-count)
      (block-validation-fail
       "Blob sidecar blob and commitment counts must match"))
    (unless (or (= proof-count blob-count)
                (= proof-count (* blob-count +cell-proofs-per-blob+)))
      (block-validation-fail
       "Blob sidecar proof count must match blobs or cell proofs per blob"))
    (dolist (blob blobs)
      (validate-sized-byte-vector blob +blob-byte-size+ "Blob")
      (handler-case
          (validate-kzg-blob-field-elements blob)
        (error (condition)
          (block-validation-fail "~A" condition))))
    (dolist (commitment commitments)
      (validate-sized-byte-vector commitment +kzg-commitment-size+
                                  "KZG commitment"))
    (dolist (proof proofs)
      (validate-sized-byte-vector proof +kzg-proof-size+ "KZG proof"))
    (when transaction
      (unless (= blob-count (transaction-blob-count transaction))
        (block-validation-fail
         "Blob sidecar count does not match transaction blob hash count"))
      (loop for actual in (blob-sidecar-versioned-hashes sidecar)
            for expected across (transaction-blob-versioned-hashes transaction)
            unless (bytes= (hash32-bytes actual)
                           (blob-versioned-hash-bytes expected))
              do (block-validation-fail
                  "Blob sidecar commitment does not match transaction blob hash")))
    (when require-proof-verification
      (validate-blob-sidecar-kzg-proofs sidecar))
    t))
