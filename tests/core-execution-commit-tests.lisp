(in-package #:ethereum-lisp.test)

(deftest execute-and-commit-block-stores-only-after-execution-success
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (contract
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-account state contract
                          (make-state-account :balance 7))
    (state-db-set-code state contract #(1 2 3))
    (state-db-set-storage state contract storage-slot 5)
    (multiple-value-bind (block receipts)
        (execute-and-commit-block
         store state
         (lambda ()
           (execute-legacy-block state sender (list transaction)
                                 :header header)))
      (is (= 1 (length receipts)))
      (is (bytes= (block-rlp block)
                  (block-rlp
                   (chain-store-known-block store (block-hash block)))))
      (is (bytes= (block-rlp block)
                  (block-rlp (chain-store-block-by-number store 0))))
      (is (chain-store-state-available-p store (block-hash block)))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (state-account-balance
              (state-db-get-account state recipient))))
      (is (= 78990
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 10
             (chain-store-account-balance store (block-hash block) recipient)))
      (is (= 7
             (chain-store-account-balance store (block-hash block) contract)))
      (is (bytes= #(1 2 3)
                  (chain-store-account-code store (block-hash block)
                                            contract)))
      (is (= 5
             (chain-store-account-storage store (block-hash block)
                                          contract storage-slot))))))

(deftest execute-and-commit-block-rolls-back-bad-execution-commitments
  (let ((sender
          (address-from-hex "0x0000000000000000000000000000000000000001"))
        (recipient
          (address-from-hex "0x00000000000000000000000000000000000000f2")))
    (labels ((bad-logs-bloom ()
               (let ((bloom (make-byte-vector 256)))
                 (setf (aref bloom 0) 1)
                 bloom))
             (assert-rejected-header (header)
               (let* ((store (make-engine-payload-memory-store))
                      (state (make-state-db))
                      (transaction
                        (make-legacy-transaction
                         :nonce 0
                         :gas-price 1
                         :gas-limit 21000
                         :to recipient
                         :value 10)))
                 (state-db-set-account state sender
                                       (make-state-account :balance 100000))
                 (signals error
                   (execute-and-commit-block
                    store state
                    (lambda ()
                      (execute-legacy-block state sender (list transaction)
                                            :header header))))
                 (is (null (chain-store-block-by-number store 0)))
                 (is (null (chain-store-canonical-hash store 0)))
                 (is (null (chain-store-transaction-location
                            store
                            (transaction-hash transaction))))
                 (is (= 100000
                        (state-account-balance
                         (state-db-get-account state sender))))
                 (is (null (state-db-get-account state recipient))))))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :state-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :receipts-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :logs-bloom (bad-logs-bloom)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :gas-used 1)))))

(deftest execute-and-commit-block-rolls-back-intra-transaction-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 1))
    (signals error
      (execute-and-commit-block
       store state
       (lambda ()
         (execute-legacy-block state sender (list transaction)
                               :header header))))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 1
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest execute-and-commit-signed-block-recovers-sender-and-stores-indexes
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (multiple-value-bind (block receipts)
        (execute-and-commit-signed-block
         store state (list transaction)
         :expected-chain-id 1
         :header header)
      (is (= 1 (length receipts)))
      (is (bytes= (block-rlp block)
                  (block-rlp (chain-store-block-by-number store 0))))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 999580000000000000
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1000000000000000000
             (chain-store-account-balance store (block-hash block)
                                          recipient))))))

(deftest execute-and-commit-signed-block-rejects-wrong-chain-id-atomically
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (signals transaction-validation-error
      (execute-and-commit-signed-block
       store state (list transaction)
       :expected-chain-id 2
       :header header))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 9
           (state-account-nonce
            (state-db-get-account state sender))))
    (is (= 2000000000000000000
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest execute-and-commit-signed-block-blockhash-follows-parent-branch
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (private-key 1)
         (sender (fixture-private-key-address private-key))
         (contract
           (address-from-hex "0x00000000000000000000000000000000000000b0"))
         (slot (zero-hash32))
         (genesis
           (make-block
            :header (make-block-header :number 0
                                       :parent-hash (zero-hash32)
                                       :extra-data #(0))))
         (canonical-ancestor
           (make-block
            :header (make-block-header :number 1
                                       :parent-hash (block-hash genesis)
                                       :extra-data #(1))))
         (side-ancestor
           (make-block
            :header (make-block-header :number 1
                                       :parent-hash (block-hash genesis)
                                       :extra-data #(2))))
         (side-parent
           (make-block
            :header (make-block-header :number 2
                                       :parent-hash (block-hash side-ancestor)
                                       :extra-data #(3))))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction :nonce 0
                                     :gas-price 1
                                     :gas-limit 100000
                                     :to contract)
            private-key
            1))
         (header
           (make-block-header :number 3
                              :parent-hash (block-hash side-parent)
                              :gas-limit 150000)))
    (dolist (block (list genesis canonical-ancestor
                         side-ancestor side-parent))
      (chain-store-put-block store block))
    (is (bytes= (hash32-bytes (block-hash canonical-ancestor))
                (hash32-bytes (chain-store-canonical-hash store 1))))
    (is (not (bytes= (hash32-bytes (block-hash canonical-ancestor))
                     (hash32-bytes (block-hash side-ancestor)))))
    (state-db-set-account state sender
                          (make-state-account :balance 1000000))
    (state-db-set-account state contract (make-state-account))
    ;; BLOCKHASH(1); SSTORE(0, result). The target block's direct parent is 2,
    ;; so resolving block 1 requires walking that parent's side-chain ancestry.
    (state-db-set-code state contract #(#x60 #x01 #x40 #x60 #x00 #x55 #x00))
    (execute-and-commit-signed-block
     store state (list transaction)
     :expected-chain-id 1
     :header header)
    (is (= (bytes-to-integer (hash32-bytes (block-hash side-ancestor)))
           (state-db-get-storage state contract slot)))
    (is (/= (bytes-to-integer (hash32-bytes (block-hash canonical-ancestor)))
            (state-db-get-storage state contract slot)))))

(defun chain-store-test-slot-counts (chain-store)
  "Entry counts of every growing chain-store table, for asserting a failed
commit left the store byte-for-byte as its pre-commit baseline. A mutator the
undo journal fails to cover shows up here as a changed count."
  (mapcar
   (lambda (reader) (hash-table-count (funcall reader chain-store)))
   (list #'ethereum-lisp.chain-store.state:memory-chain-store-blocks
         #'ethereum-lisp.chain-store.state:memory-chain-store-number-blocks
         #'ethereum-lisp.chain-store.state:memory-chain-store-canonical-hashes
         #'ethereum-lisp.chain-store.state:memory-chain-store-transaction-locations
         #'ethereum-lisp.chain-store.state:memory-chain-store-account-balances
         #'ethereum-lisp.chain-store.state:memory-chain-store-account-nonces
         #'ethereum-lisp.chain-store.state:memory-chain-store-account-codes
         #'ethereum-lisp.chain-store.state:memory-chain-store-account-storage
         #'ethereum-lisp.chain-store.state:memory-chain-store-state-blocks
         #'ethereum-lisp.chain-store.state:memory-chain-store-state-diffs)))

(deftest chain-store-atomic-commit-rolls-back-touched-keys-completely
  ;; The changed-key undo journal replaces the old whole-store deep copy, so a
  ;; failed commit must still restore the chain store exactly. Establish a
  ;; committed baseline, then run a commit that installs a child block
  ;; (canonicalizing it, bumping the head) and writes new account state before
  ;; failing; every growing table and the head must return to the baseline. A
  ;; mutator missed by the journal leaves a slot count or value changed.
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender (make-state-account :balance 100000))
    (let ((block0
            (execute-and-commit-block
             store state
             (lambda ()
               (execute-legacy-block state sender (list transaction)
                                     :header header)))))
      (let* ((chain-store
               (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                store))
             (baseline-counts (chain-store-test-slot-counts chain-store))
             (baseline-head (chain-store-head-number store))
             (baseline-sender-balance
               (chain-store-account-balance store (block-hash block0) sender))
             (child (make-block
                     :header (make-block-header
                              :number 1
                              :parent-hash (block-hash block0)
                              :gas-limit 50000))))
        (is (= 0 baseline-head))
        (signals error
          (chain-store-atomic-commit
           store
           (lambda ()
             (engine-payload-store-put-block store child
                                             :state-available-p t)
             (chain-store-put-account-balance
              store (block-hash child) sender 55555)
             (chain-store-put-account-balance
              store (block-hash child) recipient 777)
             (error "rollback the whole commit"))))
        (is (equal baseline-counts (chain-store-test-slot-counts chain-store)))
        (is (= baseline-head (chain-store-head-number store)))
        (is (null (chain-store-known-block store (block-hash child))))
        (is (null (chain-store-canonical-hash store 1)))
        (is (= baseline-sender-balance
               (chain-store-account-balance store (block-hash block0)
                                            sender)))))))

(deftest chain-store-atomic-commit-journal-work-tracks-touched-keys
  ;; Per-commit rollback work must scale with the keys a commit touches, not
  ;; the store size -- the whole point of the journal over the old copy. Seed a
  ;; block with N committed accounts, then a transaction that rewrites three of
  ;; them records the same handful of undos whether N is small or large.
  (labels ((address-for (index)
             (address-from-hex (format nil "0x~40,'0X" (1+ index))))
           (undo-count-for (prior-accounts)
             (let* ((store (make-engine-payload-memory-store))
                    (block0
                      (make-block
                       :header (make-block-header :number 0
                                                  :parent-hash (zero-hash32)
                                                  :gas-limit 50000)))
                    (block-hash (block-hash block0))
                    (count nil))
               (engine-payload-store-put-block store block0
                                               :state-available-p t)
               (dotimes (index prior-accounts)
                 (chain-store-put-account-balance
                  store block-hash (address-for index) 100))
               (call-with-chain-store-transaction
                (lambda (journal)
                  (dotimes (index 3)
                    (chain-store-put-account-balance
                     store block-hash (address-for index) 999))
                  (setf count (chain-store-journal-undo-count journal))
                  (chain-store-journal-rollback journal)))
               ;; Rollback must restore the seeded value, not the touched 999.
               (is (= 100
                      (chain-store-account-balance
                       store block-hash (address-for 0))))
               count)))
    (let ((small (undo-count-for 5))
          (large (undo-count-for 50)))
      ;; Three touched accounts share one state-blocks baseline marker key, so
      ;; the journal records three balance keys plus that one marker.
      (is (= small large))
      (is (= 4 small)))))
