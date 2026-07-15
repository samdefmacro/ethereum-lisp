(in-package #:ethereum-lisp.engine-api)

(defun engine-rpc-new-payload-version (method)
  (cond
    ((string= method "engine_newPayloadV1") 1)
    ((string= method "engine_newPayloadV2") 2)
    ((string= method "engine_newPayloadV3") 3)
    ((string= method "engine_newPayloadV4") 4)
    ((string= method "engine_newPayloadV5") 5)
    (t nil)))

(defun engine-rpc-validate-new-payload-fork (version payload config)
  (let* ((number (executable-data-number payload))
         (timestamp (executable-data-timestamp payload))
         (cancun-p (chain-config-cancun-p config number timestamp))
         (prague-p (chain-config-prague-p config number timestamp))
         (osaka-p (chain-config-osaka-p config number timestamp))
         (amsterdam-p (chain-config-amsterdam-p config number timestamp))
         (supported-p
           (case version
             (3 (and cancun-p
                     (not prague-p)
                     (not osaka-p)
                     (not amsterdam-p)))
             (4 (and (or prague-p osaka-p)
                     (not amsterdam-p)))
             (5 amsterdam-p)
             (otherwise t))))
    (unless supported-p
      (engine-rpc-fail
       +engine-rpc-error-unsupported-fork+
       (format nil "engine_newPayloadV~D is unsupported for payload timestamp ~D"
               version timestamp)))))

(defun engine-rpc-persist-new-payload
    (store candidate new-payload-persistence-function)
  (when new-payload-persistence-function
    (handler-case
        (funcall new-payload-persistence-function store candidate)
      (storage-error (condition)
        (error condition))
      (error (condition)
        (storage-fail "New payload persistence failed: ~A" condition)))))

(defun engine-rpc-handle-new-payload
    (version params store config
     &key import-function new-payload-persistence-function)
  (unless (and (listp params) params)
    (block-validation-fail "engine_newPayload params must include payload"))
  (let ((payload
          (engine-rpc-executable-data-from-object
           (json-rpc-required-param
            params 0 "payload" "engine_newPayload"))))
    (engine-rpc-validate-new-payload-fork version payload config)
    (let* ((versioned-hashes
             (when (>= version 3)
               (json-rpc-hash32-list
                (json-rpc-required-param
                 params 1 "versionedHashes" "engine_newPayload")
                "versionedHashes")))
           (parent-beacon-root
             (when (>= version 3)
               (json-rpc-optional-hash32-value
                (json-rpc-required-param
                 params 2 "parentBeaconBlockRoot" "engine_newPayload")
                "parentBeaconBlockRoot")))
           (requests
             (when (>= version 4)
               (json-rpc-byte-list
                (json-rpc-required-param
                 params 3 "executionRequests" "engine_newPayload")
                "executionRequests"))))
      (labels ((handle-payload ()
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
                   (when (string= +payload-status-valid+
                                  (payload-status-status status))
                     (unless block
                       (storage-fail
                        "VALID new payload did not publish a candidate block"))
                     (engine-rpc-persist-new-payload
                      store block new-payload-persistence-function))
                   (engine-rpc-payload-status-object status))))
        (if new-payload-persistence-function
            (chain-store-atomic-commit store #'handle-payload)
            (handle-payload))))))

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
        (let ((value (json-rpc-required-field caller field)))
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
          (json-rpc-required-quantity-field object
                                              "terminalTotalDifficulty"))
        (terminal-block-hash
          (json-rpc-required-hash32-field object "terminalBlockHash")))
    (json-rpc-required-quantity-field object "terminalBlockNumber")
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
