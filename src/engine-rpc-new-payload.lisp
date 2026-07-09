(in-package #:ethereum-lisp.core)

(defun engine-rpc-new-payload-version (method)
  (cond
    ((string= method "engine_newPayloadV1") 1)
    ((string= method "engine_newPayloadV2") 2)
    ((string= method "engine_newPayloadV3") 3)
    ((string= method "engine_newPayloadV4") 4)
    ((string= method "engine_newPayloadV5") 5)
    (t nil)))

(defun engine-rpc-required-param
    (params index label &optional (method "engine_newPayload"))
  (unless (< index (length params))
    (block-validation-fail "~A param ~A is missing" method label))
  (nth index params))

(defun engine-rpc-handle-new-payload
    (version params store config &key import-function)
  (unless (and (listp params) params)
    (block-validation-fail "engine_newPayload params must include payload"))
  (let* ((payload
           (engine-rpc-executable-data-from-object
            (engine-rpc-required-param params 0 "payload")))
         (versioned-hashes
           (when (>= version 3)
             (engine-rpc-hash32-list
              (engine-rpc-required-param params 1 "versionedHashes")
              "versionedHashes")))
         (parent-beacon-root
           (when (>= version 3)
             (engine-rpc-optional-hash32-value
              (engine-rpc-required-param params 2 "parentBeaconBlockRoot")
              "parentBeaconBlockRoot")))
         (requests
           (when (>= version 4)
             (engine-rpc-byte-list
              (engine-rpc-required-param params 3 "executionRequests")
              "executionRequests"))))
    (multiple-value-bind (status block)
        (cond
          ((<= version 2)
           (engine-new-payload-memory-status
            store version payload config
            :import-function import-function))
          ((= version 3)
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :import-function import-function))
          (t
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :requests requests
            :import-function import-function)))
      (declare (ignore block))
      (engine-rpc-payload-status-object status))))

(defun engine-rpc-string-list-p (value)
  (and (not (stringp value))
       (json-array-p value)
       (every #'stringp (json-array-values value))))

(defun engine-rpc-handle-exchange-capabilities (params)
  (when params
    (let ((remote (first params)))
      (unless (engine-rpc-string-list-p remote)
        (block-validation-fail
         "engine_exchangeCapabilities params must contain a string list"))))
  (engine-rpc-capabilities))

(defun engine-rpc-handle-get-client-version (params)
  (when params
    (let ((caller (first params)))
      (unless (json-object-p caller)
        (block-validation-fail
         "engine_getClientVersionV1 params must contain a client version object"))
      (dolist (field '("code" "name" "version" "commit"))
        (let ((value (engine-rpc-required-field caller field)))
          (unless (stringp value)
            (block-validation-fail
             "engine_getClientVersionV1 client version fields must be strings"))))))
  (list (engine-rpc-client-version)))

(defun engine-rpc-validate-transition-configuration (object config)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must contain transition configuration object"))
  (unless (typep config 'chain-config)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 config must be chain-config"))
  (let ((terminal-total-difficulty
          (engine-rpc-required-quantity-field object
                                              "terminalTotalDifficulty"))
        (terminal-block-hash
          (engine-rpc-required-hash32-field object "terminalBlockHash")))
    (engine-rpc-required-quantity-field object "terminalBlockNumber")
    (unless (= terminal-total-difficulty
               (or (chain-config-terminal-total-difficulty config) 0))
      (block-validation-fail
       "engine_exchangeTransitionConfigurationV1 terminalTotalDifficulty mismatch"))
    (unless (equalp (hash32-bytes terminal-block-hash)
                    (hash32-bytes
                     (or (chain-config-terminal-block-hash config)
                         (zero-hash32))))
      (block-validation-fail
       "engine_exchangeTransitionConfigurationV1 terminalBlockHash mismatch")))
  t)

(defun engine-rpc-handle-exchange-transition-configuration (params config)
  (unless params
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must include transition configuration"))
  (engine-rpc-validate-transition-configuration (first params) config)
  (engine-rpc-transition-configuration-object config))
