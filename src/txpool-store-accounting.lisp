(in-package #:ethereum-lisp.core)

(defun engine-payload-store-txpool-upfront-cost (transaction)
  (+ (transaction-value transaction)
     (* (transaction-gas-limit transaction)
        (transaction-max-fee-per-gas transaction))
     (* (transaction-blob-gas-used transaction)
        (if (typep transaction 'blob-transaction)
            (blob-transaction-max-fee-per-blob-gas transaction)
            0))))

(defun engine-payload-store-pending-sender-expenditure
    (store sender transaction)
  (let ((new-cost (engine-payload-store-txpool-upfront-cost transaction))
        (existing-cost 0)
        (replacement-cost nil))
    (dolist (pooled
             (engine-payload-store-indexed-sender-transactions
              (engine-payload-store-pending-sender-index store)
              sender))
      (let ((pooled-cost
              (engine-payload-store-txpool-upfront-cost pooled)))
        (incf existing-cost pooled-cost)
        (when (= (transaction-nonce pooled)
                 (transaction-nonce transaction))
          (setf replacement-cost pooled-cost))))
    (if replacement-cost
        (+ existing-cost (- new-cost replacement-cost))
        (+ existing-cost new-cost))))

(defun engine-payload-store-sender-admission-expenditure
    (store sender transaction)
  (let ((new-cost (engine-payload-store-txpool-upfront-cost transaction))
        (existing-cost 0)
        (replacement-cost nil))
    (dolist (pooled
             (engine-payload-store-sender-pooled-transactions
              store
              sender))
      (let ((pooled-cost
              (engine-payload-store-txpool-upfront-cost pooled)))
        (incf existing-cost pooled-cost)
        (when (= (transaction-nonce pooled)
                 (transaction-nonce transaction))
          (setf replacement-cost pooled-cost))))
    (if replacement-cost
        (+ existing-cost (- new-cost replacement-cost))
        (+ existing-cost new-cost))))
