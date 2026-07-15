(in-package #:ethereum-lisp.test)

(deftest evm-call-executes-callee-and-copies-return-data
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(96 42 96 0 82 96 32 96 0 243))
         (caller-code #(96 32 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 241 61 96 32 95 243)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 42 (aref (evm-result-return-data result) 31))))))

(deftest evm-call-merges-successful-child-refund-counter
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000f0"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address caller))
         ;; CALL callee with no value/input/output.
         (caller-code #(#x5f #x5f #x5f #x5f #x5f #x60 #xf0
                        #x61 #xc3 #x50 #xf1 #x00)))
    (state-db-set-code state callee #(95 96 1 85 0))
    (state-db-set-storage state callee slot 7)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 4800 (evm-result-refund-counter result)))
      (is (= 0 (state-db-get-storage state callee slot))))))

(deftest evm-call-discards-reverted-child-refund-counter
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000f1"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address caller))
         ;; CALL callee with no value/input/output.
         (caller-code #(#x5f #x5f #x5f #x5f #x5f #x60 #xf1
                        #x61 #xc3 #x50 #xf1 #x00)))
    (state-db-set-code state callee #(95 96 1 85 95 95 253))
    (state-db-set-storage state callee slot 7)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 0 (evm-result-refund-counter result)))
      (is (= 7 (state-db-get-storage state callee slot))))))

(deftest evm-call-resolves-delegated-callee-code
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (delegated (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (context (make-evm-context :state state :address caller))
         ;; Return ADDRESS, exercising callee context while using code resolved
         ;; from the delegation target.
         (target-code #(#x30 95 #x52 96 32 95 #xf3))
         (caller-code #(96 32 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 241 61 96 32 95 243)))
    (state-db-set-code state delegated (set-code-delegation-code target))
    (state-db-set-code state target target-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= (bytes-to-integer (address-bytes delegated))
             (bytes-to-integer (evm-result-return-data result)))))))

(deftest evm-call-to-delegation-targeting-precompile-does-not-run-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (delegated (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (identity-precompile (address-from-hex "0x0000000000000000000000000000000000000004"))
         (context (make-evm-context :state state :address caller))
         (caller-code #(96 42 95 82
                        96 1 95 96 1 96 31 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 241
                        96 1 95 243)))
    (state-db-set-code state delegated
                       (set-code-delegation-code identity-precompile))
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 1 (length (evm-result-return-data result))))
      (is (= 0 (aref (evm-result-return-data result) 0))))))

(deftest evm-call-forwards-stack-gas-to-callee
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(#x5a 96 0 82 96 32 96 0 243))
         (caller-code #(96 32 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 241
                        96 32 95 243)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 2642 (evm-result-gas-used result)))
      (is (= 98 (bytes-to-integer (evm-result-return-data result)))))
    (let ((clamped (execute-bytecode caller-code
                                     :context (make-evm-context :state state
                                                                :address caller)
                                     :gas-limit 2700)))
      (is (= 1 (first (evm-result-stack clamped))))
      (is (= 2642 (evm-result-gas-used clamped)))
      (is (= 77 (bytes-to-integer (evm-result-return-data clamped)))))))

(deftest evm-call-child-frame-is-not-capped-at-100000-steps
  (let* ((state (make-state-db))
         (caller
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (middle
           (address-from-hex
            "0x00000000000000000000000000000000000000bb"))
         (callee
           (address-from-hex
            "0x00000000000000000000000000000000000000cc"))
         (context (make-evm-context :state state :address caller))
         (gasless-context (make-evm-context :state state :address caller))
         (unbounded-context (make-evm-context :state state :address caller)))
    (labels ((call-and-stop (target)
               ;; CALL with 400,000 requested gas and empty input/output.
               (concat-bytes
                #(#x5f #x5f #x5f #x5f #x5f #x73)
                (address-bytes target)
                #(#x62 #x06 #x1a #x80 #xf1 #x00))))
      (let ((caller-code (call-and-stop callee))
            (middle-code (call-and-stop callee))
            (gasless-code (call-and-stop middle)))
        (state-db-set-code state callee (evm-long-loop-code))
        (state-db-set-code state middle middle-code)
        (let* ((result (execute-bytecode caller-code
                                         :context context
                                         :gas-limit 420000))
               (gasless-error
                 (capture-evm-step-limit-error
                  (lambda ()
                    ;; Both finite-gas descendants inherit the gasless root's
                    ;; one execution-tree diagnostic budget.
                    (execute-bytecode gasless-code
                                      :context gasless-context))))
               (unbounded-result
                 (execute-bytecode gasless-code
                                   :context unbounded-context
                                   :max-steps nil)))
          (is (eq :stopped (evm-result-status result)))
          (is (= 1 (first (evm-result-stack result))))
          ;; 390,005 child gas plus 2,616 for pushes, cold access, CALL, STOP.
          (is (= 392621 (evm-result-gas-used result)))
          (is gasless-error)
          (is (= 100000
                 (evm-step-limit-error-limit gasless-error)))
          (is (= 100001
                 (evm-step-limit-error-steps gasless-error)))
          (is (not (typep gasless-error 'evm-error)))
          (is (eq :stopped (evm-result-status unbounded-result)))
          (is (= 1 (first (evm-result-stack unbounded-result)))))))))

(deftest evm-tree-step-limit-rolls-back-root-state-and-context
  (let* ((state (make-state-db))
         (caller
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (middle
           (address-from-hex
            "0x00000000000000000000000000000000000000bb"))
         (callee
           (address-from-hex
            "0x00000000000000000000000000000000000000cc"))
         (sentinel
           (address-from-hex
            "0x00000000000000000000000000000000000000dd"))
         (caller-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (middle-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (callee-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (sentinel-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (accessed-addresses (make-hash-table :test 'equalp))
         (accessed-storage (make-hash-table :test 'equalp))
         (storage-clears (make-hash-table :test 'equalp))
         (storage-originals (make-hash-table :test 'equalp))
         (context
           (make-evm-context
            :state state
            :address caller
            :accessed-addresses accessed-addresses
            :accessed-storage accessed-storage
            :storage-clears storage-clears
            :storage-originals storage-originals)))
    (labels ((storage-key (address slot)
               (concat-bytes (address-bytes address) (hash32-bytes slot)))
             (call-and-stop (prefix target)
               (concat-bytes
                prefix
                #(#x5f #x5f #x5f #x5f #x5f #x73)
                (address-bytes target)
                #(#x61 #xff #xff #xf1 #x00))))
      (let* ((caller-key (storage-key caller caller-slot))
             (middle-key (storage-key middle middle-slot))
             (callee-key (storage-key callee callee-slot))
             (sentinel-key (storage-key sentinel sentinel-slot))
             (callee-code #(#x60 #x03 #x54 #x5b #x00))
             (middle-code
               (call-and-stop #(#x5f #x60 #x02 #x55) callee))
             (caller-code
               (call-and-stop #(#x5f #x60 #x01 #x55) middle)))
        (state-db-set-storage state caller caller-slot 7)
        (state-db-set-storage state middle middle-slot 7)
        (state-db-set-storage state callee callee-slot 9)
        (state-db-set-code state middle middle-code)
        (state-db-set-code state callee callee-code)
        (setf (gethash (address-bytes caller) accessed-addresses) :caller
              (gethash (address-bytes sentinel) accessed-addresses) :sentinel
              (gethash sentinel-key accessed-storage) :sentinel
              (gethash sentinel-key storage-clears) :sentinel
              (gethash sentinel-key storage-originals) :sentinel)
        (let* ((initial-root (state-db-root state))
               (condition
                 (capture-evm-step-limit-error
                  (lambda ()
                    ;; The grandchild and middle frame have returned before
                    ;; the root's final STOP attempts global step 28.
                    (execute-bytecode caller-code
                                      :context context
                                      :max-steps 27)))))
          (is condition)
          (is (= 27 (evm-step-limit-error-limit condition)))
          (is (= 28 (evm-step-limit-error-steps condition)))
          (is (= (1- (length caller-code))
                 (evm-step-limit-error-pc condition)))
          (is (ethereum-lisp.types:hash32=
               initial-root (state-db-root state)))
          (is (= 7 (state-db-get-storage state caller caller-slot)))
          (is (= 7 (state-db-get-storage state middle middle-slot)))
          (is (= 9 (state-db-get-storage state callee callee-slot)))
          (is (= 2 (hash-table-count accessed-addresses)))
          (is (= 1 (hash-table-count accessed-storage)))
          (is (= 1 (hash-table-count storage-clears)))
          (is (= 1 (hash-table-count storage-originals)))
          (is (eq :caller
                  (gethash (address-bytes caller) accessed-addresses)))
          (is (eq :sentinel
                  (gethash (address-bytes sentinel) accessed-addresses)))
          (is (not (gethash (address-bytes middle) accessed-addresses)))
          (is (not (gethash (address-bytes callee) accessed-addresses)))
          (dolist (key (list caller-key middle-key callee-key))
            (is (not (gethash key accessed-storage))))
          (is (not (gethash caller-key storage-clears)))
          (is (not (gethash middle-key storage-clears)))
          (is (not (gethash caller-key storage-originals)))
          (is (not (gethash middle-key storage-originals))))
        ;; A fresh tree budget succeeds at the exact 28-step boundary.
        (let ((result (execute-bytecode caller-code
                                        :context context
                                        :max-steps 28)))
          (is (eq :stopped (evm-result-status result)))
          (is (= 1 (first (evm-result-stack result))))
          (is (= 9600 (evm-result-refund-counter result)))
          (is (= 0 (state-db-get-storage state caller caller-slot)))
          (is (= 0 (state-db-get-storage state middle middle-slot))))))))

(deftest evm-call-charges-cold-then-warm-account-access
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (call-callee (concat-bytes #(#x5f #x5f #x5f #x5f #x5f #x73)
                                    (address-bytes callee)
                                    #(#x5f #xf1)))
         (code (concat-bytes call-callee call-callee #(0))))
    (let ((result (execute-bytecode code
                                    :context (make-evm-context
                                              :state state
                                              :address caller))))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 2730 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode code
                        :context (make-evm-context :state state
                                                   :address caller)
                        :gas-limit 2729))))

(deftest evm-call-memory-expansion-happens-before-child-gas
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (code #(96 1 96 96 96 1 96 64
                 115 0 0 0 0 0 0 0 0 0 0
                 0 0 0 0 0 0 0 0 0 187
                 96 100 #xfa #x59 0)))
    (let ((result (execute-bytecode code :context context)))
      (declare (ignore target))
      (is (= 128 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 2632 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode code :context (make-evm-context :state state
                                                        :address caller)
                        :gas-limit 2629))))

(deftest evm-call-transfers-value-to-empty-account
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (context (make-evm-context :state state :address caller))
         (code #(95 95 95 95 96 7
                 115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 204
                 96 100 241 0)))
    (state-db-set-account state caller (make-state-account :balance 10))
    (let ((result (execute-bytecode code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 34317 (evm-result-gas-used result)))
      (is (= 3 (state-account-balance (state-db-get-account state caller))))
      (is (= 7 (state-account-balance (state-db-get-account state target)))))))

(deftest evm-call-self-transfer-preserves-value-balance
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (code (concat-bytes #(#x5f #x5f #x5f #x5f #x60 #x07 #x73)
                             (address-bytes caller)
                             #(#x60 #x64 #xf1 #x00))))
    (state-db-set-account state caller (make-state-account :balance 10))
    (let ((result (execute-bytecode code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 9317 (evm-result-gas-used result)))
      (is (= 10 (state-account-balance
                 (state-db-get-account state caller)))))))

(deftest evm-call-fails-when-value-exceeds-balance
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (context (make-evm-context :state state :address caller))
         (code #(95 95 95 95 96 7
                 115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 204
                 96 100 241 0)))
    (state-db-set-account state caller (make-state-account :balance 3))
    (let ((result (execute-bytecode code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 34317 (evm-result-gas-used result)))
      (is (= 3 (state-account-balance (state-db-get-account state caller))))
      (is (not (state-db-get-account state target))))))

(deftest evm-call-insufficient-balance-keeps-callee-warm
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (rules (make-chain-rules :chain-id 1
                                  :homestead-p t
                                  :eip150-p t
                                  :eip155-p t
                                  :eip158-p t
                                  :byzantium-p t
                                  :constantinople-p t
                                  :istanbul-p t
                                  :berlin-p t
                                  :london-p t
                                  :shanghai-p t))
         (context (make-evm-context :state state
                                    :address caller
                                    :chain-rules rules))
         (code (concat-bytes
                #(#x60 #x00 #x60 #x00 #x60 #x00 #x60 #x00 #x60 #x01 #x73)
                (address-bytes target)
                #(#x5a #xf1 #x60 #x00 #x55 #x5a #x73)
                (address-bytes target)
                #(#x31 #x5a #x90 #x50 #x90 #x03 #x60 #x05 #x90 #x03
                  #x60 #x01 #x55 #x00))))
    (state-db-set-account state caller (make-state-account :nonce 1))
    (state-db-set-account state target (make-state-account :balance 1))
    (let ((result (execute-bytecode code :context context :gas-limit 1000000)))
      (is (eq :stopped (evm-result-status result)))
      (is (= 100 (state-db-get-storage state caller slot))))))

(deftest evm-call-with-value-adds-stipend-to-child-gas
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(#x5a 96 0 82 96 32 96 0 243))
         (caller-code #(96 32 95 95 95 96 1
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        95 241
                        96 32 95 243)))
    (state-db-set-account state caller (make-state-account :balance 10))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 9342 (evm-result-gas-used result)))
      (is (= 2298 (bytes-to-integer (evm-result-return-data result))))
      (is (= 9 (state-account-balance (state-db-get-account state caller))))
      (is (= 1 (state-account-balance (state-db-get-account state callee)))))))

(deftest evm-call-value-stipend-discounts-child-selfdestruct-gas
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(#x30 #xff))
         (caller-code #(95 95 95 95 96 1
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        97 #xff #xff #xf1 0)))
    (state-db-set-account state caller (make-state-account :balance 10))
    (state-db-set-code state callee callee-code)
    (state-db-set-account state callee
                          (make-state-account :code-hash
                                              (keccak-256-hash callee-code)))
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 14319 (evm-result-gas-used result)))
      (is (= 9 (state-account-balance (state-db-get-account state caller))))
      (is (= 1 (state-account-balance
                (state-db-get-account state callee)))))))

(deftest evm-call-revert-rolls-back-and-keeps-return-data
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(96 42 96 1 85 96 99 96 0 82 96 32 96 0 253))
         (caller-code #(96 32 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        97 #x75 #x30 241 61 96 32 95 243)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 0 (second (evm-result-stack result))))
      (is (= 99 (aref (evm-result-return-data result) 31)))
      (is (= 0 (state-db-get-storage state callee slot))))))

(deftest evm-call-error-rolls-back-and-clears-return-data
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(96 42 96 1 85 254))
         (caller-code #(96 32 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 241 61 96 32 95 243)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 0 (second (evm-result-stack result))))
      (is (bytes= (make-byte-vector 32) (evm-result-return-data result)))
      (is (= 0 (state-db-get-storage state callee slot))))))

(deftest evm-read-only-call-allows-zero-value-and-blocks-value
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (readonly-context (make-evm-context :state state
                                             :address caller
                                             :read-only-p t))
         (callee-code #(96 7 96 0 82 96 32 96 0 243))
         (zero-value-call #(96 32 95 95 95 95
                            115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                            96 100 241 96 32 95 243))
         (value-call #(95 95 95 95 96 1
                       115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                       96 100 241 0)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode zero-value-call :context readonly-context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 7 (aref (evm-result-return-data result) 31))))
    (signals evm-error
      (execute-bytecode value-call :context readonly-context))))

(deftest evm-staticcall-executes-read-only-and-copies-return-data
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(96 12 96 0 82 96 32 96 0 243))
         (caller-code #(96 32 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 250 61 96 32 95 243)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (eq :returned (evm-result-status result)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 1 (second (evm-result-stack result))))
      (is (= 12 (aref (evm-result-return-data result) 31))))))

(deftest evm-staticcall-blocks-state-writes
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (context (make-evm-context :state state :address caller))
         (callee-code #(96 42 96 1 85 0))
         (caller-code #(95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        96 100 250 0)))
    (state-db-set-code state callee callee-code)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 0 (state-db-get-storage state callee slot))))))

(deftest evm-selfdestruct-transfers-balance-and-stops
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (beneficiary (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (code #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                 #xff
                 96 1 0)))
    (state-db-set-account state contract (make-state-account :balance 7))
    (state-db-set-account state beneficiary (make-state-account :balance 5))
    (let ((result (execute-bytecode code :context context)))
      (is (eq :selfdestructed (evm-result-status result)))
      (is (= 7603 (evm-result-gas-used result)))
      (is (null (evm-result-stack result)))
      (is (= 0 (state-account-balance (state-db-get-account state contract))))
      (is (= 12 (state-account-balance
                 (state-db-get-account state beneficiary))))))
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address contract))
         (code #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 170
                 #xff
                 96 1 0)))
    (state-db-set-account state contract (make-state-account :balance 7))
    (let ((result (execute-bytecode code :context context)))
      (is (eq :selfdestructed (evm-result-status result)))
      (is (= 7603 (evm-result-gas-used result)))
      (is (= 7 (state-account-balance (state-db-get-account state contract))))))
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (beneficiary (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (accessed-addresses (make-hash-table :test 'equalp))
         (context (make-evm-context :state state
                                    :address contract
                                    :accessed-addresses accessed-addresses))
         (code #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                 #xff)))
    (setf (gethash (address-bytes beneficiary) accessed-addresses) t)
    (state-db-set-account state contract (make-state-account :balance 7))
    (state-db-set-account state beneficiary (make-state-account :balance 5))
    (let ((result (execute-bytecode code :context context)))
      (is (eq :selfdestructed (evm-result-status result)))
      (is (= 5003 (evm-result-gas-used result)))
      (is (= 12 (state-account-balance
                 (state-db-get-account state beneficiary)))))))

(deftest evm-selfdestruct-charges-new-account-gas
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (beneficiary (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (code #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                 #xff)))
    (state-db-set-account state contract (make-state-account :balance 7))
    (let ((result (execute-bytecode code :context context)))
      (is (eq :selfdestructed (evm-result-status result)))
      (is (= 32603 (evm-result-gas-used result)))
      (is (= 7 (state-account-balance
                (state-db-get-account state beneficiary)))))))

(deftest evm-selfdestruct-restores-cold-beneficiary-on-revert
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (callee (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (beneficiary (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address caller))
         ;; CALL callee; callee selfdestructs to beneficiary; parent reverts.
         (caller-code #(95 95 95 95 95
                        115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 204
                        97 #xff #xff #xf1
                        95 95 #xfd))
         (callee-code #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                        #xff)))
    (state-db-set-code state callee callee-code)
    (state-db-set-account state beneficiary (make-state-account :balance 5))
    (let ((reverted (execute-bytecode caller-code :context context))
          (after-revert (execute-bytecode
                         #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                           #x31 0)
                        :context context)))
      (is (eq :reverted (evm-result-status reverted)))
      (is (= 5 (state-account-balance
                (state-db-get-account state beneficiary))))
      (is (= 5 (first (evm-result-stack after-revert))))
      (is (= 2603 (evm-result-gas-used after-revert))))))

(deftest evm-selfdestruct-read-only-error
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (readonly-context (make-evm-context :state state
                                             :address contract
                                             :read-only-p t)))
    (signals evm-error
      (execute-bytecode #(95 #xff) :context readonly-context))))
