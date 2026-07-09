(in-package #:ethereum-lisp.core)

(defun engine-payload-store-canonical-parent-p (store block)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (parent-block
           (and parent-hash
                (engine-payload-store-known-block store parent-hash))))
    (or (zerop number)
        (null parent-hash)
        (hash32= parent-hash (zero-hash32))
        (null parent-block)
        (/= (block-header-number (block-header parent-block))
            (1- number))
        (let ((parent-key
                (gethash (1- number)
                         (engine-payload-memory-store-canonical-hashes
                          store))))
          (and parent-key
               (string= parent-key
                        (engine-payload-store-key parent-hash)))))))

(defun engine-payload-store-put-transaction-location
    (store block index transaction receipt log-index-start &key force)
  (let* ((transaction-key
           (engine-payload-store-key (transaction-hash transaction)))
         (locations
           (engine-payload-memory-store-transaction-locations store))
         (existing-location (gethash transaction-key locations))
         (existing-canonical-p
           (and existing-location
                (engine-payload-store-canonical-block-p
                 store
                 (engine-transaction-location-block existing-location)))))
    (when (or force
              (null existing-location)
              (engine-payload-store-canonical-block-p store block)
              (not existing-canonical-p))
      (setf (gethash transaction-key locations)
            (make-engine-transaction-location
             :block block
             :index index
             :transaction transaction
             :receipt receipt
             :log-index-start log-index-start)))))

(defun engine-payload-store-index-block-transactions
    (store block &key force)
  (loop with receipts = (block-receipts block)
        with log-index-start = 0
        for transaction in (block-transactions block)
        for index from 0
        for receipt = (nth index receipts)
        do (progn
             (engine-payload-store-put-transaction-location
              store
              block
              index
              transaction
              receipt
              log-index-start
              :force force)
             (when receipt
               (incf log-index-start
                     (length (receipt-logs receipt)))))))

(defun engine-payload-store-remove-block-transaction-locations (store block)
  (let ((locations
          (engine-payload-memory-store-transaction-locations store)))
    (dolist (transaction (block-transactions block))
      (let* ((transaction-key
               (engine-payload-store-key (transaction-hash transaction)))
             (location (gethash transaction-key locations)))
        (when (and location
                   (hash32= (block-hash block)
                             (block-hash
                              (engine-transaction-location-block location))))
          (remhash transaction-key locations)))))
  block)

(defun engine-payload-store-remove-included-block-transactions (store block)
  (dolist (transaction (block-transactions block))
    (engine-payload-store-remove-included-transaction store transaction))
  block)

(defun engine-payload-store-transaction-basefee-ineligible-p
    (store transaction)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header
                        (block-header-base-fee-per-gas header))))
    (and base-fee
         (< (transaction-max-fee-per-gas transaction) base-fee))))

(defun engine-payload-store-current-blob-base-fee
    (store &optional chain-config)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (if chain-config
          (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
              (chain-config-blob-schedule
               chain-config
               (block-header-number header)
               (block-header-timestamp header))
            (declare (ignore target-blob-gas max-blob-gas))
            (block-header-blob-base-fee
             header
             :update-fraction update-fraction))
          (block-header-blob-base-fee header)))))

(defun engine-payload-store-validate-txpool-blob-fee-cap
    (store transaction &key chain-config label)
  (when (typep transaction 'blob-transaction)
    (let ((blob-base-fee
            (engine-payload-store-current-blob-base-fee
             store
             chain-config)))
      (when blob-base-fee
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (block-validation-fail
             "~@[~A: ~]Max fee per blob gas below blob base fee"
             label))))))
  t)

(defun engine-payload-store-sender-code-admissible-p
    (store head sender)
  (or (null head)
      (not (chain-store-state-available-p store (block-hash head)))
      (let ((code (chain-store-account-code store (block-hash head) sender)))
        (or (zerop (length code))
            (set-code-delegation-target code)))))

(defun engine-payload-store-transaction-admission-funded-p
    (store sender transaction)
  (let ((head (chain-store-latest-block store)))
    (or (null head)
        (not (chain-store-state-available-p store (block-hash head)))
        (>= (chain-store-account-balance store (block-hash head) sender)
            (engine-payload-store-sender-admission-expenditure
             store
             sender
             transaction)))))

(defun engine-payload-store-reinsert-displaced-transaction
    (store transaction &key expected-chain-id chain-config)
  (let* ((hash (transaction-hash transaction))
         (head (chain-store-latest-block store))
         (sender (transaction-sender transaction
                                     :expected-chain-id expected-chain-id)))
    (when (and sender
               (not (chain-store-transaction-location store hash))
               (not (engine-payload-store-pooled-transaction store hash))
               (not (engine-payload-store-txpool-conflict-p
                     store transaction))
               (or (null head)
                   (not (engine-payload-store-over-gas-limit-txpool-transaction-p
                         head transaction)))
               (handler-case
                   (engine-payload-store-validate-txpool-blob-fee-cap
                    store
                    transaction
                    :chain-config chain-config)
                 (block-validation-error () nil))
               (engine-payload-store-sender-code-admissible-p
                store head sender)
               (engine-payload-store-transaction-admission-funded-p
                store sender transaction))
      (cond
        ((typep transaction 'blob-transaction)
         (engine-payload-store-put-blob-transaction store transaction))
        ((engine-payload-store-transaction-basefee-ineligible-p
          store transaction)
         (engine-payload-store-put-basefee-transaction store transaction))
        ((not (engine-payload-store-transaction-executable-nonce-p
               store transaction
               :expected-chain-id expected-chain-id))
         (engine-payload-store-put-queued-transaction store transaction))
        (t
         (engine-payload-store-put-pending-transaction store transaction))))))

(defun engine-payload-store-reinsert-displaced-block-transactions
    (store blocks &key expected-chain-id chain-config)
  (let ((seen-transactions (make-hash-table :test 'equal))
        (reinserted-transactions nil))
    (dolist (block (sort (copy-list blocks)
                         #'<
                         :key (lambda (block)
                                (block-header-number
                                 (block-header block)))))
      (dolist (transaction (block-transactions block))
        (let ((key (engine-payload-store-key
                    (transaction-hash transaction))))
          (unless (gethash key seen-transactions)
            (setf (gethash key seen-transactions) t)
            (when (engine-payload-store-reinsert-displaced-transaction
                   store transaction
                   :expected-chain-id expected-chain-id
                   :chain-config chain-config)
              (push transaction reinserted-transactions))))))
    (nreverse reinserted-transactions)))

(defun engine-payload-store-notify-block-filters (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Block filter notification block must be a block"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (typep filter 'engine-block-filter)
          do (engine-block-filter-record-hash filter (block-hash block))))

(defun engine-log-filter-record-change (filter block &key removed-p)
  (unless (typep filter 'engine-log-filter)
    (block-validation-fail "Log filter must be a log filter"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Log filter change block must be a block"))
  (setf (engine-log-filter-pending-changes filter)
        (append
         (engine-log-filter-pending-changes filter)
         (list (make-engine-log-filter-change
                :block block
                :removed-p (not (null removed-p))))))
  filter)

(defun engine-payload-store-notify-log-filters
    (store block &key removed-p)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (and (typep filter 'engine-log-filter)
                  (not (genesis-object-field-present-p
                        (engine-log-filter-criteria filter)
                        "blockHash")))
          do (engine-log-filter-record-change
              filter
              block
              :removed-p removed-p)))

(defun engine-payload-store-put-block
    (store block &key (state-available-p nil))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine payload store block must be a block"))
  (let ((txpool (engine-payload-store-txpool store)))
    (unless (engine-pending-txpool-empty-p txpool)
      (dolist (transaction (block-transactions block))
        (engine-pending-txpool-sender transaction))))
  (let ((stored-block (engine-payload-store-copy-block block))
        (key (engine-payload-store-key (block-hash block)))
        (canonicalized-p nil)
        (notify-head-p nil))
    (remhash key (engine-payload-memory-store-remote-blocks store))
    (setf (gethash key (engine-payload-memory-store-blocks store))
          stored-block)
    (engine-payload-store-prune-prepared-payloads-for-block store key)
    (let ((number (block-header-number (block-header stored-block))))
      (when (and (integerp number) (not (minusp number)))
        (setf (gethash number
                       (engine-payload-memory-store-number-blocks store))
              stored-block)
        (when (and (not (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store)))
                   (engine-payload-store-canonical-parent-p store stored-block))
          (setf (gethash number
                         (engine-payload-memory-store-canonical-hashes store))
                key
                canonicalized-p t))
        (when (and canonicalized-p
                   (> number (engine-payload-memory-store-head-number store)))
          (setf notify-head-p t)
          (setf (engine-payload-memory-store-head-number store) number))))
    (loop with receipts = (block-receipts stored-block)
          with log-index-start = 0
          for transaction in (block-transactions stored-block)
          for index from 0
          for receipt = (nth index receipts)
          do (progn
               (engine-payload-store-put-transaction-location
                store
                stored-block
                index
                transaction
                receipt
                log-index-start)
               (when receipt
                 (incf log-index-start
                       (length (receipt-logs receipt))))))
    (when (engine-payload-store-canonical-block-p store stored-block)
      (engine-payload-store-remove-included-block-transactions store stored-block))
    (if state-available-p
        (setf (gethash key
                       (engine-payload-memory-store-state-blocks store))
              t)
        (remhash key (engine-payload-memory-store-state-blocks store)))
    (when notify-head-p
      (engine-payload-store-notify-block-filters store stored-block))
    block))

(defun engine-payload-store-known-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-blocks store)))

(defun engine-payload-store-checkpoint-number
    (store checkpoint &key label fallback-to-head-p)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (block (and hash (engine-payload-store-known-block store hash))))
    (cond
      (block
       (block-header-number (block-header block)))
      (fallback-to-head-p
       (engine-payload-memory-store-head-number store))
      (t
       (block-validation-fail "~A block not found" label)))))

(defun engine-payload-store-head-number (store)
  (engine-payload-store-checkpoint-number
   store
   (engine-payload-memory-store-head-checkpoint store)
   :label "head"
   :fallback-to-head-p t))

(defun engine-payload-store-block-tag-number (store tag)
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (engine-payload-store-head-number store))
    ((string= tag "safe")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-safe-checkpoint store)
      :label "safe"))
    ((string= tag "finalized")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-finalized-checkpoint store)
      :label "finalized"))))

(defun engine-payload-store-forkchoice-checkpoint-hash (hash)
  (unless (hash32= hash (zero-hash32))
    hash))

(defun engine-payload-store-update-forkchoice-checkpoints (store state)
  (let* ((head-hash (forkchoice-state-head-block-hash state))
         (head-block (engine-payload-store-known-block store head-hash))
         (safe-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-safe-block-hash state)))
         (finalized-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-finalized-block-hash state))))
    (unless head-block
      (block-validation-fail "forkchoice head block is not available"))
    (unless (engine-payload-store-state-available-p store head-hash)
      (block-validation-fail "forkchoice head block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-known-block store safe-hash)))
      (block-validation-fail "forkchoice safe block is not available"))
    (when (and safe-hash
               (not (engine-payload-store-state-available-p
                     store safe-hash)))
      (block-validation-fail "forkchoice safe block state is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-known-block store finalized-hash)))
      (block-validation-fail "forkchoice finalized block is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-state-available-p
                     store finalized-hash)))
      (block-validation-fail
       "forkchoice finalized block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "forkchoice safe block is not an ancestor of head"))
    (when (and finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "forkchoice finalized block is not an ancestor of head"))
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
         "forkchoice safe block is older than finalized block"))))
  (setf (engine-payload-memory-store-head-checkpoint store)
        (make-chain-store-checkpoint
         :label :head
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-head-block-hash state)))
        (engine-payload-memory-store-safe-checkpoint store)
        (make-chain-store-checkpoint
         :label :safe
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-safe-block-hash state)))
        (engine-payload-memory-store-finalized-checkpoint store)
        (make-chain-store-checkpoint
         :label :finalized
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-finalized-block-hash state))))
  store)

(defun engine-payload-store-block-by-number (store number)
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail "Engine payload store block number must be non-negative"))
  (let ((canonical-key
          (gethash number
                   (engine-payload-memory-store-canonical-hashes store))))
    (when canonical-key
      (gethash canonical-key
               (engine-payload-memory-store-blocks store)))))

(defun engine-payload-store-canonical-hash (store number)
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail
     "Engine payload store canonical block number must be non-negative"))
  (let ((canonical-key
          (gethash number
                   (engine-payload-memory-store-canonical-hashes store))))
    (when canonical-key
      (hash32-from-hex canonical-key))))

(defun engine-payload-store-canonical-block-p (store block)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (canonical-key
           (and (integerp number)
                (not (minusp number))
                (gethash number
                         (engine-payload-memory-store-canonical-hashes
                          store)))))
    (and canonical-key
         (string= canonical-key
                  (engine-payload-store-key (block-hash block))))))

(defun engine-payload-store-ancestor-p (store ancestor-hash head-hash)
  (cond
    ((hash32= ancestor-hash head-hash) t)
    ((or (hash32= ancestor-hash (zero-hash32))
         (hash32= head-hash (zero-hash32)))
     nil)
    (t
     (let ((ancestor-block
             (engine-payload-store-known-block store ancestor-hash))
           (current
             (engine-payload-store-known-block store head-hash)))
       (when (and ancestor-block current)
         (let ((ancestor-number
                 (block-header-number (block-header ancestor-block))))
           (loop
             (let* ((header (block-header current))
                    (number (block-header-number header)))
               (cond
                 ((< number ancestor-number)
                  (return nil))
                 ((and (= number ancestor-number)
                       (hash32= (block-hash current) ancestor-hash))
                  (return t))
                 ((zerop number)
                  (return nil))
                 (t
                  (let* ((parent-hash (block-header-parent-hash header))
                         (parent-block
                           (and parent-hash
                                (engine-payload-store-known-block
                                 store parent-hash))))
                    (unless parent-block
                      (return nil))
                    (setf current parent-block))))))))))))

(defun engine-payload-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let* ((head-block (engine-payload-store-known-block store hash))
         (previous-head-hash
           (engine-payload-store-canonical-hash
            store
            (engine-payload-memory-store-head-number store)))
         (head-changed-p
           (or (null previous-head-hash)
               (not (hash32= previous-head-hash hash)))))
    (unless head-block
      (block-validation-fail "Canonical head block must be known"))
    (let ((path '()))
      (loop with current = head-block
            do (let* ((header (block-header current))
                      (number (block-header-number header))
                      (current-hash (block-hash current))
                      (current-key (engine-payload-store-key current-hash))
                      (canonical-key
                        (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store))))
                 (when (and canonical-key
                            (string= canonical-key current-key))
                   (return))
                 (push current path)
                 (when (zerop number)
                   (return))
                 (let* ((parent-hash (block-header-parent-hash header))
                        (parent-block
                          (and parent-hash
                               (engine-payload-store-known-block
                                store parent-hash))))
                   (when (or (null parent-hash)
                             (hash32= parent-hash (zero-hash32)))
                     (return))
                   (unless parent-block
                     (block-validation-fail
                      "Canonical head ancestry must be fully known"))
                   (setf current parent-block))))
      (let ((displaced-blocks '()))
        (dolist (block path)
          (let* ((header (block-header block))
                 (number (block-header-number header))
                 (old-block (engine-payload-store-block-by-number
                             store number)))
            (when (and old-block
                       (not (hash32= (block-hash old-block)
                                     (block-hash block))))
              (push old-block displaced-blocks))))
        (dolist (block path)
          (let* ((header (block-header block))
                 (number (block-header-number header))
                 (key (engine-payload-store-key (block-hash block))))
            (setf (gethash number
                           (engine-payload-memory-store-canonical-hashes store))
                  key
                  (gethash number
                           (engine-payload-memory-store-number-blocks store))
                  block)
            (engine-payload-store-index-block-transactions
             store
             block
             :force t)
            (engine-payload-store-remove-included-block-transactions
             store
             block)))
        (let ((new-head-number
                (block-header-number (block-header head-block)))
              (stale-numbers '()))
          (maphash (lambda (number key)
                     (declare (ignore key))
                     (when (> number new-head-number)
                       (let ((old-block
                               (engine-payload-store-block-by-number
                                store number)))
                         (when old-block
                           (push old-block displaced-blocks)))
                       (push number stale-numbers)))
                   (engine-payload-memory-store-canonical-hashes store))
          (dolist (number stale-numbers)
            (remhash number
                     (engine-payload-memory-store-canonical-hashes store)))
          (setf (engine-payload-memory-store-head-number store) new-head-number
                (engine-payload-memory-store-head-checkpoint store)
                (make-chain-store-checkpoint :label :head :block-hash hash)))
        (engine-payload-store-remove-new-head-invalid-txpool-transactions
         store
         :chain-config chain-config)
        (dolist (block displaced-blocks)
          (engine-payload-store-remove-block-transaction-locations
           store
           block))
        (engine-payload-store-reinsert-displaced-block-transactions
         store
         displaced-blocks
         :expected-chain-id expected-chain-id
         :chain-config chain-config)
        (when head-changed-p
          (dolist (block (sort (copy-list displaced-blocks)
                               #'<
                               :key (lambda (block)
                                      (block-header-number
                                       (block-header block)))))
            (engine-payload-store-notify-log-filters
             store
             block
             :removed-p t))
          (dolist (block (sort (copy-list path)
                               #'<
                               :key (lambda (block)
                                      (block-header-number
                                       (block-header block)))))
            (engine-payload-store-notify-log-filters store block))))
      (engine-payload-store-remove-new-head-invalid-txpool-transactions
       store
       :chain-config chain-config)
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
      (when head-changed-p
        (engine-payload-store-notify-block-filters store head-block))
      head-block)))

(defun engine-payload-store-transaction-location (store hash)
  (let ((location
          (gethash (engine-payload-store-key hash)
                   (engine-payload-memory-store-transaction-locations
                    store))))
    (when (and location
               (engine-payload-store-canonical-block-p
                store
                (engine-transaction-location-block location)))
      (engine-payload-store-copy-transaction-location location))))

(defun chain-store-require-memory-store (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Chain store must be an engine payload memory store"))
  store)

(defun engine-payload-store-copy-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-payload-store-copy-filter (filter)
  (cond
    ((typep filter 'engine-log-filter)
     (make-engine-log-filter
      :criteria (copy-tree (engine-log-filter-criteria filter))
      :last-block-number (engine-log-filter-last-block-number filter)
      :pending-changes
      (copy-list (engine-log-filter-pending-changes filter))
      :block-hash-consumed-p
      (engine-log-filter-block-hash-consumed-p filter)))
    ((typep filter 'engine-block-filter)
     (make-engine-block-filter
      :last-block-number (engine-block-filter-last-block-number filter)
      :hashes (copy-list (engine-block-filter-hashes filter))))
    ((typep filter 'engine-pending-transaction-filter)
     (make-engine-pending-transaction-filter
      :hashes (copy-list
               (engine-pending-transaction-filter-hashes filter))))
    (t filter)))

(defun engine-payload-store-copy-filter-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-filter value)))
             table)
    copy))

(defun engine-payload-store-copy-prepared-payload (prepared-payload)
  (cond
    ((typep prepared-payload 'engine-prepared-payload)
     (make-engine-prepared-payload
      :payload-id (maybe-copy-bytes
                   (engine-prepared-payload-payload-id prepared-payload))
      :version (engine-prepared-payload-version prepared-payload)
      :block
      (engine-payload-store-copy-block
       (engine-prepared-payload-block prepared-payload))
      :blobs-bundle
      (maybe-copy-blob-sidecar
       (engine-prepared-payload-blobs-bundle prepared-payload))))
    (t prepared-payload)))

(defun engine-payload-store-copy-prepared-payload-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-prepared-payload value)))
             table)
    copy))

(defun engine-payload-store-copy-blob-and-proofs (blob-and-proofs)
  (cond
    ((typep blob-and-proofs 'engine-blob-and-proofs)
     (make-engine-blob-and-proofs
      :blob (maybe-copy-bytes
             (engine-blob-and-proofs-blob blob-and-proofs))
      :commitment (maybe-copy-bytes
                   (engine-blob-and-proofs-commitment blob-and-proofs))
      :proof (maybe-copy-bytes
              (engine-blob-and-proofs-proof blob-and-proofs))
      :cell-proofs
      (mapcar #'maybe-copy-bytes
              (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
    (t blob-and-proofs)))

(defun engine-payload-store-copy-blob-sidecar-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-blob-and-proofs value)))
             table)
    copy))

(defun maybe-copy-hash32 (hash)
  (when hash
    (make-hash32 (copy-seq (hash32-bytes hash)))))

(defun maybe-copy-address (address)
  (when address
    (make-address (copy-seq (address-bytes address)))))

(defun engine-payload-store-copy-block-header (header)
  (when header
    (make-block-header
     :parent-hash (maybe-copy-hash32 (block-header-parent-hash header))
     :ommers-hash (maybe-copy-hash32 (block-header-ommers-hash header))
     :beneficiary (maybe-copy-address (block-header-beneficiary header))
     :state-root (maybe-copy-hash32 (block-header-state-root header))
     :transactions-root
     (maybe-copy-hash32 (block-header-transactions-root header))
     :receipts-root (maybe-copy-hash32 (block-header-receipts-root header))
     :logs-bloom (maybe-copy-bytes (block-header-logs-bloom header))
     :difficulty (block-header-difficulty header)
     :number (block-header-number header)
     :gas-limit (block-header-gas-limit header)
     :gas-used (block-header-gas-used header)
     :timestamp (block-header-timestamp header)
     :extra-data (maybe-copy-bytes (block-header-extra-data header))
     :mix-hash (maybe-copy-hash32 (block-header-mix-hash header))
     :nonce (maybe-copy-bytes (block-header-nonce header))
     :base-fee-per-gas (block-header-base-fee-per-gas header)
     :withdrawals-root (maybe-copy-hash32 (block-header-withdrawals-root header))
     :blob-gas-used (block-header-blob-gas-used header)
     :excess-blob-gas (block-header-excess-blob-gas header)
     :parent-beacon-root
     (maybe-copy-hash32 (block-header-parent-beacon-root header))
     :requests-hash (maybe-copy-hash32 (block-header-requests-hash header))
     :block-access-list-hash
     (maybe-copy-hash32 (block-header-block-access-list-hash header))
     :slot-number (block-header-slot-number header))))

(defun engine-payload-store-copy-log-entry (log)
  (cond
    ((typep log 'log-entry)
     (make-log-entry
      :address (maybe-copy-address (log-entry-address log))
      :topics (mapcar (lambda (topic)
                        (if (typep topic 'hash32)
                            (maybe-copy-hash32 topic)
                            (maybe-copy-bytes topic)))
                      (log-entry-topics log))
      :data (maybe-copy-bytes (log-entry-data log))))
    (t log)))

(defun engine-payload-store-copy-receipt (receipt)
  (cond
    ((typep receipt 'receipt)
     (make-receipt
      :post-state (maybe-copy-bytes (receipt-post-state receipt))
      :status (receipt-status receipt)
      :cumulative-gas-used (receipt-cumulative-gas-used receipt)
      :logs (mapcar #'engine-payload-store-copy-log-entry
                    (receipt-logs receipt))))
    (t receipt)))

(defun engine-payload-store-copy-block (block)
  (cond
    ((typep block 'ethereum-block)
     (let ((copy (copy-ethereum-block block)))
       (setf (block-header copy)
             (engine-payload-store-copy-block-header (block-header block))
             (block-transactions copy)
             (mapcar (lambda (transaction)
                       (transaction-from-encoding
                        (transaction-encoding transaction)))
                     (block-transactions block))
             (block-receipts copy)
             (mapcar #'engine-payload-store-copy-receipt
                     (block-receipts block))
             (block-ommers copy) (copy-list (block-ommers block))
             (block-withdrawals copy)
             (maybe-copy-withdrawals (block-withdrawals block))
             (block-requests copy) (maybe-copy-requests (block-requests block))
             (block-block-access-list copy)
             (copy-tree (block-block-access-list block))
             (block-encoded-block-access-list copy)
             (maybe-copy-bytes (block-encoded-block-access-list block)))
       copy))
    (t block)))

(defun engine-payload-store-copy-block-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-block value)))
             table)
    copy))

(defun engine-payload-store-copy-transaction (transaction)
  (transaction-from-encoding (transaction-encoding transaction)))

(defun engine-payload-store-copy-transaction-location (location)
  (cond
    ((typep location 'engine-transaction-location)
     (let* ((index (engine-transaction-location-index location))
            (block-copy
              (engine-payload-store-copy-block
               (engine-transaction-location-block location)))
            (transaction
              (engine-transaction-location-transaction location))
            (receipt (engine-transaction-location-receipt location)))
       (make-engine-transaction-location
        :block block-copy
        :index index
        :transaction (or (nth index (block-transactions block-copy))
                         (and transaction
                              (engine-payload-store-copy-transaction
                               transaction)))
        :receipt (or (nth index (block-receipts block-copy))
                     (engine-payload-store-copy-receipt receipt))
        :log-index-start
        (engine-transaction-location-log-index-start location))))
    (t location)))

(defun engine-payload-store-copy-transaction-location-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-transaction-location value)))
             table)
    copy))

(defun engine-payload-store-snapshot (store)
  (make-engine-payload-memory-store
   :blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-blocks store))
   :number-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-number-blocks store))
   :canonical-hashes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-canonical-hashes store))
   :transaction-locations
   (engine-payload-store-copy-transaction-location-table
    (engine-payload-memory-store-transaction-locations store))
   :account-balances
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-balances store))
   :account-nonces
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-nonces store))
   :account-codes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-codes store))
   :account-storage
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-storage store))
   :head-number (engine-payload-memory-store-head-number store)
   :state-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-state-blocks store))
   :remote-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-remote-blocks store))
   :invalid-tipsets
   (engine-payload-store-copy-block-table
    (engine-payload-memory-store-invalid-tipsets store))
   :prepared-payloads
   (engine-payload-store-copy-prepared-payload-table
    (engine-payload-memory-store-prepared-payloads store))
   :blob-sidecars
   (engine-payload-store-copy-blob-sidecar-table
    (engine-payload-memory-store-blob-sidecars store))
   :txpool
   (engine-pending-txpool-copy
    (engine-payload-memory-store-txpool store))
   :log-filters
   (engine-payload-store-copy-filter-table
    (engine-payload-memory-store-log-filters store))
   :next-log-filter-id
   (engine-payload-memory-store-next-log-filter-id store)
   :head-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-head-checkpoint store))
   :safe-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-safe-checkpoint store))
   :finalized-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-finalized-checkpoint store))))

(defun engine-payload-store-restore (store snapshot)
  (setf (engine-payload-memory-store-blocks store)
        (engine-payload-memory-store-blocks snapshot)
        (engine-payload-memory-store-number-blocks store)
        (engine-payload-memory-store-number-blocks snapshot)
        (engine-payload-memory-store-canonical-hashes store)
        (engine-payload-memory-store-canonical-hashes snapshot)
        (engine-payload-memory-store-transaction-locations store)
        (engine-payload-memory-store-transaction-locations snapshot)
        (engine-payload-memory-store-account-balances store)
        (engine-payload-memory-store-account-balances snapshot)
        (engine-payload-memory-store-account-nonces store)
        (engine-payload-memory-store-account-nonces snapshot)
        (engine-payload-memory-store-account-codes store)
        (engine-payload-memory-store-account-codes snapshot)
        (engine-payload-memory-store-account-storage store)
        (engine-payload-memory-store-account-storage snapshot)
        (engine-payload-memory-store-head-number store)
        (engine-payload-memory-store-head-number snapshot)
        (engine-payload-memory-store-state-blocks store)
        (engine-payload-memory-store-state-blocks snapshot)
        (engine-payload-memory-store-remote-blocks store)
        (engine-payload-memory-store-remote-blocks snapshot)
        (engine-payload-memory-store-invalid-tipsets store)
        (engine-payload-memory-store-invalid-tipsets snapshot)
        (engine-payload-memory-store-prepared-payloads store)
        (engine-payload-memory-store-prepared-payloads snapshot)
        (engine-payload-memory-store-blob-sidecars store)
        (engine-payload-memory-store-blob-sidecars snapshot)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool snapshot)
        (engine-payload-memory-store-log-filters store)
        (engine-payload-memory-store-log-filters snapshot)
        (engine-payload-memory-store-next-log-filter-id store)
        (engine-payload-memory-store-next-log-filter-id snapshot)
        (engine-payload-memory-store-head-checkpoint store)
        (engine-payload-memory-store-head-checkpoint snapshot)
        (engine-payload-memory-store-safe-checkpoint store)
        (engine-payload-memory-store-safe-checkpoint snapshot)
        (engine-payload-memory-store-finalized-checkpoint store)
        (engine-payload-memory-store-finalized-checkpoint snapshot))
  store)

(defun chain-store-atomic-commit (store thunk)
  (let* ((store (chain-store-require-memory-store store))
         (snapshot (engine-payload-store-snapshot store)))
    (handler-case
        (funcall thunk)
      (error (condition)
        (engine-payload-store-restore store snapshot)
        (error condition)))))

(defun chain-store-put-block (store block &key (state-available-p nil))
  (engine-payload-store-put-block
   (chain-store-require-memory-store store)
   block
   :state-available-p state-available-p))

(defun chain-store-known-block (store hash)
  (engine-payload-store-known-block
   (chain-store-require-memory-store store)
   hash))

(defun chain-store-block-by-number (store number)
  (engine-payload-store-block-by-number
   (chain-store-require-memory-store store)
   number))

(defun chain-store-canonical-hash (store number)
  (engine-payload-store-canonical-hash
   (chain-store-require-memory-store store)
   number))

(defun chain-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (engine-payload-store-set-canonical-head
   (chain-store-require-memory-store store)
   hash
   :expected-chain-id expected-chain-id
   :chain-config chain-config))

(defun chain-store-head-number (store)
  (engine-payload-store-head-number
   (chain-store-require-memory-store store)))

(defun chain-store-block-tag-number (store tag)
  (engine-payload-store-block-tag-number
   (chain-store-require-memory-store store)
   tag))

(defun chain-store-latest-block (store)
  (chain-store-block-by-number
   store
   (chain-store-head-number store)))

(defun chain-store-transaction-location (store hash)
  (engine-payload-store-transaction-location
   (chain-store-require-memory-store store)
   hash))

(defun chain-store-block-receipts (store hash)
  (let ((block (chain-store-known-block store hash)))
    (when block
      (mapcar #'engine-payload-store-copy-receipt
              (block-receipts block)))))

(defun chain-store-state-available-p (store hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-remove-prefixed-keys (table prefix)
  (let ((keys '()))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (when (engine-payload-store-string-prefix-p prefix key)
         (push key keys)))
     table)
    (dolist (key keys)
      (remhash key table))
    (length keys)))

(defun engine-payload-store-prune-state-snapshot (store block-key)
  (let ((prefix (format nil "~A:" block-key)))
    (remhash block-key (engine-payload-memory-store-state-blocks store))
    (+ (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-balances store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-nonces store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-codes store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-storage store)
        prefix))))

(defun chain-store-prune-state-before (store block-number)
  (let ((store (chain-store-require-memory-store store)))
    (unless (and (integerp block-number) (not (minusp block-number)))
      (block-validation-fail
       "Chain state pruning block number must be a non-negative integer"))
    (let ((block-keys '())
          (head-block-key
            (let ((checkpoint
                    (engine-payload-memory-store-head-checkpoint store)))
              (let ((hash (and checkpoint
                               (chain-store-checkpoint-block-hash
                                checkpoint))))
                (if hash
                    (engine-payload-store-key hash)
                    (gethash
                     (engine-payload-memory-store-head-number store)
                     (engine-payload-memory-store-canonical-hashes
                      store)))))))
      (maphash
       (lambda (block-key state-available-p)
         (when state-available-p
           (let ((block (gethash block-key
                                  (engine-payload-memory-store-blocks store))))
             (when (and block
                        (or (null head-block-key)
                            (not (string= block-key head-block-key)))
                        (< (block-header-number (block-header block))
                           block-number))
               (push block-key block-keys)))))
       (engine-payload-memory-store-state-blocks store))
      (dolist (block-key block-keys)
        (engine-payload-store-prune-state-snapshot store block-key))
      (length block-keys))))

(defun chain-store-update-forkchoice-checkpoints (store state)
  (engine-payload-store-update-forkchoice-checkpoints
   (chain-store-require-memory-store store)
   state))

(defun chain-store-head-checkpoint (store)
  (engine-payload-memory-store-head-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-safe-checkpoint (store)
  (engine-payload-memory-store-safe-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-finalized-checkpoint (store)
  (engine-payload-memory-store-finalized-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-checkpoint-block (store checkpoint)
  (let ((hash (and checkpoint
                   (chain-store-checkpoint-block-hash checkpoint))))
    (when hash
      (chain-store-known-block store hash))))

(defun chain-store-head-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-head-checkpoint store)))

(defun chain-store-safe-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-safe-checkpoint store)))

(defun chain-store-finalized-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-finalized-checkpoint store)))

(defun chain-store-put-prepared-payload (store prepared-payload)
  (engine-payload-store-put-prepared-payload
   (chain-store-require-memory-store store)
   prepared-payload))

(defun chain-store-prepared-payload (store payload-id)
  (engine-payload-store-prepared-payload
   (chain-store-require-memory-store store)
   payload-id))

(defun engine-payload-store-put-log-filter (store filter)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-log-filter
           :criteria filter
           :last-block-number
           (unless (genesis-object-field-present-p filter "blockHash")
             (let ((from-block (genesis-object-field filter "fromBlock")))
               (when (or (null from-block)
                         (and (stringp from-block)
                              (or (string= from-block "latest")
                                  (string= from-block "pending"))))
                 (engine-payload-memory-store-head-number store))))))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-block-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-block-filter
           :last-block-number
           (engine-payload-memory-store-head-number store)))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-pending-transaction-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-pending-transaction-filter))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-log-filter (store id)
  (gethash id (engine-payload-memory-store-log-filters store)))

(defun engine-payload-store-uninstall-log-filter (store id)
  (remhash id (engine-payload-memory-store-log-filters store)))

(defun engine-payload-store-account-key (block-hash address)
  (format nil "~A:~A"
          (engine-payload-store-key block-hash)
          (address-to-hex address)))

(defun engine-payload-store-account-storage-key (block-hash address slot)
  (format nil "~A:~A"
          (engine-payload-store-account-key block-hash address)
          (hash32-to-hex slot)))

(defun engine-payload-store-put-account-balance
    (store block-hash address balance)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account balance address must be an address"))
  (unless (uint256-p balance)
    (block-validation-fail "Engine account balance must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account balance block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-balances store))
          balance
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    balance))

(defun engine-payload-store-account-balance (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-balances store)
           0))

(defun engine-payload-store-put-account-nonce
    (store block-hash address nonce)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account nonce address must be an address"))
  (unless (uint64-value-p nonce)
    (block-validation-fail "Engine account nonce must be uint64"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account nonce block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-nonces store))
          nonce
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    nonce))

(defun engine-payload-store-account-nonce (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-nonces store)
           0))

(defun engine-payload-store-put-account-code
    (store block-hash address code)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account code address must be an address"))
  (let ((block (engine-payload-store-known-block store block-hash))
        (code (ensure-byte-vector code)))
    (unless block
      (block-validation-fail
       "Engine account code block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))
          (copy-seq code)
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    code))

(defun engine-payload-store-account-code (store block-hash address)
  (let ((code
          (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))))
    (if code
        (copy-seq code)
        (make-byte-vector 0))))

(defun engine-payload-store-put-account-storage
    (store block-hash address slot value)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account storage address must be an address"))
  (unless (hash32-p slot)
    (block-validation-fail "Engine account storage slot must be a hash32"))
  (unless (uint256-p value)
    (block-validation-fail "Engine account storage value must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account storage block must be known by the memory store"))
    (setf (gethash
           (engine-payload-store-account-storage-key block-hash address slot)
           (engine-payload-memory-store-account-storage store))
          value
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    value))

(defun engine-payload-store-account-storage (store block-hash address slot)
  (gethash (engine-payload-store-account-storage-key block-hash address slot)
           (engine-payload-memory-store-account-storage store)
           0))

(defun chain-store-put-account-balance
    (store block-hash address balance)
  (engine-payload-store-put-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address
   balance))

(defun chain-store-account-balance (store block-hash address)
  (engine-payload-store-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-nonce
    (store block-hash address nonce)
  (engine-payload-store-put-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address
   nonce))

(defun chain-store-account-nonce (store block-hash address)
  (engine-payload-store-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-code
    (store block-hash address code)
  (engine-payload-store-put-account-code
   (chain-store-require-memory-store store)
   block-hash
   address
   code))

(defun chain-store-account-code (store block-hash address)
  (engine-payload-store-account-code
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-storage
    (store block-hash address slot value)
  (engine-payload-store-put-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot
   value))

(defun chain-store-account-storage (store block-hash address slot)
  (engine-payload-store-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun engine-payload-store-remember-account-key
    (accounts block-prefix key &key storage-key-p)
  (when (engine-payload-store-string-prefix-p block-prefix key)
    (let* ((rest (subseq key (length block-prefix)))
           (address-hex
             (if storage-key-p
                 (let ((slot-separator (position #\: rest)))
                   (and slot-separator
                        (subseq rest 0 slot-separator)))
                 rest)))
      (when address-hex
        (setf (gethash address-hex accounts) t)))))

(defun engine-payload-store-sorted-hash-keys (table)
  (let (keys)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sort keys #'string<)))

(defun engine-payload-store-account-storage-entries
    (memory-store block-hash address)
  (let ((account-prefix
          (format nil "~A:"
                  (engine-payload-store-account-key block-hash address)))
        (entries '()))
    (dolist (key (engine-payload-store-sorted-hash-keys
                  (engine-payload-memory-store-account-storage memory-store)))
      (when (engine-payload-store-string-prefix-p account-prefix key)
        (push (cons (hash32-from-hex
                     (subseq key (length account-prefix)))
                    (gethash
                     key
                     (engine-payload-memory-store-account-storage memory-store)))
              entries)))
    (nreverse entries)))

(defun chain-store-for-each-account (store block-hash function)
  (let ((memory-store (chain-store-require-memory-store store)))
    (when (chain-store-state-available-p store block-hash)
      (let ((block-prefix
              (format nil "~A:" (engine-payload-store-key block-hash)))
            (accounts (make-hash-table :test #'equal)))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-balances memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-nonces memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-codes memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key :storage-key-p t))
         (engine-payload-memory-store-account-storage memory-store))
        (dolist (address-hex (engine-payload-store-sorted-hash-keys accounts))
           (let* ((address (address-from-hex address-hex))
                  (account-key
                    (engine-payload-store-account-key block-hash address)))
             (funcall
              function
              address
              (gethash account-key
                       (engine-payload-memory-store-account-balances
                        memory-store)
                       0)
              (gethash account-key
                       (engine-payload-memory-store-account-nonces
                        memory-store)
                       0)
              (engine-payload-store-account-code
               memory-store block-hash address)
              (engine-payload-store-account-storage-entries
               memory-store block-hash address))))
        store))))

(defun engine-payload-store-state-available-p
    (store hash)
  (not (null
        (gethash (engine-payload-store-key hash)
                 (engine-payload-memory-store-state-blocks store)))))

(defun engine-payload-store-remote-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-remote-blocks store))))

(defun engine-payload-store-put-remote-block
    (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine remote block cache value must be a block"))
  (setf (gethash (engine-payload-store-key (block-hash block))
                 (engine-payload-memory-store-remote-blocks store))
        (engine-payload-store-copy-block block))
  block)

(defun engine-payload-store-remove-remote-block
    (store hash)
  (remhash (engine-payload-store-key hash)
           (engine-payload-memory-store-remote-blocks store)))

(defun engine-payload-store-prune-prepared-payloads-for-block
    (store block-key)
  (let ((stale-payload-id-keys nil))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (string= block-key
                      (engine-payload-store-key
                       (block-hash
                        (engine-prepared-payload-block prepared-payload))))
         (push payload-id-key stale-payload-id-keys)))
     (engine-payload-memory-store-prepared-payloads store))
    (dolist (payload-id-key stale-payload-id-keys)
      (remhash payload-id-key
               (engine-payload-memory-store-prepared-payloads store)))))

(defun engine-payload-store-mark-invalid
    (store invalid-block &key head-hash)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep invalid-block 'ethereum-block)
    (block-validation-fail "Engine payload invalid marker must be a block"))
  (let* ((invalid-hash (block-hash invalid-block))
         (key (engine-payload-store-key (or head-hash invalid-hash))))
    (engine-payload-store-remove-remote-block store invalid-hash)
    (engine-payload-store-prune-prepared-payloads-for-block
     store
     (engine-payload-store-key invalid-hash))
    (when head-hash
      (engine-payload-store-remove-remote-block store head-hash)
      (engine-payload-store-prune-prepared-payloads-for-block store key))
    (setf (gethash key (engine-payload-memory-store-invalid-tipsets store))
          (engine-payload-store-copy-block invalid-block))
    invalid-block))

(defun engine-payload-store-invalid-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-invalid-tipsets store))))

(defun engine-payload-store-invalid-ancestor-status
    (store check-hash head-hash)
  (let ((invalid-block
          (engine-payload-store-invalid-block store check-hash)))
    (when invalid-block
      (unless (string= (engine-payload-store-key check-hash)
                       (engine-payload-store-key head-hash))
        (engine-payload-store-mark-invalid
         store invalid-block :head-hash head-hash))
      (make-payload-status
       :status +payload-status-invalid+
       :latest-valid-hash
       (block-header-parent-hash (block-header invalid-block))
       :validation-error "links to previously rejected block"))))

(defun engine-payload-id-key (payload-id)
  (let ((bytes (ensure-byte-vector payload-id)))
    (unless (= 8 (length bytes))
      (block-validation-fail "Engine payload id must be 8 bytes"))
    (bytes-to-hex bytes)))

(defun engine-payload-id-to-hex (payload-id)
  (engine-payload-id-key payload-id))

(defun engine-payload-store-put-prepared-payload
    (store prepared-payload)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (validate-engine-prepared-payload prepared-payload)
  (let ((stored-payload
          (engine-payload-store-copy-prepared-payload prepared-payload)))
    (setf (gethash
           (engine-payload-id-key
            (engine-prepared-payload-payload-id stored-payload))
           (engine-payload-memory-store-prepared-payloads store))
          stored-payload))
  prepared-payload)

(defun engine-payload-store-prepared-payload (store payload-id)
  (engine-payload-store-copy-prepared-payload
   (gethash (engine-payload-id-key payload-id)
            (engine-payload-memory-store-prepared-payloads store))))

(defun engine-payload-store-put-blob-sidecar
    (store sidecar)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep sidecar 'blob-sidecar)
    (block-validation-fail
     "Engine blob sidecar store value must be a blob sidecar"))
  (let ((hashes (blob-sidecar-versioned-hashes sidecar))
        (blobs (blob-sidecar-blobs sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length hashes) (length blobs))
      (block-validation-fail
       "Engine blob sidecar blobs and commitments must have matching lengths"))
    (unless (or (= (length proofs) (length blobs))
                (= (length proofs)
                   (* (length blobs) +cell-proofs-per-blob+)))
      (block-validation-fail
       "Engine blob sidecar proofs must be one per blob or cell proofs per blob"))
    (loop for versioned-hash in hashes
          for blob in blobs
          for index from 0
          for proof = (if (= (length proofs) (length blobs))
                          (nth index proofs)
                          (nth (* index +cell-proofs-per-blob+) proofs))
          for cell-proofs = (when (= (length proofs)
                                     (* (length blobs)
                                        +cell-proofs-per-blob+))
                              (subseq proofs
                                      (* index +cell-proofs-per-blob+)
                                      (* (1+ index)
                                         +cell-proofs-per-blob+)))
          do (setf (gethash
                    (engine-payload-store-key versioned-hash)
                    (engine-payload-memory-store-blob-sidecars store))
                   (make-engine-blob-and-proofs
                    :blob (maybe-copy-bytes blob)
                    :commitment
                    (maybe-copy-bytes
                     (nth index (blob-sidecar-commitments sidecar)))
                    :proof (maybe-copy-bytes proof)
                    :cell-proofs (mapcar #'maybe-copy-bytes
                                         cell-proofs)))))
  sidecar)

(defun engine-payload-store-blob-and-proofs-v1
    (store versioned-hash)
  (engine-payload-store-copy-blob-and-proofs
   (gethash (engine-payload-store-key versioned-hash)
            (engine-payload-memory-store-blob-sidecars store))))

(defun engine-payload-store-blob-and-proofs-v2
    (store versioned-hash)
  (let ((blob-and-proofs
          (engine-payload-store-blob-and-proofs-v1 store versioned-hash)))
    (when (and blob-and-proofs
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      blob-and-proofs)))
