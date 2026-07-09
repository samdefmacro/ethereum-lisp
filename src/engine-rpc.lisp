(in-package #:ethereum-lisp.core)

(defun engine-rpc-handle-engine-method
    (id method params store config &key import-function)
  (let ((version (engine-rpc-new-payload-version method)))
    (cond
      (version
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-new-payload
         version params store config
         :import-function import-function)))
      ((string= method "engine_exchangeCapabilities")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-capabilities params)))
      ((string= method "engine_forkchoiceUpdatedV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v1 params store config)))
      ((string= method "engine_forkchoiceUpdatedV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v2 params store config)))
      ((string= method "engine_forkchoiceUpdatedV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v3 params store config)))
      ((string= method "engine_forkchoiceUpdatedV4")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v4 params store config)))
      ((string= method "engine_getPayloadV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v1 params store)))
      ((string= method "engine_getPayloadV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v2 params store)))
      ((string= method "engine_getPayloadV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v3 params store)))
      ((string= method "engine_getPayloadV4")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v4 params store)))
      ((string= method "engine_getPayloadV5")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v5 params store)))
      ((string= method "engine_getPayloadV6")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v6 params store)))
      ((string= method "engine_getPayloadBodiesByHashV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByHashV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v2
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v2
         params store)))
      ((string= method "engine_getBlobsV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v1 params store)))
      ((string= method "engine_getBlobsV2")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v2 params store)))
      ((string= method "engine_getBlobsV3")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v3 params store)))
      ((string= method "engine_getClientVersionV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-get-client-version params)))
      ((string= method "engine_exchangeTransitionConfigurationV1")
       (engine-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-transition-configuration
         params config))))))
