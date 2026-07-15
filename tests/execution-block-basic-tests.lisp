(in-package #:ethereum-lisp.test)

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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (requests (list #(#x00 #xbb) #(#x01 #xaa)))
         (header
           (make-block-header
            :gas-limit 50000
            :requests-hash (execution-requests-hash requests))))
    (multiple-value-bind (block receipts)
        (execute-legacy-block state sender '()
                              :header header
                              :chain-rules (make-chain-rules)
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))
    (is (string= (hash32-to-hex (zero-hash32))
                 (hash32-to-hex (block-header-state-root header))))))

(deftest legacy-block-execution-rejects-supplied-gas-used-mismatch
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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

(deftest legacy-block-execution-rejects-zero-committed-gas-used
  (let* ((sender
           (address-from-hex
            "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex
            "0x00000000000000000000000000000000000000f2"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (derivation-state (make-state-db))
         (template-header (make-block-header :gas-limit 50000))
         (committed-block nil))
    (state-db-set-account derivation-state sender
                          (make-state-account :balance 100000))
    ;; A zero gas-used header remains a valid local template when no remote
    ;; block-hash commitment is supplied.
    (is (= 0 (block-header-gas-used template-header)))
    (multiple-value-bind (block receipts)
        (execute-legacy-block derivation-state sender (list transaction)
                              :header template-header)
      (is (= 1 (length receipts)))
      (is (= 21000 (block-header-gas-used (block-header block))))
      (setf committed-block block))
    (let* ((candidate-block
             (block-from-rlp (block-rlp committed-block)))
           (candidate-header (block-header candidate-block))
           (committed-block-hash (block-hash committed-block))
           (state (make-state-db)))
      (state-db-set-account state sender
                            (make-state-account :balance 100000))
      (setf (block-header-gas-used candidate-header) 0)
      (let* ((expected-block-hash (block-hash candidate-block))
             (header-rlp-before
               (copy-seq (block-header-rlp candidate-header)))
             (header-hash-before (block-header-hash candidate-header))
             (gas-used-before (block-header-gas-used candidate-header))
             (state-root-before (state-db-root state))
             (sender-before (state-db-get-account state sender))
             (sender-nonce-before (state-account-nonce sender-before))
             (sender-balance-before (state-account-balance sender-before)))
        (is (not (bytes= (hash32-bytes committed-block-hash)
                         (hash32-bytes expected-block-hash))))
        (is (null (state-db-get-account state recipient)))
        (signals block-validation-error
          (execute-legacy-block state sender
                                (block-transactions candidate-block)
                                :header candidate-header
                                :expected-block-hash expected-block-hash))
        (is (= gas-used-before
               (block-header-gas-used candidate-header)))
        (is (bytes= header-rlp-before
                    (block-header-rlp candidate-header)))
        (is (bytes= (hash32-bytes header-hash-before)
                    (hash32-bytes
                     (block-header-hash candidate-header))))
        (is (bytes= (hash32-bytes state-root-before)
                    (hash32-bytes (state-db-root state))))
        (let ((sender-after (state-db-get-account state sender)))
          (is (= sender-nonce-before
                 (state-account-nonce sender-after)))
          (is (= sender-balance-before
                 (state-account-balance sender-after))))
        (is (null (state-db-get-account state recipient)))))))

(deftest block-execution-restores-header-on-execution-phase-failure
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (blob-hash (hash32-from-hex
                     "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (header (make-block-header :gas-limit 100000
                                    :gas-used 1
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
    (signals block-validation-error
      (execute-legacy-block state sender (list transaction)
                            :header header))
    (is (= 1 (block-header-gas-used header)))
    (is (null (block-header-blob-gas-used header)))
    (is (= 2314058 (block-header-excess-blob-gas header)))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 1000000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest dynamic-fee-block-execution-rejects-supplied-legacy-receipts-root
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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

(deftest signed-block-executes-contract-beyond-100000-steps-within-gas
  (let* ((state (make-state-db))
         (sender (fixture-private-key-address 1))
         (contract
           (address-from-hex
            "0x00000000000000000000000000000000000000cc"))
         (header (make-block-header :gas-limit 500000))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction :nonce 0
                                     :gas-price 1
                                     :gas-limit 420000
                                     :to contract)
            1
            1)))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (state-db-set-code state contract (evm-long-loop-code))
    (multiple-value-bind (block receipts)
        (execute-signed-block state (list transaction)
                              :expected-chain-id 1
                              :header header)
      (let ((receipt (first receipts)))
        (is (= 1 (length receipts)))
        (is (= 1 (receipt-status receipt)))
        ;; 21,000 intrinsic gas plus 390,005 exact EVM execution gas.
        (is (= 411005 (receipt-cumulative-gas-used receipt)))
        (is (= 411005 (block-header-gas-used (block-header block))))
        (is (= 1 (state-account-nonce
                  (state-db-get-account state sender))))
        (is (= 588995 (state-account-balance
                       (state-db-get-account state sender))))))))

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
      (is (string= (hash32-to-hex (ethereum-lisp.blocks:ommers-hash
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))
