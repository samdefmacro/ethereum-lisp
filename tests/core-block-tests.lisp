(in-package #:ethereum-lisp.test)

(deftest block-package-boundary
  (let ((blocks (find-package '#:ethereum-lisp.blocks))
        (transactions (find-package '#:ethereum-lisp.transactions))
        (receipts (find-package '#:ethereum-lisp.receipts))
        (requests (find-package '#:ethereum-lisp.execution-requests))
        (access-lists (find-package '#:ethereum-lisp.block-access-lists))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list blocks))))
    (dolist (dependency (list transactions receipts requests access-lists))
      (is (member dependency (package-use-list blocks))))
    (dolist (name '("BLOCK-HEADER" "MAKE-BLOCK" "BLOCK-FROM-RLP"))
      (multiple-value-bind (block-symbol block-status)
          (find-symbol name blocks)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external block-status))
          (is (eq :external core-status))
          (is (eq block-symbol core-symbol)))))
    (dolist (name '("EXECUTABLE-DATA" "CHAIN-STORE-CHECKPOINT"))
      (multiple-value-bind (symbol status)
          (find-symbol name blocks)
        (is (null symbol))
        (is (null status))))))

(deftest block-from-parts-preserves-header-commitments
  (let* ((transactions-root (zero-hash32))
         (header (make-block-header :transactions-root transactions-root))
         (block (ethereum-lisp.blocks:make-block-from-parts
                 :header header
                 :transactions (list (make-legacy-transaction)))))
    (is (eq header (block-header block)))
    (is (eq transactions-root
            (block-header-transactions-root (block-header block))))))

(deftest transaction-type-validation-uses-chain-config
  (let* ((config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :cancun-time 20
                                    :prague-time 30))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (legacy (make-legacy-transaction :to recipient))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (blob (make-blob-transaction
                :to recipient
                :blob-versioned-hashes (list blob-hash)))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient)))))
    (is (validate-transaction-type-for-config legacy config 0 0))
    (signals block-validation-error
      (validate-transaction-type-for-config access-list config 4 0))
    (is (validate-transaction-type-for-config access-list config 5 0))
    (signals block-validation-error
      (validate-transaction-type-for-config dynamic config 9 0))
    (is (validate-transaction-type-for-config dynamic config 10 0))
    (signals block-validation-error
      (validate-transaction-type-for-config blob config 10 19))
    (is (validate-transaction-type-for-config blob config 10 20))
    (signals block-validation-error
      (validate-transaction-type-for-config set-code config 10 29))
    (is (validate-transaction-type-for-config set-code config 10 30))))

(deftest block-header-basic-parent-validation
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (parent-hash parent-hash)
                        (number 8)
                        (gas-limit 1024000)
                        (gas-used 1000)
                        (timestamp 101)
                        (extra-data #())
                        (base-fee-per-gas 1000)
                        withdrawals-root
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root
                        requests-hash)
             (make-block-header :parent-hash parent-hash
                                :number number
                                :gas-limit gas-limit
                                :gas-used gas-used
                                :timestamp timestamp
                                :extra-data extra-data
                                :base-fee-per-gas base-fee-per-gas
                                :withdrawals-root withdrawals-root
                                :blob-gas-used blob-gas-used
                                :excess-blob-gas excess-blob-gas
                                :parent-beacon-root parent-beacon-root
                                :requests-hash requests-hash)))
      (is (validate-block-header-basics parent (child)))
      (is (validate-gas-limit-delta 1024000 1024999))
      (is (validate-block-header-basics
           parent
           (child :blob-gas-used +blob-gas-per-blob+
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32))))
      (is (validate-block-header-basics
           parent
           (child :requests-hash (execution-requests-hash '()))
           :requests-enabled-p t))
      (is (validate-block-header-basics
           parent
           (child :withdrawals-root (withdrawal-list-root '()))
           :withdrawals-enabled-p t))
      (is (= 0 (expected-excess-blob-gas parent)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :parent-hash (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent (child :number 9)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :timestamp 100)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :gas-used 1024001)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :gas-limit 1025000)))
      (signals block-validation-error
        (validate-gas-limit-delta 1024000 4999))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used
                                             +blob-gas-per-blob+)))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used 1
                                             :excess-blob-gas 0
                                             :parent-beacon-root
                                             (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :parent-beacon-root
                                             (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent (child)
                                      :requests-enabled-p t))
      (signals block-validation-error
        (validate-block-header-basics parent (child)
                                      :withdrawals-enabled-p t))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :withdrawals-root (withdrawal-list-root '()))
         :withdrawals-enabled-p nil))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :requests-hash (execution-requests-hash '()))
         :requests-enabled-p nil))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used
                                             +blob-gas-per-blob+
                                             :excess-blob-gas 0)))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :extra-data
                (make-array (1+ +maximum-extra-data-size+)
                            :element-type '(unsigned-byte 8)
                            :initial-element 0))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :base-fee-per-gas 999))))))

(deftest block-header-validates-field-shapes-before-comparison
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (parent-hash parent-hash)
                        beneficiary
                        state-root
                        logs-bloom
                        (extra-data #())
                        nonce
                        (base-fee-per-gas 1000)
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root)
             (make-block-header :parent-hash parent-hash
                                :beneficiary beneficiary
                                :state-root state-root
                                :number 8
                                :gas-limit 1024000
                                :gas-used 1000
                                :timestamp 101
                                :logs-bloom logs-bloom
                                :extra-data extra-data
                                :nonce nonce
                                :base-fee-per-gas base-fee-per-gas
                                :blob-gas-used blob-gas-used
                                :excess-blob-gas excess-blob-gas
                                :parent-beacon-root parent-beacon-root)))
      (signals block-validation-error
        (validate-block-header-basics "not a header" (child)))
      (signals block-validation-error
        (validate-block-header-basics parent "not a header"))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :parent-hash "not a hash")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :beneficiary "not an address")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :state-root "not a root")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :logs-bloom #())))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :extra-data "not bytes")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :nonce #())))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :base-fee-per-gas "fee")))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :blob-gas-used "blob"
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)))))))

(deftest post-merge-header-validates-seal-fields
  (let* ((parent (make-block-header :number 7
                                    :difficulty 1
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (difficulty 0)
                        (nonce (make-byte-vector 8))
                        (ommers-hash +empty-ommers-hash+)
                        (parent-hash parent-hash)
                        (number 8)
                        (gas-limit 1024000)
                        (timestamp 101))
             (make-block-header :parent-hash parent-hash
                                :ommers-hash ommers-hash
                                :difficulty difficulty
                                :number number
                                :gas-limit gas-limit
                                :gas-used 1000
                                :timestamp timestamp
                                :nonce nonce
                                :base-fee-per-gas 1000)))
      (is (validate-block-header-basics parent (child)))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :nonce #(#x00 #x00 #x00 #x00 #x00 #x00 #x00 #x01))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :ommers-hash (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :gas-limit #x8000000000000000)))
      (let ((post-merge-parent (child)))
        (signals block-validation-error
          (validate-block-header-basics
           post-merge-parent
           (child :difficulty 1
                  :number 9
                  :timestamp 102
                  :parent-hash (block-header-hash post-merge-parent))))))))

(deftest block-header-validation-uses-chain-config-forks
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300
                                    :amsterdam-time 400))
         (parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 198
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (timestamp 200)
                        withdrawals-root
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root
                        requests-hash
                        block-access-list-hash
                        slot-number)
             (make-block-header
              :parent-hash parent-hash
              :number 8
              :gas-limit 1024000
              :gas-used 1000
              :timestamp timestamp
              :base-fee-per-gas 1000
              :withdrawals-root withdrawals-root
              :blob-gas-used blob-gas-used
              :excess-blob-gas excess-blob-gas
              :parent-beacon-root parent-beacon-root
              :requests-hash requests-hash
              :block-access-list-hash block-access-list-hash
              :slot-number slot-number)))
      (is (validate-block-header-against-config
           parent
           (child :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '()))
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 300
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '()))
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 400
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '())
                  :block-access-list-hash +empty-ommers-hash+
                  :slot-number 0)
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 300
                  :blob-gas-used (* +osaka-max-blobs-per-block+
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '()))
           config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 149
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 150)
         config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child) config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 199
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 300
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 300
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '())
                :requests-hash (execution-requests-hash '())
                :block-access-list-hash +empty-ommers-hash+
                :slot-number 0)
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 400
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '())
                :requests-hash (execution-requests-hash '()))
         config)))))

(deftest amsterdam-header-slot-number-must-exceed-parent
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300
                                    :amsterdam-time 400))
         (parent (make-block-header :number 8
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 400
                                    :base-fee-per-gas 1000
                                    :withdrawals-root (withdrawal-list-root '())
                                    :blob-gas-used 0
                                    :excess-blob-gas 0
                                    :parent-beacon-root (zero-hash32)
                                    :requests-hash (execution-requests-hash '())
                                    :block-access-list-hash +empty-ommers-hash+
                                    :slot-number 10))
         (parent-hash (block-header-hash parent)))
    (flet ((child (slot-number)
             (make-block-header
              :parent-hash parent-hash
              :number 9
              :gas-limit 1024000
              :gas-used 1000
              :timestamp 410
              :base-fee-per-gas 1000
              :withdrawals-root (withdrawal-list-root '())
              :blob-gas-used 0
              :excess-blob-gas 0
              :parent-beacon-root (zero-hash32)
              :requests-hash (execution-requests-hash '())
              :block-access-list-hash +empty-ommers-hash+
              :slot-number slot-number)))
      (is (validate-block-header-against-config parent (child 11) config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child 10) config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child 9) config)))))

(deftest london-fork-block-validates-gas-limit-against-elastic-parent
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100))
         (parent-hash (block-header-hash parent))
         (valid-london
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 2048999
                              :gas-used 1000
                              :timestamp 101
                              :base-fee-per-gas +initial-base-fee+))
         (too-far
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 2050000
                              :gas-used 1000
                              :timestamp 101
                              :base-fee-per-gas +initial-base-fee+)))
    (is (= 2048000 (adjusted-parent-gas-limit-for-1559 parent nil)))
    (is (validate-block-header-basics parent valid-london
                                      :london-parent-p nil))
    (signals block-validation-error
      (validate-block-header-basics parent too-far
                                    :london-parent-p nil))))

(deftest excess-blob-gas-calculation-and-validation
  (let* ((parent (make-block-header :blob-gas-used (* 4 +blob-gas-per-blob+)
                                    :excess-blob-gas (* 2 +blob-gas-per-blob+)))
         (expected (* 3 +blob-gas-per-blob+))
         (header (make-block-header :blob-gas-used +blob-gas-per-blob+
                                    :excess-blob-gas expected))
         (empty-parent (make-block-header)))
    (is (= expected (expected-excess-blob-gas parent)))
    (is (validate-block-excess-blob-gas parent header))
    (is (= 0 (expected-excess-blob-gas empty-parent)))
    (setf (block-header-excess-blob-gas header) (1+ expected))
    (signals block-validation-error
      (validate-block-excess-blob-gas parent header))))

(deftest eip7918-excess-blob-gas-calculation-and-validation
  (let* ((osaka-target-gas (* +osaka-target-blobs-per-block+
                              +blob-gas-per-blob+))
         (osaka-max-gas (* +osaka-max-blobs-per-block+
                           +blob-gas-per-blob+))
         (below-reserve-parent
           (make-block-header :base-fee-per-gas 1000000000
                              :gas-limit 30000000
                              :gas-used 15000000
                              :timestamp 9
                              :blob-gas-used osaka-target-gas
                              :excess-blob-gas 0))
         (below-reserve-expected (floor osaka-target-gas 3))
         (below-reserve-header
           (make-block-header :blob-gas-used 0
                              :excess-blob-gas below-reserve-expected))
         (above-reserve-parent
           (make-block-header :base-fee-per-gas 1
                              :blob-gas-used osaka-target-gas
                              :excess-blob-gas 0))
         (above-reserve-header
           (make-block-header :blob-gas-used 0
                              :excess-blob-gas 0))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (parent-hash (block-header-hash below-reserve-parent))
         (config-child
           (make-block-header :parent-hash parent-hash
                              :number 1
                              :timestamp 10
                              :gas-limit 30000000
                              :base-fee-per-gas 1000000000
                              :blob-gas-used 0
                              :excess-blob-gas below-reserve-expected
                              :parent-beacon-root (zero-hash32))))
    (is (= below-reserve-expected
           (expected-excess-blob-gas
            below-reserve-parent
            :target-blob-gas osaka-target-gas
            :max-blob-gas osaka-max-gas
            :eip7918-p t
            :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (is (= 0
           (expected-excess-blob-gas
            above-reserve-parent
            :target-blob-gas osaka-target-gas
            :max-blob-gas osaka-max-gas
            :eip7918-p t
            :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (is (validate-block-excess-blob-gas
         below-reserve-parent below-reserve-header
         :target-blob-gas osaka-target-gas
         :max-blob-gas osaka-max-gas
         :eip7918-p t
         :update-fraction +osaka-blob-base-fee-update-fraction+))
    (is (validate-block-excess-blob-gas
         above-reserve-parent above-reserve-header
         :target-blob-gas osaka-target-gas
         :max-blob-gas osaka-max-gas
         :eip7918-p t
         :update-fraction +osaka-blob-base-fee-update-fraction+))
    (is (validate-block-header-against-config
         below-reserve-parent config-child config))
    (setf (block-header-excess-blob-gas config-child) 0)
    (signals block-validation-error
      (validate-block-header-against-config
       below-reserve-parent config-child config))))

(deftest blob-base-fee-fake-exponential-vectors
  (dolist (case '((1 0 1 1)
                  (38493 0 1000 38493)
                  (0 1234 2345 0)
                  (1 2 1 6)
                  (1 4 2 6)
                  (1 3 1 16)
                  (1 6 2 18)
                  (1 4 1 49)
                  (1 8 2 50)
                  (10 8 2 542)
                  (11 8 2 596)
                  (1 5 1 136)
                  (1 5 2 11)
                  (2 5 2 23)
                  (1 50000000 2225652 5709098764)))
    (destructuring-bind (factor numerator denominator expected) case
      (is (= expected
             (fake-exponential factor numerator denominator)))))
  (is (= 1 (blob-base-fee 0)))
  (is (= 1 (blob-base-fee 2314057)))
  (is (= 2 (blob-base-fee 2314058)))
  (is (= 23 (blob-base-fee (* 10 1024 1024))))
  (is (= 23 (block-header-blob-base-fee
             (make-block-header :excess-blob-gas (* 10 1024 1024))))))

(deftest withdrawal-rlp-and-root
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (root (withdrawal-list-root (list withdrawal))))
    (is (string= "0xd8010294000000000000000000000000000000000000000103"
                 (bytes-to-hex (withdrawal-rlp withdrawal))))
    (is (hash32-p root))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (hash32-to-hex (withdrawal-list-root '()))))))

(deftest block-access-list-rlp-encodes-account-shells
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (access-list (list account)))
    (is (string=
         "0xdbda940000000000000000000000000000000000000001c0c0c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (string= (hash32-to-hex +empty-ommers-hash+)
                 (hash32-to-hex (block-access-list-hash '()))))
    (is (not (string= (hash32-to-hex +empty-ommers-hash+)
                      (hash32-to-hex
                       (block-access-list-hash access-list)))))))

(deftest block-access-list-rlp-encodes-storage-reads
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :storage-reads (list slot-1 slot-2)))
         (access-list (list account)))
    (is (string=
         "0xdddc940000000000000000000000000000000000000001c0c20102c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-reads (list slot-2 slot-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-reads (list slot-1 slot-1)))))))

(deftest block-access-list-rlp-encodes-storage-writes
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (write-1 (make-block-access-storage-write :tx-index 1 :value-after 2))
         (write-2 (make-block-access-storage-write :tx-index 2 :value-after 3))
         (slot-writes (make-block-access-slot-writes
                       :slot slot-1
                       :accesses (list write-1 write-2)))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :storage-writes (list slot-writes)))
         (access-list (list account)))
    (is (string=
         "0xe4e3940000000000000000000000000000000000000001c9c801c6c20102c20203c0c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-2
                     :accesses (list write-1))
                    (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-1)))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-2 write-1)))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-1)))
              :storage-reads (list slot-1)))))))

(deftest block-access-list-rlp-encodes-balance-changes
  (let* ((change-1 (make-block-access-balance-change
                    :tx-index 1
                    :balance 100))
         (change-2 (make-block-access-balance-change
                    :tx-index 2
                    :balance 500))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :balance-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe3e2940000000000000000000000000000000000000001c0c0c8c20164c4028201f4c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes
              (list (make-block-access-balance-change
                     :tx-index (expt 2 32)
                     :balance 100))))))))

(deftest block-access-list-rlp-encodes-nonce-changes
  (let* ((change-1 (make-block-access-nonce-change
                    :tx-index 1
                    :nonce 2))
         (change-2 (make-block-access-nonce-change
                    :tx-index 2
                    :nonce 6))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :nonce-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe1e0940000000000000000000000000000000000000001c0c0c0c6c20102c20206c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes
              (list (make-block-access-nonce-change
                     :tx-index 1
                     :nonce (expt 2 64)))))))))

(deftest block-access-list-rlp-encodes-code-changes
  (let* ((change-1 (make-block-access-code-change
                    :tx-index 1
                    :code #(222 173 190 239)))
         (change-2 (make-block-access-code-change
                    :tx-index 2
                    :code #(96 0)))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :code-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe7e6940000000000000000000000000000000000000001c0c0c0c0ccc60184deadbeefc402826000"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes
              (list (make-block-access-code-change
                     :tx-index 1
                     :code "not bytes"))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       access-list
       :max-code-size 3))))

(deftest block-access-list-rlp-decodes-round-trip
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes
           (make-block-access-slot-writes
            :slot slot-1
            :accesses
            (list (make-block-access-storage-write
                   :tx-index 1
                   :value-after 2)
                  (make-block-access-storage-write
                   :tx-index 3
                   :value-after 4))))
         (account
           (make-block-access-account
            :address (address-from-hex
                      "0x0000000000000000000000000000000000000001")
            :storage-writes (list slot-writes)
            :storage-reads (list slot-2)
            :balance-changes
            (list (make-block-access-balance-change
                   :tx-index 1
                   :balance 100))
            :nonce-changes
            (list (make-block-access-nonce-change
                   :tx-index 2
                   :nonce 7))
            :code-changes
            (list (make-block-access-code-change
                   :tx-index 4
                   :code #(96 0 96 1)))))
         (access-list (list account))
         (encoded (block-access-list-rlp access-list))
         (decoded (block-access-list-from-rlp
                   encoded
                   :max-code-size 4
                   :max-items 3)))
    (is (= 3 (block-access-list-item-count decoded)))
    (is (bytes= encoded (block-access-list-rlp decoded)))
    (is (string= (hash32-to-hex (keccak-256-hash encoded))
                 (hash32-to-hex (block-access-list-rlp-hash encoded))))
    (is (string= (hash32-to-hex (block-access-list-hash access-list))
                 (hash32-to-hex (block-access-list-hash decoded))))
    (signals block-validation-error
      (block-access-list-from-rlp encoded :max-code-size 3))
    (signals block-validation-error
      (block-access-list-from-rlp encoded :max-items 2))
    (signals block-validation-error
      (block-access-list-rlp-hash encoded :max-code-size 3))
    (signals block-validation-error
      (block-access-list-rlp-hash "not bytes"))))

(deftest block-access-list-rlp-decode-rejects-malformed-shape
  (signals block-validation-error
    (block-access-list-from-rlp (make-byte-vector 0)))
  (signals block-validation-error
    (block-access-list-from-rlp (rlp-encode (ensure-byte-vector '(1 2 3)))))
  (signals block-validation-error
    (block-access-list-from-rlp
     (rlp-encode
      (list (make-rlp-list
             (make-byte-vector 20))))))
  (signals block-validation-error
    (block-access-list-from-rlp
     (rlp-encode
      (list (make-rlp-list
             (make-byte-vector 19)
             '()
             '()
             '()
             '()
             '()))))))

(deftest block-access-list-validates-account-order
  (let ((first (make-block-access-account
                :address (address-from-hex
                          "0x0000000000000000000000000000000000000001")))
        (second (make-block-access-account
                 :address (address-from-hex
                           "0x0000000000000000000000000000000000000002"))))
    (is (validate-block-access-list-fields (list first second)))
    (signals block-validation-error
      (validate-block-access-list-fields (list second first)))
    (signals block-validation-error
      (validate-block-access-list-fields (list first first)))))
