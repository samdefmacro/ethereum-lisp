(in-package #:ethereum-lisp.bls12381)

;;;; Capability boundary for the EIP-2537 BLS12-381 group operations.
;;;;
;;;; The precompile layer owns input parsing and gas; the arithmetic is
;;;; delegated to a backend installed here. When no backend is installed the
;;;; operations are unavailable rather than silently wrong, matching the
;;;; treatment of KZG proof verification.

(defparameter +bls12381-operations+
  '(:g1-add :g1-msm :g2-add :g2-msm :pairing-check :map-fp-to-g1 :map-fp2-to-g2)
  "Operations an EIP-2537 backend must implement.")

(defvar *bls12381-backend* nil
  "Optional backend for EIP-2537 BLS12-381 group operations.

When non-NIL, the value must be a function of an OPERATION keyword drawn from
+BLS12381-OPERATIONS+ and an INPUT byte vector. It returns the operation output
as a byte vector, or signals an error when the input is rejected.")

(defun bls12381-backend-available-p ()
  "Return true when EIP-2537 group operations can be evaluated."
  (functionp *bls12381-backend*))

(defun run-bls12381-operation (operation input)
  "Evaluate OPERATION over INPUT using the installed backend.

Signals an error when no backend is installed, when OPERATION is unknown, or
when the backend rejects INPUT."
  (unless (member operation +bls12381-operations+)
    (error "Unknown BLS12-381 operation: ~S" operation))
  (unless (bls12381-backend-available-p)
    (error "BLS12-381 group operations are not available"))
  (let ((output (funcall *bls12381-backend* operation (ensure-byte-vector input))))
    (unless (typep output '(vector (unsigned-byte 8)))
      (error "BLS12-381 backend returned a non-byte-vector result"))
    output))
