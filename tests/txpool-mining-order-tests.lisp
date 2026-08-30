(in-package #:ethereum-lisp.test)

;;;; Which transactions a block tries to include, and in what order.

(defun mining-order-test-transaction (private-key nonce gas-price)
  "A signed legacy transaction, whose gas price IS its offer: for a legacy
transaction the effective tip is simply the gas price less the base fee."
  (fixture-sign-legacy-transaction
   (make-legacy-transaction
    :nonce nonce :gas-price gas-price :gas-limit 21000
    :to (address-from-hex "0x0000000000000000000000000000000000003001")
    :value 1)
   private-key
   1))

(deftest transaction-effective-tip-is-what-the-builder-earns
  (:layer :unit :module :txpool)
  ;; The base fee is burned, so a builder earns the priority fee -- but only as
  ;; far as the fee cap leaves room above the base fee. A transaction promising
  ;; a large tip it cannot afford is worth only that remaining room.
  (let ((base-fee 30))
    ;; A legacy gas price is both the cap and the offer.
    (is (= 70 (ethereum-lisp.txpool:transaction-effective-tip
               (make-legacy-transaction :gas-price 100) base-fee)))
    ;; Capped by the fee cap, not by the promise.
    (is (= 20 (ethereum-lisp.txpool:transaction-effective-tip
               (make-dynamic-fee-transaction :max-fee-per-gas 50
                                             :max-priority-fee-per-gas 40)
               base-fee)))
    ;; Room to spare: the promise is what is earned.
    (is (= 40 (ethereum-lisp.txpool:transaction-effective-tip
               (make-dynamic-fee-transaction :max-fee-per-gas 500
                                             :max-priority-fee-per-gas 40)
               base-fee)))
    ;; A cap below the base fee earns nothing, and must never go negative.
    (is (= 0 (ethereum-lisp.txpool:transaction-effective-tip
              (make-dynamic-fee-transaction :max-fee-per-gas 10
                                            :max-priority-fee-per-gas 40)
              base-fee)))
    ;; No base fee given: the whole promise, rather than an error.
    (is (= 40 (ethereum-lisp.txpool:transaction-effective-tip
               (make-dynamic-fee-transaction :max-fee-per-gas 500
                                             :max-priority-fee-per-gas 40)
               nil)))))

(deftest mining-order-prefers-payment-while-keeping-nonce-order
  (:layer :unit :module :txpool)
  ;; Ordering used to be by sender ADDRESS, so a block filled with whoever
  ;; sorted first and left better-paying transactions out whenever the gas limit
  ;; bound. Now senders are ordered by what their next transaction pays -- but a
  ;; sender's own nonces must still ascend, while every inclusion exposes that
  ;; sender's next nonce for a fresh profitability comparison.
  (let* ((poor-key 1)
         (rich-key 2)
         (base-fee 100)
         ;; The richer sender's FIRST transaction is what places it.
         (poor (list (mining-order-test-transaction poor-key 0 150)
                     (mining-order-test-transaction poor-key 1 9000)))
         (rich (list (mining-order-test-transaction rich-key 0 5000)
                     (mining-order-test-transaction rich-key 1 120)))
         (store (make-engine-payload-memory-store)))
    (dolist (transaction (append poor rich))
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       store transaction))
    (let* ((ordered (ethereum-lisp.txpool:engine-payload-store-pending-mining-transactions
                     store 1 :base-fee base-fee))
           (senders (mapcar (lambda (transaction)
                              (address-to-hex
                               (transaction-sender transaction
                                                   :expected-chain-id 1)))
                            ordered))
           (rich-address (address-to-hex (fixture-private-key-address rich-key)))
           (poor-address (address-to-hex (fixture-private-key-address poor-key))))
      (is (= 4 (length ordered)))
      ;; The better-paying sender goes first, whatever the addresses sort like.
      (is (string= rich-address (first senders)))
      (is (string= poor-address (second senders)))
      (is (string= poor-address (third senders)))
      (is (string= rich-address (fourth senders)))
      ;; Each sender's own nonce order remains ascending.
      (is (equal '(0 0 1 1) (mapcar #'transaction-nonce ordered)))
      ;; And the poor sender's high-paying SECOND transaction did not jump the
      ;; queue: it cannot execute before its own nonce 0.
      (is (= 9000 (transaction-max-fee-per-gas (third ordered)))))
    ;; Without a base fee the deterministic address order is kept, so a caller
    ;; that does not know the base fee is unaffected.
    (let ((ordered (ethereum-lisp.txpool:engine-payload-store-pending-mining-transactions
                    store 1)))
      (is (= 4 (length ordered)))
      (is (equal (sort (mapcar (lambda (transaction)
                                 (address-to-hex
                                  (transaction-sender transaction
                                                      :expected-chain-id 1)))
                               ordered)
                       #'string<)
                 (mapcar (lambda (transaction)
                           (address-to-hex
                            (transaction-sender transaction
                                                :expected-chain-id 1)))
                         ordered))))))

(deftest mining-order-filters-at-the-child-base-fee
  (:layer :unit :module :txpool)
  (let* ((store (make-engine-payload-memory-store))
         (ineligible (mining-order-test-transaction 1 0 109))
         (eligible (mining-order-test-transaction 2 0 110)))
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store ineligible)
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store eligible)
    (let ((ordered
            (ethereum-lisp.txpool:engine-payload-store-pending-mining-transactions
             store 1 :base-fee 110)))
      (is (= 1 (length ordered)))
      (is (bytes= (transaction-encoding eligible)
                  (transaction-encoding (first ordered)))))))

(deftest prepared-payload-skips-an-invalid-sender
  (:layer :unit :module :engine)
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1
                                    :byzantium-block 0
                                    :constantinople-block 0
                                    :petersburg-block 0
                                    :berlin-block 0
                                    :london-block 0))
         (invalid-key 1)
         (valid-key 2)
         (invalid-sender (fixture-private-key-address invalid-key))
         (valid-sender (fixture-private-key-address valid-key))
         (recipient
           (address-from-hex
            "0x0000000000000000000000000000000000003002"))
         (invalid
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1 :gas-price 1000 :gas-limit 21000
             :to recipient :value 1)
            invalid-key 1))
         (valid
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0 :gas-price 1000 :gas-limit 21000
             :to recipient :value 1)
            valid-key 1))
         (parent-state (make-state-db))
         (attributes
           (make-payload-attributes-v1
            :timestamp 11
            :prev-randao (zero-hash32)
            :suggested-fee-recipient (zero-address))))
    (state-db-set-account
     parent-state invalid-sender
     (make-state-account :nonce 0 :balance 1000000000))
    (state-db-set-account
     parent-state valid-sender
     (make-state-account :nonce 0 :balance 1000000000))
    (let* ((parent
             (make-block
              :header
              (make-block-header
               :number 0 :timestamp 10 :gas-limit 42000 :gas-used 0
               :base-fee-per-gas 100
               :state-root (state-db-root parent-state))))
           (parent-hash (block-hash parent)))
      (chain-store-put-block store parent :state-available-p t)
      (commit-state-db-to-chain-store store parent-hash parent-state)
      (multiple-value-bind (block viable)
          (ethereum-lisp.engine-api::engine-rpc-build-viable-prepared-payload
           store parent attributes config (list invalid valid))
        (is (= 1 (length viable)))
        (is (= 1 (length (block-transactions block))))
        (is (bytes= (transaction-encoding valid)
                    (transaction-encoding
                     (first (block-transactions block)))))))))

(deftest devnet-broadcast-offers-each-transaction-to-a-peer-once
  (:layer :unit :module :devnet)
  ;; Without this seam a transaction submitted to our RPC reaches nobody: the
  ;; pool only ever drained into blocks we built ourselves. Each peer consumes
  ;; an independent cursor over the bounded change log, separate from journal
  ;; dirty keys.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (pending (ethereum-lisp.cli::devnet-peer-pending-broadcast node))
         (other-peer (ethereum-lisp.cli::devnet-peer-pending-broadcast node)))
    ;; Nothing pooled yet, so nothing to say.
    (is (null (funcall pending)))
    (let ((first-transaction (mining-order-test-transaction 1 0 500)))
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       store first-transaction)
      (let ((offered (funcall pending)))
        (is (= 1 (length offered)))
        (is (bytes= (transaction-encoding first-transaction)
                    (transaction-encoding (first offered)))))
      ;; Asked again, the same transaction is NOT re-sent to that peer.
      (is (null (funcall pending)))
      ;; But a different peer has not seen it, and each peer tracks its own.
      (is (= 1 (length (funcall other-peer))))
      (is (null (funcall other-peer)))
      ;; A newly pooled transaction is offered to both.
      (let ((second-transaction (mining-order-test-transaction 2 0 700)))
        (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
         store second-transaction)
        (is (= 1 (length (funcall pending))))
        (is (= 1 (length (funcall other-peer))))
        (is (null (funcall pending))))
      ;; Non-pending subpools are announced too: a peer may have the missing
      ;; nonce or a lower base fee and can make use of them.
      (let ((queued-transaction (mining-order-test-transaction 3 4 900)))
        (ethereum-lisp.txpool:engine-payload-store-put-queued-transaction
         store queued-transaction)
        (let ((offered (funcall pending)))
          (is (= 1 (length offered)))
          (is (bytes= (transaction-encoding queued-transaction)
                      (transaction-encoding (first offered))))))
      ;; Sidecar format is peer-version-specific, so the shared change cursor
      ;; must retain the bare blob transaction until the peer announce path can
      ;; choose the legacy proof or the eth/72 cell-proof representation.
      (let ((blob-transaction
              (make-blob-transaction
               :chain-id 1 :nonce 0 :max-fee-per-gas 1000
               :max-priority-fee-per-gas 1 :gas-limit 21000
               :max-fee-per-blob-gas 10
               :to (address-from-hex
                    "0x0000000000000000000000000000000000003001")
               :blob-versioned-hashes
               (list
                (hex-to-bytes
                 "0x0100000000000000000000000000000000000000000000000000000000000001"))
               :y-parity 0 :r 8 :s 9)))
        (ethereum-lisp.txpool:engine-payload-store-put-blob-transaction
         store blob-transaction)
        (let ((offered (funcall pending)))
          (is (= 1 (length offered)))
          (is (typep (first offered) 'blob-transaction)))))))

(deftest devnet-pooled-blob-sidecar-serves-rpc-legacy-proof-to-eth-69
  (:layer :unit :module :devnet)
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (transaction
           (make-blob-transaction
            :chain-id 1 :nonce 0 :max-fee-per-gas 1000
            :max-priority-fee-per-gas 1 :gas-limit 21000
            :max-fee-per-blob-gas 10
            :to (address-from-hex
                 "0x0000000000000000000000000000000000003001")
            :blob-versioned-hashes
            (list (kzg-commitment-to-versioned-hash commitment))
            :y-parity 0 :r 8 :s 9))
         (sidecar
           (make-blob-sidecar
            :blobs (list blob)
            :commitments (list commitment)
            :proofs (list proof))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (actual-blob actual-commitment actual-proof)
              (and (bytes= blob actual-blob)
                   (bytes= commitment actual-commitment)
                   (bytes= proof actual-proof)))))
      (engine-payload-store-put-blob-sidecar store sidecar))
    (let ((legacy
            (ethereum-lisp.cli::devnet-pooled-blob-sidecar
             store transaction :version 1)))
      (is legacy)
      (is (= 1 (length (blob-sidecar-proofs legacy))))
      (is (bytes= proof (first (blob-sidecar-proofs legacy)))))
    ;; A V1 RPC wrapper has no cell proofs and must not be mislabeled as the
    ;; eth/72 sidecar representation.
    (is (null
         (ethereum-lisp.cli::devnet-pooled-blob-sidecar
          store transaction :version 2)))))

(deftest devnet-broadcast-retains-a-burst-past-the-wire-batch-limit
  (:layer :unit :module :devnet)
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (pending (ethereum-lisp.cli::devnet-peer-pending-broadcast node))
         (count (+ ethereum-lisp.cli::+devnet-broadcast-batch-limit+ 17))
         (transactions
           (loop for private-key from 1 to count
                 collect (mining-order-test-transaction
                          private-key 0 (+ 1000 private-key)))))
    (dolist (transaction transactions)
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       store transaction))
    (let* ((first (funcall pending))
           (second (funcall pending))
           (offered (append first second)))
      (is (= ethereum-lisp.cli::+devnet-broadcast-batch-limit+
             (length first)))
      (is (= 17 (length second)))
      (is (= count (length offered)))
      (is (= count
             (length
              (remove-duplicates
               (mapcar (lambda (entry)
                         (bytes-to-hex
                          (hash32-bytes
                           (transaction-hash
                            (ethereum-lisp.eth-wire:eth-pooled-entry-transaction
                             entry)))))
                       offered)
               :test #'string=))))
      (is (null (funcall pending))))))
