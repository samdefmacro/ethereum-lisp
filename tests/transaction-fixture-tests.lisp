(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defparameter +transaction-envelope-fixture-format+
  "ethereum-lisp/transaction-envelope-fixtures-v1")

(defparameter +transaction-fixture-forks+
  '("Frontier" "Berlin" "London" "Cancun" "Prague"))

(defparameter +transaction-fixture-required-types+
  '(:legacy :access-list :dynamic-fee :blob :set-code))

(defparameter +transaction-fixture-known-exceptions+
  '("TransactionException.TYPE_1_TX_PRE_FORK"
    "TransactionException.TYPE_2_TX_PRE_FORK"
    "TransactionException.TYPE_3_TX_PRE_FORK"
    "TransactionException.TYPE_4_TX_PRE_FORK"))

(defun validate-transaction-envelope-fixture-metadata (fixture)
  (validate-fixture-format fixture +transaction-envelope-fixture-format+)
  (when (blank-string-p
         (fixture-required-field fixture "source"))
    (error "Transaction fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture)
  (let ((references
          (fixture-required-field fixture "referenceClients")))
    (unless (listp references)
      (error "Transaction fixture referenceClients must be a JSON object"))
    (dolist (client '("geth" "nethermind" "reth"))
      (unless (fixture-field-present-p references client)
        (error "Transaction fixture referenceClients is missing ~A"
               client)))
    (dolist (client '("geth" "nethermind"))
      (when (blank-string-p (fixture-object-field references client))
        (error "Transaction fixture referenceClients.~A must be present"
               client)))))

(defun transaction-fixture-type-keyword (type)
  (cond
    ((string= type "legacy") :legacy)
    ((string= type "access-list") :access-list)
    ((string= type "dynamic-fee") :dynamic-fee)
    ((string= type "blob") :blob)
    ((string= type "set-code") :set-code)
    (t (error "Unknown transaction fixture type: ~A" type))))

(defun validate-transaction-fixture-string-field (vector field)
  (when (blank-string-p (fixture-required-field vector field))
    (error "Transaction fixture ~A must be present" field)))

(defun validate-transaction-fixture-unique-field
    (seen vector field)
  (let ((value (fixture-required-field vector field)))
    (when (blank-string-p value)
      (error "Transaction fixture ~A must be present" field))
    (let ((previous (gethash value seen)))
      (when previous
        (error "Transaction fixture duplicate ~A ~A in ~A and ~A"
               field value previous (fixture-object-field vector "name"))))
    (setf (gethash value seen) (fixture-object-field vector "name"))))

(defun transaction-fixture-txbytes-value (vector)
  (let ((has-txbytes (fixture-field-present-p vector "txbytes"))
        (has-raw (fixture-field-present-p vector "raw")))
    (unless (or has-txbytes has-raw)
      (error "Transaction fixture txbytes must be present"))
    (when (and has-txbytes has-raw)
      (error "Transaction fixture must not include both txbytes and raw"))
    (let ((value (if has-txbytes
                     (fixture-object-field vector "txbytes")
                     (fixture-object-field vector "raw"))))
      (when (blank-string-p value)
        (error "Transaction fixture txbytes must be present"))
      (when (zerop (length (hex-to-bytes value)))
        (error "Transaction fixture txbytes must encode at least one byte"))
      value)))

(defun validate-transaction-fixture-hash-field (vector)
  (hash32-from-hex (fixture-required-field vector "hash")))

(defun validate-transaction-fixture-address-field (vector)
  (address-from-hex (fixture-required-field vector "sender")))

(defun validate-transaction-fixture-vector-shape (vector)
  (transaction-fixture-txbytes-value vector)
  (validate-transaction-fixture-hash-field vector)
  (validate-transaction-fixture-address-field vector))

(defun validate-transaction-fixture-unique-txbytes (seen vector)
  (let ((value (transaction-fixture-txbytes-value vector)))
    (let ((previous (gethash value seen)))
      (when previous
        (error "Transaction fixture duplicate txbytes ~A in ~A and ~A"
               value previous (fixture-object-field vector "name"))))
    (setf (gethash value seen) (fixture-object-field vector "name"))))

(defun transaction-fixture-known-exception-p (exception)
  (member exception +transaction-fixture-known-exceptions+ :test #'string=))

(defun transaction-fixture-type-valid-on-fork-p (type fork)
  (ecase type
    (:legacy t)
    (:access-list (member fork '("Berlin" "London" "Cancun" "Prague")
                          :test #'string=))
    (:dynamic-fee (member fork '("London" "Cancun" "Prague")
                          :test #'string=))
    (:blob (member fork '("Cancun" "Prague") :test #'string=))
    (:set-code (string= fork "Prague"))))

(defun transaction-fixture-expected-pre-fork-exception (type)
  (ecase type
    (:legacy nil)
    (:access-list "TransactionException.TYPE_1_TX_PRE_FORK")
    (:dynamic-fee "TransactionException.TYPE_2_TX_PRE_FORK")
    (:blob "TransactionException.TYPE_3_TX_PRE_FORK")
    (:set-code "TransactionException.TYPE_4_TX_PRE_FORK")))

(defun validate-transaction-fixture-result-entry
    (vector type fork result)
  (unless (listp result)
    (error "Transaction fixture ~A result for fork ~A must be a JSON object"
           (fixture-object-field vector "name")
           fork))
  (let ((exception (fixture-object-field result "exception"))
        (intrinsic-gas (fixture-object-field result "intrinsicGas")))
    (if (blank-string-p exception)
        (when (blank-string-p intrinsic-gas)
          (error "Transaction fixture ~A valid result for fork ~A needs intrinsicGas"
                 (fixture-object-field vector "name")
                 fork))
        (progn
          (unless (transaction-fixture-known-exception-p exception)
            (error "Transaction fixture ~A result for fork ~A has unknown exception ~A"
                   (fixture-object-field vector "name")
                   fork
                   exception))
          (when intrinsic-gas
            (error "Transaction fixture ~A invalid result for fork ~A must not include intrinsicGas"
                   (fixture-object-field vector "name")
                   fork))))
    (let ((expected-valid
            (transaction-fixture-type-valid-on-fork-p type fork)))
      (if expected-valid
          (unless (blank-string-p exception)
            (error "Transaction fixture ~A type ~A should be valid on fork ~A"
                   (fixture-object-field vector "name")
                   type
                   fork))
          (unless (string= exception
                           (transaction-fixture-expected-pre-fork-exception
                            type))
            (error "Transaction fixture ~A type ~A has wrong pre-fork result on ~A"
                   (fixture-object-field vector "name")
                   type
                   fork))))))

(defun validate-transaction-fixture-result-shape (vector)
  (let ((type (transaction-fixture-type-keyword
               (fixture-required-field vector "type")))
        (result (fixture-object-field vector "result")))
    (unless (listp result)
      (error "Transaction fixture result must be a JSON object"))
    (dolist (check result)
      (validate-transaction-fixture-result-entry
       vector
       type
       (car check)
       (cdr check)))))

(defun validate-transaction-envelope-vector-coverage (vectors)
  (let ((seen-names (make-hash-table :test 'equal))
        (seen-txbytes (make-hash-table :test 'equal))
        (seen-hashes (make-hash-table :test 'equal))
        (seen-types '()))
    (dolist (vector vectors)
      (unless (listp vector)
        (error "Transaction fixture vector must be a JSON object"))
      (validate-transaction-fixture-vector-shape vector)
      (validate-transaction-fixture-unique-field seen-names vector "name")
      (validate-transaction-fixture-unique-txbytes seen-txbytes vector)
      (validate-transaction-fixture-unique-field seen-hashes vector "hash")
      (validate-transaction-fixture-string-field vector "sender")
      (let ((type (transaction-fixture-type-keyword
                   (fixture-required-field vector "type"))))
        (pushnew type seen-types))
      (unless (and (integerp (fixture-required-field vector "chainId"))
                   (not (minusp (fixture-required-field vector "chainId"))))
        (error "Transaction fixture chainId must be a non-negative integer"))
      (validate-transaction-fixture-result-shape vector))
    (dolist (type +transaction-fixture-required-types+)
      (unless (member type seen-types)
        (error "Transaction fixture vectors are missing required type ~A"
               type)))))

(defun load-transaction-envelope-vectors (path)
  (let* ((fixture (load-handwritten-fixture-file path))
         (vectors (fixture-object-field fixture "vectors")))
    (validate-transaction-envelope-fixture-metadata fixture)
    (unless (listp vectors)
      (error "Transaction fixture vectors must be a JSON array"))
    (validate-transaction-envelope-vector-coverage vectors)
    vectors))

(defun transaction-fixture-txbytes (vector)
  (transaction-fixture-txbytes-value vector))

(defun transaction-fixture-fork-config (fork)
  (cond
    ((string= fork "Frontier")
     (make-chain-config))
    ((string= fork "Berlin")
     (make-chain-config :berlin-block 0))
    ((string= fork "London")
     (make-chain-config :berlin-block 0
                        :london-block 0))
    ((string= fork "Cancun")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :cancun-time 0))
    ((string= fork "Prague")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :cancun-time 0
                        :prague-time 0))
    (t (error "Unknown transaction fixture fork: ~A" fork))))

(defun transaction-fixture-result-checks (vector)
  (let ((result (fixture-object-field vector "result")))
    (unless (listp result)
      (error "Transaction fixture result must be a JSON object"))
    (dolist (fork +transaction-fixture-forks+)
      (unless (assoc fork result :test #'string=)
        (error "Transaction fixture ~A is missing result for fork ~A"
               (fixture-object-field vector "name")
               fork)))
    (dolist (check result)
      (unless (member (car check) +transaction-fixture-forks+ :test #'string=)
        (error "Transaction fixture ~A has unknown result fork ~A"
               (fixture-object-field vector "name")
               (car check))))
    result))

(defun transaction-fixture-result-valid-p (result)
  (blank-string-p (fixture-object-field result "exception")))

(defun transaction-fixture-exception-message (exception)
  (cond
    ((string= exception "TransactionException.TYPE_1_TX_PRE_FORK")
     "Access-list transaction before Berlin")
    ((string= exception "TransactionException.TYPE_2_TX_PRE_FORK")
     "Dynamic-fee transaction before London")
    ((string= exception "TransactionException.TYPE_3_TX_PRE_FORK")
     "Blob transaction before Cancun")
    ((string= exception "TransactionException.TYPE_4_TX_PRE_FORK")
     "Set-code transaction before Prague")
    (t (error "Unknown transaction fixture exception: ~A" exception))))

(defun transaction-vector-type (transaction)
  (typecase transaction
    (legacy-transaction :legacy)
    (access-list-transaction :access-list)
    (dynamic-fee-transaction :dynamic-fee)
    (blob-transaction :blob)
    (set-code-transaction :set-code)
    (otherwise :unknown)))

(deftest transaction-fixture-result-shape-validation
  (let ((vector (list (cons "name" "shape-test")
                      (cons "type" "dynamic-fee"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" nil))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "exception" ""))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.UNKNOWN"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" nil))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_1_TX_PRE_FORK"))))
    (validate-transaction-fixture-result-entry
     vector :dynamic-fee "London" (list (cons "intrinsicGas" "0x5208")))
    (validate-transaction-fixture-result-entry
     vector :dynamic-fee "Berlin" (list (cons "exception"
                                 "TransactionException.TYPE_2_TX_PRE_FORK")))))

(deftest transaction-fixture-vector-shape-validation
  (let ((valid-vector
          (list (cons "name" "shape-test")
                (cons "txbytes" "0x01")
                (cons "hash"
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                (cons "sender" "0x0000000000000000000000000000000000000001"))))
    (validate-transaction-fixture-vector-shape valid-vector))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "both-raw-and-txbytes")
           (cons "txbytes" "0x01")
           (cons "raw" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "empty-txbytes")
           (cons "txbytes" "0x")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-hash")
           (cons "txbytes" "0x01")
           (cons "hash" "0x01")
           (cons "sender" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-sender")
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x01")))))

(deftest transaction-envelope-fixture-vectors
  (dolist (vector (load-transaction-envelope-vectors
                   +transaction-envelope-fixture-path+))
    (let* ((raw (transaction-fixture-txbytes vector))
           (chain-id (fixture-object-field vector "chainId"))
           (transaction (transaction-from-encoding (hex-to-bytes raw)))
           (sender (transaction-sender transaction :expected-chain-id chain-id)))
      (is (eq (transaction-fixture-type-keyword
               (fixture-object-field vector "type"))
              (transaction-vector-type transaction)))
      (is (string= raw (bytes-to-hex (transaction-encoding transaction))))
      (is (string= (fixture-object-field vector "hash")
                   (hash32-to-hex (transaction-hash transaction))))
      (is sender)
      (is (string= (fixture-object-field vector "sender")
                   (address-to-hex sender)))
      (is (null (transaction-sender transaction
                                    :expected-chain-id (1+ chain-id))))
      (dolist (check (transaction-fixture-result-checks vector))
        (let ((config (transaction-fixture-fork-config (car check)))
              (result (cdr check)))
          (if (transaction-fixture-result-valid-p result)
              (progn
                (is (validate-transaction-type-for-config
                     transaction config 0 0))
                (is (string= (fixture-object-field result "intrinsicGas")
                             (quantity-to-hex
                              (transaction-intrinsic-gas transaction)))))
              (handler-case
                  (progn
                    (validate-transaction-type-for-config
                     transaction config 0 0)
                    (error "Expected transaction fixture exception ~A"
                           (fixture-object-field result "exception")))
                (block-validation-error (condition)
                  (is (string=
                       (transaction-fixture-exception-message
                        (fixture-object-field result "exception"))
                       (block-validation-error-message condition)))))))))))
