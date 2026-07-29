(in-package #:ethereum-lisp.public-api)

(defun engine-rpc-handle-eth-get-logs (params store)
  (let* ((method "eth_getLogs")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-filter-logs filter store method)))

(defun engine-rpc-handle-eth-new-filter (params store &key now)
  (let* ((method "eth_newFilter")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-log-filter-addresses filter method)
    (eth-rpc-log-filter-topics filter method)
    (eth-rpc-log-filter-blocks filter store method)
    (let* ((block-hash-p
             (json-object-field-present-p filter "blockHash"))
           (from-block (json-object-field filter "fromBlock"))
           (start-at-head-p
             (and (not block-hash-p)
                  (or (null from-block)
                      (and (stringp from-block)
                           (or (string= from-block "latest")
                               (string= from-block "pending")))))))
      (engine-payload-store-put-log-filter
       store
       filter
       :block-hash-p block-hash-p
       :last-block-number
       (and start-at-head-p
            (engine-payload-store-head-number store))
       :now (or now (unix-time))))))

(defun engine-rpc-handle-eth-new-block-filter (params store &key now)
  (when params
    (block-validation-fail "eth_newBlockFilter params must be empty"))
  (engine-payload-store-put-block-filter
   store :now (or now (unix-time))))

(defun engine-rpc-handle-eth-new-pending-transaction-filter
    (params store &key now)
  (when params
    (block-validation-fail
     "eth_newPendingTransactionFilter params must be empty"))
  (engine-payload-store-put-pending-transaction-filter
   store :now (or now (unix-time))))

(defun eth-rpc-filter-id-param (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter id"
                           method))
  (let ((value (first params)))
    (unless (stringp value)
      (block-validation-fail "~A filter id must be a hex string" method))
    (let ((bytes
            (handler-case
                (hex-to-bytes value)
              (error ()
                (block-validation-fail
                 "~A filter id must be hex bytes" method)))))
      (unless (= 16 (length bytes))
        (block-validation-fail "~A filter id must be 16 bytes" method))
      (bytes-to-hex bytes))))

(defun engine-rpc-handle-eth-get-filter-logs (params store &key now)
  (let* ((method "eth_getFilterLogs")
         (id (eth-rpc-filter-id-param params method))
         (log-filter
           (engine-payload-store-log-filter
            store id :now (or now (unix-time)))))
    (unless (typep log-filter 'engine-log-filter)
      (block-validation-fail "~A filter not found" method))
    (eth-rpc-filter-logs
     (engine-log-filter-criteria log-filter) store method)))

(defun engine-rpc-handle-eth-get-filter-changes
    (params store config &key now)
  (let* ((method "eth_getFilterChanges")
         (id (eth-rpc-filter-id-param params method))
         (filter
           (engine-payload-store-log-filter
            store id :now (or now (unix-time)))))
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

(defun engine-rpc-handle-eth-uninstall-filter (params store &key now)
  (let* ((method "eth_uninstallFilter")
         (id (eth-rpc-filter-id-param params method)))
    (engine-payload-store-sweep-expired-filters
     store (or now (unix-time)))
    (if (engine-payload-store-uninstall-log-filter store id)
        t
        :false)))
