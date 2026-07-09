(in-package #:ethereum-lisp.core)

(defun fork-block-active-p (fork-block block-number)
  (and fork-block block-number (>= block-number fork-block)))

(defun fork-time-active-p (fork-time timestamp)
  (and fork-time timestamp (>= timestamp fork-time)))

(defun chain-config-homestead-p (config block-number)
  (fork-block-active-p (chain-config-homestead-block config) block-number))

(defun chain-config-dao-fork-p (config block-number)
  (fork-block-active-p (chain-config-dao-fork-block config) block-number))

(defun chain-config-eip150-p (config block-number)
  (fork-block-active-p (chain-config-eip150-block config) block-number))

(defun chain-config-eip155-p (config block-number)
  (fork-block-active-p (chain-config-eip155-block config) block-number))

(defun chain-config-eip158-p (config block-number)
  (fork-block-active-p (chain-config-eip158-block config) block-number))

(defun chain-config-byzantium-p (config block-number)
  (fork-block-active-p (chain-config-byzantium-block config) block-number))

(defun chain-config-constantinople-p (config block-number)
  (fork-block-active-p (chain-config-constantinople-block config)
                       block-number))

(defun chain-config-petersburg-p (config block-number)
  (or (fork-block-active-p (chain-config-petersburg-block config)
                           block-number)
      (and (null (chain-config-petersburg-block config))
           (chain-config-constantinople-p config block-number))))

(defun chain-config-istanbul-p (config block-number)
  (fork-block-active-p (chain-config-istanbul-block config) block-number))

(defun chain-config-berlin-p (config block-number)
  (fork-block-active-p (chain-config-berlin-block config) block-number))

(defun chain-config-london-p (config block-number)
  (fork-block-active-p (chain-config-london-block config) block-number))

(defun chain-config-shanghai-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-shanghai-time config) timestamp)))

(defun chain-config-cancun-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-cancun-time config) timestamp)))

(defun chain-config-prague-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-prague-time config) timestamp)))

(defun chain-config-osaka-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-osaka-time config) timestamp)))

(defun chain-config-bpo1-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo1-time config) timestamp)))

(defun chain-config-bpo2-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo2-time config) timestamp)))

(defun chain-config-bpo3-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo3-time config) timestamp)))

(defun chain-config-bpo4-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo4-time config) timestamp)))

(defun chain-config-bpo5-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo5-time config) timestamp)))

(defun chain-config-amsterdam-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-amsterdam-time config) timestamp)))

(defun chain-config-ubt-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-ubt-time config) timestamp)))

(defun chain-config-ubt-genesis-p (config)
  (chain-config-enable-ubt-at-genesis-p config))

(defun chain-config-expanded-blob-schedule-p (config block-number timestamp)
  (or (chain-config-prague-p config block-number timestamp)
      (chain-config-osaka-p config block-number timestamp)
      (chain-config-bpo1-p config block-number timestamp)
      (chain-config-bpo2-p config block-number timestamp)
      (chain-config-bpo3-p config block-number timestamp)
      (chain-config-bpo4-p config block-number timestamp)))

(defun chain-rules-expanded-blob-schedule-p (rules)
  (or (chain-rules-prague-p rules)
      (chain-rules-osaka-p rules)
      (chain-rules-bpo1-p rules)
      (chain-rules-bpo2-p rules)
      (chain-rules-bpo3-p rules)
      (chain-rules-bpo4-p rules)))
