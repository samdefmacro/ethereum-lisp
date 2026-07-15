(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-transaction-basefee-ineligible-p
    (store transaction)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header
                        (block-header-base-fee-per-gas header))))
    (and base-fee
         (< (transaction-max-fee-per-gas transaction) base-fee))))

(defun engine-payload-store-current-blob-base-fee
    (store &optional chain-config)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (if chain-config
          (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
              (chain-config-blob-schedule
               chain-config
               (block-header-number header)
               (block-header-timestamp header))
            (declare (ignore target-blob-gas max-blob-gas))
            (block-header-blob-base-fee
             header
             :update-fraction update-fraction))
          (block-header-blob-base-fee header)))))

(defun engine-payload-store-validate-txpool-blob-fee-cap
    (store transaction &key chain-config label)
  (when (typep transaction 'blob-transaction)
    (let ((blob-base-fee
            (engine-payload-store-current-blob-base-fee
             store
             chain-config)))
      (when blob-base-fee
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (block-validation-fail
             "~@[~A: ~]Max fee per blob gas below blob base fee"
             label))))))
  t)

(defun engine-payload-store-sender-code-admissible-p
    (store head sender)
  (or (null head)
      (not (chain-store-state-available-p store (block-hash head)))
      (let ((code (chain-store-account-code store (block-hash head) sender)))
        (or (zerop (length code))
            (set-code-delegation-target code)))))

(defun engine-payload-store-transaction-admission-funded-p
    (store sender transaction)
  (let ((head (chain-store-latest-block store)))
    (or (null head)
        (not (chain-store-state-available-p store (block-hash head)))
        (>= (chain-store-account-balance store (block-hash head) sender)
            (engine-payload-store-sender-admission-expenditure
             store
             sender
             transaction)))))
