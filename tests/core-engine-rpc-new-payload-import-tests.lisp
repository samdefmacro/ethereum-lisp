(in-package #:ethereum-lisp.test)

(deftest engine-rpc-new-payload-v2-imports-one-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (expected-state (state-db-copy parent-state))
             (child-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash (zero-hash32)
                :number 42
                :gas-limit 50000
                :gas-used 0
                :timestamp 99
                :base-fee-per-gas 100))
             (child-block
               (execute-signed-block
                expected-state
                (list transaction)
                :expected-chain-id 1
                :header child-header
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 27)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= "2.0" (field response "jsonrpc")))
          (is (= 27 (field response "id")))
          (is (string= +payload-status-valid+ (field result "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash child-block)))
          (is (chain-store-state-available-p
               store (block-hash child-block)))
          (is (= 10
                 (chain-store-account-nonce
                  store (block-hash child-block) sender)))
          (is (= 999580000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) sender)))
          (is (= 1000000000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) recipient)))
          (is (= +wei-per-gwei+
                 (chain-store-account-balance
                  store (block-hash child-block) withdrawal-recipient)))
          (is (typep (chain-store-transaction-location
                      store
                      (transaction-hash transaction))
                     'engine-transaction-location))
          (let* ((receipts
                   (chain-store-block-receipts store (block-hash child-block)))
                 (receipt-response
                   (engine-rpc-handle-request
                    (receipt-request 28 (transaction-hash transaction))
                    store config))
                 (receipt (field receipt-response "result"))
                 (receipts-root
                   (block-header-receipts-root (block-header child-block))))
            (is (= 1 (length receipts)))
            (is (string= (hash32-to-hex (receipt-list-root receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (hash32-to-hex
                          (transaction-receipt-list-root
                           (list transaction)
                           receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (quantity-to-hex 0) (field receipt "type")))
            (is (string= (quantity-to-hex 1)
                         (field receipt "status")))))))))

(deftest engine-rpc-new-payload-v2-rolls-back-state-projection-on-bad-commitment
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (bad-logs-bloom ()
             (let ((bloom (make-byte-vector 256)))
               (setf (aref bloom 0) 1)
               bloom)))
    (let* ((config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header)))
        (labels ((child-block ()
                   (execute-signed-block
                    (state-db-copy parent-state)
                    (list transaction)
                    :expected-chain-id 1
                    :header (make-block-header
                             :parent-hash (block-hash parent-block)
                             :beneficiary fee-recipient
                             :mix-hash (zero-hash32)
                             :number 42
                             :gas-limit 50000
                             :gas-used 0
                             :timestamp 99
                             :base-fee-per-gas 100)
                    :chain-config config
                    :withdrawals (list withdrawal)))
                 (check-case (mutate-header expected-error)
                   (let* ((store (make-engine-payload-memory-store))
                          (bad-block (child-block)))
                     (funcall mutate-header (block-header bad-block))
                     (let* ((bad-block-hash (block-hash bad-block))
                            (payload
                              (execution-payload-envelope-execution-payload
                               (block-to-executable-data bad-block)))
                            (request
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 29)
                               (cons "method" "engine_newPayloadV2")
                               (cons
                                "params"
                                (list (engine-rpc-executable-data-object
                                       payload))))))
                       (engine-payload-store-put-block
                        store parent-block :state-available-p t)
                       (commit-state-db-to-chain-store
                        store (block-hash parent-block) parent-state)
                       (let* ((response
                                (engine-rpc-handle-request
                                 request store config
                                 :import-function
                                 #'execute-and-commit-engine-payload))
                              (result (field response "result")))
                         (is (string= +payload-status-invalid+
                                      (field result "status")))
                         (is (string= expected-error
                                      (field result "validationError")))
                         (is (not (chain-store-known-block
                                   store bad-block-hash)))
                         (is (not (chain-store-state-available-p
                                   store bad-block-hash)))
                         (is (not (chain-store-transaction-location
                                   store
                                   (transaction-hash transaction))))
                         (is (= 0
                                (chain-store-account-nonce
                                 store bad-block-hash sender)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash recipient)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash withdrawal-recipient)))
                         (is (= 9
                                (chain-store-account-nonce
                                 store (block-hash parent-block) sender)))
                         (is (= 2000000000000000000
                                (chain-store-account-balance
                                 store (block-hash parent-block) sender))))))))
          (check-case
           (lambda (header)
             (setf (block-header-state-root header) (zero-hash32)))
           "State root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-receipts-root header) (zero-hash32)))
           "Receipts root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-logs-bloom header) (bad-logs-bloom)))
           "Logs bloom mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-gas-used header) 1))
           "Gas used mismatch"))))))

