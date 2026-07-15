(in-package #:ethereum-lisp.evm.internal)

(define-condition evm-error (error)
  ((message :initarg :message :reader evm-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (evm-error-message condition)))))

(define-condition evm-step-limit-error (error)
  ((limit :initarg :limit :reader evm-step-limit-error-limit)
   (steps :initarg :steps :reader evm-step-limit-error-steps)
   (pc :initarg :pc :reader evm-step-limit-error-pc))
  (:report
   (lambda (condition stream)
     (format stream
             "EVM exceeded maximum step count ~D at pc ~D (attempted step ~D)"
             (evm-step-limit-error-limit condition)
             (evm-step-limit-error-pc condition)
             (evm-step-limit-error-steps condition)))))

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

(defun active-precompile-address-p (address rules)
  (let ((number (address-to-word address)))
    (and (<= 1 number 10)
         (active-precompile-address-number-p number rules))))

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
(defconstant +precompile-consume-all-child-gas+ (1- +word-modulus+))
(defconstant +stack-limit+ 1024)
(defconstant +max-account-nonce+ (1- (ash 1 64)))
(defconstant +initcode-word-gas+ 2)
(defconstant +keccak256-word-gas+ 6)
(defconstant +exp-byte-gas+ 10)
(defconstant +exp-byte-gas-eip160+ 50)
(defconstant +max-contract-code-size+
  ethereum-lisp.chain-config:+max-contract-code-size+)
(defconstant +max-initcode-size+ 49152)
(defconstant +amsterdam-max-contract-code-size+
  ethereum-lisp.chain-config:+amsterdam-max-contract-code-size+)
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
(defconstant +modexp-eip198-quad-divisor+ 20)
(defconstant +modexp-eip2565-min-gas+ 200)
(defconstant +modexp-eip2565-quad-divisor+ 3)
(defconstant +modexp-eip2565-exp-byte-multiplier+ 8)
(defconstant +modexp-eip7883-min-gas+ 500)
(defconstant +modexp-eip7883-exp-byte-multiplier+ 16)
(defconstant +modexp-eip7883-large-length-multiplier+ 2)
(defconstant +modexp-osaka-max-input-length+ 1024)
(defconstant +bn254-field-prime+
  21888242871839275222246405745257275088696311157297823662689037894645226208583)
(defconstant +bn254-curve-order+
  21888242871839275222246405745257275088548364400416034343698204186575808495617)
(defconstant +bn254-add-gas-eip196+ 500)
(defconstant +bn254-mul-gas-eip196+ 40000)
(defconstant +bn254-pairing-base-gas-eip197+ 100000)
(defconstant +bn254-pairing-per-point-gas-eip197+ 80000)
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
