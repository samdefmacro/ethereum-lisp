(in-package #:ethereum-lisp.test)

(defparameter +minimal-blockchain-fixture-path+
  "tests/fixtures/execution-spec-tests/minimal-blockchain.json")

(defparameter +eest-blockchain-engine-fixture-fields+
  '("fixture-format" "network" "blocks" "engineNewPayloadV2"))

(defparameter +eest-blockchain-engine-newpayload-v2-fields+
  '("chainId" "config" "parent" "payload" "expect"))

(defparameter +eest-blockchain-engine-newpayloads-fixture-fields+
  '("network" "lastblockhash" "config" "pre" "postState"
    "genesisBlockHeader" "engineNewPayloads" "_info"))

(defparameter +eest-blockchain-engine-newpayloads-entry-fields+
  '("params" "newPayloadVersion" "forkchoiceUpdatedVersion"))

(defparameter +eest-blockchain-rpc-payload-v2-fields+
  '("parentHash" "feeRecipient" "stateRoot" "receiptsRoot" "logsBloom"
    "blockNumber" "gasLimit" "gasUsed" "timestamp" "extraData"
    "prevRandao" "baseFeePerGas" "blockHash" "transactions" "withdrawals"))

(defparameter +eest-blockchain-standard-fixture-fields+
  '("network" "genesisBlockHeader" "pre" "postState" "lastblockhash"
    "sealEngine" "blocks"))

(defparameter +eest-blockchain-standard-block-fields+
  '("rlp" "blockHeader" "expectException" "uncleHeaders"))

(defparameter +eest-state-test-case-fields+
  '("env" "pre" "transaction" "post" "_info"))

(defparameter +eest-state-test-transaction-fields+
  '("data" "gasLimit" "gasPrice" "nonce" "to" "value" "secretKey"
    "accessLists" "maxFeePerGas" "maxPriorityFeePerGas"))

(defconstant +phase-a-eest-state-test-selectors-env+
  "ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS")

(defconstant +phase-a-eest-state-test-auto-selector+ "auto")

(defparameter +phase-a-eest-state-test-case-names+
  '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
    "london/phase-a-state-sample.json/phase_a_london_dynamic_fee_state_sample"
    "london/phase-a-state-sample.json/phase_a_london_state_sample"
    "shanghai/phase-a-state-sample.json"))

(defparameter +phase-a-eest-state-test-supported-forks+
  '("London" "Shanghai"))

(defconstant +phase-a-eest-blockchain-replay-selectors-env+
  "ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS")

(defconstant +phase-a-eest-blockchain-replay-auto-selector+ "auto")

(defconstant +phase-a-eest-blockchain-replay-pinned-selector+
  "pinned-v5.4.0")

(defparameter +phase-a-eest-blockchain-replay-materialization-kind-names+
  '("engineNewPayloadV2" "blockRlp"))

(defparameter +phase-a-eest-blockchain-replay-materialization-kinds+
  '(("shanghai/phase-a-access-list-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-dynamic-fee-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-empty-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-empty-standard.json" . "blockRlp")
    ("shanghai/phase-a-log-contract-engine.json" . "engineNewPayloadV2")
    ("shanghai/phase-a-transfer-engine.json" . "engineNewPayloadV2")))

(defparameter +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+
  '(("berlin/eip2930_access_list/test_eip2930_tx_validity.json/tests/berlin/eip2930_access_list/test_tx_type.py::test_eip2930_tx_validity[fork_Shanghai-valid-blockchain_test_engine_from_state_test]"
     . "engineNewPayloadV2")))

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

(defun eest-state-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST state test"))

(defun eest-state-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST state test"))

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

(defun validate-eest-state-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST state test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST state test case name in ~A must be a string" source))
        (when (blank-string-p name)
          (error "EEST state test case name in ~A must be present" source))
        (when (gethash name seen)
          (error "EEST state test file ~A has duplicate case name ~A"
                 source
                 name))
        (unless (listp case)
          (error "EEST state test case ~A must be a JSON object" name))
        (validate-fixture-object-fields
         case
         +eest-state-test-case-fields+
         (format nil "EEST state test case ~A" name))
        (dolist (field '("env" "pre" "transaction" "post"))
          (fixture-required-field case field))
        (setf (gethash name seen) t)))))

(defun normalize-eest-blockchain-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun normalize-eest-state-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun eest-blockchain-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun eest-state-root-case-name (root path key singleton-p)
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

(defun load-eest-state-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-state-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-state-root-case-name root path (car entry) singleton-p)))
           (unless (eest-state-selector-source-style-p source-name)
             (error "EEST state source name ~A must be source-style"
                    source-name))
           (normalize-eest-state-test-case source-name (cdr entry))))
       entries))))

(defun validate-eest-blockchain-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST blockchain"
   :allow-nested-case-name t))

(defun validate-eest-state-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST state"
   :allow-nested-case-name t))

(defun eest-blockchain-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun eest-state-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun load-eest-blockchain-test-root-cases (root &key names)
  (when names
    (validate-eest-blockchain-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (eest-blockchain-test-root-json-paths root)
         append (load-eest-blockchain-test-root-file-cases root path))
   names
   "EEST blockchain test"))

(defun load-eest-state-test-root-cases (root &key names)
  (when names
    (validate-eest-state-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (eest-state-test-root-json-paths root)
         append (load-eest-state-test-root-file-cases root path))
   names
   "EEST state test"))

(defun eest-state-test-case-fork-names (case)
  (let ((post (fixture-required-field
               (fixture-required-field case "fixture")
               "post")))
    (unless (listp post)
      (error "EEST state test case ~A post must be a JSON object"
             (fixture-required-field case "name")))
    (sort (mapcar #'car post) #'string<)))

(defun eest-state-test-transaction-combination-count (case)
  (let ((transaction (fixture-required-field
                      (fixture-required-field case "fixture")
                      "transaction")))
    (validate-fixture-object-fields
     transaction
     +eest-state-test-transaction-fields+
     (format nil "EEST state test case ~A transaction"
             (fixture-required-field case "name")))
    (dolist (field '("data" "gasLimit" "value"))
      (let ((values (fixture-required-field transaction field)))
        (unless (and (listp values) values)
          (error "EEST state test case ~A transaction ~A must be a non-empty JSON array"
                 (fixture-required-field case "name")
                 field))))
    (let ((access-lists (fixture-object-field transaction "accessLists")))
      (when (fixture-field-present-p transaction "accessLists")
        (unless (and (listp access-lists) access-lists)
          (error "EEST state test case ~A transaction accessLists must be a non-empty JSON array"
                 (fixture-required-field case "name"))))
      (* (length (fixture-required-field transaction "data"))
         (length (fixture-required-field transaction "gasLimit"))
         (length (fixture-required-field transaction "value"))
         (if (fixture-field-present-p transaction "accessLists")
             (length access-lists)
             1)))))

(defun phase-a-eest-state-materializable-case-p (case)
  (handler-case
      (and (intersection +phase-a-eest-state-test-supported-forks+
                         (eest-state-test-case-fork-names case)
                         :test #'string=)
           (plusp (eest-state-test-transaction-combination-count case)))
    (error () nil)))

(defun discover-phase-a-eest-state-test-selectors (root)
  (loop for case in (load-eest-state-test-root-cases root)
        when (phase-a-eest-state-materializable-case-p case)
          collect (fixture-required-field case "name")))

(defun eest-state-test-root-summary (cases)
  (let ((fork-counts (make-hash-table :test 'equal))
        (combination-count 0))
    (dolist (case cases)
      (dolist (fork (eest-state-test-case-fork-names case))
        (incf (gethash fork fork-counts 0)))
      (incf combination-count
            (eest-state-test-transaction-combination-count case)))
    (list
     (cons "count" (length cases))
     (cons "names" (mapcar (lambda (case)
                             (fixture-required-field case "name"))
                           cases))
     (cons "forkCounts"
           (sort
            (loop for key being the hash-keys of fork-counts
                  using (hash-value count)
                  collect (cons key count))
            #'string<
            :key #'car))
     (cons "transactionCombinationCount" combination-count))))

(defun report-eest-state-test-root-case (case)
  (list (cons "name" (fixture-required-field case "name"))
        (cons "forks" (eest-state-test-case-fork-names case))
        (cons "transactionCombinations"
              (eest-state-test-transaction-combination-count case))))

(defun eest-fixture-trim-string (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(defun eest-fixture-split-string (value delimiter)
  (let ((parts '())
        (start 0))
    (loop
      for position = (position delimiter value :start start)
      do (push (subseq value start position) parts)
      if position
        do (setf start (1+ position))
      else
        do (return (nreverse parts)))))

(defun parse-phase-a-eest-state-test-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST state test selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-state-test-selectors nil))
  (let ((selectors
          (mapcar #'eest-fixture-trim-string
                  (eest-fixture-split-string value #\,))))
    (validate-eest-state-selector-list selectors)
    selectors))

(defun phase-a-eest-state-test-env-selectors (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-state-test-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string" +phase-a-eest-state-test-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-state-test-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST state_tests root"
                +phase-a-eest-state-test-selectors-env+))
       (let ((selectors (discover-phase-a-eest-state-test-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A state_tests selectors"
                  +phase-a-eest-state-test-selectors-env+))
         selectors))
      (t
       (parse-phase-a-eest-state-test-selectors value)))))

(defun phase-a-eest-state-test-selector-string (selectors &key limit)
  (validate-eest-state-selector-list selectors)
  (let ((bounded-selectors
          (if (and limit (> (length selectors) limit))
              (subseq selectors 0 limit)
              selectors)))
    (format nil "~{~A~^,~}" bounded-selectors)))

(defun validate-phase-a-eest-state-test-summary
    (cases &key (expected-names +phase-a-eest-state-test-case-names+))
  (validate-eest-state-selector-list expected-names)
  (unless (and (listp cases) cases)
    (error "Phase A EEST state_tests cases must be a non-empty list"))
  (let* ((summary (eest-state-test-root-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (combination-count
           (fixture-required-field summary "transactionCombinationCount")))
    (unless (= count (length expected-names))
      (error "Phase A EEST state_tests selector count ~A loaded ~A cases"
             (length expected-names)
             count))
    (unless (equal names expected-names)
      (error "Phase A EEST state_tests names ~S do not match selectors ~S"
             names
             expected-names))
    (dolist (case cases)
      (unless (intersection +phase-a-eest-state-test-supported-forks+
                            (eest-state-test-case-fork-names case)
                            :test #'string=)
        (error "Phase A EEST state_tests case ~A has no supported fork"
               (fixture-required-field case "name"))))
    (unless (plusp combination-count)
      (error "Phase A EEST state_tests replay must include transaction combinations"))
    summary))

(defun load-phase-a-eest-state-test-root-cases
    (root &key (expected-names +phase-a-eest-state-test-case-names+))
  (let ((cases (load-eest-state-test-root-cases
                root
                :names expected-names)))
    (validate-phase-a-eest-state-test-summary
     cases
     :expected-names expected-names)
    cases))

(defun load-optional-phase-a-eest-state-test-root-cases ()
  (with-execution-spec-tests-state-test-root (root)
    (let ((expected-names (phase-a-eest-state-test-env-selectors root)))
      (unless expected-names
        (let ((candidates (discover-phase-a-eest-state-test-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to auto or comma-separated selectors such as ~A to run Phase A state_tests replay against this external root"
                       +phase-a-eest-state-test-selectors-env+
                       (phase-a-eest-state-test-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selectors to run Phase A state_tests replay against an external root"
                       +phase-a-eest-state-test-selectors-env+)))))
      (load-phase-a-eest-state-test-root-cases
       root
       :expected-names expected-names))))

(defun parse-phase-a-eest-blockchain-replay-selector (value)
  (let* ((selector (eest-fixture-trim-string value))
         (separator (position #\= selector)))
    (unless separator
      (error "Phase A EEST blockchain replay selector ~A must use name=kind"
             selector))
    (let ((name (eest-fixture-trim-string
                 (subseq selector 0 separator)))
          (kind (eest-fixture-trim-string
                 (subseq selector (1+ separator)))))
      (validate-eest-blockchain-selector-list (list name))
      (unless (member kind
                      +phase-a-eest-blockchain-replay-materialization-kind-names+
                      :test #'string=)
        (error "Phase A EEST blockchain replay selector ~A has unsupported materialization kind ~A"
               name
               kind))
      (cons name kind))))

(defun parse-phase-a-eest-blockchain-replay-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST blockchain replay selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-blockchain-replay-selectors nil))
  (let ((selectors
          (mapcar #'parse-phase-a-eest-blockchain-replay-selector
                  (eest-fixture-split-string value #\,))))
    (validate-eest-blockchain-selector-list (mapcar #'car selectors))
    selectors))

(defun phase-a-eest-blockchain-replay-env-materialization-kinds
    (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-blockchain-replay-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string"
              +phase-a-eest-blockchain-replay-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-blockchain-replay-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+))
       (let ((selectors
               (discover-phase-a-eest-blockchain-replay-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A blockchain replay selectors"
                  +phase-a-eest-blockchain-replay-selectors-env+))
         selectors))
      ((string= +phase-a-eest-blockchain-replay-pinned-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=~A requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+
                +phase-a-eest-blockchain-replay-pinned-selector+))
       (phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
        root))
      (t
       (parse-phase-a-eest-blockchain-replay-selectors value)))))

(defun phase-a-eest-blockchain-replay-selector-string
    (selectors &key limit)
  (validate-eest-blockchain-selector-list (mapcar #'car selectors))
  (let* ((bounded-selectors
           (if (and limit (> (length selectors) limit))
               (subseq selectors 0 limit)
               selectors))
         (entries
           (mapcar (lambda (selector)
                     (format nil "~A=~A" (car selector) (cdr selector)))
                   bounded-selectors)))
    (format nil "~{~A~^,~}" entries)))

(defun eest-blockchain-replay-materialization-kind (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (cond
      ((fixture-field-present-p fixture "engineNewPayloadV2")
       "engineNewPayloadV2")
      ((and (fixture-field-present-p fixture "engineNewPayloads")
            (eest-blockchain-engine-newpayloads-v2-entry case))
       "engineNewPayloadV2")
      ((let ((blocks (fixture-object-field fixture "blocks")))
         (and (listp blocks)
              blocks
              (fixture-field-present-p (first blocks) "rlp")))
       "blockRlp")
      (t
       "unsupported"))))

(defun phase-a-eest-blockchain-replay-materializable-kind (case)
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (kind (eest-blockchain-replay-materialization-kind case)))
        (when (and (stringp network)
                   (string= "Shanghai" network))
          (cond
            ((string= "engineNewPayloadV2" kind)
             (if (fixture-field-present-p fixture "engineNewPayloadV2")
                 (validate-eest-blockchain-engine-newpayload-v2-case case)
                 (validate-eest-blockchain-engine-newpayloads-v2-case case))
             kind)
            ((string= "blockRlp" kind)
             (validate-eest-blockchain-standard-newpayload-v2-case case)
             kind)
            (t nil))))
    (error () nil)))

(defun discover-phase-a-eest-blockchain-replay-selectors (root)
  (loop for case in (load-eest-blockchain-test-root-cases root)
        for kind = (phase-a-eest-blockchain-replay-materializable-kind case)
        when kind
          collect (cons (fixture-required-field case "name") kind)))

(defun validate-phase-a-eest-blockchain-discovered-replay-selectors
    (root expected-kinds)
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (let ((discovered (discover-phase-a-eest-blockchain-replay-selectors root)))
    (unless (equal discovered expected-kinds)
      (error "Discovered Phase A EEST blockchain replay selectors ~S do not match pinned selectors ~S"
             discovered
             expected-kinds))
    discovered))

(defun phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
    (root)
  (validate-phase-a-eest-blockchain-discovered-replay-selectors
   root
   +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+))

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
    (unless (or (null blocks) (listp blocks))
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
    (when (find "blockRlp" expected-kinds :key #'cdr :test #'string=)
      (unless (plusp (or (fixture-object-field kind-counts "blockRlp") 0))
        (error "Phase A EEST blockchain replay is missing standard block RLP coverage"))
      (unless (plusp block-count)
        (error "Phase A EEST blockchain replay is missing decoded block coverage")))
    summary))

(defun load-phase-a-eest-blockchain-replay-cases
    (root &key
          (expected-kinds
           +phase-a-eest-blockchain-replay-materialization-kinds+))
  (let ((cases (load-eest-blockchain-test-root-cases
                root
                :names (mapcar #'car expected-kinds))))
    (validate-phase-a-eest-blockchain-replay-summary
     cases
     :expected-kinds expected-kinds)
    cases))

(defun load-optional-phase-a-eest-blockchain-replay-cases ()
  (with-execution-spec-tests-blockchain-test-root (root)
    (let ((expected-kinds
            (phase-a-eest-blockchain-replay-env-materialization-kinds
             root)))
      (unless expected-kinds
        (let ((candidates
                (discover-phase-a-eest-blockchain-replay-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to ~A, auto, or comma-separated selector=kind pairs such as ~A to run Phase A blockchain replay against this external root"
                       +phase-a-eest-blockchain-replay-selectors-env+
                       +phase-a-eest-blockchain-replay-pinned-selector+
                       (phase-a-eest-blockchain-replay-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selector=kind pairs to run Phase A blockchain replay against an external root"
                       +phase-a-eest-blockchain-replay-selectors-env+)))))
      (load-phase-a-eest-blockchain-replay-cases
       root
       :expected-kinds expected-kinds))))

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
    (unless (listp account)
      (error "~A pre account ~A must be a JSON object" label address))
    (let ((storage (or (fixture-object-field account "storage") '())))
      (unless (listp storage)
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
                     storage))))))

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
    (is (= 6 (length paths)))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json")
               (eest-blockchain-test-root-file-names root)))))

(deftest eest-blockchain-test-root-skips-empty-preferred-layout
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-fixture-root-~A/" (gensym))
            #P"/private/tmp/"))
         (engine-root
           (merge-pathnames "blockchain_tests_engine/" root))
         (generic-root
           (merge-pathnames "blockchain_tests/" root))
         (json-path
           (merge-pathnames "shanghai/test.json" generic-root)))
    (ensure-directories-exist engine-root)
    (ensure-directories-exist json-path)
    (with-open-file (stream json-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "{}" stream))
    (let ((selected-root (execution-spec-tests-blockchain-test-root root)))
      (is (string= (namestring (truename generic-root))
                   (namestring (truename selected-root))))
      (is (equal '("shanghai/test.json")
                 (eest-blockchain-test-root-file-names selected-root))))))

(deftest eest-blockchain-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-blockchain-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-blockchain-test-root-json-paths root))))

(deftest eest-state-test-root-json-discovery
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-state-test-root-json-paths root)))
    (is (= 2 (length paths)))
    (is (equal '("london/phase-a-state-sample.json"
                 "shanghai/phase-a-state-sample.json")
               (eest-state-test-root-file-names root)))))

(deftest eest-state-test-root-json-discovery-rejects-empty-roots
  (let ((root (execution-spec-tests-state-test-root
               "tests/fixtures/geth-spec-tests-root/")))
    (signals error
      (eest-state-test-root-json-paths root))))

(deftest eest-state-test-root-case-loading
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-state-test-root-cases root))
         (selectors (discover-phase-a-eest-state-test-selectors root))
         (phase-a-cases (load-phase-a-eest-state-test-root-cases root))
         (selected (load-eest-state-test-root-cases
                    root
                    :names '("london/phase-a-state-sample.json/phase_a_london_state_sample")))
         (phase-a-summary
           (validate-phase-a-eest-state-test-summary phase-a-cases))
         (summary (eest-state-test-root-summary cases))
         (report (report-eest-state-test-root-case (first selected))))
    (is (= 5 (length cases)))
    (is (equal +phase-a-eest-state-test-case-names+ selectors))
    (is (equal +phase-a-eest-state-test-case-names+
               (fixture-object-field phase-a-summary "names")))
    (is (= 5 (fixture-object-field summary "count")))
    (is (= 3 (fixture-object-field
              (fixture-object-field summary "forkCounts")
              "London")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "forkCounts")
              "Shanghai")))
    (is (= 8 (fixture-object-field summary "transactionCombinationCount")))
    (is (equal '("London") (fixture-object-field report "forks")))
    (is (= 4 (fixture-object-field report "transactionCombinations")))
    (signals error
      (load-eest-state-test-root-cases
       root
       :names '("london/phase-a-state-sample.json/missing_case")))
    (signals error
      (load-eest-state-test-root-file-cases
       "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/"
       "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/shanghai/phase-a-empty-engine.json"))))

(deftest phase-a-eest-state-test-selector-workflow
  (let ((selectors
          (parse-phase-a-eest-state-test-selectors
           "london/phase-a-state-sample.json/phase_a_london_access_list_state_sample, london/phase-a-state-sample.json/phase_a_london_state_sample")))
    (is (equal '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
                 "london/phase-a-state-sample.json/phase_a_london_state_sample")
               selectors))
    (is (string= "london/phase-a-state-sample.json/phase_a_london_access_list_state_sample,london/phase-a-state-sample.json/phase_a_london_state_sample"
                 (phase-a-eest-state-test-selector-string selectors))))
  (signals error
    (parse-phase-a-eest-state-test-selectors
     "london/phase-a-state-sample.json"))
  (signals error
    (parse-phase-a-eest-state-test-selectors
     "london/phase-a-state-sample.json/phase_a_london_state_sample, london/phase-a-state-sample.json/phase_a_london_state_sample"))
  (let* ((*fixture-root-environment-reader*
           (lambda (name)
             (when (string= name +phase-a-eest-state-test-selectors-env+)
               "auto")))
         (root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/")))
    (is (equal +phase-a-eest-state-test-case-names+
               (phase-a-eest-state-test-env-selectors root))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (when (string= name +phase-a-eest-state-test-selectors-env+)
              (phase-a-eest-state-test-selector-string
               +phase-a-eest-state-test-case-names+)))))
    (is (equal +phase-a-eest-state-test-case-names+
               (phase-a-eest-state-test-env-selectors)))))

(deftest phase-a-eest-blockchain-replay-selector-parsing
  (let ((selectors
          (parse-phase-a-eest-blockchain-replay-selectors
           "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2, shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-standard.json=blockRlp, shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2, shanghai/phase-a-transfer-engine.json=engineNewPayloadV2")))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               selectors)))
  (let ((selectors
          (parse-phase-a-eest-blockchain-replay-selectors
           "shanghai/test.json/tests/shanghai/test_payload.py::test_case[fork_Shanghai]=engineNewPayloadV2")))
    (is (equal '(("shanghai/test.json/tests/shanghai/test_payload.py::test_case[fork_Shanghai]" . "engineNewPayloadV2"))
               selectors)))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json"))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json=unsupported"))
  (signals error
    (parse-phase-a-eest-blockchain-replay-selectors
     "shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=blockRlp"))
  (signals error
    (let ((*fixture-root-environment-reader*
            (lambda (name)
              (declare (ignore name))
              42)))
      (phase-a-eest-blockchain-replay-env-materialization-kinds))))

(deftest eest-blockchain-test-root-case-loading
  (let* ((root (execution-spec-tests-blockchain-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-blockchain-test-root-cases root))
         (phase-a-cases (load-phase-a-eest-blockchain-replay-cases root))
         (summary
           (validate-phase-a-eest-blockchain-replay-summary phase-a-cases))
         (selectors (discover-phase-a-eest-blockchain-replay-selectors root))
         (selected (load-eest-blockchain-test-root-cases
                    root
                    :names '("shanghai/phase-a-empty-engine.json")))
         (standard (first
                    (load-eest-blockchain-test-root-cases
                     root
                     :names '("shanghai/phase-a-empty-standard.json"))))
         (report (report-eest-blockchain-test-root-case (first selected))))
    (is (= 6 (length cases)))
    (is (= 6 (length phase-a-cases)))
    (is (= 6 (fixture-object-field summary "count")))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json")
               (fixture-object-field summary "names")))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               selectors))
    (is (equal +phase-a-eest-blockchain-replay-materialization-kinds+
               (validate-phase-a-eest-blockchain-discovered-replay-selectors
                root
                +phase-a-eest-blockchain-replay-materialization-kinds+)))
    (signals error
      (validate-phase-a-eest-blockchain-discovered-replay-selectors
       root
       (list (cons "shanghai/phase-a-empty-engine.json"
                   "engineNewPayloadV2"))))
    (is (string=
         "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2"
         (phase-a-eest-blockchain-replay-selector-string selectors)))
    (is (= 5 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "blockRlp")))
    (is (= 6 (fixture-object-field
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
       '("phase-a-empty-engine/case/extra")))
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
      (is (null (phase-a-eest-blockchain-replay-materializable-kind
                 bad-case)))
      (signals error
      (validate-phase-a-eest-blockchain-replay-summary
       (list bad-case (second phase-a-cases)))))))

(deftest eest-blockchain-engine-newpayloads-v2-materialization
  (let* ((source-name
           "berlin/eip2930_access_list/test.json/tests/berlin/test_tx_type.py::test_case[fork_Shanghai]")
         (case
           (list
            (cons "name" source-name)
            (cons "fixture"
                  (list
                   (cons "network" "Shanghai")
                   (cons "lastblockhash"
                         "0x2222222222222222222222222222222222222222222222222222222222222222")
                   (cons "config" '(("chainid" . "0x01")))
                   (cons "genesisBlockHeader"
                         '(("coinbase" . "0x0000000000000000000000000000000000000000")
                           ("number" . "0x00")
                           ("gasLimit" . "0x07270e00")
                           ("gasUsed" . "0x00")
                           ("timestamp" . "0x00")
                           ("baseFeePerGas" . "0x07")))
                   (cons "pre"
                         '(("0x0000000000000000000000000000000000001001"
                            ("nonce" . "0x00")
                            ("balance" . "0x10")
                            ("code" . "0x")
                            ("storage" ("0x00" . "0x01")))))
                   (cons "postState" '())
                   (cons "engineNewPayloads"
                         (list
                          (list
                           (cons "newPayloadVersion" "2")
                           (cons "forkchoiceUpdatedVersion" "2")
                           (cons "params"
                                 (list
                                  (list
                                   (cons "parentHash"
                                         "0x1111111111111111111111111111111111111111111111111111111111111111")
                                   (cons "feeRecipient"
                                         "0x0000000000000000000000000000000000000000")
                                   (cons "stateRoot"
                                         "0x3333333333333333333333333333333333333333333333333333333333333333")
                                   (cons "receiptsRoot"
                                         "0x4444444444444444444444444444444444444444444444444444444444444444")
                                   (cons "logsBloom"
                                         "0x")
                                   (cons "blockNumber" "0x1")
                                   (cons "gasLimit" "0x7270e00")
                                   (cons "gasUsed" "0x0")
                                   (cons "timestamp" "0x3e8")
                                   (cons "extraData" "0x00")
                                   (cons "prevRandao"
                                         "0x0000000000000000000000000000000000000000000000000000000000000000")
                                   (cons "baseFeePerGas" "0x7")
                                   (cons "blockHash"
                                         "0x2222222222222222222222222222222222222222222222222222222222222222")
                                   (cons "transactions" '())
                                   (cons "withdrawals" '())))))))
                   (cons "_info" '()))))))
    (is (string= "engineNewPayloadV2"
                 (eest-blockchain-replay-materialization-kind case)))
    (is (string= "engineNewPayloadV2"
                 (phase-a-eest-blockchain-replay-materializable-kind case)))
    (let* ((summary
             (validate-phase-a-eest-blockchain-replay-summary
              (list case)
              :expected-kinds (list (cons source-name "engineNewPayloadV2"))))
           (materialized
             (materialize-eest-blockchain-engine-newpayload-v2-case case))
           (parent (fixture-required-field materialized "parent"))
           (account (first (fixture-required-field parent "accounts")))
           (payload (fixture-required-field materialized "payload"))
           (expect (fixture-required-field materialized "expect")))
      (is (= 1 (fixture-required-field summary "count")))
      (is (= 0 (fixture-required-field summary "blockCount")))
      (is (string= "0x1" (fixture-required-field materialized "chainId")))
      (is (string= "0x1" (fixture-required-field payload "number")))
      (is (string= "0x3333333333333333333333333333333333333333333333333333333333333333"
                   (fixture-required-field expect "stateRoot")))
      (is (equal '(("0x0000000000000000000000000000000000000000000000000000000000000000"
                    . "0x1"))
                 (fixture-required-field account "storage"))))))

(deftest optional-phase-a-eest-blockchain-replay-cases
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2")
              (t nil)))))
    (let ((cases (load-optional-phase-a-eest-blockchain-replay-cases)))
      (is (= 6 (length cases)))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "pinned-v5.4.0")
              (t nil)))))
    (signals error
      (load-optional-phase-a-eest-blockchain-replay-cases)))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               "auto")
              (t nil)))))
    (let ((cases (load-optional-phase-a-eest-blockchain-replay-cases)))
      (is (= 6 (length cases)))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (cond
              ((string= name +execution-spec-tests-fixture-root-env+)
               "tests/fixtures/execution-spec-tests-root/")
              ((string= name +phase-a-eest-blockchain-replay-selectors-env+)
               nil)
              (t nil)))))
    (signals test-skipped
      (load-optional-phase-a-eest-blockchain-replay-cases))))
