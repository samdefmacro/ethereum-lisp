(in-package #:ethereum-lisp.test)

(defparameter +minimal-blockchain-fixture-path+
  "tests/fixtures/execution-spec-tests/minimal-blockchain.json")

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

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
