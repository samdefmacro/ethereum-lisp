(in-package #:ethereum-lisp.test)

(deftest evm-memory-growth-reuses-geometric-backing
  (let* ((first
           (ethereum-lisp.evm.internal::ensure-memory-size
            (make-byte-vector 0) 1))
         (second
           (ethereum-lisp.evm.internal::ensure-memory-size first 33)))
    (multiple-value-bind (first-backing first-offset)
        (array-displacement first)
      (multiple-value-bind (second-backing second-offset)
          (array-displacement second)
        (is (eq first-backing second-backing))
        (is (= 0 first-offset))
        (is (= 0 second-offset))
        (is (= 32 (length first)))
        (is (= 64 (length second)))
        (is (>= (array-total-size second-backing) 64))))))

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
         (byzantium-context
           (make-evm-context :input #(1 2 3 4)
                             :return-data #(5 6 7 8)
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :byzantium-p t
                                               :shanghai-p t)))
         (sha3-existing-word (execute-bytecode #(96 1 95 82 96 32 95 32 0)))
         (sha3-expands-memory
           (execute-bytecode #(96 1 96 32 32 89 0)))
         (calldatacopy-two-words (execute-bytecode #(96 33 95 95 55 0)
                                                   :context context))
         (calldatacopy-zero (execute-bytecode #(95 95 95 55 0)
                                              :context context))
         (calldatacopy-zero-high-offset
           (execute-bytecode #(95 95 97 2 0 55 97 2 0 81 0)
                             :context context))
         (returndatacopy-zero-high-offset
           (execute-bytecode #(95 95 97 2 0 #x3e 97 2 0 81 0)
                             :context byzantium-context))
         (mcopy-expands-source (execute-bytecode #(96 1 96 64 83
                                                   96 33 96 64 95 #x5e 0))))
    (is (= 52 (evm-result-gas-used sha3-existing-word)))
    (is (= 50 (evm-result-gas-used sha3-expands-memory)))
    (is (= 64 (first (evm-result-stack sha3-expands-memory))))
    (is (= 22 (evm-result-gas-used calldatacopy-two-words)))
    (is (= 9 (evm-result-gas-used calldatacopy-zero)))
    (is (= 67 (evm-result-gas-used calldatacopy-zero-high-offset)))
    (is (= 67 (evm-result-gas-used returndatacopy-zero-high-offset)))
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

;;; A zero-length region touches no memory, whatever its offset: go-ethereum
;;; v1.17.6 sizes it at zero (core/vm/common.go calcMemSize64WithUint) and
;;; resizes only for a positive size (core/vm/interpreter.go).  An empty LOG
;;; that grew memory to its offset let the next expansion be charged from the
;;; larger size: Hoodi block 3685491 (LOG3 at 0x80, then MSTORE to 0x80) came
;;; out 3 gas short.  Each case reads MSIZE right after the empty region, and
;;; the LOG0 and KECCAK256 cases then pay for the MLOAD at 0x200 that makes
;;; memory seventeen words: 48 gas more than a run that has already grown it
;;; to sixteen.

(deftest evm-zero-length-regions-touch-no-memory-at-any-offset
  (let ((log0 (execute-bytecode #(95 97 2 0 #xa0 89 97 2 0 81 0)
                                :context (make-evm-context)))
        (keccak (execute-bytecode #(95 97 2 0 #x20 89 97 2 0 81 0))))
    ;; LOG0: PUSH0 2, PUSH2 3, LOG0 375, MSIZE 2, PUSH2 3, MLOAD 3 + 51.
    (is (eq :stopped (evm-result-status log0)))
    (is (= 0 (second (evm-result-stack log0))))
    (is (= 439 (evm-result-gas-used log0)))
    (is (= 1 (length (evm-result-logs log0))))
    ;; KECCAK256 of nothing: 30 instead of LOG0's 375.
    (is (= 0 (second (evm-result-stack keccak))))
    (is (= #xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
           (third (evm-result-stack keccak))))
    (is (= 94 (evm-result-gas-used keccak))))
  ;; An offset of 2^256 - 1 is legal with a zero size and costs nothing.
  (let* ((max-word (make-array 32 :element-type '(unsigned-byte 8)
                                  :initial-element #xff))
         (log0-at-max-offset
           (execute-bytecode (concat-bytes #(95 127) max-word #(#xa0 89 0))
                             :context (make-evm-context)))
         (keccak-at-max-offset
           (execute-bytecode (concat-bytes #(95 127) max-word #(#x20 89 0)))))
    (is (eq :stopped (evm-result-status log0-at-max-offset)))
    (is (= 0 (first (evm-result-stack log0-at-max-offset))))
    (is (= 382 (evm-result-gas-used log0-at-max-offset)))
    (is (eq :stopped (evm-result-status keccak-at-max-offset)))
    (is (= 0 (first (evm-result-stack keccak-at-max-offset))))
    (is (= 37 (evm-result-gas-used keccak-at-max-offset))))
  ;; CREATE and CREATE2 with empty initcode at 0x200.
  (let* ((state (make-state-db))
         (creator (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address creator)))
    (state-db-set-account state creator (make-state-account :balance 10))
    (let ((create (execute-bytecode #(95 97 2 0 95 #xf0 89 0) :context context))
          (create2 (execute-bytecode #(95 95 97 2 0 95 #xf5 89 0)
                                     :context context)))
      (is (= 0 (first (evm-result-stack create))))
      (is (plusp (second (evm-result-stack create))))
      (is (= 0 (first (evm-result-stack create2))))
      (is (plusp (second (evm-result-stack create2)))))))

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
  (signals evm-step-limit-error
    (execute-bytecode #(91 96 0 86) :max-steps 4)))

(deftest evm-gas-bounds-long-finite-execution-instead-of-implicit-step-limit
  (let* ((code (evm-long-loop-code))
         (result
           (execute-bytecode code :gas-limit +evm-long-loop-gas+))
         (step-limit-error
           (capture-evm-step-limit-error
            (lambda ()
              (execute-bytecode code
                                :gas-limit +evm-long-loop-gas+
                                :max-steps 100000))))
         (gasless-default-error
           (capture-evm-step-limit-error
            (lambda ()
              ;; Gasless tooling retains its implicit safety guard.
              (execute-bytecode #(#x5b #x60 #x00 #x56)))))
         (out-of-gas-error
           (capture-evm-error-message
            (lambda ()
              (execute-bytecode code
                                :gas-limit (1- +evm-long-loop-gas+))))))
    (is (eq :stopped (evm-result-status result)))
    (is (= +evm-long-loop-gas+ (evm-result-gas-used result)))
    (is (and step-limit-error
             (= 100000
                (evm-step-limit-error-limit step-limit-error))))
    (is (= 100001 (evm-step-limit-error-steps step-limit-error)))
    (is (not (typep step-limit-error 'evm-error)))
    (is (search "maximum step count 100000"
                (princ-to-string step-limit-error)))
    (is (and gasless-default-error
             (= 100000
                (evm-step-limit-error-limit gasless-default-error))))
    (is (= 100001 (evm-step-limit-error-steps gasless-default-error)))
    (is (search "maximum step count 100000"
                (princ-to-string gasless-default-error)))
    (is (and out-of-gas-error
             (search "out of gas" out-of-gas-error)))
    (is (not (search "maximum step count" out-of-gas-error)))))
