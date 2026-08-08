(in-package #:ethereum-lisp.test)

(deftest execute-atomic-block-commit-commits-state-and-store-together
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction)))
    (multiple-value-bind (result committed-block)
        (execute-atomic-block-commit
         store state
         (lambda ()
           (chain-store-put-block store block :state-available-p t)
           (chain-store-put-account-balance store block-hash address 99)
           (state-db-set-account state address
                                 (make-state-account :balance 99))
           (values :committed block)))
      (is (eq :committed result))
      (is (eq block committed-block)))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-known-block store block-hash))))
    (is (chain-store-state-available-p store block-hash))
    (is (= 99 (chain-store-account-balance store block-hash address)))
    (is (typep (chain-store-transaction-location store transaction-hash)
               'engine-transaction-location))
    (is (= 99
           (state-account-balance
            (state-db-get-account state address))))))

(deftest execute-atomic-block-commit-rolls-back-state-and-store-on-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction))
         (payload-id #(3 0 0 0 0 0 0 1))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+
                                       :initial-element 0))
         (proof (make-byte-vector +kzg-proof-size+))
         (sidecar nil)
         (versioned-hash nil)
         (head-checkpoint
           (chain-store-head-checkpoint store))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 3
            :block block))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 7
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (invalid-block-hash (block-hash invalid-block))
         (new-invalid-block
           (make-block
            :header
            (make-block-header :number 8
                               :parent-hash invalid-block-hash
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (new-invalid-block-hash (block-hash new-invalid-block))
         (pending-filter-id
           (ethereum-lisp.chain-store:engine-payload-store-put-pending-transaction-filter
            store)))
    (state-db-set-account state address (make-state-account :balance 10))
    (setf (aref blob 0) #x02
          (aref commitment 0) #x11
          (aref proof 0) #xcc
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list proof))
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (let ((*kzg-blob-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proof)
              (and (bytes= blob verified-blob)
                   (bytes= commitment verified-commitment)
                   (bytes= proof verified-proof)))))
      (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
       store sidecar))
    (ethereum-lisp.chain-store:engine-payload-store-mark-invalid store invalid-block)
    (signals error
      (execute-atomic-block-commit
       store state
       (lambda ()
         (chain-store-put-block store block :state-available-p t)
         (chain-store-put-account-balance store block-hash address 99)
         (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
          store transaction)
         (setf (ethereum-lisp.engine-payloads:engine-prepared-payload-version
                (chain-store-prepared-payload store payload-id))
               6)
         (setf (aref
                (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob
                 (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
                  store versioned-hash))
                0)
               #xff)
         (setf (ethereum-lisp.chain-store.model:chain-store-checkpoint-label
                (chain-store-head-checkpoint store))
               :mutated-head)
         (setf (block-header-gas-used
                (block-header
                 (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                  store invalid-block-hash)))
               77)
         (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
          store new-invalid-block)
         (state-db-set-account state address
                               (make-state-account :balance 99))
         (error "Injected atomic commit failure"))))
    (is (null (chain-store-known-block store block-hash)))
    (is (null (chain-store-canonical-hash store 0)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (not (chain-store-state-available-p store block-hash)))
    (is (= 0 (chain-store-account-balance store block-hash address)))
    (is (= 0
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (null (ethereum-lisp.txpool:engine-payload-store-pending-transaction
               store transaction-hash)))
    (is (null
         (ethereum-lisp.chain-store.model:engine-pending-transaction-filter-hashes
          (ethereum-lisp.chain-store:engine-payload-store-log-filter
           store pending-filter-id))))
    (is (= 3
           (ethereum-lisp.engine-payloads:engine-prepared-payload-version
            (chain-store-prepared-payload store payload-id))))
    (is (= #x02
           (aref
            (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob
             (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
              store versioned-hash))
            0)))
    (is (eq :head
            (ethereum-lisp.chain-store.model:chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (not (eq head-checkpoint
                 (chain-store-head-checkpoint store))))
    (let ((cached-invalid
            (ethereum-lisp.chain-store:engine-payload-store-invalid-block
             store invalid-block-hash)))
      (is cached-invalid)
      (is (not (eq invalid-block cached-invalid)))
      (is (= 0
             (block-header-gas-used
              (block-header cached-invalid)))))
    (is (null
         (ethereum-lisp.chain-store:engine-payload-store-invalid-block
          store new-invalid-block-hash)))
    (is (= 10
           (state-account-balance
            (state-db-get-account state address))))))

(deftest nested-chain-store-journal-deduplicates-equalp-keys
  ;; A nested transaction can be the first frame to touch a byte-vector key.
  ;; After it merges, a fresh but EQUALP key in the parent must still share the
  ;; same first-touch before-image; otherwise rollback work grows with writes
  ;; rather than distinct changed keys.
  (let ((table (make-hash-table :test 'equalp))
        (key #(1 2 3 4)))
    (setf (gethash key table) :before)
    (ethereum-lisp.chain-store::call-with-chain-store-transaction
     (lambda (outer-journal)
       (ethereum-lisp.chain-store::call-with-chain-store-transaction
        (lambda (inner-journal)
          (declare (ignore inner-journal))
          (ethereum-lisp.chain-store::chain-store-journal-puthash
           table (copy-seq key) :inner)))
       (ethereum-lisp.chain-store::chain-store-journal-puthash
        table (copy-seq key) :outer)
       (is (= 1
              (ethereum-lisp.chain-store::chain-store-journal-undo-count
               outer-journal)))
       (ethereum-lisp.chain-store::chain-store-journal-rollback
        outer-journal)))
    (is (eq :before (gethash key table)))))

(deftest execute-atomic-block-commit-rollback-scales-with-changed-state
  ;; A block/commit snapshot must not clone the already loaded state.  Seed a
  ;; materially larger baseline, mutate one account, flush the account trie and
  ;; clear the commit change set before injecting failure.  Rollback must still
  ;; restore the root, journal boundary, and touched set exactly without ever
  ;; invoking the deliberate full-copy API.
  (labels ((address-for (index)
             (address-from-hex (format nil "0x~40,'0X" (1+ index)))))
    (let* ((store (make-engine-payload-memory-store))
           (state (make-state-db))
           (changed-address (address-for 7))
           (untouched-address (address-for 191))
           (full-copy-count 0))
      (dotimes (index 192)
        (state-db-set-account
         state (address-for index)
         (make-state-account :balance (+ 1000 index))))
      (let ((baseline-root (state-db-root state))
            (baseline-journal-size
              (fill-pointer (ethereum-lisp.state::state-db-journal state))))
        (state-db-clear-touched-accounts state)
        (let ((ethereum-lisp.state::*state-db-copy-observer*
                (lambda (copied-state)
                  (declare (ignore copied-state))
                  (incf full-copy-count))))
          (signals error
            (execute-atomic-block-commit
             store state
             (lambda ()
               (state-db-set-account
                state changed-address (make-state-account :balance 999999))
               (state-db-root state)
               ;; Simulate the live persistence path consuming the change set
               ;; before a durable commit failure is reported.
               (state-db-clear-touched-accounts state)
               (error "Injected bounded state rollback failure")))))
        (is (= 0 full-copy-count))
        (is (= baseline-journal-size
               (fill-pointer (ethereum-lisp.state::state-db-journal state))))
        (is (= 1007
               (state-account-balance
                (state-db-get-account state changed-address))))
        (is (= 1191
               (state-account-balance
                (state-db-get-account state untouched-address))))
        (is (ethereum-lisp.types:hash32= baseline-root
                                          (state-db-root state)))
        (let ((touched-count 0))
          (state-db-for-each-touched-account
           state
           (lambda (&rest ignored)
             (declare (ignore ignored))
             (incf touched-count)))
          (is (= 0 touched-count)))
        (let ((ethereum-lisp.state::*state-db-copy-observer*
                (lambda (copied-state)
                  (declare (ignore copied-state))
                  (incf full-copy-count))))
          (state-db-copy state))
        (is (= 1 full-copy-count))))))

(deftest chain-store-atomic-commit-txpool-rollback-scales-with-changed-keys
  ;; The production atomic boundary must not clone the retained txpool. The
  ;; explicit snapshot call at the end is the positive control proving that
  ;; the copy observer is wired to the costly path this test excludes.
  (labels ((transaction-for (nonce)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price (+ 100 nonce)
               :gas-limit 21000
               :to
               (address-from-hex
                "0x3535353535353535353535353535353535353535"))
              1
              1)))
    (let* ((store (make-engine-payload-memory-store))
           (retained-count 64)
           (new-transaction (transaction-for retained-count))
           (new-hash (transaction-hash new-transaction))
           (full-copy-count 0))
      (dotimes (nonce retained-count)
        (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
         store (transaction-for nonce)))
      (let ((baseline-cursor
              (nth-value
               1
               (ethereum-lisp.txpool:engine-payload-store-txpool-changes-since
                store 0))))
        (let ((ethereum-lisp.txpool.index::*engine-pending-txpool-copy-observer*
                (lambda (copied-txpool)
                  (declare (ignore copied-txpool))
                  (incf full-copy-count))))
          (signals error
            (chain-store-atomic-commit
             store
             (lambda ()
               (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
                store new-transaction)
               (error "Injected bounded txpool rollback failure"))))
          (is (= 0 full-copy-count))
          (is (= retained-count
                 (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                  store)))
          (is (null
               (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                store new-hash)))
          (multiple-value-bind (changes current overflow-p)
              (ethereum-lisp.txpool:engine-payload-store-txpool-changes-since
               store baseline-cursor)
            (is (null changes))
            (is (= baseline-cursor current))
            (is (null overflow-p)))
          (ethereum-lisp.node-store:engine-payload-store-snapshot store)
          (is (= 1 full-copy-count)))))))
