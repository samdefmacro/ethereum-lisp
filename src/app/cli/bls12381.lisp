(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped EIP-2537 backend configuration.

(defun call-with-devnet-cli-bls12381-backend
    (command timeout-seconds thunk)
  "Run THUNK with a COMMAND-backed EIP-2537 backend installed.

The helper process is persistent, so it is shut down when THUNK returns rather
than left behind for the lifetime of the image."
  (unless (functionp thunk)
    (error "Devnet BLS12-381 backend thunk must be a function"))
  (if (null command)
      (funcall thunk)
      (multiple-value-bind (function backend)
          (make-bls12381-command-backend command)
        (let ((*bls12381-backend-timeout-seconds*
                (or timeout-seconds *bls12381-backend-timeout-seconds*))
              (*bls12381-backend* function))
          (unwind-protect (funcall thunk)
            (shutdown-bls12381-command-backend backend))))))
