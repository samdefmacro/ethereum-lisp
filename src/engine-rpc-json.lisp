(in-package #:ethereum-lisp.core)

(defun engine-rpc-handle-request-string
    (request-json store config &key import-function
                                  network-id
                                  coinbase
                                  (allowed-method-p #'engine-rpc-any-method-p)
                                  allow-unprotected-transactions-p
                                  txpool-price-limit
                                  txpool-price-bump-percent
                                  txpool-account-slot-limit
                                  txpool-global-slot-limit
                                  txpool-account-queue-limit
                                  txpool-global-queue-limit
                                  txpool-local-addresses
                                  txpool-no-local-exemptions-p
                                  txpool-lifetime-seconds
                                  txpool-now)
  (let ((request
          (handler-case
              (parse-json request-json :preserve-empty-arrays t)
            (block-validation-error ()
              (return-from engine-rpc-handle-request-string
                (json-rpc-parse-error-response))))))
    (engine-rpc-handle-request-value
     request
     store
     config
     :import-function import-function
     :network-id network-id
     :coinbase coinbase
     :allowed-method-p allowed-method-p
     :allow-unprotected-transactions-p allow-unprotected-transactions-p
     :txpool-price-limit txpool-price-limit
     :txpool-price-bump-percent txpool-price-bump-percent
     :txpool-account-slot-limit txpool-account-slot-limit
     :txpool-global-slot-limit txpool-global-slot-limit
     :txpool-account-queue-limit txpool-account-queue-limit
     :txpool-global-queue-limit txpool-global-queue-limit
     :txpool-local-addresses txpool-local-addresses
     :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
     :txpool-lifetime-seconds txpool-lifetime-seconds
     :txpool-now txpool-now)))

(defun engine-rpc-handle-request-json
    (request-json store config &key import-function
                                  network-id
                                  coinbase
                                  (allowed-method-p #'engine-rpc-any-method-p)
                                  allow-unprotected-transactions-p
                                  txpool-price-limit
                                  txpool-price-bump-percent
                                  txpool-account-slot-limit
                                  txpool-global-slot-limit
                                  txpool-account-queue-limit
                                  txpool-global-queue-limit
                                  txpool-local-addresses
                                  txpool-no-local-exemptions-p
                                  txpool-lifetime-seconds
                                  txpool-now)
  (let ((response
          (engine-rpc-handle-request-string
           request-json store config
           :import-function import-function
           :network-id network-id
           :coinbase coinbase
           :allowed-method-p allowed-method-p
           :allow-unprotected-transactions-p
           allow-unprotected-transactions-p
           :txpool-price-limit txpool-price-limit
           :txpool-price-bump-percent txpool-price-bump-percent
           :txpool-account-slot-limit txpool-account-slot-limit
           :txpool-global-slot-limit txpool-global-slot-limit
           :txpool-account-queue-limit txpool-account-queue-limit
           :txpool-global-queue-limit txpool-global-queue-limit
           :txpool-local-addresses txpool-local-addresses
           :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
           :txpool-lifetime-seconds txpool-lifetime-seconds
           :txpool-now txpool-now)))
    (if response
        (json-encode response)
        "")))
