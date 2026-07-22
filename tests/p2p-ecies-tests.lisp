(in-package #:ethereum-lisp.test)

;;;; ECIES tests: the concatKDF vector from go-ethereum, plus round-trip and
;;;; authentication properties.

(deftest ecies-concat-kdf-matches-go-ethereum
  ;; go-ethereum crypto/ecies TestKDF: concatKDF(SHA256, "input", nil, len).
  (let ((input (ascii-to-bytes "input")))
    (is (string= "0x858b192fa2ed"
                 (bytes-to-hex (ecies-concat-kdf input 6))))
    (is (string= "0x858b192fa2ed4395e2bf88dd8d5770d67dc284ee539f12da8bceaa45d06ebae0"
                 (bytes-to-hex (ecies-concat-kdf input 32))))
    (is (string= (concatenate 'string
                              "0x858b192fa2ed4395e2bf88dd8d5770d6"
                              "7dc284ee539f12da8bceaa45d06ebae0"
                              "700f1ab918a5f0413b8140f9940d6955")
                 (bytes-to-hex (ecies-concat-kdf input 48))))
    (is (string= (concatenate 'string
                              "0x858b192fa2ed4395e2bf88dd8d5770d6"
                              "7dc284ee539f12da8bceaa45d06ebae0"
                              "700f1ab918a5f0413b8140f9940d6955"
                              "f3467fd6672cce1024c5b1effccc0f61")
                 (bytes-to-hex (ecies-concat-kdf input 64))))))

(deftest ecies-round-trips-and-authenticates
  (let* ((recipient-priv
          #xd0b043b4c5d657670778242d82d68a29d25d7d711127d17b8e299f156dad361a)
         (recipient-pub (secp256k1-private-key-public-key recipient-priv))
         (other-priv
          #x4b50fa71f5c3eeb8fdc452224b2395af2fcc3d125e06c32c82e048c0559db03f)
         (message (ascii-to-bytes "Hello, world.")))
    ;; Encrypt (with pinned ephemeral key + IV) then decrypt recovers the message.
    (let ((ciphertext
            (ecies-encrypt recipient-pub message
                           :ephemeral-private-key
                           #x1111111111111111111111111111111111111111111111111111111111111111
                           :iv (hex-to-bytes "0x0102030405060708090a0b0c0d0e0f10"))))
      (is (= (+ (length message) 65 16 32) (length ciphertext)))
      (is (= #x04 (aref ciphertext 0)))
      (is (bytes= message (ecies-decrypt recipient-priv ciphertext)))
      ;; The wrong private key cannot decrypt.
      (signals error (ecies-decrypt other-priv ciphertext))
      ;; A single flipped byte in the tag fails authentication.
      (let ((tampered (copy-seq ciphertext)))
        (setf (aref tampered (1- (length tampered)))
              (logxor (aref tampered (1- (length tampered))) 1))
        (signals error (ecies-decrypt recipient-priv tampered))))
    ;; Shared data (s2) is authenticated: it must match on both sides.
    (let ((ciphertext (ecies-encrypt recipient-pub message
                                     :shared-data (hex-to-bytes "0xcafe"))))
      (is (bytes= message
                  (ecies-decrypt recipient-priv ciphertext
                                 :shared-data (hex-to-bytes "0xcafe"))))
      (signals error (ecies-decrypt recipient-priv ciphertext))
      (signals error (ecies-decrypt recipient-priv ciphertext
                                    :shared-data (hex-to-bytes "0xbeef"))))
    ;; Fresh randomness each call still round-trips.
    (let ((ciphertext (ecies-encrypt recipient-pub message)))
      (is (bytes= message (ecies-decrypt recipient-priv ciphertext))))))
