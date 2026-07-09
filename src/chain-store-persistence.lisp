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

(defun chain-store-clear-readable-tables (store)
  (setf (engine-payload-memory-store-blocks store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-number-blocks store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-transaction-locations store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-balances store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-nonces store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-codes store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-account-storage store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-state-blocks store)
        (make-hash-table :test 'equal)
        (engine-payload-memory-store-head-number store)
        0
        (engine-payload-memory-store-head-checkpoint store)
        (make-chain-store-checkpoint :label :head)
        (engine-payload-memory-store-safe-checkpoint store)
        (make-chain-store-checkpoint :label :safe)
        (engine-payload-memory-store-finalized-checkpoint store)
        (make-chain-store-checkpoint :label :finalized))
  store)

(defun chain-store-publish-readable-tables (store source)
  (setf (engine-payload-memory-store-blocks store)
        (engine-payload-memory-store-blocks source)
        (engine-payload-memory-store-number-blocks store)
        (engine-payload-memory-store-number-blocks source)
        (engine-payload-memory-store-canonical-hashes store)
        (engine-payload-memory-store-canonical-hashes source)
        (engine-payload-memory-store-transaction-locations store)
        (engine-payload-memory-store-transaction-locations source)
        (engine-payload-memory-store-account-balances store)
        (engine-payload-memory-store-account-balances source)
        (engine-payload-memory-store-account-nonces store)
        (engine-payload-memory-store-account-nonces source)
        (engine-payload-memory-store-account-codes store)
        (engine-payload-memory-store-account-codes source)
        (engine-payload-memory-store-account-storage store)
        (engine-payload-memory-store-account-storage source)
        (engine-payload-memory-store-state-blocks store)
        (engine-payload-memory-store-state-blocks source)
        (engine-payload-memory-store-head-number store)
        (engine-payload-memory-store-head-number source)
        (engine-payload-memory-store-head-checkpoint store)
        (engine-payload-memory-store-head-checkpoint source)
        (engine-payload-memory-store-safe-checkpoint store)
        (engine-payload-memory-store-safe-checkpoint source)
        (engine-payload-memory-store-finalized-checkpoint store)
        (engine-payload-memory-store-finalized-checkpoint source)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool source)
        (engine-payload-memory-store-invalid-tipsets store)
        (engine-payload-memory-store-invalid-tipsets source)
        (engine-payload-memory-store-remote-blocks store)
        (engine-payload-memory-store-remote-blocks source)
        (engine-payload-memory-store-blob-sidecars store)
        (engine-payload-memory-store-blob-sidecars source)
        (engine-payload-memory-store-prepared-payloads store)
        (engine-payload-memory-store-prepared-payloads source))
  store)

(defun chain-store-import-block-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :block))
    (let* ((identifier (car entry))
           (block (block-from-rlp (cdr entry)))
           (actual (hash32-bytes (block-hash block))))
      (unless (bytes= identifier actual)
        (block-validation-fail
         "KV block record key does not match encoded block hash"))
      (chain-store-put-block store block)))
  (setf (engine-payload-memory-store-canonical-hashes store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-number-blocks store)
        (make-hash-table :test 'eql)
        (engine-payload-memory-store-transaction-locations store)
        (make-hash-table :test 'equal)))

(defun chain-store-import-header-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :header))
    (let* ((identifier (car entry))
           (hash (make-hash32 identifier))
           (block (chain-store-known-block store hash)))
      (unless block
        (block-validation-fail
         "KV header record references an unknown block"))
      (unless (bytes= (cdr entry)
                      (block-header-rlp (block-header block)))
        (block-validation-fail
         "KV header record does not match block header")))))

(defun chain-store-import-canonical-indexes-from-kv (store database)
  (let ((head-number 0))
    (dolist (entry (kv-chain-canonical-hashes database))
      (let* ((number (car entry))
             (hash (make-hash32 (cdr entry)))
             (key (engine-payload-store-key hash))
             (block (chain-store-known-block store hash)))
        (unless block
          (block-validation-fail
           "KV canonical hash references an unknown block"))
        (setf (gethash number
                       (engine-payload-memory-store-canonical-hashes store))
              key
              (gethash number
                       (engine-payload-memory-store-number-blocks store))
              block)
        (setf head-number (max head-number number))))
    (maphash
     (lambda (number block)
       (let ((header (block-header block)))
         (unless (= number (block-header-number header))
           (block-validation-fail
            "KV canonical height does not match block number"))
         (when (plusp number)
           (let ((parent
                   (chain-store-block-by-number store (1- number))))
             (unless (or (not parent)
                         (hash32=
                          (block-header-parent-hash header)
                          (block-hash parent)))
               (block-validation-fail
                "KV canonical chain is not parent-linked"))))))
     (engine-payload-memory-store-number-blocks store))
    (setf (engine-payload-memory-store-head-number store) head-number)))

(defun chain-store-import-checkpoints-from-kv (store database)
  (let (head-hash safe-hash finalized-hash)
    (dolist (entry (kv-chain-checkpoints database))
      (let ((label (car entry))
            (hash (make-hash32 (cdr entry))))
        (unless (chain-store-known-block store hash)
          (block-validation-fail
           "KV checkpoint references an unknown block"))
        (ecase label
          (:head (setf head-hash hash))
          (:safe (setf safe-hash hash))
          (:finalized (setf finalized-hash hash)))))
    (when (and (or safe-hash finalized-hash) (not head-hash))
      (block-validation-fail
       "KV safe/finalized checkpoint requires a head checkpoint"))
    (when (and head-hash
               (not (engine-payload-store-state-available-p
                     store head-hash)))
      (block-validation-fail "KV head checkpoint state is not available"))
    (when head-hash
      (let* ((head-block (engine-payload-store-known-block store head-hash))
             (head-number (block-header-number (block-header head-block)))
             (canonical-head (chain-store-canonical-hash store head-number)))
        (unless (and canonical-head
                     (hash32= canonical-head head-hash)
                     (= head-number
                        (engine-payload-memory-store-head-number store)))
          (block-validation-fail
           "KV head checkpoint does not match canonical head"))))
    (when (and head-hash safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "KV safe checkpoint is not an ancestor of head"))
    (when (and head-hash finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "KV finalized checkpoint is not an ancestor of head"))
    (let ((safe-block
            (and safe-hash
                 (engine-payload-store-known-block store safe-hash)))
          (finalized-block
            (and finalized-hash
                 (engine-payload-store-known-block store finalized-hash))))
      (when (and safe-block finalized-block
                 (< (block-header-number (block-header safe-block))
                    (block-header-number (block-header finalized-block))))
        (block-validation-fail
         "KV safe checkpoint is older than finalized checkpoint")))
    (setf (engine-payload-memory-store-head-checkpoint store)
          (make-chain-store-checkpoint :label :head :block-hash head-hash)
          (engine-payload-memory-store-safe-checkpoint store)
          (make-chain-store-checkpoint :label :safe :block-hash safe-hash)
          (engine-payload-memory-store-finalized-checkpoint store)
          (make-chain-store-checkpoint
           :label :finalized :block-hash finalized-hash))))

(defun log-entry-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Receipt log entry")))
    (unless (= (length fields) 3)
      (block-validation-fail "Receipt log entry must contain 3 fields"))
    (make-log-entry
     :address (rlp-address-field (first fields) "Receipt log address")
     :topics (mapcar (lambda (topic)
                       (rlp-hash32-field topic "Receipt log topic"))
                     (rlp-list-field (second fields) "Receipt log topics"))
     :data (rlp-bytes-field (third fields) "Receipt log data"))))

(defun receipt-status-from-rlp-field (value)
  (let ((bytes (rlp-bytes-field value "Receipt status")))
    (cond
      ((zerop (length bytes))
       (values nil 0))
      ((and (= (length bytes) 1)
            (= (aref bytes 0) 1))
       (values nil 1))
      ((= (length bytes) 32)
       (values bytes 1))
      (t
       (block-validation-fail
        "Receipt status must be empty, 0x01, or 32-byte post-state")))))

(defun receipt-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Receipt")))
    (unless (= (length fields) 4)
      (block-validation-fail "Receipt must contain 4 fields"))
    (multiple-value-bind (post-state status)
        (receipt-status-from-rlp-field (first fields))
      (let* ((logs (mapcar #'log-entry-from-rlp-object
                           (rlp-list-field (fourth fields)
                                           "Receipt logs")))
             (expected-bloom
               (rlp-sized-bytes-field (third fields) 256 "Receipt bloom"))
             (actual-bloom (bloom-bytes (receipt-bloom logs))))
        (unless (bytes= expected-bloom actual-bloom)
          (block-validation-fail
           "Receipt bloom does not match decoded receipt logs"))
        (make-receipt
         :post-state post-state
         :status status
         :cumulative-gas-used
         (rlp-uint-field (second fields) "Receipt cumulative gas used")
         :logs logs)))))

(defun receipt-from-transaction-encoding (transaction encoded)
  (let ((encoded (ensure-byte-vector encoded))
        (type (transaction-type transaction)))
    (if (zerop type)
        (receipt-from-rlp-object (rlp-decode-one encoded))
        (progn
          (when (< (length encoded) 2)
            (block-validation-fail "Typed receipt encoding is too short"))
          (unless (= type (aref encoded 0))
            (block-validation-fail
             "Typed receipt prefix does not match transaction type"))
          (receipt-from-rlp-object (rlp-decode-one (subseq encoded 1)))))))

(defun block-receipts-from-record (block record)
  (handler-case
      (let* ((transactions (block-transactions block))
             (encoded-receipts
               (rlp-list-field (rlp-decode-one record)
                               "Block receipt record")))
        (unless (= (length transactions) (length encoded-receipts))
          (block-validation-fail
           "KV receipt record count does not match block transactions"))
        (let ((receipts
                (loop for transaction in transactions
                      for encoded in encoded-receipts
                      for receipt = (receipt-from-transaction-encoding
                                     transaction encoded)
                      do (unless (bytes= encoded
                                          (transaction-receipt-encoding
                                           transaction receipt))
                           (block-validation-fail
                            "KV receipt record does not round-trip"))
                      collect receipt)))
          (unless (hash32= (block-header-receipts-root (block-header block))
                           (transaction-receipt-list-root transactions
                                                          receipts))
            (block-validation-fail
             "KV receipt record root does not match block header"))
          receipts))
    (rlp-error (condition)
      (block-validation-fail "Invalid KV receipt record RLP: ~A" condition))))

(defun chain-store-import-receipt-record-from-kv
    (store block-identifier receipt-record)
  (let* ((block-hash (make-hash32 block-identifier))
         (block (chain-store-known-block store block-hash)))
    (unless block
      (block-validation-fail "KV receipt record references an unknown block"))
    (setf (block-receipts block)
          (block-receipts-from-record block receipt-record))))

(defun chain-store-import-receipt-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :receipt))
    (chain-store-import-receipt-record-from-kv
     store (car entry) (cdr entry))))

(defun state-storage-entry-from-rlp-object (value)
  (let ((fields (rlp-list-field value "State storage snapshot entry")))
    (unless (= (length fields) 2)
      (block-validation-fail
       "State storage snapshot entry must contain 2 fields"))
    (cons (rlp-hash32-field (first fields) "State storage snapshot slot")
          (rlp-uint-field (second fields)
                          "State storage snapshot value"))))

(defun state-account-snapshot-from-rlp-object (value)
  (let ((fields (rlp-list-field value "State account snapshot")))
    (unless (= (length fields) 5)
      (block-validation-fail
       "State account snapshot must contain 5 fields"))
    (values
     (rlp-address-field (first fields) "State account snapshot address")
     (rlp-uint-field (second fields) "State account snapshot balance")
     (rlp-uint-field (third fields) "State account snapshot nonce")
     (rlp-bytes-field (fourth fields) "State account snapshot code")
     (mapcar #'state-storage-entry-from-rlp-object
             (rlp-list-field (fifth fields)
                             "State account snapshot storage")))))

(defun chain-store-state-snapshot-storage-root (storage-entries)
  (let ((trie (make-mpt)))
    (dolist (entry storage-entries)
      (mpt-put trie
               (keccak-256 (hash32-bytes (car entry)))
               (rlp-encode (cdr entry))))
    (make-hash32 (mpt-root-hash trie))))

(defun chain-store-state-snapshot-account
    (balance nonce code storage-entries)
  (make-state-account
   :nonce nonce
   :balance balance
   :storage-root (chain-store-state-snapshot-storage-root storage-entries)
   :code-hash (if (plusp (length code))
                  (keccak-256-hash code)
                  +empty-code-hash+)))

(defun chain-store-state-snapshot-root (store block-hash)
  (let ((trie (make-mpt)))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (mpt-put trie
                (keccak-256 (address-bytes address))
                (state-account-rlp
                 (chain-store-state-snapshot-account
                  balance nonce code storage-entries)))))
    (make-hash32 (mpt-root-hash trie))))

(defun chain-store-validate-imported-state-root (store block-hash)
  (let* ((block (chain-store-known-block store block-hash))
         (expected-root
           (and block (block-header-state-root (block-header block)))))
    (when expected-root
      (unless (chain-store-state-available-p store block-hash)
        (block-validation-fail
         "KV state record did not restore an available state snapshot"))
      (unless (hash32= expected-root
                       (chain-store-state-snapshot-root store block-hash))
        (block-validation-fail
         "KV state record root does not match block header")))))

(defun chain-store-import-state-record-from-kv
    (store block-identifier state-record)
  (let ((block-hash (make-hash32 block-identifier)))
    (unless (chain-store-known-block store block-hash)
      (block-validation-fail "KV state record references an unknown block"))
    (handler-case
        (progn
          (setf (gethash (engine-payload-store-key block-hash)
                         (engine-payload-memory-store-state-blocks store))
                t)
          (dolist (account (rlp-list-field (rlp-decode-one state-record)
                                           "State snapshot"))
            (multiple-value-bind (address balance nonce code storage-entries)
                (state-account-snapshot-from-rlp-object account)
              (chain-store-put-account-balance store block-hash address balance)
              (chain-store-put-account-nonce store block-hash address nonce)
              (chain-store-put-account-code store block-hash address code)
              (dolist (entry storage-entries)
                (chain-store-put-account-storage
                 store block-hash address (car entry) (cdr entry)))))
          (chain-store-validate-imported-state-root store block-hash))
      (rlp-error (condition)
        (block-validation-fail
         "Invalid KV state record RLP: ~A" condition)))))

(defun chain-store-import-state-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :state))
    (chain-store-import-state-record-from-kv store (car entry) (cdr entry))))

(defun transaction-location-record-values (record)
  (let ((fields (rlp-list-field (rlp-decode-one record)
                                "Transaction location record")))
    (unless (= (length fields) 3)
      (block-validation-fail
       "Transaction location record must contain 3 fields"))
    (values
     (rlp-hash32-field (first fields) "Transaction location block hash")
     (rlp-uint-field (second fields) "Transaction location index")
     (rlp-uint-field (third fields) "Transaction location log index start"))))

(defun chain-store-expected-log-index-start (receipts index)
  (loop for receipt in receipts
        for receipt-index from 0 below index
        do (unless receipt
             (block-validation-fail
              "KV transaction location references a missing receipt"))
        sum (length (receipt-logs receipt))))

(defun chain-store-import-transaction-location-from-kv
    (store transaction-identifier location-record)
  (let ((transaction-hash (make-hash32 transaction-identifier)))
    (multiple-value-bind (block-hash index log-index-start)
        (transaction-location-record-values location-record)
      (let* ((block (chain-store-known-block store block-hash))
             (transactions (and block (block-transactions block))))
        (unless block
          (block-validation-fail
           "KV transaction location references an unknown block"))
        (unless (engine-payload-store-canonical-block-p store block)
          (block-validation-fail
           "KV transaction location references a non-canonical block"))
        (unless (< index (length transactions))
          (block-validation-fail
           "KV transaction location index is outside the block body"))
        (let* ((receipts (block-receipts block))
               (transaction (nth index transactions))
               (receipt (nth index receipts)))
          (unless (hash32= transaction-hash (transaction-hash transaction))
            (block-validation-fail
             "KV transaction location key does not match block transaction"))
          (unless receipt
            (block-validation-fail
             "KV transaction location references a missing receipt"))
          (unless (= log-index-start
                     (chain-store-expected-log-index-start receipts index))
            (block-validation-fail
             "KV transaction location log index is inconsistent"))
          (setf (gethash (hash32-to-hex transaction-hash)
                         (engine-payload-memory-store-transaction-locations
                          store))
                (make-engine-transaction-location
                 :block block
                 :index index
                 :transaction transaction
                 :receipt receipt
                 :log-index-start log-index-start)))))))

(defun chain-store-import-transaction-locations-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :transaction-location))
    (chain-store-import-transaction-location-from-kv
     store (car entry) (cdr entry))))

(defun chain-store-txpool-transaction-record-values (record)
  (handler-case
      (let ((fields (rlp-list-field (rlp-decode-one record)
                                    "Txpool transaction record")))
        (unless (= (length fields) 2)
          (block-validation-fail
           "Txpool transaction record must contain 2 fields"))
        (let* ((subpool
                 (chain-store-txpool-subpool-label
                  (rlp-bytes-field (first fields)
                                   "Txpool transaction subpool")))
               (encoded
                 (rlp-bytes-field (second fields)
                                  "Txpool transaction encoding"))
               (transaction (transaction-from-encoding encoded)))
          (unless (bytes= encoded (transaction-encoding transaction))
            (block-validation-fail
             "Txpool transaction record does not round-trip"))
          (values subpool transaction)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV txpool transaction record RLP: ~A" condition))))

(defun chain-store-import-txpool-transaction-conflict-p
    (txpool transaction)
  (or (engine-pending-txpool-pending-conflict txpool transaction)
      (engine-pending-txpool-queued-conflict txpool transaction)
      (engine-pending-txpool-basefee-conflict txpool transaction)
      (engine-pending-txpool-blob-conflict txpool transaction)))

(defun chain-store-import-txpool-transaction-to-subpool
    (txpool subpool transaction)
  (ecase subpool
    (:pending
     (engine-pending-txpool-put-pending-transaction txpool transaction))
    (:queued
     (engine-pending-txpool-put-queued-transaction txpool transaction))
    (:basefee
     (engine-pending-txpool-put-basefee-transaction txpool transaction))
    (:blob
     (engine-pending-txpool-put-blob-transaction txpool transaction))))

(defun chain-store-import-txpool-transaction-rules
    (store transaction chain-config)
  (when chain-config
    (let* ((head (chain-store-latest-block store))
           (header (and head (block-header head)))
           (number (if header (block-header-number header) 0))
           (timestamp (if header (block-header-timestamp header) 0)))
      (validate-transaction-type-for-config
       transaction chain-config number timestamp))))

(defun chain-store-import-txpool-subpool-compatible-p
    (subpool transaction)
  (cond
    ((eq subpool :blob)
     (unless (typep transaction 'blob-transaction)
       (block-validation-fail
        "KV txpool blob subpool record must contain a blob transaction")))
    ((typep transaction 'blob-transaction)
     (block-validation-fail
      "KV txpool blob transaction must restore to the blob subpool")))
  t)

(defun chain-store-import-txpool-transaction-static-fields (transaction)
  (validate-transaction-data-field transaction)
  (validate-transaction-recipient-field transaction)
  (validate-transaction-scalar-fields transaction)
  (validate-transaction-signature-fields transaction)
  (validate-access-list-fields transaction)
  (validate-set-code-transaction-fields transaction)
  (validate-set-code-authorization-signatures transaction)
  (when (typep transaction 'blob-transaction)
    (validate-blob-transaction-fields transaction))
  t)

(defun chain-store-import-txpool-transaction-from-kv
    (store transaction-identifier record &key expected-chain-id chain-config)
  (let ((transaction-hash (make-hash32 transaction-identifier))
        (txpool (engine-payload-store-txpool store)))
    (multiple-value-bind (subpool transaction)
        (chain-store-txpool-transaction-record-values record)
      (unless (hash32= transaction-hash (transaction-hash transaction))
        (block-validation-fail
         "KV txpool record key does not match encoded transaction hash"))
      (chain-store-import-txpool-transaction-static-fields transaction)
      (unless (transaction-sender transaction
                                  :expected-chain-id expected-chain-id)
        (block-validation-fail
         "KV txpool record sender recovery failed"))
      (chain-store-import-txpool-subpool-compatible-p subpool transaction)
      (chain-store-import-txpool-transaction-rules
       store transaction chain-config)
      (engine-payload-store-validate-txpool-blob-fee-cap
       store
       transaction
       :chain-config chain-config
       :label "KV txpool record")
      (when (chain-store-transaction-location store transaction-hash)
        (block-validation-fail
         "KV txpool record duplicates an indexed transaction"))
      (when (engine-payload-store-pooled-transaction store transaction-hash)
        (block-validation-fail
         "KV txpool record duplicates a pooled transaction hash"))
      (when (chain-store-import-txpool-transaction-conflict-p
             txpool transaction)
        (block-validation-fail
         "KV txpool record duplicates a sender nonce"))
      (chain-store-import-txpool-transaction-to-subpool
       txpool subpool transaction))))

(defun chain-store-import-txpool-records-from-kv
    (store database &key expected-chain-id chain-config)
  (dolist (entry (kv-chain-record-entries database :txpool))
    (chain-store-import-txpool-transaction-from-kv
     store
     (car entry)
     (cdr entry)
     :expected-chain-id expected-chain-id
     :chain-config chain-config)))

(defun chain-store-restore-txpool-consistency
    (store &key expected-chain-id chain-config)
  (let ((head (chain-store-latest-block store)))
    (when head
      (engine-payload-store-remove-new-head-invalid-txpool-transactions
       store
       :expected-chain-id expected-chain-id
       :chain-config chain-config)
      (when (chain-store-state-available-p store (block-hash head))
        (engine-payload-store-revalidate-pending-transactions
         store
         :expected-chain-id expected-chain-id)
        (engine-payload-store-promote-queued-transactions
         store
         nil
         :expected-chain-id expected-chain-id)
        (engine-payload-store-promote-basefee-and-queued-transactions
         store
         :expected-chain-id expected-chain-id)
        (engine-payload-store-prune-overbudget-parked-transactions store))))
  store)

(defun chain-store-import-invalid-tipset-from-kv
    (store tipset-identifier record)
  (handler-case
      (let ((tipset-hash (make-hash32 tipset-identifier))
            (invalid-block (block-from-rlp record)))
        (unless (hash32= tipset-hash (block-hash invalid-block))
          (block-validation-fail
           "KV invalid-tipset record key does not match encoded block hash"))
        (when (chain-store-known-block store tipset-hash)
          (block-validation-fail
           "KV invalid-tipset record duplicates a known block"))
        (setf (gethash
               (engine-payload-store-key tipset-hash)
               (engine-payload-memory-store-invalid-tipsets store))
              invalid-block))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV invalid-tipset record RLP: ~A" condition))))

(defun chain-store-import-invalid-tipsets-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :invalid-tipset))
    (chain-store-import-invalid-tipset-from-kv
     store (car entry) (cdr entry))))

(defun chain-store-import-remote-block-from-kv
    (store block-identifier record)
  (handler-case
      (let* ((block-hash (make-hash32 block-identifier))
             (block (block-from-rlp record)))
        (unless (hash32= block-hash (block-hash block))
          (block-validation-fail
           "KV remote-block record key does not match encoded block hash"))
        (unless (or (chain-store-known-block store block-hash)
                    (engine-payload-store-invalid-block store block-hash))
          (setf (gethash
                 (engine-payload-store-key block-hash)
                 (engine-payload-memory-store-remote-blocks store))
                block)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV remote-block record RLP: ~A" condition))))

(defun chain-store-import-remote-blocks-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :remote-block))
    (chain-store-import-remote-block-from-kv
     store (car entry) (cdr entry))))

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
           (engine-payload-memory-store-blob-sidecars store))
          blob-and-proofs)))

(defun chain-store-import-blob-sidecars-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :blob-sidecar))
    (chain-store-import-blob-sidecar-from-kv
     store (car entry) (cdr entry))))

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

(defun chain-store-import-from-kv
    (store database &key expected-chain-id chain-config)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Chain import source must be a key-value database"))
    (let ((staging (make-engine-payload-memory-store)))
      (chain-store-import-block-records-from-kv staging database)
      (chain-store-import-header-records-from-kv staging database)
      (chain-store-import-canonical-indexes-from-kv staging database)
      (chain-store-import-receipt-records-from-kv staging database)
      (chain-store-import-state-records-from-kv staging database)
      (chain-store-import-checkpoints-from-kv staging database)
      (chain-store-import-transaction-locations-from-kv staging database)
      (chain-store-import-txpool-records-from-kv
       staging
       database
       :expected-chain-id expected-chain-id
       :chain-config chain-config)
      (chain-store-import-invalid-tipsets-from-kv staging database)
      (chain-store-import-remote-blocks-from-kv staging database)
      (chain-store-import-blob-sidecars-from-kv staging database)
      (chain-store-import-prepared-payloads-from-kv staging database)
      (chain-store-restore-txpool-consistency
       staging
       :expected-chain-id expected-chain-id
       :chain-config chain-config)
      (chain-store-publish-readable-tables store staging))
    store))
