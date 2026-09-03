(in-package #:ethereum-lisp.test)

(deftest eth-rpc-call-executes-retained-state-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (expected (let ((bytes (make-byte-vector 32)))
                       (setf (aref bytes 31) 7)
                       (bytes-to-hex bytes))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 104)
                      (cons "method" "eth_call")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000))
                                   (cons "data" "0x"))
                             "latest")))
                store
                config))
             (result (field response "result")))
        (is (string= expected result))
        (is (= 0
               (chain-store-account-storage
                store (block-hash block) contract slot)))))))

(deftest eth-rpc-call-default-gas-is-not-block-gas-limited
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :berlin-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cd"))
           ;; SSTORE slot 0 := 1; STOP. This needs more execution gas than the
           ;; block limit leaves after intrinsic gas below.
           (code #(#x60 #x01 #x60 #x00 #x55 #x00))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 22000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "to" (address-to-hex contract)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 161 "eth_call" (list call-object "latest")
                        store config))
             (access-list-response
               (request 162 "eth_createAccessList"
                        (list call-object "latest")
                        store config))
             (access-list-result (field access-list-response "result")))
        (is (string= "0x" (field call-response "result")))
        (is (< (block-header-gas-limit (block-header block))
               (hex-to-quantity (field access-list-result "gasUsed"))))
        (is (= 0
               (chain-store-account-storage
                store
                (block-hash block)
                contract
                (zero-hash32))))))))

(deftest eth-rpc-simulates-contract-creation-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (created-address (sender nonce)
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) nonce)))
               12 32)))
           (address-word-hex (address)
             (let ((bytes (make-byte-vector 32)))
               (replace bytes (address-bytes address) :start1 12)
               (bytes-to-hex bytes)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           ;; MSTORE8 0 := 0; RETURN mem[0:1].
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           ;; ADDRESS; MSTORE 0; RETURN mem[0:32].
           (address-initcode #(#x30 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (contract (created-address sender 0))
           (nonce-contract (created-address sender 7))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (tx (make-legacy-transaction :gas-limit 100000
                                        :to nil
                                        :data initcode))
           (expected-gas
             (+ (transaction-intrinsic-gas tx) 18 200))
           (call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (bytes-to-hex initcode))))
           (nonce-call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "nonce" (quantity-to-hex 7))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (bytes-to-hex address-initcode)))))
      (state-db-set-account state sender
                            (make-state-account :nonce 0
                                                :balance 1000000))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 140 "eth_call" (list call-object "latest")
                        store config))
             (estimate-response
               (request 141 "eth_estimateGas" (list call-object "latest")
                        store config))
             (access-list-response
               (request 142 "eth_createAccessList" (list call-object "latest")
                        store config))
             (code-response
               (request 143 "eth_getCode"
                        (list (address-to-hex contract) "latest")
                        store config))
             (nonce-call-response
               (request 144 "eth_call" (list nonce-call-object "latest")
                        store config))
             (nonce-code-response
               (request 145 "eth_getCode"
                        (list (address-to-hex nonce-contract) "latest")
                        store config))
             (access-list-result (field access-list-response "result")))
        (is (string= "0x00" (field call-response "result")))
        (is (string= (address-word-hex nonce-contract)
                     (field nonce-call-response "result")))
        (is (string= (quantity-to-hex expected-gas)
                     (field estimate-response "result")))
        (is (string= (quantity-to-hex expected-gas)
                     (field access-list-result "gasUsed")))
        (is (string= "0x" (field code-response "result")))
        (is (string= "0x" (field nonce-code-response "result")))))))

(deftest eth-rpc-simulates-call-value-transfer-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (bytes-to-hex
              (ethereum-lisp.crypto::integer-to-fixed-bytes value 32)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (recipient
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (contract
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) 0)))
               12 32)))
           ;; CALLER BALANCE; MSTORE 0; RETURN mem[0:32].
           (balance-code #(51 49 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "to" (address-to-hex recipient))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 42))))
           (create-object
             (list (cons "from" (address-to-hex sender))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 42))
                   (cons "data" (bytes-to-hex balance-code))))
           (overdraft-object
             (list (cons "from" (address-to-hex sender))
                   (cons "to" (address-to-hex recipient))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 1001)))))
      (state-db-set-account state sender
                            (make-state-account :nonce 0
                                                :balance 1000))
      (state-db-set-code state recipient balance-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 144 "eth_call" (list call-object "latest")
                        store config))
             (create-response
               (request 145 "eth_call" (list create-object "latest")
                        store config))
             (sender-balance-response
               (request 146 "eth_getBalance"
                        (list (address-to-hex sender) "latest")
                        store config))
             (recipient-balance-response
               (request 147 "eth_getBalance"
                        (list (address-to-hex recipient) "latest")
                        store config))
             (contract-balance-response
               (request 148 "eth_getBalance"
                        (list (address-to-hex contract) "latest")
                        store config))
             (overdraft-response
               (request 149 "eth_estimateGas"
                        (list overdraft-object "latest")
                        store config)))
        (is (string= (word-hex 958) (field call-response "result")))
        (is (string= (word-hex 958) (field create-response "result")))
        (is (string= (quantity-to-hex 1000)
                     (field sender-balance-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field recipient-balance-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field contract-balance-response "result")))
        (is (= -32602
               (field (field overdraft-response "error") "code")))))))

(deftest eth-rpc-estimate-gas-uses-fork-intrinsic-gas
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (tx (make-legacy-transaction :gas-limit 100000 :to nil))
           (call-object
             (list (cons "gas" (quantity-to-hex 100000)))))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let ((response
              (engine-rpc-handle-request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 150)
                     (cons "method" "eth_estimateGas")
                     (cons "params" (list call-object "latest")))
               store
               config)))
        (is (string= (quantity-to-hex
                      (transaction-intrinsic-gas tx :eip3860-p nil))
                     (field response "result")))))))

(deftest eth-rpc-call-object-access-list-warms-retained-simulation
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" "eth_estimateGas")
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :berlin-block 0
                                      :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (target
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           ;; PUSH20 target; BALANCE; POP; STOP.
           (code (concat-bytes #(#x73) (address-bytes target)
                               #(#x31 #x50 #x00)))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (access-list
             (list
              (list
               (cons "address" (address-to-hex target))
               (cons "storageKeys" '()))))
           (access-list-transaction
             (make-access-list-transaction
              :chain-id 1
              :gas-limit 100000
              :to contract
              :access-list
              (list (make-access-list-entry :address target))))
           (expected-gas
             (+ (transaction-intrinsic-gas access-list-transaction)
                105))
           (access-list-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex expected-gas))
                   (cons "accessList" access-list)))
           (cold-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex expected-gas)))))
      (state-db-set-code state contract code)
      (state-db-set-account state target (make-state-account :balance 11))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((access-list-response
               (request 152 (list access-list-call "latest") store config))
             (cold-response
               (request 153 (list cold-call "latest") store config))
             (cold-error (field cold-response "error")))
        (is (string= (quantity-to-hex expected-gas)
                     (field access-list-response "result")))
        (is (= -32602 (field cold-error "code")))
        (is (string= "eth_estimateGas execution reverted or exceeded gas cap"
                     (field cold-error "message")))))))

(deftest eth-rpc-call-object-dynamic-fee-uses-effective-gas-price
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes)))
           (call (id call-object store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" "eth_call")
                    (cons "params" (list call-object "latest")))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (basefee-contract
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; GASPRICE; MSTORE 0; RETURN 32 bytes.
           (code #(#x3a #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           ;; BASEFEE; MSTORE 0; RETURN 32 bytes.
           (basefee-code #(#x48 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 10
                       :state-root (state-db-root state))))
           (dynamic-call
             (list (cons "to" (address-to-hex contract))
                   (cons "chainId" (quantity-to-hex 1))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxFeePerGas" (quantity-to-hex 11))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (low-gas-price-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "gasPrice" (quantity-to-hex 7))))
           (priority-only-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (zero-price-basefee-call
             (list (cons "to" (address-to-hex basefee-contract))
                   (cons "gas" (quantity-to-hex 100000))))
           (dynamic-basefee-call
             (list (cons "to" (address-to-hex basefee-contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxFeePerGas" (quantity-to-hex 11))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (mixed-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "gasPrice" (quantity-to-hex 7))
                   (cons "maxFeePerGas" (quantity-to-hex 11))))
           (wrong-chain-call
             (list (cons "to" (address-to-hex contract))
                   (cons "chainId" (quantity-to-hex 2))
                   (cons "gas" (quantity-to-hex 100000)))))
      (state-db-set-code state contract code)
      (state-db-set-code state basefee-contract basefee-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((dynamic-response (call 154 dynamic-call store config))
             (low-gas-price-response (call 155 low-gas-price-call store config))
             (priority-only-response (call 156 priority-only-call store config))
             (zero-price-basefee-response
               (call 157 zero-price-basefee-call store config))
             (dynamic-basefee-response
               (call 158 dynamic-basefee-call store config))
             (mixed-response (call 159 mixed-call store config))
             (wrong-chain-response (call 160 wrong-chain-call store config))
             (mixed-error (field mixed-response "error"))
             (wrong-chain-error (field wrong-chain-response "error")))
        (is (string= (word-hex 11) (field dynamic-response "result")))
        (is (string= (word-hex 7) (field low-gas-price-response "result")))
        (is (string= (word-hex 0) (field priority-only-response "result")))
        (is (string= (word-hex 0) (field zero-price-basefee-response "result")))
        (is (string= (word-hex 10) (field dynamic-basefee-response "result")))
        (is (= -32602 (field mixed-error "code")))
        (is (string=
             "eth_call cannot specify gasPrice with maxFeePerGas or maxPriorityFeePerGas"
             (field mixed-error "message")))
        (is (= -32602 (field wrong-chain-error "code")))
        (is (string= "eth_call chainId does not match configured chain id"
                     (field wrong-chain-error "message")))))))

(deftest eth-rpc-call-object-input-precedes-data
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           ;; CALLDATALOAD 0; MSTORE 0; RETURN 32 bytes.
           (code #(#x60 #x00 #x35 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (word-hex 1))
                   (cons "input" (word-hex 2)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let ((response
              (engine-rpc-handle-request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 157)
                     (cons "method" "eth_call")
                     (cons "params" (list call-object "latest")))
               store
               config)))
        (is (string= (word-hex 2) (field response "result")))))))

(deftest eth-rpc-call-rejects-non-revert-execution-failure
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           ;; SSTORE slot 1 := 42; STOP. With only 1000 execution gas after
           ;; intrinsic gas, this fails as out-of-gas rather than REVERT.
           (code #(96 42 96 1 85 0))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 22000)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 151)
                      (cons "method" "eth_call")
                      (cons "params" (list call-object "latest")))
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code")))
        (is (string= "eth_call execution failed"
                     (field error "message")))))))

(deftest eth-rpc-state-methods-support-block-identifier-objects
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes)))
           (state-with-contract (contract balance return-value)
             (let ((state (make-state-db)))
               (state-db-set-account
                state
                contract
                (make-state-account :balance balance))
               (state-db-set-code
                state
                contract
                (vector #x60 return-value #x60 #x00 #x52
                        #x60 #x20 #x60 #x00 #xf3))
               state))
           (state-block (parent number timestamp state)
             (make-block
              :header (make-block-header
                       :parent-hash (and parent (block-hash parent))
                       :number number
                       :timestamp timestamp
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x0000000000000000000000000000000000000e19"))
           (genesis-state (make-state-db))
           (genesis (state-block nil 0 0 genesis-state))
           (canonical-state (state-with-contract contract 11 1))
           (side-state (state-with-contract contract 22 2))
           (canonical-block (state-block genesis 1 12 canonical-state))
           (side-block (state-block genesis 1 24 side-state))
           (side-selector
             (list (cons "blockHash" (hash32-to-hex (block-hash side-block)))))
           (side-canonical-selector
             (list (cons "blockHash" (hash32-to-hex (block-hash side-block)))
                   (cons "requireCanonical" t)))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000)))))
      (dolist (block (list genesis canonical-block side-block))
        (chain-store-put-block store block :state-available-p t))
      (commit-state-db-to-chain-store store (block-hash genesis) genesis-state)
      (commit-state-db-to-chain-store
       store
       (block-hash canonical-block)
       canonical-state)
      (commit-state-db-to-chain-store store (block-hash side-block) side-state)
      (chain-store-set-canonical-head store (block-hash canonical-block))
      (let* ((latest-balance-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 131)
                      (cons "method" "eth_getBalance")
                      (cons "params" (list (address-to-hex contract) "latest")))
                store
                config))
             (side-balance-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 132)
                      (cons "method" "eth_getBalance")
                      (cons "params"
                            (list (address-to-hex contract) side-selector)))
                store
                config))
             (side-call-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 133)
                      (cons "method" "eth_call")
                      (cons "params" (list call-object side-selector)))
                store
                config))
             (side-require-canonical-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 134)
                      (cons "method" "eth_getBalance")
                      (cons "params"
                            (list (address-to-hex contract)
                                  side-canonical-selector)))
                store
                config))
             (side-require-canonical-error
               (field side-require-canonical-response "error")))
        (is (string= (quantity-to-hex 11)
                     (field latest-balance-response "result")))
        (is (string= (quantity-to-hex 22)
                     (field side-balance-response "result")))
        (is (string= (word-hex 2)
                     (field side-call-response "result")))
        (is (= -32602 (field side-require-canonical-error "code")))
        (is (string= "eth_getBalance block hash is not canonical"
                     (field side-require-canonical-error "message")))))))

(deftest eth-rpc-estimate-gas-binary-searches-retained-state-call
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (hex-quantity-integer (value)
             (parse-integer (subseq value 2) :radix 16)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (reverter
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (revert-code #(96 0 96 0 253))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-code state reverter revert-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((transfer-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 105)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex recipient)))
                             "latest")))
                store
                config))
             (contract-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 106)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (revert-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 107)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex reverter))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (contract-estimate
               (hex-quantity-integer (field contract-response "result"))))
        (is (string= (quantity-to-hex 21000)
                     (field transfer-response "result")))
        (is (> contract-estimate 21000))
        (is (<= contract-estimate 100000))
        (is (= -32602
               (field (field revert-response "error") "code")))))))

(deftest eth-rpc-create-access-list-reports-touched-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (entry-for (access-list address)
             (find (address-to-hex address)
                   access-list
                   :test #'string=
                   :key (lambda (entry) (field entry "address")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (target
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SLOAD slot 1; BALANCE target; STOP.
           (code (concat-bytes #(#x60 #x01 #x54 #x73)
                               (address-bytes target)
                               #(#x31 #x00)))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 32
                       :timestamp 320
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-storage state contract slot 7)
      (state-db-set-account state target (make-state-account :balance 11))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 108)
                      (cons "method" "eth_createAccessList")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (result (field response "result"))
             (access-list (field result "accessList"))
             (contract-entry (entry-for access-list contract))
             (target-entry (entry-for access-list target)))
        (is (stringp (field result "gasUsed")))
        (is (= 2 (length access-list)))
        (is (string= (hash32-to-hex slot)
                     (first (field contract-entry "storageKeys"))))
        ;; A touched account with no accessed slots reports an empty array,
        ;; the way go-ethereum does, not null.
        (is (equalp #() (field target-entry "storageKeys")))))))

(deftest eth-rpc-create-access-list-reports-revert-in-result
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :london-block 0))
           (contract
             (address-from-hex
              "0x00000000000000000000000000000000000000ce"))
           ;; PUSH1 0; PUSH1 0; REVERT.
           (code #(#x60 #x00 #x60 #x00 #xfd))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 33
                       :timestamp 330
                       :gas-limit 100000
                       :base-fee-per-gas 0))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 109)
                 (cons "method" "eth_createAccessList")
                 (cons "params"
                       (list
                        (list (cons "to" (address-to-hex contract))
                              (cons "gas" (quantity-to-hex 100000)))
                        "latest")))
                store config))
             (result (field response "result")))
        (is (null (field response "error")))
        (is (string= "execution reverted" (field result "error")))
        (is (stringp (field result "gasUsed")))
        (is (field result "accessList"))))))

(deftest eth-rpc-simulation-methods-require-retained-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id method)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" method)
                   (cons "params"
                         (list
                          (list
                           (cons "to"
                                 "0x00000000000000000000000000000000000000cc"))
                          "latest"))))
           (assert-state-error (response method)
             (let ((error (field response "error")))
               (is (= -32602 (field error "code")))
               (is (string= (format nil "~A state is not available" method)
                            (field error "message"))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (block
             (make-block
              :header (make-block-header
                       :number 33
                       :timestamp 330
                       :gas-limit 100000
                       :base-fee-per-gas 0))))
      (engine-payload-store-put-block store block)
      (assert-state-error
       (engine-rpc-handle-request (request 109 "eth_call") store config)
       "eth_call")
      (assert-state-error
       (engine-rpc-handle-request (request 110 "eth_estimateGas") store config)
       "eth_estimateGas")
      (assert-state-error
       (engine-rpc-handle-request
        (request 111 "eth_createAccessList") store config)
       "eth_createAccessList"))))


(deftest eth-rpc-call-reports-revert-as-an-error-with-data
  ;; go-ethereum returns a reverted call as JSON-RPC error code 3 carrying the
  ;; revert bytes in the data member. Returning them as a successful result
  ;; makes clients decode revert data as a return value.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           ;; REVERT is gated on Byzantium, and fork blocks are not implied by
           ;; later ones, so it must be activated explicitly.
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; MSTORE 0 := 7; REVERT mem[0:32].
           (code #(96 7 96 0 82 96 32 96 0 253))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 210)
                      (cons "method" "eth_call")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000))
                                   (cons "data" "0x"))
                             "latest")))
                store
                config))
             (error-object (field response "error")))
      ;; A revert is an error, never a result.
      (is (null (field response "result")))
      (is error-object)
      (is (= 3 (field error-object "code")))
      (is (string= "execution reverted" (field error-object "message")))
      ;; The revert bytes travel in the data member.
      (let ((expected (let ((bytes (make-byte-vector 32)))
                        (setf (aref bytes 31) 7)
                        (bytes-to-hex bytes))))
        (is (string= expected (field error-object "data"))))))))

(deftest eth-rpc-revert-reason-decoding
  (let* ((padded-boom (concatenate 'string "626f6f6d" (make-string 56 :initial-element #\0)))
         (error-string-payload
           (hex-to-bytes
            (concatenate
             'string
             "0x08c379a0"
             "0000000000000000000000000000000000000000000000000000000000000020"
             "0000000000000000000000000000000000000000000000000000000000000004"
             padded-boom))))
    ;; A canonical Error(string) payload decodes.
    (is (string= "boom"
                 (ethereum-lisp.public-api::eth-rpc-decode-revert-reason
                  error-string-payload)))
    ;; Anything else yields NIL rather than a guess.
    (is (null (ethereum-lisp.public-api::eth-rpc-decode-revert-reason
               (make-byte-vector 32))))
    (is (null (ethereum-lisp.public-api::eth-rpc-decode-revert-reason
               (make-byte-vector 0))))
    ;; A custom error selector is not Error(string).
    (is (null (ethereum-lisp.public-api::eth-rpc-decode-revert-reason
               (hex-to-bytes "0xdeadbeef"))))
    ;; revert("") is a well-formed 68-byte payload and decodes to the empty
    ;; string, matching go-ethereum's "execution reverted: ".
    (let ((empty-reason
            (hex-to-bytes
             (concatenate
              'string
              "0x08c379a0"
              "0000000000000000000000000000000000000000000000000000000000000020"
              "0000000000000000000000000000000000000000000000000000000000000000"))))
      (is (= 68 (length empty-reason)))
      (is (string= ""
                   (ethereum-lisp.public-api::eth-rpc-decode-revert-reason
                    empty-reason))))))

(deftest eth-rpc-fee-history-next-blob-base-fee-applies-eip7918
  ;; The next block's blob base fee is derived from this header as parent, so
  ;; past Osaka it must include the EIP-7918 reserve price. Omitting it reported
  ;; a lower, stale fee. Values chosen so the reserve price actually fires.
  (let* ((config (make-chain-config :chain-id 1
                                    :london-block 0
                                    :cancun-time 0
                                    :prague-time 0
                                    :osaka-time 0))
         (header (make-block-header
                  :number 100
                  :timestamp 1000
                  :gas-limit 30000000
                  :base-fee-per-gas 81
                  :blob-gas-used +blob-gas-per-blob+
                  :excess-blob-gas 8250000)))
    (multiple-value-bind (target max update-fraction)
        (ethereum-lisp.public-api::eth-rpc-fee-history-blob-schedule header config)
      (let ((with-7918
              (blob-base-fee
               (expected-excess-blob-gas header
                                         :target-blob-gas target
                                         :max-blob-gas max
                                         :eip7918-p t
                                         :update-fraction update-fraction)
               :update-fraction update-fraction))
            (without-7918
              (blob-base-fee
               (expected-excess-blob-gas header
                                         :target-blob-gas target
                                         :max-blob-gas max
                                         :eip7918-p nil
                                         :update-fraction update-fraction)
               :update-fraction update-fraction)))
        ;; The reserve price must actually change the answer, or the test is empty.
        (is (/= with-7918 without-7918))
        (is (string= (quantity-to-hex with-7918)
                     (ethereum-lisp.public-api::eth-rpc-fee-history-next-blob-base-fee
                      header config)))))))

(deftest eth-rpc-empty-collections-encode-as-json-arrays
  ;; An empty list is NIL in Lisp and would otherwise serialise as null, which
  ;; breaks clients expecting "logs": [] and "topics": [] on every plain
  ;; transfer receipt.
  (is (string= "[]" (json-encode (ethereum-lisp.public-api::eth-rpc-json-array '()))))
  (is (string= "[]" (json-encode (ethereum-lisp.public-api::eth-rpc-json-array nil))))
  (is (string= "null" (json-encode nil))))

(deftest debug-get-raw-methods-return-canonical-encodings
  ;; debug_getRaw* must return exactly the bytes that were hashed and gossiped,
  ;; so a decode of the result reproduces the stored object.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (call (method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 900)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block (make-block
                   :header (make-block-header
                            :number 5
                            :timestamp 50
                            :gas-limit 30000000
                            :base-fee-per-gas 7
                            :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (let* ((number (quantity-to-hex (block-header-number (block-header block))))
             (raw-header (field (call "debug_getRawHeader" (list number) store config)
                                "result"))
             (raw-block (field (call "debug_getRawBlock" (list number) store config)
                               "result"))
             (raw-receipts (field (call "debug_getRawReceipts" (list number) store config)
                                  "result")))
        ;; The header encoding decodes back to the same header hash.
        (is (stringp raw-header))
        (is (bytes= (block-header-rlp (block-header block))
                    (hex-to-bytes raw-header)))
        (is (string= (hash32-to-hex (block-header-hash (block-header block)))
                     (hash32-to-hex
                      (block-header-hash
                       (block-header-from-rlp (hex-to-bytes raw-header))))))
        ;; The block encoding decodes back to the same block hash.
        (is (stringp raw-block))
        (is (string= (hash32-to-hex (block-hash block))
                     (hash32-to-hex
                      (block-hash (block-from-rlp (hex-to-bytes raw-block))))))
        ;; A block with no receipts reports an empty array, never null.
        (is (zerop (length raw-receipts)))
        (is (string= "[]" (json-encode raw-receipts))))
      ;; Addressing the same block by hash agrees with addressing it by number.
      (let ((by-number (field (call "debug_getRawHeader"
                                    (list (quantity-to-hex 5)) store config)
                              "result"))
            (by-hash (field (call "debug_getRawHeader"
                                  (list (hash32-to-hex (block-hash block)))
                                  store config)
                            "result")))
        (is (string= by-number by-hash))))))

(deftest debug-get-raw-transaction-rejects-unprefixed-hash
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":901,\"method\":\"debug_getRawTransaction\",\"params\":[\"1000000000000000000000000000000000000000000000000000000000000001\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest debug-namespace-is-advertised-and-gateable
  ;; rpc_modules must list debug, and --http.api must be able to withhold it.
  (let ((modules (ethereum-lisp.public-api::engine-rpc-handle-rpc-modules
                   nil #'ethereum-lisp.engine-api:engine-rpc-public-method-p)))
    (is (assoc "debug" modules :test #'string=)))
  (is (ethereum-lisp.engine-api:engine-rpc-public-method-p "debug_getRawHeader"))
  (let ((default
          (ethereum-lisp.cli::devnet-cli-public-api-method-filter nil)))
    (is (not (funcall default "debug_getRawHeader"))))
  (let ((eth-only (ethereum-lisp.cli::devnet-cli-public-api-method-filter (list "eth"))))
    (is (funcall eth-only "eth_chainId"))
    (is (not (funcall eth-only "debug_getRawHeader"))))
  (let ((with-debug (ethereum-lisp.cli::devnet-cli-public-api-method-filter (list "eth" "debug"))))
    (is (funcall with-debug "debug_getRawHeader"))))

(deftest eth-rpc-estimate-gas-reports-revert-like-eth-call
  ;; A reverting estimate must carry the same error shape as eth_call, so
  ;; callers can decode the reason rather than seeing an opaque failure.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000de"))
           ;; MSTORE 0 := 9; REVERT mem[0:32].
           (code #(96 9 96 0 82 96 32 96 0 253))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 40
                       :timestamp 400
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 311)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list (list (cons "to" (address-to-hex contract))
                                        (cons "gas" (quantity-to-hex 100000))
                                        (cons "data" "0x"))
                                  "latest")))
                store
                config))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is error-object)
        (is (= 3 (field error-object "code")))
        (is (string= "execution reverted" (field error-object "message")))
        (let ((expected (let ((bytes (make-byte-vector 32)))
                          (setf (aref bytes 31) 9)
                          (bytes-to-hex bytes))))
          (is (string= expected (field error-object "data"))))))))

(deftest eth-rpc-call-applies-state-and-block-overrides
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex
              "0x00000000000000000000000000000000000000ee"))
           ;; NUMBER; MSTORE(0); RETURN(0, 32).
           (code #(#x43 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 401)
                 (cons "method" "eth_call")
                 (cons
                  "params"
                  (list
                   (list (cons "to" (address-to-hex contract)))
                   "latest"
                   (list
                    (cons
                     (address-to-hex contract)
                     (list (cons "code" (bytes-to-hex code)))))
                   (list (cons "number" "0x2a")))))
                store config))
             (result (field response "result")))
        (is (= 42 (bytes-to-integer (hex-to-bytes result))))
        (is (= 0
               (length
                (chain-store-account-code
                 store (block-hash block) contract))))))))

(deftest eth-rpc-simulate-v1-executes-calls
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex
              "0x00000000000000000000000000000000000000ef"))
           (code #(#x60 #x07 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 402)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (list
                    (cons
                     "blockStateCalls"
                     (list
                      (list
                       (cons
                        "calls"
                        (list
                         (list
                          (cons "to" (address-to-hex contract))))))))))))
                store config))
             (blocks (field response "result"))
             (calls (field (first blocks) "calls"))
             (call (first calls)))
        (is (= 1 (length blocks)))
        (is (string= "0x1" (field call "status")))
        (is (= 7
               (bytes-to-integer
                (hex-to-bytes (field call "returnData")))))))))

(deftest eth-rpc-simulate-v1-refuses-too-many-blocks-with-specific-error
  ;; Execution APIs e5d1bb60 `ethSimulate-big-block-state-calls-array.io`
  ;; requires the dedicated limit error rather than generic invalid params.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((response
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" 403)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons "blockStateCalls"
                        (loop repeat 300 collect '()))))))
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (error-object (field response "error")))
      (is (null (field response "result")))
      (is (not (null error-object)))
      (when error-object
        (is (= -38026 (field error-object "code")))
        (is (string= "too many blocks"
                     (field error-object "message")))))))

(deftest eth-rpc-simulate-v1-bounds-call-counts-before-state-lookup
  ;; Geth 8a0223e8 caps one synthetic block at 5,000 calls and the complete
  ;; request at 10,000 calls before resolving the base block. This prevents a
  ;; valid per-block shape from bypassing the aggregate request budget.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (block-state-call (count)
             (list
              (cons "calls"
                    (loop repeat count collect '()))))
           (request (counts id)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" id)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons "blockStateCalls"
                        (mapcar #'block-state-call counts))))))
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (assert-limit-error (response message)
             (let ((error-object (field response "error")))
               (is (null (field response "result")))
               (is (not (null error-object)))
               (when error-object
                 (is (= -38026 (field error-object "code")))
                 (is (string= message (field error-object "message")))))))
    (assert-limit-error
     (request '(5001) 421)
     "too many calls in block: 5001 > 5000")
    (assert-limit-error
     (request '(5000 5000 1) 422)
     "too many calls: 10001 > 10000")
    ;; Exactly 10,000 calls clear both limits and continue to base-block lookup.
    (let* ((response (request '(5000 5000) 423))
           (error-object (field response "error")))
      (is (not (null error-object)))
      (when error-object
        (is (= -32602 (field error-object "code")))))))

(deftest eth-rpc-simulate-v1-rejects-non-increasing-block-overrides
  ;; Execution APIs e5d1bb60 pins these codes in
  ;; `ethSimulate-block-num-order-38020.io` and
  ;; `ethSimulate-block-timestamp-{order-38021,non-increment}.io`.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config overrides)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" 404)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons
                   "blockStateCalls"
                   (loop for block-overrides in overrides
                         collect
                         (list (cons "blockOverrides"
                                     block-overrides))))))))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (dolist (case
               (list
                (list -38020 "block numbers must be in order"
                      (list (list (cons "number" "0xa"))
                            (list (cons "number" "0x9"))))
                (list -38021 "block timestamps must be in order"
                      (list (list (cons "time" "0x14"))
                            (list (cons "time" "0x14"))))
                ;; A number gap implicitly inserts blocks at timestamps 22 and
                ;; 34. The requested block at 34 must therefore be rejected.
                (list -38021 "block timestamps must be in order"
                      (list (list (cons "number" "0x4")
                                  (cons "time" "0x22"))))))
        (destructuring-bind (expected-code expected-message overrides) case
          (let* ((response (request store config overrides))
                 (error-object (field response "error")))
            (is (null (field response "result")))
            (is (not (null error-object)))
            (when error-object
              (is (= expected-code (field error-object "code")))
              (is (search expected-message
                          (field error-object "message")))))))
      ;; A blanket two-block rejection would satisfy both negative controls.
      (let ((response
              (request store config
                       (list (list (cons "number" "0x2")
                                   (cons "time" "0x14"))
                             (list (cons "number" "0x3")
                                   (cons "time" "0x15"))))))
        (is (null (field response "error")))
        (is (= 2 (length (field response "result")))))
      ;; The same gap is valid once its explicit timestamp is later than every
      ;; implicit predecessor timestamp, and both implicit blocks are returned.
      (let ((response
              (request store config
                       (list (list (cons "number" "0x4")
                                   (cons "time" "0x23"))))))
        (is (null (field response "error")))
        (is (= 3 (length (field response "result"))))))))

(deftest eth-rpc-simulate-v1-materializes-implicit-number-gap-blocks
  ;; Execution APIs e5d1bb60's
  ;; `ethSimulate-add-more-non-defined-BlockStateCalls-than-fit-but-now-with-fit.io`
  ;; returns every implicit empty block, not only the caller-supplied entries.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 405)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (list
                    (cons
                     "blockStateCalls"
                     (list
                      (list
                       (cons "blockOverrides"
                             (list (cons "number" "0x4"))))))))))
                store config))
             (blocks (field response "result")))
        (is (null (field response "error")))
        (is (= 3 (length blocks)))
        (is (equal '("0x2" "0x3" "0x4")
                   (mapcar (lambda (result) (field result "number")) blocks)))
        (is (equal '("0x16" "0x22" "0x2e")
                   (mapcar (lambda (result) (field result "timestamp"))
                           blocks)))))))

(deftest eth-rpc-simulate-v1-bounds-implicit-number-gap-blocks
  ;; `maxSimulateBlocks` bounds the sanitized span, not just the supplied array.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config number)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" 406)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons
                   "blockStateCalls"
                   (list
                    (list
                     (cons "blockOverrides"
                           (list (cons "number" number))))))))))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response (request store config "0x102"))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is (not (null error-object)))
        (when error-object
          (is (= -38026 (field error-object "code")))
          (is (string= "too many blocks"
                       (field error-object "message")))))
      ;; Exactly 256 simulated blocks remains the permitted positive boundary.
      (let ((response (request store config "0x101")))
        (is (null (field response "error")))))))

(deftest eth-rpc-simulate-v1-enforces-per-block-gas-admission
  ;; Execution APIs e5d1bb60 defines omitted call gas as the remaining gas in
  ;; the current block. Pinned geth `simulate.go` rejects an explicit call gas
  ;; above that remainder with -38015; `errors.go` pins intrinsic-gas failures
  ;; to -38013.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config gas-limit calls id)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" id)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons
                   "blockStateCalls"
                   (list
                    (list
                     (cons "blockOverrides"
                           (list (cons "gasLimit"
                                       (quantity-to-hex gas-limit))))
                     (cons "calls" calls))))))))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (recipient (address-to-hex (zero-address)))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      ;; Two omitted gas values consume exactly the block allowance. Besides
      ;; the aggregate, maxUsedGas is required on each call result.
      (let* ((response
               (request
                store config 42000
                (list (list (cons "to" recipient))
                      (list (cons "to" recipient)))
                407))
             (block-result (first (field response "result")))
             (calls (and block-result (field block-result "calls"))))
        (is (null (field response "error")))
        (is (= 2 (length calls)))
        (is (string= "0xa410" (field block-result "gasUsed")))
        (dolist (call calls)
          (is (string= "0x1" (field call "status")))
          (is (string= "0x5208" (field call "gasUsed")))
          (is (string= "0x5208" (field call "maxUsedGas")))))
      ;; Admission uses the requested gas against the current remainder, not the
      ;; full block limit or the smaller amount an EOA call would consume.
      (let* ((response
               (request
                store config 42000
                (list
                 (list (cons "to" recipient))
                 (list (cons "to" recipient)
                       (cons "gas" (quantity-to-hex 21001))))
                408))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is (not (null error-object)))
        (when error-object
          (is (= -38015 (field error-object "code")))
          (is (search "block gas limit reached"
                      (field error-object "message")))))
      ;; The block has room, but the call cannot pay its intrinsic gas.
      (let* ((response
               (request
                store config 42000
                (list
                 (list (cons "to" recipient)
                       (cons "gas" "0x0")))
                409))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is (not (null error-object)))
        (when error-object
          (is (= -38013 (field error-object "code")))
          (is (search "intrinsic gas too low"
                      (field error-object "message"))))))))

(deftest eth-rpc-simulate-v1-rejects-insufficient-funds
  ;; Execution APIs e5d1bb60 `ethSimulate-gas-fees-and-value-error-38014.io`
  ;; and pinned geth's `stateTransition.buyGas` require max-fee gas plus value
  ;; to fit the sender balance even when transaction validation is disabled.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config balance gas max-fee value validation id)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" id)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (append
                  (list
                   (cons
                    "blockStateCalls"
                    (list
                     (append
                      (when balance
                        (list
                         (cons
                          "stateOverrides"
                          (list
                           (cons
                            "0xc000000000000000000000000000000000000000"
                            (list (cons "balance"
                                        (quantity-to-hex balance))))))))
                      (list
                       (cons
                        "calls"
                        (list
                         (append
                          (list
                           (cons "from"
                                 "0xc000000000000000000000000000000000000000")
                           (cons "to"
                                 "0xc100000000000000000000000000000000000000")
                           (cons "value" (quantity-to-hex value)))
                          (when gas
                            (list (cons "gas" (quantity-to-hex gas))))
                          (when max-fee
                            (list
                             (cons "maxFeePerGas"
                                   (quantity-to-hex max-fee))))))))))))
                  (list (cons "validation" validation)))
                 "latest")))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (dolist (case
               (list (list nil nil nil 1000 :false 415)
                     (list 21999 21000 1 1000 :false 416)
                     (list 21999 21000 1 1000 t 417)))
        (destructuring-bind (balance gas max-fee value validation id) case
          (let* ((response
                   (request store config balance gas max-fee value
                            validation id))
                 (error-object (field response "error")))
            (is (null (field response "result")))
            (is (not (null error-object)))
            (when error-object
              (is (= -38014 (field error-object "code")))
              (is (search "insufficient funds for gas * price + value"
                          (field error-object "message")))))))
      ;; Equality is the positive admission boundary: 21000 * 1 + 1000.
      (let ((response
              (request store config 22000 21000 1 1000 :false 418)))
        (is (null (field response "error")))
        (is (= 1 (length (field response "result"))))))))

(deftest eth-rpc-simulate-v1-validation-enforces-base-fee-admission
  ;; Execution APIs e5d1bb60 pins the validation-mode failure to -38012 in
  ;; `ethSimulate-basefee-too-low-with-validation-38012.io`, while the paired
  ;; no-validation fixture permits the same zero-fee call.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config validation id)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" id)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons
                   "blockStateCalls"
                   (list
                    (list
                     (cons "blockOverrides"
                           (list (cons "baseFeePerGas" "0xa")))
                     (cons
                      "calls"
                      (list
                       (list
                        (cons "from"
                              "0xc000000000000000000000000000000000000000")
                        (cons "to"
                              "0xc100000000000000000000000000000000000000")
                        (cons "maxFeePerGas" "0x0")
                        (cons "maxPriorityFeePerGas" "0x0")))))))
                  (cons "validation" validation))
                 "latest")))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response (request store config t 410))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is (not (null error-object)))
        (when error-object
          (is (= -38012 (field error-object "code")))
          (is (search "max fee per gas less than block base fee"
                      (field error-object "message")))))
      (let ((response (request store config :false 411)))
        (is (null (field response "error")))
        (is (= 1 (length (field response "result"))))))))

(deftest eth-rpc-simulate-v1-derives-base-fee-for-each-synthetic-block
  ;; Execution APIs e5d1bb60 pins the three base-fee modes: no-validation
  ;; blocks default to zero, explicit overrides are retained, and validation
  ;; derives each omitted value from its synthetic parent.  With a 100000 gas
  ;; limit, zero gas used, and parent fees 100 then 88, EIP-1559 yields 88 then
  ;; 77 for the two validation blocks.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (store config validation overrides id)
             (engine-rpc-handle-request
              (list
               (cons "jsonrpc" "2.0")
               (cons "id" id)
               (cons "method" "eth_simulateV1")
               (cons
                "params"
                (list
                 (list
                  (cons
                   "blockStateCalls"
                   (mapcar
                    (lambda (block-overrides)
                      (append
                       (when block-overrides
                         (list (cons "blockOverrides" block-overrides)))
                       (list (cons "calls" #()))))
                    overrides))
                  (cons "validation" validation))
                 "latest")))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 1 :timestamp 10 :gas-limit 100000 :gas-used 0
               :base-fee-per-gas 100 :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response (request store config :false '(nil nil) 412))
             (blocks (field response "result")))
        (is (null (field response "error")))
        (is (equal '("0x0" "0x0")
                   (mapcar (lambda (result)
                             (field result "baseFeePerGas"))
                           blocks))))
      (let* ((response (request store config t '(nil nil) 413))
             (blocks (field response "result")))
        (is (null (field response "error")))
        (is (equal '("0x58" "0x4d")
                   (mapcar (lambda (result)
                             (field result "baseFeePerGas"))
                           blocks))))
      (let* ((response
               (request store config :false
                        (list (list (cons "baseFeePerGas" "0x7")))
                        414))
             (blocks (field response "result")))
        (is (null (field response "error")))
        (is (string= "0x7" (field (first blocks) "baseFeePerGas")))))))

(deftest eth-rpc-simulate-v1-carries-successful-state-across-calls-and-blocks
  ;; Execution APIs e5d1bb60 `ethSimulate-transfer-over-BlockStateCalls.io`
  ;; requires each successful call to feed the next call and each resulting
  ;; block state to feed the next synthetic block. Keep the fixture's addresses,
  ;; balances, values, and two-block shape so drift remains auditable.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 54 :timestamp 540 :gas-limit 200000000
               :base-fee-per-gas 0 :state-root (state-db-root state))))
           (sender "0xc000000000000000000000000000000000000000")
           (first-recipient "0xc100000000000000000000000000000000000000")
           (second-recipient "0xc200000000000000000000000000000000000000")
           (override-recipient "0xc300000000000000000000000000000000000000")
           (response nil))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (setf response
            (engine-rpc-handle-request
             (list
              (cons "jsonrpc" "2.0")
              (cons "id" 415)
              (cons "method" "eth_simulateV1")
              (cons
               "params"
               (list
                (list
                 (cons
                  "blockStateCalls"
                  (list
                   (list
                    (cons "stateOverrides"
                          (list
                           (cons sender
                                 (list (cons "balance" "0x1388")))))
                    (cons
                     "calls"
                     (list
                      (list (cons "from" sender)
                            (cons "to" first-recipient)
                            (cons "value" "0x7d0"))
                      (list (cons "from" sender)
                            (cons "to" override-recipient)
                            (cons "value" "0x7d0")))))
                   (list
                    (cons "stateOverrides"
                          (list
                           (cons override-recipient
                                 (list (cons "balance" "0x1388")))))
                    (cons
                     "calls"
                     (list
                      (list (cons "from" first-recipient)
                            (cons "to" second-recipient)
                            (cons "value" "0x3e8"))
                      (list (cons "from" override-recipient)
                            (cons "to" second-recipient)
                            (cons "value" "0x3e8"))))))))
                "latest")))
             store config))
      (let ((blocks (field response "result")))
        (is (null (field response "error")))
        (is (= 2 (length blocks)))
        (is (every (lambda (result)
                     (every (lambda (call)
                              (string= "0x1" (field call "status")))
                            (field result "calls")))
                   blocks))
        (is (not (string= (hash32-to-hex (block-header-state-root
                                          (block-header block)))
                          (field (first blocks) "stateRoot"))))
        (is (not (string= (field (first blocks) "stateRoot")
                          (field (second blocks) "stateRoot")))))
      ;; The mutable simulation state is request-local; canonical retained state
      ;; remains unchanged after the response is assembled.
      (is (= 0
             (chain-store-account-balance
              store (block-hash block)
              (address-from-hex first-recipient)))))))

(deftest eth-rpc-simulate-v1-defaults-and-advances-sender-nonce
  ;; Execution APIs e5d1bb60 specifies that an omitted call nonce comes from the
  ;; current account and advances after every included call. Contract creation
  ;; makes that state transition observable without relying on response hashes;
  ;; starting at uint64 maximum also pins its no-validation overflow fixture.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (created-address (sender nonce)
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) nonce)))
               12 32)))
           (address-word-hex (address)
             (let ((bytes (make-byte-vector 32)))
               (replace bytes (address-bytes address) :start1 12)
               (bytes-to-hex bytes))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (sender
             (address-from-hex
              "0xc000000000000000000000000000000000000000"))
           ;; ADDRESS; MSTORE(0); RETURN(0, 32).
           (initcode #(#x30 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (start-nonce (1- (ash 1 64)))
           (call
             (list (cons "from" (address-to-hex sender))
                   (cons "gas" "0x186a0")
                   (cons "input" (bytes-to-hex initcode))))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 54 :timestamp 540 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (state-db-set-account
       state sender (make-state-account :nonce start-nonce))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 416)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (list
                    (cons
                     "blockStateCalls"
                     (list (list (cons "calls" (list call)))
                           (list (cons "calls" (list call))))))
                   "latest")))
                store config))
             (blocks (field response "result"))
             (call-results
               (mapcar (lambda (result)
                         (first (field result "calls")))
                       blocks)))
        (is (null (field response "error")))
        (is (= 2 (length call-results)))
        (is (every (lambda (result)
                     (string= "0x1" (field result "status")))
                   call-results))
        (is (equal
             (list (address-word-hex
                    (created-address sender start-nonce))
                   (address-word-hex (created-address sender 0)))
             (mapcar (lambda (result) (field result "returnData"))
                     call-results))))
      ;; Simulation state remains request-local.
      (is (= start-nonce
             (chain-store-account-nonce
              store (block-hash block) sender))))))

(deftest eth-rpc-simulate-v1-validates-sender-nonce
  ;; Pinned geth `simulate.go` fills omitted nonces from state before its state
  ;; transition. Validation mode then exposes the standardized -38010/-38011
  ;; nonce mismatch errors and rejects the uint64 maximum before incrementing.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request
               (store config sender nonce
                &key override-nonce override-base-fee)
             (let ((call
                     (append
                      (list (cons "from" (address-to-hex sender))
                            (cons "to" (address-to-hex (zero-address))))
                      (when nonce
                        (list (cons "nonce" (quantity-to-hex nonce)))))))
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 417)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (append
                    (list
                     (cons
                      "blockStateCalls"
                      (list
                       (append
                        (when override-base-fee
                          (list
                           (cons "blockOverrides"
                                 (list
                                  (cons "baseFeePerGas"
                                        (quantity-to-hex
                                         override-base-fee))))))
                        (when override-nonce
                          (list
                           (cons
                            "stateOverrides"
                            (list
                             (cons
                              (address-to-hex sender)
                              (list
                               (cons "nonce"
                                     (quantity-to-hex override-nonce))))))))
                        (list (cons "calls" (list call)))))))
                    (list (cons "validation" t)))
                   "latest")))
                store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (sender
             (address-from-hex
              "0xc000000000000000000000000000000000000000"))
           (state (make-state-db))
           (block
             (make-block
              :header
              (make-block-header
               :number 54 :timestamp 540 :gas-limit 100000
               :base-fee-per-gas 0 :state-root (state-db-root state)))))
      (state-db-set-account state sender (make-state-account :nonce 7))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (dolist (case (list (list 6 -38010 "nonce too low")
                          (list 8 -38011 "nonce too high")))
        (destructuring-bind (nonce expected-code expected-message) case
          (let* ((response (request store config sender nonce))
                 (error-object (field response "error")))
            (is (null (field response "result")))
            (is (not (null error-object)))
            (when error-object
              (is (= expected-code (field error-object "code")))
              (is (search expected-message
                          (field error-object "message")))))))
      ;; A matching explicit nonce is the positive control.
      (let ((response (request store config sender 7)))
        (is (null (field response "error")))
        (is (= 1 (length (field response "result")))))
      ;; Validation must not wrap a sender nonce beyond uint64.
      (let* ((response
               (request store config sender nil
                        :override-nonce (1- (ash 1 64))
                        :override-base-fee 1))
             (error-object (field response "error")))
        (is (null (field response "result")))
        (is (not (null error-object)))
        (when error-object
          (is (= -32603 (field error-object "code")))
          (is (search "nonce has max value"
                      (field error-object "message"))))))))

(deftest eth-rpc-simulate-v1-settles-gas-fees
  ;; Execution APIs e5d1bb60 `ethSimulate-fee-recipient-receiving-funds.io`
  ;; and pinned geth's
  ;; state transition charge the effective gas price, refund unused gas, burn
  ;; the base fee, and credit only the priority fee to the synthetic coinbase.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (sender
             (address-from-hex
              "0xc000000000000000000000000000000000000000"))
           (recipient
             (address-from-hex
              "0xc100000000000000000000000000000000000000"))
           (fee-recipient
             (address-from-hex
              "0xc200000000000000000000000000000000000000"))
           (state (make-state-db))
           (block nil)
           (expected-state nil))
      (state-db-set-account
       state sender (make-state-account :balance 500000))
      (setf block
            (make-block
             :header
             (make-block-header
              :number 54 :timestamp 540 :gas-limit 100000
              :base-fee-per-gas 0 :state-root (state-db-root state))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (setf expected-state (state-db-copy state))
      ;; effective gas price = min(10, 2 + 3) = 5. The EOA transfer uses 21000
      ;; gas, so sender pays 105000 gas + 1000 value, coinbase receives the
      ;; 63000 priority fee, and the remaining 42000 base fee is burned.
      (state-db-set-account
       expected-state sender
       (make-state-account :nonce 1 :balance 394000))
      (state-db-set-account
       expected-state recipient
       (make-state-account :balance 1000))
      (state-db-set-account
       expected-state fee-recipient
       (make-state-account :balance 63000))
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 419)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (list
                    (cons
                     "blockStateCalls"
                     (list
                      (list
                       (cons
                        "blockOverrides"
                        (list
                         (cons "baseFeePerGas" "0x2")
                         (cons "feeRecipient"
                               (address-to-hex fee-recipient))))
                       (cons
                        "calls"
                        (list
                         (list
                          (cons "from" (address-to-hex sender))
                          (cons "to" (address-to-hex recipient))
                          (cons "gas" "0x7530")
                          (cons "value" "0x3e8")
                          (cons "maxFeePerGas" "0xa")
                          (cons "maxPriorityFeePerGas" "0x3")))))))
                    (cons "validation" t))
                   "latest")))
                store config))
             (block-result (first (field response "result")))
             (call-result (and block-result
                               (first (field block-result "calls")))))
        (is (null (field response "error")))
        (is (string= "0x1" (field call-result "status")))
        (is (string= "0x5208" (field call-result "gasUsed")))
        (is (string= "0x5208" (field call-result "maxUsedGas")))
        (is (string= (state-db-root-hex expected-state)
                     (field block-result "stateRoot"))))
      ;; Fee settlement, like every simulation mutation, remains request-local.
      (is (= 500000
             (chain-store-account-balance
              store (block-hash block) sender)))
      (is (= 0
             (chain-store-account-balance
              store (block-hash block) fee-recipient))))))

(deftest eth-rpc-simulate-v1-applies-evm-gas-refunds
  ;; Geth state_transition.go records MaxUsedGas before the EIP-3529 refund,
  ;; bills UsedGas after it, and settles balances using that billed amount.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :berlin-block 0
                                      :london-block 0))
           (sender
             (address-from-hex
              "0xc000000000000000000000000000000000000000"))
           (contract
             (address-from-hex
              "0xc100000000000000000000000000000000000000"))
           (fee-recipient
             (address-from-hex
              "0xc200000000000000000000000000000000000000"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SSTORE slot 1 := 0; RETURN(0, 0).
           (code #(96 0 96 1 85 96 0 96 0 243))
           (state (make-state-db))
           (block nil)
           (expected-state nil))
      (state-db-set-account
       state sender (make-state-account :balance 1000000))
      (state-db-set-code state contract code)
      (state-db-set-storage state contract slot 7)
      (setf block
            (make-block
             :header
             (make-block-header
              :number 54 :timestamp 540 :gas-limit 100000
              :base-fee-per-gas 0 :state-root (state-db-root state))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (setf expected-state (state-db-copy state))
      ;; Pre-refund gas is 26012. Clearing the slot earns a 4800 refund, below
      ;; the London one-fifth cap, so billed gas is 21212. At effective price 5
      ;; the sender retains 893940 and the synthetic coinbase earns 63636.
      (state-db-set-account
       expected-state sender
       (make-state-account :nonce 1 :balance 893940))
      (state-db-set-account
       expected-state fee-recipient
       (make-state-account :balance 63636))
      (state-db-set-storage expected-state contract slot 0)
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 420)
                 (cons "method" "eth_simulateV1")
                 (cons
                  "params"
                  (list
                   (list
                    (cons
                     "blockStateCalls"
                     (list
                      (list
                       (cons
                        "blockOverrides"
                        (list
                         (cons "baseFeePerGas" "0x2")
                         (cons "feeRecipient"
                               (address-to-hex fee-recipient))))
                       (cons
                        "calls"
                        (list
                         (list
                          (cons "from" (address-to-hex sender))
                          (cons "to" (address-to-hex contract))
                          (cons "gas" "0x186a0")
                          (cons "maxFeePerGas" "0xa")
                          (cons "maxPriorityFeePerGas" "0x3"))))))))
                   "latest")))
                store config))
             (block-result (first (field response "result")))
             (call-result (and block-result
                               (first (field block-result "calls")))))
        (is (null (field response "error")))
        (is (string= "0x1" (field call-result "status")))
        (is (string= "0x52dc" (field call-result "gasUsed")))
        (is (string= "0x659c" (field call-result "maxUsedGas")))
        (is (string= "0x52dc" (field block-result "gasUsed")))
        (is (string= (state-db-root-hex expected-state)
                     (field block-result "stateRoot")))))))
