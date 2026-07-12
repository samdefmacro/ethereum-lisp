(in-package #:ethereum-lisp.chain-config)

(defun chain-rules-initcode-metering-p (rules)
  (or (null rules) (chain-rules-shanghai-p rules)))

(defun chain-rules-code-prefix-restricted-p (rules)
  (or (null rules) (chain-rules-london-p rules)))

(defun chain-rules-contract-code-size-limit (rules)
  (if (and rules (chain-rules-amsterdam-p rules))
      +amsterdam-max-contract-code-size+
      +max-contract-code-size+))

(defun chain-rules-contract-initcode-size-limit (rules)
  (* 2 (chain-rules-contract-code-size-limit rules)))

(defun chain-config-rules (config block-number timestamp)
  (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
      (chain-config-blob-schedule config block-number timestamp)
    (make-chain-rules
     :chain-id (chain-config-chain-id config)
     :homestead-p (chain-config-homestead-p config block-number)
     :eip150-p (chain-config-eip150-p config block-number)
     :eip155-p (chain-config-eip155-p config block-number)
     :eip158-p (chain-config-eip158-p config block-number)
     :byzantium-p (chain-config-byzantium-p config block-number)
     :constantinople-p (chain-config-constantinople-p config block-number)
     :petersburg-p (chain-config-petersburg-p config block-number)
     :istanbul-p (chain-config-istanbul-p config block-number)
     :berlin-p (chain-config-berlin-p config block-number)
     :london-p (chain-config-london-p config block-number)
     :shanghai-p (chain-config-shanghai-p config block-number timestamp)
     :cancun-p (chain-config-cancun-p config block-number timestamp)
     :prague-p (chain-config-prague-p config block-number timestamp)
     :osaka-p (chain-config-osaka-p config block-number timestamp)
     :bpo1-p (chain-config-bpo1-p config block-number timestamp)
     :bpo2-p (chain-config-bpo2-p config block-number timestamp)
     :bpo3-p (chain-config-bpo3-p config block-number timestamp)
     :bpo4-p (chain-config-bpo4-p config block-number timestamp)
     :bpo5-p (chain-config-bpo5-p config block-number timestamp)
     :amsterdam-p (chain-config-amsterdam-p config block-number timestamp)
     :ubt-p (chain-config-ubt-p config block-number timestamp)
     :blob-schedule-target-gas target-blob-gas
     :blob-schedule-max-gas max-blob-gas
     :blob-schedule-update-fraction update-fraction)))
