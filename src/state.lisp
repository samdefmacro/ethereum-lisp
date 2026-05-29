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

(defstruct (state-storage-proof
            (:constructor make-state-storage-proof
                (&key slot value proof)))
  slot
  value
  proof)

(defstruct (state-proof-result
            (:constructor make-state-proof-result
                (&key address balance nonce code-hash storage-root
                 account-proof storage-proofs)))
  address
  balance
  nonce
  code-hash
  storage-root
  account-proof
  (storage-proofs '() :type list))

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
    (and object
         (state-object-account object)
         (account-with-storage-root object))))

(defun empty-state-account-p (account)
  (and account
       (zerop (state-account-nonce account))
       (zerop (state-account-balance account))
       (bytes= (hash32-bytes (state-account-storage-root account))
               (hash32-bytes +empty-trie-hash+))
       (bytes= (hash32-bytes (state-account-code-hash account))
               (hash32-bytes +empty-code-hash+))))

(defun empty-state-object-p (object)
  (and object
       (empty-state-account-p (state-object-account object))
       (zerop (length (state-object-code object)))
       (zerop (hash-table-count (state-object-storage object)))))

(defun prune-empty-state-object (state key object)
  (when (empty-state-object-p object)
    (remhash key (state-db-objects state)))
  state)

(defun state-db-set-account (state address account)
  (let* ((key (address-key address))
         (object (or (gethash key (state-db-objects state))
                     (setf (gethash key (state-db-objects state))
                           (make-state-object)))))
    (setf (state-object-account object) account)
    state))

(defun state-db-clear-account (state address)
  (remhash (address-key address) (state-db-objects state))
  state)

(defun state-db-set-code (state address code)
  (let* ((key (address-key address))
         (code (ensure-byte-vector code))
         (object (or (gethash key (state-db-objects state))
                     (and (plusp (length code))
                          (setf (gethash key (state-db-objects state))
                                (make-state-object))))))
    (when object
      (setf (state-object-code object) code)
      (let ((account (or (state-object-account object) (make-state-account))))
        (setf (state-object-account object)
              (make-state-account
               :nonce (state-account-nonce account)
               :balance (state-account-balance account)
               :storage-root (state-account-storage-root account)
               :code-hash (keccak-256-hash code))))
      (prune-empty-state-object state key object))
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
         (value (ensure-state-uint256 value "Storage value"))
         (object (or (gethash key (state-db-objects state))
                     (and (not (zerop value))
                          (setf (gethash key (state-db-objects state))
                                (make-state-object
                                 :account (make-state-account))))))
         (storage-key (storage-key slot))
         (storage (and object (state-object-storage object))))
    (cond
      ((zerop value)
       (when object
         (remhash storage-key storage)
         (prune-empty-state-object state key object)))
      (t
       (setf (gethash storage-key storage) value)))
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

(defun state-db-storage-proof-key (slot)
  (keccak-256 (hash32-bytes slot)))

(defun state-object-storage-trie (object)
  (let ((trie (make-mpt)))
    (when object
      (maphash (lambda (slot value)
                 (mpt-put trie
                          (state-db-storage-proof-key (hash32-from-hex slot))
                          (rlp-encode value)))
               (state-object-storage object)))
    trie))

(defun storage-root (object)
  (make-hash32 (mpt-root-hash (state-object-storage-trie object))))

(defun state-db-get-storage-root (state address)
  (storage-root (state-db-get-object state address)))

(defun state-db-get-storage-proof (state address slot)
  (mpt-get-proof (state-object-storage-trie (state-db-get-object state address))
                 (state-db-storage-proof-key slot)))

(defun state-db-verify-storage-proof (storage-root slot proof)
  (mpt-verify-proof storage-root (state-db-storage-proof-key slot) proof))

(defun rlp-uint256-value (value label)
  (unless (typep value 'byte-vector)
    (error "~A must be an RLP byte string" label))
  (let ((integer (bytes-to-integer value)))
    (ensure-state-uint256 integer label)))

(defun decode-state-account-rlp (bytes)
  (let ((decoded (rlp-decode-one bytes)))
    (unless (typep decoded 'rlp-list)
      (error "State account proof value must decode to an RLP list"))
    (let ((items (rlp-list-items decoded)))
      (unless (= 4 (length items))
        (error "State account proof value must contain four fields, got ~D"
               (length items)))
      (destructuring-bind (nonce balance storage-root code-hash) items
        (make-state-account
         :nonce (rlp-uint256-value nonce "Account nonce")
         :balance (rlp-uint256-value balance "Account balance")
         :storage-root (make-hash32 storage-root)
         :code-hash (make-hash32 code-hash))))))

(defun decode-storage-value-rlp (bytes)
  (rlp-uint256-value (rlp-decode-one bytes) "Storage proof value"))

(defun copy-state-proof-nodes (proof)
  (mapcar (lambda (node)
            (copy-seq (ensure-byte-vector node)))
          proof))

(defun copy-state-proof-address (address)
  (make-address (copy-seq (address-bytes address))))

(defun copy-state-proof-hash32 (hash)
  (make-hash32 (copy-seq (hash32-bytes hash))))

(defun account-proof-result-account (result)
  (make-state-account
   :nonce (state-proof-result-nonce result)
   :balance (state-proof-result-balance result)
   :storage-root (state-proof-result-storage-root result)
   :code-hash (state-proof-result-code-hash result)))

(defun state-storage-proof-for-slot (state address slot)
  (make-state-storage-proof
   :slot (copy-state-proof-hash32 slot)
   :value (state-db-get-storage state address slot)
   :proof (copy-state-proof-nodes
           (state-db-get-storage-proof state address slot))))

(defun state-db-get-proof (state address slots)
  (let ((account (or (state-db-get-account state address)
                     (make-state-account))))
    (make-state-proof-result
     :address (copy-state-proof-address address)
     :nonce (state-account-nonce account)
     :balance (state-account-balance account)
     :storage-root (copy-state-proof-hash32
                    (state-account-storage-root account))
     :code-hash (copy-state-proof-hash32
                 (state-account-code-hash account))
     :account-proof (copy-state-proof-nodes
                     (state-db-get-account-proof state address))
     :storage-proofs
     (mapcar (lambda (slot)
               (state-storage-proof-for-slot state address slot))
             slots))))

(defun ensure-state-account-equal (expected actual)
  (unless (and (= (state-account-nonce expected) (state-account-nonce actual))
               (= (state-account-balance expected) (state-account-balance actual))
               (bytes= (hash32-bytes (state-account-storage-root expected))
                       (hash32-bytes (state-account-storage-root actual)))
               (bytes= (hash32-bytes (state-account-code-hash expected))
                       (hash32-bytes (state-account-code-hash actual))))
    (error "State proof account fields do not match account proof value"))
  t)

(defun state-db-verify-proof (state-root proof)
  (unless (typep proof 'state-proof-result)
    (error "State proof must be a state-proof-result"))
  (multiple-value-bind (account-rlp present-p)
      (state-db-verify-account-proof
       state-root
       (state-proof-result-address proof)
       (state-proof-result-account-proof proof))
    (let ((expected-account (account-proof-result-account proof)))
      (if present-p
          (ensure-state-account-equal expected-account
                                      (decode-state-account-rlp account-rlp))
          (ensure-state-account-equal expected-account
                                      (make-state-account)))))
  (dolist (storage-proof (state-proof-result-storage-proofs proof) t)
    (unless (typep storage-proof 'state-storage-proof)
      (error "Storage proof entry must be a state-storage-proof"))
    (multiple-value-bind (value-rlp present-p)
        (state-db-verify-storage-proof
         (state-proof-result-storage-root proof)
         (state-storage-proof-slot storage-proof)
         (state-storage-proof-proof storage-proof))
      (let ((expected-value (state-storage-proof-value storage-proof)))
        (unless (if present-p
                    (= expected-value (decode-storage-value-rlp value-rlp))
                    (zerop expected-value))
          (error "State proof storage value does not match storage proof"))))))

(defun state-proof-node-hex-list (proof)
  (mapcar #'bytes-to-hex proof))

(defun state-storage-proof-rpc-object (proof)
  (unless (typep proof 'state-storage-proof)
    (error "Storage proof entry must be a state-storage-proof"))
  (list (cons "key" (hash32-to-hex (state-storage-proof-slot proof)))
        (cons "value" (quantity-to-hex (state-storage-proof-value proof)))
        (cons "proof" (state-proof-node-hex-list
                       (state-storage-proof-proof proof)))))

(defun state-proof-result-rpc-object (proof)
  (unless (typep proof 'state-proof-result)
    (error "State proof must be a state-proof-result"))
  (list (cons "address" (address-to-hex (state-proof-result-address proof)))
        (cons "accountProof"
              (state-proof-node-hex-list
               (state-proof-result-account-proof proof)))
        (cons "balance" (quantity-to-hex (state-proof-result-balance proof)))
        (cons "codeHash" (hash32-to-hex (state-proof-result-code-hash proof)))
        (cons "nonce" (quantity-to-hex (state-proof-result-nonce proof)))
        (cons "storageHash"
              (hash32-to-hex (state-proof-result-storage-root proof)))
        (cons "storageProof"
              (mapcar #'state-storage-proof-rpc-object
                      (state-proof-result-storage-proofs proof)))))

(defun state-proof-rpc-required-field (object field label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((entry (assoc field object :test #'string=)))
    (unless entry
      (error "~A is missing ~A" label field))
    (cdr entry)))

(defun state-proof-rpc-string-field (object field label)
  (let ((value (state-proof-rpc-required-field object field label)))
    (unless (stringp value)
      (error "~A.~A must be a string" label field))
    value))

(defun state-proof-rpc-node-list (object field label)
  (let ((nodes (state-proof-rpc-required-field object field label)))
    (unless (listp nodes)
      (error "~A.~A must be a list" label field))
    (mapcar (lambda (node)
              (unless (stringp node)
                (error "~A.~A entries must be hex strings" label field))
              (hex-to-bytes node))
            nodes)))

(defun state-proof-rpc-storage-key (value)
  (unless (stringp value)
    (error "Storage proof key must be a string"))
  (let ((bytes (hex-to-bytes value)))
    (when (> (length bytes) 32)
      (error "Storage proof key is wider than 32 bytes"))
    (let ((padded (make-byte-vector 32)))
      (replace padded bytes :start1 (- 32 (length bytes)))
      (make-hash32 padded))))

(defun state-storage-proof-from-rpc-object (object)
  (make-state-storage-proof
   :slot (state-proof-rpc-storage-key
          (state-proof-rpc-string-field object "key" "Storage proof"))
   :value (hex-to-quantity
           (state-proof-rpc-string-field object "value" "Storage proof"))
   :proof (state-proof-rpc-node-list object "proof" "Storage proof")))

(defun state-proof-result-from-rpc-object (object)
  (make-state-proof-result
   :address (address-from-hex
             (state-proof-rpc-string-field object "address" "State proof"))
   :nonce (hex-to-quantity
           (state-proof-rpc-string-field object "nonce" "State proof"))
   :balance (hex-to-quantity
             (state-proof-rpc-string-field object "balance" "State proof"))
   :code-hash (hash32-from-hex
               (state-proof-rpc-string-field object "codeHash" "State proof"))
   :storage-root
   (hash32-from-hex
    (state-proof-rpc-string-field object "storageHash" "State proof"))
   :account-proof (state-proof-rpc-node-list
                   object "accountProof" "State proof")
   :storage-proofs
   (let ((storage-proofs
           (state-proof-rpc-required-field
            object "storageProof" "State proof")))
     (unless (listp storage-proofs)
       (error "State proof.storageProof must be a list"))
     (mapcar #'state-storage-proof-from-rpc-object storage-proofs))))

(defun account-with-storage-root (object)
  (let ((account (or (state-object-account object) (make-state-account))))
    (make-state-account
     :nonce (state-account-nonce account)
     :balance (state-account-balance account)
     :storage-root (storage-root object)
     :code-hash (state-account-code-hash account))))

(defun state-db-state-trie (state)
  (let ((trie (make-mpt)))
    (maphash (lambda (address object)
               (let* ((address-hash (keccak-256 (address-bytes (address-from-hex address))))
                      (account (account-with-storage-root object)))
                 (mpt-put trie address-hash (state-account-rlp account))))
             (state-db-objects state))
    trie))

(defun state-db-account-proof-key (address)
  (keccak-256 (address-bytes address)))

(defun state-db-get-account-proof (state address)
  (mpt-get-proof (state-db-state-trie state)
                 (state-db-account-proof-key address)))

(defun state-db-verify-account-proof (state-root address proof)
  (mpt-verify-proof state-root (state-db-account-proof-key address) proof))

(defun state-db-root (state)
  (make-hash32 (mpt-root-hash (state-db-state-trie state))))

(defun state-db-root-hex (state)
  (hash32-to-hex (state-db-root state)))

(defun state-db-for-each-account (state function)
  (maphash
   (lambda (address-key object)
     (let ((address (address-from-hex address-key))
           (account (account-with-storage-root object))
           (code (copy-seq (state-object-code object)))
           (storage-entries '()))
       (maphash (lambda (slot value)
                  (push (cons (hash32-from-hex slot) value)
                        storage-entries))
                (state-object-storage object))
       (funcall function address account code (nreverse storage-entries))))
   (state-db-objects state))
  state)

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

(defun genesis-state-root-from-genesis-alloc (alloc)
  (state-db-root (state-db-from-genesis-alloc alloc)))

(defun genesis-state-root-from-genesis-json-string (string)
  (genesis-state-root-from-genesis-alloc
   (genesis-alloc-from-genesis-json-string string)))

(defun genesis-state-root-from-genesis-json-file (path)
  (genesis-state-root-from-genesis-alloc
   (genesis-alloc-from-genesis-json-file path)))

(defun validate-genesis-state-root (computed-root expected-root)
  (unless (hash32-p computed-root)
    (error 'block-validation-error
           :message "Computed genesis state root must be a hash32"))
  (unless (hash32-p expected-root)
    (error 'block-validation-error
           :message "Expected genesis state root must be a hash32"))
  (unless (bytes= (hash32-bytes computed-root) (hash32-bytes expected-root))
    (error 'block-validation-error :message "Genesis state root mismatch"))
  t)

(defun validate-genesis-json-state-root (string)
  (let* ((genesis-object (parse-json string))
         (expected-root
           (genesis-expected-state-root-from-genesis-object genesis-object)))
    (unless expected-root
      (error 'block-validation-error :message "Genesis stateRoot is missing"))
    (validate-genesis-state-root
     (genesis-state-root-from-genesis-alloc
      (genesis-alloc-from-genesis-object genesis-object))
     expected-root)))

(defun genesis-header-from-state-genesis-object (object &key config)
  (let* ((computed-root
           (genesis-state-root-from-genesis-alloc
            (genesis-alloc-from-genesis-object object)))
         (expected-root
           (genesis-expected-state-root-from-genesis-object object)))
    (when expected-root
      (validate-genesis-state-root computed-root expected-root))
    (genesis-header-from-genesis-object object
                                        :state-root computed-root
                                        :config config)))

(defun genesis-header-from-state-genesis-json-string (string &key config)
  (genesis-header-from-state-genesis-object (parse-json string) :config config))

(defun genesis-header-from-state-genesis-json-file (path &key config)
  (genesis-header-from-state-genesis-json-string
   (with-open-file (stream path :direction :input)
     (let ((string (make-string (file-length stream))))
       (read-sequence string stream)
       string))
   :config config))

(defun genesis-block-from-state-genesis-object (object &key config)
  (genesis-block-from-genesis-header
   (genesis-header-from-state-genesis-object object :config config)))

(defun genesis-block-from-state-genesis-json-string (string &key config)
  (genesis-block-from-state-genesis-object (parse-json string) :config config))

(defun genesis-block-from-state-genesis-json-file (path &key config)
  (genesis-block-from-state-genesis-json-string
   (with-open-file (stream path :direction :input)
     (let ((string (make-string (file-length stream))))
       (read-sequence string stream)
       string))
   :config config))

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
