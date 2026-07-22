(in-package #:ethereum-lisp.p2p)

;;;; discv4 discovery over UDP: the transport and a minimal find-peers driver.
;;;;
;;;; The driver bonds with a bootnode (Ping/Pong endpoint proof, in both
;;;; directions), then asks it for neighbors (FindNode/Neighbors) and returns
;;;; their enode URLs to dial. It is the first datagram user in the tree, so it
;;;; carries its own contrib require.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defconstant +discv4-unix-epoch-universal-time+ 2208988800
  "Seconds between the Lisp universal-time epoch (1900) and the Unix epoch.")

(defun discv4-unix-time ()
  (- (get-universal-time) +discv4-unix-epoch-universal-time+))

(defun discv4-expiration (&optional (seconds-from-now 20))
  "A discv4 packet expiration: a Unix timestamp SECONDS-FROM-NOW in the future."
  (+ (discv4-unix-time) seconds-from-now))

(defun discv4-endpoint-for-host (host udp-port tcp-port)
  "Build a discv4 endpoint from a dotted-quad HOST string and its ports."
  (make-discv4-endpoint (ensure-byte-vector (sb-bsd-sockets:make-inet-address host))
                        udp-port tcp-port))

(defun discv4-ip-string (ip-bytes)
  "Render a 4-byte IPv4 as a dotted-quad, or a 16-byte IPv6 as a bracketed
address; NIL for any other length."
  (let ((ip (ensure-byte-vector ip-bytes)))
    (cond
      ((= 4 (length ip))
       (format nil "~D.~D.~D.~D" (aref ip 0) (aref ip 1) (aref ip 2) (aref ip 3)))
      ((= 16 (length ip))
       (format nil "[~{~(~X~)~^:~}]"
               (loop for i from 0 below 16 by 2
                     collect (logior (ash (aref ip i) 8) (aref ip (1+ i))))))
      (t nil))))

(defun discv4-make-socket (&key (host "0.0.0.0") (port 0))
  "Open and bind a UDP datagram socket; return (VALUES SOCKET BOUND-PORT)."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :datagram :protocol :udp)))
    (handler-case
        (progn
          (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
          (sb-bsd-sockets:socket-bind socket
                                      (sb-bsd-sockets:make-inet-address host) port)
          (multiple-value-bind (address bound-port) (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (values socket bound-port)))
      ;; Do not leak the file descriptor if a sockopt or bind fails.
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

(defun discv4-send-to (socket packet host port)
  "Send PACKET to HOST:PORT over the datagram SOCKET."
  (let ((packet (ensure-byte-vector packet)))
    (sb-bsd-sockets:socket-send
     socket packet (length packet)
     :address (list (sb-bsd-sockets:make-inet-address host) port))))

(defun discv4-receive (socket timeout-seconds)
  "Receive one datagram within TIMEOUT-SECONDS, or NIL on timeout.
Returns the packet bytes.

Waits for the socket to become readable first: sb-sys:with-deadline does not
interrupt a blocking recvfrom, so a bare receive would ignore the timeout and
could block forever on an unresponsive peer. wait-until-fd-usable honours the
timeout, and once it reports readable the receive returns the pending datagram
immediately."
  (when (sb-sys:wait-until-fd-usable
         (sb-bsd-sockets:socket-file-descriptor socket) :input timeout-seconds)
    (handler-case
        (let ((buffer (make-byte-vector +discv4-max-packet-size+)))
          (multiple-value-bind (received size)
              (sb-bsd-sockets:socket-receive socket buffer nil)
            (declare (ignore received))
            (and size (plusp size) (subseq buffer 0 size))))
      (error () nil))))

(defun discv4-find-peers (bootnode-enode private-key
                          &key (timeout-seconds 5) target
                               (local-host "0.0.0.0") (local-port 0))
  "Discover peers via a bootnode. Returns (VALUES ENODE-URLS BONDED-P).

Sends a Ping to BOOTNODE-ENODE and waits for the matching Pong (endpoint
proof), answering the bootnode's own Ping so the bond is mutual, then sends
FindNode and collects the Neighbors it returns, converting them to enode URLs.
BONDED-P reports whether the Ping/Pong endpoint proof completed — true even when
the bootnode has no neighbors to return."
  (multiple-value-bind (boot-id boot-host boot-tcp boot-disc)
      (parse-enode-url bootnode-enode)
    (multiple-value-bind (socket local-udp) (discv4-make-socket :host local-host
                                                                :port local-port)
      (unwind-protect
           (let* ((our-node-id (node-id-from-private-key private-key))
                  (boot-id (ensure-byte-vector boot-id))
                  (from (discv4-endpoint-for-host "127.0.0.1" local-udp local-udp))
                  (to (discv4-endpoint-for-host boot-host boot-disc boot-tcp))
                  (ping-packet
                    (encode-discv4-packet
                     private-key +discv4-packet-ping+
                     (encode-discv4-ping
                      (make-discv4-ping :from from :to to
                                        :expiration (discv4-expiration)))))
                  (ping-hash (subseq ping-packet 0 32))
                  (bonded nil)
                  (neighbors '())
                  (find-sent-at nil)
                  ;; A full Neighbors reply spans several packets; once the first
                  ;; arrives, keep reading for a short grace window to collect the
                  ;; rest before returning.
                  (neighbors-deadline nil)
                  (deadline (+ (get-universal-time) timeout-seconds)))
             (discv4-send-to socket ping-packet boot-host boot-disc)
             (loop
               (let ((now (get-universal-time)))
                 (when (or (>= now deadline)
                           (and neighbors-deadline (>= now neighbors-deadline)))
                   (return))
                 ;; Once bonded, ask for neighbors — once, then at most once a
                 ;; second while still waiting, to ride out the bond race without
                 ;; flooding the bootnode.
                 (when (and bonded (null neighbors)
                            (or (null find-sent-at) (>= now (1+ find-sent-at))))
                   (discv4-send-to
                    socket
                    (encode-discv4-packet
                     private-key +discv4-packet-find-node+
                     (encode-discv4-find-node
                      (make-discv4-find-node :target (or target our-node-id)
                                             :expiration (discv4-expiration))))
                    boot-host boot-disc)
                   (setf find-sent-at now)))
               (let ((packet (discv4-receive socket 1)))
                 (when packet
                   (handler-case
                       (multiple-value-bind (type data sender)
                           (decode-discv4-packet packet)
                         (cond
                           ;; The bootnode pings us to verify our endpoint; a
                           ;; Pong lets it consider us bonded and answer FindNode.
                           ((= type +discv4-packet-ping+)
                            (let ((their-hash (subseq packet 0 32))
                                  (their-ping (decode-discv4-ping data)))
                              (discv4-send-to
                               socket
                               (encode-discv4-packet
                                private-key +discv4-packet-pong+
                                (encode-discv4-pong
                                 (make-discv4-pong
                                  :to (discv4-ping-from their-ping)
                                  :ping-hash their-hash
                                  :expiration (discv4-expiration))))
                               boot-host boot-disc)))
                           ;; Our Ping is answered by the bootnode itself: the
                           ;; endpoint proof is complete.
                           ((and (= type +discv4-packet-pong+)
                                 (bytes= sender boot-id)
                                 (bytes= ping-hash
                                         (discv4-pong-ping-hash
                                          (decode-discv4-pong data))))
                            (setf bonded t))
                           ;; Only trust neighbors from the bootnode we asked.
                           ((and (= type +discv4-packet-neighbors+)
                                 (bytes= sender boot-id))
                            (setf neighbors
                                  (append neighbors
                                          (discv4-neighbors-nodes
                                           (decode-discv4-neighbors data))))
                            (unless neighbors-deadline
                              (setf neighbors-deadline (1+ (get-universal-time)))))))
                     (error () nil)))))
             (values (loop for node in neighbors
                           for host = (discv4-ip-string (discv4-node-ip node))
                           when host
                             collect (enode-url (discv4-node-node-id node)
                                                host
                                                (discv4-node-tcp-port node)))
                     bonded))
        (ignore-errors (sb-bsd-sockets:socket-close socket))))))
