(in-package #:ethereum-lisp.test)

(deftest evm-adds-two-numbers
  (let ((result (execute-bytecode #(96 2 96 3 1 0))))
    (is (eq :stopped (evm-result-status result)))
    (is (= 5 (first (evm-result-stack result))))
    (is (= 9 (evm-result-gas-used result)))))

(deftest evm-context-carries-chain-rules
  (let* ((rules (make-chain-rules :chain-id 1 :london-p t :prague-p t))
         (context (make-evm-context :chain-id 1 :chain-rules rules)))
    (is (eq rules (evm-context-chain-rules context)))
    (is (chain-rules-london-p (evm-context-chain-rules context)))
    (is (chain-rules-prague-p (evm-context-chain-rules context)))))

(deftest evm-chain-rules-gate-fork-opcodes
  (let* ((pre-shanghai
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1 :london-p t)))
         (shanghai
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t)))
         (pre-cancun
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t)))
         (cancun
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t
                                               :cancun-p t)
                             :blob-base-fee 7)))
    (signals evm-error
      (execute-bytecode #(#x5f 0) :context pre-shanghai))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(#x5f 0) :context shanghai)))))
    (signals evm-error
      (execute-bytecode #(96 0 96 0 96 0 #x5e 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 0 #x5c 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 2 96 1 #x5d 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 0 #x49 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(#x4a 0) :context pre-cancun))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 #x5e 0)
                               :context cancun))))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(96 0 #x5c 0) :context cancun)))))
    (is (= 7 (first (evm-result-stack
                     (execute-bytecode #(#x4a 0) :context cancun)))))))

(deftest evm-chain-rules-gate-environment-opcodes
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (pre-istanbul
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t)))
         (istanbul
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t
                                               :istanbul-p t)))
         (london
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t
                                               :istanbul-p t
                                               :berlin-p t
                                               :london-p t))))
    (state-db-add-balance state address 13)
    (signals evm-error
      (execute-bytecode #(#x46 0) :context pre-istanbul))
    (signals evm-error
      (execute-bytecode #(#x47 0) :context pre-istanbul))
    (signals evm-error
      (execute-bytecode #(#x48 0) :context istanbul))
    (is (= 7 (first (evm-result-stack
                     (execute-bytecode #(#x46 0) :context istanbul)))))
    (is (= 13 (first (evm-result-stack
                      (execute-bytecode #(#x47 0) :context istanbul)))))
    (is (= 11 (first (evm-result-stack
                      (execute-bytecode #(#x48 0) :context london)))))))

(deftest evm-chain-rules-gate-legacy-fork-opcodes
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (frontier (make-evm-context :state state
                                     :address address
                                     :chain-rules
                                     (make-chain-rules :chain-id 1)))
         (homestead (make-evm-context :state state
                                      :address address
                                      :chain-rules
                                      (make-chain-rules :chain-id 1
                                                        :homestead-p t)))
         (pre-byzantium
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t)))
         (byzantium
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t
                                               :byzantium-p t)))
         (pre-constantinople byzantium)
         (constantinople
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t
                                               :byzantium-p t
                                               :constantinople-p t))))
    (signals evm-error
      (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xf4 0)
                        :context frontier))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xf4 0)
                               :context homestead))))
    (dolist (code (list #(#x3d 0)
                        #(96 0 96 0 96 0 #x3e 0)
                        #(96 0 96 0 #xfd)
                        #(96 0 96 0 96 0 96 0 96 0 96 0 #xfa 0)))
      (signals evm-error
        (execute-bytecode code :context pre-byzantium)))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(#x3d 0) :context byzantium)))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 #x3e 0)
                               :context byzantium))))
    (is (eq :reverted
            (evm-result-status
             (execute-bytecode #(96 0 96 0 #xfd) :context byzantium))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xfa 0)
                               :context byzantium))))
    (dolist (code (list #(96 1 96 1 #x1b 0)
                        #(96 1 96 2 #x1c 0)
                        #(96 1 96 2 #x1d 0)
                        #(96 0 #x3f 0)
                        #(96 0 96 0 96 0 96 0 #xf5 0)))
      (signals evm-error
        (execute-bytecode code :context pre-constantinople)))
    (is (= 2 (first (evm-result-stack
                     (execute-bytecode #(96 1 96 1 #x1b 0)
                                       :context constantinople)))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 #x3f 0) :context constantinople))))
    (is (eq :stopped
            (evm-result-status
            (execute-bytecode #(96 0 96 0 96 0 96 0 #xf5 0)
                               :context constantinople))))))

(deftest evm-chain-rules-gate-active-precompiles
  (let* ((frontier-rules (make-chain-rules :chain-id 1))
         (byzantium-rules (make-chain-rules :chain-id 1 :byzantium-p t))
         (istanbul-rules (make-chain-rules :chain-id 1
                                           :byzantium-p t
                                           :istanbul-p t))
         (cancun-rules (make-chain-rules :chain-id 1
                                         :byzantium-p t
                                         :istanbul-p t
                                         :berlin-p t
                                         :london-p t
                                         :shanghai-p t
                                         :cancun-p t))
         (frontier-context (make-evm-context :chain-rules frontier-rules))
         (cancun-context (make-evm-context :chain-rules cancun-rules))
         (frontier-accesses (evm-context-accessed-addresses frontier-context))
         (cancun-accesses (evm-context-accessed-addresses cancun-context)))
    (is (ethereum-lisp.evm::active-precompile-address-number-p 4
                                                              frontier-rules))
    (is (not (ethereum-lisp.evm::active-precompile-address-number-p
              5 frontier-rules)))
    (is (ethereum-lisp.evm::active-precompile-address-number-p 5
                                                              byzantium-rules))
    (is (not (ethereum-lisp.evm::active-precompile-address-number-p
              9 byzantium-rules)))
    (is (ethereum-lisp.evm::active-precompile-address-number-p 9
                                                              istanbul-rules))
    (is (ethereum-lisp.evm::active-precompile-address-number-p 10
                                                              cancun-rules))
    (is (gethash (address-bytes (ethereum-lisp.evm::precompile-address 4))
                 frontier-accesses))
    (is (not (gethash (address-bytes (ethereum-lisp.evm::precompile-address 5))
                      frontier-accesses)))
    (is (gethash (address-bytes (ethereum-lisp.evm::precompile-address 10))
                 cancun-accesses))
    (multiple-value-bind (output gas active-p)
        (ethereum-lisp.evm::run-precompile
         (ethereum-lisp.evm::precompile-address 5) #() frontier-rules)
      (is (null output))
      (is (= 0 gas))
      (is (not active-p)))
    (multiple-value-bind (output gas active-p)
        (ethereum-lisp.evm::run-precompile
         (ethereum-lisp.evm::precompile-address 5) #() byzantium-rules)
      (is (byte-vector-p output))
      (is (plusp gas))
      (is active-p))))

(deftest evm-mstore-and-return
  (let ((result (execute-bytecode #(96 42 96 0 82 96 32 96 0 243))))
    (is (eq :returned (evm-result-status result)))
    (is (= 32 (length (evm-result-return-data result))))
    (is (= 42 (aref (evm-result-return-data result) 31)))
    (is (= 18 (evm-result-gas-used result)))))

(deftest evm-memory-expansion-gas-for-load-store
  (let ((mstore-first-word (execute-bytecode #(96 1 95 82 0)))
        (mstore8-second-word (execute-bytecode #(96 255 96 32 83 0)))
        (mload-existing-word (execute-bytecode #(96 1 95 83 95 81 0)))
        (mstore-quadratic-word (execute-bytecode #(96 1 97 2 192 82 0))))
    (is (= 11 (evm-result-gas-used mstore-first-word)))
    (is (= 15 (evm-result-gas-used mstore8-second-word)))
    (is (= 16 (evm-result-gas-used mload-existing-word)))
    (is (= 79 (evm-result-gas-used mstore-quadratic-word))))
  (signals evm-error
    (execute-bytecode #(96 1 95 82 0) :gas-limit 10)))

(deftest evm-dynamic-memory-gas-for-hash-and-copy
  (let* ((context (make-evm-context :input #(1 2 3 4)))
         (sha3-existing-word (execute-bytecode #(96 1 95 82 96 32 95 32 0)))
         (sha3-expands-memory
           (execute-bytecode #(96 1 96 32 32 89 0)))
         (calldatacopy-two-words (execute-bytecode #(96 33 95 95 55 0)
                                                   :context context))
         (calldatacopy-zero (execute-bytecode #(95 95 95 55 0)
                                              :context context))
         (mcopy-expands-source (execute-bytecode #(96 1 96 64 83
                                                   96 33 96 64 95 #x5e 0))))
    (is (= 52 (evm-result-gas-used sha3-existing-word)))
    (is (= 50 (evm-result-gas-used sha3-expands-memory)))
    (is (= 64 (first (evm-result-stack sha3-expands-memory))))
    (is (= 22 (evm-result-gas-used calldatacopy-two-words)))
    (is (= 9 (evm-result-gas-used calldatacopy-zero)))
    (is (= 38 (evm-result-gas-used mcopy-expands-source))))
  (signals evm-error
    (execute-bytecode #(96 33 95 95 55 0)
                      :context (make-evm-context :input #(1 2 3 4))
                      :gas-limit 21)))

(deftest evm-memory-gas-for-return-revert-and-log
  (let* ((returned (execute-bytecode #(96 32 96 32 243)))
         (reverted (execute-bytecode #(96 32 96 32 #xfd)))
         (log0 (execute-bytecode #(96 33 95 160 0)
                                 :context (make-evm-context))))
    (is (eq :returned (evm-result-status returned)))
    (is (= 32 (length (evm-result-return-data returned))))
    (is (= 12 (evm-result-gas-used returned)))
    (is (eq :reverted (evm-result-status reverted)))
    (is (= 12 (evm-result-gas-used reverted)))
    (is (= 1 (length (evm-result-logs log0))))
    (is (= 33 (length (log-entry-data (first (evm-result-logs log0))))))
    (is (= 650 (evm-result-gas-used log0))))
  (signals evm-error
    (execute-bytecode #(96 32 96 32 243) :gas-limit 11)))

(deftest evm-mcopy-overlapping-memory
  (let* ((setup #(96 1 95 83 96 2 96 1 83 96 3 96 2 83
                  96 4 96 3 83 96 5 96 4 83 96 6 96 5 83
                  96 7 96 6 83 96 8 96 7 83 96 9 96 8 83))
         (copy-left #(96 8 96 1 95 #x5e 96 8 95 243))
         (copy-right #(96 8 95 96 1 #x5e 96 9 95 243))
         (left-result (execute-bytecode (concat-bytes setup copy-left)))
         (right-result (execute-bytecode (concat-bytes setup copy-right))))
    (is (bytes= #(2 3 4 5 6 7 8 9) (evm-result-return-data left-result)))
    (is (bytes= #(1 1 2 3 4 5 6 7 8)
                (evm-result-return-data right-result)))))

(deftest evm-push0-dup-swap
  (let ((result (execute-bytecode #(95 96 7 128 144 1 0))))
    (is (= 14 (first (evm-result-stack result))))
    (is (= 0 (second (evm-result-stack result))))))

(deftest evm-rejects-stack-overflow
  (let ((pushes (make-array 1025 :element-type '(unsigned-byte 8)
                                 :initial-element 95)))
    (signals evm-error
      (execute-bytecode pushes)))
  (let ((full-stack-then-dup
          (make-array 1025 :element-type '(unsigned-byte 8)
                           :initial-element 95)))
    (setf (aref full-stack-then-dup 1024) #x80)
    (signals evm-error
      (execute-bytecode full-stack-then-dup))))

(deftest evm-rejects-unsupported-opcode
  (signals evm-error (execute-bytecode #(254))))

(deftest evm-jump-and-jumpi
  (let ((jumped (execute-bytecode #(96 5 86 96 0 91 96 42 0)))
        (not-jumped (execute-bytecode #(95 96 6 87 96 9 91 96 3 1 0))))
    (is (= 42 (first (evm-result-stack jumped))))
    (is (= 12 (first (evm-result-stack not-jumped))))))

(deftest evm-rejects-invalid-jump-and-step-limit
  (signals evm-error (execute-bytecode #(96 1 86)))
  (signals evm-error (execute-bytecode #(96 3 86 97 91 0 91 0)))
  (signals evm-error (execute-bytecode #(91 96 0 86) :max-steps 4)))

(deftest evm-sstore-and-sload-through-state-context
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (execute-bytecode #(96 42 96 1 85) :context context)
    (is (= 42 (state-db-get-storage state address slot)))
    (let ((result (execute-bytecode #(96 1 84 0) :context context)))
      (is (= 42 (first (evm-result-stack result)))))))

(deftest evm-sload-charges-cold-then-warm-storage-read
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; PUSH1 1; SLOAD cold; PUSH1 1; SLOAD warm; STOP.
         (code #(96 1 84 96 1 84 0)))
    (state-db-set-storage state address slot 7)
    (let ((result (execute-bytecode code :context context)))
      (is (= 7 (first (evm-result-stack result))))
      (is (= 2206 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode code
                        :context (make-evm-context :state state
                                                   :address address)
                        :gas-limit 2205))))

(deftest evm-sload-revert-restores-warm-storage-slot
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (state-db-set-storage state address slot 7)
    (let ((reverted (execute-bytecode #(96 1 84 95 95 253)
                                      :context context))
          (after-revert (execute-bytecode #(96 1 84 0)
                                          :context context)))
      (is (eq :reverted (evm-result-status reverted)))
      (is (= 2107 (evm-result-gas-used reverted)))
      (is (= 7 (first (evm-result-stack after-revert))))
      (is (= 2103 (evm-result-gas-used after-revert))))))

(deftest evm-balance-charges-cold-then-warm-account-access
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (code (concat-bytes #(#x73)
                             (address-bytes target)
                             #(#x31 #x73)
                             (address-bytes target)
                             #(#x31 #x00))))
    (state-db-set-account state target (make-state-account :balance 7))
    (let ((result (execute-bytecode code :context context)))
      (is (= 7 (first (evm-result-stack result))))
      (is (= 7 (second (evm-result-stack result))))
      (is (= 2706 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode code
                        :context (make-evm-context :state state
                                                   :address contract)
                        :gas-limit 2705))))

(deftest evm-balance-revert-restores-warm-account-access
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (balance-target (concat-bytes #(#x73)
                                       (address-bytes target)
                                       #(#x31))))
    (state-db-set-account state target (make-state-account :balance 7))
    (let ((reverted (execute-bytecode (concat-bytes balance-target
                                                    #(95 95 #xfd))
                                      :context context))
          (after-revert (execute-bytecode (concat-bytes balance-target
                                                        #(0))
                                          :context context)))
      (is (eq :reverted (evm-result-status reverted)))
      (is (= 2607 (evm-result-gas-used reverted)))
      (is (= 7 (first (evm-result-stack after-revert))))
      (is (= 2603 (evm-result-gas-used after-revert))))))

(deftest evm-sstore-charges-cold-then-warm-storage-access
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 9; SSTORE slot 1 := 10.
         (result (execute-bytecode #(96 9 96 1 85 96 10 96 1 85 0)
                                   :context context)))
    (is (= 22212 (evm-result-gas-used result)))
    (is (= 10 (state-db-get-storage state address slot)))))

(deftest evm-sstore-clear-refund-counter-is-discarded-on-revert
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0; REVERT 0 0.
         (result (progn
                   (state-db-set-storage state address slot 7)
                   (execute-bytecode #(95 96 1 85 95 95 253)
                                     :context context))))
    (is (eq :reverted (evm-result-status result)))
    (is (= 0 (evm-result-refund-counter result)))))

(deftest evm-sstore-recreate-reverses-clear-refund-counter
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0; SSTORE slot 1 := 9.
         (result (progn
                   (state-db-set-storage state address slot 7)
                   (execute-bytecode #(95 96 1 85 96 9 96 1 85 0)
                                     :context context))))
    (is (= 0 (evm-result-refund-counter result)))
    (is (= 9 (state-db-get-storage state address slot)))))

(deftest evm-sstore-created-slot-clear-adds-reset-refund-counter
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 9; SSTORE slot 1 := 0.
         (result (execute-bytecode #(96 9 96 1 85 95 96 1 85 0)
                                   :context context)))
    (is (= 19900 (evm-result-refund-counter result)))
    (is (= 0 (state-db-get-storage state address slot)))))

(deftest evm-sstore-reset-original-nonzero-adds-refund-counter
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 9; SSTORE slot 1 := original 7.
         (result (progn
                   (state-db-set-storage state address slot 7)
                   (execute-bytecode #(96 9 96 1 85 96 7 96 1 85 0)
                                     :context context))))
    (is (= 2800 (evm-result-refund-counter result)))
    (is (= 7 (state-db-get-storage state address slot)))))

(deftest evm-sstore-clear-then-reset-original-nonzero-keeps-reset-refund
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address address))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; SSTORE slot 1 := 0; SSTORE slot 1 := original 7.
         (result (progn
                   (state-db-set-storage state address slot 7)
                   (execute-bytecode #(95 96 1 85 96 7 96 1 85 0)
                                     :context context))))
    (is (= 2800 (evm-result-refund-counter result)))
    (is (= 7 (state-db-get-storage state address slot)))))

(deftest evm-delegatecall-shares-sstore-original-values-for-refunds
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; Parent dirties slot 1 to 9; delegatecall resets it to original 7.
         (caller-code #(96 9 96 1 85 95 95 95 95 96 #xbb 97 #xc3 #x50 #xf4 0)))
    (state-db-set-code state library #(96 7 96 1 85 0))
    (state-db-set-storage state contract slot 7)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 2800 (evm-result-refund-counter result)))
      (is (= 7 (state-db-get-storage state contract slot))))))

(deftest evm-delegatecall-reverses-parent-sstore-clear-refund
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; Parent clears slot 1; delegatecall recreates it as 9.
         (caller-code #(95 96 1 85
                        95 95 95 95 96 #xbb 97 #xc3 #x50 #xf4 0)))
    (state-db-set-code state library #(96 9 96 1 85 0))
    (state-db-set-storage state contract slot 7)
    (let ((result (execute-bytecode caller-code :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 0 (evm-result-refund-counter result)))
      (is (= 9 (state-db-get-storage state contract slot))))))

(deftest evm-storage-context-errors
  (signals evm-error (execute-bytecode #(96 1 84)))
  (let* ((state (make-state-db))
         (context (make-evm-context :state state :read-only-p t)))
    (signals evm-error (execute-bytecode #(96 1 96 2 85) :context context))))

(deftest evm-transient-storage-load-store
  (let* ((transient-storage (make-hash-table :test 'equalp))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (other (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :address contract
                                    :transient-storage transient-storage))
         (other-context (make-evm-context :address other
                                          :transient-storage transient-storage))
         (stored (execute-bytecode #(96 42 96 1 #x5d 96 1 #x5c 96 2 #x5c 0)
                                   :context context))
         (other-load (execute-bytecode #(96 1 #x5c 0) :context other-context))
         (same-load (execute-bytecode #(96 1 #x5c 0) :context context)))
    (is (= 0 (first (evm-result-stack stored))))
    (is (= 42 (second (evm-result-stack stored))))
    (is (= 0 (first (evm-result-stack other-load))))
    (is (= 42 (first (evm-result-stack same-load))))))

(deftest evm-transient-storage-read-only-error
  (let ((readonly-context (make-evm-context :read-only-p t)))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(96 1 #x5c 0)
                                       :context readonly-context)))))
    (signals evm-error
      (execute-bytecode #(96 42 96 1 #x5d) :context readonly-context))))

(deftest evm-transient-storage-revert-rolls-back-frame
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (library (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :state state :address contract))
         (library-code #(96 42 96 1 #x5d 95 95 #xfd))
         (delegatecall-code #(95 95 95 95
                              115 0 0 0 0 0 0 0 0 0 0
                              0 0 0 0 0 0 0 0 0 187
                              96 100 #xf4 96 1 #x5c 0))
         (top-revert #(96 77 96 2 #x5d 95 95 #xfd)))
    (state-db-set-code state library library-code)
    (let ((result (execute-bytecode delegatecall-code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 0 (second (evm-result-stack result)))))
    (let ((reverted (execute-bytecode top-revert :context context)))
      (is (eq :reverted (evm-result-status reverted))))
    (let ((result (execute-bytecode #(96 2 #x5c 0) :context context)))
      (is (= 0 (first (evm-result-stack result)))))))

(deftest evm-context-address-caller-value
  (let* ((context
           (make-evm-context
            :address (address-from-hex "0x000000000000000000000000000000000000000a")
            :caller (address-from-hex "0x000000000000000000000000000000000000000b")
            :call-value 12))
         (result (execute-bytecode #(48 51 52 0) :context context)))
    (is (= 12 (first (evm-result-stack result))))
    (is (= 11 (second (evm-result-stack result))))
    (is (= 10 (third (evm-result-stack result))))))

(deftest evm-calldata-load-size-copy
  (let* ((context (make-evm-context :input #(1 2 3 4 5)))
         (loaded (execute-bytecode #(95 53 0) :context context))
         (copied (execute-bytecode #(96 3 96 1 95 55 96 3 95 243)
                                   :context context)))
    (is (= #x0102030405000000000000000000000000000000000000000000000000000000
           (first (evm-result-stack loaded))))
    (is (bytes= #(2 3 4) (evm-result-return-data copied)))))

(deftest evm-code-size-and-copy
  (let ((result (execute-bytecode #(96 2 96 0 96 0 57 96 2 96 0 243))))
    (is (bytes= #(96 2) (evm-result-return-data result)))))

(deftest evm-return-data-size-and-copy
  (let* ((context (make-evm-context :return-data #(10 20 30 40 50)))
         (result (execute-bytecode #(61 96 3 96 1 95 62 96 3 95 243)
                                   :context context)))
    (is (eq :returned (evm-result-status result)))
    (is (= 5 (first (evm-result-stack result))))
    (is (bytes= #(20 30 40) (evm-result-return-data result))))
  (signals evm-error
    (execute-bytecode #(96 4 96 3 95 62) :context
                      (make-evm-context :return-data #(10 20 30 40 50))))
  (signals evm-error (execute-bytecode #(61))))

(deftest evm-basic-gas-limit
  (signals evm-error (execute-bytecode #(96 2 96 3 1 0) :gas-limit 8))
  (let ((result (execute-bytecode #(96 2 96 3 1 0) :gas-limit 9)))
    (is (= 9 (evm-result-gas-used result))))
  (let ((result (execute-bytecode #(#x5a 0) :gas-limit 10)))
    (is (= 8 (first (evm-result-stack result))))
    (is (= 2 (evm-result-gas-used result)))))

(deftest evm-log1-emits-log-entry
  (let* ((address (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (context (make-evm-context :address address))
         (result (execute-bytecode #(96 42 96 0 82 96 7 96 32 96 0 161 0)
                                   :context context))
         (log (first (evm-result-logs result))))
    (is (= 1 (length (evm-result-logs result))))
    (is (= 1027 (evm-result-gas-used result)))
    (is (bytes= (address-bytes address)
                (address-bytes (log-entry-address log))))
    (is (= 7 (bytes-to-integer
              (hash32-bytes (first (log-entry-topics log))))))
    (is (= 42 (aref (log-entry-data log) 31)))))

(deftest evm-log-read-only-error
  (signals evm-error
    (execute-bytecode #(95 95 160)
                      :context (make-evm-context :read-only-p t))))

(deftest evm-addmod-mulmod-exp
  (let ((addmod (execute-bytecode #(96 9 96 7 96 5 8 0)))
        (mulmod (execute-bytecode #(96 9 96 7 96 5 9 0)))
        (exp (execute-bytecode #(96 10 96 2 10 0)))
        (zero-modulus (execute-bytecode #(95 96 7 96 5 8 0))))
    (is (= 3 (first (evm-result-stack addmod))))
    (is (= 8 (first (evm-result-stack mulmod))))
    (is (= 1024 (first (evm-result-stack exp))))
    (is (= 0 (first (evm-result-stack zero-modulus))))))

(deftest evm-signed-arithmetic-and-comparison
  (let ((sdiv (execute-bytecode #(96 2 127
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 251
                                  5 0)))
        (smod (execute-bytecode #(96 2 127
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 255
                                  255 255 255 255 255 255 255 251
                                  7 0)))
        (slt (execute-bytecode #(96 1 127
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 18 0)))
        (sgt (execute-bytecode #(127
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 255 255 255 255 255 255 255 255
                                 96 1 19 0))))
    (is (= (- (expt 2 256) 2) (first (evm-result-stack sdiv))))
    (is (= (1- (expt 2 256)) (first (evm-result-stack smod))))
    (is (= 1 (first (evm-result-stack slt))))
    (is (= 1 (first (evm-result-stack sgt))))))

(deftest evm-signextend-and-sar
  (let ((signextended (execute-bytecode #(96 128 96 0 11 0)))
        (positive (execute-bytecode #(96 127 96 0 11 0)))
        (sar-negative (execute-bytecode #(127
                                          255 255 255 255 255 255 255 255
                                          255 255 255 255 255 255 255 255
                                          255 255 255 255 255 255 255 255
                                          255 255 255 255 255 255 255 252
                                          96 1 29 0)))
        (sar-large (execute-bytecode #(127
                                       255 255 255 255 255 255 255 255
                                       255 255 255 255 255 255 255 255
                                       255 255 255 255 255 255 255 255
                                       255 255 255 255 255 255 255 252
                                       97 1 0 29 0))))
    (is (= (- (expt 2 256) #x80) (first (evm-result-stack signextended))))
    (is (= #x7f (first (evm-result-stack positive))))
    (is (= (- (expt 2 256) 2) (first (evm-result-stack sar-negative))))
    (is (= (1- (expt 2 256)) (first (evm-result-stack sar-large))))))

(deftest evm-sha3-hashes-memory
  (let* ((result (execute-bytecode #(96 42 96 0 82 96 32 96 0 32 0)))
         (expected-data (make-byte-vector 32)))
    (setf (aref expected-data 31) 42)
    (is (= (bytes-to-integer (keccak-256 expected-data))
           (first (evm-result-stack result))))))

(deftest evm-environment-opcodes
  (let* ((state (make-state-db))
         (contract (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (origin (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (caller (address-from-hex "0x00000000000000000000000000000000000000dd"))
         (coinbase (address-from-hex "0x00000000000000000000000000000000000000ee"))
         (randao (hash32-from-hex
                  "0x1111111111111111111111111111111111111111111111111111111111111111")))
    (state-db-set-account state target (make-state-account :balance 1234))
    (state-db-set-account state contract (make-state-account :balance 5678))
    (let* ((context (make-evm-context
                     :state state
                     :address contract
                     :origin origin
                     :caller caller
                     :gas-price 10
                     :coinbase coinbase
                     :timestamp 20
                     :block-number 30
                     :prev-randao randao
                     :gas-limit 40
                     :chain-id 50
                     :base-fee 60))
           (result (execute-bytecode
                    #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                      49 50 51 48 58 65 66 67 68 69 70 71 72 0)
                    :context context))
           (stack (evm-result-stack result)))
      (is (= 60 (first stack)))
      (is (= 5678 (second stack)))
      (is (= 50 (third stack)))
      (is (= 40 (fourth stack)))
      (is (= (bytes-to-integer (hash32-bytes randao)) (fifth stack)))
      (is (= 30 (sixth stack)))
      (is (= 20 (seventh stack)))
      (is (= (bytes-to-integer (address-bytes coinbase)) (eighth stack)))
      (is (= 10 (ninth stack)))
      (is (= (bytes-to-integer (address-bytes contract)) (tenth stack)))
      (is (= (bytes-to-integer (address-bytes caller)) (nth 10 stack)))
      (is (= (bytes-to-integer (address-bytes origin)) (nth 11 stack)))
      (is (= 1234 (nth 12 stack))))))

(deftest evm-blockhash-window
  (let* ((block-hashes (make-hash-table))
         (hash (hash32-from-hex
                "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (context (make-evm-context
                   :block-number 300
                   :block-hashes block-hashes)))
    (setf (gethash 299 block-hashes) hash)
    (let* ((result (execute-bytecode #(97 0 43 64 97 1 44 64 97 1 43 64 0)
                                     :context context))
           (stack (evm-result-stack result)))
      (is (= (bytes-to-integer (hash32-bytes hash)) (first stack)))
      (is (= 0 (second stack)))
      (is (= 0 (third stack))))))

(deftest evm-blob-environment-opcodes
  (let* ((first-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (second-hash
           (hash32-from-hex
            "0x202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"))
         (context (make-evm-context
                   :blob-hashes (vector first-hash second-hash)
                   :blob-base-fee 1234))
         (result (execute-bytecode #(95 #x49 96 1 #x49 96 2 #x49 #x4a 0)
                                   :context context))
         (stack (evm-result-stack result)))
    (is (= 1234 (first stack)))
    (is (= 0 (second stack)))
    (is (= (bytes-to-integer (hash32-bytes second-hash)) (third stack)))
    (is (= (bytes-to-integer (hash32-bytes first-hash)) (fourth stack))))
  (signals evm-error (execute-bytecode #(95 #x49)))
  (signals evm-error (execute-bytecode #(#x4a))))

(deftest evm-external-code-opcodes
  (let* ((state (make-state-db))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (empty (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (code #(96 1 96 2 1 0))
         (context (make-evm-context :state state)))
    (state-db-set-code state target code)
    (state-db-set-account state empty (make-state-account))
    (let ((size (execute-bytecode
                 #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187 59 0)
                 :context context))
          (copy (execute-bytecode
                 #(96 4 96 1 95
                   115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                   60 96 4 95 243)
                 :context context))
          (hashes (execute-bytecode
                   #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 221 63
                     115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 204 63
                     115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187 63
                     0)
                   :context context)))
      (is (= (length code) (first (evm-result-stack size))))
      (is (bytes= #(1 96 2 1) (evm-result-return-data copy)))
      (is (= (bytes-to-integer (hash32-bytes (state-db-get-code-hash state target)))
             (first (evm-result-stack hashes))))
      (is (= (bytes-to-integer (hash32-bytes +empty-code-hash+))
             (second (evm-result-stack hashes))))
      (is (= 0 (third (evm-result-stack hashes)))))))

(deftest evm-external-code-opcodes-share-warm-account-access
  (let* ((state (make-state-db))
         (target (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (code #(96 1 96 2 1 0))
         (target-push (concat-bytes #(#x73) (address-bytes target)))
         (program
           (concat-bytes
            target-push
            #(#x3b)
            target-push
            #(#x3f)
            #(#x5f #x5f #x5f)
            target-push
            #(#x3c #x00))))
    (state-db-set-code state target code)
    (let ((result (execute-bytecode program
                                    :context (make-evm-context
                                              :state state))))
      (is (= (bytes-to-integer
              (hash32-bytes (state-db-get-code-hash state target)))
             (first (evm-result-stack result))))
      (is (= (length code) (second (evm-result-stack result))))
      (is (= 2815 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode program
                        :context (make-evm-context :state state)
                        :gas-limit 2814))))

(deftest evm-external-code-opcodes-see-delegation-designator
  (let* ((state (make-state-db))
         (delegated (address-from-hex "0x00000000000000000000000000000000000000bb"))
         (target (address-from-hex "0x00000000000000000000000000000000000000cc"))
         (target-code #(96 42 95 82 96 32 95 243))
         (delegation-code (set-code-delegation-code target))
         (context (make-evm-context :state state)))
    (state-db-set-code state delegated delegation-code)
    (state-db-set-code state target target-code)
    (let ((size (execute-bytecode
                 #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187 59 0)
                 :context context))
          (copy (execute-bytecode
                 #(96 4 95 95
                   115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187
                   60 96 4 95 243)
                 :context context))
          (hash (execute-bytecode
                 #(115 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 187 63 0)
                 :context context)))
      (is (= (length delegation-code) (first (evm-result-stack size))))
      (is (bytes= (subseq delegation-code 0 4)
                  (evm-result-return-data copy)))
      (is (= (bytes-to-integer
              (hash32-bytes (state-db-get-code-hash state delegated)))
             (first (evm-result-stack hash)))))))

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
      (is (= 36617 (evm-result-gas-used result)))
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
      (is (= 11617 (evm-result-gas-used result)))
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
      (is (= 36617 (evm-result-gas-used result)))
      (is (= 3 (state-account-balance (state-db-get-account state caller))))
      (is (not (state-db-get-account state target))))))

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
      (is (= 11642 (evm-result-gas-used result)))
      (is (= 2298 (bytes-to-integer (evm-result-return-data result))))
      (is (= 9 (state-account-balance (state-db-get-account state caller))))
      (is (= 1 (state-account-balance (state-db-get-account state callee)))))))

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

(deftest evm-call-and-staticcall-identity-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 1 95 83 96 2 96 1 83 96 3 96 2 83))
         (call-code #(96 3 95 96 3 95 95 96 4 96 100 241 96 3 95 243))
         (staticcall-code #(96 3 95 96 3 95 96 4 96 100 250 96 3 95 243))
         (oog-call-code #(96 3 95 96 3 95 95 96 4 96 17 241 96 3 95 243))
         (call-result (execute-bytecode (concat-bytes setup call-code)
                                        :context context))
         (static-result (execute-bytecode (concat-bytes setup staticcall-code)
                                          :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack call-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data call-result)))
    (is (= 1 (first (evm-result-stack static-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data static-result)))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (bytes= #(0 0 0) (evm-result-return-data oog-result)))))

(deftest evm-call-ecrecover-precompile
  (labels ((program (input gas-high gas-low)
             (let ((copy-code #(96 128 96 23 95 57))
                   (call-code (vector 96 32 95 96 128 95 95 96 1
                                      97 gas-high gas-low
                                      241 96 32 95 243)))
               (concat-bytes copy-code call-code input))))
    (let* ((state (make-state-db))
           (caller (address-from-hex
                    "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (valid-input
             (hex-to-bytes
              "0x18c547e4f7b0f325ad1e56f57e26c745b09a3e503d86e00e5255ff7f715d3d1c000000000000000000000000000000000000000000000000000000000000001c73b1693892219d736caba55bdb67216e485557ea6b6af75f37096c9aa6a5a75feeb940b1d03b21e36b0e47e79769f095fe2ab855bd91e3a38756b7d75a9c4549"))
           (invalid-v-input (copy-seq valid-input))
           (result (execute-bytecode (program valid-input 11 184)
                                     :context context))
           (invalid-result
             (progn
               (setf (aref invalid-v-input 32) 1)
               (execute-bytecode (program invalid-v-input 11 184)
                                 :context context)))
           (oog-result (execute-bytecode (program valid-input 11 183)
                                         :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (string= "0x000000000000000000000000a94f5374fce5edbc8e2a8697c15331677e6ebf0b"
                   (bytes-to-hex (evm-result-return-data result))))
      (is (= 1 (first (evm-result-stack invalid-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-result)))
      (is (= 0 (first (evm-result-stack oog-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data oog-result))))))

(deftest evm-call-sha256-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 97 95 83 96 98 96 1 83 96 99 96 2 83))
         (call-code #(96 32 95 96 3 95 95 96 2 96 100 241 96 32 95 243))
         (oog-call-code #(96 32 95 96 3 95 95 96 2 96 71 241 96 32 95 243))
         (result (execute-bytecode (concat-bytes setup call-code)
                                   :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 224 (evm-result-gas-used result)))
    (is (string= "0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 223 (evm-result-gas-used oog-result)))
    (is (bytes= (make-byte-vector 32) (evm-result-return-data oog-result)))))

(deftest evm-call-ripemd160-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 97 95 83 96 98 96 1 83 96 99 96 2 83))
         (call-code #(96 32 95 96 3 95 95 96 3 97 2 208 241
                      96 32 95 243))
         (oog-call-code #(96 32 95 96 3 95 95 96 3 97 2 207 241
                          96 32 95 243))
         (result (execute-bytecode (concat-bytes setup call-code)
                                   :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 872 (evm-result-gas-used result)))
    (is (string= "0x0000000000000000000000008eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 871 (evm-result-gas-used oog-result)))
    (is (bytes= (make-byte-vector 32) (evm-result-return-data oog-result)))))

(deftest evm-call-modexp-precompile
  (labels ((fixed32 (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               bytes))
           (program (call-gas-high call-gas-low)
             (let* ((input (concat-bytes (fixed32 1)
                                         (fixed32 1)
                                         (fixed32 1)
                                         #(2 5 13)))
                    (copy-code #(96 99 96 23 95 57))
                    (call-code (vector 96 1 95 96 99 95 95 96 5
                                       97 call-gas-high call-gas-low
                                       241 96 1 95 243)))
               (concat-bytes copy-code call-code input))))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (result (execute-bytecode (program 3 132) :context context))
           (oog-result (execute-bytecode (program 0 199) :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 358 (evm-result-gas-used result)))
      (is (bytes= #(6) (evm-result-return-data result)))
      (is (= 0 (first (evm-result-stack oog-result))))
      (is (= 357 (evm-result-gas-used oog-result)))
      (is (bytes= #(0) (evm-result-return-data oog-result))))))

(deftest evm-call-bn254-add-and-mul-precompiles
  (labels ((bn254-add-program (input)
             (concat-bytes
              #(96 128 96 22 95 57
                96 64 95 96 128 95 95 96 6 96 150 241
                96 64 95 243)
              input))
           (bn254-mul-program (input)
             (concat-bytes
              #(96 96 96 23 95 57
                96 64 95 96 96 95 95 96 7 97 23 112 241
                96 64 95 243)
              input))
           (fixed32 (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               bytes)))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (g (hex-to-bytes
               "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
           (two-g (hex-to-bytes
                   "0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd315ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4"))
           (three-g (hex-to-bytes
                     "0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf02ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261"))
           (add-result
             (execute-bytecode (bn254-add-program (concat-bytes g two-g))
                               :context context))
           (mul-result
             (execute-bytecode (bn254-mul-program
                                (concat-bytes g (fixed32 3)))
                               :context context))
           (zero-mul-result
             (execute-bytecode (bn254-mul-program
                                (concat-bytes g (make-byte-vector 32)))
                               :context context)))
      (is (= 1 (first (evm-result-stack add-result))))
      (is (bytes= three-g (evm-result-return-data add-result)))
      (is (= 1 (first (evm-result-stack mul-result))))
      (is (bytes= three-g (evm-result-return-data mul-result)))
      (is (= 1 (first (evm-result-stack zero-mul-result))))
      (is (bytes= (make-byte-vector 64)
                  (evm-result-return-data zero-mul-result))))))

(deftest evm-call-bn254-add-invalid-point-fails
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (field-prime-and-y (hex-to-bytes
                             "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd470000000000000000000000000000000000000000000000000000000000000002"))
         (g (hex-to-bytes
             "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
         (program
           (concat-bytes
            #(96 128 96 22 95 57
              96 64 95 96 128 95 95 96 6 96 150 241
              96 64 95 243)
            (concat-bytes field-prime-and-y g)))
         (result (execute-bytecode program :context context)))
    (is (= 0 (first (evm-result-stack result))))
    (is (bytes= (make-byte-vector 64)
                (evm-result-return-data result)))))

(deftest evm-call-bn254-pairing-empty-zero-element-and-malformed-input
  (labels ((pairing-code (input)
             (concat-bytes
              #(96 192 96 24 95 57
                96 32 95 96 192 95 95 96 8 98 1 52 152 241
                96 32 95 243)
              input)))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (empty-code #(96 32 95 95 95 95 96 8 97 175 200 241
                         96 32 95 243))
           (malformed-code #(96 1 95 83
                             96 32 95 96 1 95 95 96 8 97 175 200 241
                             96 32 95 243))
           (g (hex-to-bytes
               "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
           (field-prime
             (hex-to-bytes
              "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"))
           (g2 (hex-to-bytes
                "0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c21800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa"))
           (g2-coordinate-too-large
             (concat-bytes field-prime (subseq g2 32 128)))
           (g2-off-curve
             (concat-bytes (subseq g2 0 127) #(171)))
           (empty-result (execute-bytecode empty-code :context context))
           (zero-g2-result
             (execute-bytecode
              (pairing-code (concat-bytes g (make-byte-vector 128)))
              :context context))
           (zero-g1-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64) g2))
              :context context))
           (invalid-g2-coordinate-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64)
                                          g2-coordinate-too-large))
              :context context))
           (invalid-g2-curve-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64)
                                          g2-off-curve))
              :context context))
           (malformed-result (execute-bytecode malformed-code :context context)))
      (is (= 1 (first (evm-result-stack empty-result))))
      (is (= 1 (aref (evm-result-return-data empty-result) 31)))
      (is (= 1 (first (evm-result-stack zero-g2-result))))
      (is (= 1 (aref (evm-result-return-data zero-g2-result) 31)))
      (is (= 1 (first (evm-result-stack zero-g1-result))))
      (is (= 1 (aref (evm-result-return-data zero-g1-result) 31)))
      (is (= 0 (first (evm-result-stack invalid-g2-coordinate-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-g2-coordinate-result)))
      (is (= 0 (first (evm-result-stack invalid-g2-curve-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-g2-curve-result)))
      (is (= 0 (first (evm-result-stack malformed-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data malformed-result))))))

(deftest evm-call-kzg-point-evaluation-rejects-malformed-inputs
  (labels ((program (input)
             (let* ((input (ensure-byte-vector input))
                    (size (length input))
                    (code (vector 96 size 96 23 95 57
                                  96 32 95 96 size 95 95 96 10
                                  97 #xc3 #x50 241
                                  96 32 95 243)))
               (concat-bytes code input))))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (short-input #(1))
           (mismatched-version-input (make-byte-vector 192))
           (short-result
             (execute-bytecode (program short-input) :context context))
           (mismatch-result
             (execute-bytecode (program mismatched-version-input)
                               :context context)))
      (is (= 0 (first (evm-result-stack short-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data short-result)))
      (is (= 0 (first (evm-result-stack mismatch-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data mismatch-result))))))

(deftest evm-call-blake2f-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (input
           (hex-to-bytes
            "0x0000000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000001"))
         (copy-code #(97 0 213 96 24 95 57))
         (call-code #(96 64 95 97 0 213 95 95 96 9 96 12 241
                      96 64 95 243))
         (oog-call-code #(96 64 95 97 0 213 95 95 96 9 96 11 241
                          96 64 95 243))
         (result (execute-bytecode (concat-bytes copy-code call-code input)
                                   :context context))
         (oog-result (execute-bytecode
                      (concat-bytes copy-code oog-call-code input)
                      :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 188 (evm-result-gas-used result)))
    (is (string= "0xba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 187 (evm-result-gas-used oog-result)))
    (is (bytes= (make-byte-vector 64) (evm-result-return-data oog-result)))))

(deftest evm-call-blake2f-malformed-input-fails
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (bad-flag-input
           (hex-to-bytes
            "0x0000000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000002"))
         (short-input
           (hex-to-bytes
            "0x00000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000001"))
         (bad-flag-code #(97 0 213 96 24 95 57
                          96 64 95 97 0 213 95 95 96 9 96 12 241
                          96 64 95 243))
         (short-code #(96 212 96 23 95 57
                       96 64 95 96 212 95 95 96 9 96 100 241
                       96 64 95 243))
         (bad-flag-result
           (execute-bytecode (concat-bytes bad-flag-code bad-flag-input)
                             :context context))
         (short-result
           (execute-bytecode (concat-bytes short-code short-input)
                             :context context)))
    (is (= 0 (first (evm-result-stack bad-flag-result))))
    (is (= 188 (evm-result-gas-used bad-flag-result)))
    (is (bytes= (make-byte-vector 64)
                (evm-result-return-data bad-flag-result)))
    (is (= 0 (first (evm-result-stack short-result))))
    (is (< (evm-result-gas-used short-result)
           (evm-result-gas-used bad-flag-result)))
    (is (bytes= (make-byte-vector 64)
                (evm-result-return-data short-result)))))

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

(deftest evm-create-charges-initcode-memory-expansion
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (code #(96 1 96 64 95 240 89 0)))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode code :context context)))
      (is (= 96 (first (evm-result-stack result))))
      (is (plusp (second (evm-result-stack result))))
      (is (= 32021 (evm-result-gas-used result))))
    (signals evm-error
      (execute-bytecode code :context context :gas-limit 32018))))

(deftest evm-create-rejects-oversized-initcode
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator)))
    (state-db-set-account state creator (make-state-account :balance 10))
    (signals evm-error
      (execute-bytecode #(97 #xc0 #x01 95 95 #xf0)
                        :context context))
    (signals evm-error
      (execute-bytecode #(95 97 #xc0 #x01 95 95 #xf5)
                        :context context))))

(deftest evm-create-initcode-extra-gas-follows-shanghai-rules
  (let ((pre-shanghai (make-chain-rules :chain-id 1 :london-p t))
        (shanghai (make-chain-rules :chain-id 1
                                    :london-p t
                                    :shanghai-p t))
        (oversized (1+ ethereum-lisp.evm::+max-initcode-size+)))
    (is (= 0
           (ethereum-lisp.evm::create-initcode-extra-gas
            oversized
            :rules pre-shanghai)))
    (is (= (* ethereum-lisp.evm::+keccak256-word-gas+
              (ceiling oversized 32))
           (ethereum-lisp.evm::create-initcode-extra-gas
            oversized
            :create2-p t
            :rules pre-shanghai)))
    (signals evm-error
      (ethereum-lisp.evm::create-initcode-extra-gas
       oversized
       :rules shanghai))
    (signals evm-error
      (ethereum-lisp.evm::create-initcode-extra-gas
       oversized
       :create2-p t
       :rules shanghai))))

(deftest evm-create-prewarms-created-address-for-initcode
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (code #(96 3 96 12 95 57
                 96 3 95 95 240
                 0
                 #x30 #x31 0)))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode code :context context)))
      (is (plusp (first (evm-result-stack result))))
      (is (= 32128 (evm-result-gas-used result))))))

(deftest evm-create2-prewarms-created-address-for-initcode
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (code #(96 3 96 14 95 57
                 96 5 96 3 95 95 245
                 0
                 #x30 #x31 0)))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode code :context context)))
      (is (plusp (first (evm-result-stack result))))
      (is (= 32137 (evm-result-gas-used result))))))

(deftest evm-create-rejects-creator-nonce-overflow
  (let* ((creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (max-nonce (1- (ash 1 64)))
         (balance 10))
    (dolist (code (list #(95 95 95 #xf0)
                        #(95 95 95 95 #xf5)))
      (let* ((state (make-state-db))
             (context (make-evm-context :state state :address creator)))
        (state-db-set-account state creator
                              (make-state-account :nonce max-nonce
                                                  :balance balance))
        (signals evm-error
          (execute-bytecode code :context context))
        (is (= max-nonce
               (state-account-nonce (state-db-get-account state creator))))
        (is (= balance
               (state-account-balance
                (state-db-get-account state creator))))))))

(deftest evm-create-deploys-returned-code
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (create-code #(96 10 96 12 95 57 96 10 95 95 240 0
                        96 0 96 0 83 96 1 96 0 243))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (declare (ignore initcode))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code :context context)))
      (is (= (bytes-to-integer (address-bytes expected-address))
             (first (evm-result-stack result))))
      (is (= 32244 (evm-result-gas-used result)))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (bytes= #(0) (state-db-get-code state expected-address))))))

(deftest evm-create-retains-initcode-logs
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 42 95 95 161 95 95 83 96 1 95 243))
         (create-code (concat-bytes
                       #(96 12 96 12 95 57 96 12 95 95 240 0)
                       initcode))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let* ((result (execute-bytecode create-code :context context))
           (log (first (evm-result-logs result))))
      (is (= (bytes-to-integer (address-bytes expected-address))
             (first (evm-result-stack result))))
      (is (= 1 (length (evm-result-logs result))))
      (is (bytes= (address-bytes expected-address)
                  (address-bytes (log-entry-address log))))
      (is (= 42 (bytes-to-integer
                 (hash32-bytes (first (log-entry-topics log))))))
      (is (bytes= #(0) (state-db-get-code state expected-address))))))

(deftest evm-create-code-deposit-out-of-gas-fails
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (create-code #(96 10 96 12 95 57 96 10 95 95 240 0
                        96 0 96 0 83 96 1 96 0 243))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code
                                    :context context
                                    :gas-limit 32100)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 32099 (evm-result-gas-used result)))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (not (state-db-get-account state expected-address))))))

(deftest evm-create-rejects-ef-prefixed-runtime-code
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (create-code #(96 10 96 12 95 57 96 10 95 95 240 0
                        96 #xef 96 0 83 96 1 96 0 243))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 32044 (evm-result-gas-used result)))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (not (state-db-get-account state expected-address))))))

(deftest evm-create-allows-ef-prefixed-runtime-code-before-london
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context
                   :state state
                   :address creator
                   :chain-rules (make-chain-rules :chain-id 1
                                                  :constantinople-p t)))
         (create-code #(96 10 96 15 96 0 57 96 10 96 0 96 0 240 0
                        96 #xef 96 0 83 96 1 96 0 243))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code :context context)))
      (is (not (zerop (first (evm-result-stack result)))))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (bytes= #(#xef) (state-db-get-code state expected-address))))))

(deftest evm-create-collision-consumes-child-gas
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (create-code #(96 10 96 12 95 57 96 10 95 95 240 0
                        96 0 96 0 83 96 1 96 0 243))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (state-db-set-account state expected-address (make-state-account :nonce 1))
    (let ((result (execute-bytecode create-code
                                    :context context
                                    :gas-limit 100000)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 98938 (evm-result-gas-used result)))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (= 1 (state-account-nonce
                (state-db-get-account state expected-address)))))))

(deftest evm-create2-rejects-ef-prefixed-runtime-code
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 #xef 96 0 83 96 1 96 0 243))
         (salt-bytes (make-byte-vector 32))
         (create-code #(96 10 96 14 95 57 96 5 96 10 95 95 245 0
                        96 #xef 96 0 83 96 1 96 0 243)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let ((result (execute-bytecode create-code :context context)))
        (is (= 0 (first (evm-result-stack result))))
        (is (= 32053 (evm-result-gas-used result)))
        (is (= 1 (state-account-nonce (state-db-get-account state creator))))
        (is (not (state-db-get-account state expected-address)))))))

(deftest evm-create2-allows-ef-prefixed-runtime-code-before-london
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context
                   :state state
                   :address creator
                   :chain-rules (make-chain-rules :chain-id 1
                                                  :constantinople-p t)))
         (initcode #(96 #xef 96 0 83 96 1 96 0 243))
         (salt-bytes (make-byte-vector 32))
         (create-code #(96 10 96 17 96 0 57 96 5 96 10 96 0 96 0 245 0
                        96 #xef 96 0 83 96 1 96 0 243)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let ((result (execute-bytecode create-code :context context)))
        (is (not (zerop (first (evm-result-stack result)))))
        (is (bytes= #(#xef) (state-db-get-code state expected-address)))))))

(deftest evm-create2-collision-consumes-child-gas
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (salt-bytes (make-byte-vector 32))
         (create-code #(96 10 96 14 95 57 96 5 96 10 95 95 245 0
                        96 0 96 0 83 96 1 96 0 243)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (state-db-set-account state expected-address
                            (make-state-account :nonce 1))
      (let ((result (execute-bytecode create-code
                                      :context context
                                      :gas-limit 100000)))
        (is (= 0 (first (evm-result-stack result))))
        (is (= 98939 (evm-result-gas-used result)))
        (is (= 1 (state-account-nonce (state-db-get-account state creator))))
        (is (= 1 (state-account-nonce
                  (state-db-get-account state expected-address))))))))

(deftest evm-create-revert-rolls-back-created-account-but-keeps-nonce
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (create-code #(96 10 96 13 95 57 96 10 95 95 240 61 0
                        96 99 96 0 82 96 32 96 0 253))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code :context context)))
      (is (= 32 (first (evm-result-stack result))))
      (is (= 0 (second (evm-result-stack result))))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (not (state-db-get-account state expected-address))))))

(deftest evm-create-revert-discards-initcode-logs
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 42 95 95 161 95 95 253))
         (create-code (concat-bytes
                       #(96 8 96 12 95 57 96 8 95 95 240 0)
                       initcode))
         (expected-address
           (make-address
            (subseq (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes creator) 0)))
                    12 32))))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((result (execute-bytecode create-code :context context)))
      (is (= 0 (first (evm-result-stack result))))
      (is (= 0 (length (evm-result-logs result))))
      (is (= 1 (state-account-nonce (state-db-get-account state creator))))
      (is (not (state-db-get-account state expected-address))))))

(deftest evm-create2-deploys-returned-code-at-salted-address
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (salt-bytes (make-byte-vector 32))
         (create-code #(96 10 96 14 95 57 96 5 96 10 95 95 245 0
                        96 0 96 0 83 96 1 96 0 243)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let ((result (execute-bytecode create-code :context context)))
        (is (= (bytes-to-integer (address-bytes expected-address))
               (first (evm-result-stack result))))
        (is (= 32253 (evm-result-gas-used result)))
        (is (= 1 (state-account-nonce (state-db-get-account state creator))))
        (is (bytes= #(0) (state-db-get-code state expected-address)))))))

(deftest evm-create2-retains-initcode-logs
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 42 95 95 161 95 95 83 96 1 95 243))
         (salt-bytes (make-byte-vector 32))
         (create-code (concat-bytes
                       #(96 12 96 14 95 57 96 5 96 12 95 95 245 0)
                       initcode)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let* ((result (execute-bytecode create-code :context context))
             (log (first (evm-result-logs result))))
        (is (= (bytes-to-integer (address-bytes expected-address))
               (first (evm-result-stack result))))
        (is (= 1 (length (evm-result-logs result))))
        (is (bytes= (address-bytes expected-address)
                    (address-bytes (log-entry-address log))))
        (is (= 42 (bytes-to-integer
                   (hash32-bytes (first (log-entry-topics log))))))
        (is (bytes= #(0) (state-db-get-code state expected-address)))))))

(deftest evm-create2-revert-discards-initcode-logs
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 42 95 95 161 95 95 253))
         (salt-bytes (make-byte-vector 32))
         (create-code (concat-bytes
                       #(96 8 96 14 95 57 96 5 96 8 95 95 245 0)
                       initcode)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let ((result (execute-bytecode create-code :context context)))
        (is (= 0 (first (evm-result-stack result))))
        (is (= 0 (length (evm-result-logs result))))
        (is (= 1 (state-account-nonce (state-db-get-account state creator))))
        (is (not (state-db-get-account state expected-address)))))))

(deftest evm-create2-collision-fails-after-creator-nonce-increment
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (salt-bytes (make-byte-vector 32))
         (create-code #(96 10 96 21 95 57
                        96 5 96 10 95 95 245
                        96 5 96 10 95 95 245
                        0
                        96 0 96 0 83 96 1 96 0 243)))
    (setf (aref salt-bytes 31) 5)
    (let ((expected-address
            (make-address
             (subseq
              (keccak-256
               (concat-bytes #(255)
                             (address-bytes creator)
                             salt-bytes
                             (keccak-256 initcode)))
              12 32))))
      (state-db-set-account state creator (make-state-account :balance 10))
      (let ((result (execute-bytecode create-code :context context)))
        (is (= 0 (first (evm-result-stack result))))
        (is (= (bytes-to-integer (address-bytes expected-address))
               (second (evm-result-stack result))))
        (is (= 2 (state-account-nonce (state-db-get-account state creator))))
        (is (bytes= #(0) (state-db-get-code state expected-address)))))))
