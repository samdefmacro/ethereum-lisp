(in-package #:ethereum-lisp.core)

(defun eth-rpc-hash-table-object (table)
  (if (zerop (hash-table-count table))
      +json-empty-object+
      (loop for key in (sort (loop for key being the hash-keys of table
                                   collect key)
                             #'string<)
            collect (cons key (gethash key table)))))

(defun txpool-rpc-nonce-key< (left right)
  (< (parse-integer left :junk-allowed nil)
     (parse-integer right :junk-allowed nil)))

(defun txpool-rpc-indexed-nonce-transactions
    (sender-transactions value-function)
  (let ((entries
          (unless (or (null sender-transactions)
                      (zerop (hash-table-count sender-transactions)))
            (loop for nonce in (sort (loop for nonce being the hash-keys
                                             of sender-transactions
                                           collect nonce)
                                     #'txpool-rpc-nonce-key<)
                  for value = (funcall value-function
                                       (gethash nonce sender-transactions))
                  when value
                    collect (cons nonce value)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-nonce-transactions-from-sender-indexes
    (address value-function &rest sender-indexes)
  (let ((sender-key (address-to-hex address))
        (merged-transactions (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (let ((sender-transactions (gethash sender-key sender-index)))
        (when sender-transactions
          (maphash
           (lambda (nonce transaction)
             (setf (gethash nonce merged-transactions) transaction))
           sender-transactions))))
    (txpool-rpc-indexed-nonce-transactions
     merged-transactions
     value-function)))

(defun txpool-rpc-indexed-sender-transactions
    (sender-index value-function)
  (let ((entries
          (unless (zerop (hash-table-count sender-index))
            (loop for sender in (sort (loop for sender being the hash-keys
                                              of sender-index
                                            collect sender)
                                      #'string<)
                  for transactions =
                    (txpool-rpc-indexed-nonce-transactions
                     (gethash sender sender-index)
                     value-function)
                  unless (json-empty-object-p transactions)
                    collect (cons sender transactions)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-sender-transactions-from-indexes
    (value-function &rest sender-indexes)
  (let ((merged-senders (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (maphash
       (lambda (sender sender-transactions)
         (let ((merged-transactions
                 (or (gethash sender merged-senders)
                     (setf (gethash sender merged-senders)
                           (make-hash-table :test 'equal)))))
           (maphash
            (lambda (nonce transaction)
              (setf (gethash nonce merged-transactions) transaction))
            sender-transactions)))
       sender-index))
    (txpool-rpc-indexed-sender-transactions
     merged-senders
     value-function)))

(defun txpool-rpc-transaction-summary (transaction &key expected-chain-id)
  (when (transaction-sender
         transaction
         :expected-chain-id expected-chain-id)
    (let ((to (transaction-to transaction)))
      (format nil "~A: ~D wei + ~D gas x ~D wei"
              (if to
                  (address-to-hex to)
                  "contract creation")
              (transaction-value transaction)
              (transaction-gas-limit transaction)
              (transaction-max-fee-per-gas transaction)))))

(defun txpool-rpc-indexed-content-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (when (transaction-sender
            transaction
            :expected-chain-id expected-chain-id)
       (eth-rpc-pending-transaction-object
        transaction
        :expected-chain-id expected-chain-id)))))

(defun txpool-rpc-indexed-inspect-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (txpool-rpc-transaction-summary
      transaction
      :expected-chain-id expected-chain-id))))

(defun eth-rpc-validate-set-code-authorization-signatures (transaction)
  (validate-set-code-authorization-signatures transaction))

(defun eth-rpc-txpool-admission-head-context (store)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (values head
            (if header (block-header-number header) 0)
            (if header (block-header-timestamp header) 0))))

(defun eth-rpc-validate-txpool-sender-code (store head sender)
  (when head
    (let ((code (chain-store-account-code store (block-hash head) sender)))
      (when (and (plusp (length code))
                 (not (set-code-delegation-target code)))
        (block-validation-fail
         "eth_sendRawTransaction sender has non-delegation code"))))
  t)

(defun eth-rpc-txpool-upfront-cost (transaction)
  (engine-payload-store-txpool-upfront-cost transaction))

(defun eth-rpc-txpool-sender-admission-expenditure
    (store sender transaction)
  (engine-payload-store-sender-admission-expenditure
   store sender transaction))

(defun eth-rpc-validate-txpool-sender-state (store head sender transaction)
  (when (and head
             (chain-store-state-available-p store (block-hash head)))
    (let* ((block-hash (block-hash head))
           (state-nonce (chain-store-account-nonce store block-hash sender))
           (state-balance
             (chain-store-account-balance store block-hash sender)))
      (when (< (transaction-nonce transaction) state-nonce)
        (block-validation-fail "eth_sendRawTransaction nonce too low"))
      (when (< state-balance
               (eth-rpc-txpool-sender-admission-expenditure
                store
                sender
                transaction))
        (block-validation-fail
         "eth_sendRawTransaction insufficient sender balance"))))
  t)

(defun eth-rpc-txpool-queued-nonce-gap-p
    (store sender transaction &key expected-chain-id)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (and head
         (chain-store-state-available-p store (block-hash head))
         (> (transaction-nonce transaction)
            (engine-payload-store-pending-contiguous-nonce
             store
             sender
             (chain-store-account-nonce
              store
              (block-hash head)
              sender)
             :expected-chain-id expected-chain-id)))))

(defun eth-rpc-txpool-basefee-ineligible-p (store transaction)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (let* ((header (and head (block-header head)))
           (base-fee (and header
                          (block-header-base-fee-per-gas header))))
      (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee)))))

(defun eth-rpc-validate-txpool-admission
    (transaction sender store config)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (let ((rules (chain-config-rules config block-number timestamp)))
      (validate-transaction-type-for-config
       transaction config block-number timestamp)
      (validate-transaction-data-field transaction)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction))
      (engine-payload-store-validate-txpool-blob-fee-cap
       store
       transaction
       :chain-config config
       :label "eth_sendRawTransaction")
      (let ((intrinsic-gas
              (ethereum-lisp.state:transaction-intrinsic-gas
               transaction
               :eip3860-p (or (null rules)
                               (chain-rules-shanghai-p rules)))))
        (when (< (transaction-gas-limit transaction) intrinsic-gas)
          (block-validation-fail
           "eth_sendRawTransaction gas limit below intrinsic gas")))
      (when (and head
                 (> (transaction-gas-limit transaction)
                    (block-header-gas-limit (block-header head))))
        (block-validation-fail
         "eth_sendRawTransaction gas limit exceeds block gas limit"))
      (eth-rpc-validate-txpool-sender-state
       store head sender transaction)
      (eth-rpc-validate-txpool-sender-code store head sender)))
  t)

(defun eth-rpc-unprotected-transaction-p (transaction)
  (and (typep transaction 'legacy-transaction)
       (not (legacy-transaction-protected-p transaction))))

(defun eth-rpc-validate-unprotected-transaction-policy
    (transaction allow-unprotected-transactions-p)
  (when (and (eth-rpc-unprotected-transaction-p transaction)
             (not allow-unprotected-transactions-p))
    (block-validation-fail
     "eth_sendRawTransaction unprotected legacy transaction rejected"))
  t)

(defun eth-rpc-validate-txpool-price-limit
    (transaction txpool-price-limit local-transaction-p)
  (when (and txpool-price-limit
             (not local-transaction-p)
             (plusp txpool-price-limit)
             (< (transaction-max-fee-per-gas transaction)
                txpool-price-limit))
    (block-validation-fail
     "eth_sendRawTransaction gas price below txpool price limit"))
  t)

(defun eth-rpc-local-transaction-p
    (sender txpool-local-addresses txpool-no-local-exemptions-p)
  (and (not txpool-no-local-exemptions-p)
       (some (lambda (local-address)
               (string= (address-to-hex sender)
                        (address-to-hex local-address)))
             txpool-local-addresses)))

(defun eth-rpc-local-transaction-predicate
    (config txpool-local-addresses txpool-no-local-exemptions-p)
  (lambda (transaction)
    (let ((sender
            (transaction-sender
             transaction
             :expected-chain-id (chain-config-chain-id config))))
      (and sender
           (eth-rpc-local-transaction-p
            sender
            txpool-local-addresses
            txpool-no-local-exemptions-p)))))

(defun eth-rpc-remove-expired-txpool-transactions
    (store config txpool-lifetime-seconds txpool-now
     txpool-local-addresses txpool-no-local-exemptions-p)
  (when txpool-lifetime-seconds
    (engine-payload-store-remove-expired-txpool-queued-view-transactions
     store
     txpool-lifetime-seconds
     txpool-now
     :local-transaction-predicate
     (eth-rpc-local-transaction-predicate
      config txpool-local-addresses txpool-no-local-exemptions-p))))

(defun engine-rpc-handle-eth-send-raw-transaction
    (params store config &key allow-unprotected-transactions-p
                              txpool-price-limit
                              txpool-price-bump-percent
                              txpool-account-slot-limit
                              txpool-global-slot-limit
                              txpool-account-queue-limit
                              txpool-global-queue-limit
                              txpool-local-addresses
                              txpool-no-local-exemptions-p
                              txpool-now)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_sendRawTransaction params must contain exactly one transaction"))
  (let* ((raw-bytes
            (engine-rpc-bytes
             (first params)
             "eth_sendRawTransaction transaction"))
         (transaction (transaction-from-encoding raw-bytes))
         (hash (transaction-hash transaction)))
    (validate-set-code-transaction-fields transaction)
    (eth-rpc-validate-set-code-authorization-signatures transaction)
    (let ((sender
            (or (transaction-sender
                 transaction
                 :expected-chain-id (chain-config-chain-id config))
                (block-validation-fail
                 "eth_sendRawTransaction transaction sender recovery failed"))))
      (let ((local-transaction-p
              (eth-rpc-local-transaction-p
               sender txpool-local-addresses txpool-no-local-exemptions-p)))
        (unless (or (chain-store-transaction-location store hash)
                    (engine-payload-store-pooled-transaction store hash))
          (eth-rpc-validate-unprotected-transaction-policy
           transaction
           allow-unprotected-transactions-p)
          (eth-rpc-validate-txpool-price-limit
           transaction
           txpool-price-limit
           local-transaction-p)
          (eth-rpc-validate-txpool-admission transaction sender store config)
          (cond
            ((typep transaction 'blob-transaction)
             (engine-payload-store-put-blob-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now))
            ((eth-rpc-txpool-basefee-ineligible-p store transaction)
             (engine-payload-store-put-basefee-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now))
            ((eth-rpc-txpool-queued-nonce-gap-p
              store
              sender
              transaction
              :expected-chain-id (chain-config-chain-id config))
             (engine-payload-store-put-queued-transaction
             store
             transaction
             :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now
              :account-queue-limit
              (unless local-transaction-p txpool-account-queue-limit)
              :global-queue-limit
              (unless local-transaction-p txpool-global-queue-limit)))
            (t
             (engine-payload-store-put-pending-transaction
              store
              transaction
              :price-bump-percent txpool-price-bump-percent
              :admitted-at txpool-now
              :account-slot-limit
              (unless local-transaction-p txpool-account-slot-limit)
              :global-slot-limit
              (unless local-transaction-p txpool-global-slot-limit))
             (engine-payload-store-promote-queued-transactions
              store sender
              :expected-chain-id (chain-config-chain-id config)
              :account-slot-limit txpool-account-slot-limit
              :global-slot-limit txpool-global-slot-limit
              :local-transaction-predicate
              (lambda (transaction)
                (let ((sender
                        (transaction-sender
                         transaction
                         :expected-chain-id (chain-config-chain-id config))))
                  (and sender
                       (eth-rpc-local-transaction-p
                        sender
                        txpool-local-addresses
                        txpool-no-local-exemptions-p)))))
             (engine-payload-store-promote-basefee-and-queued-transactions
              store
              :expected-chain-id (chain-config-chain-id config)
              :account-slot-limit txpool-account-slot-limit
              :global-slot-limit txpool-global-slot-limit
              :local-transaction-predicate
              (lambda (transaction)
                (let ((sender
                        (transaction-sender
                         transaction
                         :expected-chain-id (chain-config-chain-id config))))
                  (and sender
                       (eth-rpc-local-transaction-p
                        sender
                        txpool-local-addresses
                        txpool-no-local-exemptions-p))))))))))
    (hash32-to-hex hash)))

(defun eth-rpc-txpool-queued-view-transactions (store)
  (append (engine-payload-store-queued-transactions store)
          (engine-payload-store-basefee-transactions store)
          (engine-payload-store-blob-transactions store)))

(defun eth-rpc-txpool-visible-transaction-count
    (transactions expected-chain-id)
  (count-if
   (lambda (transaction)
     (transaction-sender
      transaction
      :expected-chain-id expected-chain-id))
   transactions))

(defun eth-rpc-txpool-pending-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (engine-payload-store-pending-transactions store)
   expected-chain-id))

(defun eth-rpc-txpool-queued-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (eth-rpc-txpool-queued-view-transactions store)
   expected-chain-id))

(defun engine-rpc-handle-eth-pending-transactions (params store config)
  (when params
    (block-validation-fail "eth_pendingTransactions params must be empty"))
  (eth-rpc-pending-transaction-objects
   (engine-payload-store-pending-transactions store)
   :expected-chain-id (chain-config-chain-id config)))

(defun engine-rpc-handle-txpool-status (params store config)
  (when params
    (block-validation-fail "txpool_status params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (quantity-to-hex
            (eth-rpc-txpool-pending-view-count store chain-id)))
     (cons "queued"
           (quantity-to-hex
            (eth-rpc-txpool-queued-view-count store chain-id))))))

(defun engine-rpc-handle-txpool-content (params store config)
  (when params
    (block-validation-fail "txpool_content params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-content-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))
(defun engine-rpc-handle-txpool-content-from (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "txpool_contentFrom params must contain exactly one address"))
  (let ((address (eth-rpc-address-param
                  (first params) "txpool_contentFrom" "address"))
        (chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-nonce-transactions
            (gethash
             (address-to-hex address)
             (engine-payload-store-pending-transactions-by-sender store))
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))))
     (cons "queued"
           (txpool-rpc-indexed-nonce-transactions-from-sender-indexes
            address
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-txpool-inspect (params store config)
  (when params
    (block-validation-fail "txpool_inspect params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-inspect-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (txpool-rpc-transaction-summary
               transaction
               :expected-chain-id chain-id))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))
