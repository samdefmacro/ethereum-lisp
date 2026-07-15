(in-package #:ethereum-lisp.kzg)

(defvar *kzg-point-proof-verifier* nil
  "Optional verifier for EIP-4844 point proofs.

When non-NIL, the value must be a function of COMMITMENT, Z, Y, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defvar *kzg-blob-proof-verifier* nil
  "Optional verifier for EIP-4844 blob proofs.

When non-NIL, the value must be a function of BLOB, COMMITMENT, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defstruct (kzg-verifier
            (:constructor make-kzg-verifier
                (&key point-proof-function blob-proof-function)))
  point-proof-function
  blob-proof-function)

(defvar *kzg-verifier* nil
  "Dynamically scoped KZG verifier used by validation and RPC services.")

(defun current-kzg-point-proof-function ()
  (or (and *kzg-verifier*
           (kzg-verifier-point-proof-function *kzg-verifier*))
      *kzg-point-proof-verifier*))

(defun current-kzg-blob-proof-function ()
  (or (and *kzg-verifier*
           (kzg-verifier-blob-proof-function *kzg-verifier*))
      *kzg-blob-proof-verifier*))

(defun kzg-point-proof-verification-available-p ()
  (functionp (current-kzg-point-proof-function)))

(defun kzg-blob-proof-verification-available-p ()
  (functionp (current-kzg-blob-proof-function)))

(defun kzg-proof-verification-available-p ()
  (and (kzg-point-proof-verification-available-p)
       (kzg-blob-proof-verification-available-p)))
