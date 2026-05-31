(in-package #:ethereum-lisp.test)

(defparameter +minimal-blockchain-fixture-path+
  "tests/fixtures/execution-spec-tests/minimal-blockchain.json")

(defparameter +eest-blockchain-engine-fixture-fields+
  '("fixture-format" "network" "blocks" "engineNewPayloadV2"))

(defparameter +eest-blockchain-engine-newpayload-v2-fields+
  '("chainId" "config" "parent" "payload" "expect"))

(defparameter +eest-blockchain-standard-fixture-fields+
  '("network" "genesisBlockHeader" "pre" "postState" "lastblockhash"
    "sealEngine" "blocks"))

(defparameter +eest-blockchain-standard-block-fields+
  '("rlp" "blockHeader" "expectException" "uncleHeaders"))

(defparameter +phase-a-eest-blockchain-replay-materialization-kinds+
  '(("shanghai/phase-a-empty-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-empty-standard.json" . "blockRlp")))

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

(defun validate-eest-blockchain-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST blockchain test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST blockchain test case name in ~A must be a string"
                 source))
        (when (blank-string-p name)
          (error "EEST blockchain test case name in ~A must be present"
                 source))
        (when (gethash name seen)
          (error "EEST blockchain test file ~A has duplicate case name ~A"
                 source name))
        (unless (listp case)
          (error "EEST blockchain test case ~A must be a JSON object"
                 name))
        (setf (gethash name seen) t)))))

(defun normalize-eest-blockchain-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun eest-blockchain-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun load-eest-blockchain-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-blockchain-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-blockchain-root-case-name
                  root
                  path
                  (car entry)
                  singleton-p)))
           (unless (eest-blockchain-selector-source-style-p source-name)
             (error "EEST blockchain source name ~A must be source-style"
                    source-name))
           (normalize-eest-blockchain-test-case source-name (cdr entry))))
       entries))))

(defun validate-eest-blockchain-selector-list (names)
  (validate-execution-spec-tests-selector-list names "EEST blockchain"))

(defun eest-blockchain-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p name))

(defun load-eest-blockchain-test-root-cases (root &key names)
  (when names
    (validate-eest-blockchain-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (eest-blockchain-test-root-json-paths root)
         append (load-eest-blockchain-test-root-file-cases root path))
   names
   "EEST blockchain test"))

(defun eest-blockchain-replay-materialization-kind (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (cond
      ((fixture-field-present-p fixture "engineNewPayloadV2")
       "engineNewPayloadV2")
      ((let ((blocks (fixture-object-field fixture "blocks")))
         (and (listp blocks)
              blocks
              (fixture-field-present-p (first blocks) "rlp")))
       "blockRlp")
      (t
       "unsupported"))))

(defun eest-blockchain-count-by-string (values)
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (value values)
      (unless (stringp value)
        (error "EEST blockchain replay summary value must be a string"))
      (incf (gethash value counts 0)))
    (sort
     (loop for key being the hash-keys of counts
           using (hash-value count)
           collect (cons key count))
     #'string<
     :key #'car)))

(defun eest-blockchain-replay-block-count (case)
  (let ((blocks (fixture-object-field
                 (fixture-required-field case "fixture")
                 "blocks")))
    (unless (listp blocks)
      (error "EEST blockchain replay case ~A blocks must be a JSON array"
             (fixture-required-field case "name")))
    (length blocks)))

(defun eest-blockchain-replay-case-summary (cases)
  (list (cons "count" (length cases))
        (cons "names" (mapcar (lambda (case)
                                (fixture-required-field case "name"))
                              cases))
        (cons "networkCounts"
              (eest-blockchain-count-by-string
               (mapcar (lambda (case)
                         (fixture-required-field
                          (fixture-required-field case "fixture")
                          "network"))
                       cases)))
        (cons "materializationKindCounts"
              (eest-blockchain-count-by-string
               (mapcar #'eest-blockchain-replay-materialization-kind cases)))
        (cons "blockCount"
              (loop for case in cases
                    sum (eest-blockchain-replay-block-count case)))))

(defun validate-phase-a-eest-blockchain-replay-summary
    (cases &key
           (expected-kinds
            +phase-a-eest-blockchain-replay-materialization-kinds+))
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (unless (and (listp cases) cases)
    (error "Phase A EEST blockchain replay cases must be a non-empty list"))
  (let* ((summary (eest-blockchain-replay-case-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (network-counts (fixture-required-field summary "networkCounts"))
         (kind-counts
           (fixture-required-field summary "materializationKindCounts"))
         (block-count (fixture-required-field summary "blockCount")))
    (unless (= count (length expected-kinds))
      (error "Phase A EEST blockchain replay selector count ~A loaded ~A cases"
             (length expected-kinds)
             count))
    (unless (equal names (mapcar #'car expected-kinds))
      (error "Phase A EEST blockchain replay names ~S do not match selectors ~S"
             names
             (mapcar #'car expected-kinds)))
    (dolist (expected expected-kinds)
      (let* ((name (car expected))
             (kind (cdr expected))
             (case (find name cases
                         :key (lambda (entry)
                                (fixture-required-field entry "name"))
                         :test #'string=)))
        (unless case
          (error "Phase A EEST blockchain replay selector ~A was not loaded"
                 name))
        (unless (string= kind (eest-blockchain-replay-materialization-kind case))
          (error "Phase A EEST blockchain replay selector ~A expected ~A but found ~A"
                 name
                 kind
                 (eest-blockchain-replay-materialization-kind case)))))
    (unless (= count (or (fixture-object-field network-counts "Shanghai") 0))
      (error "Phase A EEST blockchain replay must load only Shanghai cases"))
    (unless (plusp (or (fixture-object-field kind-counts "engineNewPayloadV2")
                       0))
      (error "Phase A EEST blockchain replay is missing embedded Engine coverage"))
    (unless (plusp (or (fixture-object-field kind-counts "blockRlp") 0))
      (error "Phase A EEST blockchain replay is missing standard block RLP coverage"))
    (unless (plusp block-count)
      (error "Phase A EEST blockchain replay is missing decoded block coverage"))
    summary))

(defun load-phase-a-eest-blockchain-replay-cases (root)
  (let ((cases (load-eest-blockchain-test-root-cases
                root
                :names (mapcar
                        #'car
                        +phase-a-eest-blockchain-replay-materialization-kinds+))))
    (validate-phase-a-eest-blockchain-replay-summary cases)
    cases))

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
    (unless (listp account)
      (error "~A pre account ~A must be a JSON object" label address))
    (let ((storage (or (fixture-object-field account "storage") '())))
      (unless (listp storage)
        (error "~A pre account ~A storage must be a JSON object"
               label address))
      (list
       (cons "address" address)
       (cons "nonce"
             (or (fixture-object-field account "nonce") "0x0"))
       (cons "balance"
             (or (fixture-object-field account "balance") "0x0"))
       (cons "code"
             (or (fixture-object-field account "code") "0x"))
       (cons "storage" storage)))))

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
        (materialize-eest-blockchain-standard-newpayload-v2-case case))))

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

(deftest handwritten-fixture-runner-selects-and-reports-case
  (let ((report
          (run-handwritten-fixture-case
           +minimal-blockchain-fixture-path+
           "empty-shanghai-blockchain-smoke")))
    (is (string= "ethereum-lisp/minimal-blockchain-fixture-v1"
                 (fixture-object-field report "format")))
    (is (string= "empty-shanghai-blockchain-smoke"
                 (fixture-object-field report "name")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (is (string= "valid" (fixture-object-field report "status")))))

(deftest handwritten-fixture-runner-rejects-missing-case
  (signals error
    (run-handwritten-fixture-case
     +minimal-blockchain-fixture-path+
     "missing-case")))

(deftest eest-blockchain-test-root-json-discovery
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-blockchain-test-root-json-paths root)))
    (is (= 2 (length paths)))
    (is (equal '("shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json")
               (eest-blockchain-test-root-file-names root)))))

(deftest eest-blockchain-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-blockchain-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-blockchain-test-root-json-paths root))))

(deftest eest-blockchain-test-root-case-loading
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-blockchain-test-root-cases root))
         (phase-a-cases (load-phase-a-eest-blockchain-replay-cases root))
         (summary
           (validate-phase-a-eest-blockchain-replay-summary phase-a-cases))
         (selected (load-eest-blockchain-test-root-cases
                    root
                    :names '("shanghai/phase-a-empty-engine.json")))
         (standard (first
                    (load-eest-blockchain-test-root-cases
                     root
                     :names '("shanghai/phase-a-empty-standard.json"))))
         (report (report-eest-blockchain-test-root-case (first selected))))
    (is (= 2 (length cases)))
    (is (= 2 (length phase-a-cases)))
    (is (= 2 (fixture-object-field summary "count")))
    (is (equal '("shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json")
               (fixture-object-field summary "names")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "blockRlp")))
    (is (= 2 (fixture-object-field
              (fixture-object-field summary "networkCounts")
              "Shanghai")))
    (is (= 1 (fixture-object-field summary "blockCount")))
    (is (= 1 (length selected)))
    (is (string= "shanghai/phase-a-empty-engine.json"
                 (fixture-object-field report "name")))
    (is (string= "blockchain_test" (fixture-object-field report "format")))
    (is (string= "Shanghai" (fixture-object-field report "network")))
    (is (= 0 (fixture-object-field report "blocks")))
    (let ((materialized
            (materialize-eest-blockchain-engine-newpayload-v2-case
             (first selected))))
      (is (string= "shanghai/phase-a-empty-engine.json"
                   (fixture-object-field materialized "name")))
      (is (string= "VALID"
                   (fixture-object-field
                    (fixture-object-field materialized "expect")
                    "status"))))
    (let ((materialized
            (materialize-eest-blockchain-engine-newpayload-v2-case
             standard)))
      (is (string= "shanghai/phase-a-empty-standard.json"
                   (fixture-object-field materialized "name")))
      (is (= 0 (length (fixture-object-field
                        (fixture-object-field materialized "payload")
                        "transactions"))))
      (is (string= "0x2a"
                   (fixture-object-field
                    (fixture-object-field materialized "payload")
                    "number")))
      (is (string= "VALID"
                   (fixture-object-field
                    (fixture-object-field materialized "expect")
                    "status"))))
    (signals error
      (load-eest-blockchain-test-root-cases
       root
       :names '("missing.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("shanghai/phase-a-empty-engine.json"
         "shanghai/phase-a-empty-engine.json")))
    (signals error
      (validate-eest-blockchain-selector-list
       '("phase-a-empty-engine.json/case/extra")))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary nil))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       (list (first phase-a-cases))))
    (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       phase-a-cases
       :expected-kinds
       '(("shanghai/phase-a-empty-engine.json" . "blockRlp")
         ("shanghai/phase-a-empty-standard.json" . "engineNewPayloadV2"))))
    (let* ((bad-case (copy-tree (first phase-a-cases)))
           (bad-fixture (fixture-required-field bad-case "fixture")))
      (setf (cdr (assoc "network" bad-fixture :test #'string=)) "Cancun")
      (signals error
        (validate-phase-a-eest-blockchain-replay-summary
         (list bad-case (second phase-a-cases)))))))
