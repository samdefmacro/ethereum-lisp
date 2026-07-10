(in-package #:ethereum-lisp.core)

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
              store
              :sender sender
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
