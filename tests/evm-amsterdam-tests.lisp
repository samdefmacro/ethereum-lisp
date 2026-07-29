(in-package #:ethereum-lisp.test)

(defun amsterdam-test-context (&key (slot-number 0) (amsterdam-p t))
  (make-evm-context
   :slot-number slot-number
   :chain-rules
   (make-chain-rules :chain-id 1
                     :byzantium-p t
                     :constantinople-p t
                     :istanbul-p t
                     :berlin-p t
                     :london-p t
                     :shanghai-p t
                     :cancun-p t
                     :prague-p t
                     :osaka-p t
                     :amsterdam-p amsterdam-p)))

(deftest evm-slotnum-is-amsterdam-gated
  (let ((result
          (execute-bytecode #(#x4b 0)
                            :context
                            (amsterdam-test-context :slot-number 42))))
    (is (= 42 (first (evm-result-stack result))))
    (is (= 2 (evm-result-gas-used result))))
  (signals evm-error
    (execute-bytecode #(#x4b 0)
                      :context
                      (amsterdam-test-context :amsterdam-p nil))))

(deftest evm-eip8024-stack-opcodes-decode-immediates
  (let ((dupn
          (execute-bytecode
           #(#x60 1 #x60 2 #x60 3 #x60 4 #x60 5 #x60 6
             #x60 7 #x60 8 #x60 9 #x60 10 #x60 11 #x60 12
             #x60 13 #x60 14 #x60 15 #x60 16 #x60 17
             #xe6 #x80 0)
           :context (amsterdam-test-context)))
        (swapn
          (execute-bytecode
           #(#x60 1 #x60 2 #x60 3 #x60 4 #x60 5 #x60 6
             #x60 7 #x60 8 #x60 9 #x60 10 #x60 11 #x60 12
             #x60 13 #x60 14 #x60 15 #x60 16 #x60 17 #x60 18
             #xe7 #x80 0)
           :context (amsterdam-test-context)))
        (exchange
          (execute-bytecode
           #(#x60 1 #x60 2 #x60 3 #xe8 #x8e 0)
           :context (amsterdam-test-context))))
    (is (= 1 (first (evm-result-stack dupn))))
    (is (= 54 (evm-result-gas-used dupn)))
    (is (= 1 (first (evm-result-stack swapn))))
    (is (= 18 (nth 17 (evm-result-stack swapn))))
    (is (= 57 (evm-result-gas-used swapn)))
    (is (equal '(3 1 2) (evm-result-stack exchange)))
    (is (= 12 (evm-result-gas-used exchange)))))

(deftest evm-eip8024-stack-opcodes-reject-invalid-contexts
  (dolist (opcode '(#xe6 #xe7 #xe8))
    (signals evm-error
      (execute-bytecode
       (vector opcode #x80 0)
       :context (amsterdam-test-context :amsterdam-p nil))))
  (signals evm-error
    (execute-bytecode #(#xe8 #x5b 0)
                      :context (amsterdam-test-context)))
  ;; The immediate byte is data, even when it is JUMPDEST.
  (signals evm-error
    (execute-bytecode #(#x60 4 #x56 #xe6 #x5b 0)
                      :context (amsterdam-test-context))))

(deftest amsterdam-contract-code-limit-is-eip7954-value
  (is (= 65536 +amsterdam-max-contract-code-size+))
  (is (= 65536 +block-access-list-amsterdam-max-code-size+))
  (is (= 65536
         (chain-rules-contract-code-size-limit
          (make-chain-rules :chain-id 1 :amsterdam-p t)))))

(deftest amsterdam-precompile-activation-count-matches-osaka
  (let ((accessed (make-hash-table :test 'equalp)))
    (prewarm-precompile-addresses
     accessed
     (evm-context-chain-rules (amsterdam-test-context)))
    (is (= 18 (hash-table-count accessed)))))

(deftest eth-transfer-system-log-has-eip7708-shape
  (let* ((sender
           (make-address
            (hex-to-bytes "0x0000000000000000000000000000000000000011")))
         (recipient
           (make-address
            (hex-to-bytes "0x0000000000000000000000000000000000000022")))
         (log (make-eth-transfer-log-entry sender recipient 7)))
    (is (string=
         "0xfffffffffffffffffffffffffffffffffffffffe"
         (address-to-hex (log-entry-address log))))
    (is (= 3 (length (log-entry-topics log))))
    (is (= 7 (bytes-to-integer (log-entry-data log))))))

(defun amsterdam-transfer-test-rules ()
  (make-chain-rules :chain-id 1
                    :shanghai-p t
                    :cancun-p t
                    :prague-p t
                    :osaka-p t
                    :amsterdam-p t))

(deftest amsterdam-emits-top-level-eth-transfer-log
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x0000000000000000000000000000000000000011"))
         (recipient
           (address-from-hex
            "0x0000000000000000000000000000000000000022"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 7)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt
            (apply-message state sender tx
                           :chain-rules
                           (amsterdam-transfer-test-rules))))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (length (receipt-logs receipt)))))))

(deftest amsterdam-emits-nested-call-and-selfdestruct-transfer-logs
  (let ((sender
          (address-from-hex
           "0x0000000000000000000000000000000000000011"))
        (recipient
          (address-from-hex
           "0x0000000000000000000000000000000000000022")))
    (dolist (code
             (list
              ;; CALL address 0x22 with value 7.
              #(#x60 0 #x60 0 #x60 0 #x60 0
                #x60 7 #x60 #x22 #x61 #xff #xff #xf1 0)
              ;; SELFDESTRUCT to address 0x22.
              #(#x60 #x22 #xff)))
      (let* ((state (make-state-db))
             (contract
               (address-from-hex
                "0x0000000000000000000000000000000000000200"))
             (tx (make-legacy-transaction :nonce 0
                                          :gas-price 1
                                          :gas-limit 100000
                                          :to contract)))
        (state-db-set-account state sender
                              (make-state-account :balance 200000))
        (state-db-set-account state contract
                              (make-state-account :balance 10))
        (state-db-set-code state contract code)
        (let ((receipt
                (apply-message state sender tx
                               :chain-rules
                               (amsterdam-transfer-test-rules))))
          (is (= 1 (receipt-status receipt)))
          (is (= 1 (length (receipt-logs receipt))))
          (is (= (if (= (length code) 3) 10 7)
                 (bytes-to-integer
                  (log-entry-data (first (receipt-logs receipt)))))))))))

(deftest amsterdam-created-contract-selfdestruct-to-self-keeps-balance-only
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x0000000000000000000000000000000000000011"))
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
                                      :value 7
                                      :data #(#x30 #xff))))
    (state-db-set-account state sender
                          (make-state-account :balance 200000))
    (let ((receipt
            (apply-message state sender tx
                           :chain-rules
                           (amsterdam-transfer-test-rules)))
          (account nil))
      (setf account (state-db-get-account state contract))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (length (receipt-logs receipt))))
      (is account)
      (is (= 7 (state-account-balance account)))
      (is (= 0 (state-account-nonce account)))
      (is (= 0 (length (state-db-get-code state contract)))))))

(deftest storage-only-account-is-empty-but-still-collides-on-create
  (let* ((state (make-state-db))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000033"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context
           (make-evm-context
            :state state
            :chain-rules
            (make-chain-rules :chain-id 1
                              :constantinople-p t
                              :berlin-p t))))
    (state-db-set-storage state address slot 7)
    (let ((result
            (execute-bytecode #(#x60 #x33 #x3f 0)
                              :context context)))
      (is (= 0 (first (evm-result-stack result)))))
    (is (ethereum-lisp.evm.internal::contract-address-collision-p
         state address))))
