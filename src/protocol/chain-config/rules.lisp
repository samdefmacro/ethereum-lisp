(in-package #:ethereum-lisp.chain-config)

(defun chain-rules-fork-level (rules)
  "Return the latest execution fork named by RULES.

Production rules (CHAIN-CONFIG-RULES) are cumulative, while focused tests and
RPC callers may name only the latest fork.  A single ordered level keeps both
forms equivalent for historical rule selection."
  (cond
    ((chain-rules-ubt-p rules) 19)
    ((chain-rules-amsterdam-p rules) 18)
    ((or (chain-rules-bpo5-p rules)
         (chain-rules-bpo4-p rules)
         (chain-rules-bpo3-p rules)
         (chain-rules-bpo2-p rules)
         (chain-rules-bpo1-p rules)) 17)
    ((chain-rules-osaka-p rules) 16)
    ((chain-rules-prague-p rules) 15)
    ((chain-rules-cancun-p rules) 14)
    ((chain-rules-shanghai-p rules) 13)
    ((chain-rules-london-p rules) 12)
    ((chain-rules-berlin-p rules) 11)
    ((chain-rules-istanbul-p rules) 10)
    ((chain-rules-petersburg-p rules) 9)
    ((chain-rules-constantinople-p rules) 8)
    ((chain-rules-byzantium-p rules) 7)
    ((chain-rules-eip158-p rules) 6)
    ((chain-rules-eip155-p rules) 5)
    ((chain-rules-eip150-p rules) 4)
    ((chain-rules-homestead-p rules) 3)
    (t 0)))

;;; The pre-Spurious-Dragon predicates below read RULES cumulatively: NIL rules
;;; are the latest fork, an explicit rule set with no flag is Frontier, and a
;;; later flag implies every earlier fork. Each asks its own flag first, so a
;;; production rule set never walks CHAIN-RULES-FORK-LEVEL.

(defun chain-rules-homestead-active-p (rules)
  "Whether RULES are Homestead or later."
  (or (null rules)
      (chain-rules-homestead-p rules)
      (>= (chain-rules-fork-level rules) 3)))

(defun chain-rules-eip155-active-p (rules)
  "Whether RULES are EIP-155 (replay-protected signatures) or later."
  (or (null rules)
      (chain-rules-eip155-p rules)
      (>= (chain-rules-fork-level rules) 5)))

(defun chain-rules-eip158-active-p (rules)
  "Whether RULES are Spurious Dragon (EIP-158/160/161/170) or later."
  (or (null rules)
      (chain-rules-eip158-p rules)
      (>= (chain-rules-fork-level rules) 6)))

(defun chain-rules-code-size-limited-p (rules)
  "Whether RULES refuse deployed code above CHAIN-RULES-CONTRACT-CODE-SIZE-LIMIT.
EIP-170 arrived with Spurious Dragon: go-ethereum v1.17.6
core/vm/common.go CheckMaxCodeSize checks nothing before IsEIP158."
  (chain-rules-eip158-active-p rules))

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

(defun chain-rules-max-blobs-per-transaction (rules)
  "Per-transaction blob limit. Osaka fixes it at 6 (EIP-7594); earlier forks
bound a transaction only by the per-block blob limit from the schedule."
  (cond
    ((null rules) +max-blobs-per-transaction-eip7594+)
    ((chain-rules-osaka-p rules) +max-blobs-per-transaction-eip7594+)
    ((chain-rules-blob-schedule-max-gas rules)
     (floor (chain-rules-blob-schedule-max-gas rules) +blob-gas-per-blob+))
    (t +max-blobs-per-block+)))

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
