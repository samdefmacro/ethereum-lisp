(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-call-status-success-p (status)
  (member status '(:stopped :returned :selfdestructed :successful)))

(defun eth-rpc-call-object-gas-cap (object header method)
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (let* ((block-limit (or (and header (block-header-gas-limit header))
                          +genesis-gas-limit+))
         (requested
           (eth-rpc-call-object-quantity-field
            object "gas" :default block-limit)))
    (min requested block-limit)))

(defun eth-rpc-estimate-gas-success-p
    (object block store config gas-limit)
  (multiple-value-bind (status return-data gas-used)
      (eth-rpc-simulate-call-object
       object block store config "eth_estimateGas" :gas-limit gas-limit)
    (declare (ignore return-data gas-used))
    (eth-rpc-call-status-success-p status)))

(defun eth-rpc-call-intrinsic-gas (tx header config)
  (let ((rules (and config
                    header
                    (chain-config-rules config
                                        (block-header-number header)
                                        (block-header-timestamp header)))))
    (ethereum-lisp.execution:transaction-intrinsic-gas
     tx
     :eip3860-p (or (null rules) (chain-rules-shanghai-p rules)))))

(defun engine-rpc-handle-eth-estimate-gas (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_estimateGas params must contain call object and optional block id"))
  (let* ((object (first params))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_estimateGas")))
    (multiple-value-bind (sender tx)
        (eth-rpc-call-object-transaction
         object (block-header block) "eth_estimateGas" config)
      (declare (ignore sender))
      (let* ((intrinsic-gas
               (eth-rpc-call-intrinsic-gas
                tx (block-header block) config))
             (high
               (eth-rpc-call-object-gas-cap
                object (block-header block) "eth_estimateGas")))
        (when (> intrinsic-gas high)
          (block-validation-fail
           "eth_estimateGas intrinsic gas exceeds gas cap"))
        (unless (eth-rpc-estimate-gas-success-p
                 object block store config high)
          (block-validation-fail
           "eth_estimateGas execution reverted or exceeded gas cap"))
        (loop with low = intrinsic-gas
              while (< low high)
              for mid = (floor (+ low high) 2)
              do (if (eth-rpc-estimate-gas-success-p
                      object block store config mid)
                     (setf high mid)
                     (setf low (1+ mid)))
              finally (return (quantity-to-hex low)))))))
