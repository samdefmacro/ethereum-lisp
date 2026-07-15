(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-indexed-sender-nonce-transaction
    (sender-index sender nonce)
  (let ((sender-transactions
          (gethash (address-to-hex sender) sender-index)))
    (when sender-transactions
      (gethash (write-to-string nonce :base 10) sender-transactions))))

(defun engine-payload-store-indexed-sender-transactions
    (sender-index sender)
  (let ((sender-transactions
          (gethash (address-to-hex sender) sender-index)))
    (when sender-transactions
      (loop for transaction being the hash-values of sender-transactions
            collect transaction))))

(defun engine-payload-store-indexed-sender-transactions-sorted
    (sender-index sender)
  (sort (engine-payload-store-indexed-sender-transactions
         sender-index
         sender)
        #'<
        :key #'transaction-nonce))

(defun engine-payload-store-indexed-senders-into (sender-index senders)
  (loop for sender-key being the hash-keys of sender-index
        do (setf (gethash sender-key senders)
                 (address-from-hex sender-key)))
  senders)

(defun engine-payload-store-pooled-senders (store)
  (let ((senders (make-hash-table :test 'equalp)))
    (dolist (sender-index
             (list (engine-payload-store-pending-sender-index store)
                   (engine-payload-store-queued-sender-index store)
                   (engine-payload-store-basefee-sender-index store)
                   (engine-payload-store-blob-sender-index store)))
      (engine-payload-store-indexed-senders-into sender-index senders))
    (loop for sender being the hash-values of senders
          collect sender)))

(defun engine-payload-store-sender-pooled-transactions (store sender)
  (loop for sender-index in
          (list (engine-payload-store-pending-sender-index store)
                (engine-payload-store-queued-sender-index store)
                (engine-payload-store-basefee-sender-index store)
                (engine-payload-store-blob-sender-index store))
        append (engine-payload-store-indexed-sender-transactions
                sender-index
                sender)))

(defun engine-payload-store-indexed-senders (sender-index)
  (loop for sender-key being the hash-keys of sender-index
        collect (address-from-hex sender-key)))

(defun engine-payload-store-pending-contiguous-nonce
    (store sender state-nonce &key expected-chain-id)
  (loop with next-nonce = state-nonce
        for transaction =
          (engine-payload-store-indexed-sender-nonce-transaction
           (engine-payload-store-pending-sender-index store)
           sender
           next-nonce)
        while (and transaction
                   (or (null expected-chain-id)
                       (transaction-sender
                        transaction
                        :expected-chain-id expected-chain-id)))
          do (incf next-nonce)
        finally (return next-nonce)))
