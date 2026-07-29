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
    (store parent-block payload-attributes config transactions
     &key gas-limit-target)
  (let* ((block (engine-build-empty-payload
                 parent-block payload-attributes config
                 gas-limit-target))
         (header (block-header block))
         (block-number (block-header-number header))
         (timestamp (block-header-timestamp header)))
    (if (not (or transactions
                 (and
                  (payload-attributes-v1-withdrawals-present-p
                   payload-attributes)
                  (payload-attributes-v1-withdrawals payload-attributes))
                 (chain-config-cancun-p
                  config block-number timestamp)
                 (chain-config-prague-p
                  config block-number timestamp)
                 (chain-config-ubt-p
                  config block-number timestamp)))
        block
        (let ((state (chain-store-state-db store (block-hash parent-block))))
          (unless state
            (block-validation-fail
             "Prepared payload parent state is unavailable"))
          (setf (block-header-transactions-root header)
                (transaction-list-root transactions)
                (block-header-state-root header) nil
                (block-header-receipts-root header) nil
                (block-header-logs-bloom header) nil)
          (when (chain-config-cancun-p config block-number timestamp)
            (setf (block-header-blob-gas-used header)
                  (blob-gas-used transactions)))
          (apply
           #'execute-signed-block
           state
           transactions
           (append
            (list
             :expected-chain-id (chain-config-chain-id config)
             :header header
             :chain-config config
             :block-hashes
             (chain-store-block-hashes-for-header store header))
            (engine-rpc-prepared-payload-body-arguments
             payload-attributes config block-number timestamp)))))))

(defun engine-rpc-transaction-sender-key (transaction expected-chain-id)
  (let ((sender (transaction-sender
                 transaction :expected-chain-id expected-chain-id)))
    (and sender (address-to-hex sender))))

(defun engine-rpc-first-invalid-transaction-sender-key
    (store parent-block payload-attributes config transactions
     &key gas-limit-target)
  "Find the sender whose next transaction makes payload execution invalid.

Each probe starts from the parent state through
ENGINE-RPC-BUILD-PREPARED-PAYLOAD, so a successful prefix cannot leak its
mutated working state into the next probe."
  (loop with prefix = '()
        for transaction in transactions
        do (setf prefix (append prefix (list transaction)))
           (handler-case
               (engine-rpc-build-prepared-payload
                store parent-block payload-attributes config prefix
                :gas-limit-target gas-limit-target)
             (transaction-validation-error ()
               (return
                 (engine-rpc-transaction-sender-key
                  transaction (chain-config-chain-id config)))))))

(defun engine-rpc-build-viable-prepared-payload
    (store parent-block payload-attributes config transactions
     &key gas-limit-target)
  "Execute and fill TRANSACTIONS in order using actual cumulative gas.

Each candidate is probed on top of the already accepted transactions.  A
sender whose next nonce is invalid or cannot fit the remaining gas is skipped
for the rest of this payload; other senders are still considered."
  (let ((block
          (engine-rpc-build-prepared-payload
           store parent-block payload-attributes config nil
           :gas-limit-target gas-limit-target))
        (selected '())
        (blocked-senders (make-hash-table :test #'equal))
        (expected-chain-id (chain-config-chain-id config)))
    (dolist (transaction transactions)
      (let ((sender-key
              (engine-rpc-transaction-sender-key
               transaction expected-chain-id)))
        (unless (gethash sender-key blocked-senders)
          (handler-case
              (let ((candidate
                      (engine-rpc-build-prepared-payload
                       store parent-block payload-attributes config
                       (append selected (list transaction))
                       :gas-limit-target gas-limit-target)))
                (let ((header (block-header candidate)))
                  (when (and
                         (chain-config-osaka-p
                          config
                          (block-header-number header)
                          (block-header-timestamp header))
                         (> (length (block-rlp candidate))
                            +max-rlp-block-size-eip7934+))
                    (block-validation-fail
                     "Block RLP size exceeds the EIP-7934 cap")))
                (setf selected (append selected (list transaction))
                      block candidate))
            (transaction-validation-error ()
              (setf (gethash sender-key blocked-senders) t))
            (block-validation-error ()
              (setf (gethash sender-key blocked-senders) t))))))
    (values block selected)))

(defun engine-rpc-pending-build-transactions (store config parent-header)
  (engine-payload-store-pending-mining-transactions
   store (chain-config-chain-id config)
   :base-fee (ignore-errors
              (expected-base-fee-per-gas parent-header))))

(defun engine-rpc-blobs-bundle-for-transactions (store transactions)
  (let ((blobs '())
        (commitments '())
        (proofs '()))
    (dolist (transaction transactions)
      (when (typep transaction 'blob-transaction)
        (dolist (versioned-hash
                 (blob-transaction-blob-versioned-hashes transaction))
          (let ((blob-and-proofs
                  (engine-payload-store-blob-and-proofs-v1
                   store versioned-hash)))
            (unless blob-and-proofs
              (block-validation-fail
               "Selected blob transaction sidecar is unavailable"))
            (push (engine-blob-and-proofs-blob blob-and-proofs) blobs)
            (push (engine-blob-and-proofs-commitment blob-and-proofs)
                  commitments)
            (push (engine-blob-and-proofs-proof blob-and-proofs) proofs)))))
    (make-blob-sidecar
     :blobs (nreverse blobs)
     :commitments (nreverse commitments)
     :proofs (nreverse proofs))))

(defun engine-rpc-improve-prepared-payload (store config prepared-payload)
  "Rebuild an open payload from the latest txpool contents under the same id."
  (unless (typep prepared-payload 'engine-prepared-payload)
    (block-validation-fail "Payload improvement requires a prepared payload"))
  (if (not (engine-prepared-payload-open-p prepared-payload))
      prepared-payload
      (let* ((parent-block
               (chain-store-known-block
                store
                (engine-prepared-payload-parent-hash prepared-payload)))
             (transactions
               (engine-rpc-pending-build-transactions
                store config (block-header parent-block)))
             (candidate-root (transaction-list-root transactions)))
        (if (hash32=
             candidate-root
             (engine-prepared-payload-candidate-transactions-root
              prepared-payload))
            prepared-payload
            (multiple-value-bind (block viable-transactions)
                (engine-rpc-build-viable-prepared-payload
                 store
                 parent-block
                 (engine-prepared-payload-payload-attributes prepared-payload)
                 config
                 transactions
                 :gas-limit-target
                 (engine-prepared-payload-gas-limit-target prepared-payload))
              (let ((improved
                      (make-engine-prepared-payload
                       :payload-id
                       (engine-prepared-payload-payload-id prepared-payload)
                       :version
                       (engine-prepared-payload-version prepared-payload)
                       :block block
                       :blobs-bundle
                       (engine-rpc-blobs-bundle-for-transactions
                        store viable-transactions)
                       :parent-hash
                       (engine-prepared-payload-parent-hash prepared-payload)
                       :payload-attributes
                       (engine-prepared-payload-payload-attributes
                        prepared-payload)
                       :gas-limit-target
                       (engine-prepared-payload-gas-limit-target
                        prepared-payload)
                       :candidate-transactions-root candidate-root
                       :open-p t)))
                (chain-store-put-prepared-payload store improved)
                improved))))))

(defun engine-rpc-improve-open-payloads (store config)
  "Improve every payload that has not yet been retrieved."
  (dolist (prepared-payload (chain-store-prepared-payloads store))
    (when (engine-prepared-payload-open-p prepared-payload)
      (engine-rpc-improve-prepared-payload store config prepared-payload)))
  nil)

(defun engine-rpc-persist-forkchoice
    (store transition forkchoice-persistence-function)
  (when forkchoice-persistence-function
    (handler-case
        (funcall forkchoice-persistence-function store transition)
      (storage-error (condition)
        (error condition))
      (error (condition)
        (storage-fail "Forkchoice persistence failed: ~A" condition)))))

(defun engine-rpc-prepared-payload-version
    (forkchoice-version config block-number timestamp)
  (case forkchoice-version
    (3
     (cond
       ((chain-config-amsterdam-p config block-number timestamp)
        (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                         "forkchoiceUpdatedV3 is unsupported after Amsterdam"))
       ((chain-config-osaka-p config block-number timestamp) 5)
       ((chain-config-prague-p config block-number timestamp) 4)
       ((chain-config-cancun-p config block-number timestamp) 3)
       (t
        (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                         "forkchoiceUpdatedV3 requires Cancun or later"))))
    (4
     (if (chain-config-amsterdam-p config block-number timestamp)
         6
         (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                          "forkchoiceUpdatedV4 requires Amsterdam")))
    (otherwise forkchoice-version)))

(defun engine-rpc-handle-forkchoice-updated
    (params store config method payload-version payload-attributes-parser
     &key forkchoice-persistence-function gas-limit-target)
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
           (multiple-value-bind (head transition)
               (chain-store-set-canonical-head
                store
                (forkchoice-state-head-block-hash state)
                :expected-chain-id (chain-config-chain-id config)
                :chain-config config)
             (declare (ignore head))
             (engine-rpc-persist-forkchoice
              store transition forkchoice-persistence-function)))))
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
               (parent-header (block-header parent-block))
               (block-number (1+ (block-header-number parent-header)))
               (timestamp (payload-attributes-v1-timestamp
                           payload-attributes))
               (prepared-payload-version
                 (engine-rpc-prepared-payload-version
                  payload-version config block-number timestamp))
               (candidate-id
                 (engine-payload-id
                  prepared-payload-version head-hash payload-attributes)))
          (unless (chain-store-prepared-payload store candidate-id)
            (multiple-value-bind (block viable-transactions)
                (handler-case
                    (engine-rpc-build-viable-prepared-payload
                     store parent-block payload-attributes config nil
                     :gas-limit-target gas-limit-target)
                  (block-validation-error (condition)
                    (engine-rpc-fail
                     +engine-rpc-error-invalid-payload-attributes+
                     (block-validation-error-message condition)))
                  (transaction-validation-error (condition)
                    (engine-rpc-fail
                     +engine-rpc-error-invalid-payload-attributes+
                     (princ-to-string condition))))
              (chain-store-put-prepared-payload
               store
               (make-engine-prepared-payload
                :payload-id candidate-id
                :version prepared-payload-version
                :block block
                :blobs-bundle
                (engine-rpc-blobs-bundle-for-transactions
                 store viable-transactions)
                :parent-hash head-hash
                :payload-attributes payload-attributes
                :gas-limit-target gas-limit-target
                :candidate-transactions-root
                (transaction-list-root nil)
                :open-p t))))
          (setf payload-id candidate-id)))
      (engine-rpc-forkchoice-response-object
       status
       :payload-id payload-id))))

(defun engine-rpc-handle-forkchoice-updated-v1
    (params store config &key forkchoice-persistence-function gas-limit-target)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV1" 1
   (lambda (payload-attributes)
     (engine-rpc-validate-payload-attributes-v1
      payload-attributes :method "engine_forkchoiceUpdatedV1"))
   :forkchoice-persistence-function forkchoice-persistence-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v2
    (params store config &key forkchoice-persistence-function gas-limit-target)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV2" 2
   #'engine-rpc-validate-payload-attributes-v2
   :forkchoice-persistence-function forkchoice-persistence-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v3
    (params store config &key forkchoice-persistence-function gas-limit-target)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV3" 3
   #'engine-rpc-validate-payload-attributes-v3
   :forkchoice-persistence-function forkchoice-persistence-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v4
    (params store config &key forkchoice-persistence-function gas-limit-target)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV4" 4
   #'engine-rpc-validate-payload-attributes-v4
   :forkchoice-persistence-function forkchoice-persistence-function
   :gas-limit-target gas-limit-target))
