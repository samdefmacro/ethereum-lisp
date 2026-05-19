(in-package #:ethereum-lisp.test)

(defparameter +receipt-root-fixture-path+
  "tests/fixtures/execution-spec-tests/receipt-roots.json")

(defun load-receipt-root-vectors (path)
  (let* ((fixture (load-handwritten-fixture-file path))
         (vectors (fixture-object-field fixture "vectors")))
    (unless (listp vectors)
      (error "Receipt fixture vectors must be a JSON array"))
    vectors))

(defun receipt-fixture-receipt (object)
  (make-receipt
   :status (hex-to-quantity (fixture-object-field object "status"))
   :cumulative-gas-used
   (hex-to-quantity (fixture-object-field object "cumulativeGasUsed"))))

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
           (expected-lengths
             (fixture-object-field vector "expectedEncodingLengths"))
           (typed-root
             (transaction-receipt-list-root transactions receipts))
           (legacy-only-root
             (receipt-list-root receipts)))
      (is (= (length transactions) (length receipts)))
      (is (= (length expected-prefixes) (length receipts)))
      (is (= (length expected-lengths) (length receipts)))
      (loop for transaction in transactions
            for receipt in receipts
            for expected-prefix in expected-prefixes
            for expected-length in expected-lengths
            do (let ((encoding
                       (bytes-to-hex
                        (transaction-receipt-encoding
                         transaction receipt))))
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
