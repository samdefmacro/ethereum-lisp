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

(defconstant +devnet-discovery-crawl-seconds+ 8
  "Budget for one crawl. Longer than the bare bond-and-ask crawl needed, because
a filtered crawl adds a request/response round trip per bonded node -- and a
node whose record has not arrived by the deadline is a node the crawl cannot
return. Our policy.")

(defun devnet-node-chain-context (node)
  "NODE's eth chain context at the current head, or NIL if it cannot be read.

Best-effort on purpose: both callers below are discovery, and discovery that
cannot describe our chain should degrade rather than take the node down."
  (ignore-errors (nth-value 2 (devnet-peer-sync-status node))))

(defun devnet-node-record-pairs (node)
  "The chain-specific ENR entries this node advertises.

Recomputed per request rather than cached, because our fork id moves as the head
crosses a fork and a record still advertising the previous one is precisely the
stale advertisement that gets a node filtered out."
  (let ((chain-context (devnet-node-chain-context node)))
    (when chain-context
      (eth-chain-context-record-pairs chain-context))))

(defun devnet-discovery-record-filter (node)
  "A predicate on a discovered node's ENR: is it on our chain?

Rebuilt for each crawl rather than captured once, for the same reason the served
record is: our own fork id moves with the head, and a filter frozen at startup
would go on judging peers against a fork we have since crossed.

Returns NIL when our own chain context cannot be read, which turns filtering OFF
for that crawl rather than rejecting everybody. A node that cannot say what
chain it is on has no basis to refuse anyone else's."
  (let ((chain-context (devnet-node-chain-context node)))
    (when chain-context
      (lambda (record)
        (eth-chain-context-record-compatible-p
         chain-context (enr-value record "eth"))))))

(defun devnet-start-discovery-thread
    (node shutdown-controller error-callback)
  "Start the discv4 crawl worker, or return NIL when no bootnodes are configured
(or off SBCL). It crawls the bootnodes and offers what it finds to the dial
scheduler, re-crawling periodically. It no longer dials anything itself: doing
that here meant one slow peer stalled every later dial on this thread. A failed
crawl is logged and retried; only an escaping error is fail-stop."
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
                     (multiple-value-bind (found stats)
                         (discv4-lookup
                          bootnodes private-key
                          :timeout-seconds +devnet-discovery-crawl-seconds+
                          :record-filter (devnet-discovery-record-filter node))
                       ;; Log the crawl's shape every time, not just when it
                       ;; goes wrong. A filtered crawl legitimately returns far
                       ;; fewer nodes than an unfiltered one, so without the
                       ;; counts behind the number there is no way to tell a
                       ;; working filter from a broken crawl.
                       (telemetry-log
                        :info "peer.discovery.crawl"
                        :fields (append
                                 (loop for (name . count) in stats
                                       collect (cons name
                                                     (princ-to-string count)))
                                 (list (cons "offered"
                                             (princ-to-string (length found)))))
                        :sink (devnet-node-telemetry-sink node))
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


;;;; Answering discovery.
;;;;
;;;; The crawl above asks questions. This thread answers them, which is what
;;;; makes the node findable by anyone who did not already have its enode.
;;;; It owns one long-lived UDP socket for the node's lifetime, unlike the
;;;; crawl, whose socket exists only while it runs.

(defconstant +devnet-discovery-tick-seconds+ 1
  "How long one receive waits before the loop re-checks for shutdown. Our
policy.")

(defun devnet-discovery-handle-packet (node private-key table packet host port)
  "Dispatch one received discovery packet, returning the replies to send.

Every branch is guarded by the sender having proved its endpoint, except Ping
itself -- which is how a sender proves it. A packet we cannot decode is dropped:
an unsigned or malformed datagram is not something to answer."
  (multiple-value-bind (type data sender) (decode-discv4-packet packet)
    (let ((now (unix-time)))
      (cond
        ((= type +discv4-packet-ping+)
         (let ((pong (discv4-serve-ping private-key table packet data sender
                                        host now)))
           (when pong
             (devnet-peer-manager-log node "p2p.discovery.ping" "host" host)
             (list pong))))
        ((= type +discv4-packet-find-node+)
         (let ((packets (discv4-serve-find-node private-key table data sender now)))
           (when packets
             (devnet-peer-manager-log node "p2p.discovery.find_node"
                                      "host" host "packets" (length packets)))
           packets))
        ((= type +discv4-packet-enr-request+)
         (let ((response (discv4-serve-enr-request
                          private-key table data sender packet now
                          :record-pairs (devnet-node-record-pairs node))))
           (when response (list response))))
        ((= type +discv4-packet-pong+)
         ;; Somebody answered a Ping of ours: proof enough to keep them.
         (let ((entry (discv4-table-entry table sender)))
           (when entry
             (discv4-table-put table sender host
                               (discv4-table-entry-udp-port entry)
                               (discv4-table-entry-tcp-port entry)
                               now :bonded t)))
         nil)
        ((= type +discv4-packet-neighbors+)
         ;; Nodes somebody else vouches for. Recorded UNBONDED: we have not
         ;; heard from them ourselves, so they are not passed on to anyone yet.
         (let ((reply (decode-discv4-neighbors data)))
           (unless (discv4-expired-p (discv4-neighbors-expiration reply))
             (dolist (peer (discv4-neighbors-nodes reply))
               (ignore-errors
                (let ((peer-host (discv4-ip-string (discv4-node-ip peer))))
                  (when peer-host
                    (discv4-table-put table (discv4-node-node-id peer) peer-host
                                      (discv4-node-udp-port peer)
                                      (discv4-node-tcp-port peer)
                                      now)))))))
         nil)
        (t nil)))))

(defun devnet-start-discovery-server-thread
    (node shutdown-controller error-callback)
  "Start the discv4 responder, or return NIL when the node has no p2p port.

Bound to the same port number as the TCP listener, which is the convention an
enode URL assumes: one number identifies both a node's TCP and UDP endpoints.
A malformed or hostile packet is logged and the loop CONTINUES -- a public UDP
port receives junk as a matter of course, and taking discovery down for it would
be a liveness bug."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((port (devnet-node-p2p-port node)))
    (when port
      (let* ((private-key (devnet-node-node-key node))
             (table (devnet-node-discovery-table node))
             (socket (discv4-make-socket
                      :host (or (devnet-node-p2p-host node) "0.0.0.0")
                      :port port)))
        ;; Registered before the loop starts: closing the socket is what wakes a
        ;; receive that is already blocked.
        (devnet-shutdown-controller-add-closeable
         shutdown-controller
         (lambda () (ignore-errors (sb-bsd-sockets:socket-close socket))))
        (sb-thread:make-thread
         (lambda ()
           (handler-case
               (unwind-protect
                    (loop until (devnet-shutdown-requested-p shutdown-controller)
                          do (handler-case
                                 (multiple-value-bind (packet host packet-port)
                                     (discv4-receive socket
                                                     +devnet-discovery-tick-seconds+)
                                   (when packet
                                     (dolist (reply
                                              (call-with-devnet-peer-table
                                               node
                                               (lambda ()
                                                 (devnet-discovery-handle-packet
                                                  node private-key table packet
                                                  host packet-port))))
                                       (ignore-errors
                                        (discv4-send-to socket reply host
                                                        packet-port)))))
                               (error (condition)
                                 (devnet-peer-manager-log
                                  node "p2p.discovery.packet_failed"
                                  "error" condition))))
                 (ignore-errors (sb-bsd-sockets:socket-close socket)))
             (error (condition)
               (funcall error-callback condition)
               (devnet-shutdown-request shutdown-controller))))
         :name "ethereum-lisp-devnet-discovery-server")))))
