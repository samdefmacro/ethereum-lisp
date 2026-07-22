(in-package #:ethereum-lisp.test)

;;;; devp2p "p2p" capability: message encode/decode and framed round-trips.

(defun p2p-test-session-pair ()
  "Two RLPx sessions whose writer egress MAC and reader ingress MAC share a
state, as the handshake initialises them."
  (let ((aes-secret (keccak-256 (ascii-to-bytes "aes")))
        (mac-secret (keccak-256 (ascii-to-bytes "mac")))
        (seed (ascii-to-bytes "devp2p mac seed"))
        (writer-egress (make-keccak-256))
        (reader-ingress (make-keccak-256)))
    (keccak-256-update writer-egress seed)
    (keccak-256-update reader-ingress seed)
    (values
     (make-rlpx-session aes-secret mac-secret
                        (rlpx-keccak-mac writer-egress)
                        (rlpx-keccak-mac (make-keccak-256)))
     (make-rlpx-session aes-secret mac-secret
                        (rlpx-keccak-mac (make-keccak-256))
                        (rlpx-keccak-mac reader-ingress)))))

(deftest devp2p-hello-round-trips
  (let* ((node-id (secp256k1-private-key-public-key
                   #x1111111111111111111111111111111111111111111111111111111111111111))
         (hello (make-devp2p-hello
                 :client-id "ethereum-lisp/v0.1"
                 :capabilities (list (make-devp2p-capability "eth" 68)
                                     (make-devp2p-capability "snap" 1))
                 :listen-port 30303
                 :node-id node-id))
         (decoded (decode-devp2p-hello (encode-devp2p-hello hello))))
    (is (= 5 (devp2p-hello-version decoded)))
    (is (string= "ethereum-lisp/v0.1" (devp2p-hello-client-id decoded)))
    (is (= 30303 (devp2p-hello-listen-port decoded)))
    (is (bytes= node-id (devp2p-hello-node-id decoded)))
    (is (= 2 (length (devp2p-hello-capabilities decoded))))
    (let ((eth (first (devp2p-hello-capabilities decoded))))
      (is (string= "eth" (ethereum-lisp.p2p:devp2p-capability-name eth)))
      (is (= 68 (ethereum-lisp.p2p:devp2p-capability-version eth))))))

(deftest devp2p-disconnect-round-trips
  (is (= 4 (decode-devp2p-disconnect (encode-devp2p-disconnect 4))))
  ;; An empty body decodes to "disconnect requested".
  (is (= 0 (decode-devp2p-disconnect (rlp-encode (make-rlp-list))))))

(deftest devp2p-messages-frame-and-unframe
  ;; Hello goes uncompressed; later messages are Snappy-compressed. Both survive
  ;; the frame codec.
  (multiple-value-bind (writer reader) (p2p-test-session-pair)
    (let* ((hello (make-devp2p-hello
                   :client-id "peer" :capabilities '()
                   :node-id (make-byte-vector 64 :initial-element 7)))
           (hello-frame (rlpx-write-message writer +devp2p-message-hello+
                                            (encode-devp2p-hello hello)
                                            :compressed nil)))
      (multiple-value-bind (code payload)
          (rlpx-read-message reader hello-frame :compressed nil)
        (is (= +devp2p-message-hello+ code))
        (is (string= "peer" (devp2p-hello-client-id (decode-devp2p-hello payload))))))
    ;; A compressed Ping then Pong, in order on the same session pair.
    (let ((ping-frame (rlpx-write-message writer +devp2p-message-ping+
                                          (encode-devp2p-ping))))
      (multiple-value-bind (code payload)
          (rlpx-read-message reader ping-frame)
        (is (= +devp2p-message-ping+ code))
        (is (bytes= (encode-devp2p-ping) payload))))
    (let ((pong-frame (rlpx-write-message writer +devp2p-message-pong+
                                          (encode-devp2p-pong))))
      (multiple-value-bind (code payload)
          (rlpx-read-message reader pong-frame)
        (is (= +devp2p-message-pong+ code))
        (is (bytes= (encode-devp2p-pong) payload))))))
