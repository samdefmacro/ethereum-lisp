(in-package #:ethereum-lisp.core)

(defun engine-payload-store-state-available-p
    (store hash)
  (not (null
        (gethash (engine-payload-store-key hash)
                 (engine-payload-memory-store-state-blocks store)))))

(defun chain-store-state-available-p (store hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun engine-payload-store-remove-prefixed-keys (table prefix)
  (let ((keys '()))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (when (engine-payload-store-string-prefix-p prefix key)
         (push key keys)))
     table)
    (dolist (key keys)
      (remhash key table))
    (length keys)))

(defun engine-payload-store-prune-state-snapshot (store block-key)
  (let ((prefix (format nil "~A:" block-key)))
    (remhash block-key (engine-payload-memory-store-state-blocks store))
    (+ (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-balances store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-nonces store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-codes store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-storage store)
        prefix))))

(defun chain-store-prune-state-before (store block-number)
  (let ((store (chain-store-require-memory-store store)))
    (unless (and (integerp block-number) (not (minusp block-number)))
      (block-validation-fail
       "Chain state pruning block number must be a non-negative integer"))
    (let ((block-keys '())
          (head-block-key
            (let ((checkpoint
                    (engine-payload-memory-store-head-checkpoint store)))
              (let ((hash (and checkpoint
                               (chain-store-checkpoint-block-hash
                                checkpoint))))
                (if hash
                    (engine-payload-store-key hash)
                    (gethash
                     (engine-payload-memory-store-head-number store)
                     (engine-payload-memory-store-canonical-hashes
                      store)))))))
      (maphash
       (lambda (block-key state-available-p)
         (when state-available-p
           (let ((block (gethash block-key
                                  (engine-payload-memory-store-blocks store))))
             (when (and block
                        (or (null head-block-key)
                            (not (string= block-key head-block-key)))
                        (< (block-header-number (block-header block))
                           block-number))
               (push block-key block-keys)))))
       (engine-payload-memory-store-state-blocks store))
      (dolist (block-key block-keys)
        (engine-payload-store-prune-state-snapshot store block-key))
      (length block-keys))))

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
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account balance address must be an address"))
  (unless (uint256-p balance)
    (block-validation-fail "Engine account balance must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account balance block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-balances store))
          balance
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    balance))

(defun engine-payload-store-account-balance (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-balances store)
           0))

(defun engine-payload-store-put-account-nonce
    (store block-hash address nonce)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account nonce address must be an address"))
  (unless (uint64-value-p nonce)
    (block-validation-fail "Engine account nonce must be uint64"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account nonce block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-nonces store))
          nonce
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    nonce))

(defun engine-payload-store-account-nonce (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-nonces store)
           0))

(defun engine-payload-store-put-account-code
    (store block-hash address code)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account code address must be an address"))
  (let ((block (engine-payload-store-known-block store block-hash))
        (code (ensure-byte-vector code)))
    (unless block
      (block-validation-fail
       "Engine account code block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))
          (copy-seq code)
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    code))

(defun engine-payload-store-account-code (store block-hash address)
  (let ((code
          (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))))
    (if code
        (copy-seq code)
        (make-byte-vector 0))))

(defun engine-payload-store-put-account-storage
    (store block-hash address slot value)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
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
           (engine-payload-memory-store-account-storage store))
          value
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    value))

(defun engine-payload-store-account-storage (store block-hash address slot)
  (gethash (engine-payload-store-account-storage-key block-hash address slot)
           (engine-payload-memory-store-account-storage store)
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

(defun engine-payload-store-remember-account-key
    (accounts block-prefix key &key storage-key-p)
  (when (engine-payload-store-string-prefix-p block-prefix key)
    (let* ((rest (subseq key (length block-prefix)))
           (address-hex
             (if storage-key-p
                 (let ((slot-separator (position #\: rest)))
                   (and slot-separator
                        (subseq rest 0 slot-separator)))
                 rest)))
      (when address-hex
        (setf (gethash address-hex accounts) t)))))

(defun engine-payload-store-sorted-hash-keys (table)
  (let (keys)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sort keys #'string<)))

(defun engine-payload-store-account-storage-entries
    (memory-store block-hash address)
  (let ((account-prefix
          (format nil "~A:"
                  (engine-payload-store-account-key block-hash address)))
        (entries '()))
    (dolist (key (engine-payload-store-sorted-hash-keys
                  (engine-payload-memory-store-account-storage memory-store)))
      (when (engine-payload-store-string-prefix-p account-prefix key)
        (push (cons (hash32-from-hex
                     (subseq key (length account-prefix)))
                    (gethash
                     key
                     (engine-payload-memory-store-account-storage memory-store)))
              entries)))
    (nreverse entries)))

(defun chain-store-for-each-account (store block-hash function)
  (let ((memory-store (chain-store-require-memory-store store)))
    (when (chain-store-state-available-p store block-hash)
      (let ((block-prefix
              (format nil "~A:" (engine-payload-store-key block-hash)))
            (accounts (make-hash-table :test #'equal)))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-balances memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-nonces memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-codes memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key :storage-key-p t))
         (engine-payload-memory-store-account-storage memory-store))
        (dolist (address-hex (engine-payload-store-sorted-hash-keys accounts))
           (let* ((address (address-from-hex address-hex))
                  (account-key
                    (engine-payload-store-account-key block-hash address)))
             (funcall
              function
              address
              (gethash account-key
                       (engine-payload-memory-store-account-balances
                        memory-store)
                       0)
              (gethash account-key
                       (engine-payload-memory-store-account-nonces
                        memory-store)
                       0)
              (engine-payload-store-account-code
               memory-store block-hash address)
              (engine-payload-store-account-storage-entries
               memory-store block-hash address))))
        store))))
