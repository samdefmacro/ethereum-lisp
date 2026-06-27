(in-package #:ethereum-lisp.evm)

(define-condition evm-error (error)
  ((message :initarg :message :reader evm-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (evm-error-message condition)))))

(define-condition evm-precompile-error (evm-error)
  ((gas-used :initarg :gas-used :reader evm-precompile-error-gas-used)))

(defun precompile-address (number)
  (let ((bytes (make-byte-vector 20)))
    (setf (aref bytes 19) number)
    (make-address bytes)))

(defun active-precompile-address-number-p (number rules)
  (or (null rules)
      (<= number 4)
      (and (<= 5 number 8) (chain-rules-byzantium-p rules))
      (and (= number 9) (chain-rules-istanbul-p rules))
      (and (= number 10) (chain-rules-cancun-p rules))))

(defun prewarm-precompile-addresses (accessed-addresses &optional rules)
  (dotimes (i 10 accessed-addresses)
    (let ((number (1+ i)))
      (when (active-precompile-address-number-p number rules)
        (setf (gethash (address-bytes (precompile-address number))
                       accessed-addresses)
              t)))))

(defun make-initial-accessed-addresses (&optional rules)
  (prewarm-precompile-addresses (make-hash-table :test 'equalp) rules))

(defstruct evm-result
  (status :stopped)
  (stack '() :type list)
  (memory (make-byte-vector 0) :type byte-vector)
  (return-data (make-byte-vector 0) :type byte-vector)
  (logs '() :type list)
  (pc 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (refund-counter 0 :type integer))

(defstruct (evm-context (:constructor make-evm-context
                          (&key state
                                (address (zero-address))
                                (caller (zero-address))
                                (origin (zero-address))
                                (call-value 0)
                                (gas-price 0)
                                (input #())
                                (return-data #())
                                (coinbase (zero-address))
                                (timestamp 0)
                                (block-number 0)
                                (prev-randao (zero-hash32))
                                (difficulty 0)
                                (random-p t)
                                (gas-limit 0)
                                (chain-id 0)
                                chain-rules
                                (base-fee 0)
                                (blob-hashes #())
                                (blob-base-fee 0)
                                (transient-storage
                                 (make-hash-table :test 'equalp))
                                (storage-originals
                                 (make-hash-table :test 'equalp))
                                (storage-clears
                                 (make-hash-table :test 'equalp))
                                (selfdestructed-addresses
                                 (make-hash-table :test 'equalp))
                                (accessed-storage
                                 (make-hash-table :test 'equalp))
                                (accessed-addresses
                                 (make-initial-accessed-addresses chain-rules))
                                (block-hashes (make-hash-table))
                                (read-only-p nil))))
  state
  address
  caller
  origin
  (call-value 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  input
  return-data
  coinbase
  (timestamp 0 :type (integer 0 *))
  (block-number 0 :type (integer 0 *))
  prev-randao
  (difficulty 0 :type (integer 0 *))
  (random-p t :type boolean)
  (gas-limit 0 :type (integer 0 *))
  (chain-id 0 :type (integer 0 *))
  chain-rules
  (base-fee 0 :type (integer 0 *))
  blob-hashes
  (blob-base-fee 0 :type (integer 0 *))
  transient-storage
  storage-originals
  storage-clears
  selfdestructed-addresses
  accessed-storage
  accessed-addresses
  block-hashes
  (read-only-p nil :type boolean))

(defconstant +word-modulus+ (expt 2 256))
(defconstant +stack-limit+ 1024)
(defconstant +max-account-nonce+ (1- (ash 1 64)))
(defconstant +initcode-word-gas+ 2)
(defconstant +keccak256-word-gas+ 6)
(defconstant +max-contract-code-size+ 24576)
(defconstant +max-initcode-size+ 49152)
(defconstant +amsterdam-max-contract-code-size+ 32768)
(defconstant +amsterdam-max-initcode-size+
  (* 2 +amsterdam-max-contract-code-size+))
(defconstant +call-stipend+ 2300)
(defconstant +call-value-transfer-gas+ 9000)
(defconstant +call-new-account-gas+ 25000)
(defconstant +cold-account-access-cost-eip2929+ 2600)
(defconstant +cold-sload-cost-eip2929+ 2100)
(defconstant +warm-storage-read-cost-eip2929+ 100)
(defconstant +sstore-sentry-gas-eip2200+ 2300)
(defconstant +sstore-set-gas-eip2200+ 20000)
(defconstant +sstore-reset-gas-eip2200+ 5000)
(defconstant +sstore-clears-schedule-refund-eip3529+ 4800)
(defconstant +sstore-reset-original-refund-eip3529+ 2800)
(defconstant +sstore-reset-original-zero-refund-eip3529+ 19900)
(defconstant +memory-gas+ 3)
(defconstant +memory-quad-divisor+ 512)
(defconstant +copy-word-gas+ 3)
(defconstant +log-topic-gas+ 375)
(defconstant +log-data-gas+ 8)
(defconstant +ecrecover-gas+ 3000)
(defconstant +sha256-base-gas+ 60)
(defconstant +sha256-word-gas+ 12)
(defconstant +ripemd160-base-gas+ 600)
(defconstant +ripemd160-word-gas+ 120)
(defconstant +modexp-min-gas+ 200)
(defconstant +modexp-quad-divisor+ 3)
(defconstant +modexp-exp-byte-multiplier+ 8)
(defconstant +bn254-field-prime+
  21888242871839275222246405745257275088696311157297823662689037894645226208583)
(defconstant +bn254-curve-order+
  21888242871839275222246405745257275088548364400416034343698204186575808495617)
(defconstant +bn254-add-gas+ 150)
(defconstant +bn254-mul-gas+ 6000)
(defconstant +bn254-pairing-base-gas+ 45000)
(defconstant +bn254-pairing-per-point-gas+ 34000)
(defconstant +kzg-point-evaluation-gas+ 50000)
(defconstant +kzg-point-evaluation-input-size+ 192)
(defconstant +bls-field-elements-per-blob+ 4096)
(defconstant +bls-field-modulus+
  #x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
(defconstant +blake2f-input-size+ 213)
(defconstant +uint64-modulus+ (expt 2 64))
(defconstant +uint64-mask+ #xffffffffffffffff)
(defconstant +identity-base-gas+ 15)
(defconstant +identity-word-gas+ 3)
(defconstant +create-data-gas+ 200)

(defparameter +blake2b-iv+
  #(#x6a09e667f3bcc908 #xbb67ae8584caa73b
    #x3c6ef372fe94f82b #xa54ff53a5f1d36f1
    #x510e527fade682d1 #x9b05688c2b3e6c1f
    #x1f83d9abfb41bd6b #x5be0cd19137e2179))

(defparameter +blake2b-sigma+
  #(#(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
    #(14 10 4 8 9 15 13 6 1 12 0 2 11 7 5 3)
    #(11 8 12 0 5 2 15 13 10 14 3 6 7 1 9 4)
    #(7 9 3 1 13 12 11 14 2 6 5 10 4 0 15 8)
    #(9 0 5 7 2 4 10 15 14 1 11 12 6 8 3 13)
    #(2 12 6 10 0 11 8 3 4 13 7 5 15 14 1 9)
    #(12 5 1 15 14 13 4 10 0 7 6 3 9 2 8 11)
    #(13 11 7 14 12 1 3 9 5 0 15 4 8 6 2 10)
    #(6 15 14 9 11 3 0 8 12 2 13 7 1 4 10 5)
    #(10 2 8 4 7 6 1 5 15 11 9 14 3 12 13 0)))

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
  (let ((memory (ensure-memory-size memory (+ offset size))))
    (subseq memory offset (+ offset size))))

(defun copy-into-memory (memory memory-offset data)
  (let* ((data (ensure-byte-vector data))
         (memory (ensure-memory-size memory (+ memory-offset (length data)))))
    (replace memory data :start1 memory-offset)
    memory))

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
                  #x41 #x42 #x43 #x44 #x45 #x46 #x47 #x48
                  #x4a #x58 #x59 #x5a)
             :test #'=)
     2)
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
             (bytes= (hash32-bytes (state-account-code-hash account))
                     (hash32-bytes +empty-code-hash+))))))

(defun call-value-extra-gas (state callee value &key new-account-p)
  (let ((gas 0))
    (when (plusp value)
      (incf gas +call-value-transfer-gas+)
      (when (and new-account-p (empty-account-p state callee))
        (incf gas +call-new-account-gas+)))
    gas))

(defun selfdestruct-extra-gas (state contract beneficiary)
  (if (and (plusp (account-balance state contract))
           (empty-account-p state beneficiary))
      +call-new-account-gas+
      0))

(defun contract-address-collision-p (state address)
  (let ((account (state-db-get-account state address)))
    (and account
         (or (plusp (state-account-nonce account))
             (not (bytes= (hash32-bytes (state-account-code-hash account))
                          (hash32-bytes +empty-code-hash+)))))))

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

(defun integer-to-fixed-bytes (value size)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector size))
         (copy-size (min size (length minimal))))
    (replace result
             minimal
             :start1 (- size copy-size)
             :start2 (- (length minimal) copy-size))
    result))

(defun u64 (value)
  (logand value +uint64-mask+))

(defun rotr64 (value count)
  (let ((count (mod count 64))
        (value (u64 value)))
    (if (zerop count)
        value
        (u64 (logior (ash value (- count))
                     (ash value (- 64 count)))))))

(defun load-little-endian-u64 (bytes start)
  (loop for i below 8
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u64 (value bytes start)
  (loop for i below 8
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun load-big-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 (- 3 i)))))

(defun modular-expt (base exponent modulus)
  (cond
    ((zerop modulus) 0)
    ((zerop exponent) (mod 1 modulus))
    (t
     (loop with result = 1
           with factor = (mod base modulus)
           for exp = exponent then (ash exp -1)
           while (plusp exp)
           do (when (oddp exp)
                (setf result (mod (* result factor) modulus)))
              (setf factor (mod (* factor factor) modulus))
           finally (return result)))))

(defun modexp-iteration-count (exp-len exp-head)
  (max 1
       (+ (if (> exp-len 32)
              (* (- exp-len 32) +modexp-exp-byte-multiplier+)
              0)
          (let ((bits (integer-length exp-head)))
            (if (plusp bits) (1- bits) 0)))))

(defun modexp-gas (base-len exp-len mod-len exp-head)
  (let* ((max-len (max base-len mod-len))
         (words (ceiling max-len 8))
         (mult-complexity (* words words))
         (iteration-count (modexp-iteration-count exp-len exp-head)))
    (max +modexp-min-gas+
         (floor (* mult-complexity iteration-count)
                +modexp-quad-divisor+))))

(defun run-modexp-precompile (input)
  (let* ((base-len (bytes-to-integer (padded-data-slice input 0 32)))
         (exp-len (bytes-to-integer (padded-data-slice input 32 32)))
         (mod-len (bytes-to-integer (padded-data-slice input 64 32)))
         (body (if (> (length input) 96)
                   (subseq input 96)
                   (make-byte-vector 0)))
         (exp-head-size (if (> exp-len 32) 32 exp-len))
         (exp-head (if (plusp exp-head-size)
                       (bytes-to-integer
                        (padded-data-slice body base-len exp-head-size))
                       0))
         (gas (modexp-gas base-len exp-len mod-len exp-head)))
    (if (and (zerop base-len) (zerop mod-len))
        (values (make-byte-vector 0) gas)
        (let* ((base (bytes-to-integer (padded-data-slice body 0 base-len)))
               (exponent (bytes-to-integer
                          (padded-data-slice body base-len exp-len)))
               (modulus (bytes-to-integer
                         (padded-data-slice body (+ base-len exp-len) mod-len)))
               (value (if (zerop modulus)
                          0
                          (modular-expt base exponent modulus))))
          (values (integer-to-fixed-bytes value mod-len) gas)))))

(defun bn254-modular-inverse (value)
  (labels ((egcd (a b)
             (if (zerop b)
                 (values a 1 0)
                 (multiple-value-bind (g x y) (egcd b (mod a b))
                   (values g y (- x (* (floor a b) y)))))))
    (multiple-value-bind (g x ignored)
        (egcd (mod value +bn254-field-prime+) +bn254-field-prime+)
      (declare (ignore ignored))
      (unless (= g 1)
        (fail "BN254 modular inverse does not exist"))
      (mod x +bn254-field-prime+))))

(defun bn254-valid-coordinate-p (value)
  (< value +bn254-field-prime+))

(defun bn254-on-curve-p (x y)
  (= (mod (* y y) +bn254-field-prime+)
     (mod (+ (* x x x) 3) +bn254-field-prime+)))

(defun parse-bn254-g1-point (bytes gas-used)
  (let* ((bytes (padded-data-slice bytes 0 64))
         (x (bytes-to-integer (subseq bytes 0 32)))
         (y (bytes-to-integer (subseq bytes 32 64))))
    (cond
      ((and (zerop x) (zerop y)) nil)
      ((and (bn254-valid-coordinate-p x)
            (bn254-valid-coordinate-p y)
            (bn254-on-curve-p x y))
       (cons x y))
      (t
       (fail-precompile gas-used "Invalid BN254 G1 point")))))

(defun serialize-bn254-g1-point (point)
  (if point
      (concat-bytes (integer-to-fixed-bytes (car point) 32)
                    (integer-to-fixed-bytes (cdr point) 32))
      (make-byte-vector 64)))

(defun bn254-g1-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (let ((x1 (car left))
           (y1 (cdr left))
           (x2 (car right))
           (y2 (cdr right)))
       (cond
         ((and (= x1 x2)
               (zerop (mod (+ y1 y2) +bn254-field-prime+)))
          nil)
         (t
          (let* ((slope
                   (if (= x1 x2)
                       (mod (* 3 x1 x1
                               (bn254-modular-inverse (* 2 y1)))
                            +bn254-field-prime+)
                       (mod (* (- y2 y1)
                               (bn254-modular-inverse (- x2 x1)))
                            +bn254-field-prime+)))
                 (x3 (mod (- (* slope slope) x1 x2)
                          +bn254-field-prime+))
                 (y3 (mod (- (* slope (- x1 x3)) y1)
                          +bn254-field-prime+)))
            (cons x3 y3))))))))

(defun bn254-g1-mul (point scalar)
  (loop with result = nil
        with addend = point
        for k = scalar then (ash k -1)
        while (plusp k)
        do (when (oddp k)
             (setf result (bn254-g1-add result addend)))
           (setf addend (bn254-g1-add addend addend))
        finally (return result)))

(defun run-bn254-add-precompile (input)
  (let* ((left (parse-bn254-g1-point (padded-data-slice input 0 64)
                                     +bn254-add-gas+))
         (right (parse-bn254-g1-point (padded-data-slice input 64 64)
                                      +bn254-add-gas+)))
    (values (serialize-bn254-g1-point (bn254-g1-add left right))
            +bn254-add-gas+)))

(defun run-bn254-mul-precompile (input)
  (let* ((point (parse-bn254-g1-point (padded-data-slice input 0 64)
                                      +bn254-mul-gas+))
         (scalar (bytes-to-integer (padded-data-slice input 64 32))))
    (values (serialize-bn254-g1-point (bn254-g1-mul point scalar))
            +bn254-mul-gas+)))

(defun bn254-pairing-gas (input)
  (+ +bn254-pairing-base-gas+
     (* +bn254-pairing-per-point-gas+
        (floor (length (ensure-byte-vector input)) 192))))

(defun bn254-fp2 (real imaginary)
  (cons (mod real +bn254-field-prime+)
        (mod imaginary +bn254-field-prime+)))

(defun bn254-fp2-add (left right)
  (bn254-fp2 (+ (car left) (car right))
             (+ (cdr left) (cdr right))))

(defun bn254-fp2-sub (left right)
  (bn254-fp2 (- (car left) (car right))
             (- (cdr left) (cdr right))))

(defun bn254-fp2-mul (left right)
  (let ((a (car left))
        (b (cdr left))
        (c (car right))
        (d (cdr right)))
    (bn254-fp2 (- (* a c) (* b d))
               (+ (* a d) (* b c)))))

(defun bn254-fp2-square (value)
  (bn254-fp2-mul value value))

(defun bn254-fp2-neg (value)
  (bn254-fp2 (- (car value)) (- (cdr value))))

(defun bn254-fp2-double (value)
  (bn254-fp2 (+ (car value) (car value))
             (+ (cdr value) (cdr value))))

(defun bn254-fp2-mul-scalar (value scalar)
  (bn254-fp2 (* (car value) scalar)
             (* (cdr value) scalar)))

(defun bn254-fp2-conjugate (value)
  (bn254-fp2 (car value) (- (cdr value))))

(defun bn254-fp2-zero ()
  (bn254-fp2 0 0))

(defun bn254-fp2-one ()
  (bn254-fp2 1 0))

(defun bn254-fp2-zero-p (value)
  (and (zerop (car value)) (zerop (cdr value))))

(defun bn254-fp2-one-p (value)
  (and (= 1 (car value)) (zerop (cdr value))))

(defun bn254-fp2-mul-xi (value)
  "Multiply VALUE by xi = 9 + i in Fp2."
  (let ((real (car value))
        (imaginary (cdr value)))
    (bn254-fp2 (- (* 9 real) imaginary)
               (+ real (* 9 imaginary)))))

(defun bn254-fp2-inverse (value)
  (let* ((real (car value))
         (imaginary (cdr value))
         (denominator
           (mod (+ (* real real) (* imaginary imaginary))
                +bn254-field-prime+)))
    (when (zerop denominator)
      (fail "BN254 Fp2 inverse does not exist"))
    (let ((inverse (bn254-modular-inverse denominator)))
      (bn254-fp2 (* real inverse)
                 (- (* imaginary inverse))))))

(defun bn254-g2-curve-constant ()
  (let ((inverse-82 (bn254-modular-inverse 82)))
    (bn254-fp2 (* 27 inverse-82)
               (- (* 3 inverse-82)))))

(defun bn254-g2-on-curve-p (x y)
  (let ((left (bn254-fp2-square y))
        (right (bn254-fp2-add
                (bn254-fp2-mul (bn254-fp2-square x) x)
                (bn254-g2-curve-constant))))
    (and (= (car left) (car right))
         (= (cdr left) (cdr right)))))

(defun bn254-g2-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (destructuring-bind (x1 y1) left
       (destructuring-bind (x2 y2) right
         (cond
           ((and (bn254-fp2= x1 x2)
                 (bn254-fp2-negation-p y1 y2))
            nil)
           (t
            (let* ((slope
                     (if (and (bn254-fp2= x1 x2)
                              (bn254-fp2= y1 y2))
                         (bn254-fp2-mul
                          (bn254-fp2-mul (bn254-fp2 3 0)
                                         (bn254-fp2-square x1))
                          (bn254-fp2-inverse
                           (bn254-fp2-mul (bn254-fp2 2 0) y1)))
                         (bn254-fp2-mul
                          (bn254-fp2-sub y2 y1)
                          (bn254-fp2-inverse (bn254-fp2-sub x2 x1)))))
                   (x3 (bn254-fp2-sub
                        (bn254-fp2-sub (bn254-fp2-square slope) x1)
                        x2))
                   (y3 (bn254-fp2-sub
                        (bn254-fp2-mul slope (bn254-fp2-sub x1 x3))
                        y1)))
              (list x3 y3)))))))))

(defun bn254-g2-mul (point scalar)
  (loop with result = nil
        with addend = point
        for k = scalar then (ash k -1)
        while (plusp k)
        do (when (oddp k)
             (setf result (bn254-g2-add result addend)))
           (setf addend (bn254-g2-add addend addend))
        finally (return result)))

(defun bn254-g2-subgroup-p (point)
  (null (bn254-g2-mul point +bn254-curve-order+)))

(defun parse-bn254-g2-pairing-point (bytes gas-used)
  (let ((bytes (padded-data-slice bytes 0 128)))
    (cond
      ((loop for byte across bytes always (zerop byte)) nil)
      (t
       (let ((x-imaginary (bytes-to-integer (subseq bytes 0 32)))
             (x-real (bytes-to-integer (subseq bytes 32 64)))
             (y-imaginary (bytes-to-integer (subseq bytes 64 96)))
             (y-real (bytes-to-integer (subseq bytes 96 128))))
         (unless (and (bn254-valid-coordinate-p x-real)
                      (bn254-valid-coordinate-p x-imaginary)
                      (bn254-valid-coordinate-p y-real)
                      (bn254-valid-coordinate-p y-imaginary))
           (fail-precompile gas-used "Invalid BN254 G2 coordinate"))
         (let ((x (bn254-fp2 x-real x-imaginary))
               (y (bn254-fp2 y-real y-imaginary)))
           (unless (bn254-g2-on-curve-p x y)
             (fail-precompile gas-used "Invalid BN254 G2 point"))
           (let ((point (list x y)))
             (unless (bn254-g2-subgroup-p point)
               (fail-precompile gas-used "Invalid BN254 G2 subgroup"))
             point)))))))

(defun bn254-fp2= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun bn254-fp2-negation-p (left right)
  (and (zerop (mod (+ (car left) (car right))
                   +bn254-field-prime+))
       (zerop (mod (+ (cdr left) (cdr right))
                   +bn254-field-prime+))))

(defun bn254-fp6 (x y z)
  (list x y z))

(defun bn254-fp6-x (value) (first value))
(defun bn254-fp6-y (value) (second value))
(defun bn254-fp6-z (value) (third value))

(defun bn254-fp6-zero ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-zero)))

(defun bn254-fp6-one ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-one)))

(defun bn254-fp6-zero-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-zero-p (bn254-fp6-z value))))

(defun bn254-fp6-one-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-one-p (bn254-fp6-z value))))

(defun bn254-fp6-neg (value)
  (bn254-fp6 (bn254-fp2-neg (bn254-fp6-x value))
             (bn254-fp2-neg (bn254-fp6-y value))
             (bn254-fp2-neg (bn254-fp6-z value))))

(defun bn254-fp6-add (left right)
  (bn254-fp6 (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-add (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-sub (left right)
  (bn254-fp6 (bn254-fp2-sub (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-sub (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-sub (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-double (value)
  (bn254-fp6 (bn254-fp2-double (bn254-fp6-x value))
             (bn254-fp2-double (bn254-fp6-y value))
             (bn254-fp2-double (bn254-fp6-z value))))

(defun bn254-fp6-mul (left right)
  (let* ((v0 (bn254-fp2-mul (bn254-fp6-z left) (bn254-fp6-z right)))
         (v1 (bn254-fp2-mul (bn254-fp6-y left) (bn254-fp6-y right)))
         (v2 (bn254-fp2-mul (bn254-fp6-x left) (bn254-fp6-x right)))
         (tz (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-y left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-y right))))
         (tz (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub tz v1) v2))
              v0))
         (ty (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-y right) (bn254-fp6-z right))))
         (ty (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub ty v0) v1)
              (bn254-fp2-mul-xi v2)))
         (tx (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-z right))))
         (tx (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub tx v0) v1) v2)))
    (bn254-fp6 tx ty tz)))

(defun bn254-fp6-square (value)
  (let* ((v0 (bn254-fp2-square (bn254-fp6-z value)))
         (v1 (bn254-fp2-square (bn254-fp6-y value)))
         (v2 (bn254-fp2-square (bn254-fp6-x value)))
         (c0 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-y value))))
         (c0 (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub c0 v1) v2))
              v0))
         (c1 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-y value) (bn254-fp6-z value))))
         (c1 (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub c1 v0) v1)
              (bn254-fp2-mul-xi v2)))
         (c2 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-z value))))
         (c2 (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub c2 v0) v1) v2)))
    (bn254-fp6 c2 c1 c0)))

(defun bn254-fp6-mul-scalar-fp2 (value scalar)
  (bn254-fp6 (bn254-fp2-mul (bn254-fp6-x value) scalar)
             (bn254-fp2-mul (bn254-fp6-y value) scalar)
             (bn254-fp2-mul (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-scalar-fp (value scalar)
  (bn254-fp6 (bn254-fp2-mul-scalar (bn254-fp6-x value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-y value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-tau (value)
  (bn254-fp6 (bn254-fp6-y value)
             (bn254-fp6-z value)
             (bn254-fp2-mul-xi (bn254-fp6-x value))))

(defun bn254-fp6-inverse (value)
  (let* ((a (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-z value))
             (bn254-fp2-mul-xi
              (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-y value)))))
         (b (bn254-fp2-sub
             (bn254-fp2-mul-xi (bn254-fp2-square (bn254-fp6-x value)))
             (bn254-fp2-mul (bn254-fp6-y value) (bn254-fp6-z value))))
         (c (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-y value))
             (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-z value))))
         (f (bn254-fp2-add
             (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-mul c (bn254-fp6-y value)))
              (bn254-fp2-mul a (bn254-fp6-z value)))
             (bn254-fp2-mul-xi (bn254-fp2-mul b (bn254-fp6-x value)))))
         (f-inv (bn254-fp2-inverse f)))
    (bn254-fp6 (bn254-fp2-mul c f-inv)
               (bn254-fp2-mul b f-inv)
               (bn254-fp2-mul a f-inv))))

(defparameter +bn254-xi-to-p-minus-1-over-6+
  (bn254-fp2 8376118865763821496583973867626364092589906065868298776909617916018768340080
             16469823323077808223889137241176536799009286646108169935659301613961712198316))

(defparameter +bn254-xi-to-p-minus-1-over-3+
  (bn254-fp2 21575463638280843010398324269430826099269044274347216827212613867836435027261
             10307601595873709700152284273816112264069230130616436755625194854815875713954))

(defparameter +bn254-xi-to-p-minus-1-over-2+
  (bn254-fp2 2821565182194536844548159561693502659359617185244120367078079554186484126554
             3505843767911556378687030309984248845540243509899259641013678093033130930403))

(defparameter +bn254-xi-to-p-squared-minus-1-over-3+
  21888242871839275220042445260109153167277707414472061641714758635765020556616)

(defparameter +bn254-xi-to-2p-squared-minus-2-over-3+
  2203960485148121921418603742825762020974279258880205651966)

(defparameter +bn254-xi-to-p-squared-minus-1-over-6+
  21888242871839275220042445260109153167277707414472061641714758635765020556617)

(defparameter +bn254-xi-to-2p-minus-2-over-3+
  (bn254-fp2 2581911344467009335267311115468803099551665605076196740867805258568234346338
             19937756971775647987995932169929341994314640652964949448313374472400716661030))

(defun bn254-fp6-frobenius (value)
  (bn254-fp6
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-x value))
    +bn254-xi-to-2p-minus-2-over-3+)
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-y value))
    +bn254-xi-to-p-minus-1-over-3+)
   (bn254-fp2-conjugate (bn254-fp6-z value))))

(defun bn254-fp6-frobenius-p2 (value)
  (bn254-fp6
   (bn254-fp2-mul-scalar (bn254-fp6-x value)
                         +bn254-xi-to-2p-squared-minus-2-over-3+)
   (bn254-fp2-mul-scalar (bn254-fp6-y value)
                         +bn254-xi-to-p-squared-minus-1-over-3+)
   (bn254-fp6-z value)))

(defun bn254-fp12 (x y)
  (list x y))

(defun bn254-fp12-x (value) (first value))
(defun bn254-fp12-y (value) (second value))

(defun bn254-fp12-one ()
  (bn254-fp12 (bn254-fp6-zero) (bn254-fp6-one)))

(defun bn254-fp12-one-p (value)
  (and (bn254-fp6-zero-p (bn254-fp12-x value))
       (bn254-fp6-one-p (bn254-fp12-y value))))

(defun bn254-fp12-conjugate (value)
  (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
              (bn254-fp12-y value)))

(defun bn254-fp12-mul (left right)
  (let* ((tx (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-y right))
              (bn254-fp6-mul (bn254-fp12-x right) (bn254-fp12-y left))))
         (ty (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-y left) (bn254-fp12-y right))
              (bn254-fp6-mul-tau
               (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-x right))))))
    (bn254-fp12 tx ty)))

(defun bn254-fp12-mul-scalar-fp6 (value scalar)
  (bn254-fp12 (bn254-fp6-mul (bn254-fp12-x value) scalar)
              (bn254-fp6-mul (bn254-fp12-y value) scalar)))

(defun bn254-fp12-square (value)
  (let* ((v0 (bn254-fp6-mul (bn254-fp12-x value) (bn254-fp12-y value)))
         (tau-term (bn254-fp6-add (bn254-fp6-mul-tau (bn254-fp12-x value))
                                  (bn254-fp12-y value)))
         (ty (bn254-fp6-mul
              (bn254-fp6-add (bn254-fp12-x value) (bn254-fp12-y value))
              tau-term))
         (ty (bn254-fp6-sub
              (bn254-fp6-sub ty v0)
              (bn254-fp6-mul-tau v0))))
    (bn254-fp12 (bn254-fp6-double v0) ty)))

(defun bn254-fp12-inverse (value)
  (let* ((t1 (bn254-fp6-mul-tau
              (bn254-fp6-square (bn254-fp12-x value))))
         (t2 (bn254-fp6-square (bn254-fp12-y value)))
         (inv (bn254-fp6-inverse (bn254-fp6-sub t2 t1))))
    (bn254-fp12-mul-scalar-fp6
     (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
                 (bn254-fp12-y value))
     inv)))

(defun bn254-fp12-exp (value power)
  (loop with result = (bn254-fp12-one)
        for i from (1- (integer-length power)) downto 0
        do (setf result (bn254-fp12-square result))
           (when (logbitp i power)
             (setf result (bn254-fp12-mul result value)))
        finally (return result)))

(defun bn254-fp12-frobenius (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp2
    (bn254-fp6-frobenius (bn254-fp12-x value))
    +bn254-xi-to-p-minus-1-over-6+)
   (bn254-fp6-frobenius (bn254-fp12-y value))))

(defun bn254-fp12-frobenius-p2 (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp
    (bn254-fp6-frobenius-p2 (bn254-fp12-x value))
    +bn254-xi-to-p-squared-minus-1-over-6+)
   (bn254-fp6-frobenius-p2 (bn254-fp12-y value))))

(defun bn254-twist-point (x y z tt)
  (list x y z tt))

(defun bn254-twist-x (point) (first point))
(defun bn254-twist-y (point) (second point))
(defun bn254-twist-z (point) (third point))
(defun bn254-twist-t (point) (fourth point))

(defun bn254-twist-affine (point)
  (destructuring-bind (x y) point
    (bn254-twist-point x y (bn254-fp2-one) (bn254-fp2-one))))

(defun bn254-twist-neg (point)
  (bn254-twist-point (bn254-twist-x point)
                     (bn254-fp2-neg (bn254-twist-y point))
                     (bn254-twist-z point)
                     (bn254-fp2-zero)))

(defun bn254-line-function-add (r p q r2)
  (let* ((b (bn254-fp2-mul (bn254-twist-x p) (bn254-twist-t r)))
         (d (bn254-fp2-square
             (bn254-fp2-add (bn254-twist-y p) (bn254-twist-z r))))
         (d (bn254-fp2-mul
             (bn254-fp2-sub
              (bn254-fp2-sub d r2)
              (bn254-twist-t r))
             (bn254-twist-t r)))
         (h (bn254-fp2-sub b (bn254-twist-x r)))
         (i (bn254-fp2-square h))
         (e (bn254-fp2-double (bn254-fp2-double i)))
         (j (bn254-fp2-mul h e))
         (l1 (bn254-fp2-sub
              (bn254-fp2-sub d (bn254-twist-y r))
              (bn254-twist-y r)))
         (v (bn254-fp2-mul (bn254-twist-x r) e))
         (out-x (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-sub (bn254-fp2-square l1) j)
                  v)
                 v))
         (out-z (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-square
                   (bn254-fp2-add (bn254-twist-z r) h))
                  (bn254-twist-t r))
                 i))
         (out-y (bn254-fp2-sub
                 (bn254-fp2-mul l1 (bn254-fp2-sub v out-x))
                 (bn254-fp2-double (bn254-fp2-mul (bn254-twist-y r) j))))
         (out-t (bn254-fp2-square out-z))
         (line-temp (bn254-fp2-square (bn254-fp2-add (bn254-twist-y p) out-z)))
         (line-temp (bn254-fp2-sub (bn254-fp2-sub line-temp r2) out-t))
         (t2 (bn254-fp2-double (bn254-fp2-mul l1 (bn254-twist-x p))))
         (a (bn254-fp2-sub t2 line-temp))
         (c (bn254-fp2-double (bn254-fp2-mul-scalar out-z (cdr q))))
         (line-b (bn254-fp2-double
                  (bn254-fp2-mul-scalar (bn254-fp2-neg l1) (car q)))))
    (values a line-b c (bn254-twist-point out-x out-y out-z out-t))))

(defun bn254-line-function-double (r q)
  (let* ((a0 (bn254-fp2-square (bn254-twist-x r)))
         (b0 (bn254-fp2-square (bn254-twist-y r)))
         (c0 (bn254-fp2-square b0))
         (d (bn254-fp2-square (bn254-fp2-add (bn254-twist-x r) b0)))
         (d (bn254-fp2-double (bn254-fp2-sub (bn254-fp2-sub d a0) c0)))
         (e (bn254-fp2-add (bn254-fp2-double a0) a0))
         (g (bn254-fp2-square e))
         (out-x (bn254-fp2-sub (bn254-fp2-sub g d) d))
         (out-z (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-square
                   (bn254-fp2-add (bn254-twist-y r) (bn254-twist-z r)))
                  b0)
                 (bn254-twist-t r)))
         (out-y (bn254-fp2-sub
                 (bn254-fp2-mul (bn254-fp2-sub d out-x) e)
                 (bn254-fp2-double
                  (bn254-fp2-double (bn254-fp2-double c0)))))
         (out-t (bn254-fp2-square out-z))
         (line-temp (bn254-fp2-double (bn254-fp2-mul e (bn254-twist-t r))))
         (line-b (bn254-fp2-mul-scalar (bn254-fp2-neg line-temp) (car q)))
         (line-a (bn254-fp2-sub
                  (bn254-fp2-sub
                   (bn254-fp2-square (bn254-fp2-add (bn254-twist-x r) e))
                   a0)
                  g))
         (line-a (bn254-fp2-sub line-a (bn254-fp2-double (bn254-fp2-double b0))))
         (line-c (bn254-fp2-mul-scalar
                  (bn254-fp2-double
                   (bn254-fp2-mul out-z (bn254-twist-t r)))
                  (cdr q))))
    (values line-a line-b line-c
            (bn254-twist-point out-x out-y out-z out-t))))

(defun bn254-fp12-mul-line (value a b c)
  (let* ((a2 (bn254-fp6 (bn254-fp2-zero) a b))
         (a2 (bn254-fp6-mul a2 (bn254-fp12-x value)))
         (t3 (bn254-fp6-mul-scalar-fp2 (bn254-fp12-y value) c))
         (line-temp (bn254-fp2-add b c))
         (t2 (bn254-fp6 (bn254-fp2-zero) a line-temp))
         (x (bn254-fp6-add (bn254-fp12-x value) (bn254-fp12-y value)))
         (x (bn254-fp6-sub (bn254-fp6-sub (bn254-fp6-mul x t2) a2) t3))
         (y (bn254-fp6-add t3 (bn254-fp6-mul-tau a2))))
    (bn254-fp12 x y)))

(defparameter +bn254-six-u-plus-2-naf+
  #(0 0 0 1 0 1 0 -1 0 0 1 -1 0 0 1 0
    0 1 1 0 -1 0 0 1 0 -1 0 0 0 0 1 1
    1 0 0 -1 0 0 1 0 0 0 0 0 -1 0 0 1
    1 0 0 -1 0 0 0 1 1 0 -1 0 0 1 0 1 1))

(defun bn254-miller (g2 g1)
  (let* ((a-affine (bn254-twist-affine g2))
         (minus-a (bn254-twist-neg a-affine))
         (r a-affine)
         (r2 (bn254-fp2-square (bn254-twist-y a-affine)))
         (ret (bn254-fp12-one))
         (last-index (1- (length +bn254-six-u-plus-2-naf+))))
    (loop for i from last-index downto 1
          do (progn
               (multiple-value-bind (a b c next-r)
                   (bn254-line-function-double r g1)
                 (unless (= i last-index)
                   (setf ret (bn254-fp12-square ret)))
                 (setf ret (bn254-fp12-mul-line ret a b c))
                 (setf r next-r))
               (case (aref +bn254-six-u-plus-2-naf+ (1- i))
                 (1
                  (multiple-value-bind (a b c next-r)
                      (bn254-line-function-add r a-affine g1 r2)
                    (setf ret (bn254-fp12-mul-line ret a b c))
                    (setf r next-r)))
                 (-1
                  (multiple-value-bind (a b c next-r)
                      (bn254-line-function-add r minus-a g1 r2)
                    (setf ret (bn254-fp12-mul-line ret a b c))
                    (setf r next-r))))))
    (let* ((q1 (bn254-twist-point
                (bn254-fp2-mul
                 (bn254-fp2-conjugate (bn254-twist-x a-affine))
                 +bn254-xi-to-p-minus-1-over-3+)
                (bn254-fp2-mul
                 (bn254-fp2-conjugate (bn254-twist-y a-affine))
                 +bn254-xi-to-p-minus-1-over-2+)
                (bn254-fp2-one)
                (bn254-fp2-one)))
           (minus-q2 (bn254-twist-point
                      (bn254-fp2-mul-scalar
                       (bn254-twist-x a-affine)
                       +bn254-xi-to-p-squared-minus-1-over-3+)
                      (bn254-twist-y a-affine)
                      (bn254-fp2-one)
                      (bn254-fp2-one))))
      (multiple-value-bind (a b c next-r)
          (bn254-line-function-add r q1 g1 (bn254-fp2-square (bn254-twist-y q1)))
        (setf ret (bn254-fp12-mul-line ret a b c))
        (setf r next-r))
      (multiple-value-bind (a b c next-r)
          (bn254-line-function-add
           r minus-q2 g1 (bn254-fp2-square (bn254-twist-y minus-q2)))
        (declare (ignore next-r))
        (setf ret (bn254-fp12-mul-line ret a b c))))
    ret))

(defun bn254-final-exponentiation (value)
  (let* ((t1 (bn254-fp12-conjugate value))
         (inv (bn254-fp12-inverse value))
         (t1 (bn254-fp12-mul t1 inv))
         (t2 (bn254-fp12-frobenius-p2 t1))
         (t1 (bn254-fp12-mul t1 t2))
         (fp (bn254-fp12-frobenius t1))
         (fp2 (bn254-fp12-frobenius-p2 t1))
         (fp3 (bn254-fp12-frobenius fp2))
         (fu (bn254-fp12-exp t1 4965661367192848881))
         (fu2 (bn254-fp12-exp fu 4965661367192848881))
         (fu3 (bn254-fp12-exp fu2 4965661367192848881))
         (y3 (bn254-fp12-frobenius fu))
         (fu2p (bn254-fp12-frobenius fu2))
         (fu3p (bn254-fp12-frobenius fu3))
         (y2 (bn254-fp12-frobenius-p2 fu2))
         (y0 (bn254-fp12-mul (bn254-fp12-mul fp fp2) fp3))
         (y1 (bn254-fp12-conjugate t1))
         (y5 (bn254-fp12-conjugate fu2))
         (y3 (bn254-fp12-conjugate y3))
         (y4 (bn254-fp12-conjugate (bn254-fp12-mul fu fu2p)))
         (y6 (bn254-fp12-conjugate (bn254-fp12-mul fu3 fu3p)))
         (t0 (bn254-fp12-square y6))
         (t0 (bn254-fp12-mul (bn254-fp12-mul t0 y4) y5))
         (t1 (bn254-fp12-mul (bn254-fp12-mul y3 y5) t0))
         (t0 (bn254-fp12-mul t0 y2))
         (t1 (bn254-fp12-square t1))
         (t1 (bn254-fp12-mul t1 t0))
         (t1 (bn254-fp12-square t1))
         (t0 (bn254-fp12-mul t1 y1))
         (t1 (bn254-fp12-mul t1 y0))
         (t0 (bn254-fp12-square t0)))
    (bn254-fp12-mul t0 t1)))

(defun bn254-optimal-ate-pairing-check (pairs)
  "Return true when the product of all BN254 pairings equals one."
  (let ((acc (bn254-fp12-one)))
    (dolist (pair pairs)
      (destructuring-bind (g1 g2) pair
        (setf acc (bn254-fp12-mul acc (bn254-miller g2 g1)))))
    (bn254-fp12-one-p (bn254-final-exponentiation acc))))

(defun bn254-g1= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun bn254-g1-negation-p (left right)
  (and (= (car left) (car right))
       (zerop (mod (+ (cdr left) (cdr right))
                   +bn254-field-prime+))))

(defun bn254-g2= (left right)
  (and (bn254-fp2= (first left) (first right))
       (bn254-fp2= (second left) (second right))))

(defun bn254-g2-negation-p (left right)
  (and (bn254-fp2= (first left) (first right))
       (bn254-fp2-negation-p (second left) (second right))))

(defun bn254-pairing-cancel-p (left right)
  (destructuring-bind (left-g1 left-g2) left
    (destructuring-bind (right-g1 right-g2) right
      (or (and (bn254-g2= left-g2 right-g2)
               (bn254-g1-negation-p left-g1 right-g1))
          (and (bn254-g1= left-g1 right-g1)
               (bn254-g2-negation-p left-g2 right-g2))))))

(defun bn254-pairing-cancellation-model-check (pairs)
  "Stopgap BN254 pairing backend covering obvious inverse-pair products.

The real precompile requires an optimal Ate pairing check. This model exists as
an explicit backend boundary so the parsing, gas, and validation shell can be
kept stable while a library-backed pairing implementation is wired in."
  (labels ((remove-one-cancel (remaining)
             (cond
               ((null remaining) nil)
               (t
                (let ((head (first remaining))
                      (tail (rest remaining)))
                  (loop for candidate in tail
                        for index from 0
                        when (bn254-pairing-cancel-p head candidate)
                          do (return
                               (append (subseq tail 0 index)
                                       (subseq tail (1+ index))))
                        finally (return :no-cancel)))))))
    (loop with remaining = pairs
          until (null remaining)
          for next = (remove-one-cancel remaining)
          when (eq next :no-cancel)
            do (return nil)
          do (setf remaining next)
          finally (return t))))

(defvar *bn254-pairing-checker* #'bn254-optimal-ate-pairing-check
  "Callable used for non-zero BN254 pairing products after point validation.")

(defun bn254-pairing-check (pairs)
  (funcall *bn254-pairing-checker* pairs))

(defun true32-byte-vector ()
  (let ((output (make-byte-vector 32)))
    (setf (aref output 31) 1)
    output))

(defun false32-byte-vector ()
  (make-byte-vector 32))

(defun run-bn254-pairing-precompile (input)
  (let ((gas (bn254-pairing-gas input)))
    (cond
      ((not (zerop (mod (length input) 192)))
       (fail-precompile gas "Invalid BN254 pairing input size"))
      ((zerop (length input))
       (values (true32-byte-vector) gas))
      (t
       (let ((pairs
               (loop for offset from 0 below (length input) by 192
                     for g1 = (parse-bn254-g1-point
                               (subseq input offset (+ offset 64))
                               gas)
                     for g2 = (parse-bn254-g2-pairing-point
                               (subseq input (+ offset 64) (+ offset 192))
                               gas)
                     when (and g1 g2)
                       collect (list g1 g2))))
         (values (if (bn254-pairing-check pairs)
                     (true32-byte-vector)
                     (false32-byte-vector))
                 gas))))))

(defun kzg-point-evaluation-return-value ()
  (concat-bytes
   (integer-to-fixed-bytes +bls-field-elements-per-blob+ 32)
   (integer-to-fixed-bytes +bls-field-modulus+ 32)))

(defun run-kzg-point-evaluation-precompile (input)
  (let ((input (ensure-byte-vector input))
        (gas +kzg-point-evaluation-gas+))
    (unless (= (length input) +kzg-point-evaluation-input-size+)
      (fail-precompile gas "Invalid KZG point evaluation input length"))
    (let* ((versioned-hash (subseq input 0 32))
           (z (subseq input 32 64))
           (y (subseq input 64 96))
           (commitment (subseq input 96 144))
           (proof (subseq input 144 192))
           (computed-versioned-hash
             (hash32-bytes (kzg-commitment-to-versioned-hash commitment))))
      (unless (bytes= versioned-hash computed-versioned-hash)
        (fail-precompile gas "Mismatched KZG commitment versioned hash"))
      (handler-case
          (progn
            (verify-kzg-point-proof commitment z y proof)
            (values (kzg-point-evaluation-return-value) gas))
        (error (condition)
          (fail-precompile gas "~A" condition))))))

(defun blake2b-mix (v a b c d x y)
  (setf (aref v a) (u64 (+ (aref v a) (aref v b) x))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 32)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 24)
        (aref v a) (u64 (+ (aref v a) (aref v b) y))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 16)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 63)))

(defun run-blake2f-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (unless (= (length input) +blake2f-input-size+)
      (fail-precompile 0 "BLAKE2F invalid input length"))
    (let ((rounds (load-big-endian-u32 input 0))
          (h (make-array 8))
          (m (make-array 16))
          (v (make-array 16))
          (t0 (load-little-endian-u64 input 196))
          (t1 (load-little-endian-u64 input 204))
          (final-p (= (aref input 212) 1)))
      (unless (member (aref input 212) '(0 1) :test #'=)
        (fail-precompile rounds "BLAKE2F invalid final flag"))
      (dotimes (i 8)
        (setf (aref h i) (load-little-endian-u64 input (+ 4 (* i 8)))
              (aref v i) (aref h i)
              (aref v (+ i 8)) (aref +blake2b-iv+ i)))
      (dotimes (i 16)
        (setf (aref m i) (load-little-endian-u64 input (+ 68 (* i 8)))))
      (setf (aref v 12) (logxor (aref v 12) t0)
            (aref v 13) (logxor (aref v 13) t1))
      (when final-p
        (setf (aref v 14) (logxor (aref v 14) +uint64-mask+)))
      (dotimes (round rounds)
        (let ((s (aref +blake2b-sigma+ (mod round 10))))
          (blake2b-mix v 0 4 8 12
                       (aref m (aref s 0)) (aref m (aref s 1)))
          (blake2b-mix v 1 5 9 13
                       (aref m (aref s 2)) (aref m (aref s 3)))
          (blake2b-mix v 2 6 10 14
                       (aref m (aref s 4)) (aref m (aref s 5)))
          (blake2b-mix v 3 7 11 15
                       (aref m (aref s 6)) (aref m (aref s 7)))
          (blake2b-mix v 0 5 10 15
                       (aref m (aref s 8)) (aref m (aref s 9)))
          (blake2b-mix v 1 6 11 12
                       (aref m (aref s 10)) (aref m (aref s 11)))
          (blake2b-mix v 2 7 8 13
                       (aref m (aref s 12)) (aref m (aref s 13)))
          (blake2b-mix v 3 4 9 14
                       (aref m (aref s 14)) (aref m (aref s 15)))))
      (let ((output (make-byte-vector 64)))
        (dotimes (i 8)
          (store-little-endian-u64
           (logxor (aref h i) (aref v i) (aref v (+ i 8)))
           output
           (* i 8)))
        (values output rounds)))))

(defun all-zero-bytes-p (bytes start end)
  (loop for i from start below end
        always (zerop (aref bytes i))))

(defun run-ecrecover-precompile (input)
  (let* ((padded (padded-data-slice input 0 128))
         (v-byte (aref padded 63))
         (v (- v-byte 27))
         (r (bytes-to-integer (subseq padded 64 96)))
         (s (bytes-to-integer (subseq padded 96 128))))
    (let ((address
            (and (all-zero-bytes-p padded 32 63)
                 (secp256k1-recover-address (subseq padded 0 32) v r s))))
      (if address
          (let ((output (make-byte-vector 32)))
            (replace output (address-bytes address) :start1 12)
            (values output +ecrecover-gas+))
          (values (make-byte-vector 0) +ecrecover-gas+)))))

(defun precompile-word-count (input)
  (ceiling (length (ensure-byte-vector input)) 32))

(defun run-precompile (address input &optional rules)
  (let ((input (ensure-byte-vector input)))
    (case (address-to-word address)
      (1 (if (active-precompile-address-number-p 1 rules)
             (multiple-value-bind (output gas) (run-ecrecover-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (2 (if (active-precompile-address-number-p 2 rules)
             (values (sha256 input)
                     (+ +sha256-base-gas+
                        (* +sha256-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (3 (if (active-precompile-address-number-p 3 rules)
             (let ((output (make-byte-vector 32)))
               (replace output (ripemd160 input) :start1 12)
               (values output
                       (+ +ripemd160-base-gas+
                          (* +ripemd160-word-gas+
                             (precompile-word-count input)))
                       t))
             (values nil 0 nil)))
      (5 (if (active-precompile-address-number-p 5 rules)
             (multiple-value-bind (output gas) (run-modexp-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (6 (if (active-precompile-address-number-p 6 rules)
             (multiple-value-bind (output gas) (run-bn254-add-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (7 (if (active-precompile-address-number-p 7 rules)
             (multiple-value-bind (output gas) (run-bn254-mul-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (8 (if (active-precompile-address-number-p 8 rules)
             (multiple-value-bind (output gas)
                 (run-bn254-pairing-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (9 (if (active-precompile-address-number-p 9 rules)
             (multiple-value-bind (output gas) (run-blake2f-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (10 (if (active-precompile-address-number-p 10 rules)
              (multiple-value-bind (output gas)
                  (run-kzg-point-evaluation-precompile input)
                (values output gas t))
              (values nil 0 nil)))
      (4 (if (active-precompile-address-number-p 4 rules)
             (values (subseq input 0)
                     (+ +identity-base-gas+
                        (* +identity-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (otherwise (values nil 0 nil)))))

(defun execute-bytecode (code &key context gas-limit (max-steps 100000))
  (let ((code (ensure-byte-vector code))
        (pc 0)
        (steps 0)
        (gas-used 0)
        (stack '())
        (memory (make-byte-vector 0))
        (return-data (make-byte-vector 0))
        (return-data-buffer (if context
                                (ensure-byte-vector
                                 (evm-context-return-data context))
                                (make-byte-vector 0)))
        (frame-transient-snapshot (copy-transient-storage context))
        (frame-storage-clears-snapshot (copy-storage-clears context))
        (frame-accessed-storage-snapshot (copy-accessed-storage context))
        (frame-accessed-addresses-snapshot (copy-accessed-addresses context))
        (frame-selfdestructed-snapshot
          (copy-selfdestructed-addresses context))
        (original-storage-values
          (if context
              (evm-context-storage-originals context)
              (make-hash-table :test 'equalp)))
        (cleared-storage-slots
          (if context
              (evm-context-storage-clears context)
              (make-hash-table :test 'equalp)))
        (logs '())
        (refund-counter 0)
        (status :stopped))
    (labels ((binary (fn)
               (multiple-value-bind (a b rest) (pop2 stack)
                 (setf stack (stack-push rest (funcall fn a b)))))
             (comparison (predicate)
               (binary (lambda (a b) (if (funcall predicate a b) 1 0))))
             (charge-extra-gas (amount)
               (incf gas-used amount)
               (when (and gas-limit (> gas-used gas-limit))
                 (fail "EVM out of gas at pc ~D" pc)))
             (charge-memory-gas (offset size)
               (charge-extra-gas
                (memory-expansion-gas memory offset size)))
             (charge-copy-gas (offset size)
               (charge-extra-gas
                (+ (memory-expansion-gas memory offset size)
                   (* +copy-word-gas+ (memory-word-count size))))))
      (loop while (< pc (length code))
            do (let ((op (aref code pc)))
                 (incf steps)
                 (when (> steps max-steps)
                   (fail "EVM exceeded maximum step count ~D" max-steps))
                 (incf gas-used (opcode-base-gas op))
                 (when (and gas-limit (> gas-used gas-limit))
                   (fail "EVM out of gas at pc ~D" pc))
                 (cond
                   ((= op #x00)
                    (setf status :stopped)
                    (return))
                   ((= op #x01) (binary #'+) (incf pc))
                   ((= op #x02) (binary #'*) (incf pc))
                   ((= op #x03) (binary #'-) (incf pc))
                   ((= op #x04)
                    (binary (lambda (a b) (if (zerop b) 0 (floor a b))))
                    (incf pc))
                   ((= op #x05)
                    (binary #'signed-divide-word)
                    (incf pc))
                   ((= op #x06)
                    (binary (lambda (a b) (if (zerop b) 0 (mod a b))))
                    (incf pc))
                   ((= op #x07)
                    (binary #'signed-mod-word)
                    (incf pc))
                   ((= op #x08)
                    (multiple-value-bind (a b modulus rest) (pop3 stack)
                      (setf stack
                            (stack-push
                             rest
                             (if (zerop modulus) 0 (mod (+ a b) modulus)))))
                    (incf pc))
                   ((= op #x09)
                    (multiple-value-bind (a b modulus rest) (pop3 stack)
                      (setf stack
                            (stack-push
                             rest
                             (if (zerop modulus) 0 (mod (* a b) modulus)))))
                    (incf pc))
                   ((= op #x0a)
                    (binary #'modexp-word)
                    (incf pc))
                   ((= op #x0b)
                    (binary #'signextend-word)
                    (incf pc))
                   ((= op #x10) (comparison #'<) (incf pc))
                   ((= op #x11) (comparison #'>) (incf pc))
                   ((= op #x12)
                    (comparison (lambda (a b)
                                  (< (signed-word a) (signed-word b))))
                    (incf pc))
                   ((= op #x13)
                    (comparison (lambda (a b)
                                  (> (signed-word a) (signed-word b))))
                    (incf pc))
                   ((= op #x14) (comparison #'=) (incf pc))
                   ((= op #x15)
                    (multiple-value-bind (a rest) (pop1 stack)
                      (setf stack (stack-push rest (if (zerop a) 1 0))))
                    (incf pc))
                   ((= op #x16) (binary #'logand) (incf pc))
                   ((= op #x17) (binary #'logior) (incf pc))
                   ((= op #x18) (binary #'logxor) (incf pc))
                   ((= op #x19)
                    (multiple-value-bind (a rest) (pop1 stack)
                      (setf stack (stack-push rest (logxor a (1- +word-modulus+)))))
                    (incf pc))
                   ((= op #x1a)
                    (binary #'byte-op)
                    (incf pc))
                   ((= op #x1b)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SHL" pc)
                    (binary (lambda (shift value)
                              (if (>= shift 256) 0 (word (ash value shift)))))
                    (incf pc))
                   ((= op #x1c)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SHR" pc)
                    (binary (lambda (shift value)
                              (if (>= shift 256) 0 (ash value (- shift)))))
                    (incf pc))
                   ((= op #x1d)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SAR" pc)
                    (binary #'arithmetic-shift-right-word)
                    (incf pc))
                   ((= op #x20)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-extra-gas
                       (+ (memory-expansion-gas memory offset size)
                          (* +keccak256-word-gas+
                             (memory-word-count size))))
                      (setf memory (ensure-memory-size memory (+ offset size)))
                      (setf stack
                            (stack-push
                             rest
                             (bytes-to-integer
                              (keccak-256 (memory-slice memory offset size))))))
                    (incf pc))
                   ((= op #x30)
                    (unless context
                      (fail "ADDRESS requires an EVM context"))
                    (setf stack (stack-push stack
                                            (address-to-word
                                             (evm-context-address context))))
                    (incf pc))
                   ((= op #x31)
                    (unless (and context (evm-context-state context))
                      (fail "BALANCE requires an EVM context with state"))
                    (multiple-value-bind (address-word rest) (pop1 stack)
                      (let ((address (word-to-address address-word)))
                        (charge-account-access-gas
                         context
                         address
                         #'charge-extra-gas)
                        (setf stack
                              (stack-push
                               rest
                               (account-balance
                                (evm-context-state context)
                                address)))))
                    (incf pc))
                   ((= op #x32)
                    (unless context
                      (fail "ORIGIN requires an EVM context"))
                    (setf stack (stack-push stack
                                            (address-to-word
                                             (evm-context-origin context))))
                    (incf pc))
                   ((= op #x33)
                    (unless context
                      (fail "CALLER requires an EVM context"))
                    (setf stack (stack-push stack
                                            (address-to-word
                                             (evm-context-caller context))))
                    (incf pc))
                   ((= op #x34)
                    (unless context
                      (fail "CALLVALUE requires an EVM context"))
                    (setf stack (stack-push stack
                                            (word (evm-context-call-value context))))
                    (incf pc))
                   ((= op #x35)
                    (unless context
                      (fail "CALLDATALOAD requires an EVM context"))
                    (multiple-value-bind (offset rest) (pop1 stack)
                      (setf stack
                            (stack-push
                             rest
                             (bytes-to-integer
                              (padded-data-slice
                               (evm-context-input context) offset 32)))))
                    (incf pc))
                   ((= op #x36)
                    (unless context
                      (fail "CALLDATASIZE requires an EVM context"))
                    (setf stack (stack-push stack
                                            (length (ensure-byte-vector
                                                     (evm-context-input context)))))
                    (incf pc))
                   ((= op #x37)
                    (unless context
                      (fail "CALLDATACOPY requires an EVM context"))
                    (multiple-value-bind (memory-offset data-offset rest1)
                        (pop2 stack)
                      (multiple-value-bind (size rest) (pop1 rest1)
                        (charge-copy-gas memory-offset size)
                        (setf memory
                              (copy-into-memory
                               memory
                               memory-offset
                               (padded-data-slice
                                (evm-context-input context) data-offset size))
                              stack rest)))
                    (incf pc))
                   ((= op #x38)
                    (setf stack (stack-push stack (length code)))
                    (incf pc))
                   ((= op #x39)
                    (multiple-value-bind (memory-offset code-offset rest1)
                        (pop2 stack)
                      (multiple-value-bind (size rest) (pop1 rest1)
                        (charge-copy-gas memory-offset size)
                        (setf memory
                              (copy-into-memory
                               memory
                               memory-offset
                               (padded-data-slice code code-offset size))
                              stack rest)))
                    (incf pc))
                   ((= op #x3a)
                    (unless context
                      (fail "GASPRICE requires an EVM context"))
                    (setf stack (stack-push stack
                                            (evm-context-gas-price context)))
                    (incf pc))
                   ((= op #x3b)
                    (unless (and context (evm-context-state context))
                      (fail "EXTCODESIZE requires an EVM context with state"))
                    (multiple-value-bind (address-word rest) (pop1 stack)
                      (let ((address (word-to-address address-word)))
                        (charge-account-access-gas
                         context
                         address
                         #'charge-extra-gas)
                        (setf stack
                              (stack-push
                               rest
                               (length
                                (state-db-get-code
                                 (evm-context-state context)
                                 address))))))
                    (incf pc))
                   ((= op #x3c)
                    (unless (and context (evm-context-state context))
                      (fail "EXTCODECOPY requires an EVM context with state"))
                    (multiple-value-bind (address-word memory-offset rest1)
                        (pop2 stack)
                      (multiple-value-bind (code-offset size rest) (pop2 rest1)
                        (let ((address (word-to-address address-word)))
                          (charge-account-access-gas
                           context
                           address
                           #'charge-extra-gas)
                        (charge-copy-gas memory-offset size)
                        (setf memory
                              (copy-into-memory
                               memory
                               memory-offset
                               (padded-data-slice
                                (state-db-get-code
                                 (evm-context-state context)
                                 address)
                                code-offset
                                size))
                              stack rest))))
                    (incf pc))
                   ((= op #x3d)
                    (unless context
                      (fail "RETURNDATASIZE requires an EVM context"))
                    (require-context-fork context #'chain-rules-byzantium-p
                                          "Byzantium" "RETURNDATASIZE" pc)
                    (setf stack (stack-push stack (length return-data-buffer)))
                    (incf pc))
                   ((= op #x3e)
                    (unless context
                      (fail "RETURNDATACOPY requires an EVM context"))
                    (require-context-fork context #'chain-rules-byzantium-p
                                          "Byzantium" "RETURNDATACOPY" pc)
                    (multiple-value-bind (memory-offset data-offset rest1)
                        (pop2 stack)
                      (multiple-value-bind (size rest) (pop1 rest1)
                        (charge-copy-gas memory-offset size)
                        (setf memory
                              (copy-into-memory
                               memory
                               memory-offset
                               (bounded-data-slice
                                return-data-buffer
                                data-offset
                                size
                                "RETURNDATACOPY"))
                              stack rest)))
                    (incf pc))
                   ((= op #x3f)
                    (unless (and context (evm-context-state context))
                      (fail "EXTCODEHASH requires an EVM context with state"))
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "EXTCODEHASH" pc)
                    (multiple-value-bind (address-word rest) (pop1 stack)
                      (let ((address (word-to-address address-word)))
                        (charge-account-access-gas
                         context
                         address
                         #'charge-extra-gas)
                        (setf stack
                              (stack-push
                               rest
                               (account-code-hash-word
                                (evm-context-state context)
                                address)))))
                    (incf pc))
                   ((= op #x40)
                    (unless context
                      (fail "BLOCKHASH requires an EVM context"))
                    (multiple-value-bind (number rest) (pop1 stack)
                      (setf stack (stack-push rest
                                              (blockhash-word context number))))
                    (incf pc))
                   ((= op #x41)
                    (unless context
                      (fail "COINBASE requires an EVM context"))
                    (setf stack (stack-push stack
                                            (address-to-word
                                             (evm-context-coinbase context))))
                    (incf pc))
                   ((= op #x42)
                    (unless context
                      (fail "TIMESTAMP requires an EVM context"))
                    (setf stack (stack-push stack
                                            (evm-context-timestamp context)))
                    (incf pc))
                   ((= op #x43)
                    (unless context
                      (fail "NUMBER requires an EVM context"))
                    (setf stack (stack-push stack
                                            (evm-context-block-number context)))
                    (incf pc))
                   ((= op #x44)
                    (unless context
                      (fail "DIFFICULTY/PREVRANDAO requires an EVM context"))
                    (setf stack (stack-push stack
                                            (evm-context-difficulty-or-random-word
                                             context)))
                    (incf pc))
                   ((= op #x45)
                    (unless context
                      (fail "GASLIMIT requires an EVM context"))
                    (setf stack (stack-push stack
                                            (evm-context-gas-limit context)))
                    (incf pc))
                   ((= op #x46)
                    (unless context
                      (fail "CHAINID requires an EVM context"))
                    (require-context-fork context #'chain-rules-istanbul-p
                                          "Istanbul" "CHAINID" pc)
                    (setf stack (stack-push stack
                                            (evm-context-chain-id context)))
                    (incf pc))
                   ((= op #x47)
                    (unless (and context (evm-context-state context))
                      (fail "SELFBALANCE requires an EVM context with state"))
                    (require-context-fork context #'chain-rules-istanbul-p
                                          "Istanbul" "SELFBALANCE" pc)
                    (setf stack
                          (stack-push stack
                                      (account-balance
                                       (evm-context-state context)
                                       (evm-context-address context))))
                    (incf pc))
                   ((= op #x48)
                    (unless context
                      (fail "BASEFEE requires an EVM context"))
                    (require-context-fork context #'chain-rules-london-p
                                          "London" "BASEFEE" pc)
                    (setf stack (stack-push stack
                                            (evm-context-base-fee context)))
                    (incf pc))
                   ((= op #x49)
                    (unless context
                      (fail "BLOBHASH requires an EVM context"))
                    (require-context-fork context #'chain-rules-cancun-p
                                          "Cancun" "BLOBHASH" pc)
                    (multiple-value-bind (index rest) (pop1 stack)
                      (setf stack
                            (stack-push rest (blobhash-word context index))))
                    (incf pc))
                   ((= op #x4a)
                    (unless context
                      (fail "BLOBBASEFEE requires an EVM context"))
                    (require-context-fork context #'chain-rules-cancun-p
                                          "Cancun" "BLOBBASEFEE" pc)
                    (setf stack
                          (stack-push stack
                                      (evm-context-blob-base-fee context)))
                    (incf pc))
                   ((= op #x50)
                    (multiple-value-bind (ignored rest) (pop1 stack)
                      (declare (ignore ignored))
                      (setf stack rest))
                    (incf pc))
                   ((= op #x56)
                    (multiple-value-bind (destination rest) (pop1 stack)
                      (unless (valid-jump-destination-p code destination)
                        (fail "Invalid EVM jump destination ~D" destination))
                      (setf stack rest
                            pc destination)))
                   ((= op #x57)
                    (multiple-value-bind (destination condition rest) (pop2 stack)
                      (setf stack rest)
                      (if (zerop condition)
                          (incf pc)
                          (progn
                            (unless (valid-jump-destination-p code destination)
                              (fail "Invalid EVM jump destination ~D" destination))
                            (setf pc destination)))))
                   ((= op #x51)
                    (multiple-value-bind (offset rest) (pop1 stack)
                      (charge-memory-gas offset 32)
                      (setf memory (ensure-memory-size memory (+ offset 32))
                            stack (stack-push rest (mload memory offset))))
                    (incf pc))
                   ((= op #x52)
                    (multiple-value-bind (offset value rest) (pop2 stack)
                      (charge-memory-gas offset 32)
                      (setf memory (mstore memory offset value)
                            stack rest))
                    (incf pc))
                   ((= op #x53)
                    (multiple-value-bind (offset value rest) (pop2 stack)
                      (charge-memory-gas offset 1)
                      (setf memory (mstore8 memory offset value)
                            stack rest))
                    (incf pc))
                   ((= op #x54)
                    (unless (and context (evm-context-state context))
                      (fail "SLOAD requires an EVM context with state"))
                    (multiple-value-bind (slot rest) (pop1 stack)
                      (let* ((slot-hash (word-to-hash32 slot))
                             (value (state-db-get-storage
                                     (evm-context-state context)
                                     (evm-context-address context)
                                     slot-hash)))
                        (charge-storage-read-access-gas
                         context
                         (evm-context-address context)
                         slot-hash
                         #'charge-extra-gas)
                        (setf stack (stack-push rest value))))
                    (incf pc))
                   ((= op #x55)
                    (unless (and context (evm-context-state context))
                      (fail "SSTORE requires an EVM context with state"))
                    (when (evm-context-read-only-p context)
                      (fail "SSTORE is not allowed in read-only EVM context"))
                    (when (and gas-limit
                               (<= (remaining-gas gas-limit gas-used)
                                   +sstore-sentry-gas-eip2200+))
                      (fail "SSTORE requires more than the EIP-2200 sentry gas"))
                    (multiple-value-bind (slot value rest) (pop2 stack)
                      (let* ((slot-hash (word-to-hash32 slot))
                             (refund-key
                               (storage-refund-key
                                (evm-context-address context)
                                slot-hash))
                             (current-value
                               (state-db-get-storage
                                (evm-context-state context)
                                (evm-context-address context)
                                slot-hash)))
                        (unless (nth-value 1
                                  (gethash refund-key
                                           original-storage-values))
                          (setf (gethash refund-key original-storage-values)
                                current-value))
                        (let ((original-value
                                (gethash refund-key original-storage-values)))
                          (charge-extra-gas
                           (sstore-dynamic-gas
                            (storage-cold-access-surcharge
                             context
                             (evm-context-address context)
                             slot-hash)
                            original-value
                            current-value
                            value))
                          (mark-storage-accessed
                           context
                           (evm-context-address context)
                           slot-hash)
                          (when (and (not (zerop original-value))
                                     (not (zerop current-value))
                                     (zerop value))
                          (setf (gethash refund-key cleared-storage-slots) t)
                          (incf refund-counter
                                +sstore-clears-schedule-refund-eip3529+))
                        (when (and (not (zerop original-value))
                                   (zerop current-value)
                                   (not (zerop value))
                                   (gethash refund-key cleared-storage-slots))
                          (remhash refund-key cleared-storage-slots)
                          (decf refund-counter
                                +sstore-clears-schedule-refund-eip3529+))
                        (when (and (/= current-value original-value)
                                   (= value original-value))
                          (incf refund-counter
                                (if (zerop original-value)
                                    +sstore-reset-original-zero-refund-eip3529+
                                    +sstore-reset-original-refund-eip3529+))))
                        (state-db-set-storage
                         (evm-context-state context)
                         (evm-context-address context)
                         slot-hash
                         value)
                        (setf stack rest)))
                    (incf pc))
                   ((= op #x58)
                    (setf stack (stack-push stack pc))
                    (incf pc))
                   ((= op #x59)
                    (setf stack (stack-push stack (length memory)))
                    (incf pc))
                   ((= op #x5a)
                    (setf stack (stack-push stack
                                            (remaining-gas gas-limit gas-used)))
                    (incf pc))
                   ((= op #x5b)
                    (incf pc))
                   ((= op #x5c)
                    (unless context
                      (fail "TLOAD requires an EVM context"))
                    (require-context-fork context #'chain-rules-cancun-p
                                          "Cancun" "TLOAD" pc)
                    (multiple-value-bind (slot rest) (pop1 stack)
                      (setf stack
                            (stack-push
                             rest
                             (transient-storage-get
                              context
                              (evm-context-address context)
                              (word-to-hash32 slot)))))
                    (incf pc))
                   ((= op #x5d)
                    (unless context
                      (fail "TSTORE requires an EVM context"))
                    (require-context-fork context #'chain-rules-cancun-p
                                          "Cancun" "TSTORE" pc)
                    (when (evm-context-read-only-p context)
                      (fail "TSTORE is not allowed in read-only EVM context"))
                    (multiple-value-bind (slot value rest) (pop2 stack)
                      (transient-storage-set
                       context
                       (evm-context-address context)
                       (word-to-hash32 slot)
                       value)
                      (setf stack rest))
                    (incf pc))
                   ((= op #x5e)
                    (require-context-fork context #'chain-rules-cancun-p
                                          "Cancun" "MCOPY" pc)
                    (multiple-value-bind (destination source size rest)
                        (pop3 stack)
                      (charge-extra-gas
                       (+ (memory-expansion-gas
                           memory
                           0
                           (max (+ destination size) (+ source size)))
                          (* +copy-word-gas+ (memory-word-count size))))
                      (setf memory
                            (copy-memory-region memory destination source size)
                            stack rest))
                    (incf pc))
                   ((= op #x5f)
                    (require-context-fork context #'chain-rules-shanghai-p
                                          "Shanghai" "PUSH0" pc)
                    (setf stack (stack-push stack 0))
                    (incf pc))
                   ((<= #x60 op #x7f)
                    (let ((size (- op #x5f)))
                      (setf stack (stack-push stack (read-push-immediate code pc size))
                            pc (+ pc 1 size))))
                   ((<= #x80 op #x8f)
                    (let ((depth (- op #x7f)))
                      (when (< (length stack) depth)
                        (fail "EVM stack underflow on DUP~D" depth))
                      (setf stack (stack-push stack (nth (1- depth) stack))))
                    (incf pc))
                   ((<= #x90 op #x9f)
                    (let ((depth (- op #x8f)))
                      (when (< (length stack) (1+ depth))
                        (fail "EVM stack underflow on SWAP~D" depth))
                      (rotatef (first stack) (nth depth stack)))
                    (incf pc))
                   ((<= #xa0 op #xa4)
                    (unless context
                      (fail "LOG requires an EVM context"))
                    (when (evm-context-read-only-p context)
                      (fail "LOG is not allowed in read-only EVM context"))
                   (let ((topic-count (- op #xa0)))
                      (multiple-value-bind (memory-offset size rest1)
                          (pop2 stack)
                        (charge-extra-gas
                         (+ (memory-expansion-gas memory memory-offset size)
                            (* topic-count +log-topic-gas+)
                            (* size +log-data-gas+)))
                        (setf memory
                              (ensure-memory-size memory
                                                  (+ memory-offset size)))
                        (let ((topics '())
                              (rest rest1))
                          (dotimes (i topic-count)
                            (multiple-value-bind (topic next-rest) (pop1 rest)
                              (push (word-to-hash32 topic) topics)
                              (setf rest next-rest)))
                          (push (make-log-entry
                                 :address (evm-context-address context)
                                 :topics (nreverse topics)
                                 :data (memory-slice memory memory-offset size))
                                logs)
                          (setf stack rest))))
                    (incf pc))
                   ((= op #xf0)
                    (unless (and context (evm-context-state context))
                      (fail "CREATE requires an EVM context with state"))
                   (when (evm-context-read-only-p context)
                     (fail "CREATE is not allowed in read-only EVM context"))
                    (multiple-value-bind (value offset size rest) (pop3 stack)
                      (charge-extra-gas
                       (create-initcode-extra-gas
                        size
                        :rules (evm-context-chain-rules context)))
                      (charge-memory-gas offset size)
                      (setf memory (ensure-memory-size memory (+ offset size)))
                      (let* ((state (evm-context-state context))
                             (creator (evm-context-address context))
                             (creator-account (account-or-empty state creator))
                             (new-address
                               (create-address creator
                                               (state-account-nonce
                                                creator-account)))
                             (initcode (memory-slice memory offset size))
                             (child-return-data (make-byte-vector 0))
                             (child-gas-limit
                               (child-create-gas-limit gas-limit gas-used))
                             (child-started-p nil)
                             (child-gas-used 0)
                             (child-logs '())
                             (success-address 0))
                        (when (< (state-account-balance creator-account) value)
                          (fail "Insufficient balance for CREATE value"))
                        (increment-account-nonce state creator)
                        (mark-account-accessed context new-address)
                        (if (contract-address-collision-p state new-address)
                            (setf child-gas-used (or child-gas-limit 0))
                            (let ((snapshot (state-db-copy state))
                                  (transient-snapshot
                                    (copy-transient-storage context))
                                  (storage-clears-snapshot
                                    (copy-storage-clears context))
                                  (accessed-storage-snapshot
                                    (copy-accessed-storage context))
                                  (accessed-addresses-snapshot
                                    (copy-accessed-addresses context))
                                  (selfdestructed-snapshot
                                    (copy-selfdestructed-addresses context)))
                              (handler-case
                                  (progn
                                    (transfer-call-value state creator new-address value)
                                    (let ((created-account
                                            (account-or-empty state new-address)))
                                      (put-account-values
                                       state
                                       new-address
                                       1
                                       (state-account-balance created-account)
                                       (state-account-code-hash created-account)))
                                    (let* ((child-context
                                             (make-evm-context
                                              :state state
                                              :address new-address
                                              :caller creator
                                              :origin (evm-context-origin context)
                                              :call-value value
                                              :gas-price (evm-context-gas-price context)
                                              :input (make-byte-vector 0)
                                              :coinbase (evm-context-coinbase context)
                                              :timestamp (evm-context-timestamp context)
                                              :block-number (evm-context-block-number context)
                                              :prev-randao (evm-context-prev-randao context)
                                              :difficulty (evm-context-difficulty context)
                                              :random-p (evm-context-random-p context)
                                              :gas-limit (evm-context-gas-limit context)
                                              :chain-id (evm-context-chain-id context)
                                              :chain-rules (evm-context-chain-rules context)
                                              :base-fee (evm-context-base-fee context)
                                              :blob-hashes (evm-context-blob-hashes context)
                                              :blob-base-fee (evm-context-blob-base-fee context)
                                              :transient-storage
                                              (evm-context-transient-storage context)
                                              :storage-originals
                                              (evm-context-storage-originals context)
                                              :storage-clears
                                              (evm-context-storage-clears context)
                                              :selfdestructed-addresses
                                              (evm-context-selfdestructed-addresses
                                               context)
                                              :accessed-storage
                                              (evm-context-accessed-storage context)
                                              :accessed-addresses
                                              (evm-context-accessed-addresses context)
                                              :block-hashes (evm-context-block-hashes context)))
                                           (child-result
                                             (progn
                                               (setf child-started-p t)
                                               (if child-gas-limit
                                                   (execute-bytecode
                                                    initcode
                                                    :context child-context
                                                    :gas-limit child-gas-limit)
                                                   (execute-bytecode
                                                    initcode
                                                    :context child-context)))))
                                      (setf child-gas-used
                                            (evm-result-gas-used child-result))
                                      (setf child-return-data
                                            (evm-result-return-data child-result))
                                      (if (eq (evm-result-status child-result)
                                              :reverted)
	                                          (restore-execution-snapshot
	                                           state snapshot context transient-snapshot
	                                           storage-clears-snapshot
	                                           accessed-storage-snapshot
	                                           accessed-addresses-snapshot
                                             selfdestructed-snapshot)
	                                          (progn
                                            (setf child-logs
                                                  (evm-result-logs child-result))
                                            (when (invalid-created-runtime-code-p
                                                   child-return-data
                                                   (evm-context-chain-rules
                                                    context))
                                              (fail "CREATE produced invalid runtime code"))
                                            (incf child-gas-used
                                                  (created-code-deposit-gas
                                                   child-return-data))
                                            (when (and gas-limit
                                                       (> (+ gas-used
                                                             child-gas-used)
                                                          gas-limit))
                                              (fail "CREATE code deposit out of gas"))
                                            (state-db-set-code state
                                                               new-address
                                                               child-return-data)
                                            (incf refund-counter
                                                  (evm-result-refund-counter
                                                   child-result))
                                            (setf success-address
                                                  (address-to-word
                                                   new-address)
                                                  child-return-data
                                                  (make-byte-vector 0))))))
                                (evm-error ()
                                  (restore-execution-snapshot
                                   state snapshot context transient-snapshot
                                   storage-clears-snapshot
                                   accessed-storage-snapshot
                                   accessed-addresses-snapshot
                                   selfdestructed-snapshot)
                                  (setf success-address 0
                                        child-return-data
                                        (make-byte-vector 0)
                                        child-logs '()
                                        child-gas-used
                                          (if (and child-started-p
                                                   child-gas-limit)
                                              child-gas-limit
                                              child-gas-used))))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              logs (append (reverse child-logs) logs)
                              stack (stack-push rest success-address))))
                    (incf pc))
                   ((= op #xf5)
                    (unless (and context (evm-context-state context))
                      (fail "CREATE2 requires an EVM context with state"))
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "CREATE2" pc)
                    (when (evm-context-read-only-p context)
                      (fail "CREATE2 is not allowed in read-only EVM context"))
                    (multiple-value-bind (value offset size rest1) (pop3 stack)
                      (multiple-value-bind (salt rest) (pop1 rest1)
	                        (charge-extra-gas
	                         (create-initcode-extra-gas
	                          size
	                          :create2-p t
	                          :rules (evm-context-chain-rules context)))
                        (charge-memory-gas offset size)
                        (setf memory (ensure-memory-size memory (+ offset size)))
                        (let* ((state (evm-context-state context))
                               (creator (evm-context-address context))
                               (creator-account (account-or-empty state creator))
                               (initcode (memory-slice memory offset size))
                               (new-address
                                 (create2-address creator salt initcode))
                               (child-return-data (make-byte-vector 0))
                               (child-gas-limit
                                 (child-create-gas-limit gas-limit gas-used))
                               (child-started-p nil)
                               (child-gas-used 0)
                               (child-logs '())
                               (success-address 0))
                          (when (< (state-account-balance creator-account) value)
                            (fail "Insufficient balance for CREATE2 value"))
                          (increment-account-nonce state creator)
                          (mark-account-accessed context new-address)
                          (if (contract-address-collision-p state new-address)
                              (setf child-gas-used (or child-gas-limit 0))
                              (let ((snapshot (state-db-copy state))
                                    (transient-snapshot
                                      (copy-transient-storage context))
                                    (storage-clears-snapshot
                                      (copy-storage-clears context))
                                    (accessed-storage-snapshot
                                      (copy-accessed-storage context))
                                    (accessed-addresses-snapshot
                                      (copy-accessed-addresses context))
                                    (selfdestructed-snapshot
                                      (copy-selfdestructed-addresses context)))
                                (handler-case
                                    (progn
                                      (transfer-call-value state creator new-address value)
                                      (let ((created-account
                                              (account-or-empty state new-address)))
                                        (put-account-values
                                         state
                                         new-address
                                         1
                                         (state-account-balance created-account)
                                         (state-account-code-hash created-account)))
                                      (let* ((child-context
                                               (make-evm-context
                                                :state state
                                                :address new-address
                                                :caller creator
                                                :origin (evm-context-origin context)
                                                :call-value value
                                                :gas-price (evm-context-gas-price context)
                                                :input (make-byte-vector 0)
                                                :coinbase (evm-context-coinbase context)
                                                :timestamp (evm-context-timestamp context)
                                                :block-number (evm-context-block-number context)
                                                :prev-randao (evm-context-prev-randao context)
                                                :difficulty (evm-context-difficulty context)
                                                :random-p (evm-context-random-p context)
                                                :gas-limit (evm-context-gas-limit context)
                                                :chain-id (evm-context-chain-id context)
                                                :chain-rules (evm-context-chain-rules context)
                                                :base-fee (evm-context-base-fee context)
                                                :blob-hashes (evm-context-blob-hashes context)
                                                :blob-base-fee (evm-context-blob-base-fee context)
                                                :transient-storage
                                                (evm-context-transient-storage context)
                                                :storage-originals
                                                (evm-context-storage-originals context)
                                                :storage-clears
                                                (evm-context-storage-clears context)
                                                :selfdestructed-addresses
                                                (evm-context-selfdestructed-addresses
                                                 context)
                                                :accessed-storage
                                                (evm-context-accessed-storage context)
                                                :accessed-addresses
                                                (evm-context-accessed-addresses context)
                                                :block-hashes (evm-context-block-hashes context)))
                                             (child-result
                                               (progn
                                                 (setf child-started-p t)
                                                 (if child-gas-limit
                                                     (execute-bytecode
                                                      initcode
                                                      :context child-context
                                                      :gas-limit child-gas-limit)
                                                     (execute-bytecode
                                                      initcode
                                                      :context child-context)))))
                                        (setf child-gas-used
                                              (evm-result-gas-used child-result))
                                        (setf child-return-data
                                              (evm-result-return-data child-result))
                                        (if (eq (evm-result-status child-result)
                                                :reverted)
	                                            (restore-execution-snapshot
	                                             state snapshot context transient-snapshot
	                                             storage-clears-snapshot
	                                             accessed-storage-snapshot
	                                             accessed-addresses-snapshot
                                               selfdestructed-snapshot)
	                                            (progn
                                              (setf child-logs
                                                    (evm-result-logs child-result))
                                              (when (invalid-created-runtime-code-p
                                                     child-return-data
                                                     (evm-context-chain-rules
                                                      context))
                                                (fail "CREATE2 produced invalid runtime code"))
                                              (incf child-gas-used
                                                    (created-code-deposit-gas
                                                     child-return-data))
                                              (when (and gas-limit
                                                         (> (+ gas-used
                                                               child-gas-used)
                                                            gas-limit))
                                                (fail "CREATE2 code deposit out of gas"))
                                              (state-db-set-code state
                                                                 new-address
                                                                 child-return-data)
                                              (incf refund-counter
                                                    (evm-result-refund-counter
                                                     child-result))
                                              (setf success-address
                                                    (address-to-word new-address)
                                                    child-return-data
                                                    (make-byte-vector 0))))))
                                  (evm-error ()
                                    (restore-execution-snapshot
                                     state snapshot context transient-snapshot
                                     storage-clears-snapshot
                                     accessed-storage-snapshot
                                     accessed-addresses-snapshot
                                     selfdestructed-snapshot)
                                    (setf success-address 0
                                          child-return-data
                                          (make-byte-vector 0)
                                          child-logs '()
                                          child-gas-used
                                          (if (and child-started-p
                                                   child-gas-limit)
                                              child-gas-limit
                                              child-gas-used))))))
                          (charge-extra-gas child-gas-used)
                          (setf return-data-buffer child-return-data
                                logs (append (reverse child-logs) logs)
                                stack (stack-push rest success-address)))))
                    (incf pc))
                   ((= op #xf1)
                    (unless (and context (evm-context-state context))
                      (fail "CALL requires an EVM context with state"))
                    (multiple-value-bind (call-gas address-word value
                                                  args-offset args-size
                                                  return-offset return-size rest)
                        (pop7 stack)
                      (when (and (evm-context-read-only-p context) (plusp value))
                        (fail "CALL with value is not allowed in read-only EVM context"))
                      (charge-extra-gas
                       (memory-regions-expansion-gas
                        memory
                        (list args-offset args-size)
                        (list return-offset return-size)))
                      (setf memory
                            (ensure-memory-regions
                             memory
                             (list args-offset args-size)
                             (list return-offset return-size)))
                      (let* ((state (evm-context-state context))
                             (callee (word-to-address address-word))
                             (snapshot (state-db-copy state))
                             (transient-snapshot
                               (copy-transient-storage context))
                             (storage-clears-snapshot
                               (copy-storage-clears context))
                             (accessed-storage-snapshot
                               (copy-accessed-storage context))
                             (accessed-addresses-snapshot
                               (copy-accessed-addresses context))
                             (selfdestructed-snapshot
                               (copy-selfdestructed-addresses context))
                             (args (memory-slice memory args-offset args-size))
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         callee
                         #'charge-extra-gas)
                        (charge-extra-gas
                         (call-value-extra-gas state callee value
                                               :new-account-p t))
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used
                               :stipend (if (plusp value)
                                            +call-stipend+
                                            0)))
                        (handler-case
                            (progn
                              (when (plusp value)
                                (transfer-call-value
                                 state
                                 (evm-context-address context)
                                 callee
                                 value))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile callee args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state callee)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-evm-context
                                                    :state state
                                                    :address callee
                                                    :caller (evm-context-address context)
                                                    :origin (evm-context-origin context)
                                                    :call-value value
                                                    :gas-price (evm-context-gas-price context)
                                                    :input args
                                                    :coinbase (evm-context-coinbase context)
                                                    :timestamp (evm-context-timestamp context)
                                                    :block-number (evm-context-block-number context)
                                                    :prev-randao (evm-context-prev-randao context)
                                                    :difficulty (evm-context-difficulty context)
                                                    :random-p (evm-context-random-p context)
                                                    :gas-limit (evm-context-gas-limit context)
                                                    :chain-id (evm-context-chain-id context)
                                                    :chain-rules (evm-context-chain-rules context)
                                                    :base-fee (evm-context-base-fee context)
                                                    :blob-hashes (evm-context-blob-hashes context)
                                                    :blob-base-fee (evm-context-blob-base-fee context)
                                                    :transient-storage
                                                    (evm-context-transient-storage context)
                                                    :storage-originals
                                                    (evm-context-storage-originals context)
                                                    :storage-clears
                                                    (evm-context-storage-clears context)
                                                    :selfdestructed-addresses
                                                    (evm-context-selfdestructed-addresses
                                                     context)
                                                    :accessed-storage
                                                    (evm-context-accessed-storage context)
                                                    :accessed-addresses
                                                    (evm-context-accessed-addresses context)
                                                    :block-hashes (evm-context-block-hashes context)
                                                    :read-only-p (evm-context-read-only-p context)))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                   (execute-bytecode callee-code
                                                                     :context child-context
                                                                     :gas-limit child-gas-limit))))
                                            (setf child-gas-used
                                                  (evm-result-gas-used child-result))
                                            (setf child-return-data
                                                  (evm-result-return-data child-result))
                                            (if (eq (evm-result-status child-result) :reverted)
                                                (restore-execution-snapshot
                                                 state snapshot context transient-snapshot
                                                 storage-clears-snapshot
                                                 accessed-storage-snapshot
                                                 accessed-addresses-snapshot
                                                 selfdestructed-snapshot)
                                                (progn
                                                  (incf refund-counter
                                                        (evm-result-refund-counter
                                                         child-result))
                                                  (setf success 1
                                                        child-logs
                                                        (evm-result-logs child-result))))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (min (evm-precompile-error-gas-used condition)
                                       child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used (if child-started-p
                                                     child-gas-limit
                                                     child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-into-memory
                               memory
                               return-offset
                               (padded-data-slice child-return-data 0 return-size))
                              logs (append (reverse child-logs) logs)
                              stack (stack-push rest success))))
                    (incf pc))
                   ((= op #xf3)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-memory-gas offset size)
                      (setf return-data (memory-slice memory offset size)
                            stack rest
                            status :returned)
                      (return)))
                   ((= op #xf2)
                    (unless (and context (evm-context-state context))
                      (fail "CALLCODE requires an EVM context with state"))
                    (multiple-value-bind (call-gas address-word value
                                                  args-offset args-size
                                                  return-offset return-size rest)
                        (pop7 stack)
                      (charge-extra-gas
                       (memory-regions-expansion-gas
                        memory
                        (list args-offset args-size)
                        (list return-offset return-size)))
                      (setf memory
                            (ensure-memory-regions
                             memory
                             (list args-offset args-size)
                             (list return-offset return-size)))
                      (let* ((state (evm-context-state context))
                             (code-address (word-to-address address-word))
                             (snapshot (state-db-copy state))
                             (transient-snapshot
                               (copy-transient-storage context))
                             (storage-clears-snapshot
                               (copy-storage-clears context))
                             (accessed-storage-snapshot
                               (copy-accessed-storage context))
                             (accessed-addresses-snapshot
                               (copy-accessed-addresses context))
                             (selfdestructed-snapshot
                               (copy-selfdestructed-addresses context))
                             (args (memory-slice memory args-offset args-size))
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         code-address
                         #'charge-extra-gas)
                        (charge-extra-gas
                         (call-value-extra-gas state code-address value))
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used
                               :stipend (if (plusp value)
                                            +call-stipend+
                                            0)))
                        (handler-case
                            (progn
                              (when (< (account-balance state
                                                        (evm-context-address context))
                                       value)
                                (fail "Insufficient balance for CALLCODE value"))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile code-address args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state code-address)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-evm-context
                                                    :state state
                                                    :address (evm-context-address context)
                                                    :caller (evm-context-address context)
                                                    :origin (evm-context-origin context)
                                                    :call-value value
                                                    :gas-price (evm-context-gas-price context)
                                                    :input args
                                                    :coinbase (evm-context-coinbase context)
                                                    :timestamp (evm-context-timestamp context)
                                                    :block-number (evm-context-block-number context)
                                                    :prev-randao (evm-context-prev-randao context)
                                                    :difficulty (evm-context-difficulty context)
                                                    :random-p (evm-context-random-p context)
                                                    :gas-limit (evm-context-gas-limit context)
                                                    :chain-id (evm-context-chain-id context)
                                                    :chain-rules (evm-context-chain-rules context)
                                                    :base-fee (evm-context-base-fee context)
                                                    :blob-hashes (evm-context-blob-hashes context)
                                                    :blob-base-fee (evm-context-blob-base-fee context)
                                                    :transient-storage
                                                    (evm-context-transient-storage context)
                                                    :storage-originals
                                                    (evm-context-storage-originals context)
                                                    :storage-clears
                                                    (evm-context-storage-clears context)
                                                    :selfdestructed-addresses
                                                    (evm-context-selfdestructed-addresses
                                                     context)
                                                    :accessed-storage
                                                    (evm-context-accessed-storage context)
                                                    :accessed-addresses
                                                    (evm-context-accessed-addresses context)
                                                    :block-hashes (evm-context-block-hashes context)
                                                    :read-only-p (evm-context-read-only-p context)))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                   (execute-bytecode callee-code
                                                                     :context child-context
                                                                     :gas-limit child-gas-limit))))
                                            (setf child-gas-used
                                                  (evm-result-gas-used child-result))
                                            (setf child-return-data
                                                  (evm-result-return-data child-result))
                                            (if (eq (evm-result-status child-result) :reverted)
                                                (restore-execution-snapshot
                                                 state snapshot context transient-snapshot
                                                 storage-clears-snapshot
                                                 accessed-storage-snapshot
                                                 accessed-addresses-snapshot
                                                 selfdestructed-snapshot)
                                                (progn
                                                  (incf refund-counter
                                                        (evm-result-refund-counter
                                                         child-result))
                                                  (setf success 1
                                                        child-logs
                                                        (evm-result-logs child-result))))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (min (evm-precompile-error-gas-used condition)
                                       child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used (if child-started-p
                                                     child-gas-limit
                                                     child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-into-memory
                               memory
                               return-offset
                               (padded-data-slice child-return-data 0 return-size))
                              logs (append (reverse child-logs) logs)
                              stack (stack-push rest success))))
                    (incf pc))
                   ((= op #xf4)
                    (unless (and context (evm-context-state context))
                      (fail "DELEGATECALL requires an EVM context with state"))
                    (require-context-fork context #'chain-rules-homestead-p
                                          "Homestead" "DELEGATECALL" pc)
                    (multiple-value-bind (call-gas address-word
                                                   args-offset args-size
                                                   return-offset return-size rest)
                        (pop6 stack)
                      (charge-extra-gas
                       (memory-regions-expansion-gas
                        memory
                        (list args-offset args-size)
                        (list return-offset return-size)))
                      (setf memory
                            (ensure-memory-regions
                             memory
                             (list args-offset args-size)
                             (list return-offset return-size)))
                      (let* ((state (evm-context-state context))
                             (code-address (word-to-address address-word))
                             (snapshot (state-db-copy state))
                             (transient-snapshot
                               (copy-transient-storage context))
                             (storage-clears-snapshot
                               (copy-storage-clears context))
                             (accessed-storage-snapshot
                               (copy-accessed-storage context))
                             (accessed-addresses-snapshot
                               (copy-accessed-addresses context))
                             (selfdestructed-snapshot
                               (copy-selfdestructed-addresses context))
                             (args (memory-slice memory args-offset args-size))
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         code-address
                         #'charge-extra-gas)
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used))
                        (handler-case
                            (multiple-value-bind
                                  (precompile-output precompile-gas precompile-p)
                                (run-precompile code-address args
                                                (evm-context-chain-rules context))
                              (if precompile-p
                                  (progn
                                    (setf child-started-p t)
                                    (when (> precompile-gas child-gas-limit)
                                      (fail "Precompile out of gas"))
                                    (setf success 1
                                          child-gas-used precompile-gas
                                          child-return-data precompile-output))
                                  (let ((callee-code
                                          (evm-resolved-code state code-address)))
                                    (if (zerop (length callee-code))
                                        (setf success 1)
                                        (let* ((child-context
                                                 (make-evm-context
                                                  :state state
                                                  :address (evm-context-address context)
                                                  :caller (evm-context-caller context)
                                                  :origin (evm-context-origin context)
                                                  :call-value (evm-context-call-value context)
                                                  :gas-price (evm-context-gas-price context)
                                                  :input args
                                                  :coinbase (evm-context-coinbase context)
                                                  :timestamp (evm-context-timestamp context)
                                                  :block-number (evm-context-block-number context)
                                                  :prev-randao (evm-context-prev-randao context)
                                                  :difficulty (evm-context-difficulty context)
                                                  :random-p (evm-context-random-p context)
                                                  :gas-limit (evm-context-gas-limit context)
                                                  :chain-id (evm-context-chain-id context)
                                                  :chain-rules (evm-context-chain-rules context)
                                                  :base-fee (evm-context-base-fee context)
                                                  :blob-hashes (evm-context-blob-hashes context)
                                                  :blob-base-fee (evm-context-blob-base-fee context)
                                                  :transient-storage
                                                  (evm-context-transient-storage context)
                                                  :storage-originals
                                                  (evm-context-storage-originals context)
                                                  :storage-clears
                                                  (evm-context-storage-clears context)
                                                  :selfdestructed-addresses
                                                  (evm-context-selfdestructed-addresses
                                                   context)
                                                  :accessed-storage
                                                  (evm-context-accessed-storage context)
                                                  :accessed-addresses
                                                  (evm-context-accessed-addresses context)
                                                  :block-hashes (evm-context-block-hashes context)
                                                  :read-only-p (evm-context-read-only-p context)))
                                               (child-result
                                               (progn
                                                 (setf child-started-p t)
                                                 (execute-bytecode callee-code
                                                                   :context child-context
                                                                   :gas-limit child-gas-limit))))
                                          (setf child-gas-used
                                                (evm-result-gas-used child-result))
                                          (setf child-return-data
                                                (evm-result-return-data child-result))
                                          (if (eq (evm-result-status child-result) :reverted)
                                              (restore-execution-snapshot
                                               state snapshot context transient-snapshot
                                               storage-clears-snapshot
                                               accessed-storage-snapshot
                                               accessed-addresses-snapshot
                                               selfdestructed-snapshot)
                                              (progn
                                                (incf refund-counter
                                                      (evm-result-refund-counter
                                                       child-result))
                                                (setf success 1
                                                      child-logs
                                                      (evm-result-logs child-result)))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (min (evm-precompile-error-gas-used condition)
                                       child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used (if child-started-p
                                                     child-gas-limit
                                                     child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-into-memory
                               memory
                               return-offset
                               (padded-data-slice child-return-data 0 return-size))
                              logs (append (reverse child-logs) logs)
                              stack (stack-push rest success))))
                    (incf pc))
                   ((= op #xfa)
                    (unless (and context (evm-context-state context))
                      (fail "STATICCALL requires an EVM context with state"))
                    (require-context-fork context #'chain-rules-byzantium-p
                                          "Byzantium" "STATICCALL" pc)
                    (multiple-value-bind (call-gas address-word
                                                   args-offset args-size
                                                   return-offset return-size rest)
                        (pop6 stack)
                      (charge-extra-gas
                       (memory-regions-expansion-gas
                        memory
                        (list args-offset args-size)
                        (list return-offset return-size)))
                      (setf memory
                            (ensure-memory-regions
                             memory
                             (list args-offset args-size)
                             (list return-offset return-size)))
                      (let* ((state (evm-context-state context))
                             (callee (word-to-address address-word))
                             (snapshot (state-db-copy state))
                             (transient-snapshot
                               (copy-transient-storage context))
                             (storage-clears-snapshot
                               (copy-storage-clears context))
                             (accessed-storage-snapshot
                               (copy-accessed-storage context))
                             (accessed-addresses-snapshot
                               (copy-accessed-addresses context))
                             (selfdestructed-snapshot
                               (copy-selfdestructed-addresses context))
                             (args (memory-slice memory args-offset args-size))
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         callee
                         #'charge-extra-gas)
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used))
                        (handler-case
                            (multiple-value-bind
                                  (precompile-output precompile-gas precompile-p)
                                (run-precompile callee args
                                                (evm-context-chain-rules context))
                              (if precompile-p
                                  (progn
                                    (setf child-started-p t)
                                    (when (> precompile-gas child-gas-limit)
                                      (fail "Precompile out of gas"))
                                    (setf success 1
                                          child-gas-used precompile-gas
                                          child-return-data precompile-output))
                                  (let ((callee-code
                                          (evm-resolved-code state callee)))
                                    (if (zerop (length callee-code))
                                        (setf success 1)
                                        (let* ((child-context
                                                 (make-evm-context
                                                  :state state
                                                  :address callee
                                                  :caller (evm-context-address context)
                                                  :origin (evm-context-origin context)
                                                  :call-value 0
                                                  :gas-price (evm-context-gas-price context)
                                                  :input args
                                                  :coinbase (evm-context-coinbase context)
                                                  :timestamp (evm-context-timestamp context)
                                                  :block-number (evm-context-block-number context)
                                                  :prev-randao (evm-context-prev-randao context)
                                                  :difficulty (evm-context-difficulty context)
                                                  :random-p (evm-context-random-p context)
                                                  :gas-limit (evm-context-gas-limit context)
                                                  :chain-id (evm-context-chain-id context)
                                                  :chain-rules (evm-context-chain-rules context)
                                                  :base-fee (evm-context-base-fee context)
                                                  :blob-hashes (evm-context-blob-hashes context)
                                                  :blob-base-fee (evm-context-blob-base-fee context)
                                                  :transient-storage
                                                  (evm-context-transient-storage context)
                                                  :storage-originals
                                                  (evm-context-storage-originals context)
                                                  :storage-clears
                                                  (evm-context-storage-clears context)
                                                  :selfdestructed-addresses
                                                  (evm-context-selfdestructed-addresses
                                                   context)
                                                  :accessed-storage
                                                  (evm-context-accessed-storage context)
                                                  :accessed-addresses
                                                  (evm-context-accessed-addresses context)
                                                  :block-hashes (evm-context-block-hashes context)
                                                  :read-only-p t))
                                               (child-result
                                               (progn
                                                 (setf child-started-p t)
                                                 (execute-bytecode callee-code
                                                                   :context child-context
                                                                   :gas-limit child-gas-limit))))
                                          (setf child-gas-used
                                                (evm-result-gas-used child-result))
                                          (setf child-return-data
                                                (evm-result-return-data child-result))
                                          (if (eq (evm-result-status child-result) :reverted)
                                              (restore-execution-snapshot
                                               state snapshot context transient-snapshot
                                               storage-clears-snapshot
                                               accessed-storage-snapshot
                                               accessed-addresses-snapshot
                                               selfdestructed-snapshot)
                                              (progn
                                                (incf refund-counter
                                                      (evm-result-refund-counter
                                                       child-result))
                                                (setf success 1))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-gas-used
                                  (min (evm-precompile-error-gas-used condition)
                                       child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state snapshot context transient-snapshot
                             storage-clears-snapshot
                             accessed-storage-snapshot
                             accessed-addresses-snapshot
                             selfdestructed-snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-gas-used (if child-started-p
                                                     child-gas-limit
                                                     child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-into-memory
                               memory
                               return-offset
                               (padded-data-slice child-return-data 0 return-size))
                              stack (stack-push rest success))))
                    (incf pc))
                   ((= op #xff)
                    (unless (and context (evm-context-state context))
                      (fail "SELFDESTRUCT requires an EVM context with state"))
                    (when (evm-context-read-only-p context)
                      (fail "SELFDESTRUCT is not allowed in read-only EVM context"))
                    (multiple-value-bind (beneficiary-word rest) (pop1 stack)
                      (let ((beneficiary (word-to-address beneficiary-word)))
                        (charge-cold-account-access-gas
                         context
                         beneficiary
                         #'charge-extra-gas)
                        (charge-extra-gas
                         (selfdestruct-extra-gas
                          (evm-context-state context)
                          (evm-context-address context)
                          beneficiary))
                        (selfdestruct-account
                         (evm-context-state context)
                         (evm-context-address context)
                         beneficiary)
                        (unless (and (evm-context-chain-rules context)
                                     (chain-rules-cancun-p
                                      (evm-context-chain-rules context)))
                          (mark-selfdestructed-address
                           context
                           (evm-context-address context))))
                      (setf stack rest
                            status :selfdestructed)
                      (return)))
                   ((= op #xfd)
                    (require-context-fork context #'chain-rules-byzantium-p
                                          "Byzantium" "REVERT" pc)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-memory-gas offset size)
                      (restore-transient-storage context
                                                 frame-transient-snapshot)
                      (restore-storage-clears context
                                              frame-storage-clears-snapshot)
                      (restore-accessed-storage context
                                                frame-accessed-storage-snapshot)
                      (restore-accessed-addresses
                       context
                       frame-accessed-addresses-snapshot)
                      (restore-selfdestructed-addresses
                       context
                       frame-selfdestructed-snapshot)
                      (setf return-data (memory-slice memory offset size)
                            stack rest
                            refund-counter 0
                            status :reverted)
                      (return)))
                   (t
                    (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
    (make-evm-result :status status
                     :stack stack
                     :memory memory
                     :return-data return-data
                     :logs (nreverse logs)
                     :pc pc
                     :gas-used gas-used
                     :refund-counter refund-counter)))
