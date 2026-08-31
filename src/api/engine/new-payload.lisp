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
             (1 (not (chain-config-shanghai-p
                      config number timestamp)))
             (2 (not cancun-p))
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

(defun engine-rpc-validate-new-payload-method-shape (version payload)
  "Validate fields that are unconditionally required by the method version."
  (when (>= version 3)
    (when (null (executable-data-excess-blob-gas payload))
      (engine-rpc-fail -32602 "excessBlobGas is required by newPayloadV3+"))
    (when (null (executable-data-blob-gas-used payload))
      (engine-rpc-fail -32602 "blobGasUsed is required by newPayloadV3+"))))

(defun engine-rpc-persist-new-payload
    (store candidate new-payload-persistence-function &rest provenance)
  (when new-payload-persistence-function
    (handler-case
        (apply new-payload-persistence-function
               store candidate provenance)
      (storage-error (condition)
        (error condition))
      (error (condition)
        (storage-fail "New payload persistence failed: ~A" condition)))))

(defun engine-rpc-prepared-execution-for-block (store block)
  "Return a copied prepared block and post-state matching BLOCK exactly."
  (loop with hash = (block-hash block)
        for prepared-payload in (chain-store-prepared-payloads store)
        for prepared-block = (engine-prepared-payload-block prepared-payload)
        for execution-state =
          (engine-prepared-payload-execution-state prepared-payload)
        when (and (typep execution-state 'ethereum-lisp.state:state-db)
                  (hash32= hash (block-hash prepared-block)))
          do (return (values prepared-block execution-state))))

(defun engine-rpc-import-with-prepared-execution
    (store block config fallback-import-function)
  "Publish an exact process-local build result, or execute BLOCK normally."
  (multiple-value-bind (prepared-block execution-state)
      (engine-rpc-prepared-execution-for-block store block)
    (if execution-state
        (let ((state (ethereum-lisp.state:state-db-copy execution-state)))
          (unless (hash32=
                   (ethereum-lisp.state:state-db-root state)
                   (block-header-state-root (block-header prepared-block)))
            (storage-fail
             "Prepared payload execution state does not match its block"))
          (execute-and-commit-block
           store state
           (lambda ()
             (values prepared-block (block-receipts prepared-block)))
           :state-available-p t
           :canonicalize-p nil))
        (funcall (or fallback-import-function
                     #'execute-and-commit-engine-payload)
                 store block config))))

(defun engine-rpc-handle-new-payload
    (version params store config
     &key import-function new-payload-persistence-function)
  (unless (and (listp params) params)
    (block-validation-fail "engine_newPayload params must include payload"))
  (let ((payload
          (engine-rpc-executable-data-from-object
           (json-rpc-required-param
            params 0 "payload" "engine_newPayload"))))
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
      ;; executionRequests is an Engine method parameter.  Its structural
      ;; ordering and uniqueness constraints therefore fail as invalid params
      ;; (-32602), before payload reconstruction can turn them into an INVALID
      ;; consensus verdict.
      (when (>= version 4)
        (validate-execution-request-list-fields requests))
      (engine-rpc-validate-new-payload-method-shape version payload)
      ;; A complete request for an inactive method version is an unsupported
      ;; fork.  Perform this check only after decoding all method parameters
      ;; and validating the version's unconditionally required fields.
      (engine-rpc-validate-new-payload-fork version payload config)
      (let ((invalid-message
              (engine-new-payload-version-invalid-p
               version payload config
               (>= version 3)
               (>= version 3)
               (>= version 4))))
        (when invalid-message
          (engine-rpc-fail -32602 invalid-message)))
      (multiple-value-bind (status block receipts)
          (apply
           #'import-executable-payload
           store version payload config
           (append
            (list
             :source :engine
             :import-function
             (lambda (candidate-store candidate candidate-config)
               (engine-rpc-import-with-prepared-execution
                candidate-store candidate candidate-config import-function))
             :durability-function
             (and
              new-payload-persistence-function
              (lambda (callback-store candidate &rest provenance)
                (apply
                 #'engine-rpc-persist-new-payload
                 callback-store candidate
                 new-payload-persistence-function
                 provenance))))
            (when (>= version 3)
              (list :versioned-hashes versioned-hashes
                    :parent-beacon-root parent-beacon-root))
            (when (>= version 4)
              (list :requests requests))))
        (declare (ignore receipts))
        (when (and (string= +payload-status-valid+
                            (payload-status-status status))
                   (null block))
          (storage-fail
           "VALID new payload did not publish a candidate block"))
        (engine-rpc-payload-status-object status)))))

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
