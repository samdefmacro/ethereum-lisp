(in-package #:ethereum-lisp.execution)

;;;; Fork body-shape checks and mutable header snapshot helpers.

(defun validate-block-fork-body-shape-before-execution
    (header chain-config &key withdrawals-supplied-p requests-supplied-p
                              block-access-list-supplied-p
                              max-blob-gas)
  (when chain-config
    (let* ((number (block-header-number header))
           (timestamp (block-header-timestamp header))
           (london-p (chain-config-london-p chain-config number))
           (shanghai-p (chain-config-shanghai-p chain-config number timestamp))
           (cancun-p (chain-config-cancun-p chain-config number timestamp))
           (prague-p (chain-config-prague-p chain-config number timestamp))
           (amsterdam-p (chain-config-amsterdam-p chain-config number timestamp)))
      (cond
        (london-p
         (unless (block-header-base-fee-per-gas header)
           (error 'block-validation-error
                  :message "Header is missing base fee")))
        ((block-header-base-fee-per-gas header)
         (error 'block-validation-error
                :message "Base fee present before London")))
      (cond
        (shanghai-p
         (unless (or withdrawals-supplied-p
                     (block-header-withdrawals-root header))
           (error 'block-validation-error
                  :message "Header is missing withdrawals root")))
        ((or withdrawals-supplied-p
             (block-header-withdrawals-root header))
         (error 'block-validation-error
                :message "Withdrawals present before Shanghai")))
      (validate-block-cancun-fields header :cancun-enabled-p cancun-p)
      (if cancun-p
          (validate-block-blob-gas-fields header
                                          :blob-gas-enabled-p t
                                          :max-blob-gas max-blob-gas)
          (validate-block-blob-gas-fields header :blob-gas-enabled-p nil))
      (cond
        (prague-p
         (unless (or requests-supplied-p
                     (block-header-requests-hash header))
           (error 'block-validation-error
                  :message "Header is missing requests hash")))
        ((or requests-supplied-p
             (block-header-requests-hash header))
         (error 'block-validation-error
                :message "Execution requests present before Prague")))
      (cond
        (amsterdam-p
         (unless (or block-access-list-supplied-p
                     (block-header-block-access-list-hash header))
           (error 'block-validation-error
                  :message "Header is missing block access list hash")))
        ((or block-access-list-supplied-p
             (block-header-block-access-list-hash header))
         (error 'block-validation-error
                :message "Block access list present before Amsterdam")))))
  t)

(defun copy-block-header-for-execution (header)
  (make-block-header
   :parent-hash (block-header-parent-hash header)
   :ommers-hash (block-header-ommers-hash header)
   :beneficiary (block-header-beneficiary header)
   :state-root (block-header-state-root header)
   :transactions-root (block-header-transactions-root header)
   :receipts-root (block-header-receipts-root header)
   :logs-bloom (block-header-logs-bloom header)
   :difficulty (block-header-difficulty header)
   :number (block-header-number header)
   :gas-limit (block-header-gas-limit header)
   :gas-used (block-header-gas-used header)
   :timestamp (block-header-timestamp header)
   :extra-data (block-header-extra-data header)
   :mix-hash (block-header-mix-hash header)
   :nonce (block-header-nonce header)
   :base-fee-per-gas (block-header-base-fee-per-gas header)
   :withdrawals-root (block-header-withdrawals-root header)
   :blob-gas-used (block-header-blob-gas-used header)
   :excess-blob-gas (block-header-excess-blob-gas header)
   :parent-beacon-root (block-header-parent-beacon-root header)
   :requests-hash (block-header-requests-hash header)
   :block-access-list-hash (block-header-block-access-list-hash header)
   :slot-number (block-header-slot-number header)))

(defun restore-block-header-for-execution (header snapshot)
  (setf (block-header-parent-hash header) (block-header-parent-hash snapshot)
        (block-header-ommers-hash header) (block-header-ommers-hash snapshot)
        (block-header-beneficiary header) (block-header-beneficiary snapshot)
        (block-header-state-root header) (block-header-state-root snapshot)
        (block-header-transactions-root header)
        (block-header-transactions-root snapshot)
        (block-header-receipts-root header) (block-header-receipts-root snapshot)
        (block-header-logs-bloom header) (block-header-logs-bloom snapshot)
        (block-header-difficulty header) (block-header-difficulty snapshot)
        (block-header-number header) (block-header-number snapshot)
        (block-header-gas-limit header) (block-header-gas-limit snapshot)
        (block-header-gas-used header) (block-header-gas-used snapshot)
        (block-header-timestamp header) (block-header-timestamp snapshot)
        (block-header-extra-data header) (block-header-extra-data snapshot)
        (block-header-mix-hash header) (block-header-mix-hash snapshot)
        (block-header-nonce header) (block-header-nonce snapshot)
        (block-header-base-fee-per-gas header)
        (block-header-base-fee-per-gas snapshot)
        (block-header-withdrawals-root header)
        (block-header-withdrawals-root snapshot)
        (block-header-blob-gas-used header)
        (block-header-blob-gas-used snapshot)
        (block-header-excess-blob-gas header)
        (block-header-excess-blob-gas snapshot)
        (block-header-parent-beacon-root header)
        (block-header-parent-beacon-root snapshot)
        (block-header-requests-hash header) (block-header-requests-hash snapshot)
        (block-header-block-access-list-hash header)
        (block-header-block-access-list-hash snapshot)
        (block-header-slot-number header) (block-header-slot-number snapshot))
  header)
