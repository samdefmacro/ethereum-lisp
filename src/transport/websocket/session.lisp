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
            (:constructor %make-websocket-connection (stream)))
  "A connection that has completed its handshake.

BUFFER holds bytes read but not yet forming a whole frame; FRAGMENTS holds the
payloads of a message still being delivered across continuation frames."
  stream
  (buffer (make-byte-vector 0))
  (fragments '())
  (fragment-opcode nil)
  (closed-p nil))

(defun make-websocket-connection (stream)
  (%make-websocket-connection stream))

(defun websocket-write-frame (connection frame-bytes)
  "Write one already-encoded frame. The pump is the only caller, by design."
  (let ((stream (websocket-connection-stream connection)))
    (write-sequence (coerce frame-bytes '(vector (unsigned-byte 8))) stream)
    (finish-output stream)))

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
                                  +websocket-default-max-message-bytes+))
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
      ((= opcode +websocket-opcode-pong+) t)
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

(defun websocket-pump (connection on-message
                       &key stop-p pending-notifications max-message-bytes
                            (poll-timeout-seconds +websocket-poll-timeout-seconds+)
                            max-iterations)
  "Serve CONNECTION until it closes or STOP-P says to stop.

ON-MESSAGE receives each complete text message and returns the string to send
back, or NIL to send nothing. PENDING-NOTIFICATIONS, when supplied, is called
each pass and returns a list of strings to push. MAX-ITERATIONS bounds the loop
for tests; NIL means run until the connection ends."
  (let ((iterations 0))
    (loop
      (when (and stop-p (funcall stop-p))
        (websocket-send-close connection :status 1001 :reason "going away")
        (return :stopped))
      (when (and max-iterations (>= iterations max-iterations))
        (return :max-iterations))
      (incf iterations)
      ;; Read whatever is there before pushing, so a client's unsubscribe takes
      ;; effect before the next batch of notifications rather than after it.
      (when (websocket-stream-readable-p
             (websocket-connection-stream connection) poll-timeout-seconds)
        (unless (websocket-fill-buffer connection)
          (return :eof))
        (loop
          (let ((frame (websocket-take-frame
                        connection :max-payload-bytes max-message-bytes)))
            (unless frame (return))
            (unless (websocket-handle-frame connection frame on-message
                                            :max-message-bytes max-message-bytes)
              (return-from websocket-pump :closed)))))
      (when pending-notifications
        (dolist (notification (funcall pending-notifications))
          (websocket-send-text connection notification))))))
