(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defparameter +transaction-fixture-forks+
  '("Frontier" "Berlin" "London" "Cancun" "Prague"))

(defun transaction-fixture-type-keyword (type)
  (cond
    ((string= type "legacy") :legacy)
    ((string= type "access-list") :access-list)
    ((string= type "dynamic-fee") :dynamic-fee)
    ((string= type "blob") :blob)
    ((string= type "set-code") :set-code)
    (t (error "Unknown transaction fixture type: ~A" type))))

(defun load-transaction-envelope-vectors (path)
  (let* ((fixture (load-handwritten-fixture-file path))
         (vectors (fixture-object-field fixture "vectors")))
    (unless (listp vectors)
      (error "Transaction fixture vectors must be a JSON array"))
    vectors))

(defun transaction-fixture-txbytes (vector)
  (or (fixture-object-field vector "txbytes")
      (fixture-object-field vector "raw")
      (error "Transaction fixture vector is missing txbytes")))

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
