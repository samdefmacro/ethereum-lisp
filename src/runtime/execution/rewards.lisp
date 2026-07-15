(in-package #:ethereum-lisp.execution)

(defun block-reward-for-rules (rules)
  (cond
    ((and rules (chain-rules-constantinople-p rules))
     +constantinople-block-reward+)
    ((and rules (chain-rules-byzantium-p rules))
     +byzantium-block-reward+)
    (t +frontier-block-reward+)))

(defun apply-block-beneficiary-reward (state beneficiary rules
                                       &key (ommer-count 0))
  (let* ((base-reward (block-reward-for-rules rules))
         (reward (+ base-reward
                    (* ommer-count (floor base-reward 32)))))
    (state-db-add-balance state beneficiary reward)
    reward))

(defun ommer-block-reward (base-reward header ommer)
  (floor (* (+ (block-header-number ommer) 8
               (- (block-header-number header)))
            base-reward)
         8))

(defun apply-block-ommer-rewards (state header ommers rules)
  (let ((base-reward (block-reward-for-rules rules)))
    (dolist (ommer ommers)
      (state-db-add-balance state
                            (or (block-header-beneficiary ommer) (zero-address))
                            (ommer-block-reward base-reward header ommer)))))

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun apply-block-rewards-for-header (state header ommers rules)
  (unless (block-header-post-merge-p header)
    (apply-block-beneficiary-reward
     state
     (or (block-header-beneficiary header) (zero-address))
     rules
     :ommer-count (length ommers))
    (apply-block-ommer-rewards state header ommers rules)))
