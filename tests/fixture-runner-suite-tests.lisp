(in-package #:ethereum-lisp.test)

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
    (is (= 9 (length paths)))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-contract-creation-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-internal-create2-engine.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json"
                 "shanghai/phase-a-two-legacy-transfers-engine.json")
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

(deftest phase-a-eest-blockchain-discovery-skips-unsupported-fork-roots
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-blockchain-discovery-root-~A/" (gensym))
            #P"/private/tmp/"))
         (shanghai-path
           (merge-pathnames "shanghai/phase-a-empty-engine.json" root))
         (cancun-path
           (merge-pathnames "cancun/eip4844_blobs/invalid.json" root)))
    (labels ((file-string (path)
               (with-open-file (stream path :direction :input)
                 (let ((string (make-string (file-length stream))))
                   (read-sequence string stream)
                   string)))
             (write-file (path contents)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (write-string contents stream))))
      (write-file
       shanghai-path
       (file-string
        "tests/fixtures/execution-spec-tests-root/fixtures/blockchain_tests_engine/shanghai/phase-a-empty-engine.json"))
      (write-file cancun-path "{")
      (is (equal
           '(("shanghai/phase-a-empty-engine.json" . "engineNewPayloadV2"))
           (discover-phase-a-eest-blockchain-replay-selectors root))))))

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

(deftest eest-state-test-file-entries-accept-optional-config
  (is (null
       (validate-eest-state-test-file-entries
        '(("case_with_config"
           ("env")
           ("pre")
           ("transaction")
           ("post")
           ("config" ("chainid" . "0x01"))))
        "state_tests/sample.json")))
  (signals error
    (validate-eest-state-test-file-entries
     '(("case_with_unknown_field"
        ("env")
        ("pre")
        ("transaction")
        ("post")
        ("unexpected")))
     "state_tests/sample.json")))

(deftest eest-state-test-root-case-loading-honors-selector-files
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-state-test-root-cases
                 root
                 :names '("london/phase-a-state-sample.json/phase_a_london_state_sample"))))
    (is (= 1 (length cases)))
    (is (equal '("london/phase-a-state-sample.json/phase_a_london_state_sample")
               (mapcar (lambda (case)
                         (fixture-required-field case "name"))
                       cases))))
  (let ((root (execution-spec-tests-state-test-root
               "tests/fixtures/execution-spec-tests-root/")))
    (signals error
      (load-eest-state-test-root-cases
       root
       :names '("london/missing-state-sample.json/missing_case")))))

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

(deftest phase-a-eest-state-discovery-skips-unsupported-and-oversized-roots
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-state-discovery-root-~A/" (gensym))
            #P"/private/tmp/"))
         (london-path
           (merge-pathnames "london/phase-a-state-sample.json" root))
         (cancun-path
           (merge-pathnames "cancun/eip4844_blobs/invalid.json" root))
         (oversized-shanghai-path
           (merge-pathnames "shanghai/eip3860_initcode/test_gas_usage.json"
                            root)))
    (labels ((file-string (path)
               (with-open-file (stream path :direction :input)
                 (let ((string (make-string (file-length stream))))
                   (read-sequence string stream)
                   string)))
             (write-file (path contents)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (write-string contents stream)))
             (write-oversized-file (path)
               (ensure-directories-exist path)
               (with-open-file (stream path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (loop repeat (1+ +phase-a-eest-state-test-discovery-max-file-bytes+)
                       do (write-char #\{ stream)))))
      (write-file
       london-path
       (file-string
        "tests/fixtures/execution-spec-tests-root/fixtures/state_tests/london/phase-a-state-sample.json"))
      (write-file cancun-path "{")
      (write-oversized-file oversized-shanghai-path)
      (is (equal
           '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample"
             "london/phase-a-state-sample.json/phase_a_london_dynamic_fee_state_sample"
             "london/phase-a-state-sample.json/phase_a_london_state_sample")
           (discover-phase-a-eest-state-test-selectors root))))))

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
           "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2, shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2, shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-engine.json=engineNewPayloadV2, shanghai/phase-a-empty-standard.json=blockRlp, shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2, shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2, shanghai/phase-a-transfer-engine.json=engineNewPayloadV2, shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2")))
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
    (is (= 9 (length cases)))
    (is (= 9 (length phase-a-cases)))
    (is (= 9 (fixture-object-field summary "count")))
    (is (equal '("shanghai/phase-a-access-list-engine.json"
                 "shanghai/phase-a-contract-creation-engine.json"
                 "shanghai/phase-a-dynamic-fee-engine.json"
                 "shanghai/phase-a-empty-engine.json"
                 "shanghai/phase-a-empty-standard.json"
                 "shanghai/phase-a-internal-create2-engine.json"
                 "shanghai/phase-a-log-contract-engine.json"
                 "shanghai/phase-a-transfer-engine.json"
                 "shanghai/phase-a-two-legacy-transfers-engine.json")
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
         "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2,shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2"
         (phase-a-eest-blockchain-replay-selector-string selectors)))
    (is (= 8 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field
              (fixture-object-field summary "materializationKindCounts")
              "blockRlp")))
    (is (= 9 (fixture-object-field
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
               "shanghai/phase-a-access-list-engine.json=engineNewPayloadV2,shanghai/phase-a-contract-creation-engine.json=engineNewPayloadV2,shanghai/phase-a-dynamic-fee-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-engine.json=engineNewPayloadV2,shanghai/phase-a-empty-standard.json=blockRlp,shanghai/phase-a-internal-create2-engine.json=engineNewPayloadV2,shanghai/phase-a-log-contract-engine.json=engineNewPayloadV2,shanghai/phase-a-transfer-engine.json=engineNewPayloadV2,shanghai/phase-a-two-legacy-transfers-engine.json=engineNewPayloadV2")
              (t nil)))))
    (let ((cases (load-optional-phase-a-eest-blockchain-replay-cases)))
      (is (= 9 (length cases)))))
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
      (is (= 9 (length cases)))))
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
