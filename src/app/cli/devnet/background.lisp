(in-package #:ethereum-lisp.cli)

;;;; Periodic background workers for devnet runtime maintenance.

(defconstant +devnet-payload-improvement-interval-seconds+ 2
  "Cadence for rebuilding open Engine payloads while the proposer waits.")

(defun devnet-start-payload-improvement-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (loop until (devnet-shutdown-requested-p shutdown-controller)
               do (loop repeat +devnet-payload-improvement-interval-seconds+
                        until (devnet-shutdown-requested-p shutdown-controller)
                        do (sleep 1))
                  (unless (devnet-shutdown-requested-p shutdown-controller)
                    (call-with-devnet-node-store-guard
                     node
                     (lambda ()
                       (engine-rpc-improve-open-payloads
                        (devnet-node-store node)
                        (devnet-node-config node))))))
       ;; MANDATORY, not defensive: the node runs as `sbcl --script`, which
       ;; implies --disable-debugger, so an unhandled SERIOUS-CONDITION here
       ;; (a STORAGE-CONDITION such as control-stack exhaustion is a
       ;; serious-condition that is NOT an ERROR, so an ERROR handler never
       ;; sees it) exits the whole process rather than fail-stopping the node.
       ;; Catch SERIOUS-CONDITION like every other worker in this file.
       (serious-condition (condition)
         (funcall error-callback condition)
         (devnet-shutdown-request shutdown-controller))))
   :name "ethereum-lisp-devnet-payload-improvement"))

(defun devnet-start-txpool-maintenance-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((lifetime (devnet-node-txpool-lifetime-seconds node)))
    (when lifetime
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (loop repeat 60
                            until (devnet-shutdown-requested-p
                                   shutdown-controller)
                            do (sleep 1))
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (call-with-devnet-node-store-guard
                         node
                         (lambda ()
                           (engine-payload-store-remove-expired-txpool-queued-view-transactions
                            (devnet-node-store node)
                            lifetime
                            (unix-time)
                            :local-transaction-predicate
                            (txpool-local-transaction-predicate
                             (devnet-node-config node)
                             (devnet-peer-txpool-policy node)))))))
           ;; MANDATORY, not defensive: the node runs as `sbcl --script`, which
           ;; implies --disable-debugger, so an unhandled SERIOUS-CONDITION here
           ;; (a STORAGE-CONDITION such as control-stack exhaustion is a
           ;; serious-condition that is NOT an ERROR, so an ERROR handler never
           ;; sees it) exits the whole process rather than fail-stopping the
           ;; node. Catch SERIOUS-CONDITION like every other worker in this file.
           (serious-condition (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-txpool-maintenance"))))

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
           (serious-condition (condition)
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
           (serious-condition (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-dev-period"))))

(defconstant +devnet-discovery-crawl-seconds+ 12
  "Budget for one crawl. Longer than the bare bond-and-ask crawl needed, because
a filtered crawl adds a request/response round trip per bonded node -- and a
node whose record has not arrived by the deadline is a node the crawl cannot
return. Our policy.")

(defconstant +devnet-discovery-crawl-alpha+ 6
  "Concurrent bond/query fan-out for the bounded public discovery crawl.")

(defconstant +devnet-discovery-crawl-max-queries+ 48
  "Maximum FindNode queries in one crawl while SNAP needs scarce public peers.")

(defconstant +devnet-discovery-crawl-seed-limit+ 256
  "Maximum endpoint-proven DHT routing hops retained process-locally.")

(defun devnet-discovery-next-crawl-seeds (bootnodes previous discovered)
  "Keep BOOTNODES plus recent endpoint-proven routing hops within one bound."
  (let* ((ordered
           (remove-duplicates
            (append bootnodes discovered previous)
            :test #'string= :from-end t))
         (count (min (length ordered)
                     +devnet-discovery-crawl-seed-limit+)))
    (subseq ordered 0 count)))

(defconstant +devnet-dns-discovery-refresh-seconds+ 300
  "How often to refresh an authenticated EIP-1459 tree after success. The root
has a short DNS TTL, while its Merkle entries are content addressed and remain
cacheable; five minutes keeps discovery current without downloading the tree on
every thirty-second discv4 crawl.")

(defun devnet-node-chain-context (node)
  "NODE's eth chain context, refreshed when the store guard happens to be free
and reused from the last refresh when it is not.

DISCOVERY MUST NEVER WAIT FOR THE STORE GUARD, and this is the whole reason
the function exists rather than the obvious call to DEVNET-PEER-SYNC-STATUS.
The guard is held for the duration of a block import. A discovery thread that
blocks on it does not merely run slower -- it stops entirely for as long as the
node is busy, which is exactly when finding peers matters. The peer table is
kept off this guard for the same reason (CALL-WITH-DEVNET-PEER-TABLE); this is
that rule applied to the fork id. It was learned the expensive way: taking the
guard here cost a live node every single crawl for half an hour.

Staleness is cheap by comparison. The only thing read out of the context is our
fork id, which changes when the head crosses a fork -- so a context minutes old
still answers correctly, and a fresh one is no better. NIL until the first
refresh succeeds, which turns filtering off rather than rejecting everybody."
  (let* ((store (devnet-node-store node))
         (genesis-block (devnet-node-genesis-block node))
         (genesis-hash (hash32-bytes (block-hash genesis-block)))
         (genesis-timestamp
           (block-header-timestamp
            (block-header genesis-block))))
    (multiple-value-bind (head ran-p)
        (call-with-devnet-node-store-guard-if-free
         node
         (lambda ()
           (ignore-errors
            (let ((head-number (chain-store-head-number store)))
              (list head-number
                    (block-header-timestamp
                     (block-header (chain-store-latest-block store)))
                    (hash32-bytes (chain-store-canonical-hash store 0)))))))
      (when (and ran-p head)
        (setf (devnet-node-chain-context-cache node)
              (make-eth-chain-context (devnet-node-config node)
                                      (third head) (first head) (second head)
                                      genesis-timestamp)))
      (or
       (devnet-node-chain-context-cache node)
       ;; SNAP import deliberately holds the store guard across its durable
       ;; state transition. Discovery can race that import on a fresh process,
       ;; before any head snapshot has populated the cache. The chain is still
       ;; unambiguous at genesis: publish and enforce its EIP-2124 fork id now
       ;; instead of admitting an unfiltered shared-DHT candidate set for the
       ;; entire state download.
       (setf (devnet-node-chain-context-cache node)
             (make-eth-chain-context
              (devnet-node-config node) genesis-hash 0 genesis-timestamp
              genesis-timestamp))))))

(defun devnet-node-record-pairs (node)
  "The endpoint and chain-specific ENR entries this node advertises.

Recomputed per request rather than cached, because our fork id moves as the head
crosses a fork and a record still advertising the previous one is precisely the
stale advertisement that gets a node filtered out."
  (let* ((chain-context (devnet-node-chain-context node))
         (host (devnet-node-advertised-host node))
         (port (devnet-node-p2p-port node))
         (endpoint-pairs
           (when port
             (list
              (cons "ip"
                    (ensure-byte-vector
                     (sb-bsd-sockets:make-inet-address host)))
              (cons "tcp" (integer-to-minimal-bytes port))
              (cons "udp" (integer-to-minimal-bytes port))))))
    (let ((pairs
            (append endpoint-pairs
                    (when chain-context
                      (eth-chain-context-record-pairs chain-context)))))
      (unless (equalp pairs (devnet-node-enr-pairs node))
        (when (devnet-node-enr-pairs node)
          (let ((next (1+ (devnet-node-enr-seq node))))
            (when (devnet-node-enr-seq-persistence-function node)
              (funcall (devnet-node-enr-seq-persistence-function node) next))
            (setf (devnet-node-enr-seq node) next)))
        (setf (devnet-node-enr-pairs node) pairs))
      pairs)))

(defun devnet-node-record-seq (node)
  "The monotonic sequence of the endpoint/fork-id pairs last constructed."
  (devnet-node-enr-seq node))

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
  "Start authenticated DNS and discv4 discovery, or NIL when neither is set.

Both transports only offer candidates to the dial scheduler. EIP-1459 runs
first so its chain-filtered, signed records cannot be crowded out by the noisy
cross-chain discv4 DHT. Transport failures are logged and retried; only an
escaping serious condition is fail-stop."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((bootnodes (devnet-node-bootnodes node))
        (dns-url (devnet-node-discovery-dns node)))
    (when (and (devnet-node-discovery-enabled-p node)
               (or bootnodes dns-url))
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (let ((private-key (devnet-node-node-key node))
                   (previous-dns-sequence
                     (devnet-node-discovery-dns-sequence node))
                   (next-dns-refresh-at 0)
                   (crawl-seeds (copy-list bootnodes)))
               (labels ((offer (found)
                          (call-with-devnet-peer-table
                           node
                           (lambda ()
                             (dolist (enode found)
                               (ignore-errors
                                (devnet-dial-registry-offer-dynamic
                                 (devnet-node-dial-registry node)
                                 (node-id-to-hex
                                  (nth-value 0 (parse-enode-url enode)))
                                 enode)))))))
                 (loop until (devnet-shutdown-requested-p shutdown-controller) do
                   (let ((record-filter (devnet-discovery-record-filter node))
                         (now (get-universal-time)))
                     (when (and dns-url (>= now next-dns-refresh-at))
                       (handler-case
                           (multiple-value-bind (found sequence stats)
                               (eip1459-resolve-enodes
                                dns-url
                                :previous-sequence previous-dns-sequence
                                :record-filter record-filter)
                             ;; Publish candidates only after the new rollback
                             ;; floor is durable. A crash can repeat work, but
                             ;; cannot make the next process accept an older
                             ;; signed root it had already observed.
                             (when (devnet-node-discovery-dns-sequence-persistence-function
                                    node)
                               (funcall
                                (devnet-node-discovery-dns-sequence-persistence-function
                                 node)
                                sequence))
                             (setf previous-dns-sequence sequence
                                   (devnet-node-discovery-dns-sequence node)
                                   sequence
                                   next-dns-refresh-at
                                   (+ now +devnet-dns-discovery-refresh-seconds+))
                             (offer found)
                             (telemetry-log
                              :info "peer.discovery.dns"
                              :fields
                              (append
                               (list (cons "sequence" (princ-to-string sequence)))
                               (loop for (name . count) in stats
                                     collect (cons name (princ-to-string count)))
                               (list
                                (cons "filtered"
                                      (if record-filter "true" "false"))
                                (cons "offered"
                                      (princ-to-string (length found)))))
                              :sink (devnet-node-telemetry-sink node)))
                         (error (condition)
                           ;; A transient resolver failure retries on the normal
                           ;; 30-second worker cadence rather than waiting five
                           ;; minutes. The last accepted sequence remains the
                           ;; rollback floor.
                           (setf next-dns-refresh-at (+ now 30))
                           (telemetry-log
                            :warning "peer.discovery.dns_failed"
                            :fields
                            (list (cons "error" (princ-to-string condition)))
                            :sink (devnet-node-telemetry-sink node)))))
                     (when bootnodes
                       (handler-case
                           (multiple-value-bind (found stats bonded-enodes)
                               (discv4-lookup
                                crawl-seeds private-key
                                :alpha +devnet-discovery-crawl-alpha+
                                :max-queries
                                +devnet-discovery-crawl-max-queries+
                                :timeout-seconds +devnet-discovery-crawl-seconds+
                                :local-tcp-port (or (devnet-node-p2p-port node) 0)
                                :advertised-host
                                (devnet-node-advertised-host node)
                                :record-filter record-filter)
                             (setf crawl-seeds
                                   (devnet-discovery-next-crawl-seeds
                                    bootnodes crawl-seeds bonded-enodes))
                             (telemetry-log
                              :info "peer.discovery.crawl"
                              :fields
                              (append
                               (loop for (name . count) in stats
                                     collect (cons name (princ-to-string count)))
                               (list
                                (cons "filtered"
                                      (if record-filter "true" "false"))
                                (cons "offered"
                                      (princ-to-string (length found)))
                                (cons "routingSeeds"
                                      (princ-to-string
                                       (length crawl-seeds)))))
                              :sink (devnet-node-telemetry-sink node))
                             (offer found))
                         (error (condition)
                           (telemetry-log
                            :warning "peer.discovery.crawl_failed"
                            :fields
                            (list (cons "error" (princ-to-string condition)))
                            :sink (devnet-node-telemetry-sink node))))))
                   (loop repeat 30
                         until (devnet-shutdown-requested-p shutdown-controller)
                         do (sleep 1)))))
           (serious-condition (condition)
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
         (multiple-value-bind (pong ping-back)
             (discv4-serve-ping
              private-key table packet data sender host port now
              :local-endpoint
              (discv4-endpoint-for-host
               (devnet-node-advertised-host node)
               (devnet-node-p2p-port node)
               (devnet-node-p2p-port node)))
           (when pong
             (devnet-peer-manager-log node "p2p.discovery.ping" "host" host)
             (remove nil (list pong ping-back)))))
        ((= type +discv4-packet-find-node+)
         (let ((packets (discv4-serve-find-node
                         private-key table data sender now
                         :requester-host host)))
           (when packets
             (devnet-peer-manager-log node "p2p.discovery.find_node"
                                      "host" host "packets" (length packets)))
           packets))
        ((= type +discv4-packet-enr-request+)
         (let ((response (discv4-serve-enr-request
                          private-key table data sender packet now
                          :record-pairs (devnet-node-record-pairs node)
                          :record-seq (devnet-node-record-seq node))))
           (when response (list response))))
        ((= type +discv4-packet-pong+)
         ;; Only the exact answer to our outstanding Ping proves the endpoint.
         (let ((pong (decode-discv4-pong data)))
           (unless (discv4-expired-p (discv4-pong-expiration pong))
             (discv4-table-accept-pong
              table sender host port (discv4-pong-ping-hash pong) now)))
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

(defun devnet-discovery-revalidation-probe (node private-key table now)
  "Build one routing-table endpoint probe.

Returns (VALUES PACKET HOST UDP-PORT), or no values when no entry is due. The
table caller holds the peer-table lock while choosing and recording the probe,
so a Pong cannot race ahead of PENDING-PING-HASH."
  (let ((entry (discv4-table-revalidation-candidate table now)))
    (when entry
      (let* ((host (discv4-table-entry-host entry))
             (udp-port (discv4-table-entry-udp-port entry))
             (from
               (discv4-endpoint-for-host
                (devnet-node-advertised-host node)
                (devnet-node-p2p-port node)
                (devnet-node-p2p-port node)))
             (to
               (discv4-endpoint-for-host
                host udp-port (discv4-table-entry-tcp-port entry)))
             (packet
               (encode-discv4-packet
                private-key +discv4-packet-ping+
                (encode-discv4-ping
                 (make-discv4-ping
                  :from from :to to :expiration (discv4-expiration))))))
        (discv4-table-note-ping
         table (discv4-table-entry-node-id entry) (subseq packet 0 32) now)
        (values packet host udp-port)))))

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
    (when (and (devnet-node-discovery-enabled-p node) port)
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
                                                        packet-port))))
                                   (multiple-value-bind
                                       (probe probe-host probe-port)
                                       (call-with-devnet-peer-table
                                        node
                                        (lambda ()
                                          (devnet-discovery-revalidation-probe
                                           node private-key table (unix-time))))
                                     (when probe
                                       (discv4-send-to
                                        socket probe probe-host probe-port))))
                               (error (condition)
                                 (devnet-peer-manager-log
                                  node "p2p.discovery.packet_failed"
                                  "error" condition))))
                 (ignore-errors (sb-bsd-sockets:socket-close socket)))
             (serious-condition (condition)
               (funcall error-callback condition)
               (devnet-shutdown-request shutdown-controller))))
         :name "ethereum-lisp-devnet-discovery-server")))))
