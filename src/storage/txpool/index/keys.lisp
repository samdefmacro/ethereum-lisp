(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-sender (transaction)
  (or (transaction-sender transaction)
      (block-validation-fail
       "Txpool transaction sender recovery failed")))

(defun engine-pending-txpool-sender-key (transaction)
  (address-to-hex (engine-pending-txpool-sender transaction)))

(defun engine-pending-txpool-nonce-key (transaction)
  (write-to-string (transaction-nonce transaction) :base 10))

(defun engine-pending-txpool-hash-key (hash)
  (unless (hash32-p hash)
    (block-validation-fail "Txpool hash key must be a hash32"))
  (hash32-to-hex hash))

(defun engine-pending-txpool-transaction-hash-key (transaction)
  (engine-pending-txpool-hash-key (transaction-hash transaction)))

(defun engine-pending-txpool-note-admission-time
    (txpool transaction admitted-at)
  (when admitted-at
    (setf (gethash (engine-pending-txpool-transaction-hash-key transaction)
                   (engine-pending-txpool-transaction-admitted-at txpool))
          admitted-at))
  transaction)

(defun engine-pending-txpool-clear-admission-time
    (txpool transaction-or-hash)
  (remhash (engine-pending-txpool-hash-key
            (if (hash32-p transaction-or-hash)
                transaction-or-hash
                (transaction-hash transaction-or-hash)))
           (engine-pending-txpool-transaction-admitted-at txpool)))

(defun engine-pending-txpool-admission-time (txpool transaction)
  (gethash (engine-pending-txpool-transaction-hash-key transaction)
           (engine-pending-txpool-transaction-admitted-at txpool)))

(defun engine-payload-store-pending-sender-key (transaction)
  (engine-pending-txpool-sender-key transaction))

(defun engine-payload-store-pending-nonce-key (transaction)
  (engine-pending-txpool-nonce-key transaction))
