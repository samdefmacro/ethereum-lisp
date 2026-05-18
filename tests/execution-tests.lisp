(in-package #:ethereum-lisp.test)

(deftest state-code-storage-updates-code-hash
  (let ((state (make-state-db))
        (address (address-from-hex "0x00000000000000000000000000000000000000cc"))
        (code #(96 1 96 0 85 0)))
    (state-db-set-code state address code)
    (is (bytes= code (state-db-get-code state address)))
    (is (string= (hash32-to-hex (keccak-256-hash code))
                 (hash32-to-hex (state-db-get-code-hash state address))))))

(deftest message-evm-context-derives-chain-rules-from-config
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :shanghai-time 20
                                    :cancun-time 30
                                    :prague-time 40))
         (tx (make-legacy-transaction :to recipient :value 1))
         (context (ethereum-lisp.execution::make-message-evm-context
                   state sender tx recipient #() 1
                   :chain-config config
                   :block-number 10
                   :timestamp 40))
         (rules (evm-context-chain-rules context)))
    (is (chain-rules-berlin-p rules))
    (is (chain-rules-london-p rules))
    (is (chain-rules-shanghai-p rules))
    (is (chain-rules-cancun-p rules))
    (is (chain-rules-prague-p rules))))

(deftest message-evm-context-prewarms-active-precompiles-by-rules
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (frontier-rules (make-chain-rules :chain-id 1))
         (byzantium-rules (make-chain-rules :chain-id 1 :byzantium-p t))
         (frontier-context
           (ethereum-lisp.execution::make-message-evm-context
            state sender (make-legacy-transaction :to recipient) recipient #() 1
            :chain-rules frontier-rules))
         (byzantium-context
           (ethereum-lisp.execution::make-message-evm-context
            state sender (make-legacy-transaction :to recipient) recipient #() 1
            :chain-rules byzantium-rules))
         (frontier-accesses (evm-context-accessed-addresses frontier-context))
         (byzantium-accesses (evm-context-accessed-addresses byzantium-context)))
    (is (gethash (address-bytes (precompile-address 4)) frontier-accesses))
    (is (not (gethash (address-bytes (precompile-address 5))
                      frontier-accesses)))
    (is (gethash (address-bytes (precompile-address 5))
                 byzantium-accesses))))

(deftest legacy-message-executes-recipient-code-and-logs
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 42; MSTORE 0 := 7; LOG1 topic 9, mem[0:32].
         (code #(96 42 96 1 85 96 7 96 0 82 96 9 96 32 96 0 161 0))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 50000
                                      :to contract
                                      :value 5)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract code)
    (let* ((receipt (apply-legacy-message state sender tx))
           (log (first (receipt-logs receipt))))
      (is (= 1 (receipt-status receipt)))
      (is (= 42 (state-db-get-storage state contract slot)))
      (is (= 5 (state-account-balance (state-db-get-account state contract))))
      (is (= 1 (length (receipt-logs receipt))))
      (is (= 9 (bytes-to-integer
                (hash32-bytes (first (log-entry-topics log))))))
      (is (= 7 (aref (log-entry-data log) 31))))))

(deftest signed-message-recovers-sender-and-applies-transfer
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex "0x3535353535353535353535353535353535353535"))
         (balance 2000000000000000000)
         (value 1000000000000000000)
         (gas-cost (* 21000 20000000000))
         (tx (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value value
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account state sender
                          (make-state-account :nonce 9 :balance balance))
    (let ((receipt (apply-signed-message state tx :expected-chain-id 1)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 10 (state-account-nonce
                 (state-db-get-account state sender))))
      (is (= (- balance gas-cost value)
             (state-account-balance
              (state-db-get-account state sender))))
      (is (= value
             (state-account-balance
              (state-db-get-account state recipient))))))
  (let ((state (make-state-db))
        (sender (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
        (tx (make-legacy-transaction
             :nonce 9
             :gas-price 20000000000
             :gas-limit 21000
             :to (address-from-hex "0x3535353535353535353535353535353535353535")
             :value 1000000000000000000
             :v 37
             :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
             :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account
     state sender
     (make-state-account :nonce 9 :balance 2000000000000000000))
    (signals transaction-validation-error
      (apply-signed-message state tx :expected-chain-id 2))
    (is (= 9 (state-account-nonce
              (state-db-get-account state sender))))))

(deftest legacy-message-zero-value-to-empty-recipient-does-not-create-account
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 30000
                                      :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= 79000
             (state-account-balance (state-db-get-account state sender))))
      (is (null (state-db-get-account state recipient))))))

(deftest legacy-message-self-transfer-preserves-value-balance
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 30000
                                      :to sender
                                      :value 10)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= 79000
             (state-account-balance (state-db-get-account state sender)))))))

(deftest message-rejects-sender-nonce-overflow
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (balance 100000)
         (tx (make-legacy-transaction :nonce (1- (ash 1 64))
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient)))
    (state-db-set-account
     state sender
     (make-state-account :nonce (1- (ash 1 64)) :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= (1- (ash 1 64))
           (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))))

(deftest message-rejects-overwide-transaction-nonce-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (nonce (ash 1 64))
         (balance 100000)
         (tx (make-legacy-transaction :nonce nonce
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 1)))
    (state-db-set-account
     state sender
     (make-state-account :nonce nonce :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= nonce
           (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest message-rejects-overwide-value-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (value (1+ +uint256-max+))
         (balance (+ value 21000))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value value)))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest message-rejects-overwide-gas-limit-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (gas-limit (ash 1 64))
         (balance (+ gas-limit 1))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit gas-limit
                                      :to recipient
                                      :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender tx))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest legacy-message-execution-list-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000dd"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 50000
                                      :to contract)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state contract #(96 1 96 1 85 0))
    (let ((result (execute-legacy-messages state sender (list tx))))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (= 1 (length (execution-result-receipts result)))))))

(deftest signed-message-execution-list-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex "0x3535353535353535353535353535353535353535"))
         (tx (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account
     state sender
     (make-state-account :nonce 9 :balance 2000000000000000000))
    (let ((result (execute-signed-messages state (list tx)
                                           :expected-chain-id 1)))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (= 1 (length (execution-result-receipts result))))
      (is (= 10 (state-account-nonce
                 (state-db-get-account state sender)))))))

(deftest legacy-block-execution-applies-withdrawals-and-header-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 10))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address recipient
                                      :amount 4)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender (list tx)
                              :withdrawals (list withdrawal))
      (let ((header (block-header block)))
        (is (= 1 (length receipts)))
        (is (= 21000 (block-header-gas-used header)))
        (is (string= (hash32-to-hex (state-db-root state))
                     (hash32-to-hex (block-header-state-root header))))
        (is (string= (hash32-to-hex (transaction-list-root (list tx)))
                     (hash32-to-hex (block-header-transactions-root header))))
        (is (string= (hash32-to-hex (receipt-list-root receipts))
                     (hash32-to-hex (block-header-receipts-root header))))
        (is (string= (hash32-to-hex (withdrawal-list-root (list withdrawal)))
                     (hash32-to-hex (block-header-withdrawals-root header))))
        (is (= (+ 10 (* 4 +wei-per-gwei+))
               (state-account-balance
                (state-db-get-account state recipient))))))))

(deftest legacy-block-execution-carries-execution-requests
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (header (make-block-header :gas-limit 50000))
         (requests (list #(#x00) #(#x01 #xaa))))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :requests requests)
      (declare (ignore receipts))
      (is (block-requests-present-p block))
      (is (= 2 (length (block-requests block))))
      (is (string= (hash32-to-hex (execution-requests-hash requests))
                   (hash32-to-hex
                    (block-header-requests-hash (block-header block))))))))

(deftest legacy-block-execution-rejects-transaction-root-mismatch-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000
                                    :transactions-root (zero-hash32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 10)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list tx)
                            :header header))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest legacy-block-execution-rejects-withdrawals-root-mismatch-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000
                                    :withdrawals-root (zero-hash32)))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address recipient
                                      :amount 4)))
    (signals block-validation-error
      (execute-legacy-block state sender '()
                            :header header
                            :withdrawals (list withdrawal)))
    (is (null (state-db-get-account state recipient)))))

(deftest legacy-block-execution-rejects-requests-hash-mismatch-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000
                                    :requests-hash (zero-hash32)))
         (requests (list #(#x01 #xaa)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 10)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list tx)
                            :header header
                            :requests requests))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest legacy-block-execution-rejects-supplied-state-root-mismatch
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000
                                    :state-root (zero-hash32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 10)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list tx)
                            :header header))
    (is (string= (hash32-to-hex (zero-hash32))
                 (hash32-to-hex (block-header-state-root header))))))

(deftest legacy-block-execution-rejects-supplied-gas-used-mismatch
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 50000
                                    :gas-used 1))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 10)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list tx)
                            :header header))
    (is (= 1 (block-header-gas-used header)))))

(deftest dynamic-fee-block-execution-rejects-supplied-legacy-receipts-root
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction (make-dynamic-fee-transaction
                       :nonce 0
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 3
                       :gas-limit 21000
                       :to recipient
                       :value 1))
         (legacy-receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header
                  :gas-limit 50000
                  :base-fee-per-gas 2
                  :receipts-root (receipt-list-root (list legacy-receipt)))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header))
    (is (string= (hash32-to-hex (receipt-list-root (list legacy-receipt)))
                 (hash32-to-hex (block-header-receipts-root header))))))

(deftest signed-block-execution-recovers-sender-and-header-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex "0x3535353535353535353535353535353535353535"))
         (header (make-block-header :gas-limit 50000))
         (tx (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account
     state sender
     (make-state-account :nonce 9 :balance 2000000000000000000))
    (multiple-value-bind (block receipts)
        (execute-signed-block state (list tx)
                              :expected-chain-id 1
                              :header header)
      (let ((header (block-header block)))
        (is (= 1 (length receipts)))
        (is (= 21000 (block-header-gas-used header)))
        (is (= 10 (state-account-nonce
                   (state-db-get-account state sender))))
        (is (string= (hash32-to-hex (state-db-root state))
                     (hash32-to-hex (block-header-state-root header))))
        (is (string= (hash32-to-hex (transaction-list-root (list tx)))
                     (hash32-to-hex (block-header-transactions-root header))))
        (is (string= (hash32-to-hex (transaction-receipt-list-root
                                      (list tx) receipts))
                     (hash32-to-hex (block-header-receipts-root header))))))))

(deftest historical-block-reward-follows-fork-rules
  (is (= 5000000000000000000
         (ethereum-lisp.execution::block-reward-for-rules
          (make-chain-rules :chain-id 1))))
  (is (= 3000000000000000000
         (ethereum-lisp.execution::block-reward-for-rules
          (make-chain-rules :chain-id 1 :byzantium-p t))))
  (is (= 2000000000000000000
         (ethereum-lisp.execution::block-reward-for-rules
          (make-chain-rules :chain-id 1
                            :byzantium-p t
                            :constantinople-p t)))))

(deftest historical-ommer-reward-follows-ethash-formula
  (let ((header (make-block-header :number 10))
        (ommer (make-block-header :number 8)))
    (is (= 1500000000000000000
           (ethereum-lisp.execution::ommer-block-reward
            2000000000000000000
            header
            ommer)))))

(deftest legacy-block-execution-can-apply-historical-block-reward
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (header (make-block-header :beneficiary coinbase
                                    :difficulty 1
                                    :number 12
                                    :gas-limit 100000))
         (rules (make-chain-rules :chain-id 1 :byzantium-p t)))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :chain-rules rules
                              :apply-block-rewards-p t)
      (is (null receipts))
      (is (= 3000000000000000000
             (state-account-balance
              (state-db-get-account state coinbase))))
      (is (string= (hash32-to-hex (state-db-root state))
                   (hash32-to-hex
                    (block-header-state-root (block-header block))))))))

(deftest legacy-block-execution-can-apply-ommer-rewards
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (ommer-beneficiary
           (address-from-hex "0x00000000000000000000000000000000000000dd"))
         (header (make-block-header :beneficiary coinbase
                                    :difficulty 1
                                    :number 10
                                    :gas-limit 100000))
         (ommer (make-block-header :beneficiary ommer-beneficiary
                                   :difficulty 1
                                   :number 8))
         (rules (make-chain-rules :chain-id 1
                                  :byzantium-p t
                                  :constantinople-p t)))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :chain-rules rules
                              :ommers (list ommer)
                              :apply-block-rewards-p t)
      (is (null receipts))
      (is (= 2062500000000000000
             (state-account-balance
              (state-db-get-account state coinbase))))
      (is (= 1500000000000000000
             (state-account-balance
              (state-db-get-account state ommer-beneficiary))))
      (is (string= (hash32-to-hex (ethereum-lisp.core::ommers-hash
                                    (list ommer)))
                   (hash32-to-hex
                    (block-header-ommers-hash (block-header block)))))
      (is (string= (hash32-to-hex (state-db-root state))
                   (hash32-to-hex
                    (block-header-state-root (block-header block))))))))

(deftest post-merge-block-execution-skips-ethash-rewards
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (ommer-beneficiary
           (address-from-hex "0x00000000000000000000000000000000000000dd"))
         (header (make-block-header :beneficiary coinbase
                                    :difficulty 0
                                    :number 10
                                    :gas-limit 100000))
         (ommer (make-block-header :beneficiary ommer-beneficiary
                                   :difficulty 1
                                   :number 8))
         (rules (make-chain-rules :chain-id 1
                                  :byzantium-p t
                                  :constantinople-p t)))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :chain-rules rules
                              :ommers (list ommer)
                              :apply-block-rewards-p t)
      (is (null receipts))
      (is (null (state-db-get-account state coinbase)))
      (is (null (state-db-get-account state ommer-beneficiary)))
      (is (string= (hash32-to-hex (state-db-root state))
                   (hash32-to-hex
                    (block-header-state-root (block-header block))))))))

(deftest block-execution-rejects-cumulative-gas-above-limit
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (header (make-block-header :gas-limit 30000))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to recipient
                                         :value 1))
         (second (make-legacy-transaction :nonce 1
                                          :gas-price 1
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals block-validation-error
      (execute-legacy-block state sender (list first second)
                            :header header))
    (is (= 1 (state-account-nonce (state-db-get-account state sender))))
    (is (= 1 (state-account-balance
              (state-db-get-account state recipient))))))

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
                            :requests (list #())))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

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
    (signals block-validation-error
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

(deftest transaction-prewarms-coinbase-address
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000ae"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         ;; COINBASE; BALANCE.
         (code #(#x41 #x31 #x00))
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 30000
            :to contract)))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-account state coinbase (make-state-account :balance 7))
    (state-db-set-code state contract code)
    (let ((receipt (apply-message state sender transaction
                                  :coinbase coinbase)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21102 (receipt-cumulative-gas-used receipt)))
      (is (= 78898
             (state-account-balance
              (state-db-get-account state sender)))))))

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

(deftest contract-creation-prewarms-coinbase-address
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000cb"))
         ;; COINBASE; BALANCE.
         (transaction
           (make-legacy-transaction
            :gas-price 1
            :gas-limit 60000
            :to nil
            :data #(#x41 #x31))))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (state-db-set-account state coinbase (make-state-account :balance 7))
    (let ((receipt (apply-message state sender transaction
                                  :coinbase coinbase)))
      (is (= 1 (receipt-status receipt)))
      (is (= 53136 (receipt-cumulative-gas-used receipt)))
      (is (= 46864
             (state-account-balance
              (state-db-get-account state sender)))))))

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

(deftest set-code-intrinsic-gas-adds-authorization-cost
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000002"))
         (authorization (make-set-code-authorization
                         :chain-id 1
                         :address address
                         :nonce 0))
         (transaction (make-set-code-transaction
                       :gas-limit 80000
                       :to address
                       :authorization-list
                       (list authorization authorization))))
    (is (= (+ 21000 (* 2 25000))
           (transaction-intrinsic-gas transaction)))))

(deftest set-code-message-requires-nonempty-authorization-list-and-to
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (authorization (make-set-code-authorization
                         :chain-id 1
                         :address recipient
                         :nonce 0)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 50000
                      :to recipient)))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 80000
                      :to nil
                      :authorization-list (list authorization))))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))))

(deftest set-code-message-applies-valid-authorization-delegation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 36800 (receipt-cumulative-gas-used receipt)))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state sender)))
      (is (string= (address-to-hex delegated-address)
                   (address-to-hex
                   (set-code-delegation-target
                    (state-db-get-code state sender))))))))

(deftest set-code-message-does-not-refund-new-authority-account
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 0
            :r #x4e87877b1ceac0f507bd190e5635ceaaf9c8ead07a83a6fc17ebf0b2eca77b2a
            :s #x513a91f278ece01d0ae0adf08d2b035cdcf06d4524177c93a88ab5e0f17be886))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 1 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state authority))))))

(deftest set-code-message-applies-sequential-authorizations-for-same-authority
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (first-delegated-address (address-from-hex
                                   "0x000000000000000000000000000000000000bbbb"))
         (second-delegated-address (address-from-hex
                                    "0x000000000000000000000000000000000000cccc"))
         (first-authorization
           (make-set-code-authorization
            :chain-id 1337
            :address first-delegated-address
            :nonce 0
            :y-parity 0
            :r #x4e87877b1ceac0f507bd190e5635ceaaf9c8ead07a83a6fc17ebf0b2eca77b2a
            :s #x513a91f278ece01d0ae0adf08d2b035cdcf06d4524177c93a88ab5e0f17be886))
         (second-authorization
           (make-set-code-authorization
            :chain-id 1337
            :address second-delegated-address
            :nonce 1
            :y-parity 1
            :r #xb2c581c09af7db2163ec3947a2fbcae978069374873e262d155857e6460a10f0
            :s #x1e21e98a465c88d201a5b9f582bfdc58145eca358dee2e7bb15f335375b3a28c))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 71000
            :to recipient
            :authorization-list (list first-authorization
                                      second-authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 58500 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= (set-code-delegation-code second-delegated-address)
                  (state-db-get-code state authority))))))

(deftest set-code-authorization-persists-when-recipient-reverts
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 50000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state recipient #(95 95 #xfd))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 0 (receipt-status receipt)))
      (is (= 36804 (receipt-cumulative-gas-used receipt)))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state sender))))))

(deftest set-code-message-skips-wrong-chain-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (zerop (length (state-db-get-code state sender)))))))

(deftest set-code-message-skips-nonce-mismatch-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x703c4b2bd70c169f5717101caee543299fc946c7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 1
            :r #x5011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98
            :s #x56c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf61))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 1))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 1 (state-account-nonce
                (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest set-code-message-skips-max-nonce-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce #xffffffffffffffff
            :y-parity 0
            :r #xdf70aeed45ec378d210bc3d5739164187460ed3bb3beaad729eb7d4195d1889a
            :s #x1133f2cc049be60413c177e08e0b1a517bdc0ec3943fed1ad350dd04612437c9))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce #xffffffffffffffff))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= #xffffffffffffffff
             (state-account-nonce
              (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest set-code-message-skips-authority-with-nondelegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x703c4b2bd70c169f5717101caee543299fc946c7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authority-code #(96 0 96 0))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 1
            :r #x5011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98
            :s #x56c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf61))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 0))
    (state-db-set-code state authority authority-code)
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 0 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= authority-code
                  (state-db-get-code state authority))))))

(deftest set-code-message-skips-invalid-zero-address-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (old-delegated-address (address-from-hex
                                 "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address (zero-address)
            :nonce 1
            :y-parity 1
            :r #x167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432d
            :s #x1c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender
                       (set-code-delegation-code old-delegated-address))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code old-delegated-address)
                  (state-db-get-code state sender))))))

(deftest set-code-message-clears-delegation-with-zero-address-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (old-delegated-address (address-from-hex
                                 "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address (zero-address)
            :nonce 1
            :y-parity 1
            :r #x8948ba19b8c3795a0af4c43e5ee7c8d70c435b2972f6c119b6e38d711e20febf
            :s #x5610c3123ed0ecbce774751954cac6ee7cdfb02f76e87b65a6e3528eaee0f4d8))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 1))
    (state-db-set-code state authority
                       (set-code-delegation-code old-delegated-address))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest message-rejects-sender-with-nondelegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender #(0))
    (signals transaction-validation-error
      (apply-message state sender transaction))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))))

(deftest message-allows-sender-with-delegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (target (address-from-hex
                  "0x00000000000000000000000000000000000000aa"))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender (set-code-delegation-code target))
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender)))))))

(deftest delegated-message-executes-target-code-at-delegated-address
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (delegated (address-from-hex
                     "0x00000000000000000000000000000000000000dd"))
         (target (address-from-hex
                  "0x00000000000000000000000000000000000000aa"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; Store ADDRESS at slot 1. Delegated execution should keep ADDRESS
         ;; equal to the originally called account, not the code target.
         (target-code #(#x30 96 1 #x55 0))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 50000
                       :to delegated)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state delegated (set-code-delegation-code target))
    (state-db-set-code state target target-code)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= (bytes-to-integer (address-bytes delegated))
             (state-db-get-storage state delegated slot)))
      (is (= 0 (state-db-get-storage state target slot))))))

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
    (signals block-validation-error
      (apply-message state sender transaction
                     :base-fee 2
                     :blob-base-fee 3))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance (state-db-get-account state sender))))))

(deftest blob-block-execution-populates-blob-gas-used
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
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
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
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
      (is (validate-block-body-against-config block config))
      (is (= (- 1000000
                (* 21000 3)
                +blob-gas-per-blob+)
             (state-account-balance
              (state-db-get-account state sender)))))))

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
