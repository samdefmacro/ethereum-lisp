(in-package #:ethereum-lisp.public-api)

(defconstant +eth-rpc-gas-oracle-block-count+ 20)
(defconstant +eth-rpc-gas-oracle-percentile+ 60)
(defconstant +eth-rpc-gas-oracle-default-tip+ 1000000)
(defconstant +eth-rpc-gas-oracle-samples-per-block+ 3)
(defconstant +eth-rpc-gas-oracle-ignore-under+ 2)
(defconstant +eth-rpc-gas-oracle-maximum-tip+ 500000000000)

(defstruct (eth-rpc-gas-oracle-state
            (:constructor make-eth-rpc-gas-oracle-state
                (&key
                 (last-price +eth-rpc-gas-oracle-default-tip+))))
  "Process-local recommendation state shared by one RPC service."
  last-head
  last-price
  (lock #+sbcl
        (sb-thread:make-mutex :name "ethereum-lisp-gas-oracle")
        #-sbcl nil))

(defun call-with-eth-rpc-gas-oracle-lock (oracle thunk)
  #+sbcl
  (sb-thread:with-mutex ((eth-rpc-gas-oracle-state-lock oracle))
    (funcall thunk))
  #-sbcl
  (progn oracle (funcall thunk)))

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

(defun eth-rpc-gas-oracle-head-equal-p (left right)
  (or (and (null left) (null right))
      (and left right (hash32= left right))))

(defun eth-rpc-gas-oracle-sample-history (store config head-number last-price)
  "Sample at least the normal lookback, extending sparse history to twice it."
  (let ((number head-number)
        (blocks 0)
        (samples '())
        (maximum-blocks (* 2 +eth-rpc-gas-oracle-block-count+)))
    (loop while (and (> number 0)
                     (< blocks maximum-blocks)
                     (or (< blocks +eth-rpc-gas-oracle-block-count+)
                         (< (length samples) maximum-blocks)))
          for block = (chain-store-block-by-number store number)
          for block-samples = (and block
                                   (eth-rpc-gas-oracle-block-samples
                                    block config))
          do (setf samples
                   (nconc samples (or block-samples (list last-price))))
             (incf blocks)
             (decf number))
    samples))

(defun engine-rpc-suggest-gas-tip-cap
    (store config &optional (oracle (make-eth-rpc-gas-oracle-state)))
  (call-with-eth-rpc-gas-oracle-lock
   oracle
   (lambda ()
     (let* ((head (chain-store-latest-block store))
            (head-hash (and head (block-hash head)))
            (last-head (eth-rpc-gas-oracle-state-last-head oracle))
            (last-price (eth-rpc-gas-oracle-state-last-price oracle)))
       (if (eth-rpc-gas-oracle-head-equal-p head-hash last-head)
           last-price
           (let* ((samples
                    (eth-rpc-gas-oracle-sample-history
                     store config (chain-store-head-number store) last-price))
                  (price
                    (min +eth-rpc-gas-oracle-maximum-tip+
                         (if samples
                             (eth-rpc-gas-oracle-percentile
                              samples +eth-rpc-gas-oracle-percentile+)
                             last-price))))
             (setf (eth-rpc-gas-oracle-state-last-head oracle) head-hash
                   (eth-rpc-gas-oracle-state-last-price oracle) price)
             price))))))

(defun engine-rpc-handle-eth-max-priority-fee-per-gas
    (params store config &optional oracle)
  (when params
    (block-validation-fail "eth_maxPriorityFeePerGas params must be empty"))
  (quantity-to-hex
   (engine-rpc-suggest-gas-tip-cap
    store config (or oracle (make-eth-rpc-gas-oracle-state)))))

(defun engine-rpc-handle-eth-gas-price (params store config &optional oracle)
  (when params
    (block-validation-fail "eth_gasPrice params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (if header
                       (or (block-header-base-fee-per-gas header) 0)
                       0)))
    (quantity-to-hex
     (+ base-fee
        (engine-rpc-suggest-gas-tip-cap
         store config (or oracle (make-eth-rpc-gas-oracle-state)))))))

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
