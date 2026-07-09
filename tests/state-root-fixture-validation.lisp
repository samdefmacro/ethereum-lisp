(in-package #:ethereum-lisp.test)

(defun validate-state-root-fixture-object-fields
    (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (unless (stringp name)
          (error "~A field name must be a string" label))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-state-root-fixture-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-state-root-fixture-address-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be an address hex string" label field))
    (let ((address (address-from-hex value)))
      (unless (string= value (address-to-hex address))
        (error "~A ~A must be canonical lowercase 0x-prefixed address hex"
               label field)))))

(defun validate-state-root-fixture-hash-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hash hex string" label field))
    (let ((hash (hash32-from-hex value)))
      (unless (string= value (hash32-to-hex hash))
        (error "~A ~A must be canonical lowercase 0x-prefixed hash hex"
               label field)))))

(defun validate-state-root-fixture-hex-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hex string" label field))
    (let ((bytes (hex-to-bytes value)))
      (unless (string= value (bytes-to-hex bytes))
        (error "~A ~A must be canonical lowercase 0x-prefixed hex"
               label field)))))

(defun validate-state-root-fixture-metadata (fixture)
  (validate-state-root-fixture-object-fields
   fixture
   +state-root-fixture-top-level-fields+
   "State root fixture")
  (validate-fixture-format fixture +state-root-fixture-format+)
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "State root fixture source")
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
  (validate-state-root-fixture-address-field
   operation
   "address"
   "State root fixture operation"))

(defun validate-state-root-fixture-recipient (operation)
  (validate-state-root-fixture-address-field
   operation
   "recipient"
   "State root fixture operation"))

(defun validate-state-root-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (validate-state-root-fixture-non-empty-string
     name
     "State root fixture case name")
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
    (unless (stringp op)
      (error "State root fixture operation op must be a string"))
    (validate-state-root-fixture-address operation)
    (cond
      ((string= op "setAccount")
       (validate-state-root-fixture-non-negative-integer operation "nonce")
       (validate-state-root-fixture-non-negative-integer operation "balance"))
      ((string= op "addBalance")
       (validate-state-root-fixture-non-negative-integer
        operation "amount" :required-p t)
       (validate-state-root-fixture-operation-absent-fields
        operation
        '("recipient" "nonce" "balance" "slot" "value" "code")))
      ((string= op "transferValue")
       (validate-state-root-fixture-recipient operation)
       (validate-state-root-fixture-non-negative-integer
        operation "amount" :required-p t)
       (validate-state-root-fixture-operation-absent-fields
        operation
        '("nonce" "balance" "slot" "value" "code")))
      ((string= op "setStorage")
       (validate-state-root-fixture-hash-field
        operation
        "slot"
        "State root fixture operation")
       (validate-state-root-fixture-non-negative-integer
        operation "value" :required-p t))
      ((string= op "setCode")
       (validate-state-root-fixture-hex-field
        operation
        "code"
        "State root fixture operation"))
      ((string= op "clearAccount")
       (validate-state-root-fixture-operation-absent-fields
        operation
        '("recipient" "nonce" "balance" "slot" "value" "code")))
      (t
       (error "Unknown state root fixture operation: ~A" op)))))

(defun validate-state-root-fixture-storage-root-shape (expected)
  (unless (listp expected)
    (error "State root fixture expectedStorageRoots entry must be a JSON object"))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-storage-root-fields+
   "State root fixture expectedStorageRoots entry")
  (validate-state-root-fixture-address-field
   expected
   "address"
   "State root fixture expectedStorageRoots entry")
  (validate-state-root-fixture-hash-field
   expected
   "root"
   "State root fixture expectedStorageRoots entry"))

(defun validate-state-root-fixture-storage-trie-shape (expected)
  (unless (listp expected)
    (error "State root fixture expectedStorageTrieShapes entry must be a JSON object"))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-storage-trie-shape-fields+
   "State root fixture expectedStorageTrieShapes entry")
  (validate-state-root-fixture-address-field
   expected
   "address"
   "State root fixture expectedStorageTrieShapes entry")
  (let ((shape (fixture-required-field expected "shape")))
    (unless (and (stringp shape)
                 (member shape +state-root-fixture-trie-shapes+
                         :test #'string=))
      (error "State root fixture expectedStorageTrieShapes shape is unknown: ~A"
             shape)))
  (when (fixture-field-present-p expected "rootPathNibbles")
    (validate-state-root-fixture-nibble-list
     (fixture-object-field expected "rootPathNibbles")
     "State root fixture expectedStorageTrieShapes rootPathNibbles"))
  (when (fixture-field-present-p expected "childReference")
    (let ((kind (fixture-object-field expected "childReference")))
      (unless (and (stringp kind)
                   (member kind
                           +state-root-fixture-child-reference-kinds+
                           :test #'string=))
        (error "State root fixture expectedStorageTrieShapes childReference is unknown: ~A"
               kind))))
  (when (fixture-field-present-p expected "rootChildren")
    (validate-state-root-fixture-nibble-list
     (fixture-object-field expected "rootChildren")
     "State root fixture expectedStorageTrieShapes rootChildren"
     :child-index-p t))
  (when (fixture-field-present-p expected "rootChildShapes")
    (validate-state-root-fixture-state-trie-child-shapes
     (fixture-object-field expected "rootChildShapes")))
  (when (fixture-field-present-p expected "rootChildReferences")
    (validate-state-root-fixture-child-reference-map
     (fixture-object-field expected "rootChildReferences")
     "State root fixture expectedStorageTrieShapes rootChildReferences")))

(defun validate-state-root-fixture-account-shape (expected)
  (unless (listp expected)
    (error "State root fixture expectedAccounts entry must be a JSON object"))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-account-fields+
   "State root fixture expectedAccounts entry")
  (validate-state-root-fixture-address-field
   expected
   "address"
   "State root fixture expectedAccounts entry")
  (validate-state-root-fixture-non-negative-integer expected "nonce")
  (validate-state-root-fixture-non-negative-integer expected "balance")
  (when (fixture-field-present-p expected "storageRoot")
    (validate-state-root-fixture-hash-field
     expected
     "storageRoot"
     "State root fixture expectedAccounts entry"))
  (when (fixture-field-present-p expected "codeHash")
    (validate-state-root-fixture-hash-field
     expected
     "codeHash"
     "State root fixture expectedAccounts entry"))
  (when (fixture-field-present-p expected "rlp")
    (validate-state-root-fixture-hex-field
     expected
     "rlp"
     "State root fixture expectedAccounts entry")))

(defun validate-state-root-fixture-account-range-storage-shape
    (expected case-name)
  (unless (listp expected)
    (error "State root fixture case ~A expectedAccountRanges storage entry must be a JSON object"
           case-name))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-account-range-storage-fields+
   (format nil "State root fixture case ~A expectedAccountRanges storage entry"
           case-name))
  (validate-state-root-fixture-hash-field
   expected
   "slot"
   "State root fixture expectedAccountRanges storage entry")
  (validate-state-root-fixture-non-negative-integer
   expected
   "value"
   :required-p t))

(defun validate-state-root-fixture-account-range-account-shape
    (expected case-name)
  (unless (listp expected)
    (error "State root fixture case ~A expectedAccountRanges account entry must be a JSON object"
           case-name))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-account-range-account-fields+
   (format nil "State root fixture case ~A expectedAccountRanges account entry"
           case-name))
  (validate-state-root-fixture-hash-field
   expected
   "proofKey"
   "State root fixture expectedAccountRanges account entry")
  (validate-state-root-fixture-address-field
   expected
   "address"
   "State root fixture expectedAccountRanges account entry")
  (validate-state-root-fixture-hex-field
   expected
   "rlp"
   "State root fixture expectedAccountRanges account entry")
  (validate-state-root-fixture-hex-field
   expected
   "code"
   "State root fixture expectedAccountRanges account entry")
  (let ((storage (fixture-required-field expected "storage")))
    (unless (listp storage)
      (error "State root fixture case ~A expectedAccountRanges storage must be a JSON array"
             case-name))
    (let ((seen-slots (make-hash-table :test 'equal)))
      (dolist (entry storage)
        (validate-state-root-fixture-account-range-storage-shape
         entry case-name)
        (let ((slot (fixture-required-field entry "slot")))
          (when (gethash slot seen-slots)
            (error "State root fixture case ~A expectedAccountRanges has duplicate storage slot ~A"
                   case-name slot))
          (setf (gethash slot seen-slots) t))))))

(defun validate-state-root-fixture-account-range-shape (expected case-name)
  (unless (listp expected)
    (error "State root fixture case ~A expectedAccountRanges entry must be a JSON object"
           case-name))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-account-range-fields+
   (format nil "State root fixture case ~A expectedAccountRanges entry"
           case-name))
  (when (fixture-field-present-p expected "startProofKey")
    (validate-state-root-fixture-hash-field
     expected
     "startProofKey"
     "State root fixture expectedAccountRanges entry"))
  (when (fixture-field-present-p expected "endProofKey")
    (validate-state-root-fixture-hash-field
     expected
     "endProofKey"
     "State root fixture expectedAccountRanges entry"))
  (let ((accounts (fixture-required-field expected "expectedAccounts"))
        (seen-proof-keys (make-hash-table :test 'equal))
        (previous-proof-key nil))
    (unless (listp accounts)
      (error "State root fixture case ~A expectedAccountRanges expectedAccounts must be a JSON array"
             case-name))
    (dolist (account accounts)
      (validate-state-root-fixture-account-range-account-shape
       account case-name)
      (let ((proof-key (fixture-required-field account "proofKey")))
        (when (gethash proof-key seen-proof-keys)
          (error "State root fixture case ~A expectedAccountRanges has duplicate proofKey ~A"
                 case-name proof-key))
        (when (and previous-proof-key
                   (string< proof-key previous-proof-key))
          (error "State root fixture case ~A expectedAccountRanges proofKeys must be sorted"
                 case-name))
        (setf (gethash proof-key seen-proof-keys) t
              previous-proof-key proof-key)))))

(defun validate-state-root-fixture-storage-range-entry-shape
    (expected case-name)
  (unless (listp expected)
    (error "State root fixture case ~A expectedStorageRanges entry item must be a JSON object"
           case-name))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-storage-range-entry-fields+
   (format nil "State root fixture case ~A expectedStorageRanges entry item"
           case-name))
  (validate-state-root-fixture-hash-field
   expected
   "proofKey"
   "State root fixture expectedStorageRanges entry")
  (validate-state-root-fixture-hash-field
   expected
   "slot"
   "State root fixture expectedStorageRanges entry")
  (validate-state-root-fixture-non-negative-integer
   expected
   "value"
   :required-p t))

(defun validate-state-root-fixture-storage-range-shape (expected case-name)
  (unless (listp expected)
    (error "State root fixture case ~A expectedStorageRanges entry must be a JSON object"
           case-name))
  (validate-state-root-fixture-object-fields
   expected
   +state-root-fixture-storage-range-fields+
   (format nil "State root fixture case ~A expectedStorageRanges entry"
           case-name))
  (validate-state-root-fixture-address-field
   expected
   "address"
   "State root fixture expectedStorageRanges entry")
  (when (fixture-field-present-p expected "startProofKey")
    (validate-state-root-fixture-hash-field
     expected
     "startProofKey"
     "State root fixture expectedStorageRanges entry"))
  (when (fixture-field-present-p expected "endProofKey")
    (validate-state-root-fixture-hash-field
     expected
     "endProofKey"
     "State root fixture expectedStorageRanges entry"))
  (let ((storage (fixture-required-field expected "expectedStorage"))
        (seen-proof-keys (make-hash-table :test 'equal))
        (previous-proof-key nil))
    (unless (listp storage)
      (error "State root fixture case ~A expectedStorageRanges expectedStorage must be a JSON array"
             case-name))
    (dolist (entry storage)
      (validate-state-root-fixture-storage-range-entry-shape
       entry case-name)
      (let ((proof-key (fixture-required-field entry "proofKey")))
        (when (gethash proof-key seen-proof-keys)
          (error "State root fixture case ~A expectedStorageRanges has duplicate proofKey ~A"
                 case-name proof-key))
        (when (and previous-proof-key
                   (string< proof-key previous-proof-key))
          (error "State root fixture case ~A expectedStorageRanges proofKeys must be sorted"
                 case-name))
        (setf (gethash proof-key seen-proof-keys) t
              previous-proof-key proof-key)))))

(defun validate-state-root-fixture-trie-shape-field (case)
  (when (fixture-field-present-p case "expectedStateTrieShape")
    (let ((shape (fixture-object-field case "expectedStateTrieShape")))
      (unless (and (stringp shape)
                   (member shape +state-root-fixture-trie-shapes+
                           :test #'string=))
        (error "State root fixture expectedStateTrieShape is unknown: ~A"
               shape)))))

(defun validate-state-root-fixture-nibble-list (values label &key child-index-p)
  (unless (listp values)
    (error "~A must be a JSON array" label))
  (let ((seen (make-hash-table :test 'eql)))
    (dolist (value values)
      (unless (and (integerp value)
                   (not (minusp value))
                   (<= value (if child-index-p 15 16)))
        (error "~A contains invalid nibble/index ~A" label value))
      (when child-index-p
        (when (gethash value seen)
          (error "~A has duplicate child index ~A" label value))
        (setf (gethash value seen) t)))))

(defun validate-state-root-fixture-state-trie-child-shapes (value)
  (unless (listp value)
    (error "State root fixture expectedStateTrieRootChildShapes must be a JSON object"))
  (let ((seen (make-hash-table :test 'eql)))
    (dolist (entry value)
      (let ((index-text (car entry))
            (shape (cdr entry)))
        (unless (stringp index-text)
          (error "State root fixture state trie child-shape index must be a string"))
        (let ((index (parse-integer index-text :junk-allowed nil)))
          (unless (<= 0 index 15)
            (error "State root fixture state trie child-shape index is out of range: ~A"
                   index-text))
          (when (gethash index seen)
            (error "State root fixture state trie child-shape index is duplicated: ~A"
                   index-text))
          (setf (gethash index seen) t))
        (unless (and (stringp shape)
                     (member shape +state-root-fixture-trie-shapes+
                             :test #'string=))
          (error "State root fixture state trie child-shape is unknown: ~A"
                 shape))))))

(defun validate-state-root-fixture-child-reference-map (value label)
  (unless (listp value)
    (error "~A must be a JSON object" label))
  (let ((seen (make-hash-table :test 'eql)))
    (dolist (entry value)
      (let ((index-text (car entry))
            (kind (cdr entry)))
        (unless (stringp index-text)
          (error "~A child-reference index must be a string" label))
        (let ((index (parse-integer index-text :junk-allowed nil)))
          (unless (<= 0 index 15)
            (error "~A child-reference index is out of range: ~A"
                   label
                   index-text))
          (when (gethash index seen)
            (error "~A child-reference index is duplicated: ~A"
                   label
                   index-text))
          (setf (gethash index seen) t))
        (unless (and (stringp kind)
                     (member kind
                             +state-root-fixture-child-reference-kinds+
                             :test #'string=))
          (error "~A child-reference kind is unknown: ~A"
                 label
                 kind))))))

(defun validate-state-root-fixture-state-trie-expectations (case)
  (validate-state-root-fixture-trie-shape-field case)
  (when (fixture-field-present-p case "expectedStateTrieRootPathNibbles")
    (validate-state-root-fixture-nibble-list
     (fixture-object-field case "expectedStateTrieRootPathNibbles")
     "State root fixture expectedStateTrieRootPathNibbles"))
  (when (fixture-field-present-p case "expectedStateTrieChildReference")
    (let ((kind (fixture-object-field case "expectedStateTrieChildReference")))
      (unless (and (stringp kind)
                   (member kind
                           +state-root-fixture-child-reference-kinds+
                           :test #'string=))
        (error "State root fixture expectedStateTrieChildReference is unknown: ~A"
               kind))))
  (when (fixture-field-present-p case "expectedStateTrieRootChildren")
    (validate-state-root-fixture-nibble-list
     (fixture-object-field case "expectedStateTrieRootChildren")
     "State root fixture expectedStateTrieRootChildren"
     :child-index-p t))
  (when (fixture-field-present-p case "expectedStateTrieRootChildShapes")
    (validate-state-root-fixture-state-trie-child-shapes
     (fixture-object-field case "expectedStateTrieRootChildShapes")))
  (when (fixture-field-present-p case "expectedStateTrieRootChildReferences")
    (validate-state-root-fixture-child-reference-map
     (fixture-object-field case "expectedStateTrieRootChildReferences")
     "State root fixture expectedStateTrieRootChildReferences")))

(defun validate-state-root-fixture-case-shape (case)
  (unless (listp case)
    (error "State root fixture case must be a JSON object"))
  (validate-state-root-fixture-object-fields
   case
   +state-root-fixture-case-fields+
   "State root fixture case")
  (validate-state-root-fixture-non-empty-string
   (fixture-required-field case "name")
   "State root fixture case name")
  (validate-state-root-fixture-case-tags case (make-hash-table :test 'equal))
  (let ((operations (fixture-required-field case "operations")))
    (unless (listp operations)
      (error "State root fixture case operations must be a JSON array"))
    (dolist (operation operations)
      (validate-state-root-fixture-operation-shape operation)))
  (validate-state-root-fixture-hash-field
   case
   "expectedRoot"
   "State root fixture case")
  (when (fixture-field-present-p case "expectedStorageRoots")
    (let ((expected-storage-roots
            (fixture-object-field case "expectedStorageRoots"))
          (seen-addresses (make-hash-table :test 'equal)))
      (unless (listp expected-storage-roots)
        (error "State root fixture case expectedStorageRoots must be a JSON array"))
      (dolist (expected expected-storage-roots)
        (validate-state-root-fixture-storage-root-shape expected)
        (let* ((address (fixture-required-field expected "address"))
               (address-id (address-to-hex (address-from-hex address))))
          (when (gethash address-id seen-addresses)
            (error "State root fixture case has duplicate expectedStorageRoots address ~A"
                   address))
          (setf (gethash address-id seen-addresses) t)))))
  (when (fixture-field-present-p case "expectedStorageTrieShapes")
    (let ((expected-storage-trie-shapes
            (fixture-object-field case "expectedStorageTrieShapes"))
          (seen-addresses (make-hash-table :test 'equal)))
      (unless (listp expected-storage-trie-shapes)
        (error "State root fixture case expectedStorageTrieShapes must be a JSON array"))
      (dolist (expected expected-storage-trie-shapes)
        (validate-state-root-fixture-storage-trie-shape expected)
        (let* ((address (fixture-required-field expected "address"))
               (address-id (address-to-hex (address-from-hex address))))
          (when (gethash address-id seen-addresses)
            (error "State root fixture case has duplicate expectedStorageTrieShapes address ~A"
                   address))
          (setf (gethash address-id seen-addresses) t)))))
  (when (fixture-field-present-p case "expectedAccounts")
    (let ((expected-accounts
            (fixture-object-field case "expectedAccounts"))
          (seen-addresses (make-hash-table :test 'equal)))
      (unless (listp expected-accounts)
        (error "State root fixture case expectedAccounts must be a JSON array"))
      (dolist (expected expected-accounts)
        (validate-state-root-fixture-account-shape expected)
        (let* ((address (fixture-required-field expected "address"))
               (address-id (address-to-hex (address-from-hex address))))
          (when (gethash address-id seen-addresses)
            (error "State root fixture case has duplicate expectedAccounts address ~A"
                   address))
          (setf (gethash address-id seen-addresses) t)))))
  (when (fixture-field-present-p case "expectedAccountRanges")
    (let ((expected-account-ranges
            (fixture-object-field case "expectedAccountRanges")))
      (unless (listp expected-account-ranges)
        (error "State root fixture case expectedAccountRanges must be a JSON array"))
      (dolist (expected expected-account-ranges)
        (validate-state-root-fixture-account-range-shape
         expected
         (fixture-required-field case "name")))))
  (when (fixture-field-present-p case "expectedStorageRanges")
    (let ((expected-storage-ranges
            (fixture-object-field case "expectedStorageRanges")))
      (unless (listp expected-storage-ranges)
        (error "State root fixture case expectedStorageRanges must be a JSON array"))
      (dolist (expected expected-storage-ranges)
        (validate-state-root-fixture-storage-range-shape
         expected
         (fixture-required-field case "name")))))
  (validate-state-root-fixture-state-trie-expectations case))

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

