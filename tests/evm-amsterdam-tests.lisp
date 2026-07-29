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
                                      :gas-limit 250000
                                      :to recipient
                                      :value 7)))
    (state-db-set-account state sender
                          (make-state-account :balance 500000))
    (let ((receipt
            (apply-message state sender tx
                           :chain-rules
                           (amsterdam-transfer-test-rules))))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-regular-gas-used receipt)))
      (is (= 183600 (receipt-state-gas-used receipt)))
      (is (= 204600 (receipt-cumulative-gas-used receipt)))
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
                                          :gas-limit 500000
                                          :to contract)))
        (state-db-set-account state sender
                              (make-state-account :balance 1000000))
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
                                      :gas-limit 500000
                                      :to nil
                                      :value 7
                                      :data #(#x30 #xff))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
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

(deftest eip8037-gas-budget-spills-and-refills-lifo
  (let ((budget (make-evm-gas-budget :regular 50 :state 100)))
    (is (ethereum-lisp.evm.internal::evm-gas-budget-charge-state
         budget 120))
    (is (= 30 (evm-gas-budget-regular budget)))
    (is (= 0 (evm-gas-budget-state budget)))
    (is (= 120 (evm-gas-budget-used-state budget)))
    (is (= 20 (evm-gas-budget-spilled budget)))
    (ethereum-lisp.evm.internal::evm-gas-budget-refill-state budget 120)
    (is (= 50 (evm-gas-budget-regular budget)))
    (is (= 100 (evm-gas-budget-state budget)))
    (is (= 0 (evm-gas-budget-used-state budget)))
    (is (= 0 (evm-gas-budget-spilled budget)))))

(defun amsterdam-state-gas-test-context (state address &optional (active-p t))
  (make-evm-context
   :state state
   :address address
   :chain-rules
   (make-chain-rules :chain-id 1
                     :homestead-p t
                     :byzantium-p t
                     :constantinople-p t
                     :istanbul-p t
                     :berlin-p t
                     :london-p t
                     :shanghai-p t
                     :cancun-p t
                     :prague-p t
                     :osaka-p t
                     :amsterdam-p active-p)))

(deftest eip8038-storage-access-fork-matrix
  (dolist (case '((nil 2102) (t 3002)))
    (let* ((state (make-state-db))
           (address
             (address-from-hex
              "0x0000000000000000000000000000000000000044"))
           (result
             (execute-bytecode
              #(#x5f #x54 0)
              :context
              (amsterdam-state-gas-test-context
               state address (first case))
              :gas-limit 10000)))
      (is (= (second case) (evm-result-regular-gas-used result)))
      (is (= 0 (evm-result-state-gas-used result))))))

(deftest eip8037-and-8038-sstore-charges-and-refills
  (let* ((state (make-state-db))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         (context (amsterdam-state-gas-test-context state address))
         (new-slot
           (execute-bytecode
            #(#x60 1 #x5f #x55 0)
            :context context
            :gas-limit 200000
            :gas-budget
            (make-evm-gas-budget :regular 200000 :state 100000)))
         (clear-context
           (amsterdam-state-gas-test-context
            (make-state-db) address))
         (set-and-clear
           (execute-bytecode
            #(#x60 1 #x5f #x55 #x5f #x5f #x55 0)
            :context clear-context
            :gas-limit 200000
            :gas-budget
            (make-evm-gas-budget :regular 200000 :state 100000))))
    (is (= 13005 (evm-result-regular-gas-used new-slot)))
    (is (= 97920 (evm-result-state-gas-used new-slot)))
    (is (= 13109 (evm-result-regular-gas-used set-and-clear)))
    (is (= 0 (evm-result-state-gas-used set-and-clear)))
    (is (= 10000 (evm-result-refund-counter set-and-clear)))))

(defun amsterdam-sstore-sequence (values)
  (coerce
   (append
    (loop for value in values
          append (list #x60 value #x60 0 #x55))
    '(0))
   '(vector (unsigned-byte 8))))

(deftest eip8037-and-8038-sstore-complete-cases-table
  ;; Ported from geth v1.17.5 TestEIP8038SStore.  Each store has two PUSH1s;
  ;; the first slot access is cold and later accesses are warm.
  (dolist (case
           '(("noop" 1 (1) 3006 0 0)
             ("create" 0 (1) 13006 97920 0)
             ("first change" 1 (2) 13006 0 0)
             ("clear" 1 (0) 13006 0 12480)
             ("create warm" 0 (0 1) 13112 97920 0)
             ("first change warm" 1 (1 2) 13112 0 0)
             ("clear warm" 1 (1 0) 13112 0 12480)
             ("dirty modified again" 1 (2 3) 13112 0 0)
             ("reset to zero" 0 (1 0) 13112 0 10000)
             ("reset to original" 1 (2 1) 13112 0 10000)
             ("cleared then restored" 1 (0 1) 13112 0 10000)
             ("cleared then new" 1 (0 2) 13112 0 0)
             ("zero round trip" 0 (1 0 1) 23218 97920 10000)
             ("nonzero round trip" 1 (0 1 0) 23218 0 22480)))
    (destructuring-bind
        (name original values regular state-gas refund) case
      (declare (ignore name))
      (let* ((state (make-state-db))
             (address
               (address-from-hex
                "0x0000000000000000000000000000000000000044"))
             (slot
               (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000000")))
        (unless (zerop original)
          (state-db-set-storage state address slot original))
        (let ((result
                (execute-bytecode
                 (amsterdam-sstore-sequence values)
                 :context (amsterdam-state-gas-test-context state address)
                 :gas-limit 1000000
                 :gas-budget
                 (make-evm-gas-budget :regular 1000000 :state 1000000))))
          (is (= regular (evm-result-regular-gas-used result)))
          (is (= state-gas (evm-result-state-gas-used result)))
          (is (= refund (evm-result-refund-counter result))))))))

(deftest eip8038-account-opcodes-price-cold-warm-and-code-reads
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         (target
           (address-from-hex
            "0x0000000000000000000000000000000000000022")))
    (state-db-set-account state target (make-state-account :balance 7))
    (state-db-set-code state target #(#x00))
    (let ((balance
            (execute-bytecode
             #(#x60 #x22 #x31 #x50 #x60 #x22 #x31 0)
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 10000))
          (code-size
            (execute-bytecode
             #(#x60 #x22 #x3b #x50 #x60 #x22 #x3b 0)
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 10000))
          (code-hash
            (execute-bytecode
             #(#x60 #x22 #x3f #x50 #x60 #x22 #x3f 0)
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 10000))
          (code-copy
            (execute-bytecode
             #(#x5f #x5f #x5f #x60 #x22 #x3c
                #x5f #x5f #x5f #x60 #x22 #x3c 0)
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 10000)))
      (is (= 3108 (evm-result-regular-gas-used balance)))
      (is (= 3308 (evm-result-regular-gas-used code-size)))
      (is (= 3108 (evm-result-regular-gas-used code-hash)))
      (is (= 3318 (evm-result-regular-gas-used code-copy))))))

(defun amsterdam-call-family-code (opcode &optional (value 0))
  (coerce
   (append
    '(#x60 0 #x60 0 #x60 0 #x60 0)
    (when (member opcode '(#xf1 #xf2)) (list #x60 value))
    '(#x60 #x22 #x5a)
    (list opcode)
    '(#x50 0))
   '(vector (unsigned-byte 8))))

(deftest eip8038-prices-every-call-family-member
  ;; geth v1.17.5 TestEIP8038Calls: cold account access is 3,000 total,
  ;; value CALL/CALLCODE retains an 8,000 net account-write cost when the
  ;; returned stipend is unused, and only CALL can create destination state.
  (dolist (case
           '((#xf1 0 3022 0)
             (#xf1 1 11022 183600)
             (#xf2 1 11022 0)
             (#xf4 0 3019 0)
             (#xfa 0 3019 0)))
    (destructuring-bind (opcode value regular state-gas) case
      (let* ((state (make-state-db))
             (contract
               (address-from-hex
                "0x0000000000000000000000000000000000000044")))
        (state-db-set-account state contract
                              (make-state-account :balance 10))
        (let ((result
                (execute-bytecode
                 (amsterdam-call-family-code opcode value)
                 :context (amsterdam-state-gas-test-context state contract)
                 :gas-limit 1000000
                 :gas-budget
                 (make-evm-gas-budget :regular 1000000 :state 1000000))))
          (is (= regular (evm-result-regular-gas-used result)))
          (is (= state-gas (evm-result-state-gas-used result))))))))

(deftest eip8037-call-state-charge-refills-when-parent-reverts
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         (call (amsterdam-call-family-code #xf1 1))
         (code
           (concatenate
            '(vector (unsigned-byte 8))
            (subseq call 0 (- (length call) 2))
            #(#x60 0 #x60 0 #xfd))))
    (state-db-set-account state contract (make-state-account :balance 10))
    (let ((result
            (execute-bytecode
             code
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 1000000
             :gas-budget
             (make-evm-gas-budget :regular 1000000 :state 1000000))))
      (is (eq :reverted (evm-result-status result)))
      (is (= 0 (evm-result-state-gas-used result))))))

(deftest eip8037-call-state-charge-refills-on-pre-frame-failure
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         (result
           (execute-bytecode
            (amsterdam-call-family-code #xf1 1)
            :context (amsterdam-state-gas-test-context state contract)
            :gas-limit 1000000
            :gas-budget
            (make-evm-gas-budget :regular 1000000 :state 1000000))))
    (is (= 0 (evm-result-state-gas-used result)))))

(deftest eip8037-and-8038-create-create2-and-code-deposit
  (dolist (case
           '((#xf0 #(#x64 #x60 3 #x60 0 #xf3 #x5f #x52
                      #x60 5 #x60 27 #x5f #xf0 0)
              11036)
             (#xf5 #(#x64 #x60 3 #x60 0 #xf3 #x5f #x52
                      #x5f #x60 5 #x60 27 #x5f #xf5 0)
              11044)))
    (destructuring-bind (opcode code regular) case
      (declare (ignore opcode))
      (let* ((state (make-state-db))
             (contract
               (address-from-hex
                "0x0000000000000000000000000000000000000044"))
             (result
               (execute-bytecode
                code
                :context (amsterdam-state-gas-test-context state contract)
                :gas-limit 1000000
                :gas-budget
                (make-evm-gas-budget :regular 1000000 :state 1000000))))
        (is (= regular (evm-result-regular-gas-used result)))
        (is (= (+ 183600 (* 3 1530))
               (evm-result-state-gas-used result)))))))

(deftest eip8037-create-state-charge-refills-on-initcode-revert
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         ;; PUSH3 5f5ffd; PUSH0; MSTORE; PUSH1 3; PUSH1 29; PUSH0; CREATE.
         (result
           (execute-bytecode
            #(#x62 #x5f #x5f #xfd #x5f #x52
              #x60 3 #x60 29 #x5f #xf0 0)
            :context (amsterdam-state-gas-test-context state contract)
            :gas-limit 1000000
            :gas-budget
            (make-evm-gas-budget :regular 1000000 :state 1000000))))
    (is (= 0 (first (evm-result-stack result))))
    (is (= 0 (evm-result-state-gas-used result)))))

(deftest eip8037-and-8038-selfdestruct-creates-beneficiary-state
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000044")))
    (state-db-set-account state contract (make-state-account :balance 1))
    (let ((result
            (execute-bytecode
             #(#x60 #x22 #xff)
             :context (amsterdam-state-gas-test-context state contract)
             :gas-limit 1000000
             :gas-budget
             (make-evm-gas-budget :regular 1000000 :state 1000000))))
      (is (= 16003 (evm-result-regular-gas-used result)))
      (is (= 183600 (evm-result-state-gas-used result))))))

(deftest eip8038-access-list-intrinsic-pricing-follows-fork
  (let* ((address
           (address-from-hex
            "0x0000000000000000000000000000000000000022"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (tx
           (make-access-list-transaction
            :chain-id 1
            :gas-limit 100000
            :to address
            :access-list
            (list (make-access-list-entry
                   :address address :storage-keys (list slot))))))
    (is (= (+ 21000 2400 1900)
           (transaction-intrinsic-gas tx)))
    (is (= (+ 21000 3000 3000)
           (transaction-intrinsic-gas
            tx :chain-rules (amsterdam-transfer-test-rules))))))

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
