(in-package #:ethereum-lisp.consensus)

(defconstant +base-fee-elasticity-multiplier+ 2)
(defconstant +base-fee-change-denominator+ 8)
(defconstant +min-blob-gas-price+ 1)
(defconstant +min-blobs-per-transaction+ 1)
(defconstant +blob-base-cost+ 8192)
(defconstant +gas-limit-bound-divisor+ 1024)
(defconstant +minimum-gas-limit+ 5000)
