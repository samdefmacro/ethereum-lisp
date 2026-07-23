(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-account-key (block-hash address)
  (format nil "~A:~A"
          (engine-payload-store-key block-hash)
          (address-to-hex address)))

(defun engine-payload-store-account-storage-key (block-hash address slot)
  (format nil "~A:~A"
          (engine-payload-store-account-key block-hash address)
          (hash32-to-hex slot)))

(defun engine-payload-store-put-account-balance
    (store block-hash address balance)
  (setf store (chain-store-require-memory-store store))
  (unless (address-p address)
    (block-validation-fail "Engine account balance address must be an address"))
  (unless (uint256-p balance)
    (block-validation-fail "Engine account balance must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account balance block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (memory-chain-store-account-balances store))
          balance
          (gethash (engine-payload-store-key block-hash)
                   (memory-chain-store-state-blocks store))
          :baseline)
    balance))

(defun engine-payload-store-account-balance (store block-hash address)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-resolve-state-value
   store block-hash
   #'chain-state-diff-balances
   (address-to-hex address)
   (memory-chain-store-account-balances store)
   0))

(defun engine-payload-store-put-account-nonce
    (store block-hash address nonce)
  (setf store (chain-store-require-memory-store store))
  (unless (address-p address)
    (block-validation-fail "Engine account nonce address must be an address"))
  (unless (uint64-value-p nonce)
    (block-validation-fail "Engine account nonce must be uint64"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account nonce block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (memory-chain-store-account-nonces store))
          nonce
          (gethash (engine-payload-store-key block-hash)
                   (memory-chain-store-state-blocks store))
          :baseline)
    nonce))

(defun engine-payload-store-account-nonce (store block-hash address)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-resolve-state-value
   store block-hash
   #'chain-state-diff-nonces
   (address-to-hex address)
   (memory-chain-store-account-nonces store)
   0))

(defun engine-payload-store-put-account-code
    (store block-hash address code)
  (setf store (chain-store-require-memory-store store))
  (unless (address-p address)
    (block-validation-fail "Engine account code address must be an address"))
  (let ((block (engine-payload-store-known-block store block-hash))
        (code (ensure-byte-vector code)))
    (unless block
      (block-validation-fail
       "Engine account code block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (memory-chain-store-account-codes store))
          (copy-seq code)
          (gethash (engine-payload-store-key block-hash)
                   (memory-chain-store-state-blocks store))
          :baseline)
    code))

(defun engine-payload-store-account-code (store block-hash address)
  (setf store (chain-store-require-memory-store store))
  (let ((code
          (engine-payload-store-resolve-state-value
           store block-hash
           #'chain-state-diff-codes
           (address-to-hex address)
           (memory-chain-store-account-codes store)
           nil)))
    (if code
        (copy-seq code)
        (make-byte-vector 0))))

(defun engine-payload-store-put-account-storage
    (store block-hash address slot value)
  (setf store (chain-store-require-memory-store store))
  (unless (address-p address)
    (block-validation-fail "Engine account storage address must be an address"))
  (unless (hash32-p slot)
    (block-validation-fail "Engine account storage slot must be a hash32"))
  (unless (uint256-p value)
    (block-validation-fail "Engine account storage value must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account storage block must be known by the memory store"))
    (setf (gethash
           (engine-payload-store-account-storage-key block-hash address slot)
           (memory-chain-store-account-storage store))
          value
          (gethash (engine-payload-store-key block-hash)
                   (memory-chain-store-state-blocks store))
          :baseline)
    value))

(defun engine-payload-store-account-storage (store block-hash address slot)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-resolve-state-value
   store block-hash
   #'chain-state-diff-storage
   (format nil "~A:~A" (address-to-hex address) (hash32-to-hex slot))
   (memory-chain-store-account-storage store)
   0))

(defun chain-store-put-account-balance
    (store block-hash address balance)
  (engine-payload-store-put-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address
   balance))

(defun chain-store-account-balance (store block-hash address)
  (engine-payload-store-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-nonce
    (store block-hash address nonce)
  (engine-payload-store-put-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address
   nonce))

(defun chain-store-account-nonce (store block-hash address)
  (engine-payload-store-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-code
    (store block-hash address code)
  (engine-payload-store-put-account-code
   (chain-store-require-memory-store store)
   block-hash
   address
   code))

(defun chain-store-account-code (store block-hash address)
  (engine-payload-store-account-code
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-storage
    (store block-hash address slot value)
  (engine-payload-store-put-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot
   value))

(defun chain-store-account-storage (store block-hash address slot)
  (engine-payload-store-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot))
