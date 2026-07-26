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
             ;; Share the node's stable identity, and the node-wide dialed set,
             ;; The crawl only produces candidates; the dial scheduler decides
             ;; which to dial and when.
             (let ((private-key (devnet-node-node-key node)))
               (loop until (devnet-shutdown-requested-p shutdown-controller) do
                 ;; Discovery is best-effort: a failed crawl (socket exhaustion,
                 ;; a bad packet) is logged and retried, never a node-wide
                 ;; fail-stop.
                 (handler-case
                     ;; Offer what the crawl found to the dial scheduler and
                     ;; move on. This thread no longer dials: doing it here meant
                     ;; one slow peer stalled every later dial on the same
                     ;; thread, and the fixed crawl interval was the only
                     ;; backoff there was.
                     (let ((found (discv4-lookup bootnodes private-key
                                                 :timeout-seconds 4)))
                       (call-with-devnet-peer-table
                        node
                        (lambda ()
                          (dolist (enode found)
                            (ignore-errors
                             (devnet-dial-registry-offer-dynamic
                              (devnet-node-dial-registry node)
                              (node-id-to-hex
                               (nth-value 0 (parse-enode-url enode)))
                              enode))))))
                   (error (condition)
                     (telemetry-log
                      :warning "peer.discovery.crawl_failed"
                      :fields (list (cons "error" (princ-to-string condition)))
                      :sink (devnet-node-telemetry-sink node))))
                 ;; Re-crawl periodically, waking each second to notice shutdown.
                 (loop repeat 30
                       until (devnet-shutdown-requested-p shutdown-controller)
                       do (sleep 1))))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-discovery"))))
