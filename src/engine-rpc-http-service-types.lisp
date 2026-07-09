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
