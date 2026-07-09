(in-package #:ethereum-lisp.core)

(defun engine-payload-store-stale-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (chain-store-state-available-p store (block-hash head))
         (< (transaction-nonce transaction)
            (chain-store-account-nonce
             store
             (block-hash head)
             sender)))))

(defun engine-payload-store-remove-stale-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-stale (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-stale-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-stale
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-stale
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-stale
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-stale
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-expired-txpool-transaction-p
    (store transaction lifetime-seconds now)
  (let ((admitted-at
          (engine-pending-txpool-admission-time
           (engine-payload-store-txpool store)
           transaction)))
    (and admitted-at
         (>= (- now admitted-at) lifetime-seconds))))

(defun engine-payload-store-remove-expired-txpool-queued-view-transactions
    (store lifetime-seconds now &key local-transaction-predicate)
  (let ((removed-transactions nil))
    (when lifetime-seconds
      (unless (and (integerp lifetime-seconds) (not (minusp lifetime-seconds)))
        (block-validation-fail
         "Txpool lifetime must be a non-negative integer"))
      (unless (and (integerp now) (not (minusp now)))
        (block-validation-fail
         "Txpool cleanup time must be a non-negative integer"))
      (flet ((remove-expired (transactions remove-function)
               (dolist (transaction transactions)
                 (when (and (not (and local-transaction-predicate
                                       (funcall local-transaction-predicate
                                                transaction)))
                            (engine-payload-store-expired-txpool-transaction-p
                             store transaction lifetime-seconds now))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-expired
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-expired
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-expired
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-sender-code-invalid-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (not (engine-payload-store-sender-code-admissible-p
               store
               head
               sender)))))

(defun engine-payload-store-remove-sender-code-invalid-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-sender-code-invalid
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-sender-code-invalid-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-sender-code-invalid
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-over-gas-limit-txpool-transaction-p
    (head transaction)
  (> (transaction-gas-limit transaction)
     (block-header-gas-limit (block-header head))))

(defun engine-payload-store-remove-over-gas-limit-txpool-transactions (store)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when head
      (flet ((remove-over-gas (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-over-gas-limit-txpool-transaction-p
                        head transaction)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-over-gas
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-over-gas
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-over-gas
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-over-gas
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-underpriced-blob-txpool-transactions
    (store &key chain-config)
  (let ((blob-base-fee
          (engine-payload-store-current-blob-base-fee
           store
           chain-config))
        (removed-transactions nil))
    (when blob-base-fee
      (dolist (transaction (engine-payload-store-blob-transactions store))
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (engine-pending-txpool-remove-blob-transaction
             (engine-payload-store-txpool store)
             (transaction-hash transaction))
            (push transaction removed-transactions)))))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-invalid-sender-txpool-transactions
    (store &key expected-chain-id)
  (let ((removed-transactions nil))
    (when expected-chain-id
      (flet ((remove-invalid-sender
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (null (transaction-sender
                              transaction
                              :expected-chain-id expected-chain-id))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-invalid-sender
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-invalid-sender
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-invalid-sender
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-invalid-sender
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-chain-config-expected-chain-id
    (expected-chain-id chain-config)
  (or expected-chain-id
      (and chain-config
           (chain-config-chain-id chain-config))))

(defun engine-payload-store-remove-new-head-invalid-txpool-transactions
    (store &key expected-chain-id chain-config)
  (let ((txpool-chain-id
          (engine-payload-store-chain-config-expected-chain-id
           expected-chain-id
           chain-config)))
    (nconc
     (engine-payload-store-remove-invalid-sender-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-stale-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-over-gas-limit-txpool-transactions store)
     (engine-payload-store-remove-underpriced-blob-txpool-transactions
      store
      :chain-config chain-config)
     (engine-payload-store-remove-sender-code-invalid-txpool-transactions
      store
      :expected-chain-id txpool-chain-id))))

(defun engine-payload-store-pending-revalidation-senders (store)
  (loop for sender-key
          being the hash-keys of
            (engine-payload-store-pending-sender-index store)
        collect (address-from-hex sender-key)))

(defun engine-payload-store-demote-pending-transaction
    (store transaction base-fee)
  (engine-payload-store-remove-pending-transaction
   store
   (transaction-hash transaction))
  (if (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee))
      (engine-payload-store-put-basefee-transaction store transaction)
      (engine-payload-store-put-queued-transaction store transaction))
  transaction)

(defun engine-payload-store-revalidate-pending-sender-transactions
    (store sender head base-fee)
  (let* ((block-hash (block-hash head))
         (state-nonce
           (chain-store-account-nonce store block-hash sender))
         (remaining-balance
           (chain-store-account-balance store block-hash sender))
         (next-nonce state-nonce)
         (blocked-p nil)
         (demoted-transactions nil))
    (dolist (transaction
             (engine-payload-store-pending-sender-transactions store sender))
      (cond
        ((< (transaction-nonce transaction) state-nonce)
         (engine-payload-store-remove-pending-transaction
          store
          (transaction-hash transaction)))
        ((or blocked-p
             (/= (transaction-nonce transaction) next-nonce)
             (and base-fee
                  (< (transaction-max-fee-per-gas transaction) base-fee)))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        ((< remaining-balance
            (engine-payload-store-txpool-upfront-cost transaction))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        (t
         (decf remaining-balance
               (engine-payload-store-txpool-upfront-cost transaction))
         (incf next-nonce))))
    (nreverse demoted-transactions)))

(defun engine-payload-store-revalidate-pending-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (demoted-transactions nil))
    (engine-payload-store-remove-invalid-sender-txpool-transactions
     store
     :expected-chain-id expected-chain-id)
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let* ((header (block-header head))
             (base-fee (and header
                            (block-header-base-fee-per-gas header))))
        (dolist (sender
                 (engine-payload-store-pending-revalidation-senders store))
          (setf demoted-transactions
                (nconc
                 demoted-transactions
                 (engine-payload-store-revalidate-pending-sender-transactions
                  store sender head base-fee))))))
    demoted-transactions))
