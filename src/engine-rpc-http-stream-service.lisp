(in-package #:ethereum-lisp.core)

(defun engine-rpc-http-service-handle-stream
    (service input-stream output-stream)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (let ((sink (engine-rpc-http-service-telemetry-sink service))
        (fields `(("endpoint" . ,(engine-rpc-http-service-endpoint service))
                  ("host" . ,(engine-rpc-http-service-host service))
                  ("port" . ,(engine-rpc-http-service-port service)))))
    (ethereum-lisp.telemetry:telemetry-log
     :debug
     "engine.rpc.http.stream.start"
     :sink sink
     :fields fields)
    (unwind-protect
         (engine-rpc-handle-http-stream
          input-stream
          output-stream
          (engine-rpc-http-service-store service)
          (engine-rpc-http-service-config service)
          :jwt-secret (engine-rpc-http-service-jwt-secret service)
          :now (funcall (engine-rpc-http-service-now-provider service))
          :import-function (engine-rpc-http-service-import-function service)
          :network-id (engine-rpc-http-service-network-id service)
          :coinbase (engine-rpc-http-service-coinbase service)
          :rpc-prefix (engine-rpc-http-service-rpc-prefix service)
          :allowed-method-p
          (engine-rpc-http-service-allowed-method-p service)
          :cors-origins (engine-rpc-http-service-cors-origins service)
          :allowed-hosts (engine-rpc-http-service-allowed-hosts service)
          :allow-unprotected-transactions-p
          (engine-rpc-http-service-allow-unprotected-transactions-p service)
          :txpool-price-limit
          (engine-rpc-http-service-txpool-price-limit service)
          :txpool-price-bump-percent
          (engine-rpc-http-service-txpool-price-bump-percent service)
          :txpool-account-slot-limit
          (engine-rpc-http-service-txpool-account-slot-limit service)
          :txpool-global-slot-limit
          (engine-rpc-http-service-txpool-global-slot-limit service)
          :txpool-account-queue-limit
          (engine-rpc-http-service-txpool-account-queue-limit service)
          :txpool-global-queue-limit
          (engine-rpc-http-service-txpool-global-queue-limit service)
          :txpool-local-addresses
          (engine-rpc-http-service-txpool-local-addresses service)
          :txpool-no-local-exemptions-p
          (engine-rpc-http-service-txpool-no-local-exemptions-p service)
          :txpool-lifetime-seconds
          (engine-rpc-http-service-txpool-lifetime-seconds service)
          :telemetry-sink sink
          :telemetry-fields fields)
      (ethereum-lisp.telemetry:telemetry-metric
       "engine.rpc.http.streams"
       1
       :sink sink
       :fields fields)
      (ethereum-lisp.telemetry:telemetry-log
       :debug
       "engine.rpc.http.stream.finish"
       :sink sink
       :fields fields))))
