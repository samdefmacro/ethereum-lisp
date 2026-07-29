(in-package #:ethereum-lisp.discv5)

;;;; Discovery v5.1 UDP transport and one-request exchange driver.
;;;;
;;;; The driver performs the random-packet -> WHOAREYOU -> authenticated
;;;; handshake path when no session exists, then returns the first authenticated
;;;; response matching the request ID. It owns no threads; callers decide how a
;;;; long-running server loop is scheduled.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defun discv5-make-socket (&key (host "0.0.0.0") (port 0))
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :datagram :protocol :udp)))
    (handler-case
        (progn
          (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
          (sb-bsd-sockets:socket-bind
           socket (sb-bsd-sockets:make-inet-address host) port)
          (multiple-value-bind (address bound-port)
              (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (values socket bound-port)))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

(defun discv5-send-to (socket packet host port)
  (let ((packet (ensure-byte-vector packet)))
    (sb-bsd-sockets:socket-send
     socket packet (length packet)
     :address (list (sb-bsd-sockets:make-inet-address host) port))))

(defun discv5-receive (socket timeout-seconds)
  "Return (VALUES PACKET SOURCE-IP SOURCE-PORT), or NIL on timeout."
  (when (sb-sys:wait-until-fd-usable
         (sb-bsd-sockets:socket-file-descriptor socket)
         :input timeout-seconds)
    (let ((buffer (make-byte-vector +discv5-max-packet-size+)))
      (multiple-value-bind (received size address port)
          (sb-bsd-sockets:socket-receive socket buffer nil)
        (declare (ignore received))
        (when (and size (plusp size))
          (values (subseq buffer 0 size)
                  (ensure-byte-vector address)
                  port))))))

(defun discv5-endpoint-name (host port)
  (format nil "~A:~D" host port))

(defun discv5-message-request-id (message)
  (etypecase message
    (discv5-ping (discv5-ping-request-id message))
    (discv5-pong (discv5-pong-request-id message))
    (discv5-findnode (discv5-findnode-request-id message))
    (discv5-nodes (discv5-nodes-request-id message))))

(defun discv5-exchange
    (codec remote-record host port request
     &key (timeout-seconds 2) socket)
  "Send REQUEST to REMOTE-RECORD, handshaking if needed.

Returns the first authenticated response with the matching request ID. A caller
performing FINDNODE can continue with DISCV5-RECEIVE to collect the announced
NODES total."
  (let* ((remote (decode-enr remote-record))
         (remote-id (discv5-node-id (enr-public-key remote)))
         (endpoint (discv5-endpoint-name host port))
         (owned-socket-p (null socket))
         (socket (or socket (discv5-make-socket)))
         (initial-nonce nil))
    (unwind-protect
         (progn
           (if (discv5-codec-session codec remote-id endpoint)
               (discv5-send-to
                socket
                (discv5-encode-message-packet
                 codec remote-id endpoint request)
                host port)
               (multiple-value-bind (probe nonce)
                   (discv5-encode-random-packet codec remote-id)
                 (setf initial-nonce nonce)
                 (discv5-send-to socket probe host port)))
           (let ((deadline (+ (get-internal-real-time)
                              (* timeout-seconds internal-time-units-per-second)))
                 (sent-handshake-p nil))
             (loop
               (let ((remaining
                       (/ (max 0 (- deadline (get-internal-real-time)))
                          (coerce internal-time-units-per-second 'double-float))))
                 (when (zerop remaining) (return nil))
                 (multiple-value-bind (packet source-ip source-port)
                     (discv5-receive socket remaining)
                   (unless packet (return nil))
                   ;; The response must come from the endpoint we addressed.
                   (when (and (= source-port port)
                              (equalp source-ip
                                      (sb-bsd-sockets:make-inet-address host)))
                     (multiple-value-bind (kind message source-id)
                         (discv5-decode-packet
                          codec packet endpoint :expected-node-id remote-id)
                       (cond
                         ((and (eq kind :whoareyou)
                               (not sent-handshake-p)
                               (or (null initial-nonce)
                                   (equalp
                                    initial-nonce
                                    (discv5-whoareyou-request-nonce message))))
                          (discv5-send-to
                           socket
                           (discv5-encode-handshake-packet
                            codec remote-id endpoint message request remote-record)
                           host port)
                          (setf sent-handshake-p t))
                         ((and (eq kind :message)
                               (equalp source-id remote-id)
                               (equalp (discv5-message-request-id message)
                                       (discv5-message-request-id request)))
                          (return message))))))))))
      (when owned-socket-p
        (ignore-errors (sb-bsd-sockets:socket-close socket))))))
