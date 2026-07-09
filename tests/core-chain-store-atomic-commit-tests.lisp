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
         (blob #(#xaa #xbb))
         (commitment (make-byte-vector +kzg-commitment-size+
                                       :initial-element 0))
         (proof #(#xcc #xdd))
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
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction-filter
            store)))
    (state-db-set-account state address (make-state-account :balance 10))
    (setf (aref commitment 0) #x11
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list proof))
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (ethereum-lisp.core::engine-payload-store-put-blob-sidecar store sidecar)
    (ethereum-lisp.core::engine-payload-store-mark-invalid store invalid-block)
    (signals error
      (execute-atomic-block-commit
       store state
       (lambda ()
         (chain-store-put-block store block :state-available-p t)
         (chain-store-put-account-balance store block-hash address 99)
         (ethereum-lisp.core::engine-payload-store-put-pending-transaction
          store transaction)
         (setf (ethereum-lisp.core::engine-prepared-payload-version
                (chain-store-prepared-payload store payload-id))
               6)
         (setf (aref
                (ethereum-lisp.core::engine-blob-and-proofs-blob
                 (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                  store versioned-hash))
                0)
               #xff)
         (setf (ethereum-lisp.core::chain-store-checkpoint-label
                (chain-store-head-checkpoint store))
               :mutated-head)
         (setf (block-header-gas-used
                (block-header
                 (ethereum-lisp.core::engine-payload-store-invalid-block
                  store invalid-block-hash)))
               77)
         (ethereum-lisp.core::engine-payload-store-mark-invalid
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
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (null (ethereum-lisp.core::engine-payload-store-pending-transaction
               store transaction-hash)))
    (is (null
         (ethereum-lisp.core::engine-pending-transaction-filter-hashes
          (ethereum-lisp.core::engine-payload-store-log-filter
           store pending-filter-id))))
    (is (= 3
           (ethereum-lisp.core::engine-prepared-payload-version
            (chain-store-prepared-payload store payload-id))))
    (is (= #xaa
           (aref
            (ethereum-lisp.core::engine-blob-and-proofs-blob
             (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
              store versioned-hash))
            0)))
    (is (eq :head
            (ethereum-lisp.core::chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (not (eq head-checkpoint
                 (chain-store-head-checkpoint store))))
    (let ((cached-invalid
            (ethereum-lisp.core::engine-payload-store-invalid-block
             store invalid-block-hash)))
      (is cached-invalid)
      (is (not (eq invalid-block cached-invalid)))
      (is (= 0
             (block-header-gas-used
              (block-header cached-invalid)))))
    (is (null
         (ethereum-lisp.core::engine-payload-store-invalid-block
          store new-invalid-block-hash)))
    (is (= 10
           (state-account-balance
            (state-db-get-account state address))))))

