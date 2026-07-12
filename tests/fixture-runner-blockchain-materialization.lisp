(in-package #:ethereum-lisp.test)

(defun report-eest-blockchain-test-root-case (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "format"
                (or (fixture-object-field fixture "fixture-format")
                    "blockchain_test"))
          (cons "network" (fixture-object-field fixture "network"))
          (cons "blocks" (length (fixture-object-field fixture "blocks"))))))

(defun validate-eest-blockchain-json-array-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (listp value)
      (error "~A ~A must be a JSON array" label field))
    value))

(defun validate-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (unless (fixture-field-present-p fixture "engineNewPayloadV2")
      (error "~A does not carry an embedded engineNewPayloadV2 case"
             label))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-engine-fixture-fields+
     label)
    (unless (string= "blockchain_test"
                     (fixture-required-field fixture "fixture-format"))
      (error "~A fixture-format must be blockchain_test" label))
    (validate-eest-blockchain-json-array-field fixture "blocks" label)
    (when (plusp (length (fixture-object-field fixture "blocks")))
      (error "~A replay materializer expects an embedded engineNewPayloadV2 case"
             label))
    (let ((engine (fixture-required-field fixture "engineNewPayloadV2")))
      (validate-fixture-object-fields
       engine
       +eest-blockchain-engine-newpayload-v2-fields+
       (format nil "~A engineNewPayloadV2" label))
      (dolist (field +eest-blockchain-engine-newpayload-v2-fields+)
        (fixture-required-field engine field))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "parent")
       "accounts"
       (format nil "~A parent" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "transactions"
       (format nil "~A payload" label))
      (validate-eest-blockchain-json-array-field
       (fixture-required-field engine "payload")
       "withdrawals"
       (format nil "~A payload" label))
      engine)))

(defun eest-blockchain-engine-newpayloads-v2-entry (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (entries (fixture-object-field fixture "engineNewPayloads")))
    (when (listp entries)
      (find "2" entries
            :key (lambda (entry)
                   (and (listp entry)
                        (fixture-object-field entry "newPayloadVersion")))
            :test #'string=))))

(defun validate-eest-blockchain-engine-newpayloads-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-engine-newpayloads-fixture-fields+
     label)
    (unless (string= "Shanghai" (fixture-required-field fixture "network"))
      (error "~A engineNewPayloads materializer currently supports Shanghai V2"
             label))
    (let ((entries (fixture-required-field fixture "engineNewPayloads")))
      (unless (and (listp entries) entries)
        (error "~A engineNewPayloads must be a non-empty JSON array" label))
      (let ((entry (eest-blockchain-engine-newpayloads-v2-entry case)))
        (unless entry
          (error "~A does not carry an engineNewPayloads V2 entry" label))
        (validate-fixture-object-fields
         entry
         +eest-blockchain-engine-newpayloads-entry-fields+
         (format nil "~A engineNewPayloads entry" label))
        (unless (string= "2" (fixture-required-field entry "newPayloadVersion"))
          (error "~A engineNewPayloads entry must be V2" label))
        (unless (string= "2" (fixture-required-field entry "forkchoiceUpdatedVersion"))
          (error "~A forkchoiceUpdatedVersion must be V2" label))
        (let ((params (fixture-required-field entry "params")))
          (unless (and (listp params) (= 1 (length params)))
            (error "~A engineNewPayloads V2 params must contain one payload"
                   label))
          (let ((payload (first params)))
            (unless (listp payload)
              (error "~A engineNewPayloads V2 payload must be a JSON object"
                     label))
            (validate-fixture-object-fields
             payload
             +eest-blockchain-rpc-payload-v2-fields+
             (format nil "~A engineNewPayloads V2 payload" label))
            (dolist (field '("parentHash" "stateRoot" "receiptsRoot"
                             "prevRandao" "blockHash"))
              (validate-eest-blockchain-hash-string
               (fixture-required-field payload field)
               (format nil "~A payload ~A" label field)))
            (validate-eest-blockchain-address-string
             (fixture-required-field payload "feeRecipient")
             (format nil "~A payload feeRecipient" label))
            (dolist (field '("blockNumber" "gasLimit" "gasUsed" "timestamp"
                             "baseFeePerGas"))
              (validate-eest-blockchain-quantity-string
               (fixture-required-field payload field)
               (format nil "~A payload ~A" label field)))
            (validate-eest-blockchain-hex-string
             (fixture-required-field payload "extraData")
             (format nil "~A payload extraData" label))
            (validate-eest-blockchain-json-array-field
             payload
             "transactions"
             (format nil "~A payload" label))
            (validate-eest-blockchain-json-array-field
             payload
             "withdrawals"
             (format nil "~A payload" label))
            (let ((last-block-hash
                    (fixture-required-field fixture "lastblockhash"))
                  (block-hash (fixture-required-field payload "blockHash")))
              (validate-eest-blockchain-hash-string
               last-block-hash
               (format nil "~A lastblockhash" label))
              (unless (string= last-block-hash block-hash)
                (error "~A lastblockhash does not match engine payload blockHash"
                       label)))
            payload))))))

(defun validate-eest-blockchain-hex-string (value label)
  (unless (stringp value)
    (error "~A must be a 0x-prefixed hex string" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (string= value (bytes-to-hex bytes))
          (error "~A must be canonical lowercase 0x-prefixed hex" label))
        value)
    (error (condition)
      (error "~A must be hex bytes: ~A" label condition))))

(defun validate-eest-blockchain-hash-string (value label)
  (validate-eest-blockchain-hex-string value label)
  (handler-case
      (hash32-from-hex value)
    (error (condition)
      (error "~A must be a 32-byte hash: ~A" label condition))))

(defun validate-eest-blockchain-address-string (value label)
  (validate-eest-blockchain-hex-string value label)
  (handler-case
      (address-from-hex value)
    (error (condition)
      (error "~A must be a 20-byte address: ~A" label condition))))

(defun validate-eest-blockchain-quantity-string (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (handler-case
      (hex-to-quantity value)
    (error (condition)
      (error "~A must be a hex quantity: ~A" label condition))))

(defun eest-blockchain-standard-required-header-field (header field label)
  (let ((value (fixture-required-field header field)))
    (validate-eest-blockchain-quantity-string
     value
     (format nil "~A ~A" label field))
    value))

(defun eest-blockchain-standard-required-address-field (header field label)
  (let ((value (fixture-required-field header field)))
    (validate-eest-blockchain-address-string
     value
     (format nil "~A ~A" label field))
    value))

(defun eest-blockchain-standard-account-entry (entry label)
  (let ((address (car entry))
        (account (cdr entry)))
    (validate-eest-blockchain-address-string
     address
     (format nil "~A pre account address" label))
    (unless (fixture-json-object-p account)
      (error "~A pre account ~A must be a JSON object" label address))
    (let ((storage (or (fixture-object-field account "storage") '())))
      (unless (fixture-json-object-p storage)
        (error "~A pre account ~A storage must be a JSON object"
               label address))
      (list
       (cons "address" address)
       (cons "nonce"
             (quantity-to-hex
              (hex-to-quantity
               (or (fixture-object-field account "nonce") "0x0"))))
       (cons "balance"
             (quantity-to-hex
              (hex-to-quantity
               (or (fixture-object-field account "balance") "0x0"))))
       (cons "code"
             (or (fixture-object-field account "code") "0x"))
       (cons "storage"
             (mapcar (lambda (storage-entry)
                       (cons
                        (eest-blockchain-normalized-storage-slot
                         (car storage-entry)
                         (format nil "~A pre account ~A storage key"
                                 label
                                 address))
                        (quantity-to-hex
                         (hex-to-quantity (cdr storage-entry)))))
                     (ethereum-lisp.json:json-object-entries
                      storage
                      (format nil "~A pre account ~A storage" label address))))))))

(defun eest-blockchain-normalized-storage-slot (value label)
  (unless (stringp value)
    (error "~A must be a hex storage key" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (when (> (length bytes) 32)
          (error "~A must be at most 32 bytes" label))
        (let ((padded (make-byte-vector 32)))
          (replace padded bytes :start1 (- 32 (length bytes)))
          (hash32-to-hex (make-hash32 padded))))
    (error (condition)
      (error "~A must be hex storage key bytes: ~A" label condition))))

(defun eest-blockchain-standard-parent (fixture label)
  (let ((header (fixture-required-field fixture "genesisBlockHeader")))
    (unless (listp header)
      (error "~A genesisBlockHeader must be a JSON object" label))
    (list
     (cons "number"
           (eest-blockchain-standard-required-header-field
            header "number" label))
     (cons "gasLimit"
           (eest-blockchain-standard-required-header-field
            header "gasLimit" label))
     (cons "gasUsed"
           (eest-blockchain-standard-required-header-field
            header "gasUsed" label))
     (cons "timestamp"
           (eest-blockchain-standard-required-header-field
            header "timestamp" label))
     (cons "baseFeePerGas"
           (eest-blockchain-standard-required-header-field
            header "baseFeePerGas" label))
     (cons "feeRecipient"
           (eest-blockchain-standard-required-address-field
            header "coinbase" label))
     (cons "accounts"
           (mapcar
            (lambda (entry)
              (eest-blockchain-standard-account-entry entry label))
            (sort (copy-list (fixture-required-field fixture "pre"))
                  #'string<
                  :key #'car))))))

(defun eest-blockchain-standard-withdrawal (withdrawal)
  (list (cons "index" (quantity-to-hex (withdrawal-index withdrawal)))
        (cons "validatorIndex"
              (quantity-to-hex (withdrawal-validator-index withdrawal)))
        (cons "address" (address-to-hex (withdrawal-address withdrawal)))
        (cons "amount" (quantity-to-hex (withdrawal-amount withdrawal)))))

(defun eest-blockchain-standard-payload (block)
  (let ((header (block-header block)))
    (list
     (cons "number" (quantity-to-hex (block-header-number header)))
     (cons "gasLimit" (quantity-to-hex (block-header-gas-limit header)))
     (cons "timestamp" (quantity-to-hex (block-header-timestamp header)))
     (cons "baseFeePerGas"
           (quantity-to-hex (or (block-header-base-fee-per-gas header) 0)))
     (cons "transactions"
           (mapcar (lambda (transaction)
                     (bytes-to-hex (transaction-encoding transaction)))
                   (block-transactions block)))
     (cons "withdrawals"
           (mapcar #'eest-blockchain-standard-withdrawal
                   (or (block-withdrawals block) '()))))))

(defun eest-blockchain-standard-expect (block)
  (let ((header (block-header block)))
    (list (cons "status" "VALID")
          (cons "stateRoot" (hash32-to-hex (block-header-state-root header)))
          (cons "receiptsRoot"
                (hash32-to-hex (block-header-receipts-root header)))
          (cons "gasUsed" (quantity-to-hex (block-header-gas-used header))))))

(defun validate-eest-blockchain-standard-newpayload-v2-case (case)
  (let* ((case-name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (label (format nil "EEST blockchain case ~A" case-name)))
    (validate-fixture-object-fields
     fixture
     +eest-blockchain-standard-fixture-fields+
     label)
    (unless (string= "Shanghai" (fixture-required-field fixture "network"))
      (error "~A standard replay materializer currently supports Shanghai"
             label))
    (let ((blocks (validate-eest-blockchain-json-array-field
                   fixture
                   "blocks"
                   label)))
      (unless (= 1 (length blocks))
        (error "~A standard replay materializer expects exactly one block"
               label))
      (let ((block-case (first blocks)))
        (validate-fixture-object-fields
         block-case
         +eest-blockchain-standard-block-fields+
         (format nil "~A block" label))
        (when (fixture-field-present-p block-case "expectException")
          (error "~A standard replay materializer expects a valid block"
                 label))
        (validate-eest-blockchain-hex-string
         (fixture-required-field block-case "rlp")
         (format nil "~A block rlp" label))
        (let* ((block (block-from-rlp
                       (hex-to-bytes
                        (fixture-required-field block-case "rlp"))))
               (block-hash (hash32-to-hex (block-hash block)))
               (last-block-hash
                 (fixture-required-field fixture "lastblockhash")))
          (validate-eest-blockchain-hash-string
           last-block-hash
           (format nil "~A lastblockhash" label))
          (unless (string= last-block-hash block-hash)
            (error "~A lastblockhash does not match decoded block hash"
                   label))
          (when (fixture-field-present-p block-case "blockHeader")
            (let ((header-hash
                    (fixture-object-field
                     (fixture-object-field block-case "blockHeader")
                     "hash")))
              (when header-hash
                (validate-eest-blockchain-hash-string
                 header-hash
                 (format nil "~A blockHeader hash" label))
                (unless (string= header-hash block-hash)
                  (error "~A blockHeader hash does not match decoded block"
                         label)))))
          block)))))

(defun materialize-eest-blockchain-standard-newpayload-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (block (validate-eest-blockchain-standard-newpayload-v2-case case)))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "network" (fixture-required-field fixture "network"))
          (cons "chainId" "0x1")
          (cons "config"
                '(("berlinBlock" . "0x0")
                  ("londonBlock" . "0x0")
                  ("shanghaiTime" . "0x0")))
          (cons "parent"
                (eest-blockchain-standard-parent
                 fixture
                 (format nil "EEST blockchain case ~A"
                         (fixture-required-field case "name"))))
          (cons "payload" (eest-blockchain-standard-payload block))
          (cons "expect" (eest-blockchain-standard-expect block)))))

(defun materialize-eest-blockchain-engine-newpayload-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture")))
    (if (fixture-field-present-p fixture "engineNewPayloadV2")
        (let ((engine (validate-eest-blockchain-engine-newpayload-v2-case
                       case)))
          (list (cons "name" (fixture-required-field case "name"))
                (cons "network" (fixture-required-field fixture "network"))
                (cons "chainId" (fixture-required-field engine "chainId"))
                (cons "config" (fixture-required-field engine "config"))
                (cons "parent" (fixture-required-field engine "parent"))
                (cons "payload" (fixture-required-field engine "payload"))
                (cons "expect" (fixture-required-field engine "expect"))))
        (if (fixture-field-present-p fixture "engineNewPayloads")
            (materialize-eest-blockchain-engine-newpayloads-v2-case case)
            (materialize-eest-blockchain-standard-newpayload-v2-case case)))))

(defun materialize-eest-blockchain-engine-newpayloads-v2-case (case)
  (let* ((fixture (fixture-required-field case "fixture"))
         (payload
           (validate-eest-blockchain-engine-newpayloads-v2-case case)))
    (list (cons "name" (fixture-required-field case "name"))
          (cons "network" (fixture-required-field fixture "network"))
          (cons "chainId"
                (quantity-to-hex
                 (hex-to-quantity
                  (or (fixture-object-field
                       (fixture-object-field fixture "config")
                       "chainid")
                      "0x1"))))
          (cons "config"
                '(("berlinBlock" . "0x0")
                  ("londonBlock" . "0x0")
                  ("shanghaiTime" . "0x0")))
          (cons "parent"
                (mapcar
                 (lambda (entry)
                   (if (string= "feeRecipient" (car entry))
                       (cons "feeRecipient"
                             (fixture-required-field payload "feeRecipient"))
                       entry))
                 (eest-blockchain-standard-parent
                  fixture
                  (format nil "EEST blockchain case ~A"
                          (fixture-required-field case "name")))))
          (cons "payload"
                (list
                 (cons "number"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "blockNumber"))))
                 (cons "gasLimit"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "gasLimit"))))
                 (cons "timestamp"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "timestamp"))))
                 (cons "baseFeePerGas"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "baseFeePerGas"))))
                 (cons "transactions"
                       (fixture-required-field payload "transactions"))
                 (cons "withdrawals"
                       (fixture-required-field payload "withdrawals"))))
          (cons "expect"
                (list
                 (cons "status" "VALID")
                 (cons "stateRoot"
                       (fixture-required-field payload "stateRoot"))
                 (cons "receiptsRoot"
                       (fixture-required-field payload "receiptsRoot"))
                 (cons "gasUsed"
                       (quantity-to-hex
                        (hex-to-quantity
                         (fixture-required-field payload "gasUsed")))))))))

(defun load-handwritten-fixture-file (path)
  (parse-json (fixture-file-string path)))

(defun handwritten-fixture-cases (fixture)
  (let ((cases (fixture-object-field fixture "cases")))
    (unless (listp cases)
      (error "Fixture cases must be a JSON array"))
    cases))

(defun select-handwritten-fixture-case (fixture name)
  (find name (handwritten-fixture-cases fixture)
        :key (lambda (case)
               (fixture-object-field case "name"))
        :test #'string=))

(defun report-handwritten-fixture-case (fixture case path)
  (list (cons "format" (fixture-object-field fixture "format"))
        (cons "name" (fixture-object-field case "name"))
        (cons "network" (fixture-object-field case "network"))
        (cons "source" path)
        (cons "blocks" (length (fixture-object-field case "blocks")))
        (cons "status"
              (fixture-object-field
               (fixture-object-field case "expect")
               "status"))))

(defun run-handwritten-fixture-case (path name)
  (let* ((fixture (load-handwritten-fixture-file path))
         (case (select-handwritten-fixture-case fixture name)))
    (unless case
      (error "Fixture case not found: ~A" name))
    (report-handwritten-fixture-case fixture case path)))
