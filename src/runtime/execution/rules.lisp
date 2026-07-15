(in-package #:ethereum-lisp.execution)

(defun execution-chain-rules (chain-rules chain-config block-number timestamp)
  (or chain-rules
      (when chain-config
        (chain-config-rules chain-config block-number timestamp))))

(defun execution-blob-base-fee-update-fraction
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if effective-chain-rules
        (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
            (chain-rules-blob-schedule effective-chain-rules)
          (declare (ignore target-blob-gas max-blob-gas))
          update-fraction)
        +blob-base-fee-update-fraction+)))

(defun execution-max-blob-gas
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if effective-chain-rules
        (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
            (chain-rules-blob-schedule effective-chain-rules)
          (declare (ignore target-blob-gas update-fraction))
          max-blob-gas)
        (* +max-blobs-per-block+ +blob-gas-per-blob+))))

(defun execution-block-access-list-max-code-size
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if (and effective-chain-rules
             (chain-rules-amsterdam-p effective-chain-rules))
        +block-access-list-amsterdam-max-code-size+
        +block-access-list-max-code-size+)))

(defun execution-block-blob-base-fee (header chain-rules chain-config)
  (if (block-header-excess-blob-gas header)
      (block-header-blob-base-fee
       header
       :update-fraction
       (execution-blob-base-fee-update-fraction
        chain-rules
        chain-config
        (block-header-number header)
        (block-header-timestamp header)))
      0))
