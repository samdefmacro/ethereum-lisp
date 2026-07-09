(in-package #:ethereum-lisp.core)

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
   :target-blobs (parse-genesis-field entry-object "target"
                                      :label (format nil "~A blob target" fork-name)
                                      :required-p t)
   :max-blobs (parse-genesis-field entry-object "max"
                                   :label (format nil "~A blob max" fork-name)
                                   :required-p t)
   :update-fraction
   (parse-genesis-field entry-object "baseFeeUpdateFraction"
                        :label (format nil "~A blob base fee update fraction"
                                       fork-name)
                        :required-p t)))

(defun parse-genesis-blob-schedule (object)
  (let ((schedule-object (genesis-object-field object "blobSchedule")))
    (when schedule-object
      (loop for (fork-name . entry-object)
              in (genesis-object-entries schedule-object "blobSchedule")
            for timestamp-field = (and (or (stringp fork-name) (symbolp fork-name))
                                       (genesis-blob-schedule-timestamp-field
                                        (if (stringp fork-name)
                                            fork-name
                                            (symbol-name fork-name))))
            for timestamp = (and timestamp-field
                                 (parse-genesis-field object timestamp-field))
            when timestamp
              collect (parse-genesis-blob-schedule-entry
                       timestamp entry-object fork-name)))))

(defun chain-config-from-genesis-config (object)
  (make-chain-config
   :chain-id (or (parse-genesis-field object "chainId") 1)
   :homestead-block (parse-genesis-field object "homesteadBlock")
   :dao-fork-block (parse-genesis-field object "daoForkBlock")
   :dao-fork-support
   (parse-genesis-boolean-field object "daoForkSupport" "daoForkSupport")
   :eip150-block (parse-genesis-field
                  object '("eip150Block" "tangerineWhistleBlock")
                  :label "eip150Block")
   :eip155-block (parse-genesis-field
                  object '("eip155Block" "spuriousDragonBlock")
                  :label "eip155Block")
   :eip158-block (parse-genesis-field
                  object '("eip158Block" "spuriousDragonBlock")
                  :label "eip158Block")
   :byzantium-block (parse-genesis-field object "byzantiumBlock")
   :constantinople-block (parse-genesis-field object "constantinopleBlock")
   :petersburg-block (parse-genesis-field object "petersburgBlock")
   :istanbul-block (parse-genesis-field object "istanbulBlock")
   :muir-glacier-block (parse-genesis-field object "muirGlacierBlock")
   :berlin-block (parse-genesis-field object "berlinBlock")
   :london-block (parse-genesis-field object "londonBlock")
   :arrow-glacier-block (parse-genesis-field object "arrowGlacierBlock")
   :gray-glacier-block (parse-genesis-field object "grayGlacierBlock")
   :shanghai-time (parse-genesis-field object "shanghaiTime")
   :cancun-time (parse-genesis-field object "cancunTime")
   :prague-time (parse-genesis-field object "pragueTime")
   :osaka-time (parse-genesis-field object "osakaTime")
   :bpo1-time (parse-genesis-field object "bpo1Time")
   :bpo2-time (parse-genesis-field object "bpo2Time")
   :bpo3-time (parse-genesis-field object "bpo3Time")
   :bpo4-time (parse-genesis-field object "bpo4Time")
   :bpo5-time (parse-genesis-field object "bpo5Time")
   :amsterdam-time (parse-genesis-field object "amsterdamTime")
   :ubt-time (parse-genesis-field object "ubtTime")
   :enable-ubt-at-genesis-p
   (parse-genesis-boolean-field object "enableUBTAtGenesis"
                                "enableUBTAtGenesis")
   :terminal-total-difficulty
   (parse-genesis-field object "terminalTotalDifficulty")
   :terminal-total-difficulty-passed
   (parse-genesis-boolean-field object "terminalTotalDifficultyPassed"
                                "terminalTotalDifficultyPassed")
   :merge-netsplit-block (parse-genesis-field object "mergeNetsplitBlock")
   :deposit-contract-address
   (parse-genesis-address-field object "depositContractAddress"
                                "Genesis deposit contract address")
   :custom-blob-schedule (parse-genesis-blob-schedule object)))
