(in-package #:ethereum-lisp.test)

(deftest keccak-known-vectors
  (is (string= "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
               (keccak-256-hex (ascii-to-bytes "abc"))))
  (is (string= "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
               (hash32-to-hex +empty-code-hash+)))
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (hash32-to-hex +empty-trie-hash+))))

(deftest sha256-known-vectors
  (is (string= "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
               (sha256-hex #())))
  (is (string= "0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
               (sha256-hex (ascii-to-bytes "abc")))))

(deftest ripemd160-known-vectors
  (is (string= "0x9c1185a5c5e9fc54612808977ee8f548b2258d31"
               (ripemd160-hex #())))
  (is (string= "0x8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
               (ripemd160-hex (ascii-to-bytes "abc")))))

(deftest secp256k1-recovers-ecrecover-vector-address
  (let* ((input
           (hex-to-bytes
            "0x18c547e4f7b0f325ad1e56f57e26c745b09a3e503d86e00e5255ff7f715d3d1c000000000000000000000000000000000000000000000000000000000000001c73b1693892219d736caba55bdb67216e485557ea6b6af75f37096c9aa6a5a75feeb940b1d03b21e36b0e47e79769f095fe2ab855bd91e3a38756b7d75a9c4549"))
         (hash (subseq input 0 32))
         (v (- (aref input 63) 27))
         (r (bytes-to-integer (subseq input 64 96)))
         (s (bytes-to-integer (subseq input 96 128)))
         (public-key (secp256k1-recover-public-key hash v r s))
         (address (secp256k1-recover-address hash v r s)))
    (is (= 64 (length public-key)))
    (is (string= "0xa94f5374fce5edbc8e2a8697c15331677e6ebf0b"
                 (address-to-hex address)))
    (is (null (secp256k1-recover-address hash 2 r s)))
    (is (null (secp256k1-recover-address hash v 0 s)))
    (is (null (secp256k1-recover-address hash v r 0)))))

(deftest secp256k1-private-key-address-vector
  (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
               (address-to-hex
                (secp256k1-private-key-address
                 (hex-to-quantity
                  "0x4646464646464646464646464646464646464646464646464646464646464646")))))
  (signals error (secp256k1-private-key-address 0)))

(deftest kzg-commitment-versioned-hash
  (let* ((commitment (make-byte-vector +kzg-commitment-size+))
         (versioned-hash
           (kzg-commitment-to-versioned-hash commitment)))
    (is (hash32-p versioned-hash))
    (is (= +kzg-commitment-version+
           (aref (hash32-bytes versioned-hash) 0)))
    (is (string= "0x01b0761f87b081d5cf10757ccc89f12be355c70e2e29df288b65b30710dcbcd1"
                 (hash32-to-hex versioned-hash))))
  (signals error (kzg-commitment-to-versioned-hash #(1 2 3))))
