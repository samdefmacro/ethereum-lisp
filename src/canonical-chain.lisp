(in-package #:ethereum-lisp.canonical-chain)

(defstruct (canonical-chain-transition
            (:constructor make-canonical-chain-transition
                (&key installed-blocks displaced-blocks
                      changed-txpool-hashes)))
  (installed-blocks nil :type list)
  (displaced-blocks nil :type list)
  (changed-txpool-hashes nil :type list))

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
                     (memory-chain-store-canonical-hashes store))
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

(defun canonical-chain-install-path (chain-store txpool path)
  (dolist (block path)
    (let* ((number (canonical-chain-block-number block))
           (key (engine-payload-store-key (block-hash block))))
      (setf (gethash number
                     (memory-chain-store-canonical-hashes chain-store))
            key
            (gethash number
                     (memory-chain-store-number-blocks chain-store))
            block)
      (engine-payload-store-index-block-transactions
       chain-store block :force t)
      (engine-payload-store-remove-included-block-transactions
       txpool block))))

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
     (memory-chain-store-canonical-hashes store))
    (dolist (number stale-numbers)
      (remhash number
               (memory-chain-store-canonical-hashes store)))
    displaced-blocks))

(defun canonical-chain-set-head-metadata (store head-block)
  (let ((hash (block-hash head-block)))
    (setf (memory-chain-store-head-number store)
          (canonical-chain-block-number head-block)
          (memory-chain-store-head-checkpoint store)
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
  (let* ((chain-store (chain-store-require-memory-store store))
         (txpool (or (txpool-component store)
                     (block-validation-fail
                      "Canonical chain requires a txpool component")))
         (head-block (engine-payload-store-known-block chain-store hash))
         (previous-head-hash
           (engine-payload-store-canonical-hash
            chain-store
            (memory-chain-store-head-number chain-store))))
    (unless head-block
      (block-validation-fail "Canonical head block must be known"))
    (let* ((head-changed-p
             (or (null previous-head-hash)
                 (not (hash32= previous-head-hash hash))))
           (path (canonical-chain-path chain-store head-block))
           (displaced-blocks
             (canonical-chain-replaced-blocks chain-store path))
           (changed-txpool-keys (make-hash-table :test 'equalp)))
      (call-with-engine-pending-txpool-change-tracking
       (lambda (transaction-hash)
         (setf (gethash (hash32-to-hex transaction-hash)
                        changed-txpool-keys)
               t))
       (lambda ()
         (canonical-chain-install-path chain-store txpool path)
         (setf displaced-blocks
               (nconc displaced-blocks
                      (canonical-chain-prune-descendants
                       chain-store
                       (canonical-chain-block-number head-block))))
         (canonical-chain-set-head-metadata chain-store head-block)
         (canonical-chain-reinsert-displaced-transactions
          store displaced-blocks expected-chain-id chain-config)
         (when head-changed-p
           (canonical-chain-notify-log-filters
            chain-store displaced-blocks path))
         (canonical-chain-reconcile-txpool
          store expected-chain-id chain-config)
         (when head-changed-p
           (engine-payload-store-notify-block-filters
            chain-store head-block))))
      (dolist (transaction-hash
               (engine-payload-store-txpool-database-dirty-transaction-hashes
                store))
        (setf (gethash (hash32-to-hex transaction-hash)
                       changed-txpool-keys)
              t))
      (values
       head-block
       (make-canonical-chain-transition
        :installed-blocks (copy-list path)
        :displaced-blocks (copy-list displaced-blocks)
        :changed-txpool-hashes
        (mapcar
         #'hash32-from-hex
         (sort
          (loop for key being the hash-keys of changed-txpool-keys
                collect key)
          #'string<)))))))

(defun chain-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (canonical-chain-set-head
   store
   hash
   :expected-chain-id expected-chain-id
   :chain-config chain-config))
