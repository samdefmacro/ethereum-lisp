(in-package #:ethereum-lisp.test)

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
        (amsterdam (make-chain-rules :chain-id 1
                                     :london-p t
                                     :shanghai-p t
                                     :amsterdam-p t))
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
       :rules shanghai))
    (is (= (* ethereum-lisp.evm::+initcode-word-gas+
              (ceiling oversized 32))
           (ethereum-lisp.evm::create-initcode-extra-gas
            oversized
            :rules amsterdam)))
    (signals evm-error
      (ethereum-lisp.evm::create-initcode-extra-gas
       (1+ ethereum-lisp.evm::+amsterdam-max-initcode-size+)
       :rules amsterdam))))

(deftest evm-created-runtime-code-size-follows-amsterdam-rules
  (let ((pre-amsterdam (make-chain-rules :chain-id 1
                                         :london-p t
                                         :shanghai-p t))
        (amsterdam (make-chain-rules :chain-id 1
                                     :london-p t
                                     :shanghai-p t
                                     :amsterdam-p t)))
    (is (ethereum-lisp.evm::invalid-created-runtime-code-p
         (make-byte-vector (1+ ethereum-lisp.evm::+max-contract-code-size+))
         pre-amsterdam))
    (is (not (ethereum-lisp.evm::invalid-created-runtime-code-p
              (make-byte-vector (1+ ethereum-lisp.evm::+max-contract-code-size+))
              amsterdam)))
    (is (ethereum-lisp.evm::invalid-created-runtime-code-p
         (make-byte-vector
          (1+ ethereum-lisp.evm::+amsterdam-max-contract-code-size+))
         amsterdam))))

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

(deftest evm-create-collision-rejects-balance-and-storage-accounts
  (labels ((create-code ()
             (concat-bytes
              #(96 10 96 12 95 57 96 10 95 95 240 0)
              #(96 0 96 0 83 96 1 96 0 243)))
           (expected-create-address (creator)
             (make-address
              (subseq (keccak-256
                       (rlp-encode
                        (make-rlp-list (address-bytes creator) 0)))
                      12 32)))
           (run-collision (prepare-target verify-target)
             (let* ((state (make-state-db))
                    (creator
                      (address-from-hex
                       "0x00000000000000000000000000000000000000aa"))
                    (context (make-evm-context :state state
                                               :address creator))
                    (expected-address (expected-create-address creator)))
               (state-db-set-account state creator
                                     (make-state-account :balance 10))
               (funcall prepare-target state expected-address)
               (let ((result (execute-bytecode (create-code)
                                               :context context
                                               :gas-limit 100000)))
                 (is (= 0 (first (evm-result-stack result))))
                 (is (= 98938 (evm-result-gas-used result)))
                 (is (= 1 (state-account-nonce
                           (state-db-get-account state creator))))
                 (funcall verify-target state expected-address)))))
    (run-collision
     (lambda (state address)
       (state-db-set-account state address
                             (make-state-account :balance 1)))
     (lambda (state address)
       (is (= 1 (state-account-balance
                 (state-db-get-account state address))))))
    (run-collision
     (lambda (state address)
       (state-db-set-storage
        state
        address
        (hash32-from-hex
         "0x0000000000000000000000000000000000000000000000000000000000000001")
        2))
     (lambda (state address)
       (is (= 2
              (state-db-get-storage
               state
               address
               (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))))))))

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
