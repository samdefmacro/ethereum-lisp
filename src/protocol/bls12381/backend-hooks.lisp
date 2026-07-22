(in-package #:ethereum-lisp.bls12381)

;;;; Capability boundary for the EIP-2537 BLS12-381 group operations.
;;;;
;;;; The precompile layer owns input parsing and gas; the arithmetic is
;;;; delegated to a backend installed here. Two failure classes are kept
;;;; distinct because they demand opposite consensus responses:
;;;;
;;;;   BLS12381-INPUT-ERROR       the backend gave a definite verdict that the
;;;;                              input is invalid. Deterministic — every node
;;;;                              agrees — so the precompile fails and burns gas.
;;;;   BLS12381-UNAVAILABLE-ERROR the backend could not be consulted at all
;;;;                              (absent, crashed, timed out, malformed reply).
;;;;                              NOT a consensus verdict: a node with a working
;;;;                              backend would answer differently, so this must
;;;;                              propagate and make the node refuse to validate
;;;;                              rather than fabricate a result.

(define-condition bls12381-error (error)
  ((message :initarg :message :reader bls12381-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (bls12381-error-message condition)))))

(define-condition bls12381-input-error (bls12381-error) ()
  (:documentation "A definite backend verdict that the input is invalid."))

(define-condition bls12381-unavailable-error (bls12381-error) ()
  (:documentation "The backend could not be consulted; not a consensus verdict."))

(defun bls12381-input-error (control &rest args)
  (error 'bls12381-input-error :message (apply #'format nil control args)))

(defun bls12381-unavailable-error (control &rest args)
  (error 'bls12381-unavailable-error :message (apply #'format nil control args)))

(defparameter +bls12381-operations+
  '(:g1-add :g1-msm :g2-add :g2-msm :pairing-check :map-fp-to-g1 :map-fp2-to-g2)
  "Operations an EIP-2537 backend must implement.")

(defvar *bls12381-backend* nil
  "Optional backend for EIP-2537 BLS12-381 group operations.

When non-NIL, the value must be a function of an OPERATION keyword drawn from
+BLS12381-OPERATIONS+ and an INPUT byte vector. It returns the operation output
as a byte vector, signals BLS12381-INPUT-ERROR when the input is invalid, and
signals BLS12381-UNAVAILABLE-ERROR when it cannot produce a verdict.")

(defun bls12381-backend-available-p ()
  "Return true when EIP-2537 group operations can be evaluated."
  (functionp *bls12381-backend*))

(defun run-bls12381-operation (operation input)
  "Evaluate OPERATION over INPUT using the installed backend.

Signals BLS12381-UNAVAILABLE-ERROR when no backend is installed or the backend
returns a malformed result, and propagates whatever the backend signals for a
given input."
  (unless (member operation +bls12381-operations+)
    (error "Unknown BLS12-381 operation: ~S" operation))
  (unless (bls12381-backend-available-p)
    (bls12381-unavailable-error "BLS12-381 group operations are not available"))
  (let ((output (funcall *bls12381-backend* operation (ensure-byte-vector input))))
    (unless (typep output '(vector (unsigned-byte 8)))
      (bls12381-unavailable-error
       "BLS12-381 backend returned a non-byte-vector result"))
    output))
