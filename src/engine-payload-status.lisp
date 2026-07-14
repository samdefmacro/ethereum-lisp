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
    (store check-hash head-hash)
  (let ((invalid-block
          (engine-payload-store-invalid-block store check-hash)))
    (when invalid-block
      (unless (string= (engine-payload-store-key check-hash)
                       (engine-payload-store-key head-hash))
        (engine-payload-store-mark-invalid
         store invalid-block :head-hash head-hash))
      (make-payload-status
       :status +payload-status-invalid+
       :latest-valid-hash
       (block-header-parent-hash (block-header invalid-block))
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
       (make-payload-status :status +payload-status-syncing+)))))

(defun engine-new-payload-memory-status
    (store version payload config
     &key (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p)
          import-function
          (import-state-available-p t))
  (unless (typep store 'engine-payload-memory-store)
    (return-from engine-new-payload-memory-status
      (values (invalid-payload-status
               "newPayload store must be engine-payload-memory-store")
              nil)))
  (multiple-value-bind (status block)
      (engine-new-payload-version-status-for-request
       version payload config
       parent-beacon-root parent-beacon-root-supplied-p
       versioned-hashes versioned-hashes-supplied-p
       requests requests-supplied-p)
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
               store hash hash)))
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
          (engine-payload-store-put-remote-block store block)
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-syncing+)
                    block)))
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
          (engine-payload-store-put-remote-block store block)
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-accepted+)
                    block)))
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
              (error (condition)
                (engine-payload-store-mark-invalid store block)
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error
                  (if (typep condition 'block-validation-error)
                      (block-validation-error-message condition)
                      (format nil "~A" condition)))
                 nil)))
            (progn
              (engine-payload-store-put-block
               store block
               :state-available-p import-state-available-p
               :canonicalize-p nil)
              (values (make-payload-status
                       :status +payload-status-valid+
                       :latest-valid-hash hash)
                      block)))))))
