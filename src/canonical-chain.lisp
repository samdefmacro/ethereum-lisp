(in-package #:ethereum-lisp.canonical-chain)

(defun canonical-chain-block-number (block)
  (block-header-number (block-header block)))

(defun canonical-chain-sorted-blocks (blocks)
  (sort (copy-list blocks) #'< :key #'canonical-chain-block-number))

(defun canonical-chain-path (store head-block)
  (let ((path nil))
    (loop with current = head-block
          for header = (block-header current)
          for number = (block-header-number header)
          for current-hash = (block-hash current)
          for canonical-key =
            (gethash number
                     (engine-payload-memory-store-canonical-hashes store))
          do (when (and canonical-key
                        (string= canonical-key
                                 (engine-payload-store-key current-hash)))
               (return path))
             (push current path)
             (when (zerop number)
               (return path))
             (let* ((parent-hash (block-header-parent-hash header))
                    (parent-block
                      (and parent-hash
                           (engine-payload-store-known-block
                            store parent-hash))))
               (when (or (null parent-hash)
                         (hash32= parent-hash (zero-hash32)))
                 (return path))
               (unless parent-block
                 (block-validation-fail
                  "Canonical head ancestry must be fully known"))
               (setf current parent-block)))))

(defun canonical-chain-replaced-blocks (store path)
  (loop for block in path
        for number = (canonical-chain-block-number block)
        for old-block = (engine-payload-store-block-by-number store number)
        when (and old-block
                  (not (hash32= (block-hash old-block) (block-hash block))))
          collect old-block))

(defun canonical-chain-install-path (store path)
  (dolist (block path)
    (let* ((number (canonical-chain-block-number block))
           (key (engine-payload-store-key (block-hash block))))
      (setf (gethash number
                     (engine-payload-memory-store-canonical-hashes store))
            key
            (gethash number
                     (engine-payload-memory-store-number-blocks store))
            block)
      (engine-payload-store-index-block-transactions store block :force t)
      (engine-payload-store-remove-included-block-transactions store block))))

(defun canonical-chain-prune-descendants (store new-head-number)
  (let ((stale-numbers nil)
        (displaced-blocks nil))
    (maphash
     (lambda (number key)
       (declare (ignore key))
       (when (> number new-head-number)
         (let ((block (engine-payload-store-block-by-number store number)))
           (when block
             (push block displaced-blocks)))
         (push number stale-numbers)))
     (engine-payload-memory-store-canonical-hashes store))
    (dolist (number stale-numbers)
      (remhash number
               (engine-payload-memory-store-canonical-hashes store)))
    displaced-blocks))

(defun canonical-chain-set-head-metadata (store head-block)
  (let ((hash (block-hash head-block)))
    (setf (engine-payload-memory-store-head-number store)
          (canonical-chain-block-number head-block)
          (engine-payload-memory-store-head-checkpoint store)
          (make-chain-store-checkpoint :label :head :block-hash hash))))

(defun canonical-chain-reinsert-displaced-transactions
    (store displaced-blocks expected-chain-id chain-config)
  (engine-payload-store-remove-new-head-invalid-txpool-transactions
   store
   :expected-chain-id expected-chain-id
   :chain-config chain-config)
  (dolist (block displaced-blocks)
    (engine-payload-store-remove-block-transaction-locations store block))
  (engine-payload-store-reinsert-displaced-block-transactions
   store
   displaced-blocks
   :expected-chain-id expected-chain-id
   :chain-config chain-config))

(defun canonical-chain-notify-log-filters (store displaced-blocks path)
  (dolist (block (canonical-chain-sorted-blocks displaced-blocks))
    (engine-payload-store-notify-log-filters store block :removed-p t))
  (dolist (block (canonical-chain-sorted-blocks path))
    (engine-payload-store-notify-log-filters store block)))

(defun canonical-chain-reconcile-txpool
    (store expected-chain-id chain-config)
  (engine-payload-store-remove-new-head-invalid-txpool-transactions
   store
   :expected-chain-id expected-chain-id
   :chain-config chain-config)
  (engine-payload-store-revalidate-pending-transactions
   store
   :expected-chain-id expected-chain-id)
  (engine-payload-store-promote-queued-transactions
   store
   :expected-chain-id expected-chain-id)
  (engine-payload-store-promote-basefee-and-queued-transactions
   store
   :expected-chain-id expected-chain-id))

(defun canonical-chain-set-head
    (store hash &key expected-chain-id chain-config)
  (let* ((head-block (engine-payload-store-known-block store hash))
         (previous-head-hash
           (engine-payload-store-canonical-hash
            store
            (engine-payload-memory-store-head-number store))))
    (unless head-block
      (block-validation-fail "Canonical head block must be known"))
    (let* ((head-changed-p
             (or (null previous-head-hash)
                 (not (hash32= previous-head-hash hash))))
           (path (canonical-chain-path store head-block))
           (displaced-blocks
             (canonical-chain-replaced-blocks store path)))
      (canonical-chain-install-path store path)
      (setf displaced-blocks
            (nconc displaced-blocks
                   (canonical-chain-prune-descendants
                    store
                    (canonical-chain-block-number head-block))))
      (canonical-chain-set-head-metadata store head-block)
      (canonical-chain-reinsert-displaced-transactions
       store displaced-blocks expected-chain-id chain-config)
      (when head-changed-p
        (canonical-chain-notify-log-filters store displaced-blocks path))
      (canonical-chain-reconcile-txpool
       store expected-chain-id chain-config)
      (when head-changed-p
        (engine-payload-store-notify-block-filters store head-block))
      head-block)))

(defun chain-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (canonical-chain-set-head
   (chain-store-require-memory-store store)
   hash
   :expected-chain-id expected-chain-id
   :chain-config chain-config))
