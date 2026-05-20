(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defparameter +eest-transaction-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/transaction_tests/phase-a-sample.json")

(defparameter +phase-a-eest-transaction-test-case-names+
  '("phase-a-sample.json/legacy-eip155-sample"
    "phase-a-sample.json/typed-eip2930-access-list-sample"
    "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"))

(defparameter +transaction-envelope-fixture-format+
  "ethereum-lisp/transaction-envelope-fixtures-v1")

(defparameter +transaction-fixture-forks+
  '("Frontier" "Berlin" "London" "Shanghai" "Cancun" "Prague"))

(defparameter +transaction-fixture-required-types+
  '(:legacy :access-list :dynamic-fee :blob :set-code))

(defparameter +phase-a-eest-transaction-required-types+
  '(:legacy :access-list :dynamic-fee))

(defparameter +phase-a-eest-transaction-forbidden-types+
  '(:blob :set-code))

(defparameter +phase-a-eest-transaction-target-fork+
  "Shanghai")

(defparameter +transaction-fixture-known-exceptions+
  '("TransactionException.TYPE_1_TX_PRE_FORK"
    "TransactionException.TYPE_2_TX_PRE_FORK"
    "TransactionException.TYPE_3_TX_PRE_FORK"
    "TransactionException.TYPE_4_TX_PRE_FORK"))

(defparameter +transaction-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "referenceClients" "vectors"))

(defparameter +transaction-fixture-reference-client-fields+
  '("geth" "nethermind" "reth"))

(defparameter +transaction-fixture-vector-fields+
  '("name" "type" "chainId" "txbytes" "hash" "sender" "result"))

(defparameter +transaction-fixture-required-vector-fields+
  '("name" "type" "chainId" "txbytes" "hash" "sender" "result"))

(defparameter +transaction-fixture-result-entry-fields+
  '("exception" "intrinsicGas"))

(defparameter +eest-transaction-test-case-fields+
  '("txbytes" "result"))

(defparameter +eest-transaction-test-result-entry-fields+
  '("hash" "sender" "exception" "intrinsicGas"))

(defun validate-transaction-fixture-object-fields
    (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-transaction-envelope-fixture-metadata (fixture)
  (validate-transaction-fixture-object-fields
   fixture
   +transaction-fixture-top-level-fields+
   "Transaction fixture")
  (validate-fixture-format fixture +transaction-envelope-fixture-format+)
  (when (blank-string-p
         (fixture-required-field fixture "source"))
    (error "Transaction fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture)
  (let ((references
          (fixture-required-field fixture "referenceClients")))
    (validate-transaction-fixture-object-fields
     references
     +transaction-fixture-reference-client-fields+
     "Transaction fixture referenceClients")
    (dolist (client +transaction-fixture-reference-client-fields+)
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

(defun transaction-fixture-type-name (type)
  (ecase type
    (:legacy "legacy")
    (:access-list "access-list")
    (:dynamic-fee "dynamic-fee")
    (:blob "blob")
    (:set-code "set-code")))

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
    (unless has-txbytes
      (error "Transaction fixture txbytes must be present"))
    (when has-raw
      (error "Transaction fixture must use txbytes, not raw"))
    (let ((value (fixture-object-field vector "txbytes")))
      (when (blank-string-p value)
        (error "Transaction fixture txbytes must be present"))
      (when (zerop (length (hex-to-bytes value)))
        (error "Transaction fixture txbytes must encode at least one byte"))
      value)))

(defun validate-transaction-fixture-hash-field (vector)
  (hash32-from-hex (fixture-required-field vector "hash")))

(defun validate-transaction-fixture-address-field (vector)
  (address-from-hex (fixture-required-field vector "sender")))

(defun transaction-fixture-hex-prefixed-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun transaction-fixture-normalized-hex (value label)
  (when (blank-string-p value)
    (error "~A must be present" label))
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (if (transaction-fixture-hex-prefixed-p value)
      value
      (concatenate 'string "0x" value)))

(defun transaction-fixture-canonical-quantity (value label)
  (let ((canonical (quantity-to-hex (hex-to-quantity value))))
    (unless (string= value canonical)
      (error "~A must be a canonical quantity" label))
    canonical))

(defun normalize-eest-transaction-result-entry (case-name fork result)
  (unless (listp result)
    (error "EEST transaction case ~A result for fork ~A must be a JSON object"
           case-name
           fork))
  (validate-transaction-fixture-object-fields
   result
   +eest-transaction-test-result-entry-fields+
   (format nil "EEST transaction case ~A result for fork ~A"
           case-name
           fork))
  (let ((hash-present-p (fixture-field-present-p result "hash"))
        (sender-present-p (fixture-field-present-p result "sender"))
        (intrinsic-gas-present-p (fixture-field-present-p result "intrinsicGas"))
        (exception (fixture-object-field result "exception"))
        (intrinsic-gas (fixture-object-field result "intrinsicGas")))
    (when (and hash-present-p (not (blank-string-p exception)))
      (error "EEST transaction case ~A result for fork ~A cannot have both hash and exception"
             case-name
             fork))
    (when (and (not hash-present-p) (blank-string-p exception))
      (error "EEST transaction case ~A result for fork ~A needs hash or exception"
             case-name
             fork))
    (when (and (not hash-present-p) sender-present-p)
      (error "EEST transaction case ~A result for fork ~A cannot have sender without hash"
             case-name
             fork))
    (when (and (not hash-present-p) intrinsic-gas-present-p)
      (error "EEST transaction case ~A result for fork ~A cannot have intrinsicGas without hash"
             case-name
             fork))
    (when (and (not (blank-string-p exception))
               (not (transaction-fixture-known-exception-p exception)))
      (error "EEST transaction case ~A result for fork ~A has unknown exception ~A"
             case-name
             fork
             exception))
    (when (and hash-present-p (not sender-present-p))
      (error "EEST transaction case ~A result for fork ~A needs sender with hash"
             case-name
             fork))
    (when (and hash-present-p (blank-string-p intrinsic-gas))
      (error "EEST transaction case ~A result for fork ~A needs intrinsicGas with hash"
             case-name
             fork))
    (let ((normalized nil))
      (when hash-present-p
        (let ((hash (transaction-fixture-normalized-hex
                     (fixture-required-field result "hash")
                     "EEST transaction hash"))
              (sender (transaction-fixture-normalized-hex
                       (fixture-required-field result "sender")
                       "EEST transaction sender")))
          (hash32-from-hex hash)
          (address-from-hex sender)
          (push (cons "hash" hash) normalized)
          (push (cons "sender" sender) normalized)
          (push (cons "intrinsicGas"
                      (transaction-fixture-canonical-quantity
                       intrinsic-gas
                       "EEST transaction intrinsicGas"))
                normalized)))
      (unless (blank-string-p exception)
        (push (cons "exception" exception) normalized))
      (nreverse normalized))))

(defun validate-eest-transaction-result-forks (case-name result)
  (let ((seen-forks (make-hash-table :test 'equal)))
    (dolist (entry result)
      (let ((fork (car entry)))
        (when (gethash fork seen-forks)
          (error "EEST transaction case ~A has duplicate result fork ~A"
                 case-name
                 fork))
        (setf (gethash fork seen-forks) t)
        (unless (member fork +transaction-fixture-forks+ :test #'string=)
          (error "EEST transaction case ~A has unknown result fork ~A"
                 case-name
                 fork))))))

(defun normalize-eest-transaction-test-case (name case)
  (unless (listp case)
    (error "EEST transaction case ~A must be a JSON object" name))
  (validate-transaction-fixture-object-fields
   case
   +eest-transaction-test-case-fields+
   (format nil "EEST transaction case ~A" name))
  (let ((txbytes (transaction-fixture-normalized-hex
                  (fixture-required-field case "txbytes")
                  "EEST transaction txbytes"))
        (result (fixture-required-field case "result")))
    (when (zerop (length (hex-to-bytes txbytes)))
      (error "EEST transaction case ~A txbytes must encode at least one byte"
             name))
    (unless (listp result)
      (error "EEST transaction case ~A result must be a JSON object" name))
    (validate-eest-transaction-result-forks name result)
    (list
     (cons "name" name)
     (cons "txbytes" txbytes)
     (cons "result"
           (mapcar
            (lambda (entry)
              (cons (car entry)
                    (normalize-eest-transaction-result-entry
                     name
                     (car entry)
                     (cdr entry))))
            result)))))

(defun load-eest-transaction-test-file (path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST transaction test file must be a JSON object"))
    (mapcar
     (lambda (entry)
       (normalize-eest-transaction-test-case (car entry) (cdr entry)))
     (sort (copy-list cases) #'string< :key #'car))))

(defun eest-transaction-test-json-paths (root)
  (let* ((root-path (pathname root))
         (pattern
           (make-pathname
            :directory (append (pathname-directory root-path)
                               (list :wild-inferiors))
            :name :wild
            :type "json"
            :defaults root-path)))
    (sort (directory pattern) #'string< :key #'namestring)))

(defun eest-transaction-root-case-name (root path key singleton-p)
  (let ((relative (enough-namestring (truename path) (truename root))))
    (if singleton-p
        relative
        (format nil "~A/~A" relative key))))

(defun load-eest-transaction-test-root-file-cases (root path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST transaction test file must be a JSON object"))
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (normalize-eest-transaction-test-case
          (eest-transaction-root-case-name root path (car entry) singleton-p)
          (cdr entry)))
       entries))))

(defun filter-eest-transaction-test-root-cases (cases names)
  (if names
      (let ((selected nil)
            (seen (make-hash-table :test 'equal)))
        (dolist (case cases)
          (let ((name (fixture-object-field case "name")))
            (when (member name names :test #'string=)
              (push case selected)
              (setf (gethash name seen) t))))
        (dolist (name names)
          (unless (gethash name seen)
            (error "EEST transaction selector ~A did not match any loaded case"
                   name)))
        (nreverse selected))
      cases))

(defun validate-eest-transaction-selector-list (names)
  (unless names
    (error "EEST transaction selector list must not be empty"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (when (blank-string-p name)
        (error "EEST transaction selector name must be present"))
      (when (gethash name seen)
        (error "EEST transaction selector list has duplicate name ~A"
               name))
      (setf (gethash name seen) t))))

(defun load-eest-transaction-test-root-cases (root &key names)
  (when names
    (validate-eest-transaction-selector-list names))
  (let ((paths (eest-transaction-test-json-paths root)))
    (unless paths
      (error "EEST transaction test root ~A has no JSON files" root))
    (filter-eest-transaction-test-root-cases
     (loop for path in paths
           append (load-eest-transaction-test-root-file-cases root path))
     names)))

(defun eest-transaction-case-success-result (case)
  (let ((result (fixture-object-field case "result")))
    (dolist (fork +transaction-fixture-forks+)
      (let ((entry (fixture-object-field result fork)))
        (when (and entry (fixture-field-present-p entry "hash"))
          (return entry))))))

(defun validate-eest-transaction-success-results-consistent
    (case success)
  (let ((result (fixture-object-field case "result"))
        (expected-hash (fixture-required-field success "hash"))
        (expected-sender (fixture-required-field success "sender")))
    (dolist (fork +transaction-fixture-forks+)
      (let ((entry (fixture-object-field result fork)))
        (when (and entry (fixture-field-present-p entry "hash"))
          (unless (string= expected-hash
                           (fixture-required-field entry "hash"))
            (error "EEST transaction case ~A has inconsistent hash on fork ~A"
                   (fixture-object-field case "name")
                   fork))
          (unless (string= expected-sender
                           (fixture-required-field entry "sender"))
            (error "EEST transaction case ~A has inconsistent sender on fork ~A"
                   (fixture-object-field case "name")
                   fork)))))))

(defun validate-eest-transaction-success-result-derived
    (case transaction success)
  (let ((case-name (fixture-object-field case "name"))
        (result (fixture-object-field case "result"))
        (expected-gas (quantity-to-hex
                       (transaction-intrinsic-gas transaction)))
        (chain-id (transaction-vector-chain-id transaction)))
    (unless (string= (fixture-required-field success "hash")
                     (hash32-to-hex (transaction-hash transaction)))
      (error "EEST transaction case ~A success hash does not match txbytes"
             case-name))
    (let ((sender (transaction-sender transaction :expected-chain-id chain-id)))
      (unless sender
        (error "EEST transaction case ~A sender recovery failed"
               case-name))
      (unless (string= (fixture-required-field success "sender")
                       (address-to-hex sender))
        (error "EEST transaction case ~A success sender does not match txbytes"
               case-name)))
    (dolist (fork +transaction-fixture-forks+)
      (let ((entry (fixture-object-field result fork)))
        (when (and entry (fixture-field-present-p entry "hash"))
          (unless (string= expected-gas
                           (fixture-required-field entry "intrinsicGas"))
            (error "EEST transaction case ~A success intrinsicGas on fork ~A does not match txbytes"
                   case-name
                   fork)))))))

(defun eest-transaction-result-to-fixture-result (case)
  (let ((result (fixture-object-field case "result")))
    (mapcar
     (lambda (fork)
       (let ((entry (fixture-object-field result fork)))
         (unless entry
           (error "EEST transaction case ~A is missing result for fork ~A"
                  (fixture-object-field case "name")
                  fork))
         (cons fork
               (if (fixture-field-present-p entry "hash")
                   (list (cons "intrinsicGas"
                               (fixture-required-field entry "intrinsicGas")))
                   (list (cons "exception"
                               (fixture-required-field entry "exception")))))))
     +transaction-fixture-forks+)))

(defun convert-eest-transaction-case-to-vector (case)
  (let* ((name (fixture-required-field case "name"))
         (txbytes (fixture-required-field case "txbytes"))
         (transaction (transaction-from-encoding (hex-to-bytes txbytes)))
         (success (eest-transaction-case-success-result case)))
    (unless success
      (error "EEST transaction case ~A has no successful tracked fork result"
             name))
    (validate-eest-transaction-success-results-consistent case success)
    (validate-eest-transaction-success-result-derived
     case transaction success)
    (let ((vector
            (list
             (cons "name" name)
             (cons "type" (transaction-fixture-type-name
                           (transaction-vector-type transaction)))
             (cons "chainId" (transaction-vector-chain-id transaction))
             (cons "txbytes" txbytes)
             (cons "hash" (fixture-required-field success "hash"))
             (cons "sender" (fixture-required-field success "sender"))
             (cons "result"
                   (eest-transaction-result-to-fixture-result case)))))
      (validate-transaction-fixture-vector-shape vector)
      (validate-transaction-fixture-result-shape vector)
      (validate-transaction-fixture-decoded-vector vector)
      vector)))

(defun load-eest-transaction-test-root-vectors (root &key names)
  (let ((vectors
          (mapcar #'convert-eest-transaction-case-to-vector
                  (load-eest-transaction-test-root-cases root :names names))))
    (validate-transaction-fixture-vector-set vectors)
    vectors))

(defun load-phase-a-eest-transaction-test-root-vectors (root)
  (validate-eest-transaction-selector-list
   +phase-a-eest-transaction-test-case-names+)
  (let ((vectors
          (load-eest-transaction-test-root-vectors
           root
           :names +phase-a-eest-transaction-test-case-names+)))
    (validate-phase-a-eest-transaction-vector-summary vectors)
    vectors))

(defun transaction-fixture-vector-type-counts (vectors)
  (let ((counts (make-hash-table :test 'eq)))
    (dolist (vector vectors)
      (let ((type (transaction-fixture-type-keyword
                   (fixture-required-field vector "type"))))
        (setf (gethash type counts)
              (1+ (gethash type counts 0)))))
    (loop for type in +transaction-fixture-required-types+
          for count = (gethash type counts)
          when count
            collect (cons type count))))

(defun transaction-fixture-vector-summary (vectors)
  (list
   (cons "count" (length vectors))
   (cons "types" (transaction-fixture-vector-type-counts vectors))
   (cons "names" (mapcar (lambda (vector)
                           (fixture-required-field vector "name"))
                         vectors))))

(defun transaction-fixture-string-list-set-equal-p (left right)
  (and (= (length left) (length right))
       (every (lambda (value)
                (member value right :test #'string=))
              left)
       (every (lambda (value)
                (member value left :test #'string=))
              right)))

(defun validate-phase-a-eest-transaction-summary-types (types)
  (unless types
    (error "Phase A EEST transaction summary must include at least one transaction type"))
  (let ((seen-types (make-hash-table :test 'eq)))
    (dolist (entry types)
      (unless (and (consp entry)
                   (member (car entry)
                           (append +phase-a-eest-transaction-required-types+
                                   +phase-a-eest-transaction-forbidden-types+)
                           :test #'eq)
                   (integerp (cdr entry))
                   (plusp (cdr entry)))
        (error "Phase A EEST transaction summary has malformed type entry ~S"
               entry))
      (when (gethash (car entry) seen-types)
        (error "Phase A EEST transaction summary has duplicate type ~A"
               (car entry)))
      (setf (gethash (car entry) seen-types) t)))
  (dolist (type +phase-a-eest-transaction-required-types+)
    (unless (assoc type types)
      (error "Phase A EEST transaction summary is missing required type ~A"
             type)))
  (dolist (type +phase-a-eest-transaction-forbidden-types+)
    (when (assoc type types)
      (error "Phase A EEST transaction summary includes out-of-scope type ~A"
             type)))
  types)

(defun validate-phase-a-eest-transaction-target-fork-results (vectors)
  (dolist (vector vectors)
    (let* ((name (fixture-required-field vector "name"))
           (result (fixture-required-field vector "result"))
           (target-result
             (and (listp result)
                  (fixture-object-field
                   result
                   +phase-a-eest-transaction-target-fork+))))
      (unless (listp result)
        (error "Phase A EEST transaction vector ~A result must be a JSON object"
               name))
      (unless target-result
        (error "Phase A EEST transaction vector ~A is missing ~A result"
               name
               +phase-a-eest-transaction-target-fork+))
      (when (fixture-field-present-p target-result "exception")
        (error "Phase A EEST transaction vector ~A is invalid on ~A"
               name
               +phase-a-eest-transaction-target-fork+))
      (unless (fixture-field-present-p target-result "intrinsicGas")
        (error "Phase A EEST transaction vector ~A lacks ~A intrinsicGas"
               name
               +phase-a-eest-transaction-target-fork+))))
  vectors)

(defun validate-phase-a-eest-transaction-vector-summary (vectors)
  (validate-eest-transaction-selector-list
   +phase-a-eest-transaction-test-case-names+)
  (let* ((summary (transaction-fixture-vector-summary vectors))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (types (fixture-required-field summary "types")))
    (unless (= count (length +phase-a-eest-transaction-test-case-names+))
      (error "Phase A EEST transaction selector count ~A loaded ~A vectors"
             (length +phase-a-eest-transaction-test-case-names+)
             count))
    (unless (transaction-fixture-string-list-set-equal-p
             names
             +phase-a-eest-transaction-test-case-names+)
      (error "Phase A EEST transaction summary names ~S do not match selectors ~S"
             names
             +phase-a-eest-transaction-test-case-names+))
    (validate-phase-a-eest-transaction-target-fork-results vectors)
    (validate-phase-a-eest-transaction-summary-types types)
    summary))

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
    (:access-list (member fork '("Berlin" "London" "Shanghai" "Cancun"
                                 "Prague")
                          :test #'string=))
    (:dynamic-fee (member fork '("London" "Shanghai" "Cancun" "Prague")
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
    (when (blank-string-p value)
      (error "Transaction fixture ~A valid result for fork ~A needs ~A"
             (fixture-object-field vector "name")
             fork
             field))
    (unless (string= value
                     (quantity-to-hex (hex-to-quantity value)))
      (error "Transaction fixture ~A result for fork ~A has non-canonical ~A"
             (fixture-object-field vector "name")
             fork
             field))))

(defun validate-transaction-fixture-result-entry
    (vector type fork result)
  (validate-transaction-fixture-object-fields
   result
   +transaction-fixture-result-entry-fields+
   (format nil "Transaction fixture ~A result for fork ~A"
           (fixture-object-field vector "name")
           fork))
  (let ((exception-present-p (fixture-field-present-p result "exception"))
        (intrinsic-gas-present-p (fixture-field-present-p result "intrinsicGas"))
        (exception (fixture-object-field result "exception"))
        (intrinsic-gas (fixture-object-field result "intrinsicGas")))
    (when (and exception-present-p (blank-string-p exception))
      (error "Transaction fixture ~A result for fork ~A has a blank exception"
             (fixture-object-field vector "name")
             fork))
    (if (blank-string-p exception)
        (validate-transaction-fixture-quantity-field
         vector fork result "intrinsicGas")
        (progn
          (unless (transaction-fixture-known-exception-p exception)
            (error "Transaction fixture ~A result for fork ~A has unknown exception ~A"
                   (fixture-object-field vector "name")
                   fork
                   exception))
          (when intrinsic-gas-present-p
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

(defun validate-transaction-fixture-result-forks (vector result)
  (dolist (fork +transaction-fixture-forks+)
    (unless (assoc fork result :test #'string=)
      (error "Transaction fixture ~A is missing result for fork ~A"
             (fixture-object-field vector "name")
             fork)))
  (let ((seen-forks (make-hash-table :test 'equal)))
    (dolist (check result)
      (let ((fork (car check)))
        (when (gethash fork seen-forks)
          (error "Transaction fixture ~A has duplicate result fork ~A"
                 (fixture-object-field vector "name")
                 fork))
        (setf (gethash fork seen-forks) t)
        (unless (member fork +transaction-fixture-forks+ :test #'string=)
          (error "Transaction fixture ~A has unknown result fork ~A"
                 (fixture-object-field vector "name")
                 fork))))))

(defun validate-transaction-fixture-result-shape (vector)
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

(defun validate-transaction-envelope-vector-coverage (vectors)
  (validate-transaction-fixture-vector-set vectors :require-required-types t))

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
    ((string= fork "Shanghai")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :shanghai-time 0))
    ((string= fork "Cancun")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :shanghai-time 0
                        :cancun-time 0))
    ((string= fork "Prague")
     (make-chain-config :berlin-block 0
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
                       (transaction-intrinsic-gas transaction))))
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
                   expected-gas)))))))

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
    (validate-transaction-fixture-derived-results vector transaction)
    transaction))

(deftest transaction-fixture-result-shape-validation
  (let ((vector (list (cons "name" "shape-test")
                      (cons "type" "dynamic-fee"))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "missing-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (list (cons "Frontier"
                               (list (cons "exception"
                                           "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "unknown-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons "Osaka"
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "duplicate-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons "London"
                                (list (cons "intrinsicGas" "0x5208")))))))))
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
       "London"
       (list (cons "exception" "")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "intrinsicGas" "0x5208")
             (cons "gas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "intrinsicGas" "0x5208")
             (cons "intrinsicGas" "0x5209"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0x05208"))))
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
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" nil))))
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

(defun transaction-fixture-metadata-shape-test-fixture
    (&key top-extra reference-extra)
  (append
   (list
    (cons "format" +transaction-envelope-fixture-format+)
    (cons "source" "test fixture")
    (cons "executionSpecTests"
          (list (cons "release" +phase-a-eest-release+)
                (cons "tagTarget" +phase-a-eest-tag-target+)
                (cons "archive" +phase-a-eest-archive+)
                (cons "status" "test")))
    (cons "referenceClients"
          (append
           (list (cons "geth" "test-geth")
                 (cons "nethermind" "test-nethermind")
                 (cons "reth" nil))
           reference-extra))
    (cons "vectors" nil))
   top-extra))

(deftest transaction-fixture-metadata-shape-validation
  (validate-transaction-envelope-fixture-metadata
   (transaction-fixture-metadata-shape-test-fixture))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :reference-extra (list (cons "besu" "test-besu"))))))

(deftest transaction-fixture-vector-shape-validation
  (let ((valid-vector
          (list (cons "name" "shape-test")
                (cons "type" "legacy")
                (cons "chainId" 1)
                (cons "txbytes" "0x01")
                (cons "hash"
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                (cons "sender" "0x0000000000000000000000000000000000000001")
                (cons "result" nil))))
    (validate-transaction-fixture-vector-shape valid-vector))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "missing-result")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-type")
           (cons "type" "unknown")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-chain-id")
           (cons "type" "legacy")
           (cons "chainId" -1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "both-raw-and-txbytes")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "raw" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "raw-only")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "raw" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "empty-txbytes")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-hash")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash" "0x01")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-sender")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x01")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "unknown-vector-field")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil)
           (cons "unexpectedVectorField" t))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "duplicate-vector-field")
           (cons "name" "duplicate-vector-field-shadow")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil)))))

(deftest transaction-fixture-decoded-envelope-validation
  (let ((vector (list (cons "name" "decoded-shape-test")
                      (cons "type" "dynamic-fee")
                      (cons "chainId" 1))))
    (validate-transaction-fixture-decoded-envelope
     vector
     (make-dynamic-fee-transaction :chain-id 1))
    (signals error
      (validate-transaction-fixture-decoded-envelope
       vector
       (make-access-list-transaction :chain-id 1)))
    (signals error
      (validate-transaction-fixture-decoded-envelope
       vector
       (make-dynamic-fee-transaction :chain-id 2)))))

(deftest transaction-fixture-decoded-vector-validation
  (let ((vector (first (load-transaction-envelope-vectors
                       +transaction-envelope-fixture-path+))))
    (labels ((replace-field (field value)
               (cons (cons field value)
                     (remove field vector :key #'car :test #'string=))))
      (validate-transaction-fixture-decoded-vector vector)
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field
          "hash"
          "0x0000000000000000000000000000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field "sender"
                        "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field
          "result"
          (list (cons "Frontier" (list (cons "intrinsicGas" "0x5209")))
                (cons "Berlin" (list (cons "intrinsicGas" "0x5208")))
                (cons "London" (list (cons "intrinsicGas" "0x5208")))
                (cons "Shanghai" (list (cons "intrinsicGas" "0x5208")))
                (cons "Cancun" (list (cons "intrinsicGas" "0x5208")))
                (cons "Prague" (list (cons "intrinsicGas" "0x5208"))))))))))

(deftest eest-transaction-success-result-consistency-validation
  (let* ((case (first (load-eest-transaction-test-file
                       +eest-transaction-test-sample-path+)))
         (result (fixture-required-field case "result"))
         (success (eest-transaction-case-success-result case)))
    (validate-eest-transaction-success-results-consistent case success)
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-fork-entry (fork entry)
               (cons (cons fork entry)
                     (remove fork result :key #'car :test #'string=))))
      (signals error
        (let* ((london (fixture-required-field result "London"))
               (bad-london
                 (replace-field
                  london
                  "hash"
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "London" bad-london))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((london (fixture-required-field result "London"))
               (bad-london
                 (replace-field
                  london
                  "sender"
                  "0x0000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "London" bad-london))))
          (convert-eest-transaction-case-to-vector bad-case))))))

(deftest eest-transaction-success-result-derived-validation
  (let* ((case (first (load-eest-transaction-test-file
                       +eest-transaction-test-sample-path+)))
         (result (fixture-required-field case "result")))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-fork-entry (fork entry)
               (cons (cons fork entry)
                     (remove fork result :key #'car :test #'string=))))
      (convert-eest-transaction-case-to-vector case)
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "hash"
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "sender"
                  "0x0000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "intrinsicGas"
                  "0x5209"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case))))))

(deftest eest-transaction-test-file-shape-validation
  (let* ((case (first (load-eest-transaction-test-file
                       +eest-transaction-test-sample-path+)))
         (result (fixture-object-field case "result"))
         (shanghai (fixture-object-field result "Shanghai"))
         (vector (convert-eest-transaction-case-to-vector case)))
    (is (string= "legacy-eip155-sample"
                 (fixture-object-field case "name")))
    (is (string= "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
                 (fixture-object-field case "txbytes")))
    (is (string= "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
                 (fixture-object-field shanghai "hash")))
    (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
                 (fixture-object-field shanghai "sender")))
    (is (string= "0x5208"
                 (fixture-object-field shanghai "intrinsicGas")))
    (is (string= "legacy"
                 (fixture-object-field vector "type")))
    (is (= 1 (fixture-object-field vector "chainId")))
    (is (string= "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
                 (fixture-object-field vector "hash")))
    (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
                 (fixture-object-field vector "sender"))))
  (signals error
    (normalize-eest-transaction-test-case
     "missing-result"
     (list (cons "txbytes" "0x01"))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-case-field"
     (list (cons "txbytes" "0x01")
           (cons "result" nil)
           (cons "unexpected" t))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Osaka"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.UNKNOWN"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "duplicate-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")))
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "missing-success-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208")))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-with-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208")
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-prefixless-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-leading-zero-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x05208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "exception-with-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "exception-with-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (convert-eest-transaction-case-to-vector
     (list
      (cons "name" "missing-tracked-fork")
      (cons "txbytes"
            "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")
      (cons "result"
            (list
             (cons "Shanghai"
                   (list (cons "hash"
                               "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788")
                         (cons "sender"
                               "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
                         (cons "intrinsicGas" "0x5208"))))))))

(deftest eest-transaction-test-root-vector-loading
  (let* ((root (execution-spec-tests-transaction-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-transaction-test-json-paths root))
         (cases (load-eest-transaction-test-root-cases root))
         (selected-cases
           (load-eest-transaction-test-root-cases
            root
            :names +phase-a-eest-transaction-test-case-names+))
         (vectors (load-eest-transaction-test-root-vectors root))
         (selected-vectors
           (load-phase-a-eest-transaction-test-root-vectors root))
         (vector (first vectors))
         (typed-vector
           (find "phase-a-sample.json/typed-eip2930-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-vector
           (find "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (summary (transaction-fixture-vector-summary selected-vectors)))
    (is (= 1 (length paths)))
    (is (= 3 (length cases)))
    (is (= 3 (length selected-cases)))
    (is (= 3 (length vectors)))
    (is (= 3 (length selected-vectors)))
    (is (string= "phase-a-sample.json/legacy-eip155-sample"
                 (fixture-object-field (first cases) "name")))
    (is (string= "phase-a-sample.json/legacy-eip155-sample"
                 (fixture-object-field vector "name")))
    (is (string= "legacy"
                 (fixture-object-field vector "type")))
    (is typed-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-vector "type")))
    (is dynamic-fee-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-vector "type")))
    (is (= 3 (fixture-object-field summary "count")))
    (is (equal '((:legacy . 1) (:access-list . 1) (:dynamic-fee . 1))
               (fixture-object-field summary "types")))
    (is (equal '("phase-a-sample.json/legacy-eip155-sample"
                 "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
                 "phase-a-sample.json/typed-eip2930-access-list-sample")
               (fixture-object-field summary "names")))
    (is (equal summary
               (validate-phase-a-eest-transaction-vector-summary
                selected-vectors)))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       (remove dynamic-fee-vector selected-vectors)))
    (signals error
      (validate-phase-a-eest-transaction-target-fork-results
       (list
        (list
         (cons "name" "phase-a-invalid-on-target")
         (cons "result"
               (list
                (cons +phase-a-eest-transaction-target-fork+
                      (list
                       (cons "exception"
                             "TransactionException.TYPE_2_TX_PRE_FORK")))))))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:blob . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:set-code . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1)
         (:unknown . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:legacy . 1)
         (:access-list . 1)
         (:dynamic-fee . 1))))
    (signals error
      (validate-phase-a-eest-transaction-summary-types
       '((:legacy . 1)
         (:access-list . 0)
         (:dynamic-fee . 1))))
    (is (string= "phase-a-sample.json/alpha"
                 (eest-transaction-root-case-name root
                                                  (first paths)
                                                  "alpha"
                                                  nil)))
    (signals error
      (validate-transaction-fixture-vector-set
       (append vectors (list vector))))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("missing.json")))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("")))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("phase-a-sample.json" "phase-a-sample.json")))
    (validate-eest-transaction-selector-list
     +phase-a-eest-transaction-test-case-names+)
    (signals error
      (validate-eest-transaction-selector-list nil))
    (signals error
      (validate-eest-transaction-selector-list '("")))
    (signals error
      (validate-eest-transaction-selector-list
       '("phase-a-sample.json" "phase-a-sample.json"))))
  (signals error
    (validate-phase-a-eest-transaction-vector-summary nil))
  (signals error
    (load-eest-transaction-test-root-cases
     "tests/fixtures/geth-spec-tests-root/spec-tests/fixtures/transaction_tests/")))

(deftest optional-eest-transaction-test-root-vectors
  (with-execution-spec-tests-transaction-test-root (root)
    (let* ((vectors (load-phase-a-eest-transaction-test-root-vectors root))
           (summary (transaction-fixture-vector-summary vectors)))
      (is (< 0 (fixture-object-field summary "count")))
      (is (< 0 (length (fixture-object-field summary "types")))))))

(deftest transaction-envelope-fixture-vectors
  (dolist (vector (load-transaction-envelope-vectors
                   +transaction-envelope-fixture-path+))
    (let* ((raw (transaction-fixture-txbytes vector))
           (chain-id (fixture-object-field vector "chainId"))
           (transaction (transaction-from-encoding (hex-to-bytes raw)))
           (sender (transaction-sender transaction :expected-chain-id chain-id)))
      (validate-transaction-fixture-decoded-envelope vector transaction)
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
