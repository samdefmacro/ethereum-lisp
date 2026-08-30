(in-package #:ethereum-lisp.execution)

(defun execution-byzantium-p (rules)
  "Whether RULES use Byzantium-or-later receipt status semantics.

Production chain rules are cumulative.  Direct test and RPC configurations may
name only their latest active fork, so a later flag also implies Byzantium."
  (or (null rules)
      (chain-rules-byzantium-p rules)
      (chain-rules-constantinople-p rules)
      (chain-rules-petersburg-p rules)
      (chain-rules-istanbul-p rules)
      (chain-rules-berlin-p rules)
      (chain-rules-london-p rules)
      (chain-rules-shanghai-p rules)
      (chain-rules-cancun-p rules)
      (chain-rules-prague-p rules)
      (chain-rules-osaka-p rules)
      (chain-rules-bpo1-p rules)
      (chain-rules-bpo2-p rules)
      (chain-rules-bpo3-p rules)
      (chain-rules-bpo4-p rules)
      (chain-rules-bpo5-p rules)
      (chain-rules-amsterdam-p rules)
      (chain-rules-ubt-p rules)))

(defun execution-amsterdam-p (rules)
  (and rules (chain-rules-amsterdam-p rules)))

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
