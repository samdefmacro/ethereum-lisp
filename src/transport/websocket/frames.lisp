(in-package #:ethereum-lisp.websocket)

;;;; The WebSocket frame codec (RFC 6455 section 5).
;;;;
;;;; Pure, and deliberately so: framing is where a hand-written WebSocket
;;;; implementation goes wrong, and every one of those mistakes is reachable
;;;; from a byte vector. Nothing here touches a socket.
;;;;
;;;; THE MASKING RULE IS ASYMMETRIC AND NOT NEGOTIABLE. A client MUST mask every
;;;; frame it sends and a server MUST NOT mask any. It is not a security
;;;; measure between us and the peer -- the key travels in the frame -- it
;;;; exists so that a hostile page cannot make a browser emit bytes that a
;;;; confused intermediary would read as a second HTTP request. So an unmasked
;;;; client frame is a protocol error rather than a leniency we can extend, and
;;;; masking our own replies would break well-behaved clients.

(defun string-to-utf8-bytes (string)
  "STRING as UTF-8 octets.

A WebSocket text frame is defined to carry UTF-8, not whatever the host's
default happens to be, so the encoding is named explicitly. Everything we send
is JSON-RPC and in practice ASCII; a client that puts a non-ASCII string in an
error message would still be framed correctly."
  #+sbcl
  (ensure-byte-vector (sb-ext:string-to-octets string :external-format :utf-8))
  #-sbcl
  (ascii-to-bytes string))

(defun utf8-bytes-to-string (bytes)
  "UTF-8 octets as a string. The inverse of STRING-TO-UTF8-BYTES."
  #+sbcl
  (sb-ext:octets-to-string (coerce (ensure-byte-vector bytes)
                                   '(vector (unsigned-byte 8)))
                           :external-format :utf-8)
  #-sbcl
  (bytes-to-ascii bytes))

(defconstant +websocket-opcode-continuation+ #x0)
(defconstant +websocket-opcode-text+ #x1)
(defconstant +websocket-opcode-binary+ #x2)
(defconstant +websocket-opcode-close+ #x8)
(defconstant +websocket-opcode-ping+ #x9)
(defconstant +websocket-opcode-pong+ #xA)

(defconstant +websocket-max-control-payload+ 125
  "The largest payload a control frame may carry (RFC 6455 5.5). Fixed by the
spec, not by us: a control frame must fit in one frame so it can be handled
while a fragmented message is still in flight.")

(defconstant +websocket-default-max-message-bytes+ (* 16 1024 1024)
  "How large one assembled message may be. Our policy, and a bound rather than a
target: the length field is 64 bits wide, so without it a peer can announce a
payload larger than memory and we would try to allocate it before reading a
single byte of the body.")

(define-condition websocket-protocol-error (error)
  ((message :initarg :message :reader websocket-protocol-error-message)
   (status :initarg :status :initform 1002
           :reader websocket-protocol-error-status))
  (:report (lambda (condition stream)
             (format stream "WebSocket protocol error: ~A"
                     (websocket-protocol-error-message condition)))))

(defun websocket-fail (status format &rest arguments)
  (error 'websocket-protocol-error
         :status status
         :message (apply #'format nil format arguments)))

(defstruct (websocket-frame
            (:constructor make-websocket-frame (&key fin-p opcode payload)))
  "One decoded frame. PAYLOAD is already unmasked."
  (fin-p t)
  (opcode +websocket-opcode-text+)
  (payload (make-byte-vector 0)))

(defun websocket-control-opcode-p (opcode)
  (logtest opcode #x8))

(defun websocket-unmask (payload key)
  "PAYLOAD with the four-byte masking KEY removed, in place.

The transform is its own inverse, which is why the same routine serves both
directions -- though only one direction is ever used here, since a server never
masks."
  (loop for index from 0 below (length payload)
        do (setf (aref payload index)
                 (logxor (aref payload index) (aref key (mod index 4)))))
  payload)

(defun websocket-decode-frame
    (bytes &key (start 0) (max-payload-bytes +websocket-default-max-message-bytes+))
  "Decode one frame from BYTES at START.

Returns (VALUES FRAME NEXT-INDEX), or NIL when BYTES does not yet hold a whole
frame -- the caller reads more and asks again. Signals WEBSOCKET-PROTOCOL-ERROR
for a frame that can never be valid however many bytes arrive.

MAX-PAYLOAD-BYTES is checked against the ANNOUNCED length, before anything is
allocated. Checking after would mean honouring the announcement first, which is
the whole attack."
  (let ((available (- (length bytes) start)))
    (when (< available 2)
      (return-from websocket-decode-frame nil))
    (let* ((byte0 (aref bytes start))
           (byte1 (aref bytes (+ start 1)))
           (fin-p (logtest byte0 #x80))
           (reserved (logand byte0 #x70))
           (opcode (logand byte0 #x0F))
           (masked-p (logtest byte1 #x80))
           (length-field (logand byte1 #x7F))
           (cursor (+ start 2))
           (payload-length length-field))
      ;; We negotiate no extensions, so a reserved bit set means the peer is
      ;; speaking a protocol we did not agree to.
      (unless (zerop reserved)
        (websocket-fail 1002 "reserved bits set without a negotiated extension"))
      (cond
        ((= length-field 126)
         (when (< (- (length bytes) cursor) 2)
           (return-from websocket-decode-frame nil))
         (setf payload-length (+ (ash (aref bytes cursor) 8)
                                 (aref bytes (+ cursor 1))))
         (incf cursor 2)
         ;; A two-byte length below 126 is the long encoding of a short
         ;; payload, which the spec forbids: every length has one encoding.
         (when (< payload-length 126)
           (websocket-fail 1002 "payload length is not minimally encoded")))
        ((= length-field 127)
         (when (< (- (length bytes) cursor) 8)
           (return-from websocket-decode-frame nil))
         (setf payload-length 0)
         (loop repeat 8
               do (setf payload-length (+ (ash payload-length 8)
                                          (aref bytes cursor)))
                  (incf cursor))
         (when (< payload-length 65536)
           (websocket-fail 1002 "payload length is not minimally encoded"))))
      (when (websocket-control-opcode-p opcode)
        (unless fin-p
          (websocket-fail 1002 "control frames may not be fragmented"))
        (when (> payload-length +websocket-max-control-payload+)
          (websocket-fail 1002 "control frame payload exceeds ~D bytes"
                          +websocket-max-control-payload+)))
      (when (> payload-length max-payload-bytes)
        (websocket-fail 1009 "frame payload of ~D bytes exceeds the ~D byte limit"
                        payload-length max-payload-bytes))
      (let ((key nil))
        (when masked-p
          (when (< (- (length bytes) cursor) 4)
            (return-from websocket-decode-frame nil))
          (setf key (subseq bytes cursor (+ cursor 4)))
          (incf cursor 4))
        (when (< (- (length bytes) cursor) payload-length)
          (return-from websocket-decode-frame nil))
        (let ((payload (subseq bytes cursor (+ cursor payload-length))))
          (when key
            (websocket-unmask payload key))
          (values (make-websocket-frame :fin-p (and fin-p t)
                                        :opcode opcode
                                        :payload payload)
                  (+ cursor payload-length)))))))

(defun websocket-encode-frame (opcode payload &key (fin-p t))
  "One frame, as octets, for sending to a CLIENT.

Never masked, because a server must not mask. The length uses the shortest of
the three encodings, which is required rather than merely tidy."
  (let* ((payload (ensure-byte-vector payload))
         (length (length payload))
         (header
           (cond
             ((< length 126) (list (logior (if fin-p #x80 0) opcode) length))
             ((< length 65536)
              (list (logior (if fin-p #x80 0) opcode) 126
                    (ldb (byte 8 8) length) (ldb (byte 8 0) length)))
             (t
              (append (list (logior (if fin-p #x80 0) opcode) 127)
                      (loop for shift from 56 downto 0 by 8
                            collect (ldb (byte 8 shift) length)))))))
    (concat-bytes (ensure-byte-vector header) payload)))

(defun websocket-text-frame (string)
  "STRING as a text frame. The payload is UTF-8, which the spec requires."
  (websocket-encode-frame +websocket-opcode-text+
                          (string-to-utf8-bytes string)))

(defun websocket-close-frame (&key (status 1000) (reason ""))
  "A Close frame carrying STATUS and REASON.

A status of NIL sends an empty payload, which means `no status given` and is
what a close with nothing to say should look like."
  (websocket-encode-frame
   +websocket-opcode-close+
   (if (null status)
       (make-byte-vector 0)
       (concat-bytes (ensure-byte-vector
                      (list (ldb (byte 8 8) status) (ldb (byte 8 0) status)))
                     (string-to-utf8-bytes reason)))))

(defun websocket-pong-frame (payload)
  "A Pong echoing PAYLOAD, which is what a Ping obliges us to send back."
  (websocket-encode-frame +websocket-opcode-pong+ payload))
