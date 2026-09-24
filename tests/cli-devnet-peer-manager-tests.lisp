(in-package #:ethereum-lisp.test)

;;;; Inbound peering: the admission table, the shutdown closeables registry, and
;;;; the property the whole design exists for — a node with a silent inbound
;;;; peer still shuts down.
;;;;
;;;; Almost everything here is pure and instant. The one test that binds a
;;;; socket and spawns threads joins everything with a timeout it asserts on,
;;;; because the unit and integration layers have no per-test timeout: a test
;;;; that can block does not fail, it stops the run.

(define-condition devnet-test-storage-condition (storage-condition) ())

(defun devnet-peer-table-test-entry
    (id-hex &key (direction :inbound) (host "127.0.0.1"))
  (ethereum-lisp.cli:make-devnet-peer-entry
   :id-hex id-hex :direction direction
   :remote-host host :remote-port 30303))

(deftest devnet-peer-table-default-matches-public-client-baseline
  (:layer :unit :module :p2p)
  (let ((table
          (ethereum-lisp.cli:make-devnet-peer-table :self-id-hex "self")))
    ;; geth 38271784 and Nethermind e52dc19a both default to 50. Keeping the
    ;; public-node default here avoids halving the candidate pool from which
    ;; the long SNAP healer obtains state-capable peers.
    (is (= 50 ethereum-lisp.cli:+devnet-default-max-peers+))
    (is (= 50 (ethereum-lisp.cli::devnet-peer-table-max-peers table)))))

(deftest devnet-peer-table-admission-verdicts
  ;; Both phases of admission, as a table. No sockets, no threads, no clock:
  ;; `now` is just an integer.
  (let ((table (ethereum-lisp.cli:make-devnet-peer-table
                :self-id-hex "aa" :max-peers 2)))
    ;; Phase one is identity-free, because at accept time there is no identity.
    (is (eq :reserve (ethereum-lisp.cli:devnet-peer-table-slot-verdict table)))
    ;; Phase two knows who it is talking to.
    (is (eq :self (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "aa")))
    (is (eq :accept (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "bb")))
    (is (ethereum-lisp.cli:devnet-peer-table-admit
         table (devnet-peer-table-test-entry "bb") 1000))
    (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count table)))
    ;; The same peer twice is one peer, whichever way it arrived.
    (is (eq :already-connected
            (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "bb")))
    (is (null (ethereum-lisp.cli:devnet-peer-table-admit
               table (devnet-peer-table-test-entry "bb") 1001)))
    (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count table)))
    ;; Filling the last slot closes the door.
    (is (eq :accept (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "cc")))
    (ethereum-lisp.cli:devnet-peer-table-admit
     table (devnet-peer-table-test-entry "cc") 1002)
    (is (eq :too-many-peers
            (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "dd")))
    ;; And a departure reopens it.
    (is (ethereum-lisp.cli:devnet-peer-table-remove table "bb"))
    (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count table)))
    (is (eq :accept (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "dd")))
    (is (null (ethereum-lisp.cli:devnet-peer-table-remove table "zz")))
    ;; The snapshot reports connection order, oldest first.
    (let ((snapshot (ethereum-lisp.cli:devnet-peer-table-snapshot table)))
      (is (= 1 (length snapshot)))
      (is (equal "cc" (getf (first snapshot) :id)))
      (is (eq :inbound (getf (first snapshot) :direction)))
      (is (= 1002 (getf (first snapshot) :connected-at))))))

(deftest devnet-peer-table-bounds-handshakes-in-flight
  ;; The reservation is what stops a connection flood from spawning threads
  ;; without limit before anyone has proven who they are.
  (let ((table (ethereum-lisp.cli:make-devnet-peer-table
                :self-id-hex "aa" :max-peers 2)))
    (loop repeat (+ 2 ethereum-lisp.cli::+devnet-peer-handshake-headroom+)
          do (is (eq :reserve
                     (ethereum-lisp.cli:devnet-peer-table-slot-verdict table)))
             (ethereum-lisp.cli:devnet-peer-table-reserve-slot table))
    (is (eq :no-slot (ethereum-lisp.cli:devnet-peer-table-slot-verdict table)))
    ;; A finished handshake gives its reservation back whether or not it became
    ;; a peer.
    (ethereum-lisp.cli:devnet-peer-table-release-slot table)
    (is (eq :reserve (ethereum-lisp.cli:devnet-peer-table-slot-verdict table)))
    ;; Releasing more than were taken must not corrupt the count into letting
    ;; everything through.
    (loop repeat 20 do (ethereum-lisp.cli:devnet-peer-table-release-slot table))
    (is (= 0 (ethereum-lisp.cli::devnet-peer-table-pending table))))
  ;; A peer limit of zero means peering is off, not "unlimited".
  (let ((table (ethereum-lisp.cli:make-devnet-peer-table
                :self-id-hex "aa" :max-peers 0)))
    (is (eq :no-slot (ethereum-lisp.cli:devnet-peer-table-slot-verdict table)))
    (is (eq :too-many-peers
            (ethereum-lisp.cli:devnet-peer-table-inbound-verdict table "bb")))))

(deftest devnet-peer-table-throttles-addresses-and-scores-abuse
  (:layer :unit :module :p2p)
  (let ((table
          (ethereum-lisp.cli:make-devnet-peer-table
           :self-id-hex "self" :max-peers 20
           :inbound-per-ip 1 :inbound-per-subnet 2
           :netrestrict '("198.51.100.0/24"))))
    (is (eq :netrestrict
            (ethereum-lisp.cli:devnet-peer-table-slot-verdict
             table "203.0.113.1")))
    (is (eq :reserve
            (ethereum-lisp.cli:devnet-peer-table-slot-verdict
             table "198.51.100.3")))
    (ethereum-lisp.cli:devnet-peer-table-reserve-slot table "198.51.100.3")
    (is (eq :ip-throttled
            (ethereum-lisp.cli:devnet-peer-table-slot-verdict
             table "198.51.100.3")))
    (ethereum-lisp.cli:devnet-peer-table-release-slot table "198.51.100.3")
    (ethereum-lisp.cli:devnet-peer-table-admit
     table (devnet-peer-table-test-entry "a" :host "198.51.100.3") 1)
    (ethereum-lisp.cli:devnet-peer-table-admit
     table (devnet-peer-table-test-entry "b" :host "198.51.100.4") 2)
    (is (eq :subnet-throttled
            (ethereum-lisp.cli:devnet-peer-table-slot-verdict
             table "198.51.100.5")))
    (ethereum-lisp.cli:devnet-peer-note-score table "hostile" -100)
    (is (eq :useless-peer
            (ethereum-lisp.cli:devnet-peer-table-inbound-verdict
             table "hostile")))
    (is (= -100 (ethereum-lisp.cli:devnet-peer-score table "hostile")))))

(deftest devnet-peer-table-exempts-lan-addresses-from-host-throttles
  (:layer :unit :module :p2p)
  ;; Hive and private testnets legitimately originate several independent node
  ;; identities behind one bridge address. Geth likewise exempts LAN addresses
  ;; from its source-IP throttle; the global handshake/peer bounds still apply.
  (dolist (host '("10.1.2.3" "172.18.0.3" "192.168.1.2"
                  "127.0.0.1" "169.254.1.2" "fd00::1" "fe80::1" "::1"
                  "::ffff:172.18.0.3"))
    (let ((table
            (ethereum-lisp.cli:make-devnet-peer-table
             :self-id-hex "self" :max-peers 20
             :inbound-per-ip 1 :inbound-per-subnet 1)))
      (ethereum-lisp.cli:devnet-peer-table-reserve-slot table host)
      (is (eq :reserve
              (ethereum-lisp.cli:devnet-peer-table-slot-verdict table host)))))
  ;; A public source remains bounded by the configured per-host policy.
  (let ((table
          (ethereum-lisp.cli:make-devnet-peer-table
           :self-id-hex "self" :max-peers 20
           :inbound-per-ip 1 :inbound-per-subnet 2)))
    (ethereum-lisp.cli:devnet-peer-table-reserve-slot table "198.51.100.3")
    (is (eq :ip-throttled
            (ethereum-lisp.cli:devnet-peer-table-slot-verdict
             table "198.51.100.3")))))

(deftest devnet-shutdown-controller-closes-registered-closeables
  ;; A peer socket is not a listener, so it needs somewhere to be registered or
  ;; a thread blocked reading it never wakes. No sockets or threads needed to
  ;; test that: the registry is just thunks.
  (let* ((controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (closed '())
         (note (lambda (name) (lambda () (push name closed)))))
    (let ((first-token (ethereum-lisp.cli:devnet-shutdown-controller-add-closeable
                        controller (funcall note :a)))
          (second-token (ethereum-lisp.cli:devnet-shutdown-controller-add-closeable
                         controller (funcall note :b))))
      (is (not (null first-token)))
      (is (not (eql first-token second-token)))
      ;; A deregistered closeable does not run.
      (ethereum-lisp.cli:devnet-shutdown-controller-remove-closeable
       controller second-token)
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (is (equal '(:a) closed)))
    ;; Registering AFTER the sweep runs the thunk immediately and returns NIL.
    ;; Otherwise a session that registered a moment too late would be left with
    ;; its socket open and its thread blocked forever.
    (let ((late (ethereum-lisp.cli:devnet-shutdown-controller-add-closeable
                 controller (funcall note :late))))
      (is (null late))
      (is (equal '(:late :a) closed)))))

(deftest devnet-peer-thread-contains-storage-conditions
  (:layer :unit :module :devnet)
  ;; If the production guard regresses to (ERROR ...), this test does not report
  ;; a normal assertion failure: the unhandled STORAGE-CONDITION kills the
  ;; sbcl --script test process. That destructive red is the property at stake.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (escaped nil)
         (thread
           (sb-thread:make-thread
            (lambda ()
              ;; The outer ERROR handler satisfies the test-thread safety rule
              ;; without masking STORAGE-CONDITION. The production guard is
              ;; what must catch that wider condition family.
              (handler-case
                  (ethereum-lisp.cli::devnet-call-with-peer-session-thread-guard
                   node "hostile-peer"
                   (lambda () (error 'devnet-test-storage-condition)))
                (error (condition)
                  (setf escaped condition))))
            :name "ethereum-lisp-storage-condition-regression")))
    (is (not (eq :timeout
                 (sb-thread:join-thread thread :timeout 5 :default :timeout))))
    (is (null escaped))))

(deftest devnet-node-shuts-down-with-a-silent-inbound-peer
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The regression this whole design exists for. A peer connects and then says
  ;; nothing at all — no handshake, no bytes. Both the accept loop and the
  ;; session thread must still stop when shutdown is requested, and neither may
  ;; be waiting on that peer to do something first.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :p2p-host "127.0.0.1" :p2p-port 0
                :max-peers 4))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (silent (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream :protocol :tcp))
         (listener-error nil))
    (setf (ethereum-lisp.cli::devnet-node-p2p-port node)
          (eth-sync-listener-port listener))
    (unwind-protect
         (multiple-value-bind (accept-thread sessions)
             (ethereum-lisp.cli:devnet-start-p2p-listener-thread
              node listener controller
              (lambda (condition) (setf listener-error condition)))
           (is (not (null accept-thread)))
           ;; Connect and then go completely silent.
           (sb-bsd-sockets:socket-connect
            silent (sb-bsd-sockets:make-inet-address "127.0.0.1")
            (eth-sync-listener-port listener))
           ;; Give the accept loop a moment to take it and spawn a session.
           (loop repeat 50
                 until (funcall sessions)
                 do (sleep 0.1))
           (is (not (null (funcall sessions))))
           ;; Now stop everything. This is the assertion: it comes back.
           (ethereum-lisp.cli:devnet-shutdown-request controller)
           (is (not (eq :timeout
                        (sb-thread:join-thread accept-thread
                                               :timeout 15
                                               :default :timeout))))
           (ethereum-lisp.cli:devnet-join-peer-sessions sessions :timeout 10)
           (dolist (thread (funcall sessions))
             (is (not (sb-thread:thread-alive-p thread))))
           (when listener-error
             (error "p2p listener failed: ~A" listener-error))
           ;; And the peer never became a peer, since it never identified itself.
           (is (= 0 (ethereum-lisp.cli:devnet-peer-table-count
                     (ethereum-lisp.cli:devnet-node-peer-table node)))))
      (ignore-errors (sb-bsd-sockets:socket-close silent))
      (eth-sync-listener-close listener))))

(deftest devnet-cli-peer-flags-reach-the-node
  ;; --port is the devp2p port and must NOT be confused with the Engine RPC
  ;; port, which is --engine-port and rides a different key entirely. Parsing
  ;; only: nothing here binds a socket.
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "devnet" "--port" "30311" "--maxpeers" "7"
                        "--netrestrict" "10.0.0.0/8,192.0.2.0/24"
                        "--no-serve"))))
    (is (= 30311 (getf options :p2p-port)))
    (is (= 7 (getf options :max-peers)))
    (is (equal '("10.0.0.0/8" "192.0.2.0/24")
               (getf options :netrestrict)))
    ;; The Engine port is untouched by --port.
    (is (/= 30311 (getf options :port))))
  ;; No --port at all means no inbound listener, which is the default: a devnet
  ;; that binds a fixed port by habit collides with the next one on the machine.
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "devnet" "--no-serve"))))
    (is (null (getf options :p2p-port)))
    (is (null (getf options :max-peers))))
  ;; The range check on --port still applies.
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     (list "devnet" "--port" "70000" "--no-serve")))
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     (list "devnet" "--maxpeers" "-1" "--no-serve"))))

(deftest devnet-summary-reports-the-node-enode
  ;; The wave is only observable if a node can say how to reach it. Nothing in
  ;; the tree computed our own enode before this.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :p2p-host "0.0.0.0" :p2p-port 30399 :max-peers 7))
         (summary (ethereum-lisp.cli:devnet-node-summary node)))
    (is (getf summary :p2p-enabled-p))
    (is (= 30399 (getf summary :p2p-port)))
    (is (= 7 (getf summary :max-peers)))
    ;; A real enode, and never a wildcard address: 0.0.0.0 is not dialable.
    (multiple-value-bind (node-id host port) (parse-enode-url (getf summary :enode))
      (is (bytes= (node-id-from-private-key
                   (ethereum-lisp.cli::devnet-node-node-key node))
                  node-id))
      (is (string= "127.0.0.1" host))
      (is (= 30399 port))))
  ;; Without a listener the node says so rather than inventing an endpoint.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node)))
    (is (null (getf summary :p2p-enabled-p)))
    (is (null (getf summary :enode)))))

(deftest devnet-peer-session-failure-does-not-take-the-node-down
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; A peer that connects and sends garbage fails its handshake. That failure
  ;; MUST stay inside its session thread: under `sbcl --script` -- how the node
  ;; and this very test suite run -- the disabled debugger turns an unhandled
  ;; condition in ANY thread into (exit 1) for the whole process. So without the
  ;; handler this test does not fail, it kills the run. Measured, not assumed.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (rude (make-instance 'sb-bsd-sockets:inet-socket
                              :type :stream :protocol :tcp))
         (listener-error nil))
    (setf (ethereum-lisp.cli::devnet-node-p2p-port node)
          (eth-sync-listener-port listener))
    (unwind-protect
         (multiple-value-bind (accept-thread sessions)
             (ethereum-lisp.cli:devnet-start-p2p-listener-thread
              node listener controller
              (lambda (condition) (setf listener-error condition)))
           (is (not (null accept-thread)))
           (sb-bsd-sockets:socket-connect
            rude (sb-bsd-sockets:make-inet-address "127.0.0.1")
            (eth-sync-listener-port listener))
           ;; A well-formed length prefix followed by garbage: the read
           ;; completes, so nothing times out, and then ECIES rejects it.
           (let ((stream (sb-bsd-sockets:socket-make-stream
                          rude :input t :output t
                               :element-type '(unsigned-byte 8))))
             (write-sequence (concat-bytes (vector 1 0) (make-array 256
                                                                   :initial-element 7))
                             stream)
             (force-output stream))
           (loop repeat 50 until (funcall sessions) do (sleep 0.1))
           (is (not (null (funcall sessions))))
           ;; The session ends on its own, without the accept loop noticing.
           (ethereum-lisp.cli:devnet-join-peer-sessions sessions :timeout 10)
           (dolist (thread (funcall sessions))
             (is (not (sb-thread:thread-alive-p thread))))
           ;; The listener is still up and still accepting: one bad peer is not
           ;; a reason to stop peering.
           (is (not (eth-sync-listener-closed-p listener)))
           (is (sb-thread:thread-alive-p accept-thread))
           (is (null listener-error))
           ;; It never became a peer, and its reservation was given back.
           (let ((table (ethereum-lisp.cli:devnet-node-peer-table node)))
             (is (= 0 (ethereum-lisp.cli:devnet-peer-table-count table)))
             (is (= 0 (ethereum-lisp.cli::devnet-peer-table-pending table))))
           (ethereum-lisp.cli:devnet-shutdown-request controller)
           (is (not (eq :timeout (sb-thread:join-thread accept-thread
                                                        :timeout 15
                                                        :default :timeout)))))
      (ignore-errors (sb-bsd-sockets:socket-close rude))
      (eth-sync-listener-close listener))))

;;;; Inbound sessions against the live failure classes of the b5161312 Hoodi
;;;; run (docs/evidence/sec5-rlpx-inbound-auth.txt): what each class looks like
;;;; from our side, and that none of them keeps a slot.

(defun devnet-test-call-with-inbound-listener (node function)
  "Run FUNCTION with the port of NODE's running inbound listener, then stop the
listener and join its threads, asserting that each one came back."
  (let ((controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
        (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
        (listener-error nil))
    (setf (ethereum-lisp.cli::devnet-node-p2p-port node)
          (eth-sync-listener-port listener))
    (unwind-protect
         (multiple-value-bind (accept-thread sessions)
             (ethereum-lisp.cli:devnet-start-p2p-listener-thread
              node listener controller
              (lambda (condition) (setf listener-error condition)))
           (unwind-protect
                (funcall function (eth-sync-listener-port listener))
             (ethereum-lisp.cli:devnet-shutdown-request controller)
             (is (not (eq :timeout
                          (sb-thread:join-thread accept-thread :timeout 15
                                                               :default :timeout))))
             (ethereum-lisp.cli:devnet-join-peer-sessions sessions :timeout 10))
           (is (null listener-error)))
      (eth-sync-listener-close listener))))

(defun devnet-test-connect-socket (port)
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (sb-bsd-sockets:socket-connect
     socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
    socket))

(defun devnet-test-await-event (sink name predicate &key (seconds 10))
  "The first NAME event whose fields satisfy PREDICATE, waiting up to SECONDS."
  (loop repeat (* 10 seconds)
        do (let ((event
                   (find-if (lambda (event)
                              (and (equal name
                                          (ethereum-lisp.telemetry:telemetry-event-name
                                           event))
                                   (funcall predicate
                                            (ethereum-lisp.telemetry:telemetry-event-fields
                                             event))))
                            (ethereum-lisp.telemetry:telemetry-events sink))))
             (when event (return event)))
           (sleep 0.1)))

(defun devnet-test-await-slots (table &key (count 0) (pending 0) (seconds 10))
  "Whether TABLE reaches COUNT peers and PENDING reservations within SECONDS.
PENDING NIL waits for the peer count alone."
  (loop repeat (* 10 seconds)
        thereis (and (= count (ethereum-lisp.cli:devnet-peer-table-count table))
                     (or (null pending)
                         (= pending
                            (ethereum-lisp.cli::devnet-peer-table-pending table))))
        do (sleep 0.1)))

(defun devnet-test-eth-handshake (server port &key (stream-timeout-seconds 10))
  "Dial SERVER's listener on PORT as a fresh node and run the whole RLPx, Hello
and eth Status handshake. Returns (VALUES PEER SOCKET), or the error."
  (let ((client (ethereum-lisp.cli:make-devnet-node
                 :genesis-json *eth-sync-paris-genesis-json*
                 :port 0 :public-port 0))
        (socket (devnet-test-connect-socket port)))
    (multiple-value-bind (status head-number chain-context)
        (ethereum-lisp.cli::devnet-peer-sync-status client)
      (declare (ignore head-number))
      (handler-case
          (eth-sync-connect-peer
           "127.0.0.1" port
           (secp256k1-private-key-public-key
            (ethereum-lisp.cli::devnet-node-node-key server))
           (ethereum-lisp.cli::devnet-node-node-key client) status
           :socket socket
           :stream-timeout-seconds stream-timeout-seconds
           :chain-context chain-context)
        (error (condition)
          (ignore-errors (sb-bsd-sockets:socket-close socket))
          condition)))))

(deftest devnet-inbound-handshake-does-not-wait-for-the-store-guard
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; b5161312 on Hoodi, 00:00-01:50Z: dial sessions held the store guard for
  ;; 10-134 s at a time, and the inbound admission read our head for its eth
  ;; Status under that guard BEFORE running the RLPx handshake. The ack waited
  ;; behind the hold, geth initiators gave up after their 5 s handshake
  ;; deadline ("RLPx stream ended after 0 of 32 bytes" once we did answer), and
  ;; the waiting sessions held every reservation ("no-slot"). The whole inbound
  ;; handshake must complete while another thread holds the guard.
  (let* ((server (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0
                  :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4))
         (table (ethereum-lisp.cli:devnet-node-peer-table server))
         (holding nil)
         (release nil)
         (holder-error nil)
         (holder
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (ethereum-lisp.cli::call-with-devnet-node-store-guard
                   server
                   (lambda ()
                     (setf holding t)
                     (loop repeat 300 until release do (sleep 0.1))))
                (error (condition) (setf holder-error condition))))
            :name "devnet-test-store-guard-holder")))
    (unwind-protect
         (progn
           (loop repeat 50 until holding do (sleep 0.1))
           (is holding)
           (devnet-test-call-with-inbound-listener
            server
            (lambda (port)
              (let* ((started (get-internal-real-time))
                     (outcome (multiple-value-list
                               (devnet-test-eth-handshake server port)))
                     (seconds (/ (- (get-internal-real-time) started)
                                 internal-time-units-per-second)))
                ;; Still held: this is the whole point.
                (is (not release))
                (is (typep (first outcome) 'ethereum-lisp.eth-sync:eth-peer))
                (is (< seconds 4))
                (is (devnet-test-await-slots table :count 1 :pending 0 :seconds 4))
                (when (second outcome)
                  (ignore-errors (sb-bsd-sockets:socket-close (second outcome))))
                (setf release t)))))
      (setf release t)
      (is (not (eq :timeout (sb-thread:join-thread holder :timeout 40
                                                          :default :timeout))))
      (is (null holder-error)))))

(deftest devnet-inbound-slot-is-freed-by-failed-sessions-and-kept-by-a-live-one
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; Slot accounting on every live failure path. Each failing session must give
  ;; its reservation back; the positive control is a session that does not
  ;; fail, which must keep its slot until the peer goes away.
  (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (server (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0 :telemetry-sink sink
                  :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4))
         (server-public (secp256k1-private-key-public-key
                         (ethereum-lisp.cli::devnet-node-node-key server)))
         (table (ethereum-lisp.cli:devnet-node-peer-table server))
         (client-key (secp256k1-random-private-key)))
    (flet ((failed-with (text)
             (devnet-test-await-event
              sink "p2p.peer.session_failed"
              (lambda (fields)
                (equal text (cdr (assoc "error" fields :test #'equal)))))))
      (devnet-test-call-with-inbound-listener
       server
       (lambda (port)
         ;; 1. An auth addressed to another node key: the live majority class.
         (let* ((socket (devnet-test-connect-socket port))
                (stream (eth-sync-socket-stream socket :timeout 10)))
           (unwind-protect
                (progn
                  (write-sequence
                   (rlpx-create-auth client-key (secp256k1-random-private-key)
                                     (secp256k1-private-key-public-key
                                      (secp256k1-random-private-key))
                                     (secure-random-bytes 32))
                   stream)
                  (force-output stream)
                  (is (failed-with "ECIES tag does not authenticate the message"))
                  (is (devnet-test-await-slots table :count 0 :pending 0)))
             (ignore-errors (sb-bsd-sockets:socket-close socket))))
         ;; 2. A correctly addressed auth trickled in three pieces: the reader
         ;; waits for exactly auth-size bytes and answers. The client then
         ;; hangs up without a Hello: the live "0 of 32" class, seen from us.
         (let* ((socket (devnet-test-connect-socket port))
                (stream (eth-sync-socket-stream socket :timeout 10))
                (auth (rlpx-create-auth client-key (secp256k1-random-private-key)
                                        server-public (secure-random-bytes 32)))
                (cuts (list 0 1 (floor (length auth) 2) (length auth))))
           (unwind-protect
                (progn
                  (loop for (start end) on cuts
                        while end
                        do (write-sequence (subseq auth start end) stream)
                           (force-output stream)
                           (sleep 0.3))
                  (is (null (rlpx-failure-message
                             (lambda ()
                               (rlpx-open-ack
                                client-key
                                (ethereum-lisp.p2p::rlpx-read-handshake-packet
                                 stream))))))
                  ;; Let the server finish its Hello and start reading ours.
                  (sleep 0.5))
             (ignore-errors (sb-bsd-sockets:socket-close socket)))
           (is (failed-with "RLPx stream ended after 0 of 32 bytes"))
           (is (devnet-test-await-slots table :count 0 :pending 0)))
         ;; 3. Positive control: a peer that completes the handshake keeps
         ;; its slot while it stays, and gives it back when it leaves.
         (multiple-value-bind (peer socket)
             (devnet-test-eth-handshake server port)
           (is (typep peer 'ethereum-lisp.eth-sync:eth-peer))
           (unwind-protect
                (progn
                  (is (devnet-test-await-slots table :count 1 :pending nil))
                  ;; Its handshake is over, so its reservation is too: the
                  ;; entry alone counts it. (It used to be held until the
                  ;; session ended, counting every inbound peer twice.)
                  (is (devnet-test-await-slots table :count 1 :pending 0
                                                     :seconds 2))
                  (sleep 1.5)
                  (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count table)))
                  (is (= 0 (ethereum-lisp.cli::devnet-peer-table-pending table))))
             (when socket
               (ignore-errors (sb-bsd-sockets:socket-close socket)))))
         (is (devnet-test-await-slots table :count 0 :pending 0 :seconds 15)))))))

(deftest devnet-inbound-session-that-stalls-mid-auth-gives-back-its-slot
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The accepted stream had no read bound: only the first byte was waited for
  ;; with a deadline. A peer that sends part of its auth and stops -- or a
  ;; legacy pre-EIP-8 auth, which reads as a 1024-1279 byte size -- held the
  ;; session thread and its reservation until it hung up. The bound is the
  ;; dialer's per-read stream timeout, shortened here to one second.
  (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (server (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0 :telemetry-sink sink
                  :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4))
         (table (ethereum-lisp.cli:devnet-node-peer-table server))
         ;; Through SYMBOL-VALUE, so that this test also compiles and runs
         ;; against the pre-fix tree, where the parameter does not exist.
         (parameter 'ethereum-lisp.cli::*devnet-inbound-session-stream-timeout-seconds*)
         (saved (and (boundp parameter) (symbol-value parameter))))
    (unwind-protect
         (progn
           ;; SETF, not LET: the session thread cannot see a binding made here.
           (setf (symbol-value parameter) 1)
           (devnet-test-call-with-inbound-listener
            server
            (lambda (port)
              (let* ((socket (devnet-test-connect-socket port))
                     (stream (eth-sync-socket-stream socket :timeout 10))
                     (auth (rlpx-create-auth
                            (secp256k1-random-private-key)
                            (secp256k1-random-private-key)
                            (secp256k1-private-key-public-key
                             (ethereum-lisp.cli::devnet-node-node-key server))
                            (secure-random-bytes 32))))
                (unwind-protect
                     (progn
                       (write-sequence (subseq auth 0 100) stream)
                       (force-output stream)
                       (is (devnet-test-await-event
                            sink "p2p.peer.session_failed"
                            (lambda (fields)
                              (search "timeout"
                                      (string-downcase
                                       (or (cdr (assoc "error" fields
                                                       :test #'equal))
                                           ""))))
                            :seconds 6))
                       (is (devnet-test-await-slots table :count 0 :pending 0
                                                          :seconds 2)))
                  (ignore-errors (sb-bsd-sockets:socket-close socket)))))))
      (if saved
          (setf (symbol-value parameter) saved)
          (makunbound parameter)))))

(deftest devnet-listener-rejection-names-its-verdict
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The live log said "no-slot" 4,888 times, but the accept-time verdict has
  ;; four refusals (netrestrict, ip-throttled, subnet-throttled, no-slot) and
  ;; the log printed "no-slot" for all of them. A netrestricted loopback
  ;; connection has plenty of slots, so it can only be named correctly.
  (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (server (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0 :telemetry-sink sink
                  :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4
                  :netrestrict (list "10.0.0.0/8"))))
    (devnet-test-call-with-inbound-listener
     server
     (lambda (port)
       (let ((socket (devnet-test-connect-socket port)))
         (unwind-protect
              (let* ((event (devnet-test-await-event
                             sink "p2p.listener.rejected"
                             (lambda (fields) (declare (ignore fields)) t)))
                     (fields (and event
                                  (ethereum-lisp.telemetry:telemetry-event-fields
                                   event))))
                (is event)
                (is (equal "netrestrict"
                           (cdr (assoc "reason" fields :test #'equal))))
                ;; The counts the verdict was taken on travel with it.
                (is (equal "0" (cdr (assoc "peers" fields :test #'equal))))
                (is (equal "0" (cdr (assoc "pending" fields :test #'equal)))))
           (ignore-errors (sb-bsd-sockets:socket-close socket))))))))
