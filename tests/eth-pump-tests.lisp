(in-package #:ethereum-lisp.test)

;;;; The session pump.
;;;;
;;;; Almost all of this is a truth table over a pure function: no clock, no
;;;; socket, no thread, `now` passed in as an integer. That is deliberate. The
;;;; one property that cannot be tested that way — that a connection carrying
;;;; only keepalives still comes back to the loop — needs a real socket, and it
;;;; is the single most important test in the file.

(defun eth-pump-test-action (&key (policy (make-eth-pump-policy))
                                  (last-read 0) (last-ping 0) (last-drain 0)
                                  (now 0) readable-p stop-p drainable-p
                                  urgent-drainable-p
                                  request-p chain-update-p broadcast-p)
  (let ((state (make-eth-pump-state)))
    (setf (eth-pump-state-last-read-at state) last-read
          (eth-pump-state-last-ping-at state) last-ping
          (eth-pump-state-last-drain-at state) last-drain)
    (eth-pump-next-action policy state now
                          :readable-p readable-p :stop-p stop-p
                          :request-p request-p :drainable-p drainable-p
                          :urgent-drainable-p urgent-drainable-p
                          :chain-update-p chain-update-p
                          :broadcast-p broadcast-p)))

(deftest eth-pump-next-action-truth-table
  (:layer :unit :module :p2p)
  ;; Queued snap healing requests are dependent and therefore cannot overlap.
  ;; Keep the default writer wake bounded tightly enough that the readiness
  ;; poll itself cannot reduce a healthy peer to about one request per second.
  (is (plusp +eth-pump-read-tick-seconds+))
  (is (<= +eth-pump-read-tick-seconds+ 0.05d0))
  ;; Stopping beats everything: a shutdown must never wait on a peer.
  (is (eq :stop (eth-pump-test-action :stop-p t)))
  (is (eq :stop (eth-pump-test-action :stop-p t :readable-p t)))
  (is (eq :stop (eth-pump-test-action :stop-p t :now 10000)))
  (is (eq :stop (eth-pump-test-action :stop-p t :readable-p t :drainable-p t
                                      :broadcast-p t :now 10000)))
  ;; A queued coordinator request outranks readability.  Its response loop
  ;; handles interleaved peer traffic, and allowing reads to win here would
  ;; starve snap healing on a continuously talkative public peer.
  (is (eq :request
          (eth-pump-test-action :readable-p t :request-p t :now 20)))
  ;; Without a request, reading beats every periodic job so a talkative peer is
  ;; drained before we add periodic traffic of our own...
  (is (eq :read (eth-pump-test-action :readable-p t)))
  (is (eq :read (eth-pump-test-action :readable-p t :now 20)))
  (is (eq :read (eth-pump-test-action :readable-p t :drainable-p t :now 20)))
  ;; An omitted eth/72 blob is not merely periodic gossip: it cannot be
  ;; admitted until GetCells completes and must not starve behind a peer that
  ;; keeps the descriptor readable.
  (is (eq :drain
          (eth-pump-test-action :readable-p t :drainable-p t
                                :urgent-drainable-p t :now 3)))
  ;; ...and in particular, a peer whose data is already waiting can never be
  ;; timed out as idle.
  (is (eq :read (eth-pump-test-action :readable-p t :now 100000)))
  ;; Nothing readable: the periodic jobs, in order.
  (is (eq :idle-timeout (eth-pump-test-action :now 61)))
  ;; Coordinator requests run on the sole socket writer and outrank periodic
  ;; traffic, including an otherwise-due idle timeout.
  (is (eq :request (eth-pump-test-action :now 61 :request-p t)))
  (is (eq :ping (eth-pump-test-action :now 20)))
  (is (eq :drain (eth-pump-test-action :now 3 :drainable-p t)))
  (is (eq :chain-update
          (eth-pump-test-action :now 1 :chain-update-p t)))
  (is (eq :chain-update
          (eth-pump-test-action :now 1 :chain-update-p t :broadcast-p t)))
  (is (eq :broadcast (eth-pump-test-action :now 1 :broadcast-p t)))
  (is (eq :wait (eth-pump-test-action :now 1)))
  ;; A drain is only due when there is something to ask for.
  (is (eq :wait (eth-pump-test-action :now 3)))
  ;; Boundaries are inclusive: due AT the interval, not one tick after.
  (is (eq :ping (eth-pump-test-action :now +eth-pump-ping-interval-seconds+)))
  (is (eq :wait (eth-pump-test-action
                 :now (1- +eth-pump-ping-interval-seconds+))))
  (is (eq :idle-timeout
          (eth-pump-test-action :now +eth-pump-idle-timeout-seconds+)))
  ;; A NIL interval turns that behavior off rather than firing constantly.
  (let ((policy (make-eth-pump-policy :ping-interval-seconds nil
                                      :idle-timeout-seconds nil
                                      :drain-interval-seconds nil)))
    (is (eq :wait (eth-pump-test-action :policy policy :now 100000)))
    (is (eq :wait (eth-pump-test-action :policy policy :now 100000
                                        :drainable-p t)))
    (is (eq :read (eth-pump-test-action :policy policy :now 100000
                                        :readable-p t)))))

(deftest eth-peer-run-session-does-not-starve-a-queued-request
  (:layer :unit :module :p2p)
  ;; Exercise the shipped loop, not only its pure policy.  READABLE-FUNCTION is
  ;; deliberately always true, matching an active Hoodi peer.  The request must
  ;; run without touching the connection; the pre-fix loop instead tries to
  ;; read and signals because this test peer intentionally has no connection.
  (let ((peer (ethereum-lisp.eth-sync::%make-eth-peer))
        (request-calls 0)
        (readiness-calls 0))
    (multiple-value-bind (actions reason)
        (eth-peer-run-session
         peer
         :readable-function
         (lambda (timeout)
           (declare (ignore timeout))
           (incf readiness-calls)
           t)
         :pending-request
         (lambda ()
           (lambda () (incf request-calls)))
         :max-actions 1)
      (is (= 1 actions))
      (is (eq :max-actions reason))
      (is (= 1 request-calls))
      (is (zerop readiness-calls)))))

(deftest eth-peer-run-session-routes-a-pipelined-snap-response
  (:layer :unit :module :p2p)
  (let* ((peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (real-read (fdefinition read-symbol))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-account-range+
            (ethereum-lisp.snap:make-snap-account-range 77 nil nil)))
         (routed nil))
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-account-range+
                           payload)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer
                :readable-function (lambda (timeout)
                                     (declare (ignore timeout))
                                     t)
                :snap-response-handler
                (lambda (message-id encoded)
                  (setf routed
                        (list message-id
                              (ethereum-lisp.snap:snap-account-range-id
                               (ethereum-lisp.snap:decode-snap-message
                                message-id encoded))))
                  t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason)))
           (is (equal
                (list ethereum-lisp.snap:+snap-message-account-range+ 77)
                routed)))
      (setf (fdefinition read-symbol) real-read))))

(deftest eth-peer-run-session-answers-a-keepalive-and-still-returns
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; THE regression for the reader split. A peer that sends only a devp2p Ping
  ;; produces no subprotocol message ever, so a session built on the looping
  ;; ETH-WIRE-READ blocks inside it forever: the Pong goes out, but the loop
  ;; never returns, STOP-P is never consulted again and no periodic work runs.
  ;; The pump therefore runs on a thread here and the join is bounded, so a
  ;; regression fails red instead of stopping the whole suite.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (server-saw nil)
         (server-error nil))
    (flet ((status ()
             (eth-build-status config *eth-sync-test-genesis* 0 0
                               *eth-sync-test-best* 0)))
      (unwind-protect
           (let ((server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (multiple-value-bind (socket host port)
                              (eth-sync-listener-accept listener
                                                        :timeout-seconds 10)
                            (declare (ignore host port))
                            (when socket
                              (unwind-protect
                                   (let ((peer (eth-sync-accept-peer
                                                socket server-static (status))))
                                     ;; Only a keepalive. Never any eth message.
                                     (rlpx-send-ping (eth-peer-connection peer))
                                     (multiple-value-bind (kind id payload)
                                         (eth-peer-read-once peer)
                                       (declare (ignore payload))
                                       (setf server-saw (list kind id))))
                                (ignore-errors
                                 (sb-bsd-sockets:socket-close socket)))))
                        (error (condition) (setf server-error condition))))
                    :name "eth-pump-test-server")))
             (multiple-value-bind (peer socket)
                 (eth-sync-connect-peer "127.0.0.1"
                                        (eth-sync-listener-port listener)
                                        server-static-pub client-static (status))
               (unwind-protect
                    ;; The connection's own stream, never a second one over the
                    ;; same descriptor: two buffered streams on one socket would
                    ;; each hold half a frame.
                    (let* ((stream (rlpx-connection-stream
                                    (eth-peer-connection peer)))
                           (reads 0)
                           (result nil)
                           (pump-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (setf result
                                          (multiple-value-list
                                           (eth-peer-run-session
                                            peer
                                            :readable-function
                                            (lambda (timeout)
                                              ;; Buffered bytes are invisible to
                                              ;; a bare descriptor poll, so the
                                              ;; gate asks the stream first.
                                              (or (listen stream)
                                                  (sb-sys:wait-until-fd-usable
                                                   (sb-sys:fd-stream-fd stream)
                                                   :input timeout nil)))
                                            :on-event
                                            (lambda (action)
                                              (when (eq action :read)
                                                (incf reads)))
                                            ;; Stop once the keepalive has been
                                            ;; handled: reaching this at all is
                                            ;; the property under test.
                                            :stop-p (lambda () (plusp reads))
                                            :max-actions 50)))
                                  (error (condition) (setf result condition))))
                              :name "eth-pump-test-pump")))
                      ;; The session must come back. Against the looping reader
                      ;; this join times out and the assertion fails red.
                      (is (not (eq :timeout
                                   (sb-thread:join-thread pump-thread
                                                          :timeout 15
                                                          :default :timeout))))
                      (when (typep result 'condition)
                        (error "pump session failed: ~A" result))
                      (is (listp result))
                      (is (eq :stop (second result)))
                      (is (= 1 reads)))
                 (ignore-errors (sb-bsd-sockets:socket-close socket))))
             (is (not (eq :timeout (sb-thread:join-thread server-thread
                                                          :timeout 15
                                                          :default :timeout))))
             (when server-error
               (error "pump test server side failed: ~A" server-error))
             ;; The pump answered the keepalive rather than ignoring it.
             (is (equal (list :base +devp2p-message-pong+) server-saw)))
        (eth-sync-listener-close listener)))))
