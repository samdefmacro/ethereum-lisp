(in-package #:ethereum-lisp.core)

(defun eth-rpc-hash-table-object (table)
  (if (zerop (hash-table-count table))
      +json-empty-object+
      (loop for key in (sort (loop for key being the hash-keys of table
                                   collect key)
                             #'string<)
            collect (cons key (gethash key table)))))

(defun txpool-rpc-nonce-key< (left right)
  (< (parse-integer left :junk-allowed nil)
     (parse-integer right :junk-allowed nil)))

(defun txpool-rpc-indexed-nonce-transactions
    (sender-transactions value-function)
  (let ((entries
          (unless (or (null sender-transactions)
                      (zerop (hash-table-count sender-transactions)))
            (loop for nonce in (sort (loop for nonce being the hash-keys
                                             of sender-transactions
                                           collect nonce)
                                     #'txpool-rpc-nonce-key<)
                  for value = (funcall value-function
                                       (gethash nonce sender-transactions))
                  when value
                    collect (cons nonce value)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-nonce-transactions-from-sender-indexes
    (address value-function &rest sender-indexes)
  (let ((sender-key (address-to-hex address))
        (merged-transactions (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (let ((sender-transactions (gethash sender-key sender-index)))
        (when sender-transactions
          (maphash
           (lambda (nonce transaction)
             (setf (gethash nonce merged-transactions) transaction))
           sender-transactions))))
    (txpool-rpc-indexed-nonce-transactions
     merged-transactions
     value-function)))

(defun txpool-rpc-indexed-sender-transactions
    (sender-index value-function)
  (let ((entries
          (unless (zerop (hash-table-count sender-index))
            (loop for sender in (sort (loop for sender being the hash-keys
                                              of sender-index
                                            collect sender)
                                      #'string<)
                  for transactions =
                    (txpool-rpc-indexed-nonce-transactions
                     (gethash sender sender-index)
                     value-function)
                  unless (json-empty-object-p transactions)
                    collect (cons sender transactions)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-sender-transactions-from-indexes
    (value-function &rest sender-indexes)
  (let ((merged-senders (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (maphash
       (lambda (sender sender-transactions)
         (let ((merged-transactions
                 (or (gethash sender merged-senders)
                     (setf (gethash sender merged-senders)
                           (make-hash-table :test 'equal)))))
           (maphash
            (lambda (nonce transaction)
              (setf (gethash nonce merged-transactions) transaction))
            sender-transactions)))
       sender-index))
    (txpool-rpc-indexed-sender-transactions
     merged-senders
     value-function)))

(defun txpool-rpc-transaction-summary (transaction &key expected-chain-id)
  (when (transaction-sender
         transaction
         :expected-chain-id expected-chain-id)
    (let ((to (transaction-to transaction)))
      (format nil "~A: ~D wei + ~D gas x ~D wei"
              (if to
                  (address-to-hex to)
                  "contract creation")
              (transaction-value transaction)
              (transaction-gas-limit transaction)
              (transaction-max-fee-per-gas transaction)))))

(defun txpool-rpc-indexed-content-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (when (transaction-sender
            transaction
            :expected-chain-id expected-chain-id)
       (eth-rpc-pending-transaction-object
        transaction
        :expected-chain-id expected-chain-id)))))

(defun txpool-rpc-indexed-inspect-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (txpool-rpc-transaction-summary
      transaction
      :expected-chain-id expected-chain-id))))

(defun eth-rpc-txpool-queued-view-transactions (store)
  (append (engine-payload-store-queued-transactions store)
          (engine-payload-store-basefee-transactions store)
          (engine-payload-store-blob-transactions store)))

(defun eth-rpc-txpool-visible-transaction-count
    (transactions expected-chain-id)
  (count-if
   (lambda (transaction)
     (transaction-sender
      transaction
      :expected-chain-id expected-chain-id))
   transactions))

(defun eth-rpc-txpool-pending-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (engine-payload-store-pending-transactions store)
   expected-chain-id))

(defun eth-rpc-txpool-queued-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (eth-rpc-txpool-queued-view-transactions store)
   expected-chain-id))
