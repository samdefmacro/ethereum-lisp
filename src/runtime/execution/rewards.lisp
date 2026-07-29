(in-package #:ethereum-lisp.execution)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun apply-block-rewards-for-header (state header ommers rules)
  (declare (ignore state rules))
  (when ommers
    (error 'block-validation-error
           :message
           "Ommers are unsupported by this post-Merge client"))
  (unless (block-header-post-merge-p header)
    (error 'block-validation-error
           :message
           "Proof-of-work block rewards are unsupported"))
  0)
