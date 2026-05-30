(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defparameter +eest-transaction-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/transaction_tests/phase-a-sample.json")

(defparameter +phase-a-eest-transaction-test-case-names+
  '("phase-a-sample.json/legacy-eip155-sample"
    "phase-a-sample.json/legacy-unprotected-sample"
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
    "eip4844-blob-access-list-calldata"
    "eip7702-set-code-access-list-calldata"
    "eip7702-set-code"))

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
  (unless (listp names)
    (error "EEST transaction selector list must be a list"))
  (unless names
    (error "EEST transaction selector list must not be empty"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (unless (stringp name)
        (error "EEST transaction selector name must be a string"))
      (when (blank-string-p name)
        (error "EEST transaction selector name must be present"))
      (unless (eest-transaction-selector-source-style-p name)
        (error "EEST transaction selector ~A must be a source-style JSON case name"
               name))
      (when (gethash name seen)
        (error "EEST transaction selector list has duplicate name ~A"
               name))
      (setf (gethash name seen) t))))

(defun eest-transaction-selector-source-style-p (name)
  (and (stringp name)
       (not (blank-string-p name))
       (not (char= (char name 0) #\/))
       (null (search ".." name))
       (null (search "//" name))
       (let* ((json-position (search ".json" name :test #'char-equal))
              (after-json (and json-position (+ json-position 5))))
         (and json-position
              (plusp json-position)
              (not (char= (char name (1- json-position)) #\/))
              (or (= after-json (length name))
                  (and (< after-json (length name))
                       (char= (char name after-json) #\/)
                       (< (1+ after-json) (length name))
                       (not (char= (char name (1+ after-json)) #\/))))))))

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
                    (ethereum-lisp.core::eth-rpc-validate-set-code-authorization-signatures
                     transaction)
                    "accepted")
                (error () "signature")))
          (error () "field")))
    (error () "decode")))

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

(defun eest-invalid-transaction-exception-stage-entry
    (exception counts)
  (let ((entry
          (list
           (cons "exception" exception)
           (cons "decodeErrorCount" (gethash "decode" counts 0))
           (cons "fieldValidationErrorCount" (gethash "field" counts 0))
           (cons "signatureValidationErrorCount" (gethash "signature" counts 0))
           (cons "acceptedCount" (gethash "accepted" counts 0)))))
    (validate-eest-invalid-transaction-rejection-stage-entry
     entry
     "EEST invalid transaction rejection stage summary")
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

(defun eest-invalid-transaction-rejection-summary (cases)
  (let ((decode-error-count 0)
        (field-validation-error-count 0)
        (signature-validation-error-count 0)
        (source-file-counts (make-hash-table :test 'equal))
        (exception-counts (make-hash-table :test 'equal))
        (exception-stage-counts (make-hash-table :test 'equal))
        (accepted-names '()))
    (dolist (case cases)
      (let* ((exception (eest-invalid-transaction-case-exception case))
             (source-file (eest-transaction-case-source-file-name case))
             (stage (eest-invalid-transaction-local-rejection-stage case))
             (stage-counts
               (or (gethash exception exception-stage-counts)
                   (setf (gethash exception exception-stage-counts)
                         (make-hash-table :test 'equal)))))
        (increment-string-count source-file-counts source-file)
        (increment-string-count exception-counts exception)
        (increment-string-count stage-counts stage)
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

(defun validate-transaction-envelope-vector-coverage (vectors)
  (validate-transaction-fixture-vector-set vectors :require-required-types t)
  (validate-transaction-fixture-required-vector-names
   vectors
   +transaction-envelope-fixture-required-vector-names+)
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

(deftest transaction-fixture-result-shape-validation
  (let ((vector (list (cons "name" "shape-test")
                      (cons "type" "dynamic-fee"))))
    (signals error
      (validate-transaction-fixture-result-shape "shape-test"))
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
      (validate-transaction-fixture-result-shape
       (list (cons "name" "malformed-fork-entry")
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
                    (list "bad-entry"))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "non-string-fork")
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
                    (list (cons 42
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "non-string-fork-first")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (cons
                    (cons 42 (list (cons "intrinsicGas" "0x5208")))
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "blank-fork")
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
                    (list (cons ""
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
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "a98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash" 42)
             (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender"
                   "d02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender" 42)
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "intrinsicGas" "0x5208")
             (cons "intrinsicGas" "0x5209"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" 42))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0X5208"))))
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
       (list (cons "exception" 42))))
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
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0x5208"))))
    (validate-transaction-fixture-result-entry
     vector
     :dynamic-fee
     "London"
     (list (cons "hash"
                 "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
           (cons "sender"
                 "0xd02d72e067e77158444ef2020ff2d325f929b363")
           (cons "intrinsicGas" "0x5208")))
    (validate-transaction-fixture-result-entry
     vector :dynamic-fee "Berlin" (list (cons "exception"
                                 "TransactionException.TYPE_2_TX_PRE_FORK")))))

(defun transaction-fixture-metadata-shape-test-fixture
    (&key
       top-extra
       reference-extra
       (source "test fixture")
       (geth "test-geth")
       (nethermind "test-nethermind")
       (reth nil))
  (append
   (list
    (cons "format" +transaction-envelope-fixture-format+)
    (cons "source" source)
    (cons "executionSpecTests"
          (list (cons "release" +phase-a-eest-release+)
                (cons "tagTarget" +phase-a-eest-tag-target+)
                (cons "archive" +phase-a-eest-archive+)
                (cons "status" "test")))
    (cons "referenceClients"
          (append
           (list (cons "geth" geth)
                 (cons "nethermind" nethermind)
                 (cons "reth" reth))
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
      :top-extra (list (cons 42 t)))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :source 42))
            nil)
        (error (condition)
          (search "source must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :geth 42))
            nil)
        (error (condition)
          (search "referenceClients.geth must be a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :nethermind 42))
            nil)
        (error (condition)
          (search "referenceClients.nethermind must be a string"
                  (princ-to-string condition)))))
  (validate-transaction-envelope-fixture-metadata
   (transaction-fixture-metadata-shape-test-fixture :reth "test-reth"))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :reth 42))
            nil)
        (error (condition)
          (search "referenceClients.reth must be null or a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :reth ""))
            nil)
        (error (condition)
          (search "referenceClients.reth must be null or present"
                  (princ-to-string condition)))))
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
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" 42)
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "name must be a string" (princ-to-string condition)))))
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
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-type")
                   (cons "type" 42)
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "type must be a string" (princ-to-string condition)))))
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
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" 42)
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-txbytes-hex")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x0")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be hex bytes" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be canonical"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0XAB")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be canonical"
                  (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-hash")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash" "0x01")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-hash-message")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash" "0x01")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be a 32-byte hex string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash" 42)
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be canonical" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0X00000000000000000000000000000000000000000000000000000000000000AB")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be canonical" (princ-to-string condition)))))
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
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-sender-message")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x01")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be an address hex string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" 42)
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be canonical" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0X00000000000000000000000000000000000000AB")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be canonical" (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-contract-address")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "contractAddress" "0x01")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-contract-address")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "contractAddress" 42)
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "contractAddress must be a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-contract-address")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "contractAddress"
                         "0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "contractAddress must be canonical"
                  (princ-to-string condition)))))
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
                       +transaction-envelope-fixture-path+)))
        (contract-vector
          (find "legacy-contract-creation"
                (load-transaction-envelope-vectors
                 +transaction-envelope-fixture-path+)
                :test #'string=
                :key (lambda (candidate)
                       (fixture-object-field candidate "name")))))
    (labels ((replace-field (field value)
               (cons (cons field value)
                     (remove field vector :key #'car :test #'string=)))
             (replace-contract-field (field value)
               (cons (cons field value)
                     (remove field
                             contract-vector
                             :key #'car
                             :test #'string=))))
      (validate-transaction-fixture-decoded-vector vector)
      (validate-transaction-fixture-decoded-vector contract-vector)
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
         (replace-field "contractAddress"
                        "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (remove "contractAddress"
                 contract-vector
                 :key #'car
                 :test #'string=)))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-contract-field
          "contractAddress"
          "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field
          "signature"
          (list (cons "v" "0x25")
                (cons "yParity" "0x1")
                (cons "r"
                      "0x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276")
                (cons "s"
                      "0x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")))))
      (let ((message
              (handler-case
                  (progn
                    (validate-transaction-fixture-decoded-vector
                     (replace-field
                      "result"
                      (list (cons "Frontier"
                                  (list (cons "intrinsicGas" "0x5209")))
                            (cons "Berlin"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "London"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Paris"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Shanghai"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Cancun"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Prague"
                                  (list (cons "intrinsicGas" "0x5208"))))))
                    nil)
                (error (condition)
                  (princ-to-string condition)))))
        (is message)
        (is (search "fork Frontier" message))
        (is (search "0x5209" message))
        (is (search "0x5208" message))))))

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
  (let* ((case (find "legacy-eip155-sample"
                     (load-eest-transaction-test-file
                      +eest-transaction-test-sample-path+)
                     :key (lambda (candidate)
                            (fixture-required-field candidate "name"))
                     :test #'string=))
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

  (let* ((cases (load-eest-transaction-test-file
                 +eest-transaction-test-sample-path+))
         (legacy-case
           (find "legacy-eip155-sample" cases
                 :key (lambda (case) (fixture-required-field case "name"))
                 :test #'string=))
         (access-list-case
           (find "typed-eip2930-access-list-sample" cases
                 :key (lambda (case) (fixture-required-field case "name"))
                 :test #'string=)))
    (labels ((without-fork-result (case fork)
               (let ((result (fixture-required-field case "result")))
                 (cons (cons "result"
                             (remove fork result :key #'car :test #'string=))
                       (remove "result" case :key #'car :test #'string=)))))
      (let* ((sparse-legacy
               (without-fork-result legacy-case "Homestead"))
             (legacy-vector
               (convert-eest-transaction-case-to-vector sparse-legacy))
             (legacy-result
               (fixture-required-field legacy-vector "result"))
             (frontier
               (fixture-required-field legacy-result "Frontier"))
             (homestead
               (fixture-required-field legacy-result "Homestead")))
        (is (equal frontier homestead))
        (validate-transaction-fixture-result-shape legacy-vector))
      (let* ((sparse-access-list
               (without-fork-result access-list-case "Homestead"))
             (access-list-vector
               (convert-eest-transaction-case-to-vector sparse-access-list))
             (homestead
               (fixture-required-field
                (fixture-required-field access-list-vector "result")
                "Homestead")))
        (is (string= "TransactionException.TYPE_1_TX_PRE_FORK"
                     (fixture-required-field homestead "exception")))
        (validate-transaction-fixture-result-shape access-list-vector))
      (let* ((sparse-access-list
               (without-fork-result access-list-case "Berlin"))
             (access-list-vector
               (convert-eest-transaction-case-to-vector sparse-access-list))
             (access-list-result
               (fixture-required-field access-list-vector "result"))
             (berlin
               (fixture-required-field access-list-result "Berlin"))
             (london
               (fixture-required-field access-list-result "London")))
        (is (equal london berlin))
        (validate-transaction-fixture-result-shape access-list-vector))))

  (signals error
    (normalize-eest-transaction-test-case
     "missing-result"
     (list (cons "txbytes" "0x01"))))
  (signals error
    (normalize-eest-transaction-test-case
     ""
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     nil
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     42
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     "empty-result"
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (validate-eest-transaction-test-file-entries
   (list (cons "valid-case" nil))
   "sample.json")
  (signals error
    (validate-eest-transaction-test-file-entries nil "empty.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     '("not-an-object-entry")
     "array.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons "" nil))
     "sample.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons nil nil))
     "sample.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons "duplicate" nil)
           (cons "duplicate" nil))
     "sample.json"))
  (let ((case
          (normalize-eest-transaction-test-case
           "uppercase-success-fields"
           (list
            (cons "txbytes" "0XAB")
            (cons "result"
                  (list
                   (cons "Shanghai"
                         (list
                          (cons "hash"
                                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                          (cons "sender"
                                "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
                          (cons "intrinsicGas" "0x1")))))))))
    (let ((shanghai (fixture-object-field
                     (fixture-object-field case "result")
                     "Shanghai")))
      (is (string= "0xab" (fixture-object-field case "txbytes")))
      (is (string=
           "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
           (fixture-object-field shanghai "hash")))
      (is (string=
           "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
           (fixture-object-field shanghai "sender")))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-case-field"
     (list (cons "txbytes" "0x01")
           (cons "result" nil)
           (cons "unexpected" t))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-case-field"
     (list (cons "txbytes" "0x01")
           (cons "result" nil)
           (cons 42 t))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-txbytes"
     (list (cons "txbytes" 42)
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
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
     "malformed-result-entry"
     (list (cons "txbytes" "0x01")
           (cons "result" '("not-a-fork-entry")))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons nil
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "blank-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons ""
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
     "non-string-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception" 42))))))))
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
     "success-non-string-hash"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash" 42)
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-non-string-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender" 42)
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-non-string-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" 42))))))))
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
     "success-with-blank-exception"
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
                         (cons "exception" nil))))))))
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
         (invalid-cases
           (load-eest-transaction-test-root-invalid-cases root))
         (selected-cases
           (load-eest-transaction-test-root-cases
            root
            :names +phase-a-eest-transaction-test-case-names+))
         (vectors (load-eest-transaction-test-root-vectors root))
         (selected-vectors
           (load-phase-a-eest-transaction-test-root-vectors root))
         (full-vectors
           (load-full-eest-transaction-test-root-vectors root))
         (seed-vectors
           (load-transaction-envelope-vectors
            +transaction-envelope-fixture-path+))
         (legacy-vector
           (find "phase-a-sample.json/legacy-eip155-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (unprotected-vector
           (find "phase-a-sample.json/legacy-unprotected-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (unprotected-contract-vector
           (find "phase-a-sample.json/legacy-unprotected-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (protected-calldata-vector
           (find "phase-a-sample.json/legacy-protected-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (contract-vector
           (find "phase-a-sample.json/legacy-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-vector
           (find "phase-a-sample.json/typed-eip2930-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-pinned-blockchain-vector
           (find "phase-a-sample.json/typed-eip2930-pinned-blockchain-valid-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-address-only-vector
           (find "phase-a-sample.json/typed-eip2930-address-only-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-calldata-vector
           (find "phase-a-sample.json/typed-eip2930-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-access-list-calldata-vector
           (find "phase-a-sample.json/typed-eip2930-access-list-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-contract-vector
           (find "phase-a-sample.json/typed-eip2930-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (typed-empty-access-list-contract-vector
           (find
            "phase-a-sample.json/typed-eip2930-empty-access-list-contract-creation-sample"
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
         (dynamic-fee-calldata-vector
           (find "phase-a-sample.json/typed-eip1559-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-address-only-access-list-vector
           (find
            "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-vector
           (find "phase-a-sample.json/typed-eip1559-access-list-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-duplicate-access-list-vector
           (find
            "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-calldata-vector
           (find "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-contract-vector
           (find "phase-a-sample.json/typed-eip1559-contract-creation-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (dynamic-fee-access-list-contract-vector
           (find
            "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (blob-vector
           (find "phase-a-sample.json/typed-eip4844-blob-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (blob-access-list-calldata-vector
           (find
            "phase-a-sample.json/typed-eip4844-blob-access-list-calldata-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (set-code-access-list-calldata-vector
           (find
            "phase-a-sample.json/typed-eip7702-set-code-access-list-calldata-sample"
            vectors
            :test #'string=
            :key (lambda (candidate)
                   (fixture-object-field candidate "name"))))
         (set-code-vector
           (find "phase-a-sample.json/typed-eip7702-set-code-sample"
                 vectors
                 :test #'string=
                 :key (lambda (candidate)
                        (fixture-object-field candidate "name"))))
         (all-summary (transaction-fixture-vector-summary vectors))
         (full-summary (transaction-fixture-vector-summary full-vectors))
         (summary (transaction-fixture-vector-summary selected-vectors)))
    (is (= 13 (length paths)))
    (is (= 80 (length cases)))
    (is (= 53 (length invalid-cases)))
    (is (= 23 (length selected-cases)))
    (is (= 27 (length vectors)))
    (is (= 23 (length selected-vectors)))
    (is (= 27 (length full-vectors)))
    (validate-transaction-fixture-vector-set vectors :require-required-types t)
    (assert-transaction-fixture-vectors-replay vectors)
    (is (equal +phase-a-eest-transaction-test-case-names+
               (mapcar
                (lambda (case)
                  (fixture-object-field case "name"))
                selected-cases)))
    (is (equal +full-eest-transaction-test-case-names+
               (mapcar
                (lambda (vector)
                  (fixture-object-field vector "name"))
                full-vectors)))
    (is (equal +invalid-eest-transaction-test-file-names+
               (remove-duplicates
                (mapcar #'eest-transaction-case-source-file-name invalid-cases)
                :test #'string=)))
    (let ((invalid-rejection-summary
            (eest-invalid-transaction-rejection-summary invalid-cases)))
      (is (= 38 (fixture-required-field invalid-rejection-summary
                                        "decodeErrorCount")))
      (is (= 13 (fixture-required-field invalid-rejection-summary
                                        "fieldValidationErrorCount")))
      (is (= 2 (fixture-required-field invalid-rejection-summary
                                       "signatureValidationErrorCount")))
      (is (null (fixture-required-field invalid-rejection-summary
                                        "acceptedNames")))
      (is (equal
           '(("prague/eip7702_set_code_tx/test_empty_authorization_list.json" . 1)
             ("prague/eip7702_set_code_tx/test_invalid_auth_signature.json" . 8)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_address.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_auth_chain_id_encoding.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_encoded_as_bytes.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_extra_element.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_authorization_tuple_missing_element.json" . 12)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce.json" . 4)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_as_list.json" . 6)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_nonce_encoding.json" . 2)
             ("prague/eip7702_set_code_tx/test_invalid_tx_invalid_rlp_encoding.json" . 4))
           (fixture-required-field invalid-rejection-summary
                                   "sourceFileCounts")))
      (is (equal
           '(("TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST" . 1)
             ("TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE|TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE_S_TOO_HIGH" . 8)
             ("TransactionException.TYPE_4_INVALID_AUTHORIZATION_FORMAT" . 44))
           (fixture-required-field invalid-rejection-summary
                                   "exceptionCounts")))
      (is (equal
           (list
            '(("exception" . "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 1)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0))
            '(("exception" . "TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE|TransactionException.TYPE_4_INVALID_AUTHORITY_SIGNATURE_S_TOO_HIGH")
              ("decodeErrorCount" . 0)
              ("fieldValidationErrorCount" . 6)
              ("signatureValidationErrorCount" . 2)
              ("acceptedCount" . 0))
            '(("exception" . "TransactionException.TYPE_4_INVALID_AUTHORIZATION_FORMAT")
              ("decodeErrorCount" . 38)
              ("fieldValidationErrorCount" . 6)
              ("signatureValidationErrorCount" . 0)
              ("acceptedCount" . 0)))
           (fixture-required-field invalid-rejection-summary
                                   "exceptionStageCounts"))))
    (let* ((invalid-case (first invalid-cases))
           (invalid-result (fixture-required-field invalid-case "result"))
           (prague-result (fixture-required-field invalid-result "Prague"))
           (invalid-transaction
             (transaction-from-encoding
              (hex-to-bytes (fixture-required-field invalid-case "txbytes"))))
           (message
             (handler-case
                 (progn
                   (ethereum-lisp.execution::validate-set-code-transaction-fields
                    invalid-transaction)
                   nil)
               (transaction-validation-error (condition)
                 (format nil "~A" condition)))))
      (is (string= "prague/eip7702_set_code_tx/test_empty_authorization_list.json"
                   (fixture-object-field invalid-case "name")))
      (is (string= "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST"
                   (fixture-required-field prague-result "exception")))
      (is (typep invalid-transaction 'set-code-transaction))
      (is (null (set-code-transaction-authorization-list invalid-transaction)))
      (is message)
      (is (search "authorization list" message)))
    (is legacy-vector)
    (is (string= "phase-a-sample.json/legacy-eip155-sample"
                 (fixture-object-field legacy-vector "name")))
    (is (string= "legacy"
                 (fixture-object-field legacy-vector "type")))
    (is unprotected-vector)
    (is (string= "phase-a-sample.json/legacy-unprotected-sample"
                 (fixture-object-field unprotected-vector "name")))
    (is (string= "legacy"
                 (fixture-object-field unprotected-vector "type")))
    (is (= 0 (fixture-object-field unprotected-vector "chainId")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field unprotected-vector "txbytes")))))
      (is (not (legacy-transaction-protected-p transaction))))
    (is unprotected-contract-vector)
    (is (string= "legacy"
                 (fixture-object-field unprotected-contract-vector "type")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field unprotected-contract-vector "txbytes")))))
      (is (not (legacy-transaction-protected-p transaction)))
      (is (null (transaction-to transaction))))
    (is (string= "0xd30c8839c1145609e564b986f667b273ddcb8496"
                 (fixture-object-field
                  unprotected-contract-vector
                  "contractAddress")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field unprotected-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is protected-calldata-vector)
    (is (string= "legacy"
                 (fixture-object-field protected-calldata-vector "type")))
    (let ((transaction
            (transaction-from-encoding
             (hex-to-bytes
              (fixture-object-field protected-calldata-vector "txbytes")))))
      (is (legacy-transaction-protected-p transaction)))
    (is (equal
         (list
          (cons "nonce" "0xb")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0xdeadbeef")
          (cons "gasPrice" "0x1"))
         (fixture-object-field protected-calldata-vector "decoded")))
    (is (string= "0x5248"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field protected-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is contract-vector)
    (is (string= "0x00de48310d77a4d56aa400248b0b1613508f5b73"
                 (fixture-object-field contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field contract-vector "decoded")
                  "input")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x4")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-vector "decoded")))
    (is (equal
         (list
          (cons "yParity" "0x0")
          (cons "r"
                "0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          (cons "s"
                "0x1ed995b55ae531ccce7f7355b76d169c08886a437e3932f6f0e79c9dcc297aed"))
         (fixture-object-field typed-vector "signature")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field typed-vector "accessList")))
    (is typed-pinned-blockchain-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-pinned-blockchain-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x0")
          (cons "gasLimit" "0x186a0")
          (cons "to" "0x31fea89c26d83e9ea40dc184bba2615d70f62e61")
          (cons "value" "0x0")
          (cons "input" "0x")
          (cons "gasPrice" "0xa"))
         (fixture-object-field typed-pinned-blockchain-vector "decoded")))
    (is (not (fixture-field-present-p
              typed-pinned-blockchain-vector
              "accessList")))
    (is (string= "0x5208"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-pinned-blockchain-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-address-only-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-address-only-vector "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys" '())))
         (fixture-object-field typed-address-only-vector "accessList")))
    (is (string= "0x5b68"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-address-only-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-calldata-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x3")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-calldata-vector "decoded")))
    (is (string= "0x5228"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-access-list-calldata-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-access-list-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x7")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "gasPrice" "0x1"))
         (fixture-object-field typed-access-list-calldata-vector "decoded")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field typed-access-list-calldata-vector "accessList")))
    (is (string= "0x6a60"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-access-list-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-contract-vector)
    (is (string= "access-list"
                 (fixture-object-field typed-contract-vector "type")))
    (is (string= "0x4a4be0144ae0ef07ca7b8715b1987d7fc7118961"
                 (fixture-object-field typed-contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field typed-contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field typed-contract-vector "decoded")
                  "input")))
    (is (string= "0xe77a"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field typed-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is typed-empty-access-list-contract-vector)
    (is (string= "access-list"
                 (fixture-object-field
                  typed-empty-access-list-contract-vector
                  "type")))
    (is (string= "0x3430739421c2980e911ddb9f0385fdaaae473144"
                 (fixture-object-field
                  typed-empty-access-list-contract-vector
                  "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field
                typed-empty-access-list-contract-vector
                "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field
                   typed-empty-access-list-contract-vector
                   "decoded")
                  "input")))
    (is (not (fixture-field-present-p
              typed-empty-access-list-contract-vector
              "accessList")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    typed-empty-access-list-contract-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-vector "type")))
    (is dynamic-fee-calldata-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x5")
          (cons "gasLimit" "0x61a8")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "maxPriorityFeePerGas" "0x1")
          (cons "maxFeePerGas" "0xfa0"))
         (fixture-object-field dynamic-fee-calldata-vector "decoded")))
    (is (string= "0x5228"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-calldata-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-address-only-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field
                  dynamic-fee-address-only-access-list-vector
                  "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys" '())))
         (fixture-object-field
          dynamic-fee-address-only-access-list-vector
          "accessList")))
    (is (string= "0x5b68"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    dynamic-fee-address-only-access-list-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-vector "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-vector "accessList")))
    (is (string= "0x6a40"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-duplicate-access-list-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field
                  dynamic-fee-duplicate-access-list-vector
                  "type")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002")))
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"))))
         (fixture-object-field dynamic-fee-duplicate-access-list-vector
                               "accessList")))
    (is (string= "0x7b0c"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field
                    dynamic-fee-duplicate-access-list-vector
                    "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-calldata-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-calldata-vector "type")))
    (is (equal
         (list
          (cons "nonce" "0x8")
          (cons "gasLimit" "0xc350")
          (cons "to" "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
          (cons "value" "0xa")
          (cons "input" "0x5544")
          (cons "maxPriorityFeePerGas" "0x1")
          (cons "maxFeePerGas" "0xfa0"))
         (fixture-object-field dynamic-fee-access-list-calldata-vector "decoded")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-calldata-vector
                               "accessList")))
    (is (string= "0x6a60"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-calldata-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-contract-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-contract-vector "type")))
    (is (string= "0x91ffbaa0e407b3a8386fb0481ba4cb45693fa082"
                 (fixture-object-field dynamic-fee-contract-vector "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field dynamic-fee-contract-vector "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field dynamic-fee-contract-vector "decoded")
                  "input")))
    (is (string= "0xcf42"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-contract-vector "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is dynamic-fee-access-list-contract-vector)
    (is (string= "dynamic-fee"
                 (fixture-object-field dynamic-fee-access-list-contract-vector
                                       "type")))
    (is (string= "0x0db2f2d9790960138f1550ac55d8e5d1e60087ab"
                 (fixture-object-field dynamic-fee-access-list-contract-vector
                                       "contractAddress")))
    (is (null (fixture-object-field
               (fixture-object-field dynamic-fee-access-list-contract-vector
                                     "decoded")
               "to")))
    (is (string= "0x60006000f3"
                 (fixture-object-field
                  (fixture-object-field dynamic-fee-access-list-contract-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field dynamic-fee-access-list-contract-vector
                               "accessList")))
    (is (string= "0xe77a"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field dynamic-fee-access-list-contract-vector
                                         "result")
                   +phase-a-eest-transaction-target-fork+)
                  "intrinsicGas")))
    (is blob-vector)
    (is (string= "blob"
                 (fixture-object-field blob-vector "type")))
    (is blob-access-list-calldata-vector)
    (is (string= "blob"
                 (fixture-object-field blob-access-list-calldata-vector
                                       "type")))
    (is (string= "0xdeadbeef"
                 (fixture-object-field
                  (fixture-object-field blob-access-list-calldata-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field blob-access-list-calldata-vector
                               "accessList")))
    (is (string= "0x6a80"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field blob-access-list-calldata-vector
                                         "result")
                   "Cancun")
                  "intrinsicGas")))
    (is set-code-access-list-calldata-vector)
    (is (string= "set-code"
                 (fixture-object-field set-code-access-list-calldata-vector
                                       "type")))
    (is (string= "0xdeadbeef"
                 (fixture-object-field
                  (fixture-object-field set-code-access-list-calldata-vector
                                        "decoded")
                  "input")))
    (is (equal
         (list
          (list
           (cons "address" "0x0000000000000000000000000000000000000101")
           (cons "storageKeys"
                 '("0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000000000000000000000000000002"))))
         (fixture-object-field set-code-access-list-calldata-vector
                               "accessList")))
    (is (= 2
           (length
            (fixture-object-field
             (fixture-object-field set-code-access-list-calldata-vector
                                   "decoded")
             "authorizationList"))))
    (is (string= "0x12dd0"
                 (fixture-object-field
                  (fixture-object-field
                   (fixture-object-field set-code-access-list-calldata-vector
                                         "result")
                   "Prague")
                  "intrinsicGas")))
    (is set-code-vector)
    (is (string= "set-code"
                 (fixture-object-field set-code-vector "type")))
    (is (= 27 (fixture-object-field all-summary "count")))
    (is (equal '((:legacy . 5)
                 (:access-list . 8)
                 (:dynamic-fee . 10)
                 (:blob . 2)
                 (:set-code . 2))
               (fixture-object-field all-summary "types")))
    (is (= 27 (fixture-object-field all-summary "decodedVectorCount")))
    (is (= 27 (fixture-object-field all-summary "signatureVectorCount")))
    (is (= 12 (fixture-object-field all-summary "accessListVectorCount")))
    (is (= 5 (fixture-object-field all-summary "dynamicFeeAccessListVectorCount")))
    (is (= 2 (fixture-object-field all-summary "duplicateAccessListVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeDuplicateAccessListVectorCount")))
    (is (= 10 (fixture-object-field all-summary "typedEmptyAccessListVectorCount")))
    (is (= 3 (fixture-object-field all-summary "accessListEmptyAccessListVectorCount")))
    (is (= 5 (fixture-object-field all-summary "dynamicFeeEmptyAccessListVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListAddressOnlyVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAddressOnlyAccessListVectorCount")))
    (is (= 14 (fixture-object-field all-summary "accessListAddressCount")))
    (is (= 22 (fixture-object-field all-summary "accessListStorageKeyCount")))
    (is (= 7 (fixture-object-field all-summary "contractCreationVectorCount")))
    (is (= 7 (fixture-object-field all-summary "contractCreationAddressVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field all-summary "dynamicFeeContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAccessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field
              all-summary
              "emptyAccessListContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "accessListEmptyAccessListContractCreationVectorCount")))
    (is (= 2 (fixture-object-field
              all-summary
              "dynamicFeeEmptyAccessListContractCreationVectorCount")))
    (is (= 8 (fixture-object-field all-summary "messageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "legacyMessageCallDataVectorCount")))
    (is (= 6 (fixture-object-field all-summary "typedMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "accessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "dynamicFeeMessageCallDataVectorCount")))
    (is (= 4 (fixture-object-field all-summary "accessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeAccessListWithCallDataVectorCount")))
    (is (= 2 (fixture-object-field
              all-summary
              "emptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "accessListEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "dynamicFeeEqualFeeCapVectorCount")))
    (is (= 2 (fixture-object-field all-summary "blobVersionedHashVectorCount")))
    (is (= 4 (fixture-object-field all-summary "blobVersionedHashCount")))
    (is (= 1 (fixture-object-field all-summary "blobAccessListVectorCount")))
    (is (= 1 (fixture-object-field all-summary "blobMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field all-summary "setCodeAuthorizationVectorCount")))
    (is (= 4 (fixture-object-field all-summary "setCodeAuthorizationCount")))
    (is (= 1 (fixture-object-field all-summary "setCodeAccessListVectorCount")))
    (is (= 1 (fixture-object-field all-summary "setCodeMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              all-summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (is (= 3 (fixture-object-field all-summary "protectedLegacyVectorCount")))
    (is (= 2 (fixture-object-field all-summary "unprotectedLegacyVectorCount")))
    (is (= 169 (fixture-object-field all-summary "validResultCount")))
    (is (= 182 (fixture-object-field all-summary "exceptionResultCount")))
    (is (equal '(("Frontier" . 5)
                 ("Homestead" . 5)
                 ("EIP150" . 5)
                 ("EIP158" . 5)
                 ("Byzantium" . 5)
                 ("Constantinople" . 5)
                 ("Istanbul" . 5)
                 ("Berlin" . 13)
                 ("London" . 23)
                 ("Paris" . 23)
                 ("Shanghai" . 23)
                 ("Cancun" . 25)
                 ("Prague" . 27))
               (fixture-object-field all-summary "validForkCounts")))
    (is (equal '(("Frontier" . 22)
                 ("Homestead" . 22)
                 ("EIP150" . 22)
                 ("EIP158" . 22)
                 ("Byzantium" . 22)
                 ("Constantinople" . 22)
                 ("Istanbul" . 22)
                 ("Berlin" . 14)
                 ("London" . 4)
                 ("Paris" . 4)
                 ("Shanghai" . 4)
                 ("Cancun" . 2))
               (fixture-object-field all-summary "exceptionForkCounts")))
    (is (= 23 (fixture-object-field summary "count")))
    (is (equal '((:legacy . 5) (:access-list . 8) (:dynamic-fee . 10))
               (fixture-object-field summary "types")))
    (is (= 23 (fixture-object-field summary "decodedVectorCount")))
    (is (= 23 (fixture-object-field summary "signatureVectorCount")))
    (is (= 10 (fixture-object-field summary "accessListVectorCount")))
    (is (= 5 (fixture-object-field summary "dynamicFeeAccessListVectorCount")))
    (is (= 2 (fixture-object-field summary "duplicateAccessListVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeDuplicateAccessListVectorCount")))
    (is (= 8 (fixture-object-field summary "typedEmptyAccessListVectorCount")))
    (is (= 3 (fixture-object-field summary "accessListEmptyAccessListVectorCount")))
    (is (= 5 (fixture-object-field summary "dynamicFeeEmptyAccessListVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListAddressOnlyVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAddressOnlyAccessListVectorCount")))
    (is (= 12 (fixture-object-field summary "accessListAddressCount")))
    (is (= 18 (fixture-object-field summary "accessListStorageKeyCount")))
    (is (= 7 (fixture-object-field summary "contractCreationVectorCount")))
    (is (= 7 (fixture-object-field summary "contractCreationAddressVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field summary "dynamicFeeContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAccessListContractCreationVectorCount")))
    (is (= 3 (fixture-object-field
              summary
              "emptyAccessListContractCreationVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "accessListEmptyAccessListContractCreationVectorCount")))
    (is (= 2 (fixture-object-field
              summary
              "dynamicFeeEmptyAccessListContractCreationVectorCount")))
    (is (= 6 (fixture-object-field summary "messageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "legacyMessageCallDataVectorCount")))
    (is (= 4 (fixture-object-field summary "typedMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "dynamicFeeMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field summary "accessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeAccessListWithCallDataVectorCount")))
    (is (= 2 (fixture-object-field
              summary
              "emptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "accessListEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeEmptyAccessListWithCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              summary
              "dynamicFeeEqualFeeCapVectorCount")))
    (is (= 0 (fixture-object-field summary "blobVersionedHashVectorCount")))
    (is (= 0 (fixture-object-field summary "blobVersionedHashCount")))
    (is (= 0 (fixture-object-field summary "blobAccessListVectorCount")))
    (is (= 0 (fixture-object-field summary "blobMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field
              summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeAuthorizationVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeAuthorizationCount")))
    (is (= 0 (fixture-object-field summary "setCodeAccessListVectorCount")))
    (is (= 0 (fixture-object-field summary "setCodeMessageCallDataVectorCount")))
    (is (= 0 (fixture-object-field
              summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (is (= 3 (fixture-object-field summary "protectedLegacyVectorCount")))
    (is (= 2 (fixture-object-field summary "unprotectedLegacyVectorCount")))
    (is (= 163 (fixture-object-field summary "validResultCount")))
    (is (= 136 (fixture-object-field summary "exceptionResultCount")))
    (is (equal '(("Frontier" . 5)
                 ("Homestead" . 5)
                 ("EIP150" . 5)
                 ("EIP158" . 5)
                 ("Byzantium" . 5)
                 ("Constantinople" . 5)
                 ("Istanbul" . 5)
                 ("Berlin" . 13)
                 ("London" . 23)
                 ("Paris" . 23)
                 ("Shanghai" . 23)
                 ("Cancun" . 23)
                 ("Prague" . 23))
               (fixture-object-field summary "validForkCounts")))
    (is (equal '(("Frontier" . 18)
                 ("Homestead" . 18)
                 ("EIP150" . 18)
                 ("EIP158" . 18)
                 ("Byzantium" . 18)
                 ("Constantinople" . 18)
                 ("Istanbul" . 18)
                 ("Berlin" . 10))
               (fixture-object-field summary "exceptionForkCounts")))
    (is (equal '("phase-a-sample.json/legacy-eip155-sample"
                 "phase-a-sample.json/legacy-unprotected-sample"
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
                 "phase-a-sample.json/typed-eip1559-equal-fee-caps-sample"
                 "phase-a-sample.json/typed-eip1559-calldata-sample"
                 "phase-a-sample.json/typed-eip1559-address-only-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-duplicate-access-list-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-calldata-sample"
                 "phase-a-sample.json/typed-eip1559-contract-creation-sample"
                 "phase-a-sample.json/typed-eip1559-empty-access-list-contract-creation-sample"
                 "phase-a-sample.json/typed-eip1559-access-list-contract-creation-sample")
               (fixture-object-field summary "names")))
    (is (equal summary
               (validate-phase-a-eest-transaction-vector-summary
                selected-vectors)))
    (is (equal full-summary
               (validate-full-eest-transaction-vector-summary
                full-vectors)))
    (is (= 2 (fixture-object-field full-summary "blobVersionedHashVectorCount")))
    (is (= 4 (fixture-object-field full-summary "blobVersionedHashCount")))
    (is (= 1 (fixture-object-field full-summary "blobAccessListVectorCount")))
    (is (= 1 (fixture-object-field full-summary "blobMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              full-summary
              "blobAccessListMessageCallDataVectorCount")))
    (is (= 2 (fixture-object-field full-summary "setCodeAuthorizationVectorCount")))
    (is (= 4 (fixture-object-field full-summary "setCodeAuthorizationCount")))
    (is (= 1 (fixture-object-field full-summary "setCodeAccessListVectorCount")))
    (is (= 1 (fixture-object-field full-summary "setCodeMessageCallDataVectorCount")))
    (is (= 1 (fixture-object-field
              full-summary
              "setCodeAccessListMessageCallDataVectorCount")))
    (signals error
      (validate-transaction-fixture-result-count-summary
       selected-vectors
       (cons (cons "validResultCount" 0)
             (remove "validResultCount" summary :key #'car :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-result-count-summary
       full-vectors
       (cons (cons "exceptionForkCounts" nil)
             (remove "exceptionForkCounts"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (list (cons "accessListVectorCount" 0)
             (cons "dynamicFeeAccessListVectorCount" 0)
             (cons "duplicateAccessListVectorCount" 0)
             (cons "dynamicFeeDuplicateAccessListVectorCount" 0)
             (cons "typedEmptyAccessListVectorCount" 0)
             (cons "accessListEmptyAccessListVectorCount" 0)
             (cons "dynamicFeeEmptyAccessListVectorCount" 0)
             (cons "accessListAddressCount" 0)
             (cons "accessListAddressOnlyVectorCount" 0)
             (cons "dynamicFeeAddressOnlyAccessListVectorCount" 0)
             (cons "accessListStorageKeyCount" 0))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "accessListEmptyAccessListVectorCount" 0)
             (remove "accessListEmptyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeEmptyAccessListVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeAddressOnlyAccessListVectorCount" 0)
             (remove "dynamicFeeAddressOnlyAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-access-list-coverage
       (cons (cons "dynamicFeeDuplicateAccessListVectorCount" 0)
             (remove "dynamicFeeDuplicateAccessListVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "contractCreationVectorCount" 0)
             (remove "contractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "contractCreationAddressVectorCount" 0)
             (remove "contractCreationAddressVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeContractCreationVectorCount" 0)
             (remove "dynamicFeeContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeAccessListContractCreationVectorCount" 0)
             (remove "dynamicFeeAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "accessListContractCreationVectorCount" 0)
             (remove "accessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "emptyAccessListContractCreationVectorCount" 0)
             (remove "emptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "accessListEmptyAccessListContractCreationVectorCount" 0)
             (remove "accessListEmptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-contract-creation-coverage
       (cons (cons "dynamicFeeEmptyAccessListContractCreationVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListContractCreationVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "typedMessageCallDataVectorCount" 0)
             (remove "typedMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "legacyMessageCallDataVectorCount" 0)
             (remove "legacyMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListMessageCallDataVectorCount" 0)
             (remove "accessListMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeMessageCallDataVectorCount" 0)
             (remove "dynamicFeeMessageCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListWithCallDataVectorCount" 0)
             (remove "accessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeAccessListWithCallDataVectorCount" 0)
             (remove "dynamicFeeAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "emptyAccessListWithCallDataVectorCount" 0)
             (remove "emptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "accessListEmptyAccessListWithCallDataVectorCount" 0)
             (remove "accessListEmptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-input-coverage
       (cons (cons "dynamicFeeEmptyAccessListWithCallDataVectorCount" 0)
             (remove "dynamicFeeEmptyAccessListWithCallDataVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobVersionedHashVectorCount" 0)
             (remove "blobVersionedHashVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobVersionedHashCount" 0)
             (remove "blobVersionedHashCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobAccessListVectorCount" 0)
             (remove "blobAccessListVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobMessageCallDataVectorCount" 0)
             (remove "blobMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-blob-coverage
       (cons (cons "blobAccessListMessageCallDataVectorCount" 0)
             (remove "blobAccessListMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationVectorCount" 0)
             (remove "setCodeAuthorizationVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationCount" 0)
             (remove "setCodeAuthorizationCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAccessListVectorCount" 0)
             (remove "setCodeAccessListVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeMessageCallDataVectorCount" 0)
             (remove "setCodeMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAccessListMessageCallDataVectorCount" 0)
             (remove "setCodeAccessListMessageCallDataVectorCount"
                     full-summary
                     :key #'car
                     :test #'string=))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-set-code-coverage
       (cons (cons "setCodeAuthorizationCount" 1)
             (cons (cons "setCodeAuthorizationVectorCount" 1)
                   (remove "setCodeAuthorizationCount"
                           (remove "setCodeAuthorizationVectorCount"
                                   full-summary
                                   :key #'car
                                   :test #'string=)
                           :key #'car
                           :test #'string=)))
       "Full EEST transaction"))
    (signals error
      (validate-transaction-fixture-legacy-protection-coverage
       (cons (cons "unprotectedLegacyVectorCount" 0)
             (remove "unprotectedLegacyVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-decoded-coverage
       selected-vectors
       (cons (cons "decodedVectorCount" 0)
             (remove "decodedVectorCount" summary :key #'car :test #'string=))
       "Phase A EEST transaction"))
    (signals error
      (validate-transaction-fixture-signature-coverage
       selected-vectors
       (cons (cons "signatureVectorCount" 0)
             (remove "signatureVectorCount"
                     summary
                     :key #'car
                     :test #'string=))
       "Phase A EEST transaction"))
    (is (equal vectors
               (validate-eest-transaction-seed-alignment
                vectors
                seed-vectors)))
    (is (equal selected-vectors
               (validate-phase-a-eest-transaction-seed-alignment
                selected-vectors
                seed-vectors)))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-vector-field (vectors name field value)
               (mapcar
                (lambda (candidate)
                  (if (string= name (fixture-object-field candidate "name"))
                      (replace-field candidate field value)
                      candidate))
                vectors)))
      (signals error
        (validate-phase-a-eest-transaction-seed-alignment
         selected-vectors
         (replace-vector-field
          seed-vectors
          "eip1559-dynamic-fee"
          "decoded"
          (list (cons "nonce" "0xdead")))))
      (signals error
        (validate-phase-a-eest-transaction-seed-alignment
         selected-vectors
         (replace-vector-field
          seed-vectors
          "eip2930-access-list"
          "signature"
          (list (cons "r" "0xdead")))))
      (signals error
        (validate-eest-transaction-seed-alignment
         vectors
         (replace-vector-field
          seed-vectors
          "eip4844-blob"
          "decoded"
          (list (cons "nonce" "0xdead")))))
      (signals error
        (validate-eest-transaction-seed-alignment
         vectors
         (replace-vector-field
          seed-vectors
          "eip7702-set-code"
          "signature"
          (list (cons "r" "0xdead"))))))
    (signals error
      (transaction-fixture-vector-summary "phase-a-vectors"))
    (signals error
      (transaction-fixture-vector-summary (list "phase-a-vector")))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       (reverse selected-vectors)))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       "phase-a-vectors"))
    (signals error
      (validate-phase-a-eest-transaction-vector-summary
       (remove dynamic-fee-vector selected-vectors)))
    (signals error
      (validate-full-eest-transaction-vector-summary
       (remove set-code-vector full-vectors)))
    (signals error
      (validate-full-eest-transaction-vector-summary
       (reverse full-vectors)))
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
      (validate-phase-a-eest-transaction-seed-alignment
       selected-vectors
       (remove typed-vector seed-vectors
               :key (lambda (candidate)
                      (fixture-object-field candidate "txbytes"))
               :test #'string=)))
    (signals error
      (validate-eest-transaction-seed-alignment
       vectors
       (remove blob-vector seed-vectors
               :key (lambda (candidate)
                      (fixture-object-field candidate "txbytes"))
               :test #'string=)))
    (signals error
      (validate-eest-transaction-seed-alignment
       "eest-vectors"
       seed-vectors))
    (signals error
      (validate-eest-transaction-seed-alignment
       (append vectors (list (first vectors)))
       seed-vectors))
    (signals error
      (validate-phase-a-eest-transaction-seed-alignment
       "phase-a-vectors"
       seed-vectors))
    (signals error
      (validate-phase-a-eest-transaction-seed-alignment
       (append selected-vectors (list (first selected-vectors)))
       seed-vectors))
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
      (load-eest-transaction-test-root-file-cases
       "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/"
       (first paths)))
    (signals error
      (validate-transaction-fixture-vector-set
       (append vectors (list legacy-vector))))
    (signals error
      (validate-transaction-fixture-vector-set "phase-a-vectors"))
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
       :names "phase-a-sample.json"))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '(42)))
    (signals error
      (load-eest-transaction-test-root-cases
       root
       :names '("phase-a-sample.json" "phase-a-sample.json")))
    (signals error
      (filter-eest-transaction-test-root-cases
       (list
        (list (cons "name" "duplicate-source-name"))
        (list (cons "name" "duplicate-source-name")))
       nil))
    (signals error
      (filter-eest-transaction-test-root-cases cases "phase-a-sample.json"))
    (signals error
      (filter-eest-transaction-test-root-cases cases '("bare-case-name")))
    (validate-eest-transaction-selector-list
     +phase-a-eest-transaction-test-case-names+)
    (signals error
      (validate-eest-transaction-selector-list "phase-a-sample.json"))
    (signals error
      (validate-eest-transaction-selector-list nil))
    (signals error
      (validate-eest-transaction-selector-list '(42)))
    (signals error
      (validate-eest-transaction-selector-list '("")))
    (signals error
      (validate-eest-transaction-selector-list '("bare-case-name")))
    (signals error
      (validate-eest-transaction-selector-list '("../escape.json")))
    (signals error
      (validate-eest-transaction-selector-list '("/absolute.json")))
    (signals error
      (validate-eest-transaction-selector-list '("dir//case.json")))
    (signals error
      (validate-eest-transaction-selector-list '(".json/case")))
    (signals error
      (validate-eest-transaction-selector-list '("dir/.json/case")))
    (signals error
      (validate-eest-transaction-selector-list '("case.jsonx/name")))
    (signals error
      (validate-eest-transaction-selector-list '("case.json/")))
    (signals error
      (validate-eest-transaction-selector-list '("case.json//name")))
    (validate-eest-transaction-selector-list
     '("case.json/tests/prague/eip7702_set_code_tx/test_invalid_tx.py::test_case[fork_Prague-transaction_test]"))
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
  (let ((vectors (load-transaction-envelope-vectors
                  +transaction-envelope-fixture-path+)))
    (signals error
      (validate-transaction-envelope-vector-coverage
       (remove "eip4844-blob"
               vectors
               :test #'string=
               :key (lambda (candidate)
                      (fixture-object-field candidate "name")))))
    (assert-transaction-fixture-vectors-replay vectors)))
