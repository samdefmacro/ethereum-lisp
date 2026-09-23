(in-package #:ethereum-lisp.cli)

;;;; The WebSocket JSON-RPC endpoint.
;;;;
;;;; --ws and its friends were parsed and discarded. This is what they promised:
;;;; the same public JSON-RPC surface the HTTP listener serves (filtered by
;;;; --ws.api rather than --http.api), plus the two methods that only exist over
;;;; a connection that stays open -- eth_subscribe and eth_unsubscribe, which
;;;; the router dispatches as connection methods (DEVNET-WS-CONNECTION-CONTEXT).
;;;;
;;;; THE SUBSCRIPTION REGISTRY IS PER CONNECTION, AND SO IS THE THREAD. One
;;;; thread per client, owning that client's registry and cursor, is what makes
;;;; the whole thing free of locks above the store guard: no other thread can
;;;; see a registry, so nothing has to protect it. It also makes cleanup
;;;; trivial -- the socket closing IS the unsubscribe, which is exactly the
;;;; lifetime the spec gives a subscription.
;;;;
;;;; THE STORE GUARD IS TAKEN PER REQUEST AND PER POLL, NEVER ACROSS A WRITE.
;;;; Same rule the peer sessions follow. A client that has stopped reading must
;;;; not be able to hold the guard that block import needs.

(defconstant +devnet-ws-accept-timeout-seconds+ 1
  "How long the accept gate waits before returning to its loop. Our policy: also
the upper bound on noticing shutdown.")

(defconstant +devnet-ws-handshake-timeout-seconds+ 10
  "How long a client may take to send its upgrade request. Our policy. A socket
that connects and says nothing would otherwise occupy a thread indefinitely.")

(defconstant +devnet-ws-max-handshake-bytes+ 16384
  "The largest upgrade request accepted. Our policy, and a bound rather than a
target: without it a client that never sends the blank line can grow our heap.")

(defconstant +devnet-ws-poll-interval-seconds+ 1
  "How often a connection checks for notifications to push. Our policy, and the
worst-case latency between a block being imported and a newHeads subscriber
hearing about it. Matched to the pump's read gate so an idle connection wakes
once per second rather than twice.")

(defparameter *devnet-ws-max-connections* 128
  "How many WebSocket connections are served at once. Our policy (geth sets no
bound): each one is a thread and a poll of the store guard per second. The next
client is answered HTTP 503 on the accept thread and closed, before a session
thread exists.")

(defparameter *devnet-ws-write-timeout-seconds* 10
  "How long one frame write may wait for a client that is not reading. geth's
defaultWriteTimeout (rpc/json.go:42 at 38271784). Past it the connection ends,
so a stalled reader cannot hold its thread and its connection slot forever.")

(defparameter *devnet-ws-ping-interval-seconds* 30
  "Idle time after which the server pings. geth's wsPingInterval
(rpc/websocket.go:38).")

(defparameter *devnet-ws-pong-timeout-seconds* 30
  "How long a pinged client has to answer before the connection ends. geth's
wsPongTimeout (rpc/websocket.go:40).")

(defun devnet-ws-read-handshake (stream timeout-seconds)
  "Read the HTTP upgrade request from STREAM, returning it as a string.

Reads OCTETS, not characters. The stream has to be binary because everything
after the handshake is framed binary, and a request header is ASCII, so
decoding it by hand costs nothing and avoids depending on a bivalent stream."
  #-sbcl
  (declare (ignore stream timeout-seconds))
  #-sbcl
  nil
  #+sbcl
  (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                             :adjustable t :fill-pointer 0))
        (fd (sb-sys:fd-stream-fd stream)))
    (loop
      ;; LISTEN is false at end of file as well as when no byte is buffered,
      ;; and an fd at EOF is always usable for input. Reading only after LISTEN
      ;; therefore spun a core forever on a client that hung up before
      ;; finishing its request: wait -> usable at once -> LISTEN false -> wait.
      ;; Once the fd is usable, READ-BYTE cannot block -- it returns the next
      ;; octet or NIL at end of file -- so read it rather than ask LISTEN again.
      (let ((byte (cond
                    ((listen stream) (read-byte stream nil nil))
                    ((sb-sys:wait-until-fd-usable fd :input timeout-seconds nil)
                     (read-byte stream nil nil))
                    (t :timeout))))
        (cond
          ((eq byte :timeout) (return nil))
          ((null byte) (return nil))
          (t
           (vector-push-extend byte bytes)
           (when (> (fill-pointer bytes) +devnet-ws-max-handshake-bytes+)
             (return nil))
           ;; The request ends at the first blank line, which is the only
           ;; terminator an upgrade has -- there is no body.
           (when (and (>= (fill-pointer bytes) 4)
                      (= 13 (aref bytes (- (fill-pointer bytes) 4)))
                      (= 10 (aref bytes (- (fill-pointer bytes) 3)))
                      (= 13 (aref bytes (- (fill-pointer bytes) 2)))
                      (= 10 (aref bytes (- (fill-pointer bytes) 1))))
             (return (bytes-to-ascii (ensure-byte-vector bytes))))))))))

(defun devnet-ws-parse-handshake (text)
  "(VALUES METHOD TARGET HEADERS) from the upgrade request TEXT."
  (let* ((lines (loop with start = 0
                      for end = (position #\Newline text :start start)
                      collect (string-right-trim
                               '(#\Return)
                               (subseq text start (or end (length text))))
                      while end
                      do (setf start (1+ end))))
         (request-line (or (first lines) ""))
         (first-space (position #\Space request-line))
         (method (and first-space (subseq request-line 0 first-space)))
         (remainder (and first-space (subseq request-line (1+ first-space))))
         (second-space (and remainder (position #\Space remainder)))
         (target (and remainder
                      (subseq remainder 0
                              (or second-space (length remainder)))))
         (headers '()))
    (dolist (line (rest lines))
      (let ((colon (position #\: line)))
        (when colon
          (push (cons (string-trim '(#\Space #\Tab) (subseq line 0 colon))
                      (string-trim '(#\Space #\Tab) (subseq line (1+ colon))))
                headers))))
    (values method target (nreverse headers))))

(defun devnet-node-ws-method-filter (node)
  "The --ws.api method filter, or the public HTTP filter for a node built
without one (programmatic callers that predate --ws.api)."
  (or (devnet-node-ws-allowed-method-p node)
      (engine-rpc-http-service-allowed-method-p
       (devnet-node-public-service node))))

(defun devnet-ws-connection-context (node registry)
  "The RPC context one WebSocket connection answers through.

A copy of the public service's context with two differences. Its method filter
is --ws.api's (DEVNET-NODE-WS-METHOD-FILTER), not --http.api's. And
eth_subscribe / eth_unsubscribe are connection methods over REGISTRY: they
exist only on a connection that stays open, touch only its own registry, and
so run without the store guard. Going through the router rather than around it
gives them everything the router enforces for every other method: the method
filter, JSON-RPC notifications (no response), batches (a subscribe inside a
batch works, as it does in geth), and the batch limits."
  (rpc-context-rebind
   (engine-rpc-http-service-rpc-context (devnet-node-public-service node))
   :allowed-method-p (devnet-node-ws-method-filter node)
   :connection-method-function
   (lambda (method)
     (cond
       ((string= method "eth_subscribe")
        (lambda (params) (eth-rpc-handle-eth-subscribe params registry)))
       ((string= method "eth_unsubscribe")
        ;; T and +JSON-FALSE+ are what the writer renders as true and false.
        (lambda (params)
          (if (eth-rpc-handle-eth-unsubscribe params registry) t +json-false+)))))))

(defun devnet-ws-message-handler (node registry)
  "A function from one JSON-RPC message string to its response string, or NIL
when nothing is owed (a notification, or a batch of them)."
  (let ((context (devnet-ws-connection-context node registry)))
    (lambda (text)
      (handler-case
          (let ((response (rpc-handle-request-json text context)))
            (and (plusp (length response)) response))
        (error (condition)
          (devnet-ws-log node "ws.request_failed" condition)
          ;; NIL, not a keyword: the writer renders NIL as JSON null, and a
          ;; response whose id cannot be encoded is no response at all.
          (devnet-ws-error-json nil -32603 "Internal error"))))))


(defun devnet-ws-error-json (id code message)
  "A JSON-RPC error response, built here rather than borrowed from the router.

The router's own builders are internal to it, and reaching across for them
would couple this endpoint to the shape of another layer's private helpers for
the sake of six lines."
  (json-encode
   (list (cons "jsonrpc" "2.0")
         (cons "id" id)
         (cons "error" (list (cons "code" code)
                             (cons "message" message))))))

(defun devnet-ws-log (node name condition)
  (ethereum-lisp.telemetry:telemetry-log
   :warn name
   :sink (devnet-node-telemetry-sink node)
   :fields `(("error" . ,(princ-to-string condition)))))

(defun devnet-ws-notification-source (node registry)
  "A function returning the notifications this connection is owed.

Takes the store guard for the poll and releases it before anything is written,
because the write can block on a slow client and the guard must not."
  (lambda ()
    (call-with-devnet-node-store-guard
     node
     (lambda ()
       (eth-rpc-subscription-poll (devnet-node-store node) registry
                                  :config (devnet-node-config node))))))

(defun devnet-ws-serve-connection (node socket shutdown-controller)
  "Run one client from its handshake to its close."
  #+sbcl
  (let ((stream nil))
    (unwind-protect
         (handler-case
             (progn
               (setf stream (sb-bsd-sockets:socket-make-stream
                             socket :input t :output t
                                    :element-type '(unsigned-byte 8)
                                    :buffering :full))
               (let ((text (devnet-ws-read-handshake
                            stream +devnet-ws-handshake-timeout-seconds+)))
                 (when text
                   (multiple-value-bind (method target headers)
                       (devnet-ws-parse-handshake text)
                     (multiple-value-bind (response accepted-p)
                         (websocket-handshake-response
                          method target headers
                          :allowed-origins (devnet-node-ws-origins node)
                          :rpc-prefix (or (devnet-node-ws-rpc-prefix node) "/"))
                       (write-sequence
                        (coerce (ascii-to-bytes response)
                                '(vector (unsigned-byte 8)))
                        stream)
                       (finish-output stream)
                       (when accepted-p
                         ;; Writes past this point go to the descriptor with a
                         ;; deadline (WEBSOCKET-WRITE-FRAME), which needs it
                         ;; non-blocking; reads stay readiness-gated.
                         (setf (sb-bsd-sockets:non-blocking-mode socket) t)
                         (let* ((registry (make-eth-rpc-subscription-registry))
                                (connection
                                  (make-websocket-connection
                                   stream
                                   :write-timeout-seconds
                                   *devnet-ws-write-timeout-seconds*)))
                           (websocket-pump
                            connection
                            (devnet-ws-message-handler node registry)
                            :stop-p (lambda ()
                                      (devnet-shutdown-requested-p
                                       shutdown-controller))
                            :pending-notifications
                            (devnet-ws-notification-source node registry)
                            :poll-timeout-seconds
                            +devnet-ws-poll-interval-seconds+
                            :ping-interval-seconds
                            *devnet-ws-ping-interval-seconds*
                            :pong-timeout-seconds
                            *devnet-ws-pong-timeout-seconds*))))))))
           ;; A client that hangs up mid-frame, or sends something malformed,
           ;; ends that connection and nothing else.
           (error (condition)
             (devnet-ws-log node "ws.connection_failed" condition)))
      (if stream
          (ignore-errors (close stream))
          (ignore-errors (sb-bsd-sockets:socket-close socket)))))
  #-sbcl
  (progn node socket shutdown-controller nil))

(defun devnet-node-ws-endpoint (node)
  "(VALUES HOST PORT) for the WebSocket endpoint, or NIL when --ws is off."
  (let ((port (devnet-node-ws-port node)))
    (when (and port (devnet-node-ws-enabled-p node))
      (values (or (devnet-node-ws-host node) "127.0.0.1") port))))

(defun devnet-ws-live-session-count (sessions sessions-lock)
  #+sbcl
  (call-with-devnet-mutex
   sessions-lock
   (lambda () (count-if #'sb-thread:thread-alive-p sessions)))
  #-sbcl
  (progn sessions sessions-lock 0))

(defun devnet-ws-refuse-connection (socket)
  "Answer a connection over *DEVNET-WS-MAX-CONNECTIONS* with HTTP 503 and
close it, on the accept thread: a fresh socket's send buffer takes the short
reply without blocking, and no session thread is ever started for it."
  #+sbcl
  (ignore-errors
   (let ((stream (sb-bsd-sockets:socket-make-stream
                  socket :output t :element-type '(unsigned-byte 8)
                         :buffering :full)))
     (unwind-protect
          (progn
            (write-sequence
             (coerce (ascii-to-bytes
                      (websocket-http-error 503 "Service Unavailable"
                                            "too many WebSocket connections"))
                     '(vector (unsigned-byte 8)))
             stream)
            (finish-output stream))
       (close stream))))
  #+sbcl
  (ignore-errors (sb-bsd-sockets:socket-close socket))
  #-sbcl
  (progn socket nil))

(defun devnet-start-ws-server-thread (node shutdown-controller error-callback)
  "Start the WebSocket endpoint, returning (VALUES THREAD SESSIONS-FUNCTION).

Returns NIL when --ws is off, so a node that does not ask for it pays nothing."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (multiple-value-bind (host port) (devnet-node-ws-endpoint node)
    (when port
      (let ((listener (make-eth-sync-socket-listener :host host :port port))
            (sessions '())
            (sessions-lock (devnet-make-mutex "ethereum-lisp-ws-sessions")))
        (setf (devnet-node-ws-port node) (eth-sync-listener-port listener))
        (devnet-shutdown-controller-add-closeable
         shutdown-controller
         (lambda () (eth-sync-listener-close listener)))
        (values
         (sb-thread:make-thread
          (lambda ()
            ;; Mandatory, not defensive: an unhandled condition in ANY thread
            ;; exits the whole process under `sbcl --script`.
            (handler-case
                (loop
                  (when (devnet-shutdown-requested-p shutdown-controller)
                    (return))
                  (let ((socket (eth-sync-listener-accept
                                 listener
                                 :timeout-seconds
                                 +devnet-ws-accept-timeout-seconds+)))
                    (when (and socket
                               (>= (devnet-ws-live-session-count
                                    sessions sessions-lock)
                                   *devnet-ws-max-connections*))
                      (devnet-ws-refuse-connection socket)
                      (setf socket nil))
                    (when socket
                      ;; The accept loop never serves on its own thread, for the
                      ;; same reason the RLPx one does not: one slow client
                      ;; would stop it noticing anything, shutdown included.
                      ;; The session deregisters its socket when it ends, as
                      ;; the peer sessions do; otherwise the controller keeps
                      ;; one closure per connection ever accepted for the
                      ;; life of the node. A NIL token (shutdown already
                      ;; requested, socket already closed) removes nothing.
                      (let* ((token
                               (devnet-shutdown-controller-add-closeable
                                shutdown-controller
                                (lambda ()
                                  (ignore-errors
                                   (sb-bsd-sockets:socket-close socket)))))
                             (thread
                              (sb-thread:make-thread
                               (lambda ()
                                 (handler-case
                                     (unwind-protect
                                          (devnet-ws-serve-connection
                                           node socket shutdown-controller)
                                       (devnet-shutdown-controller-remove-closeable
                                        shutdown-controller token))
                                   (serious-condition (condition)
                                     (devnet-ws-log node "ws.session_failed"
                                                    condition))))
                               :name "ethereum-lisp-devnet-ws-session")))
                        (call-with-devnet-mutex
                         sessions-lock
                         (lambda ()
                           (setf sessions
                                 (cons thread
                                       (remove-if-not #'sb-thread:thread-alive-p
                                                      sessions)))))))))
              (serious-condition (condition)
                (funcall error-callback condition)
                (devnet-shutdown-request shutdown-controller))))
          :name "ethereum-lisp-devnet-ws")
         (lambda ()
           (call-with-devnet-mutex sessions-lock
                                   (lambda () (copy-list sessions)))))))))
