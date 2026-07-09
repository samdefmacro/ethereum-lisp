(in-package #:ethereum-lisp.core)

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
