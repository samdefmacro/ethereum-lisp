(in-package #:ethereum-lisp.test)

;;;; Discovery v5.1 official vectors, core messages, and routing policy.
;;;;
;;;; Vectors are from ethereum/devp2p discv5-wire-test-vectors.md and are also
;;;; consumed by the opt-in pinned geth v1.16.6 interoperability test.

(defun discv5-test-hex (&rest parts)
  (hex-to-bytes (apply #'concatenate 'string parts)))

(defun discv5-test-record (private-key sequence ip port)
  (ethereum-lisp.p2p:encode-enr
   private-key sequence
   (list (cons "ip" ip)
         (cons "udp" (integer-to-minimal-bytes port))
         (cons "tcp" (integer-to-minimal-bytes port)))))

(deftest discv5-official-cryptographic-vectors
  (:layer :unit :module :p2p)
  (let ((key (hex-to-bytes "0x9f2d77db7004bf8a1a85107ac686990b"))
        (nonce (hex-to-bytes "0x27b5af763c446acd2749fe8e"))
        (plaintext (hex-to-bytes "0x01c20101"))
        (ad (hex-to-bytes
             "0x93a7400fa0d6a694ebc24d5cf570f65d04215b6ac00757875e3f3a5f42107903"))
        (ciphertext (hex-to-bytes
                     "0xa5d12a2d94b8ccb3ba55558229867dc13bfa3648")))
    (is (bytes= ciphertext
                (ethereum-lisp.discv5:discv5-aes-gcm-encrypt
                 key nonce plaintext ad)))
    (is (bytes= plaintext
                (ethereum-lisp.discv5:discv5-aes-gcm-decrypt
                 key nonce ciphertext ad)))
    (let ((tampered (copy-seq ciphertext)))
      (setf (aref tampered 5) (logxor 1 (aref tampered 5)))
      (signals error
        (ethereum-lisp.discv5:discv5-aes-gcm-decrypt
         key nonce tampered ad))))
  (let* ((ephemeral-key
           #xfb757dc581730490a1d7a00deea65e9b1936924caaea8f44d476014856b68736)
         (destination-public
           (hex-to-bytes
            "0x0317931e6e0840220642f230037d285d122bc59063221ef3226b1f403ddc69ca91"))
         (node-a (hex-to-bytes
                  "0xaaaa8419e9f49d0083561b48287df592939a8d19947d8c0ef88f2a4856a69fbb"))
         (node-b (hex-to-bytes
                  "0xbbbb9d047f0488c0b5a93c1c3f2d8bafc7c8ff337024a55434a0d0555de64db9"))
         (challenge
           (hex-to-bytes
            "0x000000000000000000000000000000006469736376350001010102030405060708090a0b0c00180102030405060708090a0b0c0d0e0f100000000000000000")))
    (multiple-value-bind (initiator recipient)
        (ethereum-lisp.discv5:discv5-derive-session-keys
         ephemeral-key destination-public node-a node-b challenge)
      (is (bytes= (hex-to-bytes "0xdccc82d81bd610f4f76d3ebe97a40571")
                  initiator))
      (is (bytes= (hex-to-bytes "0xac74bb8773749920b0d3a8881c173ec5")
                  recipient)))
    (let* ((ephemeral-public
             (hex-to-bytes
              "0x039961e4c2356d61bedb83052c115d311acb3a96f5777296dcf297351130266231"))
           (signature
             (ethereum-lisp.discv5:discv5-id-signature
              ephemeral-key challenge ephemeral-public node-b)))
      (is (bytes=
           (hex-to-bytes
            "0x94852a1e2318c4e5e9d422c98eaf19d1d90d876b29cd06ca7cb7546d0fff7b484fe86c09a064fe72bdbef73ba8e9c34df0cd2b53e9d65528c2c7f336d5dfc6e6")
           signature))
      (is (ethereum-lisp.discv5:discv5-verify-id-signature
           signature
           (secp256k1-private-key-public-key ephemeral-key)
           challenge ephemeral-public node-b)))))

(deftest discv5-official-ping-and-whoareyou-packet-vectors
  (:layer :unit :module :p2p)
  (let* ((key-a
           #xeef77acb6c6a6eebc5b363a475ac583ec7eccdb42b6481424c60f59aa326547f)
         (key-b
           #x66fb62bfbd66b9177a138c1e5cddbe4f7c30c343e94e68df8769459cb1cde628)
         (record-a (discv5-test-record key-a 1 (hex-to-bytes "0x7f000001") 30303))
         (record-b (discv5-test-record key-b 1 (hex-to-bytes "0x7f000001") 30304))
         (codec-a (ethereum-lisp.discv5:make-discv5-codec key-a record-a))
         (codec-b (ethereum-lisp.discv5:make-discv5-codec key-b record-b))
         (id-a (ethereum-lisp.discv5:discv5-codec-node-id codec-a))
         (id-b (ethereum-lisp.discv5:discv5-codec-node-id codec-b))
         (zero-key (make-byte-vector 16))
         (ping-vector
           (discv5-test-hex
            "00000000000000000000000000000000088b3d4342774649325f313964a39e55"
            "ea96c005ad52be8c7560413a7008f16c9e6d2f43bbea8814a546b7409ce783d3"
            "4c4f53245d08dab84102ed931f66d1492acb308fa1c6715b9d139b81acbdcc"))
         (who-vector
           (discv5-test-hex
            "00000000000000000000000000000000088b3d434277464933a1ccc59f5967ad"
            "1d6035f15e528627dde75cd68292f9e6c27d6b66c8100a873fcbaed4e16b8d")))
    ;; The keys derive the exact node IDs printed with the official vectors.
    (is (bytes= id-a
                (hex-to-bytes
                 "0xaaaa8419e9f49d0083561b48287df592939a8d19947d8c0ef88f2a4856a69fbb")))
    (is (bytes= id-b
                (hex-to-bytes
                 "0xbbbb9d047f0488c0b5a93c1c3f2d8bafc7c8ff337024a55434a0d0555de64db9")))
    (ethereum-lisp.discv5:discv5-codec-install-session
     codec-a id-b "127.0.0.1:30304"
     (make-byte-vector 16 :initial-element 1) zero-key
     :remote-record record-b)
    (let ((encoded
            (ethereum-lisp.discv5:discv5-encode-message-packet
             codec-a id-b "127.0.0.1:30304"
             (ethereum-lisp.discv5:make-discv5-ping
              :request-id (hex-to-bytes "0x00000001") :enr-seq 2)
             :nonce (make-byte-vector 12 :initial-element #xff)
             :masking-iv (make-byte-vector 16))))
      (is (bytes= ping-vector encoded)))
    (ethereum-lisp.discv5:discv5-codec-install-session
     codec-b id-a "127.0.0.1:30303"
     zero-key (make-byte-vector 16 :initial-element 1)
     :remote-record record-a)
    (multiple-value-bind (kind message source)
        (ethereum-lisp.discv5:discv5-decode-packet
         codec-b ping-vector "127.0.0.1:30303")
      (is (eq :message kind))
      (is (bytes= id-a source))
      (is (= 2 (ethereum-lisp.discv5:discv5-ping-enr-seq message))))
    (let ((encoded
            (ethereum-lisp.discv5:discv5-encode-whoareyou-packet
             codec-a id-b "127.0.0.1:30304"
             (hex-to-bytes "0x0102030405060708090a0b0c")
             :record-seq 0
             :id-nonce
             (hex-to-bytes "0x0102030405060708090a0b0c0d0e0f10")
             :masking-iv (make-byte-vector 16))))
      (is (bytes= who-vector encoded)))
    (let* ((challenge
             (ethereum-lisp.discv5::make-discv5-whoareyou
              :request-nonce
              (hex-to-bytes "0x0102030405060708090a0b0c")
              :id-nonce
              (hex-to-bytes "0x0102030405060708090a0b0c0d0e0f10")
              :record-seq 1
              :challenge-data
              (hex-to-bytes
               "0x000000000000000000000000000000006469736376350001010102030405060708090a0b0c00180102030405060708090a0b0c0d0e0f100000000000000001")))
           (handshake-vector
             (discv5-test-hex
              "00000000000000000000000000000000088b3d4342774649305f313964a39e55"
              "ea96c005ad521d8c7560413a7008f16c9e6d2f43bbea8814a546b7409ce783d3"
              "4c4f53245d08da4bb252012b2cba3f4f374a90a75cff91f142fa9be3e0a5f3ef"
              "268ccb9065aeecfd67a999e7fdc137e062b2ec4a0eb92947f0d9a74bfbf44dfb"
              "a776b21301f8b65efd5796706adff216ab862a9186875f9494150c4ae06fa4d1"
              "f0396c93f215fa4ef524f1eadf5f0f4126b79336671cbcf7a885b1f8bd2a5d83"
              "9cf8"))
           (encoded
             (ethereum-lisp.discv5:discv5-encode-handshake-packet
              codec-a id-b "127.0.0.1:30304" challenge
              (ethereum-lisp.discv5:make-discv5-ping
               :request-id (hex-to-bytes "0x00000001") :enr-seq 1)
              record-b
              :ephemeral-key
              #x0288ef00023598499cb6c940146d050d2b1fb914198c327f76aad590bead68b6
              :nonce (make-byte-vector 12 :initial-element #xff)
              :masking-iv (make-byte-vector 16))))
      (is (bytes= handshake-vector encoded)))))

(deftest discv5-core-messages-round-trip
  (:layer :unit :module :p2p)
  (dolist
      (message
       (list
        (ethereum-lisp.discv5:make-discv5-ping
         :request-id #(1) :enr-seq 9)
        (ethereum-lisp.discv5:make-discv5-pong
         :request-id #(2) :enr-seq 10
         :recipient-ip #(127 0 0 1) :recipient-port 30303)
        (ethereum-lisp.discv5:make-discv5-findnode
         :request-id #(3) :distances '(0 1 255 256))))
    (let ((decoded
            (ethereum-lisp.discv5:decode-discv5-message
             (ethereum-lisp.discv5:encode-discv5-message message))))
      (is (typep decoded (type-of message)))))
  (let* ((key #x123456789abcdef)
         (record (discv5-test-record key 4 #(127 0 0 1) 30303))
         (message (ethereum-lisp.discv5:make-discv5-nodes
                   :request-id #(4) :total 1 :records (list record)))
         (decoded
           (ethereum-lisp.discv5:decode-discv5-message
            (ethereum-lisp.discv5:encode-discv5-message message))))
    (is (= 1 (length (ethereum-lisp.discv5:discv5-nodes-records decoded))))
    (is (= 4
           (ethereum-lisp.p2p:enr-seq
            (ethereum-lisp.p2p:decode-enr
             (first (ethereum-lisp.discv5:discv5-nodes-records decoded))))))))

(deftest discv5-routing-table-enforces-sequences-distances-and-endpoints
  (:layer :unit :module :p2p)
  (let* ((self-key #x11111111111111111111111111111111)
         (peer-key #x22222222222222222222222222222222)
         (self-record (discv5-test-record self-key 1 #(127 0 0 1) 30303))
         (peer-old (discv5-test-record peer-key 1 #(10 0 0 2) 30304))
         (peer-new (discv5-test-record peer-key 2 #(10 0 0 3) 30305))
         (table
           (ethereum-lisp.discv5:make-discv5-routing-table self-record))
         (entry
           (ethereum-lisp.discv5:discv5-routing-table-put-record
            table peer-old)))
    (is (not (ethereum-lisp.discv5:discv5-routing-entry-validated-p entry)))
    (is (zerop
         (ethereum-lisp.discv5:discv5-routing-table-count
          table :validated-only t)))
    (ethereum-lisp.discv5:discv5-routing-table-put-record
     table peer-new :host #(10 0 0 3) :port 30305 :validated-p t :now 10)
    (is (= 1
           (ethereum-lisp.discv5:discv5-routing-table-count
            table :validated-only t)))
    (let* ((peer-id
             (ethereum-lisp.discv5:discv5-node-id
              (ethereum-lisp.p2p:enr-public-key
               (ethereum-lisp.p2p:decode-enr peer-new))))
           (distance
             (ethereum-lisp.discv5:discv5-log-distance
              (ethereum-lisp.discv5::discv5-routing-table-self-id table)
              peer-id)))
      (is (= 1
             (length
              (ethereum-lisp.discv5:discv5-routing-table-at-distances
               table (list distance) :requester-ip #(10 0 0 9)))))
      ;; A public requester cannot induce relay to the private endpoint.
      (is (null
           (ethereum-lisp.discv5:discv5-routing-table-at-distances
            table (list distance) :requester-ip #(8 8 8 8)))))
    (is (not (ethereum-lisp.discv5:discv5-valid-endpoint-p #(0 0 0 0) 30303)))
    (is (not (ethereum-lisp.discv5:discv5-valid-endpoint-p #(224 0 0 1) 30303)))
    (is (ethereum-lisp.discv5:discv5-valid-endpoint-p #(127 0 0 1) 30303))))
