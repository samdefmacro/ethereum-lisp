(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-notify-block-filters (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Block filter notification block must be a block"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (typep filter 'engine-block-filter)
          do (engine-block-filter-record-hash filter (block-hash block))))

(defun engine-log-filter-record-change (filter block &key removed-p)
  (unless (typep filter 'engine-log-filter)
    (block-validation-fail "Log filter must be a log filter"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Log filter change block must be a block"))
  (setf (engine-log-filter-pending-changes filter)
        (append
         (engine-log-filter-pending-changes filter)
         (list (make-engine-log-filter-change
                :block block
                :removed-p (not (null removed-p))))))
  filter)

(defun engine-payload-store-notify-log-filters
    (store block &key removed-p)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (and (typep filter 'engine-log-filter)
                  (not (engine-log-filter-block-hash-p filter)))
          do (engine-log-filter-record-change
              filter
              block
              :removed-p removed-p)))

(defun engine-payload-store-notify-pending-transaction-filters
    (store transaction)
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (typep filter 'engine-pending-transaction-filter)
          do (engine-pending-transaction-filter-record-hash
              filter
              (transaction-hash transaction))))

(defun engine-payload-store-put-log-filter
    (store criteria &key block-hash-p last-block-number)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-log-filter
           :criteria criteria
           :block-hash-p block-hash-p
           :last-block-number last-block-number))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-block-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-block-filter
           :last-block-number
           (engine-payload-memory-store-head-number store)))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-pending-transaction-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-pending-transaction-filter))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-log-filter (store id)
  (gethash id (engine-payload-memory-store-log-filters store)))

(defun engine-payload-store-uninstall-log-filter (store id)
  (remhash id (engine-payload-memory-store-log-filters store)))
