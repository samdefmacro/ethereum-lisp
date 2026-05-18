(in-package #:ethereum-lisp.test)

(deftest state-empty-root
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (state-db-root-hex (make-state-db)))))

(deftest state-account-root-is-deterministic
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000001")))
    (state-db-set-account state address
                          (make-state-account :nonce 1 :balance 1000))
    (is (state-db-get-account state address))
    (is (string= (state-db-root-hex state) (state-db-root-hex state)))))

(deftest state-storage-roundtrip-and-delete
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000002"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000007")))
    (state-db-set-storage state address slot 99)
    (is (= 99 (state-db-get-storage state address slot)))
    (state-db-set-storage state address slot 0)
    (is (= 0 (state-db-get-storage state address slot)))))

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
