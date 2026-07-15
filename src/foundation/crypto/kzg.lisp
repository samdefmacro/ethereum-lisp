(in-package #:ethereum-lisp.crypto)

(defun require-sized-byte-vector (value size label)
  (let ((bytes (ensure-byte-vector value)))
    (unless (= size (length bytes))
      (error "~A must be exactly ~D bytes" label size))
    bytes))

(defun kzg-commitment-to-versioned-hash (commitment)
  "Return the EIP-4844 versioned hash for a 48-byte KZG COMMITMENT."
  (let ((hash (sha256 (require-sized-byte-vector
                       commitment
                       +kzg-commitment-size+
                       "KZG commitment"))))
    (setf (aref hash 0) +kzg-commitment-version+)
    (make-hash32 hash)))
