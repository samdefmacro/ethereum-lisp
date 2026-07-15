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

(defun execution-test-modexp-input ()
  (labels ((fixed32 (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               bytes)))
    (concat-bytes (fixed32 1)
                  (fixed32 1)
                  (fixed32 1)
                  #(2 5 13))))

(deftest direct-message-executes-modexp-precompile-and-charges-gas
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (modexp (precompile-address 5))
         (rules (make-chain-rules :byzantium-p t :berlin-p t))
         (input (execution-test-modexp-input))
         (value 7)
         (initial-balance 1000000)
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 50000
                                      :to modexp
                                      :value value
                                      :data input))
         (intrinsic-gas
           (ethereum-lisp.execution::execution-transaction-intrinsic-gas
            tx rules)))
    (state-db-set-account
     state sender (make-state-account :balance initial-balance))
    (let ((receipt (apply-message state sender tx :chain-rules rules)))
      (is (= 1 (receipt-status receipt)))
      (is (= (+ intrinsic-gas 200)
             (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- initial-balance intrinsic-gas 200 value)
             (state-account-balance (state-db-get-account state sender))))
      (is (= value
             (state-account-balance (state-db-get-account state modexp)))))))

(deftest direct-message-modexp-oog-reverts-value-and-consumes-all-gas
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (modexp (precompile-address 5))
         (rules (make-chain-rules :byzantium-p t :berlin-p t))
         (input (execution-test-modexp-input))
         (value 7)
         (initial-balance 1000000)
         (template (make-legacy-transaction :to modexp :data input))
         (intrinsic-gas
           (ethereum-lisp.execution::execution-transaction-intrinsic-gas
            template rules))
         (gas-limit (+ intrinsic-gas 199))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit gas-limit
                                      :to modexp
                                      :value value
                                      :data input)))
    (state-db-set-account
     state sender (make-state-account :balance initial-balance))
    (let ((receipt (apply-message state sender tx :chain-rules rules)))
      (is (= 0 (receipt-status receipt)))
      (is (= gas-limit (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce (state-db-get-account state sender))))
      (is (= (- initial-balance gas-limit)
             (state-account-balance (state-db-get-account state sender))))
      (is (null (state-db-get-account state modexp))))))

(deftest direct-call-simulation-executes-modexp-and-reports-oog
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (modexp (precompile-address 5))
         (rules (make-chain-rules :byzantium-p t :berlin-p t))
         (input (execution-test-modexp-input))
         (template (make-legacy-transaction :to modexp :data input))
         (intrinsic-gas
           (ethereum-lisp.execution::execution-transaction-intrinsic-gas
            template rules))
         (state-root-before (state-db-root state))
         (success-tx
           (make-legacy-transaction :gas-limit (+ intrinsic-gas 200)
                                    :to modexp
                                    :data input))
         (oog-tx
           (make-legacy-transaction :gas-limit (+ intrinsic-gas 199)
                                    :to modexp
                                    :data input)))
    (multiple-value-bind (status output gas-used)
        (execute-message-call state sender success-tx :chain-rules rules)
      (is (eq :successful status))
      (is (bytes= #(6) output))
      (is (= (+ intrinsic-gas 200) gas-used)))
    (multiple-value-bind (status output gas-used)
        (execute-message-call state sender oog-tx :chain-rules rules)
      (is (eq :failed status))
      (is (zerop (length output)))
      (is (= (+ intrinsic-gas 199) gas-used)))
    (is (string= (hash32-to-hex state-root-before)
                 (hash32-to-hex (state-db-root state))))))

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

(deftest signed-message-list-preflights-signatures-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex "0x3535353535353535353535353535353535353535"))
         (balance 2000000000000000000)
         (valid-tx (make-legacy-transaction
                    :nonce 9
                    :gas-price 20000000000
                    :gas-limit 21000
                    :to recipient
                    :value 1000000000000000000
                    :v 37
                    :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                    :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (invalid-tx (make-legacy-transaction
                      :nonce 10
                      :gas-price 20000000000
                      :gas-limit 21000
                      :to recipient
                      :value 1
                      :v 37
                      :r 0
                      :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account state sender
                          (make-state-account :nonce 9 :balance balance))
    (signals transaction-validation-error
      (apply-signed-message-list state (list valid-tx invalid-tx)
                                 :expected-chain-id 1))
    (is (= 9 (state-account-nonce
              (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest signed-message-list-preflights-sender-code-before-state-mutation
  (let* ((state (make-state-db))
         (first-sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (second-sender
           (address-from-hex "0xecf0824670edaa527366d79662bba5f201333bca"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (balance 2000000000000000000)
         (first (make-legacy-transaction
                 :nonce 9
                 :gas-price 20000000000
                 :gas-limit 21000
                 :to recipient
                 :value 1000000000000000000
                 :v 37
                 :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                 :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (second (make-legacy-transaction
                  :nonce 10
                  :gas-price 20000000000
                  :gas-limit 21000
                  :to recipient
                  :value 1
                  :v 37
                  :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                  :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (state-db-set-account state first-sender
                          (make-state-account :nonce 9 :balance balance))
    (state-db-set-code state second-sender #(0))
    (signals transaction-validation-error
      (apply-signed-message-list state (list first second)
                                 :expected-chain-id 1))
    (is (= 9 (state-account-nonce
              (state-db-get-account state first-sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state first-sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest message-list-preflights-transaction-fields-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (second-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to first-recipient
                                         :value 1))
         (second (make-legacy-transaction :nonce 1
                                          :gas-price 1
                                          :gas-limit 21000
                                          :to second-recipient
                                          :data "not bytes"
                                          :value 1)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals transaction-validation-error
      (apply-message-list state sender (list first second)))
    (is (= 0 (state-account-nonce (state-db-get-account state sender))))
    (is (= 100000
           (state-account-balance (state-db-get-account state sender))))
    (is (null (state-db-get-account state first-recipient)))
    (is (null (state-db-get-account state second-recipient)))))

(deftest message-list-preflights-transaction-scalars-before-state-mutation
  (let* ((sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (second-recipient
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to first-recipient
                                         :value 1))
         (bad-transactions
           (list
            (make-legacy-transaction :nonce (ash 1 64)
                                     :gas-price 1
                                     :gas-limit 21000
                                     :to second-recipient
                                     :value 1)
            (make-legacy-transaction :nonce 1
                                     :gas-price 1
                                     :gas-limit (ash 1 64)
                                     :to second-recipient
                                     :value 1)
            (make-legacy-transaction :nonce 1
                                     :gas-price 1
                                     :gas-limit 21000
                                     :to second-recipient
                                     :value (1+ +uint256-max+))
            (make-dynamic-fee-transaction
             :nonce 1
             :max-priority-fee-per-gas 2
             :max-fee-per-gas 1
             :gas-limit 21000
             :to second-recipient
             :value 1))))
    (dolist (second bad-transactions)
      (let ((state (make-state-db)))
        (state-db-set-account state sender
                              (make-state-account :balance 100000))
        (signals transaction-validation-error
          (apply-message-list state sender (list first second)))
        (is (= 0 (state-account-nonce (state-db-get-account state sender))))
        (is (= 100000
               (state-account-balance (state-db-get-account state sender))))
        (is (null (state-db-get-account state first-recipient)))
        (is (null (state-db-get-account state second-recipient)))))))

(deftest message-list-preflights-transaction-list-shape-before-state-mutation
  (let* ((sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to first-recipient
                                         :value 1)))
    (dolist (transactions (list (vector first)
                                (list first "not a transaction")))
      (let ((state (make-state-db)))
        (state-db-set-account state sender
                              (make-state-account :balance 100000))
        (signals transaction-validation-error
          (apply-message-list state sender transactions))
        (is (= 0 (state-account-nonce (state-db-get-account state sender))))
        (is (= 100000
               (state-account-balance (state-db-get-account state sender))))
        (is (null (state-db-get-account state first-recipient)))))))

(deftest message-list-preflights-transaction-static-gas-before-state-mutation
  (let* ((sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (first-recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (first (make-legacy-transaction :nonce 0
                                         :gas-price 1
                                         :gas-limit 21000
                                         :to first-recipient
                                         :value 1))
         (bad-transactions
           (list
            (make-legacy-transaction :nonce 1
                                     :gas-price 1
                                     :gas-limit 21000
                                     :to first-recipient
                                     :data #(1))
            (make-legacy-transaction :nonce 1
                                     :gas-price 1
                                     :gas-limit 1000000
                                     :to nil
                                     :data (make-byte-vector 49153)))))
    (dolist (second bad-transactions)
      (let ((state (make-state-db)))
        (state-db-set-account state sender
                              (make-state-account :balance 2000000))
        (signals transaction-validation-error
          (apply-message-list state sender (list first second)))
        (is (= 0 (state-account-nonce (state-db-get-account state sender))))
        (is (= 2000000
               (state-account-balance (state-db-get-account state sender))))
        (is (null (state-db-get-account state first-recipient)))))))

(deftest legacy-message-zero-value-to-empty-recipient-does-not-create-account
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000012"))
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
         (sender (address-from-hex "0x00000000000000000000000000000000000000aa"))
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
