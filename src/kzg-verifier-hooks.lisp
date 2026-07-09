(in-package #:ethereum-lisp.core)

(defvar *kzg-point-proof-verifier* nil
  "Optional verifier for EIP-4844 point proofs.

When non-NIL, the value must be a function of COMMITMENT, Z, Y, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defvar *kzg-blob-proof-verifier* nil
  "Optional verifier for EIP-4844 blob proofs.

When non-NIL, the value must be a function of BLOB, COMMITMENT, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defun kzg-point-proof-verification-available-p ()
  (functionp *kzg-point-proof-verifier*))

(defun kzg-blob-proof-verification-available-p ()
  (functionp *kzg-blob-proof-verifier*))

(defun kzg-proof-verification-available-p ()
  (and (kzg-point-proof-verification-available-p)
       (kzg-blob-proof-verification-available-p)))
