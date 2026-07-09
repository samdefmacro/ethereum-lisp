(in-package #:ethereum-lisp.test)


(defun increment-string-count (table key)
  (setf (gethash key table)
        (1+ (gethash key table 0))))

(defun sorted-string-counts (table)
  (sort
   (loop for key being the hash-keys of table
         using (hash-value count)
         collect (cons key count))
   #'string<
   :key #'car))

(defun validate-eest-invalid-transaction-rejection-stage-entry
    (entry label)
  (validate-transaction-fixture-object-fields
   entry
   +eest-invalid-transaction-rejection-stage-fields+
   label)
  (dolist (field +eest-invalid-transaction-rejection-stage-fields+)
    (unless (fixture-field-present-p entry field)
      (error "~A is missing ~A" label field)))
  (validate-transaction-fixture-required-string-field
   entry "exception" (format nil "~A exception" label))
  (dolist (field '("decodeErrorCount" "fieldValidationErrorCount"
                   "signatureValidationErrorCount" "acceptedCount"))
    (let ((value (fixture-required-field entry field)))
      (unless (and (integerp value) (not (minusp value)))
        (error "~A ~A must be a non-negative integer" label field)))))

(defun validate-eest-invalid-transaction-source-file-stage-entry
    (entry label)
  (validate-transaction-fixture-object-fields
   entry
   +eest-invalid-transaction-source-file-stage-fields+
   label)
  (dolist (field +eest-invalid-transaction-source-file-stage-fields+)
    (unless (fixture-field-present-p entry field)
      (error "~A is missing ~A" label field)))
  (validate-transaction-fixture-required-string-field
   entry "sourceFile" (format nil "~A sourceFile" label))
  (dolist (field '("decodeErrorCount" "fieldValidationErrorCount"
                   "signatureValidationErrorCount" "acceptedCount"))
    (let ((value (fixture-required-field entry field)))
      (unless (and (integerp value) (not (minusp value)))
        (error "~A ~A must be a non-negative integer" label field)))))

(defun eest-invalid-transaction-stage-count-entry
    (key field-name counts)
  (list
   (cons field-name key)
   (cons "decodeErrorCount" (gethash "decode" counts 0))
   (cons "fieldValidationErrorCount" (gethash "field" counts 0))
   (cons "signatureValidationErrorCount" (gethash "signature" counts 0))
   (cons "acceptedCount" (gethash "accepted" counts 0))))

(defun eest-invalid-transaction-exception-stage-entry
    (exception counts)
  (let ((entry
          (eest-invalid-transaction-stage-count-entry
           exception
           "exception"
           counts)))
    (validate-eest-invalid-transaction-rejection-stage-entry
     entry
     "EEST invalid transaction rejection stage summary")
    entry))

(defun eest-invalid-transaction-source-file-stage-entry
    (source-file counts)
  (let ((entry
          (eest-invalid-transaction-stage-count-entry
           source-file
           "sourceFile"
           counts)))
    (validate-eest-invalid-transaction-source-file-stage-entry
     entry
     "EEST invalid transaction source-file rejection stage summary")
    entry))

(defun eest-invalid-transaction-exception-stage-counts (table)
  (sort
   (loop for exception being the hash-keys of table
         using (hash-value counts)
         collect
         (eest-invalid-transaction-exception-stage-entry
          exception counts))
   #'string<
   :key (lambda (entry)
          (fixture-required-field entry "exception"))))

(defun eest-invalid-transaction-source-file-stage-counts (table)
  (sort
   (loop for source-file being the hash-keys of table
         using (hash-value counts)
         collect
         (eest-invalid-transaction-source-file-stage-entry
          source-file counts))
   #'string<
   :key (lambda (entry)
          (fixture-required-field entry "sourceFile"))))

(defun eest-invalid-transaction-rejection-summary (cases)
  (let ((decode-error-count 0)
        (field-validation-error-count 0)
        (signature-validation-error-count 0)
        (source-file-counts (make-hash-table :test 'equal))
        (exception-counts (make-hash-table :test 'equal))
        (source-file-stage-counts (make-hash-table :test 'equal))
        (exception-stage-counts (make-hash-table :test 'equal))
        (accepted-names '()))
    (dolist (case cases)
      (let* ((exception (eest-invalid-transaction-case-exception case))
             (source-file (eest-transaction-case-source-file-name case))
             (stage (eest-invalid-transaction-local-rejection-stage case))
             (stage-counts
               (or (gethash exception exception-stage-counts)
                   (setf (gethash exception exception-stage-counts)
                         (make-hash-table :test 'equal))))
             (source-stage-counts
               (or (gethash source-file source-file-stage-counts)
                   (setf (gethash source-file source-file-stage-counts)
                         (make-hash-table :test 'equal)))))
        (increment-string-count source-file-counts source-file)
        (increment-string-count exception-counts exception)
        (increment-string-count stage-counts stage)
        (increment-string-count source-stage-counts stage)
        (cond
          ((string= stage "decode")
           (incf decode-error-count))
          ((string= stage "field")
           (incf field-validation-error-count))
          ((string= stage "signature")
           (incf signature-validation-error-count))
          ((string= stage "accepted")
           (push (fixture-required-field case "name") accepted-names))
          (t (error "Unknown invalid transaction rejection stage: ~A" stage)))))
    (list
     (cons "decodeErrorCount" decode-error-count)
     (cons "fieldValidationErrorCount" field-validation-error-count)
     (cons "signatureValidationErrorCount" signature-validation-error-count)
     (cons "sourceFileCounts" (sorted-string-counts source-file-counts))
     (cons "exceptionCounts" (sorted-string-counts exception-counts))
     (cons "sourceFileStageCounts"
           (eest-invalid-transaction-source-file-stage-counts
            source-file-stage-counts))
     (cons "exceptionStageCounts"
           (eest-invalid-transaction-exception-stage-counts
            exception-stage-counts))
     (cons "acceptedNames" (nreverse accepted-names)))))

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

(defun transaction-fixture-fork-counts-alist (counts)
  (loop for fork in +transaction-fixture-forks+
        for count = (gethash fork counts 0)
        when (plusp count)
          collect (cons fork count)))

(defun transaction-fixture-result-count-summary (vectors)
  (let ((valid-count 0)
        (exception-count 0)
        (valid-fork-counts (make-hash-table :test 'equal))
        (exception-fork-counts (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (dolist (check (fixture-required-field vector "result"))
        (let ((fork (car check))
              (entry (cdr check)))
          (if (transaction-fixture-result-valid-p entry)
              (progn
                (incf valid-count)
                (incf (gethash fork valid-fork-counts 0)))
              (progn
                (incf exception-count)
                (incf (gethash fork exception-fork-counts 0)))))))
    (list
     (cons "validResultCount" valid-count)
     (cons "exceptionResultCount" exception-count)
     (cons "validForkCounts"
           (transaction-fixture-fork-counts-alist valid-fork-counts))
     (cons "exceptionForkCounts"
           (transaction-fixture-fork-counts-alist exception-fork-counts)))))

(defun access-list-duplicate-address-p (access-list)
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry access-list nil)
      (let ((address (address-to-hex (access-list-entry-address entry))))
        (when (gethash address seen)
          (return t))
        (setf (gethash address seen) t)))))

(defun transaction-fixture-access-list-summary (vectors)
  (let ((vector-count 0)
        (dynamic-fee-vector-count 0)
        (duplicate-vector-count 0)
        (dynamic-fee-duplicate-vector-count 0)
        (typed-empty-vector-count 0)
        (access-list-empty-vector-count 0)
        (dynamic-fee-empty-vector-count 0)
        (address-only-vector-count 0)
        (dynamic-fee-address-only-vector-count 0)
        (address-count 0)
        (storage-key-count 0))
    (dolist (vector vectors)
      (let* ((transaction
               (transaction-from-encoding
                (hex-to-bytes (transaction-fixture-txbytes-value vector))))
             (access-list (transaction-access-list transaction)))
        (when access-list
          (incf vector-count)
          (when (typep transaction 'dynamic-fee-transaction)
            (incf dynamic-fee-vector-count))
          (when (access-list-duplicate-address-p access-list)
            (incf duplicate-vector-count)
            (when (typep transaction 'dynamic-fee-transaction)
              (incf dynamic-fee-duplicate-vector-count)))
          (incf address-count (length access-list))
          (incf storage-key-count
                (access-list-storage-key-count access-list))
          (when (zerop (access-list-storage-key-count access-list))
            (incf address-only-vector-count)
            (when (typep transaction 'dynamic-fee-transaction)
              (incf dynamic-fee-address-only-vector-count))))
        (when (and (not (typep transaction 'legacy-transaction))
                   (null access-list))
          (incf typed-empty-vector-count)
          (when (typep transaction 'access-list-transaction)
            (incf access-list-empty-vector-count))
          (when (typep transaction 'dynamic-fee-transaction)
            (incf dynamic-fee-empty-vector-count)))))
    (list
     (cons "accessListVectorCount" vector-count)
     (cons "dynamicFeeAccessListVectorCount" dynamic-fee-vector-count)
     (cons "duplicateAccessListVectorCount" duplicate-vector-count)
     (cons "dynamicFeeDuplicateAccessListVectorCount"
           dynamic-fee-duplicate-vector-count)
     (cons "typedEmptyAccessListVectorCount" typed-empty-vector-count)
     (cons "accessListEmptyAccessListVectorCount"
           access-list-empty-vector-count)
     (cons "dynamicFeeEmptyAccessListVectorCount"
           dynamic-fee-empty-vector-count)
     (cons "accessListAddressOnlyVectorCount" address-only-vector-count)
     (cons "dynamicFeeAddressOnlyAccessListVectorCount"
           dynamic-fee-address-only-vector-count)
     (cons "accessListAddressCount" address-count)
     (cons "accessListStorageKeyCount" storage-key-count))))

(defun transaction-fixture-contract-creation-summary (vectors)
  (let ((contract-creation-count 0)
        (access-list-contract-creation-count 0)
        (dynamic-fee-contract-creation-count 0)
        (dynamic-fee-access-list-contract-creation-count 0)
        (empty-access-list-contract-creation-count 0)
        (access-list-empty-access-list-contract-creation-count 0)
        (dynamic-fee-empty-access-list-contract-creation-count 0)
        (contract-address-count 0))
    (dolist (vector vectors)
      (let* ((transaction
               (transaction-from-encoding
                (hex-to-bytes (transaction-fixture-txbytes-value vector))))
             (access-list (transaction-access-list transaction)))
        (when (null (transaction-to transaction))
          (incf contract-creation-count)
          (when (fixture-field-present-p vector "contractAddress")
            (incf contract-address-count))
          (when access-list
            (incf access-list-contract-creation-count))
          (when (and (not (typep transaction 'legacy-transaction))
                     (null access-list))
            (incf empty-access-list-contract-creation-count)
            (when (typep transaction 'access-list-transaction)
              (incf access-list-empty-access-list-contract-creation-count))
            (when (typep transaction 'dynamic-fee-transaction)
              (incf dynamic-fee-empty-access-list-contract-creation-count)))
          (when (typep transaction 'dynamic-fee-transaction)
            (incf dynamic-fee-contract-creation-count)
            (when access-list
              (incf dynamic-fee-access-list-contract-creation-count))))))
    (list
     (cons "contractCreationVectorCount" contract-creation-count)
     (cons "contractCreationAddressVectorCount" contract-address-count)
     (cons "accessListContractCreationVectorCount"
           access-list-contract-creation-count)
     (cons "dynamicFeeContractCreationVectorCount"
           dynamic-fee-contract-creation-count)
     (cons "dynamicFeeAccessListContractCreationVectorCount"
           dynamic-fee-access-list-contract-creation-count)
     (cons "emptyAccessListContractCreationVectorCount"
           empty-access-list-contract-creation-count)
     (cons "accessListEmptyAccessListContractCreationVectorCount"
           access-list-empty-access-list-contract-creation-count)
     (cons "dynamicFeeEmptyAccessListContractCreationVectorCount"
           dynamic-fee-empty-access-list-contract-creation-count))))

(defun transaction-fixture-input-summary (vectors)
  (let ((message-call-data-count 0)
        (legacy-message-call-data-count 0)
        (typed-message-call-data-count 0)
        (access-list-message-call-data-count 0)
        (dynamic-fee-message-call-data-count 0)
        (access-list-with-call-data-count 0)
        (dynamic-fee-access-list-with-call-data-count 0)
        (empty-access-list-with-call-data-count 0)
        (access-list-empty-access-list-with-call-data-count 0)
        (dynamic-fee-empty-access-list-with-call-data-count 0))
    (dolist (vector vectors)
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (transaction-fixture-txbytes-value vector)))))
        (when (and (transaction-to transaction)
                   (plusp (length (transaction-data transaction))))
          (incf message-call-data-count)
          (if (typep transaction 'legacy-transaction)
              (incf legacy-message-call-data-count)
              (incf typed-message-call-data-count))
          (when (typep transaction 'access-list-transaction)
            (incf access-list-message-call-data-count))
          (when (typep transaction 'dynamic-fee-transaction)
            (incf dynamic-fee-message-call-data-count))
          (when (transaction-access-list transaction)
            (incf access-list-with-call-data-count)
            (when (typep transaction 'dynamic-fee-transaction)
              (incf dynamic-fee-access-list-with-call-data-count)))
          (when (and (not (typep transaction 'legacy-transaction))
                     (null (transaction-access-list transaction)))
            (incf empty-access-list-with-call-data-count)
            (when (typep transaction 'access-list-transaction)
              (incf access-list-empty-access-list-with-call-data-count))
            (when (typep transaction 'dynamic-fee-transaction)
              (incf dynamic-fee-empty-access-list-with-call-data-count))))))
    (list
     (cons "messageCallDataVectorCount" message-call-data-count)
     (cons "legacyMessageCallDataVectorCount"
           legacy-message-call-data-count)
     (cons "typedMessageCallDataVectorCount"
           typed-message-call-data-count)
     (cons "accessListMessageCallDataVectorCount"
           access-list-message-call-data-count)
     (cons "dynamicFeeMessageCallDataVectorCount"
           dynamic-fee-message-call-data-count)
     (cons "accessListWithCallDataVectorCount"
           access-list-with-call-data-count)
     (cons "dynamicFeeAccessListWithCallDataVectorCount"
           dynamic-fee-access-list-with-call-data-count)
     (cons "emptyAccessListWithCallDataVectorCount"
           empty-access-list-with-call-data-count)
     (cons "accessListEmptyAccessListWithCallDataVectorCount"
           access-list-empty-access-list-with-call-data-count)
     (cons "dynamicFeeEmptyAccessListWithCallDataVectorCount"
           dynamic-fee-empty-access-list-with-call-data-count))))

(defun transaction-fixture-dynamic-fee-summary (vectors)
  (let ((equal-fee-cap-count 0))
    (dolist (vector vectors)
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (transaction-fixture-txbytes-value vector)))))
        (when (and (typep transaction 'dynamic-fee-transaction)
                   (= (dynamic-fee-transaction-max-priority-fee-per-gas
                       transaction)
                      (dynamic-fee-transaction-max-fee-per-gas
                       transaction)))
          (incf equal-fee-cap-count))))
    (list
     (cons "dynamicFeeEqualFeeCapVectorCount" equal-fee-cap-count))))

(defun transaction-fixture-blob-summary (vectors)
  (let ((blob-vector-count 0)
        (blob-versioned-hash-count 0)
        (blob-access-list-vector-count 0)
        (blob-message-call-data-vector-count 0)
        (blob-access-list-message-call-data-vector-count 0))
    (dolist (vector vectors)
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (transaction-fixture-txbytes-value vector)))))
        (when (typep transaction 'blob-transaction)
          (let ((hashes (blob-transaction-blob-versioned-hashes transaction)))
            (when hashes
              (incf blob-vector-count)
              (incf blob-versioned-hash-count (length hashes))))
          (when (transaction-access-list transaction)
            (incf blob-access-list-vector-count))
          (when (and (transaction-to transaction)
                     (plusp (length (transaction-data transaction))))
            (incf blob-message-call-data-vector-count)
            (when (transaction-access-list transaction)
              (incf blob-access-list-message-call-data-vector-count))))))
    (list
     (cons "blobVersionedHashVectorCount" blob-vector-count)
     (cons "blobVersionedHashCount" blob-versioned-hash-count)
     (cons "blobAccessListVectorCount" blob-access-list-vector-count)
     (cons "blobMessageCallDataVectorCount" blob-message-call-data-vector-count)
     (cons "blobAccessListMessageCallDataVectorCount"
           blob-access-list-message-call-data-vector-count))))

(defun transaction-fixture-set-code-summary (vectors)
  (let ((set-code-vector-count 0)
        (authorization-count 0)
        (set-code-access-list-vector-count 0)
        (set-code-message-call-data-vector-count 0)
        (set-code-access-list-message-call-data-vector-count 0))
    (dolist (vector vectors)
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (transaction-fixture-txbytes-value vector)))))
        (when (typep transaction 'set-code-transaction)
          (let ((authorizations
                  (set-code-transaction-authorization-list transaction)))
            (when authorizations
              (incf set-code-vector-count)
              (incf authorization-count (length authorizations))))
          (when (transaction-access-list transaction)
            (incf set-code-access-list-vector-count))
          (when (and (transaction-to transaction)
                     (plusp (length (transaction-data transaction))))
            (incf set-code-message-call-data-vector-count)
            (when (transaction-access-list transaction)
              (incf set-code-access-list-message-call-data-vector-count))))))
    (list
     (cons "setCodeAuthorizationVectorCount" set-code-vector-count)
     (cons "setCodeAuthorizationCount" authorization-count)
     (cons "setCodeAccessListVectorCount" set-code-access-list-vector-count)
     (cons "setCodeMessageCallDataVectorCount"
           set-code-message-call-data-vector-count)
     (cons "setCodeAccessListMessageCallDataVectorCount"
           set-code-access-list-message-call-data-vector-count))))

(defun transaction-fixture-legacy-protection-summary (vectors)
  (let ((protected-count 0)
        (unprotected-count 0))
    (dolist (vector vectors)
      (let ((transaction
              (transaction-from-encoding
               (hex-to-bytes (transaction-fixture-txbytes-value vector)))))
        (when (typep transaction 'legacy-transaction)
          (if (legacy-transaction-protected-p transaction)
              (incf protected-count)
              (incf unprotected-count)))))
    (list
     (cons "protectedLegacyVectorCount" protected-count)
     (cons "unprotectedLegacyVectorCount" unprotected-count))))

(defun transaction-fixture-decoded-summary (vectors)
  (list
   (cons "decodedVectorCount"
         (loop for vector in vectors
               count (fixture-field-present-p vector "decoded")))))

(defun transaction-fixture-signature-summary (vectors)
  (list
   (cons "signatureVectorCount"
         (loop for vector in vectors
               count (fixture-field-present-p vector "signature")))))

(defun validate-transaction-fixture-access-list-coverage (summary label)
  (dolist (field '("accessListVectorCount"
                   "dynamicFeeAccessListVectorCount"
                   "duplicateAccessListVectorCount"
                   "dynamicFeeDuplicateAccessListVectorCount"
                   "typedEmptyAccessListVectorCount"
                   "accessListEmptyAccessListVectorCount"
                   "dynamicFeeEmptyAccessListVectorCount"
                   "accessListAddressOnlyVectorCount"
                   "dynamicFeeAddressOnlyAccessListVectorCount"
                   "accessListAddressCount"
                   "accessListStorageKeyCount"))
    (let ((value (fixture-required-field summary field)))
      (unless (and (integerp value) (not (minusp value)))
        (error "~A summary field ~A must be a non-negative integer"
               label field))))
  (when (zerop (fixture-required-field summary "accessListVectorCount"))
    (error "~A summary is missing a non-empty access-list transaction" label))
  (when (zerop (fixture-required-field summary "dynamicFeeAccessListVectorCount"))
    (error "~A summary is missing a dynamic-fee access-list transaction" label))
  (when (zerop (fixture-required-field summary "duplicateAccessListVectorCount"))
    (error "~A summary is missing duplicate access-list coverage" label))
  (when (zerop (fixture-required-field
                summary
                "dynamicFeeDuplicateAccessListVectorCount"))
    (error "~A summary is missing dynamic-fee duplicate access-list coverage"
           label))
  (when (zerop (fixture-required-field summary "typedEmptyAccessListVectorCount"))
    (error "~A summary is missing a typed transaction with an empty access list"
           label))
  (when (zerop (fixture-required-field
                summary
                "accessListEmptyAccessListVectorCount"))
    (error "~A summary is missing an EIP-2930 transaction with an empty access list"
           label))
  (when (zerop (fixture-required-field
                summary
                "dynamicFeeEmptyAccessListVectorCount"))
    (error "~A summary is missing a dynamic-fee transaction with an empty access list"
           label))
  (when (zerop (fixture-required-field summary "accessListAddressCount"))
    (error "~A summary is missing access-list address coverage" label))
  (when (zerop (fixture-required-field summary "accessListAddressOnlyVectorCount"))
    (error "~A summary is missing address-only access-list coverage" label))
  (when (zerop (fixture-required-field
                summary
                "dynamicFeeAddressOnlyAccessListVectorCount"))
    (error "~A summary is missing dynamic-fee address-only access-list coverage"
           label))
  (when (zerop (fixture-required-field summary "accessListStorageKeyCount"))
    (error "~A summary is missing access-list storage-key coverage" label))
  summary)

(defun validate-transaction-fixture-contract-creation-coverage
    (summary label)
  (let ((value (fixture-required-field summary "contractCreationVectorCount"))
        (address-value
          (fixture-required-field
           summary
           "contractCreationAddressVectorCount"))
        (access-list-value
          (fixture-required-field
           summary
           "accessListContractCreationVectorCount"))
        (dynamic-fee-value
          (fixture-required-field
           summary
           "dynamicFeeContractCreationVectorCount"))
        (dynamic-fee-access-list-value
          (fixture-required-field
           summary
           "dynamicFeeAccessListContractCreationVectorCount"))
        (empty-access-list-value
          (fixture-required-field
           summary
           "emptyAccessListContractCreationVectorCount"))
        (access-list-empty-access-list-value
          (fixture-required-field
           summary
           "accessListEmptyAccessListContractCreationVectorCount"))
        (dynamic-fee-empty-access-list-value
          (fixture-required-field
           summary
           "dynamicFeeEmptyAccessListContractCreationVectorCount")))
    (unless (and (integerp value) (not (minusp value)))
      (error "~A summary field contractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp address-value) (not (minusp address-value)))
      (error "~A summary field contractCreationAddressVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-value)
                 (not (minusp dynamic-fee-value)))
      (error "~A summary field dynamicFeeContractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-value)
                 (not (minusp access-list-value)))
      (error "~A summary field accessListContractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-access-list-value)
                 (not (minusp dynamic-fee-access-list-value)))
      (error "~A summary field dynamicFeeAccessListContractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp empty-access-list-value)
                 (not (minusp empty-access-list-value)))
      (error "~A summary field emptyAccessListContractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-empty-access-list-value)
                 (not (minusp access-list-empty-access-list-value)))
      (error "~A summary field accessListEmptyAccessListContractCreationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-empty-access-list-value)
                 (not (minusp dynamic-fee-empty-access-list-value)))
      (error "~A summary field dynamicFeeEmptyAccessListContractCreationVectorCount must be a non-negative integer"
             label))
    (when (zerop value)
      (error "~A summary is missing contract-creation transaction coverage"
             label))
    (unless (= address-value value)
      (error "~A summary is missing derived contract-address coverage"
             label))
    (when (zerop access-list-value)
      (error "~A summary is missing access-list contract-creation transaction coverage"
             label))
    (when (zerop dynamic-fee-value)
      (error "~A summary is missing dynamic-fee contract-creation transaction coverage"
             label))
    (when (zerop dynamic-fee-access-list-value)
      (error "~A summary is missing dynamic-fee access-list contract-creation transaction coverage"
             label))
    (when (zerop empty-access-list-value)
      (error "~A summary is missing empty access-list contract-creation transaction coverage"
             label))
    (when (zerop access-list-empty-access-list-value)
      (error "~A summary is missing EIP-2930 empty access-list contract-creation transaction coverage"
             label))
    (when (zerop dynamic-fee-empty-access-list-value)
      (error "~A summary is missing dynamic-fee empty access-list contract-creation transaction coverage"
             label)))
  summary)

(defun validate-transaction-fixture-input-coverage
    (summary label)
  (let ((value
          (fixture-required-field summary "messageCallDataVectorCount"))
        (legacy-value
          (fixture-required-field summary "legacyMessageCallDataVectorCount"))
        (typed-value
          (fixture-required-field summary "typedMessageCallDataVectorCount"))
        (access-list-value
          (fixture-required-field
           summary
           "accessListMessageCallDataVectorCount"))
        (dynamic-fee-value
          (fixture-required-field
           summary
           "dynamicFeeMessageCallDataVectorCount"))
        (access-list-with-calldata-value
          (fixture-required-field
           summary
           "accessListWithCallDataVectorCount"))
        (dynamic-fee-access-list-with-calldata-value
          (fixture-required-field
           summary
           "dynamicFeeAccessListWithCallDataVectorCount"))
        (empty-access-list-with-calldata-value
          (fixture-required-field
           summary
           "emptyAccessListWithCallDataVectorCount"))
        (access-list-empty-access-list-with-calldata-value
          (fixture-required-field
           summary
           "accessListEmptyAccessListWithCallDataVectorCount"))
        (dynamic-fee-empty-access-list-with-calldata-value
          (fixture-required-field
           summary
           "dynamicFeeEmptyAccessListWithCallDataVectorCount")))
    (unless (and (integerp value) (not (minusp value)))
      (error "~A summary field messageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp legacy-value) (not (minusp legacy-value)))
      (error "~A summary field legacyMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp typed-value) (not (minusp typed-value)))
      (error "~A summary field typedMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-value)
                 (not (minusp access-list-value)))
      (error "~A summary field accessListMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-value)
                 (not (minusp dynamic-fee-value)))
      (error "~A summary field dynamicFeeMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-with-calldata-value)
                 (not (minusp access-list-with-calldata-value)))
      (error "~A summary field accessListWithCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-access-list-with-calldata-value)
                 (not (minusp dynamic-fee-access-list-with-calldata-value)))
      (error "~A summary field dynamicFeeAccessListWithCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp empty-access-list-with-calldata-value)
                 (not (minusp empty-access-list-with-calldata-value)))
      (error "~A summary field emptyAccessListWithCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-empty-access-list-with-calldata-value)
                 (not (minusp access-list-empty-access-list-with-calldata-value)))
      (error "~A summary field accessListEmptyAccessListWithCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp dynamic-fee-empty-access-list-with-calldata-value)
                 (not (minusp dynamic-fee-empty-access-list-with-calldata-value)))
      (error "~A summary field dynamicFeeEmptyAccessListWithCallDataVectorCount must be a non-negative integer"
             label))
    (when (zerop value)
      (error "~A summary is missing calldata message-call transaction coverage"
             label))
    (when (zerop legacy-value)
      (error "~A summary is missing legacy calldata message-call transaction coverage"
             label))
    (when (zerop typed-value)
      (error "~A summary is missing typed calldata message-call transaction coverage"
             label))
    (when (zerop access-list-value)
      (error "~A summary is missing access-list calldata message-call transaction coverage"
             label))
    (when (zerop dynamic-fee-value)
      (error "~A summary is missing dynamic-fee calldata message-call transaction coverage"
             label))
    (when (zerop access-list-with-calldata-value)
      (error "~A summary is missing combined access-list calldata transaction coverage"
             label))
    (when (zerop dynamic-fee-access-list-with-calldata-value)
      (error "~A summary is missing combined dynamic-fee access-list calldata transaction coverage"
             label))
    (when (zerop empty-access-list-with-calldata-value)
      (error "~A summary is missing empty access-list calldata transaction coverage"
             label))
    (when (zerop access-list-empty-access-list-with-calldata-value)
      (error "~A summary is missing EIP-2930 empty access-list calldata transaction coverage"
             label))
    (when (zerop dynamic-fee-empty-access-list-with-calldata-value)
      (error "~A summary is missing dynamic-fee empty access-list calldata transaction coverage"
             label)))
  summary)

(defun validate-transaction-fixture-dynamic-fee-coverage
    (summary label)
  (let ((equal-fee-cap-value
          (fixture-required-field
           summary
           "dynamicFeeEqualFeeCapVectorCount")))
    (unless (and (integerp equal-fee-cap-value)
                 (not (minusp equal-fee-cap-value)))
      (error "~A summary field dynamicFeeEqualFeeCapVectorCount must be a non-negative integer"
             label))
    (when (zerop equal-fee-cap-value)
      (error "~A summary is missing dynamic-fee equal fee-cap coverage"
             label)))
  summary)

(defun validate-transaction-fixture-blob-coverage
    (summary label)
  (let ((vector-value
          (fixture-required-field summary "blobVersionedHashVectorCount"))
        (hash-value
          (fixture-required-field summary "blobVersionedHashCount"))
        (access-list-value
          (fixture-required-field summary "blobAccessListVectorCount"))
        (calldata-value
          (fixture-required-field summary "blobMessageCallDataVectorCount"))
        (access-list-calldata-value
          (fixture-required-field
           summary
           "blobAccessListMessageCallDataVectorCount")))
    (unless (and (integerp vector-value) (not (minusp vector-value)))
      (error "~A summary field blobVersionedHashVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp hash-value) (not (minusp hash-value)))
      (error "~A summary field blobVersionedHashCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-value) (not (minusp access-list-value)))
      (error "~A summary field blobAccessListVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp calldata-value) (not (minusp calldata-value)))
      (error "~A summary field blobMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-calldata-value)
                 (not (minusp access-list-calldata-value)))
      (error "~A summary field blobAccessListMessageCallDataVectorCount must be a non-negative integer"
             label))
    (when (zerop vector-value)
      (error "~A summary is missing blob versioned-hash transaction coverage"
             label))
    (when (zerop hash-value)
      (error "~A summary is missing blob versioned-hash entries" label))
    (when (zerop access-list-value)
      (error "~A summary is missing blob access-list transaction coverage"
             label))
    (when (zerop calldata-value)
      (error "~A summary is missing blob calldata transaction coverage"
             label))
    (when (zerop access-list-calldata-value)
      (error "~A summary is missing combined blob access-list calldata coverage"
             label)))
  summary)

(defun validate-transaction-fixture-set-code-coverage
    (summary label)
  (let ((vector-value
          (fixture-required-field summary "setCodeAuthorizationVectorCount"))
        (authorization-value
          (fixture-required-field summary "setCodeAuthorizationCount"))
        (access-list-value
          (fixture-required-field summary "setCodeAccessListVectorCount"))
        (calldata-value
          (fixture-required-field summary "setCodeMessageCallDataVectorCount"))
        (access-list-calldata-value
          (fixture-required-field
           summary
           "setCodeAccessListMessageCallDataVectorCount")))
    (unless (and (integerp vector-value) (not (minusp vector-value)))
      (error "~A summary field setCodeAuthorizationVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp authorization-value)
                 (not (minusp authorization-value)))
      (error "~A summary field setCodeAuthorizationCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-value) (not (minusp access-list-value)))
      (error "~A summary field setCodeAccessListVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp calldata-value) (not (minusp calldata-value)))
      (error "~A summary field setCodeMessageCallDataVectorCount must be a non-negative integer"
             label))
    (unless (and (integerp access-list-calldata-value)
                 (not (minusp access-list-calldata-value)))
      (error "~A summary field setCodeAccessListMessageCallDataVectorCount must be a non-negative integer"
             label))
    (when (zerop vector-value)
      (error "~A summary is missing set-code authorization-list transaction coverage"
             label))
    (when (zerop authorization-value)
      (error "~A summary is missing set-code authorization entries" label))
    (unless (> authorization-value vector-value)
      (error "~A summary is missing multi-authorization set-code coverage"
             label))
    (when (zerop access-list-value)
      (error "~A summary is missing set-code access-list transaction coverage"
             label))
    (when (zerop calldata-value)
      (error "~A summary is missing set-code calldata transaction coverage"
             label))
    (when (zerop access-list-calldata-value)
      (error "~A summary is missing combined set-code access-list calldata coverage"
             label)))
  summary)

(defun validate-transaction-fixture-legacy-protection-coverage
    (summary label)
  (dolist (field '("protectedLegacyVectorCount"
                   "unprotectedLegacyVectorCount"))
    (let ((value (fixture-required-field summary field)))
      (unless (and (integerp value) (not (minusp value)))
        (error "~A summary field ~A must be a non-negative integer"
               label
               field))
      (when (zerop value)
        (error "~A summary is missing ~A coverage"
               label
               field))))
  summary)

(defun validate-transaction-fixture-decoded-coverage
    (vectors summary label)
  (let ((value (fixture-required-field summary "decodedVectorCount")))
    (unless (and (integerp value) (not (minusp value)))
      (error "~A summary field decodedVectorCount must be a non-negative integer"
             label))
    (unless (= value (length vectors))
      (error "~A summary has decodedVectorCount ~A but expected ~A"
             label
             value
             (length vectors))))
  summary)

(defun validate-transaction-fixture-signature-coverage
    (vectors summary label)
  (let ((value (fixture-required-field summary "signatureVectorCount")))
    (unless (and (integerp value) (not (minusp value)))
      (error "~A summary field signatureVectorCount must be a non-negative integer"
             label))
    (unless (= value (length vectors))
      (error "~A summary has signatureVectorCount ~A but expected ~A"
             label
             value
             (length vectors))))
  summary)

(defun transaction-fixture-expected-result-count-summary (vectors)
  (let ((valid-count 0)
        (exception-count 0)
        (valid-fork-counts (make-hash-table :test 'equal))
        (exception-fork-counts (make-hash-table :test 'equal)))
    (dolist (vector vectors)
      (let ((type (transaction-fixture-type-keyword
                   (fixture-required-field vector "type"))))
        (dolist (fork +transaction-fixture-forks+)
          (if (transaction-fixture-type-valid-on-fork-p type fork)
              (progn
                (incf valid-count)
                (incf (gethash fork valid-fork-counts 0)))
              (progn
                (incf exception-count)
                (incf (gethash fork exception-fork-counts 0)))))))
    (list
     (cons "validResultCount" valid-count)
     (cons "exceptionResultCount" exception-count)
     (cons "validForkCounts"
           (transaction-fixture-fork-counts-alist valid-fork-counts))
     (cons "exceptionForkCounts"
           (transaction-fixture-fork-counts-alist exception-fork-counts)))))

(defun validate-transaction-fixture-result-count-summary
    (vectors summary label)
  (let ((expected (transaction-fixture-expected-result-count-summary vectors)))
    (dolist (field '("validResultCount"
                     "exceptionResultCount"
                     "validForkCounts"
                     "exceptionForkCounts"))
      (unless (equal (fixture-required-field expected field)
                     (fixture-required-field summary field))
        (error "~A summary field ~A is ~S but expected ~S"
               label
               field
               (fixture-object-field summary field)
               (fixture-object-field expected field)))))
  summary)

(defun transaction-fixture-vector-summary (vectors)
  (unless (listp vectors)
    (error "Transaction fixture summary vectors must be a list"))
  (dolist (vector vectors)
    (unless (listp vector)
      (error "Transaction fixture summary vector must be a JSON object")))
  (append
   (list
    (cons "count" (length vectors))
    (cons "types" (transaction-fixture-vector-type-counts vectors))
    (cons "names" (mapcar (lambda (vector)
                            (fixture-required-field vector "name"))
                          vectors)))
   (transaction-fixture-decoded-summary vectors)
   (transaction-fixture-signature-summary vectors)
   (transaction-fixture-access-list-summary vectors)
   (transaction-fixture-contract-creation-summary vectors)
   (transaction-fixture-input-summary vectors)
   (transaction-fixture-dynamic-fee-summary vectors)
   (transaction-fixture-blob-summary vectors)
   (transaction-fixture-set-code-summary vectors)
   (transaction-fixture-legacy-protection-summary vectors)
   (transaction-fixture-result-count-summary vectors)))

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
  (unless (listp vectors)
    (error "Phase A EEST transaction vectors must be a list"))
  (let* ((summary (transaction-fixture-vector-summary vectors))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (types (fixture-required-field summary "types")))
    (unless (= count (length +phase-a-eest-transaction-test-case-names+))
      (error "Phase A EEST transaction selector count ~A loaded ~A vectors"
             (length +phase-a-eest-transaction-test-case-names+)
             count))
    (unless (equal names +phase-a-eest-transaction-test-case-names+)
      (error "Phase A EEST transaction summary names ~S do not match selectors ~S"
             names
             +phase-a-eest-transaction-test-case-names+))
    (validate-phase-a-eest-transaction-target-fork-results vectors)
    (validate-phase-a-eest-transaction-summary-types types)
    (validate-transaction-fixture-required-vector-types
     vectors
     +phase-a-eest-transaction-pinned-valid-case-types+
     "Phase A EEST transaction pinned valid vectors")
    (validate-transaction-fixture-decoded-coverage
     vectors
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-signature-coverage
     vectors
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-access-list-coverage
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-contract-creation-coverage
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-input-coverage
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-dynamic-fee-coverage
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-legacy-protection-coverage
     summary
     "Phase A EEST transaction")
    (validate-transaction-fixture-result-count-summary
     vectors
     summary
     "Phase A EEST transaction")
    summary))

(defun validate-full-eest-transaction-vector-summary (vectors)
  (validate-eest-transaction-selector-list
   +full-eest-transaction-test-case-names+)
  (unless (listp vectors)
    (error "Full EEST transaction vectors must be a list"))
  (validate-transaction-fixture-vector-set vectors :require-required-types t)
  (let* ((summary (transaction-fixture-vector-summary vectors))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (types (fixture-required-field summary "types")))
    (unless (= count (length +full-eest-transaction-test-case-names+))
      (error "Full EEST transaction selector count ~A loaded ~A vectors"
             (length +full-eest-transaction-test-case-names+)
             count))
    (unless (equal names +full-eest-transaction-test-case-names+)
      (error "Full EEST transaction summary names ~S do not match selectors ~S"
             names
             +full-eest-transaction-test-case-names+))
    (dolist (type +transaction-fixture-required-types+)
      (unless (assoc type types)
        (error "Full EEST transaction summary is missing required type ~A"
               type)))
    (validate-transaction-fixture-required-vector-types
     vectors
     +full-eest-transaction-pinned-valid-case-types+
     "Full EEST transaction pinned valid vectors")
    (validate-transaction-fixture-decoded-coverage
     vectors
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-signature-coverage
     vectors
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-access-list-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-contract-creation-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-input-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-dynamic-fee-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-blob-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-set-code-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-legacy-protection-coverage
     summary
     "Full EEST transaction")
    (validate-transaction-fixture-result-count-summary
     vectors
     summary
     "Full EEST transaction")
    summary))

