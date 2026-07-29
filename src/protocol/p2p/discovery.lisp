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
Returns (VALUES PACKET HOST PORT) -- a responder needs the sender's address, and
that address is the one it actually came from rather than the one the packet
claims, which is the whole basis of an endpoint proof.

Waits for the socket to become readable first: sb-sys:with-deadline does not
interrupt a blocking recvfrom, so a bare receive would ignore the timeout and
could block forever on an unresponsive peer. wait-until-fd-usable honours the
timeout, and once it reports readable the receive returns the pending datagram
immediately."
  (when (sb-sys:wait-until-fd-usable
         (sb-bsd-sockets:socket-file-descriptor socket) :input timeout-seconds)
    (handler-case
        (let ((buffer (make-byte-vector +discv4-max-packet-size+)))
          (multiple-value-bind (received size address port)
              (sb-bsd-sockets:socket-receive socket buffer nil)
            (declare (ignore received))
            (when (and size (plusp size))
              (values (subseq buffer 0 size)
                      (and address (discv4-ip-string address))
                      port))))
      (error () nil))))

(defun discv4-find-peers (bootnode-enode private-key
                          &key (timeout-seconds 5) target
                               (local-host "0.0.0.0") (local-port 0)
                               (local-tcp-port local-port)
                               (advertised-host "127.0.0.1"))
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
                  (from (discv4-endpoint-for-host
                         advertised-host local-udp local-tcp-port))
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

(defconstant +discv4-enr-request-attempts+ 3
  "How many times the crawl asks one node for its record before giving up.

More than once because the first attempt races the bond. We treat a node as
bonded the moment its Pong arrives, but IT treats US as bonded only once we
answer the Ping it sends back, and an ENRRequest arriving before that is
correctly dropped as unbonded -- by our own responder as much as anyone's. A
retry costs one small datagram; not retrying costs the node.")

(defconstant +discv4-enr-request-retry-seconds+ 1
  "Gap between record requests to the same node, and the grace period after the
last one before the crawl is willing to conclude. Our policy.")

(defun discv4-lookup (bootnode-enodes private-key
                      &key (alpha 3) (max-queries 16) (timeout-seconds 8)
                           (local-host "0.0.0.0") (local-port 0)
                           (local-tcp-port local-port)
                           (advertised-host "127.0.0.1")
                           record-filter)
  "Crawl outward from BOOTNODE-ENODES to discover peers over one persistent UDP
socket. Bonds with known nodes, sends FindNode toward random targets, and folds
the returned nodes back into the search, up to MAX-QUERIES FindNode requests or
TIMEOUT-SECONDS. Returns (VALUES ENODE-URLS STATS) -- the discovered enode URLs
excluding ourselves and the seed bootnodes, and an alist of crawl counts. This
is a bounded crawl; a full Kademlia routing table with k-buckets and
closest-node termination is left for later.

RECORD-FILTER, when supplied, is a predicate on a decoded ENR, and ONLY the
nodes it accepts are returned. discv4 is a single DHT shared by every chain
built on it, so an unfiltered crawl yields mostly nodes that will refuse us at
the eth handshake -- the point of asking each bonded node for its record first
is that a UDP round trip is orders of magnitude cheaper than the TCP connection
and ECIES handshake needed to learn the same thing from the peer directly.

Filtering necessarily returns far FEWER nodes, and that is the intent: a node
must be bonded and must answer ENRRequest to survive it, where an unfiltered
crawl returns every address anyone ever mentioned. Nodes that stay silent are
simply re-tried by the next crawl."
  (let ((our-node-id (node-id-from-private-key private-key)))
    (multiple-value-bind (socket local-udp)
        (discv4-make-socket :host local-host :port local-port)
      (unwind-protect
           (let ((from (discv4-endpoint-for-host
                        advertised-host local-udp local-tcp-port))
                 (seen (make-hash-table :test 'equal))    ; id-hex -> discv4-node
                 (bonded (make-hash-table :test 'equal))  ; id-hex -> t
                 (pinged (make-hash-table :test 'equal))  ; id-hex -> t
                 (queried (make-hash-table :test 'equal)) ; id-hex -> t
                 (pending (make-hash-table :test 'equal)) ; ping-hash-hex -> node
                 ;; id-hex -> (attempts . last-sent-at), and id-hex -> verdict.
                 (enr-asked (make-hash-table :test 'equal))
                 (enr-verdict (make-hash-table :test 'equal))
                 (boot-keys (make-hash-table :test 'equal))
                 (deadline (+ (get-universal-time) timeout-seconds))
                 (query-count 0)
                 (last-query-at nil)
                 (last-enr-at nil))
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
                          ;; Track the outstanding ping with the time it was sent
                          ;; so an unanswered ping can be pruned rather than
                          ;; pinning the crawl open forever.
                          (setf (gethash (bytes-to-hex (subseq packet 0 32)) pending)
                                (cons node (get-universal-time))
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
                      (enr-request-node (node)
                        (let ((key (idkey (discv4-node-node-id node)))
                              (entry (gethash (idkey (discv4-node-node-id node))
                                              enr-asked)))
                          (send-node node
                                     (encode-discv4-packet
                                      private-key +discv4-packet-enr-request+
                                      (encode-discv4-enr-request
                                       (make-discv4-enr-request
                                        :expiration (discv4-expiration)))))
                          (setf (gethash key enr-asked)
                                (cons (1+ (if entry (car entry) 0))
                                      (get-universal-time)))))
                      (enr-due-p (key now)
                        ;; A bonded node we have no verdict on yet, that is
                        ;; either unasked or due another attempt.
                        (and record-filter
                             (gethash key bonded)
                             (not (gethash key enr-verdict))
                             (let ((entry (gethash key enr-asked)))
                               (or (null entry)
                                   (and (< (car entry)
                                           +discv4-enr-request-attempts+)
                                        (>= now (+ (cdr entry)
                                                   +discv4-enr-request-retry-seconds+)))))))
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
               ;; Seed the search from the bootnodes. make-inet-address is
               ;; IPv4-only, so a bracketed-IPv6 or DNS bootnode host is skipped
               ;; here (IPv6 discovery is a TODO); a malformed entry is skipped
               ;; too rather than aborting the crawl.
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
                   ;; Drop pings that never drew a Pong so they do not pin the
                   ;; crawl open until the deadline.
                   (dolist (key (loop for k being the hash-keys of pending
                                        using (hash-value entry)
                                      when (> now (+ (cdr entry) 2)) collect k))
                     (remhash key pending))
                   ;; Stop early once nothing is in flight and no bond or query
                   ;; work remains — but only after a grace second for the last
                   ;; query's reply, so we do not quit before Neighbors arrive.
                   (when (and (zerop (hash-table-count pending))
                              (or (null last-query-at) (>= now (1+ last-query-at)))
                              (or (null last-enr-at)
                                  (>= now (+ last-enr-at
                                             +discv4-enr-request-retry-seconds+)))
                              (null (candidates
                                     (lambda (key node)
                                       (declare (ignore node))
                                       (or (and (not (gethash key bonded))
                                                (not (gethash key pinged)))
                                           (and (< query-count max-queries)
                                                (gethash key bonded)
                                                (not (gethash key queried)))
                                           (enr-due-p key now))))))
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
                       (dolist (node (subseq* ready (min alpha
                                                         (- max-queries query-count))))
                         (findnode-node node target)
                         (setf last-query-at now))))
                   ;; Ask bonded nodes for their record. Uncapped, unlike the
                   ;; bond and query fan-outs: this is one small datagram per
                   ;; bonded node, the bonded set is what the alpha-capped
                   ;; bonding already limited, and every node left unasked is a
                   ;; node the crawl cannot return.
                   (dolist (node (candidates (lambda (key node)
                                               (declare (ignore node))
                                               (enr-due-p key now))))
                     (enr-request-node node)
                     (setf last-enr-at now)))
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
                                     (entry (gethash key pending))
                                     (node (car entry)))
                                (when (and entry
                                           (bytes= sender (discv4-node-node-id node)))
                                  ;; We got our Pong: stop tracking the ping even
                                  ;; if it is stale, and bond only when fresh.
                                  (remhash key pending)
                                  (unless (discv4-expired-p
                                           (discv4-pong-expiration pong))
                                    (setf (gethash (idkey (discv4-node-node-id node))
                                                   bonded)
                                          t)))))
                             ((= type +discv4-packet-neighbors+)
                              (let ((reply (decode-discv4-neighbors data)))
                                (unless (discv4-expired-p
                                         (discv4-neighbors-expiration reply))
                                  ;; One malformed node must not lose the rest.
                                  (dolist (node (discv4-neighbors-nodes reply))
                                    (ignore-errors (add-node node))))))
                             ((and record-filter
                                   (= type +discv4-packet-enr-response+))
                              (let ((key (idkey sender)))
                                ;; Only a record we asked for, and only from the
                                ;; node it describes. The packet signature says
                                ;; who sent it and the record's own signature
                                ;; says whose it is; requiring those to agree is
                                ;; what stops a node earning a verdict by
                                ;; forwarding somebody else's record.
                                (when (gethash key enr-asked)
                                  (let* ((response
                                           (decode-discv4-enr-response data))
                                         (record
                                           (ignore-errors
                                            (decode-enr
                                             (discv4-enr-response-record
                                              response))))
                                         (public-key (and record
                                                          (enr-public-key record))))
                                    (setf (gethash key enr-verdict)
                                          (cond
                                            ((not (and public-key
                                                       (bytes= public-key sender)))
                                             :unusable)
                                            ((funcall record-filter record) :match)
                                            (t :mismatch)))))))))
                       (error () nil)))))
               (values
                (loop for node being the hash-values of seen
                      for key = (idkey (discv4-node-node-id node))
                      for host = (node-host node)
                      when (and host
                                (not (gethash key boot-keys))
                                (or (null record-filter)
                                    (eq :match (gethash key enr-verdict))))
                        collect (enode-url (discv4-node-node-id node) host
                                           (discv4-node-tcp-port node)))
                ;; What the crawl saw, so a filtered crawl that returns nothing
                ;; can be told apart from one that never got off the ground --
                ;; no bonds is a broken socket, bonds but no records is a
                ;; discv4 without EIP-868, records but no matches is a DHT full
                ;; of other people's chains.
                (list (cons "seen" (hash-table-count seen))
                      (cons "bonded" (hash-table-count bonded))
                      (cons "records" (hash-table-count enr-verdict))
                      (cons "matched"
                            (loop for v being the hash-values of enr-verdict
                                  count (eq v :match)))
                      (cons "mismatched"
                            (loop for v being the hash-values of enr-verdict
                                  count (eq v :mismatch)))))))
        (ignore-errors (sb-bsd-sockets:socket-close socket))))))


;;;; Answering discovery, rather than only performing it.
;;;;
;;;; A node that crawls but never replies is invisible: nobody can find it, so
;;;; nobody dials it, so it only ever has the peers it went looking for. These
;;;; are the replies, kept as pure functions of a packet plus a table so the
;;;; protocol decisions can be tested without a socket. The loop that owns the
;;;; socket lives in the CLI layer with the other threads.

(defun discv4-serve-ping
    (private-key table packet data sender host port now &key local-endpoint)
  "Answer a Ping and begin, but do not complete, an endpoint proof.

The Pong echoes the hash of the ping packet, which is what proves to the sender
that we received THAT ping rather than replaying an old one. An unsolicited
Ping proves nothing about the sender; when LOCAL-ENDPOINT is supplied, a Ping
back is returned as the second value and only its matching Pong may bond it."
  (let ((ping (decode-discv4-ping data)))
    (unless (discv4-expired-p (discv4-ping-expiration ping))
      (let* ((claimed (discv4-ping-from ping))
             (observed (discv4-endpoint-for-host
                        host port (discv4-endpoint-tcp-port claimed)))
             (entry (discv4-table-put
                     table sender host port
                     (discv4-endpoint-tcp-port claimed) now))
             (pong
               (encode-discv4-packet
                private-key +discv4-packet-pong+
                (encode-discv4-pong
                 (make-discv4-pong :to observed
                                   :ping-hash (subseq packet 0 32)
                                   :expiration (discv4-expiration)))))
             (ping-back
               (when (and entry local-endpoint)
                 (encode-discv4-packet
                  private-key +discv4-packet-ping+
                  (encode-discv4-ping
                   (make-discv4-ping
                    :from local-endpoint
                    :to observed
                    :expiration (discv4-expiration)))))))
        (when ping-back
          (discv4-table-note-ping table sender (subseq ping-back 0 32) now))
        (values pong ping-back)))))

(defun discv4-neighbors-packets (private-key nodes)
  "Encode NODES as Neighbors packets, split to stay inside the datagram limit.

A full bucket of sixteen nodes does not fit in one UDP packet, so the reply is
split. Sending one oversized datagram would simply be dropped."
  (let ((packets '())
        (batch '())
        (per-packet 4))
    (dolist (node nodes)
      (push node batch)
      (when (>= (length batch) per-packet)
        (push (encode-discv4-packet
               private-key +discv4-packet-neighbors+
               (encode-discv4-neighbors
                (make-discv4-neighbors :nodes (nreverse batch)
                                       :expiration (discv4-expiration))))
              packets)
        (setf batch '())))
    (when batch
      (push (encode-discv4-packet
             private-key +discv4-packet-neighbors+
             (encode-discv4-neighbors
              (make-discv4-neighbors :nodes (nreverse batch)
                                     :expiration (discv4-expiration))))
            packets))
    (nreverse packets)))

(defun discv4-private-ip-p (ip)
  "Whether IPv4 IP is non-routable and must not be relayed to a public peer."
  (let ((ip (ensure-byte-vector ip)))
    (or (/= (length ip) 4)
        (let ((a (aref ip 0))
              (b (aref ip 1)))
          (or (= a 0)
              (= a 10)
              (= a 127)
              (and (= a 169) (= b 254))
              (and (= a 172) (<= 16 b 31))
              (and (= a 192) (= b 168))
              (>= a 224))))))

(defun discv4-relay-address-p (entry requester-host)
  "Whether ENTRY may be relayed to REQUESTER-HOST.

Private peers may learn private neighbors; public peers never receive private,
loopback, link-local, multicast, or otherwise non-routable addresses."
  (or (null requester-host)
      (let ((requester-private
              (discv4-private-ip-p
               (sb-bsd-sockets:make-inet-address requester-host)))
            (entry-private
              (discv4-private-ip-p
               (sb-bsd-sockets:make-inet-address
                (discv4-table-entry-host entry)))))
        (or requester-private (not entry-private)))))

(defun discv4-serve-find-node
    (private-key table data sender now &key requester-host)
  "Answer a FindNode with the bonded nodes nearest the target, as packets.

REFUSES a sender that has not proved its own endpoint. Without that check we
would be an amplifier: a forged FindNode carrying a victim's address as its
source would have us send that victim several packets much larger than the one
byte of effort it cost the attacker."
  (let ((request (decode-discv4-find-node data)))
    (unless (or (discv4-expired-p (discv4-find-node-expiration request))
                (not (discv4-table-bonded-p table sender now)))
      (let ((nodes (mapcar (lambda (entry)
                             (make-discv4-node
                              (ensure-byte-vector
                               (sb-bsd-sockets:make-inet-address
                                (discv4-table-entry-host entry)))
                              (discv4-table-entry-udp-port entry)
                              (discv4-table-entry-tcp-port entry)
                              (discv4-table-entry-node-id entry)))
                           (remove-if-not
                            (lambda (entry)
                              (discv4-relay-address-p entry requester-host))
                            (discv4-table-closest
                             table (discv4-find-node-target request)
                             :now now)))))
        (when nodes
          (discv4-neighbors-packets private-key nodes))))))

(defun discv4-serve-enr-request (private-key table data sender packet now
                                 &key record-pairs (record-seq 1))
  "Answer an ENRRequest with our signed record.

Bonded senders only, for the same amplification reason as FindNode: a signed
record is larger than the request that asks for it.

RECORD-PAIRS are the chain-specific entries to advertise, an alist of
(key-string . value) — in practice the `eth` fork-id entry. Serving a record
without them is not harmless: a record is exactly how another node decides
whether we are worth dialing, and one that says nothing about our chain is
indistinguishable from a node on somebody else's."
  (let ((request (decode-discv4-enr-request data)))
    (unless (or (discv4-expired-p (discv4-enr-request-expiration request))
                (not (discv4-table-bonded-p table sender now)))
      (encode-discv4-packet
       private-key +discv4-packet-enr-response+
       (encode-discv4-enr-response
        (make-discv4-enr-response :request-hash (subseq packet 0 32)
                                  :record (encode-enr private-key record-seq
                                                      record-pairs)))))))
