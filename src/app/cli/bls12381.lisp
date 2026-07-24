(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped EIP-2537 backend configuration.

(defun call-with-devnet-cli-bls12381-backend (thunk)
  "Run THUNK with the in-process blst CFFI backend installed when available.

EIP-2537 runs in-process (see ethereum-lisp.bls12381); a host without the
library keeps BLS capability-gated, exactly as before there was any backend."
  (unless (functionp thunk)
    (error "Devnet BLS12-381 backend thunk must be a function"))
  ;; Assigned rather than dynamically bound for the thread-visibility reason
  ;; spelled out in CALL-WITH-DEVNET-CLI-KZG-VERIFIER: the node executes
  ;; payloads on its listener threads, and a LET binding is thread-local.
  (let ((previous-backend *bls12381-backend*))
    (unwind-protect
         (progn
           (let ((cffi-function (make-bls12381-cffi-backend)))
             (when cffi-function
               (setf *bls12381-backend* cffi-function)))
           (funcall thunk))
      (setf *bls12381-backend* previous-backend))))
