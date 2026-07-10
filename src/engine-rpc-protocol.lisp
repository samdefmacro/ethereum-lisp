(in-package #:ethereum-lisp.core)

(defun engine-rpc-response (id &key result error)
  (append (list (cons "jsonrpc" "2.0")
                (cons "id" id))
          (if error
              (list (cons "error" error))
              (list (cons "result" result)))))

(defun engine-rpc-error-object (code message)
  (list (cons "code" code)
        (cons "message" message)))

(defun engine-rpc-invalid-request-response ()
  (engine-rpc-response
   nil
   :error
   (engine-rpc-error-object -32600 "Invalid Request")))

(defun engine-rpc-parse-error-response ()
  (engine-rpc-response
   nil
   :error
   (engine-rpc-error-object -32700 "Parse error")))

(defun engine-rpc-jsonrpc-version-valid-p (request)
  (let ((version (json-object-field request "jsonrpc")))
    (and (json-object-field-present-p request "jsonrpc")
         (stringp version)
         (string= "2.0" version))))

(defun engine-rpc-notification-request-p (request)
  (and (json-object-p request)
       (engine-rpc-jsonrpc-version-valid-p request)
       (not (json-object-field-present-p request "id"))
       (stringp (json-object-field request "method"))))

(defun engine-rpc-request-id-valid-p (request)
  (or (not (json-object-field-present-p request "id"))
      (let ((id (json-object-field request "id")))
        (or (null id)
            (stringp id)
            (numberp id)))))

(defun engine-rpc-request-envelope-valid-p (request)
  (and (engine-rpc-jsonrpc-version-valid-p request)
       (engine-rpc-request-id-valid-p request)
       (json-object-field-present-p request "method")
       (stringp (json-object-field request "method"))
       (or (not (json-object-field-present-p request "params"))
           (json-array-p (json-object-field request "params")))))

(defun engine-rpc-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

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

(defun engine-rpc-kzg-proof-verification-available-p ()
  (labels ((bound-function-p (symbol-name)
             (let ((symbol (find-symbol symbol-name "ETHEREUM-LISP.CORE")))
               (and symbol
                    (boundp symbol)
                    (functionp (symbol-value symbol))))))
    (and (bound-function-p "*KZG-POINT-PROOF-VERIFIER*")
         (bound-function-p "*KZG-BLOB-PROOF-VERIFIER*"))))

(defun engine-rpc-engine-method-p (method)
  (and (stringp method)
       (or (engine-rpc-enabled-method-p method)
           (and (engine-rpc-kzg-backed-method-p method)
                (engine-rpc-kzg-proof-verification-available-p)))))

(defun engine-rpc-public-method-p (method)
  (and (stringp method)
       (or (engine-rpc-string-prefix-p "eth_" method)
           (engine-rpc-string-prefix-p "net_" method)
           (engine-rpc-string-prefix-p "web3_" method)
           (engine-rpc-string-prefix-p "rpc_" method)
           (engine-rpc-string-prefix-p "txpool_" method))))

(defun engine-rpc-any-method-p (method)
  (declare (ignore method))
  t)
