(in-package #:ethereum-lisp.engine-api)

(defvar *engine-rpc-phase-timings* :disabled
  "Per-request Engine RPC phase timings, or :DISABLED outside HTTP handling.")

(defun engine-rpc-record-phase-duration (name milliseconds)
  (unless (eq *engine-rpc-phase-timings* :disabled)
    (push (cons name milliseconds) *engine-rpc-phase-timings*))
  nil)

(defun engine-rpc-record-phase-timing (name started-at)
  (engine-rpc-record-phase-duration
   name
   (round
    (* 1000 (- (get-internal-real-time) started-at))
    internal-time-units-per-second))
  nil)

(defmacro engine-rpc-with-phase-timing ((name) &body body)
  `(let ((started-at (get-internal-real-time)))
     (multiple-value-prog1
         (progn ,@body)
       (engine-rpc-record-phase-timing ,name started-at))))

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
    ;; Amsterdam BAL side data is an execution output.  Omitting the argument
    ;; lets the local builder derive it; supplying an empty placeholder would
    ;; incorrectly require every non-empty derived list to equal NIL.
    arguments))

(defun engine-rpc-build-prepared-payload-detached
    (store parent-block payload-attributes config transactions
     &key gas-limit-target extra-data)
  (let* ((block
           (engine-rpc-with-phase-timing ("fcuEmptyBlockMs")
             (engine-build-empty-payload
              parent-block payload-attributes config gas-limit-target)))
         (header (block-header block))
         (block-number (block-header-number header))
         (timestamp (block-header-timestamp header)))
    (when extra-data
      (setf (block-header-extra-data header) (copy-seq extra-data)))
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
        (let ((state
                (engine-rpc-with-phase-timing ("fcuStateOpenMs")
                  (chain-store-state-db store (block-hash parent-block)))))
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
          (let ((block-hashes
                  (engine-rpc-with-phase-timing ("fcuBlockHashesMs")
                    (chain-store-block-hashes-for-header store header))))
            (multiple-value-bind (built-block receipts)
                (engine-rpc-with-phase-timing ("fcuExecutePayloadMs")
                  (apply
                   #'execute-signed-block
                   state
                   transactions
                   (append
                    (list
                     :expected-chain-id (chain-config-chain-id config)
                     :header header
                     :parent-header (block-header parent-block)
                     :chain-config config
                     :phase-recorder #'engine-rpc-record-phase-duration
                     :block-hashes block-hashes)
                    (engine-rpc-prepared-payload-body-arguments
                     payload-attributes config block-number timestamp))))
              (values built-block receipts state)))))))

(defun engine-rpc-build-prepared-payload
    (store parent-block payload-attributes config transactions
     &key gas-limit-target extra-data)
  "Build a validated payload candidate that remains private until newPayload."
  (engine-rpc-with-phase-timing ("fcuPrivateCandidateMs")
    (build-private-block-candidate
     store
     (lambda ()
       (engine-rpc-build-prepared-payload-detached
        store parent-block payload-attributes config transactions
        :gas-limit-target gas-limit-target
        :extra-data extra-data))
     config)))

(defun engine-rpc-transaction-sender-key (transaction expected-chain-id)
  (let ((sender (transaction-sender
                 transaction :expected-chain-id expected-chain-id)))
    (and sender (address-to-hex sender))))

(defun engine-rpc-deadline-predicate (seconds)
  "A no-argument predicate that turns true SECONDS from now."
  (let ((deadline (+ (get-internal-real-time)
                     (round (* seconds internal-time-units-per-second)))))
    (lambda () (>= (get-internal-real-time) deadline))))

(defun engine-rpc-build-selected-payload-detached
    (store parent-block payload-attributes config candidates
     &key gas-limit-target extra-data stop-predicate)
  "Build a payload from CANDIDATES in one pass, keeping those that execute.

Returns (VALUES BLOCK RECEIPTS STATE STOPPED-P).  Each candidate executes at
most once (EXECUTE-SIGNED-BLOCK-SELECTING); STOP-PREDICATE may end selection
early, and the block then holds what was kept so far."
  (if (null candidates)
      (engine-rpc-build-prepared-payload-detached
       store parent-block payload-attributes config nil
       :gas-limit-target gas-limit-target :extra-data extra-data)
      (let* ((block
               (engine-rpc-with-phase-timing ("fcuEmptyBlockMs")
                 (engine-build-empty-payload
                  parent-block payload-attributes config gas-limit-target)))
             (header (block-header block))
             (block-number (block-header-number header))
             (timestamp (block-header-timestamp header))
             (max-transaction-bytes
               ;; EIP-7934 caps the whole encoded block.  The empty block is
               ;; the header, withdrawals and list framing; the selector adds
               ;; a per-transaction framing allowance on top of each encoding.
               (when (chain-config-osaka-p config block-number timestamp)
                 (- +max-rlp-block-size-eip7934+
                    (length (block-rlp block))
                    1024))))
        (when extra-data
          (setf (block-header-extra-data header) (copy-seq extra-data)))
        (let ((state
                (engine-rpc-with-phase-timing ("fcuStateOpenMs")
                  (chain-store-state-db store (block-hash parent-block)))))
          (unless state
            (block-validation-fail
             "Prepared payload parent state is unavailable"))
          (setf (block-header-transactions-root header) nil
                (block-header-state-root header) nil
                (block-header-receipts-root header) nil
                (block-header-logs-bloom header) nil)
          (let ((block-hashes
                  (engine-rpc-with-phase-timing ("fcuBlockHashesMs")
                    (chain-store-block-hashes-for-header store header))))
            (multiple-value-bind (built-block receipts stopped-p)
                (engine-rpc-with-phase-timing ("fcuExecutePayloadMs")
                  (apply
                   #'execute-signed-block-selecting
                   state
                   candidates
                   (append
                    (list
                     :expected-chain-id (chain-config-chain-id config)
                     :header header
                     :parent-header (block-header parent-block)
                     :chain-config config
                     :phase-recorder #'engine-rpc-record-phase-duration
                     :block-hashes block-hashes
                     :stop-predicate stop-predicate
                     :max-transaction-bytes max-transaction-bytes)
                    (engine-rpc-prepared-payload-body-arguments
                     payload-attributes config block-number timestamp))))
              (when (and max-transaction-bytes
                         (> (length (block-rlp built-block))
                            +max-rlp-block-size-eip7934+))
                (block-validation-fail
                 "Block RLP size exceeds the EIP-7934 cap"))
              (values built-block receipts state stopped-p)))))))

(defun engine-rpc-build-viable-prepared-payload-by-probing
    (store parent-block payload-attributes config transactions
     &key gas-limit-target extra-data)
  "Fill TRANSACTIONS by re-executing growing prefixes (Amsterdam only).

Each candidate is probed on top of the already accepted transactions by
rebuilding the whole prefix from the parent state, so a pool with one bad
transaction costs O(N^2) executions.  It remains only because the one-pass
selector cannot roll a rejected candidate out of an EIP-7928 block access
list under construction; Amsterdam building is capability-gated off."
  ;; The overwhelmingly common case is that the txpool has already produced a
  ;; nonce-ordered, fee-eligible set which fits the block.  Execute that set
  ;; once before entering the rejection path.  The old prefix loop rebuilt
  ;; prefixes of length 1..N from the parent state, making a healthy payload
  ;; O(N^2) transaction executions and repeatedly reopening the parent trie.
  ;; Geth keeps one payload environment and reaches the same all-valid result
  ;; in one pass.  Preserve the exact filtering semantics below whenever the
  ;; aggregate candidate is invalid or exceeds Osaka's encoded-size cap.
  (when transactions
    (handler-case
        (multiple-value-bind (candidate ignored-receipts execution-state)
            (engine-rpc-build-prepared-payload
             store parent-block payload-attributes config transactions
             :gas-limit-target gas-limit-target
             :extra-data extra-data)
          (declare (ignore ignored-receipts))
          (let ((header (block-header candidate)))
            (unless (and
                     (chain-config-osaka-p
                      config
                      (block-header-number header)
                      (block-header-timestamp header))
                     (> (length (block-rlp candidate))
                        +max-rlp-block-size-eip7934+))
              (return-from engine-rpc-build-viable-prepared-payload-by-probing
                (values candidate (copy-list transactions)
                        execution-state)))))
      (transaction-validation-error ())
      (block-validation-error ())))
  (multiple-value-bind (empty-block ignored-receipts empty-execution-state)
      (engine-rpc-build-prepared-payload
       store parent-block payload-attributes config nil
       :gas-limit-target gas-limit-target
       :extra-data extra-data)
    (declare (ignore ignored-receipts))
    (let ((block empty-block)
          (execution-state empty-execution-state)
          (selected '())
          (blocked-senders (make-hash-table :test #'equal))
          (expected-chain-id (chain-config-chain-id config)))
      (dolist (transaction transactions)
        (let ((sender-key
                (engine-rpc-transaction-sender-key
                 transaction expected-chain-id)))
          (unless (gethash sender-key blocked-senders)
            (handler-case
                (multiple-value-bind
                      (candidate ignored-candidate-receipts candidate-state)
                    (engine-rpc-build-prepared-payload
                     store parent-block payload-attributes config
                     (append selected (list transaction))
                     :gas-limit-target gas-limit-target
                     :extra-data extra-data)
                  (declare (ignore ignored-candidate-receipts))
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
                        block candidate
                        execution-state candidate-state))
              (transaction-validation-error ()
                (setf (gethash sender-key blocked-senders) t))
              (block-validation-error ()
                (setf (gethash sender-key blocked-senders) t))))))
      (values block selected execution-state))))

(defun engine-rpc-buildable-transactions (store transactions)
  "TRANSACTIONS without the blob transactions whose sidecars STORE lacks.

getPayload must return every selected blob with its commitment and proof, so a
blob transaction this node holds no sidecar for cannot go into our payload."
  (remove-if-not
   (lambda (transaction)
     (or (not (typep transaction 'blob-transaction))
         (every (lambda (versioned-hash)
                  (engine-payload-store-blob-and-proofs-v1
                   store versioned-hash))
                (blob-transaction-blob-versioned-hashes transaction))))
   transactions))

(defun engine-rpc-build-viable-prepared-payload
    (store parent-block payload-attributes config transactions
     &key gas-limit-target extra-data stop-predicate)
  "Execute and fill TRANSACTIONS in order using actual cumulative gas.

One pass: each candidate executes at most once, on top of the candidates kept
before it.  A sender whose next transaction cannot execute or no longer fits
the block is skipped for the rest of this payload; other senders are still
considered.  STOP-PREDICATE, polled before each candidate, may end the pass
early; the payload then holds what was kept so far and is still valid.

Returns (VALUES BLOCK SELECTED EXECUTION-STATE STOPPED-P)."
  (let ((candidates (engine-rpc-buildable-transactions store transactions)))
    (if (chain-config-amsterdam-p
         config
         (1+ (block-header-number (block-header parent-block)))
         (payload-attributes-v1-timestamp payload-attributes))
        (multiple-value-bind (block selected execution-state)
            (engine-rpc-build-viable-prepared-payload-by-probing
             store parent-block payload-attributes config candidates
             :gas-limit-target gas-limit-target
             :extra-data extra-data)
          (values block selected execution-state nil))
        (let ((stopped-p nil))
          (multiple-value-bind (block receipts execution-state)
              (engine-rpc-with-phase-timing ("fcuPrivateCandidateMs")
                (build-private-block-candidate
                 store
                 (lambda ()
                   (multiple-value-bind (built receipts state stopped)
                       (engine-rpc-build-selected-payload-detached
                        store parent-block payload-attributes config
                        candidates
                        :gas-limit-target gas-limit-target
                        :extra-data extra-data
                        :stop-predicate stop-predicate)
                     (setf stopped-p stopped)
                     (values built receipts state)))
                 config))
            (declare (ignore receipts))
            (values block
                    (copy-list (block-transactions block))
                    execution-state
                    stopped-p))))))

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

(defun engine-rpc-block-value (block)
  "What BLOCK pays its fee recipient in priority fees, in wei."
  (let ((base-fee (or (block-header-base-fee-per-gas (block-header block)) 0))
        (previous-cumulative-gas 0))
    (loop for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for cumulative-gas = (receipt-cumulative-gas-used receipt)
          sum (* (- cumulative-gas previous-cumulative-gas)
                 (transaction-priority-fee-per-gas
                  transaction :base-fee base-fee))
          do (setf previous-cumulative-gas cumulative-gas))))

(defun engine-rpc-prepared-payload-revision
    (prepared-payload &key block blobs-bundle candidate-transactions-root
                           execution-state)
  "A copy of the open PREPARED-PAYLOAD under the same id with a new build."
  (make-engine-prepared-payload
   :payload-id (engine-prepared-payload-payload-id prepared-payload)
   :version (engine-prepared-payload-version prepared-payload)
   :block block
   :blobs-bundle blobs-bundle
   :parent-hash (engine-prepared-payload-parent-hash prepared-payload)
   :payload-attributes
   (engine-prepared-payload-payload-attributes prepared-payload)
   :gas-limit-target
   (engine-prepared-payload-gas-limit-target prepared-payload)
   :candidate-transactions-root candidate-transactions-root
   :execution-state execution-state
   :open-p t))

(defun engine-rpc-improve-prepared-payload
    (store config prepared-payload &key stop-predicate)
  "Rebuild an open payload from the latest txpool contents under the same id.

The more valuable of the new build and the current one is kept, as geth's
payload loop keeps its highest-fee block (miner/payload_building.go), so a
pass cut short by STOP-PREDICATE can never make the payload worse.  Such a
pass also leaves the pool unmarked as seen, so the next pass rebuilds it.

Returns (VALUES PAYLOAD STOPPED-P): the payload now stored under the id, and
whether this pass was cut short."
  (unless (typep prepared-payload 'engine-prepared-payload)
    (block-validation-fail "Payload improvement requires a prepared payload"))
  (if (not (engine-prepared-payload-open-p prepared-payload))
      (values prepared-payload nil)
      (let* ((parent-block
               (chain-store-known-block
                store
                (engine-prepared-payload-parent-hash prepared-payload)))
             (transactions
               (engine-rpc-pending-build-transactions
                store config (block-header parent-block)))
             (candidate-root (transaction-list-root transactions))
             (seen-root
               (engine-prepared-payload-candidate-transactions-root
                prepared-payload)))
        (if (hash32= candidate-root seen-root)
            (values prepared-payload nil)
            (multiple-value-bind
                  (block viable-transactions execution-state stopped-p)
                (engine-rpc-build-viable-prepared-payload
                 store
                 parent-block
                 (engine-prepared-payload-payload-attributes prepared-payload)
                 config
                 transactions
                 :gas-limit-target
                 (engine-prepared-payload-gas-limit-target prepared-payload)
                 :stop-predicate stop-predicate)
              (let* ((current-block
                       (engine-prepared-payload-block prepared-payload))
                     (value (engine-rpc-block-value block))
                     (current-value (engine-rpc-block-value current-block))
                     (next
                       (cond
                         ((if stopped-p
                              (> value current-value)
                              (>= value current-value))
                          (engine-rpc-prepared-payload-revision
                           prepared-payload
                           :block block
                           :blobs-bundle
                           (engine-rpc-blobs-bundle-for-transactions
                            store viable-transactions)
                           :candidate-transactions-root
                           (if stopped-p seen-root candidate-root)
                           :execution-state execution-state))
                         (stopped-p nil)
                         ;; A complete pass over this pool found nothing
                         ;; better: keep the block (and, by its unchanged
                         ;; hash, its private post-state) and mark the pool
                         ;; seen.
                         (t
                          (engine-rpc-prepared-payload-revision
                           prepared-payload
                           :block current-block
                           :blobs-bundle
                           (engine-prepared-payload-blobs-bundle
                            prepared-payload)
                           :candidate-transactions-root candidate-root)))))
                (if next
                    (progn
                      (chain-store-put-prepared-payload
                       store next
                       :transfer-execution-state-p (and execution-state t))
                      (values next stopped-p))
                    (values prepared-payload stopped-p))))))))

(defun engine-rpc-improve-open-payloads (store config &key stop-predicate)
  "Improve every payload that has not yet been retrieved.

Returns true when STOP-PREDICATE cut a pass short, so the caller knows the
pool was not fully considered."
  (let ((stopped-p nil))
    (dolist (prepared-payload
             (chain-store-prepared-payloads
              store :copy-execution-state-p nil))
      (when (and (engine-prepared-payload-open-p prepared-payload)
                 (not stopped-p))
        (multiple-value-bind (payload stopped)
            (engine-rpc-improve-prepared-payload
             store config prepared-payload :stop-predicate stop-predicate)
          (declare (ignore payload))
          (when stopped
            (setf stopped-p t)))))
    stopped-p))

(defun engine-rpc-persist-forkchoice
    (store transition forkchoice-persistence-function)
  (when forkchoice-persistence-function
    (engine-rpc-with-phase-timing ("fcuPersistenceMs")
      (handler-case
          (funcall forkchoice-persistence-function store transition)
        (storage-error (condition)
          (error condition))
        (error (condition)
          (storage-fail "Forkchoice persistence failed: ~A" condition))))))

(defun engine-rpc-prepared-payload-version
    (forkchoice-version payload-attributes config block-number timestamp)
  (case forkchoice-version
    (1
     (if (chain-config-shanghai-p config block-number timestamp)
         (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                          "forkchoiceUpdatedV1 is unsupported after Shanghai")
         1))
    (2
     (cond
       ((chain-config-cancun-p config block-number timestamp)
        (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                         "forkchoiceUpdatedV2 is unsupported after Cancun"))
       ((and (chain-config-shanghai-p config block-number timestamp)
             (not (payload-attributes-v1-withdrawals-present-p
                   payload-attributes)))
        (engine-rpc-fail
         +engine-rpc-error-invalid-payload-attributes+
         "forkchoiceUpdatedV2 requires withdrawals after Shanghai"))
       ((and (not (chain-config-shanghai-p config block-number timestamp))
             (payload-attributes-v1-withdrawals-present-p payload-attributes))
        (engine-rpc-fail
         +engine-rpc-error-invalid-payload-attributes+
         "forkchoiceUpdatedV2 does not support withdrawals before Shanghai"))
       (t 2)))
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
     &key forkchoice-persistence-function gas-limit-target
          payload-improvement-notification-function (max-params 2))
  (unless (and (listp params) (<= 1 (length params) max-params))
    (block-validation-fail
     "~A params must contain forkchoice state and optional payload attributes"
     method))
  (let ((state
          (engine-rpc-forkchoice-state-from-object
           (json-rpc-required-param
            params 0 "forkchoiceState" method)))
        (payload-attributes
          (when (< 1 (length params))
            (let ((value (second params)))
              (unless (json-null-p value)
                value)))))
    (let ((status
            (engine-rpc-with-phase-timing ("fcuStatusMs")
              (engine-forkchoice-memory-status store state)))
          (payload-id nil)
          (validated-payload-attributes nil)
          (prepared-payload-version nil)
          (payload-attributes-error nil))
      (when (string= +payload-status-valid+
                     (payload-status-status status))
        (engine-rpc-with-phase-timing ("fcuValidationMs")
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
          ;; Decode attributes before publication, but defer their RPC error
          ;; until after the valid forkchoice state is applied.  The Engine API
          ;; orders forkchoice application before payload-attribute validation.
          (when payload-attributes
            (handler-case
                (progn
                  (setf validated-payload-attributes
                        (funcall payload-attributes-parser payload-attributes))
                  (let* ((head-hash (forkchoice-state-head-block-hash state))
                         (parent-block
                           (chain-store-known-block store head-hash))
                         (parent-header (block-header parent-block))
                         (block-number
                           (1+ (block-header-number parent-header))))
                    (setf prepared-payload-version
                          (engine-rpc-prepared-payload-version
                           payload-version validated-payload-attributes config
                           block-number
                           (payload-attributes-v1-timestamp
                            validated-payload-attributes)))))
              (block-validation-error (condition)
                (setf payload-attributes-error
                      (make-condition
                       'engine-rpc-error
                       :code +engine-rpc-error-invalid-payload-attributes+
                       :message (block-validation-error-message condition))))
              (engine-rpc-error (condition)
                (setf payload-attributes-error condition)))))
        (engine-rpc-with-phase-timing ("fcuCanonicalMs")
          (publish-canonical-block
           store
           (forkchoice-state-head-block-hash state)
           config
           :authority :engine-forkchoice
           :forkchoice-state state
           :durability-function
           (and
            forkchoice-persistence-function
            (lambda (callback-store transition)
              (engine-rpc-persist-forkchoice
               callback-store transition forkchoice-persistence-function))))))
        (when payload-attributes-error
          (error payload-attributes-error))
      (when (and payload-attributes
                 (string= +payload-status-valid+
                          (payload-status-status status)))
        (let* ((payload-attributes validated-payload-attributes)
               (head-hash (forkchoice-state-head-block-hash state))
               (parent-block
                 (chain-store-known-block store head-hash))
               (candidate-id
                 (engine-payload-id
                  prepared-payload-version head-hash payload-attributes)))
          ;; A repeated build request keeps the stable id.  An open build
          ;; continues improving in place; a payload already retrieved is
          ;; explicitly reopened from an empty candidate for the new request.
          (engine-rpc-with-phase-timing ("fcuBuildMs")
            (unless
                (let ((existing
                        (engine-rpc-with-phase-timing
                            ("fcuPreparedLookupMs")
                          (chain-store-prepared-payload
                           store candidate-id :copy-execution-state-p nil))))
                  (and existing
                       (engine-prepared-payload-open-p existing)))
              (multiple-value-bind
                    (block viable-transactions execution-state)
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
                (engine-rpc-with-phase-timing ("fcuPreparedStoreMs")
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
                    :execution-state execution-state
                    :open-p t)
                   :transfer-execution-state-p t)))))
          (setf payload-id candidate-id)
          ;; The initial empty payload is now visible. Wake the production
          ;; builder after publication so it can fill from the txpool while the
          ;; proposer waits before getPayload. The callback is deliberately
          ;; advisory: scheduler failure cannot invalidate an applied FCU.
          (when payload-improvement-notification-function
            (engine-rpc-with-phase-timing ("fcuNotifyMs")
              (ignore-errors
               (funcall payload-improvement-notification-function))))))
      (engine-rpc-forkchoice-response-object
       status
       :payload-id payload-id))))

(defun engine-rpc-handle-forkchoice-updated-v1
    (params store config &key forkchoice-persistence-function gas-limit-target
                              payload-improvement-notification-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV1" 1
   (lambda (payload-attributes)
     (engine-rpc-validate-payload-attributes-v1
      payload-attributes :method "engine_forkchoiceUpdatedV1"))
   :forkchoice-persistence-function forkchoice-persistence-function
   :payload-improvement-notification-function
   payload-improvement-notification-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v2
    (params store config &key forkchoice-persistence-function gas-limit-target
                              payload-improvement-notification-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV2" 2
   #'engine-rpc-validate-payload-attributes-v2
   :forkchoice-persistence-function forkchoice-persistence-function
   :payload-improvement-notification-function
   payload-improvement-notification-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v3
    (params store config &key forkchoice-persistence-function gas-limit-target
                              payload-improvement-notification-function)
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV3" 3
   #'engine-rpc-validate-payload-attributes-v3
   :forkchoice-persistence-function forkchoice-persistence-function
   :payload-improvement-notification-function
   payload-improvement-notification-function
   :gas-limit-target gas-limit-target))

(defun engine-rpc-handle-forkchoice-updated-v4
    (params store config &key forkchoice-persistence-function gas-limit-target
                              payload-improvement-notification-function)
  (when (> (length params) 3)
    (block-validation-fail
     "engine_forkchoiceUpdatedV4 accepts at most three parameters"))
  (when (and (= 3 (length params))
             (not (json-null-p (third params))))
    (let ((custody-columns
            (json-rpc-bytes
             (third params)
             "engine_forkchoiceUpdatedV4 custodyColumns")))
      (unless (= 16 (length custody-columns))
        (block-validation-fail
         "engine_forkchoiceUpdatedV4 custodyColumns must be 16 bytes"))))
  (engine-rpc-handle-forkchoice-updated
   params store config "engine_forkchoiceUpdatedV4" 4
   #'engine-rpc-validate-payload-attributes-v4
   :max-params 3
   :forkchoice-persistence-function forkchoice-persistence-function
   :payload-improvement-notification-function
   payload-improvement-notification-function
   :gas-limit-target gas-limit-target))
