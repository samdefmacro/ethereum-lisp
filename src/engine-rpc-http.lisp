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

(defparameter +engine-rpc-http-accepted-content-types+
  '("application/json" "application/json-rpc" "application/jsonrequest"))

(defparameter +engine-rpc-default-http-host+ "localhost")
(defconstant +engine-rpc-default-http-port+ 8551)

(defconstant +engine-rpc-jwt-expiry-seconds+ 60)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defparameter +engine-rpc-base64url-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

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

(defun engine-rpc-http-trim (string)
  (string-trim '(#\Space #\Tab #\Return #\Newline) string))

(defun engine-rpc-base64url-encode (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (with-output-to-string (stream)
      (loop for index from 0 below (length bytes) by 3
            for remaining = (- (length bytes) index)
            for b0 = (aref bytes index)
            for b1 = (if (>= remaining 2) (aref bytes (1+ index)) 0)
            for b2 = (if (>= remaining 3) (aref bytes (+ index 2)) 0)
            for value = (logior (ash b0 16) (ash b1 8) b2)
            do (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 18) value))
                stream)
               (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 12) value))
                stream)
               (when (>= remaining 2)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 6) value))
                  stream))
               (when (>= remaining 3)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 0) value))
                  stream))))))

(defun engine-rpc-base64url-value (char)
  (let ((position (position char +engine-rpc-base64url-alphabet+)))
    (unless position
      (block-validation-fail "JWT contains invalid base64url data"))
    position))

(defun engine-rpc-base64url-decode (string)
  (when (= (mod (length string) 4) 1)
    (block-validation-fail "JWT contains invalid base64url length"))
  (let ((bytes '())
        (accumulator 0)
        (bits 0))
    (loop for char across string
          for value = (engine-rpc-base64url-value char)
          do (setf accumulator (logior (ash accumulator 6) value)
                   bits (+ bits 6))
             (loop while (>= bits 8)
                   do (decf bits 8)
                      (push (logand #xff (ash accumulator (- bits))) bytes)))
    (ensure-byte-vector (nreverse bytes))))

(defun engine-rpc-hmac-sha256 (key message)
  (let* ((block-size 64)
         (key (ensure-byte-vector key))
         (message (ensure-byte-vector message))
         (short-key (if (> (length key) block-size)
                        (sha256 key)
                        key))
         (padded-key (make-byte-vector block-size)))
    (replace padded-key short-key)
    (let ((inner-pad (make-byte-vector block-size))
          (outer-pad (make-byte-vector block-size)))
      (loop for index below block-size
            for byte = (aref padded-key index)
            do (setf (aref inner-pad index) (logxor byte #x36)
                     (aref outer-pad index) (logxor byte #x5c)))
      (sha256 outer-pad (sha256 inner-pad message)))))

(defun engine-rpc-constant-time-bytes= (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (and (= (length left) (length right))
         (zerop
          (loop for index below (length left)
                for difference = (logxor (aref left index)
                                         (aref right index))
                then (logior difference
                             (logxor (aref left index)
                                     (aref right index)))
                finally (return (or difference 0)))))))

(defun engine-rpc-jwt-signature (secret signing-input)
  (engine-rpc-base64url-encode
   (engine-rpc-hmac-sha256 secret (ascii-to-bytes signing-input))))

(defun engine-rpc-make-jwt-token (secret issued-at &key expires-at)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (let* ((header (engine-rpc-base64url-encode
                  (ascii-to-bytes "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")))
         (payload
           (engine-rpc-base64url-encode
            (ascii-to-bytes
             (if expires-at
                 (format nil "{\"iat\":~D,\"exp\":~D}" issued-at expires-at)
                 (format nil "{\"iat\":~D}" issued-at)))))
         (signing-input (concatenate 'string header "." payload))
         (signature (engine-rpc-jwt-signature secret signing-input)))
    (concatenate 'string signing-input "." signature)))

(defun engine-rpc-token-parts (token)
  (let* ((first-dot (position #\. token))
         (second-dot (and first-dot (position #\. token :start (1+ first-dot)))))
    (unless (and first-dot second-dot
                 (not (position #\. token :start (1+ second-dot))))
      (block-validation-fail "JWT must contain three parts"))
    (values (subseq token 0 first-dot)
            (subseq token (1+ first-dot) second-dot)
            (subseq token (1+ second-dot)))))

(defun engine-rpc-jwt-object (part label)
  (let ((decoded (bytes-to-ascii (engine-rpc-base64url-decode part))))
    (handler-case
        (let ((object (parse-json decoded)))
          (unless (json-object-p object)
            (block-validation-fail "JWT ~A must be a JSON object" label))
          object)
      (error ()
        (block-validation-fail "JWT ~A is not valid JSON" label)))))

(defun engine-rpc-required-jwt-field (object name)
  (unless (genesis-object-field-present-p object name)
    (block-validation-fail "JWT field ~A is missing" name))
  (genesis-object-field object name))

(defun engine-rpc-validate-jwt-token (token secret now)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (multiple-value-bind (header-part payload-part signature-part)
      (engine-rpc-token-parts token)
    (let* ((header (engine-rpc-jwt-object header-part "header"))
           (payload (engine-rpc-jwt-object payload-part "payload"))
           (algorithm (engine-rpc-required-jwt-field header "alg"))
           (issued-at (engine-rpc-required-jwt-field payload "iat"))
           (expires-at (genesis-object-field payload "exp"))
           (signing-input (concatenate 'string header-part "." payload-part))
           (expected-signature
             (engine-rpc-base64url-decode
              (engine-rpc-jwt-signature secret signing-input)))
           (actual-signature
             (engine-rpc-base64url-decode signature-part)))
      (unless (string= algorithm "HS256")
        (block-validation-fail "JWT algorithm must be HS256"))
      (unless (integerp issued-at)
        (block-validation-fail "JWT issued-at must be an integer"))
      (when (and expires-at
                 (or (not (integerp expires-at))
                     (< expires-at now)))
        (block-validation-fail "JWT is expired"))
      (when (> (- now issued-at) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is stale"))
      (when (> (- issued-at now) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is from the future"))
      (unless (engine-rpc-constant-time-bytes=
               expected-signature actual-signature)
        (block-validation-fail "JWT signature is invalid"))
      t)))

(defun engine-rpc-http-authorized-p (authorization secret now)
  (unless authorization
    (block-validation-fail "missing token"))
  (unless (engine-rpc-string-prefix-p "Bearer " authorization)
    (block-validation-fail "missing token"))
  (engine-rpc-validate-jwt-token
   (subseq authorization (length "Bearer "))
   secret
   now))

(defun engine-rpc-http-split-lines (string)
  (loop with start = 0
        for end = (position #\Newline string :start start)
        collect (engine-rpc-http-trim
                 (subseq string start (or end (length string))))
        while end
        do (setf start (1+ end))))

(defun engine-rpc-http-request-target (request-line)
  (let* ((first-space (position #\Space request-line))
         (second-space
           (and first-space
                (position #\Space request-line :start (1+ first-space))))
         (third-space
           (and second-space
                (position #\Space request-line :start (1+ second-space)))))
    (unless (and first-space second-space (not third-space))
      (block-validation-fail "HTTP request line is malformed"))
    (let ((version (subseq request-line (1+ second-space))))
      (unless (string= version "HTTP/1.1")
        (block-validation-fail "HTTP request line is malformed"))
      (values (subseq request-line 0 first-space)
              (subseq request-line (1+ first-space) second-space)))))

(defun engine-rpc-http-target-path (target)
  (if (and (stringp target)
           (plusp (length target))
           (char= #\/ (char target 0)))
      (subseq target 0 (or (position #\? target)
                           (length target)))
      target))

(defun engine-rpc-http-target-allowed-p (target rpc-prefix)
  (let ((path (engine-rpc-http-target-path target)))
    (or (string= path rpc-prefix)
        (and (< (length rpc-prefix) (length path))
             (not (string= rpc-prefix "/"))
             (engine-rpc-string-prefix-p rpc-prefix path)
             (char= #\/ (char path (length rpc-prefix)))))))

(defun engine-rpc-http-headers (lines)
  (loop for line in lines
        unless (string= line "")
          collect
          (let ((colon (position #\: line)))
            (unless colon
              (block-validation-fail "HTTP header is malformed"))
            (let ((name (engine-rpc-http-trim (subseq line 0 colon))))
              (when (string= name "")
                (block-validation-fail "HTTP header is malformed"))
              (cons (string-downcase name)
                    (engine-rpc-http-trim (subseq line (1+ colon))))))))

(defun engine-rpc-http-header (headers name)
  (cdr (assoc (string-downcase name) headers :test #'string=)))

(defun engine-rpc-http-header-values (headers name)
  (loop with normalized = (string-downcase name)
        for (header-name . value) in headers
        when (string= normalized header-name)
          collect value))

(defun engine-rpc-http-single-header (headers name)
  (let ((values (engine-rpc-http-header-values headers name)))
    (when (rest values)
      (block-validation-fail "HTTP ~A header is duplicated" name))
    (first values)))

(defun engine-rpc-http-media-type (content-type)
  (when content-type
    (string-downcase
     (engine-rpc-http-trim
      (subseq content-type
              0
              (or (position #\; content-type)
                  (length content-type)))))))

(defun engine-rpc-http-accepted-content-type-p (content-type)
  (let ((media-type (engine-rpc-http-media-type content-type)))
    (and media-type
         (member media-type
                 +engine-rpc-http-accepted-content-types+
                 :test #'string=))))

(defun engine-rpc-http-decimal-digits-p (string)
  (and (< 0 (length string))
       (every #'digit-char-p string)))

(defun engine-rpc-http-parse-content-length (content-length)
  (let ((content-length (engine-rpc-http-trim content-length)))
    (unless (engine-rpc-http-decimal-digits-p content-length)
      (block-validation-fail "HTTP content length is invalid"))
    (parse-integer content-length :junk-allowed nil)))

(defun engine-rpc-http-header-boundary (request)
  (let ((crlf-boundary
          (search (format nil "~C~C~C~C"
                          #\Return #\Newline #\Return #\Newline)
                  request))
        (lf-boundary (search (format nil "~C~C" #\Newline #\Newline)
                             request)))
    (cond
      (crlf-boundary (values crlf-boundary 4))
      (lf-boundary (values lf-boundary 2))
      (t (block-validation-fail "HTTP request is missing header boundary")))))

(defun engine-rpc-http-body (body headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       body)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
        (let ((length
                (engine-rpc-http-parse-content-length
                 (first content-lengths))))
          (unless (<= length (length body))
            (block-validation-fail "HTTP content length is invalid"))
          (subseq body 0 length))))))

(defun engine-rpc-request-methods (request)
  (cond
    ((json-object-p request)
     (let ((method (genesis-object-field request "method")))
       (and (stringp method) (list method))))
    ((listp request)
     (loop for item in request
           when (json-object-p item)
             append (engine-rpc-request-methods item)))
    (t nil)))

(defun engine-rpc-method-summary (methods)
  (with-output-to-string (stream)
    (loop for method in methods
          for first-p = t then nil
          do (progn
               (unless first-p
                 (write-char #\, stream))
               (write-string method stream)))))

(defun engine-rpc-http-request-telemetry-fields (request)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary request)
        (let* ((head (subseq request 0 boundary))
               (body (subseq request (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (unless lines
            (return-from engine-rpc-http-request-telemetry-fields nil))
          (multiple-value-bind (http-method target)
              (engine-rpc-http-request-target (first lines))
            (let* ((headers (engine-rpc-http-headers (rest lines)))
                   (body (engine-rpc-http-body body headers))
                   (methods
                     (and (plusp (length body))
                          (engine-rpc-request-methods (parse-json body)))))
              (append
               (list (cons "httpMethod" http-method)
                     (cons "httpTarget" target))
               (when methods
                 (list (cons "rpcMethods"
                             (engine-rpc-method-summary methods)))))))))
    (error () nil)))

(defun engine-rpc-http-response-status-code (response)
  (handler-case
      (parse-integer response :start 9 :end 12 :junk-allowed nil)
    (error () nil)))

(defun engine-rpc-http-response-body (response)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary response)
        (let* ((head (subseq response 0 boundary))
               (body (subseq response (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (engine-rpc-http-body body (engine-rpc-http-headers (rest lines)))))
    (error () nil)))

(defun engine-rpc-telemetry-summary (values)
  (with-output-to-string (stream)
    (loop for value in values
          for first-p = t then nil
          do (progn
               (unless first-p
                 (write-char #\, stream))
               (write-string value stream)))))

(defun engine-rpc-response-error-codes (response)
  (cond
    ((json-object-p response)
     (let ((error (genesis-object-field response "error")))
       (when (json-object-p error)
         (let ((code (genesis-object-field error "code")))
           (when (integerp code)
             (list (format nil "~D" code)))))))
    ((listp response)
     (loop for item in response
           append (engine-rpc-response-error-codes item)))
    (t nil)))

(defun engine-rpc-response-payload-statuses (response)
  (labels ((result-status (result)
             (when (json-object-p result)
               (let ((status (genesis-object-field result "status"))
                     (payload-status
                       (genesis-object-field result "payloadStatus")))
                 (cond
                   ((stringp status)
                    (list status))
                   ((json-object-p payload-status)
                    (let ((status
                            (genesis-object-field payload-status "status")))
                      (when (stringp status)
                        (list status))))
                   (t nil))))))
    (cond
      ((json-object-p response)
       (result-status (genesis-object-field response "result")))
      ((listp response)
       (loop for item in response
             append (engine-rpc-response-payload-statuses item)))
      (t nil))))

(defun engine-rpc-http-response-telemetry-fields (response)
  (handler-case
      (let ((body (engine-rpc-http-response-body response)))
        (when (and body (plusp (length body)))
          (let* ((rpc-response (parse-json body))
                 (error-codes
                   (engine-rpc-response-error-codes rpc-response))
                 (payload-statuses
                   (engine-rpc-response-payload-statuses rpc-response)))
            (append
             (when error-codes
               (list (cons "rpcErrorCode"
                           (engine-rpc-telemetry-summary error-codes))))
             (when payload-statuses
               (list (cons "rpcPayloadStatus"
                           (engine-rpc-telemetry-summary
                            payload-statuses))))))))
    (error () nil)))

(defun engine-rpc-http-content-length (headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       0)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
       (engine-rpc-http-parse-content-length (first content-lengths))))))

(defun engine-rpc-read-http-request-string (input-stream)
  (let ((lines '()))
    (loop for line = (read-line input-stream nil nil)
          while line
          do (push line lines)
             (when (string= "" (engine-rpc-http-trim line))
               (return)))
    (unless (and lines (string= "" (engine-rpc-http-trim (first lines))))
      (block-validation-fail "HTTP request is missing header boundary"))
    (let* ((lines (nreverse lines))
           (headers (engine-rpc-http-headers (rest lines)))
           (content-length (engine-rpc-http-content-length headers))
           (body (make-string content-length))
           (read-count (read-sequence body input-stream)))
      (unless (= read-count content-length)
        (block-validation-fail "HTTP request body is shorter than content length"))
      (with-output-to-string (request)
        (dolist (line lines)
          (write-string (engine-rpc-http-trim line) request)
          (format request "~C~C" #\Return #\Newline))
        (write-string body request)))))

(defun engine-rpc-http-response-string (status-code reason body
                                        &key
                                          (content-type "application/json")
                                          extra-headers)
  (with-output-to-string (stream)
    (format stream "HTTP/1.1 ~D ~A~C~C" status-code reason
            #\Return #\Newline)
    (when content-type
      (format stream "Content-Type: ~A~C~C" content-type #\Return #\Newline))
    (dolist (header extra-headers)
      (format stream "~A: ~A~C~C"
              (car header)
              (cdr header)
              #\Return #\Newline))
    (format stream "Connection: close~C~C" #\Return #\Newline)
    (format stream "Content-Length: ~D~C~C" (length body) #\Return #\Newline)
    (format stream "~C~C" #\Return #\Newline)
    (write-string body stream)))

(defun engine-rpc-http-error-response
    (status-code reason message &key extra-headers)
  (engine-rpc-http-response-string
   status-code reason message
   :content-type "text/plain"
   :extra-headers extra-headers))

(defun engine-rpc-http-cors-wildcard-p (origins)
  (member "*" origins :test #'string=))

(defun engine-rpc-http-cors-response-headers (headers origins)
  (let ((origin (engine-rpc-http-header headers "origin")))
    (cond
      ((null origins)
       (values nil t))
      ((engine-rpc-http-cors-wildcard-p origins)
       (values
        '(("Access-Control-Allow-Origin" . "*")
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t))
      ((and origin (member origin origins :test #'string=))
       (values
        `(("Access-Control-Allow-Origin" . ,origin)
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type")
          ("Vary" . "Origin"))
        t))
      (origin
       (values nil nil))
      (t
       (values
        '(("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t)))))

(defun engine-rpc-http-host-wildcard-p (hosts)
  (member "*" hosts :test #'string=))

(defun engine-rpc-http-host-name (host)
  (let* ((host (and host (engine-rpc-http-trim host)))
         (length (and host (length host))))
    (cond
      ((or (null host) (zerop length))
       nil)
      ((and (char= #\[ (char host 0))
            (position #\] host))
       (subseq host 0 (1+ (position #\] host))))
      (t
       (let ((colon (position #\: host :from-end t)))
         (if colon
             (subseq host 0 colon)
             host))))))

(defun engine-rpc-http-host-allowed-p (headers allowed-hosts)
  (or (null allowed-hosts)
      (engine-rpc-http-host-wildcard-p allowed-hosts)
      (let ((host (engine-rpc-http-host-name
                   (engine-rpc-http-header headers "host"))))
        (and host
             (member host allowed-hosts :test #'string-equal)))))

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
