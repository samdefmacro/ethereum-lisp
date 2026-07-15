(in-package #:ethereum-lisp.node-store.persistence)

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

(defun chain-store-prepared-payload-requests-from-rlp-object (value)
  (let ((fields
          (rlp-list-field value
                          "KV prepared-payload execution requests side data")))
    (unless (<= (length fields) 1)
      (block-validation-fail
       "KV prepared-payload execution requests side data must have at most one field"))
    (if fields
        (values
         (chain-store-byte-list-from-rlp-object
          (first fields)
          "KV prepared-payload execution request")
         t)
        (values nil nil))))

(defun chain-store-prepared-payload-block-access-list-from-rlp-object (value)
  (let ((fields
          (rlp-list-field value
                          "KV prepared-payload block access list side data")))
    (unless (<= (length fields) 1)
      (block-validation-fail
       "KV prepared-payload block access list side data must have at most one field"))
    (if fields
        (values
         (rlp-bytes-field
          (first fields)
          "KV prepared-payload block access list")
         t)
        (values nil nil))))

(defun chain-store-prepared-payload-block-with-side-data
    (block requests requests-present-p
           encoded-block-access-list block-access-list-present-p)
  (let ((restored
          (make-block-from-parts
           :header (block-header block)
           :transactions (block-transactions block)
           :receipts (block-receipts block)
           :ommers (block-ommers block)
           :withdrawals (block-withdrawals block)
           :withdrawals-present-p (block-withdrawals-present-p block)
           :requests requests
           :requests-present-p requests-present-p
           :block-access-list
           (when block-access-list-present-p
             (ethereum-lisp.block-access-lists:block-access-list-from-rlp
              encoded-block-access-list))
           :block-access-list-present-p block-access-list-present-p
           :encoded-block-access-list encoded-block-access-list)))
    (let ((header (block-header restored)))
      (cond
        ((block-header-requests-hash header)
         (unless requests-present-p
           (block-validation-fail
            "KV prepared-payload record is missing execution requests side data"))
         (ethereum-lisp.execution-requests:validate-execution-request-list-fields
          requests)
         (unless (hash32= (ethereum-lisp.execution-requests:execution-requests-hash
                           requests)
                          (block-header-requests-hash header))
           (block-validation-fail
            "KV prepared-payload execution requests hash mismatch")))
        (requests-present-p
         (block-validation-fail
          "KV prepared-payload execution requests side data has no header commitment")))
      (cond
        ((block-header-block-access-list-hash header)
         (unless block-access-list-present-p
           (block-validation-fail
            "KV prepared-payload record is missing block access list side data"))
         (unless (hash32= (validated-block-access-list-commitment restored)
                          (block-header-block-access-list-hash header))
           (block-validation-fail
            "KV prepared-payload block access list hash mismatch")))
        (block-access-list-present-p
         (block-validation-fail
          "KV prepared-payload block access list side data has no header commitment"))))
    restored))

(defun chain-store-prepared-payload-from-rlp
    (payload-id-identifier record)
  (handler-case
      (let* ((value (rlp-decode-one record))
             (fields (rlp-list-field value "KV prepared-payload record")))
        (unless (member (length fields) '(4 6))
          (block-validation-fail
           "KV prepared-payload record must have exactly 4 or 6 fields"))
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
              (block-record
                (rlp-bytes-field
                 (third fields)
                 "KV prepared-payload block"))
              (blobs-bundle
                (chain-store-blob-sidecar-bundle-from-rlp-object
                 (fourth fields))))
          (unless (bytes= payload-id (ensure-byte-vector payload-id-identifier))
            (block-validation-fail
             "KV prepared-payload record key does not match encoded payload id"))
          (multiple-value-bind
                (block legacy-requests legacy-requests-present-p
                       legacy-encoded-block-access-list
                       legacy-block-access-list-present-p)
              (chain-store-decode-persisted-block-record
               block-record "KV prepared-payload block")
            (let ((requests legacy-requests)
                  (requests-present-p legacy-requests-present-p)
                  (encoded-block-access-list
                    legacy-encoded-block-access-list)
                  (block-access-list-present-p
                    legacy-block-access-list-present-p))
              ;; Explicit private fields are authoritative for the new schema;
              ;; legacy inline values only backfill four-field records.
              (when (= 6 (length fields))
                (multiple-value-setq (requests requests-present-p)
                  (chain-store-prepared-payload-requests-from-rlp-object
                   (fifth fields)))
                (multiple-value-setq (encoded-block-access-list
                                      block-access-list-present-p)
                  (chain-store-prepared-payload-block-access-list-from-rlp-object
                   (sixth fields))))
              (setf block
                    (chain-store-prepared-payload-block-with-side-data
                     block
                     requests requests-present-p
                     encoded-block-access-list
                     block-access-list-present-p))
              (make-engine-prepared-payload
               :payload-id payload-id
               :version version
               :block block
               :blobs-bundle blobs-bundle)))))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV prepared-payload record RLP: ~A" condition))))

(defun chain-store-import-prepared-payload-from-kv
    (store payload-id-identifier record)
  (setf store (chain-store-require-memory-store store))
  (let ((prepared-payload
          (chain-store-prepared-payload-from-rlp
           payload-id-identifier record)))
    (validate-engine-prepared-payload prepared-payload)
    (let* ((block (engine-prepared-payload-block prepared-payload))
           (block-hash (block-hash block))
           (known-block (chain-store-known-block store block-hash)))
      (unless (engine-payload-store-invalid-block store block-hash)
        (when (or (null known-block)
                  (chain-store-persisted-block= known-block block))
          (setf (gethash
                 (engine-payload-id-key
                  (engine-prepared-payload-payload-id prepared-payload))
                 (memory-chain-store-prepared-payloads store))
                prepared-payload))))))

(defun chain-store-import-prepared-payloads-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :prepared-payload))
    (chain-store-import-prepared-payload-from-kv
     store (car entry) (cdr entry))))
