(in-package #:ethereum-lisp.public-api)

(defconstant +eth-rpc-gas-oracle-block-count+ 20)
(defconstant +eth-rpc-gas-oracle-percentile+ 60)
(defconstant +eth-rpc-gas-oracle-default-tip+ 1000000)
(defconstant +eth-rpc-gas-oracle-samples-per-block+ 3)
(defconstant +eth-rpc-gas-oracle-ignore-under+ 2)
(defconstant +eth-rpc-gas-oracle-maximum-tip+ 500000000000)

(defun eth-rpc-block-priority-fee-samples (block)
  "Return (TIP . GAS-USED) samples for BLOCK in transaction order."
  (let ((base-fee
          (or (block-header-base-fee-per-gas (block-header block)) 0))
        (previous-cumulative 0))
    (loop for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for cumulative = (receipt-cumulative-gas-used receipt)
          for gas-used = (- cumulative previous-cumulative)
          do (setf previous-cumulative cumulative)
          collect
          (cons
           (transaction-priority-fee-per-gas
            transaction :base-fee base-fee)
           gas-used))))

(defun eth-rpc-priority-fee-percentile (samples percentile)
  "Return the gas-weighted priority-fee percentile from (TIP . GAS) SAMPLES."
  (if (null samples)
      0
      (let* ((ordered (sort (copy-list samples) #'< :key #'car))
             (total-gas (loop for sample in ordered sum (cdr sample)))
             (threshold (* total-gas (/ percentile 100)))
             (used 0))
        (or (loop for (tip . gas) in ordered
                  do (incf used gas)
                  when (>= used threshold)
                    return tip)
            (caar (last ordered))))))

(defun eth-rpc-gas-oracle-block-samples (block config)
  "Return the lowest usable gas-oracle tip samples for BLOCK."
  (let* ((header (block-header block))
         (base-fee (or (block-header-base-fee-per-gas header) 0))
         (beneficiary (or (block-header-beneficiary header) (zero-address)))
         (expected-chain-id (chain-config-chain-id config))
         (ordered
           (sort (copy-list (block-transactions block)) #'<
                 :key (lambda (transaction)
                        (transaction-priority-fee-per-gas
                         transaction :base-fee base-fee)))))
    (loop for transaction in ordered
          for tip = (transaction-priority-fee-per-gas
                     transaction :base-fee base-fee)
          for sender = (and (>= tip +eth-rpc-gas-oracle-ignore-under+)
                            (transaction-sender
                             transaction
                             :expected-chain-id expected-chain-id))
          when (and sender
                    (not (bytes= (address-bytes sender)
                                 (address-bytes beneficiary))))
            collect tip into samples
          when (= (length samples) +eth-rpc-gas-oracle-samples-per-block+)
            return samples
          finally (return samples))))

(defun eth-rpc-gas-oracle-percentile (samples percentile)
  (let ((ordered (sort (copy-list samples) #'<)))
    (nth (floor (* (1- (length ordered)) percentile) 100) ordered)))

(defun engine-rpc-suggest-gas-tip-cap (store config)
  (let* ((head-number (chain-store-head-number store))
         (first-number
           (max 1 (1+ (- head-number +eth-rpc-gas-oracle-block-count+))))
         (samples
           (loop for number from first-number to head-number
                 for block = (chain-store-block-by-number store number)
                 when block
                   append (or (eth-rpc-gas-oracle-block-samples block config)
                              (list +eth-rpc-gas-oracle-default-tip+)))))
    (min +eth-rpc-gas-oracle-maximum-tip+
         (if samples
             (eth-rpc-gas-oracle-percentile
              samples +eth-rpc-gas-oracle-percentile+)
             +eth-rpc-gas-oracle-default-tip+))))

(defun engine-rpc-handle-eth-max-priority-fee-per-gas (params store config)
  (when params
    (block-validation-fail "eth_maxPriorityFeePerGas params must be empty"))
  (quantity-to-hex (engine-rpc-suggest-gas-tip-cap store config)))

(defun engine-rpc-handle-eth-gas-price (params store config)
  (when params
    (block-validation-fail "eth_gasPrice params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (if header
                       (or (block-header-base-fee-per-gas header) 0)
                       0)))
    (quantity-to-hex (+ base-fee
                        (engine-rpc-suggest-gas-tip-cap store config)))))

(defun engine-payload-store-head-block (store)
  (chain-store-block-by-number
   store
   (engine-payload-store-head-number store)))

(defun engine-rpc-handle-eth-base-fee (params store config)
  (when params
    (block-validation-fail "eth_baseFee params must be empty"))
  (let ((head (chain-store-latest-block store)))
    (when (and head
               (chain-config-london-p
                config
                (1+ (block-header-number (block-header head)))))
      (quantity-to-hex
       (expected-base-fee-per-gas
        (block-header head)
        :london-parent-p
        (not (null (block-header-base-fee-per-gas (block-header head)))))))))

(defun engine-rpc-handle-eth-blob-base-fee (params store config)
  (when params
    (block-validation-fail "eth_blobBaseFee params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (chain-config-blob-schedule
           config
           (block-header-number header)
           (block-header-timestamp header))
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction))))))
