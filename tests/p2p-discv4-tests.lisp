(in-package #:ethereum-lisp.test)

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
                                                        :timeout-seconds 5)
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "discv4 bootnode side failed: ~A" server-error))
                 ;; The Ping/Pong endpoint proof completed.
                 (is bonded)
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
                                       (reply
                                        (ethereum-lisp.p2p:encode-discv4-packet
                                         boot-priv ethereum-lisp.p2p:+discv4-packet-pong+
                                         (ethereum-lisp.p2p:encode-discv4-pong
                                          (ethereum-lisp.p2p:make-discv4-pong
                                           :to (ethereum-lisp.p2p:discv4-ping-from
                                                (ethereum-lisp.p2p:decode-discv4-ping data))
                                           :ping-hash (subseq buffer 0 32)
                                           :expiration (ethereum-lisp.p2p:discv4-expiration))))))
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
                             (list enode) client-priv :timeout-seconds 3))
                    (ids (mapcar (lambda (e) (nth-value 0 (parse-enode-url e))) enodes)))
               (sb-thread:join-thread server-thread)
               (when server-error
                 (error "discv4-lookup bootnode side failed: ~A" server-error))
               ;; The peer beyond the bootnode was discovered and returned.
               (is (find discovered-id ids :test #'bytes=))
               ;; The seed bootnode itself is excluded from the discovered set.
               (is (not (find boot-id ids :test #'bytes=)))))
        (ignore-errors (sb-bsd-sockets:socket-close boot-socket))))))
