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
    ("engine_forkchoiceUpdatedV4" :advertised-p t :kzg-p t :bls-p t
     :amsterdam-p t)
    ("engine_getPayloadBodiesByHashV2" :advertised-p t :kzg-p t)
    ("engine_getPayloadBodiesByRangeV2" :advertised-p t :kzg-p t)
    ("engine_getPayloadV3" :advertised-p t :kzg-p t)
    ("engine_getPayloadV4" :advertised-p t :kzg-p t :bls-p t)
    ("engine_getPayloadV5" :advertised-p t :kzg-p t :bls-p t)
    ("engine_getPayloadV6" :advertised-p t :kzg-p t :bls-p t
     :amsterdam-p t)
    ("engine_getBlobsV1" :advertised-p t :kzg-p t)
    ("engine_getBlobsV2" :advertised-p nil :kzg-p t :unsupported-p t)
    ("engine_getBlobsV3" :advertised-p nil :kzg-p t :unsupported-p t)
    ("engine_newPayloadV3" :advertised-p t :kzg-p t)
    ("engine_newPayloadV4" :advertised-p t :kzg-p t :bls-p t)
    ("engine_newPayloadV5" :advertised-p t :kzg-p t :bls-p t
     :amsterdam-p t)))

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
    (and spec
         (getf (rest spec) :kzg-p)
         (not (getf (rest spec) :unsupported-p)))))

(defun engine-rpc-method-available-p (method)
  (let ((spec (engine-rpc-method-spec method)))
    (when spec
      (let ((properties (rest spec)))
        (and (not (getf properties :unsupported-p))
             (or (not (getf properties :kzg-p))
                 (kzg-proof-verification-available-p))
             (or (not (getf properties :bls-p))
                 (bls12381-backend-available-p))
             (or (not (getf properties :amsterdam-p))
                 (amsterdam-execution-available-p)))))))

(defparameter +engine-rpc-required-eth-methods+
  '("eth_blockNumber"
    "eth_call"
    "eth_chainId"
    "eth_getCode"
    "eth_getBlockByHash"
    "eth_getBlockByNumber"
    "eth_getLogs"
    "eth_sendRawTransaction"
    "eth_syncing")
  "The `eth` methods the Engine API endpoint MUST also expose.

Verbatim from the Engine API specification (execution-apis, src/engine/common.md):
a consumer needs to reach state and logs -- proof-of-stake deposits, most of all
-- over the same connection it drives the payload build on.

NOT the whole `eth` namespace, even though the port is JWT-authenticated and
geth does expose more there. The list is what the spec obliges us to serve, and
a consensus client asking for anything else is asking for something it was never
promised. Same reasoning that keeps `admin_` out of the public predicate: the
authenticated surface should be the size of its contract, not the size of what
happens to be implemented.

A live Lighthouse found this gap: it calls `eth_syncing` on the Engine port for
its execution-layer upcheck, got -32601 every time, and so never advanced past
`Error during execution engine upcheck`.")

(defun engine-rpc-required-eth-method-p (method)
  (and (stringp method)
       (member method +engine-rpc-required-eth-methods+ :test #'string=)
       t))

(defun engine-rpc-engine-method-p (method)
  (and (stringp method)
       (or (engine-rpc-method-available-p method)
           (engine-rpc-required-eth-method-p method))))

(defun engine-rpc-public-method-p (method)
  (and (stringp method)
       (or (string-prefix-p "eth_" method)
           (string-prefix-p "net_" method)
           (string-prefix-p "web3_" method)
           (string-prefix-p "rpc_" method)
           (string-prefix-p "txpool_" method)
           (string-prefix-p "debug_" method))))

(defun engine-rpc-admin-method-p (method)
  "Whether METHOD is in the admin namespace.

Deliberately NOT part of ENGINE-RPC-PUBLIC-METHOD-P. With no --http.api the
method filter falls back to that predicate unfiltered, so folding admin_ into it
would publish admin_addPeer on a default-open HTTP port. Admin is reachable only
by being named explicitly."
  (and (stringp method) (string-prefix-p "admin_" method)))

(defun engine-rpc-any-method-p (method)
  (declare (ignore method))
  t)
