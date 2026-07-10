(in-package #:ethereum-lisp.test)

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
        (exception-present-p (fixture-field-present-p result "exception"))
        (exception (fixture-object-field result "exception"))
        (intrinsic-gas (fixture-object-field result "intrinsicGas")))
    (when (and exception-present-p
               (not (or (null exception) (stringp exception))))
      (error "EEST transaction case ~A result for fork ~A exception must be a string"
             case-name
             fork))
    (when (and intrinsic-gas-present-p
               (not (stringp intrinsic-gas)))
      (error "EEST transaction case ~A result for fork ~A intrinsicGas must be a string"
             case-name
             fork))
    (when (and exception-present-p (blank-string-p exception))
      (error "EEST transaction case ~A result for fork ~A has a blank exception"
             case-name
             fork))
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
    (when (and (not hash-present-p)
               intrinsic-gas-present-p
               (blank-string-p exception))
      (error "EEST transaction case ~A result for fork ~A cannot have intrinsicGas without hash or exception"
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
        (let ((hash (transaction-fixture-canonical-hash32
                     (transaction-fixture-normalized-hex
                      (fixture-required-field result "hash")
                      "EEST transaction hash")
                     "EEST transaction hash"))
              (sender (transaction-fixture-canonical-address
                       (transaction-fixture-normalized-hex
                        (fixture-required-field result "sender")
                        "EEST transaction sender")
                       "EEST transaction sender")))
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
  (unless result
    (error "EEST transaction case ~A result must include at least one fork"
           case-name))
  (let ((seen-forks (make-hash-table :test 'equal)))
    (dolist (entry result)
      (unless (consp entry)
        (error "EEST transaction case ~A result entries must be JSON object fields"
               case-name))
      (let ((fork (car entry)))
        (unless (stringp fork)
          (error "EEST transaction case ~A result fork must be a string"
                 case-name))
        (when (blank-string-p fork)
          (error "EEST transaction case ~A result fork must be present"
                 case-name))
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
  (unless (stringp name)
    (error "EEST transaction case name must be a string"))
  (when (blank-string-p name)
    (error "EEST transaction case name must be present"))
  (unless (listp case)
    (error "EEST transaction case ~A must be a JSON object" name))
  (validate-transaction-fixture-object-fields
   case
   +eest-transaction-test-case-fields+
   (format nil "EEST transaction case ~A" name))
  (let ((txbytes (transaction-fixture-canonical-bytes
                  (transaction-fixture-normalized-hex
                   (fixture-required-field case "txbytes")
                   "EEST transaction txbytes")
                  "EEST transaction txbytes"))
        (result (fixture-required-field case "result")))
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

(defun validate-eest-transaction-test-file-entries (entries path-label)
  (unless entries
    (error "EEST transaction test file ~A must include at least one case"
           path-label))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (unless (consp entry)
        (error "EEST transaction test file ~A entries must be JSON object fields"
               path-label))
      (let ((name (car entry)))
        (unless (stringp name)
          (error "EEST transaction test file ~A case name must be a string"
                 path-label))
        (when (blank-string-p name)
          (error "EEST transaction test file ~A case name must be present"
                 path-label))
        (when (gethash name seen)
          (error "EEST transaction test file ~A has duplicate case name ~A"
                 path-label
                 name))
        (setf (gethash name seen) t)))))

(defun load-eest-transaction-test-file (path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST transaction test file must be a JSON object"))
    (validate-eest-transaction-test-file-entries cases path)
    (mapcar
     (lambda (entry)
       (normalize-eest-transaction-test-case (car entry) (cdr entry)))
     (sort (copy-list cases) #'string< :key #'car))))

(defun eest-transaction-test-json-paths (root)
  (execution-spec-tests-json-paths root))

(defun eest-transaction-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun load-eest-transaction-test-root-file-cases (root path)
  (let ((cases (load-handwritten-fixture-file path)))
    (unless (listp cases)
      (error "EEST transaction test file must be a JSON object"))
    (validate-eest-transaction-test-file-entries
     cases
     (enough-namestring (truename path) (truename root)))
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-transaction-root-case-name
                  root
                  path
                  (car entry)
                  singleton-p)))
           (unless (eest-transaction-selector-source-style-p source-name)
             (error "EEST transaction source name ~A must be source-style"
                    source-name))
           (normalize-eest-transaction-test-case source-name (cdr entry))))
       entries))))

(defun filter-eest-transaction-test-root-cases (cases names)
  (when names
    (validate-eest-transaction-selector-list names))
  (let ((case-index (make-hash-table :test 'equal)))
    (dolist (case cases)
      (let ((name (fixture-required-field case "name")))
        (when (gethash name case-index)
          (error "EEST transaction test root has duplicate case name ~A"
                 name))
        (setf (gethash name case-index) case)))
    (if names
        (mapcar
         (lambda (name)
           (or (gethash name case-index)
               (error "EEST transaction selector ~A did not match any loaded case"
                      name)))
         names)
        cases)))

(defun validate-eest-transaction-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST transaction"
   :allow-nested-case-name t))

(defun eest-transaction-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun phase-a-eest-transaction-test-selector-string
    (&optional (names +phase-a-eest-transaction-test-case-names+))
  (validate-eest-transaction-selector-list names)
  (with-output-to-string (stream)
    (loop for name in names
          for first-p = t then nil
          do (progn
               (unless first-p
                 (write-char #\, stream))
               (write-string name stream)))))

(defun load-eest-transaction-test-root-cases (root &key names)
  (when names
    (validate-eest-transaction-selector-list names))
  (let ((paths (execution-spec-tests-root-json-paths
                root
                "EEST transaction test")))
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

(defun eest-transaction-synthesized-result-entry
    (transaction success fork)
  (let ((type (transaction-vector-type transaction)))
    (if (transaction-fixture-type-valid-on-fork-p type fork)
        (list (cons "hash" (fixture-required-field success "hash"))
              (cons "sender" (fixture-required-field success "sender"))
              (cons "intrinsicGas"
                    (quantity-to-hex
                     (transaction-intrinsic-gas transaction))))
        (list (cons "exception"
                    (transaction-fixture-expected-pre-fork-exception type))))))

(defun eest-transaction-result-to-fixture-result
    (case transaction success)
  (let ((result (fixture-object-field case "result")))
    (mapcar
     (lambda (fork)
       (let ((entry (fixture-object-field result fork)))
         (cons fork
               (if (null entry)
                   (eest-transaction-synthesized-result-entry
                    transaction
                    success
                    fork)
                   (if (fixture-field-present-p entry "hash")
                       (list (cons "hash"
                                   (fixture-required-field entry "hash"))
                             (cons "sender"
                                   (fixture-required-field entry "sender"))
                             (cons "intrinsicGas"
                                   (fixture-required-field entry "intrinsicGas")))
                       (list (cons "exception"
                                   (fixture-required-field entry "exception"))))))))
     +transaction-fixture-forks+)))

(defun convert-eest-transaction-case-to-vector (case)
  (let* ((name (fixture-required-field case "name"))
         (txbytes (fixture-required-field case "txbytes"))
         (transaction (transaction-from-encoding (hex-to-bytes txbytes)))
         (success (eest-transaction-case-success-result case))
         (sender (and success
                      (address-from-hex
                       (fixture-required-field success "sender")))))
    (unless success
      (error "EEST transaction case ~A has no successful tracked fork result"
             name))
    (validate-eest-transaction-success-results-consistent case success)
    (validate-eest-transaction-success-result-derived
     case transaction success)
    (let ((vector
            (append
             (list
              (cons "name" name)
              (cons "type" (transaction-fixture-type-name
                            (transaction-vector-type transaction)))
              (cons "chainId" (transaction-vector-chain-id transaction))
              (cons "txbytes" txbytes)
              (cons "hash" (fixture-required-field success "hash"))
              (cons "sender" (fixture-required-field success "sender"))
              (cons "signature"
                    (transaction-fixture-signature-object transaction))
              (cons "decoded" (transaction-fixture-decoded-object transaction))
              (cons "result"
                    (eest-transaction-result-to-fixture-result
                     case
                     transaction
                     success)))
             (let ((contract-address
                     (transaction-fixture-created-contract-address
                      transaction
                      sender)))
               (when contract-address
                 (list
                  (cons "contractAddress"
                        (address-to-hex contract-address)))))
             (when (transaction-access-list transaction)
               (list
                (cons "accessList"
                      (transaction-fixture-access-list-object
                       (transaction-access-list transaction))))))))
      (validate-transaction-fixture-vector-shape vector)
      (validate-transaction-fixture-result-shape vector)
      (validate-transaction-fixture-decoded-vector vector)
      vector)))

(defun eest-transaction-success-cases (cases)
  (remove-if-not #'eest-transaction-case-success-result cases))

(defun eest-transaction-invalid-cases (cases)
  (remove-if #'eest-transaction-case-success-result cases))

(defun load-eest-transaction-test-root-invalid-cases (root &key names)
  (eest-transaction-invalid-cases
   (load-eest-transaction-test-root-cases root :names names)))

(defun load-eest-transaction-test-root-vectors (root &key names)
  (let ((vectors
          (mapcar #'convert-eest-transaction-case-to-vector
                  (eest-transaction-success-cases
                   (load-eest-transaction-test-root-cases root :names names)))))
    (validate-transaction-fixture-vector-set vectors)
    vectors))

(defun eest-transaction-case-source-file-name (case)
  (let* ((name (fixture-required-field case "name"))
         (json-end (search ".json" name)))
    (unless json-end
      (error "EEST transaction case ~A does not include a JSON source file"
             name))
    (subseq name 0 (+ json-end (length ".json")))))

(defun eest-invalid-transaction-case-exception (case)
  (let* ((result (fixture-required-field case "result"))
         (prague-result (fixture-required-field result "Prague")))
    (fixture-required-field prague-result "exception")))

(defun load-phase-a-eest-transaction-test-root-vectors (root)
  (validate-eest-transaction-selector-list
   +phase-a-eest-transaction-test-case-names+)
  (let ((vectors
          (load-eest-transaction-test-root-vectors
           root
           :names +phase-a-eest-transaction-test-case-names+)))
    (validate-phase-a-eest-transaction-vector-summary vectors)
    vectors))

(defun load-full-eest-transaction-test-root-vectors (root)
  (validate-eest-transaction-selector-list
   +full-eest-transaction-test-case-names+)
  (let ((vectors
          (load-eest-transaction-test-root-vectors
           root
           :names +full-eest-transaction-test-case-names+)))
    (validate-full-eest-transaction-vector-summary vectors)
    vectors))

(defun eest-invalid-transaction-local-rejection-stage (case)
  (handler-case
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (fixture-required-field case "txbytes")))))
        (handler-case
            (progn
              (ethereum-lisp.execution::validate-set-code-transaction-fields
               transaction)
              (handler-case
                  (progn
                    (ethereum-lisp.public-api::eth-rpc-validate-set-code-authorization-signatures
                     transaction)
                    "accepted")
                (error () "signature")))
          (error () "field")))
    (error () "decode")))
