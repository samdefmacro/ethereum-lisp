(in-package #:ethereum-lisp.core)

(defun eth-rpc-log-filter-change-block-key (change)
  (engine-payload-store-key
   (block-hash (engine-log-filter-change-block change))))

(defun eth-rpc-log-filter-change-in-range-p (change from-number to-number)
  (let ((number
          (block-header-number
           (block-header (engine-log-filter-change-block change)))))
    (<= from-number number to-number)))

(defun eth-rpc-log-filter-change-logs
    (changes criteria method)
  (let ((addresses (eth-rpc-log-filter-addresses criteria method))
        (topic-filters (eth-rpc-log-filter-topics criteria method)))
    (loop for change in changes
          append (eth-rpc-block-logs-object
                  (engine-log-filter-change-block change)
                  addresses
                  topic-filters
                  :removed-p
                  (engine-log-filter-change-removed-p change)))))

(defun eth-rpc-log-filter-range-bounds (filter store method)
  (unless (json-object-field-present-p filter "blockHash")
    (values
     (eth-rpc-block-number-param
      (list (or (json-object-field filter "fromBlock") "latest"))
      store
      method)
     (eth-rpc-block-number-param
      (list (or (json-object-field filter "toBlock") "latest"))
      store
      method))))

(defun eth-rpc-log-filter-with-range (filter from-number to-number)
  (append
   (remove-if (lambda (entry)
                (member (car entry) '("fromBlock" "toBlock" "blockHash")
                        :test #'string=))
              filter)
   (list (cons "fromBlock" (quantity-to-hex from-number))
         (cons "toBlock" (quantity-to-hex to-number)))))

(defun engine-log-filter-changes (log-filter store method)
  (let ((criteria (engine-log-filter-criteria log-filter)))
    (if (json-object-field-present-p criteria "blockHash")
        (if (engine-log-filter-block-hash-consumed-p log-filter)
            (eth-rpc-json-array '())
            (prog1 (eth-rpc-filter-logs criteria store method)
              (setf (engine-log-filter-block-hash-consumed-p log-filter) t)))
        (multiple-value-bind (from-number to-number)
            (eth-rpc-log-filter-range-bounds criteria store method)
          (let* ((pending-changes
                   (engine-log-filter-pending-changes log-filter))
                 (changes
                   (remove-if-not
                    (lambda (change)
                      (eth-rpc-log-filter-change-in-range-p
                       change
                       from-number
                       to-number))
                    pending-changes))
                 (change-block-keys (make-hash-table :test 'equal))
                 (cursor (engine-log-filter-last-block-number log-filter))
                 (change-from (if cursor
                                  (max from-number (1+ cursor))
                                  from-number)))
            (dolist (change changes)
              (setf (gethash (eth-rpc-log-filter-change-block-key change)
                             change-block-keys)
                    t))
            (prog1
                (let* ((change-logs
                         (eth-rpc-log-filter-change-logs
                          changes
                          criteria
                          method))
                       (range-logs
                         (if (> change-from to-number)
                             nil
                             (let ((addresses
                                     (eth-rpc-log-filter-addresses
                                      criteria
                                      method))
                                   (topic-filters
                                     (eth-rpc-log-filter-topics
                                      criteria
                                      method)))
                               (loop for number from change-from to to-number
                                     for block =
                                       (chain-store-block-by-number
                                        store
                                        number)
                                     when (and block
                                               (not
                                                (gethash
                                                 (engine-payload-store-key
                                                  (block-hash block))
                                                 change-block-keys)))
                                       append (eth-rpc-block-logs-object
                                               block
                                               addresses
                                               topic-filters))))))
                  (eth-rpc-json-array (append change-logs range-logs)))
              (setf (engine-log-filter-last-block-number log-filter)
                    (max (or cursor 0) to-number)
                    (engine-log-filter-pending-changes log-filter)
                    nil)))))))

(defun engine-block-filter-changes (block-filter store)
  (let* ((cursor (engine-block-filter-last-block-number block-filter))
         (latest (chain-store-head-number store))
         (seen (make-hash-table :test 'equal))
         (hashes nil))
    (dolist (hash (engine-block-filter-hashes block-filter))
      (let ((hash-hex (hash32-to-hex hash)))
        (unless (gethash hash-hex seen)
          (setf (gethash hash-hex seen) t)
          (push hash-hex hashes))))
    (loop for number from (1+ cursor) to latest
          for block = (chain-store-block-by-number store number)
          when block
            do (let ((hash-hex (hash32-to-hex (block-hash block))))
                 (unless (gethash hash-hex seen)
                   (setf (gethash hash-hex seen) t)
                   (push hash-hex hashes))))
    (prog1 (eth-rpc-json-array (nreverse hashes))
      (setf (engine-block-filter-last-block-number block-filter) latest
            (engine-block-filter-hashes block-filter) nil))))

(defun engine-pending-transaction-filter-visible-hash-p
    (hash store expected-chain-id)
  (let ((transaction (engine-payload-store-pooled-transaction store hash)))
    (or (null transaction)
        (transaction-sender
         transaction
         :expected-chain-id expected-chain-id))))

(defun engine-pending-transaction-filter-changes
    (pending-filter store expected-chain-id)
  (let ((hashes (engine-pending-transaction-filter-hashes pending-filter)))
    (prog1 (eth-rpc-json-array
            (loop for hash in hashes
                  when (engine-pending-transaction-filter-visible-hash-p
                        hash store expected-chain-id)
                    collect (hash32-to-hex hash)))
      (setf (engine-pending-transaction-filter-hashes pending-filter) nil))))
