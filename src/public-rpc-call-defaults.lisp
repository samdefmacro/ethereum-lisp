(in-package #:ethereum-lisp.core)

(defconstant +eth-rpc-default-call-gas-limit+ (1- (ash 1 64)))

(defun eth-rpc-call-object-default-gas-limit (header method)
  (if (or (string= method "eth_call")
          (string= method "eth_createAccessList"))
      +eth-rpc-default-call-gas-limit+
      (or (and header (block-header-gas-limit header))
          +genesis-gas-limit+)))
