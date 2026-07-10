(in-package #:ethereum-lisp.test)

(defun validate-state-proof-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +state-proof-fixture-top-level-fields+
   "State proof fixture")
  (validate-fixture-format fixture +state-proof-fixture-format+)
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "State proof fixture source")
  (validate-fixture-pinned-eest-source fixture))

(defun validate-state-proof-reference-source (source label)
  (validate-fixture-object-fields
   source
   +state-proof-reference-fields+
   label)
  (dolist (field +state-proof-reference-fields+)
    (validate-state-root-fixture-non-empty-string
     (fixture-required-field source field)
     (format nil "~A ~A" label field))))

(defun validate-state-proof-reference-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +state-proof-reference-fixture-top-level-fields+
   "State proof reference fixture")
  (validate-fixture-format fixture +state-proof-reference-fixture-format+)
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "State proof reference fixture source")
  (let ((references (fixture-required-field fixture "references")))
    (unless (and (listp references) references)
      (error "State proof reference fixture references must be a non-empty array"))
    (dolist (source references)
      (validate-state-proof-reference-source
       source
       "State proof reference fixture reference"))))

(defun validate-state-proof-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (validate-state-root-fixture-non-empty-string
     name
     "State proof fixture case name")
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
    (unless (string= value (bytes-to-hex (hex-to-bytes value)))
      (error "~A entries must be canonical lowercase 0x-prefixed hex"
             label))
    (rlp-decode-one (hex-to-bytes value))))

(defun validate-state-proof-fixture-canonical-address-field
    (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A must be an address hex string" label))
    (unless (string= value (address-to-hex (address-from-hex value)))
      (error "~A must be canonical lowercase 0x-prefixed address hex"
             label))))

(defun validate-state-proof-fixture-canonical-hash-field
    (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A must be a hash hex string" label))
    (unless (string= value (hash32-to-hex (hash32-from-hex value)))
      (error "~A must be canonical lowercase 0x-prefixed hash hex"
             label))))

(defun validate-state-proof-fixture-canonical-quantity-field
    (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A must be a quantity string" label))
    (unless (string= value (string-downcase (quantity-to-hex (hex-to-quantity value))))
      (error "~A must be a canonical quantity" label))))

(defun state-proof-fixture-storage-key-from-request (key)
  (unless (stringp key)
    (error "State proof fixture request storage key must be a hex string"))
  (let ((hex (if (and (>= (length key) 2)
                      (char= (char key 0) #\0)
                      (member (char key 1) '(#\x #\X)))
                 (subseq key 2)
                 key)))
    (when (oddp (length hex))
      (setf hex (concatenate 'string "0" hex)))
    (when (> (length hex) 64)
      (error "State proof fixture request storage key is wider than 32 bytes"))
    (handler-case
        (let ((bytes (hex-to-bytes hex)))
          (let ((padded (make-byte-vector 32)))
            (replace padded bytes :start1 (- 32 (length bytes)))
            (make-hash32 padded)))
      (error ()
        (error "State proof fixture request storage key must be hex bytes")))))

(defun validate-state-proof-fixture-storage-key-uniqueness (storage-keys)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (key storage-keys)
      (let ((normalized (bytes-to-hex
                         (hash32-bytes
                          (state-proof-fixture-storage-key-from-request key))
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
  (let ((address (fixture-required-field request "address")))
    (unless (stringp address)
      (error "State proof fixture request address must be an address hex string"))
    (address-from-hex address))
  (let ((storage-keys (fixture-required-field request "storageKeys")))
    (unless (listp storage-keys)
      (error "State proof fixture request storageKeys must be a JSON array"))
    (dolist (key storage-keys)
      (state-proof-fixture-storage-key-from-request key))
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
  (validate-state-proof-fixture-canonical-hash-field
   proof
   "key"
   "State proof fixture storageProof key")
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "value"
   "State proof fixture storageProof value")
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

(defun validate-state-proof-reference-storage-proof-shape
    (proof &optional storage-hash)
  (validate-fixture-object-fields
   proof
   +state-proof-fixture-storage-proof-fields+
   "State proof reference fixture storageProof entry")
  (let ((key (fixture-required-field proof "key")))
    (handler-case
        (ethereum-lisp.state-proof-json::state-proof-rpc-storage-key key)
      (error ()
        (error "State proof reference fixture storageProof key is invalid"))))
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "value"
   "State proof reference fixture storageProof value")
  (let ((value (hex-to-quantity (fixture-required-field proof "value")))
        (nodes (fixture-required-field proof "proof")))
    (when (and (plusp value)
               (not nodes))
      (error "State proof reference fixture storageProof entry with non-zero value must include proof nodes"))
    (when (and storage-hash
               (not (state-proof-fixture-empty-storage-root-p storage-hash))
               (not nodes))
      (error "State proof reference fixture storageProof entry against a non-empty storageHash must include proof nodes"))
    (when nodes
      (validate-state-proof-fixture-proof-node-list
       nodes
       "State proof reference fixture storage proof"))))

(defun validate-state-proof-fixture-storage-proof-uniqueness (storage-proof)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry storage-proof)
      (let ((key (fixture-required-field entry "key")))
        (when (gethash key seen)
          (error "State proof fixture storageProof has duplicate key ~A"
                 key))
        (setf (gethash key seen) t)))))

(defun validate-state-proof-reference-storage-proof-uniqueness (storage-proof)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry storage-proof)
      (let ((key (hash32-to-hex
                  (ethereum-lisp.state-proof-json::state-proof-rpc-storage-key
                   (fixture-required-field entry "key")))))
        (when (gethash key seen)
          (error "State proof reference fixture storageProof has duplicate key ~A"
                 key))
        (setf (gethash key seen) t)))))

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
  (validate-state-proof-fixture-canonical-address-field
   proof
   "address"
   "State proof fixture expectedProof address")
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "balance"
   "State proof fixture expectedProof balance")
  (validate-state-proof-fixture-canonical-hash-field
   proof
   "codeHash"
   "State proof fixture expectedProof codeHash")
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "nonce"
   "State proof fixture expectedProof nonce")
  (validate-state-proof-fixture-canonical-hash-field
   proof
   "storageHash"
   "State proof fixture expectedProof storageHash")
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
        (validate-state-proof-fixture-storage-proof-shape entry storage-hash))
      (validate-state-proof-fixture-storage-proof-uniqueness storage-proof))))

(defun validate-state-proof-reference-proof-shape (proof)
  (validate-fixture-object-fields
   proof
   +state-proof-fixture-proof-fields+
   "State proof reference fixture expectedProof")
  (validate-state-proof-fixture-canonical-address-field
   proof
   "address"
   "State proof reference fixture expectedProof address")
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "balance"
   "State proof reference fixture expectedProof balance")
  (validate-state-proof-fixture-canonical-hash-field
   proof
   "codeHash"
   "State proof reference fixture expectedProof codeHash")
  (validate-state-proof-fixture-canonical-quantity-field
   proof
   "nonce"
   "State proof reference fixture expectedProof nonce")
  (validate-state-proof-fixture-canonical-hash-field
   proof
   "storageHash"
   "State proof reference fixture expectedProof storageHash")
  (let ((account-proof (fixture-required-field proof "accountProof"))
        (storage-hash
          (hash32-from-hex (fixture-required-field proof "storageHash"))))
    (validate-state-proof-fixture-proof-node-list
     account-proof
     "State proof reference fixture accountProof")
    (let ((storage-proof (fixture-required-field proof "storageProof")))
      (unless (listp storage-proof)
        (error "State proof reference fixture storageProof must be a JSON array"))
      (dolist (entry storage-proof)
        (validate-state-proof-reference-storage-proof-shape
         entry
         storage-hash))
      (validate-state-proof-reference-storage-proof-uniqueness
       storage-proof))))

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
          unless (bytes= (hash32-bytes
                          (state-proof-fixture-storage-key-from-request key))
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
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field case "name")
   "State proof fixture case name")
  (validate-state-proof-fixture-case-tags case (make-hash-table :test 'equal))
  (let ((operations (fixture-required-field case "operations")))
    (unless (listp operations)
      (error "State proof fixture case operations must be a JSON array"))
    (dolist (operation operations)
      (validate-state-root-fixture-operation-shape operation)))
  (let ((request (fixture-required-field case "request"))
        (proof (fixture-required-field case "expectedProof")))
    (validate-state-proof-fixture-request-shape request)
    (validate-state-root-fixture-hash-field
     case
     "expectedRoot"
     "State proof fixture case")
    (validate-state-proof-fixture-proof-shape proof)
    (validate-state-proof-fixture-request-proof-alignment request proof)))

(defun validate-state-proof-reference-fixture-case-shape (case)
  (validate-fixture-object-fields
   case
   +state-proof-reference-fixture-case-fields+
   "State proof reference fixture case")
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field case "name")
   "State proof reference fixture case name")
  (validate-state-proof-reference-source
   (fixture-required-field case "reference")
   "State proof reference fixture case reference")
  (validate-state-root-fixture-hash-field
   case
   "expectedRoot"
   "State proof reference fixture case")
  (validate-state-proof-reference-proof-shape
   (fixture-required-field case "expectedProof")))

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

(defun validate-state-proof-fixture-required-case-names (cases)
  (let ((case-by-name (make-hash-table :test 'equal))
        (seen-required-names (make-hash-table :test 'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name +state-proof-fixture-required-case-names+)
      (when (gethash name seen-required-names)
        (error "State proof fixture required case list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name case-by-name)
        (error "State proof fixture is missing required seed case ~A"
               name)))))
