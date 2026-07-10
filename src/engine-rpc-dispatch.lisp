(in-package #:ethereum-lisp.core)

(defun engine-rpc-handle-request
    (request store config &key import-function
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
  (let ((id (and (listp request)
                 (json-object-field request "id")))
        (notification-p (json-rpc-notification-p request)))
    (handler-case
        (let ((response
                (progn
                  (unless (listp request)
                    (block-validation-fail
                     "JSON-RPC request must be an object"))
                  (unless (json-rpc-request-valid-p request)
                    (return-from engine-rpc-handle-request
                      (json-rpc-invalid-request-response)))
                  (let* ((method (engine-rpc-required-field request "method"))
                         (params
                           (if (json-object-field-present-p request
                                                               "params")
                               (json-array-values
                                (json-object-field request "params"))
                               '())))
                    (unless (functionp allowed-method-p)
                      (block-validation-fail
                       "JSON-RPC method filter must be a function"))
                    (if (not (funcall allowed-method-p method))
                        (json-rpc-response
                         id
                         :error
                         (json-rpc-error-object -32601 "Method not found"))
                        (or
                         (engine-rpc-handle-engine-method
                          id method params store config
                          :import-function import-function)
                         (engine-rpc-handle-public-method
                          id method params store config
                          :network-id network-id
                          :coinbase coinbase
                          :allowed-method-p allowed-method-p
                          :allow-unprotected-transactions-p
                          allow-unprotected-transactions-p
                          :txpool-price-limit txpool-price-limit
                          :txpool-price-bump-percent
                          txpool-price-bump-percent
                          :txpool-account-slot-limit
                          txpool-account-slot-limit
                          :txpool-global-slot-limit
                          txpool-global-slot-limit
                          :txpool-account-queue-limit
                          txpool-account-queue-limit
                          :txpool-global-queue-limit
                          txpool-global-queue-limit
                          :txpool-local-addresses
                          txpool-local-addresses
                          :txpool-no-local-exemptions-p
                          txpool-no-local-exemptions-p
                          :txpool-lifetime-seconds
                          txpool-lifetime-seconds
                          :txpool-now
                          txpool-now)
                         (json-rpc-response
                          id
                          :error
                          (json-rpc-error-object
                           -32601 "Method not found"))))))))
          (unless notification-p
            response))
      (engine-rpc-error (condition)
        (unless notification-p
          (json-rpc-response
           id
           :error
           (json-rpc-error-object
            (engine-rpc-error-code condition)
            (engine-rpc-error-message condition)))))
      (block-validation-error (condition)
        (unless notification-p
          (json-rpc-response
           id
           :error
           (json-rpc-error-object
            -32602
            (block-validation-error-message condition))))))))

(defun engine-rpc-handle-request-value
    (request store config &key import-function
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
  (cond
    ((json-object-p request)
     (engine-rpc-handle-request request store config
                                :import-function import-function
                                :network-id network-id
                                :coinbase coinbase
                                :allowed-method-p allowed-method-p
                                :allow-unprotected-transactions-p
                                allow-unprotected-transactions-p
                                :txpool-price-limit txpool-price-limit
                                :txpool-price-bump-percent
                                txpool-price-bump-percent
                                :txpool-account-slot-limit
                                txpool-account-slot-limit
                                :txpool-global-slot-limit
                                txpool-global-slot-limit
                                :txpool-account-queue-limit
                                txpool-account-queue-limit
                                :txpool-global-queue-limit
                                txpool-global-queue-limit
                                :txpool-local-addresses
                                txpool-local-addresses
                                :txpool-no-local-exemptions-p
                                txpool-no-local-exemptions-p
                                :txpool-lifetime-seconds
                                txpool-lifetime-seconds
                                :txpool-now
                                txpool-now))
    ((and (listp request) request)
     (loop for item in request
           for response = (if (json-object-p item)
                              (engine-rpc-handle-request
                               item store config
                               :import-function import-function
                               :network-id network-id
                               :coinbase coinbase
                               :allowed-method-p allowed-method-p
                               :allow-unprotected-transactions-p
                               allow-unprotected-transactions-p
                               :txpool-price-limit txpool-price-limit
                               :txpool-price-bump-percent
                               txpool-price-bump-percent
                               :txpool-account-slot-limit
                               txpool-account-slot-limit
                               :txpool-global-slot-limit
                               txpool-global-slot-limit
                               :txpool-account-queue-limit
                               txpool-account-queue-limit
                               :txpool-global-queue-limit
                               txpool-global-queue-limit
                               :txpool-local-addresses
                               txpool-local-addresses
                               :txpool-no-local-exemptions-p
                               txpool-no-local-exemptions-p
                               :txpool-lifetime-seconds
                               txpool-lifetime-seconds
                               :txpool-now
                               txpool-now)
                              (json-rpc-invalid-request-response))
           when response
             collect response))
    (t (json-rpc-invalid-request-response))))
