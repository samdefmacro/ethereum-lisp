(in-package #:ethereum-lisp.core)

(defparameter +engine-rpc-default-http-host+ "localhost")
(defconstant +engine-rpc-default-http-port+ 8551)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defstruct (engine-rpc-http-service
            (:constructor %make-engine-rpc-http-service
                (&key host port store config jwt-secret now-provider
                      import-function telemetry-sink allowed-method-p
                      network-id coinbase rpc-prefix cors-origins
                      allowed-hosts allow-unprotected-transactions-p
                      txpool-price-limit txpool-price-bump-percent
                      txpool-account-slot-limit
                      txpool-global-slot-limit
                      txpool-account-queue-limit
                      txpool-global-queue-limit
                      txpool-local-addresses txpool-no-local-exemptions-p
                      txpool-lifetime-seconds)))
  host
  port
  store
  config
  jwt-secret
  now-provider
  import-function
  telemetry-sink
  allowed-method-p
  network-id
  coinbase
  rpc-prefix
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

(defstruct (engine-rpc-http-connection
            (:constructor %make-engine-rpc-http-connection
                (&key input-stream output-stream close-function)))
  input-stream
  output-stream
  close-function)

(defstruct (engine-rpc-http-listener
            (:constructor %make-engine-rpc-http-listener
                (&key endpoint accept-function close-function)))
  endpoint
  accept-function
  close-function)

(defun engine-rpc-default-import-function ()
  (let* ((package (find-package "ETHEREUM-LISP.EXECUTION"))
         (symbol (and package
                      (find-symbol "EXECUTE-AND-COMMIT-ENGINE-PAYLOAD"
                                   package))))
    (when (and symbol (fboundp symbol))
      (symbol-function symbol))))

(defun make-engine-rpc-http-service
    (&key
       (host +engine-rpc-default-http-host+)
       (port +engine-rpc-default-http-port+)
       (store (make-engine-payload-memory-store))
       (config (make-chain-config))
       jwt-secret
       (now-provider (lambda () 0))
       (import-function (engine-rpc-default-import-function))
       (allowed-method-p #'engine-rpc-any-method-p)
       network-id
       (coinbase (zero-address))
       (rpc-prefix "/")
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
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*))
  (unless (stringp host)
    (block-validation-fail "Engine RPC HTTP host must be a string"))
  (unless (and (integerp port) (<= 0 port 65535))
    (block-validation-fail "Engine RPC HTTP port must be between 0 and 65535"))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail
     "Engine RPC HTTP store must be engine-payload-memory-store"))
  (unless (typep config 'chain-config)
    (block-validation-fail "Engine RPC HTTP config must be chain-config"))
  (when (and jwt-secret
             (not (and (byte-vector-p jwt-secret)
                       (= 32 (length jwt-secret)))))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (unless (functionp now-provider)
    (block-validation-fail "Engine RPC HTTP now provider must be a function"))
  (when (and import-function
             (not (functionp import-function)))
    (block-validation-fail "Engine RPC HTTP import function must be a function"))
  (unless (functionp allowed-method-p)
    (block-validation-fail "Engine RPC HTTP method filter must be a function"))
  (when (and network-id
             (not (and (integerp network-id) (not (minusp network-id)))))
    (block-validation-fail
     "Engine RPC HTTP network id must be a non-negative integer"))
  (unless (typep coinbase 'address)
    (block-validation-fail "Engine RPC HTTP coinbase must be an address"))
  (unless (and (stringp rpc-prefix)
               (plusp (length rpc-prefix))
               (char= #\/ (char rpc-prefix 0)))
    (block-validation-fail "Engine RPC HTTP prefix must start with /"))
  (when (and cors-origins
             (not (and (listp cors-origins)
                       (every #'stringp cors-origins))))
    (block-validation-fail
     "Engine RPC HTTP CORS origins must be a string list"))
  (when (and allowed-hosts
             (not (and (listp allowed-hosts)
                       (every #'stringp allowed-hosts))))
    (block-validation-fail
     "Engine RPC HTTP allowed hosts must be a string list"))
  (when (and txpool-price-limit
             (not (and (integerp txpool-price-limit)
                       (not (minusp txpool-price-limit)))))
    (block-validation-fail
     "Engine RPC HTTP txpool price limit must be a non-negative integer"))
  (when (and txpool-price-bump-percent
             (not (and (integerp txpool-price-bump-percent)
                       (not (minusp txpool-price-bump-percent)))))
    (block-validation-fail
     "Engine RPC HTTP txpool price bump must be a non-negative integer"))
  (when (and txpool-account-slot-limit
             (not (and (integerp txpool-account-slot-limit)
                       (not (minusp txpool-account-slot-limit)))))
    (block-validation-fail
     "Engine RPC HTTP txpool account slot limit must be a non-negative integer"))
  (when (and txpool-global-slot-limit
             (not (and (integerp txpool-global-slot-limit)
                       (not (minusp txpool-global-slot-limit)))))
    (block-validation-fail
     "Engine RPC HTTP txpool global slot limit must be a non-negative integer"))
  (when (and txpool-account-queue-limit
             (not (and (integerp txpool-account-queue-limit)
                       (not (minusp txpool-account-queue-limit)))))
    (block-validation-fail
     "Engine RPC HTTP txpool account queue limit must be a non-negative integer"))
  (when (and txpool-global-queue-limit
             (not (and (integerp txpool-global-queue-limit)
                       (not (minusp txpool-global-queue-limit)))))
    (block-validation-fail
     "Engine RPC HTTP txpool global queue limit must be a non-negative integer"))
  (when (and txpool-lifetime-seconds
             (not (and (integerp txpool-lifetime-seconds)
                       (not (minusp txpool-lifetime-seconds)))))
    (block-validation-fail
     "Engine RPC HTTP txpool lifetime must be a non-negative integer"))
  (when (and txpool-local-addresses
             (not (and (listp txpool-local-addresses)
                       (every (lambda (address)
                                (typep address 'address))
                              txpool-local-addresses))))
    (block-validation-fail
     "Engine RPC HTTP txpool local addresses must be an address list"))
  (%make-engine-rpc-http-service
   :host host
   :port port
   :store store
   :config config
   :jwt-secret jwt-secret
   :now-provider now-provider
   :import-function import-function
   :telemetry-sink telemetry-sink
   :allowed-method-p allowed-method-p
   :network-id network-id
   :coinbase coinbase
   :rpc-prefix rpc-prefix
   :cors-origins cors-origins
   :allowed-hosts allowed-hosts
   :allow-unprotected-transactions-p allow-unprotected-transactions-p
   :txpool-price-limit txpool-price-limit
   :txpool-price-bump-percent txpool-price-bump-percent
   :txpool-account-slot-limit txpool-account-slot-limit
   :txpool-global-slot-limit txpool-global-slot-limit
   :txpool-account-queue-limit txpool-account-queue-limit
   :txpool-global-queue-limit txpool-global-queue-limit
   :txpool-local-addresses txpool-local-addresses
   :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
   :txpool-lifetime-seconds txpool-lifetime-seconds))

(defun engine-rpc-http-service-endpoint (service)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (format nil "~A:~D"
          (engine-rpc-http-service-host service)
          (engine-rpc-http-service-port service)))

(defun make-engine-rpc-http-connection
    (&key input-stream output-stream (close-function (lambda () nil)))
  (unless (input-stream-p input-stream)
    (block-validation-fail
     "Engine RPC HTTP connection input stream must be readable"))
  (unless (output-stream-p output-stream)
    (block-validation-fail
     "Engine RPC HTTP connection output stream must be writable"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP connection close function must be a function"))
  (%make-engine-rpc-http-connection
   :input-stream input-stream
   :output-stream output-stream
   :close-function close-function))

(defun make-engine-rpc-http-listener
    (&key endpoint accept-function (close-function (lambda () nil)))
  (unless (stringp endpoint)
    (block-validation-fail "Engine RPC HTTP listener endpoint must be a string"))
  (unless (functionp accept-function)
    (block-validation-fail
     "Engine RPC HTTP listener accept function must be a function"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP listener close function must be a function"))
  (%make-engine-rpc-http-listener
   :endpoint endpoint
   :accept-function accept-function
   :close-function close-function))

(defun engine-rpc-http-socket-host (host)
  (if (string= host "localhost")
      "127.0.0.1"
      host))

(defun engine-rpc-http-socket-endpoint-host (host)
  (if (string= host "0.0.0.0")
      "127.0.0.1"
      host))

(defun make-engine-rpc-http-socket-listener
    (service &key (backlog 16))
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (and (integerp backlog) (plusp backlog))
    (block-validation-fail "Engine RPC HTTP socket backlog must be positive"))
  #-sbcl
  (declare (ignore service backlog))
  #-sbcl
  (block-validation-fail
   "Engine RPC HTTP socket listener requires SBCL sb-bsd-sockets")
  #+sbcl
  (let* ((host (engine-rpc-http-socket-host
                (engine-rpc-http-service-host service)))
         (socket (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream
                                :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind
           socket
           (sb-bsd-sockets:make-inet-address host)
           (engine-rpc-http-service-port service))
          (sb-bsd-sockets:socket-listen socket backlog)
          (multiple-value-bind (address port)
              (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (make-engine-rpc-http-listener
             :endpoint (format nil "~A:~D"
                               (engine-rpc-http-socket-endpoint-host host)
                               port)
             :accept-function
             (lambda ()
               (multiple-value-bind (client-socket peer-address peer-port)
                   (sb-bsd-sockets:socket-accept socket)
                 (declare (ignore peer-address peer-port))
                 (let ((stream
                         (sb-bsd-sockets:socket-make-stream
                          client-socket
                          :input t
                          :output t
                          :element-type 'character
                          :external-format :utf-8
                          :buffering :none)))
                   (make-engine-rpc-http-connection
                    :input-stream stream
                    :output-stream stream
                    :close-function (lambda () (close stream))))))
             :close-function
             (lambda ()
               (sb-bsd-sockets:socket-close socket)))))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

(defun engine-rpc-http-listener-accept (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (let ((connection
          (funcall (engine-rpc-http-listener-accept-function listener))))
    (when connection
      (unless (typep connection 'engine-rpc-http-connection)
        (block-validation-fail
         "Engine RPC HTTP listener accept function returned non-connection")))
    connection))

(defun engine-rpc-http-connection-close (connection)
  (unless (typep connection 'engine-rpc-http-connection)
    (block-validation-fail
     "Engine RPC HTTP connection must be engine-rpc-http-connection"))
  (funcall (engine-rpc-http-connection-close-function connection)))

(defun engine-rpc-http-listener-close (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (funcall (engine-rpc-http-listener-close-function listener)))

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
