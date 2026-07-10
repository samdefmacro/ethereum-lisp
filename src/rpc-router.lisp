(in-package #:ethereum-lisp.rpc)

(defstruct (rpc-context
            (:constructor %make-rpc-context
                (&key store config import-function network-id coinbase
                      allowed-method-p allow-unprotected-transactions-p
                      txpool-price-limit txpool-price-bump-percent
                      txpool-account-slot-limit txpool-global-slot-limit
                      txpool-account-queue-limit txpool-global-queue-limit
                      txpool-local-addresses txpool-no-local-exemptions-p
                      txpool-lifetime-seconds txpool-now)))
  store
  config
  import-function
  network-id
  coinbase
  allowed-method-p
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

(defun make-rpc-context
    (store config &key import-function
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
  (unless (functionp allowed-method-p)
    (block-validation-fail "JSON-RPC method filter must be a function"))
  (%make-rpc-context
   :store store
   :config config
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
   :txpool-now txpool-now))

(defun rpc-method-not-found-response (id)
  (json-rpc-response
   id
   :error (json-rpc-error-object -32601 "Method not found")))

(defun rpc-dispatch-public-method (id method params context)
  (engine-rpc-handle-public-method
   id method params
   (rpc-context-store context)
   (rpc-context-config context)
   :network-id (rpc-context-network-id context)
   :coinbase (rpc-context-coinbase context)
   :allowed-method-p (rpc-context-allowed-method-p context)
   :allow-unprotected-transactions-p
   (rpc-context-allow-unprotected-transactions-p context)
   :txpool-price-limit (rpc-context-txpool-price-limit context)
   :txpool-price-bump-percent
   (rpc-context-txpool-price-bump-percent context)
   :txpool-account-slot-limit
   (rpc-context-txpool-account-slot-limit context)
   :txpool-global-slot-limit
   (rpc-context-txpool-global-slot-limit context)
   :txpool-account-queue-limit
   (rpc-context-txpool-account-queue-limit context)
   :txpool-global-queue-limit
   (rpc-context-txpool-global-queue-limit context)
   :txpool-local-addresses (rpc-context-txpool-local-addresses context)
   :txpool-no-local-exemptions-p
   (rpc-context-txpool-no-local-exemptions-p context)
   :txpool-lifetime-seconds
   (rpc-context-txpool-lifetime-seconds context)
   :txpool-now (rpc-context-txpool-now context)))

(defun rpc-dispatch-method (id method params context)
  (if (funcall (rpc-context-allowed-method-p context) method)
      (or (engine-rpc-handle-engine-method
           id method params
           (rpc-context-store context)
           (rpc-context-config context)
           :import-function (rpc-context-import-function context))
          (rpc-dispatch-public-method id method params context)
          (rpc-method-not-found-response id))
      (rpc-method-not-found-response id)))

(defun rpc-handle-request (request context)
  (unless (typep context 'rpc-context)
    (block-validation-fail "JSON-RPC context must be an rpc-context"))
  (let ((id (and (listp request)
                 (json-object-field request "id")))
        (notification-p (json-rpc-notification-p request)))
    (handler-case
        (let ((response
                (cond
                  ((not (listp request))
                   (block-validation-fail
                    "JSON-RPC request must be an object"))
                  ((not (json-rpc-request-valid-p request))
                   (json-rpc-invalid-request-response))
                  (t
                   (let ((method
                           (json-rpc-required-field request "method"))
                         (params
                           (if (json-object-field-present-p request "params")
                               (json-array-values
                                (json-object-field request "params"))
                               '())))
                     (rpc-dispatch-method id method params context))))))
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

(defun rpc-handle-request-value (request context)
  (cond
    ((json-object-p request)
     (rpc-handle-request request context))
    ((and (listp request) request)
     (loop for item in request
           for response = (if (json-object-p item)
                              (rpc-handle-request item context)
                              (json-rpc-invalid-request-response))
           when response
             collect response))
    (t
     (json-rpc-invalid-request-response))))

(defun engine-rpc-handle-request (request store config &rest options)
  (rpc-handle-request
   request
   (apply #'make-rpc-context store config options)))

(defun engine-rpc-handle-request-value (request store config &rest options)
  (rpc-handle-request-value
   request
   (apply #'make-rpc-context store config options)))
