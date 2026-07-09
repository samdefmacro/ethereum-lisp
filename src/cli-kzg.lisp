(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped KZG verifier configuration.

(defun call-with-devnet-cli-kzg-verifier
    (command timeout-seconds thunk)
  (unless (functionp thunk)
    (error "Devnet KZG verifier thunk must be a function"))
  (let ((old-point-verifier *kzg-point-proof-verifier*)
        (old-blob-verifier *kzg-blob-proof-verifier*))
    (unwind-protect
         (let ((*kzg-verifier-command-timeout-seconds*
                 (or timeout-seconds
                     *kzg-verifier-command-timeout-seconds*)))
           (when command
             (configure-kzg-proof-command-verifiers command))
           (funcall thunk))
      (setf *kzg-point-proof-verifier* old-point-verifier
            *kzg-blob-proof-verifier* old-blob-verifier))))
