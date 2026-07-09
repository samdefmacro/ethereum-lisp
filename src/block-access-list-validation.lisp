(in-package #:ethereum-lisp.core)

(defun validate-byte-sequence-field (value label &key size)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail "~A must be a byte sequence"
                                          label)))))
    (when (and size (/= size (length bytes)))
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun validate-optional-hash32-field (value label)
  (when (and value (not (hash32-p value)))
    (block-validation-fail "~A must be a hash32" label))
  t)

(defun validate-optional-address-field (value label)
  (when (and value (not (address-p value)))
    (block-validation-fail "~A must be an address" label))
  t)

(defun validate-optional-uint256-field (value label)
  (when (and value (not (uint256-p value)))
    (block-validation-fail "~A must be uint256" label))
  t)

(defun validate-optional-uint64-field (value label)
  (when (and value
             (not (and (integerp value)
                       (<= 0 value)
                       (< value (expt 2 64)))))
    (block-validation-fail "~A must be uint64" label))
  t)

(defun byte-vector-lexicographic< (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (loop for index below (min (length left) (length right))
          for left-byte = (aref left index)
          for right-byte = (aref right index)
          when (< left-byte right-byte)
            do (return t)
          when (> left-byte right-byte)
            do (return nil)
          finally (return (< (length left) (length right))))))

(defun uint32-value-p (value)
  (and (integerp value)
       (<= 0 value)
       (< value (expt 2 32))))

(defun validate-block-access-storage-write-fields (write)
  (unless (block-access-storage-write-p write)
    (block-validation-fail
     "Block access list storage write must be a storage write"))
  (unless (uint32-value-p (block-access-storage-write-tx-index write))
    (block-validation-fail "Block access list storage write tx index must be uint32"))
  (unless (uint256-p (block-access-storage-write-value-after write))
    (block-validation-fail
     "Block access list storage write value-after must be uint256"))
  t)

(defun validate-block-access-slot-writes-fields (slot-writes)
  (unless (block-access-slot-writes-p slot-writes)
    (block-validation-fail
     "Block access list storage writes entry must be slot writes"))
  (unless (hash32-p (block-access-slot-writes-slot slot-writes))
    (block-validation-fail "Block access list storage write slot must be a hash32"))
  (unless (listp (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write accesses must be a list"))
  (when (null (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write slot must contain at least one access"))
  (let ((previous-tx-index nil))
    (dolist (write (block-access-slot-writes-accesses slot-writes))
      (validate-block-access-storage-write-fields write)
      (let ((tx-index (block-access-storage-write-tx-index write)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list storage write tx indices must be sorted"))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-balance-change-fields (change)
  (unless (block-access-balance-change-p change)
    (block-validation-fail
     "Block access list balance change must be a balance change"))
  (unless (uint32-value-p (block-access-balance-change-tx-index change))
    (block-validation-fail
     "Block access list balance change tx index must be uint32"))
  (unless (uint256-p (block-access-balance-change-balance change))
    (block-validation-fail
     "Block access list balance change balance must be uint256"))
  t)

(defun validate-block-access-nonce-change-fields (change)
  (unless (block-access-nonce-change-p change)
    (block-validation-fail
     "Block access list nonce change must be a nonce change"))
  (unless (uint32-value-p (block-access-nonce-change-tx-index change))
    (block-validation-fail
     "Block access list nonce change tx index must be uint32"))
  (unless (uint64-value-p (block-access-nonce-change-nonce change))
    (block-validation-fail
     "Block access list nonce change nonce must be uint64"))
  t)

(defun validate-block-access-code-change-fields (change &key max-code-size)
  (unless (block-access-code-change-p change)
    (block-validation-fail
     "Block access list code change must be a code change"))
  (unless (uint32-value-p (block-access-code-change-tx-index change))
    (block-validation-fail
     "Block access list code change tx index must be uint32"))
  (let ((code (validate-byte-sequence-field
               (block-access-code-change-code change)
               "Block access list code change code")))
    (when (and max-code-size
               (> (length code) max-code-size))
      (block-validation-fail
       "Block access list code change exceeds maximum code size")))
  t)

(defun validate-block-access-indexed-change-list
    (changes validate-change tx-index-fn label)
  (unless (listp changes)
    (block-validation-fail "Block access list ~A must be a list" label))
  (let ((previous-tx-index nil))
    (dolist (change changes)
      (funcall validate-change change)
      (let ((tx-index (funcall tx-index-fn change)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list ~A tx indices must be sorted" label))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-account-fields (account &key max-code-size)
  (unless (block-access-account-p account)
    (block-validation-fail
     "Block access list account must be a block access account"))
  (unless (address-p (block-access-account-address account))
    (block-validation-fail "Block access list account address must be an address"))
  (unless (listp (block-access-account-storage-writes account))
    (block-validation-fail "Block access list storage writes must be a list"))
  (unless (listp (block-access-account-storage-reads account))
    (block-validation-fail "Block access list storage reads must be a list"))
  (validate-block-access-indexed-change-list
   (block-access-account-balance-changes account)
   #'validate-block-access-balance-change-fields
   #'block-access-balance-change-tx-index
   "balance changes")
  (validate-block-access-indexed-change-list
   (block-access-account-nonce-changes account)
   #'validate-block-access-nonce-change-fields
   #'block-access-nonce-change-tx-index
   "nonce changes")
  (validate-block-access-indexed-change-list
   (block-access-account-code-changes account)
   (lambda (change)
     (validate-block-access-code-change-fields
      change
      :max-code-size max-code-size))
   #'block-access-code-change-tx-index
   "code changes")
  (let ((previous-slot-bytes nil)
        (write-slot-table (make-hash-table :test #'equal)))
    (dolist (slot-writes (block-access-account-storage-writes account))
      (validate-block-access-slot-writes-fields slot-writes)
      (let* ((slot (block-access-slot-writes-slot slot-writes))
             (slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage write slots must be sorted"))
        (setf (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
              t)
        (setf previous-slot-bytes slot-bytes)))
    (setf previous-slot-bytes nil)
    (dolist (slot (block-access-account-storage-reads account))
      (unless (hash32-p slot)
        (block-validation-fail "Block access list storage read must be a hash32"))
      (let ((slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage reads must be sorted"))
        (when (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
          (block-validation-fail
           "Block access list storage read duplicates a storage write slot"))
        (setf previous-slot-bytes slot-bytes))))
  t)

(defun block-access-list-item-count (block-access-list)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (loop for account in block-access-list
        do (unless (block-access-account-p account)
             (block-validation-fail
              "Block access list account must be a block access account"))
        sum (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account)))))

(defun validate-block-access-list-fields
    (block-access-list &key max-code-size max-items)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (let ((previous-address-bytes nil)
        (item-count 0))
    (dolist (account block-access-list)
      (validate-block-access-account-fields account
                                            :max-code-size max-code-size)
      (incf item-count
            (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account))))
      (let ((address-bytes (address-bytes
                            (block-access-account-address account))))
        (when (and previous-address-bytes
                   (not (byte-vector-lexicographic< previous-address-bytes
                                                    address-bytes)))
          (block-validation-fail
           "Block access list account addresses must be sorted"))
        (setf previous-address-bytes address-bytes)))
    (when (and max-items
               (> item-count max-items))
      (block-validation-fail
       "Block access list item count exceeds gas limit")))
  t)
