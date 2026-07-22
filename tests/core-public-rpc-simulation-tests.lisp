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

(deftest debug-namespace-is-advertised-and-gateable
  ;; rpc_modules must list debug, and --http.api must be able to withhold it.
  (let ((modules (ethereum-lisp.public-api::engine-rpc-handle-rpc-modules
                   nil #'ethereum-lisp.engine-api:engine-rpc-public-method-p)))
    (is (assoc "debug" modules :test #'string=)))
  (is (ethereum-lisp.engine-api:engine-rpc-public-method-p "debug_getRawHeader"))
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
