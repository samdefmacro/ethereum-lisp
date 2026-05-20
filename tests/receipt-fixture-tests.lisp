(in-package #:ethereum-lisp.test)

(defparameter +receipt-root-fixture-path+
  "tests/fixtures/execution-spec-tests/receipt-roots.json")

(defparameter +receipt-root-fixture-format+
  "ethereum-lisp/receipt-root-fixtures-v1")

(defparameter +receipt-root-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "referenceClients" "vectors"))

(defparameter +receipt-root-fixture-reference-client-fields+
  '("geth" "nethermind" "reth"))

(defparameter +receipt-root-fixture-vector-fields+
  '("name"
    "transactions"
    "receipts"
    "expectedTypes"
    "expectedEncodingPrefixes"
    "expectedEncodingLengths"
    "expectedRoot"
    "legacyOnlyRoot"))

(defparameter +receipt-root-fixture-receipt-fields+
  '("status" "cumulativeGasUsed"))

(defparameter +receipt-root-fixture-required-vector-names+
  '("mixed-post-byzantium-typed-receipts"))

(defun validate-receipt-root-fixture-object-fields
    (object allowed-fields label)
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

(defun validate-receipt-root-fixture-string-field (object field label)
  (let ((value (fixture-required-field object field)))
    (when (blank-string-p value)
      (error "~A ~A must be a non-empty string" label field))))

(defun validate-receipt-root-fixture-metadata (fixture)
  (validate-receipt-root-fixture-object-fields
   fixture
   +receipt-root-fixture-top-level-fields+
   "Receipt root fixture")
  (validate-fixture-format fixture +receipt-root-fixture-format+)
  (validate-receipt-root-fixture-string-field
   fixture
   "source"
   "Receipt root fixture")
  (validate-fixture-pinned-eest-source fixture)
  (let ((references (fixture-required-field fixture "referenceClients")))
    (validate-receipt-root-fixture-object-fields
     references
     +receipt-root-fixture-reference-client-fields+
     "Receipt root fixture referenceClients")
    (validate-receipt-root-fixture-string-field
     references
     "geth"
     "Receipt root fixture referenceClients")
    (validate-receipt-root-fixture-string-field
     references
     "nethermind"
     "Receipt root fixture referenceClients")
    (let ((reth (fixture-object-field references "reth")))
      (unless (or (null reth)
                  (and (stringp reth) (not (blank-string-p reth))))
        (error "Receipt root fixture referenceClients reth must be null or a non-empty string")))))

(defun validate-receipt-root-fixture-receipt-shape (receipt)
  (validate-receipt-root-fixture-object-fields
   receipt
   +receipt-root-fixture-receipt-fields+
   "Receipt root fixture receipt")
  (hex-to-quantity (fixture-required-field receipt "status"))
  (hex-to-quantity (fixture-required-field receipt "cumulativeGasUsed")))

(defun validate-receipt-root-fixture-vector-shape (vector)
  (validate-receipt-root-fixture-object-fields
   vector
   +receipt-root-fixture-vector-fields+
   "Receipt root fixture vector")
  (validate-receipt-root-fixture-string-field
   vector
   "name"
   "Receipt root fixture vector")
  (let ((transactions (fixture-required-field vector "transactions"))
        (receipts (fixture-required-field vector "receipts"))
        (expected-types (fixture-required-field vector "expectedTypes"))
        (prefixes (fixture-required-field vector "expectedEncodingPrefixes"))
        (lengths (fixture-required-field vector "expectedEncodingLengths")))
    (unless (and (listp transactions) transactions)
      (error "Receipt root fixture vector transactions must be a non-empty JSON array"))
    (unless (and (listp receipts) receipts)
      (error "Receipt root fixture vector receipts must be a non-empty JSON array"))
    (unless (and (listp expected-types) expected-types)
      (error "Receipt root fixture vector expectedTypes must be a non-empty JSON array"))
    (unless (and (listp prefixes) prefixes)
      (error "Receipt root fixture vector expectedEncodingPrefixes must be a non-empty JSON array"))
    (unless (and (listp lengths) lengths)
      (error "Receipt root fixture vector expectedEncodingLengths must be a non-empty JSON array"))
    (unless (= (length transactions)
               (length receipts)
               (length expected-types)
               (length prefixes)
               (length lengths))
      (error "Receipt root fixture vector transaction, receipt, type, prefix, and length counts must match"))
    (dolist (transaction transactions)
      (hex-to-bytes transaction))
    (dolist (receipt receipts)
      (validate-receipt-root-fixture-receipt-shape receipt))
    (dolist (expected-type expected-types)
      (let ((type (hex-to-quantity expected-type)))
        (unless (<= 0 type 4)
          (error "Receipt root fixture vector expectedTypes entries must be known transaction types"))))
    (dolist (prefix prefixes)
      (hex-to-bytes prefix))
    (dolist (length lengths)
      (unless (and (integerp length) (plusp length))
        (error "Receipt root fixture vector expectedEncodingLengths entries must be positive integers"))))
  (hash32-from-hex (fixture-required-field vector "expectedRoot"))
  (hash32-from-hex (fixture-required-field vector "legacyOnlyRoot")))

(defun validate-receipt-root-fixture-vector-coverage (vectors)
  (let ((seen-names (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (validate-receipt-root-fixture-vector-shape vector)
      (let ((name (fixture-required-field vector "name")))
        (when (gethash name seen-names)
          (error "Receipt root fixture duplicate vector name ~A" name))
        (setf (gethash name seen-names) t)))
    (dolist (name +receipt-root-fixture-required-vector-names+)
      (unless (gethash name seen-names)
        (error "Receipt root fixture is missing required seed vector ~A"
               name)))))

(defun load-receipt-root-vectors (path)
  (let* ((fixture (load-handwritten-fixture-file path))
         (vectors (fixture-object-field fixture "vectors")))
    (validate-receipt-root-fixture-metadata fixture)
    (unless (listp vectors)
      (error "Receipt fixture vectors must be a JSON array"))
    (validate-receipt-root-fixture-vector-coverage vectors)
    vectors))

(defun receipt-fixture-receipt (object)
  (make-receipt
   :status (hex-to-quantity (fixture-object-field object "status"))
   :cumulative-gas-used
   (hex-to-quantity (fixture-object-field object "cumulativeGasUsed"))))

(deftest receipt-root-fixture-metadata-validation
  (let* ((fixture (load-handwritten-fixture-file +receipt-root-fixture-path+))
         (vectors (fixture-required-field fixture "vectors")))
    (validate-receipt-root-fixture-metadata fixture)
    (validate-receipt-root-fixture-vector-coverage vectors)
    (signals error
      (validate-receipt-root-fixture-metadata
       (append fixture (list (cons "unexpected" t)))))
    (signals error
      (validate-receipt-root-fixture-metadata
       (list (cons "format" +receipt-root-fixture-format+)
             (cons "source" "seed")
             (cons "source" "duplicate seed")
             (cons "executionSpecTests"
                   (list (cons "release" +phase-a-eest-release+)
                         (cons "tagTarget" +phase-a-eest-tag-target+)
                         (cons "archive" +phase-a-eest-archive+)
                         (cons "status" "seed")))
             (cons "referenceClients"
                   (list (cons "geth" "8a0223e")
                         (cons "nethermind" "1c72a72")
                         (cons "reth" nil)))
             (cons "vectors" nil))))
    (signals error
      (validate-receipt-root-fixture-vector-coverage
       (remove "mixed-post-byzantium-typed-receipts"
               vectors
               :test #'string=
               :key (lambda (candidate)
                      (fixture-required-field candidate "name")))))))

(deftest receipt-root-fixture-vectors
  (dolist (vector (load-receipt-root-vectors +receipt-root-fixture-path+))
    (let* ((transactions
             (mapcar (lambda (raw)
                       (transaction-from-encoding (hex-to-bytes raw)))
                     (fixture-object-field vector "transactions")))
           (receipts
             (mapcar #'receipt-fixture-receipt
                     (fixture-object-field vector "receipts")))
           (expected-prefixes
             (fixture-object-field vector "expectedEncodingPrefixes"))
           (expected-types
             (fixture-object-field vector "expectedTypes"))
           (expected-lengths
             (fixture-object-field vector "expectedEncodingLengths"))
           (typed-root
             (transaction-receipt-list-root transactions receipts))
           (legacy-only-root
             (receipt-list-root receipts)))
      (is (= (length transactions) (length receipts)))
      (is (= (length expected-types) (length receipts)))
      (is (= (length expected-prefixes) (length receipts)))
      (is (= (length expected-lengths) (length receipts)))
      (loop for transaction in transactions
            for receipt in receipts
            for expected-type in expected-types
            for expected-prefix in expected-prefixes
            for expected-length in expected-lengths
            do (let ((encoding
                       (bytes-to-hex
                        (transaction-receipt-encoding
                         transaction receipt))))
                 (is (= (hex-to-quantity expected-type)
                        (transaction-type transaction)))
                 (is (= expected-length (length encoding)))
                 (is (string= expected-prefix
                              (subseq encoding 0
                                      (length expected-prefix))))))
      (is (string= (fixture-object-field vector "expectedRoot")
                   (hash32-to-hex typed-root)))
      (is (string= (fixture-object-field vector "legacyOnlyRoot")
                   (hash32-to-hex legacy-only-root)))
      (is (not (string= (hash32-to-hex typed-root)
                        (hash32-to-hex legacy-only-root)))))))
