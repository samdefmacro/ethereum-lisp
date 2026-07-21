(in-package #:ethereum-lisp.rpc-http)

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
         (rpc-http-handle-stream
          input-stream
          output-stream
          (engine-rpc-http-service-rpc-context service)
          :jwt-secret (engine-rpc-http-service-jwt-secret service)
          :now (funcall (engine-rpc-http-service-now-provider service))
          :rpc-prefix (engine-rpc-http-service-rpc-prefix service)
          :cors-origins (engine-rpc-http-service-cors-origins service)
          :allowed-hosts (engine-rpc-http-service-allowed-hosts service)
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

(defun engine-rpc-http-serve-connection (service connection sink fields)
  "Serve CONNECTION to completion, containing any fault to that connection.

A peer that disappears mid-response signals on the socket write. That must end
the connection, not the listener: an escaping error unwinds the accept loop and
the supervising node treats it as a shutdown request."
  (handler-case
      (unwind-protect
           ;; The deadline covers reading the request and writing the response,
           ;; so a peer that stalls at any point cannot hold its worker.
           (engine-rpc-http-with-request-deadline
             (engine-rpc-http-service-handle-stream
              service
              (engine-rpc-http-connection-input-stream connection)
              (engine-rpc-http-connection-output-stream connection)))
        (ignore-errors
         (engine-rpc-http-connection-close connection)))
    (error (condition)
      (ethereum-lisp.telemetry:telemetry-log
       :warn
       "engine.rpc.http.connection.error"
       :sink sink
       :fields (append fields
                       (list (cons "error" (format nil "~A" condition))))))))

(defun engine-rpc-http-drain-connection-workers (semaphore limit)
  "Wait for in-flight connection workers to finish.

Reacquiring every permit proves no worker still holds one, which avoids keeping
a thread list that would grow for the lifetime of the listener."
  #+sbcl
  (when semaphore
    (dotimes (index limit)
      (declare (ignore index))
      (sb-thread:wait-on-semaphore semaphore :timeout 5)))
  #-sbcl
  (declare (ignore semaphore limit)))

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
    (block-validation-fail
     "Engine RPC HTTP max connections must be non-negative"))
  (let* ((served 0)
        (stop-p (or stop-p (lambda () nil)))
        (concurrency
          (let ((limit *engine-rpc-http-max-concurrent-connections*))
            (and limit (integerp limit) (plusp limit) limit)))
        (worker-slots
          #+sbcl (when concurrency
                   (sb-thread:make-semaphore :count concurrency
                                             :name "ethereum-lisp-rpc-http"))
          #-sbcl nil)
        (sink (engine-rpc-http-service-telemetry-sink service))
        (fields `(("endpoint" . ,(engine-rpc-http-listener-endpoint listener))
                  ("host" . ,(engine-rpc-http-service-host service))
                  ("port" . ,(engine-rpc-http-service-port service)))))
    (unless (functionp stop-p)
      (block-validation-fail
       "Engine RPC HTTP stop predicate must be a function"))
    (ethereum-lisp.telemetry:telemetry-log
     :info
     "engine.rpc.http.listener.start"
     :sink sink
     :fields fields)
    (unwind-protect
         (loop until (or (and max-connections (>= served max-connections))
                         (funcall stop-p))
               for connection = (handler-case
                                    (engine-rpc-http-listener-accept listener)
                                  (error (condition)
                                    (if (funcall stop-p)
                                        nil
                                        (error condition))))
               while connection
               do (if worker-slots
                      (progn
                        ;; Block until a worker slot frees, so an unbounded
                        ;; number of peers cannot spawn unbounded threads.
                        #+sbcl (sb-thread:wait-on-semaphore worker-slots)
                        #+sbcl
                        (sb-thread:make-thread
                         (let ((connection connection))
                           (lambda ()
                             (unwind-protect
                                  (engine-rpc-http-serve-connection
                                   service connection sink fields)
                               (sb-thread:signal-semaphore worker-slots))))
                         :name "ethereum-lisp-rpc-http-connection"))
                      (engine-rpc-http-serve-connection
                       service connection sink fields))
                  (incf served))
      ;; Let in-flight workers finish before the listener is torn down.
      (engine-rpc-http-drain-connection-workers worker-slots concurrency)
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
