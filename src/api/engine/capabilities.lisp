(in-package #:ethereum-lisp.engine-api)

(defparameter +engine-rpc-shanghai-capabilities+
  (loop for (method . properties) in +engine-rpc-method-registry+
        when (and (getf properties :advertised-p)
                  (not (getf properties :kzg-p)))
          collect method))

(defparameter +engine-rpc-capabilities+ +engine-rpc-shanghai-capabilities+)

(defparameter +engine-rpc-kzg-backed-capabilities+
  (engine-rpc-registered-methods :kzg-p t :advertised-p t))

(defun engine-rpc-capabilities ()
  (append (copy-list +engine-rpc-capabilities+)
          (when (kzg-proof-verification-available-p)
            (copy-list +engine-rpc-kzg-backed-capabilities+))))

(defparameter +engine-rpc-client-version+
  '(("code" . "CL")
    ("name" . "ethereum-lisp")
    ("version" . "0.1.0")
    ("commit" . "0x00000000")))

(defun engine-rpc-client-version ()
  (copy-tree +engine-rpc-client-version+))

(defun engine-rpc-transition-configuration-object (config)
  (unless (typep config 'chain-config)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 config must be chain-config"))
  (list (cons "terminalTotalDifficulty"
              (quantity-to-hex
               (or (chain-config-terminal-total-difficulty config) 0)))
        (cons "terminalBlockHash"
              (hash32-to-hex
               (or (chain-config-terminal-block-hash config)
                   (zero-hash32))))
        (cons "terminalBlockNumber"
              (quantity-to-hex
               (or (chain-config-terminal-block-number config) 0)))))
