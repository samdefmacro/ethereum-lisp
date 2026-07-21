(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped KZG verifier configuration.

(defun call-with-devnet-cli-kzg-verifier
    (command timeout-seconds thunk)
  (unless (functionp thunk)
    (error "Devnet KZG verifier thunk must be a function"))
  ;; Assigned rather than dynamically bound: the node serves the Engine endpoint
  ;; on its own thread, and a LET binding is thread-local in SBCL, so the
  ;; verifier would be invisible to the thread that validates blob proofs.
  (let ((previous-verifier *kzg-verifier*)
        (previous-timeout *kzg-verifier-command-timeout-seconds*))
    (unwind-protect
         (progn
           (when timeout-seconds
             (setf *kzg-verifier-command-timeout-seconds* timeout-seconds))
           (when command
             (setf *kzg-verifier* (make-kzg-command-verifier command)))
           (funcall thunk))
      (setf *kzg-verifier* previous-verifier
            *kzg-verifier-command-timeout-seconds* previous-timeout))))
