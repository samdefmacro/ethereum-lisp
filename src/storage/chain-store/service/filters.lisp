(in-package #:ethereum-lisp.chain-store)

(defconstant +engine-filter-id-bytes+ 16)
(defconstant +engine-filter-timeout-seconds+ 300)

(defun engine-filter-deadline (filter)
  (etypecase filter
    (engine-log-filter (engine-log-filter-deadline filter))
    (engine-block-filter (engine-block-filter-deadline filter))
    (engine-pending-transaction-filter
     (engine-pending-transaction-filter-deadline filter))))

(defun (setf engine-filter-deadline) (deadline filter)
  (etypecase filter
    (engine-log-filter
     (setf (engine-log-filter-deadline filter) deadline))
    (engine-block-filter
     (setf (engine-block-filter-deadline filter) deadline))
    (engine-pending-transaction-filter
     (setf (engine-pending-transaction-filter-deadline filter) deadline))))

(defun engine-filter-reset-deadline (filter now)
  (setf (engine-filter-deadline filter)
        (+ now +engine-filter-timeout-seconds+))
  filter)

(defun engine-payload-store-sweep-expired-filters (store &optional (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (let ((expired-ids nil)
        (filters (memory-chain-store-log-filters store)))
    (maphash
     (lambda (id filter)
       (when (and (engine-filter-deadline filter)
                  (<= (engine-filter-deadline filter) now))
         (push id expired-ids)))
     filters)
    (dolist (id expired-ids)
      (remhash id filters))
    (length expired-ids)))

(defun engine-payload-store-new-filter-id (store)
  (let ((filters (memory-chain-store-log-filters store)))
    (loop for id = (bytes-to-hex
                    (secure-random-bytes +engine-filter-id-bytes+))
          unless (gethash id filters)
            return id)))

(defun engine-payload-store-notify-block-filters (store block)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Block filter notification block must be a block"))
  (loop for filter
          being the hash-values of
            (memory-chain-store-log-filters store)
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
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store)
  (loop for filter
          being the hash-values of
            (memory-chain-store-log-filters store)
        when (and (typep filter 'engine-log-filter)
                  (not (engine-log-filter-block-hash-p filter)))
          do (engine-log-filter-record-change
              filter
              block
              :removed-p removed-p)))

(defun engine-payload-store-notify-pending-transaction-filters
    (store transaction)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store)
  (loop for filter
          being the hash-values of
            (memory-chain-store-log-filters store)
        when (typep filter 'engine-pending-transaction-filter)
          do (engine-pending-transaction-filter-record-hash
              filter
              (transaction-hash transaction))))

(defun engine-payload-store-put-log-filter
    (store criteria &key block-hash-p last-block-number (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store now)
  (let ((id (engine-payload-store-new-filter-id store)))
    (setf (gethash id (memory-chain-store-log-filters store))
          (make-engine-log-filter
           :criteria criteria
           :block-hash-p block-hash-p
           :last-block-number last-block-number
           :deadline (+ now +engine-filter-timeout-seconds+)))
    id))

(defun engine-payload-store-put-block-filter (store &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store now)
  (let ((id (engine-payload-store-new-filter-id store)))
    (setf (gethash id (memory-chain-store-log-filters store))
          (make-engine-block-filter
           :last-block-number
           (memory-chain-store-head-number store)
           :deadline (+ now +engine-filter-timeout-seconds+)))
    id))

(defun engine-payload-store-put-pending-transaction-filter
    (store &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store now)
  (let ((id (engine-payload-store-new-filter-id store)))
    (setf (gethash id (memory-chain-store-log-filters store))
          (make-engine-pending-transaction-filter
           :deadline (+ now +engine-filter-timeout-seconds+)))
    id))

(defun engine-payload-store-log-filter
    (store id &key (now (unix-time)) (reset-deadline-p t))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-sweep-expired-filters store now)
  (let ((filter (gethash id (memory-chain-store-log-filters store))))
    (when (and filter reset-deadline-p)
      (engine-filter-reset-deadline filter now))
    filter))

(defun engine-payload-store-uninstall-log-filter (store id)
  (setf store (chain-store-require-memory-store store))
  (remhash id (memory-chain-store-log-filters store)))
