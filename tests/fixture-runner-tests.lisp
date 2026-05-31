(in-package #:ethereum-lisp.test)

(defparameter +minimal-blockchain-fixture-path+
  "tests/fixtures/execution-spec-tests/minimal-blockchain.json")

(defparameter +eest-blockchain-engine-fixture-fields+
  '("fixture-format" "network" "blocks" "engineNewPayloadV2"))

(defparameter +eest-blockchain-engine-newpayload-v2-fields+
  '("chainId" "config" "parent" "payload" "expect"))

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

(defun validate-eest-blockchain-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST blockchain test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST blockchain test case name in ~A must be a string"
                 source))
        (when (blank-string-p name)
          (error "EEST blockchain test case name in ~A must be present"
                 source))
        (when (gethash name seen)
          (error "EEST blockchain test file ~A has duplicate case name ~A"
                 source name))
        (unless (listp case)
          (error "EEST blockchain test case ~A must be a JSON object"
                 name))
        (setf (gethash name seen) t)))))

(defun normalize-eest-blockchain-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun eest-blockchain-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun load-eest-blockchain-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-blockchain-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-blockchain-root-case-name
                  root
                  path
                  (car entry)
                  singleton-p)))
           (unless (eest-blockchain-selector-source-style-p source-name)
             (error "EEST blockchain source name ~A must be source-style"
                    source-name))
           (normalize-eest-blockchain-test-case source-name (cdr entry))))
       entries))))

(defun validate-eest-blockchain-selector-list (names)
  (validate-execution-spec-tests-selector-list names "EEST blockchain"))

(defun eest-blockchain-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p name))

(defun load-eest-blockchain-test-root-cases (root &key names)
  (when names
    (validate-eest-blockchain-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (eest-blockchain-test-root-json-paths root)
         append (load-eest-blockchain-test-root-file-cases root path))
   names
   "EEST blockchain test"))

(defun report-eest-blockchain-test-root-case (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "format" (fixture-object-field fixture "fixture-format"))
          (cons "network" (fixture-object-field fixture "network"))
          (cons "blocks" (length (fixture-object-field fixture "blocks"))))))

(defun validate-eest-blockchain-json-array-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (listp value)
      (error "~A ~A must be a JSON array" label field))
    value))

(defun validate-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-engine-fixture-fields+
     label)
    (unless (string= "blockchain_test"
                     (fixture-required-field fixture "fixture-format"))
      (error "~A fixture-format must be blockchain_test" label))
    (validate-eest-blockchain-json-array-field fixture "blocks" label)
    (when (plusp (length (fixture-object-field fixture "blocks")))
      (error "~A replay materializer expects an embedded engineNewPayloadV2 case"
             label))
    (let ((engine (fixture-required-field fixture "engineNewPayloadV2")))
      (validate-fixture-object-fields
       engine
       +eest-blockchain-engine-newpayload-v2-fields+
       (format nil "~A engineNewPayloadV2" label))
      (dolist (field +eest-blockchain-engine-newpayload-v2-fields+)
        (fixture-required-field engine field))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "parent")
       "accounts"
       (format nil "~A parent" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "transactions"
       (format nil "~A payload" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "withdrawals"
       (format nil "~A payload" label))
      engine)))

(defun materialize-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (engine (validate-eest-blockchain-engine-newpayload-v2-case case)))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "network" (fixture-required-field fixture "network"))
          (cons "chainId" (fixture-required-field engine "chainId"))
          (cons "config" (fixture-required-field engine "config"))
          (cons "parent" (fixture-required-field engine "parent"))
          (cons "payload" (fixture-required-field engine "payload"))
          (cons "expect" (fixture-required-field engine "expect")))))

(defun load-handwritten-fixture-file (path)
  (parse-json (fixture-file-string path)))

(defun handwritten-fixture-cases (fixture)
  (let ((cases (fixture-object-field fixture "cases")))
    (unless (listp cases)
      (error "Fixture cases must be a JSON array"))
    cases))

(defun select-handwritten-fixture-case (fixture name)
  (find name (handwritten-fixture-cases fixture)
        :key (lambda (case)
               (fixture-object-field case "name"))
        :test #'string=))

(defun report-handwritten-fixture-case (fixture case path)
  (list (cons "format" (fixture-object-field fixture "format"))
        (cons "name" (fixture-object-field case "name"))
        (cons "network" (fixture-object-field case "network"))
        (cons "source" path)
        (cons "blocks" (length (fixture-object-field case "blocks")))
        (cons "status"
              (fixture-object-field
               (fixture-object-field case "expect")
               "status"))))

(defun run-handwritten-fixture-case (path name)
  (let* ((fixture (load-handwritten-fixture-file path))
         (case (select-handwritten-fixture-case fixture name)))
    (unless case
      (error "Fixture case not found: ~A" name))
    (report-handwritten-fixture-case fixture case path)))

(deftest handwritten-fixture-runner-selects-and-reports-case
  (let ((report
          (run-handwritten-fixture-case
           +minimal-blockchain-fixture-path+
           "empty-shanghai-blockchain-smoke")))
    (is (string= "ethereum-lisp/minimal-blockchain-fixture-v1"
                 (fixture-object-field report "format")))
    (is (string= "empty-shanghai-blockchain-smoke"
                 (fixture-object-field report "name")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (is (string= "valid" (fixture-object-field report "status")))))

(deftest handwritten-fixture-runner-rejects-missing-case
  (signals error
    (run-handwritten-fixture-case
     +minimal-blockchain-fixture-path+
     "missing-case")))

(deftest eest-blockchain-test-root-json-discovery
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-blockchain-test-root-json-paths root)))
    (is (= 1 (length paths)))
    (is (equal '("shanghai/phase-a-empty-engine.json")
               (eest-blockchain-test-root-file-names root)))))

(deftest eest-blockchain-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-blockchain-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-blockchain-test-root-json-paths root))))

(deftest eest-blockchain-test-root-case-loading
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-blockchain-test-root-cases root))
         (selected (load-eest-blockchain-test-root-cases
                    root
                    :names '("shanghai/phase-a-empty-engine.json")))
         (report (report-eest-blockchain-test-root-case (first selected))))
    (is (= 1 (length cases)))
    (is (= 1 (length selected)))
    (is (string= "shanghai/phase-a-empty-engine.json"
                 (fixture-object-field report "name")))
    (is (string= "blockchain_test" (fixture-object-field report "format")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (let ((materialized
            (materialize-eest-blockchain-engine-newpayload-v2-case
             (first selected))))
      (is (string= "shanghai/phase-a-empty-engine.json"
                   (fixture-object-field materialized "name")))
      (is (string= "VALID"
                   (fixture-object-field
                    (fixture-object-field materialized "expect")
                    "status"))))
    (signals error
      (load-eest-blockchain-test-root-cases
       root
       :names '("missing.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("shanghai/phase-a-empty-engine.json"
         "shanghai/phase-a-empty-engine.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("phase-a-empty-engine.json/case/extra")))))
