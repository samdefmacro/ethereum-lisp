(in-package #:ethereum-lisp.test)

;;;; AES known-answer tests against NIST FIPS-197 and SP 800-38A vectors.

(deftest aes-encrypts-fips197-known-answer-blocks
  ;; FIPS-197 Appendix B (AES-128) and Appendix C examples.
  (labels ((enc (key-hex pt-hex)
             (bytes-to-hex
              (ethereum-lisp.crypto:aes-encrypt-ecb-block
               (hex-to-bytes key-hex) (hex-to-bytes pt-hex)))))
    ;; FIPS-197 Appendix B.
    (is (string= "0x3925841d02dc09fbdc118597196a0b32"
                 (enc "0x2b7e151628aed2a6abf7158809cf4f3c"
                      "0x3243f6a8885a308d313198a2e0370734")))
    ;; FIPS-197 Appendix C.1, AES-128.
    (is (string= "0x69c4e0d86a7b0430d8cdb78070b4c55a"
                 (enc "0x000102030405060708090a0b0c0d0e0f"
                      "0x00112233445566778899aabbccddeeff")))
    ;; FIPS-197 Appendix C.3, AES-256.
    (is (string= "0x8ea2b7ca516745bfeafc49904b496089"
                 (enc "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
                      "0x00112233445566778899aabbccddeeff")))))

(deftest aes-ctr-matches-sp800-38a-vectors
  ;; NIST SP 800-38A F.5.1 (CTR-AES128.Encrypt) and F.5.5 (CTR-AES256.Encrypt).
  (let ((plaintext
          (hex-to-bytes
           (concatenate 'string
                        "0x6bc1bee22e409f96e93d7e117393172a"
                        "ae2d8a571e03ac9c9eb76fac45af8e51"
                        "30c81c46a35ce411e5fbc1191a0a52ef"
                        "f69f2445df4f9b17ad2b417be66c3710")))
        (counter (hex-to-bytes "0xf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")))
    ;; AES-128-CTR.
    (is (string=
         (concatenate 'string
                      "0x874d6191b620e3261bef6864990db6ce"
                      "9806f66b7970fdff8617187bb9fffdff"
                      "5ae4df3edbd5d35e5b4f09020db03eab"
                      "1e031dda2fbe03d1792170a0f3009cee")
         (bytes-to-hex
          (ethereum-lisp.crypto:aes-ctr
           (hex-to-bytes "0x2b7e151628aed2a6abf7158809cf4f3c")
           counter plaintext))))
    ;; AES-256-CTR.
    (is (string=
         (concatenate 'string
                      "0x601ec313775789a5b7a7f504bbf3d228"
                      "f443e3ca4d62b59aca84e990cacaf5c5"
                      "2b0930daa23de94ce87017ba2d84988d"
                      "dfc9c58db67aada613c2dd08457941a6")
         (bytes-to-hex
          (ethereum-lisp.crypto:aes-ctr
           (hex-to-bytes
            "0x603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
           counter plaintext))))
    ;; CTR is its own inverse: decrypting the ciphertext restores the plaintext.
    (is (bytes= plaintext
                (ethereum-lisp.crypto:aes-ctr
                 (hex-to-bytes "0x2b7e151628aed2a6abf7158809cf4f3c")
                 counter
                 (ethereum-lisp.crypto:aes-ctr
                  (hex-to-bytes "0x2b7e151628aed2a6abf7158809cf4f3c")
                  counter plaintext))))
    ;; A partial final block still XORs only the bytes present.
    (is (= 5 (length (ethereum-lisp.crypto:aes-ctr
                      (hex-to-bytes "0x2b7e151628aed2a6abf7158809cf4f3c")
                      counter (make-byte-vector 5)))))))

(deftest hmac-sha256-matches-rfc-4231
  (labels ((mac (key-hex msg-hex)
             (bytes-to-hex
              (ethereum-lisp.crypto:hmac-sha256
               (hex-to-bytes key-hex) (hex-to-bytes msg-hex)))))
    ;; RFC 4231 Test Case 1: key = 0x0b x20, data = "Hi There".
    (is (string= "0xb0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
                 (mac "0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
                      "0x4869205468657265")))
    ;; RFC 4231 Test Case 2: key = "Jefe", data = "what do ya want for nothing?".
    (is (string= "0x5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
                 (mac "0x4a656665"
                      "0x7768617420646f2079612077616e7420666f72206e6f7468696e673f")))
    ;; RFC 4231 Test Case 6: key longer than the block size is hashed first.
    (is (string= "0x60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
                 (mac (concatenate 'string "0x" (make-string 262 :initial-element #\a))
                      "0x54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374")))))

(deftest constant-time-bytes=-compares-by-value
  (is (ethereum-lisp.crypto:constant-time-bytes=
       (hex-to-bytes "0x0011ff") (hex-to-bytes "0x0011ff")))
  (is (not (ethereum-lisp.crypto:constant-time-bytes=
            (hex-to-bytes "0x0011ff") (hex-to-bytes "0x0011fe"))))
  (is (not (ethereum-lisp.crypto:constant-time-bytes=
            (hex-to-bytes "0x0011") (hex-to-bytes "0x0011ff")))))

(deftest secp256k1-ecdh-agrees-both-ways
  ;; ECDH(a, B) = ECDH(b, A): both parties derive the same shared secret, and it
  ;; equals the X coordinate of the shared point.
  (let* ((a-priv #x1111111111111111111111111111111111111111111111111111111111111111)
         (b-priv #x2222222222222222222222222222222222222222222222222222222222222222)
         (a-pub (secp256k1-private-key-public-key a-priv))
         (b-pub (secp256k1-private-key-public-key b-priv))
         (shared-a (ethereum-lisp.crypto:secp256k1-ecdh a-priv b-pub))
         (shared-b (ethereum-lisp.crypto:secp256k1-ecdh b-priv a-pub)))
    (is (= 32 (length shared-a)))
    (is (bytes= shared-a shared-b))
    ;; The shared secret is the X coordinate of a*B, checked independently.
    (let* ((b-point (ethereum-lisp.crypto:secp256k1-public-key-point b-pub))
           (shared-point (ethereum-lisp.crypto::secp256k1-scalar-multiply a-priv b-point)))
      (is (string= (bytes-to-hex shared-a)
                   (bytes-to-hex
                    (ethereum-lisp.crypto::integer-to-fixed-bytes
                     (ethereum-lisp.crypto::secp256k1-point-x shared-point) 32))))))
  ;; A point off the curve is rejected.
  (signals error (ethereum-lisp.crypto:secp256k1-ecdh 5 (make-byte-vector 64))))

(deftest secp256k1-sign-round-trips-through-recovery
  ;; Signing then recovering must return the signer's public key, for several
  ;; keys and messages, which fully checks the signature math and recovery id.
  (dolist (private-key (list 1
                             #x1111111111111111111111111111111111111111111111111111111111111111
                             #xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789))
    (let ((public-key (secp256k1-private-key-public-key private-key)))
      (dotimes (i 4)
        (let* ((hash (sha256 (ascii-to-bytes (format nil "message ~D" i))))
               (signature (ethereum-lisp.crypto:secp256k1-sign hash private-key)))
          (is (= 65 (length signature)))
          ;; s is canonical (in the lower half of the curve order).
          (is (<= (bytes-to-integer (subseq signature 32 64))
                  (floor ethereum-lisp.crypto::+secp256k1-n+ 2)))
          ;; v is a recovery id.
          (is (member (aref signature 64) '(0 1)))
          (let ((recovered
                  (secp256k1-recover-public-key
                   hash
                   (aref signature 64)
                   (bytes-to-integer (subseq signature 0 32))
                   (bytes-to-integer (subseq signature 32 64)))))
            (is (bytes= public-key recovered)))))))
  ;; A pinned nonce is deterministic.
  (let* ((hash (sha256 (ascii-to-bytes "fixed")))
         (a (ethereum-lisp.crypto:secp256k1-sign hash 42 :k 12345))
         (b (ethereum-lisp.crypto:secp256k1-sign hash 42 :k 12345)))
    (is (bytes= a b))))

(deftest keccak-256-incremental-matches-one-shot
  (let ((data (ascii-to-bytes "the quick brown fox jumps over the lazy dog")))
    ;; Absorbing in arbitrary pieces equals hashing the whole input at once.
    (let ((sponge (ethereum-lisp.crypto:make-keccak-256)))
      (ethereum-lisp.crypto:keccak-256-update sponge (subseq data 0 5))
      (ethereum-lisp.crypto:keccak-256-update sponge (subseq data 5 6))
      (ethereum-lisp.crypto:keccak-256-update sponge (subseq data 6))
      (is (bytes= (keccak-256 data)
                  (ethereum-lisp.crypto:keccak-256-digest sponge)))
      ;; Digesting does not consume the sponge: more data can still be absorbed.
      (ethereum-lisp.crypto:keccak-256-update sponge (ascii-to-bytes "!"))
      (is (bytes= (keccak-256 (ascii-to-bytes
                               (concatenate 'string
                                            "the quick brown fox jumps over the lazy dog"
                                            "!")))
                  (ethereum-lisp.crypto:keccak-256-digest sponge))))
    ;; An input spanning several sponge blocks (> 136 bytes) still matches.
    (let ((big (make-byte-vector 300 :initial-element #xab))
          (sponge (ethereum-lisp.crypto:make-keccak-256)))
      (ethereum-lisp.crypto:keccak-256-update sponge (subseq big 0 137))
      (ethereum-lisp.crypto:keccak-256-update sponge (subseq big 137))
      (is (bytes= (keccak-256 big)
                  (ethereum-lisp.crypto:keccak-256-digest sponge))))))
