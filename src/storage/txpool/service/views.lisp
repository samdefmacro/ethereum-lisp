(in-package #:ethereum-lisp.txpool)

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

(defun transaction-effective-tip (transaction base-fee)
  "What the builder actually earns per unit of gas from TRANSACTION.

The fee cap is what a sender is willing to pay in total; the base fee is burned,
so the builder receives the priority fee, capped by whatever room the fee cap
leaves above the base fee. A transaction advertising a huge priority fee it
cannot afford at this base fee is worth exactly that remaining room, which is why
this is a MIN rather than the priority fee alone."
  (let ((cap (transaction-max-fee-per-gas transaction))
        (tip (transaction-max-priority-fee-per-gas transaction)))
    (max 0 (min tip (- cap (or base-fee 0))))))

(defun engine-mining-sender-groups (transactions expected-chain-id)
  "TRANSACTIONS grouped by sender, each group in nonce order.

Nonce order within a sender is not a preference, it is a requirement: a
sender's nonce N+1 cannot execute before N, so no ordering may separate or
reorder them."
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (transaction transactions)
      (let* ((sender (transaction-sender transaction
                                         :expected-chain-id expected-chain-id))
             (key (and sender (address-to-hex sender))))
        (when key
          (push transaction (gethash key groups)))))
    (let ((result '()))
      (maphash (lambda (key group)
                 (push (cons key (sort (nreverse group) #'<
                                       :key #'transaction-nonce))
                       result))
               groups)
      result)))

(defun engine-mining-best-sender-group (groups base-fee)
  (reduce
   (lambda (best candidate)
     (let ((best-tip
             (transaction-effective-tip (second best) base-fee))
           (candidate-tip
             (transaction-effective-tip (second candidate) base-fee)))
       (if (or (> candidate-tip best-tip)
               (and (= candidate-tip best-tip)
                    (string< (first candidate) (first best))))
           candidate
           best)))
   (rest groups)
   :initial-value (first groups)))

(defun engine-mining-interleave-sender-groups (groups base-fee)
  "Pop the most profitable executable sender head and re-compare after each."
  (loop while groups
        for best = (engine-mining-best-sender-group groups base-fee)
        collect (pop (cdr best))
        do (when (null (cdr best))
             (setf groups (delete best groups :test #'eq)))))

(defun engine-payload-store-pending-mining-transactions
    (store expected-chain-id &key base-fee)
  "The pending transactions in the order a block should try to include them.

With a BASE-FEE, senders are ordered by what their next transaction actually
pays -- most profitable first -- rather than by address, which was arbitrary.
Ordering by address meant a block filled with whoever happened to sort first and
left better-paying transactions out whenever the gas limit bound.

Each sender's transactions stay contiguous and in nonce order, so the ordering
is over SENDERS, keyed by the tip of their lowest-nonce transaction. That is
what makes profitability and nonce ordering compatible: the only transaction of
a sender that can be included next is its lowest, so its tip is the one that
decides where the sender belongs.

Without a BASE-FEE the old address/nonce/hash order is kept, so a caller that
does not know the base fee is unaffected."
  (let ((transactions
          (remove-if-not
           (lambda (transaction)
             (and
              (transaction-sender transaction
                                  :expected-chain-id expected-chain-id)
              ;; Pending classification reflects the parent state.  A rising
              ;; base fee can make the transaction ineligible for the child
              ;; being built, so enforce the child's fee here as well.
              (or (null base-fee)
                  (>= (transaction-max-fee-per-gas transaction)
                      base-fee))))
           (append
            (engine-payload-store-pending-transactions store)
            (engine-payload-store-blob-transactions store)))))
    (if (null base-fee)
        (sort (copy-list transactions)
              (lambda (left right)
                (engine-mining-transaction< left right expected-chain-id)))
        (let ((groups (engine-mining-sender-groups transactions
                                                   expected-chain-id)))
          (engine-mining-interleave-sender-groups groups base-fee)))))

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
