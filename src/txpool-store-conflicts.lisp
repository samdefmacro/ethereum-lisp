(in-package #:ethereum-lisp.core)

(defun engine-payload-store-txpool-conflict-p (store transaction)
  (let ((txpool (engine-payload-store-txpool store)))
    (or (engine-pending-txpool-pending-conflict txpool transaction)
        (engine-pending-txpool-queued-conflict txpool transaction)
        (engine-pending-txpool-basefee-conflict txpool transaction)
        (engine-pending-txpool-blob-conflict txpool transaction))))

(defun engine-payload-store-replacement-price-bumped-p
    (old-transaction new-transaction price-function
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-price-bumped-p
   old-transaction
   new-transaction
   price-function
   :price-bump-percent price-bump-percent))

(defun engine-payload-store-replacement-transaction-p
    (old-transaction new-transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-transaction-p
   old-transaction
   new-transaction
   :price-bump-percent price-bump-percent))
