(in-package #:ethereum-lisp.test)

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
         (explicit-range-flags
           (mapcar (lambda (case)
                     (fixture-field-present-p case "expectedRanges"))
                   cases))
         (explicit-range-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedRanges")
                         (length (fixture-object-field case "expectedRanges"))
                         0))
                   cases))
         (secure-explicit-range-case-count
           (loop for secure-p in secure-flags
                 for range-p in explicit-range-flags
                 count (and secure-p range-p)))
         (plain-explicit-range-case-count
           (loop for secure-p in secure-flags
                 for range-p in explicit-range-flags
                 count (and (not secure-p) range-p)))
         (intermediate-root-flags
           (mapcar (lambda (case)
                     (fixture-field-present-p case "expectedIntermediateRoots"))
                   cases))
         (intermediate-root-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedIntermediateRoots")
                         (length (fixture-object-field
                                  case
                                  "expectedIntermediateRoots"))
                         0))
                   cases))
         (plain-intermediate-root-case-count
           (loop for secure-p in secure-flags
                 for intermediate-p in intermediate-root-flags
                 count (and (not secure-p) intermediate-p)))
         (proof-node-flags
           (mapcar (lambda (case)
                     (fixture-field-present-p case "expectedProofs"))
                   cases))
         (proof-node-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedProofs")
                         (length (fixture-object-field case "expectedProofs"))
                         0))
                   cases))
         (exact-proof-node-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedProofs")
                         (count-if
                          (lambda (expected)
                            (fixture-object-field expected "exactLength"))
                          (fixture-object-field case "expectedProofs"))
                         0))
                   cases))
         (secure-proof-node-case-count
           (loop for secure-p in secure-flags
                 for proof-p in proof-node-flags
                 count (and secure-p proof-p)))
         (plain-proof-node-case-count
           (loop for secure-p in secure-flags
                 for proof-p in proof-node-flags
                 count (and (not secure-p) proof-p)))
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
         (explicit-entry-pair-flags
           (mapcar (lambda (case)
                     (fixture-field-present-p case "expectedEntryPairs"))
                   cases))
         (explicit-entry-pair-counts
           (mapcar (lambda (case)
                     (if (fixture-field-present-p case "expectedEntryPairs")
                         (length (fixture-object-field case "expectedEntryPairs"))
                         0))
                   cases))
         (secure-explicit-entry-pair-counts
           (loop for secure-p in secure-flags
                 for count in explicit-entry-pair-counts
                 when secure-p
                   collect count))
         (plain-explicit-entry-pair-counts
           (loop for secure-p in secure-flags
                 for count in explicit-entry-pair-counts
                 unless secure-p
                   collect count))
         (secure-explicit-entry-pair-case-count
           (loop for secure-p in secure-flags
                 for explicit-p in explicit-entry-pair-flags
                 count (and secure-p explicit-p)))
         (plain-explicit-entry-pair-case-count
           (loop for secure-p in secure-flags
                 for explicit-p in explicit-entry-pair-flags
                 count (and (not secure-p) explicit-p)))
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
     (cons "explicitEntryPairCaseCount"
           (count t explicit-entry-pair-flags))
     (cons "secureExplicitEntryPairCaseCount"
           secure-explicit-entry-pair-case-count)
     (cons "plainExplicitEntryPairCaseCount"
           plain-explicit-entry-pair-case-count)
     (cons "explicitEntryPairCount"
           (reduce #'+ explicit-entry-pair-counts :initial-value 0))
     (cons "secureExplicitEntryPairCount"
           (reduce #'+ secure-explicit-entry-pair-counts :initial-value 0))
     (cons "plainExplicitEntryPairCount"
           (reduce #'+ plain-explicit-entry-pair-counts :initial-value 0))
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
     (cons "explicitEntryRangeCaseCount"
           (count t explicit-range-flags))
     (cons "secureExplicitEntryRangeCaseCount"
           secure-explicit-range-case-count)
     (cons "plainExplicitEntryRangeCaseCount"
           plain-explicit-range-case-count)
     (cons "explicitEntryRangeCount"
           (reduce #'+ explicit-range-counts :initial-value 0))
     (cons "intermediateRootCaseCount"
           (count t intermediate-root-flags))
     (cons "plainIntermediateRootCaseCount"
           plain-intermediate-root-case-count)
     (cons "intermediateRootCount"
           (reduce #'+ intermediate-root-counts :initial-value 0))
     (cons "proofNodeCaseCount"
           (count t proof-node-flags))
     (cons "secureProofNodeCaseCount"
           secure-proof-node-case-count)
     (cons "plainProofNodeCaseCount"
           plain-proof-node-case-count)
     (cons "proofNodeAssertionCount"
           (reduce #'+ proof-node-counts :initial-value 0))
     (cons "exactProofNodeAssertionCount"
           (reduce #'+ exact-proof-node-counts :initial-value 0))
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
  (validate-trie-reference-gates
   cases
   +phase-a-eest-trie-reference-gates+
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
    (when (zerop (fixture-object-field summary "explicitEntryRangeCaseCount"))
      (error "Phase A EEST trie subset must include explicit entry range assertions"))
    (when (zerop (fixture-object-field summary "secureExplicitEntryRangeCaseCount"))
      (error "Phase A EEST trie subset must include secure explicit entry range assertions"))
    (when (zerop (fixture-object-field summary "plainExplicitEntryRangeCaseCount"))
      (error "Phase A EEST trie subset must include plain explicit entry range assertions"))
    (when (zerop (fixture-object-field summary "intermediateRootCaseCount"))
      (error "Phase A EEST trie subset must include intermediate root assertions"))
    (when (zerop (fixture-object-field summary "plainIntermediateRootCaseCount"))
      (error "Phase A EEST trie subset must include plain intermediate root assertions"))
    (when (zerop (fixture-object-field summary "explicitEntryPairCaseCount"))
      (error "Phase A EEST trie subset must include explicit entry-pair assertions"))
    (when (zerop (fixture-object-field summary "secureExplicitEntryPairCaseCount"))
      (error "Phase A EEST trie subset must include secure explicit entry-pair assertions"))
    (when (zerop (fixture-object-field summary "plainExplicitEntryPairCaseCount"))
      (error "Phase A EEST trie subset must include plain explicit entry-pair assertions"))
    (when (zerop (fixture-object-field summary "proofNodeCaseCount"))
      (error "Phase A EEST trie subset must include proof-node assertions"))
    (when (zerop (fixture-object-field summary "secureProofNodeCaseCount"))
      (error "Phase A EEST trie subset must include secure proof-node assertions"))
    (when (zerop (fixture-object-field summary "plainProofNodeCaseCount"))
      (error "Phase A EEST trie subset must include plain proof-node assertions"))
    (when (zerop (fixture-object-field summary "exactProofNodeAssertionCount"))
      (error "Phase A EEST trie subset must include exact-length proof-node assertions"))
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

