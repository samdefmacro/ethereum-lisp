(in-package #:ethereum-lisp.core)

(defun chain-store-export-checkpoint-to-kv (batch checkpoint)
  (let ((label (and checkpoint
                    (chain-store-checkpoint-label checkpoint)))
        (hash (and checkpoint
                   (chain-store-checkpoint-block-hash checkpoint))))
    (when (and label hash)
      (kv-batch-put-chain-checkpoint batch label (hash32-bytes hash)))))

(defun chain-store-checkpoint-labels-with-hashes (store)
  (loop for checkpoint in
          (list (engine-payload-memory-store-head-checkpoint store)
                (engine-payload-memory-store-safe-checkpoint store)
                (engine-payload-memory-store-finalized-checkpoint store))
        for label = (and checkpoint
                         (chain-store-checkpoint-label checkpoint))
        for hash = (and checkpoint
                        (chain-store-checkpoint-block-hash checkpoint))
        when (and label hash)
          collect label))

(defun chain-store-populate-index-export-batch (store database batch)
  (dolist (entry (kv-chain-canonical-hashes database))
    (unless (gethash (car entry)
                     (engine-payload-memory-store-canonical-hashes store))
      (kv-batch-delete-chain-canonical-hash batch (car entry))))
  (let ((checkpoint-labels
          (chain-store-checkpoint-labels-with-hashes store)))
    (dolist (entry (kv-chain-checkpoints database))
      (unless (member (car entry) checkpoint-labels)
        (kv-batch-delete-chain-checkpoint batch (car entry)))))
  (maphash
   (lambda (number key)
     (kv-batch-put-chain-canonical-hash
      batch
      number
      (hash32-bytes (hash32-from-hex key))))
   (engine-payload-memory-store-canonical-hashes store))
  (chain-store-export-checkpoint-to-kv
   batch
   (engine-payload-memory-store-head-checkpoint store))
  (chain-store-export-checkpoint-to-kv
   batch
   (engine-payload-memory-store-safe-checkpoint store))
  (chain-store-export-checkpoint-to-kv
   batch
   (engine-payload-memory-store-finalized-checkpoint store)))

(defun chain-store-export-indexes-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Chain index export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-index-export-batch store database batch)
      (kv-apply-batch database batch))))

(defun block-receipts-record-rlp (block)
  (let ((transactions (block-transactions block))
        (receipts (block-receipts block)))
    (unless (= (length transactions) (length receipts))
      (block-validation-fail
       "Block receipt record requires one receipt per transaction"))
    (rlp-encode
     (apply #'make-rlp-list
            (loop for transaction in transactions
                  for receipt in receipts
                  collect (transaction-receipt-encoding
                           transaction receipt))))))

(defun chain-store-export-block-record-to-kv (batch block)
  (let ((identifier (hash32-bytes (block-hash block))))
    (kv-batch-put-chain-record batch :block identifier (block-rlp block))
    (kv-batch-put-chain-record
     batch :header identifier (block-header-rlp (block-header block)))
    (kv-batch-put-chain-record
     batch :receipt identifier (block-receipts-record-rlp block))))

(defun chain-store-populate-block-record-export-batch (store batch)
  (maphash
   (lambda (key block)
     (declare (ignore key))
     (chain-store-export-block-record-to-kv batch block))
   (engine-payload-memory-store-blocks store)))

(defun chain-store-export-block-records-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain block record export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-block-record-export-batch store batch)
      (kv-apply-batch database batch))))

(defun transaction-location-record-rlp (location)
  (rlp-encode
   (make-rlp-list
    (hash32-bytes
     (block-hash (engine-transaction-location-block location)))
    (engine-transaction-location-index location)
    (engine-transaction-location-log-index-start location))))

(defun chain-store-export-transaction-location-to-kv
    (batch transaction-key location)
  (kv-batch-put-chain-record
   batch
   :transaction-location
   (hash32-bytes (hash32-from-hex transaction-key))
   (transaction-location-record-rlp location)))

(defun chain-store-populate-transaction-location-export-batch
    (store database batch)
  (let ((canonical-transaction-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (transaction-key location)
       (when (engine-payload-store-canonical-block-p
              store
              (engine-transaction-location-block location))
         (setf (gethash transaction-key canonical-transaction-keys) t)
         (chain-store-export-transaction-location-to-kv
          batch
          transaction-key
          location)))
     (engine-payload-memory-store-transaction-locations store))
    (dolist (entry (kv-chain-record-entries database :transaction-location))
      (unless (gethash (bytes-to-hex (car entry)) canonical-transaction-keys)
        (kv-batch-delete-chain-record
         batch
         :transaction-location
         (car entry))))))

(defun chain-store-export-transaction-locations-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain transaction location export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-transaction-location-export-batch
       store database batch)
      (kv-apply-batch database batch))))

(defun state-storage-entry-rlp-object (entry)
  (make-rlp-list
   (hash32-bytes (car entry))
   (cdr entry)))

(defun state-account-snapshot-rlp-object
    (address balance nonce code storage-entries)
  (make-rlp-list
   (address-bytes address)
   balance
   nonce
   code
   (apply #'make-rlp-list
          (mapcar #'state-storage-entry-rlp-object storage-entries))))

(defun chain-store-state-record-rlp (store block-hash)
  (let ((accounts '()))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (push
        (state-account-snapshot-rlp-object
         address balance nonce code storage-entries)
        accounts)))
    (rlp-encode (apply #'make-rlp-list (nreverse accounts)))))

(defun chain-store-export-state-record-to-kv
    (store batch block-key)
  (let ((block-hash (hash32-from-hex block-key)))
    (kv-batch-put-chain-record
     batch
     :state
     (hash32-bytes block-hash)
     (chain-store-state-record-rlp store block-hash))))

(defun chain-store-populate-state-record-export-batch
    (store database batch)
  (dolist (entry (kv-chain-record-entries database :state))
    (unless (gethash (bytes-to-hex (car entry))
                     (engine-payload-memory-store-state-blocks store))
      (kv-batch-delete-chain-record batch :state (car entry))))
  (maphash
   (lambda (block-key state-available-p)
     (when state-available-p
       (chain-store-export-state-record-to-kv store batch block-key)))
   (engine-payload-memory-store-state-blocks store)))

(defun chain-store-export-state-records-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain state record export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-state-record-export-batch store database batch)
      (kv-apply-batch database batch))))

(defparameter +chain-store-txpool-subpool-labels+
  '((:pending . "pending")
    (:queued . "queued")
    (:basefee . "basefee")
    (:blob . "blob")))

(defun chain-store-txpool-subpool-identifier (subpool)
  (let ((name (and (symbolp subpool)
                   (cdr (assoc subpool
                               +chain-store-txpool-subpool-labels+)))))
    (unless name
      (block-validation-fail "Unknown txpool subpool: ~S" subpool))
    name))

(defun chain-store-txpool-subpool-label (identifier)
  (let* ((name (bytes-to-ascii (ensure-byte-vector identifier)))
         (entry (rassoc name +chain-store-txpool-subpool-labels+
                        :test #'string=)))
    (unless entry
      (block-validation-fail "Unknown KV txpool subpool: ~S" name))
    (car entry)))

(defun chain-store-txpool-transaction-record-rlp
    (subpool transaction)
  (rlp-encode
   (make-rlp-list
    (ascii-to-bytes (chain-store-txpool-subpool-identifier subpool))
    (transaction-encoding transaction))))

(defun chain-store-export-txpool-transaction-to-kv
    (batch subpool transaction)
  (kv-batch-put-chain-record
   batch
   :txpool
   (hash32-bytes (transaction-hash transaction))
   (chain-store-txpool-transaction-record-rlp subpool transaction)))

(defun chain-store-populate-txpool-record-export-batch
    (store database batch)
  (let ((current-transaction-keys (make-hash-table :test 'equal)))
    (flet ((export-subpool (subpool transactions)
             (dolist (transaction transactions)
               (let ((key (hash32-to-hex (transaction-hash transaction))))
                 (setf (gethash key current-transaction-keys) t)
                 (chain-store-export-txpool-transaction-to-kv
                  batch subpool transaction)))))
      (export-subpool :pending
                      (engine-payload-store-pending-transactions store))
      (export-subpool :queued
                      (engine-payload-store-queued-transactions store))
      (export-subpool :basefee
                      (engine-payload-store-basefee-transactions store))
      (export-subpool :blob
                      (engine-payload-store-blob-transactions store)))
    (dolist (entry (kv-chain-record-entries database :txpool))
      (unless (gethash (bytes-to-hex (car entry)) current-transaction-keys)
        (kv-batch-delete-chain-record batch :txpool (car entry))))))

(defun chain-store-export-txpool-records-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain txpool export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-txpool-record-export-batch store database batch)
      (kv-apply-batch database batch))))

(defun chain-store-export-invalid-tipset-to-kv
    (batch tipset-key invalid-block)
  (kv-batch-put-chain-record
   batch
   :invalid-tipset
   (hex-to-bytes tipset-key)
   (block-rlp invalid-block)))

(defun chain-store-invalid-tipset-direct-key-p
    (tipset-key invalid-block)
  (string= tipset-key
           (engine-payload-store-key (block-hash invalid-block))))

(defun chain-store-invalid-tipset-exportable-p
    (store tipset-key invalid-block)
  (let ((invalid-hash (block-hash invalid-block)))
    (and (chain-store-invalid-tipset-direct-key-p tipset-key invalid-block)
         (not (chain-store-known-block store invalid-hash)))))

(defun chain-store-populate-invalid-tipset-export-batch
    (store database batch)
  (let ((current-tipset-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (tipset-key invalid-block)
       (when (chain-store-invalid-tipset-exportable-p
              store tipset-key invalid-block)
         (setf (gethash tipset-key current-tipset-keys) t)
         (chain-store-export-invalid-tipset-to-kv
          batch tipset-key invalid-block)))
     (engine-payload-memory-store-invalid-tipsets store))
    (dolist (entry (kv-chain-record-entries database :invalid-tipset))
      (unless (gethash (bytes-to-hex (car entry)) current-tipset-keys)
        (kv-batch-delete-chain-record
         batch
         :invalid-tipset
         (car entry))))))

(defun chain-store-export-invalid-tipsets-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain invalid-tipset export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-invalid-tipset-export-batch
       store database batch)
      (kv-apply-batch database batch))))

(defun chain-store-export-remote-block-to-kv (batch block-key block)
  (kv-batch-put-chain-record
   batch
   :remote-block
   (hex-to-bytes block-key)
   (block-rlp block)))

(defun chain-store-remote-block-exportable-p (store block-key block)
  (let ((block-hash (block-hash block)))
    (and (string= block-key (engine-payload-store-key block-hash))
         (not (chain-store-known-block store block-hash))
         (not (engine-payload-store-invalid-block store block-hash)))))

(defun chain-store-populate-remote-block-export-batch
    (store database batch)
  (let ((current-block-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (block-key block)
       (when (chain-store-remote-block-exportable-p store block-key block)
         (setf (gethash block-key current-block-keys) t)
         (chain-store-export-remote-block-to-kv batch block-key block)))
     (engine-payload-memory-store-remote-blocks store))
    (dolist (entry (kv-chain-record-entries database :remote-block))
      (unless (gethash (bytes-to-hex (car entry)) current-block-keys)
        (kv-batch-delete-chain-record
         batch
         :remote-block
         (car entry))))))

(defun chain-store-export-remote-blocks-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain remote-block export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-remote-block-export-batch store database batch)
      (kv-apply-batch database batch))))

(defun chain-store-blob-sidecar-record-rlp (blob-and-proofs)
  (rlp-encode
   (make-rlp-list
    (engine-blob-and-proofs-blob blob-and-proofs)
    (engine-blob-and-proofs-commitment blob-and-proofs)
    (engine-blob-and-proofs-proof blob-and-proofs)
    (apply #'make-rlp-list
           (engine-blob-and-proofs-cell-proofs blob-and-proofs)))))

(defun chain-store-export-blob-sidecar-to-kv
    (batch versioned-hash-key blob-and-proofs)
  (kv-batch-put-chain-record
   batch
   :blob-sidecar
   (hex-to-bytes versioned-hash-key)
   (chain-store-blob-sidecar-record-rlp blob-and-proofs)))

(defun chain-store-populate-blob-sidecar-export-batch
    (store database batch)
  (let ((current-versioned-hash-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (versioned-hash-key blob-and-proofs)
       (setf (gethash versioned-hash-key current-versioned-hash-keys) t)
       (chain-store-export-blob-sidecar-to-kv
        batch versioned-hash-key blob-and-proofs))
     (engine-payload-memory-store-blob-sidecars store))
    (dolist (entry (kv-chain-record-entries database :blob-sidecar))
      (unless (gethash (bytes-to-hex (car entry))
                       current-versioned-hash-keys)
        (kv-batch-delete-chain-record
         batch
         :blob-sidecar
         (car entry))))))

(defun chain-store-export-blob-sidecars-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain blob-sidecar export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-blob-sidecar-export-batch store database batch)
      (kv-apply-batch database batch))))

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
  (let ((current-payload-id-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (chain-store-prepared-payload-exportable-p
              store payload-id-key prepared-payload)
         (setf (gethash payload-id-key current-payload-id-keys) t)
         (chain-store-export-prepared-payload-to-kv
          batch payload-id-key prepared-payload)))
     (engine-payload-memory-store-prepared-payloads store))
    (dolist (entry (kv-chain-record-entries database :prepared-payload))
      (unless (gethash (bytes-to-hex (car entry))
                       current-payload-id-keys)
        (kv-batch-delete-chain-record
         batch
         :prepared-payload
         (car entry))))))

(defun chain-store-export-prepared-payloads-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain prepared-payload export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-prepared-payload-export-batch
       store database batch)
      (kv-apply-batch database batch))))

(defun chain-store-export-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Chain export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-index-export-batch store database batch)
      (chain-store-populate-block-record-export-batch store batch)
      (chain-store-populate-transaction-location-export-batch
       store database batch)
      (chain-store-populate-state-record-export-batch store database batch)
      (chain-store-populate-txpool-record-export-batch store database batch)
      (chain-store-populate-invalid-tipset-export-batch
       store database batch)
      (chain-store-populate-remote-block-export-batch
       store database batch)
      (chain-store-populate-blob-sidecar-export-batch
       store database batch)
      (chain-store-populate-prepared-payload-export-batch
       store database batch)
      (kv-apply-batch database batch))))
