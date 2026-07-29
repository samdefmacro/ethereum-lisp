(in-package #:ethereum-lisp.txpool.application)

(defconstant +txpool-legacy-transaction-max-bytes+ (* 128 1024))
(defconstant +txpool-blob-transaction-max-bytes+ (* 1024 1024))
(defconstant +txpool-default-price-limit+ 1)
(defconstant +txpool-default-price-bump-percent+ 10)
(defconstant +txpool-default-account-slot-limit+ 16)
(defconstant +txpool-default-global-slot-limit+ 5120)
(defconstant +txpool-default-account-queue-limit+ 64)
(defconstant +txpool-default-global-queue-limit+ 1024)

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
   :price-limit (if (null price-limit) +txpool-default-price-limit+ price-limit)
   :price-bump-percent
   (if (null price-bump-percent)
       +txpool-default-price-bump-percent+
       price-bump-percent)
   :account-slot-limit
   (if (null account-slot-limit)
       +txpool-default-account-slot-limit+
       account-slot-limit)
   :global-slot-limit
   (if (null global-slot-limit)
       +txpool-default-global-slot-limit+
       global-slot-limit)
   :account-queue-limit
   (if (null account-queue-limit)
       +txpool-default-account-queue-limit+
       account-queue-limit)
   :global-queue-limit
   (if (null global-queue-limit)
       +txpool-default-global-queue-limit+
       global-queue-limit)
   :local-addresses (copy-list local-addresses)
   :no-local-exemptions-p no-local-exemptions-p))

(defun validate-txpool-encoded-size (transaction)
  (let ((limit (if (typep transaction 'blob-transaction)
                   +txpool-blob-transaction-max-bytes+
                   +txpool-legacy-transaction-max-bytes+)))
    (when (> (length (transaction-encoding transaction)) limit)
      (block-validation-fail
       "eth_sendRawTransaction encoded transaction exceeds ~D bytes"
       limit)))
  t)

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

(defun txpool-set-code-authorities (transaction)
  (when (typep transaction 'set-code-transaction)
    (remove nil
            (mapcar #'set-code-authorization-authority
                    (transaction-authorization-list transaction)))))

(defun txpool-address= (left right)
  (and left right
       (bytes= (address-bytes left) (address-bytes right))))

(defun txpool-authority-reserved-p (store authority)
  (some
   (lambda (pooled)
     (some (lambda (reserved)
             (txpool-address= authority reserved))
           (txpool-set-code-authorities pooled)))
   (engine-payload-store-pooled-transactions store)))

(defun validate-txpool-delegation-reservations
    (store sender transaction config)
  (declare (ignore config))
  (multiple-value-bind (head block-number timestamp)
      (txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let ((sender-code
              (chain-store-account-code store (block-hash head) sender)))
        (when (set-code-delegation-target sender-code)
          (when (engine-payload-store-sender-pooled-transactions store sender)
            (block-validation-fail
             "eth_sendRawTransaction delegated account already has an in-flight transaction"))
          (unless (= (transaction-nonce transaction)
                     (chain-store-account-nonce
                      store (block-hash head) sender))
            (block-validation-fail
             "eth_sendRawTransaction delegated account nonce must be current")))))
    (when (txpool-authority-reserved-p store sender)
      (block-validation-fail
       "eth_sendRawTransaction sender is reserved by a pending set-code authorization"))
    (dolist (authority (txpool-set-code-authorities transaction))
      (when (or (engine-payload-store-sender-pooled-transactions
                 store authority)
                (txpool-authority-reserved-p store authority))
        (block-validation-fail
         "eth_sendRawTransaction set-code authority already has an in-flight transaction"))))
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
        (validate-blob-transaction-fields
         transaction
         :max-blobs (chain-rules-max-blobs-per-transaction rules)))
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
      (handler-case
          (ethereum-lisp.execution:validate-contract-initcode-size
           transaction rules)
        (ethereum-lisp.execution:transaction-validation-error (condition)
          (block-validation-fail
           "eth_sendRawTransaction ~A"
           (ethereum-lisp.execution:transaction-validation-error-message
            condition))))
      (let ((floor-gas
              (ethereum-lisp.execution:transaction-effective-floor-gas
               transaction rules)))
        (when (< (transaction-gas-limit transaction) floor-gas)
          (block-validation-fail
           "eth_sendRawTransaction gas limit below EIP-7623 floor data gas")))
      (when (and head
                 (> (transaction-gas-limit transaction)
                    (block-header-gas-limit (block-header head))))
        (block-validation-fail
         "eth_sendRawTransaction gas limit exceeds block gas limit"))
      (when (and rules
                 (chain-rules-osaka-p rules)
                 (> (transaction-gas-limit transaction)
                    +transaction-gas-limit-cap-eip7825+))
        (block-validation-fail
         "eth_sendRawTransaction gas limit exceeds the EIP-7825 cap"))
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
               (< (transaction-max-priority-fee-per-gas transaction)
                  price-limit))
      (block-validation-fail
       "eth_sendRawTransaction priority fee below txpool price limit")))
  t)

(defun admit-new-transaction
    (transaction sender store config policy admitted-at)
  (let ((local-transaction-p
          (txpool-local-transaction-p sender policy))
        (price-bump
          (txpool-admission-policy-price-bump-percent policy))
        (local-predicate
          (txpool-local-transaction-predicate config policy)))
    (validate-admission-policy transaction local-transaction-p policy)
    (validate-txpool-admission transaction sender store config)
    (engine-payload-store-configure-txpool-promotion-policy
     store
     (txpool-admission-policy-account-slot-limit policy)
     (txpool-admission-policy-global-slot-limit policy)
     local-predicate)
    (cond
      ((typep transaction 'blob-transaction)
       (engine-payload-store-put-blob-transaction
        store transaction :price-bump-percent price-bump
                          :global-slot-limit
                          (unless local-transaction-p
                            (txpool-admission-policy-global-slot-limit policy))
                          :admitted-at admitted-at))
      ((txpool-basefee-ineligible-p store transaction)
       (engine-payload-store-put-basefee-transaction
        store transaction :price-bump-percent price-bump
                          :global-slot-limit
                          (unless local-transaction-p
                            (txpool-admission-policy-global-slot-limit policy))
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
        :local-transaction-predicate local-predicate)))))

(defun txpool-admit-transaction
    (transaction store config policy &key admitted-at)
  (validate-txpool-encoded-size transaction)
  (when (typep transaction 'blob-transaction)
    (block-validation-fail
     "eth_sendRawTransaction blob sidecars and KZG admission are not supported"))
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
      (validate-txpool-delegation-reservations
       store sender transaction config)
      (admit-new-transaction
       transaction sender store config policy admitted-at))
    hash))
