(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-remove-included-block-transactions (store block)
  (let ((txpool (engine-payload-store-txpool store)))
    (dolist (transaction (block-transactions block))
      (engine-pending-txpool-remove-included-transaction
       txpool transaction)))
  block)

(defun engine-payload-store-subpool-views
    (store &key (include-pending-p t))
  (append
   (when include-pending-p
     (list (cons (engine-payload-store-pending-transactions store)
                 #'engine-pending-txpool-remove-pending-transaction)))
   (list
    (cons (engine-payload-store-queued-transactions store)
          #'engine-pending-txpool-remove-queued-transaction)
    (cons (engine-payload-store-basefee-transactions store)
          #'engine-pending-txpool-remove-basefee-transaction)
    (cons (engine-payload-store-blob-transactions store)
          #'engine-pending-txpool-remove-blob-transaction))))

(defun engine-payload-store-remove-txpool-transactions-if
    (store predicate &key (include-pending-p t))
  (let ((txpool (engine-payload-store-txpool store))
        (removed-transactions nil))
    (dolist (subpool (engine-payload-store-subpool-views
                      store
                      :include-pending-p include-pending-p))
      (destructuring-bind (transactions . remove-function) subpool
        (dolist (transaction transactions)
          (when (funcall predicate transaction)
            (funcall remove-function txpool (transaction-hash transaction))
            (push transaction removed-transactions)))))
    (nreverse removed-transactions)))

(defun engine-payload-store-stale-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (chain-store-state-available-p store (block-hash head))
         (< (transaction-nonce transaction)
            (chain-store-account-nonce
             store
             (block-hash head)
             sender)))))

(defun engine-payload-store-remove-stale-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store)))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (engine-payload-store-remove-txpool-transactions-if
       store
       (lambda (transaction)
         (engine-payload-store-stale-txpool-transaction-p
          store head transaction
          :expected-chain-id expected-chain-id))))))

(defun engine-payload-store-expired-txpool-transaction-p
    (store transaction lifetime-seconds now)
  (let ((admitted-at
          (engine-pending-txpool-admission-time
           (engine-payload-store-txpool store)
           transaction)))
    (and admitted-at
         (>= (- now admitted-at) lifetime-seconds))))

(defun engine-payload-store-remove-expired-txpool-queued-view-transactions
    (store lifetime-seconds now &key local-transaction-predicate)
  (let ((removed-transactions nil))
    (when lifetime-seconds
      (unless (and (integerp lifetime-seconds) (not (minusp lifetime-seconds)))
        (block-validation-fail
         "Txpool lifetime must be a non-negative integer"))
      (unless (and (integerp now) (not (minusp now)))
        (block-validation-fail
         "Txpool cleanup time must be a non-negative integer"))
      (setf removed-transactions
            (engine-payload-store-remove-txpool-transactions-if
             store
             (lambda (transaction)
               (and (not (and local-transaction-predicate
                              (funcall local-transaction-predicate
                                       transaction)))
                    (engine-payload-store-expired-txpool-transaction-p
                     store transaction lifetime-seconds now)))
             :include-pending-p nil)))
    removed-transactions))
