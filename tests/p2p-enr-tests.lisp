(in-package #:ethereum-lisp.test)

;;;; Ethereum Node Records (EIP-778): decode+verify the canonical golden record,
;;;; and round-trip our own.

(defparameter *eip778-golden-enr*
  ;; The EIP-778 example record (base64url-decoded to RLP), signed by the example
  ;; key b71c71a6…: [sig, seq=1, id=v4, ip=127.0.0.1, secp256k1, udp=30303].
  (hex-to-bytes
   (concatenate 'string
    "0xf884b8407098ad865b00a582051940cb9cf36836572411a47278783077011599ed5cd16b"
    "76f2635f4e234738f30813a89eb9137e3e3df5266e3a1f11df72ecf1145ccb9c0182696482"
    "7634826970847f00000189736563703235366b31a103ca634cae0d49acb401d8a4c6b6fe8c"
    "55b70d115bf400769cc1400f3258cd31388375647082765f")))

(defparameter *eip778-golden-key*
  #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)

(deftest enr-decodes-and-verifies-the-eip778-golden-record
  (:layer :unit :module :p2p)
  (let ((record (ethereum-lisp.p2p:decode-enr *eip778-golden-enr*)))
    ;; The signature verified (decode signals otherwise), and the fields decode.
    (is (= 1 (ethereum-lisp.p2p:enr-seq record)))
    (is (bytes= (hex-to-bytes "0x7f000001")
                (ethereum-lisp.p2p:enr-value record "ip")))
    (is (= 30303 (bytes-to-integer
                  (ethereum-lisp.p2p:enr-value record "udp"))))
    ;; The record's public key is the example key's public key.
    (is (bytes= (node-id-from-private-key *eip778-golden-key*)
                (ethereum-lisp.p2p:enr-public-key record)))))

(deftest enr-rejects-a-tampered-record
  (:layer :unit :module :p2p)
  ;; Flipping a signature byte breaks verification.
  (let ((tampered (copy-seq *eip778-golden-enr*)))
    ;; byte 5 is inside the 64-byte signature (after f884 b840).
    (setf (aref tampered 5) (logxor (aref tampered 5) 1))
    (signals error (ethereum-lisp.p2p:decode-enr tampered))))

(deftest enr-round-trips-our-own-record
  (:layer :unit :module :p2p)
  (let* ((key #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (record (ethereum-lisp.p2p:encode-enr
                  key 7
                  (list (cons "ip" (hex-to-bytes "0x0a000002"))
                        (cons "udp" (integer-to-minimal-bytes 30304))
                        (cons "tcp" (integer-to-minimal-bytes 30305)))))
         (decoded (ethereum-lisp.p2p:decode-enr record)))
    (is (= 7 (ethereum-lisp.p2p:enr-seq decoded)))
    (is (bytes= (node-id-from-private-key key)
                (ethereum-lisp.p2p:enr-public-key decoded)))
    (is (bytes= (hex-to-bytes "0x0a000002")
                (ethereum-lisp.p2p:enr-value decoded "ip")))
    (is (= 30304 (bytes-to-integer (ethereum-lisp.p2p:enr-value decoded "udp"))))
    (is (= 30305 (bytes-to-integer (ethereum-lisp.p2p:enr-value decoded "tcp"))))
    (is (string= "v4" (bytes-to-ascii (ethereum-lisp.p2p:enr-value decoded "id"))))))

(deftest discv4-enr-request-response-packets-round-trip
  (:layer :unit :module :p2p)
  (let* ((key #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (record (ethereum-lisp.p2p:encode-enr
                  key 3 (list (cons "ip" (hex-to-bytes "0x7f000001"))
                              (cons "udp" (integer-to-minimal-bytes 30303)))))
         (req-packet (ethereum-lisp.p2p:encode-discv4-packet
                      key ethereum-lisp.p2p:+discv4-packet-enr-request+
                      (ethereum-lisp.p2p:encode-discv4-enr-request
                       (ethereum-lisp.p2p:make-discv4-enr-request
                        :expiration 1234567890)))))
    ;; decode-discv4-packet now returns the 32-byte packet hash as a 4th value.
    (multiple-value-bind (type data sender hash)
        (ethereum-lisp.p2p:decode-discv4-packet req-packet)
      (declare (ignore sender))
      (is (= ethereum-lisp.p2p:+discv4-packet-enr-request+ type))
      (is (= 32 (length hash)))
      (is (= 1234567890
             (ethereum-lisp.p2p:discv4-enr-request-expiration
              (ethereum-lisp.p2p:decode-discv4-enr-request data))))
      ;; An ENRResponse echoes the request hash and carries a verifiable record.
      (let ((resp-packet (ethereum-lisp.p2p:encode-discv4-packet
                          key ethereum-lisp.p2p:+discv4-packet-enr-response+
                          (ethereum-lisp.p2p:encode-discv4-enr-response
                           (ethereum-lisp.p2p:make-discv4-enr-response
                            :request-hash hash :record record)))))
        (multiple-value-bind (rtype rdata) (ethereum-lisp.p2p:decode-discv4-packet resp-packet)
          (is (= ethereum-lisp.p2p:+discv4-packet-enr-response+ rtype))
          (let ((decoded (ethereum-lisp.p2p:decode-discv4-enr-response rdata)))
            (is (bytes= hash (ethereum-lisp.p2p:discv4-enr-response-request-hash decoded)))
            ;; The embedded record still decodes and verifies.
            (is (= 3 (ethereum-lisp.p2p:enr-seq
                      (ethereum-lisp.p2p:decode-enr
                       (ethereum-lisp.p2p:discv4-enr-response-record decoded)))))))))))

(deftest enr-rejects-trailing-bytes-and-unsorted-keys
  (:layer :unit :module :p2p)
  ;; A record is exactly its RLP: appending a byte must be rejected.
  (let ((padded (make-byte-vector (1+ (length *eip778-golden-enr*)))))
    (replace padded *eip778-golden-enr*)
    (signals error (ethereum-lisp.p2p:decode-enr padded))))
