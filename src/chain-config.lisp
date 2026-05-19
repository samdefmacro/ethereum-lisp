(in-package #:ethereum-lisp.core)

(defstruct (blob-schedule-entry
            (:constructor make-blob-schedule-entry
                (&key timestamp target-blobs max-blobs update-fraction)))
  timestamp
  target-blobs
  max-blobs
  update-fraction)

(defstruct (chain-config (:constructor make-chain-config
                             (&key (chain-id 1)
                                   homestead-block
                                   dao-fork-block
                                   dao-fork-support
                                   eip150-block
                                   eip155-block
                                   eip158-block
                                   byzantium-block
                                   constantinople-block
                                   petersburg-block
                                   istanbul-block
                                   muir-glacier-block
                                   berlin-block
                                   london-block
                                   arrow-glacier-block
                                   gray-glacier-block
                                   shanghai-time
                                   cancun-time
                                   prague-time
                                   osaka-time
                                   bpo1-time
                                   bpo2-time
                                   bpo3-time
                                   bpo4-time
                                   bpo5-time
                                   amsterdam-time
                                   ubt-time
                                   enable-ubt-at-genesis-p
                                   terminal-total-difficulty
                                   terminal-total-difficulty-passed
                                   merge-netsplit-block
                                   deposit-contract-address
                                   custom-blob-schedule)))
  (chain-id 1 :type (integer 0 *))
  homestead-block
  dao-fork-block
  dao-fork-support
  eip150-block
  eip155-block
  eip158-block
  byzantium-block
  constantinople-block
  petersburg-block
  istanbul-block
  muir-glacier-block
  berlin-block
  london-block
  arrow-glacier-block
  gray-glacier-block
  shanghai-time
  cancun-time
  prague-time
  osaka-time
  bpo1-time
  bpo2-time
  bpo3-time
  bpo4-time
  bpo5-time
  amsterdam-time
  ubt-time
  enable-ubt-at-genesis-p
  terminal-total-difficulty
  terminal-total-difficulty-passed
  merge-netsplit-block
  deposit-contract-address
  custom-blob-schedule)

(defstruct (chain-rules (:constructor make-chain-rules
                            (&key (chain-id 1)
                                  homestead-p
                                  eip150-p
                                  eip155-p
                                  eip158-p
                                  byzantium-p
                                  constantinople-p
                                  petersburg-p
                                  istanbul-p
                                  berlin-p
                                  london-p
                                  shanghai-p
                                  cancun-p
                                  prague-p
                                  osaka-p
                                  bpo1-p
                                  bpo2-p
                                  bpo3-p
                                  bpo4-p
                                  bpo5-p
                                  amsterdam-p
                                  ubt-p
                                  blob-schedule-target-gas
                                  blob-schedule-max-gas
                                  blob-schedule-update-fraction)))
  (chain-id 1 :type (integer 0 *))
  homestead-p
  eip150-p
  eip155-p
  eip158-p
  byzantium-p
  constantinople-p
  petersburg-p
  istanbul-p
  berlin-p
  london-p
  shanghai-p
  cancun-p
  prague-p
  osaka-p
  bpo1-p
  bpo2-p
  bpo3-p
  bpo4-p
  bpo5-p
  amsterdam-p
  ubt-p
  blob-schedule-target-gas
  blob-schedule-max-gas
  blob-schedule-update-fraction)

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
