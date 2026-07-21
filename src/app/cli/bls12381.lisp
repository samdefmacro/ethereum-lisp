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
        ;; Assigned rather than dynamically bound: the node serves the Engine
        ;; endpoint on its own thread, and a LET binding is thread-local in
        ;; SBCL. Binding here would leave the backend invisible to the very
        ;; thread that executes payloads, so every BLS precompile would report
        ;; the backend as unavailable despite the flag being set.
        (let ((previous-backend *bls12381-backend*)
              (previous-timeout *bls12381-backend-timeout-seconds*))
          (unwind-protect
               (progn
                 (when timeout-seconds
                   (setf *bls12381-backend-timeout-seconds* timeout-seconds))
                 (setf *bls12381-backend* function)
                 (funcall thunk))
            (setf *bls12381-backend* previous-backend
                  *bls12381-backend-timeout-seconds* previous-timeout)
            (shutdown-bls12381-command-backend backend))))))
