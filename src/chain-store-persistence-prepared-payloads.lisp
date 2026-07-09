(in-package #:ethereum-lisp.core)

(defun chain-store-byte-list-from-rlp-object (value label)
  (mapcar
   (lambda (field)
     (rlp-bytes-field field label))
   (rlp-list-field value label)))

(defun chain-store-blob-sidecar-bundle-from-rlp-object (value)
  (let ((fields (rlp-list-field value "KV prepared-payload blob bundle")))
    (unless (= 3 (length fields))
      (block-validation-fail
       "KV prepared-payload blob bundle must have exactly 3 fields"))
    (make-blob-sidecar
     :blobs
     (chain-store-byte-list-from-rlp-object
      (first fields)
      "KV prepared-payload blob")
     :commitments
     (chain-store-byte-list-from-rlp-object
      (second fields)
      "KV prepared-payload commitment")
     :proofs
     (chain-store-byte-list-from-rlp-object
      (third fields)
      "KV prepared-payload proof"))))

(defun chain-store-prepared-payload-from-rlp
    (payload-id-identifier record)
  (handler-case
      (let* ((value (rlp-decode-one record))
             (fields (rlp-list-field value "KV prepared-payload record")))
        (unless (= 4 (length fields))
          (block-validation-fail
           "KV prepared-payload record must have exactly 4 fields"))
        (let ((payload-id
                (validate-sized-byte-vector
                 (rlp-bytes-field
                  (first fields)
                  "KV prepared-payload id")
                 8
                 "KV prepared-payload id"))
              (version
                (rlp-uint-field
                 (second fields)
                 "KV prepared-payload version"))
              (block
                (block-from-rlp
                 (rlp-bytes-field
                  (third fields)
                  "KV prepared-payload block")))
              (blobs-bundle
                (chain-store-blob-sidecar-bundle-from-rlp-object
                 (fourth fields))))
          (unless (bytes= payload-id (ensure-byte-vector payload-id-identifier))
            (block-validation-fail
             "KV prepared-payload record key does not match encoded payload id"))
          (make-engine-prepared-payload
           :payload-id payload-id
           :version version
           :block block
           :blobs-bundle blobs-bundle)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV prepared-payload record RLP: ~A" condition))))

(defun chain-store-import-prepared-payload-from-kv
    (store payload-id-identifier record)
  (let ((prepared-payload
          (chain-store-prepared-payload-from-rlp
           payload-id-identifier record)))
    (validate-engine-prepared-payload prepared-payload)
    (let* ((block (engine-prepared-payload-block prepared-payload))
           (block-hash (block-hash block))
           (known-block (chain-store-known-block store block-hash)))
      (unless (engine-payload-store-invalid-block store block-hash)
        (when (or (null known-block)
                  (bytes= (block-rlp known-block)
                          (block-rlp block)))
        (setf (gethash
               (engine-payload-id-key
                (engine-prepared-payload-payload-id prepared-payload))
               (engine-payload-memory-store-prepared-payloads store))
              prepared-payload))))))

(defun chain-store-import-prepared-payloads-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :prepared-payload))
    (chain-store-import-prepared-payload-from-kv
     store (car entry) (cdr entry))))
