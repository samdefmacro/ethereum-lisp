(in-package #:ethereum-lisp.core)

(defconstant +eth-rpc-max-fee-history-block-count+ 1024)
(defconstant +eth-rpc-max-fee-history-reward-percentiles+ 100)

(defun eth-rpc-fee-history-block-count (params method)
  (let ((count (parse-genesis-quantity
                (engine-rpc-required-param params 0 "block count" method)
                "fee history block count"
                :required-p t)))
    (when (< count 1)
      (block-validation-fail
       "~A block count must be greater than zero" method))
    (min count +eth-rpc-max-fee-history-block-count+)))

(defun eth-rpc-fee-history-newest-block-number (params store method)
  (let ((value (engine-rpc-required-param params 1 "newest block" method)))
    (cond
      ((eth-rpc-head-block-tag-p value)
       (chain-store-block-tag-number store value))
      ((and (stringp value) (string= value "earliest")) 0)
      ((and (stringp value) (genesis-hex-quantity-string-p value))
       (parse-genesis-quantity value "newest block" :required-p t))
      (t
       (block-validation-fail
        "~A newest block must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

(defun eth-rpc-fee-history-reward-percentiles (params method)
  (let ((percentiles (engine-rpc-required-param
                      params 2 "reward percentiles" method)))
    (unless (json-array-p percentiles)
      (block-validation-fail
       "~A reward percentiles must be an array" method))
    (when (> (length (json-array-values percentiles))
             +eth-rpc-max-fee-history-reward-percentiles+)
      (block-validation-fail
       "~A reward percentiles exceed the query limit" method))
    (loop with previous = nil
          for percentile in (json-array-values percentiles)
          do (progn
               (unless (realp percentile)
                 (block-validation-fail
                  "~A reward percentiles must be numbers" method))
               (unless (<= 0 percentile 100)
                 (block-validation-fail
                  "~A reward percentiles must be between 0 and 100" method))
               (when (and previous (<= percentile previous))
                 (block-validation-fail
                  "~A reward percentiles must be strictly increasing" method))
               (setf previous percentile))
          collect percentile)))

(defun eth-rpc-fee-history-blocks (store newest-number block-count method)
  (let* ((effective-count (min block-count (1+ newest-number)))
         (oldest-number (- newest-number effective-count -1))
         (blocks '()))
    (loop for number from oldest-number to newest-number
          for block = (chain-store-block-by-number store number)
          do (unless block
               (block-validation-fail
                "~A requested block is not available" method))
             (push block blocks))
    (values oldest-number (nreverse blocks))))

(defun eth-rpc-fee-history-gas-used-ratio (header)
  (if (plusp (block-header-gas-limit header))
      (/ (block-header-gas-used header)
         (block-header-gas-limit header))
      0))

(defun eth-rpc-fee-history-base-fee (header)
  (quantity-to-hex (or (block-header-base-fee-per-gas header) 0)))

(defun eth-rpc-fee-history-next-base-fee (header config)
  (quantity-to-hex
   (if (chain-config-london-p config (1+ (block-header-number header)))
       (expected-base-fee-per-gas
        header
        :london-parent-p
        (not (null (block-header-base-fee-per-gas header))))
       (or (block-header-base-fee-per-gas header) 0))))

(defun eth-rpc-fee-history-blob-enabled-p (blocks)
  (some (lambda (block)
          (let ((header (block-header block)))
            (or (block-header-blob-gas-used header)
                (block-header-excess-blob-gas header))))
        blocks))

(defun eth-rpc-fee-history-blob-schedule (header config)
  (chain-config-blob-schedule
   config
   (block-header-number header)
   (block-header-timestamp header)))

(defun eth-rpc-fee-history-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-next-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (quantity-to-hex
         (blob-base-fee
          (expected-excess-blob-gas
           header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :update-fraction update-fraction)
          :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-blob-gas-used-ratio (header config)
  (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
      (eth-rpc-fee-history-blob-schedule header config)
    (declare (ignore target-blob-gas update-fraction))
    (if (plusp max-blob-gas)
        (/ (or (block-header-blob-gas-used header) 0) max-blob-gas)
        0)))

(defun eth-rpc-fee-history-zero-reward (percentiles)
  (loop repeat (length percentiles)
        collect (quantity-to-hex 0)))

(defun engine-rpc-handle-eth-fee-history (params store config)
  (let* ((method "eth_feeHistory")
         (block-count
           (progn
             (unless (= 3 (length params))
               (block-validation-fail
                "~A params must contain block count, newest block, and reward percentiles"
                method))
             (eth-rpc-fee-history-block-count params method)))
         (newest-number
           (eth-rpc-fee-history-newest-block-number params store method))
         (percentiles (eth-rpc-fee-history-reward-percentiles params method)))
    (multiple-value-bind (oldest-number blocks)
        (eth-rpc-fee-history-blocks store newest-number block-count method)
      (let* ((headers (mapcar #'block-header blocks))
             (newest-header (car (last headers)))
             (object
               (list
                (cons "oldestBlock" (quantity-to-hex oldest-number))
                (cons "baseFeePerGas"
                      (append
                       (mapcar #'eth-rpc-fee-history-base-fee headers)
                       (list
                        (eth-rpc-fee-history-next-base-fee
                         newest-header config))))
                (cons "gasUsedRatio"
                      (mapcar #'eth-rpc-fee-history-gas-used-ratio
                              headers)))))
        (when percentiles
          (setf object
                (append object
                        (list
                         (cons "reward"
                               (loop repeat (length blocks)
                                     collect
                                     (eth-rpc-fee-history-zero-reward
                                      percentiles)))))))
        (when (eth-rpc-fee-history-blob-enabled-p blocks)
          (setf object
                (append
                 object
                 (list
                  (cons "baseFeePerBlobGas"
                        (append
                         (mapcar
                          (lambda (header)
                            (eth-rpc-fee-history-blob-base-fee
                             header config))
                          headers)
                         (list
                          (eth-rpc-fee-history-next-blob-base-fee
                           newest-header config))))
                  (cons "blobGasUsedRatio"
                        (mapcar
                         (lambda (header)
                           (eth-rpc-fee-history-blob-gas-used-ratio
                            header config))
                         headers))))))
        object))))
