(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-pending-sender-transactions
    (store sender)
  (engine-payload-store-indexed-sender-transactions-sorted
   (engine-payload-store-pending-sender-index store)
   sender))

(defun engine-payload-store-pending-sender-nonce-transaction
    (store sender nonce)
  "Return SENDER's pending transaction at NONCE without scanning its prefix."
  (engine-payload-store-indexed-sender-nonce-transaction
   (engine-payload-store-pending-sender-index store)
   sender nonce))

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

(defun engine-mining-sort-key (transaction sender-key)
  "TRANSACTION's address/nonce/hash ordering key, computed once per build."
  (list sender-key
        (transaction-nonce transaction)
        (hash32-to-hex (transaction-hash transaction))))

(defun engine-mining-sort-key< (left right)
  (destructuring-bind (left-sender left-nonce left-hash) left
    (destructuring-bind (right-sender right-nonce right-hash) right
      (cond
        ((string< left-sender right-sender) t)
        ((string< right-sender left-sender) nil)
        ((< left-nonce right-nonce) t)
        ((< right-nonce left-nonce) nil)
        (t (string< left-hash right-hash))))))

(defun engine-mining-sort-by-key (entries)
  "The transactions of ENTRIES, (SENDER-KEY . TRANSACTION) pairs, in
address, nonce and hash order.

SORT calls its predicate about 2 n log n times, so the key is built once per
transaction rather than per comparison; the comparator used to recover both
senders and re-encode both hashes on every call."
  (mapcar #'cdr
          (sort (mapcar (lambda (entry)
                          (cons (engine-mining-sort-key (cdr entry)
                                                        (car entry))
                                (cdr entry)))
                        entries)
                #'engine-mining-sort-key<
                :key #'car)))

(defun transaction-effective-tip (transaction base-fee)
  "What the builder actually earns per unit of gas from TRANSACTION.

The fee cap is what a sender is willing to pay in total; the base fee is burned,
so the builder receives the priority fee, capped by whatever room the fee cap
leaves above the base fee. A transaction advertising a huge priority fee it
cannot afford at this base fee is worth exactly that remaining room, which is why
this is a MIN rather than the priority fee alone. Pool eviction ranks by the
same quantity (ENGINE-PENDING-TXPOOL-EFFECTIVE-TIP)."
  (engine-pending-txpool-effective-tip transaction base-fee))

(defun engine-mining-sender-keyed-transactions
    (transactions expected-chain-id)
  "(SENDER-KEY . TRANSACTION) for each of TRANSACTIONS whose sender
EXPECTED-CHAIN-ID admits, in the order given.  The one place a build asks
for each transaction's sender."
  (loop for transaction in transactions
        for sender = (transaction-sender transaction
                                         :expected-chain-id expected-chain-id)
        when sender
          collect (cons (address-to-hex sender) transaction)))

(defun engine-mining-keyed-sender-groups (entries)
  "The transactions of ENTRIES, (SENDER-KEY . TRANSACTION) pairs, grouped by
sender as (SENDER-KEY . TRANSACTIONS), each group in nonce order.

Nonce order within a sender is not a preference, it is a requirement: a
sender's nonce N+1 cannot execute before N, so no ordering may separate or
reorder them."
  (let ((groups (make-hash-table :test #'equal)))
    (loop for (key . transaction) in entries
          do (push transaction (gethash key groups)))
    (let ((result '()))
      (maphash (lambda (key group)
                 (push (cons key (sort (nreverse group) #'<
                                       :key #'transaction-nonce))
                       result))
               groups)
      result)))

(defun engine-mining-sender-groups (transactions expected-chain-id)
  "TRANSACTIONS grouped by sender, each group in nonce order (see
ENGINE-MINING-KEYED-SENDER-GROUPS)."
  (engine-mining-keyed-sender-groups
   (engine-mining-sender-keyed-transactions transactions expected-chain-id)))

(defun engine-mining-group-before-p (left right)
  "Whether heap entry LEFT, (TIP . (SENDER-KEY . TRANSACTIONS)), is included
before RIGHT: the higher tip first, the lower sender key on a tie."
  (let ((left-tip (car left))
        (right-tip (car right)))
    (or (> left-tip right-tip)
        (and (= left-tip right-tip)
             (string< (cadr left) (cadr right))))))

(defun engine-mining-heap-sift-down (heap index)
  (let ((count (fill-pointer heap)))
    (loop
      (let* ((left (1+ (* 2 index)))
             (right (1+ left))
             (best index))
        (when (and (< left count)
                   (engine-mining-group-before-p (aref heap left)
                                                 (aref heap best)))
          (setf best left))
        (when (and (< right count)
                   (engine-mining-group-before-p (aref heap right)
                                                 (aref heap best)))
          (setf best right))
        (when (= best index)
          (return heap))
        (rotatef (aref heap index) (aref heap best))
        (setf index best)))))

(defun engine-mining-interleave-sender-groups (groups base-fee)
  "Pop the most profitable executable sender head and re-compare after each.

GROUPS are (SENDER-KEY . TRANSACTIONS) in nonce order.  A binary heap keyed
by each group's head tip, computed once per head, replaces a scan of every
group per included transaction: that scan was O(transactions x senders), 107
ms of a 4,000-transaction build over 1,000 senders.  The order is the same,
since the key is a total order (sender keys are unique)."
  (let ((heap (make-array (length groups) :fill-pointer 0)))
    (dolist (group groups)
      (vector-push (cons (transaction-effective-tip (second group) base-fee)
                         group)
                   heap))
    (loop for index from (1- (floor (fill-pointer heap) 2)) downto 0
          do (engine-mining-heap-sift-down heap index))
    (loop while (plusp (fill-pointer heap))
          collect (let* ((entry (aref heap 0))
                         (group (cdr entry))
                         (transaction (pop (cdr group))))
                    (if (cdr group)
                        (setf (car entry)
                              (transaction-effective-tip (second group)
                                                         base-fee))
                        (setf (aref heap 0)
                              (aref heap (1- (fill-pointer heap)))
                              (fill-pointer heap)
                              (1- (fill-pointer heap))))
                    (engine-mining-heap-sift-down heap 0)
                    transaction))))

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
  (let ((entries
          (engine-mining-sender-keyed-transactions
           (remove-if-not
            (lambda (transaction)
              ;; Pending classification reflects the parent state.  A rising
              ;; base fee can make the transaction ineligible for the child
              ;; being built, so enforce the child's fee here as well.
              (or (null base-fee)
                  (>= (transaction-max-fee-per-gas transaction)
                      base-fee)))
            (append
             (engine-payload-store-pending-transactions store)
             (engine-payload-store-blob-transactions store)))
           expected-chain-id)))
    (if (null base-fee)
        (engine-mining-sort-by-key entries)
        (engine-mining-interleave-sender-groups
         (engine-mining-keyed-sender-groups entries)
         base-fee))))

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
  "Every pooled transaction, in transaction-hash order.  Each hash is read
once, not once per comparison."
  (mapcar
   #'cdr
   (sort
    (mapcar (lambda (transaction)
              (cons (hash32-to-hex (transaction-hash transaction))
                    transaction))
            (append (engine-payload-store-pending-transactions store)
                    (engine-payload-store-queued-transactions store)
                    (engine-payload-store-basefee-transactions store)
                    (engine-payload-store-blob-transactions store)))
    #'string<
    :key #'car)))

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
