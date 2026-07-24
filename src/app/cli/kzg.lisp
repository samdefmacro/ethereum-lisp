(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped KZG verifier configuration.

(defun call-with-devnet-cli-kzg-verifier (thunk)
  "Run THUNK with the in-process c-kzg CFFI verifier installed when available.

Blob verification runs in-process (see ethereum-lisp.kzg); a host without the
library keeps KZG capability-gated, exactly as before there was any verifier."
  (unless (functionp thunk)
    (error "Devnet KZG verifier thunk must be a function"))
  ;; Assigned rather than dynamically bound: the node serves the Engine endpoint
  ;; on its own thread, and a LET binding is thread-local in SBCL, so the
  ;; verifier would be invisible to the thread that validates blob proofs.
  (let ((previous-verifier *kzg-verifier*))
    (unwind-protect
         (progn
           (let ((cffi-verifier (make-kzg-cffi-verifier)))
             (when cffi-verifier
               (setf *kzg-verifier* cffi-verifier)))
           (funcall thunk))
      (setf *kzg-verifier* previous-verifier))))
