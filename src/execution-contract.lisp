(in-package #:ethereum-lisp.execution)

;;;; Shared execution limits, rewards, and validation condition.

(define-condition transaction-validation-error (error)
  ((message :initarg :message :reader transaction-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (transaction-validation-error-message condition)))))

(defconstant +transaction-gas+ 21000)
(defconstant +contract-creation-transaction-gas+ 53000)
(defconstant +initcode-word-gas+ 2)
(defconstant +set-code-authorization-intrinsic-gas+ 25000)

(defconstant +create-data-gas+ 200)
(defconstant +max-contract-code-size+
  ethereum-lisp.chain-config:+max-contract-code-size+)
(defconstant +max-initcode-size+ (* 2 +max-contract-code-size+))
(defconstant +amsterdam-max-contract-code-size+
  ethereum-lisp.chain-config:+amsterdam-max-contract-code-size+)
(defconstant +amsterdam-max-initcode-size+
  (* 2 +amsterdam-max-contract-code-size+))
(defconstant +max-account-nonce+ (1- (ash 1 64)))
(defconstant +max-transaction-gas-limit+ (1- (ash 1 64)))
(defconstant +refund-quotient-eip3529+ 5)
(defconstant +set-code-existing-account-refund+ 12500)
(defconstant +frontier-block-reward+ 5000000000000000000)
(defconstant +byzantium-block-reward+ 3000000000000000000)
(defconstant +constantinople-block-reward+ 2000000000000000000)
