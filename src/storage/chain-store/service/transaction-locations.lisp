(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-put-transaction-location
    (store block index transaction receipt log-index-start &key force)
  (setf store (chain-store-require-memory-store store))
  (let* ((transaction-key
           (engine-payload-store-key (transaction-hash transaction)))
         (locations
           (memory-chain-store-transaction-locations store))
         (existing-location (gethash transaction-key locations))
         (existing-canonical-p
           (and existing-location
                (engine-payload-store-canonical-block-p
                 store
                 (engine-transaction-location-block existing-location)))))
    (when (or force
              (null existing-location)
              (engine-payload-store-canonical-block-p store block)
              (not existing-canonical-p))
      (setf (gethash transaction-key locations)
            (make-engine-transaction-location
             :block block
             :index index
             :transaction transaction
             :receipt receipt
             :log-index-start log-index-start)))))

(defun engine-payload-store-index-block-transactions
    (store block &key force)
  (setf store (chain-store-require-memory-store store))
  (loop with receipts = (block-receipts block)
        with log-index-start = 0
        for transaction in (block-transactions block)
        for index from 0
        for receipt = (nth index receipts)
        do (progn
             (engine-payload-store-put-transaction-location
              store
              block
              index
              transaction
              receipt
              log-index-start
              :force force)
             (when receipt
               (incf log-index-start
                     (length (receipt-logs receipt)))))))

(defun engine-payload-store-remove-block-transaction-locations (store block)
  (setf store (chain-store-require-memory-store store))
  (let ((locations
          (memory-chain-store-transaction-locations store)))
    (dolist (transaction (block-transactions block))
      (let* ((transaction-key
               (engine-payload-store-key (transaction-hash transaction)))
             (location (gethash transaction-key locations)))
        (when (and location
                   (hash32= (block-hash block)
                             (block-hash
                              (engine-transaction-location-block location))))
          (remhash transaction-key locations)))))
  block)

(defun engine-payload-store-transaction-location (store hash)
  (setf store (chain-store-require-memory-store store))
  (let ((location
          (gethash (engine-payload-store-key hash)
                   (memory-chain-store-transaction-locations
                    store))))
    (when (and location
               (engine-payload-store-canonical-block-p
                store
                (engine-transaction-location-block location)))
      (engine-payload-store-copy-transaction-location location))))
