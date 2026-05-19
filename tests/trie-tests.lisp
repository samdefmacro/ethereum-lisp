(in-package #:ethereum-lisp.test)

(defparameter +trie-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/trie-vectors.json")

(defparameter +trie-vector-fixture-format+
  "ethereum-lisp/trie-vectors-v1")

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
      (validate-trie-fixture-expected-lookup expected name "expectedMissing"))))

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
