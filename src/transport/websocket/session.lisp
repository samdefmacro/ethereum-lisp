(in-package #:ethereum-lisp.websocket)

;;;; A WebSocket connection, from the handshake to the close.
;;;;
;;;; TRANSPORT ONLY. Nothing here knows what a block is. The session is handed
;;;; a function that turns a request string into a response string, and a
;;;; function that yields whatever should be pushed unprompted; both come from
;;;; the layer above. That is what keeps `eth_subscribe` out of the frame codec.
;;;;
;;;; ONE THREAD WRITES, AND IT IS THIS ONE. The same rule the RLPx sessions
;;;; follow, for a weaker reason but the same shape: a WebSocket frame is not
;;;; atomic on the wire, so two threads writing a frame each can interleave
;;;; their bytes and desynchronise the stream permanently. Rather than lock
;;;; around every write, the pump does all of them -- it reads when the socket
;;;; has something, and drains the notification source when it does not.
;;;;
;;;; READS ARE READINESS-GATED for the third time in this codebase, and for the
;;;; same reason as the other two: a blocking read on a quiet socket cannot be
;;;; interrupted, and this thread has a shutdown to notice.

(defconstant +websocket-poll-timeout-seconds+ 1
  "How long the pump waits on the socket before checking for work of its own.
Our policy: also the upper bound on how long a notification waits behind an idle
connection, and on noticing shutdown.")

(defstruct (websocket-connection
            (:constructor %make-websocket-connection
                (stream &key write-timeout-seconds)))
  "A connection that has completed its handshake.

BUFFER holds bytes read but not yet forming a whole frame; FRAGMENTS holds the
payloads of a message still being delivered across continuation frames.

WRITE-TIMEOUT-SECONDS, when set, bounds every frame write: the stream's
descriptor must then be non-blocking, and a client that stops reading for that
long fails the write instead of pinning this thread (and its connection slot)
forever. LAST-WRITE and PONG-DEADLINE are internal-real-time stamps for the
pump's keepalive."
  stream
  (buffer (make-byte-vector 0))
  (fragments '())
  (fragment-opcode nil)
  (closed-p nil)
  (write-timeout-seconds nil)
  (last-write (get-internal-real-time))
  (pong-deadline nil))

(defun make-websocket-connection (stream &key write-timeout-seconds)
  (%make-websocket-connection stream
                              :write-timeout-seconds write-timeout-seconds))

(define-condition websocket-write-timeout (error)
  ((seconds :initarg :seconds :reader websocket-write-timeout-seconds))
  (:report (lambda (condition stream)
             (format stream "WebSocket peer accepted no data for ~A s"
                     (websocket-write-timeout-seconds condition)))))

(defun websocket-seconds-until (deadline)
  (max 0 (/ (- deadline (get-internal-real-time))
            internal-time-units-per-second)))

(defun websocket-write-octets-with-deadline (stream octets seconds)
  "Write OCTETS to STREAM's non-blocking descriptor within SECONDS in total.

A blocking write to a peer that has stopped reading never returns, and neither
SBCL's stream timeout nor the socket API bounds it (measured on SBCL 2.2.9: a
1 s stream :TIMEOUT did not end a blocked FINISH-OUTPUT in 60 s). So the bytes
go straight to the descriptor, which returns EAGAIN when the peer's window is
full, and the wait for writability carries the deadline."
  #+sbcl
  (let* ((fd (sb-sys:fd-stream-fd stream))
         (octets (coerce octets '(simple-array (unsigned-byte 8) (*))))
         (deadline (+ (get-internal-real-time)
                      (round (* seconds internal-time-units-per-second))))
         (offset 0)
         (length (length octets)))
    (finish-output stream)
    (loop while (< offset length)
          do (multiple-value-bind (written errno)
                 (sb-unix:unix-write fd octets offset (- length offset))
               (cond
                 ((and written (plusp written)) (incf offset written))
                 ((or (eql errno sb-unix:eagain) (eql errno sb-unix:ewouldblock)
                      (eql errno sb-unix:eintr))
                  (unless (sb-sys:wait-until-fd-usable
                           fd :output (websocket-seconds-until deadline) nil)
                    (error 'websocket-write-timeout :seconds seconds)))
                 (t (error "WebSocket write failed (errno ~A)" errno))))))
  #-sbcl
  (progn seconds
         (write-sequence octets stream)
         (finish-output stream)))

(defun websocket-write-frame (connection frame-bytes)
  "Write one already-encoded frame. The pump is the only caller, by design."
  (let ((stream (websocket-connection-stream connection))
        (timeout (websocket-connection-write-timeout-seconds connection)))
    (if timeout
        (websocket-write-octets-with-deadline stream frame-bytes timeout)
        (progn
          (write-sequence (coerce frame-bytes '(vector (unsigned-byte 8))) stream)
          (finish-output stream)))
    (setf (websocket-connection-last-write connection) (get-internal-real-time))))

(defun websocket-send-text (connection string)
  (websocket-write-frame connection (websocket-text-frame string)))

(defun websocket-send-close (connection &key (status 1000) (reason ""))
  (unless (websocket-connection-closed-p connection)
    (setf (websocket-connection-closed-p connection) t)
    (ignore-errors
     (websocket-write-frame connection
                            (websocket-close-frame :status status
                                                   :reason reason)))))

(defun websocket-fill-buffer (connection)
  "Read whatever octets are available onto the buffer.

Returns NIL at end of stream. Only ever called when the descriptor said it was
readable, so the first READ-BYTE returns immediately and a NIL from it means the
peer closed rather than that we guessed wrong.

NOT READ-SEQUENCE. That blocks until it has filled the whole buffer or hit end
of stream, so asking for 4096 bytes when a client sent a 60-byte request hangs
until it sends 4036 more -- which, for a request/response protocol, is never."
  (let ((stream (websocket-connection-stream connection))
        (chunk (make-array 0 :element-type '(unsigned-byte 8)
                             :adjustable t :fill-pointer 0))
        (first-byte (read-byte (websocket-connection-stream connection) nil nil)))
    (when (null first-byte)
      (return-from websocket-fill-buffer nil))
    (vector-push-extend first-byte chunk)
    (loop while (listen stream)
          for byte = (read-byte stream nil nil)
          while byte
          do (vector-push-extend byte chunk))
    (setf (websocket-connection-buffer connection)
          (concat-bytes (websocket-connection-buffer connection)
                        (ensure-byte-vector chunk)))
    t))

(defun websocket-take-frame (connection &key max-payload-bytes)
  "Decode one frame out of the buffer, or NIL if it does not hold a whole one."
  (multiple-value-bind (frame next)
      (websocket-decode-frame (websocket-connection-buffer connection)
                              :max-payload-bytes
                              (or max-payload-bytes
                                  +websocket-default-max-message-bytes+)
                              ;; This end is always the server.
                              :require-masked-p t)
    (when frame
      (setf (websocket-connection-buffer connection)
            (subseq (websocket-connection-buffer connection) next))
      frame)))

(defun websocket-assemble-message (connection frame &key max-message-bytes)
  "Fold FRAME into the message being assembled.

Returns (VALUES PAYLOAD OPCODE) once a message is complete, or NIL while more
fragments are still expected. Control frames are never fragmented and so never
reach here."
  (let ((opcode (websocket-frame-opcode frame))
        (limit (or max-message-bytes +websocket-default-max-message-bytes+)))
    (cond
      ((= opcode +websocket-opcode-continuation+)
       (unless (websocket-connection-fragment-opcode connection)
         (websocket-fail 1002 "continuation frame with no message to continue"))
       (push (websocket-frame-payload frame)
             (websocket-connection-fragments connection)))
      (t
       (when (websocket-connection-fragment-opcode connection)
         (websocket-fail 1002 "new message began before the last one finished"))
       (setf (websocket-connection-fragment-opcode connection) opcode)
       (push (websocket-frame-payload frame)
             (websocket-connection-fragments connection))))
    ;; The limit is enforced across the assembled message, not per frame: a peer
    ;; can otherwise send an unbounded number of small fragments and reach the
    ;; same place one frame at a time.
    (let ((total (reduce #'+ (websocket-connection-fragments connection)
                         :key #'length)))
      (when (> total limit)
        (websocket-fail 1009 "message of ~D bytes exceeds the ~D byte limit"
                        total limit)))
    (when (websocket-frame-fin-p frame)
      (let ((payload (apply #'concat-bytes
                            (reverse (websocket-connection-fragments connection))))
            (message-opcode (websocket-connection-fragment-opcode connection)))
        (setf (websocket-connection-fragments connection) '()
              (websocket-connection-fragment-opcode connection) nil)
        (values payload message-opcode)))))

(defun websocket-handle-frame (connection frame on-message &key max-message-bytes)
  "Act on one frame. Returns NIL when the connection should close.

Ping and Close are answered here rather than passed up, because they are
transport obligations: a peer that pings and gets no pong is entitled to
conclude we are gone."
  (let ((opcode (websocket-frame-opcode frame)))
    (cond
      ((= opcode +websocket-opcode-close+)
       (websocket-send-close connection)
       nil)
      ((= opcode +websocket-opcode-ping+)
       (websocket-write-frame connection
                              (websocket-pong-frame
                               (websocket-frame-payload frame)))
       t)
      ((= opcode +websocket-opcode-pong+)
       ;; The answer to our keepalive ping (WEBSOCKET-PUMP): the peer is alive.
       (setf (websocket-connection-pong-deadline connection) nil)
       t)
      ((or (= opcode +websocket-opcode-text+)
           (= opcode +websocket-opcode-binary+)
           (= opcode +websocket-opcode-continuation+))
       (multiple-value-bind (payload message-opcode)
           (websocket-assemble-message connection frame
                                       :max-message-bytes max-message-bytes)
         (when payload
           (when (= message-opcode +websocket-opcode-binary+)
             ;; JSON-RPC over WebSocket is a text protocol. Accepting binary
             ;; would mean guessing at an encoding the peer never declared.
             (websocket-fail 1003 "binary messages are not accepted"))
           (let ((reply (funcall on-message (utf8-bytes-to-string payload))))
             (when reply
               (websocket-send-text connection reply)))))
       t)
      (t (websocket-fail 1002 "unknown opcode ~D" opcode)))))

(defun websocket-stream-readable-p (stream timeout-seconds)
  #+sbcl
  (if (sb-sys:fd-stream-p stream)
      (or (listen stream)
          (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd stream)
                                       :input timeout-seconds nil))
      (listen stream))
  #-sbcl
  (progn timeout-seconds (listen stream)))

(defun websocket-keepalive (connection ping-interval-seconds pong-timeout-seconds)
  "Ping an idle peer and give up on one that stops answering.

geth's shape (rpc/websocket.go:38-40, pingLoop at :371-398 at 38271784): after
PING-INTERVAL-SECONDS without a write, send a ping and expect the pong within
PONG-TIMEOUT-SECONDS. Returns :PONG-TIMEOUT when that deadline has passed."
  (let ((now (get-internal-real-time))
        (deadline (websocket-connection-pong-deadline connection)))
    (cond
      ((and deadline (> now deadline)) :pong-timeout)
      ((and (null deadline)
            (>= (- now (websocket-connection-last-write connection))
                (* ping-interval-seconds internal-time-units-per-second)))
       (websocket-write-frame
        connection
        (websocket-encode-frame +websocket-opcode-ping+ (make-byte-vector 0)))
       (setf (websocket-connection-pong-deadline connection)
             (+ (get-internal-real-time)
                (round (* pong-timeout-seconds internal-time-units-per-second))))
       nil))))

(defun websocket-close-reason (message)
  "MESSAGE cut to what fits a Close frame beside its two status bytes."
  (let ((reason (or message "")))
    (loop while (> (length (string-to-utf8-bytes reason))
                   (- +websocket-max-control-payload+ 2))
          do (setf reason (subseq reason 0 (1- (length reason)))))
    reason))

(defun websocket-pump (connection on-message
                       &key stop-p pending-notifications max-message-bytes
                            (poll-timeout-seconds +websocket-poll-timeout-seconds+)
                            ping-interval-seconds pong-timeout-seconds
                            max-iterations)
  "Serve CONNECTION until it closes or STOP-P says to stop.

ON-MESSAGE receives each complete text message and returns the string to send
back, or NIL to send nothing. PENDING-NOTIFICATIONS, when supplied, is called
each pass and returns a list of strings to push. PING-INTERVAL-SECONDS and
PONG-TIMEOUT-SECONDS, when both given, turn on the keepalive
(WEBSOCKET-KEEPALIVE); they are checked once per pass, so POLL-TIMEOUT-SECONDS
is their resolution. MAX-ITERATIONS bounds the loop for tests; NIL means run
until the connection ends.

A frame that breaks the protocol (unmasked, reserved bits, oversized) is
answered with a Close carrying its status, and the pump returns
:PROTOCOL-ERROR, as RFC 6455 section 7.1.7 asks of an endpoint that must fail
the connection."
  (let ((iterations 0))
    (handler-case
        (loop
          (when (and stop-p (funcall stop-p))
            (websocket-send-close connection :status 1001 :reason "going away")
            (return :stopped))
          (when (and max-iterations (>= iterations max-iterations))
            (return :max-iterations))
          (incf iterations)
          ;; Read whatever is there before pushing, so a client's unsubscribe
          ;; takes effect before the next batch of notifications, not after.
          (when (websocket-stream-readable-p
                 (websocket-connection-stream connection) poll-timeout-seconds)
            (unless (websocket-fill-buffer connection)
              (return :eof))
            (loop
              (let ((frame (websocket-take-frame
                            connection :max-payload-bytes max-message-bytes)))
                (unless frame (return))
                (unless (websocket-handle-frame
                         connection frame on-message
                         :max-message-bytes max-message-bytes)
                  (return-from websocket-pump :closed)))))
          (when pending-notifications
            (dolist (notification (funcall pending-notifications))
              (websocket-send-text connection notification)))
          (when (and ping-interval-seconds pong-timeout-seconds
                     (eq :pong-timeout
                         (websocket-keepalive connection ping-interval-seconds
                                              pong-timeout-seconds)))
            (websocket-send-close connection :status 1001
                                             :reason "pong timeout")
            (return :pong-timeout)))
      (websocket-protocol-error (condition)
        (websocket-send-close
         connection
         :status (websocket-protocol-error-status condition)
         :reason (websocket-close-reason
                  (websocket-protocol-error-message condition)))
        :protocol-error))))

