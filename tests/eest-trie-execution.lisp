(in-package #:ethereum-lisp.test)

(defun eest-trie-test-key-trie-key (case key label)
  (let ((key (eest-trie-test-byte-string key label)))
    (if (fixture-object-field case "secure")
        (keccak-256 key)
        key)))

(defun eest-trie-test-entry-trie-key (case entry)
  (eest-trie-test-key-trie-key
   case
   (fixture-required-field entry "key")
   (format nil "EEST trie test case ~A in entry key"
           (fixture-required-field case "name"))))

(defun apply-eest-trie-test-entry (case trie entry)
  (let ((trie-key (eest-trie-test-entry-trie-key case entry)))
    (if (fixture-field-present-p entry "delete")
        (mpt-delete trie trie-key)
        (mpt-put trie
                 trie-key
                 (eest-trie-test-byte-string
                  (fixture-required-field entry "value")
                  (format nil "EEST trie test case ~A in entry value"
                          (fixture-required-field case "name")))))))

(defun run-eest-trie-test-entries (case entries)
  (let ((trie (make-mpt)))
    (dolist (entry entries)
      (apply-eest-trie-test-entry case trie entry))
    trie))

(defun run-eest-trie-test-case (case)
  (run-eest-trie-test-entries
   case
   (fixture-required-field case "entries")))

(defun run-eest-trie-test-entries-with-root-history (case entries)
  (let ((trie (make-mpt))
        (roots nil))
    (dolist (entry entries)
      (apply-eest-trie-test-entry case trie entry)
      (push (mpt-root-hex trie) roots))
    (values trie (nreverse roots))))

(defun run-eest-trie-test-case-with-root-history (case)
  (run-eest-trie-test-entries-with-root-history
   case
   (fixture-required-field case "entries")))

(defun eest-trie-test-range-bound (case range field)
  (when (fixture-field-present-p range field)
    (eest-trie-test-key-trie-key
     case
     (fixture-object-field range field)
     (format nil "EEST trie test case ~A range ~A"
             (fixture-required-field case "name")
             field))))

(defun eest-trie-test-range-expected-keys (case range)
  (mapcar (lambda (key)
            (eest-trie-test-key-trie-key
             case
             key
             (format nil "EEST trie test case ~A range expected key"
                     (fixture-required-field case "name"))))
          (fixture-required-field range "keys")))

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

(defun assert-eest-trie-test-explicit-entry-pairs (case trie)
  (when (fixture-field-present-p case "expectedEntryPairs")
    (let ((actual (mpt-entry-pairs trie))
          (expected (fixture-required-field case "expectedEntryPairs"))
          (name (fixture-required-field case "name")))
      (unless (= (length expected) (length actual))
        (error "EEST trie test case ~A entryPairs length mismatch: expected ~A, got ~A"
               name
               (length expected)
               (length actual)))
      (loop for expected-entry in expected
            for actual-entry in actual
            for index from 0
            for expected-key =
              (eest-trie-test-key-trie-key
               case
               (fixture-required-field expected-entry "key")
               (format nil "EEST trie test case ~A entryPairs ~D key"
                       name
                       index))
            for expected-value =
              (eest-trie-test-byte-string
               (fixture-required-field expected-entry "value")
               (format nil "EEST trie test case ~A entryPairs ~D value"
                       name
                       index))
            unless (bytes= expected-key (car actual-entry))
              do (error "EEST trie test case ~A entryPairs key ~D mismatch: expected ~A, got ~A"
                        name
                        index
                        (bytes-to-hex expected-key)
                        (bytes-to-hex (car actual-entry)))
            unless (bytes= expected-value (cdr actual-entry))
              do (error "EEST trie test case ~A entryPairs value ~D mismatch for key ~A"
                        name
                        index
                        (bytes-to-hex expected-key))))))

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

(defun assert-eest-trie-test-explicit-entry-ranges (case trie)
  (loop for range in (fixture-object-field case "expectedRanges")
        for index from 0
        for start = (eest-trie-test-range-bound case range "start")
        for end = (eest-trie-test-range-bound case range "end")
        for actual-keys =
          (mapcar #'car (mpt-entry-range trie :start start :end end))
        for expected-keys = (eest-trie-test-range-expected-keys case range)
        do
           (unless (= (length expected-keys) (length actual-keys))
             (error "EEST trie test case ~A explicit range ~D mismatch: expected ~A keys, got ~A"
                    (fixture-required-field case "name")
                    index
                    (length expected-keys)
                    (length actual-keys)))
           (loop for expected-key in expected-keys
                 for actual-key in actual-keys
                 unless (bytes= expected-key actual-key)
                   do (error "EEST trie test case ~A explicit range ~D key mismatch: expected ~A, got ~A"
                             (fixture-required-field case "name")
                             index
                             (bytes-to-hex expected-key)
                             (bytes-to-hex actual-key)))))

(defun assert-eest-trie-test-intermediate-roots (case roots)
  (when (fixture-field-present-p case "expectedIntermediateRoots")
    (let ((name (fixture-required-field case "name"))
          (expected-roots (fixture-object-field case "expectedIntermediateRoots")))
      (unless (= (length expected-roots) (length roots))
        (error "EEST trie test case ~A intermediate root count mismatch: expected ~A, got ~A"
               name
               (length expected-roots)
               (length roots)))
      (loop for expected-root in expected-roots
            for actual-root in roots
            for index from 0
            unless (string= expected-root actual-root)
              do (error "EEST trie test case ~A intermediate root ~D mismatch: expected ~A, got ~A"
                        name
                        index
                        expected-root
                        actual-root)))))

(defun assert-eest-trie-test-case-root (case)
  (multiple-value-bind (trie roots)
      (run-eest-trie-test-case-with-root-history case)
    (let ((name (fixture-required-field case "name"))
          (expected-root (fixture-required-field case "root"))
          (actual-root (mpt-root-hex trie)))
      (unless (string= expected-root actual-root)
        (error "EEST trie test case ~A root mismatch: expected ~A, got ~A"
               name
               expected-root
               actual-root))
      (assert-eest-trie-test-intermediate-roots case roots)
      (assert-eest-trie-test-case-lookups case trie)
      (assert-eest-trie-test-case-explicit-output case trie)
      (assert-eest-trie-test-entry-pair-replay case trie)
      (assert-eest-trie-test-explicit-entry-pairs case trie)
      (assert-eest-trie-test-entry-ranges case trie)
      (assert-eest-trie-test-explicit-entry-ranges case trie)
      (assert-eest-trie-test-proof-nodes case trie)
      (assert-eest-trie-test-object-form-permutations case)
      trie)))

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

(defun assert-eest-trie-test-proof-nodes (case trie)
  (dolist (expected (fixture-object-field case "expectedProofs"))
    (let* ((name (fixture-required-field case "name"))
           (key (eest-trie-test-key-trie-key
                 case
                 (fixture-required-field expected "key")
                 (format nil "EEST trie test case ~A proof key" name)))
           (proof (mpt-get-proof trie key))
           (expected-node-rlps (fixture-required-field expected "nodeRlps")))
      (if (fixture-object-field expected "exactLength")
          (unless (= (length expected-node-rlps) (length proof))
            (error "EEST trie test case ~A proof for key ~A length mismatch: expected ~A, got ~A"
                   name
                   (bytes-to-hex key)
                   (length expected-node-rlps)
                   (length proof)))
          (unless (<= (length expected-node-rlps) (length proof))
            (error "EEST trie test case ~A proof for key ~A too short: expected prefix length ~A, got ~A"
                   name
                   (bytes-to-hex key)
                   (length expected-node-rlps)
                   (length proof))))
      (loop for expected-rlp in expected-node-rlps
            for actual-rlp in proof
            for index from 0
            unless (string= expected-rlp (bytes-to-hex actual-rlp))
              do (error "EEST trie test case ~A proof node ~D mismatch for key ~A: expected ~A, got ~A"
                        name
                        index
                        (bytes-to-hex key)
                        expected-rlp
                        (bytes-to-hex actual-rlp))))))

