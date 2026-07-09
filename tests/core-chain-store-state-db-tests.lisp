(in-package #:ethereum-lisp.test)

(deftest chain-store-update-forkchoice-checkpoints-rejects-safe-before-finalized
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (safe
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (finalized
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash safe)
                               :timestamp 2
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 3
                               :parent-hash (block-hash finalized)
                               :timestamp 3
                               :gas-limit 30000000))))
    (dolist (block (list genesis safe finalized head))
      (engine-payload-store-put-block store block :state-available-p t))
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash head)
        :safe-block-hash (block-hash safe)
        :finalized-block-hash (block-hash finalized))))
    (is (not (chain-store-head-block store)))
    (is (not (chain-store-safe-block store)))
    (is (not (chain-store-finalized-block store)))))

(deftest chain-store-update-forkchoice-checkpoints-requires-available-state
  (let* ((unknown-store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (missing-safe-state-store (make-engine-payload-memory-store))
         (unknown-hash
           (hash32-from-hex
            "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (safe
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (head-over-safe
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash safe)
                               :timestamp 2
                               :gas-limit 30000000))))
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       unknown-store
       (make-forkchoice-state
        :head-block-hash unknown-hash)))
    (is (not (chain-store-head-block unknown-store)))
    (engine-payload-store-put-block missing-state-store head)
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       missing-state-store
       (make-forkchoice-state
        :head-block-hash (block-hash head))))
    (is (not (chain-store-head-block missing-state-store)))
    (engine-payload-store-put-block missing-safe-state-store safe)
    (engine-payload-store-put-block
     missing-safe-state-store head-over-safe :state-available-p t)
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       missing-safe-state-store
       (make-forkchoice-state
        :head-block-hash (block-hash head-over-safe)
        :safe-block-hash (block-hash safe))))
    (is (not (chain-store-head-block missing-safe-state-store)))
    (is (not (chain-store-safe-block missing-safe-state-store)))))

(deftest chain-store-state-db-reconstructs-account-projection
  (let* ((store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (storage-only
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (storage-only-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (block
           (make-block
            :header
            (make-block-header :number 44
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block)))
    (chain-store-put-block missing-state-store block)
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address 99)
    (chain-store-put-account-nonce store block-hash address 7)
    (chain-store-put-account-code store block-hash address #(96 42 0))
    (chain-store-put-account-storage store block-hash address storage-slot 5)
    (chain-store-put-account-storage
     store block-hash storage-only storage-only-slot 11)
    (is (not (chain-store-state-db missing-state-store block-hash)))
    (let* ((state (chain-store-state-db store block-hash))
           (account (state-db-get-account state address))
           (storage-only-account
             (state-db-get-account state storage-only)))
      (is (typep state 'state-db))
      (is (= 99 (state-account-balance account)))
      (is (= 7 (state-account-nonce account)))
      (is (bytes= #(96 42 0) (state-db-get-code state address)))
      (is (= 5 (state-db-get-storage state address storage-slot)))
      (is (= 0 (state-account-balance storage-only-account)))
      (is (= 0 (state-account-nonce storage-only-account)))
      (is (= 11
             (state-db-get-storage
              state storage-only storage-only-slot))))))

(deftest chain-store-for-each-account-iterates-deterministically
  (let* ((store (make-engine-payload-memory-store))
         (address-a
           (address-from-hex "0x0000000000000000000000000000000000000501"))
         (address-b
           (address-from-hex "0x0000000000000000000000000000000000000502"))
         (address-c
           (address-from-hex "0x0000000000000000000000000000000000000503"))
         (slot-a
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-b
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000b"))
         (block
           (make-block
            :header
            (make-block-header :number 46
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block))
         (addresses '())
         (slots '()))
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address-c 3)
    (chain-store-put-account-balance store block-hash address-a 1)
    (chain-store-put-account-balance store block-hash address-b 2)
    (chain-store-put-account-storage store block-hash address-a slot-b 11)
    (chain-store-put-account-storage store block-hash address-a slot-a 1)
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (declare (ignore balance nonce code))
       (push (address-to-hex address) addresses)
       (when (bytes= (address-bytes address)
                     (address-bytes address-a))
         (setf slots (mapcar (lambda (entry)
                               (hash32-to-hex (car entry)))
                             storage-entries)))))
    (is (equal (list (address-to-hex address-a)
                     (address-to-hex address-b)
                     (address-to-hex address-c))
               (nreverse addresses)))
    (is (equal (list (hash32-to-hex slot-a)
                     (hash32-to-hex slot-b))
               slots))))

(deftest state-db-account-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (addresses
           (list (address-from-hex "0x0000000000000000000000000000000000000601")
                 (address-from-hex "0x0000000000000000000000000000000000000602")
                 (address-from-hex "0x0000000000000000000000000000000000000603")
                 (address-from-hex "0x0000000000000000000000000000000000000604")))
         (slot
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000a")))
    (loop for address in addresses
          for balance from 10 by 10
          do (state-db-set-account
              state
              address
              (make-state-account :nonce balance :balance balance)))
    (state-db-set-code state (second addresses) #(96 42))
    (state-db-set-storage state (second addresses) slot 7)
    (let* ((all (state-db-account-range state))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-account-range-entry-proof-key entry)))
                     all))
           (start (state-account-range-entry-proof-key (second all)))
           (end (state-account-range-entry-proof-key (fourth all)))
           (middle (state-db-account-range state :start start :end end))
           (prefix (state-db-account-range state :end start))
           (suffix (state-db-account-range state :start end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-account-range-entry-proof-key entry)))
                         middle)))
      (is (= 1 (length prefix)))
      (is (= 1 (length suffix)))
      (is (null (state-db-account-range state :start start :end start)))
      (let ((code-entry
              (find (address-to-hex (second addresses))
                    all
                    :key (lambda (entry)
                           (address-to-hex
                            (state-account-range-entry-address entry)))
                    :test #'string=)))
        (is (bytes= #(96 42)
                    (state-account-range-entry-code code-entry)))
        (is (= 1
               (length
                (state-account-range-entry-storage-entries code-entry))))))))

(deftest state-db-storage-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000611"))
         (slots
           (list (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000003")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000004"))))
    (loop for slot in slots
          for value from 100 by 100
          do (state-db-set-storage state address slot value))
    (let* ((all (state-db-storage-range state address))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-storage-range-entry-proof-key entry)))
                     all))
           (start (state-storage-range-entry-proof-key (second all)))
           (end (state-storage-range-entry-proof-key (fourth all)))
           (middle (state-db-storage-range state address :start start :end end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-storage-range-entry-proof-key entry)))
                         middle)))
      (is (every #'plusp
                 (mapcar #'state-storage-range-entry-value middle)))
      (is (null (state-db-storage-range state address :start start :end start)))
      (is (null (state-db-storage-range
                 state
                 (address-from-hex
                  "0x0000000000000000000000000000000000000612")))))))

(deftest chain-store-state-db-round-trips-nontrivial-state-root
  (let* ((store (make-engine-payload-memory-store))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000411"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000412"))
         (sender-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000011"))
         (recipient-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000012"))
         (state (make-state-db))
         (block
           (make-block
            :header
            (make-block-header :number 45
                               :timestamp 450
                               :gas-limit 30000000))))
    (state-db-set-account
     state sender (make-state-account :nonce 7 :balance 1000))
    (state-db-set-code state sender #(96 1 96 0 85))
    (state-db-set-storage state sender sender-slot 42)
    (state-db-set-account
     state recipient (make-state-account :nonce 3 :balance 5))
    (state-db-set-code state recipient #(96 2 96 0 85))
    (state-db-set-storage state recipient recipient-slot 99)
    (ethereum-lisp.state::state-db-transfer-value
     state sender recipient 37)
    (setf (block-header-state-root (block-header block))
          (state-db-root state))
    (chain-store-put-block store block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash block) state)
    (let* ((reconstructed (chain-store-state-db store (block-hash block)))
           (sender-account (state-db-get-account reconstructed sender))
           (recipient-account
             (state-db-get-account reconstructed recipient)))
      (is (typep reconstructed 'state-db))
      (is (string= (state-db-root-hex state)
                   (state-db-root-hex reconstructed)))
      (is (= 963 (state-account-balance sender-account)))
      (is (= 42 (state-db-get-storage reconstructed sender sender-slot)))
      (is (bytes= #(96 1 96 0 85)
                  (state-db-get-code reconstructed sender)))
      (is (bytes= (hash32-bytes (state-account-storage-root
                                  (state-db-get-account state sender)))
                  (hash32-bytes
                   (state-account-storage-root sender-account))))
      (is (= 42 (state-account-balance recipient-account)))
      (is (= 99
             (state-db-get-storage
              reconstructed recipient recipient-slot)))
      (is (bytes= #(96 2 96 0 85)
                  (state-db-get-code reconstructed recipient)))
      (is (bytes= (hash32-bytes (state-account-code-hash
                                  (state-db-get-account state recipient)))
                  (hash32-bytes
                   (state-account-code-hash recipient-account)))))))

