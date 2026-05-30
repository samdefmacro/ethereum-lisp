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
    "phase-a-secureTrie.json/phase-a-secure-branch-child-branch"
    "phase-a-secureTrie.json/phase-a-secure-branch-child-extension"
    "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
    "phase-a-secureTrie.json/phase-a-secure-delete"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-child-keeps-branch"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-sibling-collapses-to-extension"
    "phase-a-secureTrie.json/phase-a-secure-delete-extension-child"
    "phase-a-secureTrie.json/phase-a-secure-duplicate-overwrite"
    "phase-a-secureTrie.json/phase-a-secure-extension"
    "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
    "phase-a-secureTrie.json/phase-a-secure-insert"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence"
    "phase-a-secureTrie.json/phase-a-secure-missing-delete-branch"
    "phase-a-secureTrie.json/phase-a-secure-missing-delete-extension"
    "phase-a-secureTrie.json/phase-a-secure-object-form-branch"
    "phase-a-secureTrie.json/phase-a-secure-object-form-empty-value-delete"
    "phase-a-secureTrie.json/phase-a-secure-object-form-missing-delete"
    "phase-a-secureTrie.json/phase-a-secure-object-form-value-hex-bytes"
    "phase-a-secureTrie.json/phase-a-secure-value-hex-byte-delete"
    "phase-a-trie-multi.json/alpha"
    "phase-a-trie-multi.json/geth-long-leaf-value"
    "phase-a-trie-multi.json/geth-large-value-branch"
    "phase-a-trie-multi.json/geth-tiny-account-step-1"
    "phase-a-trie-multi.json/geth-tiny-account-step-2"
    "phase-a-trie-multi.json/geth-tiny-account-step-3"
    "phase-a-trie-multi.json/hex-byte-value-leaf"
    "phase-a-trie-multi.json/branch"
    "phase-a-trie-multi.json/branch-child-branch"
    "phase-a-trie-multi.json/branch-child-extension"
    "phase-a-trie-multi.json/object-form-branch"
    "phase-a-trie-multi.json/object-form-empty-value-delete"
    "phase-a-trie-multi.json/object-form-hex-byte-value-leaf"
    "phase-a-trie-multi.json/object-form-missing-delete"
    "phase-a-trie-multi.json/branch-value"
    "phase-a-trie-multi.json/branch-value-zero-child"
    "phase-a-trie-multi.json/delete-branch-child"
    "phase-a-trie-multi.json/delete-branch-child-no-value"
    "phase-a-trie-multi.json/delete-branch-child-keeps-branch"
    "phase-a-trie-multi.json/delete-branch-sibling-collapses-to-extension"
    "phase-a-trie-multi.json/delete-branch-value"
    "phase-a-trie-multi.json/delete-extension-child-collapses-to-leaf"
    "phase-a-trie-multi.json/delete-missing-branch-child"
    "phase-a-trie-multi.json/delete-missing-leaf"
    "phase-a-trie-multi.json/duplicate-overwrite"
    "phase-a-trie-multi.json/delete-collapse"
    "phase-a-trie-multi.json/delete-missing-extension-child"
    "phase-a-trie-multi.json/delete-nested-branch-value"
    "phase-a-trie-multi.json/delete-prefix-branch-value"
    "phase-a-trie-multi.json/embedded-extension"
    "phase-a-trie-multi.json/extension"
    "phase-a-trie-multi.json/geth-insert-shared-prefix"
    "phase-a-trie-multi.json/geth-delete-sequence"
    "phase-a-trie-multi.json/geth-empty-value-sequence"
    "phase-a-trie-multi.json/geth-replication-sequence"
    "phase-a-trie-multi.json/geth-random-cases-sequence"
    "phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary"
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
    "hex-value"
    "secure-key"
    "lookup-assertions"
    "empty-value-delete"
    "single-node-proof"
    "exact-proof-node-rlp"
    "proof-node-rlp"
    "delete-proof-node-rlp"
    "missing-proof-node-rlp"
    "entry-pair-replay"
    "entry-range"
    "intermediate-roots"))

(defparameter +trie-fixture-required-case-names+
  '("single-leaf"
    "geth-one-element-proof"
    "geth-long-leaf-value"
    "geth-large-value-branch"
    "geth-tiny-account-step-1"
    "geth-tiny-account-step-2"
    "geth-tiny-account-step-3"
    "hex-byte-value-leaf"
    "delete-missing-key-keeps-leaf"
    "duplicate-key-overwrites-leaf-value"
    "geth-insert-shared-prefix"
    "geth-delete-sequence"
    "geth-empty-value-sequence"
    "geth-replication-sequence"
    "geth-random-cases-sequence"
    "geth-stacktrie-extension-child-boundary"
    "geth-stacktrie-short-branch-growth"
    "geth-stacktrie-root-branch-short-long-growth"
    "geth-stacktrie-extension-branch-short-long-growth"
    "geth-stacktrie-sparse-root-branch-long-values"
    "geth-stacktrie-root-branch-nested-right-branch"
    "geth-stacktrie-root-branch-nested-left-branch"
    "nethermind-partial-path-proof-nodes"
    "branch-extension-shared-prefix"
    "branch-child-branch"
    "branch-child-extension"
    "extension-embedded-child-reference"
    "extension-hashed-child-reference"
    "delete-collapses-path"
    "delete-nested-branch-value-keeps-extension"
    "delete-prefix-branch-value-keeps-sibling-extension"
    "delete-extension-child-collapses-to-leaf"
    "delete-branch-sibling-collapses-to-extension"
    "delete-missing-extension-child-keeps-extension"
    "delete-last-entry-empty-root"
    "secure-branch-root"
    "secure-branch-child-branch"
    "secure-branch-child-extension"
    "secure-missing-delete-keeps-branch-root"
    "secure-extension-root"
    "secure-missing-delete-keeps-extension-root"
    "secure-delete-branch-child-collapses-to-leaf"
    "secure-delete-branch-child-keeps-branch"
    "secure-delete-branch-sibling-collapses-to-extension"
    "secure-delete-extension-child-collapses-to-leaf"
    "secure-duplicate-key-overwrites-leaf-value"
    "geth-secure-account-step-1"
    "geth-secure-account-step-2"
    "geth-secure-account-step-3"
    "geth-secure-delete-sequence"
    "secure-single-leaf"
    "secure-delete-last-entry-empty-root"
    "root-branch-sparse-children"
    "root-branch-mixed-child-references"
    "delete-missing-branch-child-keeps-root-branch"
    "root-branch-value-for-prefix-key"
    "root-branch-value-with-zero-child"
    "delete-root-branch-value-collapses-to-leaf"
    "delete-root-branch-child-without-value-collapses-to-leaf"
    "delete-root-branch-child-without-value-keeps-branch"
    "delete-root-branch-child-collapses-to-root-value-leaf"
    "geth-general-range-iteration"))

(defparameter +trie-fixture-reference-case-requirements+
  '(("geth-one-element-proof" . :plain)
    ("geth-long-leaf-value" . :plain)
    ("geth-large-value-branch" . :plain)
    ("geth-general-range-iteration" . :plain)
    ("geth-tiny-account-step-1" . :plain)
    ("geth-tiny-account-step-2" . :plain)
    ("geth-tiny-account-step-3" . :plain)
    ("geth-insert-shared-prefix" . :plain)
    ("geth-delete-sequence" . :plain)
    ("geth-empty-value-sequence" . :plain)
    ("geth-replication-sequence" . :plain)
    ("geth-random-cases-sequence" . :plain)
    ("geth-stacktrie-extension-child-boundary" . :plain)
    ("geth-stacktrie-short-branch-growth" . :plain)
    ("geth-stacktrie-root-branch-short-long-growth" . :plain)
    ("geth-stacktrie-extension-branch-short-long-growth" . :plain)
    ("geth-stacktrie-sparse-root-branch-long-values" . :plain)
    ("geth-stacktrie-root-branch-nested-right-branch" . :plain)
    ("geth-stacktrie-root-branch-nested-left-branch" . :plain)
    ("nethermind-partial-path-proof-nodes" . :plain)
    ("geth-secure-account-step-1" . :secure)
    ("geth-secure-account-step-2" . :secure)
    ("geth-secure-account-step-3" . :secure)
    ("geth-secure-delete-sequence" . :secure)))

(defparameter +phase-a-eest-trie-reference-case-requirements+
  '(("phase-a-trie-multi.json/geth-long-leaf-value" . :plain)
    ("phase-a-trie-multi.json/geth-large-value-branch" . :plain)
    ("phase-a-trie-multi.json/geth-tiny-account-step-1" . :plain)
    ("phase-a-trie-multi.json/geth-tiny-account-step-2" . :plain)
    ("phase-a-trie-multi.json/geth-tiny-account-step-3" . :plain)
    ("phase-a-trie-multi.json/geth-insert-shared-prefix" . :plain)
    ("phase-a-trie-multi.json/geth-delete-sequence" . :plain)
    ("phase-a-trie-multi.json/geth-empty-value-sequence" . :plain)
    ("phase-a-trie-multi.json/geth-replication-sequence" . :plain)
    ("phase-a-trie-multi.json/geth-random-cases-sequence" . :plain)
    ("phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary" . :plain)
    ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1" . :secure)
    ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2" . :secure)
    ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3" . :secure)
    ("phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence" . :secure)))

(defparameter +phase-a-eest-trie-explicit-output-reference-case-names+
  '("phase-a-trie-multi.json/geth-tiny-account-step-3"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"))

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
    "hex-value"
    "secure-key"
    "lookup-assertions"
    "empty-value-delete"
    "single-node-proof"
    "exact-proof-node-rlp"
    "proof-node-rlp"
    "delete-proof-node-rlp"
    "missing-proof-node-rlp"
    "entry-pair-replay"
    "entry-range"))

(defparameter +trie-fixture-root-shapes+
  '("empty" "leaf" "extension" "branch"))

(defparameter +trie-fixture-child-shapes+
  '("leaf" "extension" "branch"))

(defparameter +trie-fixture-child-reference-kinds+
  '("embedded" "hashed"))

(defparameter +trie-fixture-case-fields+
  '("name"
    "secure"
    "tags"
    "operations"
    "expectedIntermediateRoots"
    "expectedRoot"
    "expectedShape"
    "expectedChildReference"
    "expectedRootChildren"
    "expectedRootChildReferences"
    "expectedRootChildShapes"
    "expectedRootPathNibbles"
    "expectedRootValueAscii"
    "expectedRootValueHex"
    "expectedGets"
    "expectedMissing"
    "expectedEntryPairs"
    "expectedEntryRanges"
    "expectedProofPrefixes"))

(defparameter +trie-fixture-operation-fields+
  '("op" "keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-get-fields+
  '("keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-missing-fields+
  '("keyHex" "keyAscii"))

(defparameter +trie-fixture-expected-entry-pair-fields+
  '("keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-entry-range-fields+
  '("startKeyHex" "startKeyAscii" "endKeyHex" "endKeyAscii" "expectedKeys"))

(defparameter +trie-fixture-expected-entry-range-key-fields+
  '("keyHex" "keyAscii"))

(defparameter +trie-fixture-expected-proof-prefix-fields+
  '("keyHex" "keyAscii" "nodeRlps" "exactLength"))

(defparameter +eest-trie-test-case-fields+
  '("in" "out" "root" "secure"))

(defun validate-trie-fixture-object-fields (object allowed-fields label)
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

(defun validate-trie-fixture-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-trie-fixture-hash-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hash hex string" label field))
    (let ((hash (hash32-from-hex value)))
      (unless (string= value (hash32-to-hex hash))
        (error "~A ~A must be canonical lowercase 0x-prefixed hash hex"
               label field)))))

(defun validate-trie-fixture-byte-field (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (string= value (bytes-to-hex bytes))
          (error "~A must be canonical lowercase 0x-prefixed hex" label)))
    (error (condition)
      (error "~A must be hex bytes: ~A" label condition))))

(defun validate-trie-fixture-value-fields (object label &key allow-empty)
  (let ((has-hex (fixture-field-present-p object "valueHex"))
        (has-ascii (fixture-field-present-p object "valueAscii")))
    (unless (or has-hex has-ascii)
      (error "~A must include valueAscii or valueHex" label))
    (when (and has-hex has-ascii)
      (error "~A must not include both valueAscii and valueHex" label))
    (when has-ascii
      (if allow-empty
          (unless (stringp (fixture-object-field object "valueAscii"))
            (error "~A valueAscii must be a string" label))
          (validate-trie-fixture-non-empty-string
           (fixture-object-field object "valueAscii")
           (format nil "~A valueAscii" label))))
    (when has-hex
      (let ((value (fixture-object-field object "valueHex")))
        (validate-trie-fixture-byte-field
         value
         (format nil "~A valueHex" label))
        (when (and (not allow-empty)
                   (zerop (length (hex-to-bytes value))))
          (error "~A valueHex must not be empty" label))))))

(defun validate-trie-fixture-metadata (fixture)
  (validate-trie-fixture-object-fields
   fixture
   +trie-fixture-top-level-fields+
   "Trie fixture")
  (validate-fixture-format fixture +trie-vector-fixture-format+)
  (validate-trie-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "Trie fixture source")
  (validate-fixture-pinned-eest-source fixture))

(defun validate-trie-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (validate-trie-fixture-non-empty-string
     name
     "Trie fixture case name")
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
      (validate-trie-fixture-byte-field
       (fixture-object-field object "keyHex")
       (format nil "~A keyHex" label)))
    (when has-ascii
      (let ((key (fixture-object-field object "keyAscii")))
        (validate-trie-fixture-non-empty-string
         key
         (format nil "~A keyAscii" label))))))

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
    (unless (stringp op)
      (error "Trie fixture case ~A operation op must be a string" case-name))
    (cond
      ((string= op "put")
       (validate-trie-fixture-value-fields
        operation
        (format nil "Trie fixture case ~A put operation" case-name)
        :allow-empty t))
      ((string= op "delete")
       (when (fixture-field-present-p operation "valueAscii")
         (error "Trie fixture case ~A delete operation must not include valueAscii"
                case-name))
       (when (fixture-field-present-p operation "valueHex")
         (error "Trie fixture case ~A delete operation must not include valueHex"
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
     (validate-trie-fixture-value-fields
      expected
      (format nil "Trie fixture case ~A expectedGets entry" case-name)))
    ((string= field "expectedMissing")
     (when (fixture-field-present-p expected "valueAscii")
       (error "Trie fixture case ~A expectedMissing entry must not include valueAscii"
              case-name))
     (when (fixture-field-present-p expected "valueHex")
       (error "Trie fixture case ~A expectedMissing entry must not include valueHex"
              case-name)))))

(defun validate-trie-fixture-expected-proof-prefix (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedProofPrefixes entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-proof-prefix-fields+
   (format nil "Trie fixture case ~A expectedProofPrefixes entry" case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedProofPrefixes entry"
           case-name))
  (when (fixture-field-present-p expected "exactLength")
    (let ((exact-length (fixture-object-field expected "exactLength")))
      (unless (or (eq exact-length t) (null exact-length))
        (error "Trie fixture case ~A expectedProofPrefixes exactLength must be a boolean"
               case-name))))
  (let ((node-rlps (fixture-required-field expected "nodeRlps")))
    (unless (and (listp node-rlps) node-rlps)
      (error "Trie fixture case ~A expectedProofPrefixes nodeRlps must be a non-empty list"
             case-name))
    (dolist (node-rlp node-rlps)
      (validate-trie-fixture-byte-field
       node-rlp
       (format nil "Trie fixture case ~A expectedProofPrefixes nodeRlp"
               case-name))
      (when (zerop (length (hex-to-bytes node-rlp)))
        (error "Trie fixture case ~A expectedProofPrefixes nodeRlp must not be empty"
               case-name)))))

(defun validate-trie-fixture-expected-entry-pair (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryPairs entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-pair-fields+
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name))
  (validate-trie-fixture-value-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name)))

(defun validate-trie-fixture-entry-range-bound (expected case-name prefix)
  (let* ((hex-field (format nil "~AKeyHex" prefix))
         (ascii-field (format nil "~AKeyAscii" prefix))
         (has-hex (fixture-field-present-p expected hex-field))
         (has-ascii (fixture-field-present-p expected ascii-field))
         (label (format nil "Trie fixture case ~A expectedEntryRanges ~A bound"
                        case-name
                        prefix)))
    (when (and has-hex has-ascii)
      (error "~A must not include both ~A and ~A"
             label hex-field ascii-field))
    (when has-hex
      (validate-trie-fixture-byte-field
       (fixture-object-field expected hex-field)
       (format nil "~A ~A" label hex-field)))
    (when has-ascii
      (let ((key (fixture-object-field expected ascii-field)))
        (validate-trie-fixture-non-empty-string
         key
         (format nil "~A ~A" label ascii-field))))))

(defun validate-trie-fixture-entry-range-key (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryRanges expectedKeys entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-range-key-fields+
   (format nil "Trie fixture case ~A expectedEntryRanges expectedKeys entry"
           case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryRanges expectedKeys entry"
           case-name)))

(defun validate-trie-fixture-expected-entry-range (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryRanges entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-range-fields+
   (format nil "Trie fixture case ~A expectedEntryRanges entry" case-name))
  (validate-trie-fixture-entry-range-bound expected case-name "start")
  (validate-trie-fixture-entry-range-bound expected case-name "end")
  (let ((expected-keys (fixture-required-field expected "expectedKeys"))
        (seen-keys (make-hash-table :test 'equal)))
    (unless (listp expected-keys)
      (error "Trie fixture case ~A expectedEntryRanges expectedKeys must be a list"
             case-name))
    (dolist (key-entry expected-keys)
      (validate-trie-fixture-entry-range-key key-entry case-name)
      (let ((key (bytes-to-hex (trie-fixture-key key-entry))))
        (when (gethash key seen-keys)
          (error "Trie fixture case ~A expectedEntryRanges has duplicate expected key ~A"
                 case-name
                 key))
        (setf (gethash key seen-keys) t)))))

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
  (validate-trie-fixture-hash-field
   case
   "expectedRoot"
   "Trie fixture case"))

(defun validate-trie-fixture-expected-intermediate-roots (case)
  (when (fixture-field-present-p case "expectedIntermediateRoots")
    (let ((roots (fixture-object-field case "expectedIntermediateRoots"))
          (operations (fixture-object-field case "operations"))
          (name (fixture-object-field case "name")))
      (unless (listp roots)
        (error "Trie fixture case ~A expectedIntermediateRoots must be a JSON array"
               name))
      (unless (= (length roots) (length operations))
        (error "Trie fixture case ~A expectedIntermediateRoots must match operation count"
               name))
      (loop for root in roots
            for index from 0
            do (validate-trie-fixture-byte-field
                root
                (format nil "Trie fixture case ~A expectedIntermediateRoots ~D"
                        name
                        index))
               (unless (= 32 (length (hex-to-bytes root)))
                 (error "Trie fixture case ~A expectedIntermediateRoots ~D must be a 32-byte hash"
                        name
                        index))))))

(defun validate-trie-fixture-expected-shape (case)
  (let ((shape (fixture-required-field case "expectedShape")))
    (unless (stringp shape)
      (error "Trie fixture case ~A expectedShape must be a string"
             (fixture-object-field case "name")))
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

(defun parse-trie-fixture-child-reference-index (case raw-index)
  (unless (stringp raw-index)
    (error "Trie fixture case ~A child reference index must be a string"
           (fixture-object-field case "name")))
  (multiple-value-bind (index position)
      (parse-integer raw-index :junk-allowed t)
    (unless (and index (= position (length raw-index)) (<= 0 index 15))
      (error "Trie fixture case ~A has malformed child reference index ~A"
             (fixture-object-field case "name")
             raw-index))
    index))

(defun validate-trie-fixture-root-child-references (case)
  (when (fixture-field-present-p case "expectedRootChildReferences")
    (let ((references
            (fixture-object-field case "expectedRootChildReferences"))
          (seen-indexes (make-hash-table)))
      (unless (listp references)
        (error "Trie fixture case ~A expectedRootChildReferences must be a JSON object"
               (fixture-object-field case "name")))
      (dolist (reference references)
        (let ((index (parse-trie-fixture-child-reference-index
                      case
                      (car reference)))
              (kind (cdr reference)))
          (when (gethash index seen-indexes)
            (error "Trie fixture case ~A has duplicate child reference index ~A"
                   (fixture-object-field case "name")
                   (car reference)))
          (setf (gethash index seen-indexes) t)
          (unless (stringp kind)
            (error "Trie fixture case ~A child reference kind must be a string"
                   (fixture-object-field case "name")))
          (unless (trie-fixture-valid-child-reference-kind-p kind)
            (error "Trie fixture case ~A has unknown child reference kind ~A"
                   (fixture-object-field case "name")
                   kind)))))))

(defun validate-trie-fixture-root-child-shapes (case)
  (when (fixture-field-present-p case "expectedRootChildShapes")
    (let ((shapes
            (fixture-object-field case "expectedRootChildShapes"))
          (seen-indexes (make-hash-table)))
      (unless (listp shapes)
        (error "Trie fixture case ~A expectedRootChildShapes must be a JSON object"
               (fixture-object-field case "name")))
      (dolist (shape-entry shapes)
        (let ((index (parse-trie-fixture-child-reference-index
                      case
                      (car shape-entry)))
              (shape (cdr shape-entry)))
          (when (gethash index seen-indexes)
            (error "Trie fixture case ~A has duplicate child shape index ~A"
                   (fixture-object-field case "name")
                   (car shape-entry)))
          (setf (gethash index seen-indexes) t)
          (unless (stringp shape)
            (error "Trie fixture case ~A child shape must be a string"
                   (fixture-object-field case "name")))
          (unless (member shape +trie-fixture-child-shapes+ :test #'string=)
            (error "Trie fixture case ~A has unknown child shape ~A"
                   (fixture-object-field case "name")
                   shape)))))))

(defun validate-trie-fixture-expected-fields (case)
  (let ((shape (validate-trie-fixture-expected-shape case)))
    (validate-trie-fixture-expected-root case)
    (validate-trie-fixture-expected-intermediate-roots case)
    (unless (or (not (fixture-field-present-p case "expectedChildReference"))
                (string= shape "extension"))
      (error "Trie fixture case ~A expectedChildReference requires an extension root"
             (fixture-object-field case "name")))
    (when (fixture-field-present-p case "expectedChildReference")
      (let ((kind (fixture-object-field case "expectedChildReference")))
        (unless (stringp kind)
          (error "Trie fixture case ~A expectedChildReference must be a string"
                 (fixture-object-field case "name")))
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
    (unless (or (not (fixture-field-present-p case "expectedRootChildShapes"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildShapes requires a branch root"
             (fixture-object-field case "name")))
    (validate-trie-fixture-root-children case)
    (validate-trie-fixture-root-child-references case)
    (validate-trie-fixture-root-child-shapes case)
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
    (when (fixture-field-present-p case "expectedRootValueAscii")
      (validate-trie-fixture-non-empty-string
       (fixture-object-field case "expectedRootValueAscii")
       (format nil "Trie fixture case ~A expectedRootValueAscii"
               (fixture-object-field case "name"))))
    (when (and (fixture-field-present-p case "expectedRootValueAscii")
               (fixture-field-present-p case "expectedRootValueHex"))
      (error "Trie fixture case ~A must not include both expectedRootValueAscii and expectedRootValueHex"
             (fixture-object-field case "name")))
    (when (fixture-field-present-p case "expectedRootValueHex")
      (let ((value (fixture-object-field case "expectedRootValueHex")))
        (validate-trie-fixture-byte-field
         value
         (format nil "Trie fixture case ~A expectedRootValueHex"
                 (fixture-object-field case "name")))
        (when (zerop (length (hex-to-bytes value)))
          (error "Trie fixture case ~A expectedRootValueHex must not be empty"
                 (fixture-object-field case "name")))))))

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
    (dolist (expected (fixture-object-field case "expectedEntryPairs"))
      (validate-trie-fixture-expected-entry-pair expected name))
    (dolist (expected (fixture-object-field case "expectedEntryRanges"))
      (validate-trie-fixture-expected-entry-range expected name))
    (dolist (expected (fixture-object-field case "expectedProofPrefixes"))
      (validate-trie-fixture-expected-proof-prefix expected name))
    (validate-trie-fixture-expected-lookup-keys case)))

(defun validate-trie-fixture-case-coverage (cases)
  (unless (and (listp cases) cases)
    (error "Trie fixture must include at least one case"))
  (let ((seen-names (make-hash-table :test #'equal))
        (seen-tags (make-hash-table :test #'equal))
        secure-leaf-root-p
        secure-delete-to-empty-p
        secure-branch-root-p
        secure-extension-root-p
        secure-entry-pair-replay-p
        entry-range-p
        exact-proof-node-rlp-p)
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
                   (member "entry-pair-replay"
                           (fixture-object-field case "tags")
                           :test #'string=))
          (setf secure-entry-pair-replay-p t))
        (when (and (member "entry-range"
                           (fixture-object-field case "tags")
                           :test #'string=)
                   (fixture-object-field case "expectedEntryRanges"))
          (setf entry-range-p t))
        (when (some (lambda (expected)
                      (fixture-object-field expected "exactLength"))
                    (fixture-object-field case "expectedProofPrefixes"))
          (setf exact-proof-node-rlp-p t))
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
      (error "Trie fixture must include a secure extension root case"))
    (unless secure-entry-pair-replay-p
      (error "Trie fixture must include a secure entry-pair replay case"))
    (unless entry-range-p
      (error "Trie fixture must include entry-range coverage"))
    (unless exact-proof-node-rlp-p
      (error "Trie fixture must include exact proof-node RLP coverage"))))

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

(defun trie-reference-case-mode (case)
  (if (fixture-object-field case "secure")
      :secure
      :plain))

(defun validate-trie-reference-case-requirements
    (cases requirements label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-requirements (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (requirement requirements)
      (destructuring-bind (name . expected-mode) requirement
        (unless (member expected-mode '(:plain :secure))
          (error "~A reference case ~A has unknown required mode ~A"
                 label
                 name
                 expected-mode))
        (when (gethash name seen-requirements)
          (error "~A reference case list has duplicate name ~A"
                 label
                 name))
        (setf (gethash name seen-requirements) t)
        (let ((case (gethash name case-by-name)))
          (unless case
            (error "~A is missing required reference-derived trie case ~A"
                   label
                   name))
          (let ((actual-mode (trie-reference-case-mode case)))
            (unless (eq actual-mode expected-mode)
              (error "~A reference-derived trie case ~A must be ~A, got ~A"
                     label
                     name
                     expected-mode
                     actual-mode))))))))

(defun validate-trie-reference-explicit-output-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A explicit-output reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing explicit-output reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedOut")
          (error "~A reference-derived trie case ~A must include explicit out assertions"
                 label
                 name))
        (multiple-value-bind (present-count missing-count)
            (eest-trie-test-explicit-output-counts case)
          (unless (and (plusp present-count)
                       (plusp missing-count))
            (error "~A reference-derived trie case ~A explicit out must include present and missing keys"
                   label
                   name)))))))

(defun validate-trie-fixture-cases (cases)
  (validate-trie-fixture-case-coverage cases)
  (validate-trie-reference-case-requirements
   cases
   +trie-fixture-reference-case-requirements+
   "Seed trie fixture")
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
  (unless (stringp name)
    (error "EEST trie test case name must be a string"))
  (when (blank-string-p name)
    (error "EEST trie test case name must be present"))
  (unless (listp case)
    (error "EEST trie test case ~A must be a JSON object" name))
  (validate-trie-fixture-object-fields
   case
   +eest-trie-test-case-fields+
   (format nil "EEST trie test case ~A" name))
  (let* ((input (fixture-required-field case "in"))
         (object-form-p (and (listp input)
                             (eest-trie-test-object-entries-p input))))
    (append
     (list
      (cons "name" name)
      (cons "entries"
            (normalize-eest-trie-test-entries name input))
      (cons "inputForm" (if object-form-p "object" "array"))
      (cons "secure"
            (eest-trie-test-normalized-secure-p
             name
             case
             default-secure-p))
      (cons "root"
            (eest-trie-test-normalized-root
             (fixture-required-field case "root")
             name)))
     (when (fixture-field-present-p case "out")
       (list
        (cons "expectedOut"
              (normalize-eest-trie-test-output-entries
               name
               (fixture-object-field case "out"))))))))

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
                     (cons "delete" t)
                     (cons "deleteSource" "empty-value")
                     (cons "deleteSourceValue" normalized-value))
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

(defun normalize-eest-trie-test-output-entries (case-name entries)
  (unless (and (listp entries)
               (eest-trie-test-object-entries-p entries))
    (error "EEST trie test case ~A out must be a JSON object" case-name))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (let* ((key (car entry))
             (key-id (bytes-to-hex
                      (eest-trie-test-byte-string
                       key
                       (format nil
                               "EEST trie test case ~A out object key"
                               case-name))
                      :prefix nil)))
        (when (gethash key-id seen)
          (error "EEST trie test case ~A out object has duplicate normalized key ~A"
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

(defun run-eest-trie-test-entries (case entries)
  (let ((trie (make-mpt)))
    (dolist (entry entries)
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

(defun run-eest-trie-test-case (case)
  (run-eest-trie-test-entries
   case
   (fixture-required-field case "entries")))

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

(defun eest-trie-test-final-proof-counts (case)
  (let ((present-count 0)
        (missing-count 0))
    (maphash
     (lambda (key-id expected)
       (declare (ignore key-id))
       (if expected
           (incf present-count)
           (incf missing-count)))
     (eest-trie-test-final-entry-map case))
    (values present-count missing-count)))

(defun eest-trie-test-explicit-output-map (case)
  (let ((output (make-hash-table :test 'equal)))
    (dolist (entry (fixture-object-field case "expectedOut"))
      (let ((key-id (bytes-to-hex
                     (eest-trie-test-entry-trie-key case entry)
                     :prefix nil)))
        (if (fixture-field-present-p entry "delete")
            (setf (gethash key-id output) nil)
            (setf (gethash key-id output)
                  (eest-trie-test-byte-string
                   (fixture-required-field entry "value")
                   (format nil "EEST trie test case ~A out entry value"
                           (fixture-required-field case "name")))))))
    output))

(defun eest-trie-test-explicit-output-counts (case)
  (let ((present-count 0)
        (missing-count 0))
    (maphash
     (lambda (key-id expected)
       (declare (ignore key-id))
       (if expected
           (incf present-count)
           (incf missing-count)))
     (eest-trie-test-explicit-output-map case))
    (values present-count missing-count)))

(defun assert-eest-trie-test-explicit-output-complete (case output)
  (let ((name (fixture-required-field case "name"))
        (final (eest-trie-test-final-entry-map case)))
    (maphash
     (lambda (key-id expected)
       (when expected
         (multiple-value-bind (actual-output output-present-p)
             (gethash key-id output)
           (unless (and output-present-p actual-output)
             (error "EEST trie test case ~A out missing final key ~A"
                    name
                    key-id)))))
     final)))

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

(defun assert-eest-trie-test-case-explicit-output (case trie)
  (when (fixture-field-present-p case "expectedOut")
    (let ((name (fixture-required-field case "name"))
          (output (eest-trie-test-explicit-output-map case)))
      (assert-eest-trie-test-explicit-output-complete case output)
      (maphash
       (lambda (key-id expected)
         (let* ((key (hex-to-bytes key-id))
                (actual (mpt-get trie key)))
           (if expected
               (progn
                 (unless (bytes= expected actual)
                   (error "EEST trie test case ~A out mismatch for key ~A"
                          name
                          key-id))
                 (assert-eest-trie-test-case-proof-present
                  case
                  trie
                  key
                  expected))
               (progn
                 (when actual
                   (error "EEST trie test case ~A expected out-missing key ~A"
                          name
                          key-id))
                 (assert-eest-trie-test-case-proof-missing
                  case
                  trie
                  key)))))
       output))))

(defun eest-trie-test-object-form-case-p (case)
  (string= "object" (fixture-required-field case "inputForm")))

(defun eest-trie-test-remove-nth (index list)
  (loop for item in list
        for i from 0
        unless (= i index)
          collect item))

(defun eest-trie-test-entry-permutations (entries)
  (if (endp entries)
      (list nil)
      (loop for entry in entries
            for index from 0
            append
            (mapcar (lambda (tail)
                      (cons entry tail))
                    (eest-trie-test-entry-permutations
                     (eest-trie-test-remove-nth index entries))))))

(defun eest-trie-test-object-form-permutation-count (case)
  (if (eest-trie-test-object-form-case-p case)
      (length
       (eest-trie-test-entry-permutations
        (fixture-required-field case "entries")))
      0))

(defun assert-eest-trie-test-object-form-permutations (case)
  (when (eest-trie-test-object-form-case-p case)
    (let ((name (fixture-required-field case "name"))
          (expected-root (fixture-required-field case "root")))
      (dolist (entries
               (eest-trie-test-entry-permutations
                (fixture-required-field case "entries")))
        (let ((actual-root
                (mpt-root-hex
                 (run-eest-trie-test-entries case entries))))
          (unless (string= expected-root actual-root)
            (error "EEST trie test case ~A object-form permutation root mismatch: expected ~A, got ~A"
                   name
                   expected-root
                   actual-root)))))))

(defun assert-eest-trie-test-entry-pair-replay (case trie)
  (let ((name (fixture-required-field case "name"))
        (rebuilt (make-mpt)))
    (dolist (entry (mpt-entry-pairs trie))
      (mpt-put rebuilt (car entry) (cdr entry)))
    (unless (string= (mpt-root-hex trie) (mpt-root-hex rebuilt))
      (error "EEST trie test case ~A entry-pair replay root mismatch: expected ~A, got ~A"
             name
             (mpt-root-hex trie)
             (mpt-root-hex rebuilt)))
    (dolist (entry (mpt-entry-pairs trie))
      (let ((value (mpt-get rebuilt (car entry))))
        (unless (bytes= (cdr entry) value)
          (error "EEST trie test case ~A entry-pair replay value mismatch for key ~A"
                 name
                 (bytes-to-hex (car entry))))))))

(defun eest-trie-test-entry-pairs-equal-p (left right)
  (and (= (length left) (length right))
       (loop for left-entry in left
             for right-entry in right
             always (and (bytes= (car left-entry) (car right-entry))
                         (bytes= (cdr left-entry) (cdr right-entry))))))

(defun assert-eest-trie-test-entry-range
    (case trie label start end expected)
  (let ((actual (mpt-entry-range trie :start start :end end))
        (name (fixture-required-field case "name")))
    (unless (eest-trie-test-entry-pairs-equal-p expected actual)
      (error "EEST trie test case ~A entry range ~A mismatch: expected ~A entries, got ~A"
             name
             label
             (length expected)
             (length actual)))))

(defun assert-eest-trie-test-entry-ranges (case trie)
  (let* ((entries (mpt-entry-pairs trie))
         (entry-count (length entries)))
    (assert-eest-trie-test-entry-range
     case trie "full" nil nil entries)
    (when (plusp entry-count)
      (let ((first-key (caar entries))
            (last-key (caar (last entries))))
        (assert-eest-trie-test-entry-range
         case trie "from-first" first-key nil entries)
        (assert-eest-trie-test-entry-range
         case trie "to-last" nil last-key (butlast entries))
        (assert-eest-trie-test-entry-range
         case trie "equal-first" first-key first-key nil)
        (when (> entry-count 2)
          (assert-eest-trie-test-entry-range
           case
           trie
           "second-to-last"
           (car (second entries))
           last-key
           (subseq entries 1 (1- entry-count))))))))

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
    (assert-eest-trie-test-case-explicit-output case trie)
    (assert-eest-trie-test-entry-pair-replay case trie)
    (assert-eest-trie-test-entry-ranges case trie)
    (assert-eest-trie-test-object-form-permutations case)
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
      (unless (consp entry)
        (error "EEST trie test file ~A entries must be JSON object fields"
               source))
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

(defun eest-trie-test-empty-key-entry-p (entry)
  (zerop (length (eest-trie-test-byte-string
                  (fixture-required-field entry "key")
                  "EEST trie summary entry key"))))

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

(defun eest-trie-test-entry-hex-key-p (entry)
  (eest-trie-test-prefixed-hex-string-p
   (fixture-required-field entry "key")))

(defun eest-trie-test-entry-hex-value-p (entry)
  (let ((value (fixture-object-field entry "value")))
    (and value
         (eest-trie-test-prefixed-hex-string-p value))))

(defun eest-trie-test-entry-empty-value-delete-p (entry)
  (string= "empty-value" (fixture-object-field entry "deleteSource")))

(defun eest-trie-test-entry-hex-empty-value-delete-p (entry)
  (and (eest-trie-test-entry-empty-value-delete-p entry)
       (string= "0x" (fixture-object-field entry "deleteSourceValue"))))

(defun eest-trie-test-entry-string-empty-value-delete-p (entry)
  (and (eest-trie-test-entry-empty-value-delete-p entry)
       (string= "" (fixture-object-field entry "deleteSourceValue"))))

(defun eest-trie-test-case-missing-delete-p (case)
  (let ((present-keys (make-hash-table :test 'equal)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key-id (bytes-to-hex
                     (eest-trie-test-entry-trie-key case entry)
                     :prefix nil)))
        (if (fixture-field-present-p entry "delete")
            (progn
              (unless (gethash key-id present-keys)
                (return-from eest-trie-test-case-missing-delete-p t))
              (remhash key-id present-keys))
            (setf (gethash key-id present-keys) t)))))
  nil)

(defun eest-trie-test-case-valueless-branch-delete-to-leaf-p (case)
  (let ((trie (make-mpt)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key (eest-trie-test-entry-trie-key case entry)))
        (if (fixture-field-present-p entry "delete")
            (let ((branch-before-delete-p
                    (and (plusp (length key))
                         (string= "branch" (trie-fixture-root-shape trie))
                         (blank-string-p (trie-fixture-root-value trie)))))
              (mpt-delete trie key)
              (when (and branch-before-delete-p
                         (string= "leaf" (trie-fixture-root-shape trie))
                         (not (blank-string-p
                               (trie-fixture-root-value trie))))
                (return-from
                 eest-trie-test-case-valueless-branch-delete-to-leaf-p
                 t)))
            (mpt-put trie
                     key
                     (eest-trie-test-byte-string
                      (fixture-required-field entry "value")
                      (format nil "EEST trie test case ~A in entry value"
                              (fixture-required-field case "name"))))))))
  nil)

(defun eest-trie-test-case-valueless-branch-delete-keeps-branch-p (case)
  (let ((trie (make-mpt)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key (eest-trie-test-entry-trie-key case entry)))
        (if (fixture-field-present-p entry "delete")
            (let ((branch-before-delete-p
                    (and (plusp (length key))
                         (mpt-get trie key)
                         (string= "branch" (trie-fixture-root-shape trie))
                         (blank-string-p (trie-fixture-root-value trie)))))
              (mpt-delete trie key)
              (when (and branch-before-delete-p
                         (string= "branch" (trie-fixture-root-shape trie))
                         (blank-string-p (trie-fixture-root-value trie)))
                (return-from
                 eest-trie-test-case-valueless-branch-delete-keeps-branch-p
                 t)))
            (mpt-put trie
                     key
                     (eest-trie-test-byte-string
                      (fixture-required-field entry "value")
                      (format nil "EEST trie test case ~A in entry value"
                              (fixture-required-field case "name"))))))))
  nil)

(defun eest-trie-test-case-extension-delete-to-leaf-p (case)
  (let ((trie (make-mpt)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key (eest-trie-test-entry-trie-key case entry)))
        (if (fixture-field-present-p entry "delete")
            (let ((extension-before-delete-p
                    (and (plusp (length key))
                         (mpt-get trie key)
                         (string= "extension"
                                  (trie-fixture-root-shape trie)))))
              (mpt-delete trie key)
              (when (and extension-before-delete-p
                         (string= "leaf" (trie-fixture-root-shape trie))
                         (not (blank-string-p
                               (trie-fixture-root-value trie))))
                (return-from
                 eest-trie-test-case-extension-delete-to-leaf-p
                 t)))
            (mpt-put trie
                     key
                     (eest-trie-test-byte-string
                      (fixture-required-field entry "value")
                      (format nil "EEST trie test case ~A in entry value"
                             (fixture-required-field case "name"))))))))
  nil)

(defun eest-trie-test-case-present-delete-to-extension-p (case)
  (let ((trie (make-mpt)))
    (dolist (entry (fixture-required-field case "entries"))
      (let ((key (eest-trie-test-entry-trie-key case entry)))
        (if (fixture-field-present-p entry "delete")
            (let ((present-before-delete-p
                    (and (plusp (length key))
                         (mpt-get trie key))))
              (mpt-delete trie key)
              (when (and present-before-delete-p
                         (string= "extension"
                                  (trie-fixture-root-shape trie)))
                (return-from
                 eest-trie-test-case-present-delete-to-extension-p
                 t)))
            (mpt-put trie
                     key
                     (eest-trie-test-byte-string
                      (fixture-required-field entry "value")
                      (format nil "EEST trie test case ~A in entry value"
                              (fixture-required-field case "name"))))))))
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
         (input-forms
           (mapcar (lambda (case)
                     (fixture-required-field case "inputForm"))
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
         (proof-present-counts
           (loop for case in cases
                 collect
                 (multiple-value-bind (present-count missing-count)
                     (eest-trie-test-final-proof-counts case)
                   (declare (ignore missing-count))
                   present-count)))
         (proof-missing-counts
           (loop for case in cases
                 collect
                 (multiple-value-bind (present-count missing-count)
                     (eest-trie-test-final-proof-counts case)
                   (declare (ignore present-count))
                   missing-count)))
         (explicit-output-flags
           (mapcar (lambda (case)
                     (fixture-field-present-p case "expectedOut"))
                   cases))
         (explicit-output-entry-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedOut")
                         (length (fixture-object-field case "expectedOut"))
                         0))
                   cases))
         (explicit-output-present-counts
           (loop for case in cases
                 collect
                 (multiple-value-bind (present-count missing-count)
                     (eest-trie-test-explicit-output-counts case)
                   (declare (ignore missing-count))
                   present-count)))
         (explicit-output-missing-counts
           (loop for case in cases
                 collect
                 (multiple-value-bind (present-count missing-count)
                     (eest-trie-test-explicit-output-counts case)
                   (declare (ignore present-count))
                   missing-count)))
         (secure-explicit-output-case-count
           (loop for secure-p in secure-flags
                 for output-p in explicit-output-flags
                 count (and secure-p output-p)))
         (plain-explicit-output-case-count
           (loop for secure-p in secure-flags
                 for output-p in explicit-output-flags
                 count (and (not secure-p) output-p)))
         (secure-explicit-output-present-counts
           (loop for secure-p in secure-flags
                 for count in explicit-output-present-counts
                 when secure-p
                   collect count))
         (plain-explicit-output-present-counts
           (loop for secure-p in secure-flags
                 for count in explicit-output-present-counts
                 unless secure-p
                   collect count))
         (secure-explicit-output-missing-counts
           (loop for secure-p in secure-flags
                 for count in explicit-output-missing-counts
                 when secure-p
                   collect count))
         (plain-explicit-output-missing-counts
           (loop for secure-p in secure-flags
                 for count in explicit-output-missing-counts
                 unless secure-p
                   collect count))
         (object-form-explicit-output-case-count
           (loop for input-form in input-forms
                 for output-p in explicit-output-flags
                 count (and (string= "object" input-form) output-p)))
         (secure-object-form-explicit-output-case-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for output-p in explicit-output-flags
                 count (and secure-p
                            (string= "object" input-form)
                            output-p)))
         (plain-object-form-explicit-output-case-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for output-p in explicit-output-flags
                 count (and (not secure-p)
                            (string= "object" input-form)
                            output-p)))
         (object-form-explicit-output-present-counts
           (loop for input-form in input-forms
                 for count in explicit-output-present-counts
                 when (string= "object" input-form)
                   collect count))
         (object-form-explicit-output-missing-counts
           (loop for input-form in input-forms
                 for count in explicit-output-missing-counts
                 when (string= "object" input-form)
                   collect count))
         (secure-proof-present-counts
           (loop for secure-p in secure-flags
                 for count in proof-present-counts
                 when secure-p
                   collect count))
         (plain-proof-present-counts
           (loop for secure-p in secure-flags
                 for count in proof-present-counts
                 unless secure-p
                   collect count))
         (secure-proof-missing-counts
           (loop for secure-p in secure-flags
                 for count in proof-missing-counts
                 when secure-p
                   collect count))
         (plain-proof-missing-counts
           (loop for secure-p in secure-flags
                 for count in proof-missing-counts
                 unless secure-p
                   collect count))
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
         (final-entry-pair-counts
           (mapcar (lambda (trie)
                     (length (mpt-entry-pairs trie)))
                   tries))
         (secure-final-entry-pair-counts
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 when secure-p
                   collect count))
         (plain-final-entry-pair-counts
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 unless secure-p
                   collect count))
         (final-entry-pair-replay-case-count
           (count-if #'plusp final-entry-pair-counts))
         (entry-range-replay-case-count
           (length cases))
         (non-empty-entry-range-replay-case-count
           (count-if #'plusp final-entry-pair-counts))
         (bounded-entry-range-replay-case-count
           (count-if (lambda (count)
                       (> count 2))
                     final-entry-pair-counts))
         (secure-entry-range-replay-case-count
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 count (and secure-p (plusp count))))
         (plain-entry-range-replay-case-count
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 count (and (not secure-p) (plusp count))))
         (secure-final-entry-pair-replay-case-count
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 count (and secure-p (plusp count))))
         (plain-final-entry-pair-replay-case-count
           (loop for secure-p in secure-flags
                 for count in final-entry-pair-counts
                 count (and (not secure-p) (plusp count))))
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
         (branch-child-shapes
           (loop for shape in root-shapes
                 for trie in tries
                 when (string= "branch" shape)
                   append
                   (mapcar (lambda (index)
                             (trie-fixture-root-child-shape trie index))
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
         (secure-branch-child-shapes
           (loop for secure-p in secure-flags
                 for shape in root-shapes
                 for trie in tries
                 when (and secure-p
                           (string= "branch" shape))
                   append
                   (mapcar (lambda (index)
                             (trie-fixture-root-child-shape trie index))
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
         (branch-child-delete-plain-leaf-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and (not secure-p)
                            (eest-trie-test-case-valueless-branch-delete-to-leaf-p
                             case))))
         (branch-child-delete-plain-branch-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and (not secure-p)
                            (eest-trie-test-case-valueless-branch-delete-keeps-branch-p
                             case))))
         (branch-child-delete-secure-branch-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and secure-p
                            (eest-trie-test-case-valueless-branch-delete-keeps-branch-p
                             case))))
         (extension-delete-plain-leaf-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and (not secure-p)
                            (eest-trie-test-case-extension-delete-to-leaf-p
                             case))))
         (extension-delete-secure-leaf-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and secure-p
                            (eest-trie-test-case-extension-delete-to-leaf-p
                             case))))
         (extension-delete-plain-extension-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and (not secure-p)
                            (eest-trie-test-case-present-delete-to-extension-p
                             case))))
         (extension-delete-secure-extension-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and secure-p
                            (eest-trie-test-case-present-delete-to-extension-p
                             case))))
         (branch-delete-root-count
           (loop for delete-count in delete-counts
                 for shape in root-shapes
                 count (and (plusp delete-count)
                            (string= "branch" shape))))
         (overwritten-key-case-count
           (count-if #'eest-trie-test-case-overwrites-key-p cases))
         (secure-overwritten-key-case-count
           (loop for secure-p in secure-flags
                 for case in cases
                 count (and secure-p
                            (eest-trie-test-case-overwrites-key-p case))))
         (secure-branch-overwrite-root-count
           (loop for secure-p in secure-flags
                 for case in cases
                 for shape in root-shapes
                 count (and secure-p
                            (string= "branch" shape)
                            (eest-trie-test-case-overwrites-key-p case))))
         (secure-extension-overwrite-root-count
           (loop for secure-p in secure-flags
                 for case in cases
                 for shape in root-shapes
                 count (and secure-p
                            (string= "extension" shape)
                            (eest-trie-test-case-overwrites-key-p case))))
         (leaf-missing-delete-root-count
           (loop for case in cases
                 for shape in root-shapes
                 count (and (string= "leaf" shape)
                            (eest-trie-test-case-missing-delete-p case))))
         (secure-branch-missing-delete-root-count
           (loop for secure-p in secure-flags
                 for case in cases
                 for shape in root-shapes
                 count (and secure-p
                            (string= "branch" shape)
                            (eest-trie-test-case-missing-delete-p case))))
         (secure-extension-missing-delete-root-count
           (loop for secure-p in secure-flags
                 for case in cases
                 for shape in root-shapes
                 count (and secure-p
                            (string= "extension" shape)
                            (eest-trie-test-case-missing-delete-p case))))
         (hex-byte-string-entry-count
           (loop for entries in entries-by-case
                 sum (count-if
                      (lambda (entry)
                        (or (eest-trie-test-entry-hex-key-p entry)
                            (eest-trie-test-entry-hex-value-p entry)))
                      entries)))
         (hex-value-entry-count
           (loop for entries in entries-by-case
                 sum (count-if #'eest-trie-test-entry-hex-value-p entries)))
         (secure-hex-value-entry-count
           (loop for secure-p in secure-flags
                 for entries in entries-by-case
                 when secure-p
                   sum (count-if #'eest-trie-test-entry-hex-value-p
                                 entries)))
         (plain-hex-value-entry-count
           (loop for secure-p in secure-flags
                 for entries in entries-by-case
                 unless secure-p
                   sum (count-if #'eest-trie-test-entry-hex-value-p
                                 entries)))
         (secure-object-form-hex-value-entry-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for entries in entries-by-case
                 when (and secure-p
                           (string= "object" input-form))
                   sum (count-if #'eest-trie-test-entry-hex-value-p
                                 entries)))
         (plain-object-form-hex-value-entry-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for entries in entries-by-case
                 when (and (not secure-p)
                           (string= "object" input-form))
                   sum (count-if #'eest-trie-test-entry-hex-value-p
                                 entries)))
         (empty-value-delete-entry-count
           (loop for entries in entries-by-case
                 sum (count-if
                      #'eest-trie-test-entry-empty-value-delete-p
                      entries)))
         (hex-empty-value-delete-entry-count
           (loop for entries in entries-by-case
                 sum (count-if
                      #'eest-trie-test-entry-hex-empty-value-delete-p
                      entries)))
         (string-empty-value-delete-entry-count
           (loop for entries in entries-by-case
                 sum (count-if
                      #'eest-trie-test-entry-string-empty-value-delete-p
                      entries)))
         (object-form-delete-entry-count
           (loop for input-form in input-forms
                 for entries in entries-by-case
                 when (string= "object" input-form)
                   sum (count-if
                        (lambda (entry)
                          (fixture-field-present-p entry "delete"))
                        entries)))
         (object-form-empty-value-delete-entry-count
           (loop for input-form in input-forms
                 for entries in entries-by-case
                 when (string= "object" input-form)
                   sum (count-if
                        #'eest-trie-test-entry-empty-value-delete-p
                        entries)))
         (object-form-string-empty-value-delete-entry-count
           (loop for input-form in input-forms
                 for entries in entries-by-case
                 when (string= "object" input-form)
                   sum (count-if
                        #'eest-trie-test-entry-string-empty-value-delete-p
                        entries)))
         (object-form-write-only-case-count
           (loop for input-form in input-forms
                 for write-count in write-counts
                 for delete-count in delete-counts
                 count (and (string= "object" input-form)
                            (plusp write-count)
                            (zerop delete-count))))
         (secure-object-form-case-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 count (and secure-p
                            (string= "object" input-form))))
         (object-form-permutation-counts
           (mapcar #'eest-trie-test-object-form-permutation-count cases))
         (secure-object-form-permutation-counts
           (loop for secure-p in secure-flags
                 for count in object-form-permutation-counts
                 when secure-p
                   collect count))
         (plain-object-form-permutation-counts
           (loop for secure-p in secure-flags
                 for count in object-form-permutation-counts
                 unless secure-p
                   collect count))
         (secure-object-form-delete-entry-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for entries in entries-by-case
                 when (and secure-p
                           (string= "object" input-form))
                   sum (count-if
                        (lambda (entry)
                          (fixture-field-present-p entry "delete"))
                        entries)))
         (secure-object-form-empty-value-delete-entry-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for entries in entries-by-case
                 when (and secure-p
                           (string= "object" input-form))
                   sum (count-if
                        #'eest-trie-test-entry-empty-value-delete-p
                        entries)))
         (plain-object-form-empty-value-delete-entry-count
           (loop for secure-p in secure-flags
                 for input-form in input-forms
                 for entries in entries-by-case
                 when (and (not secure-p)
                           (string= "object" input-form))
                   sum (count-if
                        #'eest-trie-test-entry-empty-value-delete-p
                        entries)))
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
     (cons "inputForms" input-forms)
     (cons "objectFormCaseCount"
           (count "object" input-forms :test #'string=))
     (cons "objectFormDeleteEntryCount" object-form-delete-entry-count)
     (cons "objectFormEmptyValueDeleteEntryCount"
           object-form-empty-value-delete-entry-count)
     (cons "objectFormWriteOnlyCaseCount" object-form-write-only-case-count)
     (cons "secureObjectFormCaseCount" secure-object-form-case-count)
     (cons "objectFormPermutationReplayCount"
           (reduce #'+ object-form-permutation-counts :initial-value 0))
     (cons "secureObjectFormPermutationReplayCount"
           (reduce #'+
                   secure-object-form-permutation-counts
                   :initial-value 0))
     (cons "plainObjectFormPermutationReplayCount"
           (reduce #'+
                   plain-object-form-permutation-counts
                   :initial-value 0))
     (cons "secureObjectFormDeleteEntryCount"
           secure-object-form-delete-entry-count)
     (cons "secureObjectFormEmptyValueDeleteEntryCount"
           secure-object-form-empty-value-delete-entry-count)
     (cons "plainObjectFormEmptyValueDeleteEntryCount"
           plain-object-form-empty-value-delete-entry-count)
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
     (cons "branchChildShapes" branch-child-shapes)
     (cons "branchChildBranchCount"
           (count "branch" branch-child-shapes :test #'string=))
     (cons "branchChildExtensionCount"
           (count "extension" branch-child-shapes :test #'string=))
     (cons "secureBranchChildReferenceKinds"
           secure-branch-child-reference-kinds)
     (cons "secureBranchChildShapes" secure-branch-child-shapes)
     (cons "secureBranchChildBranchCount"
           (count "branch" secure-branch-child-shapes :test #'string=))
     (cons "secureBranchChildExtensionCount"
           (count "extension" secure-branch-child-shapes :test #'string=))
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
     (cons "branchChildDeletePlainLeafCount"
           branch-child-delete-plain-leaf-count)
     (cons "branchChildDeletePlainBranchCount"
           branch-child-delete-plain-branch-count)
     (cons "branchChildDeleteSecureBranchCount"
           branch-child-delete-secure-branch-count)
     (cons "extensionDeletePlainLeafCount"
           extension-delete-plain-leaf-count)
     (cons "extensionDeleteSecureLeafCount"
           extension-delete-secure-leaf-count)
     (cons "extensionDeletePlainExtensionCount"
           extension-delete-plain-extension-count)
     (cons "extensionDeleteSecureExtensionCount"
           extension-delete-secure-extension-count)
     (cons "branchDeleteRootCount" branch-delete-root-count)
     (cons "overwrittenKeyCaseCount" overwritten-key-case-count)
     (cons "secureOverwrittenKeyCaseCount"
           secure-overwritten-key-case-count)
     (cons "secureBranchOverwriteRootCount"
           secure-branch-overwrite-root-count)
     (cons "secureExtensionOverwriteRootCount"
           secure-extension-overwrite-root-count)
     (cons "leafMissingDeleteRootCount" leaf-missing-delete-root-count)
     (cons "secureBranchMissingDeleteRootCount"
           secure-branch-missing-delete-root-count)
     (cons "secureExtensionMissingDeleteRootCount"
           secure-extension-missing-delete-root-count)
     (cons "hexByteStringEntryCount" hex-byte-string-entry-count)
     (cons "hexValueEntryCount" hex-value-entry-count)
     (cons "secureHexValueEntryCount" secure-hex-value-entry-count)
     (cons "plainHexValueEntryCount" plain-hex-value-entry-count)
     (cons "secureObjectFormHexValueEntryCount"
           secure-object-form-hex-value-entry-count)
     (cons "plainObjectFormHexValueEntryCount"
           plain-object-form-hex-value-entry-count)
     (cons "emptyValueDeleteEntryCount" empty-value-delete-entry-count)
     (cons "hexEmptyValueDeleteEntryCount"
           hex-empty-value-delete-entry-count)
     (cons "stringEmptyValueDeleteEntryCount"
           string-empty-value-delete-entry-count)
     (cons "objectFormStringEmptyValueDeleteEntryCount"
           object-form-string-empty-value-delete-entry-count)
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
     (cons "finalEntryPairCounts" final-entry-pair-counts)
     (cons "finalEntryPairCount"
           (reduce #'+ final-entry-pair-counts :initial-value 0))
     (cons "finalEntryPairReplayCaseCount"
           final-entry-pair-replay-case-count)
     (cons "secureFinalEntryPairCount"
           (reduce #'+ secure-final-entry-pair-counts :initial-value 0))
     (cons "plainFinalEntryPairCount"
           (reduce #'+ plain-final-entry-pair-counts :initial-value 0))
     (cons "secureFinalEntryPairReplayCaseCount"
           secure-final-entry-pair-replay-case-count)
     (cons "plainFinalEntryPairReplayCaseCount"
           plain-final-entry-pair-replay-case-count)
     (cons "entryRangeReplayCaseCount"
           entry-range-replay-case-count)
     (cons "nonEmptyEntryRangeReplayCaseCount"
           non-empty-entry-range-replay-case-count)
     (cons "boundedEntryRangeReplayCaseCount"
           bounded-entry-range-replay-case-count)
     (cons "secureEntryRangeReplayCaseCount"
           secure-entry-range-replay-case-count)
     (cons "plainEntryRangeReplayCaseCount"
           plain-entry-range-replay-case-count)
     (cons "writeEntryCounts" write-counts)
     (cons "totalWriteEntryCount" (reduce #'+ write-counts :initial-value 0))
     (cons "proofPresentKeyCounts" proof-present-counts)
     (cons "proofPresentKeyCount"
           (reduce #'+ proof-present-counts :initial-value 0))
     (cons "secureProofPresentKeyCount"
           (reduce #'+ secure-proof-present-counts :initial-value 0))
     (cons "plainProofPresentKeyCount"
           (reduce #'+ plain-proof-present-counts :initial-value 0))
     (cons "proofMissingKeyCounts" proof-missing-counts)
     (cons "proofMissingKeyCount"
           (reduce #'+ proof-missing-counts :initial-value 0))
     (cons "secureProofMissingKeyCount"
           (reduce #'+ secure-proof-missing-counts :initial-value 0))
     (cons "plainProofMissingKeyCount"
           (reduce #'+ plain-proof-missing-counts :initial-value 0))
     (cons "explicitOutputCaseCount"
           (count t explicit-output-flags))
     (cons "secureExplicitOutputCaseCount"
           secure-explicit-output-case-count)
     (cons "plainExplicitOutputCaseCount"
           plain-explicit-output-case-count)
     (cons "explicitOutputEntryCounts"
           explicit-output-entry-counts)
     (cons "explicitOutputEntryCount"
           (reduce #'+ explicit-output-entry-counts :initial-value 0))
     (cons "explicitOutputPresentKeyCount"
           (reduce #'+ explicit-output-present-counts :initial-value 0))
     (cons "secureExplicitOutputPresentKeyCount"
           (reduce #'+ secure-explicit-output-present-counts :initial-value 0))
     (cons "plainExplicitOutputPresentKeyCount"
           (reduce #'+ plain-explicit-output-present-counts :initial-value 0))
     (cons "explicitOutputMissingKeyCount"
           (reduce #'+ explicit-output-missing-counts :initial-value 0))
     (cons "secureExplicitOutputMissingKeyCount"
           (reduce #'+ secure-explicit-output-missing-counts :initial-value 0))
     (cons "plainExplicitOutputMissingKeyCount"
           (reduce #'+ plain-explicit-output-missing-counts :initial-value 0))
     (cons "objectFormExplicitOutputCaseCount"
           object-form-explicit-output-case-count)
     (cons "secureObjectFormExplicitOutputCaseCount"
           secure-object-form-explicit-output-case-count)
     (cons "plainObjectFormExplicitOutputCaseCount"
           plain-object-form-explicit-output-case-count)
     (cons "objectFormExplicitOutputPresentKeyCount"
           (reduce #'+ object-form-explicit-output-present-counts
                   :initial-value 0))
     (cons "objectFormExplicitOutputMissingKeyCount"
           (reduce #'+ object-form-explicit-output-missing-counts
                   :initial-value 0))
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
  (validate-trie-reference-case-requirements
   cases
   +phase-a-eest-trie-reference-case-requirements+
   "Phase A EEST trie subset")
  (validate-trie-reference-explicit-output-requirements
   cases
   +phase-a-eest-trie-explicit-output-reference-case-names+
   "Phase A EEST trie subset")
  (let ((summary (eest-trie-test-case-summary cases)))
    (when (zerop (fixture-object-field summary "secureCaseCount"))
      (error "Phase A EEST trie subset must include a secure trie case"))
    (when (zerop (fixture-object-field summary "plainCaseCount"))
      (error "Phase A EEST trie subset must include a plain trie case"))
    (when (zerop (fixture-object-field summary "objectFormCaseCount"))
      (error "Phase A EEST trie subset must include an object-form input case"))
    (when (zerop (fixture-object-field summary "objectFormDeleteEntryCount"))
      (error "Phase A EEST trie subset must include an object-form delete entry"))
    (when (zerop (fixture-object-field summary "objectFormEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include an object-form empty-value delete entry"))
    (when (zerop (fixture-object-field summary "objectFormWriteOnlyCaseCount"))
      (error "Phase A EEST trie subset must include an object-form write-only case"))
    (when (zerop (fixture-object-field summary "objectFormPermutationReplayCount"))
      (error "Phase A EEST trie subset must include object-form permutation replay"))
    (when (zerop (fixture-object-field summary "secureObjectFormCaseCount"))
      (error "Phase A EEST trie subset must include a secure object-form input case"))
    (when (zerop (fixture-object-field summary "secureObjectFormPermutationReplayCount"))
      (error "Phase A EEST trie subset must include secure object-form permutation replay"))
    (when (zerop (fixture-object-field summary "plainObjectFormPermutationReplayCount"))
      (error "Phase A EEST trie subset must include plain object-form permutation replay"))
    (when (zerop (fixture-object-field summary "secureObjectFormDeleteEntryCount"))
      (error "Phase A EEST trie subset must include a secure object-form delete entry"))
    (when (zerop (fixture-object-field summary "secureObjectFormEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include a secure object-form empty-value delete entry"))
    (when (zerop (fixture-object-field summary "plainObjectFormEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include a plain object-form empty-value delete entry"))
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
    (when (zerop (fixture-object-field summary "finalEntryPairReplayCaseCount"))
      (error "Phase A EEST trie subset must include final entry-pair replay"))
    (when (zerop (fixture-object-field summary "secureFinalEntryPairReplayCaseCount"))
      (error "Phase A EEST trie subset must include secure final entry-pair replay"))
    (when (zerop (fixture-object-field summary "plainFinalEntryPairReplayCaseCount"))
      (error "Phase A EEST trie subset must include plain final entry-pair replay"))
    (when (zerop (fixture-object-field summary "entryRangeReplayCaseCount"))
      (error "Phase A EEST trie subset must include entry range replay"))
    (when (zerop (fixture-object-field summary "nonEmptyEntryRangeReplayCaseCount"))
      (error "Phase A EEST trie subset must include non-empty entry range replay"))
    (when (zerop (fixture-object-field summary "boundedEntryRangeReplayCaseCount"))
      (error "Phase A EEST trie subset must include bounded entry range replay"))
    (when (zerop (fixture-object-field summary "secureEntryRangeReplayCaseCount"))
      (error "Phase A EEST trie subset must include secure entry range replay"))
    (when (zerop (fixture-object-field summary "plainEntryRangeReplayCaseCount"))
      (error "Phase A EEST trie subset must include plain entry range replay"))
    (when (zerop (fixture-object-field summary "proofPresentKeyCount"))
      (error "Phase A EEST trie subset must include present-key proof coverage"))
    (when (zerop (fixture-object-field summary "proofMissingKeyCount"))
      (error "Phase A EEST trie subset must include missing-key proof coverage"))
    (when (zerop (fixture-object-field summary "secureProofPresentKeyCount"))
      (error "Phase A EEST trie subset must include secure present-key proof coverage"))
    (when (zerop (fixture-object-field summary "secureProofMissingKeyCount"))
      (error "Phase A EEST trie subset must include secure missing-key proof coverage"))
    (when (zerop (fixture-object-field summary "plainProofPresentKeyCount"))
      (error "Phase A EEST trie subset must include plain present-key proof coverage"))
    (when (zerop (fixture-object-field summary "plainProofMissingKeyCount"))
      (error "Phase A EEST trie subset must include plain missing-key proof coverage"))
    (when (zerop (fixture-object-field summary "explicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include explicit out assertions"))
    (when (zerop (fixture-object-field summary "secureExplicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include secure explicit out assertions"))
    (when (zerop (fixture-object-field summary "plainExplicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include plain explicit out assertions"))
    (when (zerop (fixture-object-field summary "explicitOutputPresentKeyCount"))
      (error "Phase A EEST trie subset must include present-key explicit out assertions"))
    (when (zerop (fixture-object-field summary "explicitOutputMissingKeyCount"))
      (error "Phase A EEST trie subset must include missing-key explicit out assertions"))
    (when (zerop (fixture-object-field summary "objectFormExplicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include object-form explicit out assertions"))
    (when (zerop (fixture-object-field summary "secureObjectFormExplicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include secure object-form explicit out assertions"))
    (when (zerop (fixture-object-field summary "plainObjectFormExplicitOutputCaseCount"))
      (error "Phase A EEST trie subset must include plain object-form explicit out assertions"))
    (when (zerop (fixture-object-field summary "objectFormExplicitOutputPresentKeyCount"))
      (error "Phase A EEST trie subset must include object-form present-key explicit out assertions"))
    (when (zerop (fixture-object-field summary "objectFormExplicitOutputMissingKeyCount"))
      (error "Phase A EEST trie subset must include object-form missing-key explicit out assertions"))
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
    (when (zerop (fixture-object-field summary "secureBranchChildBranchCount"))
      (error "Phase A EEST trie subset must include a secure branch root with a branch child"))
    (when (zerop (fixture-object-field summary "secureBranchChildExtensionCount"))
      (error "Phase A EEST trie subset must include a secure branch root with an extension child"))
    (when (zerop (fixture-object-field summary "branchChildExtensionCount"))
      (error "Phase A EEST trie subset must include a branch root with an extension child"))
    (when (zerop (fixture-object-field summary "branchChildBranchCount"))
      (error "Phase A EEST trie subset must include a branch root with a branch child"))
    (when (zerop (fixture-object-field summary "branchValueRootCount"))
      (error "Phase A EEST trie subset must include a branch root value"))
    (when (zerop (fixture-object-field summary "branchValueZeroChildRootCount"))
      (error "Phase A EEST trie subset must include a branch root value with child index 0"))
    (when (zerop (fixture-object-field summary "emptyKeyDeleteNonEmptyRootCount"))
      (error "Phase A EEST trie subset must include an empty-key delete with a non-empty final root"))
    (when (zerop (fixture-object-field summary "branchChildDeleteValueLeafCount"))
      (error "Phase A EEST trie subset must include a branch child delete that preserves a root value leaf"))
    (when (zerop (fixture-object-field summary "branchChildDeletePlainLeafCount"))
      (error "Phase A EEST trie subset must include a branch child delete that collapses a valueless branch to a leaf"))
    (when (zerop (fixture-object-field summary "branchChildDeletePlainBranchCount"))
      (error "Phase A EEST trie subset must include a branch child delete that preserves a valueless branch root"))
    (when (zerop (fixture-object-field summary "branchChildDeleteSecureBranchCount"))
      (error "Phase A EEST trie subset must include a secure branch child delete that preserves a valueless branch root"))
    (when (zerop (fixture-object-field summary "extensionDeletePlainLeafCount"))
      (error "Phase A EEST trie subset must include an extension child delete that collapses to a leaf"))
    (when (zerop (fixture-object-field summary "extensionDeleteSecureLeafCount"))
      (error "Phase A EEST trie subset must include a secure extension child delete that collapses to a leaf"))
    (when (zerop (fixture-object-field summary "extensionDeletePlainExtensionCount"))
      (error "Phase A EEST trie subset must include a delete that preserves an extension root"))
    (when (zerop (fixture-object-field summary "extensionDeleteSecureExtensionCount"))
      (error "Phase A EEST trie subset must include a secure delete that preserves an extension root"))
    (when (zerop (fixture-object-field summary "branchDeleteRootCount"))
      (error "Phase A EEST trie subset must include a branch-root delete case"))
    (when (zerop (fixture-object-field summary "overwrittenKeyCaseCount"))
      (error "Phase A EEST trie subset must include a duplicate-key overwrite case"))
    (when (zerop (fixture-object-field summary "secureOverwrittenKeyCaseCount"))
      (error "Phase A EEST trie subset must include a secure duplicate-key overwrite case"))
    (when (zerop (fixture-object-field summary "secureBranchOverwriteRootCount"))
      (error "Phase A EEST trie subset must include a secure duplicate-key overwrite that preserves a branch root"))
    (when (zerop (fixture-object-field summary "secureExtensionOverwriteRootCount"))
      (error "Phase A EEST trie subset must include a secure duplicate-key overwrite that preserves an extension root"))
    (when (zerop (fixture-object-field summary "leafMissingDeleteRootCount"))
      (error "Phase A EEST trie subset must include a leaf-root missing-delete case"))
    (when (zerop (fixture-object-field summary "secureBranchMissingDeleteRootCount"))
      (error "Phase A EEST trie subset must include a secure branch-root missing-delete case"))
    (when (zerop (fixture-object-field summary "secureExtensionMissingDeleteRootCount"))
      (error "Phase A EEST trie subset must include a secure extension-root missing-delete case"))
    (when (zerop (fixture-object-field summary "hexByteStringEntryCount"))
      (error "Phase A EEST trie subset must include hex byte-string keys or values"))
    (when (zerop (fixture-object-field summary "hexValueEntryCount"))
      (error "Phase A EEST trie subset must include a hex byte-string value"))
    (when (zerop (fixture-object-field summary "secureHexValueEntryCount"))
      (error "Phase A EEST trie subset must include a secure hex byte-string value"))
    (when (zerop (fixture-object-field summary "plainHexValueEntryCount"))
      (error "Phase A EEST trie subset must include a plain hex byte-string value"))
    (when (zerop (fixture-object-field summary "secureObjectFormHexValueEntryCount"))
      (error "Phase A EEST trie subset must include a secure object-form hex byte-string value"))
    (when (zerop (fixture-object-field summary "plainObjectFormHexValueEntryCount"))
      (error "Phase A EEST trie subset must include a plain object-form hex byte-string value"))
    (when (zerop (fixture-object-field summary "emptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include an empty-value delete"))
    (when (zerop (fixture-object-field summary "hexEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include a 0x empty-value delete"))
    (when (zerop (fixture-object-field summary "stringEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include a string empty-value delete"))
    (when (zerop (fixture-object-field summary "objectFormStringEmptyValueDeleteEntryCount"))
      (error "Phase A EEST trie subset must include an object-form string empty-value delete"))
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

(defun trie-fixture-node-shape (node)
  (cond
    ((null node) "empty")
    ((typep node 'ethereum-lisp.trie::leaf-node) "leaf")
    ((typep node 'ethereum-lisp.trie::extension-node) "extension")
    ((typep node 'ethereum-lisp.trie::branch-node) "branch")
    (t "unknown")))

(defun trie-fixture-root-shape (trie)
  (let ((root (mpt-root-node trie)))
    (trie-fixture-node-shape root)))

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

(defun trie-fixture-root-child-shape (trie index)
  (let ((root (mpt-root-node trie)))
    (when (typep root 'ethereum-lisp.trie::branch-node)
      (trie-fixture-node-shape
       (aref (ethereum-lisp.trie::branch-node-children root)
             index)))))

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

(defun trie-fixture-root-value-bytes (trie)
  (let ((root (mpt-root-node trie)))
    (cond
      ((typep root 'ethereum-lisp.trie::leaf-node)
       (ethereum-lisp.trie::leaf-node-value root))
      ((typep root 'ethereum-lisp.trie::branch-node)
       (ethereum-lisp.trie::branch-node-value root)))))

(defun trie-fixture-root-value (trie)
  (bytes-to-ascii (trie-fixture-root-value-bytes trie)))

(defun trie-fixture-key (object)
  (or (let ((hex (fixture-object-field object "keyHex")))
        (when hex (hex-to-bytes hex)))
      (ascii-to-bytes (fixture-object-field object "keyAscii"))))

(defun trie-fixture-value (object)
  (or (let ((hex (fixture-object-field object "valueHex")))
        (when hex (hex-to-bytes hex)))
      (ascii-to-bytes (fixture-object-field object "valueAscii"))))

(defun trie-fixture-secure-key-p (case)
  (not (null (fixture-object-field case "secure"))))

(defun trie-fixture-trie-key (case object)
  (let ((key (trie-fixture-key object)))
    (if (trie-fixture-secure-key-p case)
        (keccak-256 key)
        key)))

(defun trie-fixture-entry-range-bound (case object prefix)
  (let* ((hex-field (format nil "~AKeyHex" prefix))
         (ascii-field (format nil "~AKeyAscii" prefix))
         (key (or (let ((hex (fixture-object-field object hex-field)))
                    (when hex (hex-to-bytes hex)))
                  (let ((ascii (fixture-object-field object ascii-field)))
                    (when ascii (ascii-to-bytes ascii))))))
    (when key
      (if (trie-fixture-secure-key-p case)
          (keccak-256 key)
          key))))

(defun apply-trie-fixture-operation (trie case operation)
  (let ((op (fixture-object-field operation "op"))
        (key (trie-fixture-trie-key case operation)))
    (cond
      ((string= op "put")
       (mpt-put trie key (trie-fixture-value operation)))
      ((string= op "delete")
       (mpt-delete trie key))
      (t (error "Unknown trie fixture operation: ~A" op)))))

(defun run-trie-fixture-case-with-root-history (case)
  (let ((trie (make-mpt)))
    (values
     trie
     (loop for operation in (fixture-object-field case "operations")
           do (apply-trie-fixture-operation trie case operation)
           collect (mpt-root-hex trie)))))

(defun run-trie-fixture-case (case)
  (nth-value 0 (run-trie-fixture-case-with-root-history case)))

(defun trie-fixture-final-operation-state (case)
  (let ((entries '()))
    (dolist (operation (fixture-object-field case "operations"))
      (let ((key (trie-fixture-trie-key case operation))
            (op (fixture-object-field operation "op")))
        (setf entries (remove key entries :key #'car :test #'bytes=))
        (cond
          ((string= op "put")
           (let ((value (trie-fixture-value operation)))
             (push (cons key (and (plusp (length value)) value)) entries)))
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

(defun trie-fixture-case-tag-p (case tag)
  (not (null (member tag (fixture-object-field case "tags")
                     :test #'string=))))

(defun assert-trie-fixture-intermediate-roots (roots case)
  (let ((expected-roots
          (fixture-object-field case "expectedIntermediateRoots")))
    (when expected-roots
      (is (= (length expected-roots) (length roots)))
      (loop for expected-root in expected-roots
            for actual-root in roots
            do (is (string= expected-root actual-root))))))

(defun assert-trie-fixture-entry-pair-replay (trie case)
  (when (trie-fixture-case-tag-p case "entry-pair-replay")
    (let ((entries (mpt-entry-pairs trie))
          (rebuilt (make-mpt)))
      (dolist (entry entries)
        (mpt-put rebuilt (car entry) (cdr entry)))
      (is (string= (mpt-root-hex trie)
                   (mpt-root-hex rebuilt)))
      (dolist (entry entries)
        (is (bytes= (cdr entry)
                    (mpt-get rebuilt (car entry)))))
      (let ((expected-entries
              (fixture-object-field case "expectedEntryPairs")))
        (when expected-entries
          (is (= (length expected-entries) (length entries)))
          (loop for expected in expected-entries
                for actual in entries
                do (is (bytes= (trie-fixture-trie-key case expected)
                               (car actual)))
                   (is (bytes= (trie-fixture-value expected)
                               (cdr actual)))))))))

(defun assert-trie-fixture-entry-ranges (trie case)
  (dolist (expected (fixture-object-field case "expectedEntryRanges"))
    (let* ((start (trie-fixture-entry-range-bound case expected "start"))
           (end (trie-fixture-entry-range-bound case expected "end"))
           (actual-keys
             (mapcar #'car
                     (mpt-entry-range trie :start start :end end)))
           (expected-keys
             (mapcar (lambda (key-entry)
                       (trie-fixture-trie-key case key-entry))
                     (fixture-required-field expected "expectedKeys"))))
      (is (= (length expected-keys) (length actual-keys)))
      (loop for expected-key in expected-keys
            for actual-key in actual-keys
            do (is (bytes= expected-key actual-key))))))

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

(defun assert-trie-fixture-proof-prefixes (trie case)
  (dolist (expected (fixture-object-field case "expectedProofPrefixes"))
    (let* ((key (trie-fixture-trie-key case expected))
           (proof (mpt-get-proof trie key))
           (node-rlps (fixture-required-field expected "nodeRlps")))
      (if (fixture-object-field expected "exactLength")
          (is (= (length node-rlps) (length proof)))
          (is (<= (length node-rlps) (length proof))))
      (loop for expected-rlp in node-rlps
            for actual-rlp in proof
            do (is (string= expected-rlp
                            (bytes-to-hex actual-rlp)))))))

(defun assert-trie-fixture-lookups (trie case)
  (dolist (expected (fixture-object-field case "expectedGets"))
    (let ((key (trie-fixture-trie-key case expected))
          (value (trie-fixture-value expected)))
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

(deftest trie-entry-pairs-rebuild-root
  (let ((trie (make-mpt))
        (rebuilt (make-mpt)))
    (dolist (pair '(("dog" . "puppy") ("do" . "verb") ("horse" . "stallion")))
      (mpt-put trie (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (dolist (entry (mpt-entry-pairs trie))
      (mpt-put rebuilt (car entry) (cdr entry)))
    (is (string= (mpt-root-hex trie) (mpt-root-hex rebuilt)))
    (is (equal '("646f" "646f67" "686f727365")
               (mapcar (lambda (entry)
                         (bytes-to-hex (car entry) :prefix nil))
                       (mpt-entry-pairs trie))))))

(deftest trie-entry-range-uses-half-open-lexicographic-bounds
  (let ((trie (make-mpt)))
    (dolist (pair '(("apple" . "fruit1")
                    ("apricot" . "fruit2")
                    ("banana" . "fruit3")
                    ("cherry" . "fruit4")
                    ("date" . "fruit5")
                    ("fig" . "fruit6")
                    ("grape" . "fruit7")))
      (mpt-put trie
               (ascii-to-bytes (car pair))
               (ascii-to-bytes (cdr pair))))
    (is (equal '("banana" "cherry" "date")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :start (ascii-to-bytes "banana")
                        :end (ascii-to-bytes "fig")))))
    (is (equal '("apple" "apricot")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :end (ascii-to-bytes "banana")))))
    (is (equal '("fig" "grape")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :start (ascii-to-bytes "fig")))))
    (is (null (mpt-entry-range
               trie
               :start (ascii-to-bytes "banana")
               :end (ascii-to-bytes "banana"))))))

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

(deftest trie-proof-rejects-tampered-referenced-node
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "key1") (hex-to-bytes "0x63636363"))
    (mpt-put trie
             (ascii-to-bytes "key2")
             (hex-to-bytes
              "0x0101010101010101010101010101010101010101010101010101010101010101"))
    (let* ((proof (mpt-get-proof trie (ascii-to-bytes "key2")))
           (tampered-node (copy-seq (second proof)))
           (tampered-proof (copy-list proof)))
      (is (>= (length proof) 2))
      (setf (aref tampered-node 0)
            (logxor (aref tampered-node 0) #x01))
      (setf (second tampered-proof) tampered-node)
      (signals error
        (mpt-verify-proof
         (mpt-root-hash trie)
         (ascii-to-bytes "key2")
         tampered-proof)))))

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
     (list (cons "name" "non-string-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" 42)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" 42)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "odd-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0x0")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "prefixless-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "00")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "uppercase-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0X00")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-operation-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" 42)))))))
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
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-expected-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" 42))))))))

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
           (cons "source" "seed")
           (cons 42 t)
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
                      (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" 42)
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
     (list (cons "name" 42)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-root")
           (cons "expectedRoot" 42)
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "prefixless-root")
           (cons "expectedRoot"
                 "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "uppercase-root")
           (cons "expectedRoot"
                 "0X56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421")
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
     (list (cons "name" "non-string-shape")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" 42)
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-root-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedRootValueAscii" 42)
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
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
     (list (cons "name" "non-string-child-reference")
           (cons "expectedRoot"
                 "0x1da465b71da985f1e07e3ed8dcd9e678546164ef2b17fb5c46c678fd91429de3")
           (cons "expectedShape" "extension")
           (cons "expectedChildReference" 42)
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "do")
                             (cons "valueAscii" "v")))))))
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
     (list (cons "name" "non-string-child-reference-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons 1 "embedded")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "malformed-child-reference-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1x" "embedded")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-reference-kind")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1" 42)))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "child-shape-on-leaf")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedRootChildShapes"
                 (list (cons "1" "extension")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-shape")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildShapes"
                 (list (cons "1" 42)))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-child-shape")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildShapes"
                 (list (cons "1" "empty")))
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
                 (list (list (cons "keyHex" "0x646f67"))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "entry-pair-without-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedEntryPairs"
                 (list (list (cons "keyAscii" "dog"))))))))

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
     (list (cons "name" "non-string-case-field")
           (cons 42 t)
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
     (list (cons "name" "non-string-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons 42 t)))))))
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
     (list (cons "name" "non-string-get-field")
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
                             (cons 42 t)))))))
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
                             (cons "proof" nil)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-boolean-exact-proof")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedProofPrefixes"
                 (list (list (cons "keyAscii" "dog")
                             (cons "exactLength" "yes")
                             (cons "nodeRlps"
                                   (list "0xc88320646f67857075707079")))))))))

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
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-secure-account-step-3"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-required-case-names
       (remove-if
        (lambda (case)
          (string= "root-branch-mixed-child-references"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-one-element-proof"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-large-value-branch"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-general-range-iteration"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-empty-value-sequence"
                   (fixture-object-field case "name")))
        cases)))
    (let ((+trie-fixture-required-case-names+
            '("single-leaf" "single-leaf")))
      (signals error
        (validate-trie-fixture-required-case-names cases)))
    (validate-trie-reference-case-requirements
     cases
     +trie-fixture-reference-case-requirements+
     "Seed trie fixture")
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("missing-geth-derived-case" . :plain))
       "Seed trie fixture"))
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("geth-secure-account-step-3" . :plain))
       "Seed trie fixture"))
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("geth-long-leaf-value" . :plain)
         ("geth-long-leaf-value" . :plain))
       "Seed trie fixture"))))

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
    (is (string= "array"
                 (fixture-object-field case "inputForm")))
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
    (is (string= "empty-value"
                 (fixture-object-field hex-delete-entry "deleteSource")))
    (is (string= "0x"
                 (fixture-object-field hex-delete-entry "deleteSourceValue")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((cases (load-eest-trie-test-file +eest-trie-test-secure-sample-path+))
         (case (first cases))
         (branch-child-branch-case (second cases))
         (branch-child-extension-case (third cases))
         (branch-update-case (fourth cases))
         (delete-case (fifth cases))
         (delete-branch-child-case (sixth cases))
         (delete-branch-child-keeps-branch-case (seventh cases))
         (delete-branch-sibling-case (eighth cases))
         (delete-extension-child-case (ninth cases))
         (duplicate-overwrite-case (nth 9 cases))
         (extension-case (nth 10 cases))
         (extension-update-case (nth 11 cases))
         (insert-case (nth 12 cases))
         (missing-delete-branch-case (nth 13 cases))
         (missing-delete-extension-case (nth 14 cases))
         (object-branch-case (nth 15 cases))
         (object-empty-value-delete-case (nth 16 cases))
         (object-missing-delete-case (nth 17 cases))
         (object-hex-byte-case (nth 18 cases))
         (hex-byte-delete-case (nth 19 cases))
         (geth-secure-account-step-1-case (nth 20 cases))
         (geth-secure-account-step-2-case (nth 21 cases))
         (geth-secure-account-step-3-case (nth 22 cases))
         (geth-secure-delete-case (nth 23 cases))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 24 (length cases)))
    (is (string= "phase-a-secure-branch"
                 (fixture-object-field case "name")))
    (is (fixture-object-field case "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie)))
    (is (string= "phase-a-secure-branch-child-branch"
                 (fixture-object-field branch-child-branch-case "name")))
    (is (fixture-object-field branch-child-branch-case "secure"))
    (is (string= "0x626be931db190ef431bdb5638866b8aa95af9384f3ee1c88c3065ec971a17b88"
                 (fixture-object-field branch-child-branch-case "root")))
    (is (string= "phase-a-secure-branch-child-extension"
                 (fixture-object-field branch-child-extension-case "name")))
    (is (fixture-object-field branch-child-extension-case "secure"))
    (is (string= "0x5f8d3f000e83f459e92adbebecb70ac84fc99fd16ee2e6b5a5b400b7d6e974b4"
                 (fixture-object-field branch-child-extension-case "root")))
    (is (string= "phase-a-secure-branch-update-keeps-branch"
                 (fixture-object-field branch-update-case "name")))
    (is (fixture-object-field branch-update-case "secure"))
    (is (string= "0xf853f5608648461d01d9b7df43a7723db3a35d69c80efb1482f9d5a093038f2d"
                 (fixture-object-field branch-update-case "root")))
    (is (string= "phase-a-secure-extension"
                 (fixture-object-field extension-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field extension-case "root")))
    (is (string= "phase-a-secure-extension-update-keeps-extension"
                 (fixture-object-field extension-update-case "name")))
    (is (fixture-object-field extension-update-case "secure"))
    (is (string= "0xa2e17a0ab859cc7b48061c3cc6617389e39a5a12791460d6c14047a0d4b89f69"
                 (fixture-object-field extension-update-case "root")))
    (is (string= "phase-a-secure-delete"
                 (fixture-object-field delete-case "name")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field delete-case "root")))
    (is (string= "phase-a-secure-delete-branch-child"
                 (fixture-object-field delete-branch-child-case "name")))
    (is (string= "0xc8fb1ca12e912e15bb7db6d06ae4967dd3b59a5903f0306dd797dcaab6afcb3b"
                 (fixture-object-field delete-branch-child-case "root")))
    (is (string= "phase-a-secure-delete-branch-child-keeps-branch"
                 (fixture-object-field delete-branch-child-keeps-branch-case "name")))
    (is (string= "0x1d5d556f96abcc20327918d9209473b0709ff666a2723575202cb03388dc0103"
                 (fixture-object-field delete-branch-child-keeps-branch-case "root")))
    (is (string= "phase-a-secure-delete-branch-sibling-collapses-to-extension"
                 (fixture-object-field delete-branch-sibling-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field delete-branch-sibling-case "root")))
    (is (string= "phase-a-secure-delete-extension-child"
                 (fixture-object-field delete-extension-child-case "name")))
    (is (string= "0xc0613970ee4545b8b874a3720590eadfc7258e9232a3edd82d6fef1a86db614f"
                 (fixture-object-field delete-extension-child-case "root")))
    (is (string= "phase-a-secure-duplicate-overwrite"
                 (fixture-object-field duplicate-overwrite-case "name")))
    (is (fixture-object-field duplicate-overwrite-case "secure"))
    (is (string= "0x293455756e50fb29ac430e499f8596798349a543f1a1dbba37880701b5a9c8fc"
                 (fixture-object-field duplicate-overwrite-case "root")))
    (is (string= "phase-a-secure-insert"
                 (fixture-object-field insert-case "name")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field insert-case "root")))
    (is (string= "phase-a-secure-missing-delete-branch"
                 (fixture-object-field missing-delete-branch-case "name")))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field missing-delete-branch-case "root")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field missing-delete-branch-case "entries")))
    (is (string= "phase-a-secure-missing-delete-extension"
                 (fixture-object-field missing-delete-extension-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field missing-delete-extension-case "root")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field missing-delete-extension-case "entries")))
    (is (string= "phase-a-secure-object-form-branch"
                 (fixture-object-field object-branch-case "name")))
    (is (string= "object"
                 (fixture-object-field object-branch-case "inputForm")))
    (is (fixture-object-field object-branch-case "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field object-branch-case "root")))
    (is (string= "phase-a-secure-object-form-empty-value-delete"
                 (fixture-object-field object-empty-value-delete-case "name")))
    (is (string= "object"
                 (fixture-object-field object-empty-value-delete-case
                                       "inputForm")))
    (is (fixture-object-field object-empty-value-delete-case "secure"))
    (is (find-if (lambda (entry)
                   (and (string= "empty-value"
                                 (fixture-object-field entry "deleteSource"))
                        (string= ""
                                 (fixture-object-field entry
                                                       "deleteSourceValue"))))
                 (fixture-object-field object-empty-value-delete-case
                                       "entries")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field object-empty-value-delete-case
                                       "root")))
    (is (string= "phase-a-secure-object-form-missing-delete"
                 (fixture-object-field object-missing-delete-case "name")))
    (is (string= "object"
                 (fixture-object-field object-missing-delete-case "inputForm")))
    (is (fixture-object-field object-missing-delete-case "secure"))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field object-missing-delete-case "entries")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field object-missing-delete-case "root")))
    (is (string= "phase-a-secure-object-form-value-hex-bytes"
                 (fixture-object-field object-hex-byte-case "name")))
    (is (string= "object"
                 (fixture-object-field object-hex-byte-case "inputForm")))
    (is (fixture-object-field object-hex-byte-case "secure"))
    (is (string= "0x71fbc97d2b878e33df7dfb4b690789c4b7fe4eef64dd650928aeba15553b3e94"
                 (fixture-object-field object-hex-byte-case "root")))
    (is (find-if (lambda (entry)
                   (string= "0xdeadbeef"
                            (fixture-object-field entry "value")))
                 (fixture-object-field object-hex-byte-case "entries")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field object-hex-byte-case "entries")))
    (is (string= "phase-a-secure-value-hex-byte-delete"
                 (fixture-object-field hex-byte-delete-case "name")))
    (is (fixture-object-field hex-byte-delete-case "secure"))
    (is (string= "array"
                 (fixture-object-field hex-byte-delete-case "inputForm")))
    (is (string= "0x51601f67f06338ad14e87799781d9eb786daf72d238e3122434a6d7b71900c7f"
                 (fixture-object-field hex-byte-delete-case "root")))
    (is (find-if (lambda (entry)
                   (string= "0xdeadbeef"
                            (fixture-object-field entry "value")))
                 (fixture-object-field hex-byte-delete-case "entries")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field hex-byte-delete-case "entries")))
    (is (string= "phase-a-secure-zgeth-account-step-1"
                 (fixture-object-field geth-secure-account-step-1-case "name")))
    (is (fixture-object-field geth-secure-account-step-1-case "secure"))
    (is (string= "0xc8c796b39027107040d7bae53042070762d888d7ec5e8fa875c95bde2ab3e8a5"
                 (fixture-object-field geth-secure-account-step-1-case "root")))
    (is (string= "phase-a-secure-zgeth-account-step-2"
                 (fixture-object-field geth-secure-account-step-2-case "name")))
    (is (fixture-object-field geth-secure-account-step-2-case "secure"))
    (is (string= "0x95e5d195992feeb1c07e0725456fde075005f3fe3ae2270b0b956004049de80f"
                 (fixture-object-field geth-secure-account-step-2-case "root")))
    (is (string= "phase-a-secure-zgeth-account-step-3"
                 (fixture-object-field geth-secure-account-step-3-case "name")))
    (is (fixture-object-field geth-secure-account-step-3-case "secure"))
    (is (string= "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                 (fixture-object-field geth-secure-account-step-3-case "root")))
    (is (string= "phase-a-secure-zgeth-delete-sequence"
                 (fixture-object-field geth-secure-delete-case "name")))
    (is (fixture-object-field geth-secure-delete-case "secure"))
    (is (string= "0x29b235a58c3c25ab83010c327d5932bcf05324b7d6b1185e650798034783ca9d"
                 (fixture-object-field geth-secure-delete-case "root"))))
  (let* ((case (normalize-eest-trie-test-case
                "empty-value-delete"
                (list (cons "in" (list (list "dog" "")))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (entry (first (fixture-required-field case "entries"))))
    (is (string= "array"
                 (fixture-object-field case "inputForm")))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (fixture-object-field entry "delete"))
    (is (string= ""
                 (fixture-object-field entry "deleteSourceValue"))))
  (let* ((case (normalize-eest-trie-test-case
                "object-form-entry"
                (list (cons "in" (list (cons "dog" "puppy")))
                      (cons "root"
                            "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
         (entry (first (fixture-required-field case "entries")))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "object"
                 (fixture-object-field case "inputForm")))
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
    (is (string= "object"
                 (fixture-object-field case "inputForm")))
    (is (string= "cat"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= "dog"
                 (fixture-object-field put-entry "key")))
    (is (string= "puppy"
                 (fixture-object-field put-entry "value")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (is (handler-case
          (progn
            (assert-eest-trie-test-case-root
             (normalize-eest-trie-test-case
              "out-missing-final-key"
              (list (cons "in" (list (list "dog" "puppy")))
                    (cons "out" (list (cons "cat" nil)))
                    (cons "root"
                          "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
            nil)
        (error (condition)
          (not (null
                (search "out missing final key"
                        (princ-to-string condition)))))))
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
     42
     (list (cons "in" nil)
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
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
     (list "not-a-json-object-field")
     "inline-entry-shape"))
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
    (is (= 64 (length cases)))
    (is (= 63 (length selected-cases)))
    (validate-trie-reference-case-requirements
     selected-cases
     +phase-a-eest-trie-reference-case-requirements+
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-case-requirements
       selected-cases
       '(("phase-a-trie-multi.json/missing-geth-case" . :plain))
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-case-requirements
       selected-cases
       '(("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3" . :plain))
       "Phase A EEST trie subset"))
    (validate-trie-reference-explicit-output-requirements
     selected-cases
     +phase-a-eest-trie-explicit-output-reference-case-names+
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-explicit-output-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-explicit-output-requirements
       selected-cases
       '("phase-a-trie-multi.json/geth-tiny-account-step-2")
       "Phase A EEST trie subset"))
    (let ((case-names
            (mapcar (lambda (case)
                      (fixture-object-field case "name"))
                    cases))
          (selected-names (fixture-object-field summary "names"))
          (roots (fixture-object-field summary "roots")))
      (is (member "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
                  case-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
                  case-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
                  selected-names
                  :test #'string=))
      (is (member "0xf853f5608648461d01d9b7df43a7723db3a35d69c80efb1482f9d5a093038f2d"
                  roots
                  :test #'string=))
      (is (member "0xa2e17a0ab859cc7b48061c3cc6617389e39a5a12791460d6c14047a0d4b89f69"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-insert-shared-prefix"
                  selected-names
                  :test #'string=))
      (is (member "0x8aad789dff2f538bca5d8ea56e8abe10f4c7ba3a5dea95fea4cd6e7c3a1168d3"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-long-leaf-value"
                  selected-names
                  :test #'string=))
      (is (member "0xd23786fb4a010da3ce639d66d5e904a11dbc02746d1ce25029e53290cabf28ab"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-large-value-branch"
                  selected-names
                  :test #'string=))
      (is (member "0xafebee6cfce72f9d2a7a4f5926ac11f2a79bd75f3a9ae6358a08252ba5dce3be"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-tiny-account-step-3"
                  selected-names
                  :test #'string=))
      (is (member "0x0608c1d1dc3905fa22204c7a0e43644831c3b6d3def0f274be623a948197e64a"
                  roots
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
                  selected-names
                  :test #'string=))
      (is (member "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                  roots
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence"
                  selected-names
                  :test #'string=))
      (is (member "0x29b235a58c3c25ab83010c327d5932bcf05324b7d6b1185e650798034783ca9d"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-delete-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-empty-value-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-replication-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-random-cases-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary"
                  selected-names
                  :test #'string=))
      (is (member "0x5991bb8c6514148a29db676a14ac506cd2cd5775ace63c30a4fe457715e9ac84"
                  roots
                  :test #'string=))
      (is (member "0x09c889feaafd53779755259beaa0ff41c32512c8cac45152af46fae7ebdef210"
                  roots
                  :test #'string=))
      (is (member "0x380d56237a963e2c17a7c282142dc0b85d3236cd515d4f0348c787e70a68d24c"
                  roots
                  :test #'string=))
      (is (member "0x962c0fffdeef7612a4f7bff1950d67e3e81c878e48b9ae45b3b374253b050bd8"
                  roots
                  :test #'string=)))
    (is (fixture-object-field (first cases) "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field (first cases) "root")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 63 cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-branch"
                 (fixture-object-field (first selected-cases) "name")))
    (is (fixture-object-field (first selected-cases) "secure"))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-object-form-value-hex-bytes"
                 (fixture-object-field (nth 18 selected-cases) "name")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 62 selected-cases) "name")))
    (is (= 63 (fixture-object-field summary "count")))
    (is (= 8 (fixture-object-field summary "objectFormCaseCount")))
    (is (= 5 (fixture-object-field summary "objectFormDeleteEntryCount")))
    (is (= 2 (fixture-object-field summary "objectFormEmptyValueDeleteEntryCount")))
    (is (= 3 (fixture-object-field summary "objectFormWriteOnlyCaseCount")))
    (is (= 4 (fixture-object-field summary "secureObjectFormCaseCount")))
    (is (= 23 (fixture-object-field summary "objectFormPermutationReplayCount")))
    (is (= 12 (fixture-object-field
               summary
               "secureObjectFormPermutationReplayCount")))
    (is (= 11 (fixture-object-field
               summary
               "plainObjectFormPermutationReplayCount")))
    (is (= 3 (fixture-object-field summary "secureObjectFormDeleteEntryCount")))
    (is (= 1 (fixture-object-field
              summary
              "secureObjectFormEmptyValueDeleteEntryCount")))
    (is (= 1 (fixture-object-field
              summary
              "plainObjectFormEmptyValueDeleteEntryCount")))
    (is (= 24 (fixture-object-field summary "secureCaseCount")))
    (is (= 39 (fixture-object-field summary "plainCaseCount")))
    (is (= 23 (fixture-object-field summary "secureNonEmptyRootCount")))
    (is (= 11 (fixture-object-field summary "secureBranchRootCount")))
    (is (= 4 (fixture-object-field summary "secureExtensionRootCount")))
    (is (= 38 (fixture-object-field summary "plainNonEmptyRootCount")))
    (is (= 23 (fixture-object-field summary "branchRootCount")))
    (is (= 3 (fixture-object-field summary "branchChildBranchCount")))
    (is (= 3 (fixture-object-field summary "branchChildExtensionCount")))
    (is (= 1 (fixture-object-field summary "secureBranchChildBranchCount")))
    (is (= 1 (fixture-object-field summary "secureBranchChildExtensionCount")))
    (is (= 15 (fixture-object-field summary "embeddedBranchChildReferenceCount")))
    (is (= 32 (fixture-object-field summary "hashedBranchChildReferenceCount")))
    (is (= 25 (fixture-object-field summary "secureHashedBranchChildReferenceCount")))
    (is (= 2 (fixture-object-field summary "branchValueRootCount")))
    (is (= 1 (fixture-object-field summary "branchValueZeroChildRootCount")))
    (is (= 1 (fixture-object-field summary "emptyKeyDeleteNonEmptyRootCount")))
    (is (= 10 (fixture-object-field summary "branchChildDeleteValueLeafCount")))
    (is (= 1 (fixture-object-field summary "branchChildDeletePlainLeafCount")))
    (is (= 4 (fixture-object-field summary "branchChildDeletePlainBranchCount")))
    (is (= 2 (fixture-object-field summary "branchChildDeleteSecureBranchCount")))
    (is (= 1 (fixture-object-field summary "extensionDeletePlainLeafCount")))
    (is (= 2 (fixture-object-field summary "extensionDeleteSecureLeafCount")))
    (is (= 6 (fixture-object-field summary "extensionDeletePlainExtensionCount")))
    (is (= 1 (fixture-object-field summary "extensionDeleteSecureExtensionCount")))
    (is (= 8 (fixture-object-field summary "branchDeleteRootCount")))
    (is (= 5 (fixture-object-field summary "overwrittenKeyCaseCount")))
    (is (= 3 (fixture-object-field summary "secureOverwrittenKeyCaseCount")))
    (is (= 1 (fixture-object-field summary "secureBranchOverwriteRootCount")))
    (is (= 1 (fixture-object-field summary "secureExtensionOverwriteRootCount")))
    (is (= 4 (fixture-object-field summary "leafMissingDeleteRootCount")))
    (is (= 2 (fixture-object-field summary "secureBranchMissingDeleteRootCount")))
    (is (= 1 (fixture-object-field summary "secureExtensionMissingDeleteRootCount")))
    (is (= 73 (fixture-object-field summary "hexByteStringEntryCount")))
    (is (= 29 (fixture-object-field summary "hexValueEntryCount")))
    (is (= 10 (fixture-object-field summary "secureHexValueEntryCount")))
    (is (= 19 (fixture-object-field summary "plainHexValueEntryCount")))
    (is (= 2 (fixture-object-field summary "secureObjectFormHexValueEntryCount")))
    (is (= 1 (fixture-object-field summary "plainObjectFormHexValueEntryCount")))
    (is (= 5 (fixture-object-field summary "emptyValueDeleteEntryCount")))
    (is (= 1 (fixture-object-field summary "hexEmptyValueDeleteEntryCount")))
    (is (= 4 (fixture-object-field summary "stringEmptyValueDeleteEntryCount")))
    (is (= 2 (fixture-object-field
              summary
              "objectFormStringEmptyValueDeleteEntryCount")))
    (is (= 18 (fixture-object-field summary "extensionRootCount")))
    (is (= 4 (fixture-object-field summary "embeddedExtensionChildReferenceCount")))
    (is (= 14 (fixture-object-field summary "hashedExtensionChildReferenceCount")))
    (is (= 4 (fixture-object-field summary "secureHashedExtensionChildReferenceCount")))
    (is (= 28 (fixture-object-field summary "nonEmptyDeleteRootCount")))
    (is (= 11 (fixture-object-field summary "secureNonEmptyDeleteRootCount")))
    (is (= 194 (fixture-object-field summary "totalEntryCount")))
    (is (= 125 (fixture-object-field summary "finalEntryPairCount")))
    (is (= 61 (fixture-object-field summary "finalEntryPairReplayCaseCount")))
    (is (= 43 (fixture-object-field summary "secureFinalEntryPairCount")))
    (is (= 82 (fixture-object-field summary "plainFinalEntryPairCount")))
    (is (= 23 (fixture-object-field
                summary
                "secureFinalEntryPairReplayCaseCount")))
    (is (= 38 (fixture-object-field
                summary
                "plainFinalEntryPairReplayCaseCount")))
    (is (= 63 (fixture-object-field summary "entryRangeReplayCaseCount")))
    (is (= 61 (fixture-object-field
               summary
               "nonEmptyEntryRangeReplayCaseCount")))
    (is (= 15 (fixture-object-field
               summary
               "boundedEntryRangeReplayCaseCount")))
    (is (= 23 (fixture-object-field
               summary
               "secureEntryRangeReplayCaseCount")))
    (is (= 38 (fixture-object-field
               summary
               "plainEntryRangeReplayCaseCount")))
    (is (= 158 (fixture-object-field summary "totalWriteEntryCount")))
    (is (= 125 (fixture-object-field summary "proofPresentKeyCount")))
    (is (= 43 (fixture-object-field summary "secureProofPresentKeyCount")))
    (is (= 82 (fixture-object-field summary "plainProofPresentKeyCount")))
    (is (= 34 (fixture-object-field summary "proofMissingKeyCount")))
    (is (= 13 (fixture-object-field summary "secureProofMissingKeyCount")))
    (is (= 21 (fixture-object-field summary "plainProofMissingKeyCount")))
    (is (= 7 (fixture-object-field summary "explicitOutputCaseCount")))
    (is (= 3 (fixture-object-field summary "secureExplicitOutputCaseCount")))
    (is (= 4 (fixture-object-field summary "plainExplicitOutputCaseCount")))
    (is (= 23 (fixture-object-field summary "explicitOutputEntryCount")))
    (is (= 16 (fixture-object-field summary "explicitOutputPresentKeyCount")))
    (is (= 7 (fixture-object-field summary "secureExplicitOutputPresentKeyCount")))
    (is (= 9 (fixture-object-field summary "plainExplicitOutputPresentKeyCount")))
    (is (= 7 (fixture-object-field summary "explicitOutputMissingKeyCount")))
    (is (= 3 (fixture-object-field summary "secureExplicitOutputMissingKeyCount")))
    (is (= 4 (fixture-object-field summary "plainExplicitOutputMissingKeyCount")))
    (is (= 2 (fixture-object-field summary "objectFormExplicitOutputCaseCount")))
    (is (= 1 (fixture-object-field summary "secureObjectFormExplicitOutputCaseCount")))
    (is (= 1 (fixture-object-field summary "plainObjectFormExplicitOutputCaseCount")))
    (is (= 4 (fixture-object-field summary "objectFormExplicitOutputPresentKeyCount")))
    (is (= 2 (fixture-object-field summary "objectFormExplicitOutputMissingKeyCount")))
    (is (= 54 (fixture-object-field summary "secureWriteEntryCount")))
    (is (= 104 (fixture-object-field summary "plainWriteEntryCount")))
    (is (= 36 (fixture-object-field summary "totalDeleteEntryCount")))
    (is (= 13 (fixture-object-field summary "secureDeleteEntryCount")))
    (is (= 23 (fixture-object-field summary "plainDeleteEntryCount")))
    (flet ((remove-selected-name (name)
             (remove-if
              (lambda (case)
                (string= name (fixture-object-field case "name")))
              selected-cases)))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove-selected-name
          "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch")))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove-selected-name
          "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension")))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove (second selected-cases) selected-cases)))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove (third selected-cases) selected-cases))))
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
      (multiple-value-bind (trie roots)
          (run-trie-fixture-case-with-root-history case)
        (assert-trie-fixture-intermediate-roots roots case)
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
        (let ((child-shapes
                (fixture-object-field case "expectedRootChildShapes")))
          (when child-shapes
            (dolist (expected child-shapes)
              (is (string=
                   (cdr expected)
                   (trie-fixture-root-child-shape
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
        (let ((branch-value
                (fixture-object-field case "expectedRootValueHex")))
          (when branch-value
            (is (string= branch-value
                         (bytes-to-hex
                          (trie-fixture-root-value-bytes trie))))))
        (assert-trie-fixture-final-operation-lookups trie case)
        (assert-trie-fixture-entry-pair-replay trie case)
        (assert-trie-fixture-entry-ranges trie case)
        (assert-trie-fixture-proof-prefixes trie case)
        (assert-trie-fixture-lookups trie case)))))
