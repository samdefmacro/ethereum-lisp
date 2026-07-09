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
