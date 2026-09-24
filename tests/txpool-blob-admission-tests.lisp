(in-package #:ethereum-lisp.test)

;;;; Pooled blob transactions: one admission, one mutation, and a sidecar that
;;;; lives exactly as long as a pooled transaction references it.
;;;;
;;;; Oracles: EIP-4844 (versioned hash = 0x01 || sha256(commitment)[1:]),
;;;; EIP-7594 (cell proofs), and go-ethereum v1.17 core/txpool/blobpool:
;;;; BlobPool.Add runs ValidateTxBasics and ValidateCells (KZG) before
;;;; AddPooledTx takes the pool lock, and addLocked stores the transaction and
;;;; its blobs as ONE record, so a transaction the pool refuses leaves nothing
;;;; behind and a pooled transaction can never lose its blobs.

(defun txpool-s6-config ()
  (make-chain-config :chain-id 1337
                     :london-block 0
                     :shanghai-time 0
                     :cancun-time 0
                     :prague-time 0))

(defun txpool-s6-store (private-keys &key (base-fee 1) (gas-used 0)
                                          (balance (expt 10 24))
                                          london-only-p)
  "A memory node store whose head block (number 0) holds state funding every
key in PRIVATE-KEYS. Returns the store, its config and the head block.
LONDON-ONLY-P gives a London header and config, which the durable block codec
round-trips without the later forks' header fields."
  (let* ((store (make-engine-payload-memory-store))
         (config (if london-only-p
                     (make-chain-config :chain-id 1337 :london-block 0)
                     (txpool-s6-config)))
         (state (make-state-db))
         (head
           (make-block
            :header
            (if london-only-p
                (make-block-header
                 :number 0 :timestamp 0 :gas-limit 30000000
                 :gas-used gas-used :base-fee-per-gas base-fee)
                (make-block-header
                 :number 0 :timestamp 0 :gas-limit 30000000
                 :gas-used gas-used :base-fee-per-gas base-fee
                 :blob-gas-used 0 :excess-blob-gas 0)))))
    (dolist (key private-keys)
      (state-db-set-account
       state (fixture-private-key-address key)
       (make-state-account :nonce 0 :balance balance)))
    (setf (block-header-state-root (block-header head)) (state-db-root state))
    (chain-store-put-block store head :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash head) state)
    (values store config head)))

(defun txpool-s6-commitment (byte)
  (make-byte-vector +kzg-commitment-size+ :initial-element byte))

(defun txpool-s6-blob-transaction
    (private-key commitment-byte
     &key (nonce 0) (tip 2) (fee-cap 1000) (blob-fee-cap 100)
          (chain-id 1337))
  "A signed one-blob transaction and its V0 (blob proof) sidecar. The blob is
all zeros, a valid field-element encoding; proof verification is stubbed by
the callers, so only the commitment has to match the versioned hash."
  (let* ((commitment (txpool-s6-commitment commitment-byte))
         (transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id chain-id :nonce nonce
             :max-priority-fee-per-gas tip :max-fee-per-gas fee-cap
             :gas-limit 21000
             :to (address-from-hex "0x0000000000000000000000000000000000003001")
             :max-fee-per-blob-gas blob-fee-cap
             :blob-versioned-hashes
             (list (kzg-commitment-to-versioned-hash commitment)))
            private-key))
         (sidecar
           (make-blob-sidecar
            :blobs (list (make-byte-vector +blob-byte-size+))
            :commitments (list commitment)
            :proofs (list (make-byte-vector +kzg-proof-size+
                                            :initial-element #x22)))))
    (values transaction sidecar
            (kzg-commitment-to-versioned-hash commitment))))

(defun txpool-s6-pool-image (store)
  "Every byte the txpool and the blob store hold, in a canonical order: each
pooled transaction's subpool, encoding and admission time, then each cached
blob record keyed by versioned hash. Two equal images are two identical pools."
  (let* ((txpool (ethereum-lisp.txpool:engine-payload-store-txpool store))
         (chain (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                 store))
         (entries '()))
    (flet ((note-subpool (label transactions)
             (dolist (transaction transactions)
               (push (list (hash32-to-hex (transaction-hash transaction))
                           label
                           (bytes-to-hex (transaction-encoding transaction))
                           (ethereum-lisp.txpool.index:engine-pending-txpool-admission-time
                            txpool transaction))
                     entries))))
      (note-subpool "pending"
                    (ethereum-lisp.txpool:engine-payload-store-pending-transactions
                     store))
      (note-subpool "queued"
                    (ethereum-lisp.txpool:engine-payload-store-queued-transactions
                     store))
      (note-subpool "basefee"
                    (ethereum-lisp.txpool:engine-payload-store-basefee-transactions
                     store))
      (note-subpool "blob"
                    (ethereum-lisp.txpool:engine-payload-store-blob-transactions
                     store)))
    (maphash
     (lambda (key record)
       (push (list key "sidecar"
                   (bytes-to-hex
                    (apply #'concat-bytes
                           (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob
                            record)
                           (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                            record)
                           (ethereum-lisp.chain-store.model:engine-blob-and-proofs-proof
                            record)
                           (ethereum-lisp.chain-store.model:engine-blob-and-proofs-cell-proofs
                            record)))
                   nil)
             entries))
     (ethereum-lisp.chain-store.state:memory-chain-store-blob-sidecars chain))
    (sort entries #'string< :key #'first)))

(defun txpool-s6-send-raw (store config transaction sidecar)
  "eth_sendRawTransaction of TRANSACTION's pooled (wrapper) form; returns the
decoded JSON response."
  (parse-json
   (engine-rpc-handle-request-json
    (concatenate
     'string
     "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_sendRawTransaction\","
     "\"params\":[\""
     (bytes-to-hex (blob-pooled-transaction-encoding transaction sidecar))
     "\"]}")
    store config)))

(defun txpool-s6-field (object name)
  (cdr (assoc name object :test #'string=)))

(defmacro with-txpool-s6-blob-proofs ((&key (valid-p t) calls) &body body)
  "Run BODY with the EIP-4844 blob-proof verifier stubbed to VALID-P, counting
its calls in the place CALLS when given."
  (let ((blob (gensym "BLOB")) (commitment (gensym "COMMITMENT"))
        (proof (gensym "PROOF")))
    `(let ((*kzg-blob-proof-verifier*
             (lambda (,blob ,commitment ,proof)
               (declare (ignore ,blob ,commitment ,proof))
               ,@(when calls `((incf ,calls)))
               ,valid-p)))
       ,@body)))

;;; A wrong proof or a malformed sidecar never reaches the pool.

(deftest txpool-blob-admission-rejects-bad-sidecars-before-any-pool-mutation
  (:layer :unit :module :txpool)
  (multiple-value-bind (store config) (txpool-s6-store '(11))
    (multiple-value-bind (transaction sidecar versioned-hash)
        (txpool-s6-blob-transaction 11 #x31)
      (let ((before (txpool-s6-pool-image store)))
        ;; 1. The proof does not verify.
        (let ((response
                (with-txpool-s6-blob-proofs (:valid-p nil)
                  (txpool-s6-send-raw store config transaction sidecar))))
          (is (txpool-s6-field response "error"))
          (is (equalp before (txpool-s6-pool-image store))))
        ;; 2. The commitment is not the one the transaction commits to.
        (let ((wrong-commitment
                (make-blob-sidecar
                 :blobs (blob-sidecar-blobs sidecar)
                 :commitments (list (txpool-s6-commitment #x32))
                 :proofs (blob-sidecar-proofs sidecar))))
          (let ((response
                  (with-txpool-s6-blob-proofs ()
                    (txpool-s6-send-raw store config transaction
                                        wrong-commitment))))
            (is (txpool-s6-field response "error"))
            (is (equalp before (txpool-s6-pool-image store)))))
        ;; 3. A blob that is not 131072 bytes.
        (let ((short-blob
                (make-blob-sidecar
                 :blobs (list (make-byte-vector 7))
                 :commitments (blob-sidecar-commitments sidecar)
                 :proofs (blob-sidecar-proofs sidecar))))
          (let ((response
                  (with-txpool-s6-blob-proofs ()
                    (txpool-s6-send-raw store config transaction short-blob))))
            (is (txpool-s6-field response "error"))
            (is (equalp before (txpool-s6-pool-image store)))))
        ;; Positive control: the same transaction with a verifying proof is
        ;; admitted, and it changes the image (transaction AND sidecar).
        (let ((response
                (with-txpool-s6-blob-proofs ()
                  (txpool-s6-send-raw store config transaction sidecar))))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (txpool-s6-field response "result")))
          (is (not (equalp before (txpool-s6-pool-image store))))
          (is (= 1 (ethereum-lisp.txpool:engine-payload-store-blob-transaction-count
                    store)))
          (is (engine-payload-store-blob-and-proofs-v1 store versioned-hash)))))))

(deftest txpool-blob-admission-verifies-each-proof-once
  (:layer :unit :module :txpool)
  ;; The RPC path verified the sidecar, admitted the transaction, and then
  ;; the store verified the same proofs again before publishing them.
  (multiple-value-bind (store config) (txpool-s6-store '(12))
    (multiple-value-bind (transaction sidecar) (txpool-s6-blob-transaction 12 #x41)
      (let ((calls 0))
        (let ((response
                (with-txpool-s6-blob-proofs (:calls calls)
                  (txpool-s6-send-raw store config transaction sidecar))))
          (is (txpool-s6-field response "result")))
        ;; Positive control that the counter is wired: the proof was verified.
        (is (<= 1 calls))
        (is (= 1 calls))))))

;;; The sidecar belongs to the pooled transaction.

(deftest txpool-pooled-blob-sidecar-survives-cache-pressure-and-age
  (:layer :unit :module :txpool)
  ;; The sidecar cache evicts by count, bytes and a three-hour age. A pooled
  ;; transaction's blobs must not go with that pressure: the transaction would
  ;; stay pending with nothing to build or serve.
  (multiple-value-bind (store config) (txpool-s6-store '(13))
    (multiple-value-bind (transaction sidecar versioned-hash)
        (txpool-s6-blob-transaction 13 #x51)
      (multiple-value-bind (loose loose-sidecar loose-hash)
          (txpool-s6-blob-transaction 14 #x52)
        (declare (ignore loose))
        (with-txpool-s6-blob-proofs ()
          (is (txpool-s6-field
               (txpool-s6-send-raw store config transaction sidecar)
               "result"))
          ;; A sidecar no pooled transaction references (as a block import
          ;; would leave one) is the positive control for the eviction.
          (engine-payload-store-put-blob-sidecar store loose-sidecar))
        (is (engine-payload-store-blob-and-proofs-v1 store loose-hash))
        (let ((later (+ (unix-time) (* 4 60 60))))
          (ethereum-lisp.chain-store::engine-payload-store-enforce-cache-bounds
           store :sidecar later nil :count-limit 0 :byte-limit 0)
          (is (null (engine-payload-store-blob-and-proofs-v1
                     store loose-hash :now later)))
          (is (= 1 (ethereum-lisp.txpool:engine-payload-store-blob-transaction-count
                    store)))
          (is (engine-payload-store-blob-and-proofs-v1
               store versioned-hash :now later)))))))

(deftest txpool-blob-sidecar-leaves-with-its-transaction
  (:layer :unit :module :txpool)
  ;; Inclusion and replacement both take the transaction out of the pool; its
  ;; blobs must go with it rather than linger for the cache's three hours.
  (multiple-value-bind (store config) (txpool-s6-store '(15 16))
    (multiple-value-bind (included included-sidecar included-hash)
        (txpool-s6-blob-transaction 15 #x61)
      (multiple-value-bind (replaced replaced-sidecar replaced-hash)
          (txpool-s6-blob-transaction 16 #x62)
        (multiple-value-bind (replacement replacement-sidecar replacement-hash)
            (txpool-s6-blob-transaction 16 #x63 :tip 4 :fee-cap 2000
                                                :blob-fee-cap 200)
          (with-txpool-s6-blob-proofs ()
            (is (txpool-s6-field
                 (txpool-s6-send-raw store config included included-sidecar)
                 "result"))
            (is (txpool-s6-field
                 (txpool-s6-send-raw store config replaced replaced-sidecar)
                 "result")))
          ;; Control: both sidecars are there while their transactions are.
          (is (engine-payload-store-blob-and-proofs-v1 store included-hash))
          (is (engine-payload-store-blob-and-proofs-v1 store replaced-hash))
          ;; Inclusion.
          (ethereum-lisp.txpool:engine-payload-store-remove-included-block-transactions
           store (make-block :header (make-block-header :number 1)
                             :transactions (list included)))
          (is (null (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                     store (transaction-hash included))))
          (is (null (engine-payload-store-blob-and-proofs-v1 store included-hash)))
          ;; Replacement (a 100% bump on every fee, as blob replacement needs).
          (with-txpool-s6-blob-proofs ()
            (is (txpool-s6-field
                 (txpool-s6-send-raw store config replacement
                                     replacement-sidecar)
                 "result")))
          (is (null (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                     store (transaction-hash replaced))))
          (is (null (engine-payload-store-blob-and-proofs-v1 store replaced-hash)))
          (is (engine-payload-store-blob-and-proofs-v1 store replacement-hash)))))))

;;; Admission age survives a restart.

(deftest txpool-admission-age-survives-a-restart
  (:layer :unit :module :txpool)
  ;; --txpool.lifetime drops a parked transaction by its admission time. The
  ;; time lived only in memory, so every restart gave every parked transaction
  ;; a fresh (in fact an absent, never-expiring) age.
  (let ((path (merge-pathnames
               (make-pathname
                :name (format nil "ethereum-lisp-txpool-age-~A" (gensym))
                :type "sexp")
               #P"/private/tmp/")))
    (multiple-value-bind (source config)
        (txpool-s6-store '(17) :london-only-p t)
      (let* ((queued
               (fixture-sign-legacy-transaction
                (make-legacy-transaction
                 :nonce 3 :gas-price 100 :gas-limit 21000
                 :to (address-from-hex
                      "0x0000000000000000000000000000000000003001"))
                17 1337))
             (policy (ethereum-lisp.txpool.application:make-txpool-admission-policy)))
        (ethereum-lisp.txpool.application:txpool-admit-transaction
         queued source config policy :admitted-at 1000)
        (is (= 1 (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                  source)))
        (unwind-protect
             (let ((restored (make-engine-payload-memory-store)))
               (node-store-export-to-kv source (make-file-key-value-database path))
               (node-store-import-from-kv restored
                                          (make-file-key-value-database path))
               (is (= 1 (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                         restored)))
               (let ((txpool (ethereum-lisp.txpool:engine-payload-store-txpool
                              restored)))
                 (is (eql 1000
                          (ethereum-lisp.txpool.index:engine-pending-txpool-admission-time
                           txpool queued))))
               ;; Control: an hour's lifetime has not passed at 1000 + 10 ...
               (is (null
                    (ethereum-lisp.txpool:engine-payload-store-remove-expired-txpool-queued-view-transactions
                     restored 3600 1010)))
               ;; ... and has at 1000 + 3600, after the restart as before it.
               (is (= 1
                      (length
                       (ethereum-lisp.txpool:engine-payload-store-remove-expired-txpool-queued-view-transactions
                        restored 3600 4600)))))
          (when (probe-file path)
            (delete-file path)))))))

;;; The production gossip wiring: a devnet node's peer backend.

(defconstant +txpool-s6-devnet-funded-key+ 81)

(defun txpool-s6-cancun-devnet-node ()
  (ethereum-lisp.cli:make-devnet-node
   :genesis-json
   (devnet-cli-funded-txpool-genesis-json
    :private-keys (list +txpool-s6-devnet-funded-key+)
    :config-fields (list (cons "cancunTime" "0x0")))
   :port 0 :public-port 0))

(deftest txpool-blob-gossip-rejected-by-the-pool-leaves-no-sidecar
  (:layer :integration :module :txpool)
  ;; A peer's blob transaction whose sender cannot pay: the sidecar used to be
  ;; stored by one callback before the pool refused the transaction in
  ;; another, leaving blobs no pooled transaction owns.
  (let* ((node (txpool-s6-cancun-devnet-node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (chain-id (chain-config-chain-id
                    (ethereum-lisp.cli:devnet-node-config node)))
         (backend (ethereum-lisp.cli::devnet-peer-serve-backend node)))
    (multiple-value-bind (unfunded unfunded-sidecar unfunded-hash)
        (txpool-s6-blob-transaction 7 #x71 :chain-id chain-id
                                           :fee-cap 2000000000)
      (multiple-value-bind (funded funded-sidecar funded-hash)
          (txpool-s6-blob-transaction +txpool-s6-devnet-funded-key+ #x72
                                      :chain-id chain-id :fee-cap 2000000000)
        (let ((before (txpool-s6-pool-image store)))
          (with-txpool-s6-blob-proofs ()
            (is (zerop (eth-accept-transactions
                        backend
                        (list (make-blob-network-transaction
                               unfunded unfunded-sidecar))))))
          (is (null (engine-payload-store-blob-and-proofs-v1
                     store unfunded-hash)))
          (is (equalp before (txpool-s6-pool-image store)))
          ;; Positive control: a funded sender's transaction enters with its
          ;; blobs through the same backend.
          (with-txpool-s6-blob-proofs ()
            (is (= 1 (eth-accept-transactions
                      backend
                      (list (make-blob-network-transaction
                             funded funded-sidecar))))))
          (is (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
               store (transaction-hash funded)))
          (is (engine-payload-store-blob-and-proofs-v1 store funded-hash)))))))

(deftest txpool-blob-gossip-verifies-once-and-outside-the-store-guard
  (:layer :integration :module :txpool)
  ;; KZG verification costs milliseconds per blob; the node store guard also
  ;; serializes every Engine request. The proof is checked once, before the
  ;; guard is taken for the pool mutation.
  #-sbcl
  (skip-test "Store-guard probe requires SBCL threads")
  #+sbcl
  (let* ((node (txpool-s6-cancun-devnet-node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (chain-id (chain-config-chain-id
                    (ethereum-lisp.cli:devnet-node-config node)))
         (backend (ethereum-lisp.cli::devnet-peer-serve-backend node))
         (verifications 0)
         (under-guard 0))
    (multiple-value-bind (transaction sidecar versioned-hash)
        (txpool-s6-blob-transaction +txpool-s6-devnet-funded-key+ #x73
                                    :chain-id chain-id :fee-cap 2000000000)
      (let ((*kzg-blob-proof-verifier*
              (lambda (blob commitment proof)
                (declare (ignore blob commitment proof))
                (incf verifications)
                ;; Probe from another thread: a guard held here refuses.
                (unless (sb-thread:join-thread
                         (sb-thread:make-thread
                          (lambda ()
                            (handler-case
                                (nth-value
                                 1
                                 (ethereum-lisp.cli::call-with-devnet-node-store-guard-if-free
                                  node (lambda () t)))
                              (serious-condition () nil)))))
                  (incf under-guard))
                t)))
        (is (= 1 (eth-accept-transactions
                  backend
                  (list (make-blob-network-transaction transaction sidecar))))))
      (is (engine-payload-store-blob-and-proofs-v1 store versioned-hash))
      (is (= 1 verifications))
      (is (zerop under-guard)))))
