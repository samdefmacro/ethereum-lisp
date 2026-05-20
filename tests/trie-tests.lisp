(in-package #:ethereum-lisp.test)

(defparameter +trie-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/trie-vectors.json")

(defparameter +trie-vector-fixture-format+
  "ethereum-lisp/trie-vectors-v1")

(defparameter +eest-trie-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-trie-sample.json")

(defparameter +eest-trie-test-secure-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-secureTrie.json")

(defparameter +phase-a-eest-trie-test-case-names+
  '("phase-a-secureTrie.json"
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
    "lookup-assertions"))

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
    "lookup-assertions"))

(defparameter +trie-fixture-root-shapes+
  '("empty" "leaf" "extension" "branch"))

(defparameter +trie-fixture-child-reference-kinds+
  '("embedded" "hashed"))

(defparameter +trie-fixture-case-fields+
  '("name"
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
        (seen-tags (make-hash-table :test #'equal)))
    (dolist (case cases)
      (unless (listp case)
        (error "Trie fixture case must be a JSON object"))
      (validate-trie-fixture-case-name case seen-names)
      (validate-trie-fixture-case-tags case seen-tags))
    (dolist (tag +trie-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "Trie fixture is missing required coverage tag ~A" tag)))))

(defun validate-trie-fixture-cases (cases)
  (validate-trie-fixture-case-coverage cases)
  (dolist (case cases)
    (validate-trie-fixture-case-shape case)))

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
      (let ((key (car entry)))
        (when (gethash key seen)
          (error "EEST trie test case ~A in object has duplicate key ~A"
                 case-name
                 key))
        (setf (gethash key seen) t))))
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
       (let ((actual (mpt-get trie (hex-to-bytes key-id))))
         (if expected
             (unless (bytes= expected actual)
               (error "EEST trie test case ~A lookup mismatch for key ~A"
                      name
                      key-id))
             (when actual
               (error "EEST trie test case ~A expected missing key ~A"
                      name
                      key-id)))))
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
  (unless names
    (error "EEST trie selector list must not be empty"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (when (blank-string-p name)
        (error "EEST trie selector name must be present"))
      (when (gethash name seen)
        (error "EEST trie selector list has duplicate name ~A"
               name))
      (setf (gethash name seen) t))))

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
           (mapcar #'- entry-counts delete-counts)))
    (list
     (cons "count" (length cases))
     (cons "names" (mapcar (lambda (case)
                             (fixture-required-field case "name"))
                           cases))
     (cons "secureFlags" secure-flags)
     (cons "secureCaseCount" (count t secure-flags))
     (cons "plainCaseCount" (count nil secure-flags))
     (cons "entryCounts" entry-counts)
     (cons "totalEntryCount" (reduce #'+ entry-counts :initial-value 0))
     (cons "writeEntryCounts" write-counts)
     (cons "totalWriteEntryCount" (reduce #'+ write-counts :initial-value 0))
     (cons "deleteEntryCounts" delete-counts)
     (cons "totalDeleteEntryCount" (reduce #'+ delete-counts :initial-value 0))
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
      (error "Phase A EEST trie subset must include delete entries"))))

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

(defun apply-trie-fixture-operation (trie operation)
  (let ((op (fixture-object-field operation "op"))
        (key (trie-fixture-key operation)))
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
      (apply-trie-fixture-operation trie operation))
    trie))

(defun trie-fixture-final-operation-state (case)
  (let ((entries '()))
    (dolist (operation (fixture-object-field case "operations"))
      (let ((key (trie-fixture-key operation))
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

(defun assert-trie-fixture-lookups (trie case)
  (dolist (expected (fixture-object-field case "expectedGets"))
    (is (bytes= (ascii-to-bytes (fixture-object-field expected "valueAscii"))
                (mpt-get trie (trie-fixture-key expected)))))
  (dolist (expected (fixture-object-field case "expectedMissing"))
    (is (null (mpt-get trie (trie-fixture-key expected))))))

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
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 1 (length cases)))
    (is (string= "phase-a-secure"
                 (fixture-object-field case "name")))
    (is (fixture-object-field case "secure"))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
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
    (is (= 4 (length cases)))
    (is (= 2 (length selected-cases)))
    (is (equal '("phase-a-secureTrie.json"
                 "phase-a-trie-multi.json/alpha"
                 "phase-a-trie-multi.json/beta"
                 "phase-a-trie-sample.json")
               (mapcar (lambda (case)
                         (fixture-object-field case "name"))
                       cases)))
    (is (fixture-object-field (first cases) "secure"))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field (first cases) "root")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (fourth cases) "name")))
    (is (string= "phase-a-secureTrie.json"
                 (fixture-object-field (first selected-cases) "name")))
    (is (fixture-object-field (first selected-cases) "secure"))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (second selected-cases) "name")))
    (is (= 2 (fixture-object-field summary "count")))
    (is (equal '("phase-a-secureTrie.json"
                 "phase-a-trie-sample.json")
               (fixture-object-field summary "names")))
    (is (equal '(t nil)
               (fixture-object-field summary "secureFlags")))
    (is (= 1 (fixture-object-field summary "secureCaseCount")))
    (is (= 1 (fixture-object-field summary "plainCaseCount")))
    (is (equal '(1 4)
               (fixture-object-field summary "entryCounts")))
    (is (= 5 (fixture-object-field summary "totalEntryCount")))
    (is (equal '(1 2)
               (fixture-object-field summary "writeEntryCounts")))
    (is (= 3 (fixture-object-field summary "totalWriteEntryCount")))
    (is (equal '(0 2)
               (fixture-object-field summary "deleteEntryCounts")))
    (is (= 2 (fixture-object-field summary "totalDeleteEntryCount")))
    (is (equal '("0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
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
      (validate-eest-trie-selector-list '("")))
    (signals error
      (validate-eest-trie-selector-list
       '("phase-a-trie-sample.json" "phase-a-trie-sample.json")))
    (signals error
      (validate-eest-trie-test-root-case-names
       (append cases (list (first cases)))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (fourth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (first cases))))
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
