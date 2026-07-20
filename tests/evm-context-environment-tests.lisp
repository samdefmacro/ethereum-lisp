(in-package #:ethereum-lisp.test)

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

(deftest evm-exp-charges-fork-dependent-exponent-byte-gas
  (let* ((legacy (make-evm-context
                  :chain-rules (make-chain-rules :chain-id 1
                                                  :homestead-p t
                                                  :eip150-p t)))
         (eip160 (make-evm-context
                  :chain-rules (make-chain-rules :chain-id 1
                                                  :homestead-p t
                                                  :eip150-p t
                                                  :eip158-p t)))
         (legacy-one-byte (execute-bytecode #(96 1 96 1 #x0a 0)
                                            :context legacy))
         (eip160-one-byte (execute-bytecode #(96 1 96 1 #x0a 0)
                                            :context eip160))
         (eip160-zero (execute-bytecode #(96 0 96 1 #x0a 0)
                                        :context eip160))
         (eip160-two-byte (execute-bytecode #(97 1 0 96 1 #x0a 0)
                                            :context eip160)))
    (is (= 26 (evm-result-gas-used legacy-one-byte)))
    (is (= 66 (evm-result-gas-used eip160-one-byte)))
    (is (= 16 (evm-result-gas-used eip160-zero)))
    (is (= 116 (evm-result-gas-used eip160-two-byte)))))

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

(deftest evm-difficulty-prev-randao-opcode-mode
  (let* ((randao (hash32-from-hex
                  "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (post-merge-context (make-evm-context :prev-randao randao
                                               :difficulty 123
                                               :random-p t))
         (pre-merge-context (make-evm-context :prev-randao randao
                                              :difficulty 123
                                              :random-p nil)))
    (is (= (bytes-to-integer (hash32-bytes randao))
           (first (evm-result-stack
                   (execute-bytecode #(#x44 0)
                                     :context post-merge-context)))))
    (is (= 123
           (first (evm-result-stack
                   (execute-bytecode #(#x44 0)
                                     :context pre-merge-context)))))))

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
      ;; EIP-1052: EXTCODEHASH of an existing but EIP-161-empty account is 0,
      ;; not keccak256("").
      (is (= 0 (second (evm-result-stack hashes))))
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

