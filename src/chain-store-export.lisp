(in-package #:ethereum-lisp.node-store.persistence)

(defun node-store-put-immutable-record
    (database batch kind identifier value record-label)
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
        "~A conflicts with persisted ~A record"
        record-label kind)))))

(defun node-store-put-immutable-block-records
    (database batch block record-label)
  (let ((identifier (hash32-bytes (block-hash block)))
        (changed-p nil))
    (when (node-store-put-immutable-record
           database batch :block identifier (block-rlp block) record-label)
      (setf changed-p t))
    (when (node-store-put-immutable-record
           database batch :header identifier
           (block-header-rlp (block-header block)) record-label)
      (setf changed-p t))
    (when (node-store-put-immutable-record
           database batch :receipt identifier
           (block-receipts-record-rlp block) record-label)
      (setf changed-p t))
    changed-p))

(defun node-store-sync-chain-record
    (database batch kind identifier desired-value)
  (multiple-value-bind (existing-value present-p)
      (kv-get-chain-record database kind identifier)
    (cond
      ((and desired-value present-p
            (bytes= existing-value desired-value))
       nil)
      (desired-value
       (kv-batch-put-chain-record batch kind identifier desired-value)
       t)
      (present-p
       (kv-batch-delete-chain-record batch kind identifier)
       t)
      (t nil))))

(defun node-store-sync-canonical-hash (database batch store number)
  (let ((desired-hash (chain-store-canonical-hash store number)))
    (multiple-value-bind (existing-hash present-p)
        (kv-get-chain-canonical-hash database number)
      (cond
        ((and desired-hash present-p
              (bytes= existing-hash (hash32-bytes desired-hash)))
         nil)
        (desired-hash
         (kv-batch-put-chain-canonical-hash
          batch number (hash32-bytes desired-hash))
         t)
        (present-p
         (kv-batch-delete-chain-canonical-hash batch number)
         t)
        (t nil)))))

(defun node-store-sync-checkpoint (database batch checkpoint label)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (desired-value (and hash (hash32-bytes hash))))
    (multiple-value-bind (existing-value present-p)
        (kv-get-chain-checkpoint database label)
      (cond
        ((and desired-value present-p
              (bytes= existing-value desired-value))
         nil)
        (desired-value
         (kv-batch-put-chain-checkpoint batch label desired-value)
         t)
        (present-p
         (kv-batch-delete-chain-checkpoint batch label)
         t)
        (t nil)))))

(defun node-store-transition-blocks (transition)
  (append
   (canonical-chain-transition-installed-blocks transition)
   (canonical-chain-transition-displaced-blocks transition)))

(defun node-store-unique-blocks (blocks)
  (let ((blocks-by-hash (make-hash-table :test 'equalp)))
    (dolist (block blocks)
      (unless (typep block 'ethereum-block)
        (block-validation-fail
         "Forkchoice transition contains a non-block entry"))
      (setf (gethash (hash32-to-hex (block-hash block)) blocks-by-hash)
            block))
    (sort
     (loop for block being the hash-values of blocks-by-hash collect block)
     #'<
     :key (lambda (block)
            (block-header-number (block-header block))))))

(defun node-store-database-head-number (database)
  (multiple-value-bind (identifier present-p)
      (kv-get-chain-checkpoint database :head)
    (when present-p
      (let ((head-hash (make-hash32 identifier)))
        (multiple-value-bind (record block-present-p)
            (kv-get-chain-record database :block identifier)
          (unless block-present-p
            (block-validation-fail
             "Persisted head checkpoint has no block record"))
          (let ((block (block-from-rlp record)))
            (unless (hash32= (block-hash block) head-hash)
              (block-validation-fail
               "Persisted head checkpoint block hash does not match"))
            (block-header-number (block-header block))))))))

(defun node-store-database-canonical-block
    (database number identifier)
  (let ((expected-hash (make-hash32 identifier)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :block identifier)
      (unless present-p
        (block-validation-fail
         "Persisted canonical height ~D has no block record" number))
      (let ((block (block-from-rlp record)))
        (unless (and (hash32= (block-hash block) expected-hash)
                     (= (block-header-number (block-header block)) number))
          (block-validation-fail
           "Persisted canonical block does not match height ~D" number))
        block))))

(defun node-store-canonical-difference (store database)
  "Return keyed canonical changes needed to advance DATABASE to STORE.

The walk stops at the first matching canonical ancestor and reads no database
range.  This also covers locally canonicalized blocks that predate a
same-head forkchoice call without reintroducing a full-store scan."
  (let* ((current-head-number (chain-store-head-number store))
         (database-head-number (node-store-database-head-number database))
         (numbers (make-hash-table :test 'eql))
         (blocks nil)
         (persisted-displaced-blocks nil))
    (unless database-head-number
      (block-validation-fail
       "Forkchoice delta export requires a persisted head checkpoint"))
    (loop for number from current-head-number downto 0
          for current-hash = (chain-store-canonical-hash store number)
          do (multiple-value-bind (persisted-hash present-p)
                 (kv-get-chain-canonical-hash database number)
               (when (and current-hash
                          present-p
                          (bytes= persisted-hash
                                  (hash32-bytes current-hash)))
                 (loop-finish))
               (when present-p
                 (push
                  (node-store-database-canonical-block
                   database number persisted-hash)
                  persisted-displaced-blocks))
               (when (or current-hash present-p)
                 (setf (gethash number numbers) t)
                 (when current-hash
                   (let ((block (chain-store-block-by-number store number)))
                     (unless (and block
                                  (hash32= (block-hash block) current-hash))
                       (block-validation-fail
                        "Current canonical block is missing at height ~D"
                        number))
                     (push block blocks))))))
    (when (and database-head-number
               (> database-head-number current-head-number))
      (loop for number from (1+ current-head-number)
              to database-head-number
            do (multiple-value-bind (persisted-hash present-p)
                   (kv-get-chain-canonical-hash database number)
                 (when present-p
                   (push
                    (node-store-database-canonical-block
                     database number persisted-hash)
                    persisted-displaced-blocks)
                   (setf (gethash number numbers) t)))))
    (values
     (sort (loop for number being the hash-keys of numbers collect number)
           #'<)
     (nreverse blocks)
     (nreverse persisted-displaced-blocks))))

(defun node-store-transition-affected-numbers (transition)
  (let ((numbers (make-hash-table :test 'eql)))
    (dolist (block (node-store-transition-blocks transition))
      (unless (typep block 'ethereum-block)
        (block-validation-fail
         "Forkchoice transition contains a non-block entry"))
      (setf (gethash (block-header-number (block-header block)) numbers) t))
    (sort (loop for number being the hash-keys of numbers collect number) #'<)))

(defun node-store-transition-affected-transaction-hashes
    (transition &optional additional-blocks)
  (let ((hashes (make-hash-table :test 'equalp)))
    (dolist (block
             (append (node-store-transition-blocks transition)
                     additional-blocks))
      (dolist (transaction (block-transactions block))
        (let ((hash (transaction-hash transaction)))
          (setf (gethash (hash32-to-hex hash) hashes) hash))))
    (dolist (hash (canonical-chain-transition-changed-txpool-hashes transition))
      (unless (hash32-p hash)
        (block-validation-fail
         "Forkchoice transition contains a non-hash txpool change"))
      (setf (gethash (hash32-to-hex hash) hashes) hash))
    (mapcar
     (lambda (key) (gethash key hashes))
     (sort (loop for key being the hash-keys of hashes collect key) #'string<))))

(defun node-store-final-txpool-record (store transaction-hash)
  (let ((entries nil))
    (flet ((collect-entry (subpool transaction)
             (when transaction
               (push (cons subpool transaction) entries))))
      (collect-entry
       :pending
       (engine-payload-store-pending-transaction store transaction-hash))
      (collect-entry
       :queued
       (engine-payload-store-queued-transaction store transaction-hash))
      (collect-entry
       :basefee
       (engine-payload-store-basefee-transaction store transaction-hash))
      (collect-entry
       :blob
       (engine-payload-store-blob-transaction store transaction-hash)))
    (when (< 1 (length entries))
      (block-validation-fail
       "Forkchoice transition left a transaction in multiple txpool subpools"))
    (when entries
      (chain-store-txpool-transaction-record-rlp
       (caar entries) (cdar entries)))))

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
            (when (node-store-put-immutable-block-records
                   database batch current "Payload candidate")
              (setf changed-p t))
            (when (chain-store-state-available-p chain-store hash)
              (when (node-store-put-immutable-record
                     database batch :state identifier
                     (chain-store-state-record-rlp chain-store hash)
                     "Payload candidate")
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

(defun node-store-export-forkchoice-to-kv (store transition database)
  (let ((chain-store (chain-store-require-memory-store store)))
    (unless (canonical-chain-transition-p transition)
      (block-validation-fail
       "Forkchoice export requires a canonical chain transition"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Forkchoice export target must be a key-value database"))
    (unless (engine-payload-store-txpool-database-change-tracking-enabled-p
             store)
      (block-validation-fail
       "Forkchoice export requires txpool database change tracking"))
    (multiple-value-bind
        (reconciled-numbers reconciled-blocks persisted-displaced-blocks)
        (node-store-canonical-difference chain-store database)
      (let* ((batch (make-kv-write-batch))
             (changed-p nil)
             (installed-blocks
               (node-store-unique-blocks
                (append
                 (canonical-chain-transition-installed-blocks transition)
                 reconciled-blocks)))
             (affected-numbers (make-hash-table :test 'eql))
             (transaction-hashes
               (node-store-transition-affected-transaction-hashes
                transition
                (append reconciled-blocks persisted-displaced-blocks))))
        (dolist (number (node-store-transition-affected-numbers transition))
          (setf (gethash number affected-numbers) t))
        (dolist (number reconciled-numbers)
          (setf (gethash number affected-numbers) t))
        (dolist (number
                 (sort
                  (loop for key being the hash-keys of affected-numbers
                        collect key)
                  #'<))
          (when (node-store-sync-canonical-hash
                 database batch chain-store number)
            (setf changed-p t)))
        (dolist (entry
                 (list
                  (cons :head (chain-store-head-checkpoint chain-store))
                  (cons :safe (chain-store-safe-checkpoint chain-store))
                  (cons :finalized
                        (chain-store-finalized-checkpoint chain-store))))
          (when (node-store-sync-checkpoint
                 database batch (cdr entry) (car entry))
            (setf changed-p t)))
        (dolist (block installed-blocks)
          (let* ((hash (block-hash block))
                 (known-block (chain-store-known-block chain-store hash))
                 (identifier (hash32-bytes hash)))
            (unless (and known-block
                         (bytes= (block-rlp known-block) (block-rlp block))
                         (chain-store-canonical-block-p chain-store block))
              (block-validation-fail
               "Forkchoice transition installed block is not canonical"))
            (when (node-store-put-immutable-block-records
                   database batch block "Forkchoice transition")
              (setf changed-p t))
            (when (chain-store-state-available-p chain-store hash)
              (when (node-store-put-immutable-record
                     database batch :state identifier
                     (chain-store-state-record-rlp chain-store hash)
                     "Forkchoice transition")
                (setf changed-p t)))))
        (dolist (transaction-hash transaction-hashes)
          (let* ((identifier (hash32-bytes transaction-hash))
                 (location
                   (chain-store-transaction-location
                    chain-store transaction-hash))
                 (location-value
                   (and location
                        (chain-store-canonical-block-p
                         chain-store
                         (engine-transaction-location-block location))
                        (transaction-location-record-rlp location))))
            (when (node-store-sync-chain-record
                   database batch :transaction-location identifier
                   location-value)
              (setf changed-p t))
            (when (node-store-sync-chain-record
                   database batch :txpool identifier
                   (node-store-final-txpool-record store transaction-hash))
              (setf changed-p t))))
        (when changed-p
          (kv-apply-batch database batch))
        (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
         store transaction-hashes)
        database))))

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
