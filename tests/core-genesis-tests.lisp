(in-package #:ethereum-lisp.test)

(deftest block-header-hash-is-hash32
  (let ((hash (block-header-hash (make-block-header))))
    (is (hash32-p hash))
    (is (= 66 (length (hash32-to-hex hash))))))

(deftest execution-requests-hash-skips-empty-request-payloads
  (flet ((requests-hash-hex (requests)
           (hash32-to-hex (execution-requests-hash requests))))
    (is (string= "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                 (requests-hash-hex '())))
    (is (string= "0x5718d61e4ad0bf7361f89a3d32dd9b29967017c96043bed3e6f7f0a29912f49e"
                 (requests-hash-hex (list #(#x00) #(#x01 #xaa)))))
    (is (string= "0xf050ca62d7d8be620cce73c1100a9d310f09935cee72604b696542da6d0f7496"
                 (requests-hash-hex
                  (list #(#x01 #xaa) #(#x02 #xbb #xcc)))))))

(deftest execution-request-fields-validation
  (let ((block (make-block)))
    (is (bytes= #(#x01)
                (validate-execution-request-fields #(#x01))))
    (signals block-validation-error
      (validate-execution-request-fields #()))
    (signals block-validation-error
      (validate-execution-request-fields "not bytes"))
    (setf (block-requests block) (list #())
          (block-requests-present-p block) t
          (block-header-requests-hash (block-header block))
          (execution-requests-hash '()))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-execution-request-list-fields
         (list #(#x00 #xaa) #(#x01 #xbb))))
    (signals block-validation-error
      (validate-execution-request-list-fields (list #(#x00))))
    (signals block-validation-error
      (validate-execution-request-list-fields
       (list #(#x00 #xaa) #(#x00 #xbb))))
    (signals block-validation-error
      (validate-execution-request-list-fields
       (list #(#x01 #xaa) #(#x00 #xbb))))))

(deftest eip1559-base-fee-calculation-and-validation
  (let* ((parent (make-block-header :gas-limit 2000
                                    :gas-used 1000
                                    :base-fee-per-gas 1000))
         (same-target (make-block-header :base-fee-per-gas 1000))
         (over-target (make-block-header :base-fee-per-gas 1125))
         (under-target (make-block-header :base-fee-per-gas 875))
         (low-base-parent (make-block-header :gas-limit 2000
                                             :gas-used 2000
                                             :base-fee-per-gas 7))
         (first-london (make-block-header :base-fee-per-gas
                                          +initial-base-fee+)))
    (is (= 1000 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent same-target))
    (setf (block-header-gas-used parent) 2000)
    (is (= 1125 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent over-target))
    (setf (block-header-gas-used parent) 0)
    (is (= 875 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent under-target))
    (is (= 8 (expected-base-fee-per-gas low-base-parent)))
    (is (= +initial-base-fee+
           (expected-base-fee-per-gas parent :london-parent-p nil)))
    (is (validate-block-base-fee parent first-london
                                 :london-parent-p nil))
    (setf (block-header-base-fee-per-gas same-target) 999)
    (signals block-validation-error
      (validate-block-base-fee parent same-target))))

(deftest eip1559-transaction-fee-validation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (legacy (make-legacy-transaction :gas-price 7))
         (dynamic (make-dynamic-fee-transaction
                   :to recipient
                   :max-priority-fee-per-gas 3
                   :max-fee-per-gas 10))
         (capped (make-dynamic-fee-transaction
                  :to recipient
                  :max-priority-fee-per-gas 10
                  :max-fee-per-gas 12))
         (tip-too-high (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas 11
                        :max-fee-per-gas 10))
         (tip-too-wide (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas (1+ +uint256-max+)
                        :max-fee-per-gas (1+ +uint256-max+)))
         (fee-too-wide (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas 1
                        :max-fee-per-gas (1+ +uint256-max+)))
         (fee-too-low (make-dynamic-fee-transaction
                       :to recipient
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4)))
    (is (= 7 (transaction-effective-gas-price legacy :base-fee 5)))
    (is (= 8 (transaction-effective-gas-price dynamic :base-fee 5)))
    (is (= 12 (transaction-effective-gas-price capped :base-fee 5)))
    (is (validate-1559-transaction-fees dynamic 5))
    (signals block-validation-error
      (validate-1559-transaction-fees tip-too-high 5))
    (signals block-validation-error
      (validate-1559-transaction-fees tip-too-wide 5))
    (signals block-validation-error
      (validate-1559-transaction-fees fee-too-wide 5))
    (signals block-validation-error
      (transaction-effective-gas-price fee-too-low :base-fee 5))))

(deftest transaction-constructors-reject-negative-fee-fields
  (let ((negative (parse-integer "-1"))
        (recipient (address-from-hex
                    "0x0000000000000000000000000000000000000001"))
        (blob-hash (hash32-from-hex
                    "0x0100000000000000000000000000000000000000000000000000000000000000")))
    (signals type-error
      (make-legacy-transaction :gas-price negative))
    (signals type-error
      (make-dynamic-fee-transaction :to recipient
                                    :max-priority-fee-per-gas negative
                                    :max-fee-per-gas 10))
    (signals type-error
      (make-dynamic-fee-transaction :to recipient
                                    :max-priority-fee-per-gas 1
                                    :max-fee-per-gas negative))
    (signals type-error
      (make-blob-transaction :to recipient
                             :max-fee-per-blob-gas negative
                             :blob-versioned-hashes (list blob-hash)))))

(deftest chain-config-fork-activation
  (let ((config (make-chain-config :chain-id 1
                                   :constantinople-block 7
                                   :london-block 10
                                   :shanghai-time 100
                                   :cancun-time 200
                                   :prague-time 300
                                   :osaka-time 400
                                   :bpo1-time 500
                                   :bpo2-time 600
                                   :bpo3-time 700
                                   :bpo4-time 800
                                   :bpo5-time 900
                                   :amsterdam-time 1000
                                   :ubt-time 1100
                                   :enable-ubt-at-genesis-p t)))
    (is (not (fork-block-active-p nil 10)))
    (is (not (fork-block-active-p 10 9)))
    (is (fork-block-active-p 10 10))
    (is (not (fork-time-active-p nil 100)))
    (is (not (fork-time-active-p 100 99)))
    (is (fork-time-active-p 100 100))
    (is (= 1 (chain-config-chain-id config)))
    (is (not (chain-config-london-p config 9)))
    (is (chain-config-london-p config 10))
    (is (not (chain-config-shanghai-p config 9 100)))
    (is (chain-config-shanghai-p config 10 100))
    (is (not (chain-config-cancun-p config 10 199)))
    (is (chain-config-cancun-p config 10 200))
    (is (not (chain-config-prague-p config 10 299)))
    (is (chain-config-prague-p config 10 300))
    (is (not (chain-config-expanded-blob-schedule-p config 10 299)))
    (is (chain-config-expanded-blob-schedule-p config 10 300))
    (is (not (chain-config-osaka-p config 10 399)))
    (is (chain-config-osaka-p config 10 400))
    (is (not (chain-config-bpo1-p config 10 499)))
    (is (chain-config-bpo1-p config 10 500))
    (is (not (chain-config-bpo2-p config 10 599)))
    (is (chain-config-bpo2-p config 10 600))
    (is (not (chain-config-bpo3-p config 10 699)))
    (is (chain-config-bpo3-p config 10 700))
    (is (not (chain-config-bpo4-p config 10 799)))
    (is (chain-config-bpo4-p config 10 800))
    (is (not (chain-config-bpo5-p config 10 899)))
    (is (chain-config-bpo5-p config 10 900))
    (is (not (chain-config-amsterdam-p config 10 999)))
    (is (chain-config-amsterdam-p config 10 1000))
    (is (not (chain-config-ubt-p config 10 1099)))
    (is (chain-config-ubt-p config 10 1100))
    (is (chain-config-ubt-genesis-p config))
    (is (not (chain-config-petersburg-p config 6)))
    (is (chain-config-petersburg-p config 7))))

(deftest chain-config-package-boundary
  (let ((chain-config-package
          (find-package '#:ethereum-lisp.chain-config))
        (core-package
          (find-package '#:ethereum-lisp.core)))
    (is (not (member core-package
                     (package-use-list chain-config-package))))
    (dolist (name '("CHAIN-CONFIG" "CHAIN-CONFIG-RULES"
                    "CHAIN-RULES-CANCUN-P"))
      (multiple-value-bind (chain-config-symbol chain-config-status)
          (find-symbol name chain-config-package)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core-package)
          (is (eq :external chain-config-status))
          (is (eq :external core-status))
          (is (eq chain-config-symbol core-symbol)))))
    (multiple-value-bind (symbol status)
        (find-symbol "CHAIN-RULES-TRANSACTION-TYPE-SUPPORTED-P"
                     chain-config-package)
      (is (null symbol))
      (is (null status)))))

(deftest chain-config-rules-snapshot
  (let* ((config (make-chain-config :chain-id 5
                                    :berlin-block 5
                                    :london-block 10
                                    :shanghai-time 20
                                    :cancun-time 30
                                    :prague-time 40
                                    :osaka-time 50
                                    :bpo1-time 60
                                    :bpo2-time 70
                                    :bpo3-time 80
                                    :bpo4-time 90
                                    :bpo5-time 100
                                    :amsterdam-time 110
                                    :ubt-time 120))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (blob (make-blob-transaction
                :to recipient
                :blob-versioned-hashes
                (list (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient))))
         (london-rules (chain-config-rules config 10 20))
         (prague-rules (chain-config-rules config 10 40))
         (osaka-rules (chain-config-rules config 10 50))
         (bpo1-rules (chain-config-rules config 10 60))
         (bpo2-rules (chain-config-rules config 10 70))
         (bpo3-rules (chain-config-rules config 10 80))
         (bpo4-rules (chain-config-rules config 10 90))
         (bpo5-rules (chain-config-rules config 10 100))
         (amsterdam-rules (chain-config-rules config 10 110))
         (ubt-rules (chain-config-rules config 10 120)))
    (is (= 5 (chain-rules-chain-id london-rules)))
    (is (chain-rules-berlin-p london-rules))
    (is (chain-rules-london-p london-rules))
    (is (chain-rules-shanghai-p london-rules))
    (is (not (chain-rules-cancun-p london-rules)))
    (is (not (chain-rules-prague-p london-rules)))
    (is (chain-rules-transaction-type-supported-p london-rules access-list))
    (is (chain-rules-transaction-type-supported-p london-rules dynamic))
    (is (not (chain-rules-transaction-type-supported-p london-rules blob)))
    (is (chain-rules-cancun-p prague-rules))
    (is (chain-rules-prague-p prague-rules))
    (is (not (chain-rules-osaka-p prague-rules)))
    (is (chain-rules-expanded-blob-schedule-p prague-rules))
    (is (chain-rules-osaka-p osaka-rules))
    (is (chain-rules-expanded-blob-schedule-p osaka-rules))
    (is (chain-rules-bpo1-p bpo1-rules))
    (is (chain-rules-bpo2-p bpo2-rules))
    (is (chain-rules-bpo3-p bpo3-rules))
    (is (chain-rules-bpo4-p bpo4-rules))
    (is (chain-rules-bpo5-p bpo5-rules))
    (is (chain-rules-amsterdam-p amsterdam-rules))
    (is (not (chain-rules-ubt-p amsterdam-rules)))
    (is (chain-rules-ubt-p ubt-rules))
    (is (chain-rules-transaction-type-supported-p prague-rules blob))
    (is (chain-rules-transaction-type-supported-p prague-rules set-code))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 10 60)
      (is (= (* +bpo1-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo1-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo1-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-rules-blob-schedule bpo2-rules)
      (is (= (* +bpo2-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo2-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo2-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 10 80)
      (is (= (* +bpo3-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo3-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo3-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-rules-blob-schedule bpo4-rules)
      (is (= (* +bpo4-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo4-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo4-blob-base-fee-update-fraction+ update-fraction)))))

(deftest custom-blob-schedule-overrides-fork-defaults
  (let* ((early-entry (make-blob-schedule-entry :timestamp 40
                                                :target-blobs 5
                                                :max-blobs 7
                                                :update-fraction 424242))
         (late-entry (make-blob-schedule-entry :timestamp 90
                                               :target-blobs 2
                                               :max-blobs 4
                                               :update-fraction 999999))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo3-time 80
                                    :custom-blob-schedule
                                    (list late-entry early-entry))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 39)
      (is (= (* +target-blobs-per-block+ +blob-gas-per-blob+) target))
      (is (= (* +max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 80)
      (is (= (* 5 +blob-gas-per-blob+) target))
      (is (= (* 7 +blob-gas-per-blob+) max))
      (is (= 424242 update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 90)
      (is (= (* 2 +blob-gas-per-blob+) target))
      (is (= (* 4 +blob-gas-per-blob+) max))
      (is (= 999999 update-fraction)))
    (let ((rules (chain-config-rules config 1 80)))
      (multiple-value-bind (target max update-fraction)
          (chain-rules-blob-schedule rules)
        (is (= (* 5 +blob-gas-per-blob+) target))
        (is (= (* 7 +blob-gas-per-blob+) max))
        (is (= 424242 update-fraction))))))

(deftest chain-config-from-genesis-config-parses-geth-fields
  (let* ((genesis-config
           '(("chainId" . "123")
             ("homesteadBlock" . 0)
             ("daoForkBlock" . 2)
             ("daoForkSupport" . t)
             ("londonBlock" . "5")
             ("muirGlacierBlock" . 6)
             ("arrowGlacierBlock" . 7)
             ("grayGlacierBlock" . 8)
             ("cancunTime" . "0x10")
             ("bpo3Time" . 30)
             ("bpo5Time" . 40)
             ("amsterdamTime" . 50)
             ("ubtTime" . 60)
             ("enableUBTAtGenesis" . t)
             ("terminalTotalDifficulty" . 0)
             ("terminalTotalDifficultyPassed" . t)
             ("mergeNetsplitBlock" . "9")
             ("depositContractAddress" .
              "0x00000000219ab540356cbb839cbe05303d7705fa")
             ("blobSchedule" .
              (("bpo3" .
                (("target" . 8)
                 ("max" . 11)
                 ("baseFeeUpdateFraction" . "12345")))
               ("bpo5" .
                (("target" . 34)
                 ("max" . 55)
                 ("baseFeeUpdateFraction" . 98765)))
               ("bpo4" .
                (("target" . 13)
                 ("max" . 17)
                 ("baseFeeUpdateFraction" . 67890)))))))
         (config (chain-config-from-genesis-config genesis-config)))
    (is (= 123 (chain-config-chain-id config)))
    (is (= 0 (chain-config-homestead-block config)))
    (is (= 2 (chain-config-dao-fork-block config)))
    (is (chain-config-dao-fork-support config))
    (is (chain-config-dao-fork-p config 2))
    (is (= 5 (chain-config-london-block config)))
    (is (= 6 (chain-config-muir-glacier-block config)))
    (is (= 7 (chain-config-arrow-glacier-block config)))
    (is (= 8 (chain-config-gray-glacier-block config)))
    (is (= 16 (chain-config-cancun-time config)))
    (is (= 30 (chain-config-bpo3-time config)))
    (is (= 40 (chain-config-bpo5-time config)))
    (is (= 50 (chain-config-amsterdam-time config)))
    (is (= 60 (chain-config-ubt-time config)))
    (is (chain-config-enable-ubt-at-genesis-p config))
    (is (= 0 (chain-config-terminal-total-difficulty config)))
    (is (chain-config-terminal-total-difficulty-passed config))
    (is (= 9 (chain-config-merge-netsplit-block config)))
    (is (string= "0x00000000219ab540356cbb839cbe05303d7705fa"
                 (address-to-hex
                  (chain-config-deposit-contract-address config))))
    (is (= 2 (length (chain-config-custom-blob-schedule config))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 30)
      (is (= (* 8 +blob-gas-per-blob+) target))
      (is (= (* 11 +blob-gas-per-blob+) max))
      (is (= 12345 update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 40)
      (is (= (* 34 +blob-gas-per-blob+) target))
      (is (= (* 55 +blob-gas-per-blob+) max))
      (is (= 98765 update-fraction)))))

(deftest chain-config-from-genesis-config-parses-nethermind-fork-aliases
  (let ((config (chain-config-from-genesis-config
                 '(("chainId" . 1)
                   ("tangerineWhistleBlock" . 11)
                   ("spuriousDragonBlock" . 22)))))
    (is (= 11 (chain-config-eip150-block config)))
    (is (= 22 (chain-config-eip155-block config)))
    (is (= 22 (chain-config-eip158-block config)))))

(deftest chain-config-from-genesis-config-rejects-bad-blob-schedule
  (signals block-validation-error
    (chain-config-from-genesis-config
     '(("chainId" . 1)
       ("cancunTime" . 0)
       ("blobSchedule" .
        (("cancun" .
          (("target" . 3)
           ("max" . 6)))))))))

(deftest chain-config-from-genesis-config-rejects-bad-merge-flag
  (signals block-validation-error
    (chain-config-from-genesis-config
     '(("chainId" . 1)
       ("terminalTotalDifficultyPassed" . "true")))))

(deftest chain-config-from-genesis-json-string-parses-config
  (let* ((json "{\"config\":{\"chainId\":\"0x7b\",\"londonBlock\":\"5\",\"cancunTime\":16,\"bpo3Time\":30,\"terminalTotalDifficultyPassed\":true,\"depositContractAddress\":\"0x00000000219ab540356cbb839cbe05303d7705fa\",\"blobSchedule\":{\"bpo3\":{\"target\":8,\"max\":11,\"baseFeeUpdateFraction\":\"12345\"}}}}")
         (config (chain-config-from-genesis-json-string json)))
    (is (= 123 (chain-config-chain-id config)))
    (is (= 5 (chain-config-london-block config)))
    (is (= 16 (chain-config-cancun-time config)))
    (is (= 30 (chain-config-bpo3-time config)))
    (is (chain-config-terminal-total-difficulty-passed config))
    (is (string= "0x00000000219ab540356cbb839cbe05303d7705fa"
                 (address-to-hex
                  (chain-config-deposit-contract-address config))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 30)
      (is (= (* 8 +blob-gas-per-blob+) target))
      (is (= (* 11 +blob-gas-per-blob+) max))
      (is (= 12345 update-fraction)))))

(deftest chain-config-from-genesis-json-file-parses-config
  (let ((path (make-pathname :name "ethereum-lisp-genesis-test"
                             :type "json"
                             :defaults #P"/private/tmp/")))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string
              "{\"config\":{\"chainId\":9,\"londonBlock\":0,\"cancunTime\":0}}"
              stream))
           (let ((config (chain-config-from-genesis-json-file path)))
             (is (= 9 (chain-config-chain-id config)))
             (is (= 0 (chain-config-london-block config)))
             (is (= 0 (chain-config-cancun-time config)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest genesis-json-parser-rejects-non-integer-numbers
  (signals block-validation-error
    (chain-config-from-genesis-json-string
     "{\"config\":{\"chainId\":1.5}}")))

(deftest json-package-boundary
  (let ((json (find-package '#:ethereum-lisp.json))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list json))))
    (dolist (name '("PARSE-JSON" "JSON-ENCODE"))
      (multiple-value-bind (json-symbol json-status)
          (find-symbol name json)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external json-status))
          (is (eq :external core-status))
          (is (eq json-symbol core-symbol)))))
    (dolist (name '("GENESIS-ACCOUNT" "CHAIN-CONFIG-FROM-GENESIS-CONFIG"))
      (multiple-value-bind (symbol status)
          (find-symbol name json)
        (is (null symbol))
        (is (null status))))))

(deftest json-encode-round-trips-rpc-shaped-objects
  (let* ((object
           (list (cons "jsonrpc" "2.0")
                 (cons "id" 4)
                 (cons "result"
                       (list (cons "status" +payload-status-valid+)
                             (cons "latestValidHash" nil)
                             (cons "labels" '("engine" "newPayload"))
                             (cons "quote" (format nil "line~%break"))))))
         (encoded (json-encode object))
         (decoded (parse-json encoded))
         (result (cdr (assoc "result" decoded :test #'string=))))
    (is (string= "2.0" (cdr (assoc "jsonrpc" decoded :test #'string=))))
    (is (= 4 (cdr (assoc "id" decoded :test #'string=))))
    (is (string= +payload-status-valid+
                 (cdr (assoc "status" result :test #'string=))))
    (is (not (cdr (assoc "latestValidHash" result :test #'string=))))
    (is (equal '("engine" "newPayload")
               (cdr (assoc "labels" result :test #'string=))))
    (is (string= (format nil "line~%break")
                 (cdr (assoc "quote" result :test #'string=))))))

(deftest json-empty-array-marker-rejects-empty-strings
  (let ((empty-array
          (parse-json "[]" :preserve-empty-arrays t)))
    (is (ethereum-lisp.json:json-empty-array-p empty-array))
    (is (ethereum-lisp.json:json-array-p empty-array))
    (is (not (ethereum-lisp.json:json-empty-array-p "")))
    (is (not (ethereum-lisp.json:json-array-p "")))))

(deftest genesis-alloc-from-json-parses-account-fields
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{"
                "\"0x0000000000000000000000000000000000000000000000000000000000000007\":\"0x2a\""
                "}}}}"))
         (alloc (genesis-alloc-from-genesis-json-string json))
         (account (first alloc))
         (storage-entry (first (genesis-account-storage account))))
    (is (= 1 (length alloc)))
    (is (string= "0x0000000000000000000000000000000000000001"
                 (address-to-hex (genesis-account-address account))))
    (is (= 16 (genesis-account-balance account)))
    (is (= 2 (genesis-account-nonce account)))
    (is (string= "0x60016000"
                 (bytes-to-hex (genesis-account-code account))))
    (is (string= "0x0000000000000000000000000000000000000000000000000000000000000007"
                 (hash32-to-hex (car storage-entry))))
    (is (= 42 (cdr storage-entry)))))

(deftest genesis-alloc-from-json-rejects-negative-quantities
  (signals block-validation-error
    (genesis-alloc-from-genesis-json-string
     "{\"alloc\":{\"0000000000000000000000000000000000000001\":{\"balance\":\"-1\"}}}")))

(deftest genesis-alloc-storage-pads-short-hex-keys-and-values
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0000000000000000000000000000000000000001\":{"
                "\"balance\":\"1\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (account (first (genesis-alloc-from-genesis-json-string json)))
         (storage-entry (first (genesis-account-storage account))))
    (is (string= "0x0000000000000000000000000000000000000000000000000000000000000007"
                 (hash32-to-hex (car storage-entry))))
    (is (= 42 (cdr storage-entry)))))

(deftest genesis-alloc-storage-rejects-overwide-hex-values
  (signals block-validation-error
    (genesis-alloc-from-genesis-json-string
     (concatenate
      'string
      "{\"alloc\":{\"0000000000000000000000000000000000000001\":"
      "{\"balance\":\"1\",\"storage\":{\"0x01\":\"0x"
      "010000000000000000000000000000000000000000000000000000000000000000"
      "\"}}}}"))))

(deftest genesis-expected-state-root-from-json-parses-hash
  (let* ((root "0x0000000000000000000000000000000000000000000000000000000000000007")
         (json (format nil "{\"stateRoot\":\"~A\"}" root)))
    (is (string= root
                 (hash32-to-hex
                  (genesis-expected-state-root-from-genesis-json-string json))))))

(deftest genesis-expected-state-root-from-json-rejects-bad-hash
  (signals block-validation-error
    (genesis-expected-state-root-from-genesis-json-string
     "{\"stateRoot\":\"0x1234\"}")))

(deftest genesis-header-from-json-maps-geth-fields-and-fork-defaults
  (let* ((state-root (hash32-from-hex
                      "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{"
                "\"londonBlock\":0,"
                "\"shanghaiTime\":0,"
                "\"cancunTime\":0,"
                "\"pragueTime\":0,"
                "\"amsterdamTime\":0"
                "},"
                "\"nonce\":\"0x0102030405060708\","
                "\"timestamp\":0,"
                "\"extraData\":\"0x1234\","
                "\"gasLimit\":0,"
                "\"gasUsed\":\"0x09\","
                "\"difficulty\":\"0x02\","
                "\"mixHash\":\"" (hash32-to-hex mix-hash) "\","
                "\"coinbase\":\"0x0000000000000000000000000000000000000001\""
                "}"))
         (header (genesis-header-from-genesis-json-string
                  json :state-root state-root)))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (= +genesis-gas-limit+ (block-header-gas-limit header)))
    (is (= 9 (block-header-gas-used header)))
    (is (= 2 (block-header-difficulty header)))
    (is (= +initial-base-fee+ (block-header-base-fee-per-gas header)))
    (is (string= "0x0102030405060708"
                 (bytes-to-hex (block-header-nonce header))))
    (is (string= "0x1234" (bytes-to-hex (block-header-extra-data header))))
    (is (string= "0x0000000000000000000000000000000000000001"
                 (address-to-hex (block-header-beneficiary header))))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (block-header-mix-hash header))))
    (is (string= (hash32-to-hex (withdrawal-list-root '()))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex (zero-hash32))
                 (hash32-to-hex (block-header-parent-beacon-root header))))
    (is (= 0 (block-header-excess-blob-gas header)))
    (is (= 0 (block-header-blob-gas-used header)))
    (is (string= (hash32-to-hex (execution-requests-hash '()))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex +empty-ommers-hash+)
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (= 0 (block-header-slot-number header)))))

(deftest genesis-header-from-json-accepts-geth-field-aliases
  (let* ((mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (parent-beacon-root
           (hash32-from-hex
            "0x0400000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0,\"cancunTime\":0},"
                "\"timestamp\":0,"
                "\"mixhash\":\"" (hash32-to-hex mix-hash) "\","
                "\"parentBeaconBlockRoot\":\""
                (hash32-to-hex parent-beacon-root) "\""
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (block-header-mix-hash header))))
    (is (string= (hash32-to-hex parent-beacon-root)
                 (hash32-to-hex
                  (block-header-parent-beacon-root header))))))

(deftest genesis-header-ignores-parent-beacon-root-before-cancun
  (let* ((parent-beacon-root
           (hash32-from-hex
            "0x0400000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0},"
                "\"timestamp\":0,"
                "\"parentBeaconBlockRoot\":\""
                (hash32-to-hex parent-beacon-root) "\""
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (null (block-header-parent-beacon-root header)))))

(deftest genesis-header-defaults-difficulty-to-zero-at-merge-genesis
  (let* ((json (concatenate
                'string
                "{\"config\":{\"terminalTotalDifficulty\":0},"
                "\"timestamp\":0"
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (= 0 (block-header-difficulty header)))))

(deftest genesis-block-from-json-carries-empty-fork-bodies
  (let* ((state-root (hash32-from-hex
                      "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{"
                "\"londonBlock\":0,"
                "\"shanghaiTime\":0,"
                "\"cancunTime\":0,"
                "\"pragueTime\":0,"
                "\"amsterdamTime\":0"
                "},"
                "\"timestamp\":0"
                "}"))
         (block (genesis-block-from-genesis-json-string
                 json :state-root state-root))
         (header (block-header block)))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (null (block-transactions block)))
    (is (null (block-ommers block)))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))
    (is (block-requests-present-p block))
    (is (null (block-requests block)))
    (is (block-block-access-list-present-p block))
    (is (null (block-block-access-list block)))
    (is (string= (hash32-to-hex (withdrawal-list-root '()))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex (execution-requests-hash '()))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))))
