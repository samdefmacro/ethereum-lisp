(in-package #:ethereum-lisp.test)

;;;; RLPx recipient-side handshake against the go-ethereum EIP-8 test vectors
;;;; (p2p/rlpx/rlpx_test.go): a real reference auth ciphertext, and the pinned
;;;; aes-secret / mac-secret derived from it.

(defun p2p-strip-hex (text)
  "Join a multi-line hex vector into a single 0x string."
  (concatenate 'string "0x"
               (remove-if (lambda (c)
                            (member c '(#\Space #\Newline #\Tab #\Return)))
                          text)))

(deftest rlpx-auth-rejects-control-stack-depth-as-an-ordinary-error
  (:layer :unit :module :p2p)
  (let* ((recipient-private-key
           #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (recipient-public-key
           (secp256k1-private-key-public-key recipient-private-key))
         ;; This is the audit's process-killing shape. Build it iteratively so
         ;; the test itself does not consume one Lisp frame per nesting level.
         (plaintext (rlp-test-deep-list-bytes 20000))
         (packet (ethereum-lisp.p2p::rlpx-seal-message
                  recipient-public-key plaintext)))
    (is (< (length packet) #x10002))
    (signals rlp-error
      (rlpx-open-auth recipient-private-key packet))))

(deftest rlpx-outbound-eip8-messages-carry-required-padding
  (:layer :unit :module :p2p)
  (let* ((recipient-private-key
           #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (recipient-public-key
           (secp256k1-private-key-public-key recipient-private-key))
         (body (rlp-encode
                (make-rlp-list
                 (make-byte-vector 1 :initial-element #x01)
                 (make-byte-vector 1 :initial-element #x02)
                 (make-byte-vector 1 :initial-element #x04))))
         (padding (make-array 100 :element-type '(unsigned-byte 8)
                                  :initial-element #xa5))
         (packet (ethereum-lisp.p2p::rlpx-seal-message
                  recipient-public-key body :padding padding))
         (declared-size (+ (ash (aref packet 0) 8) (aref packet 1)))
         (plaintext
           (ethereum-lisp.p2p::ecies-decrypt
            recipient-private-key (subseq packet 2)
            :shared-data (subseq packet 0 2))))
    ;; Pinned geth's sealEIP8 appends at least 100 bytes before ECIES, and the
    ;; two-byte prefix covers ciphertext only (not the prefix itself).
    (is (= declared-size (- (length packet) 2)))
    (is (= (+ (length body) 100) (length plaintext)))
    (is (bytes= body (subseq plaintext 0 (length body))))
    (is (bytes= padding (subseq plaintext (length body))))
    (dotimes (i 16)
      (declare (ignore i))
      (let ((random-padding
              (ethereum-lisp.p2p::rlpx-random-eip8-padding)))
        (is (<= 100 (length random-padding) 199))))))

(deftest rlpx-recipient-handshake-matches-eip8-vectors
  (let* ((key-b #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (eph-b #xe238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4)
         (key-a #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (nonce-a (hex-to-bytes
                   "0x7e968bba13b6c50e2c4cd7f241cc0d64d1ac25c7f5952df231ac6a2bda8ee5d6"))
         (nonce-b (hex-to-bytes
                   "0x559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd"))
         (pub-a (secp256k1-private-key-public-key key-a))
         ;; (Auth2) EIP-8 auth ciphertext, produced by a reference implementation.
         (auth-packet
           (hex-to-bytes
            (p2p-strip-hex
             "01b304ab7578555167be8154d5cc456f567d5ba302662433674222360f08d5f1534499d3678b513b
              0fca474f3a514b18e75683032eb63fccb16c156dc6eb2c0b1593f0d84ac74f6e475f1b8d56116b84
              9634a8c458705bf83a626ea0384d4d7341aae591fae42ce6bd5c850bfe0b999a694a49bbbaf3ef6c
              da61110601d3b4c02ab6c30437257a6e0117792631a4b47c1d52fc0f8f89caadeb7d02770bf999cc
              147d2df3b62e1ffb2c9d8c125a3984865356266bca11ce7d3a688663a51d82defaa8aad69da39ab6
              d5470e81ec5f2a7a47fb865ff7cca21516f9299a07b1bc63ba56c7a1a892112841ca44b6e0034dee
              70c9adabc15d76a54f443593fafdc3b27af8059703f88928e199cb122362a4b35f62386da7caad09
              c001edaeb5f8a06d2b26fb6cb93c52a9fca51853b68193916982358fe1e5369e249875bb8d0d0ec3
              6f917bc5e1eafd5896d46bd61ff23f1a863a8a8dcd54c7b109b771c8e61ec9c8908c733c0263440e
              2aa067241aaa433f0bb053c7b31a838504b148f570c0ad62837129e547678c5190341e4f1693956c
              3bf7678318e2d5b5340c9e488eefea198576344afbdf66db5f51204a6961a63ce072c8926c")))
         ;; Open the auth message: decrypt (ECIES) and decode the RLP body.
         (auth (rlpx-open-auth key-b auth-packet)))
    (is (= 4 (ethereum-lisp.p2p:rlpx-auth-message-version auth)))
    (is (bytes= nonce-a (ethereum-lisp.p2p:rlpx-auth-message-initiator-nonce auth)))
    (is (bytes= pub-a (ethereum-lisp.p2p:rlpx-auth-message-initiator-public-key auth)))
    ;; Recover the initiator's ephemeral public key from the signature, then
    ;; derive the session secrets and match go-ethereum's pinned values.
    (let* ((eph-pub-a (rlpx-recover-initiator-ephemeral-key key-b auth))
           (ephemeral-key (secp256k1-ecdh eph-b eph-pub-a)))
      (multiple-value-bind (aes-secret mac-secret)
          (rlpx-derive-secrets ephemeral-key nonce-a nonce-b)
        (is (string= "0x80e8632c05fed6fc2a13b0f8d31a3cf645366239170ea067065aba8e28bac487"
                     (bytes-to-hex aes-secret)))
        (is (string= "0x2ea74ec5dae199227dff1af715362700e989d889d7a493cb0639691efb8e5f98"
                     (bytes-to-hex mac-secret)))))))

(deftest rlpx-full-handshake-round-trips-and-agrees-on-secrets
  ;; Initiator builds auth; recipient opens it, recovers the initiator ephemeral
  ;; key, and both sides independently derive the same session secrets.
  (let* ((init-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (recip-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (init-eph
          #x869d6ecf5211f1cc60418a13b9d870b22959d0c16f02bec714c960dd2298a32d)
         (recip-eph
          #xe238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4)
         (init-nonce (secure-random-bytes 32))
         (recip-nonce (secure-random-bytes 32))
         (recip-static-pub (secp256k1-private-key-public-key recip-static))
         (init-static-pub (secp256k1-private-key-public-key init-static))
         (auth-packet (rlpx-create-auth init-static init-eph
                                        recip-static-pub init-nonce))
         (auth (rlpx-open-auth recip-static auth-packet)))
    (is (= 4 (ethereum-lisp.p2p:rlpx-auth-message-version auth)))
    (is (bytes= init-nonce (ethereum-lisp.p2p:rlpx-auth-message-initiator-nonce auth)))
    (is (bytes= init-static-pub
                (ethereum-lisp.p2p:rlpx-auth-message-initiator-public-key auth)))
    (let ((recovered-eph
            (rlpx-recover-initiator-ephemeral-key recip-static auth)))
      ;; The recovered ephemeral key is the initiator's ephemeral public key.
      (is (bytes= (secp256k1-private-key-public-key init-eph) recovered-eph))
      ;; Recipient derives from its own ephemeral key and the recovered one;
      ;; initiator derives from its ephemeral key and the recipient's. Same key.
      (let ((recip-ephemeral (secp256k1-ecdh recip-eph recovered-eph))
            (init-ephemeral
              (secp256k1-ecdh init-eph
                              (secp256k1-private-key-public-key recip-eph))))
        (is (bytes= recip-ephemeral init-ephemeral))
        (multiple-value-bind (aes-r mac-r)
            (rlpx-derive-secrets recip-ephemeral init-nonce recip-nonce)
          (multiple-value-bind (aes-i mac-i)
              (rlpx-derive-secrets init-ephemeral init-nonce recip-nonce)
            (is (bytes= aes-r aes-i))
            (is (bytes= mac-r mac-i))))))))

(deftest rlpx-open-ack-matches-eip8-vector-and-round-trips
  (let* ((key-a #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (eph-b #xe238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4)
         (nonce-b (hex-to-bytes
                   "0x559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd"))
         ;; (Ack2) EIP-8 ack ciphertext from go-ethereum, opened by the initiator.
         (ack-packet
           (hex-to-bytes
            (p2p-strip-hex
             "01ea0451958701280a56482929d3b0757da8f7fbe5286784beead59d95089c217c9b917788989470
              b0e330cc6e4fb383c0340ed85fab836ec9fb8a49672712aeabbdfd1e837c1ff4cace34311cd7f4de
              05d59279e3524ab26ef753a0095637ac88f2b499b9914b5f64e143eae548a1066e14cd2f4bd7f814
              c4652f11b254f8a2d0191e2f5546fae6055694aed14d906df79ad3b407d94692694e259191cde171
              ad542fc588fa2b7333313d82a9f887332f1dfc36cea03f831cb9a23fea05b33deb999e85489e645f
              6aab1872475d488d7bd6c7c120caf28dbfc5d6833888155ed69d34dbdc39c1f299be1057810f34fb
              e754d021bfca14dc989753d61c413d261934e1a9c67ee060a25eefb54e81a4d14baff922180c395d
              3f998d70f46f6b58306f969627ae364497e73fc27f6d17ae45a413d322cb8814276be6ddd13b885b
              201b943213656cde498fa0e9ddc8e0b8f8a53824fbd82254f3e2c17e8eaea009c38b4aa0a3f306e8
              797db43c25d68e86f262e564086f59a2fc60511c42abfb3057c247a8a8fe4fb3ccbadde17514b7ac
              8000cdb6a912778426260c47f38919a91f25f4b5ffb455d6aaaf150f7e5529c100ce62d6d92826a7
              1778d809bdf60232ae21ce8a437eca8223f45ac37f6487452ce626f549b3b5fdee26afd2072e4bc7
              5833c2464c805246155289f4")))
         (ack (rlpx-open-ack key-a ack-packet)))
    (is (= 4 (ethereum-lisp.p2p:rlpx-ack-message-version ack)))
    (is (bytes= nonce-b (ethereum-lisp.p2p:rlpx-ack-message-recipient-nonce ack)))
    (is (bytes= (secp256k1-private-key-public-key eph-b)
                (ethereum-lisp.p2p:rlpx-ack-message-recipient-ephemeral-public-key ack)))
    ;; Our own ack round-trips too.
    (let* ((init-static #x1111111111111111111111111111111111111111111111111111111111111111)
           (init-pub (secp256k1-private-key-public-key init-static))
           (our-nonce (secure-random-bytes 32))
           (packet (rlpx-create-ack eph-b init-pub our-nonce))
           (opened (rlpx-open-ack init-static packet)))
      (is (bytes= our-nonce
                  (ethereum-lisp.p2p:rlpx-ack-message-recipient-nonce opened)))
      (is (bytes= (secp256k1-private-key-public-key eph-b)
                  (ethereum-lisp.p2p:rlpx-ack-message-recipient-ephemeral-public-key opened))))))

;;;; Reading an inbound auth, pinned to go-ethereum v1.17.4.
;;;;
;;;; go-ethereum v1.17.4 p2p/rlpx/rlpx.go (byte-identical to the pinned
;;;; references/go-ethereum 38271784) reads every handshake message in
;;;; handshakeState.readMsg: a two-byte big-endian size, "message too big" above
;;;; 2048, exactly that many bytes, then ecies Decrypt with the two prefix bytes
;;;; as the authenticated data. There is no pre-EIP-8 path any more: a legacy
;;;; 307-byte auth begins with its 0x04 key tag, so it reads as a size of
;;;; 1024-1279 and the reader waits for bytes the peer never sends. The vectors
;;;; are EIP-8's (Auth1, Auth3, Ack3); geth's rlpx_test.go keeps Auth2/3, Ack2/3.

(defparameter *rlpx-eip8-auth1-legacy-hex*
  "048ca79ad18e4b0659fab4853fe5bc58eb83992980f4c9cc147d2aa31532efd29a3d3dc6a3d89eaf
   913150cfc777ce0ce4af2758bf4810235f6e6ceccfee1acc6b22c005e9e3a49d6448610a58e98744
   ba3ac0399e82692d67c1f58849050b3024e21a52c9d3b01d871ff5f210817912773e610443a9ef14
   2e91cdba0bd77b5fdf0769b05671fc35f83d83e4d3b0b000c6b2a1b1bba89e0fc51bf4e460df3105
   c444f14be226458940d6061c296350937ffd5e3acaceeaaefd3c6f74be8e23e0f45163cc7ebd7622
   0f0128410fd05250273156d548a414444ae2f7dea4dfca2d43c057adb701a715bf59f6fb66b2d1d2
   0f2c703f851cbf5ac47396d9ca65b6260bd141ac4d53e2de585a73d1750780db4c9ee4cd4d225173
   a4592ee77e2bd94d0be3691f3b406f9bba9b591fc63facc016bfa8"
  "EIP-8 (Auth1): the legacy pre-EIP-8 auth from A to B, 307 bytes, no prefix.")

(defparameter *rlpx-eip8-auth2-hex*
  "01b304ab7578555167be8154d5cc456f567d5ba302662433674222360f08d5f1534499d3678b513b
   0fca474f3a514b18e75683032eb63fccb16c156dc6eb2c0b1593f0d84ac74f6e475f1b8d56116b84
   9634a8c458705bf83a626ea0384d4d7341aae591fae42ce6bd5c850bfe0b999a694a49bbbaf3ef6c
   da61110601d3b4c02ab6c30437257a6e0117792631a4b47c1d52fc0f8f89caadeb7d02770bf999cc
   147d2df3b62e1ffb2c9d8c125a3984865356266bca11ce7d3a688663a51d82defaa8aad69da39ab6
   d5470e81ec5f2a7a47fb865ff7cca21516f9299a07b1bc63ba56c7a1a892112841ca44b6e0034dee
   70c9adabc15d76a54f443593fafdc3b27af8059703f88928e199cb122362a4b35f62386da7caad09
   c001edaeb5f8a06d2b26fb6cb93c52a9fca51853b68193916982358fe1e5369e249875bb8d0d0ec3
   6f917bc5e1eafd5896d46bd61ff23f1a863a8a8dcd54c7b109b771c8e61ec9c8908c733c0263440e
   2aa067241aaa433f0bb053c7b31a838504b148f570c0ad62837129e547678c5190341e4f1693956c
   3bf7678318e2d5b5340c9e488eefea198576344afbdf66db5f51204a6961a63ce072c8926c"
  "EIP-8 (Auth2): EIP-8 auth from A to B, version 4, no extra list elements.")

(defparameter *rlpx-eip8-auth3-hex*
  "01b8044c6c312173685d1edd268aa95e1d495474c6959bcdd10067ba4c9013df9e40ff45f5bfd6f7
   2471f93a91b493f8e00abc4b80f682973de715d77ba3a005a242eb859f9a211d93a347fa64b597bf
   280a6b88e26299cf263b01b8dfdb712278464fd1c25840b995e84d367d743f66c0e54a586725b7bb
   f12acca27170ae3283c1073adda4b6d79f27656993aefccf16e0d0409fe07db2dc398a1b7e8ee93b
   cd181485fd332f381d6a050fba4c7641a5112ac1b0b61168d20f01b479e19adf7fdbfa0905f63352
   bfc7e23cf3357657455119d879c78d3cf8c8c06375f3f7d4861aa02a122467e069acaf513025ff19
   6641f6d2810ce493f51bee9c966b15c5043505350392b57645385a18c78f14669cc4d960446c1757
   1b7c5d725021babbcd786957f3d17089c084907bda22c2b2675b4378b114c601d858802a55345a15
   116bc61da4193996187ed70d16730e9ae6b3bb8787ebcaea1871d850997ddc08b4f4ea668fbf3740
   7ac044b55be0908ecb94d4ed172ece66fd31bfdadf2b97a8bc690163ee11f5b575a4b44e36e2bfb2
   f0fce91676fd64c7773bac6a003f481fddd0bae0a1f31aa27504e2a533af4cef3b623f4791b2cca6
   d490"
  "EIP-8 (Auth3): EIP-8 auth from A to B, version 56, three extra list elements.")

(defparameter *rlpx-eip8-ack3-hex*
  "01f004076e58aae772bb101ab1a8e64e01ee96e64857ce82b1113817c6cdd52c09d26f7b90981cd7
   ae835aeac72e1573b8a0225dd56d157a010846d888dac7464baf53f2ad4e3d584531fa203658fab0
   3a06c9fd5e35737e417bc28c1cbf5e5dfc666de7090f69c3b29754725f84f75382891c561040ea1d
   dc0d8f381ed1b9d0d4ad2a0ec021421d847820d6fa0ba66eaf58175f1b235e851c7e2124069fbc20
   2888ddb3ac4d56bcbd1b9b7eab59e78f2e2d400905050f4a92dec1c4bdf797b3fc9b2f8e84a482f3
   d800386186712dae00d5c386ec9387a5e9c9a1aca5a573ca91082c7d68421f388e79127a5177d4f8
   590237364fd348c9611fa39f78dcdceee3f390f07991b7b47e1daa3ebcb6ccc9607811cb17ce51f1
   c8c2c5098dbdd28fca547b3f58c01a424ac05f869f49c6a34672ea2cbbc558428aa1fe48bbfd6115
   8b1b735a65d99f21e70dbc020bfdface9f724a0d1fb5895db971cc81aa7608baa0920abb0a565c9c
   436e2fd13323428296c86385f2384e408a31e104670df0791d93e743a3a5194ee6b076fb6323ca59
   3011b7348c16cf58f66b9633906ba54a2ee803187344b394f75dd2e663a57b956cb830dd7a908d4f
   39a2336a61ef9fda549180d4ccde21514d117b6c6fd07a9102b5efe710a32af4eeacae2cb3b1dec0
   35b9593b48b9d3ca4c13d245d5f04169b0b1"
  "EIP-8 (Ack3): EIP-8 ack from B to A, version 57, three extra list elements.")

(defparameter *rlpx-vector-key-a*
  #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
(defparameter *rlpx-vector-key-b*
  #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
(defparameter *rlpx-vector-ephemeral-a*
  #x869d6ecf5211f1cc60418a13b9d870b22959d0c16f02bec714c960dd2298a32d)
(defparameter *rlpx-vector-ephemeral-b*
  #xe238eb8e04fee6511ab04c6dd3c89ce097b11f25d584863ac2b6d5b35b1847e4)

(defun rlpx-vector-bytes (hex)
  (hex-to-bytes (p2p-strip-hex hex)))

(defclass p2p-octet-input-stream (sb-gray:fundamental-binary-input-stream)
  ((octets :initarg :octets :reader p2p-octet-input-stream-octets)
   (index :initform 0 :accessor p2p-octet-input-stream-index))
  (:documentation "An in-memory octet stream that ends where its bytes do."))

(defmethod sb-gray:stream-read-byte ((stream p2p-octet-input-stream))
  (let ((octets (p2p-octet-input-stream-octets stream))
        (index (p2p-octet-input-stream-index stream)))
    (if (< index (length octets))
        (prog1 (aref octets index)
          (setf (p2p-octet-input-stream-index stream) (1+ index)))
        :eof)))

(defmethod sb-gray:stream-read-sequence
    ((stream p2p-octet-input-stream) sequence &optional (start 0) end)
  (let* ((octets (p2p-octet-input-stream-octets stream))
         (index (p2p-octet-input-stream-index stream))
         (end (or end (length sequence)))
         (count (min (- end start) (- (length octets) index))))
    (replace sequence octets :start1 start :end1 (+ start count) :start2 index)
    (setf (p2p-octet-input-stream-index stream) (+ index count))
    (+ start count)))

(defun rlpx-read-handshake-outcome (octets)
  "Read one handshake packet from OCTETS: (:PACKET bytes), (:ENDED filled
expected) or (:ERROR message)."
  (handler-case
      (list :packet
            (ethereum-lisp.p2p::rlpx-read-handshake-packet
             (make-instance 'p2p-octet-input-stream
                            :octets (ensure-byte-vector octets))))
    (ethereum-lisp.p2p:rlpx-stream-ended (condition)
      (list :ended
            (ethereum-lisp.p2p::rlpx-stream-ended-filled condition)
            (ethereum-lisp.p2p::rlpx-stream-ended-expected condition)))
    (error (condition)
      (list :error (princ-to-string condition)))))

(defun rlpx-failure-message (thunk)
  "NIL when THUNK returns, else the report of the error it signals."
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (princ-to-string condition))))

(deftest rlpx-handshake-reader-takes-geth-v1-17-4-eip8-vectors-whole
  (:layer :unit :module :p2p)
  ;; geth's TestHandshakeForwardCompatibility requires readMsg to return
  ;; exactly the input bytes; Auth3 and Ack3 add version 56/57 and trailing
  ;; list elements that must be ignored rather than rejected.
  (let ((pub-a (secp256k1-private-key-public-key *rlpx-vector-key-a*))
        (nonce-a (hex-to-bytes
                  "0x7e968bba13b6c50e2c4cd7f241cc0d64d1ac25c7f5952df231ac6a2bda8ee5d6"))
        (nonce-b (hex-to-bytes
                  "0x559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd"))
        (auth-signature
          (hex-to-bytes
           "0x299ca6acfd35e3d72d8ba3d1e2b60b5561d5af5218eb5bc182045769eb4226910a301acae3b369fffc4a4899d6b02531e89fd4fe36a2cf0d93607ba470b50f7800")))
    (dolist (case (list (list *rlpx-eip8-auth2-hex* 4)
                        (list *rlpx-eip8-auth3-hex* 56)))
      (destructuring-bind (hex version) case
        (let* ((input (rlpx-vector-bytes hex))
               (outcome (rlpx-read-handshake-outcome input)))
          (is (eq :packet (first outcome)))
          (is (bytes= input (second outcome)))
          (let ((auth (rlpx-open-auth *rlpx-vector-key-b* (second outcome))))
            (is (= version (ethereum-lisp.p2p:rlpx-auth-message-version auth)))
            (is (bytes= nonce-a
                        (ethereum-lisp.p2p:rlpx-auth-message-initiator-nonce auth)))
            (is (bytes= pub-a
                        (ethereum-lisp.p2p:rlpx-auth-message-initiator-public-key
                         auth)))
            (is (bytes= auth-signature
                        (ethereum-lisp.p2p::rlpx-auth-message-signature auth)))
            (is (bytes= (secp256k1-private-key-public-key
                         *rlpx-vector-ephemeral-a*)
                        (rlpx-recover-initiator-ephemeral-key
                         *rlpx-vector-key-b* auth)))))))
    (let* ((input (rlpx-vector-bytes *rlpx-eip8-ack3-hex*))
           (outcome (rlpx-read-handshake-outcome input))
           (ack (rlpx-open-ack *rlpx-vector-key-a* (second outcome))))
      (is (eq :packet (first outcome)))
      (is (bytes= input (second outcome)))
      (is (= 57 (ethereum-lisp.p2p::rlpx-ack-message-version ack)))
      (is (bytes= nonce-b (ethereum-lisp.p2p:rlpx-ack-message-recipient-nonce ack)))
      (is (bytes= (secp256k1-private-key-public-key *rlpx-vector-ephemeral-b*)
                  (ethereum-lisp.p2p:rlpx-ack-message-recipient-ephemeral-public-key
                   ack))))))

(deftest rlpx-auth-for-another-node-fails-the-ecies-tag
  (:layer :unit :module :p2p)
  ;; The live classification rule: an initiator that encrypted its auth to a
  ;; key other than ours produces exactly this error. Auth2 is addressed to B.
  (let* ((packet (rlpx-vector-bytes *rlpx-eip8-auth2-hex*))
         (prefix (subseq packet 0 2))
         (body (subseq packet 2))
         (tag-failure "ECIES tag does not authenticate the message"))
    ;; Positive control: B, the addressee, opens it.
    (is (null (rlpx-failure-message
               (lambda () (rlpx-open-auth *rlpx-vector-key-b* packet)))))
    (is (null (rlpx-failure-message
               (lambda () (ecies-decrypt *rlpx-vector-key-b* body
                                         :shared-data prefix)))))
    ;; A is not the addressee.
    (is (equal tag-failure
               (rlpx-failure-message
                (lambda () (rlpx-open-auth *rlpx-vector-key-a* packet)))))
    ;; The two prefix bytes themselves are the authenticated data: dropping
    ;; them, or changing one, fails the same tag even for the right key.
    (is (equal tag-failure
               (rlpx-failure-message
                (lambda () (ecies-decrypt *rlpx-vector-key-b* body)))))
    (is (equal tag-failure
               (rlpx-failure-message
                (lambda ()
                  (ecies-decrypt *rlpx-vector-key-b* body
                                 :shared-data
                                 (vector (aref prefix 0)
                                         (logxor #xff (aref prefix 1))))))))))

(deftest rlpx-legacy-pre-eip8-auth-is-refused-as-geth-v1-17-4-refuses-it
  (:layer :unit :module :p2p)
  ;; A 307-byte pre-EIP-8 auth reads as a size prefix of #x048c, so, exactly as
  ;; in geth's readMsg, the reader wants 1164 bytes and the peer has sent 305.
  ;; This is the live "RLPx stream ended after 305 of 1024..1279 bytes" line.
  (let ((legacy (rlpx-vector-bytes *rlpx-eip8-auth1-legacy-hex*)))
    (is (= 307 (length legacy)))
    (is (equal (list :ended 305 #x048c) (rlpx-read-handshake-outcome legacy)))
    ;; Given the bytes it asked for, the size-prefixed reading cannot misparse
    ;; a legacy packet either: what it takes for the ECIES key tag is the
    ;; legacy key's second byte, #x8c, and it stops there.
    (let* ((padded (concat-bytes legacy (make-byte-vector (- #x048c 305))))
           (outcome (rlpx-read-handshake-outcome padded)))
      (is (eq :packet (first outcome)))
      (is (equal "ECIES ephemeral key must be uncompressed"
                 (rlpx-failure-message
                  (lambda () (rlpx-open-auth *rlpx-vector-key-b* padded))))))))

(deftest rlpx-handshake-reader-refuses-a-size-over-geths-2048
  (:layer :unit :module :p2p)
  ;; geth v1.17.4 readMsg refuses a size above 2048 ("message too big") on the
  ;; prefix alone, before reading any body byte. Without that bound one
  ;; connection makes us wait for, and allocate, up to 64 KiB.
  (let ((over (concat-bytes (vector #x08 #x01) (make-byte-vector 2049)))
        (limit (concat-bytes (vector #x08 #x00) (make-byte-vector 2048))))
    (let ((outcome (rlpx-read-handshake-outcome over)))
      (is (eq :error (first outcome)))
      (is (search "2048" (princ-to-string (second outcome)))))
    ;; The size alone decides: no body byte has to arrive first.
    (let ((outcome (rlpx-read-handshake-outcome (vector #x08 #x01))))
      (is (eq :error (first outcome)))
      (is (search "2048" (princ-to-string (second outcome)))))
    ;; Boundary control: 2048 itself is geth's largest accepted size.
    (let ((outcome (rlpx-read-handshake-outcome limit)))
      (is (eq :packet (first outcome)))
      (is (= 2050 (length (second outcome)))))))

(deftest rlpx-handshake-reader-reports-a-truncated-auth-by-byte-count
  (:layer :unit :module :p2p)
  ;; A short read is never taken for a complete message: the reader names how
  ;; far it got, which is what separates the live failure classes.
  (let ((auth (rlpx-vector-bytes *rlpx-eip8-auth2-hex*)))
    (is (= #x01b3 (- (length auth) 2)))
    (is (equal (list :ended 434 435)
               (rlpx-read-handshake-outcome (subseq auth 0 (1- (length auth))))))
    (is (equal (list :ended 1 2) (rlpx-read-handshake-outcome (subseq auth 0 1))))
    (is (equal (list :ended 0 2) (rlpx-read-handshake-outcome (make-byte-vector 0))))))

(deftest rlpx-recipient-opens-every-fresh-auth-across-threads
  (:layer :unit :module :p2p)
  ;; The live node runs one handshake per session thread. If ECDH, the KDF, the
  ;; MAC or AES kept state between calls, or were unsafe across threads, some
  ;; correctly addressed auths would fail the ECIES tag. None may.
  (let* ((recipient *rlpx-vector-key-b*)
         (recipient-public (secp256k1-private-key-public-key recipient))
         (per-thread 40)
         (thread-count 8)
         (lock (sb-thread:make-mutex :name "rlpx-stress-results"))
         (opened 0)
         (failures '()))
    (flet ((one-handshake (addressee)
             (let* ((ephemeral (secp256k1-random-private-key))
                    (nonce (secure-random-bytes 32))
                    (packet (rlpx-create-auth (secp256k1-random-private-key)
                                              ephemeral addressee nonce))
                    (outcome (rlpx-read-handshake-outcome packet))
                    (auth (rlpx-open-auth recipient (second outcome))))
               (unless (and (eq :packet (first outcome))
                            (bytes= nonce
                                    (ethereum-lisp.p2p:rlpx-auth-message-initiator-nonce
                                     auth))
                            (bytes= (secp256k1-private-key-public-key ephemeral)
                                    (rlpx-recover-initiator-ephemeral-key
                                     recipient auth)))
                 (error "auth opened to the wrong contents")))))
      ;; Positive control: the harness does report a misaddressed auth.
      (is (equal "ECIES tag does not authenticate the message"
                 (rlpx-failure-message
                  (lambda ()
                    (one-handshake
                     (secp256k1-private-key-public-key *rlpx-vector-key-a*))))))
      (let ((threads
              (loop for index below thread-count
                    collect
                    (sb-thread:make-thread
                     (lambda ()
                       (loop repeat per-thread
                             do (handler-case
                                    (progn
                                      (one-handshake recipient-public)
                                      (sb-thread:with-mutex (lock) (incf opened)))
                                  (serious-condition (condition)
                                    (sb-thread:with-mutex (lock)
                                      (push (princ-to-string condition)
                                            failures))))))
                     :name (format nil "rlpx-stress-~D" index)))))
        (dolist (thread threads)
          (is (not (eq :timeout
                       (sb-thread:join-thread thread :timeout 120
                                                     :default :timeout)))))
        (is (null failures))
        (is (= (* per-thread thread-count) opened))))))
