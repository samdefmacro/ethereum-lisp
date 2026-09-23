;;;; Operations crash worker: one node operation in a real process, to be killed.
;;;;
;;;; Usage: sbcl --script scripts/ops-crash-worker.lisp MODE WORKDIR
;;;;
;;;; Each MODE runs one production operation against a RocksDB store under
;;;; WORKDIR and publishes its progress to WORKDIR/marker.sexp as it goes. The
;;;; parent test SIGKILLs (or SIGTERMs) this process while the operation is in
;;;; flight, then reopens the store and checks what survived. The scenarios live
;;;; in tests/ops-recovery-tests.lisp, so this process loads the test system:
;;;; the parent and the child then share one definition of every fixture. See
;;;; OPS-RECOVERY-WORKER-MAIN there for the modes.

(defparameter *root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)
(asdf:load-asd (merge-pathnames "ethereum-lisp.asd" *root*))
(asdf:load-system :ethereum-lisp/test)

(let ((args (cdr sb-ext:*posix-argv*)))
  (when (and args (string= (first args) "--"))
    (setf args (rest args)))
  (unless (= 2 (length args))
    (format *error-output* "usage: ops-crash-worker.lisp MODE WORKDIR~%")
    (sb-ext:exit :code 2))
  (sb-ext:exit
   :code (funcall (find-symbol "OPS-RECOVERY-WORKER-MAIN" "ETHEREUM-LISP.TEST")
                  (first args) (second args))))
