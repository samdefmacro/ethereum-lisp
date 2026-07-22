(in-package #:ethereum-lisp.chain-config)

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

(defun chain-config-sorted-fork-points (values)
  "Return VALUES sorted ascending with nils, zeros, and duplicates removed.

Forks that share an activation point (Constantinople and Petersburg on mainnet,
or the several Spurious Dragon EIPs) collapse to a single fold input, and a
fork at block 0 belongs to the genesis ruleset rather than a transition."
  (sort (remove-duplicates
         (remove-if (lambda (v) (or (null v) (zerop v))) values))
        #'<))

(defun chain-config-block-fork-schedule (config)
  "Return the ascending, de-duplicated block numbers at which CONFIG's
block-number forks activate. This is the block-height half of the EIP-2124
fork-id fold, in canonical order and dropping unset forks and the genesis."
  (chain-config-sorted-fork-points
   (list (chain-config-homestead-block config)
         (chain-config-dao-fork-block config)
         (chain-config-eip150-block config)
         (chain-config-eip155-block config)
         (chain-config-eip158-block config)
         (chain-config-byzantium-block config)
         (chain-config-constantinople-block config)
         (chain-config-petersburg-block config)
         (chain-config-istanbul-block config)
         (chain-config-muir-glacier-block config)
         (chain-config-berlin-block config)
         (chain-config-london-block config)
         (chain-config-arrow-glacier-block config)
         (chain-config-gray-glacier-block config))))

(defun chain-config-time-fork-schedule (config &optional (genesis-timestamp 0))
  "Return the ascending, de-duplicated timestamps at which CONFIG's time-based
forks activate, ordered after all block forks in the EIP-2124 fold.

A fork whose timestamp equals GENESIS-TIMESTAMP is part of the genesis ruleset,
not a transition, so it is dropped."
  (let ((points (chain-config-sorted-fork-points
                 (list (chain-config-shanghai-time config)
                       (chain-config-cancun-time config)
                       (chain-config-prague-time config)
                       (chain-config-osaka-time config)
                       (chain-config-bpo1-time config)
                       (chain-config-bpo2-time config)
                       (chain-config-bpo3-time config)
                       (chain-config-bpo4-time config)
                       (chain-config-bpo5-time config)
                       (chain-config-amsterdam-time config)
                       (chain-config-ubt-time config)))))
    (if (and points (= (first points) genesis-timestamp))
        (rest points)
        points)))

(defun chain-config-expanded-blob-schedule-p (config block-number timestamp)
  (or (chain-config-prague-p config block-number timestamp)
      (chain-config-osaka-p config block-number timestamp)
      (chain-config-bpo1-p config block-number timestamp)
      (chain-config-bpo2-p config block-number timestamp)
      (chain-config-bpo3-p config block-number timestamp)
      (chain-config-bpo4-p config block-number timestamp)
      (chain-config-bpo5-p config block-number timestamp)))

(defun chain-rules-expanded-blob-schedule-p (rules)
  (or (chain-rules-prague-p rules)
      (chain-rules-osaka-p rules)
      (chain-rules-bpo1-p rules)
      (chain-rules-bpo2-p rules)
      (chain-rules-bpo3-p rules)
      (chain-rules-bpo4-p rules)
      (chain-rules-bpo5-p rules)))
