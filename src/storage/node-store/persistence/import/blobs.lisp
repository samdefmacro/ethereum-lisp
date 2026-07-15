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

(defun chain-store-import-blob-sidecar-from-kv
    (store versioned-hash-identifier record)
  (setf store (chain-store-require-memory-store store))
  (let ((versioned-hash (make-hash32 versioned-hash-identifier))
        (blob-and-proofs
          (chain-store-blob-sidecar-record-from-rlp record)))
    (unless (hash32= versioned-hash
                     (kzg-commitment-to-versioned-hash
                      (engine-blob-and-proofs-commitment blob-and-proofs)))
      (block-validation-fail
       "KV blob-sidecar record key does not match encoded commitment"))
    (setf (gethash
           (engine-payload-store-key versioned-hash)
           (memory-chain-store-blob-sidecars store))
          blob-and-proofs)))

(defun chain-store-import-blob-sidecars-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :blob-sidecar))
    (chain-store-import-blob-sidecar-from-kv
     store (car entry) (cdr entry))))
