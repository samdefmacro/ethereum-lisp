(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defparameter +eest-transaction-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/transaction_tests/phase-a-sample.json")

(defparameter +phase-a-eest-transaction-test-case-names+
  '("phase-a-sample.json/legacy-eip155-sample"
    "phase-a-sample.json/legacy-unprotected-sample"
    "phase-a-sample.json/legacy-pinned-blockchain-valid-sample"
    "phase-a-sample.json/legacy-unprotected-contract-creation-sample"
    "phase-a-sample.json/legacy-protected-calldata-sample"
    "phase-a-sample.json/legacy-contract-creation-sample"
    "phase-a-sample.json/typed-eip2930-access-list-sample"
    "phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample"
    "phase-a-sample.json/typed-eip2930-address-only-access-list-sample"
    "phase-a-sample.json/typed-eip2930-duplicate-access-list-sample"
    "phase-a-sample.json/typed-eip2930-calldata-sample"
    "phase-a-sample.json/typed-eip2930-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip2930-contract-creation-sample"
    "phase-a-sample.json/typed-eip2930-empty-access-list-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
    "phase-a-sample.json/typed-eip1559-pinned-blockchain-valid-sample"
    "phase-a-sample.json/typed-eip1559-equal-fee-caps-sample"
    "phase-a-sample.json/typed-eip1559-calldata-sample"
    "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
    "phase-a-sample.json/typed-eip1559-access-list-sample"
    "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
    "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip1559-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-empty-access-list-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample"))

(defparameter +full-eest-transaction-test-case-names+
  '("phase-a-sample.json/legacy-eip155-sample"
    "phase-a-sample.json/legacy-unprotected-sample"
    "phase-a-sample.json/legacy-pinned-blockchain-valid-sample"
    "phase-a-sample.json/legacy-unprotected-contract-creation-sample"
    "phase-a-sample.json/legacy-protected-calldata-sample"
    "phase-a-sample.json/legacy-contract-creation-sample"
    "phase-a-sample.json/typed-eip2930-access-list-sample"
    "phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample"
    "phase-a-sample.json/typed-eip2930-address-only-access-list-sample"
    "phase-a-sample.json/typed-eip2930-duplicate-access-list-sample"
    "phase-a-sample.json/typed-eip2930-calldata-sample"
    "phase-a-sample.json/typed-eip2930-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip2930-contract-creation-sample"
    "phase-a-sample.json/typed-eip2930-empty-access-list-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-dynamic-fee-sample"
    "phase-a-sample.json/typed-eip1559-pinned-blockchain-valid-sample"
    "phase-a-sample.json/typed-eip1559-equal-fee-caps-sample"
    "phase-a-sample.json/typed-eip1559-calldata-sample"
    "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
    "phase-a-sample.json/typed-eip1559-access-list-sample"
    "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
    "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip1559-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-empty-access-list-contract-creation-sample"
    "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample"
    "phase-a-sample.json/typed-eip4844-blob-sample"
    "phase-a-sample.json/typed-eip4844-pinned-blockchain-valid-sample"
    "phase-a-sample.json/typed-eip4844-blob-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip7702-set-code-access-list-calldata-sample"
    "phase-a-sample.json/typed-eip7702-set-code-sample"))

(defparameter +invalid-eest-transaction-test-file-names+
  '("prague/eip7702_set_code_tx/test_empty_authorization_list.json"
    "prague/eip7702_set_code_tx/test_invalid_auth_signature.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_address.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id_encoding.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_encoded_as_bytes.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_extra_element.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_missing_element.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_as_list.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_encoding.json"
    "prague/eip7702_set_code_tx/test_invalid_tx_invalid_rlp_encoding.json"))

(defparameter +transaction-envelope-fixture-required-vector-names+
  '("legacy-eip155"
    "legacy-unprotected"
    "legacy-pinned-blockchain-valid"
    "legacy-unprotected-contract-creation"
    "legacy-protected-calldata"
    "legacy-contract-creation"
    "eip2930-access-list"
    "eip2930-pinned-blockchain-valid"
    "eip2930-address-only-access-list"
    "eip2930-duplicate-access-list"
    "eip2930-calldata"
    "eip2930-access-list-calldata"
    "eip2930-contract-creation"
    "eip2930-empty-access-list-contract-creation"
    "eip1559-dynamic-fee"
    "eip1559-pinned-blockchain-valid"
    "eip1559-equal-fee-caps"
    "eip1559-calldata"
    "eip1559-address-only-access-list"
    "eip1559-access-list"
    "eip1559-duplicate-access-list"
    "eip1559-access-list-calldata"
    "eip1559-contract-creation"
    "eip1559-empty-access-list-contract-creation"
    "eip1559-access-list-contract-creation"
    "eip4844-blob"
    "eip4844-pinned-blockchain-valid"
    "eip4844-blob-access-list-calldata"
    "eip7702-set-code-access-list-calldata"
    "eip7702-set-code"))

(defparameter +transaction-envelope-fixture-pinned-valid-vector-types+
  '(("legacy-pinned-blockchain-valid" . :legacy)
    ("eip2930-pinned-blockchain-valid" . :access-list)
    ("eip1559-pinned-blockchain-valid" . :dynamic-fee)
    ("eip4844-pinned-blockchain-valid" . :blob)))

(defparameter +phase-a-eest-transaction-pinned-valid-case-types+
  '(("phase-a-sample.json/legacy-pinned-blockchain-valid-sample" . :legacy)
    ("phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample" . :access-list)
    ("phase-a-sample.json/typed-eip1559-pinned-blockchain-valid-sample" . :dynamic-fee)))

(defparameter +full-eest-transaction-pinned-valid-case-types+
  (append
   +phase-a-eest-transaction-pinned-valid-case-types+
   '(("phase-a-sample.json/typed-eip4844-pinned-blockchain-valid-sample" . :blob))))

(defparameter +transaction-envelope-fixture-format+
  "ethereum-lisp/transaction-envelope-fixtures-v1")

(defparameter +transaction-fixture-forks+
  '("Frontier" "Homestead" "EIP150" "EIP158" "Byzantium"
    "Constantinople" "Istanbul" "Berlin" "London" "Paris" "Shanghai"
    "Cancun" "Prague"))

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
    "TransactionException.TYPE_4_TX_PRE_FORK"
    "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST"
    "TransactionException.TYPE_4_INVALID_AUTHORIZATION_FORMAT"
    "TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE"
    "TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE_S_TOO_HIGH"))

(defparameter +transaction-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "referenceClients" "vectors"))

(defparameter +transaction-fixture-reference-client-fields+
  '("geth" "nethermind" "reth"))

(defparameter +transaction-fixture-vector-fields+
  '("name" "type" "chainId" "txbytes" "hash" "sender" "signature"
    "result" "decoded" "accessList" "contractAddress"))

(defparameter +transaction-fixture-required-vector-fields+
  '("name" "type" "chainId" "txbytes" "hash" "sender" "result"))

(defparameter +transaction-fixture-result-entry-fields+
  '("hash" "sender" "exception" "intrinsicGas"))

(defparameter +transaction-fixture-access-list-entry-fields+
  '("address" "storageKeys"))

(defparameter +transaction-fixture-decoded-fields+
  '("nonce" "gasLimit" "to" "value" "input" "gasPrice"
    "maxPriorityFeePerGas" "maxFeePerGas" "maxFeePerBlobGas"
    "blobVersionedHashes" "authorizationList"))

(defparameter +transaction-fixture-signature-fields+
  '("v" "yParity" "r" "s"))

(defparameter +transaction-fixture-authorization-fields+
  '("chainId" "address" "nonce" "yParity" "r" "s"))

(defparameter +eest-transaction-test-case-fields+
  '("txbytes" "result" "_info"))

(defparameter +eest-transaction-test-result-entry-fields+
  '("hash" "sender" "exception" "intrinsicGas"))

(defparameter +eest-invalid-transaction-rejection-stage-fields+
  '("exception" "decodeErrorCount" "fieldValidationErrorCount"
    "signatureValidationErrorCount" "acceptedCount"))

(defparameter +eest-invalid-transaction-source-file-stage-fields+
  '("sourceFile" "decodeErrorCount" "fieldValidationErrorCount"
    "signatureValidationErrorCount" "acceptedCount"))

(defun validate-transaction-fixture-object-fields
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

(defun validate-transaction-fixture-required-string-field
    (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A must be a string" label))
    (when (blank-string-p value)
      (error "~A must be present" label))))

(defun validate-transaction-fixture-optional-string-field
    (object field label)
  (let ((value (fixture-object-field object field)))
    (unless (or (null value) (stringp value))
      (error "~A must be null or a string" label))
    (when (and (stringp value) (blank-string-p value))
      (error "~A must be null or present" label))))

(defun validate-transaction-envelope-fixture-metadata (fixture)
  (validate-transaction-fixture-object-fields
   fixture
   +transaction-fixture-top-level-fields+
   "Transaction fixture")
  (validate-fixture-format fixture +transaction-envelope-fixture-format+)
  (validate-transaction-fixture-required-string-field
   fixture "source" "Transaction fixture source")
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
      (validate-transaction-fixture-required-string-field
       references
       client
       (format nil "Transaction fixture referenceClients.~A" client)))
    (validate-transaction-fixture-optional-string-field
     references
     "reth"
     "Transaction fixture referenceClients.reth")))

(defun transaction-fixture-type-keyword (type)
  (unless (stringp type)
    (error "Transaction fixture type must be a string"))
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
  (validate-transaction-fixture-required-string-field
   vector
   field
   (format nil "Transaction fixture ~A" field)))

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
      (unless (stringp value)
        (error "Transaction fixture txbytes must be a string"))
      (when (blank-string-p value)
        (error "Transaction fixture txbytes must be present"))
      (let ((canonical
              (handler-case
                  (transaction-fixture-canonical-bytes
                   value
                   "Transaction fixture txbytes")
                (error (condition)
                  (error "Transaction fixture txbytes must be hex bytes: ~A"
                         condition)))))
        (unless (string= value canonical)
          (error "Transaction fixture txbytes must be canonical lowercase 0x-prefixed hex bytes")))
      value)))

(defun validate-transaction-fixture-hash-field (vector)
  (let ((value (fixture-required-field vector "hash")))
    (unless (stringp value)
      (error "Transaction fixture hash must be a string"))
    (let ((canonical
            (handler-case
                (transaction-fixture-canonical-hash32
                 value
                 "Transaction fixture hash")
              (error (condition)
                (error "Transaction fixture hash must be a 32-byte hex string: ~A"
                       condition)))))
      (unless (string= value canonical)
        (error "Transaction fixture hash must be canonical lowercase 0x-prefixed hex")))))

(defun validate-transaction-fixture-address-field (vector)
  (let ((value (fixture-required-field vector "sender")))
    (unless (stringp value)
      (error "Transaction fixture sender must be a string"))
    (let ((canonical
            (handler-case
                (transaction-fixture-canonical-address
                 value
                 "Transaction fixture sender")
              (error (condition)
                (error "Transaction fixture sender must be an address hex string: ~A"
                       condition)))))
      (unless (string= value canonical)
        (error "Transaction fixture sender must be canonical lowercase 0x-prefixed hex")))))

(defun validate-transaction-fixture-contract-address-field (vector)
  (when (fixture-field-present-p vector "contractAddress")
    (let ((value (fixture-object-field vector "contractAddress")))
      (unless (stringp value)
        (error "Transaction fixture contractAddress must be a string"))
      (let ((canonical
              (handler-case
                  (transaction-fixture-canonical-address
                   value
                   "Transaction fixture contractAddress")
                (error (condition)
                  (error "Transaction fixture contractAddress must be an address hex string: ~A"
                         condition)))))
        (unless (string= value canonical)
          (error "Transaction fixture contractAddress must be canonical lowercase 0x-prefixed hex"))))))

(defun validate-transaction-fixture-access-list-shape (vector)
  (when (fixture-field-present-p vector "accessList")
    (let ((access-list (fixture-object-field vector "accessList")))
      (unless (listp access-list)
        (error "Transaction fixture accessList must be a JSON array"))
      (dolist (entry access-list)
        (validate-transaction-fixture-object-fields
         entry
         +transaction-fixture-access-list-entry-fields+
         "Transaction fixture accessList entry")
        (let ((address (fixture-required-field entry "address"))
              (storage-keys (fixture-required-field entry "storageKeys")))
          (unless (stringp address)
            (error "Transaction fixture accessList address must be a string"))
          (unless (string= address
                           (transaction-fixture-canonical-address
                            address
                            "Transaction fixture accessList address"))
            (error "Transaction fixture accessList address must be canonical lowercase 0x-prefixed hex"))
          (unless (listp storage-keys)
            (error "Transaction fixture accessList storageKeys must be a JSON array"))
          (dolist (storage-key storage-keys)
            (unless (stringp storage-key)
              (error "Transaction fixture accessList storage key must be a string"))
            (unless (string= storage-key
                             (transaction-fixture-canonical-hash32
                              storage-key
                              "Transaction fixture accessList storage key"))
              (error "Transaction fixture accessList storage key must be canonical lowercase 0x-prefixed hex"))))))))

(defun validate-transaction-fixture-decoded-quantity-field
    (decoded field label)
  (let ((value (fixture-required-field decoded field)))
    (unless (stringp value)
      (error "~A ~A must be a string" label field))
    (transaction-fixture-canonical-quantity
     value
     (format nil "~A ~A" label field))))

(defun validate-transaction-fixture-decoded-optional-quantity-field
    (decoded field label)
  (when (fixture-field-present-p decoded field)
    (validate-transaction-fixture-decoded-quantity-field decoded field label)))

(defun validate-transaction-fixture-signature-shape (vector)
  (when (fixture-field-present-p vector "signature")
    (let ((signature (fixture-object-field vector "signature"))
          (type (transaction-fixture-type-keyword
                 (fixture-required-field vector "type")))
          (label (format nil "Transaction fixture ~A signature"
                         (fixture-object-field vector "name"))))
      (validate-transaction-fixture-object-fields
       signature
       +transaction-fixture-signature-fields+
       label)
      (dolist (field '("yParity" "r" "s"))
        (validate-transaction-fixture-decoded-quantity-field
         signature
         field
         label))
      (when (fixture-field-present-p signature "v")
        (validate-transaction-fixture-decoded-quantity-field
         signature
         "v"
         label))
      (when (and (eq type :legacy)
                 (not (fixture-field-present-p signature "v")))
        (error "~A v must be present for legacy transactions" label))
      (when (and (not (eq type :legacy))
                 (fixture-field-present-p signature "v"))
        (error "~A v is only valid for legacy transactions" label)))))

(defun validate-transaction-fixture-decoded-address-field
    (decoded field label)
  (let ((value (fixture-object-field decoded field)))
    (unless (or (null value) (stringp value))
      (error "~A ~A must be null or a string" label field))
    (when value
      (unless (string= value
                       (transaction-fixture-canonical-address
                        value
                        (format nil "~A ~A" label field)))
        (error "~A ~A must be canonical lowercase 0x-prefixed hex"
               label
               field)))))

(defun validate-transaction-fixture-decoded-required-address-field
    (decoded field label)
  (unless (fixture-field-present-p decoded field)
    (error "~A ~A must be present" label field))
  (validate-transaction-fixture-decoded-address-field decoded field label))

(defun validate-transaction-fixture-decoded-input-field (decoded label)
  (let ((value (fixture-required-field decoded "input")))
    (unless (stringp value)
      (error "~A input must be a string" label))
    (unless (string= value
                     (transaction-fixture-canonical-byte-string
                      value
                      (format nil "~A input" label)))
      (error "~A input must be canonical lowercase 0x-prefixed hex bytes"
             label))))

(defun validate-transaction-fixture-decoded-blob-hashes
    (decoded label)
  (when (fixture-field-present-p decoded "blobVersionedHashes")
    (let ((hashes (fixture-object-field decoded "blobVersionedHashes")))
      (unless (listp hashes)
        (error "~A blobVersionedHashes must be a JSON array" label))
      (dolist (hash hashes)
        (unless (stringp hash)
          (error "~A blobVersionedHashes entry must be a string" label))
        (unless (string= hash
                         (transaction-fixture-canonical-hash32
                          hash
                          (format nil "~A blobVersionedHashes entry" label)))
          (error "~A blobVersionedHashes entry must be canonical lowercase 0x-prefixed hex"
                 label))))))

(defun validate-transaction-fixture-decoded-authorization-shape
    (authorization label)
  (validate-transaction-fixture-object-fields
   authorization
   +transaction-fixture-authorization-fields+
   label)
  (dolist (field '("chainId" "nonce" "yParity" "r" "s"))
    (validate-transaction-fixture-decoded-quantity-field
     authorization
     field
     label))
  (validate-transaction-fixture-decoded-required-address-field
   authorization
   "address"
   label))

(defun validate-transaction-fixture-decoded-authorizations
    (decoded label)
  (when (fixture-field-present-p decoded "authorizationList")
    (let ((authorizations (fixture-object-field decoded "authorizationList")))
      (unless (listp authorizations)
        (error "~A authorizationList must be a JSON array" label))
      (dolist (authorization authorizations)
        (validate-transaction-fixture-decoded-authorization-shape
         authorization
         (format nil "~A authorizationList entry" label))))))

(defun validate-transaction-fixture-decoded-shape (vector)
  (when (fixture-field-present-p vector "decoded")
    (let ((decoded (fixture-object-field vector "decoded"))
          (label (format nil "Transaction fixture ~A decoded"
                         (fixture-object-field vector "name"))))
      (validate-transaction-fixture-object-fields
       decoded
       +transaction-fixture-decoded-fields+
       label)
      (dolist (field '("nonce" "gasLimit" "value"))
        (validate-transaction-fixture-decoded-quantity-field
         decoded
         field
         label))
      (validate-transaction-fixture-decoded-required-address-field
       decoded
       "to"
       label)
      (validate-transaction-fixture-decoded-input-field decoded label)
      (dolist (field '("gasPrice"
                       "maxPriorityFeePerGas"
                       "maxFeePerGas"
                       "maxFeePerBlobGas"))
        (validate-transaction-fixture-decoded-optional-quantity-field
         decoded
         field
         label))
      (validate-transaction-fixture-decoded-blob-hashes decoded label)
      (validate-transaction-fixture-decoded-authorizations decoded label))))

(defun transaction-fixture-hex-prefixed-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun transaction-fixture-normalized-hex (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  (if (transaction-fixture-hex-prefixed-p value)
      value
      (concatenate 'string "0x" value)))

(defun transaction-fixture-canonical-quantity (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (let ((canonical (string-downcase (quantity-to-hex (hex-to-quantity value)))))
    (unless (string= value canonical)
      (error "~A must be a canonical quantity" label))
    canonical))

(defun transaction-fixture-canonical-hash32 (value label)
  (declare (ignore label))
  (hash32-to-hex (hash32-from-hex value)))

(defun transaction-fixture-canonical-address (value label)
  (declare (ignore label))
  (address-to-hex (address-from-hex value)))

(defun transaction-fixture-canonical-bytes (value label)
  (let ((bytes (hex-to-bytes value)))
    (when (zerop (length bytes))
      (error "~A must encode at least one byte" label))
    (bytes-to-hex bytes)))

(defun transaction-fixture-canonical-byte-string (value label)
  (declare (ignore label))
  (bytes-to-hex (hex-to-bytes value)))

(defun transaction-fixture-access-list-object (access-list)
  (mapcar
   (lambda (entry)
     (list
      (cons "address" (address-to-hex (access-list-entry-address entry)))
      (cons "storageKeys"
            (mapcar #'hash32-to-hex
                    (access-list-entry-storage-keys entry)))))
   access-list))

(defun transaction-fixture-transaction-to-object (recipient)
  (and recipient (address-to-hex recipient)))

(defun transaction-fixture-created-contract-address (transaction sender)
  (when (and (null (transaction-to transaction)) sender)
    (let* ((hash (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender)
                                  (transaction-nonce transaction)))))
           (bytes (make-byte-vector 20)))
      (replace bytes hash :start2 12)
      (make-address bytes))))

(defun transaction-fixture-authorization-object (authorization)
  (list
   (cons "chainId"
         (quantity-to-hex
          (set-code-authorization-chain-id authorization)))
   (cons "address"
         (address-to-hex
          (set-code-authorization-address authorization)))
   (cons "nonce"
         (quantity-to-hex
          (set-code-authorization-nonce authorization)))
   (cons "yParity"
         (quantity-to-hex
          (set-code-authorization-y-parity authorization)))
   (cons "r"
         (quantity-to-hex
          (set-code-authorization-r authorization)))
   (cons "s"
         (quantity-to-hex
          (set-code-authorization-s authorization)))))

(defun transaction-fixture-legacy-y-parity (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) (- v 27))
      ((>= v 35) (mod (- v 35) 2))
      (t nil))))

(defun transaction-fixture-signature-object (transaction)
  (etypecase transaction
    (legacy-transaction
     (list
      (cons "v" (quantity-to-hex (legacy-transaction-v transaction)))
      (cons "yParity"
            (quantity-to-hex
             (transaction-fixture-legacy-y-parity transaction)))
      (cons "r" (quantity-to-hex (legacy-transaction-r transaction)))
      (cons "s" (quantity-to-hex (legacy-transaction-s transaction)))))
    (access-list-transaction
     (list
      (cons "yParity"
            (quantity-to-hex
             (access-list-transaction-y-parity transaction)))
      (cons "r" (quantity-to-hex (access-list-transaction-r transaction)))
      (cons "s" (quantity-to-hex (access-list-transaction-s transaction)))))
    (dynamic-fee-transaction
     (list
      (cons "yParity"
            (quantity-to-hex
             (dynamic-fee-transaction-y-parity transaction)))
      (cons "r" (quantity-to-hex (dynamic-fee-transaction-r transaction)))
      (cons "s" (quantity-to-hex (dynamic-fee-transaction-s transaction)))))
    (blob-transaction
     (list
      (cons "yParity"
            (quantity-to-hex
             (blob-transaction-y-parity transaction)))
      (cons "r" (quantity-to-hex (blob-transaction-r transaction)))
      (cons "s" (quantity-to-hex (blob-transaction-s transaction)))))
    (set-code-transaction
     (list
      (cons "yParity"
            (quantity-to-hex
             (set-code-transaction-y-parity transaction)))
      (cons "r" (quantity-to-hex (set-code-transaction-r transaction)))
      (cons "s" (quantity-to-hex (set-code-transaction-s transaction)))))))

(defun transaction-fixture-decoded-object (transaction)
  (let ((decoded
          (list
           (cons "nonce" (quantity-to-hex (transaction-nonce transaction)))
           (cons "gasLimit"
                 (quantity-to-hex (transaction-gas-limit transaction)))
           (cons "to"
                 (transaction-fixture-transaction-to-object
                  (transaction-to transaction)))
           (cons "value" (quantity-to-hex (transaction-value transaction)))
           (cons "input" (bytes-to-hex (transaction-data transaction))))))
    (etypecase transaction
      (legacy-transaction
       (setf decoded
             (append
              decoded
              (list
               (cons "gasPrice"
                     (quantity-to-hex
                      (legacy-transaction-gas-price transaction)))))))
      (access-list-transaction
       (setf decoded
             (append
              decoded
              (list
               (cons "gasPrice"
                     (quantity-to-hex
                      (access-list-transaction-gas-price transaction)))))))
      (dynamic-fee-transaction
       (setf decoded
             (append
              decoded
              (list
               (cons "maxPriorityFeePerGas"
                     (quantity-to-hex
                      (dynamic-fee-transaction-max-priority-fee-per-gas
                       transaction)))
               (cons "maxFeePerGas"
                     (quantity-to-hex
                      (dynamic-fee-transaction-max-fee-per-gas
                       transaction)))))))
      (blob-transaction
       (setf decoded
             (append
              decoded
              (list
               (cons "maxPriorityFeePerGas"
                     (quantity-to-hex
                      (blob-transaction-max-priority-fee-per-gas
                       transaction)))
               (cons "maxFeePerGas"
                     (quantity-to-hex
                      (blob-transaction-max-fee-per-gas transaction)))
               (cons "maxFeePerBlobGas"
                     (quantity-to-hex
                      (blob-transaction-max-fee-per-blob-gas transaction)))
               (cons "blobVersionedHashes"
                     (mapcar #'hash32-to-hex
                             (blob-transaction-blob-versioned-hashes
                              transaction)))))))
      (set-code-transaction
       (setf decoded
             (append
              decoded
              (list
               (cons "maxPriorityFeePerGas"
                     (quantity-to-hex
                      (set-code-transaction-max-priority-fee-per-gas
                       transaction)))
               (cons "maxFeePerGas"
                     (quantity-to-hex
                      (set-code-transaction-max-fee-per-gas transaction)))
               (cons "authorizationList"
                     (mapcar #'transaction-fixture-authorization-object
                             (set-code-transaction-authorization-list
                              transaction))))))))
    decoded))

