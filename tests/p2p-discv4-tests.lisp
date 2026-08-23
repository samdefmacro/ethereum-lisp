(in-package #:ethereum-lisp.test)

(deftest discv4-bonded-public-enodes-retains-only-endpoint-proven-routes
  (:layer :unit :module :p2p)
  (let* ((public-id
           (node-id-from-private-key (secp256k1-random-private-key)))
         (private-id
           (node-id-from-private-key (secp256k1-random-private-key)))
         (unbonded-id
           (node-id-from-private-key (secp256k1-random-private-key)))
         (public-node
           (ethereum-lisp.p2p:make-discv4-node
            (hex-to-bytes "0x08080808") 30304 30303 public-id))
         (private-node
           (ethereum-lisp.p2p:make-discv4-node
            (hex-to-bytes "0x0a000001") 30305 30305 private-id))
         (unbonded-node
           (ethereum-lisp.p2p:make-discv4-node
            (hex-to-bytes "0x09090909") 30306 30306 unbonded-id))
         (seen (make-hash-table :test #'equal))
         (bonded (make-hash-table :test #'equal)))
    (setf (gethash (node-id-to-hex public-id) seen) public-node
          (gethash (node-id-to-hex private-id) seen) private-node
          (gethash (node-id-to-hex unbonded-id) seen) unbonded-node
          (gethash (node-id-to-hex public-id) bonded) t
          (gethash (node-id-to-hex private-id) bonded) t)
    (let ((routes
            (ethereum-lisp.p2p::discv4-bonded-public-enodes seen bonded)))
      (is (= 1 (length routes)))
      (multiple-value-bind (node-id host tcp-port discovery-port)
          (parse-enode-url (first routes))
        (is (bytes= public-id node-id))
        (is (string= "8.8.8.8" host))
        (is (= 30303 tcp-port))
        ;; The endpoint proof applies to UDP, which may differ from TCP.
        (is (= 30304 discovery-port))))))

(deftest nat-pmp-and-upnp-scripted-gateways-map-both-protocols
  (:layer :unit :module :p2p)
  (let ((calls '()))
    (flet ((pmp-exchange (host port request)
             (push (list host port (aref request 1)) calls)
             (case (aref request 1)
               (0 (ensure-byte-vector
                   #(0 128 0 0 0 0 0 1 203 0 113 9)))
               (1 (ensure-byte-vector
                   #(0 129 0 0 0 0 0 2 118 95 118 95 0 0 14 16)))
               (2 (ensure-byte-vector
                   #(0 130 0 0 0 0 0 3 118 95 118 95 0 0 14 16))))))
      (multiple-value-bind (address mapped-p)
          (ethereum-lisp.nat:nat-resolve-and-map
           (ethereum-lisp.nat:parse-nat-policy "pmp:192.0.2.1")
           30303 :udp-exchange #'pmp-exchange)
        (is (string= "203.0.113.9" address))
        (is mapped-p)
        (is (= 3 (length calls))))))
  (let ((posts 0))
    (flet ((udp (host port request)
             (declare (ignore host port request))
             (format nil
                     "HTTP/1.1 200 OK~C~CLOCATION: http://192.0.2.1/root.xml~C~C~C~C"
                     #\Return #\Linefeed #\Return #\Linefeed
                     #\Return #\Linefeed))
           (http-get-fixture (url)
             (declare (ignore url))
             "<root><service><controlURL>/upnp/control</controlURL></service></root>")
           (post (url request)
             (is (string= "/upnp/control" url))
             (is (search "AddPortMapping" request))
             (incf posts)
             (format nil "HTTP/1.1 200 OK~C~C~C~C"
                     #\Return #\Linefeed #\Return #\Linefeed)))
      (multiple-value-bind (address mapped-p)
          (ethereum-lisp.nat:nat-resolve-and-map
           (ethereum-lisp.nat:parse-nat-policy "upnp") 30303
           :udp-exchange #'udp :http-get #'http-get-fixture :http-post #'post
           :internal-address "192.168.1.2")
        (is (null address))
        (is mapped-p)
        (is (= 2 posts)))))
  (multiple-value-bind (address mapped-p)
      (ethereum-lisp.nat:nat-resolve-and-map
       (ethereum-lisp.nat:parse-nat-policy "extip:198.51.100.4") 30303)
    (is (string= "198.51.100.4" address))
    (is (null mapped-p))))

;;;; discv4 packet codec: sign/frame/recover and per-packet RLP round-trips.

(deftest discv4-packet-signs-frames-and-recovers-the-sender
  (:layer :unit :module :p2p)
  (let* ((private-key (secp256k1-random-private-key))
         (node-id (node-id-from-private-key private-key))
         (from (ethereum-lisp.p2p:make-discv4-endpoint
                (hex-to-bytes "0x7f000001") 30303 30303))
         (to (ethereum-lisp.p2p:make-discv4-endpoint
              (hex-to-bytes "0x0a000002") 30304 0))
         (ping (ethereum-lisp.p2p:make-discv4-ping
                :from from :to to :expiration 1234567890))
         (packet (ethereum-lisp.p2p:encode-discv4-packet
                  private-key ethereum-lisp.p2p:+discv4-packet-ping+
                  (ethereum-lisp.p2p:encode-discv4-ping ping))))
    (multiple-value-bind (type data sender)
        (ethereum-lisp.p2p:decode-discv4-packet packet)
      (is (= ethereum-lisp.p2p:+discv4-packet-ping+ type))
      ;; The signer's node id is recovered from the signature.
      (is (bytes= node-id sender))
      (let ((decoded (ethereum-lisp.p2p:decode-discv4-ping data)))
        (is (= 4 (ethereum-lisp.p2p:discv4-ping-version decoded)))
        (is (= 1234567890 (ethereum-lisp.p2p:discv4-ping-expiration decoded)))
        (is (= 30303 (ethereum-lisp.p2p:discv4-endpoint-udp-port
                      (ethereum-lisp.p2p:discv4-ping-from decoded))))
        ;; A zero port round-trips through the empty-string encoding.
        (is (= 0 (ethereum-lisp.p2p:discv4-endpoint-tcp-port
                  (ethereum-lisp.p2p:discv4-ping-to decoded))))
        (is (bytes= (hex-to-bytes "0x0a000002")
                    (ethereum-lisp.p2p:discv4-endpoint-ip
                     (ethereum-lisp.p2p:discv4-ping-to decoded))))))))

(deftest discv4-pong-carries-the-ping-hash
  (:layer :unit :module :p2p)
  (let* ((private-key (secp256k1-random-private-key))
         (ping-hash (hex-to-bytes
                     "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (pong (ethereum-lisp.p2p:make-discv4-pong
                :to (ethereum-lisp.p2p:make-discv4-endpoint
                     (hex-to-bytes "0x7f000001") 30303 30303)
                :ping-hash ping-hash :expiration 42))
         (packet (ethereum-lisp.p2p:encode-discv4-packet
                  private-key ethereum-lisp.p2p:+discv4-packet-pong+
                  (ethereum-lisp.p2p:encode-discv4-pong pong))))
    (multiple-value-bind (type data sender)
        (ethereum-lisp.p2p:decode-discv4-packet packet)
      (declare (ignore sender))
      (is (= ethereum-lisp.p2p:+discv4-packet-pong+ type))
      (let ((decoded (ethereum-lisp.p2p:decode-discv4-pong data)))
        (is (bytes= ping-hash (ethereum-lisp.p2p:discv4-pong-ping-hash decoded)))
        (is (= 42 (ethereum-lisp.p2p:discv4-pong-expiration decoded)))))))

(deftest discv4-find-node-and-neighbors-round-trip
  (:layer :unit :module :p2p)
  (let* ((private-key (secp256k1-random-private-key))
         (target (node-id-from-private-key (secp256k1-random-private-key)))
         (fn (ethereum-lisp.p2p:make-discv4-find-node :target target :expiration 99))
         (fn-packet (ethereum-lisp.p2p:encode-discv4-packet
                     private-key ethereum-lisp.p2p:+discv4-packet-find-node+
                     (ethereum-lisp.p2p:encode-discv4-find-node fn)))
         (node-a (ethereum-lisp.p2p:make-discv4-node
                  (hex-to-bytes "0x0a000001") 30303 30303
                  (node-id-from-private-key (secp256k1-random-private-key))))
         (node-b (ethereum-lisp.p2p:make-discv4-node
                  (hex-to-bytes "0x0a000002") 30304 30305
                  (node-id-from-private-key (secp256k1-random-private-key))))
         (neighbors (ethereum-lisp.p2p:make-discv4-neighbors
                     :nodes (list node-a node-b) :expiration 100))
         (nb-packet (ethereum-lisp.p2p:encode-discv4-packet
                     private-key ethereum-lisp.p2p:+discv4-packet-neighbors+
                     (ethereum-lisp.p2p:encode-discv4-neighbors neighbors))))
    (multiple-value-bind (type data sender)
        (ethereum-lisp.p2p:decode-discv4-packet fn-packet)
      (declare (ignore sender))
      (is (= ethereum-lisp.p2p:+discv4-packet-find-node+ type))
      (is (bytes= target (ethereum-lisp.p2p:discv4-find-node-target
                          (ethereum-lisp.p2p:decode-discv4-find-node data)))))
    (multiple-value-bind (type data sender)
        (ethereum-lisp.p2p:decode-discv4-packet nb-packet)
      (declare (ignore sender))
      (is (= ethereum-lisp.p2p:+discv4-packet-neighbors+ type))
      (let* ((decoded (ethereum-lisp.p2p:decode-discv4-neighbors data))
             (nodes (ethereum-lisp.p2p:discv4-neighbors-nodes decoded)))
        (is (= 2 (length nodes)))
        (is (= 30305 (ethereum-lisp.p2p:discv4-node-tcp-port (second nodes))))
        (is (bytes= (ethereum-lisp.p2p:discv4-node-node-id node-a)
                    (ethereum-lisp.p2p:discv4-node-node-id (first nodes))))))))

(deftest discv4-decode-rejects-tampered-and-oversize-packets
  (:layer :unit :module :p2p)
  (let* ((private-key (secp256k1-random-private-key))
         (packet (ethereum-lisp.p2p:encode-discv4-packet
                  private-key ethereum-lisp.p2p:+discv4-packet-find-node+
                  (ethereum-lisp.p2p:encode-discv4-find-node
                   (ethereum-lisp.p2p:make-discv4-find-node
                    :target (node-id-from-private-key private-key)
                    :expiration 1)))))
    ;; A single flipped byte breaks the hash check.
    (let ((tampered (copy-seq packet)))
      (setf (aref tampered 40) (logxor (aref tampered 40) 1))
      (signals error (ethereum-lisp.p2p:decode-discv4-packet tampered)))
    ;; A packet over the 1280-byte limit is rejected.
    (signals error
      (ethereum-lisp.p2p:decode-discv4-packet
       (make-byte-vector (1+ ethereum-lisp.p2p:+discv4-max-packet-size+))))
    ;; A packet with no room for a body is rejected.
    (signals error
      (ethereum-lisp.p2p:decode-discv4-packet (make-byte-vector 98)))))

(deftest discv4-find-peers-bonds-and-collects-neighbors-over-udp
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((server-priv
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (server-id (node-id-from-private-key server-priv))
         (client-priv
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (advertised-id (node-id-from-private-key
                         #x0102030405060708090a0b0c0d0e0f101112131415161718))
         (client-from nil)
         (server-error nil))
    (multiple-value-bind (server-socket server-port)
        (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
      (unwind-protect
           (let ((server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (loop named serve repeat 4 do
                            (let ((buffer (make-byte-vector 1280)))
                              (multiple-value-bind (received size peer-addr peer-port)
                                  (sb-bsd-sockets:socket-receive server-socket buffer nil)
                                (declare (ignore received))
                                (multiple-value-bind (type data sender)
                                    (ethereum-lisp.p2p:decode-discv4-packet
                                     (subseq buffer 0 size))
                                  (declare (ignore sender))
                                  (flet ((reply (packet)
                                           (sb-bsd-sockets:socket-send
                                            server-socket packet (length packet)
                                            :address (list peer-addr peer-port))))
                                    (cond
                                      ((= type ethereum-lisp.p2p:+discv4-packet-ping+)
                                       (setf client-from
                                             (ethereum-lisp.p2p:discv4-ping-from
                                              (ethereum-lisp.p2p:decode-discv4-ping
                                               data)))
                                       (reply
                                        (ethereum-lisp.p2p:encode-discv4-packet
                                         server-priv ethereum-lisp.p2p:+discv4-packet-pong+
                                         (ethereum-lisp.p2p:encode-discv4-pong
                                          (ethereum-lisp.p2p:make-discv4-pong
                                           :to (ethereum-lisp.p2p:discv4-ping-from
                                                (ethereum-lisp.p2p:decode-discv4-ping data))
                                           :ping-hash (subseq buffer 0 32)
                                           :expiration (ethereum-lisp.p2p:discv4-expiration))))))
                                      ((= type ethereum-lisp.p2p:+discv4-packet-find-node+)
                                       (reply
                                        (ethereum-lisp.p2p:encode-discv4-packet
                                         server-priv ethereum-lisp.p2p:+discv4-packet-neighbors+
                                         (ethereum-lisp.p2p:encode-discv4-neighbors
                                          (ethereum-lisp.p2p:make-discv4-neighbors
                                           :nodes (list (ethereum-lisp.p2p:make-discv4-node
                                                         (hex-to-bytes "0x0a000005")
                                                         30303 30303 advertised-id))
                                           :expiration (ethereum-lisp.p2p:discv4-expiration)))))
                                       (return-from serve))))))))
                        (error (condition) (setf server-error condition))))
                    :name "discv4-test-bootnode")))
             (let* ((enode (enode-url server-id "127.0.0.1" server-port)))
               (multiple-value-bind (enodes bonded)
                   (ethereum-lisp.p2p:discv4-find-peers enode client-priv
                                                        :timeout-seconds 5
                                                        :local-tcp-port 30399
                                                        :advertised-host
                                                        "127.0.0.1")
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "discv4 bootnode side failed: ~A" server-error))
                 ;; The Ping/Pong endpoint proof completed.
                 (is bonded)
                 ;; The claimed TCP endpoint is the node's real listener, not
                 ;; the crawl's ephemeral UDP source port.
                 (is (not (null client-from)))
                 (when client-from
                   (is (= 30399
                          (ethereum-lisp.p2p:discv4-endpoint-tcp-port
                           client-from))))
                 ;; The advertised neighbor came back as a dialable enode.
                 (is (= 1 (length enodes)))
                 (multiple-value-bind (id host tcp disc) (parse-enode-url (first enodes))
                   (declare (ignore disc))
                   (is (bytes= advertised-id id))
                   (is (string= "10.0.0.5" host))
                   (is (= 30303 tcp))))))
        (ignore-errors (sb-bsd-sockets:socket-close server-socket))))))

(deftest discv4-find-peers-times-out-on-a-silent-bootnode
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; A bootnode that never answers must not hang the driver: with-deadline
  ;; cannot interrupt a blocking recv, so discv4-receive waits on the fd instead.
  (multiple-value-bind (silent-socket silent-port)
      (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
    (unwind-protect
         (let* ((boot-id (node-id-from-private-key
                          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291))
                (enode (enode-url boot-id "127.0.0.1" silent-port))
                (start (get-universal-time)))
           (multiple-value-bind (enodes bonded)
               (ethereum-lisp.p2p:discv4-find-peers
                enode
                #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee
                :timeout-seconds 2)
             (is (null bonded))
             (is (null enodes))
             ;; Returned in a bounded time rather than blocking forever.
             (is (<= (- (get-universal-time) start) 20))))
      (ignore-errors (sb-bsd-sockets:socket-close silent-socket)))))

(deftest discv4-expired-p-drops-past-timestamps
  (:layer :unit :module :p2p)
  ;; A stamp far in the past is expired; a fresh future stamp is not.
  (is (ethereum-lisp.p2p:discv4-expired-p 1000000000))
  (is (not (ethereum-lisp.p2p:discv4-expired-p (ethereum-lisp.p2p:discv4-expiration))))
  ;; grace-seconds tolerates a slightly-past stamp.
  (let ((just-past (- (ethereum-lisp.p2p:discv4-unix-time) 1)))
    (is (not (ethereum-lisp.p2p:discv4-expired-p just-past :grace-seconds 5)))
    (is (ethereum-lisp.p2p:discv4-expired-p just-past :grace-seconds 0))))

(deftest discv4-node-distance-is-symmetric-and-zero-to-self
  (:layer :unit :module :p2p)
  (let ((a (node-id-from-private-key (secp256k1-random-private-key)))
        (b (node-id-from-private-key (secp256k1-random-private-key))))
    (is (= 0 (ethereum-lisp.p2p:discv4-node-distance a a)))
    (is (= (ethereum-lisp.p2p:discv4-node-distance a b)
           (ethereum-lisp.p2p:discv4-node-distance b a)))
    (is (plusp (ethereum-lisp.p2p:discv4-node-distance a b)))))

(deftest discv4-lookup-crawls-a-bootnode-and-discovers-a-peer
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((boot-priv
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (boot-id (node-id-from-private-key boot-priv))
         (client-priv
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (discovered-id (node-id-from-private-key
                         #x0102030405060708090a0b0c0d0e0f101112131415161718))
         (observed-advertised-udp nil)
         (server-error nil))
    (multiple-value-bind (boot-socket boot-port)
        (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
      (unwind-protect
           (let ((server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (loop named serve repeat 4 do
                            (let ((buffer (make-byte-vector 1280)))
                              (multiple-value-bind (received size peer-addr peer-port)
                                  (sb-bsd-sockets:socket-receive boot-socket buffer nil)
                                (declare (ignore received))
                                (multiple-value-bind (type data sender)
                                    (ethereum-lisp.p2p:decode-discv4-packet
                                     (subseq buffer 0 size))
                                  (declare (ignore sender))
                                  (flet ((reply (packet)
                                           (sb-bsd-sockets:socket-send
                                            boot-socket packet (length packet)
                                            :address (list peer-addr peer-port))))
                                    (cond
                                      ((= type ethereum-lisp.p2p:+discv4-packet-ping+)
                                       (let* ((ping
                                                (ethereum-lisp.p2p:decode-discv4-ping
                                                 data))
                                              (from
                                                (ethereum-lisp.p2p:discv4-ping-from
                                                 ping)))
                                         (setf observed-advertised-udp
                                               (ethereum-lisp.p2p:discv4-endpoint-udp-port
                                                from))
                                         (reply
                                          (ethereum-lisp.p2p:encode-discv4-packet
                                           boot-priv
                                           ethereum-lisp.p2p:+discv4-packet-pong+
                                           (ethereum-lisp.p2p:encode-discv4-pong
                                            (ethereum-lisp.p2p:make-discv4-pong
                                             :to from
                                             :ping-hash (subseq buffer 0 32)
                                             :expiration
                                             (ethereum-lisp.p2p:discv4-expiration)))))))
                                      ((= type ethereum-lisp.p2p:+discv4-packet-find-node+)
                                       (reply
                                        (ethereum-lisp.p2p:encode-discv4-packet
                                         boot-priv ethereum-lisp.p2p:+discv4-packet-neighbors+
                                         (ethereum-lisp.p2p:encode-discv4-neighbors
                                          (ethereum-lisp.p2p:make-discv4-neighbors
                                           :nodes (list (ethereum-lisp.p2p:make-discv4-node
                                                         (hex-to-bytes "0x0a000007")
                                                         30303 30303 discovered-id))
                                           :expiration (ethereum-lisp.p2p:discv4-expiration)))))
                                       (return-from serve))))))))
                        (error (condition) (setf server-error condition))))
                    :name "discv4-lookup-test-bootnode")))
             (let* ((enode (enode-url boot-id "127.0.0.1" boot-port))
                    (enodes (ethereum-lisp.p2p:discv4-lookup
                             (list enode) client-priv :timeout-seconds 3
                             :advertised-udp-port 40404))
                    (ids (mapcar (lambda (e) (nth-value 0 (parse-enode-url e))) enodes)))
               (sb-thread:join-thread server-thread)
               (when server-error
                 (error "discv4-lookup bootnode side failed: ~A" server-error))
               ;; The peer beyond the bootnode was discovered and returned.
               (is (find discovered-id ids :test #'bytes=))
               ;; The seed bootnode itself is excluded from the discovered set.
               (is (not (find boot-id ids :test #'bytes=)))
               ;; The short-lived crawl socket remains private, while the Ping
               ;; advertises the long-lived responder's public UDP endpoint.
               (is (= 40404 observed-advertised-udp))))
        (ignore-errors (sb-bsd-sockets:socket-close boot-socket))))))

(defun discv4-test-receive-datagram (socket timeout-seconds)
  "Receive one datagram within TIMEOUT-SECONDS, or NIL. (VALUES PACKET ADDRESS PORT).

A test server that blocks forever in SOCKET-RECEIVE takes JOIN-THREAD down with
it, turning any failure of the code under test into a hung suite rather than a
red one."
  (when (sb-sys:wait-until-fd-usable
         (sb-bsd-sockets:socket-file-descriptor socket) :input timeout-seconds)
    (let ((buffer (make-byte-vector 1280)))
      (multiple-value-bind (received size address port)
          (sb-bsd-sockets:socket-receive socket buffer nil)
        (declare (ignore received))
        (when (and size (plusp size))
          (values (subseq buffer 0 size) address port))))))

(deftest discv4-lookup-filters-discovered-nodes-by-their-record
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; Two nodes are discovered beyond the bootnode. Both bond, both answer
  ;; ENRRequest with a properly signed record, and they differ in exactly one
  ;; thing: the fork id inside it.
  ;;
  ;; This is the entire reason the crawl asks for records. discv4 is a single
  ;; DHT shared by every chain built on it, so a crawl returns whatever anyone
  ;; happens to be running -- and the wrong-chain node has to be dropped before
  ;; we spend a TCP connection and an ECIES handshake learning from the peer
  ;; itself what its record would have told us for one datagram.
  (let* ((boot-priv
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (boot-id (node-id-from-private-key boot-priv))
         (client-priv
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (ours-priv #x0102030405060708090a0b0c0d0e0f101112131415161718)
         (theirs-priv #x1112131415161718191a1b1c1d1e1f202122232425262728)
         (ours-id (node-id-from-private-key ours-priv))
         (theirs-id (node-id-from-private-key theirs-priv))
         (ours-hash (hex-to-bytes "0xaabbccdd"))
         (theirs-hash (hex-to-bytes "0x11223344"))
         ;; Written from several threads, read only after they are joined.
         (server-error nil))
    (multiple-value-bind (boot-socket boot-port)
        (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
      (multiple-value-bind (ours-socket ours-port)
          (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
        (multiple-value-bind (theirs-socket theirs-port)
            (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)
          (unwind-protect
               (labels
                   ((pong-for (priv packet data address port socket)
                      (let ((reply
                              (ethereum-lisp.p2p:encode-discv4-packet
                               priv ethereum-lisp.p2p:+discv4-packet-pong+
                               (ethereum-lisp.p2p:encode-discv4-pong
                                (ethereum-lisp.p2p:make-discv4-pong
                                 :to (ethereum-lisp.p2p:discv4-ping-from
                                      (ethereum-lisp.p2p:decode-discv4-ping data))
                                 :ping-hash (subseq packet 0 32)
                                 :expiration (ethereum-lisp.p2p:discv4-expiration))))))
                        (sb-bsd-sockets:socket-send
                         socket reply (length reply) :address (list address port))))
                    (serve-peer (socket priv fork-hash)
                      ;; Answer pings, then one ENRRequest, then stop. Ending on
                      ;; the record request rather than a packet count keeps the
                      ;; thread's lifetime tied to the exchange being tested.
                      (lambda ()
                        (handler-case
                            (loop named serve do
                              (multiple-value-bind (packet address port)
                                  (discv4-test-receive-datagram socket 5)
                                (unless packet (return-from serve))
                                (multiple-value-bind (type data sender)
                                    (ethereum-lisp.p2p:decode-discv4-packet packet)
                                  (declare (ignore sender))
                                  (cond
                                    ((= type ethereum-lisp.p2p:+discv4-packet-ping+)
                                     (pong-for priv packet data address port socket))
                                    ((= type ethereum-lisp.p2p:+discv4-packet-enr-request+)
                                     (let ((reply
                                             (ethereum-lisp.p2p:encode-discv4-packet
                                              priv
                                              ethereum-lisp.p2p:+discv4-packet-enr-response+
                                              (ethereum-lisp.p2p:encode-discv4-enr-response
                                               (ethereum-lisp.p2p:make-discv4-enr-response
                                                :request-hash (subseq packet 0 32)
                                                :record
                                                (ethereum-lisp.p2p:encode-enr
                                                 priv 1
                                                 (list (cons "eth"
                                                             (ethereum-lisp.eth-wire:eth-fork-id-enr-entry
                                                              (ethereum-lisp.eth-wire:make-eth-fork-id
                                                               fork-hash 0))))))))))
                                       (sb-bsd-sockets:socket-send
                                        socket reply (length reply)
                                        :address (list address port)))
                                     (return-from serve))))))
                          (error (condition) (setf server-error condition)))))
                    (serve-bootnode ()
                      (lambda ()
                        (handler-case
                            (loop named serve do
                              (multiple-value-bind (packet address port)
                                  (discv4-test-receive-datagram boot-socket 5)
                                (unless packet (return-from serve))
                                (multiple-value-bind (type data sender)
                                    (ethereum-lisp.p2p:decode-discv4-packet packet)
                                  (declare (ignore sender))
                                  (cond
                                    ((= type ethereum-lisp.p2p:+discv4-packet-ping+)
                                     (pong-for boot-priv packet data address port
                                               boot-socket))
                                    ((= type ethereum-lisp.p2p:+discv4-packet-find-node+)
                                     (let ((reply
                                             (ethereum-lisp.p2p:encode-discv4-packet
                                              boot-priv
                                              ethereum-lisp.p2p:+discv4-packet-neighbors+
                                              (ethereum-lisp.p2p:encode-discv4-neighbors
                                               (ethereum-lisp.p2p:make-discv4-neighbors
                                                :nodes
                                                (list (ethereum-lisp.p2p:make-discv4-node
                                                       (hex-to-bytes "0x7f000001")
                                                       ours-port ours-port ours-id)
                                                      (ethereum-lisp.p2p:make-discv4-node
                                                       (hex-to-bytes "0x7f000001")
                                                       theirs-port theirs-port
                                                       theirs-id))
                                                :expiration
                                                (ethereum-lisp.p2p:discv4-expiration))))))
                                       (sb-bsd-sockets:socket-send
                                        boot-socket reply (length reply)
                                        :address (list address port)))
                                     (return-from serve))))))
                          (error (condition) (setf server-error condition))))))
                 (let ((threads
                         (list (sb-thread:make-thread (serve-bootnode)
                                                      :name "discv4-filter-boot")
                               (sb-thread:make-thread
                                (serve-peer ours-socket ours-priv ours-hash)
                                :name "discv4-filter-ours")
                               (sb-thread:make-thread
                                (serve-peer theirs-socket theirs-priv theirs-hash)
                                :name "discv4-filter-theirs"))))
                   (multiple-value-bind (enodes stats)
                       (ethereum-lisp.p2p:discv4-lookup
                        (list (enode-url boot-id "127.0.0.1" boot-port))
                        client-priv
                        :timeout-seconds 6
                        :record-filter
                        (lambda (record)
                          (let ((fork-id
                                  (ethereum-lisp.eth-wire:eth-fork-id-from-enr-entry
                                   (ethereum-lisp.p2p:enr-value record "eth"))))
                            (and fork-id
                                 (bytes= ours-hash
                                         (ethereum-lisp.eth-wire:eth-fork-id-hash
                                          fork-id))))))
                     (mapc #'sb-thread:join-thread threads)
                     (when server-error
                       (error "discv4 filter test server side failed: ~A"
                              server-error))
                     (let ((ids (mapcar (lambda (e)
                                          (nth-value 0 (parse-enode-url e)))
                                        enodes)))
                       ;; The node on our chain is returned.
                       (is (find ours-id ids :test #'bytes=))
                       ;; The node on another chain is not.
                       (is (not (find theirs-id ids :test #'bytes=))))
                     ;; And it was JUDGED rather than merely missed: both records
                     ;; arrived, one matched and one did not. Without this the
                     ;; test would still pass if the crawl had simply failed to
                     ;; reach the second node at all.
                     (is (= 2 (cdr (assoc "records" stats :test #'string=))))
                     (is (= 1 (cdr (assoc "matched" stats :test #'string=))))
                     (is (= 1 (cdr (assoc "mismatched" stats :test #'string=)))))))
            (ignore-errors (sb-bsd-sockets:socket-close boot-socket))
            (ignore-errors (sb-bsd-sockets:socket-close ours-socket))
            (ignore-errors (sb-bsd-sockets:socket-close theirs-socket))))))))
