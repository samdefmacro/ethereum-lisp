(in-package #:ethereum-lisp.core)

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
