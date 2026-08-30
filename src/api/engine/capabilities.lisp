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
  (loop for (method . properties) in +engine-rpc-method-registry+
        when (and (getf properties :advertised-p)
                  (engine-rpc-method-available-p method))
          collect method))

(defun engine-rpc-build-commit (&optional
                                  (revision
                                    (uiop:getenv
                                     "ETHEREUM_LISP_BUILD_REVISION")))
  "Return the EIP-7642 commit identifier embedded by the runtime build.

Docker supplies the full Git object id while saving the executable.  Source
and test loads deliberately retain the anonymous value instead of trusting a
short or malformed environment value."
  (if (and (stringp revision)
           (= 40 (length revision))
           (every (lambda (character)
                    (digit-char-p character 16))
                  revision))
      (format nil "0x~A" (string-downcase (subseq revision 0 8)))
      "0x00000000"))

(defparameter +engine-rpc-client-version+
  (list (cons "code" "CL")
        (cons "name" "ethereum-lisp")
        (cons "version" "0.1.0")
        (cons "commit" (engine-rpc-build-commit))))

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
