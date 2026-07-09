(in-package #:ethereum-lisp.test)

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
  (execution-spec-tests-root-case-name root path key singleton-p))

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
  (filter-execution-spec-tests-root-cases
   cases
   names
   "EEST trie test"
   :selector-order-p nil))

(defun validate-eest-trie-selector-list (names)
  (validate-execution-spec-tests-selector-list names "EEST trie"))

(defun eest-trie-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p name))

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

