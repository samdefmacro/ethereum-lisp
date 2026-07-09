(in-package #:ethereum-lisp.core)

(defun engine-rpc-handle-eth-get-logs (params store)
  (let* ((method "eth_getLogs")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-filter-logs filter store method)))

(defun engine-rpc-handle-eth-new-filter (params store)
  (let* ((method "eth_newFilter")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-log-filter-addresses filter method)
    (eth-rpc-log-filter-topics filter method)
    (eth-rpc-log-filter-blocks filter store method)
    (quantity-to-hex
     (engine-payload-store-put-log-filter store filter))))

(defun engine-rpc-handle-eth-new-block-filter (params store)
  (when params
    (block-validation-fail "eth_newBlockFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-block-filter store)))

(defun engine-rpc-handle-eth-new-pending-transaction-filter (params store)
  (when params
    (block-validation-fail
     "eth_newPendingTransactionFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-pending-transaction-filter store)))

(defun eth-rpc-filter-id-param (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter id"
                           method))
  (engine-rpc-quantity-param params 0 "filter id" method))

(defun engine-rpc-handle-eth-get-filter-logs (params store)
  (let* ((method "eth_getFilterLogs")
         (id (eth-rpc-filter-id-param params method))
         (log-filter (engine-payload-store-log-filter store id)))
    (unless (typep log-filter 'engine-log-filter)
      (block-validation-fail "~A filter not found" method))
    (eth-rpc-filter-logs
     (engine-log-filter-criteria log-filter) store method)))

(defun engine-rpc-handle-eth-get-filter-changes (params store config)
  (let* ((method "eth_getFilterChanges")
         (id (eth-rpc-filter-id-param params method))
         (filter (engine-payload-store-log-filter store id)))
    (cond
      ((typep filter 'engine-log-filter)
       (engine-log-filter-changes filter store method))
      ((typep filter 'engine-block-filter)
       (engine-block-filter-changes filter store))
      ((typep filter 'engine-pending-transaction-filter)
       (engine-pending-transaction-filter-changes
        filter store (chain-config-chain-id config)))
      (t
       (block-validation-fail "~A filter not found" method)))))

(defun engine-rpc-handle-eth-uninstall-filter (params store)
  (let* ((method "eth_uninstallFilter")
         (id (eth-rpc-filter-id-param params method)))
    (if (engine-payload-store-uninstall-log-filter store id)
        t
        :false)))
