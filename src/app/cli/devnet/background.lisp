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
                        (handler-case
                            (devnet-dev-period-state-tick state)
                          ;; KV batch errors promise that no durable operation
                          ;; remains visible.  The seal rollback restores the
                          ;; old public view and leaves LAST-RUN-TIME unchanged,
                          ;; so a later worker tick can safely retry.  Execution
                          ;; and invariant failures still reach the outer
                          ;; fail-stop handler below.
                          (storage-error (condition)
                            (telemetry-log
                             :warning
                             "devnet.dev_period.persistence_retry"
                             :fields
                             (list
                              (cons "error"
                                    (princ-to-string condition)))
                             :sink (devnet-node-telemetry-sink node))))))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-dev-period"))))

(defun devnet-start-discovery-thread
    (node shutdown-controller error-callback)
  "Start the discv4 discovery worker, or return NIL when no bootnodes are
configured (or off SBCL). It crawls the bootnodes for peers and dials each new
one into the node via the peer-sync path, re-crawling periodically. A per-peer
failure is logged and skipped; only an escaping error is fail-stop."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((bootnodes (devnet-node-bootnodes node)))
    (when bootnodes
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (let ((private-key (secp256k1-random-private-key))
                   (dialed (make-hash-table :test 'equal)))
               (loop until (devnet-shutdown-requested-p shutdown-controller) do
                 (dolist (enode (discv4-lookup bootnodes private-key))
                   (when (devnet-shutdown-requested-p shutdown-controller)
                     (return))
                   (unless (gethash enode dialed)
                     (setf (gethash enode dialed) t)
                     (handler-case
                         (devnet-peer-sync-one node enode private-key)
                       (error (condition)
                         (telemetry-log
                          :warning "peer.sync.peer_failed"
                          :fields (list (cons "enode" enode)
                                        (cons "error" (princ-to-string condition)))
                          :sink (devnet-node-telemetry-sink node))))))
                 ;; Re-crawl periodically, waking each second to notice shutdown.
                 (loop repeat 30
                       until (devnet-shutdown-requested-p shutdown-controller)
                       do (sleep 1))))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-discovery"))))
