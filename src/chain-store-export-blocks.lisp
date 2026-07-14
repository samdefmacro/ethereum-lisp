(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-block-access-list-side-data (block)
  "Return BLOCK's validated encoded block access list, or NIL when absent."
  (let ((header-commitment
          (block-header-block-access-list-hash (block-header block))))
    (cond
      ((block-block-access-list-present-p block)
       (unless header-commitment
         (block-validation-fail
          "Block access list body has no header commitment"))
       (let ((encoded
               (or (block-encoded-block-access-list block)
                   (ethereum-lisp.block-access-lists:block-access-list-rlp
                    (block-block-access-list block)))))
         (unless (hash32= (validated-block-access-list-commitment block)
                          header-commitment)
           (block-validation-fail
            "Block access list side data does not match its header"))
         encoded))
      (header-commitment
       (block-validation-fail
        "Block access list header commitment has no body"))
      (t nil))))

(defun chain-store-block-record-rlp (block)
  "Encode the durable block record without private block access-list data."
  (block-rlp block))

(defun chain-store-populate-block-access-list-side-data-batch (batch block)
  (let ((side-data (chain-store-block-access-list-side-data block)))
    (when side-data
      (kv-batch-put-chain-record
       batch :block-access-list
       (hash32-bytes (block-hash block))
       side-data)
      t)))

(defun chain-store-block-with-access-list-side-data
    (database identifier block record-label
     &key legacy-encoded-block-access-list
          legacy-block-access-list-present-p)
  "Attach hash-addressed BAL side data to BLOCK and validate its commitment.

Legacy records that still contain an inline BAL remain readable.  A block
without a BAL commitment needs no side-data record."
  (multiple-value-bind (side-data side-data-present-p)
      (kv-get-chain-record database :block-access-list identifier)
    (when (and side-data-present-p legacy-block-access-list-present-p
               (not (bytes= side-data legacy-encoded-block-access-list)))
      (block-validation-fail
       "~A legacy inline block access list conflicts with persisted side data"
       record-label))
    (let ((effective-side-data
            (if side-data-present-p
                side-data
                legacy-encoded-block-access-list))
          (effective-side-data-present-p
            (or side-data-present-p legacy-block-access-list-present-p)))
      (cond
        (effective-side-data-present-p
         (unless (block-header-block-access-list-hash (block-header block))
           (block-validation-fail
            "~A has block access-list side data without a header commitment"
            record-label))
         (when (block-block-access-list-present-p block)
           (unless (bytes= effective-side-data
                           (chain-store-block-access-list-side-data block))
             (block-validation-fail
              "~A inline block access list conflicts with persisted side data"
              record-label)))
         (let* ((access-list
                  (ethereum-lisp.block-access-lists:block-access-list-from-rlp
                   effective-side-data))
                (attached
                  (make-block-from-parts
                   :header (block-header block)
                   :transactions (block-transactions block)
                   :receipts (block-receipts block)
                   :ommers (block-ommers block)
                   :withdrawals (block-withdrawals block)
                   :withdrawals-present-p (block-withdrawals-present-p block)
                   :requests (block-requests block)
                   :requests-present-p (block-requests-present-p block)
                   :block-access-list access-list
                   :block-access-list-present-p t
                   :encoded-block-access-list effective-side-data)))
           (unless (hash32=
                    (validated-block-access-list-commitment attached)
                    (block-header-block-access-list-hash
                     (block-header attached)))
             (block-validation-fail
              "~A block access-list side data does not match its header"
              record-label))
           attached))
        ((block-block-access-list-present-p block)
         ;; Backward compatibility for old records that encoded the BAL inline.
         (chain-store-block-access-list-side-data block)
         block)
        ((block-header-block-access-list-hash (block-header block))
         (block-validation-fail
          "~A is missing block access-list side data" record-label))
        (t block)))))

(defun chain-store-decode-persisted-block-record (record record-label)
  "Decode canonical or legacy private block records.

Returns five values: the canonical block, legacy requests, whether legacy
requests were present, legacy encoded block access-list data, and whether
that BAL was present.  The canonical block is always decoded from only the
standard three or four Ethereum block fields."
  (handler-case
      (let* ((decoded (rlp-decode-one record))
             (items (rlp-list-field decoded record-label))
             (field-count (length items)))
        (unless (member field-count '(3 4 5 6))
          (block-validation-fail
           "~A must contain 3 to 6 fields" record-label))
        (let* ((canonical-field-count (min field-count 4))
               (canonical-record
                 (rlp-encode
                  (apply #'make-rlp-list
                         (subseq items 0 canonical-field-count))))
               (block (block-from-rlp canonical-record))
               (legacy-requests-present-p (> field-count 4))
               (legacy-requests
                 (when legacy-requests-present-p
                   (mapcar
                    #'rlp-encode
                    (rlp-list-field
                     (nth 4 items) (format nil "~A legacy requests"
                                           record-label)))))
               (legacy-block-access-list-present-p (> field-count 5))
               (legacy-encoded-block-access-list
                 (when legacy-block-access-list-present-p
                   (rlp-encode (nth 5 items)))))
          (when legacy-requests-present-p
            (let ((requests-hash
                    (block-header-requests-hash (block-header block))))
              (unless (and requests-hash
                           (hash32=
                            requests-hash
                            (ethereum-lisp.execution-requests:execution-requests-hash
                             legacy-requests)))
                (block-validation-fail
                 "~A legacy requests do not match its header" record-label))))
          (values block
                  legacy-requests
                  legacy-requests-present-p
                  legacy-encoded-block-access-list
                  legacy-block-access-list-present-p)))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid ~A RLP: ~A" record-label condition))))

(defun chain-store-block-from-persisted-record
    (database identifier record record-label)
  (multiple-value-bind
        (block legacy-requests legacy-requests-present-p
               legacy-encoded-block-access-list
               legacy-block-access-list-present-p)
      (chain-store-decode-persisted-block-record record record-label)
    (declare (ignore legacy-requests legacy-requests-present-p))
    (chain-store-block-with-access-list-side-data
     database identifier block record-label
     :legacy-encoded-block-access-list legacy-encoded-block-access-list
     :legacy-block-access-list-present-p
     legacy-block-access-list-present-p)))

(defun chain-store-persisted-block= (left right)
  "Compare durable canonical block data, including private BAL side data."
  (and (hash32= (block-hash left) (block-hash right))
       (bytes= (chain-store-block-record-rlp left)
               (chain-store-block-record-rlp right))
       (let ((left-side-data
               (chain-store-block-access-list-side-data left))
             (right-side-data
               (chain-store-block-access-list-side-data right)))
         (if left-side-data
             (and right-side-data (bytes= left-side-data right-side-data))
             (null right-side-data)))))

(defun node-store-put-immutable-block-body-record
    (database batch kind block record-label)
  "Write a canonical block body and its immutable BAL side record.

An old inline-BAL record for the same block is accepted and migrated to the
canonical body-only representation."
  (let* ((identifier (hash32-bytes (block-hash block)))
         (desired-record (chain-store-block-record-rlp block))
         (side-data (chain-store-block-access-list-side-data block))
         (changed-p nil))
    (multiple-value-bind (existing-record present-p)
        (kv-get-chain-record database kind identifier)
      (cond
        ((not present-p)
         (kv-batch-put-chain-record batch kind identifier desired-record)
         (setf changed-p t))
        ((bytes= existing-record desired-record))
        (t
         (handler-case
             (let ((existing-block
                     (chain-store-block-from-persisted-record
                      database identifier existing-record record-label)))
               (unless (and (hash32= (block-hash existing-block)
                                     (block-hash block))
                            (bytes= (chain-store-block-record-rlp
                                     existing-block)
                                    desired-record)
                            (let ((existing-side-data
                                    (chain-store-block-access-list-side-data
                                     existing-block)))
                              (if side-data
                                  (and existing-side-data
                                       (bytes= existing-side-data side-data))
                                  (null existing-side-data))))
                 (block-validation-fail
                  "~A conflicts with persisted ~A record"
                  record-label kind))
               (kv-batch-put-chain-record batch kind identifier desired-record)
               (setf changed-p t))
           (block-validation-error (condition)
             (error condition))
           (error ()
             (block-validation-fail
              "~A conflicts with persisted ~A record"
              record-label kind))))))
    (when side-data
      (multiple-value-bind (existing-side-data present-p)
          (kv-get-chain-record database :block-access-list identifier)
        (cond
          ((not present-p)
           (kv-batch-put-chain-record
            batch :block-access-list identifier side-data)
           (setf changed-p t))
          ((not (bytes= existing-side-data side-data))
           (block-validation-fail
            "~A conflicts with persisted block access-list side data"
            record-label)))))
    changed-p))

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
    (kv-batch-put-chain-record
     batch :block identifier (chain-store-block-record-rlp block))
    (kv-batch-put-chain-record
     batch :header identifier (block-header-rlp (block-header block)))
    (kv-batch-put-chain-record
     batch :receipt identifier (block-receipts-record-rlp block))
    (chain-store-populate-block-access-list-side-data-batch batch block)))

(defun chain-store-populate-block-record-export-batch (store database batch)
  (declare (ignore database))
  (setf store (chain-store-require-memory-store store))
  (maphash
   (lambda (key block)
     (declare (ignore key))
     (chain-store-export-block-record-to-kv batch block))
   (memory-chain-store-blocks store)))

(defun chain-store-export-block-records-to-kv (store database)
  (chain-store-apply-export-batch
   store database "block record"
   #'chain-store-populate-block-record-export-batch))
