(in-package #:ethereum-lisp.test)

(deftest message-execution-rejects-typed-transaction-before-fork
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 10))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (apply-message state sender transaction
                     :chain-config config
                     :block-number 9))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-rejects-typed-transaction-before-fork
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :berlin-block 5))
         (header (make-block-header :number 4 :gas-limit 50000))
         (transaction (make-access-list-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-typed-transaction-forks
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (second-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (config (make-chain-config :berlin-block 5))
         (header (make-block-header :number 4 :gas-limit 50000))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to first-recipient
                                         :value 1))
         (second (make-access-list-transaction :nonce 1
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to second-recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list first second)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state first-recipient)))
    (is (null (state-db-get-account state second-recipient)))))

(deftest block-execution-requires-base-fee-after-london-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0))
         (header (make-block-header :number 1 :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-rejects-base-fee-before-london-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 10))
         (header (make-block-header :number 9
                                    :gas-limit 50000
                                    :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-withdrawals-fork-shape
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (withdrawal-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (config (make-chain-config :london-block 0
                                    :shanghai-time 10))
         (header (make-block-header :timestamp 9 :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address withdrawal-recipient
                                      :amount 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config
                            :withdrawals (list withdrawal)))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))
    (is (null (state-db-get-account state withdrawal-recipient)))))

(deftest block-execution-preflights-withdrawal-fields-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (withdrawal-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (header (make-block-header :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address withdrawal-recipient
                                      :amount (1+ +uint256-max+))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :withdrawals (list withdrawal)))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))
    (is (null (state-db-get-account state withdrawal-recipient)))))

(deftest block-execution-applies-withdrawals-after-selfdestruct-clearing
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (beneficiary
           (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (config (make-chain-config :london-block 0
                                    :shanghai-time 10))
         (header (make-block-header :number 1
                                    :timestamp 10
                                    :gas-limit 100000
                                    :base-fee-per-gas 0))
         ;; CALLDATALOAD 0; SELFDESTRUCT to the address encoded in calldata.
         (code #(96 0 53 #xff))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 80000
                       :to contract
                       :data (concatenate
                              'vector
                              (make-byte-vector 12)
                              (address-bytes beneficiary))))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address contract
                                      :amount 99)))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (state-db-set-code state contract code)
    (state-db-set-account state contract
                          (make-state-account :balance 7
                                              :code-hash
                                              (keccak-256-hash code)))
    (execute-legacy-block state sender (list transaction)
                          :header header
                          :chain-config config
                          :withdrawals (list withdrawal))
    (let ((contract-account (state-db-get-account state contract)))
      (is (= (* 99 +wei-per-gwei+)
             (state-account-balance contract-account)))
      (is (= 0 (state-account-nonce contract-account)))
      (is (zerop (length (state-db-get-code state contract)))))
    (is (= 7 (state-account-balance
              (state-db-get-account state beneficiary))))))

(deftest block-execution-requires-withdrawals-after-shanghai-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0
                                    :shanghai-time 10))
         (header (make-block-header :number 1
                                    :timestamp 10
                                    :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-requests-fork-shape
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0
                                    :prague-time 10))
         (header (make-block-header :timestamp 9 :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1))
         (requests (list #(#x01 #xaa))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config
                            :requests requests))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-execution-request-fields-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :requests (list #(#x00))))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-block-access-list-fork-shape
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10))
         (header (make-block-header :timestamp 9
                                    :gas-limit 50000
                                    :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config
                            :block-access-list '()))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-requires-block-access-list-after-amsterdam-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10))
         (header (make-block-header :timestamp 10
                                    :gas-limit 50000
                                    :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest block-execution-preflights-block-access-list-item-gas-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (read-slot (hash32-from-hex
                     "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (write-slot (hash32-from-hex
                      "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (access-list
           (list (make-block-access-account
                  :address sender
                  :storage-writes
                  (list (make-block-access-slot-writes
                         :slot write-slot
                         :accesses
                         (list (make-block-access-storage-write
                                :tx-index 0
                                :value-after 7))))
                  :storage-reads (list read-slot))))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10))
         (header (make-block-header
                  :timestamp 10
                  :gas-limit (* 2 +block-access-list-item-gas-cost+)
                  :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header
                            :chain-config config
                            :block-access-list access-list))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest legacy-block-execution-carries-empty-block-access-list
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10))
         (header (make-block-header :timestamp 10
                                    :gas-limit 50000
                                    :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header
                              :chain-config config
                              :block-access-list '())
      (is (= 1 (length receipts)))
      (is (block-block-access-list-present-p block))
      (is (null (block-block-access-list block)))
      (is (string= (hash32-to-hex (block-access-list-hash '()))
                   (hash32-to-hex
                    (block-header-block-access-list-hash
                     (block-header block))))))))

(deftest legacy-block-execution-carries-encoded-block-access-list
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000003")))
         (encoded (block-access-list-rlp (list account)))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10))
         (header (make-block-header :timestamp 10
                                    :gas-limit 50000
                                    :base-fee-per-gas 1))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 21000
                                               :to recipient
                                               :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header
                              :chain-config config
                              :block-access-list-rlp encoded)
      (is (= 1 (length receipts)))
      (is (block-block-access-list-present-p block))
      (is (bytes= encoded (block-encoded-block-access-list block)))
      (is (bytes= encoded
                  (block-access-list-rlp (block-block-access-list block))))
      (is (string= (hash32-to-hex (block-access-list-rlp-hash encoded))
                   (hash32-to-hex
                    (block-header-block-access-list-hash
                     (block-header block)))))))
  (let ((encoded (block-access-list-rlp '())))
    (signals block-validation-error
      (execute-legacy-block
       (make-state-db)
       (address-from-hex "0x0000000000000000000000000000000000000001")
       '()
       :block-access-list '()
       :block-access-list-rlp encoded)))
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (account-address
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (encoded
           (rlp-encode
            (make-rlp-list
             (make-rlp-list
              (address-bytes account-address)
              (make-rlp-list)
              (make-rlp-list (ensure-byte-vector '(0)))
              (make-rlp-list)
              (make-rlp-list)
              (make-rlp-list)))))
         (header (make-block-header
                  :timestamp 10
                  :gas-limit 50000
                  :base-fee-per-gas 1
                  :block-access-list-hash (keccak-256-hash encoded)))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 10)))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :chain-config config
                              :block-access-list-rlp encoded)
      (is (null receipts))
      (is (bytes= encoded (block-encoded-block-access-list block)))
      (is (string= (hash32-to-hex (keccak-256-hash encoded))
                   (hash32-to-hex
                    (block-header-block-access-list-hash
                     (block-header block))))))))

(defun eip4788-test-chain-config ()
  (make-chain-config :byzantium-block 0
                     :berlin-block 0
                     :london-block 0
                     :shanghai-time 0
                     :cancun-time 0))

(defun eip4788-test-header (parent-beacon-root)
  (make-block-header :number 1
                     :timestamp 1
                     :gas-limit 100000
                     :base-fee-per-gas 0
                     :blob-gas-used 0
                     :excess-blob-gas 0
                     :parent-beacon-root parent-beacon-root))

(defun eip4788-test-slot (number)
  (hash32-from-hex (format nil "0x~64,'0X" number)))

(deftest cancun-block-processes-parent-beacon-root-before-transactions
  (let* ((state (make-state-db))
         (system-address
           (address-from-hex
            "0xfffffffffffffffffffffffffffffffffffffffe"))
         (beacon-roots-address
           (address-from-hex
            "0x000f3df6d732807ef1319fb7b8bb8522d0beac02"))
         (sender
           (address-from-hex
            "0x0000000000000000000000000000000000000001"))
         (parent-beacon-root
           (hash32-from-hex
            "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (transaction-data
           (hash32-bytes
            (hash32-from-hex
             "0x2222222222222222222222222222222222222222222222222222222222222222")))
         ;; The system branch stores the beacon root and call identity.  The
         ;; ordinary transaction branch overwrites slot zero, proving order.
         (code
           (concat-bytes
            #(#x33 #x73)
            (address-bytes system-address)
            #(#x14 #x60 #x21 #x57
              #x60 #x00 #x35 #x60 #x00 #x55 #x00
              #x5b #x60 #x00 #x35 #x60 #x00 #x55
              #x33 #x60 #x01 #x55
              #x32 #x60 #x02 #x55
              #x34 #x60 #x03 #x55
              #x3a #x60 #x04 #x55 #x00)))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 80000
                                    :to beacon-roots-address
                                    :data transaction-data))
         (header (eip4788-test-header parent-beacon-root)))
    (state-db-set-code state beacon-roots-address code)
    (state-db-set-account state sender (make-state-account :balance 1000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block
         state sender (list transaction)
         :header header
         :withdrawals '())
      (is (= 1 (length receipts)))
      (is (= (bytes-to-integer transaction-data)
             (state-db-get-storage state beacon-roots-address
                                   (eip4788-test-slot 0))))
      (is (= (bytes-to-integer (address-bytes system-address))
             (state-db-get-storage state beacon-roots-address
                                   (eip4788-test-slot 1))))
      (is (= (bytes-to-integer (address-bytes system-address))
             (state-db-get-storage state beacon-roots-address
                                   (eip4788-test-slot 2))))
      (is (zerop (state-db-get-storage state beacon-roots-address
                                       (eip4788-test-slot 3))))
      (is (zerop (state-db-get-storage state beacon-roots-address
                                       (eip4788-test-slot 4))))
      (is (= (receipt-cumulative-gas-used (first receipts))
             (block-header-gas-used (block-header block)))))))

(deftest prague-block-processes-parent-hash-before-transactions
  (let* ((state (make-state-db))
         (history-address
           (address-from-hex
            "0x0000f90827f1c53a10cb7a02335b175320002935"))
         (sender
           (address-from-hex
            "0x0000000000000000000000000000000000000001"))
         (observer
           (address-from-hex
            "0x0000000000000000000000000000000000000002"))
         (parent-hash
           (hash32-from-hex
            "0x4444444444444444444444444444444444444444444444444444444444444444"))
         (history-code
           (hex-to-bytes
            "0x3373fffffffffffffffffffffffffffffffffffffffe14604657602036036042575f35600143038111604257611fff81430311604257611fff9006545f5260205ff35b5f5ffd5b5f35611fff60014303065500"))
         ;; Query block 8192 and persist the returned hash in observer slot zero.
         (observer-code
           (concat-bytes
            #(#x61 #x20 #x00 #x60 #x00 #x52
              #x60 #x20 #x60 #x20 #x60 #x20 #x60 #x00 #x60 #x00 #x73)
            (address-bytes history-address)
            #(#x5a #xf1 #x50 #x60 #x20 #x51 #x60 #x00 #x55 #x00)))
         (config (make-chain-config :byzantium-block 0
                                    :berlin-block 0
                                    :london-block 0
                                    :shanghai-time 0
                                    :cancun-time 0
                                    :prague-time 0))
         (header (make-block-header
                  :parent-hash parent-hash
                  :number 8193
                  :timestamp 1
                  :gas-limit 150000
                  :base-fee-per-gas 0
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :requests-hash (execution-requests-hash '())))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 120000
                                               :to observer)))
    (state-db-set-code state history-address history-code)
    (state-db-set-storage state history-address (eip4788-test-slot 0) 7)
    (state-db-set-storage state history-address (eip4788-test-slot 1) 9)
    (state-db-set-code state observer observer-code)
    (state-db-set-account state sender (make-state-account :balance 1000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header
                              :chain-config config
                              :withdrawals '()
                              :requests '())
      (is (= 1 (length receipts)))
      (is (= 7 (state-db-get-storage state history-address
                                     (eip4788-test-slot 0))))
      (is (= (bytes-to-integer (hash32-bytes parent-hash))
             (state-db-get-storage state history-address
                                   (eip4788-test-slot 1))))
      (is (= (bytes-to-integer (hash32-bytes parent-hash))
             (state-db-get-storage state observer
                                   (eip4788-test-slot 0))))
      (is (= (receipt-cumulative-gas-used (first receipts))
             (block-header-gas-used (block-header block)))))))

(deftest reverted-parent-beacon-root-system-call-does-not-reject-block
  (let* ((state (make-state-db))
         (beacon-roots-address
           (address-from-hex
            "0x000f3df6d732807ef1319fb7b8bb8522d0beac02"))
         (parent-beacon-root
           (hash32-from-hex
            "0x3333333333333333333333333333333333333333333333333333333333333333"))
         (slot (eip4788-test-slot 0))
         ;; Store calldata, then revert the system call frame.
         (code #(#x60 #x00 #x35 #x60 #x00 #x55
                 #x60 #x00 #x60 #x00 #xfd)))
    (state-db-set-code state beacon-roots-address code)
    (state-db-set-storage state beacon-roots-address slot 9)
    (multiple-value-bind (block receipts)
        (execute-legacy-block
         state
         (zero-address)
         '()
         :header (eip4788-test-header parent-beacon-root)
         :chain-config (eip4788-test-chain-config)
         :withdrawals '())
      (is (null receipts))
      (is (zerop (block-header-gas-used (block-header block))))
      (is (= 9 (state-db-get-storage state beacon-roots-address slot))))))
