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
