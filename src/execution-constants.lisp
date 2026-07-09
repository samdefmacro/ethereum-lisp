(in-package #:ethereum-lisp.execution)

(defconstant +create-data-gas+ 200)

(defconstant +max-contract-code-size+ 24576)

(defconstant +max-initcode-size+ (* 2 +max-contract-code-size+))

(defconstant +amsterdam-max-contract-code-size+ 32768)

(defconstant +amsterdam-max-initcode-size+
  (* 2 +amsterdam-max-contract-code-size+))

(defconstant +max-account-nonce+ (1- (ash 1 64)))

(defconstant +max-transaction-gas-limit+ (1- (ash 1 64)))

(defconstant +refund-quotient-eip3529+ 5)

(defconstant +set-code-existing-account-refund+ 12500)

(defconstant +frontier-block-reward+ 5000000000000000000)

(defconstant +byzantium-block-reward+ 3000000000000000000)

(defconstant +constantinople-block-reward+ 2000000000000000000)
