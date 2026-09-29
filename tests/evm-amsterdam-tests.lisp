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
                      :context (amsterdam-test-context))))

(deftest eip8024-immediate-byte-stays-a-jump-destination
  ;; Only PUSH data is excluded from JUMPDEST analysis (geth v1.17.6
  ;; core/vm/analysis_legacy.go codeBitmap). A 0x5b immediate of DUPN, SWAPN
  ;; or EXCHANGE is a valid jump target: tests-glamsterdam-devnet@v7.2.1
  ;; dupn_jump_to_immediate_byte_0x5b_succeeds and
  ;; exchange_jump_to_immediate_byte expect the jump to succeed. Before
  ;; Amsterdam 0xe6..0xe8 are undefined opcodes, so the byte after one was
  ;; always code. PUSH1 4, JUMP lands on the 0x5b at pc 4 and stops.
  (dolist (opcode '(#xe6 #xe7 #xe8))
    (dolist (amsterdam-p '(t nil))
      (let ((result (execute-bytecode
                     (vector #x60 4 #x56 opcode #x5b 0)
                     :context (amsterdam-test-context
                               :amsterdam-p amsterdam-p))))
        (is (eq :stopped (evm-result-status result))))))
  ;; The control: PUSH data is still excluded, so a 0x5b pushed as data is
  ;; not a jump target.
  (signals evm-error
    (execute-bytecode #(#x60 4 #x56 #x60 #x5b 0)
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

(deftest amsterdam-rpc-transfer-trace-does-not-replace-system-log
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
                                      :value 7))
         (*evm-trace-transfers-p* t)
         (*evm-log-tracer* (make-evm-log-tracer)))
    (state-db-set-account state sender
                          (make-state-account :balance 500000))
    (let* ((receipt
             (apply-message state sender tx
                            :chain-rules
                            (amsterdam-transfer-test-rules)))
           (system-log (first (receipt-logs receipt)))
           (trace-logs
             (nreverse (evm-log-tracer-logs *evm-log-tracer*))))
      (is (= 1 (length (receipt-logs receipt))))
      (is (= 2 (length trace-logs)))
      (is (string=
           "0xfffffffffffffffffffffffffffffffffffffffe"
           (address-to-hex (log-entry-address system-log))))
      (is (string=
           "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
           (address-to-hex (log-entry-address (first trace-logs)))))
      (is (string=
           "0xfffffffffffffffffffffffffffffffffffffffe"
           (address-to-hex (log-entry-address (second trace-logs))))))))

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

(deftest amsterdam-reverted-nested-call-discards-transfer-log
  (let* ((state (make-state-db))
         (sender
           (address-from-hex
            "0x0000000000000000000000000000000000000011"))
         (recipient
           (address-from-hex
            "0x0000000000000000000000000000000000000022"))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000200"))
         ;; CALL address 0x22 with value 7, then emit LOG0 after failure.
         (code #(#x60 0 #x60 0 #x60 0 #x60 0
                 #x60 7 #x60 #x22 #x61 #xff #xff #xf1
                 #x50 #x5f #x5f #xa0 #x00))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 500000
                                      :to contract))
         (*evm-trace-transfers-p* t)
         (*evm-log-tracer* (make-evm-log-tracer)))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (state-db-set-account state contract
                          (make-state-account :balance 10))
    (state-db-set-code state contract code)
    (state-db-set-code state recipient #(#x5f #x5f #xfd))
    (let ((receipt
            (apply-message state sender tx
                           :chain-rules
                           (amsterdam-transfer-test-rules))))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (length (receipt-logs receipt))))
      (is (= 1 (length (evm-log-tracer-logs *evm-log-tracer*))))
      ;; The reverted pseudo-transfer and EIP-7708 system log consumed indices
      ;; 0 and 1 just as geth's log tracer does; LOG0 keeps the resulting gap.
      (is (equal '(2) (evm-log-tracer-indices *evm-log-tracer*)))
      (is (= 3 (evm-log-tracer-count *evm-log-tracer*)))
      (is (= 10
             (state-account-balance
              (state-db-get-account state contract))))
      (is (= 0
             (state-account-balance
              (state-db-get-account state recipient)))))))

(deftest amsterdam-rpc-transfer-trace-captures-callcode-value
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000200"))
         (code-address
           (address-from-hex
            "0x0000000000000000000000000000000000000022"))
         (context
           (make-evm-context :state state
                             :address contract
                             :chain-rules
                             (amsterdam-transfer-test-rules)))
         ;; CALLCODE address 0x22 with value 7.
         (code #(#x60 0 #x60 0 #x60 0 #x60 0
                 #x60 7 #x60 #x22 #x61 #xff #xff #xf2 #x00))
         (*evm-trace-transfers-p* t)
         (*evm-log-tracer* (make-evm-log-tracer)))
    (state-db-set-account state contract
                          (make-state-account :balance 10))
    (state-db-set-code state code-address #())
    (let* ((result (execute-bytecode code :context context))
           (trace-log
             (first (evm-log-tracer-logs *evm-log-tracer*))))
      (is (eq :stopped (evm-result-status result)))
      (is (= 1 (length (evm-log-tracer-logs *evm-log-tracer*))))
      (is (string=
           "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
           (address-to-hex (log-entry-address trace-log))))
      (is (bytes= (address-bytes contract)
                  (subseq (hash32-bytes (second (log-entry-topics trace-log)))
                          12 32)))
      (is (bytes= (address-bytes code-address)
                  (subseq (hash32-bytes (third (log-entry-topics trace-log)))
                          12 32))))))

(deftest amsterdam-failed-value-call-consumes-transfer-trace-index
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000200"))
         (context (make-evm-context :state state
                                    :address contract
                                    :caller contract
                                    :chain-rules
                                    (amsterdam-transfer-test-rules)))
         ;; The insufficient-balance CALL fails before execution, then LOG0.
         (code #(#x60 0 #x60 0 #x60 0 #x60 0
                 #x60 7 #x60 #x22 #x61 #xff #xff #xf1
                 #x50 #x5f #x5f #xa0 #x00))
         (*evm-trace-transfers-p* t)
         (*evm-log-tracer* (make-evm-log-tracer)))
    (state-db-set-account state contract (make-state-account :balance 0))
    (let ((result
            (execute-bytecode
             code
             :context context
             :gas-limit 500000
             :gas-budget
             (make-evm-gas-budget :regular 500000 :state 500000))))
      (is (eq :stopped (evm-result-status result)))
      (is (equal '(1) (evm-log-tracer-indices *evm-log-tracer*)))
      (is (= 2 (evm-log-tracer-count *evm-log-tracer*))))))

(deftest amsterdam-selfdestruct-traces-native-log-before-pseudo-log
  (let* ((state (make-state-db))
         (contract
           (address-from-hex
            "0x0000000000000000000000000000000000000200"))
         (context (make-evm-context :state state
                                    :address contract
                                    :caller contract
                                    :chain-rules
                                    (amsterdam-transfer-test-rules)))
         (*evm-trace-transfers-p* t)
         (*evm-log-tracer* (make-evm-log-tracer)))
    (state-db-set-account state contract (make-state-account :balance 10))
    (let* ((result
             (execute-bytecode
              #(#x60 #x22 #xff)
              :context context
              :gas-limit 500000
              :gas-budget
              (make-evm-gas-budget :regular 500000 :state 500000)))
           (logs (nreverse (evm-log-tracer-logs *evm-log-tracer*))))
      (is (eq :selfdestructed (evm-result-status result)))
      (is (= 2 (length logs)))
      (is (string= "0xfffffffffffffffffffffffffffffffffffffffe"
                   (address-to-hex (log-entry-address (first logs)))))
      (is (string= "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
                   (address-to-hex (log-entry-address (second logs))))))))

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
      (is (= 2 (length (receipt-logs receipt))))
      (is (string=
           "0xcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca5"
           (hash32-to-hex
            (first (log-entry-topics (second (receipt-logs receipt)))))))
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
    ;; Amsterdam: the EIP-2780 base of a value-free call to another account,
    ;; EIP-8038's 3000 per address and key, and EIP-7981's 20 and 32 bytes at
    ;; the EIP-7976 price of 64 gas per byte.
    (is (= (+ 12000 3000 3000 3000 (* 20 64) (* 32 64))
           (transaction-intrinsic-gas
            tx :chain-rules (amsterdam-transfer-test-rules))))))

(defun amsterdam-intrinsic-test-transaction
    (&key to (value 0) (data #()) access-list authorization-list)
  (if authorization-list
      (make-set-code-transaction
       :chain-id 1 :nonce 0 :max-priority-fee-per-gas 1 :max-fee-per-gas 1
       :gas-limit 1000000 :to to :value value :data data
       :access-list access-list :authorization-list authorization-list
       :y-parity 0 :r 1 :s 1)
      (make-access-list-transaction
       :chain-id 1 :nonce 0 :gas-price 1 :gas-limit 1000000
       :to to :value value :data data :access-list access-list)))

(deftest amsterdam-intrinsic-and-floor-gas-follow-eip2780-7976-7981
  ;; Every number is geth v1.17.6 core/state_transition.go IntrinsicGas and
  ;; FloorDataGas under IsAmsterdam, spelled out term by term.
  (let* ((rules (amsterdam-transfer-test-rules))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000011"))
         (other (address-from-hex
                 "0x0000000000000000000000000000000000000022"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (flet ((intrinsic (tx &optional (from sender))
             (transaction-intrinsic-gas tx :chain-rules rules :sender from))
           (floor-gas (tx &optional (from sender))
             (transaction-effective-floor-gas tx rules :sender from)))
      ;; EIP-2780 base: 12000 for the sender, then the recipient's cold touch
      ;; (3000) or the created account's access (11000), then the value's
      ;; transfer log (1756) and recipient balance write (4244).
      (is (= 21000 (intrinsic (amsterdam-intrinsic-test-transaction
                               :to other :value 1))))
      (is (= 15000 (intrinsic (amsterdam-intrinsic-test-transaction
                               :to other))))
      (is (= 12000 (intrinsic (amsterdam-intrinsic-test-transaction
                               :to sender :value 1))))
      (is (= (+ 12000 11000 (* 32 16) 2)
             (intrinsic (amsterdam-intrinsic-test-transaction
                         :data (make-array 32 :element-type '(unsigned-byte 8)
                                              :initial-element 1)))))
      (is (= (+ 12000 11000 1756)
             (intrinsic (amsterdam-intrinsic-test-transaction :value 1))))
      ;; Calldata keeps its 4/16 intrinsic price.
      (is (= (+ 15000 4 16)
             (intrinsic (amsterdam-intrinsic-test-transaction
                         :to other :data #(0 1)))))
      ;; EIP-8037's per-authorization floor replaces Prague's 25000.
      (is (= (+ 15000 (* 2 7816))
             (intrinsic
              (amsterdam-intrinsic-test-transaction
               :to other
               :authorization-list
               (loop repeat 2
                     collect (make-set-code-authorization
                              :chain-id 1 :address other :nonce 0
                              :y-parity 0 :r 1 :s 1))))))
      ;; Unknown sender: NIL prices the call as a transfer to another
      ;; account, :SELF-TRANSFER-BOUND as a self-transfer.
      (is (= 21000 (intrinsic (amsterdam-intrinsic-test-transaction
                               :to sender :value 1)
                              nil)))
      (is (= 12000 (intrinsic (amsterdam-intrinsic-test-transaction
                               :to other :value 1)
                              :self-transfer-bound)))
      ;; EIP-7976 floor: every calldata byte is 4 tokens of 16 gas, zero or
      ;; not, on the EIP-2780 base; EIP-7981 adds 80 tokens per address and
      ;; 128 per key.
      (is (= (+ 15000 (* 16 4 2))
             (floor-gas (amsterdam-intrinsic-test-transaction
                         :to other :data #(0 1)))))
      (is (= (+ 12000 (* 16 4 3))
             (floor-gas (amsterdam-intrinsic-test-transaction
                         :to sender :value 1 :data #(0 0 7)))))
      (is (= (+ 15000 (* 16 (+ 80 128)))
             (floor-gas (amsterdam-intrinsic-test-transaction
                         :to other
                         :access-list
                         (list (make-access-list-entry
                                :address other :storage-keys (list slot)))))))
      ;; Prague keeps EIP-7623: 21000 plus 10 per token, a zero byte 1 token.
      (is (= (+ 21000 (* 10 (+ 1 4)))
             (transaction-effective-floor-gas
              (amsterdam-intrinsic-test-transaction :to other :data #(0 1))
              (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t
                                :prague-p t)
              :sender sender))))))

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

(deftest amsterdam-protocol-system-call-has-a-state-reservoir
  ;; geth v1.17.6 systemCallGasBudget: an Amsterdam protocol call runs with its
  ;; 30M regular gas plus a state reservoir of SYSTEM_MAX_SSTORES_PER_CALL (16)
  ;; new storage slots. Without the reservoir a slot's 97,920 state gas spills
  ;; into the regular budget; here that budget is 30,000, so the call would
  ;; run out of gas (tests-glamsterdam-devnet@v7.2.1 eip8282
  ;; system_contract_reaches_gas_limit expects the block to stay VALID).
  (let ((target (address-from-hex
                 "0x0000000000000000000000000000000000000abc"))
        (header (make-block-header :number 1 :timestamp 1 :gas-limit 30000000)))
    ;; PUSH1 1, PUSH1 0, SSTORE, STOP: one new slot. Prague is the control
    ;; that the call itself fits 30,000 gas there.
    (dolist (rules (list (amsterdam-transfer-test-rules)
                         (make-chain-rules :chain-id 1 :berlin-p t :london-p t
                                           :shanghai-p t :cancun-p t
                                           :prague-p t)))
      (let ((state (make-state-db)))
        (state-db-set-code state target (hex-to-bytes "0x600160005500"))
        (ethereum-lisp.execution::execute-protocol-system-call
         state target #() header rules
         :gas-limit 30000 :require-success-p t)
        (is (= 1 (state-db-get-storage state target (zero-hash32))))))
    (is (= (* 16 64 1530)
           (evm-gas-budget-state
            (ethereum-lisp.execution::protocol-system-call-gas-budget
             30000 (amsterdam-transfer-test-rules)))))
    (is (= 0
           (evm-gas-budget-state
            (ethereum-lisp.execution::protocol-system-call-gas-budget
             30000 (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t
                                     :prague-p t)))))))
