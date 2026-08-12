(in-package #:ethereum-lisp.block-import)

;;;; The single application boundary for admitting execution-layer blocks.
;;;;
;;;; Adapters decode wire or disk formats before entering here.  This service
;;;; owns consensus validation, execution, candidate publication, durability,
;;;; and canonical-authority checks.  Callers sharing a live store must still
;;;; hold their node's store guard: CHAIN-STORE-ATOMIC-COMMIT is a rollback
;;;; boundary, not a reader/writer lock.

(defparameter +block-import-sources+
  '(:engine :p2p :staged :local :dev-period :direct)
  "Ingress sources accepted by the candidate import service.")

(defun block-import-ensure-function (function label)
  (when (and function (not (functionp function)))
    (block-validation-fail "~A must be a function or NIL" label))
  function)

(defun block-import-ensure-source (source &optional executable-payload-p)
  (unless (member source
                  (if executable-payload-p
                      '(:engine :p2p)
                      +block-import-sources+))
    (block-validation-fail "Unsupported block import source ~S" source))
  source)

(defun block-import-recent-ancestor-blocks (store parent &optional (limit 7))
  "Return PARENT and up to LIMIT-1 older ancestors, newest first."
  (loop with current = parent
        repeat limit
        while current
        collect current
        do (let ((header (block-header current)))
             (setf current
                   (and (plusp (block-header-number header))
                        (chain-store-known-block
                         store (block-header-parent-hash header)))))))

(defun block-import-block-versioned-hashes (block)
  (loop for transaction in (block-transactions block)
        append (coerce (transaction-blob-versioned-hashes transaction) 'list)))

(defun block-import-validate-sidecar (block sidecar)
  (when sidecar
    (unless (typep sidecar 'blob-sidecar)
      (block-validation-fail "Block sidecar must be a blob-sidecar"))
    ;; Proof unavailability is deliberately allowed to escape as a capability
    ;; failure.  VALIDATE-BLOB-SIDECAR-FIELDS translates only deterministic bad
    ;; proofs to BLOCK-VALIDATION-ERROR.
    (validate-blob-sidecar-fields sidecar :require-proof-verification t)
    (let ((expected (block-import-block-versioned-hashes block))
          (actual (blob-sidecar-versioned-hashes sidecar)))
      (unless (= (length expected) (length actual))
        (block-validation-fail
         "Block blob hash count does not match its sidecar"))
      (loop for expected-hash in expected
            for actual-hash in actual
            for index from 0
            unless (hash32= expected-hash actual-hash)
              do (block-validation-fail
                  "Block blob hash ~D does not match its sidecar" index))))
  t)

(defun block-import-validate-p2p-bundle-commitments (block)
  "Prove a peer body belongs to BLOCK's immutable header before verdict caching.

This intentionally checks only header/body commitments. Fork limits, transaction
validity, ommer ancestry, and execution remain inside the consensus-invalid
handler because those faults are properties of the committed block itself."
  (let* ((header (block-header block))
         (transactions (block-transactions block))
         (ommers (block-ommers block))
         (withdrawals-present-p (block-withdrawals-present-p block))
         (requests-present-p (block-requests-present-p block))
         (bal-present-p (block-block-access-list-present-p block))
         (actual-blob-gas (blob-gas-used transactions)))
    (unless (hash32= (ethereum-lisp.receipts:transaction-list-root
                      transactions)
                     (block-header-transactions-root header))
      (block-validation-fail "P2P body transaction root mismatch"))
    (unless (hash32= (ommers-hash ommers)
                     (block-header-ommers-hash header))
      (block-validation-fail "P2P body ommers root mismatch"))
    (cond
      ((block-header-withdrawals-root header)
       (unless withdrawals-present-p
         (block-validation-fail "P2P body is missing committed withdrawals"))
       (unless (hash32= (ethereum-lisp.receipts:withdrawal-list-root
                         (block-withdrawals block))
                        (block-header-withdrawals-root header))
         (block-validation-fail "P2P body withdrawals root mismatch")))
      (withdrawals-present-p
       (block-validation-fail
        "P2P body supplies withdrawals absent from its header")))
    (when requests-present-p
      (unless (and (block-header-requests-hash header)
                   (hash32=
                    (ethereum-lisp.execution-requests:execution-requests-hash
                     (block-requests block))
                    (block-header-requests-hash header)))
        (block-validation-fail
         "P2P body execution requests do not match its header")))
    (when bal-present-p
      (unless (and
               (block-header-block-access-list-hash header)
               (hash32= (validated-block-access-list-commitment block)
                        (block-header-block-access-list-hash header)))
        (block-validation-fail
         "P2P body block access list does not match its header")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= actual-blob-gas (block-header-blob-gas-used header))
         (block-validation-fail "P2P body blob gas does not match its header")))
      ((plusp actual-blob-gas)
       (block-validation-fail
        "P2P body has blob transactions absent from its header"))))
  t)

(defun block-import-validate-candidate (store block config &key sidecar)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Candidate import value must be an Ethereum block"))
  (let* ((header (block-header block))
         (number (block-header-number header)))
    ;; Genesis construction has its own state-root and configuration service.
    ;; Treating a network-supplied block zero as an ordinary child would skip
    ;; the parent/header half of consensus validation.
    (unless (plusp number)
      (block-validation-fail "Candidate import cannot replace genesis"))
    (let* ((parent-hash (block-header-parent-hash header))
           (parent (chain-store-known-block store parent-hash)))
      (unless parent
        (state-unavailable-fail "Candidate block parent is unavailable"))
      (let ((ancestors
              (block-import-recent-ancestor-blocks store parent)))
        (validate-block-against-config
         (block-header parent)
         block
         config
         :ancestor-blocks (rest ancestors)))
      (engine-new-payload-require-transaction-senders block config)
      (block-import-validate-sidecar block sidecar)
      parent)))

(define-condition block-import-private-candidate-ready (error)
  ((block
    :initarg :block
    :reader block-import-private-candidate-ready-block)
   (receipts
    :initarg :receipts
    :reader block-import-private-candidate-ready-receipts))
  (:report
   (lambda (condition stream)
     (declare (ignore condition))
     (write-string "Private block candidate validation completed" stream))))

(defun build-private-block-candidate
    (store block-or-builder config &key sidecar)
  "Build and validate a detached block without publishing it to STORE.

BLOCK-OR-BUILDER is a fully formed block or a trusted zero-argument detached
state builder returning a block and optional receipts.  Parent/header/body,
ommers, transaction senders, and an optional blob sidecar are validated through
the common candidate validator.  The entire operation is deliberately rolled
back after successful validation, so accidental candidate, state, canonical,
txpool, or prepared-cache writes made by the builder cannot become visible.

The builder must not perform external side effects: only in-memory STORE writes
participate in the rollback.  Returns the detached block and builder receipts."
  (unless (or (functionp block-or-builder)
              (typep block-or-builder 'ethereum-block))
    (block-validation-fail
     "Private candidate must be an Ethereum block or builder function"))
  ;; A successful build is carried out of CHAIN-STORE-ATOMIC-COMMIT with a
  ;; private condition. Its non-local-exit cleanup rolls back the journal and
  ;; volatile slots before this outer handler converts it back to values.
  (handler-case
      (chain-store-atomic-commit
       store
       (lambda ()
         (multiple-value-bind (block receipts)
             (if (functionp block-or-builder)
                 (funcall block-or-builder)
                 (values block-or-builder nil))
           (block-import-validate-candidate
            store block config :sidecar sidecar)
           (error 'block-import-private-candidate-ready
                  :block block
                  :receipts receipts))))
    (block-import-private-candidate-ready (condition)
      (values
       (block-import-private-candidate-ready-block condition)
       (block-import-private-candidate-ready-receipts condition)))))

(defun block-import-require-executor-publication
    (store input-block candidate)
  "Verify that an injected executor published exactly INPUT-BLOCK with state."
  (unless (typep candidate 'ethereum-block)
    (storage-fail "Candidate executor did not return an Ethereum block"))
  (let* ((expected-hash (block-hash input-block))
         (candidate-hash (block-hash candidate))
         (stored (chain-store-known-block store expected-hash)))
    (unless (hash32= expected-hash candidate-hash)
      (storage-fail "Candidate executor returned a different block hash"))
    (unless (and stored
                 (hash32= expected-hash (block-hash stored)))
      (storage-fail "Candidate executor did not publish the returned block"))
    (unless (chain-store-state-available-p store expected-hash)
      (storage-fail "Candidate executor did not publish block state")))
  candidate)

(defun block-import-execute-candidate
    (store block config
     &key sidecar import-function (validate-sidecar-p t))
  "Validate and execute BLOCK as a hash-addressed, noncanonical candidate.

This is intentionally internal: every public entry point supplies the outer
rollback boundary and calls durability only after this function has completed."
  (block-import-validate-candidate
   store block config :sidecar (and validate-sidecar-p sidecar))
  (let* ((hash (block-hash block))
         (known (chain-store-known-block store hash)))
    (multiple-value-bind (candidate receipts)
        (if (and known (chain-store-state-available-p store hash))
            ;; A durable replay must not execute the completed range again, but
            ;; it still passed the full validation above and is persisted again
            ;; by the public wrapper so a prior response-loss is idempotent.
            (values known (chain-store-block-receipts store hash))
            (multiple-value-bind (imported receipts)
                (funcall
                 (or import-function
                     #'ethereum-lisp.execution-service:execute-and-commit-engine-payload)
                 store block config)
              (block-import-require-executor-publication
               store block imported)
              (values imported receipts)))
      ;; Keep sidecar publication in the same rollback frame as block/state.
      ;; The store repeats proof validation as defense in depth before exposing
      ;; data to getBlobs or devp2p consumers.
      (when sidecar
        (engine-payload-store-put-blob-sidecar
         store sidecar
         :block-number
         (block-header-number (block-header candidate))))
      (values candidate receipts))))

(defun block-import-call-candidate-durability
    (function store candidate source candidate-kind payload-status
     progress progress-supplied-p)
  (when function
    ;; Executed candidates preserve the existing two-argument callback unless
    ;; PROGRESS opts into provenance. Buffered candidates always identify their
    ;; kind: a durable adapter must select its remote-block/sync-target exporter
    ;; instead of the stateful candidate exporter.
    (if (or progress-supplied-p
            (member candidate-kind '(:buffered :invalid)))
        (apply function
               store
               candidate
               (append
                (list :source source
                      :candidate-kind candidate-kind
                      :payload-status payload-status)
                (when progress-supplied-p
                  (list :progress progress))))
        (funcall function store candidate))))

(defun import-block-candidate
    (store block config
     &key (source :direct)
          sidecar
          durability-function
          (progress nil progress-supplied-p))
  "Validate, execute, and durably admit BLOCK without changing canonical view.

Returns the admitted block and its receipts.  DURABILITY-FUNCTION is invoked
last, inside the rollback frame.  An executed candidate without PROGRESS uses
the legacy two arguments (STORE CANDIDATE).  PROGRESS opts into :SOURCE,
:CANDIDATE-KIND, :PAYLOAD-STATUS, and :PROGRESS."
  (block-import-ensure-source source)
  (block-import-ensure-function durability-function "Candidate durability callback")
  (chain-store-atomic-commit
   store
   (lambda ()
     (multiple-value-bind (candidate receipts)
         (block-import-execute-candidate store block config :sidecar sidecar)
       (block-import-call-candidate-durability
        durability-function store candidate source :executed nil
        progress progress-supplied-p)
       (values candidate receipts)))))

(defun block-import-make-valid-status (candidate)
  (make-payload-status
   :status +payload-status-valid+
   :latest-valid-hash (block-hash candidate)))

(defun block-import-make-buffered-status (status)
  (make-payload-status :status status))

(defun block-import-make-invalid-status (parent condition)
  (make-payload-status
   :status +payload-status-invalid+
   :latest-valid-hash (and parent (block-hash parent))
   :validation-error
   (etypecase condition
     (block-validation-error
      (block-validation-error-message condition))
     (ethereum-lisp.execution:transaction-validation-error
      (ethereum-lisp.execution:transaction-validation-error-message
       condition)))))

(defun block-import-validate-bufferable-p2p-block
    (block config &key sidecar)
  "Validate every peer-block property available before execution.

When PARENT is absent the parent-relative header rules necessarily wait for
gap fill, but the canonical body roots, fork body shape, transaction senders,
and optional blob sidecar are still checked before the block enters the remote
cache.  Execution requests and Amsterdam block access lists are intentionally
allowed to be absent: eth BlockBodies does not carry that execution-derived
side data, and the execution kernel validates the header commitments after it
derives them."
  (unless (typep block 'ethereum-block)
    (block-validation-fail "P2P candidate must be an Ethereum block"))
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header)))
    (validate-block-header-field-shapes header :require-parent-hash-p t)
    (unless (plusp number)
      (block-validation-fail "P2P candidate cannot replace genesis"))
    (validate-block-merge-fields
     header :post-merge-p (chain-config-post-merge-p config number))
    (validate-block-withdrawals-field
     header :withdrawals-enabled-p
     (chain-config-shanghai-p config number timestamp))
    (validate-block-cancun-fields
     header :cancun-enabled-p
     (chain-config-cancun-p config number timestamp))
    (validate-block-requests-hash-field
     header :requests-enabled-p
     (chain-config-prague-p config number timestamp))
    (validate-block-amsterdam-fields
     header :amsterdam-enabled-p
     (chain-config-amsterdam-p config number timestamp))
    (validate-block-dao-extra-data header config))
  (validate-block-body-against-config block config)
  (engine-new-payload-require-transaction-senders block config)
  (block-import-validate-sidecar block sidecar)
  t)

(defun block-import-buffer-p2p-candidate
    (store block config parent sidecar status)
  ;; Parent-relative validation is possible for ACCEPTED candidates.  A
  ;; missing-parent SYNCING target still receives all standalone body checks.
  (if parent
      (block-import-validate-candidate
       store block config)
      (block-import-validate-bufferable-p2p-block
       block config))
  (engine-payload-store-put-remote-block store block)
  (when sidecar
    (engine-payload-store-put-blob-sidecar
     store sidecar
     :block-number (block-header-number (block-header block))))
  (let ((payload-status (block-import-make-buffered-status status)))
    (values payload-status block nil)))

(defun block-import-persistable-status-p (status)
  (member (payload-status-status status)
          (list +payload-status-valid+
                +payload-status-accepted+
                +payload-status-syncing+)
          :test #'string=))

(defun block-import-status-candidate-kind (status)
  (if (string= +payload-status-valid+ (payload-status-status status))
      :executed
      :buffered))

(defun import-p2p-block-candidate
    (store block config
     &key sidecar import-function durability-function
          (progress nil progress-supplied-p))
  "Admit a typed eth-wire BLOCK as a durable, noncanonical candidate.

Unlike Engine payloads, an eth BlockBodies response has no execution requests
and (on Amsterdam) no block access list.  This entry point therefore preserves
the typed canonical header/body and lets execution derive and verify those
commitments.  Missing-parent and missing-state blocks are durably buffered and
return SYNCING or ACCEPTED.  Deterministic consensus failures return INVALID;
storage, capability, and unknown program failures propagate and roll back.

Returns PAYLOAD-STATUS, candidate block, and receipts."
  (block-import-ensure-function durability-function
                                "P2P candidate durability callback")
  (block-import-ensure-function import-function "P2P candidate executor")
  (chain-store-atomic-commit
   store
   (lambda ()
     (unless (typep block 'ethereum-block)
       (block-validation-fail "P2P candidate must be an Ethereum block"))
     (let ((header (block-header block)))
       (validate-block-header-field-shapes header :require-parent-hash-p t)
       ;; A bad bundle says nothing about the validity of the block it claims
       ;; to accompany.  Validate it before entering the consensus-invalid
       ;; classification handler below.
       (block-import-validate-sidecar block sidecar)
       ;; A downloaded body is a peer-supplied bundle for the immutable header.
       ;; Its roots must match before any block-hash INVALID verdict is cached;
       ;; otherwise a peer could pair a real header with a false body and poison
       ;; that real hash for all later peers.
       (block-import-validate-p2p-bundle-commitments block)
       (let* ((number (block-header-number header))
              (hash (block-hash block))
              (parent-hash (block-header-parent-hash header))
              (parent
                (and (plusp number)
                     (chain-store-known-block store parent-hash))))
         (unless (plusp number)
           (block-validation-fail "P2P candidate cannot replace genesis"))
         (let ((invalid-status
                 (engine-payload-store-invalid-ancestor-status
                  store hash hash))
               (parent-invalid-status
                 (engine-payload-store-invalid-ancestor-status
                  store parent-hash hash)))
           (multiple-value-bind (status candidate receipts)
               (cond
                 (invalid-status
                  (values invalid-status nil nil))
                 (parent-invalid-status
                  (values parent-invalid-status nil nil))
                 (t
                  ;; Only validation/execution is classified as a consensus
                  ;; verdict.  Durability below is deliberately outside this
                  ;; handler: a database/invariant failure must escape and roll
                  ;; back, never poison the INVALID cache.
                  (handler-case
                      (cond
                        ((null parent)
                         (block-import-buffer-p2p-candidate
                          store block config nil sidecar
                          +payload-status-syncing+))
                        ((not (chain-store-state-available-p
                               store (block-hash parent)))
                         (block-import-buffer-p2p-candidate
                          store block config parent sidecar
                          +payload-status-accepted+))
                        (t
                         (multiple-value-bind (executed receipts)
                             (block-import-execute-candidate
                              store block config :sidecar sidecar
                              :validate-sidecar-p nil
                              :import-function import-function)
                           (values
                            (block-import-make-valid-status executed)
                            executed receipts))))
                    (state-unavailable-error ()
                      (block-import-buffer-p2p-candidate
                       store block config parent sidecar
                       +payload-status-syncing+))
                    (block-validation-error (condition)
                      (engine-payload-store-mark-invalid store block)
                      (values
                       (block-import-make-invalid-status parent condition)
                       nil nil))
                    (ethereum-lisp.execution:transaction-validation-error
                        (condition)
                      (engine-payload-store-mark-invalid store block)
                      (values
                       (block-import-make-invalid-status parent condition)
                       nil nil)))))
             (when (and candidate
                        (block-import-persistable-status-p status))
               (block-import-call-candidate-durability
                durability-function store candidate :p2p
                (block-import-status-candidate-kind status)
                status progress progress-supplied-p))
             ;; This common path also covers a cached self/ancestor verdict.  It
             ;; lets a durable adapter remove a stale buffered copy even when no
             ;; execution is attempted on this replay.
             (when (string= +payload-status-invalid+
                            (payload-status-status status))
               (block-import-call-candidate-durability
                durability-function store block :p2p :invalid status nil nil))
             (values status candidate receipts))))))))

(defun import-executable-payload
    (store version payload config
     &key (source :engine)
          (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p)
          sidecar
          import-function
          durability-function
          (progress nil progress-supplied-p))
  "Admit an Engine-format payload from Engine RPC or P2P.

The V1--V5 optional-argument suppliedness is preserved exactly.  Returns
PAYLOAD-STATUS, candidate block, and receipts.  VALID candidates (including
known replays) and ACCEPTED/SYNCING buffered blocks all run the durability
callback.  Storage and local capability failures escape and roll back; they are
never converted into INVALID payload verdicts."
  (block-import-ensure-source source t)
  (block-import-ensure-function import-function "Candidate executor")
  (block-import-ensure-function durability-function "Payload durability callback")
  (chain-store-atomic-commit
   store
   (lambda ()
     (let ((kernel-ran-p nil)
           (imported-receipts nil)
           (wire-block nil))
       ;; Keep the typed block available even when the memory status later
       ;; returns INVALID.  The durability sink then can atomically remove a
       ;; previously buffered record for the same hash.  This preflight has no
       ;; store mutation; the status layer repeats its own defense-in-depth
       ;; checks below.
       (multiple-value-bind (wire-status decoded-block)
           (apply
            #'engine-new-payload-version-status
            version payload config
            (append
             (when parent-beacon-root-supplied-p
               (list :parent-beacon-root parent-beacon-root))
             (when versioned-hashes-supplied-p
               (list :versioned-hashes versioned-hashes))
             (when requests-supplied-p
               (list :requests requests))))
         (declare (ignore wire-status))
         (setf wire-block decoded-block))
       ;; Bundle/proof failure is not a consensus verdict on WIRE-BLOCK.  Keep
       ;; this outside ENGINE-NEW-PAYLOAD-MEMORY-STATUS's block-invalid handler.
       (when wire-block
         (block-import-validate-sidecar wire-block sidecar))
       (flet ((import-candidate (candidate-store candidate candidate-config)
                (multiple-value-prog1
                    (multiple-value-bind (imported receipts)
                        (block-import-execute-candidate
                         candidate-store candidate candidate-config
                         :sidecar sidecar
                         :validate-sidecar-p nil
                         :import-function import-function)
                      (setf imported-receipts receipts)
                      (values imported receipts))
                  (setf kernel-ran-p t))))
         (multiple-value-bind (status candidate)
             (apply
              #'engine-new-payload-memory-status
              store version payload config
              (append
               (list :import-function #'import-candidate)
               (when parent-beacon-root-supplied-p
                 (list :parent-beacon-root parent-beacon-root))
               (when versioned-hashes-supplied-p
                 (list :versioned-hashes versioned-hashes))
               (when requests-supplied-p
                 (list :requests requests))))
           (let ((persistable-p
                   (and candidate
                        (block-import-persistable-status-p status))))
             (when persistable-p
               ;; Known VALID replays bypass the execution callback, but still
               ;; cross the complete service validation boundary. Buffered
               ;; candidates cannot validate against a missing parent yet;
               ;; their wire shape was checked by the Engine status layer, and
               ;; supplied sidecars are independently validated here.
               (when (not kernel-ran-p)
                 (if (string= +payload-status-valid+
                              (payload-status-status status))
                     (block-import-validate-candidate
                      store candidate config))
                 (when sidecar
                   (engine-payload-store-put-blob-sidecar
                    store sidecar
                    :block-number
                    (block-header-number (block-header candidate))))))
             ;; Resolve replay receipts before durability. The callback is the
             ;; final fallible/store-observing operation in this service: after
             ;; it returns, only already-computed values leave the boundary.
             (let ((returned-receipts
                     (or imported-receipts
                         (and candidate
                              (string= +payload-status-valid+
                                       (payload-status-status status))
                              (chain-store-block-receipts
                               store (block-hash candidate))))))
               (when persistable-p
                 (block-import-call-candidate-durability
                  durability-function
                  store
                  candidate
                  source
                  (block-import-status-candidate-kind status)
                  status
                  progress
                  progress-supplied-p))
               (when (and wire-block
                          (string= +payload-status-invalid+
                                   (payload-status-status status)))
                 (block-import-call-candidate-durability
                  durability-function store wire-block source :invalid status
                  nil nil))
               (values status candidate returned-receipts)))))))))

(defun block-import-normalize-block-hash (block-or-hash)
  (typecase block-or-hash
    (ethereum-block (block-hash block-or-hash))
    (hash32 block-or-hash)
    (t (block-validation-fail
        "Canonical publication target must be a block or hash32"))))

(defun block-import-checkpoint-hash-or-zero (checkpoint)
  (or (and checkpoint (chain-store-checkpoint-block-hash checkpoint))
      (zero-hash32)))

(defun block-import-local-forkchoice-state (store head-hash)
  (make-forkchoice-state
   :head-block-hash head-hash
   :safe-block-hash
   (block-import-checkpoint-hash-or-zero
    (chain-store-safe-checkpoint store))
   :finalized-block-hash
   (block-import-checkpoint-hash-or-zero
    (chain-store-finalized-checkpoint store))))

(defun block-import-publication-state
    (store hash authority forkchoice-state)
  (let ((state
          (or forkchoice-state
              (and (eq authority :local-dev)
                   (block-import-local-forkchoice-state store hash)))))
    (unless (typep state 'forkchoice-state)
      (block-validation-fail
       "Engine canonical publication requires a forkchoice state"))
    (unless (hash32= hash (forkchoice-state-head-block-hash state))
      (block-validation-fail
       "Canonical target must equal the forkchoice head"))
    state))

(defun block-import-authorize-publication
    (authority config block local-dev-authorized-p)
  (case authority
    (:engine-forkchoice t)
    (:local-dev
     (when (and (chain-config-post-merge-p
                 config (block-header-number (block-header block)))
                (not local-dev-authorized-p))
       (block-validation-fail
        "Post-Merge local publication requires explicit dev-mode authority"))
     t)
    (otherwise
     (block-validation-fail
      "Unsupported canonical publication authority ~S" authority))))

(defun block-import-call-finality-prune
    (store function finalized-number now now-supplied-p)
  (apply (or function #'engine-payload-store-prune-caches)
         store
         (append
          (when now-supplied-p (list :now now))
          (list :finalized-number finalized-number))))

(defun block-import-call-publication-durability
    (function store transition authority forkchoice-state
     progress progress-supplied-p)
  (when function
    (if progress-supplied-p
        (funcall function store transition
                 :authority authority
                 :forkchoice-state forkchoice-state
                 :progress progress)
        (funcall function store transition))))

(defconstant +block-import-maximum-snap-tail-length+ 64)

(defun install-forkchoice-sync-pivot
    (store pivot-or-hash target-or-hash config
     &key consensus-authorized-p durability-function)
  "Atomically install a sparse snap pivot anchored by an Engine target.

TARGET-OR-HASH is the head hash previously supplied by a consensus client.
Every header from the pivot through that target must already be known, so the
target hash cryptographically commits to the pivot.  The pivot's verified state
must also be available, and the executable tail is capped at 64 blocks.

This operation is not a general canonicalization escape hatch.  Its sole
production caller sets CONSENSUS-AUTHORIZED-P only after matching durable snap
skeleton/state progress to the current Engine target.  DURABILITY-FUNCTION is
called last and receives :SYNC-PIVOT-TARGET-HASH; any failure rolls the sparse
canonical view back.  The target itself remains noncanonical until a later
forkchoiceUpdated publication succeeds normally."
  (block-import-ensure-function durability-function
                                "Snap pivot durability callback")
  (unless consensus-authorized-p
    (block-validation-fail
     "Snap pivot installation requires explicit Engine target authority"))
  (unless durability-function
    (block-validation-fail
     "Snap pivot installation requires durable target-bound evidence"))
  (let ((pivot-hash (block-import-normalize-block-hash pivot-or-hash))
        (target-hash (block-import-normalize-block-hash target-or-hash)))
    (chain-store-atomic-commit
     store
     (lambda ()
       (let ((pivot (chain-store-known-block store pivot-hash))
             (target (chain-store-known-block store target-hash)))
         (unless pivot
           (block-validation-fail "Snap pivot block must be known"))
         (unless target
           (block-validation-fail "Snap target block must be known"))
         (let ((pivot-number
                 (block-header-number (block-header pivot)))
               (target-number
                 (block-header-number (block-header target))))
           (unless (and (<= pivot-number target-number)
                        (<= (- target-number pivot-number)
                            +block-import-maximum-snap-tail-length+))
             (block-validation-fail
              "Snap target executable tail exceeds 64 blocks"))
           (unless (engine-payload-store-ancestor-p
                    store pivot-hash target-hash)
             (block-validation-fail
              "Snap pivot is not an ancestor of the Engine target"))
           (unless (chain-store-state-available-p store pivot-hash)
             (block-validation-fail
              "Snap pivot state must be available"))
           (multiple-value-bind (head transition)
               (canonical-chain-install-sync-checkpoint
                store pivot-hash
                :expected-chain-id (chain-config-chain-id config)
                :chain-config config)
             (funcall durability-function
                      store transition
                      :sync-pivot-target-hash target-hash)
             (values head transition))))))))

(defun block-import-publish-canonical
    (store block-or-hash config authority forkchoice-state
     local-dev-authorized-p durability-function finality-prune-function
     now now-supplied-p progress progress-supplied-p)
  (let* ((hash (block-import-normalize-block-hash block-or-hash))
         (block (chain-store-known-block store hash)))
    (unless block
      (block-validation-fail
       "Canonical publication target must be a known block"))
    (block-import-authorize-publication
     authority config block local-dev-authorized-p)
    (let ((state
            (block-import-publication-state
             store hash authority forkchoice-state)))
      (chain-store-update-forkchoice-checkpoints store state)
      (multiple-value-bind (head transition)
          (chain-store-set-canonical-head
           store
           hash
           :expected-chain-id (chain-config-chain-id config)
           :chain-config config)
        (let ((finalized (chain-store-finalized-block store)))
          ;; Prune before persistence so the durable adapter can delete the same
          ;; finalized cache entries in its transition batch.
          (block-import-call-finality-prune
           store
           finality-prune-function
           (and finalized
                (block-header-number (block-header finalized)))
           now
           now-supplied-p))
        (block-import-call-publication-durability
         durability-function store transition authority state
         progress progress-supplied-p)
        (values head transition)))))

(defun publish-canonical-block
    (store block-or-hash config
     &key (authority :engine-forkchoice)
          forkchoice-state
          local-dev-authorized-p
          durability-function
          finality-prune-function
          (now nil now-supplied-p)
          (progress nil progress-supplied-p))
  "Atomically publish a known candidate as canonical.

Post-Merge publication accepts :ENGINE-FORKCHOICE, or :LOCAL-DEV only when
LOCAL-DEV-AUTHORIZED-P is explicitly true.  Pre-Merge local publication is
allowed.  The order inside one rollback frame is checkpoint update, canonical
transition, finality cache pruning, then durable transition callback."
  (block-import-ensure-function durability-function
                                "Canonical durability callback")
  (block-import-ensure-function finality-prune-function
                                "Finality cache prune callback")
  (chain-store-atomic-commit
   store
   (lambda ()
     (block-import-publish-canonical
      store block-or-hash config authority forkchoice-state
      local-dev-authorized-p durability-function finality-prune-function
      now now-supplied-p progress progress-supplied-p))))

(defun build-import-and-publish-block
    (store block-or-builder config
     &key (source :dev-period)
          sidecar
          (authority :local-dev)
          forkchoice-state
          local-dev-authorized-p
          durability-function
          finality-prune-function
          (now nil now-supplied-p)
          (progress nil progress-supplied-p))
  "Build/import a candidate and publish it within one rollback boundary.

BLOCK-OR-BUILDER is either a fully formed block or a zero-argument builder that
returns a block and optional receipts.  A dev-period builder may use the normal
local execution helper to derive roots; this service then applies the same full
candidate validation before the sole canonical publication step.  The durable
callback receives the canonical transition and is responsible for persisting
both the installed candidate and its canonical indexes in one batch."
  (block-import-ensure-source source)
  (block-import-ensure-function durability-function
                                "Canonical durability callback")
  (block-import-ensure-function finality-prune-function
                                "Finality cache prune callback")
  (chain-store-atomic-commit
   store
   (lambda ()
     (multiple-value-bind (built-block builder-receipts)
         (if (functionp block-or-builder)
             (funcall block-or-builder)
             (values block-or-builder nil))
       (multiple-value-bind (candidate receipts)
           (block-import-execute-candidate
            store built-block config :sidecar sidecar)
         (multiple-value-bind (head transition)
             (block-import-publish-canonical
              store candidate config authority forkchoice-state
              local-dev-authorized-p durability-function
              finality-prune-function now now-supplied-p
              progress progress-supplied-p)
           (values head (or receipts builder-receipts) transition)))))))
