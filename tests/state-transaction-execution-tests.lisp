(in-package #:ethereum-lisp.test)

(deftest withdrawals-credit-state-balances-in-wei
  (let* ((state (make-state-db))
         (existing (address-from-hex "0x0000000000000000000000000000000000000011"))
         (new (address-from-hex "0x0000000000000000000000000000000000000012"))
         (withdrawals
           (list
            (make-withdrawal :index 0
                             :validator-index 100
                             :address existing
                             :amount 2)
            (make-withdrawal :index 1
                             :validator-index 101
                             :address new
                             :amount 3))))
    (state-db-set-account state existing
                          (make-state-account :nonce 7 :balance 5))
    (apply-withdrawals state withdrawals)
    (is (= (+ 5 (* 2 +wei-per-gwei+))
           (state-account-balance (state-db-get-account state existing))))
    (is (= (* 3 +wei-per-gwei+)
           (state-account-balance (state-db-get-account state new))))
    (is (= 7 (state-account-nonce
              (state-db-get-account state existing))))))

(deftest legacy-transfer-state-transition
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 100)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 57900 (state-account-balance
                    (state-db-get-account state sender))))
      (is (= 100 (state-account-balance
                  (state-db-get-account state recipient)))))))

(deftest legacy-transfer-zero-value-does-not-create-empty-recipient
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 79000 (state-account-balance
                    (state-db-get-account state sender))))
      (is (null (state-db-get-account state recipient))))))

(deftest legacy-transfer-self-transfer-preserves-value-balance
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to sender
                                      :value 100)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 79000 (state-account-balance
                    (state-db-get-account state sender)))))))

(deftest legacy-transfer-validation-errors
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002")))
    (state-db-set-account state sender
                          (make-state-account :nonce 1 :balance 1))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                :to recipient)))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 20000
                                :to recipient)))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 21000
                                :to recipient :value 1)))))

(deftest legacy-transaction-contract-creation-uses-message-executor
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 80000
                                      :to nil
                                      :value 7
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= (+ (transaction-intrinsic-gas tx) 18 200)
             (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= (- 100000
                (receipt-cumulative-gas-used receipt)
                (legacy-transaction-value tx))
             (state-account-balance (state-db-get-account state sender))))
      (is (= 7 (state-account-balance
                (state-db-get-account state contract))))
      (is (bytes= #(0) (state-db-get-code state contract))))))

(deftest legacy-transaction-list-execution-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (txs (list
               (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                        :to recipient :value 10)
               (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 21000
                                        :to recipient :value 20))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((result (execute-legacy-transactions state sender txs)))
      (is (= 2 (length (execution-result-receipts result))))
      (is (= 42000 (receipt-cumulative-gas-used
                    (second (execution-result-receipts result)))))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (= 30 (state-account-balance
                 (state-db-get-account state recipient)))))))

(deftest legacy-transaction-list-executes-contract-creation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (creation (make-legacy-transaction :nonce 0
                                            :gas-price 1
                                            :gas-limit 80000
                                            :to nil
                                            :value 7
                                            :data initcode))
         (transfer (make-legacy-transaction :nonce 1
                                            :gas-price 1
                                            :gas-limit 21000
                                            :to recipient
                                            :value 3))
         (txs (list creation transfer)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 200000))
    (let* ((result (execute-legacy-transactions state sender txs))
           (receipts (execution-result-receipts result)))
      (is (= 2 (length receipts)))
      (is (= (+ (transaction-intrinsic-gas creation) 18 200)
             (receipt-cumulative-gas-used (first receipts))))
      (is (= (+ (receipt-cumulative-gas-used (first receipts))
                (transaction-intrinsic-gas transfer))
             (receipt-cumulative-gas-used (second receipts))))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (bytes= #(0) (state-db-get-code state contract)))
      (is (= 7 (state-account-balance
                (state-db-get-account state contract))))
      (is (= 3 (state-account-balance
                (state-db-get-account state recipient))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender)))))))
