(in-package #:ethereum-lisp.test)

(deftest access-list-intrinsic-gas-adds-address-and-storage-key-costs
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000002"))
         (slot-a (hash32-from-hex
                  "0x000000000000000000000000000000000000000000000000000000000000000a"))
         (slot-b (hash32-from-hex
                  "0x000000000000000000000000000000000000000000000000000000000000000b"))
         (transaction (make-access-list-transaction
                       :gas-limit 30000
                       :to address
                       :data #(1 0)
                       :access-list
                       (list (make-access-list-entry
                              :address address
                              :storage-keys (list slot-a slot-b))))))
    (is (= (+ 21000 16 4 2400 (* 2 1900))
           (transaction-intrinsic-gas transaction)))))

(deftest access-list-message-validates-fields-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (balance 100000)
         (bad-address-tx
           (make-access-list-transaction
            :gas-price 1
            :gas-limit 30000
            :to recipient
            :access-list
            (list (make-access-list-entry :address nil))))
         (bad-slot-tx
           (make-access-list-transaction
            :gas-price 1
            :gas-limit 30000
            :to recipient
            :access-list
            (list (make-access-list-entry
                   :address recipient
                   :storage-keys (list nil))))))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender bad-address-tx))
    (signals transaction-validation-error
      (apply-message state sender bad-slot-tx))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest message-validates-transaction-data-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (balance 100000)
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 30000
                                      :to recipient
                                      :data "not bytes")))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest message-validates-transaction-recipient-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (balance 100000)
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 30000
                                      :to #(0 1 2))))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state sender))))))

(deftest access-list-prewarms-sload-storage-key
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SLOAD slot 1.
         (code #(96 1 84 0))
         (transaction
           (make-access-list-transaction
            :gas-price 1
            :gas-limit 30000
            :to contract
            :access-list
            (list (make-access-list-entry
                   :address contract
                   :storage-keys (list slot))))))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 25403 (receipt-cumulative-gas-used receipt)))
      (is (= 74597
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest access-list-prewarms-sstore-storage-key
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ab"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0.
         (code #(95 96 1 85 0))
         (transaction
           (make-access-list-transaction
            :gas-price 1
            :gas-limit 40000
            :to contract
            :access-list
            (list (make-access-list-entry
                   :address contract
                   :storage-keys (list slot))))))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (state-db-set-storage state contract slot 7)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 23405 (receipt-cumulative-gas-used receipt)))
      (is (= 0 (state-db-get-storage state contract slot)))
      (is (= 76595
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest access-list-prewarms-balance-address
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ac"))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         ;; BALANCE target.
         (code (concat-bytes #(#x73) (address-bytes target) #(#x31 #x00)))
         (transaction
           (make-access-list-transaction
            :gas-price 1
            :gas-limit 30000
            :to contract
            :access-list
            (list (make-access-list-entry :address target)))))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-account state target (make-state-account :balance 7))
    (state-db-set-code state contract code)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 23503 (receipt-cumulative-gas-used receipt)))
      (is (= 76497
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest transaction-prewarms-sender-and-recipient-addresses
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ad"))
         ;; BALANCE sender; BALANCE recipient.
         (code (concat-bytes #(#x73) (address-bytes sender) #(#x31)
                             #(#x73) (address-bytes contract) #(#x31 #x00)))
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 30000
            :to contract)))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21206 (receipt-cumulative-gas-used receipt)))
      (is (= 78794
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest transaction-prewarms-coinbase-address-after-shanghai
  (let* ((sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ae"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (london-rules (make-chain-rules :chain-id 1
                                         :berlin-p t
                                         :london-p t))
         (shanghai-rules (make-chain-rules :chain-id 1
                                           :berlin-p t
                                           :london-p t
                                           :shanghai-p t))
         ;; COINBASE; BALANCE.
         (code #(#x41 #x31 #x00))
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 30000
            :to contract)))
    (flet ((run (rules)
             (let ((state (make-state-db)))
               (state-db-set-account state sender
                                     (make-state-account :balance 100000))
               (state-db-set-account state coinbase
                                     (make-state-account :balance 7))
               (state-db-set-code state contract code)
               (values
                state
                (apply-message state sender transaction
                               :chain-rules rules
                               :coinbase coinbase)))))
      (multiple-value-bind (state receipt) (run london-rules)
        (is (= 1 (receipt-status receipt)))
        (is (= 23602 (receipt-cumulative-gas-used receipt)))
        (is (= 76398
               (state-account-balance
                (state-db-get-account state sender)))))
      (multiple-value-bind (state receipt) (run shanghai-rules)
        (is (= 1 (receipt-status receipt)))
        (is (= 21102 (receipt-cumulative-gas-used receipt)))
        (is (= 78898
               (state-account-balance
                (state-db-get-account state sender))))))))

(deftest contract-creation-prewarms-created-address
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         ;; ADDRESS; BALANCE.
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 60000
            :to nil
            :data #(#x30 #x31))))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 53136 (receipt-cumulative-gas-used receipt)))
      (is (= 46864
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest contract-creation-prewarms-coinbase-address-after-shanghai
  (let* ((sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (london-rules (make-chain-rules :chain-id 1
                                         :berlin-p t
                                         :london-p t))
         (shanghai-rules (make-chain-rules :chain-id 1
                                           :berlin-p t
                                           :london-p t
                                           :shanghai-p t))
         ;; COINBASE; BALANCE.
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 60000
            :to nil
            :data #(#x41 #x31))))
    (flet ((run (rules)
             (let ((state (make-state-db)))
               (state-db-set-account state sender
                                     (make-state-account :balance 100000))
               (state-db-set-account state coinbase
                                     (make-state-account :balance 7))
               (values
                state
                (apply-message state sender transaction
                               :chain-rules rules
                               :coinbase coinbase)))))
      (multiple-value-bind (state receipt) (run london-rules)
        (is (= 1 (receipt-status receipt)))
        (is (= 55634 (receipt-cumulative-gas-used receipt)))
        (is (= 44366
               (state-account-balance
                (state-db-get-account state sender)))))
      (multiple-value-bind (state receipt) (run shanghai-rules)
        (is (= 1 (receipt-status receipt)))
        (is (= 53136 (receipt-cumulative-gas-used receipt)))
        (is (= 46864
               (state-account-balance
                (state-db-get-account state sender))))))))

(deftest contract-creation-intrinsic-gas-adds-initcode-word-cost
  (let ((transaction (make-legacy-transaction :to nil
                                              :data (make-byte-vector 33))))
    (is (= (+ 53000 (* 33 4) (* 2 2))
           (transaction-intrinsic-gas transaction)))))

(deftest contract-creation-intrinsic-gas-can-skip-initcode-word-cost
  (let ((transaction (make-legacy-transaction :to nil
                                              :data (make-byte-vector 33))))
    (is (= (+ 53000 (* 33 4))
           (transaction-intrinsic-gas transaction :eip3860-p nil)))))

