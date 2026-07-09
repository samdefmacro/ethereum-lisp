(in-package #:ethereum-lisp.test)

(deftest block-body-validates-blob-gas-used
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (bad-version-hash (hash32-from-hex
                            "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :chain-id 1
                       :nonce 1
                       :max-priority-fee-per-gas 2
                       :max-fee-per-gas 3
                       :gas-limit 21000
                       :to address
                       :max-fee-per-blob-gas 4
                       :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction))))
    (is (= +blob-gas-per-blob+
           (blob-gas-used (block-transactions block))))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          +blob-gas-per-blob+)
    (is (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          (1+ +blob-gas-per-blob+))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction :to address
                                     :blob-versioned-hashes '())))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction
              :to address
              :blob-versioned-hashes (list bad-version-hash))))))))

(deftest blob-gas-limit-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (max-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (too-many-hashes (append max-hashes (list blob-hash)))
         (max-tx (make-blob-transaction :to address
                                        :blob-versioned-hashes max-hashes))
         (too-large-tx (make-blob-transaction
                        :to address
                        :blob-versioned-hashes too-many-hashes))
         (max-block (make-block :transactions (list max-tx)))
         (too-large-header
           (make-block-header :blob-gas-used (* (1+ +max-blobs-per-block+)
                                                +blob-gas-per-blob+)
                              :excess-blob-gas 0)))
    (setf (block-header-blob-gas-used (block-header max-block))
          (* +max-blobs-per-block+ +blob-gas-per-blob+))
    (is (validate-block-body-roots max-block))
    (signals block-validation-error
      (validate-blob-transaction-fields too-large-tx))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to nil
                              :blob-versioned-hashes (list blob-hash))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list nil))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list #(#x01 #x02)))))
    (signals block-validation-error
      (validate-block-blob-gas-fields too-large-header))))

(deftest osaka-block-body-allows-higher-aggregate-blob-limit
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest prague-block-body-uses-expanded-blob-schedule
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :prague-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest bpo-block-body-uses-scheduled-blob-limits
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat 3 collect blob-hash))
         (two-hashes (loop repeat 2 collect blob-hash))
         (bpo1-transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (bpo2-transactions
           (append bpo1-transactions
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes six-hashes))))
         (bpo3-transactions
           (append (loop repeat 5
                         collect (make-blob-transaction
                                  :to address
                                  :max-fee-per-blob-gas 1
                                  :blob-versioned-hashes six-hashes))
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes two-hashes))))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo1-time 30
                                    :bpo2-time 40
                                    :bpo3-time 50
                                    :bpo4-time 60))
         (bpo1-block
           (make-block :header (make-block-header
                                :number 1
                                :timestamp 30
                                :blob-gas-used
                                (* +bpo1-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo1-transactions))
         (bpo2-block
           (make-block :header (make-block-header
                                :number 2
                                :timestamp 40
                                :blob-gas-used
                                (* +bpo2-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions))
         (bpo3-block
           (make-block :header (make-block-header
                                :number 3
                                :timestamp 50
                                :blob-gas-used
                                (* +bpo3-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo3-transactions))
         (bpo4-block
           (make-block :header (make-block-header
                                :number 4
                                :timestamp 60
                                :blob-gas-used
                                (* +bpo4-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions)))
    (signals block-validation-error
      (validate-block-body-roots bpo1-block))
    (signals block-validation-error
      (validate-block-body-roots bpo2-block))
    (signals block-validation-error
      (validate-block-body-roots bpo3-block))
    (signals block-validation-error
      (validate-block-body-roots bpo4-block))
    (is (validate-block-body-against-config bpo1-block config))
    (is (validate-block-body-against-config bpo2-block config))
    (is (validate-block-body-against-config bpo3-block config))
    (is (validate-block-body-against-config bpo4-block config))))

(deftest custom-blob-schedule-body-validation-uses-active-entry
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (one-hash (list blob-hash))
         (config (make-chain-config
                  :london-block 0
                  :cancun-time 0
                  :custom-blob-schedule
                  (list (make-blob-schedule-entry :timestamp 20
                                                  :target-blobs 5
                                                  :max-blobs 7
                                                  :update-fraction 424242))))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes one-hash)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 20
                                      :blob-gas-used (* 7 +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

