(in-package #:ethereum-lisp.test)

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

