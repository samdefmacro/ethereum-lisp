(in-package #:ethereum-lisp.test)

;;;; Every EVM memory region against go-ethereum v1.17.6.
;;;;
;;;; Hoodi block 3685491 (docs/evidence/sec5-hoodi-gas-3685491.txt) was a
;;;; zero-length LOG that grew memory to its offset.  These tests pin the rest
;;;; of the memory-region rules for every opcode that takes a region, gas
;;;; metered under Osaka rules as a block executes them, so that a sibling of
;;;; that defect fails here and not on a public network.  The rules, one table
;;;; row each, are in docs/evidence/sec5-evm-edge-audit.txt; the reference is
;;;; go-ethereum's core/vm/common.go (calcMemSize64WithUint), memory_table.go,
;;;; gas_table.go (memoryGasCost) and instructions.go (opReturnDataCopy,
;;;; opCall).
;;;;
;;;; Gas below is derived by hand from geth's schedule: PUSH0 2, PUSHn 3,
;;;; MSIZE 2, the opcode's constant gas, then memory 3 per word plus
;;;; floor(words^2 / 512) over the words the region reaches, rounded up to a
;;;; word, and 100 + 2,500 for a cold account.

(defparameter +memory-audit-max-word+ (1- (expt 2 256)))

(defparameter +memory-audit-opcodes+
  '((:stop . #x00) (:keccak256 . #x20) (:calldatacopy . #x37)
    (:codecopy . #x39) (:extcodecopy . #x3c) (:returndatasize . #x3d)
    (:returndatacopy . #x3e) (:pop . #x50) (:mload . #x51) (:mstore . #x52)
    (:mstore8 . #x53) (:msize . #x59) (:mcopy . #x5e) (:log0 . #xa0)
    (:create . #xf0) (:call . #xf1) (:callcode . #xf2) (:return . #xf3)
    (:delegatecall . #xf4) (:create2 . #xf5) (:staticcall . #xfa)
    (:revert . #xfd) (:invalid . #xfe)))

(defun memory-audit-code (&rest items)
  "Bytecode from ITEMS: an integer is pushed with the shortest PUSH (PUSH0 for
zero), a keyword is the opcode of that name."
  (let ((bytes
          (loop for item in items
                append
                (cond
                  ((keywordp item)
                   (list (or (cdr (assoc item +memory-audit-opcodes+))
                             (error "Unknown audit opcode ~S" item))))
                  ((zerop item) (list #x5f))
                  (t
                   (let ((size (ceiling (integer-length item) 8)))
                     (cons (+ #x5f size)
                           (loop for index from (1- size) downto 0
                                 collect (ldb (byte 8 (* 8 index)) item)))))))))
    (make-array (length bytes)
                :element-type '(unsigned-byte 8)
                :initial-contents bytes)))

(defun memory-audit-rules ()
  "Osaka, with every earlier fork flag set, as a block on Hoodi runs."
  (make-chain-rules :chain-id 1
                    :homestead-p t :eip150-p t :eip155-p t :eip158-p t
                    :byzantium-p t :constantinople-p t :petersburg-p t
                    :istanbul-p t :berlin-p t :london-p t :shanghai-p t
                    :cancun-p t :prague-p t :osaka-p t))

(defparameter +memory-audit-contract+
  "0x00000000000000000000000000000000000000aa")

(defparameter +memory-audit-callee+
  "0x00000000000000000000000000000000000000bb")

(defun memory-audit-run (code &key (callee-code #()) (gas 1000000))
  "Execute CODE as contract 0xaa with GAS under Osaka rules.  Account 0xbb
holds CALLEE-CODE; neither account is warm."
  (let* ((state (make-state-db))
         (contract (address-from-hex +memory-audit-contract+))
         (callee (address-from-hex +memory-audit-callee+))
         (context (make-evm-context :state state
                                    :address contract
                                    :caller callee
                                    :input (make-byte-vector 0)
                                    :chain-rules (memory-audit-rules))))
    (state-db-set-account state contract (make-state-account :balance 10))
    (state-db-set-code state callee callee-code)
    (execute-bytecode code :context context :gas-limit gas)))

(defun memory-audit-halts-p (code &key (callee-code #()))
  "True when CODE ends in an exceptional halt (an EVM-ERROR at the top frame).
Any other condition, a host TYPE-ERROR included, is not caught here."
  (handler-case
      (progn (memory-audit-run code :callee-code callee-code) nil)
    (evm-error () t)))

(deftest evm-memory-audit-zero-length-regions-are-free-at-offset-two-to-the-256
  ;; geth calcMemSize64WithUint: "if length is zero, memsize is always zero,
  ;; regardless of offset", and the interpreter resizes only for a positive
  ;; size.  Every region opcode, offset 2^256 - 1, size 0: success, no memory
  ;; gas, MSIZE 0 afterwards.
  (let ((m +memory-audit-max-word+))
    (flet ((msize-after (expected-gas &rest items)
             (let ((result (memory-audit-run
                            (apply #'memory-audit-code
                                   (append items '(:msize :stop))))))
               (is (eq :stopped (evm-result-status result)))
               (is (= expected-gas (evm-result-gas-used result)))
               (is (= 0 (first (evm-result-stack result))))
               result)))
      ;; KECCAK256: PUSH0, PUSH32, 30, MSIZE.  The hash is keccak("").
      (let ((result (msize-after 37 0 m :keccak256)))
        (is (= #xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
               (second (evm-result-stack result)))))
      ;; LOG0: 375, one log with empty data.
      (let ((result (msize-after 382 0 m :log0)))
        (is (= 1 (length (evm-result-logs result))))
        (is (= 0 (length (log-entry-data (first (evm-result-logs result)))))))
      ;; The copies: size, source offset, memory offset, then the 3-gas op.
      (msize-after 13 0 m m :calldatacopy)
      (msize-after 13 0 m m :codecopy)
      ;; RETURNDATACOPY from offset 0 of an empty buffer: legal, end 0 <= 0.
      (msize-after 12 0 0 m :returndatacopy)
      ;; EXTCODECOPY of the cold account 0xbb: 100 + 2,500.
      (msize-after 2613 0 m m #xbb :extcodecopy)
      (msize-after 13 0 m m :mcopy)
      ;; CREATE/CREATE2 of empty initcode: 32,000, no initcode words, the
      ;; child spends nothing and deposits nothing; the address is pushed.
      (let ((result (msize-after 32009 0 m 0 :create)))
        (is (plusp (second (evm-result-stack result)))))
      (let ((result (msize-after 32011 0 0 m 0 :create2)))
        (is (plusp (second (evm-result-stack result)))))
      ;; The CALL family with both regions empty at 2^256 - 1, into the cold
      ;; code-less account 0xbb: 100 + 2,500, success, nothing copied.
      (let ((result (msize-after 2619 0 m 0 m 0 #xbb 0 :call)))
        (is (= 1 (second (evm-result-stack result)))))
      (let ((result (msize-after 2619 0 m 0 m 0 #xbb 0 :callcode)))
        (is (= 1 (second (evm-result-stack result)))))
      (let ((result (msize-after 2617 0 m 0 m #xbb 0 :delegatecall)))
        (is (= 1 (second (evm-result-stack result)))))
      (let ((result (msize-after 2617 0 m 0 m #xbb 0 :staticcall)))
        (is (= 1 (second (evm-result-stack result)))))))
  ;; RETURN and REVERT halt, so memory is read from the result.
  (dolist (case '((:return :returned) (:revert :reverted)))
    (let ((result (memory-audit-run
                   (memory-audit-code 0 +memory-audit-max-word+ (first case)))))
      (is (eq (second case) (evm-result-status result)))
      (is (= 5 (evm-result-gas-used result)))
      (is (= 0 (length (evm-result-return-data result))))
      (is (= 0 (length (evm-result-memory result)))))))

(deftest evm-memory-audit-unpayable-regions-halt-and-never-signal-a-host-error
  ;; A region past 2^64 is geth's ErrGasUintOverflow; one below it but beyond
  ;; any gas is ErrOutOfGas.  Both are exceptional halts.  Here each must be an
  ;; EVM-ERROR (the halt the caller turns into a failed frame), never a host
  ;; TYPE-ERROR from sizing a Lisp vector.  Offsets: 2^256 - 1, 2^64 - 1 with
  ;; a size that crosses 2^64, and 2^32 (affordable to address, not to pay).
  (let ((m +memory-audit-max-word+)
        (cross (1- (expt 2 64)))
        (far (expt 2 32)))
    (dolist (offset (list m cross far))
      (dolist (items
               (list (list offset :mload)
                     (list 1 offset :mstore)
                     (list 1 offset :mstore8)
                     (list 1 offset :keccak256)
                     (list 1 offset :log0)
                     (list 1 offset :return)
                     (list 1 offset :revert)
                     (list 1 0 offset :calldatacopy)
                     (list 1 0 offset :codecopy)
                     (list 1 0 offset #xbb :extcodecopy)
                     (list 1 0 offset :mcopy)
                     (list 1 offset 0 :mcopy)
                     (list 1 offset 0 :create)
                     (list 0 1 offset 0 :create2)
                     ;; CALL arguments region, then return region.
                     (list 0 0 1 offset 0 #xbb 0 :call)
                     (list 1 offset 0 0 0 #xbb 0 :call)
                     (list 1 offset 0 0 #xbb 0 :staticcall)))
        (is (memory-audit-halts-p
             (apply #'memory-audit-code (append items '(:stop))))))))
  ;; A size that does not fit 64 bits, from offset 0, for the size-driven
  ;; charges (copy words, hash words, log bytes, initcode words).
  (let ((huge +memory-audit-max-word+))
    (dolist (items (list (list huge 0 0 :calldatacopy)
                         (list huge 0 0 :codecopy)
                         (list huge 0 0 :mcopy)
                         (list huge 0 :keccak256)
                         (list huge 0 :log0)
                         (list huge 0 :return)
                         (list huge 0 0 :create)))
      (is (memory-audit-halts-p
           (apply #'memory-audit-code (append items '(:stop)))))))
  ;; Positive control: the same shapes at a payable offset succeed.
  (is (not (memory-audit-halts-p (memory-audit-code 1 64 :log0 :stop))))
  (is (not (memory-audit-halts-p (memory-audit-code 64 :mload :stop)))))

(defun memory-audit-returning-callee (bytes &key (halt :return))
  "Callee code that ends in HALT (RETURN or REVERT) with BYTES, an integer of
at most 32 bytes written right-aligned, taking its last LENGTH bytes."
  (let ((length (ceiling (integer-length bytes) 8)))
    (memory-audit-code bytes 0 :mstore length (- 32 length) halt)))

(deftest evm-memory-audit-call-copies-at-most-the-return-data-into-a-paid-region
  ;; geth opCall: on success or revert, Memory.Set(retOffset, retSize, ret),
  ;; which copies min(retSize, len(ret)) bytes; the region was already
  ;; resized to what memoryCall priced; on any other failure nothing is
  ;; written.  The callee returns deadbeef.
  (let ((callee (memory-audit-returning-callee #xdeadbeef))
        (ones (1- (expt 2 256))))
    (flet ((call-into-ones (return-size &optional (callee callee))
             ;; MSTORE 32 bytes of ff at 0, CALL 0xbb with the return region
             ;; (0, RETURN-SIZE), then RETURN memory 0..32.
             (memory-audit-run
              (memory-audit-code ones 0 :mstore
                                 return-size 0 0 0 0 #xbb #xffff :call
                                 :returndatasize 32 0 :return)
              :callee-code callee)))
      ;; A region wider than the data: 4 bytes land, 28 keep their ff.
      ;; Parent 11 + 17 + 2,600 + 7, callee PUSH4 PUSH0 MSTORE(+1 word)
      ;; PUSH1 PUSH1 RETURN = 17.
      (let ((result (call-into-ones 32)))
        (is (eq :returned (evm-result-status result)))
        (is (= 2652 (evm-result-gas-used result)))
        (is (equal '(4 1) (evm-result-stack result)))
        (is (bytes= (concat-bytes #(#xde #xad #xbe #xef)
                                  (make-array 28 :element-type '(unsigned-byte 8)
                                                 :initial-element #xff))
                    (evm-result-return-data result))))
      ;; A region narrower than the data: 2 bytes land.
      (let ((result (call-into-ones 2)))
        (is (bytes= (concat-bytes #(#xde #xad)
                                  (make-array 30 :element-type '(unsigned-byte 8)
                                                 :initial-element #xff))
                    (evm-result-return-data result))))
      ;; A reverting callee's data is copied too, and the call pushes 0.
      (let ((result (call-into-ones
                     32 (memory-audit-returning-callee #xdeadbeef
                                                       :halt :revert))))
        (is (equal '(4 0) (evm-result-stack result)))
        (is (bytes= #(#xde #xad #xbe #xef)
                    (subseq (evm-result-return-data result) 0 4))))
      ;; A callee that halts exceptionally writes nothing and leaves no data.
      (let ((result (call-into-ones 32 (memory-audit-code :invalid))))
        (is (equal '(0 0) (evm-result-stack result)))
        (is (bytes= (make-array 32 :element-type '(unsigned-byte 8)
                                   :initial-element #xff)
                    (evm-result-return-data result))))))
  ;; The return region is paid and sized in full even when the data is
  ;; shorter: CALL with region (64, 32) from empty memory, then MSIZE.
  ;; 7 pushes 18 + CALL 2,600 + 3 words (9 + 0) + callee 17 + MSIZE 2.
  (let ((result (memory-audit-run
                 (memory-audit-code 32 64 0 0 0 #xbb #xffff :call :msize :stop)
                 :callee-code (memory-audit-returning-callee #xdeadbeef))))
    (is (= 2646 (evm-result-gas-used result)))
    (is (equal '(96 1) (evm-result-stack result)))
    (is (bytes= (concat-bytes #(#xde #xad #xbe #xef) (make-byte-vector 28))
                (subseq (evm-result-memory result) 64 96)))))

(deftest evm-memory-audit-returndatacopy-past-the-buffer-halts-even-when-empty
  ;; geth opReturnDataCopy: an offset that overflows 64 bits, or an end
  ;; (offset + size) past len(returnData), is ErrReturnDataOutOfBounds -- for
  ;; a zero size too.  The buffer here is the callee's 4 bytes.
  (let ((callee (memory-audit-returning-callee #xdeadbeef)))
    (flet ((copy (data-offset size)
             ;; CALL with no regions, then RETURNDATACOPY to memory 0.
             (memory-audit-code 0 0 0 0 0 #xbb #xffff :call :pop
                                size data-offset 0 :returndatacopy
                                :msize :stop)))
      (let ((whole (memory-audit-run (copy 0 4) :callee-code callee)))
        (is (equal '(32) (evm-result-stack whole)))
        (is (bytes= #(#xde #xad #xbe #xef)
                    (subseq (evm-result-memory whole) 0 4))))
      ;; End exactly at the buffer's length with nothing to copy: legal.
      (let ((at-end (memory-audit-run (copy 4 0) :callee-code callee)))
        (is (equal '(0) (evm-result-stack at-end))))
      (is (memory-audit-halts-p (copy 1 4) :callee-code callee))
      (is (memory-audit-halts-p (copy 0 5) :callee-code callee))
      (is (memory-audit-halts-p (copy 5 0) :callee-code callee))
      (is (memory-audit-halts-p (copy +memory-audit-max-word+ 0)
                                :callee-code callee)))))

(deftest evm-memory-audit-expansion-price-rounds-words-up-and-the-square-down
  ;; memoryGasCost: words = ceil(size / 32), total = 3 * words
  ;; + floor(words^2 / 512), charged as the difference of totals.
  ;; MSTORE8 at 31 is one word, at 32 two words.
  (let ((one (memory-audit-run (memory-audit-code 0 31 :mstore8 :msize :stop)))
        (two (memory-audit-run (memory-audit-code 0 32 :mstore8 :msize :stop))))
    (is (= 13 (evm-result-gas-used one)))
    (is (equal '(32) (evm-result-stack one)))
    (is (= 16 (evm-result-gas-used two)))
    (is (equal '(64) (evm-result-stack two))))
  ;; MLOAD at 4,064 reaches 128 words: 384 + floor(16,384 / 512) = 416.
  ;; MSTORE8 at 4,096 reaches 129 words: 387 + floor(16,641 / 512) = 419,
  ;; so +3 (the square's 32.5 rounds down).  MSTORE8 at 4,128 reaches 130:
  ;; 390 + floor(16,900 / 512) = 423, so +4.
  (let ((result (memory-audit-run
                 (memory-audit-code 4064 :mload :pop
                                    0 4096 :mstore8
                                    0 4128 :mstore8
                                    :msize :stop))))
    (is (= (+ 3 3 416 2 2 3 3 3 2 3 3 4 2) (evm-result-gas-used result)))
    (is (equal '(4160) (evm-result-stack result))))
  ;; 1,024 words at once: 3,072 + floor(1,048,576 / 512) = 5,120.
  (let ((result (memory-audit-run (memory-audit-code 32736 :mload :msize :stop))))
    (is (= (+ 3 3 5120 2) (evm-result-gas-used result)))
    (is (= 32768 (first (evm-result-stack result))))))

;;; The allocation ceiling a fixture harness binds (src/runtime/evm/memory.lisp,
;;; *MEMORY-ALLOCATION-CEILING*).  go-ethereum charges memoryGasCost before it
;;; resizes, so one frame's memory is bounded by what its gas pays for; an
;;; allocation above that bound can only come from a handler that allocates
;;; before it charges.

(deftest evm-memory-size-payable-with-gas-inverts-geths-memory-price
  ;; The largest W with 3W + floor(W^2 / 512) <= GAS, in bytes.
  (flet ((payable (gas)
           (ethereum-lisp.evm.internal::memory-size-payable-with-gas gas))
         (total (words)
           (ethereum-lisp.evm.internal::memory-total-gas words)))
    (is (= 0 (payable 0)))
    (is (= 0 (payable 2)))
    (is (= 32 (payable 3)))
    (is (= 32 (payable 5)))
    (is (= 64 (payable 6)))
    ;; 100,000 gas: 6,428 words cost 19,284 + 80,701 = 99,985; 6,429 words
    ;; cost 19,287 + 80,726 = 100,013.
    (is (= 99985 (total 6428)))
    (is (= 100013 (total 6429)))
    (is (= (* 32 6428) (payable 100000)))
    ;; The boundary holds exactly across the floor, up to 2^64 gas.
    (dolist (gas (list 511 512 1535 1536 16777216 30000000
                       (1- (expt 2 32)) (1- (expt 2 64))))
      (let ((words (/ (payable gas) 32)))
        (is (<= (total words) gas))
        (is (> (total (1+ words)) gas))))))

(deftest evm-memory-allocation-ceiling-refuses-typed-and-never-halts
  ;; Bound, a buffer above the ceiling is refused with a STORAGE-CONDITION:
  ;; not an EVM-ERROR, so no frame turns it into an exceptional halt, and not
  ;; an ERROR, so no transaction or block handler turns it into a verdict.
  (let ((code (memory-audit-code 1 4096 :mstore :msize :stop)))
    (let ((refused
            (handler-case
                (let ((ethereum-lisp.evm.internal::*memory-allocation-ceiling*
                        1024))
                  (memory-audit-run code)
                  nil)
              (evm-error () :halted)
              (error () :error)
              (storage-condition (condition) condition))))
      (is (typep refused
                 'ethereum-lisp.evm.internal::evm-memory-allocation-refused))
      (is (not (typep refused 'error)))
      (is (= 4128 (ethereum-lisp.evm.internal::evm-memory-allocation-refused-requested
                   refused)))
      (is (= 1024 (ethereum-lisp.evm.internal::evm-memory-allocation-refused-ceiling
                   refused))))
    ;; Positive controls: the same code under no ceiling, and a store the
    ;; ceiling admits.
    (is (equal '(4128) (evm-result-stack (memory-audit-run code))))
    (let ((ethereum-lisp.evm.internal::*memory-allocation-ceiling* 1024))
      (is (equal '(544) (evm-result-stack
                         (memory-audit-run
                          (memory-audit-code 1 512 :mstore :msize :stop))))))
    ;; Copied data buffers are checked too (CALLDATACOPY's padded slice).
    (let ((ethereum-lisp.evm.internal::*memory-allocation-ceiling* 1024))
      (is (typep (handler-case
                     (ethereum-lisp.evm.internal::padded-data-slice
                      (make-byte-vector 0) 0 2048)
                   (storage-condition (condition) condition))
                 'ethereum-lisp.evm.internal::evm-memory-allocation-refused)))))

(deftest evm-memory-allocation-ceiling-catches-the-random-statetest524-shape
  ;; EEST ported_static/stRandom2/random_statetest524 runs KECCAK256 with size
  ;; 0 at offset CALLVALUE = 0x754eb077 (1,968,156,791) and 100,000 gas.  Since
  ;; d7a28c6c that is free and allocates nothing; before it, the handler grew
  ;; memory to the offset: a 1.9 GB allocation no gas had paid for.  Under the
  ;; gas-derived ceiling the fixed opcode stops normally with MSIZE 0, and the
  ;; pre-fix allocation (ENSURE-MEMORY-SIZE to offset + size, which is what an
  ;; unconditional ENSURE-MEMORY-REGION does) is refused with a typed
  ;; condition instead of exhausting the heap.
  (let* ((offset #x754eb077)
         (ceiling (* 2 (ethereum-lisp.evm.internal::memory-size-payable-with-gas
                        100000))))
    (is (= 411392 ceiling))
    (let ((ethereum-lisp.evm.internal::*memory-allocation-ceiling* ceiling))
      (let ((result (memory-audit-run
                     (memory-audit-code 0 offset :keccak256 :msize :stop)
                     :gas 100000)))
        (is (eq :stopped (evm-result-status result)))
        (is (= 0 (first (evm-result-stack result)))))
      (let ((refused
              (handler-case
                  (progn
                    (ethereum-lisp.evm.internal::ensure-memory-size
                     (make-byte-vector 0) offset)
                    nil)
                (storage-condition (condition) condition))))
        (is (typep refused
                   'ethereum-lisp.evm.internal::evm-memory-allocation-refused))
        (is (<= offset (ethereum-lisp.evm.internal::evm-memory-allocation-refused-requested
                        refused)))))))
