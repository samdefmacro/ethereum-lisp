(in-package #:ethereum-lisp.core)

(defconstant +genesis-gas-limit+ 4712388)

(defconstant +genesis-difficulty+ 131072)

(defstruct (genesis-account
            (:constructor make-genesis-account
                (&key address (balance 0) (nonce 0)
                      (code (make-byte-vector 0)) storage)))
  address
  (balance 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (code (make-byte-vector 0) :type byte-vector)
  (storage nil :type list))

(defun ensure-uint256 (value label)
  (unless (uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)
