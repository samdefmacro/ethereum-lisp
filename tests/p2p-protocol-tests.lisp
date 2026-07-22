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

(deftest rlpx-full-protocol-runs-offline-end-to-end
  ;; The complete devp2p protocol without a socket: handshake, secret agreement,
  ;; MAC-initialised sessions, then framed messages in BOTH directions. If the
  ;; initiator/recipient MAC tables were wrong, the frames would not authenticate.
  (let* ((init-static #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (recip-static #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (init-eph #x869d6ecf5211f1cc60418a13b9d870b22959d0c16f02bec714c960dd2298a32d)
         (recip-eph #xe238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4)
         (init-nonce (secure-random-bytes 32))
         (recip-nonce (secure-random-bytes 32))
         (recip-static-pub (secp256k1-private-key-public-key recip-static))
         (init-static-pub (secp256k1-private-key-public-key init-static))
         ;; --- handshake message exchange ---
         (auth (rlpx-create-auth init-static init-eph recip-static-pub init-nonce))
         (auth-msg (rlpx-open-auth recip-static auth))
         (recovered-init-eph (rlpx-recover-initiator-ephemeral-key recip-static auth-msg))
         (ack (rlpx-create-ack recip-eph init-static-pub recip-nonce))
         (ack-msg (rlpx-open-ack init-static ack)))
    ;; --- secret agreement ---
    (multiple-value-bind (r-aes r-mac)
        (rlpx-derive-secrets (secp256k1-ecdh recip-eph recovered-init-eph)
                             init-nonce recip-nonce)
      (multiple-value-bind (i-aes i-mac)
          (rlpx-derive-secrets
           (secp256k1-ecdh init-eph
                           (ethereum-lisp.p2p:rlpx-ack-message-recipient-ephemeral-public-key
                            ack-msg))
           init-nonce recip-nonce)
        (is (bytes= r-aes i-aes))
        (is (bytes= r-mac i-mac))
        ;; --- MAC-initialised sessions ---
        (let ((initiator (make-rlpx-initiator-session i-aes i-mac init-nonce
                                                      recip-nonce auth ack))
              (recipient (make-rlpx-recipient-session r-aes r-mac init-nonce
                                                      recip-nonce auth ack)))
          ;; Initiator -> recipient: uncompressed Hello.
          (let* ((hello (make-devp2p-hello :client-id "ethereum-lisp" :capabilities '()
                                           :node-id init-static-pub))
                 (frame (rlpx-write-message initiator +devp2p-message-hello+
                                            (encode-devp2p-hello hello) :compressed nil)))
            (multiple-value-bind (code payload)
                (rlpx-read-message recipient frame :compressed nil)
              (is (= +devp2p-message-hello+ code))
              (is (string= "ethereum-lisp"
                           (devp2p-hello-client-id (decode-devp2p-hello payload))))))
          ;; Recipient -> initiator: compressed Ping, then initiator's Pong back.
          (let ((ping (rlpx-write-message recipient +devp2p-message-ping+
                                          (encode-devp2p-ping))))
            (multiple-value-bind (code payload) (rlpx-read-message initiator ping)
              (is (= +devp2p-message-ping+ code))
              (is (bytes= (encode-devp2p-ping) payload))))
          (let ((pong (rlpx-write-message initiator +devp2p-message-pong+
                                          (encode-devp2p-pong))))
            (multiple-value-bind (code payload) (rlpx-read-message recipient pong)
              (is (= +devp2p-message-pong+ code)))))))))
