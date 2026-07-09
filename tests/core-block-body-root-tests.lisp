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

