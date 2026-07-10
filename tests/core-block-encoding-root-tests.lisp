(in-package #:ethereum-lisp.test)

(deftest protocol-model-package-boundaries
  (let ((accounts (find-package '#:ethereum-lisp.accounts))
        (receipts (find-package '#:ethereum-lisp.receipts))
        (transactions (find-package '#:ethereum-lisp.transactions))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list accounts))))
    (is (not (member core (package-use-list receipts))))
    (is (member transactions (package-use-list receipts)))
    (dolist (entry `((,accounts "STATE-ACCOUNT")
                     (,accounts "STATE-ACCOUNT-RLP")
                     (,receipts "RECEIPT")
                     (,receipts "TRANSACTION-RECEIPT-LIST-ROOT")))
      (destructuring-bind (owner name) entry
        (multiple-value-bind (owned-symbol owned-status)
            (find-symbol name owner)
          (multiple-value-bind (core-symbol core-status)
              (find-symbol name core)
            (is (eq :external owned-status))
            (is (eq :external core-status))
            (is (eq owned-symbol core-symbol))))))
    (dolist (entry `((,accounts "RECEIPT")
                     (,accounts "BLOCK-HEADER")
                     (,receipts "STATE-ACCOUNT")
                     (,receipts "BLOCK-HEADER")))
      (destructuring-bind (package name) entry
        (multiple-value-bind (symbol status)
            (find-symbol name package)
          (is (null symbol))
          (is (null status)))))))

(deftest bloom-add-and-lookup-log-values
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic)))
         (bloom (receipt-bloom (list log))))
    (is (bloom-contains-p bloom (address-bytes address)))
    (is (bloom-contains-p bloom (hash32-bytes topic)))))

(deftest receipt-rlp-and-root
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (root (receipt-list-root (list receipt))))
    (is (= 267 (length (receipt-rlp receipt))))
    (is (string= "0xf9010801825208"
                 (subseq (bytes-to-hex (receipt-rlp receipt)) 0 16)))
    (is (hash32-p root))))

(deftest typed-receipt-encoding-and-root
  (let* ((legacy (make-legacy-transaction :gas-price 1))
         (dynamic (make-dynamic-fee-transaction
                   :max-priority-fee-per-gas 1
                   :max-fee-per-gas 2))
         (legacy-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (dynamic-receipt (make-receipt :status 1
                                        :cumulative-gas-used 42000))
         (typed-encoding
           (transaction-receipt-encoding dynamic dynamic-receipt))
         (root
           (transaction-receipt-list-root
            (list legacy dynamic)
            (list legacy-receipt dynamic-receipt))))
    (is (= 2 (transaction-type dynamic)))
    (is (= 2 (aref typed-encoding 0)))
    (is (bytes= (receipt-rlp dynamic-receipt)
                (subseq typed-encoding 1)))
    (is (string= (hash32-to-hex (receipt-list-root
                                 (list legacy-receipt)))
                 (hash32-to-hex
                  (transaction-receipt-list-root
                   (list legacy)
                   (list legacy-receipt)))))
    (is (not (string= (hash32-to-hex
                       (receipt-list-root
                        (list legacy-receipt dynamic-receipt)))
                      (hash32-to-hex root))))
    (signals block-validation-error
      (transaction-receipt-list-root (list legacy) '()))))

(deftest transaction-list-root-empty-and-single
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (hash32-to-hex (transaction-list-root '()))))
  (let ((root (transaction-list-root
               (list (make-legacy-transaction :nonce 1
                                              :gas-price 2
                                              :gas-limit 3
                                              :value 4
                                              :data #(96 0)
                                              :v 27
                                              :r 5
                                              :s 6)))))
    (is (hash32-p root))))

(deftest typed-transaction-encodings
  (let* ((recipient (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (tx1 (make-access-list-transaction :chain-id 1
                                            :nonce 2
                                            :gas-price 3
                                            :gas-limit 4
                                            :to recipient
                                            :value 5
                                            :data #(6)
                                            :access-list access
                                            :y-parity 1
                                            :r 7
                                            :s 8))
         (tx2 (make-dynamic-fee-transaction :chain-id 1
                                            :nonce 2
                                            :max-priority-fee-per-gas 3
                                            :max-fee-per-gas 4
                                            :gas-limit 5
                                            :to recipient
                                            :value 6
                                            :data #(7)
                                            :access-list access
                                            :y-parity 1
                                            :r 8
                                            :s 9))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (tx3 (make-blob-transaction :chain-id 1
                                      :nonce 2
                                      :max-priority-fee-per-gas 3
                                      :max-fee-per-gas 4
                                      :gas-limit 5
                                      :to recipient
                                      :value 6
                                      :data #(7)
                                      :access-list access
                                      :max-fee-per-blob-gas 10
                                      :blob-versioned-hashes (list blob-hash)
                                      :y-parity 1
                                      :r 8
                                      :s 9))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (tx4 (make-set-code-transaction :chain-id 1
                                          :nonce 2
                                          :max-priority-fee-per-gas 3
                                          :max-fee-per-gas 4
                                          :gas-limit 5
                                          :to recipient
                                          :value 6
                                          :data #(7)
                                          :access-list access
                                          :authorization-list (list authorization)
                                          :y-parity 1
                                          :r 8
                                          :s 9))
         (blob-encoding (blob-transaction-encoding tx3))
         (blob-payload (rlp-decode-one (subseq blob-encoding 1)))
         (blob-items (rlp-list-items blob-payload))
         (blob-hash-items (rlp-list-items (nth 10 blob-items)))
         (set-code-encoding (set-code-transaction-encoding tx4))
         (set-code-payload (rlp-decode-one (subseq set-code-encoding 1)))
         (set-code-items (rlp-list-items set-code-payload))
         (authorization-items
           (rlp-list-items
            (first (rlp-list-items (nth 9 set-code-items))))))
    (is (= 1 (aref (access-list-transaction-encoding tx1) 0)))
    (is (= 2 (aref (dynamic-fee-transaction-encoding tx2) 0)))
    (is (= 3 (aref blob-encoding 0)))
    (is (= 4 (aref set-code-encoding 0)))
    (is (= 14 (length blob-items)))
    (is (= 10 (bytes-to-integer (nth 9 blob-items))))
    (is (= 1 (length blob-hash-items)))
    (is (bytes= (hash32-bytes blob-hash) (first blob-hash-items)))
    (is (= 13 (length set-code-items)))
    (is (= 6 (length authorization-items)))
    (is (= 11 (bytes-to-integer (third authorization-items))))
    (let ((decoded (transaction-from-encoding
                    (access-list-transaction-encoding tx1))))
      (is (typep decoded 'access-list-transaction))
      (is (= 1 (access-list-transaction-chain-id decoded)))
      (is (= 2 (access-list-transaction-nonce decoded)))
      (is (= 3 (access-list-transaction-gas-price decoded)))
      (is (= 4 (access-list-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (access-list-transaction-to decoded))))
      (is (= 5 (access-list-transaction-value decoded)))
      (is (bytes= #(6) (access-list-transaction-data decoded)))
      (is (= 1 (length (access-list-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (access-list-transaction-access-list
                                   decoded)))))))
      (is (= 1 (access-list-transaction-y-parity decoded)))
      (is (= 7 (access-list-transaction-r decoded)))
      (is (= 8 (access-list-transaction-s decoded)))
      (is (bytes= (access-list-transaction-encoding tx1)
                  (access-list-transaction-encoding decoded))))
    (signals block-validation-error
      (access-list-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (access-list-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4
                       (make-byte-vector 20)
                       5
                       (make-byte-vector 1 :initial-element 6)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 19)
                         (make-rlp-list)))
                       1 7 8))))
    (let ((decoded (transaction-from-encoding
                    (dynamic-fee-transaction-encoding tx2))))
      (is (typep decoded 'dynamic-fee-transaction))
      (is (= 1 (dynamic-fee-transaction-chain-id decoded)))
      (is (= 2 (dynamic-fee-transaction-nonce decoded)))
      (is (= 3 (dynamic-fee-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (dynamic-fee-transaction-max-fee-per-gas decoded)))
      (is (= 5 (dynamic-fee-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (dynamic-fee-transaction-to decoded))))
      (is (= 6 (dynamic-fee-transaction-value decoded)))
      (is (bytes= #(7) (dynamic-fee-transaction-data decoded)))
      (is (= 1 (length (dynamic-fee-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (dynamic-fee-transaction-access-list
                                   decoded)))))))
      (is (= 1 (dynamic-fee-transaction-y-parity decoded)))
      (is (= 8 (dynamic-fee-transaction-r decoded)))
      (is (= 9 (dynamic-fee-transaction-s decoded)))
      (is (bytes= (dynamic-fee-transaction-encoding tx2)
                  (dynamic-fee-transaction-encoding decoded))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 20)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 20)
                         (make-rlp-list (make-byte-vector 31))))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (blob-transaction-encoding tx3))))
      (is (typep decoded 'blob-transaction))
      (is (= 1 (blob-transaction-chain-id decoded)))
      (is (= 2 (blob-transaction-nonce decoded)))
      (is (= 3 (blob-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (blob-transaction-max-fee-per-gas decoded)))
      (is (= 5 (blob-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (blob-transaction-to decoded))))
      (is (= 6 (blob-transaction-value decoded)))
      (is (bytes= #(7) (blob-transaction-data decoded)))
      (is (= 1 (length (blob-transaction-access-list decoded))))
      (is (= 10 (blob-transaction-max-fee-per-blob-gas decoded)))
      (is (= 1 (length (blob-transaction-blob-versioned-hashes decoded))))
      (is (bytes= (hash32-bytes blob-hash)
                  (hash32-bytes
                   (first (blob-transaction-blob-versioned-hashes decoded)))))
      (is (= 1 (blob-transaction-y-parity decoded)))
      (is (= 8 (blob-transaction-r decoded)))
      (is (= 9 (blob-transaction-s decoded)))
      (is (bytes= (blob-transaction-encoding tx3)
                  (blob-transaction-encoding decoded))))
    (signals block-validation-error
      (blob-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (hash32-bytes blob-hash))
                       1 8 9))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (make-byte-vector 31))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (set-code-transaction-encoding tx4))))
      (is (typep decoded 'set-code-transaction))
      (is (= 1 (set-code-transaction-chain-id decoded)))
      (is (= 2 (set-code-transaction-nonce decoded)))
      (is (= 3 (set-code-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (set-code-transaction-max-fee-per-gas decoded)))
      (is (= 5 (set-code-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (set-code-transaction-to decoded))))
      (is (= 6 (set-code-transaction-value decoded)))
      (is (bytes= #(7) (set-code-transaction-data decoded)))
      (is (= 1 (length (set-code-transaction-access-list decoded))))
      (is (= 1 (length (set-code-transaction-authorization-list decoded))))
      (let ((decoded-authorization
              (first (set-code-transaction-authorization-list decoded))))
        (is (= 1 (set-code-authorization-chain-id decoded-authorization)))
        (is (string= (address-to-hex recipient)
                     (address-to-hex
                      (set-code-authorization-address
                       decoded-authorization))))
        (is (= 11 (set-code-authorization-nonce decoded-authorization)))
        (is (= 1 (set-code-authorization-y-parity decoded-authorization)))
        (is (= 12 (set-code-authorization-r decoded-authorization)))
        (is (= 13 (set-code-authorization-s decoded-authorization))))
      (is (= 1 (set-code-transaction-y-parity decoded)))
      (is (= 8 (set-code-transaction-r decoded)))
      (is (= 9 (set-code-transaction-s decoded)))
      (is (bytes= (set-code-transaction-encoding tx4)
                  (set-code-transaction-encoding decoded))))
    (signals block-validation-error
      (set-code-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (address-bytes recipient)
                                       11 1 12 13))
                       1 8 9))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (make-byte-vector 0)
                                       11 1 12 13))
                       1 8 9))))
    (is (hash32-p (transaction-hash tx1)))
    (is (hash32-p (blob-transaction-signing-hash tx3)))
    (is (not (string= (hash32-to-hex (blob-transaction-signing-hash tx3))
                      (hash32-to-hex (blob-transaction-hash tx3)))))
    (is (hash32-p (set-code-authorization-signing-hash authorization)))
    (is (hash32-p (set-code-transaction-signing-hash tx4)))
    (is (not (string= (hash32-to-hex (set-code-transaction-signing-hash tx4))
                      (hash32-to-hex (set-code-transaction-hash tx4)))))
    (is (hash32-p (transaction-list-root (list tx1 tx2 tx3 tx4))))))
