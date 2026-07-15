(in-package #:ethereum-lisp.rpc-http)

(defparameter +engine-rpc-default-http-host+ "localhost")
(defconstant +engine-rpc-default-http-port+ 8551)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defstruct (engine-rpc-http-service
            (:constructor %make-engine-rpc-http-service
                (&key host port rpc-context jwt-secret now-provider
                      telemetry-sink rpc-prefix cors-origins allowed-hosts)))
  host
  port
  rpc-context
  jwt-secret
  now-provider
  telemetry-sink
  rpc-prefix
  cors-origins
  allowed-hosts)

(defun engine-rpc-http-service-store (service)
  (rpc-context-store (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-config (service)
  (rpc-context-config (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-import-function (service)
  (rpc-context-import-function
   (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-new-payload-persistence-function (service)
  (rpc-context-new-payload-persistence-function
   (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-allowed-method-p (service)
  (rpc-context-allowed-method-p
   (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-network-id (service)
  (rpc-context-network-id (engine-rpc-http-service-rpc-context service)))

(defun engine-rpc-http-service-coinbase (service)
  (rpc-context-coinbase (engine-rpc-http-service-rpc-context service)))

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

(defun engine-rpc-http-validate-optional-non-negative (value label)
  (when (and value
             (not (and (integerp value) (not (minusp value)))))
    (block-validation-fail
     "Engine RPC HTTP ~A must be a non-negative integer" label)))

(defun engine-rpc-http-validate-optional-string-list (value label)
  (when (and value
             (not (and (listp value) (every #'stringp value))))
    (block-validation-fail
     "Engine RPC HTTP ~A must be a string list" label)))

(defun make-engine-rpc-http-service
    (&key
       (host +engine-rpc-default-http-host+)
       (port +engine-rpc-default-http-port+)
       (store (make-engine-payload-memory-store))
       (config (make-chain-config))
       jwt-secret
       (now-provider (lambda () 0))
       (import-function #'execute-and-commit-engine-payload)
       new-payload-persistence-function
       forkchoice-persistence-function
       request-guard-function
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
    (block-validation-fail
     "Engine RPC HTTP port must be between 0 and 65535"))
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
    (block-validation-fail
     "Engine RPC HTTP now provider must be a function"))
  (unless (functionp import-function)
    (block-validation-fail
     "Engine RPC HTTP import function must be a function"))
  (when (and new-payload-persistence-function
             (not (functionp new-payload-persistence-function)))
    (block-validation-fail
     "Engine RPC HTTP new payload persistence callback must be a function"))
  (when (and forkchoice-persistence-function
             (not (functionp forkchoice-persistence-function)))
    (block-validation-fail
     "Engine RPC HTTP forkchoice persistence callback must be a function"))
  (when (and request-guard-function
             (not (functionp request-guard-function)))
    (block-validation-fail
     "Engine RPC HTTP request guard must be a function"))
  (unless (functionp allowed-method-p)
    (block-validation-fail
     "Engine RPC HTTP method filter must be a function"))
  (engine-rpc-http-validate-optional-non-negative network-id "network id")
  (unless (typep coinbase 'address)
    (block-validation-fail "Engine RPC HTTP coinbase must be an address"))
  (unless (and (stringp rpc-prefix)
               (plusp (length rpc-prefix))
               (char= #\/ (char rpc-prefix 0)))
    (block-validation-fail "Engine RPC HTTP prefix must start with /"))
  (engine-rpc-http-validate-optional-string-list cors-origins "CORS origins")
  (engine-rpc-http-validate-optional-string-list allowed-hosts "allowed hosts")
  (dolist (value-and-label
           `((,txpool-price-limit . "txpool price limit")
             (,txpool-price-bump-percent . "txpool price bump")
             (,txpool-account-slot-limit . "txpool account slot limit")
             (,txpool-global-slot-limit . "txpool global slot limit")
             (,txpool-account-queue-limit . "txpool account queue limit")
             (,txpool-global-queue-limit . "txpool global queue limit")
             (,txpool-lifetime-seconds . "txpool lifetime")))
    (engine-rpc-http-validate-optional-non-negative
     (car value-and-label) (cdr value-and-label)))
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
   :rpc-context
   (make-rpc-context
    store config
    :import-function import-function
    :new-payload-persistence-function new-payload-persistence-function
    :forkchoice-persistence-function forkchoice-persistence-function
    :request-guard-function request-guard-function
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
   :now-provider now-provider
   :telemetry-sink telemetry-sink
   :rpc-prefix rpc-prefix
   :cors-origins cors-origins
   :allowed-hosts allowed-hosts))

(defun engine-rpc-http-service-endpoint (service)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (format nil "~A:~D"
          (engine-rpc-http-service-host service)
          (engine-rpc-http-service-port service)))
