(in-package #:ethereum-lisp.test)

(deftest evm-callcode-and-delegatecall-identity-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 1 95 83 96 2 96 1 83 96 3 96 2 83))
         (callcode-code #(96 3 95 96 3 95 95 96 4 96 100 242 96 3 95 243))
         (delegatecall-code #(96 3 95 96 3 95 96 4 96 100 244 96 3 95 243))
         (callcode-result (execute-bytecode (concat-bytes setup callcode-code)
                                            :context context))
         (delegatecall-result (execute-bytecode
                               (concat-bytes setup delegatecall-code)
                               :context context)))
    (is (= 1 (first (evm-result-stack callcode-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data callcode-result)))
    (is (= 1 (first (evm-result-stack delegatecall-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data delegatecall-result)))))

(deftest evm-call-family-resolves-delegated-code
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (delegated (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (context (make-evm-context :state state :address contract))
         ;; Return ADDRESS. CALLCODE/DELEGATECALL should see CONTRACT;
         ;; STATICCALL should see the delegated callee address.
         (target-code #(#x30 95 #x52 96 32 95 #xf3))
         (callcode-code #(96 32 95 95 95 95
                          115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                          96 100 #xf2 61 96 32 95 #xf3))
         (delegatecall-code #(96 32 95 95 95
                              115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                              96 100 #xf4 61 96 32 95 #xf3))
         (staticcall-code #(96 32 95 95 95
                            115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                            96 100 #xfa 61 96 32 95 #xf3)))
    (state-db-set-code state delegated (set-code-delegation-code target))
    (state-db-set-code state target target-code)
    (labels ((check (code expected-address)
               (let ((result (execute-bytecode code :context context)))
                 (is (eq :returned (evm-result-status result)))
                 (is (= 32 (first (evm-result-stack result))))
                 (is (= 1 (second (evm-result-stack result))))
                 (is (= (bytes-to-integer (address-bytes expected-address))
                        (bytes-to-integer
                         (evm-result-return-data result)))))))
      (check callcode-code contract)
      (check delegatecall-code contract)
      (check staticcall-code delegated))))

(deftest evm-delegatecall-uses-current-storage-and-preserves-callvalue
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (external-caller (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state
                                    :address contract
                                    :caller external-caller
                                    :call-value 9))
         (library-code #(96 42 96 1 85 52 96 0 82 96 32 96 0 243))
         (contract-code #(96 32 95 95 95
                          115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                          97 #x75 #x30 244 61 96 32 95 243)))
    (state-db-set-code state library library-code)
    (let ((result (execute-bytecode contract-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 9 (aref (evm-result-return-data result) 31)))
      (is (= 42 (state-db-get-storage state contract slot)))
      (is (= 0 (state-db-get-storage state library slot))))))

(deftest evm-callcode-uses-current-storage-and-explicit-callvalue
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address contract :call-value 3))
         (library-code #(96 77 96 1 85 52 96 0 82 96 32 96 0 243))
         (contract-code #(96 32 95 95 95 96 8
                          115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                          97 #x75 #x30 242 61 96 32 95 243)))
    (state-db-set-account state contract (make-state-account :balance 10))
    (state-db-set-code state library library-code)
    (let ((result (execute-bytecode contract-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 8 (aref (evm-result-return-data result) 31)))
      (is (= 77 (state-db-get-storage state contract slot)))
      (is (= 0 (state-db-get-storage state library slot)))
      (is (= 10 (state-account-balance (state-db-get-account state contract)))))))

(deftest evm-callcode-fails-when-value-exceeds-current-balance
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (library-code #(96 1 96 1 85 0))
         (contract-code #(95 95 95 95 96 8
                          115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                          96 100 242 0)))
    (state-db-set-account state contract (make-state-account :balance 7))
    (state-db-set-code state library library-code)
    (let ((result (execute-bytecode contract-code :context context)))
      (is (= 0 (first (evm-result-stack result)))))))

