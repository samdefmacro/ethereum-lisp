(in-package #:ethereum-lisp.genesis)

(defun genesis-blob-schedule-timestamp-field (fork-name)
  (cond
    ((string-equal fork-name "cancun") "cancunTime")
    ((string-equal fork-name "prague") "pragueTime")
    ((string-equal fork-name "osaka") "osakaTime")
    ((string-equal fork-name "bpo1") "bpo1Time")
    ((string-equal fork-name "bpo2") "bpo2Time")
    ((string-equal fork-name "bpo3") "bpo3Time")
    ((string-equal fork-name "bpo4") "bpo4Time")
    ((string-equal fork-name "bpo5") "bpo5Time")
    ((string-equal fork-name "amsterdam") "amsterdamTime")
    ((string-equal fork-name "ubt") "ubtTime")
    (t nil)))

(defun parse-genesis-blob-schedule-entry (timestamp entry-object fork-name)
  (make-blob-schedule-entry
   :timestamp timestamp
   :target-blobs (parse-json-quantity-field entry-object "target"
                                      :label (format nil "~A blob target" fork-name)
                                      :required-p t)
   :max-blobs (parse-json-quantity-field entry-object "max"
                                   :label (format nil "~A blob max" fork-name)
                                   :required-p t)
   :update-fraction
   (parse-json-quantity-field entry-object "baseFeeUpdateFraction"
                        :label (format nil "~A blob base fee update fraction"
                                       fork-name)
                        :required-p t)))

(defun parse-genesis-blob-schedule (object)
  (let ((schedule-object (json-object-field object "blobSchedule")))
    (when schedule-object
      (loop for (fork-name . entry-object)
              in (json-object-entries schedule-object "blobSchedule")
            for timestamp-field = (and (or (stringp fork-name) (symbolp fork-name))
                                       (genesis-blob-schedule-timestamp-field
                                        (if (stringp fork-name)
                                            fork-name
                                            (symbol-name fork-name))))
            for timestamp = (and timestamp-field
                                 (parse-json-quantity-field object timestamp-field))
            when timestamp
              collect (parse-genesis-blob-schedule-entry
                       timestamp entry-object fork-name)))))

(defun validate-chain-config-fork-order (config)
  "Reject impossible post-merge fork combinations at the genesis boundary."
  (when (and (chain-config-osaka-time config)
             (null (chain-config-prague-time config)))
    (block-validation-fail
     "Unsupported fork ordering: pragueTime is unset but osakaTime is enabled"))
  (when (and (chain-config-amsterdam-time config)
             (null (chain-config-osaka-time config)))
    (block-validation-fail
     "Unsupported fork ordering: osakaTime is unset but amsterdamTime is enabled"))
  (let ((last-name nil)
        (last-time nil))
    (dolist (fork
             (list
              (cons "shanghaiTime" (chain-config-shanghai-time config))
              (cons "cancunTime" (chain-config-cancun-time config))
              (cons "pragueTime" (chain-config-prague-time config))
              (cons "osakaTime" (chain-config-osaka-time config))
              (cons "ubtTime" (chain-config-ubt-time config))
              (cons "bpo1Time" (chain-config-bpo1-time config))
              (cons "bpo2Time" (chain-config-bpo2-time config))
              (cons "bpo3Time" (chain-config-bpo3-time config))
              (cons "bpo4Time" (chain-config-bpo4-time config))
              (cons "bpo5Time" (chain-config-bpo5-time config))
              (cons "amsterdamTime" (chain-config-amsterdam-time config))))
      (when (cdr fork)
        (when (and last-time (> last-time (cdr fork)))
          (block-validation-fail
           "Unsupported fork ordering: ~A at ~D follows ~A at ~D"
           (car fork) (cdr fork) last-name last-time))
        (setf last-name (car fork)
              last-time (cdr fork)))))
  config)

(defun chain-config-from-genesis-config (object)
  (let ((config
          (make-chain-config
   :chain-id (or (parse-json-quantity-field object "chainId") 1)
   :homestead-block (parse-json-quantity-field object "homesteadBlock")
   :dao-fork-block (parse-json-quantity-field object "daoForkBlock")
   :dao-fork-support
   (parse-genesis-boolean-field object "daoForkSupport" "daoForkSupport")
   :eip150-block (parse-json-quantity-field
                  object '("eip150Block" "tangerineWhistleBlock")
                  :label "eip150Block")
   :eip155-block (parse-json-quantity-field
                  object '("eip155Block" "spuriousDragonBlock")
                  :label "eip155Block")
   :eip158-block (parse-json-quantity-field
                  object '("eip158Block" "spuriousDragonBlock")
                  :label "eip158Block")
   :byzantium-block (parse-json-quantity-field object "byzantiumBlock")
   :constantinople-block (parse-json-quantity-field object "constantinopleBlock")
   :petersburg-block (parse-json-quantity-field object "petersburgBlock")
   :istanbul-block (parse-json-quantity-field object "istanbulBlock")
   :muir-glacier-block (parse-json-quantity-field object "muirGlacierBlock")
   :berlin-block (parse-json-quantity-field object "berlinBlock")
   :london-block (parse-json-quantity-field object "londonBlock")
   :arrow-glacier-block (parse-json-quantity-field object "arrowGlacierBlock")
   :gray-glacier-block (parse-json-quantity-field object "grayGlacierBlock")
   :shanghai-time (parse-json-quantity-field object "shanghaiTime")
   :cancun-time (parse-json-quantity-field object "cancunTime")
   :prague-time (parse-json-quantity-field object "pragueTime")
   :osaka-time (parse-json-quantity-field object "osakaTime")
   :bpo1-time (parse-json-quantity-field object "bpo1Time")
   :bpo2-time (parse-json-quantity-field object "bpo2Time")
   :bpo3-time (parse-json-quantity-field object "bpo3Time")
   :bpo4-time (parse-json-quantity-field object "bpo4Time")
   :bpo5-time (parse-json-quantity-field object "bpo5Time")
   :amsterdam-time (parse-json-quantity-field object "amsterdamTime")
   :ubt-time (parse-json-quantity-field object "ubtTime")
   :enable-ubt-at-genesis-p
   (parse-genesis-boolean-field object "enableUBTAtGenesis"
                                "enableUBTAtGenesis")
   :terminal-total-difficulty
   (parse-json-quantity-field object "terminalTotalDifficulty")
   :terminal-total-difficulty-passed
   (parse-genesis-boolean-field object "terminalTotalDifficultyPassed"
                                "terminalTotalDifficultyPassed")
   :merge-netsplit-block (parse-json-quantity-field object "mergeNetsplitBlock")
   :deposit-contract-address
   (parse-genesis-address-field object "depositContractAddress"
                                "Genesis deposit contract address")
   :custom-blob-schedule (parse-genesis-blob-schedule object))))
    (validate-chain-config-fork-order config)))
