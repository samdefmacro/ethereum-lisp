(in-package #:ethereum-lisp.execution)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun block-reward-for-rules (rules)
  (cond
    ((chain-rules-constantinople-p rules) 2000000000000000000)
    ((chain-rules-byzantium-p rules) 3000000000000000000)
    (t 5000000000000000000)))

(defun apply-block-rewards-for-header (state header ommers rules)
  (if (block-header-post-merge-p header)
      (progn
        (when ommers
          (error 'block-validation-error
                 :message "Post-Merge blocks cannot contain ommers"))
        0)
      (let* ((base-reward (block-reward-for-rules rules))
             (beneficiary
               (or (block-header-beneficiary header) (zero-address)))
             (miner-reward
               (+ base-reward
                  (* (length ommers) (floor base-reward 32)))))
        (dolist (ommer ommers)
          (let ((ommer-reward
                  (floor
                   (* (+ (block-header-number ommer)
                         8
                         (- (block-header-number header)))
                      base-reward)
                   8)))
            (state-db-add-balance
             state
             (or (block-header-beneficiary ommer) (zero-address))
             ommer-reward)))
        (state-db-add-balance state beneficiary miner-reward)
        miner-reward)))
