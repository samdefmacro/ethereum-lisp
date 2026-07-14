(in-package #:ethereum-lisp.test)

(deftest engine-payload-package-boundary
  (let ((payloads (find-package '#:ethereum-lisp.engine-payloads))
        (blocks (find-package '#:ethereum-lisp.blocks))
        (consensus (find-package '#:ethereum-lisp.consensus))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list payloads))))
    (is (member blocks (package-use-list payloads)))
    (is (member consensus (package-use-list payloads)))
    (dolist (name '("EXECUTABLE-DATA" "PAYLOAD-STATUS"
                    "EXECUTABLE-DATA-TO-BLOCK"))
      (multiple-value-bind (payload-symbol payload-status)
          (find-symbol name payloads)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external payload-status))
          (is (eq :external core-status))
          (is (eq payload-symbol core-symbol)))))
    (dolist (name '("ENGINE-PAYLOAD-MEMORY-STORE" "ENGINE-RPC-HANDLE-REQUEST"))
      (multiple-value-bind (symbol status)
          (find-symbol name payloads)
        (is (null symbol))
        (is (null status))))))

(deftest block-derives-body-roots
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4
                                               :data #(5)
                                               :v 27
                                               :r 6
                                               :s 7))
         (log (make-log-entry :address address :topics (list topic) :data #(9)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests (list #(#x00 #xbb) #(#x01 #xaa))
                            :block-access-list '()))
         (header (block-header block)))
    (is (hash32-p (block-hash block)))
    (is (= 1 (length (block-transactions block))))
    (is (= 1 (length (block-withdrawals block))))
    (is (= 2 (length (block-requests block))))
    (is (block-block-access-list-present-p block))
    (is (string= (hash32-to-hex (transaction-list-root (list transaction)))
                 (hash32-to-hex (block-header-transactions-root header))))
    (is (string= (hash32-to-hex (receipt-list-root (list receipt)))
                 (hash32-to-hex (block-header-receipts-root header))))
    (is (string= (hash32-to-hex (withdrawal-list-root (list withdrawal)))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex
                  (execution-requests-hash
                   (list #(#x00 #xbb) #(#x01 #xaa))))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (bytes= (bloom-bytes (receipt-bloom (list log)))
                (block-header-logs-bloom header)))))

(deftest block-to-executable-data-maps-engine-payload-fields
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100
                                    :blob-gas-used 0
                                    :excess-blob-gas 7
                                    :slot-number 11))
         (block (make-block :header header
                            :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests requests))
         (envelope (block-to-executable-data block :block-value 123))
         (payload (execution-payload-envelope-execution-payload envelope)))
    (is (= 123 (execution-payload-envelope-block-value envelope)))
    (is (not (execution-payload-envelope-override-p envelope)))
    (is (hash32-p (executable-data-block-hash payload)))
    (is (string= (hash32-to-hex (block-hash block))
                 (hash32-to-hex (executable-data-block-hash payload))))
    (is (string= (hash32-to-hex parent-hash)
                 (hash32-to-hex (executable-data-parent-hash payload))))
    (is (string= (address-to-hex address)
                 (address-to-hex (executable-data-fee-recipient payload))))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (executable-data-state-root payload))))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (executable-data-random payload))))
    (is (= 42 (executable-data-number payload)))
    (is (= 50000 (executable-data-gas-limit payload)))
    (is (= 21000 (executable-data-gas-used payload)))
    (is (= 99 (executable-data-timestamp payload)))
    (is (= 100 (executable-data-base-fee-per-gas payload)))
    (is (= 0 (executable-data-blob-gas-used payload)))
    (is (= 7 (executable-data-excess-blob-gas payload)))
    (is (= 11 (executable-data-slot-number payload)))
    (is (bytes= #(1 2 3) (executable-data-extra-data payload)))
    (is (bytes= (transaction-encoding transaction)
                (first (executable-data-transactions payload))))
    (is (= 1 (length (executable-data-withdrawals payload))))
    (is (= 1 (withdrawal-index
              (first (executable-data-withdrawals payload)))))
    (is (= 2 (length (execution-payload-envelope-requests envelope))))
    (is (bytes= (first requests)
                (first (execution-payload-envelope-requests envelope))))))

(deftest executable-data-decodes-transaction-bytes
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (transactions
           (list
            (make-legacy-transaction :nonce 1
                                     :gas-price 2
                                     :gas-limit 21000
                                     :to recipient
                                     :value 4
                                     :v 27
                                     :r 6
                                     :s 7)
            (make-access-list-transaction :chain-id 1
                                          :nonce 2
                                          :gas-price 3
                                          :gas-limit 4
                                          :to recipient
                                          :value 5
                                          :data #(6)
                                          :access-list access
                                          :y-parity 1
                                          :r 7
                                          :s 8)
            (make-dynamic-fee-transaction :chain-id 1
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
                                          :s 9)
            (make-blob-transaction :chain-id 1
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
                                   :s 9)
            (make-set-code-transaction :chain-id 1
                                       :nonce 2
                                       :max-priority-fee-per-gas 3
                                       :max-fee-per-gas 4
                                       :gas-limit 5
                                       :to recipient
                                       :value 6
                                       :data #(7)
                                       :access-list access
                                       :authorization-list
                                       (list authorization)
                                       :y-parity 1
                                       :r 8
                                       :s 9)))
         (payload (make-executable-data
                   :transactions (mapcar #'transaction-encoding
                                         transactions)))
         (decoded (executable-data-decoded-transactions payload)))
    (is (= (length transactions) (length decoded)))
    (loop for original in transactions
          for decoded-transaction in decoded
          do (is (typep decoded-transaction (type-of original)))
             (is (bytes= (transaction-encoding original)
                         (transaction-encoding decoded-transaction))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data
        :transactions (append (mapcar #'transaction-encoding
                                      transactions)
                              (list #())))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data :transactions (list 5))))))

(deftest block-from-rlp-decodes-shanghai-empty-body
  (let* ((encoded
           (hex-to-bytes
            "0xf90217f90211a0bd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347940000000000000000000000000000000000000001a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421b9010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000802a82c350806380a0000000000000000000000000000000000000000000000000000000000000000088000000000000000064a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421c0c0c0"))
         (block (block-from-rlp encoded))
         (header (block-header block)))
    (is (string= "0x9937880e9ca0115d6d631f925a1b1559d539eff54dde8813c393baec0b82e77b"
                 (hash32-to-hex (block-hash block))))
    (is (string= "0xbd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6"
                 (hash32-to-hex (block-header-parent-hash header))))
    (is (= #x2a (block-header-number header)))
    (is (= #xc350 (block-header-gas-limit header)))
    (is (= 0 (block-header-gas-used header)))
    (is (= #x64 (block-header-base-fee-per-gas header)))
    (is (block-withdrawals-present-p block))
    (is (= 0 (length (block-withdrawals block))))
    (is (= 0 (length (block-transactions block))))
    (is (= 0 (length (block-ommers block))))
    (is (bytes= encoded (block-rlp block)))))

(deftest canonical-block-rlp-excludes-execution-sidecars
  (let* ((legacy-block (make-block))
         (legacy-rlp (block-rlp legacy-block))
         (header (make-block-header
                  :base-fee-per-gas 1
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :slot-number 0))
         (block (make-block :header header
                            :withdrawals '()
                            :requests (list #(#x00 #xbb))
                            :block-access-list '()))
         (canonical-rlp (block-rlp block))
         (canonical-object (rlp-decode-one canonical-rlp))
         (canonical-fields (rlp-list-items canonical-object))
         (public-rlp
           (ethereum-lisp.public-api::eth-rpc-block-rlp block)))
    (is (= 3 (length (rlp-list-items (rlp-decode-one legacy-rlp)))))
    (is (= 3
           (length
            (rlp-list-items
             (rlp-decode-one
              (ethereum-lisp.public-api::eth-rpc-block-rlp legacy-block))))))
    (is (not (block-withdrawals-present-p
              (block-from-rlp legacy-rlp))))
    (is (= 4 (length canonical-fields)))
    (is (= 4 (length (rlp-list-items (rlp-decode-one public-rlp)))))
    (is (bytes= canonical-rlp public-rlp))
    (let ((decoded (block-from-rlp canonical-rlp)))
      (is (block-withdrawals-present-p decoded))
      (is (not (block-requests-present-p decoded)))
      (is (not (block-block-access-list-present-p decoded))))
    (signals block-validation-error
      (block-from-rlp
       (rlp-encode
        (apply #'make-rlp-list
               (append canonical-fields (list (make-rlp-list)))))))
    (signals block-validation-error
      (block-from-rlp
       (rlp-encode
        (apply #'make-rlp-list
               (append canonical-fields
                       (list (make-rlp-list) (make-rlp-list)))))))))
