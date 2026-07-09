(in-package #:ethereum-lisp.test)

(deftest block-body-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :withdrawals (list withdrawal))))
    (is (validate-block-body-roots block))
    (setf (block-header-transactions-root (block-header block)) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-list-before-derived-fields
  (let ((block (make-block)))
    (setf (block-transactions block) (list "not a transaction"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-ommer-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-ommers block) (list "not a header"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-commitment-fields-before-comparison
  (let* ((block (make-block))
         (header (block-header block)))
    (setf (block-header-ommers-hash header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-ommers-hash header) +empty-ommers-hash+
          (block-header-transactions-root header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-transactions-root header) +empty-trie-hash+
          (block-header-withdrawals-root header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-withdrawals-root header) nil
          (block-header-requests-hash header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validation-uses-chain-config-transaction-types
  (let* ((config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :prague-time 30))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient))))
         (berlin-block
           (make-block :header (make-block-header :number 5 :timestamp 0)
                       :transactions (list access-list)))
         (pre-london-block
           (make-block :header (make-block-header :number 9 :timestamp 0)
                       :transactions (list dynamic)))
         (london-block
           (make-block :header (make-block-header :number 10 :timestamp 0)
                       :transactions (list dynamic)))
         (pre-prague-block
           (make-block :header (make-block-header :number 10 :timestamp 29)
                       :transactions (list set-code)))
         (prague-block
           (make-block :header (make-block-header :number 10 :timestamp 30)
                       :transactions (list set-code))))
    (is (validate-block-body-against-config berlin-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-london-block config))
    (is (validate-block-body-against-config london-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-prague-block config))
    (is (validate-block-body-against-config prague-block config))))

(deftest block-body-validates-1559-fee-caps
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (valid (make-dynamic-fee-transaction
                 :to recipient
                 :max-priority-fee-per-gas 1
                 :max-fee-per-gas 5))
         (fee-too-low (make-dynamic-fee-transaction
                       :to recipient
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4))
         (tip-too-high (make-set-code-transaction
                        :to recipient
                        :max-priority-fee-per-gas 6
                        :max-fee-per-gas 5
                        :authorization-list
                        (list (make-set-code-authorization
                               :address recipient)))))
    (is (validate-block-body-roots
         (make-block :header (make-block-header :base-fee-per-gas 5)
                     :transactions (list valid))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list fee-too-low))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list tip-too-high))))))

(deftest block-body-validates-access-list-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-address-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry :address nil))))
         (bad-slot-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry
                   :address recipient
                   :storage-keys (list nil))))))
    (setf (block-transactions block) (list bad-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-slot-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-data-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-data-tx
           (make-legacy-transaction :to recipient
                                    :data "not bytes")))
    (setf (block-transactions block) (list bad-data-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-recipient-before-root-derivation
  (let* ((block (make-block))
         (bad-recipient-tx
           (make-legacy-transaction :to #(1 2 3))))
    (setf (block-transactions block) (list bad-recipient-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-scalars-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-nonce-tx
           (make-legacy-transaction :nonce (ash 1 64)
                                    :to recipient))
         (bad-gas-limit-tx
           (make-legacy-transaction :gas-limit (ash 1 64)
                                    :to recipient))
         (bad-value-tx
           (make-legacy-transaction :value (1+ +uint256-max+)
                                    :to recipient))
         (bad-fee-tx
           (make-dynamic-fee-transaction
            :to recipient
            :max-priority-fee-per-gas 2
            :max-fee-per-gas 1))
         (bad-blob-fee-tx
           (make-blob-transaction
            :to recipient
            :blob-versioned-hashes
            (list (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000000"))
            :max-fee-per-blob-gas (1+ +uint256-max+))))
    (dolist (transaction (list bad-nonce-tx
                               bad-gas-limit-tx
                               bad-value-tx
                               bad-fee-tx
                               bad-blob-fee-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-transaction-signature-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-legacy-v-tx
           (make-legacy-transaction :to recipient
                                    :v (1+ +uint256-max+)))
         (bad-typed-chain-tx
           (make-dynamic-fee-transaction :to recipient
                                         :chain-id (1+ +uint256-max+)))
         (bad-typed-y-parity-tx
           (make-dynamic-fee-transaction :to recipient
                                         :y-parity (1+ +uint256-max+)))
         (bad-typed-r-tx
           (make-dynamic-fee-transaction :to recipient
                                         :r (1+ +uint256-max+)))
         (bad-typed-s-tx
           (make-dynamic-fee-transaction :to recipient
                                         :s (1+ +uint256-max+))))
    (dolist (transaction (list bad-legacy-v-tx
                               bad-typed-chain-tx
                               bad-typed-y-parity-tx
                               bad-typed-r-tx
                               bad-typed-s-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-set-code-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (missing-to-tx
           (make-set-code-transaction
            :to nil
            :authorization-list
            (list (make-set-code-authorization :address recipient))))
         (missing-auth-tx
           (make-set-code-transaction :to recipient))
         (bad-auth-address-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization :address nil))))
         (bad-auth-chain-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization
                   :chain-id (1+ +uint256-max+)
                   :address recipient)))))
    (setf (block-transactions block) (list missing-to-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list missing-auth-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-chain-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-validation-combines-config-header-and-body-checks
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300))
         (parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 198
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent))
         (valid-header
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 300
                              :base-fee-per-gas 1000
                              :blob-gas-used 0
                              :excess-blob-gas 0
                              :parent-beacon-root (zero-hash32)))
         (valid-block
           (make-block :header valid-header
                       :withdrawals '()
                       :requests '()))
         (missing-withdrawals-parent
           (make-block-header :number 7
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 149
                              :base-fee-per-gas 1000))
         (missing-withdrawals-root
           (make-block :header
                       (make-block-header :parent-hash
                                          (block-header-hash
                                           missing-withdrawals-parent)
                                          :number 8
                                          :gas-limit 1024000
                                          :gas-used 0
                                          :timestamp 150
                                          :base-fee-per-gas 1000)))
         (pre-london-parent
           (make-block-header :number 8
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 10))
         (pre-london-header
           (make-block-header :parent-hash
                              (block-header-hash pre-london-parent)
                              :number 9
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 11))
         (pre-london-block
           (make-block :header pre-london-header
                       :transactions
                       (list (make-dynamic-fee-transaction
                              :to (address-from-hex
                                   "0x0000000000000000000000000000000000000001"))))))
    (is (validate-block-against-config parent valid-block config))
    (signals block-validation-error
      (validate-block-against-config missing-withdrawals-parent
                                     missing-withdrawals-root config))
    (signals block-validation-error
      (validate-block-against-config pre-london-parent pre-london-block
                                     (make-chain-config :london-block 10)))))

(deftest block-body-validates-execution-requests-hash
  (let* ((block (make-block :requests (list #(#x00 #xbb) #(#x01 #xaa))))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex
                  (execution-requests-hash (block-requests block)))
                 (hash32-to-hex (block-header-requests-hash header))))
    (setf (block-header-requests-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let ((header-without-requests
          (make-block-header :requests-hash
                             (execution-requests-hash (list #(#x01 #xaa))))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-requests))))
  (let ((pre-prague-block (make-block :requests (list #(#x01 #xaa)))))
    (setf (block-header-requests-hash (block-header pre-prague-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-prague-block))))

(deftest block-body-validates-request-list-before-hash-derivation
  (let ((block (make-block)))
    (setf (block-requests block) "not a request list"
          (block-requests-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-block-access-list-hash
  (let* ((block (make-block :block-access-list '()))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (setf (block-header-block-access-list-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (block (make-block :block-access-list (list account))))
    (is (validate-block-body-roots block))
    (is (bytes= (block-access-list-rlp (list account))
                (block-encoded-block-access-list block)))
    (is (string= (hash32-to-hex (block-access-list-hash (list account)))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block))))))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (encoded (block-access-list-rlp (list account)))
         (block (make-block :block-access-list-rlp encoded)))
    (is (block-block-access-list-present-p block))
    (is (bytes= encoded (block-encoded-block-access-list block)))
    (is (bytes= encoded
                (block-access-list-rlp (block-block-access-list block))))
    (is (string= (hash32-to-hex (block-access-list-rlp-hash encoded))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block)))))
    (is (validate-block-body-roots block))
    (setf (block-encoded-block-access-list block) (block-access-list-rlp '()))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (make-block :block-access-list (list account)
                  :block-access-list-rlp encoded)))
  (let ((header-without-body
          (make-block-header :block-access-list-hash
                             (block-access-list-hash '()))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-body))))
  (let ((pre-amsterdam-block (make-block :block-access-list '())))
    (setf (block-header-block-access-list-hash
           (block-header pre-amsterdam-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-amsterdam-block))))

(deftest block-body-validates-block-access-list-code-change-size
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-code (make-byte-vector
                      +block-access-list-amsterdam-max-code-size+))
         (oversized-code (make-byte-vector
                          (1+ +block-access-list-amsterdam-max-code-size+)))
         (limit-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code limit-code))))
         (oversized-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code oversized-code))))
         (limit-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list limit-account)))
         (oversized-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list oversized-account))))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))
    (signals block-validation-error
      (validate-block-body-roots
       limit-block
       :block-access-list-max-code-size
       +block-access-list-max-code-size+))))

(deftest block-body-validates-block-access-list-item-gas-limit
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (read-slot (hash32-from-hex
                     "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (write-slot (hash32-from-hex
                      "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes (make-block-access-slot-writes
                       :slot write-slot
                       :accesses
                       (list (make-block-access-storage-write
                              :tx-index 0
                              :value-after 7))))
         (account (make-block-access-account
                   :address address
                   :storage-writes (list slot-writes)
                   :storage-reads (list read-slot)))
         (access-list (list account))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 3 +block-access-list-item-gas-cost+))
                       :block-access-list access-list))
         (oversized-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 2 +block-access-list-item-gas-cost+))
                       :block-access-list access-list)))
    (is (= 3 (block-access-list-item-count access-list)))
    (is (validate-block-access-list-fields access-list
                                           :max-items 3))
    (signals block-validation-error
      (validate-block-access-list-fields access-list
                                         :max-items 2))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))))

(deftest block-body-validates-block-access-list-shape-before-hash
  (let ((block (make-block)))
    (setf (block-block-access-list block) "not a block access list"
          (block-block-access-list-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

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

(deftest blob-sidecar-field-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction (make-blob-transaction
                       :to address
                       :blob-versioned-hashes (list versioned-hash)))
         (sidecar (make-blob-sidecar :blobs (list blob)
                                     :commitments (list commitment)
                                     :proofs (list proof))))
    (is (validate-blob-sidecar-fields sidecar :transaction transaction))
    (is (bytes= (hash32-bytes versioned-hash)
                (hash32-bytes (first (blob-sidecar-versioned-hashes sidecar)))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       sidecar
       :transaction transaction
       :require-proof-verification t))
    (let ((observed nil))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (setf observed
                      (list verified-blob verified-commitment verified-proof))
                t)))
        (is (kzg-blob-proof-verification-available-p))
        (is (validate-blob-sidecar-fields
             sidecar
             :transaction transaction
             :require-proof-verification t)))
      (is (bytes= blob (first observed)))
      (is (bytes= commitment (second observed)))
      (is (bytes= proof (third observed))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proof)
              (declare (ignore verified-blob verified-commitment
                               verified-proof))
              nil)))
      (signals block-validation-error
        (validate-blob-sidecar-fields
         sidecar
         :transaction transaction
         :require-proof-verification t)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs '())
       :transaction transaction))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list #())
                          :commitments (list commitment)
                          :proofs (list proof))))
    (let ((invalid-blob (copy-seq blob))
          (called nil))
      (replace invalid-blob
               (ethereum-lisp.crypto::integer-to-fixed-bytes
                ethereum-lisp.core::+kzg-field-modulus+
                32)
               :start1 0)
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (declare (ignore verified-blob verified-commitment
                                 verified-proof))
                (setf called t)
                t)))
        (signals block-validation-error
          (validate-blob-sidecar-fields
           (make-blob-sidecar :blobs (list invalid-blob)
                              :commitments (list commitment)
                              :proofs (list proof))
           :require-proof-verification t)))
      (is (null called)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list #())
                          :proofs (list proof))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs (list #()))))
    (let ((other-commitment (copy-seq commitment)))
      (setf (aref other-commitment 0) 1)
      (signals block-validation-error
        (validate-blob-sidecar-fields
         (make-blob-sidecar :blobs (list blob)
                            :commitments (list other-commitment)
                            :proofs (list proof))
         :transaction transaction)))))

(deftest kzg-command-verifier-adapter
  (let* ((suffix (format nil "~A-~A" (get-universal-time) (random 1000000)))
         (script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.sh" suffix)
            (uiop:temporary-directory)))
         (sleep-script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-sleep-~A.sh" suffix)
            (uiop:temporary-directory)))
         (log-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.log" suffix)
            (uiop:temporary-directory)))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (z (make-byte-vector ethereum-lisp.core::+kzg-field-element-size+))
         (y (make-byte-vector ethereum-lisp.core::+kzg-field-element-size+))
         (old-point-verifier *kzg-point-proof-verifier*)
         (old-blob-verifier *kzg-blob-proof-verifier*))
    (labels ((file-contents (path)
               (with-open-file (stream path :direction :input)
                 (let ((contents (make-string (file-length stream))))
                   (read-sequence contents stream)
                   contents))))
      (unwind-protect
           (progn
             (with-open-file (stream script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "log=\"$1\"~%")
               (format stream "verdict=\"$2\"~%")
               (format stream "shift 2~%")
               (format stream "case \"$1\" in~%")
               (format stream "  point) printf 'point %s %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" \"${#5}\" > \"$log\" ;;~%")
               (format stream "  blob) printf 'blob %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" > \"$log\" ;;~%")
               (format stream "  *) printf 'unknown\\n' > \"$log\" ;;~%")
               (format stream "esac~%")
               (format stream "if [ \"$verdict\" = accept ]; then echo true; else echo false; fi~%"))
             (with-open-file (stream sleep-script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "sleep 2~%")
               (format stream "echo true~%"))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "accept"))
             (is (kzg-proof-verification-available-p))
             (is (verify-kzg-point-proof commitment z y proof))
             (is (string= (format nil "point 98 66 66 98~%")
                          (file-contents log-path)))
             (is (verify-kzg-blob-proof blob commitment proof))
             (is (string=
                  (format nil "blob ~D 98 98~%"
                          (+ 2 (* 2 +blob-byte-size+)))
                  (file-contents log-path)))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "reject"))
             (signals error
               (verify-kzg-point-proof commitment z y proof))
             (signals error
               (verify-kzg-blob-proof blob commitment proof))
             (let ((ethereum-lisp.core::*kzg-verifier-command-timeout-seconds*
                     0))
               (configure-kzg-proof-command-verifiers
                (list "sh" (namestring sleep-script-path)))
               (signals error
                 (verify-kzg-point-proof commitment z y proof)))
             (signals error
               (make-kzg-point-proof-command-verifier '())))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)
        (when (probe-file script-path)
          (delete-file script-path))
        (when (probe-file sleep-script-path)
          (delete-file sleep-script-path))
        (when (probe-file log-path)
          (delete-file log-path))))))

(deftest kzg-go-ethereum-command-verifier-replays-canonical-vectors
  (let ((script (repo-kzg-verifier-command)))
    (let* ((valid-blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (valid-commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-point-z
             (hex-to-bytes
              "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000"))
           (valid-point-y
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000002"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-point-commitment
             (hex-to-bytes
              "0xb49d88afcd7f6c61a8ea69eff5f609d2432b47e7e4cd50b02cdddb4e0c1460517e8df02e4e64dc55e3d8ca192d57193a"))
           (invalid-point-z
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (invalid-point-y
             (hex-to-bytes
              "0x443e7af5274b52214ea6c775908c54519fea957eecd98069165a8b771082fd51"))
           (invalid-point-proof
             (hex-to-bytes
              "0xa7de1e32bb336b85e42ff5028167042188317299333f091dd88675e84a550577bfa564b2f57cd2498e2acf875e0aaa40"))
           (invalid-blob-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             ;; Sources: go-eth-kzg v1.5.0 kzg-mainnet
             ;; verify_kzg_proof_case_correct_proof_395cf6d697d1a743,
             ;; verify_kzg_proof_case_incorrect_proof_444b73ff54a19b44,
             ;; verify_blob_kzg_proof_case_correct_proof_a87a4e636e0f58fb,
             ;; verify_blob_kzg_proof_case_incorrect_proof_a87a4e636e0f58fb.
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (verify-kzg-point-proof
                  valid-commitment
                  valid-point-z
                  valid-point-y
                  valid-proof))
             (signals error
               (verify-kzg-point-proof
                invalid-point-commitment
                invalid-point-z
                invalid-point-y
                invalid-point-proof))
             (is (verify-kzg-blob-proof
                  valid-blob
                  valid-commitment
                  valid-proof))
             (signals error
               (verify-kzg-blob-proof
                valid-blob
                valid-commitment
                invalid-blob-proof)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))

(deftest blob-sidecar-field-validation-replays-real-kzg-vector
  (let ((script (repo-kzg-verifier-command)))
    (let* ((blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (versioned-hash
             (kzg-commitment-to-versioned-hash commitment))
           (transaction
             (make-blob-transaction
              :to (address-from-hex
                   "0x0000000000000000000000000000000000000001")
              :blob-versioned-hashes (list versioned-hash)))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (validate-blob-sidecar-fields
                  (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list valid-proof))
                  :transaction transaction
                  :require-proof-verification t))
             (signals block-validation-error
               (validate-blob-sidecar-fields
                (make-blob-sidecar
                 :blobs (list blob)
                 :commitments (list commitment)
                 :proofs (list invalid-proof))
                :transaction transaction
                :require-proof-verification t)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))

(deftest blob-transaction-fee-cap-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (overwide-transaction (make-blob-transaction
                                :to address
                                :max-fee-per-blob-gas (1+ +uint256-max+)
                                :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 2 (block-header-blob-base-fee header)))
    (signals block-validation-error
      (validate-blob-transaction-fee-cap overwide-transaction 2))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (blob-transaction-max-fee-per-blob-gas transaction) 2)
    (setf (block-header-transactions-root header)
          (transaction-list-root (block-transactions block)))
    (is (validate-block-body-roots block)))
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-number header) 1
          (block-header-timestamp header) 10
          (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 1 (block-header-blob-base-fee
              header
              :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest block-withdrawals-presence-is-distinct-from-empty-list
  (let* ((empty-shanghai-block (make-block :withdrawals '()))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data empty-shanghai-block)))
         (payload-object (engine-rpc-executable-data-object payload))
         (decoded-payload
           (engine-rpc-executable-data-from-object payload-object))
         (decoded-block (executable-data-to-block-no-hash decoded-payload))
         (header-with-missing-body
           (make-block-header :withdrawals-root (withdrawal-list-root '())))
         (missing-body-block (make-block :header header-with-missing-body))
         (pre-shanghai-block (make-block :withdrawals '())))
    (is (block-withdrawals-present-p empty-shanghai-block))
    (is (executable-data-withdrawals-present-p payload))
    (is (assoc "withdrawals" payload-object :test #'string=))
    (is (null (cdr (assoc "withdrawals" payload-object :test #'string=))))
    (is (executable-data-withdrawals-present-p decoded-payload))
    (is (block-withdrawals-present-p decoded-block))
    (is (null (block-withdrawals decoded-block)))
    (is (validate-block-body-roots empty-shanghai-block))
    (signals block-validation-error
      (validate-block-body-roots missing-body-block))
    (setf (block-header-withdrawals-root (block-header pre-shanghai-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-shanghai-block))))

(deftest block-body-validates-withdrawal-fields
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address recipient
                                      :amount 1))
         (block (make-block :withdrawals (list withdrawal))))
    (setf (withdrawal-amount withdrawal) (1+ +uint256-max+))
    (signals block-validation-error
      (validate-withdrawal-fields withdrawal))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-withdrawal-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-withdrawals block) "not a withdrawal list"
          (block-withdrawals-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest post-merge-block-body-rejects-ommers
  (let* ((ommer (make-block-header :beneficiary
                                   (address-from-hex
                                    "0x00000000000000000000000000000000000000dd")
                                   :difficulty 1
                                   :number 7))
         (block (make-block :header (make-block-header :difficulty 0
                                                       :number 8)
                            :ommers (list ommer))))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-execution-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic) :data #(7)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (is (= 21000 (receipts-gas-used (list receipt))))
    (is (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21001)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21000
          (block-header-receipts-root header) (zero-hash32))
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))))

(deftest block-execution-validates-commitment-fields-before-comparison
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (setf (block-header-logs-bloom header) "not a bloom")
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-logs-bloom header) (make-byte-vector 256)
          (block-header-receipts-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-receipts-root header) (receipt-list-root (list receipt))
          (block-header-state-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) nil))))

(deftest block-execution-validates-receipts-before-derived-fields
  (let* ((state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (good-receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block (make-block :receipts (list good-receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block "not a receipt list" state-root))
    (signals block-validation-error
      (validate-block-execution-roots block (list "not a receipt") state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :status 1
                           :cumulative-gas-used (ash 1 64)))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :post-state "not bytes"
                           :cumulative-gas-used 21000))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :address nil))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :topics (list nil)))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :data "not bytes"))))
       state-root))))

(deftest block-execution-rejects-pre-byzantium-receipts-by-config
  (let* ((post-state (make-byte-vector 32 :initial-element #x11))
         (receipt (make-receipt :post-state post-state
                                :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block))
         (pre-byzantium-config (make-chain-config :byzantium-block 100))
         (byzantium-config (make-chain-config :byzantium-block 0)))
    (setf (block-header-number header) 42
          (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root
                                      :chain-config pre-byzantium-config))
    (is (validate-block-execution-roots block (list receipt) state-root
                                        :chain-config byzantium-config))))

(deftest block-execution-validates-receipt-cumulative-gas-order
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 30000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root)))
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 21000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root))))

(deftest bloom-add-and-lookup-log-values
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic)))
         (bloom (receipt-bloom (list log))))
    (is (bloom-contains-p bloom (address-bytes address)))
    (is (bloom-contains-p bloom (hash32-bytes topic)))))

(deftest receipt-rlp-and-root
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (root (receipt-list-root (list receipt))))
    (is (= 267 (length (receipt-rlp receipt))))
    (is (string= "0xf9010801825208"
                 (subseq (bytes-to-hex (receipt-rlp receipt)) 0 16)))
    (is (hash32-p root))))

(deftest typed-receipt-encoding-and-root
  (let* ((legacy (make-legacy-transaction :gas-price 1))
         (dynamic (make-dynamic-fee-transaction
                   :max-priority-fee-per-gas 1
                   :max-fee-per-gas 2))
         (legacy-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (dynamic-receipt (make-receipt :status 1
                                        :cumulative-gas-used 42000))
         (typed-encoding
           (transaction-receipt-encoding dynamic dynamic-receipt))
         (root
           (transaction-receipt-list-root
            (list legacy dynamic)
            (list legacy-receipt dynamic-receipt))))
    (is (= 2 (transaction-type dynamic)))
    (is (= 2 (aref typed-encoding 0)))
    (is (bytes= (receipt-rlp dynamic-receipt)
                (subseq typed-encoding 1)))
    (is (string= (hash32-to-hex (receipt-list-root
                                 (list legacy-receipt)))
                 (hash32-to-hex
                  (transaction-receipt-list-root
                   (list legacy)
                   (list legacy-receipt)))))
    (is (not (string= (hash32-to-hex
                       (receipt-list-root
                        (list legacy-receipt dynamic-receipt)))
                      (hash32-to-hex root))))
    (signals block-validation-error
      (transaction-receipt-list-root (list legacy) '()))))

(deftest transaction-list-root-empty-and-single
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (hash32-to-hex (transaction-list-root '()))))
  (let ((root (transaction-list-root
               (list (make-legacy-transaction :nonce 1
                                              :gas-price 2
                                              :gas-limit 3
                                              :value 4
                                              :data #(96 0)
                                              :v 27
                                              :r 5
                                              :s 6)))))
    (is (hash32-p root))))

(deftest typed-transaction-encodings
  (let* ((recipient (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (tx1 (make-access-list-transaction :chain-id 1
                                            :nonce 2
                                            :gas-price 3
                                            :gas-limit 4
                                            :to recipient
                                            :value 5
                                            :data #(6)
                                            :access-list access
                                            :y-parity 1
                                            :r 7
                                            :s 8))
         (tx2 (make-dynamic-fee-transaction :chain-id 1
                                            :nonce 2
                                            :max-priority-fee-per-gas 3
                                            :max-fee-per-gas 4
                                            :gas-limit 5
                                            :to recipient
                                            :value 6
                                            :data #(7)
                                            :access-list access
                                            :y-parity 1
                                            :r 8
                                            :s 9))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (tx3 (make-blob-transaction :chain-id 1
                                      :nonce 2
                                      :max-priority-fee-per-gas 3
                                      :max-fee-per-gas 4
                                      :gas-limit 5
                                      :to recipient
                                      :value 6
                                      :data #(7)
                                      :access-list access
                                      :max-fee-per-blob-gas 10
                                      :blob-versioned-hashes (list blob-hash)
                                      :y-parity 1
                                      :r 8
                                      :s 9))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (tx4 (make-set-code-transaction :chain-id 1
                                          :nonce 2
                                          :max-priority-fee-per-gas 3
                                          :max-fee-per-gas 4
                                          :gas-limit 5
                                          :to recipient
                                          :value 6
                                          :data #(7)
                                          :access-list access
                                          :authorization-list (list authorization)
                                          :y-parity 1
                                          :r 8
                                          :s 9))
         (blob-encoding (blob-transaction-encoding tx3))
         (blob-payload (rlp-decode-one (subseq blob-encoding 1)))
         (blob-items (rlp-list-items blob-payload))
         (blob-hash-items (rlp-list-items (nth 10 blob-items)))
         (set-code-encoding (set-code-transaction-encoding tx4))
         (set-code-payload (rlp-decode-one (subseq set-code-encoding 1)))
         (set-code-items (rlp-list-items set-code-payload))
         (authorization-items
           (rlp-list-items
            (first (rlp-list-items (nth 9 set-code-items))))))
    (is (= 1 (aref (access-list-transaction-encoding tx1) 0)))
    (is (= 2 (aref (dynamic-fee-transaction-encoding tx2) 0)))
    (is (= 3 (aref blob-encoding 0)))
    (is (= 4 (aref set-code-encoding 0)))
    (is (= 14 (length blob-items)))
    (is (= 10 (bytes-to-integer (nth 9 blob-items))))
    (is (= 1 (length blob-hash-items)))
    (is (bytes= (hash32-bytes blob-hash) (first blob-hash-items)))
    (is (= 13 (length set-code-items)))
    (is (= 6 (length authorization-items)))
    (is (= 11 (bytes-to-integer (third authorization-items))))
    (let ((decoded (transaction-from-encoding
                    (access-list-transaction-encoding tx1))))
      (is (typep decoded 'access-list-transaction))
      (is (= 1 (access-list-transaction-chain-id decoded)))
      (is (= 2 (access-list-transaction-nonce decoded)))
      (is (= 3 (access-list-transaction-gas-price decoded)))
      (is (= 4 (access-list-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (access-list-transaction-to decoded))))
      (is (= 5 (access-list-transaction-value decoded)))
      (is (bytes= #(6) (access-list-transaction-data decoded)))
      (is (= 1 (length (access-list-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (access-list-transaction-access-list
                                   decoded)))))))
      (is (= 1 (access-list-transaction-y-parity decoded)))
      (is (= 7 (access-list-transaction-r decoded)))
      (is (= 8 (access-list-transaction-s decoded)))
      (is (bytes= (access-list-transaction-encoding tx1)
                  (access-list-transaction-encoding decoded))))
    (signals block-validation-error
      (access-list-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (access-list-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4
                       (make-byte-vector 20)
                       5
                       (make-byte-vector 1 :initial-element 6)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 19)
                         (make-rlp-list)))
                       1 7 8))))
    (let ((decoded (transaction-from-encoding
                    (dynamic-fee-transaction-encoding tx2))))
      (is (typep decoded 'dynamic-fee-transaction))
      (is (= 1 (dynamic-fee-transaction-chain-id decoded)))
      (is (= 2 (dynamic-fee-transaction-nonce decoded)))
      (is (= 3 (dynamic-fee-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (dynamic-fee-transaction-max-fee-per-gas decoded)))
      (is (= 5 (dynamic-fee-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (dynamic-fee-transaction-to decoded))))
      (is (= 6 (dynamic-fee-transaction-value decoded)))
      (is (bytes= #(7) (dynamic-fee-transaction-data decoded)))
      (is (= 1 (length (dynamic-fee-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (dynamic-fee-transaction-access-list
                                   decoded)))))))
      (is (= 1 (dynamic-fee-transaction-y-parity decoded)))
      (is (= 8 (dynamic-fee-transaction-r decoded)))
      (is (= 9 (dynamic-fee-transaction-s decoded)))
      (is (bytes= (dynamic-fee-transaction-encoding tx2)
                  (dynamic-fee-transaction-encoding decoded))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 20)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 20)
                         (make-rlp-list (make-byte-vector 31))))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (blob-transaction-encoding tx3))))
      (is (typep decoded 'blob-transaction))
      (is (= 1 (blob-transaction-chain-id decoded)))
      (is (= 2 (blob-transaction-nonce decoded)))
      (is (= 3 (blob-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (blob-transaction-max-fee-per-gas decoded)))
      (is (= 5 (blob-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (blob-transaction-to decoded))))
      (is (= 6 (blob-transaction-value decoded)))
      (is (bytes= #(7) (blob-transaction-data decoded)))
      (is (= 1 (length (blob-transaction-access-list decoded))))
      (is (= 10 (blob-transaction-max-fee-per-blob-gas decoded)))
      (is (= 1 (length (blob-transaction-blob-versioned-hashes decoded))))
      (is (bytes= (hash32-bytes blob-hash)
                  (hash32-bytes
                   (first (blob-transaction-blob-versioned-hashes decoded)))))
      (is (= 1 (blob-transaction-y-parity decoded)))
      (is (= 8 (blob-transaction-r decoded)))
      (is (= 9 (blob-transaction-s decoded)))
      (is (bytes= (blob-transaction-encoding tx3)
                  (blob-transaction-encoding decoded))))
    (signals block-validation-error
      (blob-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (hash32-bytes blob-hash))
                       1 8 9))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (make-byte-vector 31))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (set-code-transaction-encoding tx4))))
      (is (typep decoded 'set-code-transaction))
      (is (= 1 (set-code-transaction-chain-id decoded)))
      (is (= 2 (set-code-transaction-nonce decoded)))
      (is (= 3 (set-code-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (set-code-transaction-max-fee-per-gas decoded)))
      (is (= 5 (set-code-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (set-code-transaction-to decoded))))
      (is (= 6 (set-code-transaction-value decoded)))
      (is (bytes= #(7) (set-code-transaction-data decoded)))
      (is (= 1 (length (set-code-transaction-access-list decoded))))
      (is (= 1 (length (set-code-transaction-authorization-list decoded))))
      (let ((decoded-authorization
              (first (set-code-transaction-authorization-list decoded))))
        (is (= 1 (set-code-authorization-chain-id decoded-authorization)))
        (is (string= (address-to-hex recipient)
                     (address-to-hex
                      (set-code-authorization-address
                       decoded-authorization))))
        (is (= 11 (set-code-authorization-nonce decoded-authorization)))
        (is (= 1 (set-code-authorization-y-parity decoded-authorization)))
        (is (= 12 (set-code-authorization-r decoded-authorization)))
        (is (= 13 (set-code-authorization-s decoded-authorization))))
      (is (= 1 (set-code-transaction-y-parity decoded)))
      (is (= 8 (set-code-transaction-r decoded)))
      (is (= 9 (set-code-transaction-s decoded)))
      (is (bytes= (set-code-transaction-encoding tx4)
                  (set-code-transaction-encoding decoded))))
    (signals block-validation-error
      (set-code-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (address-bytes recipient)
                                       11 1 12 13))
                       1 8 9))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (make-byte-vector 0)
                                       11 1 12 13))
                       1 8 9))))
    (is (hash32-p (transaction-hash tx1)))
    (is (hash32-p (blob-transaction-signing-hash tx3)))
    (is (not (string= (hash32-to-hex (blob-transaction-signing-hash tx3))
                      (hash32-to-hex (blob-transaction-hash tx3)))))
    (is (hash32-p (set-code-authorization-signing-hash authorization)))
    (is (hash32-p (set-code-transaction-signing-hash tx4)))
    (is (not (string= (hash32-to-hex (set-code-transaction-signing-hash tx4))
                      (hash32-to-hex (set-code-transaction-hash tx4)))))
    (is (hash32-p (transaction-list-root (list tx1 tx2 tx3 tx4))))))
