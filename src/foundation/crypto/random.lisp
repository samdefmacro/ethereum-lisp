(in-package #:ethereum-lisp.crypto)

;;;; Cryptographically secure randomness from the operating system.
;;;;
;;;; Needed for devp2p: ECIES ephemeral keys and IVs, and handshake nonces.
;;;; CL:RANDOM is not suitable — it is not a cryptographic generator.

(defun secure-random-bytes (count)
  "Return COUNT cryptographically secure random bytes from the OS CSPRNG."
  (unless (and (integerp count) (>= count 0))
    (error "secure-random-bytes count must be a non-negative integer"))
  (if (zerop count)
      (make-byte-vector 0)
      (with-open-file (stream "/dev/urandom" :element-type '(unsigned-byte 8))
        (let ((bytes (make-byte-vector count)))
          (unless (= count (read-sequence bytes stream))
            (error "Could not read ~D bytes of secure randomness" count))
          bytes))))
