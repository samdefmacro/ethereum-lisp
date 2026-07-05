(defpackage #:ethereum-lisp.test
  (:use #:cl #:ethereum-lisp)
  (:export
   #:deftest
   #:is
   #:signals
   #:run-all-tests
   #:+execution-spec-tests-fixture-root-env+
   #:*fixture-root-environment-reader*
   #:test-skipped
   #:test-skipped-reason
   #:skip-test
   #:execution-spec-tests-fixture-root
   #:execution-spec-tests-blockchain-test-root
   #:execution-spec-tests-transaction-test-root
   #:execution-spec-tests-state-test-root
   #:execution-spec-tests-trie-test-root
   #:execution-spec-tests-json-paths
   #:execution-spec-tests-root-json-paths
   #:execution-spec-tests-root-file-names
   #:execution-spec-tests-root-case-name
   #:execution-spec-tests-source-style-name-p
   #:validate-execution-spec-tests-selector-list
   #:filter-execution-spec-tests-root-cases
   #:with-execution-spec-tests-fixture-root
   #:with-execution-spec-tests-blockchain-test-root
   #:with-execution-spec-tests-transaction-test-root
   #:with-execution-spec-tests-state-test-root
   #:with-execution-spec-tests-trie-test-root
   #:repo-kzg-verifier-command))

(in-package #:ethereum-lisp.test)

(defvar *tests* '())

(defparameter *repository-root*
  (let ((source (or *load-truename* *compile-file-truename*)))
    (if source
        (uiop:ensure-directory-pathname
         (merge-pathnames
          #P"../"
          (uiop:pathname-directory-pathname source)))
        (uiop:ensure-directory-pathname (uiop:getcwd)))))

(defun repository-relative-pathname (relative)
  (merge-pathnames relative *repository-root*))

(defparameter *repo-kzg-verifier-command*
  (repository-relative-pathname #P"scripts/kzg-verifier.sh"))

(defun repo-kzg-verifier-command ()
  (or (probe-file *repo-kzg-verifier-command*)
      (error "Missing repo KZG verifier command at ~A"
             *repo-kzg-verifier-command*)))

(defconstant +execution-spec-tests-fixture-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defconstant +phase-a-eest-release+ "v5.4.0")
(defconstant +phase-a-eest-tag-target+ "88e9fb8")
(defconstant +phase-a-eest-archive+ "fixtures_stable.tar.gz")

(defparameter +phase-a-eest-source-fields+
  '("release" "tagTarget" "archive" "status"))

(defparameter +execution-spec-tests-transaction-test-subdirs+
  '("transaction_tests/"
    "fixtures/transaction_tests/"
    "spec-tests/fixtures/transaction_tests/"))

(defparameter +execution-spec-tests-state-test-subdirs+
  '("state_tests/"
    "fixtures/state_tests/"
    "spec-tests/fixtures/state_tests/"))

(defparameter +execution-spec-tests-trie-test-subdirs+
  '("trie_tests/"
    "fixtures/trie_tests/"
    "spec-tests/fixtures/trie_tests/"))

(defparameter +execution-spec-tests-blockchain-test-subdirs+
  '("blockchain_tests_engine/"
    "blockchain_tests/"
    "fixtures/blockchain_tests_engine/"
    "fixtures/blockchain_tests/"
    "spec-tests/fixtures/blockchain_tests_engine/"
    "spec-tests/fixtures/blockchain_tests/"))

(defun default-environment-reader (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defvar *fixture-root-environment-reader* #'default-environment-reader)

(define-condition test-skipped (condition)
  ((reason :initarg :reason :reader test-skipped-reason))
  (:report (lambda (condition stream)
             (format stream "~A" (test-skipped-reason condition)))))

(defun skip-test (reason)
  (signal 'test-skipped :reason reason))

(defun blank-string-p (value)
  (or (null value)
      (zerop (length value))
      (every (lambda (char)
               (find char '(#\Space #\Tab #\Newline #\Return)))
             value)))

(defun fixture-object-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun fixture-field-present-p (object name)
  (not (null (assoc name object :test #'string=))))

(defun fixture-required-field (object name)
  (unless (fixture-field-present-p object name)
    (error "Fixture is missing field ~A" name))
  (fixture-object-field object name))

(defun validate-fixture-object-fields (object allowed-fields label)
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

(defun fixture-file-string (path)
  (with-open-file (stream path :direction :input)
    (with-output-to-string (out)
      (loop for line = (read-line stream nil nil)
            while line
            do (progn
                 (write-string line out)
                 (terpri out))))))

(defun validate-fixture-format (fixture expected-format)
  (unless (string= expected-format
                   (validate-fixture-required-string-field
                    fixture "format" "Fixture"))
    (error "Fixture format must be ~A" expected-format)))

(defun validate-fixture-required-string-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A.~A must be a string" label field))
    value))

(defun validate-fixture-pinned-eest-source (fixture)
  (let ((source (fixture-required-field fixture "executionSpecTests")))
    (unless (listp source)
      (error "Fixture executionSpecTests must be a JSON object"))
    (validate-fixture-object-fields
     source
     +phase-a-eest-source-fields+
     "Fixture executionSpecTests")
    (unless (string= +phase-a-eest-release+
                     (validate-fixture-required-string-field
                      source "release" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.release must be ~A"
             +phase-a-eest-release+))
    (unless (string= +phase-a-eest-tag-target+
                     (validate-fixture-required-string-field
                      source "tagTarget" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.tagTarget must be ~A"
             +phase-a-eest-tag-target+))
    (unless (string= +phase-a-eest-archive+
                     (validate-fixture-required-string-field
                      source "archive" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.archive must be ~A"
             +phase-a-eest-archive+))
    (when (blank-string-p
           (validate-fixture-required-string-field
            source "status" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.status must be present"))))

(defun execution-spec-tests-fixture-root
    (&key (env-var +execution-spec-tests-fixture-root-env+))
  (let ((value (funcall *fixture-root-environment-reader* env-var)))
    (unless (or (null value) (stringp value))
      (error "Execution spec tests fixture root must be a string or nil"))
    (unless (blank-string-p value)
      (probe-file value))))

(defun execution-spec-tests-resolved-root (root)
  (if root
      (progn
        (unless (or (stringp root) (pathnamep root))
          (error "Execution spec tests fixture root must be a string, pathname, or nil"))
        (probe-file root))
      (execution-spec-tests-fixture-root)))

(defun execution-spec-tests-subdirectory (root subdir)
  (probe-file (merge-pathnames subdir (pathname root))))

(defun execution-spec-tests-subdirectory-json-p (root subdir)
  (let ((candidate (execution-spec-tests-subdirectory root subdir)))
    (and candidate
         (not (null (execution-spec-tests-json-paths candidate))))))

(defun execution-spec-tests-first-existing-subdirectory
    (root subdirs &key require-json-p)
  (when root
    (let ((first-existing nil))
      (dolist (subdir subdirs)
        (let ((candidate (execution-spec-tests-subdirectory root subdir)))
          (when candidate
            (unless first-existing
              (setf first-existing candidate))
            (when (or (not require-json-p)
                      (execution-spec-tests-subdirectory-json-p root subdir))
              (return-from execution-spec-tests-first-existing-subdirectory
                candidate)))))
      first-existing)))

(defun execution-spec-tests-json-paths (root)
  (let* ((root-path (pathname root))
         (pattern
           (make-pathname
            :directory (append (pathname-directory root-path)
                               (list :wild-inferiors))
            :name :wild
            :type "json"
            :defaults root-path)))
    (sort (directory pattern) #'string< :key #'namestring)))

(defun execution-spec-tests-root-json-paths (root label)
  (let ((paths (execution-spec-tests-json-paths root)))
    (unless paths
      (error "~A root ~A has no JSON files" label root))
    paths))

(defun execution-spec-tests-root-file-names (root label)
  (mapcar (lambda (path)
            (enough-namestring (truename path) (truename root)))
          (execution-spec-tests-root-json-paths root label)))

(defun execution-spec-tests-root-case-name (root path key singleton-p)
  (let ((relative (enough-namestring (truename path) (truename root))))
    (if singleton-p
        relative
        (format nil "~A/~A" relative key))))

(defun execution-spec-tests-source-style-name-p
    (name &key allow-nested-case-name)
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
                       (or allow-nested-case-name
                           (null (position #\/ name
                                           :start (1+ after-json))))))))))

(defun validate-execution-spec-tests-selector-list
    (names label &key allow-nested-case-name)
  (unless (listp names)
    (error "~A selector list must be a list" label))
  (unless names
    (error "~A selector list must not be empty" label))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (unless (stringp name)
        (error "~A selector name must be a string" label))
      (when (blank-string-p name)
        (error "~A selector name must be present" label))
      (unless (execution-spec-tests-source-style-name-p
               name
               :allow-nested-case-name allow-nested-case-name)
        (error "~A selector ~A must be a source-style JSON case name"
               label name))
      (when (gethash name seen)
        (error "~A selector list has duplicate name ~A" label name))
      (setf (gethash name seen) t))))

(defun filter-execution-spec-tests-root-cases
    (cases names label &key (selector-order-p t))
  (let ((case-index (make-hash-table :test 'equal)))
    (dolist (case cases)
      (let ((name (fixture-required-field case "name")))
        (when (gethash name case-index)
          (error "~A root has duplicate case name ~A" label name))
        (setf (gethash name case-index) case)))
    (if names
        (if selector-order-p
            (mapcar
             (lambda (name)
               (or (gethash name case-index)
                   (error "~A selector ~A did not match any loaded case"
                          label name)))
             names)
            (let ((selected nil)
                  (seen (make-hash-table :test 'equal)))
              (dolist (case cases)
                (let ((name (fixture-required-field case "name")))
                  (when (member name names :test #'string=)
                    (push case selected)
                    (setf (gethash name seen) t))))
              (dolist (name names)
                (unless (gethash name seen)
                  (error "~A selector ~A did not match any loaded case"
                         label name)))
              (nreverse selected)))
        cases)))

(defun execution-spec-tests-blockchain-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-blockchain-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-transaction-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-transaction-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-state-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-state-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-trie-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-trie-test-subdirs+
     :require-json-p t)))

(defmacro with-execution-spec-tests-fixture-root ((root) &body body)
  `(let ((,root (execution-spec-tests-fixture-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-blockchain-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-blockchain-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing blockchain_tests_engine or blockchain_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-transaction-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-transaction-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing transaction_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-state-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-state-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing state_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-trie-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-trie-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing trie_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro deftest (name &body body)
  `(progn
     (pushnew ',name *tests*)
     (defun ,name () ,@body)))

(defmacro is (form)
  `(unless ,form
     (error "Assertion failed: ~S" ',form)))

(defmacro signals (condition-type &body body)
  `(handler-case
       (progn
         ,@body
         (error "Expected condition ~S was not signaled" ',condition-type))
     (,condition-type () t)))

(defun run-all-tests ()
  (let ((passed 0)
        (skipped 0))
    (dolist (test (reverse *tests*))
      (handler-case
          (progn
            (funcall test)
            (incf passed)
            (format t "~&ok ~A" test))
        (test-skipped (condition)
          (incf skipped)
          (format t "~&skip ~A - ~A" test (test-skipped-reason condition)))))
    (format t "~&~D tests passed" passed)
    (when (plusp skipped)
      (format t ", ~D skipped" skipped))
    (format t ".~%")
    t))
