(in-package #:ethereum-lisp.test)

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

(deftest evm-tree-step-limit-rolls-back-state-less-context
  (let* ((transient-storage (make-hash-table :test 'equalp))
         (storage-originals (make-hash-table :test 'equalp))
         (contract
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (context
           (make-evm-context :address contract
                             :transient-storage transient-storage
                             :storage-originals storage-originals))
         (sentinel (make-byte-vector 52 :initial-element #x5a)))
    (setf (gethash sentinel storage-originals) :sentinel)
    (let ((condition
            (capture-evm-step-limit-error
             (lambda ()
               ;; TSTORE mutates a context without a state DB, then this loop
               ;; exceeds the root diagnostic budget at pc 5.
               (execute-bytecode
                #(#x60 #x2a #x60 #x01 #x5d #x5b #x60 #x05 #x56)
                :context context
                :max-steps 6)))))
      (is condition)
      (is (= 7 (evm-step-limit-error-steps condition)))
      (is (= 5 (evm-step-limit-error-pc condition)))
      (is (= 0 (hash-table-count transient-storage)))
      (is (= 1 (hash-table-count storage-originals)))
      (is (eq :sentinel (gethash sentinel storage-originals))))))
