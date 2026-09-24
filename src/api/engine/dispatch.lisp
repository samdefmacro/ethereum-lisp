(in-package #:ethereum-lisp.engine-api)

(defun engine-rpc-handle-engine-method
    (id method params store config
     &key import-function new-payload-persistence-function
          forkchoice-persistence-function gas-limit-target
          get-blobs-v3-function payload-improvement-notification-function)
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
         :forkchoice-persistence-function forkchoice-persistence-function
         :payload-improvement-notification-function
         payload-improvement-notification-function
         :gas-limit-target gas-limit-target)))
      ((string= method "engine_forkchoiceUpdatedV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v2
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function
         :payload-improvement-notification-function
         payload-improvement-notification-function
         :gas-limit-target gas-limit-target)))
      ((string= method "engine_forkchoiceUpdatedV3")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v3
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function
         :payload-improvement-notification-function
         payload-improvement-notification-function
         :gas-limit-target gas-limit-target)))
      ((string= method "engine_forkchoiceUpdatedV4")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-forkchoice-updated-v4
         params store config
         :forkchoice-persistence-function forkchoice-persistence-function
         :payload-improvement-notification-function
         payload-improvement-notification-function
         :gas-limit-target gas-limit-target)))
      ((string= method "engine_getPayloadV1")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v1 params store config)))
      ((string= method "engine_getPayloadV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v2 params store config)))
      ((string= method "engine_getPayloadV3")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v3 params store config)))
      ((string= method "engine_getPayloadV4")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v4 params store config)))
      ((string= method "engine_getPayloadV5")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v5 params store config)))
      ((string= method "engine_getPayloadV6")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-payload-v6 params store config)))
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
        (engine-rpc-handle-get-blobs-v1 params store config)))
      ((string= method "engine_getBlobsV2")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v2 params store config)))
      ((string= method "engine_getBlobsV3")
       (json-rpc-response
        id
        :result
        (if get-blobs-v3-function
            (funcall get-blobs-v3-function params)
            (engine-rpc-handle-get-blobs-v3 params store config))))
      ((string= method "engine_getBlobsV4")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-get-blobs-v4 params store config)))
      ((string= method "engine_hasBlobs")
       (json-rpc-response
        id
        :result
        (engine-rpc-handle-has-blobs params store)))
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

(defun engine-rpc-forkchoice-updated-method-p (method)
  (and (stringp method)
       (let ((prefix "engine_forkchoiceUpdatedV"))
         (and (> (length method) (length prefix))
              (string= prefix method :end2 (length prefix))))))

(defun engine-rpc-store-busy-response (id method)
  "The answer to Engine request METHOD when the store stayed busy with
background work past the node's wait budget.

engine_newPayload and engine_forkchoiceUpdated answer SYNCING with no latest
valid hash, which the Engine API allows while the client is syncing. Pinned
go-ethereum (38271784, eth/catalyst/api.go) answers the same when it cannot
take the request yet: delayPayloadImport for a payload while its downloader
owns the chain, and STATUS_SYNCING for a forkchoice head it must sync to
first. For a known head geth instead blocks on its chain mutex; giving up is
our addition, because our store guard can be held by background work far
longer than the CL waits. Nothing was validated or stored, so the CL simply
retries on a later slot. Every other method answers a -32000 server error:
it has no not-yet-known answer, and failing fast frees the connection that a
30 s wait would hold."
  (let ((syncing (make-payload-status :status +payload-status-syncing+)))
    (cond
      ((engine-rpc-new-payload-version method)
       (json-rpc-response
        id :result (engine-rpc-payload-status-object syncing)))
      ((engine-rpc-forkchoice-updated-method-p method)
       (json-rpc-response
        id :result (engine-rpc-forkchoice-response-object syncing)))
      (t
       (json-rpc-response
        id
        :error (json-rpc-error-object
                -32000
                "execution client busy: store held by background work"))))))
