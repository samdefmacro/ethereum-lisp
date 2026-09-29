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
  "Charge AMOUNT of regular gas, or return NIL when BUDGET cannot afford it.

This is EVM-GAS-BUDGET-CHARGE of a regular-only cost without the per-charge
cost object: with no state cost there is nothing to spill, so the charge is
affordable exactly when AMOUNT fits the regular dimension.  The interpreter
calls it once per instruction."
  (declare (type evm-gas-budget budget) (type (integer 0 *) amount))
  (when (<= amount (evm-gas-budget-regular budget))
    (decf (evm-gas-budget-regular budget) amount)
    (incf (evm-gas-budget-used-regular budget) amount)
    t))

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

;;; Amsterdam frame hand-off (EIP-8037), after go-ethereum v1.17.6
;;; core/vm/gascosts.go.  A parent pays the regular gas it forwards up front and
;;; hands the child its whole state reservoir; the child ends in one of three
;;; leftover forms, which the parent absorbs.

(defun evm-gas-budget-forward (budget regular)
  "Deduct REGULAR from BUDGET and return the child budget it funds: that
regular gas and BUDGET's whole state reservoir, which BUDGET gives up.
geth GasBudget.Forward."
  (decf (evm-gas-budget-regular budget) regular)
  (incf (evm-gas-budget-used-regular budget) regular)
  (prog1 (make-evm-gas-budget :regular regular
                              :state (evm-gas-budget-state budget))
    (setf (evm-gas-budget-state budget) 0)))

(defun evm-gas-budget-frame-reservoir (budget)
  "The state reservoir BUDGET's frame started with: every state charge the
frame made is refilled, the part it borrowed from regular gas excluded."
  (max 0 (- (+ (evm-gas-budget-state budget)
               (evm-gas-budget-used-state budget))
            (evm-gas-budget-spilled budget))))

(defun evm-gas-budget-exit-revert (budget)
  "The leftover a reverted frame hands back: its regular gas plus the regular
gas it lent to state charges, and its starting reservoir.  geth ExitRevert."
  (make-evm-gas-budget
   :regular (+ (evm-gas-budget-regular budget)
               (evm-gas-budget-spilled budget))
   :state (evm-gas-budget-frame-reservoir budget)
   :used-regular (evm-gas-budget-used-regular budget)))

(defun evm-gas-budget-exit-halt (budget)
  "The leftover an exceptionally halted frame hands back: no regular gas, and
its starting reservoir.  geth ExitHalt."
  (make-evm-gas-budget
   :regular 0
   :state (evm-gas-budget-frame-reservoir budget)
   :used-regular (+ (evm-gas-budget-used-regular budget)
                    (evm-gas-budget-regular budget)
                    (evm-gas-budget-spilled budget))))

(defun evm-gas-budget-absorb (budget child)
  "Merge CHILD's leftover into BUDGET.  State gas the child borrowed from its
regular gas is state gas, so it leaves BUDGET's regular usage.  geth Absorb."
  (decf (evm-gas-budget-used-regular budget)
        (+ (evm-gas-budget-regular child) (evm-gas-budget-spilled child)))
  (incf (evm-gas-budget-regular budget) (evm-gas-budget-regular child))
  (setf (evm-gas-budget-state budget) (evm-gas-budget-state child))
  (incf (evm-gas-budget-used-state budget) (evm-gas-budget-used-state child))
  (incf (evm-gas-budget-spilled budget) (evm-gas-budget-spilled child))
  budget)

(defun evm-gas-budget-drain-regular (budget)
  "Burn BUDGET's remaining regular gas.  geth DrainRegular."
  (incf (evm-gas-budget-used-regular budget) (evm-gas-budget-regular budget))
  (setf (evm-gas-budget-regular budget) 0)
  budget)

(defun remaining-gas (gas-limit gas-used)
  (if gas-limit
      (max 0 (- gas-limit gas-used))
      0))

(defun all-but-one-64th (gas)
  (- gas (floor gas 64)))

(defun child-call-gas-limit
    (requested gas-limit gas-used &key (stipend 0) (eip150-p t))
  (+ stipend
     (if gas-limit
         (let ((available (remaining-gas gas-limit gas-used)))
           (if eip150-p
               (min requested (all-but-one-64th available))
               (progn
                 (when (> requested available)
                   (fail "CALL gas exceeds available gas before EIP-150"))
                 requested)))
         requested)))

(defun child-create-gas-limit (gas-limit gas-used)
  (and gas-limit
       (all-but-one-64th (remaining-gas gas-limit gas-used))))

(defun child-call-regular-gas-limit (requested regular-left &key (stipend 0))
  (+ stipend (min requested (all-but-one-64th regular-left))))

(defun child-create-regular-gas-limit (regular-left &key (eip150-p t))
  (if eip150-p
      (all-but-one-64th regular-left)
      regular-left))
