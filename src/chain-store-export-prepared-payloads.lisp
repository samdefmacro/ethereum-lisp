(in-package #:ethereum-lisp.chain-store.persistence)

(defun chain-store-byte-list-rlp-object (values)
  (apply #'make-rlp-list (mapcar #'maybe-copy-bytes values)))

(defun chain-store-blob-sidecar-bundle-rlp-object (bundle)
  (let ((bundle (or bundle (make-blob-sidecar))))
    (make-rlp-list
     (chain-store-byte-list-rlp-object (blob-sidecar-blobs bundle))
     (chain-store-byte-list-rlp-object (blob-sidecar-commitments bundle))
     (chain-store-byte-list-rlp-object (blob-sidecar-proofs bundle)))))

(defun chain-store-prepared-payload-record-rlp (prepared-payload)
  (rlp-encode
   (make-rlp-list
    (maybe-copy-bytes
     (engine-prepared-payload-payload-id prepared-payload))
    (engine-prepared-payload-version prepared-payload)
    (block-rlp (engine-prepared-payload-block prepared-payload))
    (chain-store-blob-sidecar-bundle-rlp-object
     (engine-prepared-payload-blobs-bundle prepared-payload)))))

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
  (let ((current-payload-id-keys (make-hash-table :test 'equal)))
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
