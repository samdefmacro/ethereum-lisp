(in-package #:ethereum-lisp.state)

(defconstant +wei-per-gwei+ 1000000000)
(defconstant +transaction-gas+ 21000)
(defconstant +contract-creation-transaction-gas+ 53000)
(defconstant +initcode-word-gas+ 2)

(defstruct state-object
  account
  (code (make-byte-vector 0) :type byte-vector)
  (storage (make-hash-table :test #'equal)))

(defstruct (state-db (:constructor make-state-db ()))
  (objects (make-hash-table :test #'equal)))

(defun address-key (address)
  (bytes-to-hex (address-bytes address) :prefix nil))

(defun storage-key (slot)
  (bytes-to-hex (hash32-bytes slot) :prefix nil))

(defun ensure-state-uint256 (value label)
  (unless (uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)

(defun state-db-get-object (state address)
  (gethash (address-key address) (state-db-objects state)))

(defun state-db-get-account (state address)
  (let ((object (state-db-get-object state address)))
    (and object (state-object-account object))))

(defun state-db-set-account (state address account)
  (let* ((key (address-key address))
         (object (or (gethash key (state-db-objects state))
                     (setf (gethash key (state-db-objects state))
                           (make-state-object)))))
    (setf (state-object-account object) account)
    state))

(defun state-db-set-code (state address code)
  (let* ((key (address-key address))
         (code (ensure-byte-vector code))
         (object (or (gethash key (state-db-objects state))
                     (setf (gethash key (state-db-objects state))
                           (make-state-object)))))
    (setf (state-object-code object) code)
    (let ((account (or (state-object-account object) (make-state-account))))
      (setf (state-object-account object)
            (make-state-account
             :nonce (state-account-nonce account)
             :balance (state-account-balance account)
             :storage-root (state-account-storage-root account)
             :code-hash (keccak-256-hash code))))
    state))

(defun state-db-get-code (state address)
  (let ((object (state-db-get-object state address)))
    (if object
        (state-object-code object)
        (make-byte-vector 0))))

(defun state-db-get-code-hash (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (state-account-code-hash account)
        +empty-code-hash+)))

(defun copy-state-account (account)
  (and account
       (make-state-account
        :nonce (state-account-nonce account)
        :balance (state-account-balance account)
        :storage-root (state-account-storage-root account)
        :code-hash (state-account-code-hash account))))

(defun copy-hash-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun clone-state-object (object)
  (make-state-object
   :account (copy-state-account (state-object-account object))
   :code (subseq (state-object-code object) 0)
   :storage (copy-hash-table (state-object-storage object))))

(defun state-db-copy (state)
  (let ((copy (make-state-db)))
    (maphash (lambda (address object)
               (setf (gethash address (state-db-objects copy))
                     (clone-state-object object)))
             (state-db-objects state))
    copy))

(defun state-db-restore (state snapshot)
  (clrhash (state-db-objects state))
  (maphash (lambda (address object)
             (setf (gethash address (state-db-objects state))
                   (clone-state-object object)))
           (state-db-objects snapshot))
  state)

(defun state-db-set-storage (state address slot value)
  (let* ((key (address-key address))
         (object (or (gethash key (state-db-objects state))
                     (setf (gethash key (state-db-objects state))
                           (make-state-object
                            :account (make-state-account)))))
         (storage-key (storage-key slot))
         (value (ensure-state-uint256 value "Storage value")))
    (if (zerop value)
        (remhash storage-key (state-object-storage object))
        (setf (gethash storage-key (state-object-storage object)) value))
    state))

(defun state-db-get-storage (state address slot)
  (let ((object (state-db-get-object state address)))
    (if object
        (gethash (storage-key slot) (state-object-storage object) 0)
        0)))

(defun uint256-to-32-byte-hash (value)
  (let ((out (make-byte-vector 32))
        (bytes (integer-to-minimal-bytes (ensure-state-uint256 value "Storage slot"))))
    (replace out bytes :start1 (- 32 (length bytes)))
    (make-hash32 out)))

(defun storage-root (object)
  (let ((trie (make-mpt)))
    (maphash (lambda (slot value)
               (let ((slot-hash (keccak-256 (hash32-bytes (hash32-from-hex slot)))))
                 (mpt-put trie slot-hash (rlp-encode value))))
             (state-object-storage object))
    (make-hash32 (mpt-root-hash trie))))

(defun account-with-storage-root (object)
  (let ((account (or (state-object-account object) (make-state-account))))
    (make-state-account
     :nonce (state-account-nonce account)
     :balance (state-account-balance account)
     :storage-root (storage-root object)
     :code-hash (state-account-code-hash account))))

(defun state-db-root (state)
  (let ((trie (make-mpt)))
    (maphash (lambda (address object)
               (let* ((address-hash (keccak-256 (address-bytes (address-from-hex address))))
                      (account (account-with-storage-root object)))
                 (mpt-put trie address-hash (state-account-rlp account))))
             (state-db-objects state))
    (make-hash32 (mpt-root-hash trie))))

(defun state-db-root-hex (state)
  (hash32-to-hex (state-db-root state)))

(defun apply-genesis-account (state account)
  (let ((address (genesis-account-address account)))
    (state-db-set-account
     state address
     (make-state-account :nonce (genesis-account-nonce account)
                         :balance (genesis-account-balance account)))
    (when (plusp (length (genesis-account-code account)))
      (state-db-set-code state address (genesis-account-code account)))
    (dolist (entry (genesis-account-storage account))
      (state-db-set-storage state address (car entry) (cdr entry)))
    state))

(defun apply-genesis-alloc (state alloc)
  (dolist (account alloc state)
    (apply-genesis-account state account)))

(defun state-db-from-genesis-alloc (alloc)
  (apply-genesis-alloc (make-state-db) alloc))

(defun state-db-from-genesis-json-string (string)
  (state-db-from-genesis-alloc
   (genesis-alloc-from-genesis-json-string string)))

(defun state-db-from-genesis-json-file (path)
  (state-db-from-genesis-alloc
   (genesis-alloc-from-genesis-json-file path)))

(define-condition transaction-validation-error (error)
  ((message :initarg :message :reader transaction-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (transaction-validation-error-message condition)))))

(defun transaction-fail (control &rest args)
  (error 'transaction-validation-error
         :message (apply #'format nil control args)))

(defun state-db-account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun state-db-put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun state-db-transfer-value (state sender recipient value)
  (unless (bytes= (address-bytes sender) (address-bytes recipient))
    (when (plusp value)
      (let ((sender-account (state-db-account-or-empty state sender))
            (recipient-account (state-db-account-or-empty state recipient)))
        (state-db-put-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (state-db-put-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))))

(defun state-db-add-balance (state address amount)
  (let ((account (state-db-account-or-empty state address)))
    (state-db-put-account-values
     state address
     (state-account-nonce account)
     (+ (state-account-balance account) amount)
     (state-account-code-hash account))))

(defun apply-withdrawal (state withdrawal)
  (state-db-add-balance
   state
   (withdrawal-address withdrawal)
   (* (withdrawal-amount withdrawal) +wei-per-gwei+))
  state)

(defun apply-withdrawals (state withdrawals)
  (dolist (withdrawal withdrawals state)
    (apply-withdrawal state withdrawal)))

(defconstant +set-code-authorization-intrinsic-gas+ 25000)

(defun transaction-intrinsic-gas (transaction &key (eip3860-p t))
  (let ((gas (if (transaction-to transaction)
                 +transaction-gas+
                 +contract-creation-transaction-gas+))
        (access-list (transaction-access-list transaction))
        (authorization-list (transaction-authorization-list transaction)))
    (loop for byte across (ensure-byte-vector (transaction-data transaction))
          do (incf gas (if (zerop byte) 4 16)))
    (when (and eip3860-p (not (transaction-to transaction)))
      (incf gas (* +initcode-word-gas+
                   (ceiling (length (ensure-byte-vector
                                     (transaction-data transaction)))
                            32))))
    (incf gas (* 2400 (length access-list)))
    (incf gas (* 1900 (access-list-storage-key-count access-list)))
    (incf gas (* +set-code-authorization-intrinsic-gas+
                 (length authorization-list)))
    gas))

(defun apply-legacy-transaction (state sender transaction)
  "Apply a minimal legacy transfer transaction.

This does not recover signatures, deploy contracts, execute recipient code, or
refund unused gas yet. It is the first deterministic state-transition spine."
  (unless (legacy-transaction-to transaction)
    (transaction-fail "Contract creation transactions are not implemented yet"))
  (let* ((sender-account (state-db-account-or-empty state sender))
         (recipient (legacy-transaction-to transaction))
         (intrinsic-gas (transaction-intrinsic-gas transaction))
         (gas-limit (legacy-transaction-gas-limit transaction))
         (gas-price (legacy-transaction-gas-price transaction))
         (value (legacy-transaction-value transaction))
         (gas-cost (* gas-limit gas-price))
         (total-cost (+ gas-cost value)))
    (unless (= (legacy-transaction-nonce transaction)
               (state-account-nonce sender-account))
      (transaction-fail "Invalid transaction nonce"))
    (when (< gas-limit intrinsic-gas)
      (transaction-fail "Gas limit ~D below intrinsic gas ~D"
                        gas-limit intrinsic-gas))
    (when (< (state-account-balance sender-account) total-cost)
      (transaction-fail "Insufficient sender balance"))
    (state-db-put-account-values
     state sender
     (1+ (state-account-nonce sender-account))
     (- (state-account-balance sender-account) gas-cost)
     (state-account-code-hash sender-account))
    (state-db-transfer-value state sender recipient value)
    (make-receipt :status 1 :cumulative-gas-used gas-limit)))

(defstruct execution-result
  (receipts '() :type list)
  state-root
  transactions-root
  receipts-root)

(defun execute-legacy-transactions (state sender transactions)
  (let ((receipts '())
        (cumulative-gas 0))
    (dolist (transaction transactions)
      (let ((receipt (apply-legacy-transaction state sender transaction)))
        (incf cumulative-gas (receipt-cumulative-gas-used receipt))
        (push (make-receipt :status (receipt-status receipt)
                            :cumulative-gas-used cumulative-gas
                            :logs (receipt-logs receipt))
              receipts)))
    (let ((receipts (nreverse receipts)))
      (make-execution-result
       :receipts receipts
       :state-root (state-db-root state)
       :transactions-root (transaction-list-root transactions)
       :receipts-root (transaction-receipt-list-root transactions receipts)))))
