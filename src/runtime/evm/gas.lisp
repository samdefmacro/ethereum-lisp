(in-package #:ethereum-lisp.evm.internal)

(defun evm-gas-budget-total-left (budget)
  (+ (evm-gas-budget-regular budget)
     (evm-gas-budget-state budget)))

(defun evm-gas-budget-total-used (budget)
  (+ (evm-gas-budget-used-regular budget)
     (evm-gas-budget-used-state budget)))

(defun evm-gas-budget-can-afford-p (budget costs)
  (let ((regular-after
          (- (evm-gas-budget-regular budget)
             (evm-gas-costs-regular costs))))
    (and (not (minusp regular-after))
         (<= (max 0
                  (- (evm-gas-costs-state costs)
                     (evm-gas-budget-state budget)))
             regular-after))))

(defun evm-gas-budget-charge (budget costs)
  "Charge COSTS atomically, spilling state gas into regular gas when needed."
  (unless (evm-gas-budget-can-afford-p budget costs)
    (return-from evm-gas-budget-charge nil))
  (let* ((regular-cost (evm-gas-costs-regular costs))
         (state-cost (evm-gas-costs-state costs))
         (state-left (evm-gas-budget-state budget))
         (spill (max 0 (- state-cost state-left))))
    (decf (evm-gas-budget-regular budget) (+ regular-cost spill))
    (setf (evm-gas-budget-state budget)
          (max 0 (- state-left state-cost)))
    (incf (evm-gas-budget-used-regular budget) regular-cost)
    (incf (evm-gas-budget-used-state budget) state-cost)
    (incf (evm-gas-budget-spilled budget) spill)
    t))

(defun evm-gas-budget-charge-regular (budget amount)
  (evm-gas-budget-charge
   budget (make-evm-gas-costs :regular amount)))

(defun evm-gas-budget-charge-state (budget amount)
  (evm-gas-budget-charge
   budget (make-evm-gas-costs :state amount)))

(defun evm-gas-budget-refill-state (budget amount)
  "Undo state gas in LIFO order: repay regular spill before the reservoir."
  (let ((repay (min amount (evm-gas-budget-spilled budget))))
    (incf (evm-gas-budget-regular budget) repay)
    (decf (evm-gas-budget-spilled budget) repay)
    (incf (evm-gas-budget-state budget) (- amount repay))
    (decf (evm-gas-budget-used-state budget) amount))
  budget)

(defun evm-gas-budget-refill-all-state (budget)
  (let ((amount (max 0 (evm-gas-budget-used-state budget))))
    (when (plusp amount)
      (evm-gas-budget-refill-state budget amount)))
  budget)

(defun remaining-gas (gas-limit gas-used)
  (if gas-limit
      (max 0 (- gas-limit gas-used))
      0))

(defun all-but-one-64th (gas)
  (- gas (floor gas 64)))

(defun child-call-gas-limit (requested gas-limit gas-used &key (stipend 0))
  (+ stipend
     (if gas-limit
         (min requested (all-but-one-64th (remaining-gas gas-limit gas-used)))
         requested)))

(defun child-create-gas-limit (gas-limit gas-used)
  (and gas-limit
       (all-but-one-64th (remaining-gas gas-limit gas-used))))

(defun child-call-regular-gas-limit (requested regular-left &key (stipend 0))
  (+ stipend (min requested (all-but-one-64th regular-left))))

(defun child-create-regular-gas-limit (regular-left)
  (all-but-one-64th regular-left))
