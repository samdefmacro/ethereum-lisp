(in-package #:ethereum-lisp.txpool.index)

(defconstant +txpool-blob-replacement-price-bump-percent+ 100)

(defun engine-pending-txpool-replacement-price-bumped-p
    (old-transaction new-transaction price-function
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (let ((price-bump-percent
          (or price-bump-percent +txpool-replacement-price-bump-percent+))
        (old-price (funcall price-function old-transaction))
        (new-price (funcall price-function new-transaction)))
    (and (> new-price old-price)
         (>= (* new-price 100)
             (* old-price
                (+ 100 price-bump-percent))))))

(defun engine-pending-txpool-replacement-transaction-p
    (old-transaction new-transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (let ((blob-replacement-p
          (and (typep old-transaction 'blob-transaction)
               (typep new-transaction 'blob-transaction))))
    (and
     (engine-pending-txpool-replacement-price-bumped-p
      old-transaction
      new-transaction
      #'transaction-max-fee-per-gas
      :price-bump-percent
      (if blob-replacement-p
          +txpool-blob-replacement-price-bump-percent+
          price-bump-percent))
     (engine-pending-txpool-replacement-price-bumped-p
      old-transaction
      new-transaction
      #'transaction-max-priority-fee-per-gas
      :price-bump-percent
      (if blob-replacement-p
          +txpool-blob-replacement-price-bump-percent+
          price-bump-percent))
     (or
      (not blob-replacement-p)
      (engine-pending-txpool-replacement-price-bumped-p
       old-transaction
       new-transaction
       #'blob-transaction-max-fee-per-blob-gas
       :price-bump-percent
       +txpool-blob-replacement-price-bump-percent+)))))
