(in-package #:ethereum-lisp.core)

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
  (and
   (engine-pending-txpool-replacement-price-bumped-p
    old-transaction
    new-transaction
    #'transaction-max-fee-per-gas
    :price-bump-percent price-bump-percent)
   (engine-pending-txpool-replacement-price-bumped-p
    old-transaction
    new-transaction
    #'transaction-max-priority-fee-per-gas
    :price-bump-percent price-bump-percent)))
