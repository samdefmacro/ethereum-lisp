(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-blob-sidecar-record-from-rlp (record)
  (handler-case
      (let* ((value (rlp-decode-one record))
             (fields (rlp-list-field value "KV blob-sidecar record")))
        (unless (= 4 (length fields))
          (block-validation-fail
           "KV blob-sidecar record must have exactly 4 fields"))
        (let* ((blob
                 (validate-sized-byte-vector
                  (rlp-bytes-field (first fields) "KV blob-sidecar blob")
                  +blob-byte-size+
                  "KV blob-sidecar blob"))
               (commitment
                 (validate-sized-byte-vector
                  (rlp-bytes-field (second fields) "KV blob-sidecar commitment")
                  +kzg-commitment-size+
                  "KV blob-sidecar commitment"))
               (proof
                 (validate-sized-byte-vector
                  (rlp-bytes-field (third fields) "KV blob-sidecar proof")
                  +kzg-proof-size+
                  "KV blob-sidecar proof"))
               (cell-proofs
                 (mapcar
                  (lambda (proof-field)
                    (validate-sized-byte-vector
                     (rlp-bytes-field
                      proof-field
                      "KV blob-sidecar cell proof")
                     +kzg-proof-size+
                     "KV blob-sidecar cell proof"))
                  (rlp-list-field
                   (fourth fields)
                   "KV blob-sidecar cell proofs"))))
          (unless (or (null cell-proofs)
                      (= +cell-proofs-per-blob+ (length cell-proofs)))
            (block-validation-fail
             "KV blob-sidecar cell proof count must be zero or ~D"
             +cell-proofs-per-blob+))
          (make-engine-blob-and-proofs
           :blob blob
           :commitment commitment
           :proof proof
           :cell-proofs cell-proofs)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV blob-sidecar record RLP: ~A" condition))))

(defun chain-store-validate-blob-and-proofs (blob-and-proofs)
  "Verify one decoded durable blob record before exposing it to a caller."
  (let* ((cell-proofs
           (engine-blob-and-proofs-cell-proofs blob-and-proofs))
         (sidecar
           (make-blob-sidecar
            :blobs (list (engine-blob-and-proofs-blob blob-and-proofs))
            :commitments
            (list (engine-blob-and-proofs-commitment blob-and-proofs))
            :proofs (if cell-proofs
                        cell-proofs
                        (list (engine-blob-and-proofs-proof
                               blob-and-proofs))))))
    ;; VALIDATE-BLOB-SIDECAR-FIELDS classifies a statically absent verifier as
    ;; input validation. At this durable lazy-read boundary it is instead a
    ;; local capability failure: the bytes are not corrupt merely because this
    ;; process cannot currently verify them.
    (if cell-proofs
        (unless (kzg-cell-proof-verification-available-p)
          (kzg-unavailable-error
           "KZG cell proof verification is not available"))
        (unless (kzg-blob-proof-verification-available-p)
          (kzg-unavailable-error
           "KZG blob proof verification is not available")))
    (validate-blob-sidecar-fields
     sidecar
     :require-proof-verification t))
  blob-and-proofs)

(defun chain-store-import-blob-sidecar-from-kv
    (store versioned-hash-identifier record &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (let ((versioned-hash (make-hash32 versioned-hash-identifier))
        (blob-and-proofs
          (chain-store-blob-sidecar-record-from-rlp record)))
    (unless (hash32= versioned-hash
                     (kzg-commitment-to-versioned-hash
                      (engine-blob-and-proofs-commitment blob-and-proofs)))
      (block-validation-fail
       "KV blob-sidecar record key does not match encoded commitment"))
    (let* ((cell-proofs
             (engine-blob-and-proofs-cell-proofs blob-and-proofs))
           (sidecar
             (make-blob-sidecar
              :blobs (list (engine-blob-and-proofs-blob blob-and-proofs))
              :commitments
              (list (engine-blob-and-proofs-commitment blob-and-proofs))
              :proofs (if cell-proofs
                          cell-proofs
                          (list (engine-blob-and-proofs-proof
                                 blob-and-proofs))))))
      ;; Admission, metadata accounting, and eviction happen for each record;
      ;; recovery never constructs an oversized transient sidecar cache.
      (engine-payload-store-put-blob-sidecar store sidecar :now now))))

(defun chain-store-import-blob-sidecars-from-kv (store database)
  (let ((now (unix-time)))
    (multiple-value-bind (iterator closer)
        (kv-iterator
         database
         :start (kv-chain-record-kind-start-key :blob-sidecar)
         :end (kv-chain-record-kind-end-key :blob-sidecar))
      (unwind-protect
           (loop
             (multiple-value-bind (key record present-p)
                 (funcall iterator)
               (unless present-p
                 (return))
               (chain-store-import-blob-sidecar-from-kv
                store
                (kv-chain-record-key-identifier :blob-sidecar key)
                record
                :now now)))
        (funcall closer)))))

(defun node-store-import-txpool-blob-sidecars-from-kv (store database)
  "Point-read exactly the sidecars referenced by STORE's bounded txpool."
  (let ((seen (make-hash-table :test 'equal))
        (now (unix-time)))
    (dolist (transaction (node-store-current-txpool-transactions store))
      (loop for versioned-hash across
              (transaction-blob-versioned-hashes transaction)
            for identifier = (hash32-bytes versioned-hash)
            for key = (bytes-to-hex identifier)
            unless (gethash key seen)
              do (setf (gethash key seen) t)
                 (multiple-value-bind (record present-p)
                     (kv-get-chain-record
                      database :blob-sidecar identifier)
                   (unless present-p
                     (block-validation-fail
                      "Persisted blob transaction is missing sidecar ~A"
                      key))
                   (chain-store-import-blob-sidecar-from-kv
                    store identifier record :now now))))
    (engine-payload-store-prune-caches store :now now)
    store))
