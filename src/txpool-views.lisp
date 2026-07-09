(in-package #:ethereum-lisp.core)

(defun engine-payload-store-pending-sender-transactions
    (store sender)
  (engine-payload-store-indexed-sender-transactions-sorted
   (engine-payload-store-pending-sender-index store)
   sender))

(defun engine-payload-store-pending-transaction (store hash)
  (engine-pending-txpool-pending-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-queued-transaction (store hash)
  (engine-pending-txpool-queued-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-basefee-transaction (store hash)
  (engine-pending-txpool-basefee-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-blob-transaction (store hash)
  (engine-pending-txpool-blob-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-pooled-transaction (store hash)
  (or (engine-payload-store-pending-transaction store hash)
      (engine-payload-store-queued-transaction store hash)
      (engine-payload-store-basefee-transaction store hash)
      (engine-payload-store-blob-transaction store hash)))

(defun engine-payload-store-pending-transactions (store)
  (engine-pending-txpool-pending-transactions
   (engine-payload-store-txpool store)))

(defun engine-mining-transaction< (left right expected-chain-id)
  (let* ((left-sender (transaction-sender left
                                          :expected-chain-id
                                          expected-chain-id))
         (right-sender (transaction-sender right
                                           :expected-chain-id
                                           expected-chain-id))
         (left-sender-key (if left-sender
                              (address-to-hex left-sender)
                              ""))
         (right-sender-key (if right-sender
                               (address-to-hex right-sender)
                               "")))
    (cond
      ((string< left-sender-key right-sender-key) t)
      ((string< right-sender-key left-sender-key) nil)
      ((< (transaction-nonce left) (transaction-nonce right)) t)
      ((< (transaction-nonce right) (transaction-nonce left)) nil)
      (t
       (string< (hash32-to-hex (transaction-hash left))
                (hash32-to-hex (transaction-hash right)))))))

(defun engine-payload-store-pending-mining-transactions
    (store expected-chain-id)
  (sort
   (copy-list
    (remove-if-not
     (lambda (transaction)
       (transaction-sender transaction
                           :expected-chain-id expected-chain-id))
     (engine-payload-store-pending-transactions store)))
   (lambda (left right)
     (engine-mining-transaction< left right expected-chain-id))))

(defun engine-select-mining-transactions
    (transactions gas-limit expected-chain-id)
  (let ((blocked-senders (make-hash-table :test #'equal)))
    (loop with selected = nil
          with gas-used = 0
          for transaction in transactions
          for sender = (transaction-sender
                        transaction
                        :expected-chain-id expected-chain-id)
          for sender-key = (and sender (address-to-hex sender))
          for transaction-gas = (transaction-gas-limit transaction)
          when (and sender-key
                    (not (gethash sender-key blocked-senders)))
            do (if (<= (+ gas-used transaction-gas) gas-limit)
                   (progn
                     (push transaction selected)
                     (incf gas-used transaction-gas))
                   (setf (gethash sender-key blocked-senders) t))
          finally (return (nreverse selected)))))

(defun engine-payload-store-queued-transactions (store)
  (engine-pending-txpool-queued-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transactions (store)
  (engine-pending-txpool-basefee-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transactions (store)
  (engine-pending-txpool-blob-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pooled-transactions (store)
  (sort
   (append (engine-payload-store-pending-transactions store)
           (engine-payload-store-queued-transactions store)
           (engine-payload-store-basefee-transactions store)
           (engine-payload-store-blob-transactions store))
   #'string<
   :key (lambda (transaction)
          (hash32-to-hex (transaction-hash transaction)))))

(defun engine-payload-store-pending-transactions-by-sender (store)
  (engine-payload-store-pending-sender-index store))

(defun engine-payload-store-pending-transaction-count (store)
  (engine-pending-txpool-pending-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-transaction-count (store)
  (engine-pending-txpool-queued-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transaction-count (store)
  (engine-pending-txpool-basefee-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transaction-count (store)
  (engine-pending-txpool-blob-count
   (engine-payload-store-txpool store)))
