(in-package #:ethereum-lisp.txpool.application)

(defstruct (txpool-admission-policy
            (:constructor %make-txpool-admission-policy))
  allow-unprotected-transactions-p
  price-limit
  price-bump-percent
  account-slot-limit
  global-slot-limit
  account-queue-limit
  global-queue-limit
  (local-addresses '() :type list)
  no-local-exemptions-p)

(defun make-txpool-admission-policy
    (&key allow-unprotected-transactions-p
          price-limit
          price-bump-percent
          account-slot-limit
          global-slot-limit
          account-queue-limit
          global-queue-limit
          local-addresses
          no-local-exemptions-p)
  (%make-txpool-admission-policy
   :allow-unprotected-transactions-p allow-unprotected-transactions-p
   :price-limit price-limit
   :price-bump-percent price-bump-percent
   :account-slot-limit account-slot-limit
   :global-slot-limit global-slot-limit
   :account-queue-limit account-queue-limit
   :global-queue-limit global-queue-limit
   :local-addresses (copy-list local-addresses)
   :no-local-exemptions-p no-local-exemptions-p))

(defun txpool-local-transaction-p (sender policy)
  (and (not (txpool-admission-policy-no-local-exemptions-p policy))
       (some (lambda (local-address)
               (bytes= (address-bytes sender)
                       (address-bytes local-address)))
             (txpool-admission-policy-local-addresses policy))))

(defun txpool-local-transaction-predicate (config policy)
  (lambda (transaction)
    (let ((sender
            (transaction-sender
             transaction
             :expected-chain-id (chain-config-chain-id config))))
      (and sender (txpool-local-transaction-p sender policy)))))

(defun txpool-admission-head-context (store)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (values head
            (if header (block-header-number header) 0)
            (if header (block-header-timestamp header) 0))))

(defun validate-txpool-sender-code (store head sender)
  (when head
    (let ((code (chain-store-account-code store (block-hash head) sender)))
      (when (and (plusp (length code))
                 (not (set-code-delegation-target code)))
        (block-validation-fail
         "eth_sendRawTransaction sender has non-delegation code"))))
  t)

(defun validate-txpool-sender-state (store head sender transaction)
  (when (and head
             (chain-store-state-available-p store (block-hash head)))
    (let* ((block-hash (block-hash head))
           (state-nonce (chain-store-account-nonce store block-hash sender))
           (state-balance
             (chain-store-account-balance store block-hash sender)))
      (when (< (transaction-nonce transaction) state-nonce)
        (block-validation-fail "eth_sendRawTransaction nonce too low"))
      (when (< state-balance
               (engine-payload-store-sender-admission-expenditure
                store sender transaction))
        (block-validation-fail
         "eth_sendRawTransaction insufficient sender balance"))))
  t)

(defun txpool-queued-nonce-gap-p
    (store sender transaction config)
  (multiple-value-bind (head block-number timestamp)
      (txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (and head
         (chain-store-state-available-p store (block-hash head))
         (> (transaction-nonce transaction)
            (engine-payload-store-pending-contiguous-nonce
             store sender
             (chain-store-account-nonce store (block-hash head) sender)
             :expected-chain-id (chain-config-chain-id config))))))

(defun txpool-basefee-ineligible-p (store transaction)
  (multiple-value-bind (head block-number timestamp)
      (txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (let* ((header (and head (block-header head)))
           (base-fee (and header (block-header-base-fee-per-gas header))))
      (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee)))))

(defun validate-txpool-admission (transaction sender store config)
  (multiple-value-bind (head block-number timestamp)
      (txpool-admission-head-context store)
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
       store transaction
       :chain-config config
       :label "eth_sendRawTransaction")
      (let ((intrinsic-gas
              (ethereum-lisp.execution:transaction-intrinsic-gas
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
      (validate-txpool-sender-state store head sender transaction)
      (validate-txpool-sender-code store head sender)))
  t)

(defun unprotected-transaction-p (transaction)
  (and (typep transaction 'legacy-transaction)
       (not (legacy-transaction-protected-p transaction))))

(defun validate-admission-policy (transaction local-transaction-p policy)
  (when (and (unprotected-transaction-p transaction)
             (not (txpool-admission-policy-allow-unprotected-transactions-p
                   policy)))
    (block-validation-fail
     "eth_sendRawTransaction unprotected legacy transaction rejected"))
  (let ((price-limit (txpool-admission-policy-price-limit policy)))
    (when (and price-limit
               (not local-transaction-p)
               (plusp price-limit)
               (< (transaction-max-fee-per-gas transaction) price-limit))
      (block-validation-fail
       "eth_sendRawTransaction gas price below txpool price limit")))
  t)

(defun admit-new-transaction
    (transaction sender store config policy admitted-at)
  (let ((local-transaction-p
          (txpool-local-transaction-p sender policy))
        (price-bump
          (txpool-admission-policy-price-bump-percent policy)))
    (validate-admission-policy transaction local-transaction-p policy)
    (validate-txpool-admission transaction sender store config)
    (cond
      ((typep transaction 'blob-transaction)
       (engine-payload-store-put-blob-transaction
        store transaction :price-bump-percent price-bump
                          :admitted-at admitted-at))
      ((txpool-basefee-ineligible-p store transaction)
       (engine-payload-store-put-basefee-transaction
        store transaction :price-bump-percent price-bump
                          :admitted-at admitted-at))
      ((txpool-queued-nonce-gap-p store sender transaction config)
       (engine-payload-store-put-queued-transaction
        store transaction :price-bump-percent price-bump
                          :admitted-at admitted-at
        :account-queue-limit
        (unless local-transaction-p
          (txpool-admission-policy-account-queue-limit policy))
        :global-queue-limit
        (unless local-transaction-p
          (txpool-admission-policy-global-queue-limit policy))))
      (t
       (engine-payload-store-put-pending-transaction
        store transaction :price-bump-percent price-bump
                          :admitted-at admitted-at
        :account-slot-limit
        (unless local-transaction-p
          (txpool-admission-policy-account-slot-limit policy))
        :global-slot-limit
        (unless local-transaction-p
          (txpool-admission-policy-global-slot-limit policy)))
       (let ((local-predicate
               (txpool-local-transaction-predicate config policy)))
         (engine-payload-store-promote-queued-transactions
          store :sender sender
          :expected-chain-id (chain-config-chain-id config)
          :account-slot-limit
          (txpool-admission-policy-account-slot-limit policy)
          :global-slot-limit
          (txpool-admission-policy-global-slot-limit policy)
          :local-transaction-predicate local-predicate)
         (engine-payload-store-promote-basefee-and-queued-transactions
          store :expected-chain-id (chain-config-chain-id config)
          :account-slot-limit
          (txpool-admission-policy-account-slot-limit policy)
          :global-slot-limit
          (txpool-admission-policy-global-slot-limit policy)
          :local-transaction-predicate local-predicate))))))

(defun txpool-admit-transaction
    (transaction store config policy &key admitted-at)
  (validate-set-code-transaction-fields transaction)
  (validate-set-code-authorization-signatures transaction)
  (let* ((hash (transaction-hash transaction))
         (sender
           (or (transaction-sender
                transaction
                :expected-chain-id (chain-config-chain-id config))
               (block-validation-fail
                "eth_sendRawTransaction transaction sender recovery failed"))))
    (unless (or (chain-store-transaction-location store hash)
                (engine-payload-store-pooled-transaction store hash))
      (admit-new-transaction
       transaction sender store config policy admitted-at))
    hash))
