(in-package #:ethereum-lisp.test)

(defparameter +state-root-fixture-path+
  "tests/fixtures/execution-spec-tests/state-roots.json")

(defparameter +state-proof-fixture-path+
  "tests/fixtures/execution-spec-tests/state-proofs.json")

(defparameter +state-root-fixture-format+
  "ethereum-lisp/state-root-fixture-v1")

(defparameter +state-proof-fixture-format+
  "ethereum-lisp/state-proof-fixture-v1")

(defparameter +state-root-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +state-proof-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +state-root-fixture-case-fields+
  '("name"
    "tags"
    "operations"
    "expectedRoot"
    "expectedStorageRoots"
    "expectedAccounts"))

(defparameter +state-proof-fixture-case-fields+
  '("name"
    "tags"
    "operations"
    "request"
    "expectedRoot"
    "expectedProof"))

(defparameter +state-proof-fixture-request-fields+
  '("address" "storageKeys"))

(defparameter +state-proof-fixture-proof-fields+
  '("address"
    "accountProof"
    "balance"
    "codeHash"
    "nonce"
    "storageHash"
    "storageProof"))

(defparameter +state-proof-fixture-storage-proof-fields+
  '("key" "value" "proof"))

(defparameter +state-root-fixture-operation-fields+
  '("op" "address" "nonce" "balance" "slot" "value" "code"))

(defparameter +state-root-fixture-storage-root-fields+
  '("address" "root"))

(defparameter +state-root-fixture-account-fields+
  '("address" "nonce" "balance" "storageRoot" "codeHash" "rlp"))

(defparameter +state-root-fixture-known-tags+
  '("empty-state-root"
    "account-root"
    "storage-root"
    "storage-delete"
    "storage-prune"
    "storage-root-projection"
    "code-root"
    "code-delete"
    "code-prune"
    "code-update"
    "multi-account"
    "account-projection"
    "account-update"
    "account-prune"
    "storage-update"))

(defparameter +state-root-fixture-required-case-names+
  '("empty-state-root"
    "single-account-nonce-balance-root"
    "account-update-overwrites-nonce-balance-root"
    "account-clear-prunes-to-empty-root"
    "account-clear-prunes-code-and-storage-root"
    "account-clear-preserves-sibling-account-root"
    "single-account-storage-root"
    "storage-update-overwrites-slot-root"
    "storage-created-account-prunes-to-empty-root"
    "storage-delete-keeps-funded-account-root"
    "single-code-account-root"
    "code-update-overwrites-code-hash-root"
    "code-created-account-prunes-to-empty-root"
    "code-delete-keeps-funded-account-root"
    "multi-account-secure-state-root"))

(defparameter +state-root-fixture-required-tags+
  '("empty-state-root"
    "account-root"
    "storage-root"
    "storage-delete"
    "storage-prune"
    "storage-root-projection"
    "code-root"
    "code-delete"
    "code-prune"
    "code-update"
    "multi-account"
    "account-projection"
    "account-update"
    "account-prune"
    "storage-update"))

(defparameter +state-proof-fixture-known-tags+
  '("present-account"
    "missing-account"
    "storage-present"
    "storage-missing"
    "storage-deleted-missing"
    "multi-storage-present"
    "geth-shaped-result"))

(defparameter +state-proof-fixture-required-tags+
  '("present-account"
    "missing-account"
    "storage-present"
    "storage-missing"
    "storage-deleted-missing"
    "multi-storage-present"
    "geth-shaped-result"))

(defun validate-state-root-fixture-object-fields
    (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-state-root-fixture-metadata (fixture)
  (validate-state-root-fixture-object-fields
   fixture
   +state-root-fixture-top-level-fields+
   "State root fixture")
  (validate-fixture-format fixture +state-root-fixture-format+)
  (when (blank-string-p (fixture-required-field fixture "source"))
    (error "State root fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture))

(defun state-fixture-number (object name &optional (default 0))
  (let ((value (fixture-object-field object name)))
    (if value value default)))

(defun validate-state-root-fixture-non-negative-integer
    (operation name &key required-p)
  (let ((present-p (fixture-field-present-p operation name))
        (value (fixture-object-field operation name)))
    (when (or present-p required-p)
      (unless (and (integerp value) (not (minusp value)))
        (error "State root fixture operation ~A must contain non-negative integer ~A"
               (fixture-object-field operation "op")
               name)))))

(defun validate-state-root-fixture-operation-absent-fields
    (operation fields)
  (dolist (field fields)
    (when (fixture-field-present-p operation field)
      (error "State root fixture operation ~A must not contain ~A"
             (fixture-object-field operation "op")
             field))))

(defun validate-state-root-fixture-address (operation)
  (address-from-hex (fixture-required-field operation "address")))

(defun validate-state-root-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (when (blank-string-p name)
      (error "State root fixture case name must be present"))
    (let ((previous (gethash name seen-names)))
      (when previous
        (error "Duplicate state root fixture case name: ~A" name)))
    (setf (gethash name seen-names) t)))

(defun validate-state-root-fixture-case-tags (case seen-tags)
  (let ((name (fixture-object-field case "name"))
        (tags (fixture-object-field case "tags")))
    (unless (and (listp tags) tags)
      (error "State root fixture case ~A must include non-empty tags" name))
    (let ((case-tags (make-hash-table :test 'equal)))
      (dolist (tag tags)
        (when (gethash tag case-tags)
          (error "State root fixture case ~A has duplicate tag ~A" name tag))
        (setf (gethash tag case-tags) t)
        (unless (and (stringp tag)
                     (member tag +state-root-fixture-known-tags+
                             :test #'string=))
          (error "State root fixture case ~A has unknown tag ~A" name tag))
        (setf (gethash tag seen-tags) t)))))

(defun validate-state-root-fixture-operation-shape (operation)
  (unless (listp operation)
    (error "State root fixture operation must be a JSON object"))
  (validate-state-root-fixture-object-fields
   operation
   +state-root-fixture-operation-fields+
   "State root fixture operation")
  (let ((op (fixture-required-field operation "op")))
    (validate-state-root-fixture-address operation)
    (cond
      ((string= op "setAccount")
       (validate-state-root-fixture-non-negative-integer operation "nonce")
       (validate-state-root-fixture-non-negative-integer operation "balance"))
      ((string= op "setStorage")
       (hash32-from-hex (fixture-required-field operation "slot"))
       (validate-state-root-fixture-non-negative-integer
        operation "value" :required-p t))
      ((string= op "setCode")
       (hex-to-bytes (fixture-required-field operation "code")))
      ((string= op "clearAccount")
       (validate-state-root-fixture-operation-absent-fields
        operation
        '("nonce" "balance" "slot" "value" "code")))
      (t
       (error "Unknown state root fixture operation: ~A" op)))))

(defun validate-state-root-fixture-storage-root-shape (expected)
  (unless (listp expected)
    (error "State root fixture expectedStorageRoots entry must be a JSON object"))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-storage-root-fields+
   "State root fixture expectedStorageRoots entry")
  (address-from-hex (fixture-required-field expected "address"))
  (hash32-from-hex (fixture-required-field expected "root")))

(defun validate-state-root-fixture-account-shape (expected)
  (unless (listp expected)
    (error "State root fixture expectedAccounts entry must be a JSON object"))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-account-fields+
   "State root fixture expectedAccounts entry")
  (address-from-hex (fixture-required-field expected "address"))
  (validate-state-root-fixture-non-negative-integer expected "nonce")
  (validate-state-root-fixture-non-negative-integer expected "balance")
  (when (fixture-field-present-p expected "storageRoot")
    (hash32-from-hex (fixture-required-field expected "storageRoot")))
  (when (fixture-field-present-p expected "codeHash")
    (hash32-from-hex (fixture-required-field expected "codeHash")))
  (when (fixture-field-present-p expected "rlp")
    (hex-to-bytes (fixture-required-field expected "rlp"))))

(defun validate-state-root-fixture-case-shape (case)
  (unless (listp case)
    (error "State root fixture case must be a JSON object"))
  (validate-state-root-fixture-object-fields
   case
   +state-root-fixture-case-fields+
   "State root fixture case")
  (when (blank-string-p (fixture-required-field case "name"))
    (error "State root fixture case name must be present"))
  (validate-state-root-fixture-case-tags case (make-hash-table :test 'equal))
  (let ((operations (fixture-required-field case "operations")))
    (unless (listp operations)
      (error "State root fixture case operations must be a JSON array"))
    (dolist (operation operations)
      (validate-state-root-fixture-operation-shape operation)))
  (hash32-from-hex (fixture-required-field case "expectedRoot"))
  (when (fixture-field-present-p case "expectedStorageRoots")
    (let ((expected-storage-roots
            (fixture-object-field case "expectedStorageRoots"))
          (seen-addresses (make-hash-table :test 'equal)))
      (unless (listp expected-storage-roots)
        (error "State root fixture case expectedStorageRoots must be a JSON array"))
      (dolist (expected expected-storage-roots)
        (validate-state-root-fixture-storage-root-shape expected)
        (let ((address (fixture-required-field expected "address")))
          (when (gethash address seen-addresses)
            (error "State root fixture case has duplicate expectedStorageRoots address ~A"
                   address))
          (setf (gethash address seen-addresses) t)))))
  (when (fixture-field-present-p case "expectedAccounts")
    (let ((expected-accounts
            (fixture-object-field case "expectedAccounts"))
          (seen-addresses (make-hash-table :test 'equal)))
      (unless (listp expected-accounts)
        (error "State root fixture case expectedAccounts must be a JSON array"))
      (dolist (expected expected-accounts)
        (validate-state-root-fixture-account-shape expected)
        (let ((address (fixture-required-field expected "address")))
          (when (gethash address seen-addresses)
            (error "State root fixture case has duplicate expectedAccounts address ~A"
                   address))
          (setf (gethash address seen-addresses) t))))))

(defun validate-state-root-fixture-cases (cases)
  (unless (listp cases)
    (error "State root fixture cases must be a JSON array"))
  (let ((seen-names (make-hash-table :test 'equal))
        (seen-tags (make-hash-table :test 'equal)))
    (dolist (case cases)
      (validate-state-root-fixture-case-name case seen-names)
      (validate-state-root-fixture-case-tags case seen-tags)
      (validate-state-root-fixture-case-shape case))
    (dolist (tag +state-root-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "State root fixture is missing required coverage tag ~A"
               tag)))))

(defun validate-state-root-fixture-required-case-names (cases)
  (let ((case-by-name (make-hash-table :test 'equal))
        (seen-required-names (make-hash-table :test 'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name +state-root-fixture-required-case-names+)
      (when (gethash name seen-required-names)
        (error "State root fixture required case list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name case-by-name)
        (error "State root fixture is missing required seed case ~A"
               name)))))

(defun apply-state-root-fixture-operation (state operation)
  (let* ((op (fixture-object-field operation "op"))
         (address (address-from-hex (fixture-object-field operation "address"))))
    (cond
      ((string= op "setAccount")
       (state-db-set-account
        state address
        (make-state-account
         :nonce (state-fixture-number operation "nonce")
         :balance (state-fixture-number operation "balance"))))
      ((string= op "setStorage")
       (state-db-set-storage
        state address
        (hash32-from-hex (fixture-object-field operation "slot"))
        (state-fixture-number operation "value")))
      ((string= op "setCode")
       (state-db-set-code
        state address
        (hex-to-bytes (fixture-object-field operation "code"))))
      ((string= op "clearAccount")
       (state-db-clear-account state address))
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  state)

(defun run-state-root-fixture-case (case)
  (let ((state (make-state-db)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation state operation))
    state))

(defstruct (state-root-fixture-account-state
            (:constructor make-state-root-fixture-account-state
                (&key (nonce 0) (balance 0)
                      (code (make-byte-vector 0))
                      (storage (make-hash-table :test 'equal))
                      (touched-slots (make-hash-table :test 'equal)))))
  (nonce 0 :type (integer 0 *))
  (balance 0 :type (integer 0 *))
  (code (make-byte-vector 0) :type byte-vector)
  storage
  touched-slots)

(defun state-root-fixture-empty-account-state-p (account-state)
  (and (zerop (state-root-fixture-account-state-nonce account-state))
       (zerop (state-root-fixture-account-state-balance account-state))
       (zerop (length (state-root-fixture-account-state-code account-state)))
       (zerop
        (hash-table-count
         (state-root-fixture-account-state-storage account-state)))))

(defun state-root-fixture-account-state
    (states address &key create-p)
  (or (gethash address states)
      (when create-p
        (setf (gethash address states)
              (make-state-root-fixture-account-state)))))

(defun state-root-fixture-prune-account-state
    (states address account-state)
  (when (state-root-fixture-empty-account-state-p account-state)
    (remhash address states))
  states)

(defun apply-state-root-fixture-operation-model (states operation)
  (let* ((op (fixture-object-field operation "op"))
         (address (fixture-object-field operation "address"))
         (account-state nil))
    (cond
      ((string= op "setAccount")
       (setf account-state
             (state-root-fixture-account-state states address :create-p t)
             (state-root-fixture-account-state-nonce account-state)
             (state-fixture-number operation "nonce")
             (state-root-fixture-account-state-balance account-state)
             (state-fixture-number operation "balance")))
      ((string= op "setStorage")
       (let* ((slot (fixture-object-field operation "slot"))
              (value (state-fixture-number operation "value"))
              (create-p (not (zerop value))))
         (setf account-state
               (state-root-fixture-account-state
                states address :create-p create-p))
         (when account-state
           (setf (gethash slot
                          (state-root-fixture-account-state-touched-slots
                           account-state))
                 t)
           (if (zerop value)
               (remhash slot
                        (state-root-fixture-account-state-storage
                         account-state))
               (setf (gethash slot
                              (state-root-fixture-account-state-storage
                               account-state))
                     value))
           (state-root-fixture-prune-account-state
            states address account-state))))
      ((string= op "setCode")
       (let* ((code (hex-to-bytes (fixture-object-field operation "code")))
              (create-p (plusp (length code))))
         (setf account-state
               (state-root-fixture-account-state
                states address :create-p create-p))
         (when account-state
           (setf (state-root-fixture-account-state-code account-state)
                 code)
          (state-root-fixture-prune-account-state
           states address account-state))))
      ((string= op "clearAccount")
       (remhash address states))
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  states)

(defun state-root-fixture-final-operation-state (case)
  (let ((states (make-hash-table :test 'equal)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation-model states operation))
    states))

(defun assert-state-root-fixture-final-operation-state (state case)
  (let ((expected-states
          (state-root-fixture-final-operation-state case)))
    (dolist (operation (fixture-object-field case "operations"))
      (let* ((address-hex (fixture-object-field operation "address"))
             (address (address-from-hex address-hex))
             (expected (gethash address-hex expected-states))
             (account (state-db-get-account state address)))
        (if expected
            (progn
              (is account)
              (is (= (state-root-fixture-account-state-nonce expected)
                     (state-account-nonce account)))
              (is (= (state-root-fixture-account-state-balance expected)
                     (state-account-balance account)))
              (is (bytes=
                   (state-root-fixture-account-state-code expected)
                   (state-db-get-code state address)))
              (maphash
               (lambda (slot ignored)
                 (declare (ignore ignored))
                 (is (= (gethash
                         slot
                         (state-root-fixture-account-state-storage expected)
                         0)
                        (state-db-get-storage
                         state address (hash32-from-hex slot)))))
               (state-root-fixture-account-state-touched-slots expected)))
            (progn
              (is (null account))
              (is (string= "0x"
                           (bytes-to-hex
                            (state-db-get-code state address))))
              (when (string= "setStorage"
                              (fixture-object-field operation "op"))
                (is (zerop
                     (state-db-get-storage
                      state
                       address
                       (hash32-from-hex
                       (fixture-object-field operation "slot"))))))))))))

(defun assert-state-root-fixture-storage-roots (state case)
  (dolist (expected (fixture-object-field case "expectedStorageRoots"))
    (let ((address (address-from-hex (fixture-object-field expected "address"))))
      (is (string= (fixture-object-field expected "root")
                   (hash32-to-hex
                    (state-db-get-storage-root state address)))))))

(defun assert-state-root-fixture-accounts (state case)
  (dolist (expected (fixture-object-field case "expectedAccounts"))
    (let* ((address (address-from-hex (fixture-object-field expected "address")))
           (account (state-db-get-account state address)))
      (is account)
      (let ((nonce (fixture-object-field expected "nonce")))
        (when nonce
          (is (= nonce (state-account-nonce account)))))
      (let ((balance (fixture-object-field expected "balance")))
        (when balance
          (is (= balance (state-account-balance account)))))
      (let ((storage-root (fixture-object-field expected "storageRoot")))
        (when storage-root
          (is (string= storage-root
                       (hash32-to-hex
                        (state-account-storage-root account))))))
      (let ((code-hash (fixture-object-field expected "codeHash")))
        (when code-hash
          (is (string= code-hash
                       (hash32-to-hex
                        (state-account-code-hash account))))))
      (let ((rlp (fixture-object-field expected "rlp")))
        (when rlp
          (is (string= rlp
                       (bytes-to-hex (state-account-rlp account)))))))))

(defun validate-state-proof-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +state-proof-fixture-top-level-fields+
   "State proof fixture")
  (validate-fixture-format fixture +state-proof-fixture-format+)
  (when (blank-string-p (fixture-required-field fixture "source"))
    (error "State proof fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture))

(defun validate-state-proof-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (when (blank-string-p name)
      (error "State proof fixture case name must be present"))
    (when (gethash name seen-names)
      (error "Duplicate state proof fixture case name: ~A" name))
    (setf (gethash name seen-names) t)))

(defun validate-state-proof-fixture-case-tags (case seen-tags)
  (let ((name (fixture-object-field case "name"))
        (tags (fixture-object-field case "tags")))
    (unless (and (listp tags) tags)
      (error "State proof fixture case ~A must include non-empty tags" name))
    (let ((case-tags (make-hash-table :test 'equal)))
      (dolist (tag tags)
        (when (gethash tag case-tags)
          (error "State proof fixture case ~A has duplicate tag ~A" name tag))
        (setf (gethash tag case-tags) t)
        (unless (and (stringp tag)
                     (member tag +state-proof-fixture-known-tags+
                             :test #'string=))
          (error "State proof fixture case ~A has unknown tag ~A" name tag))
        (setf (gethash tag seen-tags) t)))))

(defun validate-state-proof-fixture-hex-list (values label)
  (unless (listp values)
    (error "~A must be a JSON array" label))
  (dolist (value values)
    (unless (stringp value)
      (error "~A entries must be hex strings" label))
    (hex-to-bytes value)))

(defun validate-state-proof-fixture-proof-node-list (values label)
  (validate-state-proof-fixture-hex-list values label)
  (dolist (value values)
    (rlp-decode-one (hex-to-bytes value))))

(defun validate-state-proof-fixture-storage-key-uniqueness (storage-keys)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (key storage-keys)
      (let ((normalized (bytes-to-hex
                         (hash32-bytes (hash32-from-hex key))
                         :prefix nil)))
        (when (gethash normalized seen)
          (error "State proof fixture request has duplicate storage key ~A"
                 key))
        (setf (gethash normalized seen) t)))))

(defun validate-state-proof-fixture-request-shape (request)
  (validate-fixture-object-fields
   request
   +state-proof-fixture-request-fields+
   "State proof fixture request")
  (address-from-hex (fixture-required-field request "address"))
  (let ((storage-keys (fixture-required-field request "storageKeys")))
    (validate-state-proof-fixture-hex-list
     storage-keys
     "State proof fixture request storageKeys")
    (dolist (key storage-keys)
      (hash32-from-hex key))
    (validate-state-proof-fixture-storage-key-uniqueness storage-keys)))

(defun state-proof-fixture-empty-storage-root-p (storage-hash)
  (bytes= (hash32-bytes storage-hash)
          (hash32-bytes +empty-trie-hash+)))

(defun validate-state-proof-fixture-storage-proof-shape
    (proof &optional storage-hash)
  (validate-fixture-object-fields
   proof
   +state-proof-fixture-storage-proof-fields+
   "State proof fixture storageProof entry")
  (hash32-from-hex (fixture-required-field proof "key"))
  (let ((value (hex-to-quantity (fixture-required-field proof "value")))
        (nodes (fixture-required-field proof "proof")))
    (when (and (plusp value)
               (not nodes))
      (error "State proof fixture storageProof entry with non-zero value must include proof nodes"))
    (when (and storage-hash
               (not (state-proof-fixture-empty-storage-root-p storage-hash))
               (not nodes))
      (error "State proof fixture storageProof entry against a non-empty storageHash must include proof nodes"))
    (when nodes
      (validate-state-proof-fixture-proof-node-list
       nodes
       "State proof fixture storage proof"))))

(defun state-proof-fixture-empty-account-fields-p
    (balance nonce storage-hash code-hash)
  (and (zerop balance)
       (zerop nonce)
       (bytes= (hash32-bytes storage-hash)
               (hash32-bytes +empty-trie-hash+))
       (bytes= (hash32-bytes code-hash)
               (hash32-bytes +empty-code-hash+))))

(defun validate-state-proof-fixture-proof-shape (proof)
  (validate-fixture-object-fields
   proof
   +state-proof-fixture-proof-fields+
   "State proof fixture expectedProof")
  (address-from-hex (fixture-required-field proof "address"))
  (let ((account-proof (fixture-required-field proof "accountProof"))
        (balance (hex-to-quantity (fixture-required-field proof "balance")))
        (code-hash (hash32-from-hex (fixture-required-field proof "codeHash")))
        (nonce (hex-to-quantity (fixture-required-field proof "nonce")))
        (storage-hash
          (hash32-from-hex (fixture-required-field proof "storageHash"))))
    (validate-state-proof-fixture-proof-node-list
     account-proof
     "State proof fixture accountProof")
    (when (and (not (state-proof-fixture-empty-account-fields-p
                     balance
                     nonce
                     storage-hash
                     code-hash))
               (not account-proof))
      (error "State proof fixture expectedProof with non-empty account fields must include accountProof nodes"))
    (let ((storage-proof (fixture-required-field proof "storageProof")))
      (unless (listp storage-proof)
        (error "State proof fixture storageProof must be a JSON array"))
      (dolist (entry storage-proof)
        (validate-state-proof-fixture-storage-proof-shape entry storage-hash)))))

(defun validate-state-proof-fixture-request-proof-alignment (request proof)
  (unless (bytes= (address-bytes
                   (address-from-hex
                    (fixture-required-field request "address")))
                  (address-bytes
                   (address-from-hex
                    (fixture-required-field proof "address"))))
    (error "State proof fixture expectedProof address must match request address"))
  (let ((storage-keys (fixture-required-field request "storageKeys"))
        (storage-proof (fixture-required-field proof "storageProof")))
    (unless (= (length storage-keys) (length storage-proof))
      (error "State proof fixture storageProof length must match request storageKeys"))
    (loop for key in storage-keys
          for entry in storage-proof
          for index from 0
          unless (bytes= (hash32-bytes (hash32-from-hex key))
                         (hash32-bytes
                          (hash32-from-hex
                           (fixture-required-field entry "key"))))
            do (error "State proof fixture storageProof key at index ~D must match request storageKeys"
                      index))))

(defun validate-state-proof-fixture-case-shape (case)
  (validate-fixture-object-fields
   case
   +state-proof-fixture-case-fields+
   "State proof fixture case")
  (when (blank-string-p (fixture-required-field case "name"))
    (error "State proof fixture case name must be present"))
  (validate-state-proof-fixture-case-tags case (make-hash-table :test 'equal))
  (let ((operations (fixture-required-field case "operations")))
    (unless (listp operations)
      (error "State proof fixture case operations must be a JSON array"))
    (dolist (operation operations)
      (validate-state-root-fixture-operation-shape operation)))
  (let ((request (fixture-required-field case "request"))
        (proof (fixture-required-field case "expectedProof")))
    (validate-state-proof-fixture-request-shape request)
    (hash32-from-hex (fixture-required-field case "expectedRoot"))
    (validate-state-proof-fixture-proof-shape proof)
    (validate-state-proof-fixture-request-proof-alignment request proof)))

(defun validate-state-proof-fixture-cases (cases)
  (unless (listp cases)
    (error "State proof fixture cases must be a JSON array"))
  (let ((seen-names (make-hash-table :test 'equal))
        (seen-tags (make-hash-table :test 'equal)))
    (dolist (case cases)
      (validate-state-proof-fixture-case-name case seen-names)
      (validate-state-proof-fixture-case-tags case seen-tags)
      (validate-state-proof-fixture-case-shape case))
    (dolist (tag +state-proof-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "State proof fixture is missing required coverage tag ~A"
               tag)))))

(defun run-state-proof-fixture-request (state request)
  (let ((address (address-from-hex (fixture-object-field request "address")))
        (storage-keys
          (mapcar #'hash32-from-hex
                  (fixture-object-field request "storageKeys"))))
    (state-db-get-proof state address storage-keys)))

(deftest state-root-fixture-shape-validation
  (let ((valid-case
          (list
           (cons "name" "valid-shape")
           (cons "tags" (list "account-root" "storage-root" "code-root"))
           (cons "operations"
                 (list
                  (list (cons "op" "setAccount")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "nonce" 1)
                        (cons "balance" 2))
                  (list (cons "op" "setStorage")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "slot"
                              "0x0000000000000000000000000000000000000000000000000000000000000001")
                        (cons "value" 3))
                  (list (cons "op" "setCode")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "code" "0x6001"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
    (validate-state-root-fixture-case-shape valid-case))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "seed")
           (cons "unexpected" t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-case-field")
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "root" "unexpected"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-case-field")
           (cons "name" "duplicate-case-field-shadow")
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-operation-field")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "storage" nil))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-operation-field")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "balance" 2))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "bad-storage-root-shape")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root" "0x01")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-storage-root-field")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                             (cons "root"
                                   "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-storage-root-address")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-account-field")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "storage" nil)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-account-field")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "balance" 2)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-account-address")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 2)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-tag")
           (cons "tags" (list "unknown"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-tag")
           (cons "tags" (list "account-root" "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-cases
     (list
      (list (cons "name" "duplicate")
            (cons "tags" +state-root-fixture-required-tags+)
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
      (list (cons "name" "duplicate")
            (cons "tags" +state-root-fixture-required-tags+)
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))))
  (signals error
    (validate-state-root-fixture-cases
     (list
      (list (cons "name" "missing-required-coverage")
            (cons "tags" (list "empty-state-root"))
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))))
  (let ((+state-root-fixture-required-case-names+ '("present" "missing")))
    (signals error
      (validate-state-root-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (let ((+state-root-fixture-required-case-names+ '("present" "present")))
    (signals error
      (validate-state-root-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x01")
           (cons "balance" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot" "0x01")
           (cons "value" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot"
                 "0x0000000000000000000000000000000000000000000000000000000000000001"))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "balance" -1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "clearAccount")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "balance" 0))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setCode")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "code" "0x0")))))

(deftest state-root-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-root-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-state-root-fixture-metadata fixture)
    (validate-state-root-fixture-cases cases)
    (validate-state-root-fixture-required-case-names cases)
    (dolist (case cases)
      (let ((state (run-state-root-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (assert-state-root-fixture-final-operation-state state case)
        (assert-state-root-fixture-storage-roots state case)
        (assert-state-root-fixture-accounts state case)))))

(deftest state-proof-fixture-shape-validation
  (let ((valid-case
          (list
           (cons "name" "valid-proof-shape")
           (cons "tags" +state-proof-fixture-required-tags+)
           (cons "operations"
                 (list
                  (list (cons "op" "setAccount")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "balance" 1))))
           (cons "request"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "storageKeys"
                        (list
                         "0x0000000000000000000000000000000000000000000000000000000000000001"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedProof"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "accountProof" nil)
                  (cons "balance" "0x0")
                  (cons "codeHash"
                        "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
                  (cons "nonce" "0x0")
                  (cons "storageHash"
                        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                  (cons "storageProof"
                        (list
                         (list
                          (cons "key"
                                "0x0000000000000000000000000000000000000000000000000000000000000001")
                          (cons "value" "0x0")
                          (cons "proof" nil)))))))))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=))))
      (validate-state-proof-fixture-case-shape valid-case)
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "address"
                  "0x0000000000000000000000000000000000000002")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "storageProof" nil)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "accountProof" (list "0x8101"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "balance" "0x1")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "storageHash"
                  "0x2e7827dc2c61c322f13f77e6f25dd18844ccc48426dde70301d2d57d138fced8")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((request (fixture-required-field valid-case "request"))
               (bad-request
                 (replace-field
                  request
                  "storageKeys"
                  (list
                   "0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0X0000000000000000000000000000000000000000000000000000000000000001"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "request" bad-request))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000002")
                   (cons "value" "0x0")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))))
  (signals error
    (validate-state-proof-fixture-storage-proof-shape
     (list (cons "key"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "value" "0x0")
           (cons "proof" (list "0x8101")))))
  (signals error
    (validate-state-proof-fixture-storage-proof-shape
     (list (cons "key"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "value" "0x1")
           (cons "proof" nil))))
  (signals error
    (validate-state-proof-fixture-metadata
     (list (cons "format" +state-proof-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-proof-fixture-case-shape
     (list (cons "name" "unknown-proof-field")
           (cons "tags" (list "geth-shaped-result"))
           (cons "operations" nil)
           (cons "request"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "storageKeys" nil)))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedProof"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "accountProof" nil)
                  (cons "balance" "0x0")
                  (cons "codeHash"
                        "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
                  (cons "nonce" "0x0")
                  (cons "storageHash"
                        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                  (cons "storageProof" nil)
                  (cons "unexpected" t)))))))

(deftest state-proof-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-proof-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-state-proof-fixture-metadata fixture)
    (validate-state-proof-fixture-cases cases)
    (dolist (case cases)
      (let* ((state (run-state-root-fixture-case case))
             (proof
               (run-state-proof-fixture-request
                state
                (fixture-object-field case "request"))))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (is (state-db-verify-proof (state-db-root state) proof))
        (is (equal (fixture-object-field case "expectedProof")
                   (state-proof-result-rpc-object proof)))))))
