(in-package #:ethereum-lisp.core)

;;;; Public JSON-RPC call simulation and eth_call response handling.

(defun eth-rpc-simulate-call-object
    (object block store config method &key gas-limit)
  (multiple-value-bind (sender tx)
      (eth-rpc-call-object-transaction
       object (block-header block) method config
       :gas-limit-override gas-limit)
    (handler-case
        (ethereum-lisp.execution:execute-message-call
         (ethereum-lisp.execution:chain-store-state-db
          store (block-hash block))
         sender
         tx
         :base-fee (or (block-header-base-fee-per-gas
                        (block-header block))
                       0)
         :chain-id (if config (chain-config-chain-id config) 0)
         :chain-config config
         :coinbase (or (block-header-beneficiary (block-header block))
                       (zero-address))
         :timestamp (block-header-timestamp (block-header block))
         :block-number (block-header-number (block-header block))
         :prev-randao (or (block-header-mix-hash (block-header block))
                          (zero-hash32))
         :difficulty (block-header-difficulty (block-header block))
         :random-p t
         :context-gas-limit (block-header-gas-limit (block-header block)))
      (ethereum-lisp.state:transaction-validation-error ()
        (block-validation-fail
         "~A transaction is invalid" method)))))

(defun engine-rpc-handle-eth-call (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_call params must contain call object and optional block id"))
  (let* ((block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_call")))
    (multiple-value-bind (status return-data gas-used)
        (eth-rpc-simulate-call-object
         (first params) block store config "eth_call")
      (declare (ignore gas-used))
      (unless (or (eth-rpc-call-status-success-p status)
                  (eq status :reverted))
        (block-validation-fail "eth_call execution failed"))
      (bytes-to-hex return-data))))
