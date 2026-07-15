(in-package #:ethereum-lisp.test)

(deftest blob-message-supplies-blob-environment-to-evm
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000b1"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (base-fee-slot (hash32-from-hex
                         "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (blob-hash-slot (hash32-from-hex
                          "0x0000000000000000000000000000000000000000000000000000000000000002"))
         ;; Store BLOBBASEFEE at slot 1 and BLOBHASH(0) at slot 2.
         (code #(#x4a 96 1 #x55 95 #x49 96 2 #x55 0))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 80000
                       :to contract
                       :max-fee-per-blob-gas 3
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance 2000000))
    (state-db-set-code state contract code)
    (let ((receipt (apply-message state sender transaction
                                  :base-fee 2
                                  :blob-base-fee 3)))
      (is (= 1 (receipt-status receipt)))
      (is (< (receipt-cumulative-gas-used receipt)
             (transaction-gas-limit transaction)))
      (is (= (- 2000000
                (* (receipt-cumulative-gas-used receipt) 3)
                (* +blob-gas-per-blob+ 3))
             (state-account-balance (state-db-get-account state sender))))
      (is (= 3 (state-db-get-storage state contract base-fee-slot)))
      (is (= (bytes-to-integer (hash32-bytes blob-hash))
             (state-db-get-storage state contract blob-hash-slot))))))

(deftest blob-message-rejects-insufficient-balance-for-blob-gas
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas 3
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account
                           :balance (+ (* 21000 10)
                                       (* +blob-gas-per-blob+ 3)
                                       -1)))
    (signals transaction-validation-error
      (apply-message state sender transaction
                     :base-fee 2
                     :blob-base-fee 3))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))))

(deftest blob-message-rejects-contract-creation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (balance 1000000)
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 60000
                       :to nil
                       :data #(96 0 96 0 243)
                       :max-fee-per-blob-gas 3
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals block-validation-error
      (apply-message state sender transaction
                     :base-fee 2
                     :blob-base-fee 3))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))))

(deftest blob-message-rejects-blob-fee-cap-below-blob-base-fee
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas 2
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (signals block-validation-error
      (apply-message state sender transaction
                     :base-fee 2
                     :blob-base-fee 3))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))))

(deftest blob-message-rejects-overwide-blob-fee-cap
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (balance 1000000)
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas (1+ +uint256-max+)
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender transaction
                     :base-fee 2
                     :blob-base-fee 3))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))))

(deftest blob-block-execution-populates-blob-gas-used
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (header (make-block-header :gas-limit 100000
                                    :base-fee-per-gas 2
                                    :excess-blob-gas 2314058))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas 2
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header)
      (is (= 1 (length receipts)))
      (is (= 1 (receipt-status (first receipts))))
      (is (= +blob-gas-per-blob+
             (block-header-blob-gas-used (block-header block))))
      (is (= +blob-gas-per-blob+
             (blob-gas-used (block-transactions block))))
      (is (validate-block-body-roots block))
      (is (= (- 1000000
                (* 21000 3)
                (* +blob-gas-per-blob+ 2))
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest blob-block-execution-uses-osaka-blob-base-fee-fraction
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (header (make-block-header :number 1
                                    :timestamp 10
                                    :gas-limit 100000
                                    :base-fee-per-gas 2
                                    :blob-gas-used +blob-gas-per-blob+
                                    :excess-blob-gas 2314058
                                    :parent-beacon-root (zero-hash32)))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header
                              :chain-config config)
      (is (= 1 (length receipts)))
      (is (= 1 (receipt-status (first receipts))))
      (is (validate-block-body-against-config block config))
      (is (= (- 1000000
                (* 21000 3)
                +blob-gas-per-blob+)
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest blob-block-execution-uses-prague-blob-schedule
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :prague-time 10))
         (header (make-block-header :number 1
                                    :parent-hash (zero-hash32)
                                    :timestamp 10
                                    :gas-limit 100000
                                    :base-fee-per-gas 2
                                    :blob-gas-used +blob-gas-per-blob+
                                    :excess-blob-gas 2314058
                                    :parent-beacon-root (zero-hash32)
                                    :requests-hash (execution-requests-hash
                                                    '())))
         (transaction (make-blob-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 10
                       :gas-limit 21000
                       :to recipient
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash))))
    (install-empty-prague-request-contracts state)
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list transaction)
                              :header header
                              :chain-config config
                              :requests '())
      (is (= 1 (length receipts)))
      (is (= 1 (receipt-status (first receipts))))
      (is (validate-block-body-against-config block config))
      (is (= (- 1000000
                (* 21000 3)
                +blob-gas-per-blob+)
             (state-account-balance
              (state-db-get-account state sender)))))))

(deftest osaka-blob-block-execution-allows-higher-aggregate-blob-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (second-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f3"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (header (make-block-header
                  :number 1
                  :timestamp 10
                  :gas-limit 100000
                  :base-fee-per-gas 2
                  :blob-gas-used (* +osaka-max-blobs-per-block+
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)))
         (first-transaction
           (make-blob-transaction
            :nonce 0
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to first-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes six-hashes))
         (second-transaction
           (make-blob-transaction
            :nonce 1
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to second-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes three-hashes)))
    (state-db-set-account state sender
                          (make-state-account :balance 10000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender
                              (list first-transaction second-transaction)
                              :header header
                              :chain-config config)
      (is (= 2 (length receipts)))
      (is (every (lambda (receipt) (= 1 (receipt-status receipt))) receipts))
      (is (= (* +osaka-max-blobs-per-block+ +blob-gas-per-blob+)
             (block-header-blob-gas-used (block-header block))))
      (is (validate-block-body-against-config block config)))))

(deftest bpo1-blob-block-execution-allows-scheduled-aggregate-blob-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (second-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f3"))
         (third-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f4"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +bpo1-max-blobs-per-block+
                                       (* 2 +max-blobs-per-block+))
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo1-time 10))
         (header (make-block-header
                  :number 1
                  :timestamp 10
                  :gas-limit 100000
                  :base-fee-per-gas 2
                  :blob-gas-used (* +bpo1-max-blobs-per-block+
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)))
         (first-transaction
           (make-blob-transaction
            :nonce 0
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to first-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes six-hashes))
         (second-transaction
           (make-blob-transaction
            :nonce 1
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to second-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes six-hashes))
         (third-transaction
           (make-blob-transaction
            :nonce 2
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to third-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes three-hashes)))
    (state-db-set-account state sender
                          (make-state-account :balance 10000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender
                              (list first-transaction
                                    second-transaction
                                    third-transaction)
                              :header header
                              :chain-config config)
      (is (= 3 (length receipts)))
      (is (every (lambda (receipt) (= 1 (receipt-status receipt))) receipts))
      (is (= (* +bpo1-max-blobs-per-block+ +blob-gas-per-blob+)
             (block-header-blob-gas-used (block-header block))))
      (is (validate-block-body-against-config block config)))))

(deftest bpo3-blob-block-execution-allows-scheduled-aggregate-blob-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (two-hashes (loop repeat (- +bpo3-max-blobs-per-block+
                                     (* 5 +max-blobs-per-block+))
                           collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo3-time 30))
         (header (make-block-header
                  :number 1
                  :timestamp 30
                  :gas-limit 200000
                  :base-fee-per-gas 2
                  :blob-gas-used (* +bpo3-max-blobs-per-block+
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)))
         (transactions
           (append (loop for nonce below 5
                         collect (make-blob-transaction
                                  :nonce nonce
                                  :max-priority-fee-per-gas 1
                                  :max-fee-per-gas 10
                                  :gas-limit 21000
                                  :to recipient
                                  :max-fee-per-blob-gas 1
                                  :blob-versioned-hashes six-hashes))
                   (list (make-blob-transaction
                          :nonce 5
                          :max-priority-fee-per-gas 1
                          :max-fee-per-gas 10
                          :gas-limit 21000
                          :to recipient
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes two-hashes)))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender transactions
                              :header header
                              :chain-config config)
      (is (= 6 (length receipts)))
      (is (every (lambda (receipt) (= 1 (receipt-status receipt))) receipts))
      (is (= (* +bpo3-max-blobs-per-block+ +blob-gas-per-blob+)
             (block-header-blob-gas-used (block-header block))))
      (is (validate-block-body-against-config block config)))))

(deftest custom-blob-schedule-block-execution-uses-configured-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (second-recipient
           (address-from-hex "0x00000000000000000000000000000000000000f3"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (one-hash (list blob-hash))
         (config (make-chain-config
                  :london-block 0
                  :cancun-time 0
                  :custom-blob-schedule
                  (list (make-blob-schedule-entry :timestamp 20
                                                  :target-blobs 5
                                                  :max-blobs 7
                                                  :update-fraction 424242))))
         (header (make-block-header
                  :number 1
                  :timestamp 20
                  :gas-limit 100000
                  :base-fee-per-gas 2
                  :blob-gas-used (* 7 +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)))
         (first-transaction
           (make-blob-transaction
            :nonce 0
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to first-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes six-hashes))
         (second-transaction
           (make-blob-transaction
            :nonce 1
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to second-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes one-hash)))
    (state-db-set-account state sender
                          (make-state-account :balance 10000000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender
                              (list first-transaction second-transaction)
                              :header header
                              :chain-config config)
      (is (= 2 (length receipts)))
      (is (every (lambda (receipt) (= 1 (receipt-status receipt))) receipts))
      (is (= (* 7 +blob-gas-per-blob+)
             (block-header-blob-gas-used (block-header block))))
      (is (validate-block-body-against-config block config)))))

(deftest blob-block-execution-rejects-aggregate-blob-limit-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (second-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (one-hash (list blob-hash))
         (header (make-block-header
                  :number 1
                  :timestamp 10
                  :gas-limit 100000
                  :base-fee-per-gas 2
                  :blob-gas-used (* (1+ +max-blobs-per-block+)
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)))
         (first-transaction
           (make-blob-transaction
            :nonce 0
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to first-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes six-hashes))
         (second-transaction
           (make-blob-transaction
            :nonce 1
            :max-priority-fee-per-gas 1
            :max-fee-per-gas 10
            :gas-limit 21000
            :to second-recipient
            :max-fee-per-blob-gas 1
            :blob-versioned-hashes one-hash)))
    (state-db-set-account state sender
                          (make-state-account :balance 10000000))
    (signals block-validation-error
      (execute-legacy-block state
                            sender
                            (list first-transaction second-transaction)
                            :header header))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (null (state-db-get-account state first-recipient)))
    (is (null (state-db-get-account state second-recipient)))))

(deftest blob-block-execution-rejects-blob-gas-used-mismatch-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (second-recipient (address-from-hex "0x0000000000000000000000000000000000000003"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (header (make-block-header :gas-limit 100000
                                    :base-fee-per-gas 2
                                    :blob-gas-used 0
                                    :excess-blob-gas 2314058))
         (legacy-transaction (make-legacy-transaction
                              :nonce 0
                              :gas-price 3
                              :gas-limit 21000
                              :to first-recipient
                              :value 1))
         (blob-transaction (make-blob-transaction
                            :nonce 1
                            :max-priority-fee-per-gas 1
                            :max-fee-per-gas 10
                            :gas-limit 21000
                            :to second-recipient
                            :max-fee-per-blob-gas 2
                            :blob-versioned-hashes (list blob-hash))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (signals block-validation-error
      (execute-legacy-block state sender
                            (list legacy-transaction blob-transaction)
                            :header header))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 1000000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state first-recipient)))
    (is (null (state-db-get-account state second-recipient)))
    (is (= 0 (block-header-blob-gas-used header)))))
