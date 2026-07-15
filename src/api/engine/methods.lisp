(in-package #:ethereum-lisp.engine-api)

(defparameter +engine-rpc-method-registry+
  '(("engine_exchangeCapabilities" :advertised-p nil)
    ("engine_exchangeTransitionConfigurationV1" :advertised-p t)
    ("engine_forkchoiceUpdatedV1" :advertised-p t)
    ("engine_forkchoiceUpdatedV2" :advertised-p t)
    ("engine_getPayloadBodiesByHashV1" :advertised-p t)
    ("engine_getPayloadBodiesByRangeV1" :advertised-p t)
    ("engine_getPayloadV1" :advertised-p t)
    ("engine_getPayloadV2" :advertised-p t)
    ("engine_getClientVersionV1" :advertised-p t)
    ("engine_newPayloadV1" :advertised-p t)
    ("engine_newPayloadV2" :advertised-p t)
    ("engine_forkchoiceUpdatedV3" :advertised-p t :kzg-p t)
    ("engine_forkchoiceUpdatedV4" :advertised-p t :kzg-p t)
    ("engine_getPayloadBodiesByHashV2" :advertised-p t :kzg-p t)
    ("engine_getPayloadBodiesByRangeV2" :advertised-p t :kzg-p t)
    ("engine_getPayloadV3" :advertised-p t :kzg-p t)
    ("engine_getPayloadV4" :advertised-p t :kzg-p t)
    ("engine_getPayloadV5" :advertised-p t :kzg-p t)
    ("engine_getPayloadV6" :advertised-p t :kzg-p t)
    ("engine_getBlobsV1" :advertised-p t :kzg-p t)
    ("engine_getBlobsV2" :advertised-p t :kzg-p t)
    ("engine_getBlobsV3" :advertised-p t :kzg-p t)
    ("engine_newPayloadV3" :advertised-p t :kzg-p t)
    ("engine_newPayloadV4" :advertised-p t :kzg-p t)
    ("engine_newPayloadV5" :advertised-p t :kzg-p t)))

(defun engine-rpc-method-spec (method)
  (assoc method +engine-rpc-method-registry+ :test #'string=))

(defun engine-rpc-registered-methods (&key kzg-p advertised-p)
  (loop for (method . properties) in +engine-rpc-method-registry+
        when (and (or (null kzg-p)
                      (eql kzg-p (getf properties :kzg-p)))
                  (or (null advertised-p)
                      (eql advertised-p
                           (getf properties :advertised-p))))
          collect method))

(defparameter +engine-rpc-enabled-methods+
  (loop for (method . properties) in +engine-rpc-method-registry+
        unless (getf properties :kzg-p)
          collect method))

(defparameter +engine-rpc-kzg-backed-methods+
  (engine-rpc-registered-methods :kzg-p t))

(defun engine-rpc-enabled-method-p (method)
  (let ((spec (engine-rpc-method-spec method)))
    (and spec (not (getf (rest spec) :kzg-p)))))

(defun engine-rpc-kzg-backed-method-p (method)
  (let ((spec (engine-rpc-method-spec method)))
    (and spec (getf (rest spec) :kzg-p))))

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
