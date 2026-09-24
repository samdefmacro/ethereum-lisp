(in-package #:ethereum-lisp.txpool.application)

;;;; Pooled blob transaction admission: one path, one pool mutation.
;;;;
;;;; A blob transaction and its sidecar enter the pool together or not at all.
;;;; TXPOOL-ADMIT-BLOB-TRANSACTION runs, in this order:
;;;;
;;;;   1. the pool's policy and capacity checks, which read the store but do
;;;;      not change it (sender, nonce, balance, fees, reservations, the blob
;;;;      count limit, the pooled-blob cap);
;;;;   2. the sidecar's shape: counts, element sizes, and each commitment's
;;;;      versioned hash against the transaction -- no curve arithmetic;
;;;;   3. KZG verification of every proof (EIP-4844 blob proofs, or EIP-7594
;;;;      cell proofs), and for a cell-proof sidecar the blob proof getBlobsV1
;;;;      serves, which touches no store;
;;;;   4. the checks of step 1 again, then ONE atomic commit that puts the
;;;;      transaction in the blob subpool and its blobs in the chain store's
;;;;      blob cache, marked pool-owned.
;;;;
;;;; A caller that serializes store access with a lock passes CALL-WITH-STORE,
;;;; so steps 1 and 4 run under it and steps 2 and 3 do not: KZG verification
;;;; costs milliseconds per blob, and the node store guard also serializes
;;;; every Engine request. This is go-ethereum v1.17 core/txpool/blobpool's
;;;; order: BlobPool.Add runs ValidateTxBasics and ValidateCells before
;;;; AddPooledTx takes the pool lock, and addLocked stores the transaction and
;;;; its blobs as one record.
;;;;
;;;; A malformed sidecar or a failing proof signals TXPOOL-INVALID-BLOB-SIDECAR,
;;;; so a peer layer can tell the sender's fault from a pool policy refusal.
;;;; The pooled blobs are pinned while a pooled transaction references them
;;;; (CHAIN-STORE-BLOB-SIDECAR-PINNED-P) and leave with the last one; the pool
;;;; bounds them with +TXPOOL-MAX-POOLED-BLOBS+ and the blob transaction
;;;; lifetime, which is measured from a persisted admission time.

(defconstant +txpool-max-pooled-blobs+ 1024
  "Most distinct blobs the pooled blob transactions may reference: 128 MiB of
blob data (131,072 bytes each) plus their proofs. A blob transaction that would
exceed it is refused before its proofs are verified.")

(define-condition txpool-invalid-blob-sidecar (block-validation-error) ()
  (:documentation
   "A blob transaction's sidecar is malformed or a KZG proof in it does not
verify. Unlike a pool policy refusal this is the fault of whoever sent it."))

(defun txpool-invalid-blob-sidecar-fail (control &rest arguments)
  (error 'txpool-invalid-blob-sidecar
         :message (apply #'format nil control arguments)))

(defstruct (txpool-verified-blob-sidecar
            (:constructor %make-txpool-verified-blob-sidecar
                (transaction sidecar blob-proofs)))
  "A blob transaction with a sidecar whose every KZG proof verified against it.
Only TXPOOL-VERIFY-BLOB-SIDECAR makes one. BLOB-PROOFS holds the EIP-4844 blob
proof per blob of a cell-proof sidecar, derived outside the store guard."
  (transaction nil :read-only t)
  (sidecar nil :read-only t)
  (blob-proofs nil :read-only t))

(defun txpool-transaction-known-p (transaction store)
  "Whether TRANSACTION is already pooled or already in the chain. Admitting a
known transaction is a no-op that answers its hash, as TXPOOL-ADMIT-TRANSACTION
does."
  (let ((hash (transaction-hash transaction)))
    (or (chain-store-transaction-location store hash)
        (engine-payload-store-pooled-transaction store hash))))

(defun txpool-check-blob-admission (transaction store config policy)
  "Every admission check TXPOOL-ADMIT-BLOB-TRANSACTION makes of the pool and
the chain before the proofs are verified. Reads STORE; changes nothing.
Signals BLOCK-VALIDATION-ERROR naming the refusal; returns the sender and the
admission state."
  (unless (typep transaction 'blob-transaction)
    (block-validation-fail "Blob admission requires a blob transaction"))
  (validate-txpool-encoded-size transaction)
  (let* ((hash (transaction-hash transaction))
         (sender
           (or (transaction-sender
                transaction
                :expected-chain-id (chain-config-chain-id config))
               (block-validation-fail
                "eth_sendRawTransaction transaction sender recovery failed"))))
    (when (txpool-transaction-known-p transaction store)
      (block-validation-fail "Blob transaction ~A is already known"
                             (hash32-to-hex hash)))
    (let ((admission-state (txpool-load-admission-state store sender)))
      (validate-txpool-delegation-reservations
       store sender transaction config admission-state)
      (validate-admission-policy
       transaction (txpool-local-transaction-p sender policy) policy)
      ;; Includes the fork's blob count limit, which bounds every later step.
      (validate-txpool-admission transaction sender store config
                                 admission-state)
      (let ((conflict
              (ethereum-lisp.txpool.index:engine-pending-txpool-blob-conflict
               (engine-payload-store-txpool store) transaction)))
        (if conflict
            (unless (ethereum-lisp.txpool.index:engine-pending-txpool-replacement-transaction-p
                     conflict transaction
                     :price-bump-percent
                     (txpool-admission-policy-price-bump-percent policy))
              (block-validation-fail "Blob transaction replacement underpriced"))
            (let ((new-blobs
                    (loop for versioned-hash across
                            (transaction-blob-versioned-hashes transaction)
                          count (not (engine-payload-store-blob-owned-p
                                      store versioned-hash)))))
              (when (> (+ (engine-payload-store-owned-blob-count store)
                          new-blobs)
                       +txpool-max-pooled-blobs+)
                (block-validation-fail
                 "Blob pool is full: ~D pooled blobs, cap ~D"
                 (engine-payload-store-owned-blob-count store)
                 +txpool-max-pooled-blobs+)))))
      (values sender admission-state))))

(defun txpool-check-blob-sidecar-shape (transaction sidecar)
  "The sidecar checks that need no curve arithmetic: SIDECAR carries one blob,
commitment and proof set per versioned hash of TRANSACTION, every element has
its fixed size, and each commitment hashes to the transaction's versioned hash
(EIP-4844 kzg_to_versioned_hash). Run after the pool checks have bounded the
blob count, so the work here is bounded too."
  (unless (typep sidecar 'blob-sidecar)
    (txpool-invalid-blob-sidecar-fail "Blob transaction sidecar is missing"))
  (let* ((expected (transaction-blob-versioned-hashes transaction))
         (count (length expected))
         (blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar)))
    (unless (and (= count (length blobs)) (= count (length commitments)))
      (txpool-invalid-blob-sidecar-fail
       "Blob sidecar has ~D blobs and ~D commitments for ~D versioned hashes"
       (length blobs) (length commitments) count))
    (unless (or (= (length proofs) count)
                (= (length proofs) (* count +cell-proofs-per-blob+)))
      (txpool-invalid-blob-sidecar-fail
       "Blob sidecar has ~D proofs for ~D blobs; expected one or ~D per blob"
       (length proofs) count +cell-proofs-per-blob+))
    (flet ((sized-p (value size)
             (and (typep value 'vector) (= size (length value)))))
      (unless (every (lambda (blob) (sized-p blob +blob-byte-size+)) blobs)
        (txpool-invalid-blob-sidecar-fail
         "Blob sidecar blob must be ~D bytes" +blob-byte-size+))
      (unless (every (lambda (commitment)
                       (sized-p commitment +kzg-commitment-size+))
                     commitments)
        (txpool-invalid-blob-sidecar-fail
         "Blob sidecar commitment must be ~D bytes" +kzg-commitment-size+))
      (unless (every (lambda (proof) (sized-p proof +kzg-proof-size+)) proofs)
        (txpool-invalid-blob-sidecar-fail
         "Blob sidecar proof must be ~D bytes" +kzg-proof-size+)))
    (loop for actual in (blob-sidecar-versioned-hashes sidecar)
          for wanted across expected
          for index from 0
          unless (bytes= (hash32-bytes actual)
                         (blob-versioned-hash-bytes wanted))
            do (txpool-invalid-blob-sidecar-fail
                "Blob sidecar commitment ~D does not match its versioned hash"
                index))
    t))

(defun txpool-verify-blob-sidecar (transaction sidecar)
  "Verify every KZG proof of SIDECAR against TRANSACTION and return a
TXPOOL-VERIFIED-BLOB-SIDECAR. Touches no store: call it outside any store lock.
A failing proof or a malformed field signals TXPOOL-INVALID-BLOB-SIDECAR; a
missing native KZG library still signals KZG-UNAVAILABLE-ERROR, which is this
node's capability and not the sender's fault."
  (txpool-check-blob-sidecar-shape transaction sidecar)
  (handler-case
      (validate-blob-sidecar-fields sidecar :transaction transaction
                                            :require-proof-verification t)
    (txpool-invalid-blob-sidecar (condition) (error condition))
    (block-validation-error (condition)
      (txpool-invalid-blob-sidecar-fail
       "~A" (block-validation-error-message condition))))
  (let ((blobs (blob-sidecar-blobs sidecar)))
    (%make-txpool-verified-blob-sidecar
     transaction sidecar
     ;; A cell-proof (EIP-7594) sidecar carries no EIP-4844 blob proof, which
     ;; getBlobsV1 and the V1 pooled wrapper serve: derive it here rather than
     ;; under the store guard at publication.
     (when (and blobs
                (/= (length (blob-sidecar-proofs sidecar)) (length blobs)))
       (loop for blob in blobs
             for commitment in (blob-sidecar-commitments sidecar)
             collect (compute-kzg-blob-proof blob commitment))))))

(defun txpool-admit-verified-blob-transaction
    (verified store config policy &key admitted-at)
  "Admit VERIFIED's transaction and blobs in one atomic commit, after
re-running the pool checks against the store as it is now. Returns the
transaction hash. Nothing is left behind when any step refuses."
  (unless (typep verified 'txpool-verified-blob-sidecar)
    (block-validation-fail
     "Blob admission requires a sidecar verified by TXPOOL-VERIFY-BLOB-SIDECAR"))
  (let ((transaction (txpool-verified-blob-sidecar-transaction verified))
        (now (or admitted-at (unix-time))))
    (when (txpool-transaction-known-p transaction store)
      (return-from txpool-admit-verified-blob-transaction
        (transaction-hash transaction)))
    (chain-store-atomic-commit
     store
     (lambda ()
       ;; Expired blob transactions leave first, so their blobs do not count
       ;; against the cap the new transaction is measured by.
       (engine-payload-store-remove-expired-blob-transactions store now)
       (multiple-value-bind (sender admission-state)
           (txpool-check-blob-admission transaction store config policy)
         (admit-new-transaction
          transaction sender store config policy now admission-state)
         (unless (engine-payload-store-blob-transaction
                  store (transaction-hash transaction))
           (block-validation-fail "Blob transaction was not pooled"))
         (engine-payload-store-put-blob-sidecar
          store (txpool-verified-blob-sidecar-sidecar verified)
          :now now
          :blob-proofs (txpool-verified-blob-sidecar-blob-proofs verified)
          :pool-owned-p t
          :proofs-verified-p t))))
    (transaction-hash transaction)))

(defun txpool-admit-blob-transaction
    (transaction sidecar store config policy
     &key admitted-at (call-with-store #'funcall))
  "Admit the blob TRANSACTION with its SIDECAR through the one pooled-blob
admission path (see this file's header). CALL-WITH-STORE is called with a
thunk for each step that reads or writes STORE; a node passes its store guard
so the KZG verification between them runs outside it. Returns the transaction
hash; signals TXPOOL-INVALID-BLOB-SIDECAR for the sender's fault and
BLOCK-VALIDATION-ERROR for any other refusal, in both cases before any change
to the pool or the blob store."
  (when (funcall call-with-store
                 (lambda ()
                   (or (txpool-transaction-known-p transaction store)
                       (progn
                         (txpool-check-blob-admission
                          transaction store config policy)
                         nil))))
    (return-from txpool-admit-blob-transaction
      (transaction-hash transaction)))
  (let ((verified (txpool-verify-blob-sidecar transaction sidecar)))
    (funcall call-with-store
             (lambda ()
               (txpool-admit-verified-blob-transaction
                verified store config policy :admitted-at admitted-at)))))
