(in-package #:ethereum-lisp.test)

(deftest legacy-message-contract-creation-deploys-code
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
                          (make-state-account :balance 100000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= (+ (transaction-intrinsic-gas tx) 18 200)
             (receipt-cumulative-gas-used receipt)))
      (is (< (receipt-cumulative-gas-used receipt)
             (legacy-transaction-gas-limit tx)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 100000
                (receipt-cumulative-gas-used receipt)
                (legacy-transaction-value tx))
             (state-account-balance (state-db-get-account state sender))))
      (is (= 7 (state-account-balance (state-db-get-account state contract))))
      (is (bytes= #(0) (state-db-get-code state contract))))))

(deftest legacy-message-contract-creation-rejects-storage-not-balance-collisions
  ;; EIP-7610 / EIP-684: only a nonzero nonce, non-empty code, or non-empty
  ;; storage at the target is a collision. A pre-funded (balance-only) target
  ;; is not, so the creating transaction succeeds and retains the balance.
  (let ((sender (address-from-hex
                 "0x0000000000000000000000000000000000000001"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (labels ((contract-address ()
               (make-address
                (subseq
                 (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender) 0)))
                 12 32)))
             (creation-tx ()
               (make-legacy-transaction
                :nonce 0
                :gas-price 1
                :gas-limit 80000
                :to nil
                :data #(96 0 96 0 83 96 1 96 0 243))))
      ;; Balance-only target: the creation succeeds.
      (let* ((state (make-state-db))
             (contract (contract-address)))
        (state-db-set-account state sender (make-state-account :balance 100000))
        (state-db-set-account state contract (make-state-account :balance 1))
        (let ((receipt (apply-legacy-message state sender (creation-tx))))
          (is (= 1 (receipt-status receipt)))
          (is (= 1 (state-account-nonce
                    (state-db-get-account state sender))))
          (is (plusp (length (state-db-get-code state contract))))
          (is (= 1 (state-account-balance
                    (state-db-get-account state contract))))))
      ;; Storage-only target: the creation collides and fails.
      (let* ((state (make-state-db))
             (contract (contract-address)))
        (state-db-set-account state sender (make-state-account :balance 100000))
        (state-db-set-storage state contract slot 2)
        (let ((receipt (apply-legacy-message state sender (creation-tx))))
          (is (= 0 (receipt-status receipt)))
          (is (= 80000 (receipt-cumulative-gas-used receipt)))
          (is (= 1 (state-account-nonce
                    (state-db-get-account state sender))))
          (is (= 2 (state-db-get-storage state contract slot))))))))

(deftest legacy-message-contract-creation-retains-initcode-logs
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         ;; LOG1 topic 42 with empty data, then return one zero runtime byte.
         (initcode #(96 42 95 95 161 95 95 83 96 1 95 243))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 100000
                                      :to nil
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 200000))
    (let* ((receipt (apply-legacy-message state sender tx))
           (log (first (receipt-logs receipt))))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (length (receipt-logs receipt))))
      (is (bytes= (address-bytes contract)
                  (address-bytes (log-entry-address log))))
      (is (= 42 (bytes-to-integer
                 (hash32-bytes (first (log-entry-topics log))))))
      (is (= 0 (length (log-entry-data log))))
      (is (bytes= #(0) (state-db-get-code state contract))))))

(deftest legacy-message-contract-creation-code-deposit-out-of-gas
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
         (template (make-legacy-transaction :nonce 0
                                            :gas-price 1
                                            :gas-limit 0
                                            :to nil
                                            :value 7
                                            :data initcode))
         (gas-limit (+ (transaction-intrinsic-gas template) 15 199))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit gas-limit
                                      :to nil
                                      :value 7
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= gas-limit (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 100000 gas-limit)
             (state-account-balance (state-db-get-account state sender))))
      (is (not (state-db-get-account state contract))))))

(deftest legacy-message-contract-creation-rejects-ef-prefixed-code
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode #(#x60 #xef #x60 0 #x53 #x60 1 #x60 0 #xf3))
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
                          (make-state-account :balance 100000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= 80000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= 20000 (state-account-balance
                    (state-db-get-account state sender))))
      (is (not (state-db-get-account state contract))))))

(deftest legacy-message-contract-creation-allows-ef-prefixed-code-before-london
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode #(#x60 #xef #x60 0 #x53 #x60 1 #x60 0 #xf3))
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
                                      :data initcode))
         (rules (make-chain-rules :chain-id 1
                                  :constantinople-p t
                                  :istanbul-p t)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender tx :chain-rules rules)))
      (is (= 1 (receipt-status receipt)))
      (is (bytes= #(#xef) (state-db-get-code state contract))))))

(deftest legacy-message-contract-creation-invalid-runtime-discards-initcode-logs
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         ;; LOG1 topic 42 with empty data, then return EOF-prefixed runtime code.
         (initcode #(#x60 #x2a #x5f #x5f #xa1 #x60 #xef #x5f #x53
                     #x60 #x01 #x5f #xf3))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 100000
                                      :to nil
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 200000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= 100000 (receipt-cumulative-gas-used receipt)))
      (is (= 0 (length (receipt-logs receipt))))
      (is (not (state-db-get-account state contract))))))

(deftest legacy-message-contract-creation-rejects-oversized-code
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         ;; Return 24577 zero bytes, one byte above the pre-Amsterdam limit.
         (initcode #(#x61 #x60 #x01 #x60 0 #xf3))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 5000000
                                      :to nil
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 10000000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (= 5000000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= 5000000 (state-account-balance
                      (state-db-get-account state sender))))
      (is (not (state-db-get-account state contract))))))

(deftest legacy-message-contract-creation-uses-amsterdam-code-size-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :shanghai-time 0
                                    :amsterdam-time 0))
         (allowed-initcode #(#x61 #x60 #x01 #x60 0 #xf3))
         (oversized-initcode #(#x61 #x80 #x01 #x60 0 #xf3))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (allowed-tx (make-legacy-transaction :nonce 0
                                              :gas-price 1
                                              :gas-limit 6000000
                                              :to nil
                                              :data allowed-initcode))
         (oversized-tx (make-legacy-transaction :nonce 1
                                                :gas-price 1
                                                :gas-limit 8000000
                                                :to nil
                                                :data oversized-initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 20000000))
    (let ((receipt (apply-message state sender allowed-tx
                                  :chain-config config
                                  :timestamp 0)))
      (is (= 1 (receipt-status receipt)))
      (is (= (1+ ethereum-lisp.execution::+max-contract-code-size+)
             (length (state-db-get-code state contract)))))
    (let ((receipt (apply-message state sender oversized-tx
                                  :chain-config config
                                  :timestamp 0)))
      (is (= 0 (receipt-status receipt)))
      (is (= 8000000 (receipt-cumulative-gas-used receipt))))))

(deftest legacy-message-contract-creation-rejects-oversized-initcode
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode (make-byte-vector 49153))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 1000000
                                      :to nil
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 2000000))
    (signals transaction-validation-error
      (apply-legacy-message state sender tx))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 2000000
           (state-account-balance (state-db-get-account state sender))))))

(deftest legacy-message-contract-creation-uses-amsterdam-initcode-size-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :shanghai-time 0
                                    :amsterdam-time 0))
         (allowed-initcode
           (make-byte-vector
            (1+ ethereum-lisp.execution::+max-initcode-size+)))
         (oversized-initcode
           (make-byte-vector
            (1+ ethereum-lisp.execution::+amsterdam-max-initcode-size+)))
         (allowed-tx (make-legacy-transaction :nonce 0
                                              :gas-price 1
                                              :gas-limit 500000
                                              :to nil
                                              :data allowed-initcode))
         (oversized-tx (make-legacy-transaction :nonce 1
                                                :gas-price 1
                                                :gas-limit 1000000
                                                :to nil
                                                :data oversized-initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 2000000))
    (let ((receipt (apply-message state sender allowed-tx
                                  :chain-config config
                                  :timestamp 0)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender)))))
    (signals transaction-validation-error
      (apply-message state sender oversized-tx
                     :chain-config config
                     :timestamp 0))
    (is (= 1 (state-account-nonce (state-db-get-account state sender))))))

(deftest legacy-message-contract-creation-allows-oversized-initcode-before-shanghai
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode (make-byte-vector 49153))
         (rules (make-chain-rules :chain-id 1 :london-p t))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 400000
                                      :to nil
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 800000))
    (let ((receipt (apply-message state sender tx :chain-rules rules)))
      (is (= 1 (receipt-status receipt)))
      (is (= (+ 53000 (* 49153 4))
             (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 800000 (+ 53000 (* 49153 4)))
             (state-account-balance (state-db-get-account state sender)))))))

(deftest legacy-message-contract-creation-revert-rolls-back-contract
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode #(96 99 96 0 82 96 32 96 0 253))
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
                          (make-state-account :balance 100000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (< (receipt-cumulative-gas-used receipt)
             (legacy-transaction-gas-limit tx)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- 100000 (receipt-cumulative-gas-used receipt))
             (state-account-balance (state-db-get-account state sender))))
      (is (not (state-db-get-account state contract))))))

(deftest legacy-message-contract-creation-revert-discards-initcode-logs
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         ;; LOG1 topic 42 with empty data, then revert with empty return data.
         (initcode #(96 42 95 95 161 95 95 253))
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
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-legacy-message state sender tx)))
      (is (= 0 (receipt-status receipt)))
      (is (< (receipt-cumulative-gas-used receipt)
             (legacy-transaction-gas-limit tx)))
      (is (= 0 (length (receipt-logs receipt))))
      (is (not (state-db-get-account state contract))))))

