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
