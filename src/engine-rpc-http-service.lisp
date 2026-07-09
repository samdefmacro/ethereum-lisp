(in-package #:ethereum-lisp.core)

(defun engine-rpc-http-service-serve-listener
    (service listener &key max-connections stop-p)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (unless (or (null max-connections)
              (and (integerp max-connections) (<= 0 max-connections)))
    (block-validation-fail "Engine RPC HTTP max connections must be non-negative"))
  (let ((served 0)
        (stop-p (or stop-p (lambda () nil)))
        (sink (engine-rpc-http-service-telemetry-sink service))
        (fields `(("endpoint" . ,(engine-rpc-http-listener-endpoint listener))
                  ("host" . ,(engine-rpc-http-service-host service))
                  ("port" . ,(engine-rpc-http-service-port service)))))
    (unless (functionp stop-p)
      (block-validation-fail "Engine RPC HTTP stop predicate must be a function"))
    (ethereum-lisp.telemetry:telemetry-log
     :info
     "engine.rpc.http.listener.start"
     :sink sink
     :fields fields)
    (unwind-protect
         (loop until (or (and max-connections (>= served max-connections))
                         (funcall stop-p))
               for connection = (handler-case
                                    (engine-rpc-http-listener-accept
                                     listener)
                                  (error (condition)
                                    (if (funcall stop-p)
                                        nil
                                        (error condition))))
               while connection
               do (unwind-protect
                       (engine-rpc-http-service-handle-stream
                        service
                        (engine-rpc-http-connection-input-stream connection)
                        (engine-rpc-http-connection-output-stream connection))
                    (engine-rpc-http-connection-close connection))
                  (incf served))
      (ethereum-lisp.telemetry:telemetry-metric
       "engine.rpc.http.listener.connections"
       served
       :sink sink
       :fields fields)
      (ethereum-lisp.telemetry:telemetry-log
       :info
       "engine.rpc.http.listener.finish"
       :sink sink
       :fields fields)
      (engine-rpc-http-listener-close listener))
    served))
