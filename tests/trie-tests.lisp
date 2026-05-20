(in-package #:ethereum-lisp.test)

(defparameter +trie-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/trie-vectors.json")

(defparameter +trie-vector-fixture-format+
  "ethereum-lisp/trie-vectors-v1")

(defparameter +eest-trie-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-trie-sample.json")

(defparameter +eest-trie-test-secure-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-secureTrie.json")

(defparameter +empty-trie-root-hex+
  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")

(defparameter +phase-a-eest-trie-test-case-names+
  '("phase-a-secureTrie.json/phase-a-secure-branch"
    "phase-a-secureTrie.json/phase-a-secure-delete"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
    "phase-a-secureTrie.json/phase-a-secure-extension"
    "phase-a-secureTrie.json/phase-a-secure-insert"
    "phase-a-trie-multi.json/alpha"
    "phase-a-trie-multi.json/branch"
    "phase-a-trie-multi.json/branch-value"
    "phase-a-trie-multi.json/branch-value-zero-child"
    "phase-a-trie-multi.json/delete-branch-child"
    "phase-a-trie-multi.json/delete-branch-value"
    "phase-a-trie-multi.json/delete-missing-branch-child"
    "phase-a-trie-multi.json/duplicate-overwrite"
    "phase-a-trie-multi.json/delete-collapse"
    "phase-a-trie-multi.json/delete-missing-extension-child"
    "phase-a-trie-multi.json/delete-nested-branch-value"
    "phase-a-trie-multi.json/delete-prefix-branch-value"
    "phase-a-trie-multi.json/embedded-extension"
    "phase-a-trie-multi.json/extension"
    "phase-a-trie-multi.json/mixed-branch-refs"
    "phase-a-trie-sample.json"))

(defparameter +trie-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +trie-fixture-known-tags+
  '("leaf-root"
    "branch-root"
    "extension-root"
    "path-compression"
    "delete-collapse"
    "delete-to-empty"
    "embedded-child-reference"
    "hashed-child-reference"
    "branch-child-references"
    "branch-children"
    "branch-value"
    "missing-delete-noop"
    "duplicate-overwrite"
    "hex-key"
    "secure-key"
    "lookup-assertions"))

(defparameter +trie-fixture-required-case-names+
  '("single-leaf"
    "delete-missing-key-keeps-leaf"
    "duplicate-key-overwrites-leaf-value"
    "branch-extension-shared-prefix"
    "extension-embedded-child-reference"
    "extension-hashed-child-reference"
    "delete-collapses-path"
    "delete-nested-branch-value-keeps-extension"
    "delete-prefix-branch-value-keeps-sibling-extension"
    "delete-missing-extension-child-keeps-extension"
    "delete-last-entry-empty-root"
    "secure-branch-root"
    "secure-extension-root"
    "secure-delete-branch-child-collapses-to-leaf"
    "secure-single-leaf"
    "secure-delete-last-entry-empty-root"
    "root-branch-sparse-children"
    "root-branch-mixed-child-references"
    "delete-missing-branch-child-keeps-root-branch"
    "root-branch-value-for-prefix-key"
    "root-branch-value-with-zero-child"
    "delete-root-branch-value-collapses-to-leaf"
    "delete-root-branch-child-collapses-to-root-value-leaf"))

(defparameter +trie-fixture-required-tags+
  '("leaf-root"
    "branch-root"
    "extension-root"
    "delete-collapse"
    "delete-to-empty"
    "embedded-child-reference"
    "hashed-child-reference"
    "branch-child-references"
    "branch-value"
    "missing-delete-noop"
    "duplicate-overwrite"
    "hex-key"
    "secure-key"
    "lookup-assertions"))

(defparameter +trie-fixture-root-shapes+
  '("empty" "leaf" "extension" "branch"))

(defparameter +trie-fixture-child-reference-kinds+
  '("embedded" "hashed"))

(defparameter +trie-fixture-case-fields+
  '("name"
    "secure"
    "tags"
    "operations"
    "expectedRoot"
    "expectedShape"
    "expectedChildReference"
    "expectedRootChildren"
    "expectedRootChildReferences"
    "expectedRootPathNibbles"
    "expectedRootValueAscii"
    "expectedGets"
    "expectedMissing"))

(defparameter +trie-fixture-operation-fields+
  '("op" "keyHex" "keyAscii" "valueAscii"))

(defparameter +trie-fixture-expected-get-fields+
  '("keyHex" "keyAscii" "valueAscii"))

(defparameter +trie-fixture-expected-missing-fields+
  '("keyHex" "keyAscii"))

(defparameter +eest-trie-test-case-fields+
  '("in" "root" "secure"))

(defun validate-trie-fixture-object-fields (object allowed-fields label)
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

(defun validate-trie-fixture-metadata (fixture)
  (validate-trie-fixture-object-fields
   fixture
   +trie-fixture-top-level-fields+
   "Trie fixture")
  (validate-fixture-format fixture +trie-vector-fixture-format+)
  (when (blank-string-p (fixture-required-field fixture "source"))
    (error "Trie fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture))

(defun validate-trie-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (when (blank-string-p name)
      (error "Trie fixture case is missing a non-empty name"))
    (let ((previous (gethash name seen-names)))
      (when previous
        (error "Duplicate trie fixture case name: ~A" name)))
    (setf (gethash name seen-names) t)))

(defun validate-trie-fixture-case-tags (case seen-tags)
  (let ((name (fixture-object-field case "name"))
        (tags (fixture-object-field case "tags")))
    (unless (and (listp tags) tags)
      (error "Trie fixture case ~A must include non-empty tags" name))
    (let ((case-tags (make-hash-table :test 'equal)))
      (dolist (tag tags)
        (when (gethash tag case-tags)
          (error "Trie fixture case ~A has duplicate tag ~A" name tag))
        (setf (gethash tag case-tags) t)
        (unless (and (stringp tag)
                     (member tag +trie-fixture-known-tags+
                             :test #'string=))
          (error "Trie fixture case ~A has unknown tag ~A" name tag))
        (setf (gethash tag seen-tags) t)))))

(defun validate-trie-fixture-key-fields (object label)
  (let ((has-hex (fixture-field-present-p object "keyHex"))
        (has-ascii (fixture-field-present-p object "keyAscii")))
    (unless (or has-hex has-ascii)
      (error "~A must include keyHex or keyAscii" label))
    (when (and has-hex has-ascii)
      (error "~A must not include both keyHex and keyAscii" label))
    (when has-hex
      (unless (stringp (fixture-object-field object "keyHex"))
        (error "~A keyHex must be a string" label)))
    (when has-ascii
      (let ((key (fixture-object-field object "keyAscii")))
        (when (blank-string-p key)
          (error "~A keyAscii must be non-empty" label))))))

(defun validate-trie-fixture-operation (operation case-name)
  (unless (listp operation)
    (error "Trie fixture case ~A operation must be a JSON object" case-name))
  (validate-trie-fixture-object-fields
   operation
   +trie-fixture-operation-fields+
   (format nil "Trie fixture case ~A operation" case-name))
  (validate-trie-fixture-key-fields operation
                                    (format nil "Trie fixture case ~A operation"
                                            case-name))
  (let ((op (fixture-object-field operation "op")))
    (cond
      ((and (stringp op) (string= op "put"))
       (when (blank-string-p (fixture-object-field operation "valueAscii"))
         (error "Trie fixture case ~A put operation needs valueAscii"
                case-name)))
      ((and (stringp op) (string= op "delete"))
       (when (fixture-field-present-p operation "valueAscii")
         (error "Trie fixture case ~A delete operation must not include valueAscii"
                case-name)))
      (t (error "Unknown trie fixture operation in case ~A: ~A"
                case-name op)))))

(defun validate-trie-fixture-expected-lookup (expected case-name field)
  (unless (listp expected)
    (error "Trie fixture case ~A ~A entry must be a JSON object"
           case-name field))
  (validate-trie-fixture-object-fields
   expected
   (if (string= field "expectedGets")
       +trie-fixture-expected-get-fields+
       +trie-fixture-expected-missing-fields+)
   (format nil "Trie fixture case ~A ~A entry" case-name field))
  (validate-trie-fixture-key-fields expected
                                    (format nil "Trie fixture case ~A ~A entry"
                                            case-name field))
  (cond
    ((string= field "expectedGets")
     (when (blank-string-p (fixture-object-field expected "valueAscii"))
       (error "Trie fixture case ~A expectedGets entry needs valueAscii"
              case-name)))
    ((string= field "expectedMissing")
     (when (fixture-field-present-p expected "valueAscii")
       (error "Trie fixture case ~A expectedMissing entry must not include valueAscii"
              case-name)))))

(defun validate-trie-fixture-expected-lookup-keys (case)
  (let ((seen-keys (make-hash-table :test 'equal))
        (case-name (fixture-object-field case "name")))
    (labels ((record-key (expected field)
               (let* ((key (bytes-to-hex (trie-fixture-key expected)))
                      (previous-field (gethash key seen-keys)))
                 (when previous-field
                   (error "Trie fixture case ~A has duplicate lookup key ~A in ~A and ~A"
                          case-name
                          key
                          previous-field
                          field))
                 (setf (gethash key seen-keys) field))))
      (dolist (expected (fixture-object-field case "expectedGets"))
        (record-key expected "expectedGets"))
      (dolist (expected (fixture-object-field case "expectedMissing"))
        (record-key expected "expectedMissing")))))

(defun trie-fixture-valid-child-reference-kind-p (kind)
  (member kind +trie-fixture-child-reference-kinds+ :test #'string=))

(defun validate-trie-fixture-expected-root (case)
  (hash32-from-hex (fixture-required-field case "expectedRoot")))

(defun validate-trie-fixture-expected-shape (case)
  (let ((shape (fixture-required-field case "expectedShape")))
    (unless (member shape +trie-fixture-root-shapes+ :test #'string=)
      (error "Trie fixture case ~A has unknown expectedShape ~A"
             (fixture-object-field case "name")
             shape))
    shape))

(defun validate-trie-fixture-nibble-list (case field &key allow-terminator)
  (when (fixture-field-present-p case field)
    (let ((nibbles (fixture-object-field case field)))
      (unless (listp nibbles)
        (error "Trie fixture case ~A ~A must be a JSON array"
               (fixture-object-field case "name")
               field))
      (dolist (nibble nibbles)
        (unless (and (integerp nibble)
                     (<= 0 nibble)
                     (if allow-terminator
                         (<= nibble 16)
                         (< nibble 16)))
          (error "Trie fixture case ~A has malformed ~A nibble ~A"
                 (fixture-object-field case "name")
                 field
                 nibble))))))

(defun validate-trie-fixture-root-children (case)
  (when (fixture-field-present-p case "expectedRootChildren")
    (let ((children (fixture-object-field case "expectedRootChildren"))
          (seen (make-hash-table)))
      (unless (listp children)
        (error "Trie fixture case ~A expectedRootChildren must be a JSON array"
               (fixture-object-field case "name")))
      (dolist (child children)
        (unless (and (integerp child) (<= 0 child 15))
          (error "Trie fixture case ~A has malformed root child index ~A"
                 (fixture-object-field case "name")
                 child))
        (when (gethash child seen)
          (error "Trie fixture case ~A has duplicate root child index ~A"
                 (fixture-object-field case "name")
                 child))
        (setf (gethash child seen) t)))))

(defun validate-trie-fixture-root-child-references (case)
  (when (fixture-field-present-p case "expectedRootChildReferences")
    (let ((references
            (fixture-object-field case "expectedRootChildReferences"))
          (seen-indexes (make-hash-table)))
      (unless (listp references)
        (error "Trie fixture case ~A expectedRootChildReferences must be a JSON object"
               (fixture-object-field case "name")))
      (dolist (reference references)
        (let ((index (parse-integer (car reference)))
              (kind (cdr reference)))
          (unless (<= 0 index 15)
            (error "Trie fixture case ~A has malformed child reference index ~A"
                   (fixture-object-field case "name")
                   (car reference)))
          (when (gethash index seen-indexes)
            (error "Trie fixture case ~A has duplicate child reference index ~A"
                   (fixture-object-field case "name")
                   (car reference)))
          (setf (gethash index seen-indexes) t)
          (unless (trie-fixture-valid-child-reference-kind-p kind)
            (error "Trie fixture case ~A has unknown child reference kind ~A"
                   (fixture-object-field case "name")
                   kind)))))))

(defun validate-trie-fixture-expected-fields (case)
  (let ((shape (validate-trie-fixture-expected-shape case)))
    (validate-trie-fixture-expected-root case)
    (unless (or (not (fixture-field-present-p case "expectedChildReference"))
                (string= shape "extension"))
      (error "Trie fixture case ~A expectedChildReference requires an extension root"
             (fixture-object-field case "name")))
    (when (fixture-field-present-p case "expectedChildReference")
      (let ((kind (fixture-object-field case "expectedChildReference")))
        (unless (trie-fixture-valid-child-reference-kind-p kind)
          (error "Trie fixture case ~A has unknown expectedChildReference ~A"
                 (fixture-object-field case "name")
                 kind))))
    (unless (or (not (fixture-field-present-p case "expectedRootChildren"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildren requires a branch root"
             (fixture-object-field case "name")))
    (unless (or (not (fixture-field-present-p case "expectedRootChildReferences"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildReferences requires a branch root"
             (fixture-object-field case "name")))
    (validate-trie-fixture-root-children case)
    (validate-trie-fixture-root-child-references case)
    (cond
      ((string= shape "leaf")
       (validate-trie-fixture-nibble-list
        case "expectedRootPathNibbles" :allow-terminator t))
      ((string= shape "extension")
       (validate-trie-fixture-nibble-list
        case "expectedRootPathNibbles"))
      ((fixture-field-present-p case "expectedRootPathNibbles")
       (error "Trie fixture case ~A expectedRootPathNibbles requires a leaf or extension root"
              (fixture-object-field case "name"))))
    (when (and (fixture-field-present-p case "expectedRootValueAscii")
               (blank-string-p
                (fixture-object-field case "expectedRootValueAscii")))
      (error "Trie fixture case ~A expectedRootValueAscii must be non-empty"
             (fixture-object-field case "name")))))

(defun validate-trie-fixture-case-shape (case)
  (let ((name (fixture-object-field case "name"))
        (operations (fixture-object-field case "operations")))
    (validate-trie-fixture-object-fields
     case
     +trie-fixture-case-fields+
     (format nil "Trie fixture case ~A" name))
    (when (fixture-field-present-p case "secure")
      (let ((secure (fixture-object-field case "secure")))
        (unless (or (eq secure t) (null secure))
          (error "Trie fixture case ~A secure must be a boolean" name))))
    (unless (and (listp operations) operations)
      (error "Trie fixture case ~A must include non-empty operations" name))
    (validate-trie-fixture-expected-fields case)
    (dolist (operation operations)
      (validate-trie-fixture-operation operation name))
    (dolist (expected (fixture-object-field case "expectedGets"))
      (validate-trie-fixture-expected-lookup expected name "expectedGets"))
    (dolist (expected (fixture-object-field case "expectedMissing"))
      (validate-trie-fixture-expected-lookup expected name "expectedMissing"))
    (validate-trie-fixture-expected-lookup-keys case)))

(defun validate-trie-fixture-case-coverage (cases)
  (unless (and (listp cases) cases)
    (error "Trie fixture must include at least one case"))
  (let ((seen-names (make-hash-table :test #'equal))
        (seen-tags (make-hash-table :test #'equal))
        secure-leaf-root-p
        secure-delete-to-empty-p
        secure-branch-root-p
        secure-extension-root-p)
    (dolist (case cases)
      (unless (listp case)
        (error "Trie fixture case must be a JSON object"))
      (validate-trie-fixture-case-name case seen-names)
      (validate-trie-fixture-case-tags case seen-tags)
      (let ((secure-p (not (null (fixture-object-field case "secure"))))
            (shape (fixture-object-field case "expectedShape")))
        (when (and secure-p (stringp shape) (string= shape "branch"))
          (setf secure-branch-root-p t))
        (when (and secure-p (stringp shape) (string= shape "extension"))
          (setf secure-extension-root-p t))
        (when (and secure-p (stringp shape) (string= shape "leaf"))
          (setf secure-leaf-root-p t))
        (when (and secure-p
                   (stringp shape)
                   (string= shape "empty")
                   (member "delete-to-empty"
                           (fixture-object-field case "tags")
                           :test #'string=))
          (setf secure-delete-to-empty-p t))))
    (dolist (tag +trie-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "Trie fixture is missing required coverage tag ~A" tag)))
    (unless secure-leaf-root-p
      (error "Trie fixture must include a secure leaf root case"))
    (unless secure-delete-to-empty-p
      (error "Trie fixture must include a secure delete-to-empty case"))
    (unless secure-branch-root-p
      (error "Trie fixture must include a secure branch root case"))
    (unless secure-extension-root-p
      (error "Trie fixture must include a secure extension root case"))))

(defun validate-trie-fixture-cases (cases)
  (validate-trie-fixture-case-coverage cases)
  (dolist (case cases)
    (validate-trie-fixture-case-shape case)))

(defun validate-trie-fixture-required-case-names (cases)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-required-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name +trie-fixture-required-case-names+)
      (when (gethash name seen-required-names)
        (error "Trie fixture required case list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name case-by-name)
        (error "Trie fixture is missing required seed case ~A"
               name)))))

(defun eest-trie-test-json-paths (root)
  (let* ((root-path (pathname root))
         (pattern
           (make-pathname
            :directory (append (pathname-directory root-path)
                               (list :wild-inferiors))
            :name :wild
            :type "json"
            :defaults root-path)))
    (sort (directory pattern) #'string< :key #'namestring)))

(defun eest-trie-test-root-json-paths (root)
  (let ((paths (eest-trie-test-json-paths root)))
    (unless paths
      (error "EEST trie test root ~A has no JSON files" root))
    paths))

(defun eest-trie-test-root-file-names (root)
  (mapcar (lambda (path)
            (enough-namestring (truename path) (truename root)))
          (eest-trie-test-root-json-paths root)))

(defun eest-trie-test-normalized-root (value case-name)
  (cond
    ((null value)
     (error "EEST trie test case ~A root must be present" case-name))
    ((not (stringp value))
     (error "EEST trie test case ~A root must be a string" case-name))
    ((blank-string-p value)
     (error "EEST trie test case ~A root must be present" case-name))
    (t
     (let ((normalized
             (if (and (<= 2 (length value))
                      (char= #\0 (char value 0))
                      (char= #\x (char-downcase (char value 1))))
                 value
                 (concatenate 'string "0x" value))))
       (handler-case
           (hash32-to-hex (hash32-from-hex normalized))
         (error (condition)
           (error "EEST trie test case ~A root must be a 32-byte hex hash: ~A"
                  case-name
                  condition)))))))

(defun eest-trie-test-prefixed-hex-string-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun eest-trie-test-byte-string (value label)
  (handler-case
      (if (eest-trie-test-prefixed-hex-string-p value)
          (hex-to-bytes value)
          (ascii-to-bytes value))
    (error (condition)
      (error "~A must be an ASCII string or 0x-prefixed hex byte string: ~A"
             label
             condition))))

(defun eest-trie-test-normalized-byte-string (value label)
  (let ((bytes (eest-trie-test-byte-string value label)))
    (if (eest-trie-test-prefixed-hex-string-p value)
        (bytes-to-hex bytes)
        value)))

(defun normalize-eest-trie-test-case (name case &optional default-secure-p)
  (when (blank-string-p name)
    (error "EEST trie test case name must be present"))
  (unless (listp case)
    (error "EEST trie test case ~A must be a JSON object" name))
  (validate-trie-fixture-object-fields
   case
   +eest-trie-test-case-fields+
   (format nil "EEST trie test case ~A" name))
  (list
   (cons "name" name)
   (cons "entries"
         (normalize-eest-trie-test-entries
          name
          (fixture-required-field case "in")))
   (cons "secure"
         (eest-trie-test-normalized-secure-p
          name
          case
          default-secure-p))
   (cons "root"
         (eest-trie-test-normalized-root
          (fixture-required-field case "root")
          name))))

(defun eest-trie-test-normalized-secure-p
    (case-name case &optional default-secure-p)
  (if (fixture-field-present-p case "secure")
      (let ((value (fixture-object-field case "secure")))
        (unless (or (eq value t) (null value))
          (error "EEST trie test case ~A secure must be a boolean"
                 case-name))
        (not (null value)))
      (not (null default-secure-p))))

(defun eest-trie-test-entry-pair-p (entry)
  (and (consp entry)
       (consp (cdr entry))
       (null (cddr entry))))

(defun eest-trie-test-object-entry-p (entry)
  (and (consp entry)
       (stringp (car entry))
       (or (stringp (cdr entry))
           (null (cdr entry)))))

(defun eest-trie-test-object-entries-p (entries)
  (and entries
       (every #'eest-trie-test-object-entry-p entries)))

(defun eest-trie-test-entry-label (case-name index field)
  (if index
      (format nil "EEST trie test case ~A in entry ~D ~A"
              case-name
              index
              field)
      (format nil "EEST trie test case ~A in entry ~A"
              case-name
              field)))

(defun normalize-eest-trie-test-entry (case-name entry &optional index)
  (unless (eest-trie-test-entry-pair-p entry)
    (if index
        (error "EEST trie test case ~A in entry ~D must be a key/value pair"
               case-name
               index)
        (error "EEST trie test case ~A in entry must be a key/value pair"
               case-name)))
  (destructuring-bind (key value) entry
    (unless (stringp key)
      (if index
          (error "EEST trie test case ~A in entry ~D key must be a string"
                 case-name
                 index)
          (error "EEST trie test case ~A in entry key must be a string"
                 case-name)))
    (let ((normalized-key
            (eest-trie-test-normalized-byte-string
             key
             (eest-trie-test-entry-label case-name index "key"))))
      (cond
        ((null value)
         (list (cons "key" normalized-key)
               (cons "delete" t)))
        ((not (stringp value))
         (if index
             (error "EEST trie test case ~A in entry ~D value must be a string or null"
                    case-name
                    index)
             (error "EEST trie test case ~A in entry value must be a string or null"
                    case-name)))
        (t
         (let* ((label (eest-trie-test-entry-label case-name index "value"))
                (bytes (eest-trie-test-byte-string value label))
                (normalized-value
                  (if (eest-trie-test-prefixed-hex-string-p value)
                      (bytes-to-hex bytes)
                      value)))
           (if (zerop (length bytes))
               (list (cons "key" normalized-key)
                     (cons "delete" t))
               (list (cons "key" normalized-key)
                     (cons "value" normalized-value)))))))))

(defun normalize-eest-trie-test-object-entries (case-name entries)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (let* ((key (car entry))
             (key-id (bytes-to-hex
                      (eest-trie-test-byte-string
                       key
                       (format nil
                               "EEST trie test case ~A in object key"
                               case-name))
                      :prefix nil)))
        (when (gethash key-id seen)
          (error "EEST trie test case ~A in object has duplicate normalized key ~A"
                 case-name
                 key))
        (setf (gethash key-id seen) t))))
  (loop for entry in (sort (copy-list entries) #'string< :key #'car)
        for index from 0
        collect (normalize-eest-trie-test-entry
                 case-name
                 (list (car entry) (cdr entry))
                 index)))

(defun normalize-eest-trie-test-entries (case-name entries)
  (unless (listp entries)
    (error "EEST trie test case ~A in must be a JSON array" case-name))
  (if (eest-trie-test-object-entries-p entries)
      (normalize-eest-trie-test-object-entries case-name entries)
      (loop for entry in entries
            for index from 0
            collect (normalize-eest-trie-test-entry case-name entry index))))

(defun run-eest-trie-test-case (case)
  (let ((trie (make-mpt)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((trie-key (eest-trie-test-entry-trie-key case entry)))
        (if (fixture-field-present-p entry "delete")
            (mpt-delete trie trie-key)
            (mpt-put trie
                     trie-key
                     (eest-trie-test-byte-string
                      (fixture-required-field entry "value")
                      (format nil "EEST trie test case ~A in entry value"
                              (fixture-required-field case "name")))))))
    trie))

(defun eest-trie-test-entry-trie-key (case entry)
  (let ((key (eest-trie-test-byte-string
              (fixture-required-field entry "key")
              (format nil "EEST trie test case ~A in entry key"
                      (fixture-required-field case "name")))))
    (if (fixture-object-field case "secure")
        (keccak-256 key)
        key)))

(defun eest-trie-test-final-entry-map (case)
  (let ((final (make-hash-table :test 'equal)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key-id (bytes-to-hex
                     (eest-trie-test-entry-trie-key case entry)
                     :prefix nil)))
        (if (fixture-field-present-p entry "delete")
            (setf (gethash key-id final) nil)
            (setf (gethash key-id final)
                  (eest-trie-test-byte-string
                   (fixture-required-field entry "value")
                   (format nil "EEST trie test case ~A in entry value"
                           (fixture-required-field case "name")))))))
    final))

(defun assert-eest-trie-test-case-lookups (case trie)
  (let ((name (fixture-required-field case "name"))
        (final (eest-trie-test-final-entry-map case)))
    (maphash
     (lambda (key-id expected)
       (let* ((key (hex-to-bytes key-id))
              (actual (mpt-get trie key)))
         (if expected
             (progn
               (unless (bytes= expected actual)
                 (error "EEST trie test case ~A lookup mismatch for key ~A"
                        name
                        key-id))
               (assert-eest-trie-test-case-proof-present
                case
                trie
                key
                expected))
             (progn
               (when actual
                 (error "EEST trie test case ~A expected missing key ~A"
                        name
                        key-id))
               (assert-eest-trie-test-case-proof-missing
                case
                trie
                key)))))
     final)))

(defun assert-eest-trie-test-case-root (case)
  (let* ((trie (run-eest-trie-test-case case))
         (name (fixture-required-field case "name"))
         (expected-root (fixture-required-field case "root"))
         (actual-root (mpt-root-hex trie)))
    (unless (string= expected-root actual-root)
      (error "EEST trie test case ~A root mismatch: expected ~A, got ~A"
             name
             expected-root
             actual-root))
    (assert-eest-trie-test-case-lookups case trie)
    trie))

(defun assert-eest-trie-test-case-proof-present
    (case trie key expected-value)
  (multiple-value-bind (value present-p)
      (mpt-verify-proof (mpt-root-hash trie)
                        key
                        (mpt-get-proof trie key))
    (unless present-p
      (error "EEST trie test case ~A proof did not prove present key ~A"
             (fixture-required-field case "name")
             (bytes-to-hex key)))
    (unless (bytes= expected-value value)
      (error "EEST trie test case ~A proof value mismatch for key ~A"
             (fixture-required-field case "name")
             (bytes-to-hex key)))))

(defun assert-eest-trie-test-case-proof-missing (case trie key)
  (multiple-value-bind (value present-p)
      (mpt-verify-proof (mpt-root-hash trie)
                        key
                        (mpt-get-proof trie key))
    (when present-p
      (error "EEST trie test case ~A proof unexpectedly proved key ~A"
             (fixture-required-field case "name")
             (bytes-to-hex key)))
    (when value
      (error "EEST trie test case ~A missing-key proof returned value for key ~A"
             (fixture-required-field case "name")
             (bytes-to-hex key)))))

(defun validate-eest-trie-test-file-case-names (cases source)
  (unless cases
    (error "EEST trie test file ~A must include at least one case"
           source))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry)))
        (unless (stringp name)
          (error "EEST trie test file ~A case name must be a string"
                 source))
        (when (blank-string-p name)
          (error "EEST trie test file ~A case name must be present"
                 source))
        (when (gethash name seen)
          (error "EEST trie test file ~A has duplicate case name ~A"
                 source
                 name))
        (setf (gethash name seen) t)))))

(defun load-eest-trie-test-file (path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST trie test file must be a JSON object"))
    (validate-eest-trie-test-file-case-names cases path)
    (mapcar
     (lambda (entry)
       (normalize-eest-trie-test-case
        (car entry)
        (cdr entry)
        (eest-trie-test-secure-path-p path)))
     (sort (copy-list cases) #'string< :key #'car))))

(defun eest-trie-test-secure-path-p (path)
  (not (null (search "secureTrie" (namestring path) :test #'char-equal))))

(defun eest-trie-root-case-name (root path key singleton-p)
  (let ((relative (enough-namestring (truename path) (truename root))))
    (if singleton-p
        relative
        (format nil "~A/~A" relative key))))

(defun load-eest-trie-test-root-file-cases (root path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST trie test file must be a JSON object"))
    (validate-eest-trie-test-file-case-names cases path)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (normalize-eest-trie-test-case
          (eest-trie-root-case-name root path (car entry) singleton-p)
          (cdr entry)
          (eest-trie-test-secure-path-p path)))
       entries))))

(defun filter-eest-trie-test-root-cases (cases names)
  (if names
      (let ((selected nil)
            (seen (make-hash-table :test 'equal)))
        (dolist (case cases)
          (let ((name (fixture-object-field case "name")))
            (when (member name names :test #'string=)
              (push case selected)
              (setf (gethash name seen) t))))
        (dolist (name names)
          (unless (gethash name seen)
            (error "EEST trie selector ~A did not match any loaded case"
                   name)))
        (nreverse selected))
      cases))

(defun validate-eest-trie-selector-list (names)
  (unless (listp names)
    (error "EEST trie selector list must be a list"))
  (unless names
    (error "EEST trie selector list must not be empty"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (unless (stringp name)
        (error "EEST trie selector name must be a string"))
      (when (blank-string-p name)
        (error "EEST trie selector name must be present"))
      (unless (eest-trie-selector-source-style-p name)
        (error "EEST trie selector ~A must be a source-style JSON case name"
               name))
      (when (gethash name seen)
        (error "EEST trie selector list has duplicate name ~A"
               name))
      (setf (gethash name seen) t))))

(defun eest-trie-selector-source-style-p (name)
  (and (stringp name)
       (not (blank-string-p name))
       (not (char= (char name 0) #\/))
       (null (search ".." name))
       (null (search "//" name))
       (let* ((json-position (search ".json" name :test #'char-equal))
              (after-json (and json-position (+ json-position 5))))
         (and json-position
              (plusp json-position)
              (not (char= (char name (1- json-position)) #\/))
              (or (= after-json (length name))
                  (and (< after-json (length name))
                       (char= (char name after-json) #\/)
                       (< (1+ after-json) (length name))
                       (not (char= (char name (1+ after-json)) #\/))
                       (null (position #\/ name
                                       :start (1+ after-json)))))))))

(defun validate-eest-trie-test-root-case-names (cases)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (case cases)
      (let ((name (fixture-required-field case "name")))
        (when (gethash name seen)
          (error "EEST trie test root has duplicate case name ~A"
                 name))
        (setf (gethash name seen) t)))))

(defun load-eest-trie-test-root-cases (root &key names)
  (when names
    (validate-eest-trie-selector-list names))
  (let ((cases (loop for path in (eest-trie-test-root-json-paths root)
                     append (load-eest-trie-test-root-file-cases root path))))
    (validate-eest-trie-test-root-case-names cases)
    (filter-eest-trie-test-root-cases cases names)))

(defun load-phase-a-eest-trie-test-root-cases (root)
  (validate-eest-trie-selector-list
   +phase-a-eest-trie-test-case-names+)
  (let ((cases (load-eest-trie-test-root-cases
                root
                :names +phase-a-eest-trie-test-case-names+)))
    (validate-phase-a-eest-trie-test-coverage cases)
    cases))

(defun eest-trie-test-empty-key-delete-p (entry)
  (and (fixture-field-present-p entry "delete")
       (zerop (length (eest-trie-test-byte-string
                       (fixture-required-field entry "key")
                       "EEST trie summary entry key")))))

(defun eest-trie-test-non-empty-key-delete-p (entry)
  (and (fixture-field-present-p entry "delete")
       (plusp (length (eest-trie-test-byte-string
                       (fixture-required-field entry "key")
                       "EEST trie summary entry key")))))

(defun eest-trie-test-case-overwrites-key-p (case)
  (let ((last-operations (make-hash-table :test 'equal)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key-id (bytes-to-hex
                     (eest-trie-test-entry-trie-key case entry)
                     :prefix nil)))
        (if (fixture-field-present-p entry "delete")
            (setf (gethash key-id last-operations) :delete)
            (progn
              (when (eq (gethash key-id last-operations) :write)
                (return-from eest-trie-test-case-overwrites-key-p t))
              (setf (gethash key-id last-operations) :write))))))
  nil)

(defun eest-trie-test-case-summary (cases)
  (let* ((entries-by-case
           (mapcar (lambda (case)
                     (fixture-required-field case "entries"))
                   cases))
         (secure-flags
           (mapcar (lambda (case)
                     (not (null (fixture-object-field case "secure"))))
                   cases))
         (entry-counts
           (mapcar #'length entries-by-case))
         (delete-counts
           (mapcar (lambda (entries)
                     (count-if (lambda (entry)
                                 (fixture-field-present-p entry "delete"))
                               entries))
                   entries-by-case))
         (write-counts
           (mapcar #'- entry-counts delete-counts))
         (secure-write-counts
           (loop for secure-p in secure-flags
                 for count in write-counts
                 when secure-p
                   collect count))
         (plain-write-counts
           (loop for secure-p in secure-flags
                 for count in write-counts
                 unless secure-p
                   collect count))
         (secure-delete-counts
           (loop for secure-p in secure-flags
                 for count in delete-counts
                 when secure-p
                   collect count))
         (plain-delete-counts
           (loop for secure-p in secure-flags
                 for count in delete-counts
                 unless secure-p
                   collect count))
         (non-empty-root-flags
           (mapcar (lambda (case)
                     (not (string= +empty-trie-root-hex+
                                    (fixture-required-field case "root"))))
                   cases))
         (secure-non-empty-root-count
           (loop for secure-p in secure-flags
                 for non-empty-p in non-empty-root-flags
                 count (and secure-p non-empty-p)))
         (plain-non-empty-root-count
           (loop for secure-p in secure-flags
                 for non-empty-p in non-empty-root-flags
                 count (and (not secure-p) non-empty-p)))
         (tries
           (mapcar #'run-eest-trie-test-case cases))
         (root-shapes
           (mapcar #'trie-fixture-root-shape tries))
         (secure-branch-root-count
           (loop for secure-p in secure-flags
                 for shape in root-shapes
                 count (and secure-p
                            (string= "branch" shape))))
         (secure-extension-root-count
           (loop for secure-p in secure-flags
                 for shape in root-shapes
                 count (and secure-p
                            (string= "extension" shape))))
         (extension-child-reference-kinds
           (loop for shape in root-shapes
                 for trie in tries
                 when (string= "extension" shape)
                   collect (trie-fixture-extension-child-reference-kind trie)))
         (secure-extension-child-reference-kinds
           (loop for secure-p in secure-flags
                 for shape in root-shapes
                 for trie in tries
                 when (and secure-p
                           (string= "extension" shape))
                   collect (trie-fixture-extension-child-reference-kind trie)))
         (branch-child-reference-kinds
           (loop for shape in root-shapes
                 for trie in tries
                 when (string= "branch" shape)
                   append
                   (mapcar (lambda (index)
                             (trie-fixture-root-child-reference-kind
                             trie
                             index))
                           (trie-fixture-root-children trie))))
         (secure-branch-child-reference-kinds
           (loop for secure-p in secure-flags
                 for shape in root-shapes
                 for trie in tries
                 when (and secure-p
                           (string= "branch" shape))
                   append
                   (mapcar (lambda (index)
                             (trie-fixture-root-child-reference-kind
                              trie
                              index))
                           (trie-fixture-root-children trie))))
         (branch-value-root-count
           (loop for shape in root-shapes
                 for trie in tries
                 count (and (string= "branch" shape)
                            (not (blank-string-p
                                  (trie-fixture-root-value trie))))))
         (branch-value-zero-child-root-count
           (loop for shape in root-shapes
                 for trie in tries
                 count (and (string= "branch" shape)
                            (not (blank-string-p
                                  (trie-fixture-root-value trie)))
                            (member 0
                                    (trie-fixture-root-children trie)))))
         (empty-key-delete-non-empty-root-count
           (loop for entries in entries-by-case
                 for non-empty-p in non-empty-root-flags
                 count (and non-empty-p
                            (some #'eest-trie-test-empty-key-delete-p
                                  entries))))
         (branch-child-delete-value-leaf-count
           (loop for entries in entries-by-case
                 for non-empty-p in non-empty-root-flags
                 for shape in root-shapes
                 for trie in tries
                 count (and non-empty-p
                            (string= "leaf" shape)
                            (not (blank-string-p
                                  (trie-fixture-root-value trie)))
                            (some #'eest-trie-test-non-empty-key-delete-p
                                  entries))))
         (branch-delete-root-count
           (loop for delete-count in delete-counts
                 for shape in root-shapes
                 count (and (plusp delete-count)
                            (string= "branch" shape))))
         (overwritten-key-case-count
           (count-if #'eest-trie-test-case-overwrites-key-p cases))
         (non-empty-delete-root-count
           (loop for delete-count in delete-counts
                 for non-empty-p in non-empty-root-flags
                 count (and (plusp delete-count) non-empty-p)))
         (secure-non-empty-delete-root-count
           (loop for secure-p in secure-flags
                 for delete-count in delete-counts
                 for non-empty-p in non-empty-root-flags
                 count (and secure-p
                            (plusp delete-count)
                            non-empty-p))))
    (list
     (cons "count" (length cases))
     (cons "names" (mapcar (lambda (case)
                             (fixture-required-field case "name"))
                           cases))
     (cons "secureFlags" secure-flags)
     (cons "secureCaseCount" (count t secure-flags))
     (cons "plainCaseCount" (count nil secure-flags))
     (cons "nonEmptyRootFlags" non-empty-root-flags)
     (cons "secureNonEmptyRootCount" secure-non-empty-root-count)
     (cons "secureBranchRootCount" secure-branch-root-count)
     (cons "secureExtensionRootCount" secure-extension-root-count)
     (cons "plainNonEmptyRootCount" plain-non-empty-root-count)
     (cons "rootShapes" root-shapes)
     (cons "branchRootCount" (count "branch" root-shapes :test #'string=))
     (cons "branchChildReferenceKinds" branch-child-reference-kinds)
     (cons "secureBranchChildReferenceKinds"
           secure-branch-child-reference-kinds)
     (cons "embeddedBranchChildReferenceCount"
           (count "embedded" branch-child-reference-kinds :test #'string=))
     (cons "hashedBranchChildReferenceCount"
           (count "hashed" branch-child-reference-kinds :test #'string=))
     (cons "secureHashedBranchChildReferenceCount"
           (count "hashed"
                  secure-branch-child-reference-kinds
                  :test #'string=))
     (cons "branchValueRootCount" branch-value-root-count)
     (cons "branchValueZeroChildRootCount"
           branch-value-zero-child-root-count)
     (cons "emptyKeyDeleteNonEmptyRootCount"
           empty-key-delete-non-empty-root-count)
     (cons "branchChildDeleteValueLeafCount"
           branch-child-delete-value-leaf-count)
     (cons "branchDeleteRootCount" branch-delete-root-count)
     (cons "overwrittenKeyCaseCount" overwritten-key-case-count)
     (cons "extensionRootCount" (count "extension" root-shapes :test #'string=))
     (cons "extensionChildReferenceKinds" extension-child-reference-kinds)
     (cons "secureExtensionChildReferenceKinds"
           secure-extension-child-reference-kinds)
     (cons "embeddedExtensionChildReferenceCount"
           (count "embedded" extension-child-reference-kinds :test #'string=))
     (cons "hashedExtensionChildReferenceCount"
           (count "hashed" extension-child-reference-kinds :test #'string=))
     (cons "secureHashedExtensionChildReferenceCount"
           (count "hashed"
                  secure-extension-child-reference-kinds
                  :test #'string=))
     (cons "nonEmptyDeleteRootCount" non-empty-delete-root-count)
     (cons "secureNonEmptyDeleteRootCount"
           secure-non-empty-delete-root-count)
     (cons "entryCounts" entry-counts)
     (cons "totalEntryCount" (reduce #'+ entry-counts :initial-value 0))
     (cons "writeEntryCounts" write-counts)
     (cons "totalWriteEntryCount" (reduce #'+ write-counts :initial-value 0))
     (cons "secureWriteEntryCount"
           (reduce #'+ secure-write-counts :initial-value 0))
     (cons "plainWriteEntryCount"
           (reduce #'+ plain-write-counts :initial-value 0))
     (cons "deleteEntryCounts" delete-counts)
     (cons "totalDeleteEntryCount" (reduce #'+ delete-counts :initial-value 0))
     (cons "secureDeleteEntryCount"
           (reduce #'+ secure-delete-counts :initial-value 0))
     (cons "plainDeleteEntryCount"
           (reduce #'+ plain-delete-counts :initial-value 0))
     (cons "roots" (mapcar (lambda (case)
                             (fixture-required-field case "root"))
                           cases)))))

(defun validate-phase-a-eest-trie-test-coverage (cases)
  (let ((summary (eest-trie-test-case-summary cases)))
    (when (zerop (fixture-object-field summary "secureCaseCount"))
      (error "Phase A EEST trie subset must include a secure trie case"))
    (when (zerop (fixture-object-field summary "plainCaseCount"))
      (error "Phase A EEST trie subset must include a plain trie case"))
    (when (zerop (fixture-object-field summary "totalWriteEntryCount"))
      (error "Phase A EEST trie subset must include write entries"))
    (when (zerop (fixture-object-field summary "totalDeleteEntryCount"))
      (error "Phase A EEST trie subset must include delete entries"))
    (when (zerop (fixture-object-field summary "secureWriteEntryCount"))
      (error "Phase A EEST trie subset must include secure trie write entries"))
    (when (zerop (fixture-object-field summary "secureDeleteEntryCount"))
      (error "Phase A EEST trie subset must include secure trie delete entries"))
    (when (zerop (fixture-object-field summary "plainWriteEntryCount"))
      (error "Phase A EEST trie subset must include plain trie write entries"))
    (when (zerop (fixture-object-field summary "plainDeleteEntryCount"))
      (error "Phase A EEST trie subset must include plain trie delete entries"))
    (when (zerop (fixture-object-field summary "secureNonEmptyRootCount"))
      (error "Phase A EEST trie subset must include a non-empty secure trie root"))
    (when (zerop (fixture-object-field summary "secureBranchRootCount"))
      (error "Phase A EEST trie subset must include a replayed secure branch root"))
    (when (zerop (fixture-object-field summary "secureExtensionRootCount"))
      (error "Phase A EEST trie subset must include a replayed secure extension root"))
    (when (zerop (fixture-object-field summary "plainNonEmptyRootCount"))
      (error "Phase A EEST trie subset must include a non-empty plain trie root"))
    (when (zerop (fixture-object-field summary "branchRootCount"))
      (error "Phase A EEST trie subset must include a replayed branch root"))
    (when (zerop (fixture-object-field summary "embeddedBranchChildReferenceCount"))
      (error "Phase A EEST trie subset must include an embedded branch child reference"))
    (when (zerop (fixture-object-field summary "hashedBranchChildReferenceCount"))
      (error "Phase A EEST trie subset must include a hashed branch child reference"))
    (when (zerop (fixture-object-field summary "secureHashedBranchChildReferenceCount"))
      (error "Phase A EEST trie subset must include a secure hashed branch child reference"))
    (when (zerop (fixture-object-field summary "branchValueRootCount"))
      (error "Phase A EEST trie subset must include a branch root value"))
    (when (zerop (fixture-object-field summary "branchValueZeroChildRootCount"))
      (error "Phase A EEST trie subset must include a branch root value with child index 0"))
    (when (zerop (fixture-object-field summary "emptyKeyDeleteNonEmptyRootCount"))
      (error "Phase A EEST trie subset must include an empty-key delete with a non-empty final root"))
    (when (zerop (fixture-object-field summary "branchChildDeleteValueLeafCount"))
      (error "Phase A EEST trie subset must include a branch child delete that preserves a root value leaf"))
    (when (zerop (fixture-object-field summary "branchDeleteRootCount"))
      (error "Phase A EEST trie subset must include a branch-root delete case"))
    (when (zerop (fixture-object-field summary "overwrittenKeyCaseCount"))
      (error "Phase A EEST trie subset must include a duplicate-key overwrite case"))
    (when (zerop (fixture-object-field summary "extensionRootCount"))
      (error "Phase A EEST trie subset must include a replayed extension root"))
    (when (zerop (fixture-object-field summary "embeddedExtensionChildReferenceCount"))
      (error "Phase A EEST trie subset must include an embedded extension child reference"))
    (when (zerop (fixture-object-field summary "hashedExtensionChildReferenceCount"))
      (error "Phase A EEST trie subset must include a hashed extension child reference"))
    (when (zerop (fixture-object-field summary "secureHashedExtensionChildReferenceCount"))
      (error "Phase A EEST trie subset must include a secure hashed extension child reference"))
    (when (zerop (fixture-object-field summary "nonEmptyDeleteRootCount"))
      (error "Phase A EEST trie subset must include a delete case with a non-empty final root"))
    (when (zerop (fixture-object-field summary "secureNonEmptyDeleteRootCount"))
      (error "Phase A EEST trie subset must include a secure delete case with a non-empty final root"))))

(defun trie-fixture-root-shape (trie)
  (let ((root (mpt-root-node trie)))
    (cond
      ((null root) "empty")
      ((typep root 'ethereum-lisp.trie::leaf-node) "leaf")
      ((typep root 'ethereum-lisp.trie::extension-node) "extension")
      ((typep root 'ethereum-lisp.trie::branch-node) "branch")
      (t "unknown"))))

(defun trie-fixture-node-reference-kind (node)
  (let ((reference (ethereum-lisp.trie::node-reference node)))
    (cond
      ((typep reference 'ethereum-lisp.rlp::rlp-list) "embedded")
      ((and (vectorp reference) (= 32 (length reference))) "hashed")
      (t "unknown"))))

(defun trie-fixture-extension-child-reference-kind (trie)
  (let ((root (mpt-root-node trie)))
    (when (typep root 'ethereum-lisp.trie::extension-node)
      (trie-fixture-node-reference-kind
       (ethereum-lisp.trie::extension-node-child root)))))

(defun trie-fixture-root-child-reference-kind (trie index)
  (let ((root (mpt-root-node trie)))
    (when (typep root 'ethereum-lisp.trie::branch-node)
      (let ((child (aref (ethereum-lisp.trie::branch-node-children root)
                         index)))
        (when child
          (trie-fixture-node-reference-kind child))))))

(defun trie-fixture-root-children (trie)
  (let ((root (mpt-root-node trie)))
    (when (typep root 'ethereum-lisp.trie::branch-node)
      (loop for index below 16
            when (aref (ethereum-lisp.trie::branch-node-children root)
                       index)
              collect index))))

(defun trie-fixture-root-path-nibbles (trie)
  (let ((root (mpt-root-node trie)))
    (cond
      ((typep root 'ethereum-lisp.trie::leaf-node)
       (coerce (ethereum-lisp.trie::leaf-node-path root) 'list))
      ((typep root 'ethereum-lisp.trie::extension-node)
       (coerce (ethereum-lisp.trie::extension-node-path root) 'list)))))

(defun trie-fixture-root-value (trie)
  (let ((root (mpt-root-node trie)))
    (cond
      ((typep root 'ethereum-lisp.trie::leaf-node)
       (bytes-to-ascii
        (ethereum-lisp.trie::leaf-node-value root)))
      ((typep root 'ethereum-lisp.trie::branch-node)
       (bytes-to-ascii
        (ethereum-lisp.trie::branch-node-value root))))))

(defun trie-fixture-key (object)
  (or (let ((hex (fixture-object-field object "keyHex")))
        (when hex (hex-to-bytes hex)))
      (ascii-to-bytes (fixture-object-field object "keyAscii"))))

(defun trie-fixture-secure-key-p (case)
  (not (null (fixture-object-field case "secure"))))

(defun trie-fixture-trie-key (case object)
  (let ((key (trie-fixture-key object)))
    (if (trie-fixture-secure-key-p case)
        (keccak-256 key)
        key)))

(defun apply-trie-fixture-operation (trie case operation)
  (let ((op (fixture-object-field operation "op"))
        (key (trie-fixture-trie-key case operation)))
    (cond
      ((string= op "put")
       (mpt-put trie key
                (ascii-to-bytes
                 (fixture-object-field operation "valueAscii"))))
      ((string= op "delete")
       (mpt-delete trie key))
      (t (error "Unknown trie fixture operation: ~A" op)))))

(defun run-trie-fixture-case (case)
  (let ((trie (make-mpt)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-trie-fixture-operation trie case operation))
    trie))

(defun trie-fixture-final-operation-state (case)
  (let ((entries '()))
    (dolist (operation (fixture-object-field case "operations"))
      (let ((key (trie-fixture-trie-key case operation))
            (op (fixture-object-field operation "op")))
        (setf entries (remove key entries :key #'car :test #'bytes=))
        (cond
          ((string= op "put")
           (push (cons key
                       (ascii-to-bytes
                        (fixture-object-field operation "valueAscii")))
                 entries))
          ((string= op "delete")
           (push (cons key nil) entries))
          (t (error "Unknown trie fixture operation: ~A" op)))))
    (nreverse entries)))

(defun assert-trie-fixture-final-operation-lookups (trie case)
  (dolist (entry (trie-fixture-final-operation-state case))
    (let ((key (car entry))
          (value (cdr entry)))
      (if value
          (is (bytes= value (mpt-get trie key)))
          (is (null (mpt-get trie key)))))))

(defun assert-trie-fixture-proof-present (trie key expected-value)
  (multiple-value-bind (value present-p)
      (mpt-verify-proof (mpt-root-hash trie)
                        key
                        (mpt-get-proof trie key))
    (is present-p)
    (is (bytes= expected-value value))))

(defun assert-trie-fixture-proof-missing (trie key)
  (multiple-value-bind (value present-p)
      (mpt-verify-proof (mpt-root-hash trie)
                        key
                        (mpt-get-proof trie key))
    (is (null present-p))
    (is (null value))))

(defun assert-trie-fixture-lookups (trie case)
  (dolist (expected (fixture-object-field case "expectedGets"))
    (let ((key (trie-fixture-trie-key case expected))
          (value (ascii-to-bytes (fixture-object-field expected "valueAscii"))))
      (is (bytes= value (mpt-get trie key)))
      (assert-trie-fixture-proof-present trie key value)))
  (dolist (expected (fixture-object-field case "expectedMissing"))
    (let ((key (trie-fixture-trie-key case expected)))
      (is (null (mpt-get trie key)))
      (assert-trie-fixture-proof-missing trie key))))

(deftest trie-empty-root
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (mpt-root-hex (make-mpt)))))

(deftest trie-single-leaf-root-is-deterministic
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (is (string= (mpt-root-hex trie) (mpt-root-hex trie)))
    (is (bytes= (ascii-to-bytes "puppy")
                (mpt-get trie (ascii-to-bytes "dog"))))))

(deftest trie-insertion-order-independent
  (let ((left (make-mpt))
        (right (make-mpt)))
    (dolist (pair '(("do" . "verb") ("dog" . "puppy") ("doge" . "coin") ("horse" . "stallion")))
      (mpt-put left (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (dolist (pair '(("horse" . "stallion") ("doge" . "coin") ("dog" . "puppy") ("do" . "verb")))
      (mpt-put right (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (is (string= (mpt-root-hex left) (mpt-root-hex right)))))

(deftest trie-delete-removes-key-and-collapses-to-empty-root
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (is (bytes= (ascii-to-bytes "puppy")
                (mpt-get trie (ascii-to-bytes "dog"))))
    (mpt-delete trie (ascii-to-bytes "dog"))
    (is (null (mpt-get trie (ascii-to-bytes "dog"))))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (mpt-root-hex trie)))))

(deftest trie-proof-verifies-present-and-missing-keys
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "do") (ascii-to-bytes "verb"))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (mpt-put trie (ascii-to-bytes "horse") (ascii-to-bytes "stallion"))
    (multiple-value-bind (value present-p)
        (mpt-verify-proof
         (make-hash32 (mpt-root-hash trie))
         (ascii-to-bytes "dog")
         (mpt-get-proof trie (ascii-to-bytes "dog")))
      (is present-p)
      (is (bytes= (ascii-to-bytes "puppy") value)))
    (multiple-value-bind (value present-p)
        (mpt-verify-proof
         (mpt-root-hash trie)
         (ascii-to-bytes "cat")
         (mpt-get-proof trie (ascii-to-bytes "cat")))
      (is (null present-p))
      (is (null value)))
    (signals error
      (mpt-verify-proof
       (hash32-bytes (zero-hash32))
       (ascii-to-bytes "dog")
       (mpt-get-proof trie (ascii-to-bytes "dog"))))
    (signals error
      (mpt-verify-proof
       (mpt-root-hash trie)
       (ascii-to-bytes "dog")
       (append (mpt-get-proof trie (ascii-to-bytes "dog"))
               (mpt-get-proof trie (ascii-to-bytes "horse")))))))

(deftest trie-proof-verifies-empty-root-absence
  (multiple-value-bind (value present-p)
      (mpt-verify-proof
       (hash32-bytes +empty-trie-hash+)
       (ascii-to-bytes "dog")
       (mpt-get-proof (make-mpt) (ascii-to-bytes "dog")))
    (is (null present-p))
    (is (null value))))

(deftest trie-fixture-shape-validation-rejects-ambiguous-operations
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "missing-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "valueAscii" "value")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "ambiguous-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0x00")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "put-without-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "missing-entry-with-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog"))))
           (cons "expectedMissing"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))))))

(deftest trie-fixture-metadata-validation-rejects-wrapper-drift
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "seed")
           (cons "unexpected" t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed")))))))

(deftest trie-fixture-shape-validation-rejects-malformed-expected-fields
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-root")
           (cons "expectedRoot" "0x1234")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-shape")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "short")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-secure")
           (cons "secure" "yes")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "child-reference-on-leaf")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedChildReference" "embedded")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-child-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildren" (list 0 16))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-path-nibble")
           (cons "expectedRoot"
                 "0x1da465b71da985f1e07e3ed8dcd9e678546164ef2b17fb5c46c678fd91429de3")
           (cons "expectedShape" "extension")
           (cons "expectedRootPathNibbles" (list 6 16))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "do")
                             (cons "valueAscii" "v")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-child-reference")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1" "embedded")
                       (cons "01" "hashed")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x10")
                             (cons "valueAscii" "left"))))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-expected-get-key")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))
                       (list (cons "keyHex" "0x646f67")
                             (cons "valueAscii" "hound")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "conflicting-expected-lookup-key")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedMissing"
                 (list (list (cons "keyHex" "0x646f67")))))))

(deftest trie-fixture-shape-validation-rejects-unknown-fields
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-case-field")
           (cons "unexpected" t)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-case-field")
           (cons "name" "duplicate-case-field-shadow")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons "valueHex" "0x01")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons "keyAscii" "cat")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-get-field")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")
                             (cons "root" t)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-get-field")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")
                             (cons "valueAscii" "shadow")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-missing-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog"))))
           (cons "expectedMissing"
                 (list (list (cons "keyAscii" "dog")
                             (cons "proof" nil))))))))

(deftest trie-fixture-tag-validation-rejects-duplicates
  (signals error
    (validate-trie-fixture-case-tags
     (list (cons "name" "duplicate-tag")
           (cons "tags" (list "leaf-root" "leaf-root")))
     (make-hash-table :test 'equal))))

(deftest trie-fixture-coverage-validation-requires-secure-root-shapes
  (let* ((fixture (parse-json
                   (fixture-file-string +trie-vector-fixture-path+)))
         (cases (fixture-object-field fixture "cases")))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-branch-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-extension-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-single-leaf"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-delete-last-entry-empty-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-required-case-names
       (remove-if
        (lambda (case)
          (string= "root-branch-mixed-child-references"
                   (fixture-object-field case "name")))
        cases)))
    (let ((+trie-fixture-required-case-names+
            '("single-leaf" "single-leaf")))
      (signals error
        (validate-trie-fixture-required-case-names cases)))))

(deftest optional-eest-trie-test-root-discovery
  (with-execution-spec-tests-trie-test-root (root)
    (is (probe-file root))))

(deftest eest-trie-test-root-json-discovery
  (let* ((root (execution-spec-tests-trie-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-trie-test-root-json-paths root)))
    (is (= 3 (length paths)))
    (is (equal '("phase-a-secureTrie.json"
                 "phase-a-trie-multi.json"
                 "phase-a-trie-sample.json")
               (eest-trie-test-root-file-names root)))
    (is (string= (namestring (truename +eest-trie-test-sample-path+))
                 (namestring (truename (third paths)))))
    (is (eest-trie-test-secure-path-p
         (truename +eest-trie-test-secure-sample-path+)))))

(deftest eest-trie-test-root-json-discovery-rejects-empty-roots
  (signals error
    (eest-trie-test-root-json-paths
     (execution-spec-tests-trie-test-root
      "tests/fixtures/geth-spec-tests-root/"))))

(deftest eest-trie-test-file-shape-validation
  (let* ((cases (load-eest-trie-test-file +eest-trie-test-sample-path+))
         (case (first cases))
         (entries (fixture-required-field case "entries"))
         (entry (first entries))
         (delete-entry (second entries))
         (hex-entry (third entries))
         (hex-delete-entry (fourth entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 1 (length cases)))
    (is (string= "phase-a-trie-sample"
                 (fixture-object-field case "name")))
    (is (= 4 (length entries)))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (string= "puppy"
                 (fixture-object-field entry "value")))
    (is (string= "dog"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= "0x646f67"
                 (fixture-object-field hex-entry "key")))
    (is (string= "0x7075707079"
                 (fixture-object-field hex-entry "value")))
    (is (bytes= (ascii-to-bytes "dog")
                (eest-trie-test-byte-string
                 (fixture-object-field hex-entry "key")
                 "hex sample key")))
    (is (bytes= (ascii-to-bytes "puppy")
                (eest-trie-test-byte-string
                 (fixture-object-field hex-entry "value")
                 "hex sample value")))
    (is (fixture-object-field hex-delete-entry "delete"))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((cases (load-eest-trie-test-file +eest-trie-test-secure-sample-path+))
         (case (first cases))
         (delete-case (second cases))
         (delete-branch-child-case (third cases))
         (extension-case (fourth cases))
         (insert-case (fifth cases))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 5 (length cases)))
    (is (string= "phase-a-secure-branch"
                 (fixture-object-field case "name")))
    (is (fixture-object-field case "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie)))
    (is (string= "phase-a-secure-extension"
                 (fixture-object-field extension-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field extension-case "root")))
    (is (string= "phase-a-secure-delete"
                 (fixture-object-field delete-case "name")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field delete-case "root")))
    (is (string= "phase-a-secure-delete-branch-child"
                 (fixture-object-field delete-branch-child-case "name")))
    (is (string= "0xc8fb1ca12e912e15bb7db6d06ae4967dd3b59a5903f0306dd797dcaab6afcb3b"
                 (fixture-object-field delete-branch-child-case "root")))
    (is (string= "phase-a-secure-insert"
                 (fixture-object-field insert-case "name")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field insert-case "root"))))
  (let* ((case (normalize-eest-trie-test-case
                "empty-value-delete"
                (list (cons "in" (list (list "dog" "")))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (entry (first (fixture-required-field case "entries"))))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (fixture-object-field entry "delete")))
  (let* ((case (normalize-eest-trie-test-case
                "object-form-entry"
                (list (cons "in" (list (cons "dog" "puppy")))
                      (cons "root"
                            "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
         (entry (first (fixture-required-field case "entries")))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (string= "puppy"
                 (fixture-object-field entry "value")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "object-form-null-delete"
                (list (cons "in" (list (cons "cat" nil)
                                       (cons "dog" "puppy")))
                      (cons "root"
                            "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
         (entries (fixture-required-field case "entries"))
         (delete-entry (first entries))
         (put-entry (second entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "cat"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= "dog"
                 (fixture-object-field put-entry "key")))
    (is (string= "puppy"
                 (fixture-object-field put-entry "value")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "secure-entry"
                (list (cons "in" (list (list "dog" "puppy")))
                      (cons "secure" t)
                      (cons "root"
                            "ff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"))))
         (trie (assert-eest-trie-test-case-root case)))
    (is (fixture-object-field case "secure"))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (fixture-object-field
                (normalize-eest-trie-test-case
                 "uppercase-root"
                 (list (cons "in" nil)
                       (cons "root"
                             "0X56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421")))
                "root")))
  (let* ((case (normalize-eest-trie-test-case
                "uppercase-entry-bytes"
                (list (cons "in" (list (list "0X646F67" "0X7075707079")
                                       (list "0X646F67" "0X")))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (entries (fixture-required-field case "entries"))
         (put-entry (first entries))
         (delete-entry (second entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "0x646f67"
                 (fixture-object-field put-entry "key")))
    (is (string= "0x7075707079"
                 (fixture-object-field put-entry "value")))
    (is (string= "0x646f67"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (is (handler-case
          (progn
            (assert-eest-trie-test-case-root
             (normalize-eest-trie-test-case
              "wrong-root-message"
              (list (cons "in" (list (list "dog" "puppy")))
                    (cons "root"
                          "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case wrong-root-message root mismatch"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "missing-root"
     (list (cons "in" nil))))
  (signals error
    (normalize-eest-trie-test-case
     "missing-in"
     (list (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry"
     (list (cons "in" (list (list "dog")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-value"
     (list (cons "in" (list (list "dog" 1)))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "duplicate-object-entry"
     (list (cons "in" (list (cons "dog" "puppy")
                            (cons "dog" "hound")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "duplicate-object-entry-normalized"
     (list (cons "in" (list (cons "dog" "puppy")
                            (cons "0x646f67" "hound")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-key-hex"
     (list (cons "in" (list (list "0x0" "puppy")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (is (handler-case
          (progn
            (normalize-eest-trie-test-case
             "bad-entry-key-message"
             (list (cons "in" (list (list "dog" "puppy")
                                    (list "0x0" "puppy")))
                   (cons "root"
                         "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case bad-entry-key-message in entry 1 key"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-value-hex"
     (list (cons "in" (list (list "dog" "0x0")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "non-string-root"
     (list (cons "in" nil)
           (cons "root" 1))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-root"
     (list (cons "in" nil)
           (cons "root" "0x1234"))))
  (is (handler-case
          (progn
            (normalize-eest-trie-test-case
             "bad-root-message"
             (list (cons "in" nil)
                   (cons "root" "0x1234")))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case bad-root-message root must be a 32-byte hex hash"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "unknown-field"
     (list (cons "in" nil)
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "unexpected" t))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-secure"
     (list (cons "in" nil)
           (cons "secure" "yes")
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (validate-eest-trie-test-file-case-names nil "inline-empty"))
  (signals error
    (validate-eest-trie-test-file-case-names
     (list (cons "duplicate-case"
                 (list (cons "in" nil)
                       (cons "root"
                             "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")))
           (cons "duplicate-case"
                 (list (cons "in" nil)
                       (cons "root"
                             "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
     "inline")))

(deftest eest-trie-test-root-case-loading
  (let* ((root (execution-spec-tests-trie-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-trie-test-root-cases root))
         (selected-cases
           (load-phase-a-eest-trie-test-root-cases root))
         (summary (eest-trie-test-case-summary selected-cases)))
    (is (= 22 (length cases)))
    (is (= 21 (length selected-cases)))
    (is (equal '("phase-a-secureTrie.json/phase-a-secure-branch"
                 "phase-a-secureTrie.json/phase-a-secure-delete"
                 "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
                 "phase-a-secureTrie.json/phase-a-secure-extension"
                 "phase-a-secureTrie.json/phase-a-secure-insert"
                 "phase-a-trie-multi.json/alpha"
                 "phase-a-trie-multi.json/beta"
                 "phase-a-trie-multi.json/branch"
                 "phase-a-trie-multi.json/branch-value"
                 "phase-a-trie-multi.json/branch-value-zero-child"
                 "phase-a-trie-multi.json/delete-branch-child"
                 "phase-a-trie-multi.json/delete-branch-value"
                 "phase-a-trie-multi.json/delete-collapse"
                 "phase-a-trie-multi.json/delete-missing-branch-child"
                 "phase-a-trie-multi.json/delete-missing-extension-child"
                 "phase-a-trie-multi.json/delete-nested-branch-value"
                 "phase-a-trie-multi.json/delete-prefix-branch-value"
                 "phase-a-trie-multi.json/duplicate-overwrite"
                 "phase-a-trie-multi.json/embedded-extension"
                 "phase-a-trie-multi.json/extension"
                 "phase-a-trie-multi.json/mixed-branch-refs"
                 "phase-a-trie-sample.json")
               (mapcar (lambda (case)
                         (fixture-object-field case "name"))
                       cases)))
    (is (fixture-object-field (first cases) "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field (first cases) "root")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 21 cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-branch"
                 (fixture-object-field (first selected-cases) "name")))
    (is (fixture-object-field (first selected-cases) "secure"))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-delete"
                 (fixture-object-field (second selected-cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
                 (fixture-object-field (third selected-cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-extension"
                 (fixture-object-field (fourth selected-cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-insert"
                 (fixture-object-field (fifth selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/alpha"
                 (fixture-object-field (sixth selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/branch"
                 (fixture-object-field (seventh selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/branch-value"
                 (fixture-object-field (eighth selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/branch-value-zero-child"
                 (fixture-object-field (ninth selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-branch-child"
                 (fixture-object-field (tenth selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-branch-value"
                 (fixture-object-field (nth 10 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-collapse"
                 (fixture-object-field (nth 11 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-missing-branch-child"
                 (fixture-object-field (nth 12 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-missing-extension-child"
                 (fixture-object-field (nth 13 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-nested-branch-value"
                 (fixture-object-field (nth 14 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/delete-prefix-branch-value"
                 (fixture-object-field (nth 15 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/duplicate-overwrite"
                 (fixture-object-field (nth 16 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/embedded-extension"
                 (fixture-object-field (nth 17 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/extension"
                 (fixture-object-field (nth 18 selected-cases) "name")))
    (is (string= "phase-a-trie-multi.json/mixed-branch-refs"
                 (fixture-object-field (nth 19 selected-cases) "name")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 20 selected-cases) "name")))
    (is (= 21 (fixture-object-field summary "count")))
    (is (equal '("phase-a-secureTrie.json/phase-a-secure-branch"
                 "phase-a-secureTrie.json/phase-a-secure-delete"
                 "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
                 "phase-a-secureTrie.json/phase-a-secure-extension"
                 "phase-a-secureTrie.json/phase-a-secure-insert"
                 "phase-a-trie-multi.json/alpha"
                 "phase-a-trie-multi.json/branch"
                 "phase-a-trie-multi.json/branch-value"
                 "phase-a-trie-multi.json/branch-value-zero-child"
                 "phase-a-trie-multi.json/delete-branch-child"
                 "phase-a-trie-multi.json/delete-branch-value"
                 "phase-a-trie-multi.json/delete-collapse"
                 "phase-a-trie-multi.json/delete-missing-branch-child"
                 "phase-a-trie-multi.json/delete-missing-extension-child"
                 "phase-a-trie-multi.json/delete-nested-branch-value"
                 "phase-a-trie-multi.json/delete-prefix-branch-value"
                 "phase-a-trie-multi.json/duplicate-overwrite"
                 "phase-a-trie-multi.json/embedded-extension"
                 "phase-a-trie-multi.json/extension"
                 "phase-a-trie-multi.json/mixed-branch-refs"
                 "phase-a-trie-sample.json")
               (fixture-object-field summary "names")))
    (is (equal '(t t t t t nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil)
               (fixture-object-field summary "secureFlags")))
    (is (= 5 (fixture-object-field summary "secureCaseCount")))
    (is (= 16 (fixture-object-field summary "plainCaseCount")))
    (is (equal '(t nil t t t t t t t t t t t t t t t t t t nil)
               (fixture-object-field summary "nonEmptyRootFlags")))
    (is (= 4 (fixture-object-field summary "secureNonEmptyRootCount")))
    (is (= 1 (fixture-object-field summary "secureBranchRootCount")))
    (is (= 1 (fixture-object-field summary "secureExtensionRootCount")))
    (is (= 15 (fixture-object-field summary "plainNonEmptyRootCount")))
    (is (equal '("branch" "empty" "leaf" "extension" "leaf" "leaf"
                 "branch" "branch" "branch" "leaf" "leaf" "extension" "branch"
                 "extension" "extension" "extension" "leaf" "extension" "extension"
                 "branch" "empty")
               (fixture-object-field summary "rootShapes")))
    (is (= 6 (fixture-object-field summary "branchRootCount")))
    (is (equal '("hashed" "hashed" "embedded" "embedded" "embedded"
                 "embedded" "embedded" "embedded" "hashed" "embedded")
               (fixture-object-field summary "branchChildReferenceKinds")))
    (is (equal '("hashed" "hashed")
               (fixture-object-field summary "secureBranchChildReferenceKinds")))
    (is (= 7 (fixture-object-field summary "embeddedBranchChildReferenceCount")))
    (is (= 3 (fixture-object-field summary "hashedBranchChildReferenceCount")))
    (is (= 2 (fixture-object-field summary "secureHashedBranchChildReferenceCount")))
    (is (= 2 (fixture-object-field summary "branchValueRootCount")))
    (is (= 1 (fixture-object-field summary "branchValueZeroChildRootCount")))
    (is (= 1 (fixture-object-field summary "emptyKeyDeleteNonEmptyRootCount")))
    (is (= 2 (fixture-object-field summary "branchChildDeleteValueLeafCount")))
    (is (= 1 (fixture-object-field summary "branchDeleteRootCount")))
    (is (= 1 (fixture-object-field summary "overwrittenKeyCaseCount")))
    (is (= 7 (fixture-object-field summary "extensionRootCount")))
    (is (equal '("hashed" "embedded" "hashed" "embedded" "embedded" "embedded" "hashed")
               (fixture-object-field summary "extensionChildReferenceKinds")))
    (is (equal '("hashed")
               (fixture-object-field summary "secureExtensionChildReferenceKinds")))
    (is (= 4 (fixture-object-field summary "embeddedExtensionChildReferenceCount")))
    (is (= 3 (fixture-object-field summary "hashedExtensionChildReferenceCount")))
    (is (= 1 (fixture-object-field summary "secureHashedExtensionChildReferenceCount")))
    (is (= 8 (fixture-object-field summary "nonEmptyDeleteRootCount")))
    (is (= 1 (fixture-object-field summary "secureNonEmptyDeleteRootCount")))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (remove (third selected-cases) selected-cases)))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (remove (fourth selected-cases) selected-cases)))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (remove (ninth selected-cases) selected-cases)))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (remove (nth 12 selected-cases) selected-cases)))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (remove (nth 16 selected-cases) selected-cases)))
    (is (equal '(2 2 3 2 1 1 2 2 2 3 3 4 3 4 4 4 2 2 4 2 4)
               (fixture-object-field summary "entryCounts")))
    (is (= 56 (fixture-object-field summary "totalEntryCount")))
    (is (equal '(2 1 2 2 1 1 2 2 2 2 2 3 2 3 3 3 2 2 4 2 2)
               (fixture-object-field summary "writeEntryCounts")))
    (is (= 45 (fixture-object-field summary "totalWriteEntryCount")))
    (is (= 8 (fixture-object-field summary "secureWriteEntryCount")))
    (is (= 37 (fixture-object-field summary "plainWriteEntryCount")))
    (is (equal '(0 1 1 0 0 0 0 0 0 1 1 1 1 1 1 1 0 0 0 0 2)
               (fixture-object-field summary "deleteEntryCounts")))
    (is (= 11 (fixture-object-field summary "totalDeleteEntryCount")))
    (is (= 2 (fixture-object-field summary "secureDeleteEntryCount")))
    (is (= 9 (fixture-object-field summary "plainDeleteEntryCount")))
    (is (equal '("0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 "0xc8fb1ca12e912e15bb7db6d06ae4967dd3b59a5903f0306dd797dcaab6afcb3b"
                 "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5"
                 "0x322d957ebcabf5ba295218b9b8920a905f7da6078010c2228989ebcf004e43d8"
                 "0x14aaab8c1f35029628b1191bc6f79cf782ded044f792bf8071a0c1dda3c17da9"
                 "0xdecd353bef3878c819cdb73943e0a744d14551d9626f656c4baca465e5db165c"
                 "0xae9b7371f5ef144daa2780a50feb85d5918708e10357eb25c275cc2562f219d4"
                 "0x779db3986dd4f38416bfde49750ef7b13c6ecb3e2221620bcad9267e94604d36"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5"
                 "0xef7b2fe20f5d2c30c46ad4d83c39811bcbf1721aef2e805c0e107947320888b6"
                 "0xf803dfcb7e8f1afd45e88eedb4699a7138d6c07b71243d9ae9bff720c99925f9"
                 "0xc7615a9d094af6bb896a53d59877b9aa6db39b5f2184582aebda3c7dff53d843"
                 "0x1b8a768e0c5ca7d00a88b634464e25599c849977aefed10eb514fc03a9c4c2eb"
                 "0x1da465b71da985f1e07e3ed8dcd9e678546164ef2b17fb5c46c678fd91429de3"
                 "0x5991bb8c6514148a29db676a14ac506cd2cd5775ace63c30a4fe457715e9ac84"
                 "0x4f558f208941283dc0b60b900277073b03079edc0936d703718f88bf511f715d"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
               (fixture-object-field summary "roots")))
    (is (string= "phase-a-trie-multi.json/alpha"
                 (eest-trie-root-case-name root
                                           (second
                                            (eest-trie-test-root-json-paths
                                             root))
                                           "alpha"
                                           nil)))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("missing-trie.json")))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("phase-a-trie-sample.json" "phase-a-trie-sample.json")))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("")))
    (validate-eest-trie-selector-list
     +phase-a-eest-trie-test-case-names+)
    (signals error
      (validate-eest-trie-selector-list nil))
    (signals error
      (validate-eest-trie-selector-list "phase-a-trie-sample.json"))
    (signals error
      (validate-eest-trie-selector-list '(42)))
    (signals error
      (validate-eest-trie-selector-list '("")))
    (signals error
      (validate-eest-trie-selector-list '("bare-case-name")))
    (signals error
      (validate-eest-trie-selector-list '("../escape.json")))
    (signals error
      (validate-eest-trie-selector-list '("/absolute.json")))
    (signals error
      (validate-eest-trie-selector-list '("dir//case.json")))
    (signals error
      (validate-eest-trie-selector-list '(".json/case")))
    (signals error
      (validate-eest-trie-selector-list '("dir/.json/case")))
    (signals error
      (validate-eest-trie-selector-list '("case.jsonx/name")))
    (signals error
      (validate-eest-trie-selector-list '("case.json/")))
    (signals error
      (validate-eest-trie-selector-list '("case.json//name")))
    (signals error
      (validate-eest-trie-selector-list '("case.json/name/extra")))
    (signals error
      (validate-eest-trie-selector-list
       '("phase-a-trie-sample.json" "phase-a-trie-sample.json")))
    (signals error
      (validate-eest-trie-test-root-case-names
       (append cases (list (first cases)))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (second cases)
        (third cases)
        (fourth cases)
        (sixth cases)
        (seventh cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases)
        (nth 12 cases)
        (nth 13 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (first cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (normalize-eest-trie-test-case
         "secure-empty"
         (list (cons "in" nil)
               (cons "secure" t)
               (cons "root"
                     "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (seventh cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases)
        (nth 12 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (seventh cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (seventh cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (normalize-eest-trie-test-case
         "plain-delete-only"
         (list (cons "in" (list (list "dog" nil)))
               (cons "root"
                     "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (normalize-eest-trie-test-case
         "plain-write-only"
         (list (cons "in" (list (list "dog" "puppy")))
               (cons "root"
                     "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))))))

(deftest optional-phase-a-eest-trie-test-root-vectors
  (with-execution-spec-tests-trie-test-root (root)
    (dolist (case (load-phase-a-eest-trie-test-root-cases root))
      (assert-eest-trie-test-case-root case))))

(deftest trie-fixture-vectors
  (let* ((fixture (parse-json
                   (fixture-file-string +trie-vector-fixture-path+)))
         (cases (fixture-object-field fixture "cases")))
    (validate-trie-fixture-metadata fixture)
    (validate-trie-fixture-cases cases)
    (validate-trie-fixture-required-case-names cases)
    (dolist (case cases)
      (let ((trie (run-trie-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (mpt-root-hex trie)))
        (is (string= (fixture-object-field case "expectedShape")
                     (trie-fixture-root-shape trie)))
        (let ((reference-kind
                (fixture-object-field case "expectedChildReference")))
          (when reference-kind
            (is (string= reference-kind
                         (trie-fixture-extension-child-reference-kind
                          trie)))))
        (let ((children
                (fixture-object-field case "expectedRootChildren")))
          (when children
            (is (equal children
                       (trie-fixture-root-children trie)))))
        (let ((child-references
                (fixture-object-field case "expectedRootChildReferences")))
          (when child-references
            (dolist (expected child-references)
              (is (string=
                   (cdr expected)
                   (trie-fixture-root-child-reference-kind
                    trie
                    (parse-integer (car expected))))))))
        (let ((path-nibbles
                (fixture-object-field case "expectedRootPathNibbles")))
          (when path-nibbles
            (is (equal path-nibbles
                       (trie-fixture-root-path-nibbles trie)))))
        (let ((branch-value
                (fixture-object-field case "expectedRootValueAscii")))
          (when branch-value
            (is (string= branch-value
                         (trie-fixture-root-value trie)))))
        (assert-trie-fixture-final-operation-lookups trie case)
        (assert-trie-fixture-lookups trie case)))))
