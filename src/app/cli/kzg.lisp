(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped KZG verifier configuration.

(defun call-with-devnet-cli-kzg-verifier
    (command timeout-seconds thunk)
  (unless (functionp thunk)
    (error "Devnet KZG verifier thunk must be a function"))
  (let ((*kzg-verifier-command-timeout-seconds*
          (or timeout-seconds
              *kzg-verifier-command-timeout-seconds*))
        (*kzg-verifier*
          (if command
              (make-kzg-command-verifier command)
              *kzg-verifier*)))
    (funcall thunk)))
