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
