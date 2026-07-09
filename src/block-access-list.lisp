(in-package #:ethereum-lisp.core)

(defun execution-requests-hash (requests)
  (sha256-hash
   (apply #'concat-bytes
          (loop for request in requests
                for bytes = (validate-execution-request-fields request)
                when (> (length bytes) 1)
                  collect (sha256 bytes)))))

(defstruct (block-access-account (:constructor make-block-access-account
                                      (&key address
                                            (storage-writes '())
                                            (storage-reads '())
                                            (balance-changes '())
                                            (nonce-changes '())
                                            (code-changes '()))))
  address
  (storage-writes '() :type list)
  (storage-reads '() :type list)
  (balance-changes '() :type list)
  (nonce-changes '() :type list)
  (code-changes '() :type list))

(defstruct (block-access-storage-write
            (:constructor make-block-access-storage-write
                (&key tx-index value-after)))
  tx-index
  value-after)

(defstruct (block-access-slot-writes
            (:constructor make-block-access-slot-writes
                (&key slot (accesses '()))))
  slot
  (accesses '() :type list))

(defstruct (block-access-balance-change
            (:constructor make-block-access-balance-change
                (&key tx-index balance)))
  tx-index
  balance)

(defstruct (block-access-nonce-change
            (:constructor make-block-access-nonce-change
                (&key tx-index nonce)))
  tx-index
  nonce)

(defstruct (block-access-code-change
            (:constructor make-block-access-code-change
                (&key tx-index code)))
  tx-index
  code)

(defun hash32-uint256 (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun block-access-storage-write-rlp-object (write)
  (make-rlp-list
   (block-access-storage-write-tx-index write)
   (block-access-storage-write-value-after write)))

(defun block-access-slot-writes-rlp-object (slot-writes)
  (make-rlp-list
   (hash32-uint256 (block-access-slot-writes-slot slot-writes))
   (apply #'make-rlp-list
          (mapcar #'block-access-storage-write-rlp-object
                  (block-access-slot-writes-accesses slot-writes)))))

(defun block-access-balance-change-rlp-object (change)
  (make-rlp-list
   (block-access-balance-change-tx-index change)
   (block-access-balance-change-balance change)))

(defun block-access-nonce-change-rlp-object (change)
  (make-rlp-list
   (block-access-nonce-change-tx-index change)
   (block-access-nonce-change-nonce change)))

(defun block-access-code-change-rlp-object (change)
  (make-rlp-list
   (block-access-code-change-tx-index change)
   (ensure-byte-vector (block-access-code-change-code change))))

(defun block-access-account-rlp-object (account)
  (make-rlp-list
   (address-bytes (block-access-account-address account))
   (mapcar #'block-access-slot-writes-rlp-object
           (block-access-account-storage-writes account))
   (mapcar #'hash32-uint256 (block-access-account-storage-reads account))
   (mapcar #'block-access-balance-change-rlp-object
           (block-access-account-balance-changes account))
   (mapcar #'block-access-nonce-change-rlp-object
           (block-access-account-nonce-changes account))
   (mapcar #'block-access-code-change-rlp-object
           (block-access-account-code-changes account))))

(defun block-access-account-rlp (account)
  (rlp-encode (block-access-account-rlp-object account)))

(defun block-access-list-rlp (block-access-list)
  (rlp-encode
   (apply #'make-rlp-list
          (mapcar #'block-access-account-rlp-object block-access-list))))

(defun require-block-access-rlp-list (value label)
  (unless (rlp-list-p value)
    (block-validation-fail "Block access list ~A must be an RLP list" label))
  (rlp-list-items value))

(defun require-block-access-rlp-list-fields (value count label)
  (let ((items (require-block-access-rlp-list value label)))
    (unless (= (length items) count)
      (block-validation-fail "Block access list ~A must contain ~D fields"
                             label count))
    items))

(defun require-block-access-rlp-bytes (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "Block access list ~A must be RLP bytes" label))
  value)

(defun block-access-address-from-rlp-bytes (value label)
  (let ((bytes (require-block-access-rlp-bytes value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "Block access list ~A must be exactly 20 bytes"
                             label))
    (make-address bytes)))

(defun block-access-rlp-uint (value label)
  (bytes-to-integer (require-block-access-rlp-bytes value label)))

(defun uint256-to-hash32 (value label)
  (unless (uint256-p value)
    (block-validation-fail "Block access list ~A must be uint256" label))
  (let* ((bytes (integer-to-minimal-bytes value))
         (out (make-byte-vector 32)))
    (replace out bytes :start1 (- 32 (length bytes)))
    (make-hash32 out)))

(defun decode-block-access-storage-write-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage write")))
    (make-block-access-storage-write
     :tx-index (block-access-rlp-uint (first items) "storage write tx index")
     :value-after (block-access-rlp-uint (second items)
                                         "storage write value-after"))))

(defun decode-block-access-slot-writes-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage writes entry")))
    (make-block-access-slot-writes
     :slot (uint256-to-hash32
            (block-access-rlp-uint (first items) "storage write slot")
            "storage write slot")
     :accesses
     (mapcar #'decode-block-access-storage-write-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage write accesses")))))

(defun decode-block-access-balance-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "balance change")))
    (make-block-access-balance-change
     :tx-index (block-access-rlp-uint (first items) "balance change tx index")
     :balance (block-access-rlp-uint (second items)
                                     "balance change balance"))))

(defun decode-block-access-nonce-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "nonce change")))
    (make-block-access-nonce-change
     :tx-index (block-access-rlp-uint (first items) "nonce change tx index")
     :nonce (block-access-rlp-uint (second items) "nonce change nonce"))))

(defun decode-block-access-code-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "code change")))
    (make-block-access-code-change
     :tx-index (block-access-rlp-uint (first items) "code change tx index")
     :code (require-block-access-rlp-bytes (second items)
                                           "code change code"))))

(defun decode-block-access-account-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 6 "account")))
    (make-block-access-account
     :address (block-access-address-from-rlp-bytes (first items)
                                                   "account address")
     :storage-writes
     (mapcar #'decode-block-access-slot-writes-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage writes"))
     :storage-reads
     (mapcar (lambda (slot)
               (uint256-to-hash32
                (block-access-rlp-uint slot "storage read")
                "storage read"))
             (require-block-access-rlp-list (third items)
                                            "storage reads"))
     :balance-changes
     (mapcar #'decode-block-access-balance-change-rlp-object
             (require-block-access-rlp-list (fourth items)
                                            "balance changes"))
     :nonce-changes
     (mapcar #'decode-block-access-nonce-change-rlp-object
             (require-block-access-rlp-list (fifth items)
                                            "nonce changes"))
     :code-changes
     (mapcar #'decode-block-access-code-change-rlp-object
             (require-block-access-rlp-list (sixth items)
                                            "code changes")))))

(defun decode-block-access-list-rlp-object (value)
  (mapcar #'decode-block-access-account-rlp-object
          (require-block-access-rlp-list value "root")))

(defun block-access-list-hash (block-access-list)
  (validate-block-access-list-fields block-access-list)
  (keccak-256-hash (block-access-list-rlp block-access-list)))

(defun block-access-list-rlp-input-bytes (bytes)
  (handler-case
      (ensure-byte-vector bytes)
    (error ()
      (block-validation-fail
       "Block access list RLP must be a byte sequence"))))

(defun block-access-list-from-rlp
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (handler-case
        (let ((access-list (decode-block-access-list-rlp-object
                            (rlp-decode-one bytes))))
          (validate-block-access-list-fields access-list
                                             :max-code-size max-code-size
                                             :max-items max-items)
          access-list)
      (block-validation-error (condition)
        (error condition))
      (rlp-error (condition)
        (block-validation-fail "Invalid block access list RLP: ~A" condition)))))

(defun block-access-list-rlp-hash
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (block-access-list-from-rlp bytes
                                :max-code-size max-code-size
                                :max-items max-items)
    (keccak-256-hash bytes)))

(defun validated-block-access-list-commitment
    (block &key max-code-size max-items)
  (let ((access-list (block-block-access-list block))
        (encoded (block-encoded-block-access-list block)))
    (validate-block-access-list-fields access-list
                                       :max-code-size max-code-size
                                       :max-items max-items)
    (if encoded
        (let ((decoded (block-access-list-from-rlp
                        encoded
                        :max-code-size max-code-size
                        :max-items max-items)))
          (unless (bytes= (block-access-list-rlp decoded)
                          (block-access-list-rlp access-list))
            (block-validation-fail
             "Encoded block access list does not match block access list body"))
          (keccak-256-hash encoded))
        (block-access-list-hash access-list))))

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

(defun validate-execution-request-fields (request)
  (let ((bytes (handler-case
                   (ensure-byte-vector request)
                 (error ()
                   (block-validation-fail
                    "Execution request must be a byte vector")))))
    (when (zerop (length bytes))
      (block-validation-fail "Execution request is missing request type"))
    bytes))

(defun validate-execution-request-list-fields (requests)
  (unless (listp requests)
    (block-validation-fail "Execution requests must be a list"))
  (loop with previous-type = nil
        for request in requests
        for bytes = (validate-execution-request-fields request)
        for request-type = (aref bytes 0)
        do (when (< (length bytes) 2)
             (block-validation-fail
              "Execution request must contain request type and payload"))
           (when (and previous-type
                      (<= request-type previous-type))
             (block-validation-fail
              "Execution requests must be ordered by unique request type"))
           (setf previous-type request-type)
        finally (return t)))

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
