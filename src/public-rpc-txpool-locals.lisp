(in-package #:ethereum-lisp.core)

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
