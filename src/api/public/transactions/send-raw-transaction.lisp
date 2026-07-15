(in-package #:ethereum-lisp.public-api)

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
    (invalid-parameters-fail
     "eth_sendRawTransaction params must contain exactly one transaction"))
  (let* ((raw-bytes
            (json-rpc-bytes
             (first params)
             "eth_sendRawTransaction transaction"))
         (transaction (transaction-from-encoding raw-bytes))
         (policy
           (make-txpool-admission-policy
            :allow-unprotected-transactions-p allow-unprotected-transactions-p
            :price-limit txpool-price-limit
            :price-bump-percent txpool-price-bump-percent
            :account-slot-limit txpool-account-slot-limit
            :global-slot-limit txpool-global-slot-limit
            :account-queue-limit txpool-account-queue-limit
            :global-queue-limit txpool-global-queue-limit
            :local-addresses txpool-local-addresses
            :no-local-exemptions-p txpool-no-local-exemptions-p)))
    (hash32-to-hex
     (txpool-admit-transaction
      transaction store config policy :admitted-at txpool-now))))
