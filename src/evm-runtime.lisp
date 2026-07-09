(in-package #:ethereum-lisp.evm)

(defun word (value)
  (mod value +word-modulus+))

(defun fail (control &rest args)
  (error 'evm-error :message (apply #'format nil control args)))

(defun context-fork-enabled-p (context predicate)
  (let ((rules (and context (evm-context-chain-rules context))))
    (or (null rules) (funcall predicate rules))))

(defun require-context-fork (context predicate fork-name opcode pc)
  (unless (context-fork-enabled-p context predicate)
    (fail "~A requires the ~A fork at pc ~D" opcode fork-name pc)))

(defun fail-precompile (gas-used control &rest args)
  (error 'evm-precompile-error
         :message (apply #'format nil control args)
         :gas-used gas-used))

(defun stack-push (stack value)
  (when (>= (length stack) +stack-limit+)
    (fail "EVM stack overflow"))
  (cons (word value) stack))

(defun pop1 (stack)
  (if stack
      (values (first stack) (rest stack))
      (fail "EVM stack underflow")))

(defun pop2 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (values a b stack))))

(defun pop3 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (values a b c stack)))))

(defun pop6 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (multiple-value-bind (d stack) (pop1 stack)
          (multiple-value-bind (e stack) (pop1 stack)
            (multiple-value-bind (f stack) (pop1 stack)
              (values a b c d e f stack))))))))

(defun pop7 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (multiple-value-bind (d stack) (pop1 stack)
          (multiple-value-bind (e stack) (pop1 stack)
            (multiple-value-bind (f stack) (pop1 stack)
              (multiple-value-bind (g stack) (pop1 stack)
                (values a b c d e f g stack)))))))))

(defun modexp-word (base exponent)
  (let ((result 1)
        (base (word base))
        (exponent exponent))
    (loop while (plusp exponent)
          do (when (oddp exponent)
               (setf result (word (* result base))))
             (setf exponent (ash exponent -1)
                   base (word (* base base))))
    result))

(defun signed-word (value)
  (if (>= value (expt 2 255))
      (- value +word-modulus+)
      value))

(defun signed-divide-word (dividend divisor)
  (if (zerop divisor)
      0
      (let* ((a (signed-word dividend))
             (b (signed-word divisor))
             (quotient (floor (abs a) (abs b))))
        (word (if (eql (minusp a) (minusp b))
                  quotient
                  (- quotient))))))

(defun signed-mod-word (dividend divisor)
  (if (zerop divisor)
      0
      (let* ((a (signed-word dividend))
             (b (signed-word divisor))
             (remainder (mod (abs a) (abs b))))
        (word (if (minusp a) (- remainder) remainder)))))

(defun signextend-word (byte-index value)
  (if (>= byte-index 32)
      value
      (let* ((bit-index (+ (* 8 byte-index) 7))
             (sign-bit (ash 1 bit-index))
             (mask (1- (ash 1 (1+ bit-index)))))
        (if (zerop (logand value sign-bit))
            (logand value mask)
            (logior value (logxor mask (1- +word-modulus+)))))))

(defun arithmetic-shift-right-word (shift value)
  (let ((signed (signed-word value)))
    (word (if (>= shift 256)
              (if (minusp signed) -1 0)
              (ash signed (- shift))))))

(defun memory-word-count (size)
  (ceiling size 32))

(defun aligned-memory-size (size)
  (* 32 (memory-word-count size)))

(defun ensure-memory-size (memory size)
  (if (<= size (length memory))
      memory
      (let ((expanded (make-byte-vector (aligned-memory-size size))))
        (replace expanded memory)
        expanded)))

(defun memory-total-gas (word-count)
  (+ (* word-count +memory-gas+)
     (floor (* word-count word-count) +memory-quad-divisor+)))

(defun memory-expansion-gas (memory offset size)
  (if (zerop size)
      0
      (let* ((current-words (memory-word-count (length memory)))
             (new-words (memory-word-count (+ offset size))))
        (if (<= new-words current-words)
            0
            (- (memory-total-gas new-words)
               (memory-total-gas current-words))))))

(defun memory-regions-high-water (&rest regions)
  (loop for (offset size) in regions
        maximize (if (zerop size) 0 (+ offset size))))

(defun memory-regions-expansion-gas (memory &rest regions)
  (memory-expansion-gas memory 0
                        (apply #'memory-regions-high-water regions)))

(defun ensure-memory-regions (memory &rest regions)
  (ensure-memory-size memory (apply #'memory-regions-high-water regions)))

(defun memory-slice (memory offset size)
  (if (zerop size)
      (make-byte-vector 0)
      (let ((memory (ensure-memory-size memory (+ offset size))))
        (subseq memory offset (+ offset size)))))

(defun copy-into-memory (memory memory-offset data)
  (let* ((data (ensure-byte-vector data))
         (size (length data)))
    (if (zerop size)
        memory
        (let ((memory (ensure-memory-size memory (+ memory-offset size))))
          (replace memory data :start1 memory-offset)
          memory))))

(defun copy-memory-region (memory destination source size)
  (if (zerop size)
      memory
      (let* ((memory (ensure-memory-size
                      memory
                      (max (+ destination size) (+ source size))))
             (data (subseq memory source (+ source size))))
        (replace memory data :start1 destination)
        memory)))

(defun padded-data-slice (data offset size)
  (let* ((data (ensure-byte-vector data))
         (result (make-byte-vector size)))
    (when (< offset (length data))
      (let ((available (min size (- (length data) offset))))
        (replace result data :start1 0 :start2 offset :end2 (+ offset available))))
    result))

(defun call-output-data-slice (data size)
  (let* ((data (ensure-byte-vector data))
         (available (min size (length data))))
    (subseq data 0 available)))

(defun bounded-data-slice (data offset size label)
  (let ((data (ensure-byte-vector data)))
    (when (> (+ offset size) (length data))
      (fail "~A out of bounds" label))
    (subseq data offset (+ offset size))))

(defun mstore (memory offset value)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (dotimes (i 32 memory)
      (setf (aref memory (+ offset i))
            (logand #xff (ash value (* -8 (- 31 i))))))))

(defun mload (memory offset)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (loop for i below 32
          for value = (aref memory (+ offset i))
            then (+ (ash value 8) (aref memory (+ offset i)))
          finally (return (word (or value 0))))))

(defun mstore8 (memory offset value)
  (let ((memory (ensure-memory-size memory (1+ offset))))
    (setf (aref memory offset) (logand value #xff))
    memory))

(defun read-push-immediate (code pc size)
  (let ((value 0))
    (dotimes (i size value)
      (let ((index (+ pc 1 i)))
        (setf value
              (+ (ash value 8)
                 (if (< index (length code)) (aref code index) 0)))))))

(defun byte-op (index value)
  (if (>= index 32)
      0
      (logand #xff (ash value (* -8 (- 31 index))))))

(defun exp-byte-count (exponent)
  (if (zerop exponent)
      0
      (ceiling (integer-length exponent) 8)))

(defun exp-byte-gas (rules)
  (if (or (null rules) (chain-rules-eip158-p rules))
      +exp-byte-gas-eip160+
      +exp-byte-gas+))

(defun code-position-p (code position)
  (loop with pc = 0
        while (< pc (length code))
        do (let ((op (aref code pc)))
             (when (= pc position)
               (return t))
             (if (<= #x60 op #x7f)
                 (incf pc (+ 1 (- op #x5f)))
                 (incf pc)))
        finally (return nil)))

(defun valid-jump-destination-p (code destination)
  (and (< destination (length code))
       (= (aref code destination) #x5b)
       (code-position-p code destination)))

(defun opcode-base-gas (op)
  (cond
    ((= op #x00) 0)
    ((member op '(#x01 #x03 #x10 #x11 #x12 #x13 #x14 #x15 #x16 #x17 #x18 #x19
                  #x1a #x1b #x1c #x1d #x35 #x51 #x52 #x53 #x5e)
             :test #'=)
     3)
    ((member op '(#x02 #x04 #x05 #x06 #x07) :test #'=) 5)
    ((member op '(#x08 #x09) :test #'=) 8)
    ((= op #x0a) 10)
    ((= op #x0b) 5)
    ((= op #x20) 30)
    ((member op '(#x30 #x32 #x33 #x34 #x36 #x38 #x3a #x3d
                  #x41 #x42 #x43 #x44 #x45 #x46 #x48
                  #x4a #x58 #x59 #x5a)
             :test #'=)
     2)
    ((= op #x47) 5)
    ((= op #x49) 3)
    ((= op #x31) 100)
    ((member op '(#x3b #x3c #x3f) :test #'=) 100)
    ((= op #x3e) 3)
    ((= op #x40) 20)
    ((member op '(#x37 #x39) :test #'=) 3)
    ((= op #x50) 2)
    ((= op #x54) 0)
    ((= op #x55) 0)
    ((= op #x56) 8)
    ((= op #x57) 10)
    ((member op '(#x5c #x5d) :test #'=) 100)
    ((= op #x5b) 1)
    ((= op #x5f) 2)
    ((<= #x60 op #x7f) 3)
    ((<= #x80 op #x9f) 3)
    ((<= #xa0 op #xa4) 375)
    ((member op '(#xf0 #xf5) :test #'=) 32000)
    ((member op '(#xf1 #xf2 #xf4 #xfa) :test #'=) 100)
    ((member op '(#xf3 #xfd) :test #'=) 0)
    ((= op #xff) 5000)
    (t 0)))

(defun word-to-hash32 (value)
  (let ((out (make-byte-vector 32)))
    (dotimes (i 32 (make-hash32 out))
      (setf (aref out (- 31 i))
            (logand #xff (ash value (* -8 i)))))))

(defun word-to-address (value)
  (let ((out (make-byte-vector 20)))
    (dotimes (i 20 (make-address out))
      (setf (aref out (- 19 i))
            (logand #xff (ash value (* -8 i)))))))

(defun address-to-word (address)
  (bytes-to-integer (address-bytes address)))

(defun hash32-to-word (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun evm-context-difficulty-or-random-word (context)
  (if (evm-context-random-p context)
      (hash32-to-word (or (evm-context-prev-randao context) (zero-hash32)))
      (evm-context-difficulty context)))

(defun transient-storage-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun storage-refund-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun account-access-key (address)
  (address-bytes address))

(defun transient-storage-get (context address slot)
  (gethash (transient-storage-key address slot)
           (evm-context-transient-storage context)
           0))

(defun transient-storage-set (context address slot value)
  (let ((key (transient-storage-key address slot)))
    (if (zerop value)
        (remhash key (evm-context-transient-storage context))
        (setf (gethash key (evm-context-transient-storage context))
              (word value)))))

(defun copy-transient-storage (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-transient-storage context)))
    copy))

(defun restore-transient-storage (context snapshot)
  (when context
    (let ((storage (evm-context-transient-storage context)))
      (clrhash storage)
      (maphash (lambda (key value)
                 (setf (gethash key storage) value))
               snapshot))))

(defun copy-storage-clears (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-storage-clears context)))
    copy))

(defun restore-storage-clears (context snapshot)
  (when context
    (let ((clears (evm-context-storage-clears context)))
      (clrhash clears)
      (maphash (lambda (key value)
                 (setf (gethash key clears) value))
               snapshot))))

(defun copy-selfdestructed-addresses (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-selfdestructed-addresses context)))
    copy))

(defun restore-selfdestructed-addresses (context snapshot)
  (when context
    (let ((selfdestructed (evm-context-selfdestructed-addresses context)))
      (clrhash selfdestructed)
      (maphash (lambda (key value)
                 (setf (gethash key selfdestructed) value))
               snapshot))))

(defun mark-selfdestructed-address (context address)
  (setf (gethash (address-to-hex address)
                 (evm-context-selfdestructed-addresses context))
        t))

(defun finalize-evm-selfdestructs (state context)
  (maphash
   (lambda (key selfdestructed-p)
     (when selfdestructed-p
       (state-db-clear-account state (address-from-hex key))))
   (evm-context-selfdestructed-addresses context)))

(defun copy-accessed-storage (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-accessed-storage context)))
    copy))

(defun restore-accessed-storage (context snapshot)
  (when context
    (let ((accessed-storage (evm-context-accessed-storage context)))
      (clrhash accessed-storage)
      (maphash (lambda (key value)
                 (setf (gethash key accessed-storage) value))
               snapshot))))

(defun copy-accessed-addresses (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-accessed-addresses context)))
    copy))

(defun restore-accessed-addresses (context snapshot)
  (when context
    (let ((accessed-addresses (evm-context-accessed-addresses context)))
      (clrhash accessed-addresses)
      (maphash (lambda (key value)
                 (setf (gethash key accessed-addresses) value))
               snapshot))))

(defun account-cold-access-surcharge (context address)
  (if (gethash (account-access-key address)
               (evm-context-accessed-addresses context))
      0
      (- +cold-account-access-cost-eip2929+
         +warm-storage-read-cost-eip2929+)))

(defun mark-account-accessed (context address)
  (setf (gethash (account-access-key address)
                 (evm-context-accessed-addresses context))
        t))

(defun charge-account-access-gas (context address charge-extra-gas)
  (let ((cost (account-cold-access-surcharge context address)))
    (funcall charge-extra-gas cost)
    (mark-account-accessed context address)))

(defun charge-cold-account-access-gas (context address charge-extra-gas)
  (unless (gethash (account-access-key address)
                   (evm-context-accessed-addresses context))
    (funcall charge-extra-gas +cold-account-access-cost-eip2929+)
    (mark-account-accessed context address)))

(defun storage-access-cost (context address slot)
  (let ((key (storage-access-key address slot)))
    (if (gethash key (evm-context-accessed-storage context))
        +warm-storage-read-cost-eip2929+
        +cold-sload-cost-eip2929+)))

(defun storage-cold-access-surcharge (context address slot)
  (let ((key (storage-access-key address slot)))
    (if (gethash key (evm-context-accessed-storage context))
        0
        +cold-sload-cost-eip2929+)))

(defun mark-storage-accessed (context address slot)
  (setf (gethash (storage-access-key address slot)
                 (evm-context-accessed-storage context))
        t))

(defun charge-storage-read-access-gas (context address slot charge-extra-gas)
  (let ((cost (storage-access-cost context address slot)))
    (funcall charge-extra-gas cost)
    (mark-storage-accessed context address slot)))

(defun sstore-dynamic-gas (access-cost original-value current-value new-value)
  (cond
    ((= current-value new-value)
     (+ access-cost +warm-storage-read-cost-eip2929+))
    ((= original-value current-value)
     (+ access-cost
        (if (zerop original-value)
            +sstore-set-gas-eip2200+
            (- +sstore-reset-gas-eip2200+
               +cold-sload-cost-eip2929+))))
    (t
     (+ access-cost +warm-storage-read-cost-eip2929+))))

(defun restore-execution-snapshot (state state-snapshot context
                                   transient-snapshot
                                   &optional storage-clears-snapshot
                                             accessed-storage-snapshot
                                             accessed-addresses-snapshot
                                             selfdestructed-snapshot)
  (state-db-restore state state-snapshot)
  (restore-transient-storage context transient-snapshot)
  (when storage-clears-snapshot
    (restore-storage-clears context storage-clears-snapshot))
  (when accessed-storage-snapshot
    (restore-accessed-storage context accessed-storage-snapshot))
  (when accessed-addresses-snapshot
    (restore-accessed-addresses context accessed-addresses-snapshot))
  (when selfdestructed-snapshot
    (restore-selfdestructed-addresses context selfdestructed-snapshot)))

(defun account-balance (state address)
  (let ((account (state-db-get-account state address)))
    (if account (state-account-balance account) 0)))

(defun empty-account-p (state address)
  (let ((account (state-db-get-account state address)))
    (or (null account)
        (and (zerop (state-account-nonce account))
             (zerop (state-account-balance account))
             (bytes= (hash32-bytes (state-account-storage-root account))
                     (hash32-bytes +empty-trie-hash+))
             (bytes= (hash32-bytes (state-account-code-hash account))
                     (hash32-bytes +empty-code-hash+))))))

(defun call-value-extra-gas
    (state callee value &key new-account-p stipend-discount-p)
  (let ((gas 0))
    (when (plusp value)
      (incf gas +call-value-transfer-gas+)
      (when (and new-account-p (empty-account-p state callee))
        (incf gas +call-new-account-gas+))
      (when stipend-discount-p
        (setf gas (max 0 (- gas +call-stipend+)))))
    gas))

(defun selfdestruct-extra-gas (state contract beneficiary)
  (if (and (plusp (account-balance state contract))
           (empty-account-p state beneficiary))
      +call-new-account-gas+
      0))

(defun contract-address-collision-p (state address)
  (not (empty-account-p state address)))

(defun account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun transfer-call-value (state sender recipient value)
  (let ((sender-account (account-or-empty state sender)))
    (when (< (state-account-balance sender-account) value)
      (fail "Insufficient balance for CALL value"))
    (unless (or (zerop value)
                (bytes= (address-bytes sender) (address-bytes recipient)))
      (let ((recipient-account (account-or-empty state recipient)))
        (put-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (put-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))))

(defun evm-resolved-code (state address)
  (let* ((code (state-db-get-code state address))
         (delegation-target (set-code-delegation-target code)))
    (if delegation-target
        (state-db-get-code state delegation-target)
        code)))

(defun selfdestruct-account (state address beneficiary)
  (let* ((account (account-or-empty state address))
         (balance (state-account-balance account)))
    (unless (bytes= (address-bytes address) (address-bytes beneficiary))
      (state-db-add-balance state beneficiary balance)
      (put-account-values
       state
       address
       (state-account-nonce account)
       0
       (state-account-code-hash account)))))

(defun create-address (creator nonce)
  (let* ((hash (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes creator) nonce))))
         (out (make-byte-vector 20)))
    (replace out hash :start2 12)
    (make-address out)))

(defun create2-address (creator salt initcode)
  (let* ((hash (keccak-256
                (concat-bytes
                 #(255)
                 (address-bytes creator)
                 (hash32-bytes (word-to-hash32 salt))
                 (keccak-256 initcode))))
         (out (make-byte-vector 20)))
    (replace out hash :start2 12)
    (make-address out)))

(defun initcode-word-count (size)
  (ceiling size 32))

(defun eip3860-initcode-rules-active-p (rules)
  (or (null rules) (chain-rules-shanghai-p rules)))

(defun contract-code-size-limit (rules)
  (if (and rules (chain-rules-amsterdam-p rules))
      +amsterdam-max-contract-code-size+
      +max-contract-code-size+))

(defun contract-initcode-size-limit (rules)
  (* 2 (contract-code-size-limit rules)))

(defun create-initcode-extra-gas (size &key create2-p rules)
  (let ((word-count (initcode-word-count size)))
    (if (eip3860-initcode-rules-active-p rules)
        (progn
          (when (> size (contract-initcode-size-limit rules))
            (fail "EVM initcode exceeds maximum size"))
          (* word-count
             (+ +initcode-word-gas+
                (if create2-p +keccak256-word-gas+ 0))))
        (if create2-p
            (* word-count +keccak256-word-gas+)
            0))))

(defun created-code-deposit-gas (code)
  (* +create-data-gas+ (length (ensure-byte-vector code))))

(defun eip3541-code-prefix-restricted-p (rules)
  (or (null rules) (chain-rules-london-p rules)))

(defun invalid-created-runtime-code-p (code &optional rules)
  (let ((code (ensure-byte-vector code)))
    (or (> (length code) (contract-code-size-limit rules))
        (and (eip3541-code-prefix-restricted-p rules)
             (plusp (length code))
             (= (aref code 0) #xef)))))

(defun remaining-gas (gas-limit gas-used)
  (if gas-limit
      (max 0 (- gas-limit gas-used))
      0))

(defun all-but-one-64th (gas)
  (- gas (floor gas 64)))

(defun child-call-gas-limit (requested gas-limit gas-used &key (stipend 0))
  (+ stipend
     (if gas-limit
         (min requested (all-but-one-64th (remaining-gas gas-limit gas-used)))
         requested)))

(defun call-child-gas-charge (child-gas-used value)
  (if (plusp value)
      (max 0 (- child-gas-used +call-stipend+))
      child-gas-used))

(defun child-create-gas-limit (gas-limit gas-used)
  (and gas-limit
       (all-but-one-64th (remaining-gas gas-limit gas-used))))

(defun increment-account-nonce (state address)
  (let ((account (account-or-empty state address)))
    (when (= (state-account-nonce account) +max-account-nonce+)
      (fail "EVM account nonce overflow"))
    (put-account-values
     state
     address
     (1+ (state-account-nonce account))
     (state-account-balance account)
     (state-account-code-hash account))))

(defun account-code-hash-word (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (hash32-to-word (state-account-code-hash account))
        0)))

(defun blockhash-word (context number)
  (let* ((current (evm-context-block-number context))
         (lower (if (< current 257) 0 (- current 256))))
    (if (and (>= number lower) (< number current))
        (let ((hash (gethash number (evm-context-block-hashes context))))
          (if hash (hash32-to-word hash) 0))
        0)))

(defun blobhash-word (context index)
  (let ((hashes (evm-context-blob-hashes context)))
    (if (< index (length hashes))
        (hash32-to-word (elt hashes index))
        0)))
