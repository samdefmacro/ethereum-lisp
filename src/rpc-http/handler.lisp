(in-package #:ethereum-lisp.rpc-http)

(defun rpc-http-handle-request
    (request context &key jwt-secret now
                          (rpc-prefix "/")
                          cors-origins
                          allowed-hosts)
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
                  (engine-rpc-http-cors-response-headers headers cors-origins)
                (cond
                  ((not cors-origin-allowed-p)
                   (engine-rpc-http-error-response
                    403 "Forbidden" "origin is not allowed"))
                  ((not (engine-rpc-http-host-allowed-p headers allowed-hosts))
                   (engine-rpc-http-error-response
                    403 "Forbidden" "host is not allowed"
                    :extra-headers cors-headers))
                  ((not (engine-rpc-http-target-allowed-p target rpc-prefix))
                   (engine-rpc-http-error-response
                    404 "Not Found" "not found"
                    :extra-headers cors-headers))
                  ((string= method "OPTIONS")
                   (engine-rpc-http-response-string
                    204 "No Content" ""
                    :content-type nil
                    :extra-headers cors-headers))
                  (t
                   (when jwt-secret
                     (handler-case
                         (engine-rpc-http-authorized-p
                          (engine-rpc-http-single-header
                           headers "authorization")
                          jwt-secret
                          (or now 0))
                       (block-validation-error (condition)
                         (return-from rpc-http-handle-request
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
                       (rpc-handle-request-json
                        (engine-rpc-http-body body headers)
                        (rpc-context-with-txpool-now context (or now 0)))
                       :extra-headers cors-headers))))))))))
    (error (condition)
      (engine-rpc-http-error-response
       400 "Bad Request"
       (format nil "~A" condition)))))

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
  (rpc-http-handle-request
   request
   (make-rpc-context
    store config
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
    :txpool-lifetime-seconds txpool-lifetime-seconds)
   :jwt-secret jwt-secret
   :now now
   :rpc-prefix rpc-prefix
   :cors-origins cors-origins
   :allowed-hosts allowed-hosts))

(defun rpc-http-handle-stream
    (input-stream output-stream context
     &key jwt-secret now
          (rpc-prefix "/")
          cors-origins
          allowed-hosts
          telemetry-sink
          telemetry-fields)
  (let* ((request nil)
         (response
           (handler-case
               (progn
                 (setf request
                       (engine-rpc-read-http-request-string input-stream))
                 (rpc-http-handle-request
                  request context
                  :jwt-secret jwt-secret
                  :now now
                  :rpc-prefix rpc-prefix
                  :cors-origins cors-origins
                  :allowed-hosts allowed-hosts))
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
          telemetry-sink
          telemetry-fields)
  (rpc-http-handle-stream
   input-stream
   output-stream
   (make-rpc-context
    store config
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
    :txpool-lifetime-seconds txpool-lifetime-seconds)
   :jwt-secret jwt-secret
   :now now
   :rpc-prefix rpc-prefix
   :cors-origins cors-origins
   :allowed-hosts allowed-hosts
   :telemetry-sink telemetry-sink
   :telemetry-fields telemetry-fields))
