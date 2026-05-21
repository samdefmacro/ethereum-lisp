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
    (unless (stringp value)
      (error "~A ~A must be a string" label field))
    (when (blank-string-p value)
      (error "~A ~A must be a non-empty string" label field))))

(defun validate-receipt-root-fixture-hex-string (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (let* ((bytes (hex-to-bytes value))
         (canonical (bytes-to-hex bytes)))
    (when (zerop (length bytes))
      (error "~A must encode at least one byte" label))
    (unless (string= value canonical)
      (error "~A must be canonical lowercase 0x-prefixed hex" label))))

(defun validate-receipt-root-fixture-quantity-string (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (hex-to-quantity value))

(defun validate-receipt-root-fixture-hash-string (value label)
  (unless (stringp value)
    (error "~A must be a hash hex string" label))
  (let ((canonical (hash32-to-hex (hash32-from-hex value))))
    (unless (string= value canonical)
      (error "~A must be canonical lowercase 0x-prefixed hex" label))))

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
  (let ((status (validate-receipt-root-fixture-quantity-string
                 (fixture-required-field receipt "status")
                 "Receipt root fixture receipt status")))
    (unless (or (= status 0) (= status 1))
      (error "Receipt root fixture receipt status must be 0x0 or 0x1")))
  (validate-receipt-root-fixture-quantity-string
   (fixture-required-field receipt "cumulativeGasUsed")
   "Receipt root fixture receipt cumulativeGasUsed"))

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
      (validate-receipt-root-fixture-hex-string
       transaction
       "Receipt root fixture vector transaction"))
    (dolist (receipt receipts)
      (validate-receipt-root-fixture-receipt-shape receipt))
    (dolist (expected-type expected-types)
      (let ((type (validate-receipt-root-fixture-quantity-string
                   expected-type
                   "Receipt root fixture vector expectedType")))
        (unless (<= 0 type 4)
          (error "Receipt root fixture vector expectedTypes entries must be known transaction types"))))
    (dolist (prefix prefixes)
      (validate-receipt-root-fixture-hex-string
       prefix
       "Receipt root fixture vector expectedEncodingPrefix"))
    (dolist (length lengths)
      (unless (and (integerp length) (plusp length))
        (error "Receipt root fixture vector expectedEncodingLengths entries must be positive integers"))))
  (validate-receipt-root-fixture-hash-string
   (fixture-required-field vector "expectedRoot")
   "Receipt root fixture vector expectedRoot")
  (validate-receipt-root-fixture-hash-string
   (fixture-required-field vector "legacyOnlyRoot")
   "Receipt root fixture vector legacyOnlyRoot"))

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
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-first (items value)
               (cons value (rest items))))
      (validate-receipt-root-fixture-metadata fixture)
      (validate-receipt-root-fixture-vector-coverage vectors)
      (signals error
        (validate-receipt-root-fixture-metadata
         (append fixture (list (cons "unexpected" t)))))
      (signals error
        (validate-receipt-root-fixture-metadata
         (replace-field fixture "source" 42)))
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
      (let* ((vector (first vectors))
             (receipt (first (fixture-required-field vector "receipts"))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field vector "name" 42)))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "transactions"
            (replace-first
             (fixture-required-field vector "transactions")
             42))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "transactions"
            (replace-first
             (fixture-required-field vector "transactions")
             "f8"))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "receipts"
            (replace-first
             (fixture-required-field vector "receipts")
             (replace-field receipt "status" 42)))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "receipts"
            (replace-first
             (fixture-required-field vector "receipts")
             (replace-field receipt "status" "0x2")))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "expectedTypes"
            (replace-first
             (fixture-required-field vector "expectedTypes")
             42))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "expectedEncodingPrefixes"
            (replace-first
             (fixture-required-field vector "expectedEncodingPrefixes")
             42))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "expectedEncodingPrefixes"
            (replace-first
             (fixture-required-field vector "expectedEncodingPrefixes")
             "0x"))))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field vector "expectedRoot" 42)))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "expectedRoot"
            "0000000000000000000000000000000000000000000000000000000000000000")))
        (signals error
          (validate-receipt-root-fixture-vector-shape
           (replace-field
            vector
            "legacyOnlyRoot"
            "0X0000000000000000000000000000000000000000000000000000000000000000"))))
      (signals error
        (validate-receipt-root-fixture-vector-coverage
         (remove "mixed-post-byzantium-typed-receipts"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-required-field candidate "name"))))))))

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
