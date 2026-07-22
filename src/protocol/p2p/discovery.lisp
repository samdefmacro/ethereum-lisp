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

(defun discv4-expired-p (expiration &key (grace-seconds 2))
  "True when EXPIRATION (a Unix timestamp) is in the past by more than
GRACE-SECONDS. The discv4 spec mandates dropping packets whose expiration has
passed; GRACE-SECONDS is a small local lenience for clock skew."
  (< (+ expiration grace-seconds) (discv4-unix-time)))

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
                            (let ((their-ping (decode-discv4-ping data)))
                              (unless (discv4-expired-p
                                       (discv4-ping-expiration their-ping))
                                (discv4-send-to
                                 socket
                                 (encode-discv4-packet
                                  private-key +discv4-packet-pong+
                                  (encode-discv4-pong
                                   (make-discv4-pong
                                    :to (discv4-ping-from their-ping)
                                    :ping-hash (subseq packet 0 32)
                                    :expiration (discv4-expiration))))
                                 boot-host boot-disc))))
                           ;; Our Ping is answered by the bootnode itself: the
                           ;; endpoint proof is complete.
                           ((and (= type +discv4-packet-pong+)
                                 (bytes= sender boot-id))
                            (let ((pong (decode-discv4-pong data)))
                              (when (and (not (discv4-expired-p
                                               (discv4-pong-expiration pong)))
                                         (bytes= ping-hash
                                                 (discv4-pong-ping-hash pong)))
                                (setf bonded t))))
                           ;; Only trust neighbors from the bootnode we asked.
                           ((and (= type +discv4-packet-neighbors+)
                                 (bytes= sender boot-id))
                            (let ((reply (decode-discv4-neighbors data)))
                              (unless (discv4-expired-p
                                       (discv4-neighbors-expiration reply))
                                (setf neighbors
                                      (append neighbors
                                              (discv4-neighbors-nodes reply)))
                                (unless neighbors-deadline
                                  (setf neighbors-deadline
                                        (1+ (get-universal-time)))))))))
                     (error () nil)))))
             (values (loop for node in neighbors
                           for host = (discv4-ip-string (discv4-node-ip node))
                           when host
                             collect (enode-url (discv4-node-node-id node)
                                                host
                                                (discv4-node-tcp-port node)))
                     bonded))
        (ignore-errors (sb-bsd-sockets:socket-close socket))))))

(defun subseq* (list count)
  "The first COUNT elements of LIST, or all of them if LIST is shorter."
  (subseq list 0 (min count (length list))))

(defun discv4-node-distance (id-a id-b)
  "The Kademlia XOR distance between two 64-byte node ids: keccak256(id-a) XOR
keccak256(id-b) as a big-endian unsigned integer. Smaller means closer."
  (let ((ha (keccak-256 (ensure-byte-vector id-a)))
        (hb (keccak-256 (ensure-byte-vector id-b))))
    (bytes-to-integer (ensure-byte-vector (map 'list #'logxor ha hb)))))

(defun discv4-lookup (bootnode-enodes private-key
                      &key (alpha 3) (max-queries 16) (timeout-seconds 8)
                           (local-host "0.0.0.0") (local-port 0))
  "Crawl outward from BOOTNODE-ENODES to discover peers over one persistent UDP
socket. Bonds with known nodes, sends FindNode toward random targets, and folds
the returned nodes back into the search, up to MAX-QUERIES FindNode requests or
TIMEOUT-SECONDS. Returns the discovered enode URLs (excluding ourselves and the
seed bootnodes). This is a bounded crawl; a full Kademlia routing table with
k-buckets and closest-node termination is left for later."
  (let ((our-node-id (node-id-from-private-key private-key)))
    (multiple-value-bind (socket local-udp)
        (discv4-make-socket :host local-host :port local-port)
      (unwind-protect
           (let ((from (discv4-endpoint-for-host "127.0.0.1" local-udp local-udp))
                 (seen (make-hash-table :test 'equal))    ; id-hex -> discv4-node
                 (bonded (make-hash-table :test 'equal))  ; id-hex -> t
                 (pinged (make-hash-table :test 'equal))  ; id-hex -> t
                 (queried (make-hash-table :test 'equal)) ; id-hex -> t
                 (pending (make-hash-table :test 'equal)) ; ping-hash-hex -> node
                 (boot-keys (make-hash-table :test 'equal))
                 (deadline (+ (get-universal-time) timeout-seconds))
                 (query-count 0)
                 (last-query-at nil))
             (labels ((idkey (id) (node-id-to-hex id))
                      (node-host (node) (discv4-ip-string (discv4-node-ip node)))
                      (send-node (node packet)
                        (let ((host (node-host node)))
                          (when host
                            ;; A send to an unreachable discovered node must not
                            ;; abort the whole crawl.
                            (ignore-errors
                             (discv4-send-to socket packet host
                                             (discv4-node-udp-port node))))))
                      (ping-node (node)
                        (let* ((to (make-discv4-endpoint (discv4-node-ip node)
                                                         (discv4-node-udp-port node)
                                                         (discv4-node-tcp-port node)))
                               (packet (encode-discv4-packet
                                        private-key +discv4-packet-ping+
                                        (encode-discv4-ping
                                         (make-discv4-ping :from from :to to
                                                           :expiration (discv4-expiration))))))
                          (setf (gethash (bytes-to-hex (subseq packet 0 32)) pending) node
                                (gethash (idkey (discv4-node-node-id node)) pinged) t)
                          (send-node node packet)))
                      (findnode-node (node target)
                        (send-node node
                                   (encode-discv4-packet
                                    private-key +discv4-packet-find-node+
                                    (encode-discv4-find-node
                                     (make-discv4-find-node :target target
                                                            :expiration (discv4-expiration)))))
                        (setf (gethash (idkey (discv4-node-node-id node)) queried) t)
                        (incf query-count))
                      (add-node (node)
                        (let ((key (idkey (discv4-node-node-id node))))
                          (when (and (not (gethash key seen))
                                     (node-host node)
                                     (not (bytes= (discv4-node-node-id node) our-node-id)))
                            (setf (gethash key seen) node))))
                      (candidates (predicate)
                        (loop for node being the hash-values of seen
                              when (funcall predicate
                                            (idkey (discv4-node-node-id node)) node)
                                collect node)))
               ;; Seed the search from the bootnodes (skip any malformed entry).
               (dolist (enode bootnode-enodes)
                 (ignore-errors
                  (multiple-value-bind (id host tcp disc) (parse-enode-url enode)
                    (let ((node (make-discv4-node
                                 (ensure-byte-vector
                                  (sb-bsd-sockets:make-inet-address host))
                                 disc tcp (ensure-byte-vector id))))
                      (setf (gethash (idkey id) seen) node
                            (gethash (idkey id) boot-keys) t)))))
               (loop
                 (let ((now (get-universal-time)))
                   (when (>= now deadline) (return))
                   ;; Stop early once nothing is in flight and no bond or query
                   ;; work remains — but only after a grace second for the last
                   ;; query's reply, so we do not quit before Neighbors arrive.
                   (when (and (zerop (hash-table-count pending))
                              (or (null last-query-at) (>= now (1+ last-query-at)))
                              (null (candidates
                                     (lambda (key node)
                                       (declare (ignore node))
                                       (or (and (not (gethash key bonded))
                                                (not (gethash key pinged)))
                                           (and (< query-count max-queries)
                                                (gethash key bonded)
                                                (not (gethash key queried))))))))
                     (return))
                   ;; Bond with nodes we have not pinged yet.
                   (dolist (node (subseq* (candidates
                                           (lambda (key node)
                                             (declare (ignore node))
                                             (and (not (gethash key bonded))
                                                  (not (gethash key pinged)))))
                                          alpha))
                     (ping-node node))
                   ;; Ask bonded, un-queried nodes for neighbors near a random
                   ;; target, closest first, while under the query budget.
                   (when (< query-count max-queries)
                     (let* ((target (node-id-from-private-key
                                     (secp256k1-random-private-key)))
                            (ready (sort (candidates
                                          (lambda (key node)
                                            (declare (ignore node))
                                            (and (gethash key bonded)
                                                 (not (gethash key queried)))))
                                         #'<
                                         :key (lambda (node)
                                                (discv4-node-distance
                                                 (discv4-node-node-id node) target)))))
                       (dolist (node (subseq* ready alpha))
                         (findnode-node node target)
                         (setf last-query-at now)))))
                 (let ((packet (discv4-receive socket 1)))
                   (when packet
                     (handler-case
                         (multiple-value-bind (type data sender) (decode-discv4-packet packet)
                           (cond
                             ((= type +discv4-packet-ping+)
                              (let ((their (decode-discv4-ping data)))
                                (unless (discv4-expired-p (discv4-ping-expiration their))
                                  (send-node
                                   (make-discv4-node
                                    (discv4-endpoint-ip (discv4-ping-from their))
                                    (discv4-endpoint-udp-port (discv4-ping-from their))
                                    (discv4-endpoint-tcp-port (discv4-ping-from their))
                                    sender)
                                   (encode-discv4-packet
                                    private-key +discv4-packet-pong+
                                    (encode-discv4-pong
                                     (make-discv4-pong :to (discv4-ping-from their)
                                                       :ping-hash (subseq packet 0 32)
                                                       :expiration (discv4-expiration))))))))
                             ((= type +discv4-packet-pong+)
                              (let* ((pong (decode-discv4-pong data))
                                     (key (bytes-to-hex (discv4-pong-ping-hash pong)))
                                     (node (gethash key pending)))
                                (when (and node
                                           (bytes= sender (discv4-node-node-id node))
                                           (not (discv4-expired-p
                                                 (discv4-pong-expiration pong))))
                                  (setf (gethash (idkey (discv4-node-node-id node)) bonded) t)
                                  (remhash key pending))))
                             ((= type +discv4-packet-neighbors+)
                              (let ((reply (decode-discv4-neighbors data)))
                                (unless (discv4-expired-p
                                         (discv4-neighbors-expiration reply))
                                  (dolist (node (discv4-neighbors-nodes reply))
                                    (add-node node)))))))
                       (error () nil)))))
               (loop for node being the hash-values of seen
                     for key = (idkey (discv4-node-node-id node))
                     for host = (node-host node)
                     when (and host (not (gethash key boot-keys)))
                       collect (enode-url (discv4-node-node-id node) host
                                          (discv4-node-tcp-port node)))))
        (ignore-errors (sb-bsd-sockets:socket-close socket))))))
