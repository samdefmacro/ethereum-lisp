(in-package #:ethereum-lisp.engine-api)

(defun engine-rpc-prepared-payload-body-arguments
    (payload-attributes config block-number timestamp)
  (let ((arguments nil))
    (when (or (payload-attributes-v1-withdrawals-present-p payload-attributes)
              (chain-config-shanghai-p config block-number timestamp))
      (setf arguments
            (append arguments
                    (list :withdrawals
                          (if (payload-attributes-v1-withdrawals-present-p
                               payload-attributes)
                              (payload-attributes-v1-withdrawals
                               payload-attributes)
                              '())))))
    (when (chain-config-prague-p config block-number timestamp)
      (setf arguments (append arguments (list :requests '()))))
    (when (chain-config-amsterdam-p config block-number timestamp)
      (setf arguments (append arguments (list :block-access-list '()))))
    arguments))

(defun engine-rpc-build-prepared-payload
    (store parent-block payload-attributes config transactions)
  (let ((block (engine-build-empty-payload parent-block payload-attributes)))
    (if (null transactions)
        block
        (let* ((header (block-header block))
               (block-number (block-header-number header))
               (timestamp (block-header-timestamp header))
               (state (chain-store-state-db store (block-hash parent-block))))
          (unless state
            (block-validation-fail
             "Prepared payload parent state is unavailable"))
          (setf (block-header-transactions-root header)
                (transaction-list-root transactions)
                (block-header-state-root header) nil
                (block-header-receipts-root header) nil
                (block-header-logs-bloom header) nil)
          (apply
           #'execute-signed-block
           state
           transactions
           (append
            (list
             :expected-chain-id (chain-config-chain-id config)
             :header header
             :chain-config config)
            (engine-rpc-prepared-payload-body-arguments
             payload-attributes config block-number timestamp)))))))

(defun engine-rpc-persist-forkchoice
    (store forkchoice-persistence-function)
  (when forkchoice-persistence-function
    (handler-case
        (funcall forkchoice-persistence-function store)
      (storage-error (condition)
        (error condition))
      (error (condition)
        (storage-fail "Forkchoice persistence failed: ~A" condition)))))

(defun engine-rpc-handle-forkchoice-updated
    (params store config method payload-version payload-attributes-parser
     &key forkchoice-persistence-function)
  (unless (and (listp params) params)
    (block-validation-fail "~A params must include forkchoice state" method))
  (let ((state
          (engine-rpc-forkchoice-state-from-object
           (json-rpc-required-param
            params 0 "forkchoiceState" method)))
        (payload-attributes
          (when (< 1 (length params))
            (let ((value (second params)))
              (unless (json-null-p value)
                value)))))
    (let ((status (engine-forkchoice-memory-status store state))
          (payload-id nil))
      (when (string= +payload-status-valid+
                     (payload-status-status status))
        (let ((checkpoint-error
                (or
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-finalized-block-hash state)
                  "finalized"
                  :head-hash (forkchoice-state-head-block-hash state))
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-safe-block-hash state)
                  "safe"
                  :head-hash (forkchoice-state-head-block-hash state))
                 (engine-forkchoice-checkpoint-order-error-message
                  store state))))
          (when checkpoint-error
            (engine-rpc-fail
             +engine-rpc-error-invalid-forkchoice-state+
             checkpoint-error)))
        (chain-store-atomic-commit
         store
         (lambda ()
           (chain-store-update-forkchoice-checkpoints store state)
           (chain-store-set-canonical-head
            store
            (forkchoice-state-head-block-hash state)
            :expected-chain-id (chain-config-chain-id config)
            :chain-config config)
           (engine-rpc-persist-forkchoice
            store forkchoice-persistence-function))))
      (when (and payload-attributes
                 (string= +payload-status-valid+
                          (payload-status-status status)))
        (let* ((payload-attributes
                 (handler-case
                     (funcall payload-attributes-parser payload-attributes)
                   (block-validation-error (condition)
                     (engine-rpc-fail
                      +engine-rpc-error-invalid-payload-attributes+
                      (block-validation-error-message condition)))))
               (head-hash (forkchoice-state-head-block-hash state))
               (parent-block
                 (chain-store-known-block store head-hash))
               (transactions
                 (engine-select-mining-transactions
                  (engine-payload-store-pending-mining-transactions
                   store (chain-config-chain-id config))
                  (block-header-gas-limit (block-header parent-block))
                  (chain-config-chain-id config)))
               (candidate-id
                 (engine-payload-id-with-transactions
                  payload-version head-hash payload-attributes transactions)))
          (unless (chain-store-prepared-payload
                   store candidate-id)
            (chain-store-put-prepared-payload
             store
             (make-engine-prepared-payload
              :payload-id candidate-id
              :version payload-version
              :block
              (handler-case
                  (engine-rpc-build-prepared-payload
                   store parent-block payload-attributes config transactions)
                (block-validation-error (condition)
                  (engine-rpc-fail
                   +engine-rpc-error-invalid-payload-attributes+
                   (block-validation-error-message condition)))))))
          (setf payload-id candidate-id)))
      (engine-rpc-forkchoice-response-object
       status
       :payload-id payload-id))))

(defun engine-rpc-handle-forkchoice-updated-v1
    (params store config &key forkchoice-persistence-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV1" 1
   (lambda (payload-attributes)
     (engine-rpc-validate-payload-attributes-v1
      payload-attributes :method "engine_forkchoiceUpdatedV1"))
   :forkchoice-persistence-function forkchoice-persistence-function))

(defun engine-rpc-handle-forkchoice-updated-v2
    (params store config &key forkchoice-persistence-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV2" 2
   #'engine-rpc-validate-payload-attributes-v2
   :forkchoice-persistence-function forkchoice-persistence-function))

(defun engine-rpc-handle-forkchoice-updated-v3
    (params store config &key forkchoice-persistence-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV3" 3
   #'engine-rpc-validate-payload-attributes-v3
   :forkchoice-persistence-function forkchoice-persistence-function))

(defun engine-rpc-handle-forkchoice-updated-v4
    (params store config &key forkchoice-persistence-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV4" 4
   #'engine-rpc-validate-payload-attributes-v4
   :forkchoice-persistence-function forkchoice-persistence-function))
