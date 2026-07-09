(in-package #:ethereum-lisp.core)

(defparameter +engine-rpc-shanghai-capabilities+
  '("engine_exchangeTransitionConfigurationV1"
    "engine_forkchoiceUpdatedV1"
    "engine_forkchoiceUpdatedV2"
    "engine_getPayloadBodiesByHashV1"
    "engine_getPayloadBodiesByRangeV1"
    "engine_getPayloadV1"
    "engine_getPayloadV2"
    "engine_getClientVersionV1"
    "engine_newPayloadV1"
    "engine_newPayloadV2"))

(defparameter +engine-rpc-capabilities+ +engine-rpc-shanghai-capabilities+)

(defparameter +engine-rpc-kzg-backed-capabilities+
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

(defun engine-rpc-capabilities ()
  (append (copy-list +engine-rpc-capabilities+)
          (when (kzg-proof-verification-available-p)
            (copy-list +engine-rpc-kzg-backed-capabilities+))))

(defparameter +engine-rpc-client-version+
  '(("code" . "CL")
    ("name" . "ethereum-lisp")
    ("version" . "0.1.0")
    ("commit" . "0x00000000")))

(defun engine-rpc-client-version ()
  (copy-tree +engine-rpc-client-version+))

(defun engine-rpc-transition-configuration-object (config)
  (unless (typep config 'chain-config)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 config must be chain-config"))
  (list (cons "terminalTotalDifficulty"
              (quantity-to-hex
               (or (chain-config-terminal-total-difficulty config) 0)))
        (cons "terminalBlockHash"
              (hash32-to-hex
               (or (chain-config-terminal-block-hash config)
                   (zero-hash32))))
        (cons "terminalBlockNumber"
              (quantity-to-hex
               (or (chain-config-terminal-block-number config) 0)))))
