(in-package #:ethereum-lisp.execution)

(defun execution-hash32= (left right)
  (and left
       right
       (bytes= (hash32-bytes left) (hash32-bytes right))))

(defun normalize-execution-block-access-list-input
    (block-access-list block-access-list-supplied-p
     block-access-list-rlp block-access-list-rlp-supplied-p)
  (when (and block-access-list-supplied-p
             block-access-list-rlp-supplied-p)
    (error 'block-validation-error
           :message
           "Block access list cannot be supplied as both typed data and RLP"))
  (if block-access-list-rlp-supplied-p
      (values (block-access-list-from-rlp block-access-list-rlp)
              t
              (ensure-byte-vector block-access-list-rlp))
      (values block-access-list block-access-list-supplied-p nil)))

(defun execution-block-access-list-commitment
    (block-access-list encoded-block-access-list &key max-code-size max-items)
  (validate-block-access-list-fields block-access-list
                                     :max-code-size max-code-size
                                     :max-items max-items)
  (if encoded-block-access-list
      (let ((decoded (block-access-list-from-rlp
                      encoded-block-access-list
                      :max-code-size max-code-size
                      :max-items max-items)))
        (unless (bytes= (block-access-list-rlp decoded)
                        (block-access-list-rlp block-access-list))
          (error 'block-validation-error
                 :message
                 "Encoded block access list does not match block access list body"))
        (keccak-256-hash encoded-block-access-list))
      (block-access-list-hash block-access-list)))

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

(defun validate-block-body-commitments-before-execution
    (transactions header &key (ommers '())
                              withdrawals
                              withdrawals-supplied-p
                              requests
                              requests-supplied-p
                              block-access-list
                              block-access-list-supplied-p
                              encoded-block-access-list
                              max-blob-gas
                              block-access-list-max-code-size)
  (let ((actual-blob-gas-used (blob-gas-used transactions))
        (header-blob-gas-used (block-header-blob-gas-used header)))
    (when (and (block-header-transactions-root header)
               (not (execution-hash32=
                     (block-header-transactions-root header)
                     (transaction-list-root transactions))))
      (error 'block-validation-error :message "Transaction root hash mismatch"))
    (when (and (block-header-ommers-hash header)
               (not (execution-hash32=
                     (block-header-ommers-hash header)
                     (ommers-hash ommers))))
      (error 'block-validation-error :message "Ommers root hash mismatch"))
    (when (block-header-withdrawals-root header)
      (unless withdrawals-supplied-p
        (error 'block-validation-error
               :message "Missing withdrawals in block body"))
      (validate-withdrawal-list-fields withdrawals)
      (unless (execution-hash32= (block-header-withdrawals-root header)
                                 (withdrawal-list-root withdrawals))
        (error 'block-validation-error
               :message "Withdrawals root hash mismatch")))
    (when (and withdrawals-supplied-p
               (not (block-header-withdrawals-root header)))
      (validate-withdrawal-list-fields withdrawals))
    (when (block-header-requests-hash header)
      (unless requests-supplied-p
        (error 'block-validation-error
               :message "Missing execution requests in block body"))
      (validate-execution-request-list-fields requests)
      (unless (execution-hash32= (block-header-requests-hash header)
                                 (execution-requests-hash requests))
        (error 'block-validation-error
               :message "Execution requests hash mismatch")))
    (when (and requests-supplied-p
               (not (block-header-requests-hash header)))
      (validate-execution-request-list-fields requests))
    (when (block-header-block-access-list-hash header)
      (unless block-access-list-supplied-p
        (error 'block-validation-error
               :message "Missing block access list in block body"))
      (unless (execution-hash32= (block-header-block-access-list-hash header)
                                 (execution-block-access-list-commitment
                                  block-access-list
                                  encoded-block-access-list
                                  :max-code-size
                                  block-access-list-max-code-size
                                  :max-items
                                  (when (plusp (block-header-gas-limit header))
                                    (floor (block-header-gas-limit header)
                                           +block-access-list-item-gas-cost+))))
        (error 'block-validation-error
               :message "Block access list hash mismatch")))
    (when (and block-access-list-supplied-p
               (not (block-header-block-access-list-hash header)))
      (execution-block-access-list-commitment
       block-access-list
       encoded-block-access-list
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (when (and header-blob-gas-used
               (/= header-blob-gas-used actual-blob-gas-used))
      (error 'block-validation-error :message "Blob gas used mismatch"))
    (when (and max-blob-gas
               (> actual-blob-gas-used max-blob-gas))
      (error 'block-validation-error :message "Blob gas used exceeds maximum"))
    actual-blob-gas-used))

(defun validate-supplied-block-execution-roots
    (header transactions receipts state-root)
  (let ((receipts-root (transaction-receipt-list-root transactions receipts))
        (gas-used (if receipts
                      (receipt-cumulative-gas-used (car (last receipts)))
                      0))
        (logs-bloom (bloom-bytes
                     (receipt-bloom
                      (loop for receipt in receipts
                            append (receipt-logs receipt))))))
    (when (and (plusp (block-header-gas-used header))
               (/= (block-header-gas-used header) gas-used))
      (error 'block-validation-error :message "Gas used mismatch"))
    (when (and (block-header-state-root header)
               (not (execution-hash32= (block-header-state-root header)
                                       state-root)))
      (error 'block-validation-error :message "State root mismatch"))
    (when (and (block-header-receipts-root header)
               (not (execution-hash32= (block-header-receipts-root header)
                                       receipts-root)))
      (error 'block-validation-error :message "Receipts root mismatch"))
    (when (and (block-header-logs-bloom header)
               (not (bytes= (block-header-logs-bloom header) logs-bloom)))
      (error 'block-validation-error :message "Logs bloom mismatch")))
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
