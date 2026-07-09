(in-package #:ethereum-lisp.test)

(deftest legacy-message-revert-rolls-back-callee-effects
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ee"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 42; MSTORE 0 := 7; LOG1; REVERT 0 0.
         (code #(96 42 96 1 85 96 7 96 0 82 96 9 96 32 96 0 161 95 95 253))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 60000
                                      :to contract
                                      :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (< (receipt-cumulative-gas-used receipt)
             (legacy-transaction-gas-limit tx)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 100000 (receipt-cumulative-gas-used receipt))
             (state-account-balance (state-db-get-account state sender))))
      (is (= 0 (state-db-get-storage state contract slot)))
      (is (= 0 (state-account-balance (state-db-get-account state contract))))
      (is (= 0 (length (receipt-logs receipt)))))))

(deftest legacy-message-sstore-clear-applies-eip3529-refund
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000f0"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0.
         (code #(95 96 1 85 0))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 50000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21205 (receipt-cumulative-gas-used receipt)))
      (is (= 0 (state-db-get-storage state contract slot)))
      (is (= 78795
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest legacy-message-sstore-recreate-reverses-clear-refund
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0; SSTORE slot 1 := 9.
         (code #(95 96 1 85 96 9 96 1 85 0))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 70000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 26111 (receipt-cumulative-gas-used receipt)))
      (is (= 9 (state-db-get-storage state contract slot)))
      (is (= 73889
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest legacy-message-sstore-created-slot-clear-applies-reset-refund
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000f3"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 9; SSTORE slot 1 := 0.
         (code #(96 9 96 1 85 95 96 1 85 0))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 70000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 34569 (receipt-cumulative-gas-used receipt)))
      (is (= 0 (state-db-get-storage state contract slot)))
      (is (= 65431
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest legacy-message-sstore-reset-original-nonzero-refunds
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000f4"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 9; SSTORE slot 1 := original 7.
         (code #(96 9 96 1 85 96 7 96 1 85 0))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 70000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 23312 (receipt-cumulative-gas-used receipt)))
      (is (= 7 (state-db-get-storage state contract slot)))
      (is (= 76688
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest legacy-message-revert-discards-sstore-clear-refund
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000f1"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0; REVERT 0 0.
         (code #(95 96 1 85 95 95 253))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 50000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= 26009 (receipt-cumulative-gas-used receipt)))
      (is (= 7 (state-db-get-storage state contract slot)))
      (is (= 73991
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest legacy-message-evm-error-rolls-back-callee-effects
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ef"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21010
                                      :to contract
                                      :value 3)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract #(96 42 96 1 85 0))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= 78990 (state-account-balance (state-db-get-account state sender))))
      (is (= 0 (state-account-balance (state-db-get-account state contract)))))))
