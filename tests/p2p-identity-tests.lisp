(in-package #:ethereum-lisp.test)

;;;; devp2p node identity and enode URL tests.

(deftest node-id-derives-from-the-node-key
  ;; The node identity is the uncompressed public key body, the same value that
  ;; hashes to the account address, so the two must agree on one key.
  (let* ((private-key
           (bytes-to-integer
            (hex-to-bytes
             "0x4646464646464646464646464646464646464646464646464646464646464646")))
         (node-id (node-id-from-private-key private-key)))
    (is (= +node-id-size+ (length node-id)))
    ;; Deriving the address from the identity matches deriving it from the key.
    (is (string= (address-to-hex (secp256k1-private-key-address private-key))
                 (address-to-hex
                  (make-address (subseq (keccak-256 node-id) 12 32)))))
    ;; Hex form is unprefixed and 128 characters, as enode URLs require.
    (is (= 128 (length (node-id-to-hex node-id))))
    (is (string/= "0x" (subseq (node-id-to-hex node-id) 0 2)))
    ;; Round-trips through hex, with or without a prefix.
    (is (bytes= node-id (node-id-from-hex (node-id-to-hex node-id))))
    (is (bytes= node-id
                (node-id-from-hex
                 (concatenate 'string "0x" (node-id-to-hex node-id)))))))

(deftest node-id-rejects-malformed-input
  (signals error (node-id-from-hex "0x00"))
  (signals error (node-id-from-hex "not-hex"))
  (signals error (node-id-to-hex (make-byte-vector 32)))
  (signals error (node-id-from-private-key 0)))

(deftest enode-urls-round-trip
  (let* ((node-id (node-id-from-private-key 12345))
         (hex (node-id-to-hex node-id)))
    ;; Discovery on the TCP port is implied, so discport is omitted.
    (let ((url (enode-url node-id "10.0.0.1" 30303)))
      (is (string= (format nil "enode://~A@10.0.0.1:30303" hex) url))
      (multiple-value-bind (parsed-id host tcp discovery) (parse-enode-url url)
        (is (bytes= node-id parsed-id))
        (is (string= "10.0.0.1" host))
        (is (= 30303 tcp))
        (is (= 30303 discovery))))
    ;; A distinct discovery port is carried explicitly.
    (let ((url (enode-url node-id "10.0.0.1" 30303 :discovery-port 30304)))
      (is (string= (format nil "enode://~A@10.0.0.1:30303?discport=30304" hex)
                   url))
      (multiple-value-bind (parsed-id host tcp discovery) (parse-enode-url url)
        (declare (ignore parsed-id host))
        (is (= 30303 tcp))
        (is (= 30304 discovery))))
    ;; A discovery port equal to the TCP port stays implicit.
    (is (string= (enode-url node-id "10.0.0.1" 30303)
                 (enode-url node-id "10.0.0.1" 30303 :discovery-port 30303)))
    ;; Splitting on the last colon keeps IPv6 literals intact.
    (multiple-value-bind (parsed-id host tcp)
        (parse-enode-url (format nil "enode://~A@[::1]:30303" hex))
      (declare (ignore parsed-id))
      (is (string= "[::1]" host))
      (is (= 30303 tcp)))))

(deftest enode-urls-reject-malformed-input
  (let ((hex (node-id-to-hex (node-id-from-private-key 999))))
    (signals error (parse-enode-url "http://example.com"))
    (signals error (parse-enode-url (format nil "enode://~A" hex)))
    (signals error (parse-enode-url (format nil "enode://~A@host" hex)))
    (signals error (parse-enode-url (format nil "enode://~A@:30303" hex)))
    (signals error (parse-enode-url (format nil "enode://~A@host:99999" hex)))
    (signals error (parse-enode-url (format nil "enode://~A@host:abc" hex)))
    (signals error (parse-enode-url "enode://deadbeef@host:30303"))
    (signals error (enode-url (node-id-from-private-key 999) "host" 99999))))
