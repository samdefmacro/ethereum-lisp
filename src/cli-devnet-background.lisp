(in-package #:ethereum-lisp.cli)

;;;; Periodic background workers for devnet runtime maintenance.

(defun devnet-start-rejournal-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-rejournal-state
           node
           (devnet-node-txpool-rejournal-seconds node))))
    (when (devnet-rejournal-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-rejournal-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-txpool-rejournal"))))

(defun devnet-start-dev-period-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-dev-period-state
           node
           (devnet-node-dev-period-seconds node))))
    (when (devnet-dev-period-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-dev-period-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-dev-period"))))
