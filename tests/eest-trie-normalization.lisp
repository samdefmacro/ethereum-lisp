(in-package #:ethereum-lisp.test)

(defun eest-trie-test-json-paths (root)
  (execution-spec-tests-json-paths root))

(defun eest-trie-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST trie test"))

(defun eest-trie-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST trie test"))

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

(defun eest-trie-test-normalize-optional-byte-string
    (case-name object field index)
  (when (fixture-field-present-p object field)
    (let ((value (fixture-object-field object field)))
      (unless (or (null value) (stringp value))
        (error "EEST trie test case ~A ranges entry ~D ~A must be a string or null"
               case-name
               index
               field))
      (when value
        (cons field
              (eest-trie-test-normalized-byte-string
               value
               (format nil "EEST trie test case ~A ranges entry ~D ~A"
                       case-name
                       index
                       field)))))))

(defun normalize-eest-trie-test-range (case-name range index)
  (validate-trie-fixture-object-fields
   range
   +eest-trie-test-range-fields+
   (format nil "EEST trie test case ~A ranges entry ~D"
           case-name
           index))
  (let ((keys (fixture-required-field range "keys")))
    (unless (listp keys)
      (error "EEST trie test case ~A ranges entry ~D keys must be a JSON array"
             case-name
             index))
    (append
     (remove nil
             (list
              (eest-trie-test-normalize-optional-byte-string
               case-name range "start" index)
              (eest-trie-test-normalize-optional-byte-string
               case-name range "end" index)))
     (list
      (cons "keys"
            (loop for key in keys
                  for key-index from 0
                  collect
                  (progn
                    (unless (stringp key)
                      (error "EEST trie test case ~A ranges entry ~D key ~D must be a string"
                             case-name
                             index
                             key-index))
                    (eest-trie-test-normalized-byte-string
                     key
                     (format nil "EEST trie test case ~A ranges entry ~D key ~D"
                             case-name
                             index
                             key-index)))))))))

(defun normalize-eest-trie-test-ranges (case-name ranges)
  (unless (listp ranges)
    (error "EEST trie test case ~A ranges must be a JSON array"
           case-name))
  (loop for range in ranges
        for index from 0
        collect (normalize-eest-trie-test-range case-name range index)))

(defun normalize-eest-trie-test-intermediate-roots
    (case-name roots entry-count)
  (unless (listp roots)
    (error "EEST trie test case ~A intermediateRoots must be a JSON array"
           case-name))
  (unless (= (length roots) entry-count)
    (error "EEST trie test case ~A intermediateRoots must match in entry count"
           case-name))
  (loop for root in roots
        for index from 0
        collect
        (eest-trie-test-normalized-root
         root
         (format nil "~A intermediateRoots ~D" case-name index))))

(defun normalize-eest-trie-test-entry-pair (case-name pair index)
  (validate-trie-fixture-object-fields
   pair
   +eest-trie-test-entry-pair-fields+
   (format nil "EEST trie test case ~A entryPairs entry ~D"
           case-name
           index))
  (let ((key (fixture-required-field pair "key"))
        (value (fixture-required-field pair "value")))
    (unless (stringp key)
      (error "EEST trie test case ~A entryPairs entry ~D key must be a string"
             case-name
             index))
    (unless (stringp value)
      (error "EEST trie test case ~A entryPairs entry ~D value must be a string"
             case-name
             index))
    (list
     (cons "key"
           (eest-trie-test-normalized-byte-string
            key
            (format nil "EEST trie test case ~A entryPairs entry ~D key"
                    case-name
                    index)))
     (cons "value"
           (eest-trie-test-normalized-byte-string
            value
            (format nil "EEST trie test case ~A entryPairs entry ~D value"
                    case-name
                    index))))))

(defun normalize-eest-trie-test-entry-pairs (case-name entry-pairs)
  (unless (and (listp entry-pairs) entry-pairs)
    (error "EEST trie test case ~A entryPairs must be a non-empty JSON array"
           case-name))
  (loop for pair in entry-pairs
        for index from 0
        collect (normalize-eest-trie-test-entry-pair case-name pair index)))

(defun normalize-eest-trie-test-proof-node-rlp (case-name value index node-index)
  (validate-trie-fixture-byte-field
   value
   (format nil "EEST trie test case ~A proofs entry ~D nodeRlp ~D"
           case-name
           index
           node-index))
  (let ((bytes (hex-to-bytes value)))
    (when (zerop (length bytes))
      (error "EEST trie test case ~A proofs entry ~D nodeRlp ~D must not be empty"
             case-name
             index
             node-index))
    (bytes-to-hex bytes)))

(defun normalize-eest-trie-test-proof (case-name proof index)
  (validate-trie-fixture-object-fields
   proof
   +eest-trie-test-proof-fields+
   (format nil "EEST trie test case ~A proofs entry ~D"
           case-name
           index))
  (let ((key (fixture-required-field proof "key"))
        (node-rlps (fixture-required-field proof "nodeRlps")))
    (unless (stringp key)
      (error "EEST trie test case ~A proofs entry ~D key must be a string"
             case-name
             index))
    (unless (and (listp node-rlps) node-rlps)
      (error "EEST trie test case ~A proofs entry ~D nodeRlps must be a non-empty JSON array"
             case-name
             index))
    (when (fixture-field-present-p proof "exactLength")
      (let ((exact-length (fixture-object-field proof "exactLength")))
        (unless (or (eq exact-length t) (null exact-length))
          (error "EEST trie test case ~A proofs entry ~D exactLength must be a boolean"
                 case-name
                 index))))
    (append
     (list
      (cons "key"
            (eest-trie-test-normalized-byte-string
             key
             (format nil "EEST trie test case ~A proofs entry ~D key"
                     case-name
                     index)))
      (cons "nodeRlps"
            (loop for node-rlp in node-rlps
                  for node-index from 0
                  collect
                  (normalize-eest-trie-test-proof-node-rlp
                   case-name
                   node-rlp
                   index
                   node-index))))
     (when (fixture-field-present-p proof "exactLength")
       (list (cons "exactLength"
                   (fixture-object-field proof "exactLength")))))))

(defun normalize-eest-trie-test-proofs (case-name proofs)
  (unless (listp proofs)
    (error "EEST trie test case ~A proofs must be a JSON array"
           case-name))
  (loop for proof in proofs
        for index from 0
        collect (normalize-eest-trie-test-proof case-name proof index)))

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
                             (eest-trie-test-object-entries-p input)))
         (entries (normalize-eest-trie-test-entries name input)))
    (append
     (list
      (cons "name" name)
      (cons "entries" entries)
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
     (when (fixture-field-present-p case "intermediateRoots")
       (list
        (cons "expectedIntermediateRoots"
              (normalize-eest-trie-test-intermediate-roots
               name
               (fixture-object-field case "intermediateRoots")
               (length entries)))))
     (when (fixture-field-present-p case "out")
       (list
        (cons "expectedOut"
              (normalize-eest-trie-test-output-entries
               name
               (fixture-object-field case "out")))))
     (when (fixture-field-present-p case "entryPairs")
       (list
        (cons "expectedEntryPairs"
              (normalize-eest-trie-test-entry-pairs
               name
               (fixture-object-field case "entryPairs")))))
     (when (fixture-field-present-p case "proofs")
       (list
        (cons "expectedProofs"
              (normalize-eest-trie-test-proofs
               name
               (fixture-object-field case "proofs")))))
     (when (fixture-field-present-p case "ranges")
       (list
        (cons "expectedRanges"
              (normalize-eest-trie-test-ranges
               name
               (fixture-object-field case "ranges"))))))))

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

