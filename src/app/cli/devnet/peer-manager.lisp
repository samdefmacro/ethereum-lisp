(in-package #:ethereum-lisp.cli)

;;;; Inbound peering: the accept loop, one session thread per peer, and getting
;;;; all of them to stop.
;;;;
;;;; Every thread this wave creates is created here, which is what keeps the
;;;; networking and protocol layers free of sb-thread entirely. The peer table
;;;; below is guarded by a mutex of this manager's own — never the node store
;;;; guard. That guard is a single non-recursive mutex serializing the RPC
;;;; services, block import, journaling and export; holding it across socket I/O
;;;; would not merely slow things down, it would hang shutdown, because the
;;;; rejournal and dev-period workers join without a timeout and both wait on it.
;;;;
;;;; SHUTDOWN IS THE HARD PART, and everything here is shaped by it. The accept
;;;; loop uses a readiness-gated accept, so it returns regularly whether or not
;;;; a peer ever arrives. Each session socket is registered as a shutdown
;;;; closeable BEFORE its handshake begins, so a shutdown mid-handshake closes
;;;; the descriptor and the blocked read errors out on its own. And a session's
;;;; cleanup closes its socket and touches nothing else -- no farewell
;;;; Disconnect, no flush -- because IGNORE-ERRORS catches errors, not blocking,
;;;; and a write to a peer that has stopped reading would hang teardown.

(defconstant +devnet-peer-handshake-timeout-seconds+ 5
  "How long an accepted connection has to start its handshake. Our policy. The
RLPx handshake read is otherwise unbounded, so a peer that connects and says
nothing would hold a thread and a descriptor indefinitely.")

(defconstant +devnet-peer-accept-tick-seconds+ 1
  "How long one accept waits before returning to check for shutdown. Our policy.")

(defconstant +devnet-snap-min-request-bytes+ (* 64 1024)
  "Smallest adaptive account/storage request, matching geth's lower cap.")

(defconstant +devnet-snap-max-request-bytes+ (* 512 1024)
  "Largest adaptive account/storage request, matching geth's upper cap.")

(defconstant +devnet-snap-storage-account-byte-estimate+ 1024
  "Geth's scheduling estimate for one account in a StorageRanges request.")

(defconstant +devnet-snap-max-bytecode-hashes+ 84
  "Geth's 512 KiB ByteCodes assignment cap in code items, not wire bytes.")

(defconstant +devnet-snap-max-trie-node-paths+ 1024
  "Maximum TrieNodes lookups assigned to one peer request.")

(defconstant +devnet-snap-request-target-seconds+ 6d0
  "Conservative geth-style wall time used to size one SNAP assignment.

Geth feeds its adaptive message capacity with the request timeout rather than
the raw round-trip target.  At its two-second minimum RTT and threefold timeout
scaling that floor is six seconds.  Using the RTT itself here strands code-item
capacity near one on ordinary one-to-two-second public peers.")

(defconstant +devnet-snap-rate-measurement-impact+ 0.2d0
  "EWMA weight of one SNAP response throughput and latency measurement.")

(defconstant +devnet-snap-qos-measurement-impact+ 0.1d0
  "Geth's EWMA weight for one peer's shared SNAP round-trip estimate.")

(defconstant +devnet-snap-qos-min-rtt-seconds+ 2d0
  "Geth's minimum useful SNAP service-time target.")

(defconstant +devnet-snap-qos-max-rtt-seconds+ 20d0
  "Geth's maximum SNAP service-time estimate before timeout scaling.")

(defconstant +devnet-snap-qos-timeout-scale+ 3d0
  "Geth's RTT-to-request-timeout multiplier.")

(defconstant +devnet-snap-qos-timeout-limit-seconds+ 60d0
  "Geth's maximum timeout for one SNAP request.")

(defconstant +devnet-snap-qos-cold-timeout-seconds+ 30d0
  "Safe startup timeout until the first live peer supplies an RTT sample.")

#+sbcl
(defun devnet-snap-qos-record-round-trip (qos queue elapsed)
  "Publish QUEUE's shared SNAP RTT EWMA into node-wide QOS."
  (unless (and (realp elapsed) (plusp elapsed))
    (error "Invalid SNAP QoS round-trip measurement"))
  (when qos
    (sb-thread:with-mutex ((devnet-snap-qos-lock qos))
      (let* ((samples (devnet-snap-qos-round-trips qos))
             (old (gethash queue samples))
             (impact +devnet-snap-qos-measurement-impact+))
        (setf (gethash queue samples)
              (if old
                  (+ (* (- 1d0 impact) old)
                     (* impact (float elapsed 1d0)))
                  (float elapsed 1d0))))))
  elapsed)

#+sbcl
(defun devnet-snap-qos-forget-queue (qos queue)
  "Remove a closed peer QUEUE from node-wide SNAP QoS."
  (when qos
    (sb-thread:with-mutex ((devnet-snap-qos-lock qos))
      (remhash queue (devnet-snap-qos-round-trips qos))))
  t)

#+sbcl
(defun devnet-snap-qos-target-timeout (qos)
  "Return Geth's three-RTT request deadline from the live peer pool.

Geth orders live peer RTTs and selects index sqrt(peer-count), which deliberately
leans toward the faster healthy part of a wide pool.  The estimate is clamped to
two--twenty seconds and scaled threefold, with a sixty-second ceiling.  Until a
pool has a sample, retain the existing conservative thirty-second allowance."
  (if (null qos)
      +devnet-snap-qos-cold-timeout-seconds+
      (sb-thread:with-mutex ((devnet-snap-qos-lock qos))
        (let ((round-trips '()))
          (maphash
           (lambda (queue round-trip)
             (declare (ignore queue))
             (push round-trip round-trips))
           (devnet-snap-qos-round-trips qos))
          (if (null round-trips)
              +devnet-snap-qos-cold-timeout-seconds+
              (let* ((ordered (sort round-trips #'<))
                     (count (length ordered))
                     (selected
                       (if (= count 1)
                           (first ordered)
                           (nth (floor (sqrt count)) ordered)))
                     (target-rtt
                       (max +devnet-snap-qos-min-rtt-seconds+
                            (min +devnet-snap-qos-max-rtt-seconds+
                                 selected))))
                (min +devnet-snap-qos-timeout-limit-seconds+
                     (* +devnet-snap-qos-timeout-scale+ target-rtt))))))))

#+sbcl
(defstruct (devnet-peer-snap-rate
            (:constructor make-devnet-peer-snap-rate (capacity)))
  capacity
  throughput
  round-trip
  (samples 0))

#+sbcl
(defstruct (devnet-peer-request-job
            (:constructor make-devnet-peer-request-job
                (function &key snap-response-id snap-request-id)))
  function
  ;; NIL identifies an ordinary synchronous eth/session job. A snap job names
  ;; its response message and request id, allowing one in-flight request per
  ;; snap response type without ever giving up the session's sole writer.
  snap-response-id
  snap-request-id
  started-at
  timeout-seconds
  deadline
  (lock (sb-thread:make-mutex :name "ethereum-lisp-peer-request-job"))
  (changed (sb-thread:make-waitqueue :name "ethereum-lisp-peer-request-job"))
  values
  condition
  done-p)

#+sbcl
(defstruct (devnet-peer-request-queue
            (:constructor make-devnet-peer-request-queue (&optional snap-qos)))
  (lock (sb-thread:make-mutex :name "ethereum-lisp-peer-request-queue"))
  (pending '())
  (active '())
  (snap-rates (make-hash-table))
  snap-qos
  closed-p)

#+sbcl
(defun devnet-peer-snap-capacity-bounds (response-id)
  "Return geth-compatible capacity units for one SNAP response type."
  (case response-id
    (#.ethereum-lisp.snap:+snap-message-bytecodes+
     (values 1 +devnet-snap-max-bytecode-hashes+))
    (#.ethereum-lisp.snap:+snap-message-trie-nodes+
     (values 1 +devnet-snap-max-trie-node-paths+))
    (otherwise
     (values +devnet-snap-min-request-bytes+
             +devnet-snap-max-request-bytes+))))

#+sbcl
(defun devnet-peer-snap-clamp-capacity (response-id capacity)
  (multiple-value-bind (minimum maximum)
      (devnet-peer-snap-capacity-bounds response-id)
    (max minimum (min maximum capacity))))

#+sbcl
(defun devnet-peer-request-queue-snap-rate (queue response-id)
  "Return RESPONSE-ID's mutable rate record while QUEUE's lock is held."
  (or (gethash response-id
               (devnet-peer-request-queue-snap-rates queue))
      (setf (gethash response-id
                     (devnet-peer-request-queue-snap-rates queue))
            (make-devnet-peer-snap-rate
             (nth-value
              0 (devnet-peer-snap-capacity-bounds response-id))))))

#+sbcl
(defun devnet-peer-request-queue-snap-capacity (queue response-id)
  "Return this peer's learned byte cap for one SNAP response type."
  (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
    (devnet-peer-snap-rate-capacity
     (devnet-peer-request-queue-snap-rate queue response-id))))

#+sbcl
(defun devnet-peer-request-queue-snap-statistics (queue response-id)
  "Return learned capacity, RTT seconds, and sample count for RESPONSE-ID."
  (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
    (let ((rate
            (devnet-peer-request-queue-snap-rate queue response-id)))
      (values (devnet-peer-snap-rate-capacity rate)
              (devnet-peer-snap-rate-round-trip rate)
              (devnet-peer-snap-rate-samples rate)))))

#+sbcl
(defun devnet-peer-request-queue-record-snap-delivery
    (queue response-id delivered-units elapsed)
  "Update RESPONSE-ID's capacity from one decoded SNAP delivery.

The bounded EWMA follows geth's message-rate strategy: slow peers remain useful
with small requests, while peers that repeatedly fill them quickly grow toward
the response type's cap. DELIVERED-UNITS is bytes for ranges, code count for
ByteCodes, and node count for TrieNodes. One sample may at most double or halve
the current cap, preventing a short tail response or a single fast cache hit
from causing an unstable jump."
  (unless (and (integerp delivered-units) (not (minusp delivered-units))
               (realp elapsed) (plusp elapsed))
    (error "Invalid SNAP delivery measurement"))
  (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
    (let* ((rate
             (devnet-peer-request-queue-snap-rate queue response-id))
           (sample-throughput (/ delivered-units (float elapsed 1d0)))
           (impact +devnet-snap-rate-measurement-impact+)
           (throughput
             (if (devnet-peer-snap-rate-throughput rate)
                 (+ (* (- 1d0 impact)
                       (devnet-peer-snap-rate-throughput rate))
                    (* impact sample-throughput))
                 sample-throughput))
           (round-trip
             (if (devnet-peer-snap-rate-round-trip rate)
                 (+ (* (- 1d0 impact)
                       (devnet-peer-snap-rate-round-trip rate))
                    (* impact elapsed))
                 (float elapsed 1d0)))
           (old-capacity (devnet-peer-snap-rate-capacity rate))
           ;; Match geth's escape from a stable minimum: the explicit +1 and
           ;; CEILING ensure a full response always probes a larger assignment,
           ;; even when its elapsed time is exactly the target.  The bounded
           ;; step below still prevents a single cache hit from jumping to max.
           (desired
             (devnet-peer-snap-clamp-capacity
              response-id
              (ceiling
               (+ 1d0
                  (* throughput
                     +devnet-snap-request-target-seconds+
                     1.01d0)))))
           (capacity
             (devnet-peer-snap-clamp-capacity
              response-id
              (max (floor old-capacity 2)
                   (min (* old-capacity 2) desired)))))
      (setf (devnet-peer-snap-rate-throughput rate) throughput
            (devnet-peer-snap-rate-round-trip rate) round-trip
            (devnet-peer-snap-rate-capacity rate) capacity)
      (incf (devnet-peer-snap-rate-samples rate))
      (devnet-snap-qos-record-round-trip
       (devnet-peer-request-queue-snap-qos queue) queue elapsed)
      capacity)))

#+sbcl
(defun devnet-peer-request-job-finish (job values condition)
  (sb-thread:with-mutex ((devnet-peer-request-job-lock job))
    (unless (devnet-peer-request-job-done-p job)
      (setf (devnet-peer-request-job-values job) values
            (devnet-peer-request-job-condition job) condition
            (devnet-peer-request-job-done-p job) t)
      (sb-thread:condition-broadcast
       (devnet-peer-request-job-changed job))
      t)))

#+sbcl
(defun devnet-peer-request-queue-close (queue)
  "Close QUEUE and fail every queued or in-flight coordinator job."
  (let ((jobs nil))
    (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
      (setf (devnet-peer-request-queue-closed-p queue) t
            jobs (append (devnet-peer-request-queue-pending queue)
                         (devnet-peer-request-queue-active queue))
            (devnet-peer-request-queue-pending queue) nil
            (devnet-peer-request-queue-active queue) nil))
    (dolist (job jobs)
      (devnet-peer-request-job-finish
       job nil
       (make-condition 'simple-error
                       :format-control "peer session closed"
                       :format-arguments nil))))
  (devnet-snap-qos-forget-queue
   (devnet-peer-request-queue-snap-qos queue) queue)
  t)

#+sbcl
(defun devnet-peer-request-queue-submit-job (queue job)
  "Queue JOB, wait for its session-owned completion, and return its values."
  (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
    (when (devnet-peer-request-queue-closed-p queue)
      (error "peer session request queue is closed"))
    (setf (devnet-peer-request-queue-pending queue)
          (nconc (devnet-peer-request-queue-pending queue) (list job))))
  (sb-thread:with-mutex ((devnet-peer-request-job-lock job))
    (loop until (devnet-peer-request-job-done-p job)
          do (sb-thread:condition-wait
              (devnet-peer-request-job-changed job)
              (devnet-peer-request-job-lock job))))
  (when (devnet-peer-request-job-condition job)
    (error (devnet-peer-request-job-condition job)))
  (values-list (devnet-peer-request-job-values job)))

#+sbcl
(defun devnet-peer-request-queue-submit (queue function)
  "Run synchronous FUNCTION on the queue's session writer."
  (unless (functionp function)
    (error "Peer request job must be a function"))
  (devnet-peer-request-queue-submit-job
   queue (make-devnet-peer-request-job function)))

#+sbcl
(defun devnet-peer-request-queue-submit-snap
    (queue peer message-id request)
  "Pipeline one typed snap request through PEER's sole-writer session.

Only one request for each response message type may be in flight. Different
account, storage, bytecode, and trie-node response types may overlap and are
routed back to their waiting worker by message type plus request id."
  (let ((request-id (ethereum-lisp.snap:snap-request-id message-id request)))
    (unless (integerp request-id)
      (error "Snap request has no request id for message ~D" message-id))
    (devnet-peer-request-queue-submit-job
     queue
     (make-devnet-peer-request-job
      (lambda ()
        (ethereum-lisp.eth-sync:eth-peer-start-snap-request
         peer message-id request))
      :snap-response-id (1+ message-id)
      :snap-request-id request-id))))

#+sbcl
(defun devnet-peer-request-monotonic-seconds ()
  (/ (get-internal-real-time)
     (float internal-time-units-per-second 1d0)))

#+sbcl
(defun devnet-peer-request-queue-complete-snap
    (queue job response payload-bytes)
  (let ((started-at (devnet-peer-request-job-started-at job)))
    (when started-at
      (devnet-peer-request-queue-record-snap-delivery
       queue (devnet-peer-request-job-snap-response-id job)
       (case (devnet-peer-request-job-snap-response-id job)
         (#.ethereum-lisp.snap:+snap-message-bytecodes+
          (length (ethereum-lisp.snap:snap-bytecodes-codes response)))
         (#.ethereum-lisp.snap:+snap-message-trie-nodes+
          (length (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
         (otherwise payload-bytes))
       ;; The in-memory integration source can answer within one timer tick.
       ;; One microsecond is still far below a network RTT and avoids a
       ;; division overflow without affecting production measurements.
       (max 1d-6
            (- (devnet-peer-request-monotonic-seconds) started-at)))))
  (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
    (setf (devnet-peer-request-queue-active queue)
          (delete job (devnet-peer-request-queue-active queue)
                  :test #'eq :count 1)))
  (devnet-peer-request-job-finish job (list response) nil))

#+sbcl
(defun devnet-peer-snap-response-handler (queue)
  "Return the session-owned decoder/router for QUEUE's pipelined responses."
  (lambda (message-id payload)
    (let ((job
            (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
              (find message-id (devnet-peer-request-queue-active queue)
                    :key #'devnet-peer-request-job-snap-response-id))))
      (when job
        (let ((response
                (ethereum-lisp.snap:decode-snap-message message-id payload)))
          (unless (= (devnet-peer-request-job-snap-request-id job)
                     (ethereum-lisp.snap:snap-response-id
                      message-id response))
            (error "Snap response id does not match its in-flight request"))
          (devnet-peer-request-queue-complete-snap
           queue job response (length payload))
          t)))))

#+sbcl
(defun devnet-peer-request-queue-take-eligible (queue)
  "Take one job that cannot consume a live response belonging to another job."
  (let ((now (devnet-peer-request-monotonic-seconds)))
    (sb-thread:with-mutex ((devnet-peer-request-queue-lock queue))
      (let ((expired
              (find-if
               (lambda (job)
                 (let ((deadline (devnet-peer-request-job-deadline job)))
                   (and deadline (>= now deadline))))
               (devnet-peer-request-queue-active queue))))
        (when expired
          (error
           "snap/1 request ~D exceeded the ~,2F second wall-clock deadline"
           (devnet-peer-request-job-snap-request-id expired)
           (devnet-peer-request-job-timeout-seconds expired))))
      (let ((job
              (find-if
               (lambda (candidate)
                 (let ((response-id
                         (devnet-peer-request-job-snap-response-id candidate)))
                   (if response-id
                       (not
                        (find response-id
                              (devnet-peer-request-queue-active queue)
                              :key #'devnet-peer-request-job-snap-response-id))
                       ;; ETH-PEER-AWAIT cannot coexist with an asynchronous
                       ;; snap response: it would reject that response as
                       ;; unsolicited. Run synchronous jobs only at an empty
                       ;; response seam.
                       (null (devnet-peer-request-queue-active queue)))))
               (devnet-peer-request-queue-pending queue))))
        (when job
          (setf (devnet-peer-request-queue-pending queue)
                (delete job (devnet-peer-request-queue-pending queue)
                        :test #'eq :count 1))
          (when (devnet-peer-request-job-snap-response-id job)
            (let ((timeout
                    (devnet-snap-qos-target-timeout
                     (devnet-peer-request-queue-snap-qos queue))))
              (setf (devnet-peer-request-job-started-at job) now
                    (devnet-peer-request-job-timeout-seconds job) timeout
                    (devnet-peer-request-job-deadline job) (+ now timeout)))
            (push job (devnet-peer-request-queue-active queue)))
          job)))))

#+sbcl
(defun devnet-peer-pending-request (queue)
  "Return a closure that hands the pump its next writer-owned request thunk."
  (lambda ()
    (let ((job (devnet-peer-request-queue-take-eligible queue)))
      (when job
        (lambda ()
          (handler-case
              (if (devnet-peer-request-job-snap-response-id job)
                  ;; Sending returns immediately; the session's read path
                  ;; finishes this job after decoding its matching response.
                  (funcall (devnet-peer-request-job-function job))
                  (devnet-peer-request-job-finish
                   job
                   (multiple-value-list
                    (funcall (devnet-peer-request-job-function job)))
                   nil))
            (serious-condition (condition)
              (when (devnet-peer-request-job-snap-response-id job)
                (sb-thread:with-mutex
                    ((devnet-peer-request-queue-lock queue))
                  (setf (devnet-peer-request-queue-active queue)
                        (delete job
                                (devnet-peer-request-queue-active queue)
                                :test #'eq :count 1))))
              (devnet-peer-request-job-finish job nil condition)
              ;; A mid-frame fault makes the stream unusable. Wake the
              ;; coordinator, then propagate so session teardown closes it.
              (error condition))))))))

(defun devnet-peer-manager-log (node event &rest fields)
  (telemetry-log :info event
                 :fields (loop for (key value) on fields by #'cddr
                               collect (cons key (princ-to-string value)))
                 ;; Taken from the node explicitly: the telemetry sink special
                 ;; is a defvar used as a keyword default, and a LET binding of
                 ;; a special is invisible to a spawned thread.
                 :sink (devnet-node-telemetry-sink node)))

(defun devnet-peer-disconnect-reason (verdict)
  (ecase verdict
    (:self +devp2p-disconnect-self+)
    (:already-connected +devp2p-disconnect-already-connected+)
    (:useless-peer +devp2p-disconnect-useless-peer+)
    (:too-many-peers +devp2p-disconnect-too-many-peers+)))

(defun devnet-peer-session-readable-function (peer)
  "A readiness gate for PEER's connection.

Asks the STREAM before the descriptor: the connection is fully buffered, so a
whole frame can already be sitting in the Lisp buffer while the descriptor
reports nothing to read. A gate that polls only the descriptor would call an
actively-talking peer idle and drop it."
  #-sbcl
  (declare (ignore peer))
  #-sbcl
  (lambda (timeout) (declare (ignore timeout)) t)
  #+sbcl
  (let ((stream (rlpx-connection-stream (eth-peer-connection peer))))
    (lambda (timeout)
      (or (listen stream)
          (and (sb-sys:fd-stream-p stream)
               (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd stream)
                                            :input timeout nil))))))

(defun devnet-peer-install-sync-notification (node peer)
  "Connect validated peer announcements to NODE's coordinator wakeup.

The callback carries no block hash or height.  It only makes the coordinator
re-read its CL-authorized target and the peer status already validated by the
eth session."
  (eth-peer-set-sync-notification-function
   peer (lambda () (devnet-node-notify-sync-coordinator node))))

(defun devnet-peer-run-session (node socket shutdown-controller admit-function
                                &key on-session-start reserved-slot-p stop-p
                                     reserved-host max-actions pending-broadcast)
  "Turn an open SOCKET into a peer session and serve it until it ends.

Runs on its own thread, and is shared by both directions: everything from
registering the shutdown closeable to the four-step teardown is identical
whether we accepted the connection or dialed it. Only two things differ, and
both are injected.

ADMIT-FUNCTION is called with SOCKET and returns (VALUES PEER ENTRY REFUSAL): a
handshaken peer plus the peer-table entry holding its slot, or a REFUSAL keyword
to send back as a devp2p reason. (VALUES NIL NIL NIL) means there is nothing to
do and falls straight through to teardown.

ON-SESSION-START, when given, runs once with the peer before the message pump.
It is the one thing the directions do differently afterwards: a dialed session
downloads the peer's chain to our tip, an accepted one has nothing to do.

PENDING-BROADCAST, when given, returns transactions of ours to push to this
peer; the session loop calls it and sends what it returns.

RESERVED-SLOT-P says whether teardown must release a handshake reservation.
Inbound takes one, because at accept time there is no identity to decide on;
a dial knows who it is calling before it connects and so never reserves."
  #-sbcl
  (declare (ignore node socket shutdown-controller admit-function
                   on-session-start reserved-slot-p stop-p max-actions
                   pending-broadcast reserved-host))
  #-sbcl
  nil
  #+sbcl
  (let ((table (devnet-node-peer-table node))
        (closeable nil)
        (admitted nil))
    (unwind-protect
         (progn
           ;; Registered BEFORE the handshake: a shutdown while a peer is still
           ;; proving who it is must still close this descriptor.
           (setf closeable
                 (devnet-shutdown-controller-add-closeable
                  shutdown-controller
                  (lambda () (ignore-errors (sb-bsd-sockets:socket-close socket)))))
           (when closeable
             (multiple-value-bind (peer entry refusal)
                 (funcall admit-function socket)
               (setf admitted entry)
               (cond
                 ((and peer entry)
                  ;; Install before ON-SESSION-START and before the pump.  The
                  ;; former may run synchronous requests whose await loop also
                  ;; handles range/hash announcements.
                  (devnet-peer-install-sync-notification node peer)
                  (when on-session-start (funcall on-session-start peer))
                  (handler-case
                      (eth-peer-run-session
                       peer
                       :readable-function
                       (devnet-peer-session-readable-function peer)
                       :stop-p
                       (or stop-p
                           (lambda ()
                             (devnet-shutdown-requested-p shutdown-controller)))
                       :max-actions max-actions
                       :pending-request
                       (let ((queue (devnet-peer-entry-request-queue entry)))
                         (and queue (devnet-peer-pending-request queue)))
                       :snap-response-handler
                       (let ((queue (devnet-peer-entry-request-queue entry)))
                         (and queue (devnet-peer-snap-response-handler queue)))
                       :pending-chain-update
                       (devnet-peer-pending-chain-update node peer)
                       ;; Our own pool reaches this peer through here, as DATA
                       ;; the session loop sends -- never another thread.
                       :pending-broadcast pending-broadcast)
                    (serious-condition (condition)
                      (call-with-devnet-peer-table
                       node
                       (lambda ()
                         (devnet-peer-note-score
                          table (devnet-peer-entry-id-hex entry) -25)))
                      (error condition))))
                 ((and peer refusal)
                  (eth-sync-reject-connection
                   (eth-peer-connection peer)
                   (devnet-peer-disconnect-reason refusal)))))))
      ;; Close the socket and nothing else. No farewell Disconnect: a peer that
      ;; has stopped reading would block us here, and this runs on the path a
      ;; shutdown is waiting for. The dialer sends its own, gated, from outside.
      (when admitted
        (let ((queue (devnet-peer-entry-request-queue admitted)))
          (when queue (devnet-peer-request-queue-close queue)))
        (call-with-devnet-peer-table
         node
         (lambda ()
           (devnet-peer-table-remove table
                                     (devnet-peer-entry-id-hex admitted)))))
      (when reserved-slot-p
        (call-with-devnet-peer-table
         node
         (lambda ()
           (devnet-peer-table-release-slot table reserved-host))))
      (devnet-shutdown-controller-remove-closeable shutdown-controller closeable)
      (ignore-errors (sb-bsd-sockets:socket-close socket)))))

(defun devnet-peer-inbound-admit-function (node remote-host remote-port)
  "The admission half of an INBOUND session: bound the handshake, run the
recipient side of it, then take the identity-keyed verdict.

This is phase two of the two-phase admission the peer table documents: the
identity only exists once the handshake has proven it, so this necessarily runs
on the session thread rather than on the accept loop."
  #-sbcl
  (declare (ignore node remote-host remote-port))
  #-sbcl
  (lambda (socket) (declare (ignore socket)) (values nil nil nil))
  #+sbcl
  (lambda (socket)
    (let ((table (devnet-node-peer-table node)))
      ;; Bound the otherwise unbounded handshake read: a peer that connects and
      ;; says nothing must not hold a thread and a descriptor forever.
      (if (not (sb-sys:wait-until-fd-usable
                (sb-bsd-sockets:socket-file-descriptor socket)
                :input +devnet-peer-handshake-timeout-seconds+ nil))
          (values nil nil nil)
          (multiple-value-bind (status head-number chain-context)
              (devnet-peer-sync-status node)
            (declare (ignore head-number))
            (let* ((peer (eth-sync-accept-peer
                          socket (devnet-node-node-key node) status
                          :chain-context chain-context
                          :serve-backend (devnet-peer-serve-backend node)
                          :snap-backend (devnet-peer-snap-backend node)
                          :listen-port (or (devnet-node-p2p-port node) 0)))
                   (id-hex (node-id-to-hex (eth-peer-remote-public-key peer)))
                   (request-queue
                     (make-devnet-peer-request-queue
                      (devnet-node-snap-qos node)))
                   (entry nil)
                   (verdict
                     (call-with-devnet-peer-table
                      node
                      (lambda ()
                        (let ((verdict (devnet-peer-table-inbound-verdict
                                        table id-hex)))
                          (when (eq verdict :accept)
                            (setf entry
                                  (devnet-peer-table-admit
                                   table
                                   (make-devnet-peer-entry
                                    :id-hex id-hex
                                    :direction :inbound
                                    :remote-host remote-host
                                    :remote-port remote-port
                                    :socket socket
                                    :thread sb-thread:*current-thread*
                                    :eth-version (eth-peer-eth-version peer)
                                    :snap-version
                                    (ethereum-lisp.eth-sync:eth-peer-snap-version
                                     peer)
                                    :client-id (eth-peer-remote-client-id peer)
                                    :peer peer
                                    :request-queue request-queue)
                                   (unix-time)))
                            (unless entry (setf verdict :already-connected)))
                          verdict)))))
              (if (eq verdict :accept)
                  (progn
                    (devnet-peer-manager-log
                     node "p2p.peer.connected"
                     "id" id-hex "host" remote-host
                     "eth" (eth-peer-eth-version peer)
                     "snap"
                     (or (ethereum-lisp.eth-sync:eth-peer-snap-version peer)
                         0))
                    (values peer entry nil))
                  (progn
                    (devnet-peer-request-queue-close request-queue)
                    (devnet-peer-manager-log node "p2p.peer.refused"
                                             "id" id-hex "reason" verdict)
                    (values peer nil verdict)))))))))

(defun devnet-call-with-peer-session-thread-guard (node remote-host thunk)
  "Run a peer-session THUNK without allowing a serious condition to escape.

This is a process-safety boundary: SBCL's control-stack exhaustion is a
STORAGE-CONDITION, not an ERROR, and an unhandled condition in any thread
terminates the whole node under sbcl --script."
  (handler-case
      (funcall thunk)
    (serious-condition (condition)
      (devnet-peer-manager-log
       node "p2p.peer.session_failed"
       "host" remote-host
       "error" condition))))

(defun devnet-start-p2p-listener-thread
    (node listener shutdown-controller error-callback)
  "Start the inbound accept loop, or return NIL when there is no listener.

A transient accept failure is logged and the loop CONTINUES. For a public
listening port, one refused or aborted connection taking peering down would be a
liveness bug -- deliberately unlike the Engine RPC listener, which re-signals.
Only an error escaping the loop itself is fail-stop."
  #-sbcl
  (declare (ignore node listener shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (when listener
    (let ((table (devnet-node-peer-table node))
          (sessions '())
          (sessions-lock (devnet-make-mutex "ethereum-lisp-p2p-sessions")))
      (values
       (sb-thread:make-thread
        (lambda ()
          (handler-case
              (loop
                (when (devnet-shutdown-requested-p shutdown-controller)
                  (return))
                (handler-case
                    (multiple-value-bind (socket remote-host remote-port)
                        (eth-sync-listener-accept
                         listener
                         :timeout-seconds +devnet-peer-accept-tick-seconds+)
                      (when socket
                        (if (eq :reserve
                                (call-with-devnet-peer-table
                                 node
                                 (lambda ()
                                   (let ((verdict
                                           (devnet-peer-table-slot-verdict
                                            table remote-host)))
                                     (when (eq verdict :reserve)
                                       (devnet-peer-table-reserve-slot
                                        table remote-host))
                                     verdict))))
                            ;; Spawn and move on: the handshake must never run
                            ;; on this thread, or one silent peer stops the
                            ;; listener noticing anything, shutdown included.
                            (let ((thread
                                    (sb-thread:make-thread
                                     (lambda ()
                                       ;; A session must NEVER let a condition
                                       ;; escape its thread. Under `sbcl
                                       ;; --script`, which is how the node and
                                       ;; the whole test suite run, the disabled
                                       ;; debugger turns an unhandled condition
                                       ;; in ANY thread into (exit 1) for the
                                       ;; entire process -- so one peer sending
                                       ;; garbage, closing mid-handshake, or
                                       ;; failing the fork-id check would take
                                       ;; the node down. Measured, not assumed.
                                       (devnet-call-with-peer-session-thread-guard
                                        node remote-host
                                        (lambda ()
                                          (devnet-peer-run-session
                                           node socket shutdown-controller
                                           (devnet-peer-inbound-admit-function
                                            node remote-host remote-port)
                                           :reserved-slot-p t
                                           :reserved-host remote-host
                                           :pending-broadcast
                                           (devnet-peer-pending-broadcast node)))))
                                     :name "ethereum-lisp-devnet-peer-session")))
                              (call-with-devnet-mutex
                               sessions-lock
                               (lambda ()
                                 (setf sessions
                                       (cons thread
                                             (remove-if-not
                                              #'sb-thread:thread-alive-p
                                              sessions))))))
                            (progn
                              (devnet-peer-manager-log
                               node "p2p.listener.rejected"
                               "host" remote-host "reason" "no-slot")
                              (ignore-errors
                               (sb-bsd-sockets:socket-close socket))))))
                  (error (condition)
                    (devnet-peer-manager-log node "p2p.listener.accept_failed"
                                             "error" condition))))
            (serious-condition (condition)
              (funcall error-callback condition)
              (devnet-shutdown-request shutdown-controller))))
        :name "ethereum-lisp-devnet-p2p-listener")
       (lambda ()
         (call-with-devnet-mutex sessions-lock (lambda () (copy-list sessions))))))))

(defun devnet-join-peer-sessions (session-threads-function &key (timeout 5))
  "Join every session thread, bounded, terminating any that will not stop.

Every join here carries a timeout: an unbounded join on a thread blocked in a
socket read is how a shutdown becomes a hang."
  #-sbcl
  (declare (ignore session-threads-function timeout))
  #-sbcl
  nil
  #+sbcl
  (dolist (thread (funcall session-threads-function))
    (when (sb-thread:thread-alive-p thread)
      (when (eq :timeout
                (sb-thread:join-thread thread :timeout timeout
                                              :default :timeout))
        (ignore-errors (sb-thread:terminate-thread thread))
        (ignore-errors
         (sb-thread:join-thread thread :timeout timeout :default :timeout))))))
