(in-package #:ethereum-lisp.test)

(defparameter +trie-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/trie-vectors.json")

(defun trie-fixture-object-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun trie-fixture-file-string (path)
  (with-open-file (stream path :direction :input)
    (with-output-to-string (out)
      (loop for line = (read-line stream nil nil)
            while line
            do (progn
                 (write-string line out)
                 (terpri out))))))

(defun trie-fixture-root-shape (trie)
  (let ((root (mpt-root-node trie)))
    (cond
      ((null root) "empty")
      ((typep root 'ethereum-lisp.trie::leaf-node) "leaf")
      ((typep root 'ethereum-lisp.trie::extension-node) "extension")
      ((typep root 'ethereum-lisp.trie::branch-node) "branch")
      (t "unknown"))))

(defun apply-trie-fixture-operation (trie operation)
  (let ((op (trie-fixture-object-field operation "op"))
        (key (ascii-to-bytes (trie-fixture-object-field operation "keyAscii"))))
    (cond
      ((string= op "put")
       (mpt-put trie key
                (ascii-to-bytes
                 (trie-fixture-object-field operation "valueAscii"))))
      ((string= op "delete")
       (mpt-delete trie key))
      (t (error "Unknown trie fixture operation: ~A" op)))))

(defun run-trie-fixture-case (case)
  (let ((trie (make-mpt)))
    (dolist (operation (trie-fixture-object-field case "operations"))
      (apply-trie-fixture-operation trie operation))
    trie))

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

(deftest trie-fixture-vectors
  (let* ((fixture (parse-json
                   (trie-fixture-file-string +trie-vector-fixture-path+)))
         (cases (trie-fixture-object-field fixture "cases")))
    (dolist (case cases)
      (let ((trie (run-trie-fixture-case case)))
        (is (string= (trie-fixture-object-field case "expectedRoot")
                     (mpt-root-hex trie)))
        (is (string= (trie-fixture-object-field case "expectedShape")
                     (trie-fixture-root-shape trie)))))))
