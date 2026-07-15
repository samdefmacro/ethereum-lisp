(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-byte-list-rlp-object (values)
  (apply #'make-rlp-list (mapcar #'maybe-copy-bytes values)))

(defun chain-store-blob-sidecar-bundle-rlp-object (bundle)
  (let ((bundle (or bundle (make-blob-sidecar))))
    (make-rlp-list
     (chain-store-byte-list-rlp-object (blob-sidecar-blobs bundle))
     (chain-store-byte-list-rlp-object (blob-sidecar-commitments bundle))
     (chain-store-byte-list-rlp-object (blob-sidecar-proofs bundle)))))

(defun chain-store-prepared-payload-requests-rlp-object (block)
  (if (block-requests-present-p block)
      (make-rlp-list
       (chain-store-byte-list-rlp-object (block-requests block)))
      (make-rlp-list)))

(defun chain-store-prepared-payload-block-access-list-rlp-object (block)
  (if (block-block-access-list-present-p block)
      (make-rlp-list
       (maybe-copy-bytes
        (or (block-encoded-block-access-list block)
            (ethereum-lisp.block-access-lists:block-access-list-rlp
             (block-block-access-list block)))))
      (make-rlp-list)))

(defun chain-store-prepared-payload-record-rlp (prepared-payload)
  (let ((block (engine-prepared-payload-block prepared-payload)))
    (rlp-encode
     (make-rlp-list
      (maybe-copy-bytes
       (engine-prepared-payload-payload-id prepared-payload))
      (engine-prepared-payload-version prepared-payload)
      (block-rlp block)
      (chain-store-blob-sidecar-bundle-rlp-object
       (engine-prepared-payload-blobs-bundle prepared-payload))
      (chain-store-prepared-payload-requests-rlp-object block)
      (chain-store-prepared-payload-block-access-list-rlp-object block)))))

(defun chain-store-export-prepared-payload-to-kv
    (batch payload-id-key prepared-payload)
  (kv-batch-put-chain-record
   batch
   :prepared-payload
   (hex-to-bytes payload-id-key)
   (chain-store-prepared-payload-record-rlp prepared-payload)))

(defun chain-store-prepared-payload-exportable-p
    (store payload-id-key prepared-payload)
  (let ((payload-id (engine-prepared-payload-payload-id prepared-payload))
        (block-hash
          (block-hash (engine-prepared-payload-block prepared-payload))))
    (and (string= payload-id-key (engine-payload-id-key payload-id))
         (not (chain-store-known-block store block-hash))
         (not (engine-payload-store-invalid-block store block-hash)))))

(defun chain-store-populate-prepared-payload-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  (let ((current-payload-id-keys (make-hash-table :test 'equalp)))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (chain-store-prepared-payload-exportable-p
              store payload-id-key prepared-payload)
         (setf (gethash payload-id-key current-payload-id-keys) t)
         (chain-store-export-prepared-payload-to-kv
          batch payload-id-key prepared-payload)))
     (memory-chain-store-prepared-payloads store))
    (dolist (entry (kv-chain-record-entries database :prepared-payload))
      (unless (gethash (bytes-to-hex (car entry))
                       current-payload-id-keys)
        (kv-batch-delete-chain-record
         batch
         :prepared-payload
         (car entry))))))

(defun chain-store-export-prepared-payloads-to-kv (store database)
  (chain-store-apply-export-batch
   store database "prepared-payload"
   #'chain-store-populate-prepared-payload-export-batch))
