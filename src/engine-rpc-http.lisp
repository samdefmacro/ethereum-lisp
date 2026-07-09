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
                 (genesis-object-field request "id")))
        (notification-p (engine-rpc-notification-request-p request)))
    (handler-case
        (let ((response
                (progn
                  (unless (listp request)
                    (block-validation-fail
                     "JSON-RPC request must be an object"))
                  (unless (engine-rpc-request-envelope-valid-p request)
                    (return-from engine-rpc-handle-request
                      (engine-rpc-invalid-request-response)))
                  (let* ((method (engine-rpc-required-field request "method"))
                         (params
                           (if (genesis-object-field-present-p request
                                                               "params")
                               (json-array-values
                                (genesis-object-field request "params"))
                               '())))
                    (unless (functionp allowed-method-p)
                      (block-validation-fail
                       "JSON-RPC method filter must be a function"))
                    (if (not (funcall allowed-method-p method))
                        (engine-rpc-response
                         id
                         :error
                         (engine-rpc-error-object -32601 "Method not found"))
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
                         (engine-rpc-response
                          id
                          :error
                          (engine-rpc-error-object
                           -32601 "Method not found"))))))))
          (unless notification-p
            response))
      (engine-rpc-error (condition)
        (unless notification-p
          (engine-rpc-response
           id
           :error
           (engine-rpc-error-object
            (engine-rpc-error-code condition)
            (engine-rpc-error-message condition)))))
      (block-validation-error (condition)
        (unless notification-p
          (engine-rpc-response
           id
           :error
           (engine-rpc-error-object
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
                              (engine-rpc-invalid-request-response))
           when response
             collect response))
    (t (engine-rpc-invalid-request-response))))

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
                (engine-rpc-parse-error-response))))))
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

(defun engine-rpc-handle-http-request-string
    (request store config &key jwt-secret now import-function
                               network-id
                               coinbase
                               (rpc-prefix "/")
                               (allowed-method-p #'engine-rpc-any-method-p)
                               cors-origins
                               allowed-hosts
                               allow-unprotected-transactions-p
                               txpool-price-limit
                               txpool-price-bump-percent
                               txpool-account-slot-limit
                               txpool-global-slot-limit
                               txpool-account-queue-limit
                               txpool-global-queue-limit
                               txpool-local-addresses
                               txpool-no-local-exemptions-p
                               txpool-lifetime-seconds)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary request)
        (let* ((head (subseq request 0 boundary))
               (body (subseq request (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (unless lines
            (block-validation-fail "HTTP request is empty"))
          (multiple-value-bind (method target)
              (engine-rpc-http-request-target (first lines))
            (let ((headers (engine-rpc-http-headers (rest lines))))
              (multiple-value-bind (cors-headers cors-origin-allowed-p)
                  (engine-rpc-http-cors-response-headers
                   headers
                   cors-origins)
                (unless cors-origin-allowed-p
                  (return-from engine-rpc-handle-http-request-string
                    (engine-rpc-http-error-response
                     403 "Forbidden" "origin is not allowed")))
                (unless (engine-rpc-http-host-allowed-p
                         headers
                         allowed-hosts)
                  (return-from engine-rpc-handle-http-request-string
                    (engine-rpc-http-error-response
                     403 "Forbidden" "host is not allowed"
                     :extra-headers cors-headers)))
                (unless (engine-rpc-http-target-allowed-p target rpc-prefix)
                  (return-from engine-rpc-handle-http-request-string
                    (engine-rpc-http-error-response
                     404 "Not Found" "not found"
                     :extra-headers cors-headers)))
                (when (string= method "OPTIONS")
                  (return-from engine-rpc-handle-http-request-string
                    (engine-rpc-http-response-string
                     204 "No Content" ""
                     :content-type nil
                     :extra-headers cors-headers)))
                (when jwt-secret
                  (handler-case
                      (engine-rpc-http-authorized-p
                       (engine-rpc-http-single-header headers "authorization")
                       jwt-secret
                       (or now 0))
                    (block-validation-error (condition)
                      (return-from engine-rpc-handle-http-request-string
                        (engine-rpc-http-error-response
                         401 "Unauthorized"
                         (block-validation-error-message condition)
                         :extra-headers cors-headers)))))
                (cond
                  ((and (string= method "GET") (string= body ""))
                   (engine-rpc-http-response-string
                    200 "OK" "" :content-type nil
                    :extra-headers cors-headers))
                  ((not (string= method "POST"))
                   (engine-rpc-http-error-response
                    405 "Method Not Allowed" "method not allowed"
                    :extra-headers cors-headers))
                  ((not (engine-rpc-http-accepted-content-type-p
                         (engine-rpc-http-header headers "content-type")))
                   (engine-rpc-http-error-response
                    415 "Unsupported Media Type"
                    "invalid content type, only application/json is supported"
                    :extra-headers cors-headers))
                  (t
                   (engine-rpc-http-response-string
                    200 "OK"
                    (engine-rpc-handle-request-json
                     (engine-rpc-http-body body headers)
                     store
                     config
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
                     :txpool-now (or now 0))
                    :extra-headers cors-headers))))))))
    (error (condition)
      (engine-rpc-http-error-response
       400 "Bad Request"
       (format nil "~A" condition)))))

(defun engine-rpc-handle-http-stream
    (input-stream output-stream store config
     &key jwt-secret now import-function
          network-id
          coinbase
          (rpc-prefix "/")
          (allowed-method-p #'engine-rpc-any-method-p)
          cors-origins
          allowed-hosts
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
          telemetry-sink telemetry-fields)
  (let* ((request nil)
         (response
          (handler-case
              (progn
                (setf request (engine-rpc-read-http-request-string input-stream))
                (engine-rpc-handle-http-request-string
                 request
                 store
                 config
                 :jwt-secret jwt-secret
                 :now now
                 :import-function import-function
                 :network-id network-id
                 :coinbase coinbase
                 :rpc-prefix rpc-prefix
                 :allowed-method-p allowed-method-p
                 :cors-origins cors-origins
                 :allowed-hosts allowed-hosts
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
                 :txpool-lifetime-seconds txpool-lifetime-seconds))
            (error (condition)
              (engine-rpc-http-error-response
               400 "Bad Request"
               (format nil "~A" condition)))))
         (status-code (engine-rpc-http-response-status-code response)))
    (ethereum-lisp.telemetry:telemetry-log
     :info
     "engine.rpc.http.request"
     :sink telemetry-sink
     :fields
     (append telemetry-fields
             (and request
                  (engine-rpc-http-request-telemetry-fields request))
             (when status-code
               (list (cons "status" (format nil "~D" status-code))))
             (engine-rpc-http-response-telemetry-fields response)))
    (write-string response output-stream)
    response))
