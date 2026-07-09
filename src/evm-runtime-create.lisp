(in-package #:ethereum-lisp.evm)

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
