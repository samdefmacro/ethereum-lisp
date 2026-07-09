(in-package #:ethereum-lisp.test)

(deftest block-execution-supplies-header-environment-to-evm
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000e1"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (prev-randao (hash32-from-hex
                       "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"))
         (header (make-block-header :beneficiary coinbase
                                    :timestamp 12345
                                    :number 99
                                    :gas-limit 300000
                                    :base-fee-per-gas 7
                                    :mix-hash prev-randao))
         (slot-coinbase (hash32-from-hex
                         "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-timestamp (hash32-from-hex
                          "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-number (hash32-from-hex
                       "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (slot-gas-limit (hash32-from-hex
                          "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (slot-base-fee (hash32-from-hex
                         "0x0000000000000000000000000000000000000000000000000000000000000005"))
         (slot-prev-randao (hash32-from-hex
                            "0x0000000000000000000000000000000000000000000000000000000000000006"))
         ;; Store COINBASE, TIMESTAMP, NUMBER, GASLIMIT, BASEFEE, PREVRANDAO.
         (code #(#x41 96 1 #x55
                 #x42 96 2 #x55
                 #x43 96 3 #x55
                 #x45 96 4 #x55
                 #x48 96 5 #x55
                 #x44 96 6 #x55
                 0))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 10
                                               :gas-limit 200000
                                               :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 3000000))
    (state-db-set-code state contract code)
    (execute-legacy-block state sender (list transaction) :header header)
    (is (= (bytes-to-integer (address-bytes coinbase))
           (state-db-get-storage state contract slot-coinbase)))
    (is (= 12345 (state-db-get-storage state contract slot-timestamp)))
    (is (= 99 (state-db-get-storage state contract slot-number)))
    (is (= 300000 (state-db-get-storage state contract slot-gas-limit)))
    (is (= 7 (state-db-get-storage state contract slot-base-fee)))
    (is (= (bytes-to-integer (hash32-bytes prev-randao))
           (state-db-get-storage state contract slot-prev-randao)))))

(deftest pre-merge-block-execution-supplies-difficulty-to-evm
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000e2"))
         (randao-looking-mix-hash
           (hash32-from-hex
            "0x9999999999999999999999999999999999999999999999999999999999999999"))
         (header (make-block-header :number 99
                                    :difficulty 123
                                    :gas-limit 100000
                                    :mix-hash randao-looking-mix-hash))
         (slot-difficulty (hash32-from-hex
                           "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (code #(#x44 96 1 #x55 0))
         (transaction (make-legacy-transaction :nonce 0
                                               :gas-price 1
                                               :gas-limit 50000
                                               :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (state-db-set-code state contract code)
    (execute-legacy-block state sender (list transaction) :header header)
    (is (= 123 (state-db-get-storage state contract slot-difficulty)))))

(deftest dynamic-fee-message-transfer-uses-effective-gas-price
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 300000))
    (let ((receipt (apply-message state sender transaction :base-fee 5)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 300000 (* 21000 8) 5)
             (state-account-balance (state-db-get-account state sender))))
      (is (= 5 (state-account-balance
                (state-db-get-account state recipient)))))))

(deftest dynamic-fee-message-rejects-fee-cap-below-base-fee
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 200000))
    (signals block-validation-error
      (apply-message state sender transaction :base-fee 5))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 200000 (state-account-balance
                   (state-db-get-account state sender))))))

(deftest dynamic-fee-message-rejects-overwide-fee-caps
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (balance 200000)
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas (1+ +uint256-max+)
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender transaction :base-fee 5))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))))

(deftest dynamic-fee-message-requires-balance-for-max-fee-cap
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance (* 21000 6)))
    (signals transaction-validation-error
      (apply-message state sender transaction :base-fee 5))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= (* 21000 6)
           (state-account-balance
            (state-db-get-account state sender))))))

(deftest dynamic-fee-block-execution-pays-priority-fee-to-coinbase
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (header (make-block-header :beneficiary coinbase
                                    :base-fee-per-gas 5
                                    :gas-limit 100000))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 300000))
    (execute-legacy-block state sender (list transaction) :header header)
    (is (= 63000
           (state-account-balance
            (state-db-get-account state coinbase))))
    (is (= (- 300000 (* 21000 8) 5)
           (state-account-balance
            (state-db-get-account state sender))))
    (is (= 5 (state-account-balance
              (state-db-get-account state recipient))))))

(deftest dynamic-fee-simple-transfer-refunds-unused-gas
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (header (make-block-header :beneficiary coinbase
                                    :base-fee-per-gas 5
                                    :gas-limit 100000))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 10
                       :gas-limit 30000
                       :to recipient
                       :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 400000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction) :header header)
      (is (= 21000 (block-header-gas-used (block-header block))))
      (is (= 21000 (receipt-cumulative-gas-used (first receipts))))
      (is (= 63000
             (state-account-balance
              (state-db-get-account state coinbase))))
      (is (= (- 400000 (* 21000 8) 5)
             (state-account-balance
              (state-db-get-account state sender))))
      (is (= 5 (state-account-balance
                (state-db-get-account state recipient)))))))

(deftest dynamic-fee-block-execution-uses-typed-receipt-root
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :base-fee-per-gas 5))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 300000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header)
      (is (= 1 (length receipts)))
      (is (string= (hash32-to-hex
                    (transaction-receipt-list-root
                     (list transaction)
                     receipts))
                   (hash32-to-hex
                    (block-header-receipts-root (block-header block)))))
      (is (not (string= (hash32-to-hex (receipt-list-root receipts))
                        (hash32-to-hex
                         (block-header-receipts-root
                          (block-header block)))))))))

