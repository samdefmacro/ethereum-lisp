(in-package #:ethereum-lisp.node-store.persistence)

(defun node-store-payload-candidate-put-record
    (database batch kind identifier value)
  (multiple-value-bind (existing-value present-p)
      (kv-get-chain-record database kind identifier)
    (cond
      ((not present-p)
       (kv-batch-put-chain-record batch kind identifier value)
       t)
      ((bytes= existing-value value)
       nil)
      (t
       (block-validation-fail
        "Payload candidate conflicts with persisted ~A record"
        kind)))))

(defun node-store-payload-candidate-put-block-records
    (database batch block)
  (let ((identifier (hash32-bytes (block-hash block)))
        (changed-p nil))
    (when (node-store-payload-candidate-put-record
           database batch :block identifier (block-rlp block))
      (setf changed-p t))
    (when (node-store-payload-candidate-put-record
           database batch :header identifier
           (block-header-rlp (block-header block)))
      (setf changed-p t))
    (when (node-store-payload-candidate-put-record
           database batch :receipt identifier
           (block-receipts-record-rlp block))
      (setf changed-p t))
    changed-p))

(defun node-store-export-payload-candidate-to-kv
    (store candidate database)
  "Persist CANDIDATE and its ancestry without publishing canonical indexes."
  (let ((chain-store (chain-store-require-memory-store store)))
    (unless (typep candidate 'ethereum-block)
      (block-validation-fail
       "Payload candidate export requires an Ethereum block"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Payload candidate export target must be a key-value database"))
    (let* ((candidate-hash (block-hash candidate))
           (stored-candidate
             (chain-store-known-block chain-store candidate-hash)))
      (unless stored-candidate
        (block-validation-fail
         "Payload candidate export requires a known block"))
      (unless (bytes= (block-rlp stored-candidate) (block-rlp candidate))
        (block-validation-fail
         "Payload candidate does not match the known block"))
      (unless (chain-store-state-available-p chain-store candidate-hash)
        (block-validation-fail
         "Payload candidate export requires available state"))
      (let ((batch (make-kv-write-batch))
            (changed-p nil)
            (current stored-candidate))
        (loop
          (let* ((hash (block-hash current))
                 (header (block-header current))
                 (number (block-header-number header))
                 (identifier (hash32-bytes hash)))
            (when (node-store-payload-candidate-put-block-records
                   database batch current)
              (setf changed-p t))
            (when (chain-store-state-available-p chain-store hash)
              (when (node-store-payload-candidate-put-record
                     database batch :state identifier
                     (chain-store-state-record-rlp chain-store hash))
                (setf changed-p t)))
            (when (or (zerop number)
                      (hash32= (block-header-parent-hash header)
                               (zero-hash32)))
              (return))
            (let* ((parent-hash (block-header-parent-hash header))
                   (parent
                     (chain-store-known-block chain-store parent-hash)))
              (unless parent
                (block-validation-fail
                 "Payload candidate ancestry is incomplete"))
              (unless (= (block-header-number (block-header parent))
                         (1- number))
                (block-validation-fail
                 "Payload candidate ancestry has non-consecutive heights"))
              (setf current parent))))
        (when changed-p
          (kv-apply-batch database batch))
        database))))

(defun node-store-export-forkchoice-to-kv (store database)
  (let ((chain-store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Forkchoice export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-index-export-batch chain-store database batch)
      (chain-store-populate-block-record-export-batch
       chain-store database batch)
      (chain-store-populate-transaction-location-export-batch
       chain-store database batch)
      (chain-store-populate-state-record-export-batch
       chain-store database batch)
      ;; Canonical transitions remove included transactions and may reinsert
      ;; transactions displaced by a reorg. Persist that coupled view in the
      ;; same batch so restart never sees a canonical transaction in txpool.
      (chain-store-populate-txpool-record-export-batch store database batch)
      (kv-apply-batch database batch))))

(defun node-store-export-to-kv (store database)
  (let ((chain-store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Node export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-index-export-batch chain-store database batch)
      (chain-store-populate-block-record-export-batch
       chain-store database batch)
      (chain-store-populate-transaction-location-export-batch
       chain-store database batch)
      (chain-store-populate-state-record-export-batch
       chain-store database batch)
      (chain-store-populate-txpool-record-export-batch store database batch)
      (chain-store-populate-invalid-tipset-export-batch
       chain-store database batch)
      (chain-store-populate-remote-block-export-batch
       chain-store database batch)
      (chain-store-populate-blob-sidecar-export-batch
       chain-store database batch)
      (chain-store-populate-prepared-payload-export-batch
       chain-store database batch)
      (kv-apply-batch database batch))))
