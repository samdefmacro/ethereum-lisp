(in-package #:ethereum-lisp.test)

(defun transaction-fixture-require-types-present (vectors types label)
  (unless (listp vectors)
    (error "~A vectors must be a list" label))
  (let ((seen-types (make-hash-table :test 'eq)))
    (dolist (vector vectors)
      (unless (listp vector)
        (error "~A vector must be a JSON object" label))
      (let ((type (transaction-fixture-type-keyword
                   (fixture-required-field vector "type"))))
        (setf (gethash type seen-types) t)))
    (dolist (type types)
      (unless (gethash type seen-types)
        (error "~A is missing required transaction type ~A"
               label
               type)))))

(defun transaction-fixture-vectors-by-txbytes (vectors label)
  (unless (listp vectors)
    (error "~A vectors must be a list" label))
  (let ((by-txbytes (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (unless (listp vector)
        (error "~A vector must be a JSON object" label))
      (let ((txbytes (fixture-required-field vector "txbytes")))
        (when (gethash txbytes by-txbytes)
          (error "~A has duplicate txbytes ~A" label txbytes))
        (setf (gethash txbytes by-txbytes) vector)))
    by-txbytes))

(defun transaction-fixture-assert-vector-aligned (vector seed-by-txbytes label)
  (let* ((type (transaction-fixture-type-keyword
                (fixture-required-field vector "type")))
         (txbytes (fixture-required-field vector "txbytes"))
         (seed-vector (gethash txbytes seed-by-txbytes)))
    (unless seed-vector
      (error "~A vector ~A has no matching seed fixture txbytes"
             label
             (fixture-required-field vector "name")))
    (dolist (field '("type" "chainId" "txbytes" "hash" "sender"
                     "signature" "decoded" "result"))
      (unless (equal (fixture-required-field vector field)
                     (fixture-required-field seed-vector field))
        (error "~A type ~A field ~A does not match seed fixture"
               label
               type
               field)))
    (when (or (fixture-field-present-p vector "contractAddress")
              (fixture-field-present-p seed-vector "contractAddress"))
      (unless (equal (fixture-object-field vector "contractAddress")
                     (fixture-object-field seed-vector "contractAddress"))
        (error "~A type ~A contractAddress does not match seed fixture"
               label
               type)))
    (when (or (fixture-field-present-p vector "accessList")
              (fixture-field-present-p seed-vector "accessList"))
      (unless (equal (fixture-object-field vector "accessList")
                     (fixture-object-field seed-vector "accessList"))
        (error "~A type ~A accessList does not match seed fixture"
               label
               type)))))

(defun validate-phase-a-eest-transaction-seed-alignment
    (phase-a-vectors seed-vectors)
  (transaction-fixture-require-types-present
   phase-a-vectors
   +phase-a-eest-transaction-required-types+
   "Phase A EEST transaction subset")
  (transaction-fixture-require-types-present
   seed-vectors
   +phase-a-eest-transaction-required-types+
   "Seed transaction fixture")
  (let ((seed-by-txbytes
          (transaction-fixture-vectors-by-txbytes
           seed-vectors
           "Seed transaction fixture")))
    (dolist (vector phase-a-vectors)
      (transaction-fixture-assert-vector-aligned
       vector
       seed-by-txbytes
       "Phase A EEST transaction")))
  phase-a-vectors)

(defun validate-eest-transaction-seed-alignment
    (eest-vectors seed-vectors)
  (transaction-fixture-require-types-present
   eest-vectors
   +transaction-fixture-required-types+
   "EEST transaction subset")
  (transaction-fixture-require-types-present
   seed-vectors
   +transaction-fixture-required-types+
   "Seed transaction fixture")
  (let ((seed-by-txbytes
          (transaction-fixture-vectors-by-txbytes
           seed-vectors
           "Seed transaction fixture")))
    (dolist (vector eest-vectors)
      (transaction-fixture-assert-vector-aligned
       vector
       seed-by-txbytes
       "EEST transaction")))
  eest-vectors)

(defun validate-transaction-fixture-vector-shape (vector)
  (validate-transaction-fixture-object-fields
   vector
   +transaction-fixture-vector-fields+
   "Transaction fixture vector")
  (dolist (field +transaction-fixture-required-vector-fields+)
    (fixture-required-field vector field))
  (validate-transaction-fixture-string-field vector "name")
  (transaction-fixture-type-keyword (fixture-required-field vector "type"))
  (unless (and (integerp (fixture-required-field vector "chainId"))
               (not (minusp (fixture-required-field vector "chainId"))))
    (error "Transaction fixture chainId must be a non-negative integer"))
  (unless (listp (fixture-required-field vector "result"))
    (error "Transaction fixture result must be a JSON object"))
  (transaction-fixture-txbytes-value vector)
  (validate-transaction-fixture-hash-field vector)
  (validate-transaction-fixture-address-field vector)
  (validate-transaction-fixture-contract-address-field vector)
  (validate-transaction-fixture-signature-shape vector)
  (validate-transaction-fixture-decoded-shape vector)
  (validate-transaction-fixture-access-list-shape vector))

(defun validate-transaction-fixture-unique-txbytes (seen vector)
  (let ((value (transaction-fixture-txbytes-value vector)))
    (let ((previous (gethash value seen)))
      (when previous
        (error "Transaction fixture duplicate txbytes ~A in ~A and ~A"
               value previous (fixture-object-field vector "name"))))
    (setf (gethash value seen) (fixture-object-field vector "name"))))

(defun transaction-fixture-exception-tokens (exception)
  (let ((tokens nil)
        (start 0))
    (loop for separator = (position #\| exception :start start)
          do (let ((token (subseq exception start separator)))
               (when (blank-string-p token)
                 (error "Transaction fixture exception contains an empty token"))
               (push token tokens))
          while separator
          do (setf start (1+ separator)))
    (nreverse tokens)))

(defun transaction-fixture-known-exception-p (exception)
  (every (lambda (token)
           (member token +transaction-fixture-known-exceptions+ :test #'string=))
         (transaction-fixture-exception-tokens exception)))

(defun transaction-fixture-type-valid-on-fork-p (type fork)
  (ecase type
    (:legacy t)
    (:access-list (member fork '("Berlin" "London" "Paris" "Shanghai"
                                 "Cancun" "Prague")
                          :test #'string=))
    (:dynamic-fee (member fork '("London" "Paris" "Shanghai" "Cancun" "Prague")
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

(defun validate-transaction-fixture-quantity-field
    (vector fork result field)
  (let ((value (fixture-object-field result field)))
    (unless (or (null value) (stringp value))
      (error "Transaction fixture ~A result for fork ~A ~A must be a string"
             (fixture-object-field vector "name")
             fork
             field))
    (when (blank-string-p value)
      (error "Transaction fixture ~A valid result for fork ~A needs ~A"
             (fixture-object-field vector "name")
             fork
             field))
    (unless (string= value
                     (string-downcase
                      (quantity-to-hex (hex-to-quantity value))))
      (error "Transaction fixture ~A result for fork ~A has non-canonical ~A"
             (fixture-object-field vector "name")
             fork
             field))))

(defun validate-transaction-fixture-hash-result-field
    (vector fork result)
  (let ((value (fixture-object-field result "hash")))
    (unless (or (null value) (stringp value))
      (error "Transaction fixture ~A result for fork ~A hash must be a string"
             (fixture-object-field vector "name")
             fork))
    (when (blank-string-p value)
      (error "Transaction fixture ~A valid result for fork ~A needs hash"
             (fixture-object-field vector "name")
             fork))
    (unless (string= value
                     (transaction-fixture-canonical-hash32
                      value
                      "Transaction fixture result hash"))
      (error "Transaction fixture ~A result for fork ~A has non-canonical hash"
             (fixture-object-field vector "name")
             fork))))

(defun validate-transaction-fixture-sender-result-field
    (vector fork result)
  (let ((value (fixture-object-field result "sender")))
    (unless (or (null value) (stringp value))
      (error "Transaction fixture ~A result for fork ~A sender must be a string"
             (fixture-object-field vector "name")
             fork))
    (when (blank-string-p value)
      (error "Transaction fixture ~A valid result for fork ~A needs sender"
             (fixture-object-field vector "name")
             fork))
    (unless (string= value
                     (transaction-fixture-canonical-address
                      value
                      "Transaction fixture result sender"))
      (error "Transaction fixture ~A result for fork ~A has non-canonical sender"
             (fixture-object-field vector "name")
             fork))))

(defun validate-transaction-fixture-result-entry
    (vector type fork result)
  (validate-transaction-fixture-object-fields
   result
   +transaction-fixture-result-entry-fields+
   (format nil "Transaction fixture ~A result for fork ~A"
           (fixture-object-field vector "name")
           fork))
  (let ((hash-present-p (fixture-field-present-p result "hash"))
        (sender-present-p (fixture-field-present-p result "sender"))
        (exception-present-p (fixture-field-present-p result "exception"))
        (intrinsic-gas-present-p (fixture-field-present-p result "intrinsicGas"))
        (exception (fixture-object-field result "exception"))
        (intrinsic-gas (fixture-object-field result "intrinsicGas")))
    (when (and exception-present-p
               (not (or (null exception) (stringp exception))))
      (error "Transaction fixture ~A result for fork ~A exception must be a string"
             (fixture-object-field vector "name")
             fork))
    (when (and intrinsic-gas-present-p
               (not (stringp intrinsic-gas)))
      (error "Transaction fixture ~A result for fork ~A intrinsicGas must be a string"
             (fixture-object-field vector "name")
             fork))
    (when (and exception-present-p (blank-string-p exception))
      (error "Transaction fixture ~A result for fork ~A has a blank exception"
             (fixture-object-field vector "name")
             fork))
    (when (and hash-present-p (not sender-present-p))
      (error "Transaction fixture ~A result for fork ~A has hash without sender"
             (fixture-object-field vector "name")
             fork))
    (when (and sender-present-p (not hash-present-p))
      (error "Transaction fixture ~A result for fork ~A has sender without hash"
             (fixture-object-field vector "name")
             fork))
    (if (blank-string-p exception)
        (progn
          (validate-transaction-fixture-quantity-field
           vector fork result "intrinsicGas")
          (unless hash-present-p
            (error "Transaction fixture ~A valid result for fork ~A needs hash"
                   (fixture-object-field vector "name")
                   fork))
          (unless sender-present-p
            (error "Transaction fixture ~A valid result for fork ~A needs sender"
                   (fixture-object-field vector "name")
                   fork))
          (when hash-present-p
            (validate-transaction-fixture-hash-result-field
             vector fork result)
            (validate-transaction-fixture-sender-result-field
             vector fork result)))
        (progn
          (unless (transaction-fixture-known-exception-p exception)
            (error "Transaction fixture ~A result for fork ~A has unknown exception ~A"
                   (fixture-object-field vector "name")
                   fork
                   exception))
          (when intrinsic-gas-present-p
            (error "Transaction fixture ~A invalid result for fork ~A must not include intrinsicGas"
                   (fixture-object-field vector "name")
                   fork))
          (when hash-present-p
            (error "Transaction fixture ~A invalid result for fork ~A must not include hash"
                   (fixture-object-field vector "name")
                   fork))
          (when sender-present-p
            (error "Transaction fixture ~A invalid result for fork ~A must not include sender"
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

(defun validate-transaction-fixture-result-forks (vector result)
  (let ((seen-forks (make-hash-table :test 'equal)))
    (dolist (check result)
      (unless (consp check)
        (error "Transaction fixture ~A result entries must be JSON object fields"
               (fixture-object-field vector "name")))
      (let ((fork (car check)))
        (unless (stringp fork)
          (error "Transaction fixture ~A result fork must be a string"
                 (fixture-object-field vector "name")))
        (when (blank-string-p fork)
          (error "Transaction fixture ~A result fork must be present"
                 (fixture-object-field vector "name")))
        (when (gethash fork seen-forks)
          (error "Transaction fixture ~A has duplicate result fork ~A"
                 (fixture-object-field vector "name")
                 fork))
        (setf (gethash fork seen-forks) t)
        (unless (member fork +transaction-fixture-forks+ :test #'string=)
          (error "Transaction fixture ~A has unknown result fork ~A"
                 (fixture-object-field vector "name")
                 fork))))
    (dolist (fork +transaction-fixture-forks+)
      (unless (gethash fork seen-forks)
        (error "Transaction fixture ~A is missing result for fork ~A"
               (fixture-object-field vector "name")
               fork)))))

(defun validate-transaction-fixture-result-shape (vector)
  (unless (listp vector)
    (error "Transaction fixture result vector must be a JSON object"))
  (let ((type (transaction-fixture-type-keyword
               (fixture-required-field vector "type")))
        (result (fixture-object-field vector "result")))
    (unless (listp result)
      (error "Transaction fixture result must be a JSON object"))
    (validate-transaction-fixture-result-forks vector result)
    (dolist (check result)
      (validate-transaction-fixture-result-entry
       vector
       type
       (car check)
       (cdr check)))))

(defun validate-transaction-fixture-vector-set
    (vectors &key require-required-types)
  (unless (listp vectors)
    (error "Transaction fixture vectors must be a list"))
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
      (validate-transaction-fixture-result-shape vector)
      (validate-transaction-fixture-decoded-vector vector))
    (when require-required-types
      (dolist (type +transaction-fixture-required-types+)
        (unless (member type seen-types)
          (error "Transaction fixture vectors are missing required type ~A"
                 type))))))

(defun validate-transaction-fixture-required-vector-names
    (vectors required-names)
  (let ((vector-by-name (make-hash-table :test 'equal))
        (seen-required-names (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (setf (gethash (fixture-required-field vector "name") vector-by-name)
            vector))
    (dolist (name required-names)
      (when (gethash name seen-required-names)
        (error "Transaction fixture required vector list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name vector-by-name)
        (error "Transaction fixture is missing required seed vector ~A"
               name)))))

(defun validate-transaction-fixture-required-vector-types
    (vectors required-name-types label)
  (let ((vector-by-name (make-hash-table :test 'equal))
        (seen-required-names (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (setf (gethash (fixture-required-field vector "name") vector-by-name)
            vector))
    (dolist (entry required-name-types)
      (unless (and (consp entry)
                   (stringp (car entry))
                   (keywordp (cdr entry)))
        (error "~A required vector entry is malformed: ~S" label entry))
      (when (gethash (car entry) seen-required-names)
        (error "~A required vector list has duplicate name ~A"
               label
               (car entry)))
      (setf (gethash (car entry) seen-required-names) t)
      (let ((vector (gethash (car entry) vector-by-name)))
        (unless vector
          (error "~A is missing required vector ~A" label (car entry)))
        (let ((actual-type
                (transaction-fixture-type-keyword
                 (fixture-required-field vector "type"))))
          (unless (eq actual-type (cdr entry))
            (error "~A vector ~A has type ~A but expected ~A"
                   label
                   (car entry)
                   actual-type
                   (cdr entry)))))))
  vectors)

(defun validate-transaction-envelope-vector-coverage (vectors)
  (validate-transaction-fixture-vector-set vectors :require-required-types t)
  (validate-transaction-fixture-required-vector-names
   vectors
   +transaction-envelope-fixture-required-vector-names+)
  (validate-transaction-fixture-required-vector-types
   vectors
   +transaction-envelope-fixture-pinned-valid-vector-types+
   "Transaction fixture pinned valid vectors")
  (let ((summary (transaction-fixture-vector-summary vectors)))
    (validate-transaction-fixture-decoded-coverage
     vectors
     summary
     "Transaction fixture")
    (validate-transaction-fixture-signature-coverage
     vectors
     summary
     "Transaction fixture")
    (validate-transaction-fixture-access-list-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-contract-creation-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-input-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-dynamic-fee-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-blob-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-set-code-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-legacy-protection-coverage
     summary
     "Transaction fixture")
    (validate-transaction-fixture-result-count-summary
     vectors
     summary
     "Transaction fixture")))

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
    ((string= fork "Homestead")
     (make-chain-config :homestead-block 0))
    ((string= fork "EIP150")
     (make-chain-config :homestead-block 0
                        :eip150-block 0))
    ((string= fork "EIP158")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0))
    ((string= fork "Byzantium")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0))
    ((string= fork "Constantinople")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0))
    ((string= fork "Istanbul")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0))
    ((string= fork "Berlin")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0))
    ((string= fork "London")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0
                        :london-block 0))
    ((string= fork "Paris")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0
                        :london-block 0))
    ((string= fork "Shanghai")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0
                        :london-block 0
                        :shanghai-time 0))
    ((string= fork "Cancun")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0
                        :london-block 0
                        :shanghai-time 0
                        :cancun-time 0))
    ((string= fork "Prague")
     (make-chain-config :homestead-block 0
                        :eip150-block 0
                        :eip155-block 0
                        :eip158-block 0
                        :byzantium-block 0
                        :constantinople-block 0
                        :istanbul-block 0
                        :berlin-block 0
                        :london-block 0
                        :shanghai-time 0
                        :cancun-time 0
                        :prague-time 0))
    (t (error "Unknown transaction fixture fork: ~A" fork))))

(defun transaction-fixture-result-checks (vector)
  (let ((result (fixture-object-field vector "result")))
    (unless (listp result)
      (error "Transaction fixture result must be a JSON object"))
    (validate-transaction-fixture-result-forks vector result)
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

(defun transaction-vector-chain-id (transaction)
  (etypecase transaction
    (legacy-transaction
     (legacy-transaction-chain-id transaction))
    (access-list-transaction
     (access-list-transaction-chain-id transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-chain-id transaction))
    (blob-transaction
     (blob-transaction-chain-id transaction))
    (set-code-transaction
     (set-code-transaction-chain-id transaction))))

(defun validate-transaction-fixture-decoded-envelope (vector transaction)
  (let ((expected-type
          (transaction-fixture-type-keyword
           (fixture-required-field vector "type")))
        (actual-type (transaction-vector-type transaction))
        (expected-chain-id (fixture-required-field vector "chainId"))
        (actual-chain-id (transaction-vector-chain-id transaction)))
    (unless (eq expected-type actual-type)
      (error "Transaction fixture ~A declared type ~A but decoded type ~A"
             (fixture-object-field vector "name")
             expected-type
             actual-type))
    (unless (and (integerp actual-chain-id)
                 (= expected-chain-id actual-chain-id))
      (error "Transaction fixture ~A declared chainId ~A but decoded chainId ~A"
             (fixture-object-field vector "name")
             expected-chain-id
             actual-chain-id))))

(defun validate-transaction-fixture-derived-results (vector transaction)
  (let ((expected-gas (quantity-to-hex
                       (transaction-intrinsic-gas transaction)))
        (expected-hash (hash32-to-hex (transaction-hash transaction)))
        (expected-sender (fixture-required-field vector "sender")))
    (dolist (check (fixture-object-field vector "result"))
      (let ((fork (car check))
            (result (cdr check)))
        (when (transaction-fixture-result-valid-p result)
          (unless (string= expected-gas
                           (fixture-required-field result "intrinsicGas"))
            (error "Transaction fixture ~A result for fork ~A has intrinsicGas ~A but decoded transaction needs ~A"
                   (fixture-object-field vector "name")
                   fork
                   (fixture-object-field result "intrinsicGas")
                   expected-gas))
          (when (fixture-field-present-p result "hash")
            (unless (string= expected-hash
                             (fixture-required-field result "hash"))
              (error "Transaction fixture ~A result for fork ~A has hash ~A but decoded transaction hash is ~A"
                     (fixture-object-field vector "name")
                     fork
                     (fixture-object-field result "hash")
                     expected-hash)))
          (when (fixture-field-present-p result "sender")
            (unless (string= expected-sender
                             (fixture-required-field result "sender"))
              (error "Transaction fixture ~A result for fork ~A has sender ~A but decoded transaction sender is ~A"
                     (fixture-object-field vector "name")
                     fork
                     (fixture-object-field result "sender")
                     expected-sender))))))))

(defun validate-transaction-fixture-decoded-access-list
    (vector transaction)
  (when (fixture-field-present-p vector "accessList")
    (let ((expected (fixture-object-field vector "accessList"))
          (actual
            (transaction-fixture-access-list-object
             (transaction-access-list transaction))))
      (unless (equal expected actual)
        (error "Transaction fixture ~A accessList does not match decoded transaction"
               (fixture-object-field vector "name"))))))

(defun validate-transaction-fixture-decoded-payload
    (vector transaction)
  (when (fixture-field-present-p vector "decoded")
    (let ((expected (fixture-object-field vector "decoded"))
          (actual (transaction-fixture-decoded-object transaction)))
      (unless (equal expected actual)
        (error "Transaction fixture ~A decoded payload does not match txbytes"
               (fixture-object-field vector "name"))))))

(defun validate-transaction-fixture-signature
    (vector transaction)
  (when (fixture-field-present-p vector "signature")
    (let ((expected (fixture-object-field vector "signature"))
          (actual (transaction-fixture-signature-object transaction)))
      (unless (equal expected actual)
        (error "Transaction fixture ~A signature does not match txbytes"
               (fixture-object-field vector "name"))))))

(defun validate-transaction-fixture-contract-address
    (vector transaction sender)
  (let ((expected
          (transaction-fixture-created-contract-address transaction sender))
        (actual (fixture-object-field vector "contractAddress")))
    (if expected
        (progn
          (unless actual
            (error "Transaction fixture ~A contractAddress must be present for contract creation"
                   (fixture-object-field vector "name")))
          (unless (string= actual (address-to-hex expected))
            (error "Transaction fixture ~A contractAddress does not match sender and nonce"
                   (fixture-object-field vector "name"))))
        (when actual
          (error "Transaction fixture ~A contractAddress is only valid for contract creation"
                 (fixture-object-field vector "name"))))))

(defun validate-transaction-fixture-decoded-vector (vector)
  (let* ((raw (transaction-fixture-txbytes-value vector))
         (chain-id (fixture-required-field vector "chainId"))
         (transaction (transaction-from-encoding (hex-to-bytes raw)))
         (sender (transaction-sender transaction :expected-chain-id chain-id)))
    (validate-transaction-fixture-decoded-envelope vector transaction)
    (unless (string= (fixture-required-field vector "hash")
                     (hash32-to-hex (transaction-hash transaction)))
      (error "Transaction fixture ~A hash does not match decoded transaction"
             (fixture-object-field vector "name")))
    (unless sender
      (error "Transaction fixture ~A sender recovery failed"
             (fixture-object-field vector "name")))
    (unless (string= (fixture-required-field vector "sender")
                     (address-to-hex sender))
      (error "Transaction fixture ~A sender does not match decoded transaction"
             (fixture-object-field vector "name")))
    (validate-transaction-fixture-signature vector transaction)
    (validate-transaction-fixture-decoded-payload vector transaction)
    (validate-transaction-fixture-contract-address vector transaction sender)
    (validate-transaction-fixture-decoded-access-list vector transaction)
    (validate-transaction-fixture-derived-results vector transaction)
    transaction))

(defun assert-transaction-fixture-vectors-replay (vectors)
  (dolist (vector vectors)
    (let* ((raw (transaction-fixture-txbytes vector))
           (chain-id (fixture-object-field vector "chainId"))
           (transaction (validate-transaction-fixture-decoded-vector vector))
           (sender (transaction-sender transaction
                                       :expected-chain-id chain-id)))
      (is (eq (transaction-fixture-type-keyword
               (fixture-object-field vector "type"))
              (transaction-vector-type transaction)))
      (is (string= raw (bytes-to-hex (transaction-encoding transaction))))
      (is (string= (fixture-object-field vector "hash")
                   (hash32-to-hex (transaction-hash transaction))))
      (is sender)
      (is (string= (fixture-object-field vector "sender")
                   (address-to-hex sender)))
      (let ((contract-address
              (transaction-fixture-created-contract-address transaction sender)))
        (if contract-address
            (is (string= (fixture-object-field vector "contractAddress")
                         (address-to-hex contract-address)))
            (is (not (fixture-field-present-p vector "contractAddress")))))
      (let ((wrong-chain-sender
              (transaction-sender transaction
                                  :expected-chain-id (1+ chain-id))))
        (if (and (typep transaction 'legacy-transaction)
                 (not (legacy-transaction-protected-p transaction)))
            (is (and wrong-chain-sender
                     (string= (address-to-hex sender)
                              (address-to-hex wrong-chain-sender))))
            (is (null wrong-chain-sender))))
      (dolist (check (transaction-fixture-result-checks vector))
        (let ((config (transaction-fixture-fork-config (car check)))
              (result (cdr check)))
          (if (transaction-fixture-result-valid-p result)
              (progn
                (is (validate-transaction-type-for-config
                     transaction config 0 0))
                (is (string= (fixture-object-field result "intrinsicGas")
                             (quantity-to-hex
                              (transaction-intrinsic-gas transaction))))
                (when (fixture-field-present-p result "hash")
                  (is (string= (fixture-object-field result "hash")
                               (hash32-to-hex
                                (transaction-hash transaction)))))
                (when (fixture-field-present-p result "sender")
                  (is (string= (fixture-object-field result "sender")
                               (address-to-hex sender)))))
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

