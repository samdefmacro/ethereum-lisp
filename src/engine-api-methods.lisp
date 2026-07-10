(in-package #:ethereum-lisp.core)

(defparameter +engine-rpc-enabled-methods+
  '("engine_exchangeCapabilities"
    "engine_exchangeTransitionConfigurationV1"
    "engine_forkchoiceUpdatedV1"
    "engine_forkchoiceUpdatedV2"
    "engine_getPayloadBodiesByHashV1"
    "engine_getPayloadBodiesByRangeV1"
    "engine_getPayloadV1"
    "engine_getPayloadV2"
    "engine_getClientVersionV1"
    "engine_newPayloadV1"
    "engine_newPayloadV2"))

(defparameter +engine-rpc-kzg-backed-methods+
  '("engine_forkchoiceUpdatedV3"
    "engine_forkchoiceUpdatedV4"
    "engine_getPayloadBodiesByHashV2"
    "engine_getPayloadBodiesByRangeV2"
    "engine_getPayloadV3"
    "engine_getPayloadV4"
    "engine_getPayloadV5"
    "engine_getPayloadV6"
    "engine_getBlobsV1"
    "engine_getBlobsV2"
    "engine_getBlobsV3"
    "engine_newPayloadV3"
    "engine_newPayloadV4"
    "engine_newPayloadV5"))

(defun engine-rpc-enabled-method-p (method)
  (member method +engine-rpc-enabled-methods+ :test #'string=))

(defun engine-rpc-kzg-backed-method-p (method)
  (member method +engine-rpc-kzg-backed-methods+ :test #'string=))

(defun engine-rpc-engine-method-p (method)
  (and (stringp method)
       (or (engine-rpc-enabled-method-p method)
           (and (engine-rpc-kzg-backed-method-p method)
                (kzg-proof-verification-available-p)))))

(defun engine-rpc-public-method-p (method)
  (and (stringp method)
       (or (string-prefix-p "eth_" method)
           (string-prefix-p "net_" method)
           (string-prefix-p "web3_" method)
           (string-prefix-p "rpc_" method)
           (string-prefix-p "txpool_" method))))

(defun engine-rpc-any-method-p (method)
  (declare (ignore method))
  t)
