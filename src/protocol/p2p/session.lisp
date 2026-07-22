(in-package #:ethereum-lisp.p2p)

;;;; The devp2p session handshake: the Hello exchange and capability
;;;; multiplexing that turn an authenticated RLPx connection into a peer we can
;;;; speak a subprotocol (eth) to.
;;;;
;;;; Right after the RLPx handshake both sides send a Hello listing the
;;;; capabilities they support. The shared capabilities are then assigned
;;;; contiguous blocks of message ids past the base "p2p" protocol's 16 ids, so
;;;; a subprotocol message with local id M rides the wire at OFFSET+M.

(defconstant +devp2p-base-protocol-length+ 16
  "The base 'p2p' protocol reserves message ids 0x00-0x0f; subprotocol ids
follow.")

(defparameter +devp2p-capability-message-counts+
  '(("eth" . 17))
  "Number of message ids each supported capability occupies, used to lay out
capability blocks during negotiation. Only eth is implemented; extend this
table as new capabilities are added.")

(defun devp2p-capability-message-count (name)
  (or (cdr (assoc name +devp2p-capability-message-counts+ :test #'string=))
      (error "capability ~S has no known message-id block length" name)))

(define-condition rlpx-disconnect (error)
  ((reason :initarg :reason :reader rlpx-disconnect-reason))
  (:report (lambda (condition stream)
             (format stream "peer sent devp2p Disconnect (reason ~D)"
                     (rlpx-disconnect-reason condition))))
  (:documentation "Signalled when a peer sends Disconnect where we expected a
protocol message."))

(defstruct (rlpx-shared-capability
            (:constructor %make-rlpx-shared-capability (name version offset)))
  name
  version
  offset)

(defun rlpx-negotiate-capabilities (local-caps remote-caps)
  "Return the capabilities shared by LOCAL-CAPS and REMOTE-CAPS, each with its
negotiated message-id offset.

Two peers share a capability when both advertise the same name; the highest
version both advertise is chosen. Shared capabilities are ordered by name and
assigned contiguous message-id blocks starting past the base protocol, as the
devp2p capability multiplexing rules require."
  (let ((names (remove-duplicates (mapcar #'devp2p-capability-name local-caps)
                                  :test #'string=))
        (shared '()))
    (dolist (name names)
      (let ((local-versions
              (loop for c in local-caps
                    when (string= (devp2p-capability-name c) name)
                      collect (devp2p-capability-version c)))
            (remote-versions
              (loop for c in remote-caps
                    when (string= (devp2p-capability-name c) name)
                      collect (devp2p-capability-version c))))
        (let ((common (intersection local-versions remote-versions)))
          (when common
            (push (cons name (reduce #'max common)) shared)))))
    (setf shared (sort shared #'string< :key #'car))
    (let ((offset +devp2p-base-protocol-length+)
          (result '()))
      (dolist (entry shared (nreverse result))
        (destructuring-bind (name . version) entry
          (push (%make-rlpx-shared-capability name version offset) result)
          (incf offset (devp2p-capability-message-count name)))))))

(defun rlpx-shared-capability-named (shared-caps name)
  "Return the shared capability called NAME, or NIL if it was not negotiated."
  (find name shared-caps
        :key #'rlpx-shared-capability-name :test #'string=))

(defun rlpx-send-hello (connection hello)
  "Send our devp2p Hello over CONNECTION.

The Hello is uncompressed because Snappy compression only begins once each side
has received the peer's Hello."
  (rlpx-connection-write-message connection +devp2p-message-hello+
                                 (encode-devp2p-hello hello) :compressed nil))

(defun rlpx-receive-hello (connection)
  "Read the peer's first devp2p message and return its decoded Hello.

The first message is uncompressed and must be Hello; a Disconnect instead
signals RLPX-DISCONNECT, and anything else is a protocol error."
  (multiple-value-bind (code payload)
      (rlpx-connection-read-message connection :compressed nil)
    (cond
      ((= code +devp2p-message-hello+) (decode-devp2p-hello payload))
      ((= code +devp2p-message-disconnect+)
       (error 'rlpx-disconnect :reason (decode-devp2p-disconnect payload)))
      (t (error "expected devp2p Hello (0x00) but got message id ~D" code)))))

(defun rlpx-exchange-hello (connection hello)
  "Run the devp2p Hello exchange over CONNECTION.

Sends our HELLO, reads the peer's, and returns (VALUES PEER-HELLO
SHARED-CAPABILITIES), where the shared capabilities carry their negotiated
message-id offsets. Both sides send before reading, so there is no deadlock."
  (rlpx-send-hello connection hello)
  (let ((peer (rlpx-receive-hello connection)))
    (values peer
            (rlpx-negotiate-capabilities (devp2p-hello-capabilities hello)
                                         (devp2p-hello-capabilities peer)))))

(defun rlpx-send-ping (connection)
  "Send a devp2p Ping (compressed, as all post-Hello messages are)."
  (rlpx-connection-write-message connection +devp2p-message-ping+
                                 (encode-devp2p-ping)))

(defun rlpx-send-pong (connection)
  "Send a devp2p Pong in reply to a peer's Ping."
  (rlpx-connection-write-message connection +devp2p-message-pong+
                                 (encode-devp2p-pong)))

(defun rlpx-send-disconnect (connection reason)
  "Tell the peer we are closing the connection for REASON."
  (rlpx-connection-write-message connection +devp2p-message-disconnect+
                                 (encode-devp2p-disconnect reason)))
