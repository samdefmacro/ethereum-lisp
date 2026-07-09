(in-package #:ethereum-lisp.core)

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
