(in-package #:ethereum-lisp.consensus)

;;;; Fee-market and blob-gas validation shared by block header paths.

(defun validate-block-base-fee (parent-header header &key (london-parent-p t))
  (unless (block-header-base-fee-per-gas header)
    (block-validation-fail "Header is missing base fee"))
  (let ((expected (expected-base-fee-per-gas
                   parent-header :london-parent-p london-parent-p)))
    (unless (= expected (block-header-base-fee-per-gas header))
      (block-validation-fail "Base fee mismatch"))
    t))

(defun validate-gas-limit-delta
    (parent-gas-limit header-gas-limit
     &key (bound-divisor +gas-limit-bound-divisor+)
          (minimum-gas-limit +minimum-gas-limit+))
  (let ((limit (floor parent-gas-limit bound-divisor))
        (diff (abs (- parent-gas-limit header-gas-limit))))
    (when (>= diff limit)
      (block-validation-fail "Gas limit changed too much"))
    (when (< header-gas-limit minimum-gas-limit)
      (block-validation-fail "Gas limit below minimum"))
    t))

(defun adjusted-parent-gas-limit-for-1559 (parent-header london-parent-p)
  (let ((parent-gas-limit (block-header-gas-limit parent-header)))
    (if london-parent-p
        parent-gas-limit
        (* parent-gas-limit +base-fee-elasticity-multiplier+))))

(defun validate-block-blob-gas-fields
    (header &key (blob-gas-enabled-p
                  (or (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header)))
                 (max-blob-gas (* +max-blobs-per-block+
                                  +blob-gas-per-blob+)))
  (cond
    (blob-gas-enabled-p
     (unless (block-header-blob-gas-used header)
       (block-validation-fail "Header is missing blob gas used"))
     (unless (block-header-excess-blob-gas header)
       (block-validation-fail "Header is missing excess blob gas"))
     (when (and max-blob-gas
                (> (block-header-blob-gas-used header) max-blob-gas))
       (block-validation-fail "Blob gas used exceeds maximum"))
     (unless (zerop (mod (block-header-blob-gas-used header)
                         +blob-gas-per-blob+))
       (block-validation-fail "Blob gas used is not a blob-sized multiple")))
    ((or (block-header-blob-gas-used header)
         (block-header-excess-blob-gas header))
     (block-validation-fail "Blob gas fields present before Cancun")))
  t)

(defun expected-excess-blob-gas
    (parent-header &key (target-blob-gas
                         (* +target-blobs-per-block+
                            +blob-gas-per-blob+))
                        (max-blob-gas
                         (* +max-blobs-per-block+
                            +blob-gas-per-blob+))
                        eip7918-p
                        (update-fraction
                         +blob-base-fee-update-fraction+))
  (let* ((parent-excess (or (block-header-excess-blob-gas parent-header) 0))
         (parent-used (or (block-header-blob-gas-used parent-header) 0))
         (parent-blob-gas (+ parent-excess parent-used)))
    (cond
      ((< parent-blob-gas target-blob-gas) 0)
      ((and eip7918-p
            (block-header-base-fee-per-gas parent-header)
            (> (* +blob-base-cost+
                  (block-header-base-fee-per-gas parent-header))
               (* +blob-gas-per-blob+
                  (blob-base-fee parent-excess
                                 :update-fraction update-fraction))))
       (+ parent-excess
          (floor (* parent-used (- max-blob-gas target-blob-gas))
                 max-blob-gas)))
      (t (- parent-blob-gas target-blob-gas)))))

(defun fake-exponential (factor numerator denominator)
  (let ((output 0)
        (accumulator (* factor denominator)))
    (loop for i from 1
          while (plusp accumulator)
          do (incf output accumulator)
             (setf accumulator
                   (floor (* accumulator numerator)
                          (* denominator i))))
    (floor output denominator)))

(defun blob-base-fee
    (excess-blob-gas &key (min-blob-gas-price +min-blob-gas-price+)
                          (update-fraction
                           +blob-base-fee-update-fraction+))
  (fake-exponential min-blob-gas-price
                    excess-blob-gas
                    update-fraction))

(defun block-header-blob-base-fee
    (header &key (update-fraction +blob-base-fee-update-fraction+))
  (unless (block-header-excess-blob-gas header)
    (block-validation-fail "Header is missing excess blob gas"))
  (blob-base-fee (block-header-excess-blob-gas header)
                 :update-fraction update-fraction))

(defun validate-block-excess-blob-gas
    (parent-header header &key (target-blob-gas
                                (* +target-blobs-per-block+
                                   +blob-gas-per-blob+))
                              (max-blob-gas
                               (* +max-blobs-per-block+
                                  +blob-gas-per-blob+))
                              eip7918-p
                              (update-fraction
                               +blob-base-fee-update-fraction+))
  (validate-block-blob-gas-fields header :max-blob-gas max-blob-gas)
  (let ((expected (expected-excess-blob-gas
                   parent-header
                   :target-blob-gas target-blob-gas
                   :max-blob-gas max-blob-gas
                   :eip7918-p eip7918-p
                   :update-fraction update-fraction)))
    (unless (= expected (block-header-excess-blob-gas header))
      (block-validation-fail "Excess blob gas mismatch"))
    t))
