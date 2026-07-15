(in-package #:ethereum-lisp.engine-api)

(defun engine-rpc-handle-engine-method
    (id method params store config
     &key import-function new-payload-persistence-function
          forkchoice-persistence-function)
  (let ((version (engine-rpc-new-payload-version method)))
    (cond
      (version
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-new-payload
         version params store config
         :import-function import-function
         :new-payload-persistence-function
         new-payload-persistence-function)))
      ((string= method "engine_exchangeCapabilities")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-capabilities params)))
      ((string= method "engine_forkchoiceUpdatedV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v1
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function)))
      ((string= method "engine_forkchoiceUpdatedV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v2
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function)))
      ((string= method "engine_forkchoiceUpdatedV3")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v3
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function)))
      ((string= method "engine_forkchoiceUpdatedV4")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v4
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function)))
      ((string= method "engine_getPayloadV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v1 params store)))
      ((string= method "engine_getPayloadV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v2 params store)))
      ((string= method "engine_getPayloadV3")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v3 params store)))
      ((string= method "engine_getPayloadV4")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v4 params store)))
      ((string= method "engine_getPayloadV5")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v5 params store)))
      ((string= method "engine_getPayloadV6")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v6 params store)))
      ((string= method "engine_getPayloadBodiesByHashV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByHashV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-hash-v2
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v1
         params store)))
      ((string= method "engine_getPayloadBodiesByRangeV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-bodies-by-range-v2
         params store)))
      ((string= method "engine_getBlobsV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v1 params store)))
      ((string= method "engine_getBlobsV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v2 params store)))
      ((string= method "engine_getBlobsV3")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v3 params store)))
      ((string= method "engine_getClientVersionV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-client-version params)))
      ((string= method "engine_exchangeTransitionConfigurationV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-exchange-transition-configuration
         params config))))))
