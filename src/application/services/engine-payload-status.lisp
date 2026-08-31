(in-package #:ethereum-lisp.engine)

(defun engine-new-payload-version-status-for-request
    (version payload config
     parent-beacon-root parent-beacon-root-supplied-p
     versioned-hashes versioned-hashes-supplied-p
     requests requests-supplied-p)
  (apply #'engine-new-payload-version-status
         version
         payload
         config
         (append
          (when parent-beacon-root-supplied-p
            (list :parent-beacon-root parent-beacon-root))
          (when versioned-hashes-supplied-p
            (list :versioned-hashes versioned-hashes))
          (when requests-supplied-p
            (list :requests requests)))))

(defun engine-payload-store-invalid-ancestor-status
    (store check-hash head-hash &key (walk-remote-p t))
  (let ((invalid-block
          (engine-payload-store-invalid-ancestor
           store check-hash :walk-remote-p walk-remote-p)))
    (when invalid-block
      (unless (string= (engine-payload-store-key check-hash)
                       (engine-payload-store-key head-hash))
        (engine-payload-store-mark-invalid
         store invalid-block :head-hash head-hash))
      (make-payload-status
       :status +payload-status-invalid+
       :latest-valid-hash
       (let* ((parent-hash
                (block-header-parent-hash (block-header invalid-block)))
              (parent-block
                (and (hash32-p parent-hash)
                     (chain-store-known-block store parent-hash))))
         (if (and parent-block
                  (plusp (or (block-header-difficulty
                              (block-header parent-block))
                             0)))
             (zero-hash32)
             parent-hash))
       :validation-error "links to previously rejected block"))))

(defun engine-forkchoice-checkpoint-error-message
    (store hash label &key head-hash)
  (when (not (hash32= hash (zero-hash32)))
    (cond
      ((not (chain-store-known-block store hash))
       (format nil "forkchoice ~A block is not available" label))
      ((not (chain-store-state-available-p store hash))
       (format nil "forkchoice ~A block state is not available" label))
      ((and head-hash
            (not (engine-payload-store-ancestor-p store hash head-hash)))
       (format nil "forkchoice ~A block is not an ancestor of head"
               label)))))

(defun engine-forkchoice-checkpoint-order-error-message (store state)
  (let* ((safe-hash (forkchoice-state-safe-block-hash state))
         (finalized-hash (forkchoice-state-finalized-block-hash state))
         (safe-block
           (unless (hash32= safe-hash (zero-hash32))
             (chain-store-known-block store safe-hash)))
         (finalized-block
           (unless (hash32= finalized-hash (zero-hash32))
             (chain-store-known-block store finalized-hash))))
    (when (and safe-block finalized-block
               (< (block-header-number (block-header safe-block))
                  (block-header-number (block-header finalized-block))))
      "forkchoice safe block is older than finalized block")))

(defun engine-forkchoice-memory-status (store state)
  (unless (typep store 'engine-payload-memory-store)
    (return-from engine-forkchoice-memory-status
      (invalid-payload-status
       "forkchoiceUpdated store must be engine-payload-memory-store")))
  (unless (typep state 'forkchoice-state)
    (return-from engine-forkchoice-memory-status
      (invalid-payload-status "forkchoice state must be forkchoice-state")))
  (let ((head-hash (forkchoice-state-head-block-hash state)))
    (cond
      ((hash32= head-hash (zero-hash32))
       (forkchoice-state-zero-head-status))
      ((and (chain-store-known-block store head-hash)
            (chain-store-state-available-p store head-hash))
       (make-payload-status
        :status +payload-status-valid+
        :latest-valid-hash head-hash))
      ((engine-payload-store-invalid-ancestor-status
        store head-hash head-hash))
      (t
       ;; A skeleton/header can already be durable after a restart while its
       ;; pivot state is still unavailable.  That is still active sync work:
       ;; registering only completely unknown heads makes the coordinator lose
       ;; the CL target precisely after skeleton recovery. Forkchoice has one
       ;; current head, so replace every abandoned target in either case.
       (dolist (old (engine-payload-store-forkchoice-sync-targets store))
         (unless (hash32= old head-hash)
           (engine-payload-store-remove-forkchoice-sync-target store old)))
       (let ((known (chain-store-known-block store head-hash)))
         (engine-payload-store-put-forkchoice-sync-target
          store head-hash
          :block-number
          (and known (block-header-number (block-header known)))))
       (make-payload-status :status +payload-status-syncing+)))))

(defun engine-new-payload-memory-status
    (store version payload config
     &key (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p)
          (validated-block nil validated-block-supplied-p)
          import-function
          (import-state-available-p t))
  (unless (typep store 'engine-payload-memory-store)
    (return-from engine-new-payload-memory-status
      (values (invalid-payload-status
               "newPayload store must be engine-payload-memory-store")
              nil)))
  (multiple-value-bind (status block)
      (if validated-block-supplied-p
          ;; IMPORT-EXECUTABLE-PAYLOAD already crossed the complete wire
          ;; conversion boundary and passes that exact block here. Repeat the
          ;; cheap version/fork rules so this keyword cannot bypass them, then
          ;; bind the block by its declared payload hash. Avoiding a second
          ;; executable-data-to-block conversion is important on the Engine
          ;; hot path, where every transaction would otherwise be decoded,
          ;; rooted, and hashed twice before admission.
          (let ((invalid-message
                  (and (typep payload 'executable-data)
                       (typep config 'chain-config)
                       (engine-new-payload-version-invalid-p
                        version payload config
                        versioned-hashes-supplied-p
                        parent-beacon-root-supplied-p
                        requests-supplied-p))))
            (cond
              ((not (typep payload 'executable-data))
               (values
                (invalid-payload-status
                 "newPayload execution payload must be executable-data")
                nil))
              ((not (typep config 'chain-config))
               (values
                (invalid-payload-status
                 "newPayload chain config must be chain-config")
                nil))
              ((not (typep validated-block 'ethereum-block))
               (values
                (invalid-payload-status
                 "newPayload validated block must be an Ethereum block")
                nil))
              (invalid-message
               (values (invalid-payload-status invalid-message) nil))
              ((or (not (hash32-p (executable-data-block-hash payload)))
                   (not
                    (hash32=
                     (executable-data-block-hash payload)
                     (block-hash validated-block))))
               (values
                (invalid-payload-status
                 "newPayload validated block hash does not match payload")
                nil))
              (t
               (values
                (make-payload-status
                 :status +payload-status-valid+
                 :latest-valid-hash (block-hash validated-block))
                validated-block))))
          (engine-new-payload-version-status-for-request
           version payload config
           parent-beacon-root parent-beacon-root-supplied-p
           versioned-hashes versioned-hashes-supplied-p
           requests requests-supplied-p))
    (unless (string= +payload-status-valid+
                     (payload-status-status status))
      (return-from engine-new-payload-memory-status
        (values status nil)))
    (let* ((hash (block-hash block))
           (known-block (chain-store-known-block store hash)))
      (when (and known-block
                 (chain-store-state-available-p store hash))
        (return-from engine-new-payload-memory-status
          (values (make-payload-status
                   :status +payload-status-valid+
                   :latest-valid-hash hash)
                  known-block)))
      (let ((invalid-status
              (engine-payload-store-invalid-ancestor-status
               store hash hash :walk-remote-p nil)))
        (when invalid-status
          (return-from engine-new-payload-memory-status
            (values invalid-status nil))))
      (let* ((header (block-header block))
             (number (block-header-number header))
             (parent-hash (block-header-parent-hash header))
             (parent-block (and (plusp number)
                                (chain-store-known-block
                                 store parent-hash))))
        (when (plusp number)
          (let ((parent-invalid-status
                  (engine-payload-store-invalid-ancestor-status
                   store parent-hash hash)))
            (when parent-invalid-status
              (return-from engine-new-payload-memory-status
                (values parent-invalid-status nil)))))
        (when (and (plusp number) (null parent-block))
          ;; A durable SNAP skeleton can make BLOCK known before its parent
          ;; interval has been restored.  It is already the sync record for
          ;; this hash; also inserting it into the remote-block cache creates
          ;; the impossible durable combination "known" and "remote buffered".
          ;; Return no candidate so the outer persistence service does not try
          ;; to export that duplicate as a buffered Engine payload.
          (unless known-block
            (engine-payload-store-put-remote-block store block))
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-syncing+)
                    (unless known-block block))))
        (when parent-block
          (handler-case
              (validate-block-against-config
               (block-header parent-block)
               block
               config)
            (block-validation-error (condition)
              (engine-payload-store-mark-invalid store block)
              (return-from engine-new-payload-memory-status
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error
                  (block-validation-error-message condition))
                 nil)))))
        (when (and parent-block
                   (not (chain-store-state-available-p
                         store parent-hash)))
          ;; The same rule applies after the skeleton parent is known but its
          ;; pivot-derived state is not executable yet.  Once that state is
          ;; available this request falls through to ordinary execution.
          (unless known-block
            (engine-payload-store-put-remote-block store block))
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-accepted+)
                    (unless known-block block))))
        (handler-case
            (engine-new-payload-require-transaction-senders block config)
          (block-validation-error (condition)
            (engine-payload-store-mark-invalid store block)
            (return-from engine-new-payload-memory-status
              (values
               (make-payload-status
                :status +payload-status-invalid+
                :latest-valid-hash (and parent-block parent-hash)
                :validation-error
                (block-validation-error-message condition))
               nil))))
        (if import-function
            (handler-case
                (multiple-value-bind (imported-block receipts)
                    (funcall import-function store block config)
                  (declare (ignore receipts))
                  (let ((imported-block (or imported-block block)))
                    (values (make-payload-status
                             :status +payload-status-valid+
                             :latest-valid-hash (block-hash imported-block))
                            imported-block)))
              (state-unavailable-error ()
                (engine-payload-store-put-remote-block store block)
                (values
                 (make-payload-status :status +payload-status-syncing+)
                 block))
              (ethereum-lisp.bls12381:bls12381-unavailable-error (condition)
                ;; A precompile backend that could not be consulted is a node
                ;; capability failure, not an invalid block. Marking the block
                ;; invalid here would gossip a verdict a node with a working
                ;; backend would not share, so refuse by propagating instead.
                (error condition))
              (ethereum-lisp.kzg:kzg-unavailable-error (condition)
                ;; Proof verification unavailable locally is likewise a node
                ;; capability failure, never a consensus verdict.
                (error condition))
              (storage-error (condition)
                ;; Durability is part of accepting an import. A failed database
                ;; batch says nothing about block validity, and the unified
                ;; import transaction must be allowed to roll its memory view
                ;; back before the storage failure reaches the RPC or peer
                ;; worker.
                (error condition))
              (block-validation-error (condition)
                (engine-payload-store-mark-invalid store block)
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error (block-validation-error-message condition))
                 nil))
              (ethereum-lisp.execution:transaction-validation-error
                  (condition)
                (engine-payload-store-mark-invalid store block)
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error
                  (ethereum-lisp.execution:transaction-validation-error-message
                   condition))
                 nil))
              ;; Unknown executor/capability/program failures are local node
              ;; failures, never portable consensus verdicts.  Propagate them
              ;; so the unified atomic boundary rolls back without poisoning
              ;; the invalid cache.
              (error (condition)
                (error condition)))
            (progn
              (engine-payload-store-put-block
               store block
               :state-available-p import-state-available-p
               :canonicalize-p nil)
              (values (make-payload-status
                       :status +payload-status-valid+
                       :latest-valid-hash hash)
                      block)))))))
