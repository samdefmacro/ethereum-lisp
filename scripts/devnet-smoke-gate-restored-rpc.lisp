(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-restored-public-rpc
    (node expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     &key pruned-state-rpc-tag
          (expected-head-block-number expected-block-number))
  #+sbcl
  (let* ((primary-balance-target (first balance-targets))
         (balance-address (getf primary-balance-target :address))
         (expected-balance (getf primary-balance-target :balance))
         (primary-transaction-check (first transaction-checks))
         (transaction-hash (getf primary-transaction-check :hash))
         (expected-raw-transaction (getf primary-transaction-check :raw))
         (transaction-count (length transaction-checks))
         (expected-transaction-count (quantity-to-hex transaction-count))
         (executable-code-p
           (devnet-smoke-gate-executable-code-p expected-code))
         (extra-balance-outputs
           (loop repeat (length (rest balance-targets))
                 collect (make-string-output-stream)))
         (extra-receipt-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-hash-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-number-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-hash-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-number-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (log-range-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-block-hash-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-create-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-logs-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-uninstall-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-missing-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (block-filter-create-output (make-string-output-stream))
         (block-filter-changes-output (make-string-output-stream))
         (block-filter-get-logs-output (make-string-output-stream))
         (block-filter-uninstall-output (make-string-output-stream))
         (block-filter-missing-output (make-string-output-stream))
         (block-number-output (make-string-output-stream))
        (balance-output (make-string-output-stream))
        (nonce-output (make-string-output-stream))
        (code-output (make-string-output-stream))
        (storage-output (make-string-output-stream))
        (proof-output (make-string-output-stream))
        (receipt-output (make-string-output-stream))
        (block-output (make-string-output-stream))
        (block-by-number-output (make-string-output-stream))
        (full-block-output (make-string-output-stream))
        (full-block-by-number-output (make-string-output-stream))
        (transaction-output (make-string-output-stream))
        (block-receipts-output (make-string-output-stream))
        (block-transaction-count-by-hash-output (make-string-output-stream))
        (block-transaction-count-by-number-output (make-string-output-stream))
        (canonical-hash-balance-output (make-string-output-stream))
        (canonical-hash-require-balance-output (make-string-output-stream))
        (raw-transaction-output (make-string-output-stream))
        (raw-transaction-by-hash-output (make-string-output-stream))
        (raw-transaction-by-number-output (make-string-output-stream))
        (transaction-by-hash-index-output (make-string-output-stream))
        (transaction-by-number-index-output (make-string-output-stream))
        (safe-block-output (make-string-output-stream))
        (finalized-block-output (make-string-output-stream))
        (call-output (make-string-output-stream))
        (failed-call-output
          (and executable-code-p (make-string-output-stream)))
        (estimate-gas-output (make-string-output-stream))
        (create-access-list-output (make-string-output-stream))
        (post-call-storage-output (make-string-output-stream))
        (pruned-state-probes
          (when pruned-state-rpc-tag
            (devnet-smoke-gate-state-error-probes
             154
             pruned-state-rpc-tag
             (devnet-smoke-gate-pruned-state-error-messages)
             balance-address
             sender-address
             code-address
             storage-address
             storage-key)))
         (expected-public-connections
           (+ 22
              (length extra-balance-outputs)
              (* 7 (length extra-receipt-outputs))
              (* 6 (length log-targets))
              5
              2
              4
              (if executable-code-p 1 0)
              (length pruned-state-probes)))
        (public-requests nil))
    (setf public-requests
          (remove
           nil
           (list
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 41)
                    (cons "method" "eth_blockNumber")
                    (cons "params" '())))
             block-number-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 42)
                    (cons "method" "eth_getBalance")
                    (cons "params"
                          (list (address-to-hex balance-address)
                                expected-block-number))))
             balance-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 43)
                   (cons "method" "eth_getTransactionCount")
                   (cons "params" (list (address-to-hex sender-address)
                                        expected-block-number))))
            nonce-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 44)
                   (cons "method" "eth_getCode")
                   (cons "params" (list (address-to-hex code-address)
                                        expected-block-number))))
            code-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 45)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            storage-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 46)
                   (cons "method" "eth_getProof")
                   (cons "params" (list (address-to-hex storage-address)
                                        (list storage-key)
                                        expected-block-number))))
            proof-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 47)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            receipt-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 48)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        :false))))
            block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 49)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number :false))))
            block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 165)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash) t))))
            full-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 166)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number t))))
           full-block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 50)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 167)
                   (cons "method" "eth_getRawTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            raw-transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 51)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-receipts-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 52)
                   (cons "method" "eth_getBlockTransactionCountByHash")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-transaction-count-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 53)
                   (cons "method" "eth_getBlockTransactionCountByNumber")
                   (cons "params" (list expected-block-number))))
            block-transaction-count-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 163)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash)))))))
            canonical-hash-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 164)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash))
                                (cons "requireCanonical" t))))))
            canonical-hash-require-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 54)
                   (cons "method" "eth_getRawTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            raw-transaction-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 55)
                   (cons "method" "eth_getRawTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            raw-transaction-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 56)
                   (cons "method" "eth_getTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            transaction-by-hash-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 57)
                   (cons "method" "eth_getTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            transaction-by-number-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 58)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "safe" :false))))
            safe-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 59)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "finalized" :false))))
            finalized-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 150)
                   (cons "method" "eth_call")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            call-output)
           (when executable-code-p
             (cons
              (json-encode
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 162)
                     (cons "method" "eth_call")
                     (cons "params"
                           (list
                            (list
                             (cons "from" (address-to-hex sender-address))
                             (cons "to" (address-to-hex code-address))
                             (cons "gas" (quantity-to-hex 22000))
                             (cons "gasPrice" "0x64")
                             (cons "data" "0x"))
                            expected-block-number))))
              failed-call-output))
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 151)
                   (cons "method" "eth_estimateGas")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            estimate-gas-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 152)
                   (cons "method" "eth_createAccessList")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            create-access-list-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 153)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            post-call-storage-output))))
    (when pruned-state-probes
      (setf public-requests
            (append
             public-requests
             (mapcar
              (lambda (probe)
                (cons (json-encode (getf probe :request))
                      (getf probe :output)))
              pruned-state-probes))))
    (setf public-requests
          (nconc
           public-requests
           (loop for target in (rest balance-targets)
                 for output in extra-balance-outputs
                 for id from 60
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex (getf target :address))
                                expected-block-number))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-receipt-outputs
                 for id from 70
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-outputs
                 for id from 80
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-outputs
                 for id from 170
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-hash-outputs
                 for index from 1
                 for id from 90
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-number-outputs
                 for index from 1
                 for id from 100
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-hash-index-outputs
                 for index from 1
                 for id from 110
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-number-index-outputs
                 for index from 1
                 for id from 120
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for target in log-targets
                 for output in log-range-outputs
                 for id from 130
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" expected-block-number)
                                 (cons "toBlock" expected-block-number)
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-block-hash-outputs
                 for id from 140
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash"
                                       (hash32-to-hex block-hash))
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-create-outputs
                 for id from 180
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_newFilter")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" expected-block-number)
                                 (cons "toBlock" expected-block-number)
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-logs-outputs
                 for filter-id from 1
                 for id from 190
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getFilterLogs")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-uninstall-outputs
                 for filter-id from 1
                 for id from 200
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_uninstallFilter")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-missing-outputs
                 for filter-id from 1
                 for id from 210
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getFilterLogs")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (let ((block-filter-id
                   (quantity-to-hex (1+ (length log-targets)))))
             (list
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 220)
                      (cons "method" "eth_newBlockFilter")
                      (cons "params" '())))
               block-filter-create-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 221)
                      (cons "method" "eth_getFilterChanges")
                      (cons "params" (list block-filter-id))))
               block-filter-changes-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 222)
                      (cons "method" "eth_getFilterLogs")
                      (cons "params" (list block-filter-id))))
               block-filter-get-logs-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 223)
                      (cons "method" "eth_uninstallFilter")
                      (cons "params" (list block-filter-id))))
               block-filter-uninstall-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 224)
                      (cons "method" "eth_getFilterChanges")
                      (cons "params" (list block-filter-id))))
               block-filter-missing-output)))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "restored-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "restored-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections expected-public-connections)))
      (let* ((block-number-response
               (get-output-stream-string block-number-output))
             (balance-response
               (get-output-stream-string balance-output))
             (nonce-response
               (get-output-stream-string nonce-output))
             (code-response
               (get-output-stream-string code-output))
             (storage-response
               (get-output-stream-string storage-output))
             (proof-response
               (get-output-stream-string proof-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (block-response
               (get-output-stream-string block-output))
             (block-by-number-response
               (get-output-stream-string block-by-number-output))
             (full-block-response
               (get-output-stream-string full-block-output))
             (full-block-by-number-response
               (get-output-stream-string full-block-by-number-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (raw-transaction-response
               (get-output-stream-string raw-transaction-output))
             (block-receipts-response
               (get-output-stream-string block-receipts-output))
             (block-transaction-count-by-hash-response
               (get-output-stream-string
                block-transaction-count-by-hash-output))
             (block-transaction-count-by-number-response
               (get-output-stream-string
                block-transaction-count-by-number-output))
             (canonical-hash-balance-response
               (get-output-stream-string canonical-hash-balance-output))
             (canonical-hash-require-balance-response
               (get-output-stream-string
                canonical-hash-require-balance-output))
             (raw-transaction-by-hash-response
               (get-output-stream-string raw-transaction-by-hash-output))
             (raw-transaction-by-number-response
               (get-output-stream-string raw-transaction-by-number-output))
             (transaction-by-hash-index-response
               (get-output-stream-string transaction-by-hash-index-output))
             (transaction-by-number-index-response
               (get-output-stream-string transaction-by-number-index-output))
             (safe-block-response
               (get-output-stream-string safe-block-output))
             (finalized-block-response
               (get-output-stream-string finalized-block-output))
             (call-response
               (get-output-stream-string call-output))
             (failed-call-response
               (and failed-call-output
                    (get-output-stream-string failed-call-output)))
             (estimate-gas-response
               (get-output-stream-string estimate-gas-output))
             (create-access-list-response
               (get-output-stream-string create-access-list-output))
             (post-call-storage-response
               (get-output-stream-string post-call-storage-output))
             (block-number-rpc
               (devnet-smoke-gate-rpc-body block-number-response))
             (balance-rpc
               (devnet-smoke-gate-rpc-body balance-response))
             (nonce-rpc
               (devnet-smoke-gate-rpc-body nonce-response))
             (code-rpc
               (devnet-smoke-gate-rpc-body code-response))
             (storage-rpc
               (devnet-smoke-gate-rpc-body storage-response))
             (proof-rpc
               (devnet-smoke-gate-rpc-body proof-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (block-rpc
               (devnet-smoke-gate-rpc-body block-response))
             (block-by-number-rpc
               (devnet-smoke-gate-rpc-body block-by-number-response))
             (full-block-rpc
               (devnet-smoke-gate-rpc-body full-block-response))
             (full-block-by-number-rpc
               (devnet-smoke-gate-rpc-body full-block-by-number-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (raw-transaction-rpc
               (devnet-smoke-gate-rpc-body raw-transaction-response))
             (block-receipts-rpc
               (devnet-smoke-gate-rpc-body block-receipts-response))
             (block-transaction-count-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-hash-response))
             (block-transaction-count-by-number-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-number-response))
             (canonical-hash-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-balance-response))
             (canonical-hash-require-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-require-balance-response))
             (raw-transaction-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-hash-response))
             (raw-transaction-by-number-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-number-response))
             (transaction-by-hash-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-hash-index-response))
             (transaction-by-number-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-number-index-response))
             (safe-block-rpc
               (devnet-smoke-gate-rpc-body safe-block-response))
             (finalized-block-rpc
               (devnet-smoke-gate-rpc-body finalized-block-response))
             (call-rpc
               (devnet-smoke-gate-rpc-body call-response))
             (failed-call-rpc
               (and failed-call-response
                    (devnet-smoke-gate-rpc-body failed-call-response)))
             (estimate-gas-rpc
               (devnet-smoke-gate-rpc-body estimate-gas-response))
             (create-access-list-rpc
               (devnet-smoke-gate-rpc-body create-access-list-response))
             (post-call-storage-rpc
               (devnet-smoke-gate-rpc-body post-call-storage-response))
             (pruned-state-error-messages
               (devnet-smoke-gate-verify-state-error-probes
                pruned-state-probes
                "pruned-state"))
             (actual-block-number
               (fixture-object-field block-number-rpc "result"))
             (actual-balance
               (fixture-object-field balance-rpc "result"))
             (actual-nonce
               (fixture-object-field nonce-rpc "result"))
             (actual-code
               (fixture-object-field code-rpc "result"))
             (actual-storage
               (fixture-object-field storage-rpc "result"))
             (actual-proof
               (fixture-object-field proof-rpc "result"))
             (actual-proof-storage-proofs
               (fixture-object-field actual-proof "storageProof"))
             (actual-proof-storage
               (first actual-proof-storage-proofs))
             (actual-receipt
               (fixture-object-field receipt-rpc "result"))
             (actual-receipt-transaction-hash
               (fixture-object-field actual-receipt "transactionHash"))
             (actual-receipt-block-number
               (fixture-object-field actual-receipt "blockNumber"))
             (actual-receipt-block-hash
               (fixture-object-field actual-receipt "blockHash"))
             (actual-receipt-logs
               (fixture-object-field actual-receipt "logs"))
             (actual-block
               (fixture-object-field block-rpc "result"))
             (actual-block-hash
               (fixture-object-field actual-block "hash"))
             (actual-block-by-hash-number
               (fixture-object-field actual-block "number"))
             (actual-block-transactions
               (fixture-object-field actual-block "transactions"))
             (actual-block-transaction-hash
               (first actual-block-transactions))
             (actual-block-by-number
               (fixture-object-field block-by-number-rpc "result"))
             (actual-block-by-number-hash
               (fixture-object-field actual-block-by-number "hash"))
             (actual-block-by-number-number
               (fixture-object-field actual-block-by-number "number"))
             (actual-block-by-number-transactions
               (fixture-object-field actual-block-by-number "transactions"))
             (actual-block-by-number-transaction-hash
               (first actual-block-by-number-transactions))
             (actual-full-block
               (fixture-object-field full-block-rpc "result"))
             (actual-full-block-transactions
               (fixture-object-field actual-full-block "transactions"))
             (actual-full-block-transaction
               (first actual-full-block-transactions))
             (actual-full-block-transaction-hash
               (fixture-object-field actual-full-block-transaction "hash"))
             (actual-full-block-transaction-index
               (fixture-object-field actual-full-block-transaction
                                     "transactionIndex"))
             (actual-full-block-transaction-block-hash
               (fixture-object-field actual-full-block-transaction
                                     "blockHash"))
             (actual-full-block-transaction-block-number
               (fixture-object-field actual-full-block-transaction
                                     "blockNumber"))
             (actual-full-block-by-number
               (fixture-object-field full-block-by-number-rpc "result"))
             (actual-full-block-by-number-transactions
               (fixture-object-field
                actual-full-block-by-number "transactions"))
             (actual-full-block-by-number-transaction
               (first actual-full-block-by-number-transactions))
             (actual-full-block-by-number-transaction-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "hash"))
             (actual-full-block-by-number-transaction-index
               (fixture-object-field
                actual-full-block-by-number-transaction "transactionIndex"))
             (actual-full-block-by-number-transaction-block-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "blockHash"))
             (actual-full-block-by-number-transaction-block-number
               (fixture-object-field
                actual-full-block-by-number-transaction "blockNumber"))
             (actual-transaction
               (fixture-object-field transaction-rpc "result"))
             (actual-transaction-hash
               (fixture-object-field actual-transaction "hash"))
             (actual-transaction-block-hash
               (fixture-object-field actual-transaction "blockHash"))
             (actual-transaction-block-number
               (fixture-object-field actual-transaction "blockNumber"))
             (actual-raw-transaction
               (fixture-object-field raw-transaction-rpc "result"))
             (actual-block-receipts
               (fixture-object-field block-receipts-rpc "result"))
             (actual-block-receipt
               (first actual-block-receipts))
             (actual-block-receipt-transaction-hash
               (fixture-object-field actual-block-receipt "transactionHash"))
             (actual-block-receipt-block-hash
               (fixture-object-field actual-block-receipt "blockHash"))
             (actual-block-receipt-block-number
               (fixture-object-field actual-block-receipt "blockNumber"))
             (actual-block-receipt-logs
               (fixture-object-field actual-block-receipt "logs"))
             (actual-block-transaction-count-by-hash
               (fixture-object-field
                block-transaction-count-by-hash-rpc "result"))
             (actual-block-transaction-count-by-number
               (fixture-object-field
                block-transaction-count-by-number-rpc "result"))
             (actual-canonical-hash-balance
               (fixture-object-field canonical-hash-balance-rpc "result"))
             (actual-canonical-hash-require-balance
               (fixture-object-field
                canonical-hash-require-balance-rpc "result"))
             (actual-raw-transaction-by-hash
               (fixture-object-field raw-transaction-by-hash-rpc "result"))
             (actual-raw-transaction-by-number
               (fixture-object-field raw-transaction-by-number-rpc "result"))
             (actual-transaction-by-hash-index
               (fixture-object-field transaction-by-hash-index-rpc "result"))
             (actual-transaction-by-number-index
               (fixture-object-field transaction-by-number-index-rpc "result"))
             (actual-transaction-by-hash-index-hash
               (fixture-object-field
                actual-transaction-by-hash-index "hash"))
             (actual-transaction-by-hash-index-block-hash
               (fixture-object-field
                actual-transaction-by-hash-index "blockHash"))
             (actual-transaction-by-hash-index-block-number
               (fixture-object-field
                actual-transaction-by-hash-index "blockNumber"))
             (actual-transaction-by-hash-index-transaction-index
               (fixture-object-field
                actual-transaction-by-hash-index "transactionIndex"))
             (actual-transaction-by-number-index-hash
               (fixture-object-field
                actual-transaction-by-number-index "hash"))
             (actual-transaction-by-number-index-block-hash
               (fixture-object-field
                actual-transaction-by-number-index "blockHash"))
             (actual-transaction-by-number-index-block-number
               (fixture-object-field
                actual-transaction-by-number-index "blockNumber"))
             (actual-transaction-by-number-index-transaction-index
               (fixture-object-field
                actual-transaction-by-number-index "transactionIndex"))
             (actual-safe-block
               (fixture-object-field safe-block-rpc "result"))
             (actual-safe-block-hash
               (fixture-object-field actual-safe-block "hash"))
             (actual-safe-block-number
               (fixture-object-field actual-safe-block "number"))
             (actual-finalized-block
               (fixture-object-field finalized-block-rpc "result"))
             (actual-finalized-block-hash
               (fixture-object-field actual-finalized-block "hash"))
             (actual-finalized-block-number
               (fixture-object-field actual-finalized-block "number"))
             (actual-call-result
               (fixture-object-field call-rpc "result"))
             (actual-failed-call-error
               (and failed-call-rpc
                    (fixture-object-field failed-call-rpc "error")))
             (actual-failed-call-error-message
               (and actual-failed-call-error
                    (fixture-object-field
                     actual-failed-call-error "message")))
             (actual-estimate-gas
               (fixture-object-field estimate-gas-rpc "result"))
             (actual-create-access-list
               (fixture-object-field create-access-list-rpc "result"))
             (actual-access-list
               (fixture-object-field actual-create-access-list "accessList"))
             (actual-access-list-gas-used
               (fixture-object-field actual-create-access-list "gasUsed"))
             (actual-access-list-entry
               (devnet-smoke-gate-access-list-entry
                actual-access-list storage-address))
             (actual-access-list-storage-keys
               (and actual-access-list-entry
                    (fixture-object-field actual-access-list-entry
                                          "storageKeys")))
             (actual-post-call-storage
               (fixture-object-field post-call-storage-rpc "result"))
             (actual-log-filter-log-count 0)
             (actual-log-filter-uninstall-count 0)
             (actual-log-filter-missing-error-codes nil)
             (actual-block-filter-id nil)
             (actual-block-filter-change-count nil)
             (actual-block-filter-get-logs-error-code nil)
             (actual-block-filter-uninstall-result nil)
             (actual-block-filter-missing-error-code nil)
             (expected-proof-code-hash
               (hash32-to-hex (keccak-256-hash (hex-to-bytes expected-code))))
             (expected-proof-storage-value
               (quantity-to-hex (hex-to-quantity expected-storage))))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Restored database verification should not use Engine RPC")
        (devnet-smoke-gate-require
         (= expected-public-connections (getf summary :public-connections))
         "Restored database verification expected ~S public RPC connections, got ~S"
         expected-public-connections
         (getf summary :public-connections))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-number-response))
         "Restored eth_blockNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status balance-response))
         "Restored eth_getBalance HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status nonce-response))
         "Restored eth_getTransactionCount HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status code-response))
         "Restored eth_getCode HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status storage-response))
         "Restored eth_getStorageAt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status proof-response))
         "Restored eth_getProof HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status receipt-response))
         "Restored eth_getTransactionReceipt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-response))
         "Restored eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-by-number-response))
         "Restored eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status full-block-response))
         "Restored full eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status full-block-by-number-response))
         "Restored full eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-response))
         "Restored eth_getTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-response))
         "Restored eth_getRawTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-receipts-response))
         "Restored eth_getBlockReceipts HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-hash-response))
         "Restored eth_getBlockTransactionCountByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-number-response))
         "Restored eth_getBlockTransactionCountByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status canonical-hash-balance-response))
         "Restored EIP-1898 eth_getBalance blockHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 canonical-hash-require-balance-response))
         "Restored EIP-1898 eth_getBalance requireCanonical HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-hash-response))
         "Restored eth_getRawTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-number-response))
         "Restored eth_getRawTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-hash-index-response))
         "Restored eth_getTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-number-index-response))
         "Restored eth_getTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status safe-block-response))
         "Restored eth_getBlockByNumber safe HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status finalized-block-response))
         "Restored eth_getBlockByNumber finalized HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status call-response))
         "Restored eth_call HTTP status mismatch")
        (when failed-call-response
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status failed-call-response))
           "Restored failing eth_call HTTP status mismatch"))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status estimate-gas-response))
         "Restored eth_estimateGas HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status create-access-list-response))
         "Restored eth_createAccessList HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status post-call-storage-response))
         "Restored post-eth_call eth_getStorageAt HTTP status mismatch")
        (devnet-smoke-gate-require
         (string= expected-head-block-number actual-block-number)
         "Restored eth_blockNumber mismatch: expected ~A got ~A"
         expected-head-block-number
         actual-block-number)
        (devnet-smoke-gate-require
         (string= expected-balance actual-balance)
         "Restored eth_getBalance mismatch: expected ~A got ~A"
         expected-balance
         actual-balance)
        (loop for target in (rest balance-targets)
              for output in extra-balance-outputs
              for response = (get-output-stream-string output)
              for rpc = (devnet-smoke-gate-rpc-body response)
              for actual-extra-balance =
                (fixture-object-field rpc "result")
              do
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Restored extra eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= (getf target :balance) actual-extra-balance)
                  "Restored extra eth_getBalance mismatch: expected ~A got ~A"
                  (getf target :balance)
                  actual-extra-balance))
        (devnet-smoke-gate-require
         (string= expected-sender-nonce actual-nonce)
         "Restored eth_getTransactionCount mismatch: expected ~A got ~A"
         expected-sender-nonce
         actual-nonce)
        (devnet-smoke-gate-require
         (string= expected-code actual-code)
         "Restored eth_getCode mismatch: expected ~A got ~A"
         expected-code
         actual-code)
        (devnet-smoke-gate-require
         (string= expected-storage actual-storage)
         "Restored eth_getStorageAt mismatch: expected ~A got ~A"
         expected-storage
         actual-storage)
        (devnet-smoke-gate-require
         actual-call-result
         "Restored eth_call returned error response: ~S"
         call-rpc)
        (devnet-smoke-gate-require
         (string= "0x" actual-call-result)
         "Restored eth_call result mismatch: expected empty return, got ~A"
         actual-call-result)
        (when executable-code-p
          (devnet-smoke-gate-require
           actual-failed-call-error
           "Restored failing eth_call did not return an error response: ~S"
           failed-call-rpc)
          (devnet-smoke-gate-require
           (string= "eth_call execution failed"
                    actual-failed-call-error-message)
           "Restored failing eth_call error mismatch: ~A"
           actual-failed-call-error-message))
        (devnet-smoke-gate-require
         (<= 21000 (hex-to-quantity actual-estimate-gas))
         "Restored eth_estimateGas must be at least intrinsic gas")
        (devnet-smoke-gate-require
         (stringp actual-access-list-gas-used)
         "Restored eth_createAccessList gasUsed must be a string")
        (when (devnet-smoke-gate-executable-code-p expected-code)
          (devnet-smoke-gate-require
           actual-access-list-entry
           "Restored eth_createAccessList missing storage account entry")
          (devnet-smoke-gate-require
           (member storage-key actual-access-list-storage-keys
                   :test #'string=)
           "Restored eth_createAccessList missing storage key"))
        (devnet-smoke-gate-require
         (string= expected-storage actual-post-call-storage)
         "Restored eth_call mutated retained storage: expected ~A got ~A"
         expected-storage
         actual-post-call-storage)
        (devnet-smoke-gate-require
         (string= (address-to-hex storage-address)
                  (fixture-object-field actual-proof "address"))
         "Restored eth_getProof address mismatch")
        (devnet-smoke-gate-require
         (string= expected-proof-code-hash
                  (fixture-object-field actual-proof "codeHash"))
         "Restored eth_getProof codeHash mismatch: expected ~A got ~A"
         expected-proof-code-hash
         (fixture-object-field actual-proof "codeHash"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof "accountProof"))
         "Restored eth_getProof accountProof must be a list")
        (devnet-smoke-gate-require
         (= 1 (length actual-proof-storage-proofs))
         "Restored eth_getProof expected 1 storage proof, got ~S"
         (length actual-proof-storage-proofs))
        (devnet-smoke-gate-require
         (string= storage-key (fixture-object-field actual-proof-storage "key"))
         "Restored eth_getProof storage key mismatch: expected ~A got ~A"
         storage-key
         (fixture-object-field actual-proof-storage "key"))
        (devnet-smoke-gate-require
         (string= expected-proof-storage-value
                  (fixture-object-field actual-proof-storage "value"))
         "Restored eth_getProof storage value mismatch: expected ~A got ~A"
         expected-proof-storage-value
         (fixture-object-field actual-proof-storage "value"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof-storage "proof"))
         "Restored eth_getProof storage proof must be a list")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-receipt-transaction-hash)
         "Restored eth_getTransactionReceipt hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-receipt-block-number)
         "Restored eth_getTransactionReceipt block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-receipt-block-hash)
         "Restored eth_getTransactionReceipt block hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-hash)
         "Restored eth_getBlockByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-hash-number)
         "Restored eth_getBlockByHash block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-transaction-hash)
         "Restored eth_getBlockByHash transaction list mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-transactions))
         "Restored eth_getBlockByHash transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-by-number-hash)
         "Restored eth_getBlockByNumber hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-number-number)
         "Restored eth_getBlockByNumber block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-by-number-transaction-hash)
         "Restored eth_getBlockByNumber transaction list mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-by-number-transactions))
         "Restored eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-full-block-transactions))
         "Restored full eth_getBlockByHash transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-transaction-hash)
         "Restored full eth_getBlockByHash transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-transaction-index)
         "Restored full eth_getBlockByHash transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-transaction-block-hash)
         "Restored full eth_getBlockByHash transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-transaction-block-number)
         "Restored full eth_getBlockByHash transaction block number mismatch")
        (devnet-smoke-gate-require
         (= transaction-count
            (length actual-full-block-by-number-transactions))
         "Restored full eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-by-number-transaction-hash)
         "Restored full eth_getBlockByNumber transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-by-number-transaction-index)
         "Restored full eth_getBlockByNumber transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-by-number-transaction-block-hash)
         "Restored full eth_getBlockByNumber transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-by-number-transaction-block-number)
         "Restored full eth_getBlockByNumber transaction block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash) actual-transaction-hash)
         "Restored eth_getTransactionByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-block-hash)
         "Restored eth_getTransactionByHash block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-transaction-block-number)
         "Restored eth_getTransactionByHash block number mismatch")
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction)
         "Restored eth_getRawTransactionByHash mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-receipts))
         "Restored eth_getBlockReceipts expected ~S receipts, got ~S"
         transaction-count
         (length actual-block-receipts))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-receipt-transaction-hash)
         "Restored eth_getBlockReceipts transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-block-receipt-block-hash)
         "Restored eth_getBlockReceipts block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-receipt-block-number)
         "Restored eth_getBlockReceipts block number mismatch")
        (when log-targets
          (let ((target (first log-targets)))
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-receipt-logs))
             "Restored eth_getTransactionReceipt log count mismatch")
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-block-receipt-logs))
             "Restored eth_getBlockReceipts log count mismatch")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getTransactionReceipt")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-block-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getBlockReceipts")))
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-hash)
         "Restored eth_getBlockTransactionCountByHash mismatch")
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-number)
         "Restored eth_getBlockTransactionCountByNumber mismatch")
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-balance)
         "Restored EIP-1898 eth_getBalance blockHash mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-balance)
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-require-balance)
         "Restored EIP-1898 eth_getBalance requireCanonical mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-require-balance)
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-hash)
         "Restored eth_getRawTransactionByBlockHashAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-number)
         "Restored eth_getRawTransactionByBlockNumberAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-hash-index-hash)
         "Restored eth_getTransactionByBlockHashAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-hash-index-block-hash)
         "Restored eth_getTransactionByBlockHashAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-hash-index-block-number)
         "Restored eth_getTransactionByBlockHashAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-hash-index-transaction-index)
         "Restored eth_getTransactionByBlockHashAndIndex index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-number-index-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-number-index-block-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-number-index-block-number)
         "Restored eth_getTransactionByBlockNumberAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-number-index-transaction-index)
         "Restored eth_getTransactionByBlockNumberAndIndex index mismatch")
        (loop for check in (rest transaction-checks)
              for index from 1
              for receipt-output in extra-receipt-outputs
              for transaction-output in extra-transaction-outputs
              for raw-output in extra-raw-transaction-outputs
              for raw-by-hash-output in extra-raw-transaction-by-hash-outputs
              for raw-by-number-output in extra-raw-transaction-by-number-outputs
              for tx-by-hash-index-output in extra-transaction-by-hash-index-outputs
              for tx-by-number-index-output in extra-transaction-by-number-index-outputs
              for expected-hash = (hash32-to-hex (getf check :hash))
              for expected-raw = (getf check :raw)
              for expected-index = (quantity-to-hex index)
              do
                 (let* ((receipt-response
                          (get-output-stream-string receipt-output))
                        (transaction-response
                          (get-output-stream-string transaction-output))
                        (raw-response
                          (get-output-stream-string raw-output))
                        (raw-by-hash-response
                          (get-output-stream-string raw-by-hash-output))
                        (raw-by-number-response
                          (get-output-stream-string raw-by-number-output))
                        (tx-by-hash-index-response
                          (get-output-stream-string tx-by-hash-index-output))
                        (tx-by-number-index-response
                          (get-output-stream-string
                           tx-by-number-index-output))
                        (receipt
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body receipt-response)
                           "result"))
                        (transaction
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            transaction-response)
                           "result"))
                        (tx-by-hash-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-hash-index-response)
                           "result"))
                        (tx-by-number-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-number-index-response)
                           "result")))
                   (dolist (response
                            (list receipt-response transaction-response
                                  raw-response raw-by-hash-response
                                  raw-by-number-response tx-by-hash-index-response
                                  tx-by-number-index-response))
                     (devnet-smoke-gate-require
                      (= 200 (devnet-cli-http-status response))
                      "Restored extra transaction RPC HTTP status mismatch"))
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field receipt
                                                   "transactionHash"))
                    "Restored extra receipt transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field receipt "blockNumber"))
                    "Restored extra receipt block number mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field receipt "blockHash"))
                    "Restored extra receipt block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field transaction "hash"))
                    "Restored extra eth_getTransactionByHash mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field transaction
                                                   "blockHash"))
                    "Restored extra eth_getTransactionByHash block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field transaction
                                                   "blockNumber"))
                    "Restored extra eth_getTransactionByHash block number mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-response)
                              "result"))
                    "Restored extra raw transaction by transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-hash-response)
                              "result"))
                    "Restored extra raw transaction by hash/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-number-response)
                              "result"))
                    "Restored extra raw transaction by number/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-hash-index "hash"))
                    "Restored extra tx by hash/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-hash-index
                                                   "transactionIndex"))
                    "Restored extra tx by hash/index index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-number-index "hash"))
                    "Restored extra tx by number/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-number-index
                                                   "transactionIndex"))
                    "Restored extra tx by number/index index mismatch")))
        (loop for target in log-targets
              for range-output in log-range-outputs
              for block-hash-output in log-block-hash-outputs
              do
                 (let* ((range-response
                          (get-output-stream-string range-output))
                        (block-hash-response
                          (get-output-stream-string block-hash-output))
                        (range-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body range-response)
                           "result"))
                        (block-hash-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body block-hash-response)
                           "result")))
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status range-response))
                    "Restored eth_getLogs range HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status block-hash-response))
                    "Restored eth_getLogs blockHash HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length range-logs))
                    "Restored eth_getLogs range log count mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length block-hash-logs))
                    "Restored eth_getLogs blockHash log count mismatch")
                   (devnet-smoke-gate-verify-rpc-log
                    (first range-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs range")
                   (devnet-smoke-gate-verify-rpc-log
                    (first block-hash-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs blockHash")))
        (loop for target in log-targets
              for create-output in log-filter-create-outputs
              for logs-output in log-filter-logs-outputs
              for uninstall-output in log-filter-uninstall-outputs
              for missing-output in log-filter-missing-outputs
              for filter-id from 1
              do
                 (let* ((create-response
                          (get-output-stream-string create-output))
                        (logs-response
                          (get-output-stream-string logs-output))
                        (uninstall-response
                          (get-output-stream-string uninstall-output))
                        (missing-response
                          (get-output-stream-string missing-output))
                        (create-rpc
                          (devnet-smoke-gate-rpc-body create-response))
                        (logs-rpc
                          (devnet-smoke-gate-rpc-body logs-response))
                        (uninstall-rpc
                          (devnet-smoke-gate-rpc-body
                           uninstall-response))
                        (missing-rpc
                          (devnet-smoke-gate-rpc-body missing-response))
                        (filter-logs
                          (fixture-object-field logs-rpc "result"))
                        (missing-error-code
                          (devnet-smoke-gate-error-code missing-rpc)))
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status create-response))
                    "Restored eth_newFilter HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status logs-response))
                    "Restored eth_getFilterLogs HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status uninstall-response))
                    "Restored eth_uninstallFilter HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status missing-response))
                    "Restored missing eth_getFilterLogs HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (string= (quantity-to-hex filter-id)
                             (fixture-object-field create-rpc "result"))
                    "Restored eth_newFilter id mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length filter-logs))
                    "Restored eth_getFilterLogs log count mismatch")
                   (devnet-smoke-gate-verify-rpc-log
                    (first filter-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getFilterLogs")
                   (devnet-smoke-gate-require
                    (member (fixture-object-field uninstall-rpc "result")
                            '(t :true))
                    "Restored eth_uninstallFilter result mismatch")
                   (devnet-smoke-gate-require
                    (= -32602 missing-error-code)
                    "Restored missing eth_getFilterLogs error code mismatch")
                   (incf actual-log-filter-log-count
                         (length filter-logs))
                   (incf actual-log-filter-uninstall-count)
                   (push missing-error-code
                         actual-log-filter-missing-error-codes)))
        (let* ((block-filter-create-response
                 (get-output-stream-string block-filter-create-output))
               (block-filter-changes-response
                 (get-output-stream-string block-filter-changes-output))
               (block-filter-get-logs-response
                 (get-output-stream-string block-filter-get-logs-output))
               (block-filter-uninstall-response
                 (get-output-stream-string block-filter-uninstall-output))
               (block-filter-missing-response
                 (get-output-stream-string block-filter-missing-output))
               (block-filter-create-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-create-response))
               (block-filter-changes-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-changes-response))
               (block-filter-get-logs-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-get-logs-response))
               (block-filter-uninstall-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-uninstall-response))
               (block-filter-missing-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-missing-response))
               (expected-block-filter-id
                 (quantity-to-hex (1+ (length log-targets))))
               (block-filter-changes
                 (fixture-object-field block-filter-changes-rpc "result")))
          (dolist (response
                   (list block-filter-create-response
                         block-filter-changes-response
                         block-filter-get-logs-response
                         block-filter-uninstall-response
                         block-filter-missing-response))
            (devnet-smoke-gate-require
             (= 200 (devnet-cli-http-status response))
             "Restored block filter HTTP status mismatch"))
          (setf actual-block-filter-id
                (fixture-object-field block-filter-create-rpc "result")
                actual-block-filter-change-count
                (length block-filter-changes)
                actual-block-filter-get-logs-error-code
                (devnet-smoke-gate-error-code block-filter-get-logs-rpc)
                actual-block-filter-uninstall-result
                (fixture-object-field block-filter-uninstall-rpc "result")
                actual-block-filter-missing-error-code
                (devnet-smoke-gate-error-code block-filter-missing-rpc))
          (devnet-smoke-gate-require
           (string= expected-block-filter-id actual-block-filter-id)
           "Restored eth_newBlockFilter id mismatch")
          (devnet-smoke-gate-require
           (zerop actual-block-filter-change-count)
           "Restored eth_getFilterChanges block filter initial count mismatch")
          (devnet-smoke-gate-require
           (= -32602 actual-block-filter-get-logs-error-code)
           "Restored eth_getFilterLogs block filter error code mismatch")
          (devnet-smoke-gate-require
           (member actual-block-filter-uninstall-result '(t :true))
           "Restored eth_uninstallFilter block filter result mismatch")
          (devnet-smoke-gate-require
           (= -32602 actual-block-filter-missing-error-code)
           "Restored missing eth_getFilterChanges block filter error code mismatch"))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-safe-block-hash)
                  actual-safe-block-hash)
         "Restored eth_getBlockByNumber safe hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-safe-block-number actual-safe-block-number)
         "Restored eth_getBlockByNumber safe number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-finalized-block-hash)
                  actual-finalized-block-hash)
         "Restored eth_getBlockByNumber finalized hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-finalized-block-number
                  actual-finalized-block-number)
         "Restored eth_getBlockByNumber finalized number mismatch")
        (list :block-number actual-block-number
              :balance actual-balance
              :nonce actual-nonce
              :code actual-code
              :storage actual-storage
              :proof-address (fixture-object-field actual-proof "address")
              :proof-code-hash
              (fixture-object-field actual-proof "codeHash")
              :proof-storage-key
              (fixture-object-field actual-proof-storage "key")
              :proof-storage-value
              (fixture-object-field actual-proof-storage "value")
              :proof-storage-count (length actual-proof-storage-proofs)
              :proof-account-proof-count
              (length (fixture-object-field actual-proof "accountProof"))
              :receipt-transaction-hash actual-receipt-transaction-hash
              :receipt-block-number actual-receipt-block-number
              :block-hash actual-block-hash
              :block-by-hash-number actual-block-by-hash-number
              :block-transaction-hash actual-block-transaction-hash
              :block-by-number-hash actual-block-by-number-hash
              :block-by-number-number actual-block-by-number-number
              :block-by-number-transaction-hash
              actual-block-by-number-transaction-hash
              :full-block-transaction-count
              (length actual-full-block-transactions)
              :full-block-transaction-hash
              actual-full-block-transaction-hash
              :full-block-transaction-index
              actual-full-block-transaction-index
              :full-block-by-number-transaction-count
              (length actual-full-block-by-number-transactions)
              :full-block-by-number-transaction-hash
              actual-full-block-by-number-transaction-hash
              :full-block-by-number-transaction-index
              actual-full-block-by-number-transaction-index
              :transaction-hash actual-transaction-hash
              :transaction-block-hash actual-transaction-block-hash
              :transaction-block-number actual-transaction-block-number
              :raw-transaction actual-raw-transaction
              :block-receipts-count (length actual-block-receipts)
              :block-receipt-transaction-hash
              actual-block-receipt-transaction-hash
              :block-receipt-block-hash actual-block-receipt-block-hash
              :block-receipt-block-number actual-block-receipt-block-number
              :block-transaction-count-by-hash
              actual-block-transaction-count-by-hash
              :block-transaction-count-by-number
              actual-block-transaction-count-by-number
              :canonical-hash-balance actual-canonical-hash-balance
              :canonical-hash-require-balance
              actual-canonical-hash-require-balance
              :transaction-count transaction-count
              :balance-count (length balance-targets)
              :log-count (reduce #'+ log-targets
                                  :key (lambda (target)
                                         (getf target :count))
                                  :initial-value 0)
              :log-filter-count actual-log-filter-uninstall-count
              :log-filter-log-count actual-log-filter-log-count
              :log-filter-uninstall-count
              actual-log-filter-uninstall-count
              :log-filter-missing-error-codes
              (nreverse actual-log-filter-missing-error-codes)
              :block-filter-id actual-block-filter-id
              :block-filter-change-count actual-block-filter-change-count
              :block-filter-get-logs-error-code
              actual-block-filter-get-logs-error-code
              :block-filter-uninstall-result
              actual-block-filter-uninstall-result
              :block-filter-missing-error-code
              actual-block-filter-missing-error-code
              :raw-transaction-by-hash actual-raw-transaction-by-hash
              :raw-transaction-by-number actual-raw-transaction-by-number
              :transaction-by-hash-index-hash
              actual-transaction-by-hash-index-hash
              :transaction-by-hash-index-block-hash
              actual-transaction-by-hash-index-block-hash
              :transaction-by-hash-index-block-number
              actual-transaction-by-hash-index-block-number
              :transaction-by-hash-index-transaction-index
              actual-transaction-by-hash-index-transaction-index
              :transaction-by-number-index-hash
              actual-transaction-by-number-index-hash
              :transaction-by-number-index-block-hash
              actual-transaction-by-number-index-block-hash
              :transaction-by-number-index-block-number
              actual-transaction-by-number-index-block-number
              :transaction-by-number-index-transaction-index
              actual-transaction-by-number-index-transaction-index
              :safe-block-hash actual-safe-block-hash
              :safe-block-number actual-safe-block-number
              :finalized-block-hash actual-finalized-block-hash
              :finalized-block-number actual-finalized-block-number
              :call-result actual-call-result
              :failed-call-error-message
              (or actual-failed-call-error-message :false)
              :estimate-gas actual-estimate-gas
              :access-list-count (length actual-access-list)
              :access-list-gas-used actual-access-list-gas-used
              :post-call-storage actual-post-call-storage
              :simulation-count (if executable-code-p 5 4)
              :pruned-state-error-message
              (first pruned-state-error-messages)
              :pruned-state-error-messages pruned-state-error-messages
              :public-connections (getf summary :public-connections)))))
  #-sbcl
  (error "Restored devnet public RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-engine-rpc
    (node payload-id expected-parent-hash expected-block-number
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 170)
                  (cons "method" "engine_getPayloadV2")
                  (cons "params" (list payload-id)))))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 171)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-prepared-payload"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-prepared-payload"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload
           (fixture-object-field
            (fixture-object-field engine-rpc "result")
            "executionPayload")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored Engine prepared-payload probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored Engine prepared-payload probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored engine_getPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored prepared-payload eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored engine_getPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-parent-hash)
              (fixture-object-field payload "parentHash"))
     "Restored prepared payload parent hash mismatch")
    (devnet-smoke-gate-require
     (string= expected-block-number
              (fixture-object-field payload "blockNumber"))
     "Restored prepared payload block number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored prepared-payload public block number mismatch")
    (list :prepared-payload-id payload-id
          :prepared-payload-parent-hash
          (fixture-object-field payload "parentHash")
          :prepared-payload-block-number
          (fixture-object-field payload "blockNumber")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node payload-id expected-parent-hash expected-block-number
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-remote-block-rpc
    (node remote-payload expected-block-hash expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 172 remote-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 173)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-remote-block"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-remote-block"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored remote-block probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored remote-block probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored remote-block engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored remote-block eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored remote-block engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-syncing+
              (fixture-object-field payload-status "status"))
     "Restored remote-block engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field payload-status "latestValidHash"))
     "Restored remote-block SYNCING status should not report latestValidHash")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored remote-block public block number mismatch")
    (list :remote-block-hash (hash32-to-hex expected-block-hash)
          :remote-block-status (fixture-object-field payload-status "status")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node remote-payload expected-block-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet remote-block Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-invalid-tipset-rpc
    (node descendant-payload expected-latest-valid-hash
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 174 descendant-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 175)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-invalid-tipset"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-invalid-tipset"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result"))
         (validation-error
           (fixture-object-field payload-status "validationError")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored invalid-tipset probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored invalid-tipset probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored invalid-tipset engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored invalid-tipset eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored invalid-tipset engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-invalid+
              (fixture-object-field payload-status "status"))
     "Restored invalid-tipset engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-latest-valid-hash)
              (fixture-object-field payload-status "latestValidHash"))
     "Restored invalid-tipset latestValidHash mismatch")
    (devnet-smoke-gate-require
     (string= "links to previously rejected block" validation-error)
     "Restored invalid-tipset validation error mismatch: ~A"
     validation-error)
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored invalid-tipset public block number mismatch")
    (list :invalid-tipset-status
          (fixture-object-field payload-status "status")
          :invalid-tipset-validation-error validation-error
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node descendant-payload expected-latest-valid-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet invalid-tipset Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-txpool-transaction-entry
    (txpool-transactions name)
  (or (cdr (assoc name txpool-transactions :test #'string=))
      (error "Missing txpool transaction entry ~A" name)))

(defun devnet-smoke-gate-transaction-hash-hex (transaction)
  (hash32-to-hex (transaction-hash transaction)))

(defun devnet-smoke-gate-transaction-raw (transaction)
  (bytes-to-hex (transaction-encoding transaction)))

(defun devnet-smoke-gate-txpool-journal-records (journal-path)
  (when (probe-file journal-path)
    (handler-case
        (let ((database (make-file-key-value-database journal-path)))
          (loop for entry in (kv-chain-record-entries database :txpool)
                collect
                (multiple-value-bind (subpool transaction)
                    (ethereum-lisp.core::chain-store-txpool-transaction-record-values
                     (cdr entry))
                  (list :hash (hash32-to-hex (transaction-hash transaction))
                        :subpool subpool
                        :raw (devnet-smoke-gate-transaction-raw
                              transaction)))))
      (error (condition)
        (error "Unable to read txpool rejournal file ~A: ~A"
               (namestring journal-path)
               condition)))))

(defun devnet-smoke-gate-wait-for-txpool-journal-record
    (journal-path expected-hash expected-raw timeout-seconds
     &key expected-record-count)
  (let* ((deadline
           (+ (get-internal-real-time)
              (* timeout-seconds internal-time-units-per-second)))
         (last-records nil))
    (loop
      (setf last-records
            (devnet-smoke-gate-txpool-journal-records journal-path))
      (let ((record
              (find-if
               (lambda (record)
                 (and (string= expected-hash (getf record :hash))
                      (string= expected-raw (getf record :raw))))
               last-records)))
        (when (and record
                   (or (null expected-record-count)
                       (>= (length last-records) expected-record-count)))
          (return
            (list :record-count (length last-records)
                  :transaction-hash (getf record :hash)
                  :subpool (getf record :subpool)))))
      (when (>= (get-internal-real-time) deadline)
        (error "Timed out after ~D seconds waiting for txpool journal ~A to contain ~A with at least ~A records; observed hashes: ~S"
               timeout-seconds
               (namestring journal-path)
               expected-hash
               (or expected-record-count 1)
               (mapcar (lambda (record) (getf record :hash))
                       last-records)))
      (sleep 0.05))))

(defun devnet-smoke-gate-wait-for-dev-period-transaction
    (node transaction-hash timeout-seconds)
  (let* ((deadline
           (+ (get-internal-real-time)
              (* timeout-seconds internal-time-units-per-second)))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (last-block-number nil))
    (loop
      (setf last-block-number
            (quantity-to-hex (chain-store-head-number store)))
      (let ((location
              (chain-store-transaction-location store transaction-hash)))
        (when location
          (return location)))
      (when (>= (get-internal-real-time) deadline)
        (error "Timed out after ~D seconds waiting for dev-period mining of ~A; latest block was ~A"
               timeout-seconds
               (hash32-to-hex transaction-hash)
               last-block-number))
      (sleep 0.05))))

(defun devnet-smoke-gate-verify-dev-period-mining
    (case-name &key terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  (declare (ignore case-name))
  #+sbcl
  (let* ((probe-case-name "shanghai-one-transfer-with-withdrawal")
         (fixture (devnet-smoke-gate-engine-fixture probe-case-name))
         (store (devnet-smoke-gate-field fixture "store"))
         (config
           (ethereum-lisp.cli::devnet-cli-apply-merge-overrides
            (devnet-smoke-gate-field fixture "config")
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed
            terminal-total-difficulty-passed-p
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (parent-state
           (devnet-smoke-gate-field fixture "parentState"))
         (parent-block
           (devnet-smoke-gate-field fixture "parentBlock"))
         (txpool-transactions
           (devnet-smoke-gate-field fixture "txpoolTransactions"))
         (pending-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "pending"))
         (transaction-hash (transaction-hash pending-transaction))
         (transaction-hash-hex (hash32-to-hex transaction-hash))
         (raw-transaction
           (devnet-smoke-gate-transaction-raw pending-transaction))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :dev-mode-p t
            :dev-period-seconds 1
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed
            terminal-total-difficulty-passed-p
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (send-output (make-string-output-stream))
         (wait-output (make-string-output-stream))
         (transaction-output (make-string-output-stream))
         (receipt-output (make-string-output-stream))
         (status-output (make-string-output-stream))
         (pending-output (make-string-output-stream))
         (block-output (make-string-output-stream))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-json-rpc-request
              301 "eth_sendRawTransaction" (list raw-transaction))
             send-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              302 "eth_blockNumber" '())
             wait-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              303 "eth_getTransactionByHash" (list transaction-hash-hex))
             transaction-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              304 "eth_getTransactionReceipt" (list transaction-hash-hex))
             receipt-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              305 "txpool_status" '())
             status-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              306 "eth_pendingTransactions" '())
             pending-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              307 "eth_getBlockByNumber" (list "latest" :false))
             block-output)))
         (mined-location nil))
    (devnet-cli-set-node-store-config node store config)
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (commit-state-db-to-chain-store
     store (block-hash parent-block) parent-state)
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "dev-period-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "dev-period-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (when (eq output wait-output)
                      (setf mined-location
                            (devnet-smoke-gate-wait-for-dev-period-transaction
                             node transaction-hash 8)))
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections 7)))
      (let* ((send-response (get-output-stream-string send-output))
             (wait-response (get-output-stream-string wait-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (status-response (get-output-stream-string status-output))
             (pending-response (get-output-stream-string pending-output))
             (block-response (get-output-stream-string block-output))
             (send-rpc (devnet-smoke-gate-rpc-body send-response))
             (wait-rpc (devnet-smoke-gate-rpc-body wait-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (status-rpc (devnet-smoke-gate-rpc-body status-response))
             (pending-rpc
               (devnet-smoke-gate-rpc-body pending-response
                                           :preserve-empty-arrays t))
             (block-rpc (devnet-smoke-gate-rpc-body block-response))
             (mined-transaction
               (fixture-object-field transaction-rpc "result"))
             (receipt (fixture-object-field receipt-rpc "result"))
             (status (fixture-object-field status-rpc "result"))
             (pending-transactions
               (fixture-object-field pending-rpc "result"))
             (latest-block
               (fixture-object-field block-rpc "result"))
             (mined-block
               (and mined-location
                    (engine-transaction-location-block mined-location)))
             (mined-block-number
               (quantity-to-hex
                (block-header-number (block-header mined-block))))
             (mined-block-hash
               (hash32-to-hex (block-hash mined-block))))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Dev-period smoke expected 0 Engine connections, got ~S"
         (getf summary :engine-connections))
        (devnet-smoke-gate-require
         (= 7 (getf summary :public-connections))
         "Dev-period smoke expected 7 public connections, got ~S"
         (getf summary :public-connections))
        (dolist (response (list send-response wait-response
                                transaction-response receipt-response
                                status-response pending-response
                                block-response))
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status response))
           "Dev-period smoke RPC HTTP status mismatch"))
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field send-rpc "result"))
         "Dev-period eth_sendRawTransaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field wait-rpc "result"))
         "Dev-period mined eth_blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field mined-transaction "hash"))
         "Dev-period mined transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field mined-transaction "blockHash"))
         "Dev-period mined transaction blockHash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field mined-transaction "blockNumber"))
         "Dev-period mined transaction blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  (fixture-object-field mined-transaction "transactionIndex"))
         "Dev-period mined transaction index mismatch")
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field receipt "transactionHash"))
         "Dev-period receipt transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field receipt "blockHash"))
         "Dev-period receipt blockHash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field receipt "blockNumber"))
         "Dev-period receipt blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field receipt "transactionIndex"))
         "Dev-period receipt transaction index mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field status "pending"))
         "Dev-period txpool_status pending count mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field status "queued"))
         "Dev-period txpool_status queued count mismatch")
        (devnet-smoke-gate-require
         (devnet-smoke-gate-empty-json-array-p pending-transactions)
         "Dev-period eth_pendingTransactions should be empty after mining")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field latest-block "hash"))
         "Dev-period latest block hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field latest-block "number"))
         "Dev-period latest block number mismatch")
        (list :dev-period-seconds 1
              :transaction-hash transaction-hash-hex
              :block-number mined-block-number
              :block-hash mined-block-hash
              :receipt-block-number
              (fixture-object-field receipt "blockNumber")
              :receipt-block-hash
              (fixture-object-field receipt "blockHash")
              :transaction-index
              (fixture-object-field mined-transaction "transactionIndex")
              :txpool-status-pending
              (fixture-object-field status "pending")
              :txpool-status-queued
              (fixture-object-field status "queued")
              :pending-transaction-count (length pending-transactions)
              :public-connections (getf summary :public-connections)
              :engine-connections (getf summary :engine-connections)
              :total-connections (getf summary :total-connections)))))
  #-sbcl
  (declare (ignore terminal-total-difficulty
                   terminal-total-difficulty-passed-p terminal-block-hash
                   terminal-block-number))
  #-sbcl
  (error "Dev-period smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-transaction-nonce-key (transaction)
  (format nil "~D" (transaction-nonce transaction)))

(defun devnet-smoke-gate-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun devnet-smoke-gate-verify-restored-txpool-rpc
    (node txpool-transactions
     &key selected-pending-imported-p selected-pending-transaction)
  #+sbcl
  (let* ((pending-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "pending"))
         (selected-transaction
           (or selected-pending-transaction pending-transaction))
         (basefee-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "basefee"))
         (queued-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "queued"))
         (transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex pending-transaction))
         (selected-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex selected-transaction))
         (basefee-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex basefee-transaction))
         (queued-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex queued-transaction))
         (raw-transaction
           (devnet-smoke-gate-transaction-raw pending-transaction))
         (selected-raw-transaction
           (devnet-smoke-gate-transaction-raw selected-transaction))
         (basefee-raw-transaction
           (devnet-smoke-gate-transaction-raw basefee-transaction))
         (queued-raw-transaction
           (devnet-smoke-gate-transaction-raw queued-transaction))
         (transaction-summary
           (devnet-smoke-gate-transaction-summary pending-transaction))
         (basefee-transaction-summary
           (devnet-smoke-gate-transaction-summary basefee-transaction))
         (queued-transaction-summary
           (devnet-smoke-gate-transaction-summary queued-transaction))
         (sender (transaction-sender pending-transaction))
         (sender-hex (address-to-hex sender))
         (nonce-key
           (devnet-smoke-gate-transaction-nonce-key pending-transaction))
         (expected-pending-sender-nonce
           (quantity-to-hex (1+ (transaction-nonce pending-transaction))))
         (basefee-nonce-key
           (devnet-smoke-gate-transaction-nonce-key basefee-transaction))
         (queued-nonce-key
           (devnet-smoke-gate-transaction-nonce-key queued-transaction))
         (expected-pending-count
           (if selected-pending-imported-p 0 1))
         (expected-pending-count-hex
           (quantity-to-hex expected-pending-count))
         (raw-output (make-string-output-stream))
         (basefee-raw-output (make-string-output-stream))
         (queued-raw-output (make-string-output-stream))
         (pending-block-count-output (make-string-output-stream))
         (pending-block-output (make-string-output-stream))
         (pending-header-output (make-string-output-stream))
         (pending-fee-history-output (make-string-output-stream))
         (pending-nonce-output (make-string-output-stream))
         (pending-index-output (make-string-output-stream))
         (pending-raw-index-output (make-string-output-stream))
         (pending-output (make-string-output-stream))
         (status-output (make-string-output-stream))
         (content-output (make-string-output-stream))
         (content-from-output (make-string-output-stream))
         (inspect-output (make-string-output-stream))
         (public-requests
           (list
            (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                    (cons "id" 176)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list selected-transaction-hash-hex))))
             raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 181)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list basefee-transaction-hash-hex))))
             basefee-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 182)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list queued-transaction-hash-hex))))
             queued-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 184)
                    (cons "method" "eth_getBlockTransactionCountByNumber")
                    (cons "params" (list "pending"))))
             pending-block-count-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 187)
                    (cons "method" "eth_getBlockByNumber")
                    (cons "params" (list "pending" t))))
             pending-block-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 188)
                    (cons "method" "eth_getHeaderByNumber")
                    (cons "params" (list "pending"))))
             pending-header-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 189)
                    (cons "method" "eth_feeHistory")
                    (cons "params" (list "0x1" "latest" '()))))
             pending-fee-history-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 190)
                    (cons "method" "eth_getTransactionCount")
                    (cons "params" (list sender-hex "pending"))))
             pending-nonce-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 185)
                    (cons "method"
                          "eth_getTransactionByBlockNumberAndIndex")
                    (cons "params" (list "pending" "0x0"))))
             pending-index-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 186)
                    (cons "method"
                          "eth_getRawTransactionByBlockNumberAndIndex")
                    (cons "params" (list "pending" "0x0"))))
             pending-raw-index-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 177)
                    (cons "method" "eth_pendingTransactions")
                    (cons "params" '())))
             pending-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 178)
                    (cons "method" "txpool_status")
                    (cons "params" '())))
             status-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 179)
                    (cons "method" "txpool_content")
                    (cons "params" '())))
             content-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 180)
                    (cons "method" "txpool_contentFrom")
                    (cons "params" (list sender-hex))))
             content-from-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 183)
                    (cons "method" "txpool_inspect")
                    (cons "params" '())))
             inspect-output)))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-txpool"
             :accept-function (lambda () nil)
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-txpool"
             :accept-function
             (lambda ()
               (when public-requests
                 (destructuring-bind (body . output)
                     (pop public-requests)
                   (make-engine-rpc-http-connection
                    :input-stream
                    (make-string-input-stream
                     (devnet-cli-json-rpc-http-request body))
                    :output-stream output
                    :close-function (lambda () nil)))))
            :close-function (lambda () nil))
            :max-connections 15))
         (raw-response (get-output-stream-string raw-output))
         (basefee-raw-response
           (get-output-stream-string basefee-raw-output))
         (queued-raw-response
           (get-output-stream-string queued-raw-output))
         (pending-block-count-response
           (get-output-stream-string pending-block-count-output))
         (pending-block-response
           (get-output-stream-string pending-block-output))
         (pending-header-response
           (get-output-stream-string pending-header-output))
         (pending-fee-history-response
           (get-output-stream-string pending-fee-history-output))
         (pending-nonce-response
           (get-output-stream-string pending-nonce-output))
         (pending-index-response
           (get-output-stream-string pending-index-output))
         (pending-raw-index-response
           (get-output-stream-string pending-raw-index-output))
         (pending-response (get-output-stream-string pending-output))
         (status-response (get-output-stream-string status-output))
         (content-response (get-output-stream-string content-output))
         (content-from-response
           (get-output-stream-string content-from-output))
         (inspect-response (get-output-stream-string inspect-output))
         (raw-rpc (devnet-smoke-gate-rpc-body raw-response))
         (basefee-raw-rpc
           (devnet-smoke-gate-rpc-body basefee-raw-response))
         (queued-raw-rpc
           (devnet-smoke-gate-rpc-body queued-raw-response))
         (pending-block-count-rpc
           (devnet-smoke-gate-rpc-body pending-block-count-response))
         (pending-block-rpc
           (devnet-smoke-gate-rpc-body pending-block-response))
         (pending-header-rpc
           (devnet-smoke-gate-rpc-body pending-header-response))
         (pending-fee-history-rpc
           (devnet-smoke-gate-rpc-body pending-fee-history-response))
         (pending-nonce-rpc
           (devnet-smoke-gate-rpc-body pending-nonce-response))
         (pending-index-rpc
           (devnet-smoke-gate-rpc-body pending-index-response))
         (pending-raw-index-rpc
           (devnet-smoke-gate-rpc-body pending-raw-index-response))
         (pending-rpc (devnet-smoke-gate-rpc-body pending-response))
         (status-rpc (devnet-smoke-gate-rpc-body status-response))
         (content-rpc (devnet-smoke-gate-rpc-body content-response))
         (content-from-rpc
           (devnet-smoke-gate-rpc-body content-from-response))
         (inspect-rpc (devnet-smoke-gate-rpc-body inspect-response))
         (pending-transactions
           (fixture-object-field pending-rpc "result"))
         (pending-object (first pending-transactions))
         (pending-block
           (fixture-object-field pending-block-rpc "result"))
         (pending-header
           (fixture-object-field pending-header-rpc "result"))
         (pending-fee-history
           (fixture-object-field pending-fee-history-rpc "result"))
         (pending-fee-history-base-fees
           (fixture-object-field pending-fee-history "baseFeePerGas"))
         (pending-fee-history-next-base-fee
           (second pending-fee-history-base-fees))
         (pending-block-transactions
           (fixture-object-field pending-block "transactions"))
         (pending-block-transaction
           (first pending-block-transactions))
         (pending-index-transaction
           (fixture-object-field pending-index-rpc "result"))
         (status (fixture-object-field status-rpc "result"))
         (content (fixture-object-field content-rpc "result"))
         (content-pending (fixture-object-field content "pending"))
         (content-sender
           (fixture-object-field content-pending sender-hex))
         (content-transaction
           (fixture-object-field content-sender nonce-key))
         (content-queued (fixture-object-field content "queued"))
         (content-queued-sender
           (fixture-object-field content-queued sender-hex))
         (content-basefee-transaction
           (fixture-object-field content-queued-sender basefee-nonce-key))
         (content-queued-transaction
           (fixture-object-field content-queued-sender queued-nonce-key))
         (content-from
           (fixture-object-field content-from-rpc "result"))
         (content-from-pending
           (fixture-object-field content-from "pending"))
         (content-from-queued
           (fixture-object-field content-from "queued"))
         (content-from-transaction
           (fixture-object-field content-from-pending nonce-key))
         (content-from-basefee-transaction
           (fixture-object-field content-from-queued basefee-nonce-key))
         (content-from-queued-transaction
           (fixture-object-field content-from-queued queued-nonce-key))
         (inspect (fixture-object-field inspect-rpc "result"))
         (inspect-pending (fixture-object-field inspect "pending"))
         (inspect-sender
           (fixture-object-field inspect-pending sender-hex))
         (inspect-transaction
           (fixture-object-field inspect-sender nonce-key))
         (inspect-queued (fixture-object-field inspect "queued"))
         (inspect-queued-sender
           (fixture-object-field inspect-queued sender-hex))
         (inspect-basefee-transaction
           (fixture-object-field inspect-queued-sender basefee-nonce-key))
         (inspect-queued-transaction
           (fixture-object-field inspect-queued-sender queued-nonce-key)))
    (devnet-smoke-gate-require
     (= 15 (getf summary :public-connections))
     "Restored txpool probe expected 15 public connections, got ~S"
     (getf summary :public-connections))
    (dolist (response (list raw-response basefee-raw-response
                            queued-raw-response pending-block-count-response
                            pending-block-response pending-header-response
                            pending-fee-history-response
                            pending-nonce-response
                            pending-index-response pending-raw-index-response
                            pending-response
                            status-response content-response
                            content-from-response inspect-response))
      (devnet-smoke-gate-require
       (= 200 (devnet-cli-http-status response))
       "Restored txpool RPC HTTP status mismatch"))
    (devnet-smoke-gate-require
     (string= selected-raw-transaction
              (fixture-object-field raw-rpc "result"))
     "Restored txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= basefee-raw-transaction
              (fixture-object-field basefee-raw-rpc "result"))
     "Restored basefee txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= queued-raw-transaction
              (fixture-object-field queued-raw-rpc "result"))
     "Restored queued txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= expected-pending-count-hex
              (fixture-object-field pending-block-count-rpc "result"))
     "Restored pending block-tag transaction count mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-block "hash"))
     "Restored pending block-tag block should not expose a block hash")
    (devnet-smoke-gate-require
     (string= (fixture-object-field pending-block "number")
              (fixture-object-field pending-header "number"))
     "Restored pending header number should match pending block number")
    (devnet-smoke-gate-require
     (string= (fixture-object-field pending-block "parentHash")
              (fixture-object-field pending-header "parentHash"))
     "Restored pending header parent hash should match pending block parent hash")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-header "hash"))
     "Restored pending header should not expose a block hash")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-header "nonce"))
     "Restored pending header should not expose a nonce")
    (devnet-smoke-gate-require
     (= 2 (length pending-fee-history-base-fees))
     "Restored pending fee history baseFeePerGas length mismatch")
    (devnet-smoke-gate-require
     (string= pending-fee-history-next-base-fee
              (fixture-object-field pending-block "baseFeePerGas"))
     "Restored pending block base fee should match fee history next base fee")
    (devnet-smoke-gate-require
     (string= pending-fee-history-next-base-fee
              (fixture-object-field pending-header "baseFeePerGas"))
     "Restored pending header base fee should match fee history next base fee")
    (devnet-smoke-gate-require
     (string= expected-pending-sender-nonce
              (fixture-object-field pending-nonce-rpc "result"))
     "Restored pending transaction count nonce mismatch")
    (devnet-smoke-gate-require
     (= expected-pending-count (length pending-block-transactions))
     "Restored pending block-tag block transaction count mismatch")
    (if selected-pending-imported-p
        (progn
          (devnet-smoke-gate-require
           (null pending-index-transaction)
           "Restored pending block-tag transaction index should be empty")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-raw-index-rpc "result"))
           "Restored pending block-tag raw transaction should be empty"))
        (progn
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field pending-block-transaction "hash"))
           "Restored pending block-tag block transaction hash mismatch")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-block-transaction "blockHash"))
           "Restored pending block-tag block transaction should not have a block hash")
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field pending-index-transaction "hash"))
           "Restored pending block-tag transaction index hash mismatch")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-index-transaction "blockHash"))
           "Restored pending block-tag transaction should not have a block hash")
          (devnet-smoke-gate-require
           (string= raw-transaction
                    (fixture-object-field pending-raw-index-rpc "result"))
           "Restored pending block-tag raw transaction mismatch")))
    (devnet-smoke-gate-require
     (= expected-pending-count (length pending-transactions))
     "Restored txpool pending transaction count mismatch")
    (unless selected-pending-imported-p
      (devnet-smoke-gate-require
       (string= transaction-hash-hex
                (fixture-object-field pending-object "hash"))
       "Restored eth_pendingTransactions hash mismatch")
      (devnet-smoke-gate-require
       (null (fixture-object-field pending-object "blockHash"))
       "Restored pending transaction should not have a block hash"))
    (devnet-smoke-gate-require
     (string= expected-pending-count-hex
              (fixture-object-field status "pending"))
     "Restored txpool_status pending count mismatch")
    (devnet-smoke-gate-require
     (string= "0x2" (fixture-object-field status "queued"))
     "Restored txpool_status queued count mismatch")
    (if selected-pending-imported-p
        (progn
          (devnet-smoke-gate-require
           (null content-transaction)
           "Restored txpool_content should not expose mined pending transaction")
          (devnet-smoke-gate-require
           (null content-from-transaction)
           "Restored txpool_contentFrom should not expose mined pending transaction"))
        (progn
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field content-transaction "hash"))
           "Restored txpool_content hash mismatch")
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field content-from-transaction "hash"))
           "Restored txpool_contentFrom hash mismatch")))
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-basefee-transaction "hash"))
     "Restored txpool_content basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-queued-transaction "hash"))
     "Restored txpool_content queued hash mismatch")
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-from-basefee-transaction "hash"))
     "Restored txpool_contentFrom basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-from-queued-transaction "hash"))
     "Restored txpool_contentFrom queued hash mismatch")
    (if selected-pending-imported-p
        (devnet-smoke-gate-require
         (null inspect-transaction)
         "Restored txpool_inspect should not expose mined pending transaction")
        (devnet-smoke-gate-require
         (string= transaction-summary inspect-transaction)
         "Restored txpool_inspect pending summary mismatch"))
    (devnet-smoke-gate-require
     (string= basefee-transaction-summary inspect-basefee-transaction)
     "Restored txpool_inspect basefee summary mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-summary inspect-queued-transaction)
     "Restored txpool_inspect queued summary mismatch")
    (list :txpool-transaction-hash selected-transaction-hash-hex
          :txpool-raw-transaction selected-raw-transaction
          :txpool-sender sender-hex
          :txpool-nonce nonce-key
          :txpool-inspect-summary inspect-transaction
          :txpool-basefee-transaction-hash basefee-transaction-hash-hex
          :txpool-basefee-raw-transaction basefee-raw-transaction
          :txpool-basefee-nonce basefee-nonce-key
          :txpool-basefee-inspect-summary inspect-basefee-transaction
          :txpool-queued-transaction-hash queued-transaction-hash-hex
          :txpool-queued-raw-transaction queued-raw-transaction
          :txpool-queued-nonce queued-nonce-key
          :txpool-queued-inspect-summary inspect-queued-transaction
          :txpool-status-pending
          (fixture-object-field status "pending")
          :txpool-status-queued
          (fixture-object-field status "queued")
          :txpool-pending-block-count
          (fixture-object-field pending-block-count-rpc "result")
          :txpool-pending-block-hash
          (fixture-object-field pending-block "hash")
          :txpool-pending-block-base-fee
          (fixture-object-field pending-block "baseFeePerGas")
          :txpool-pending-header-number
          (fixture-object-field pending-header "number")
          :txpool-pending-header-parent-hash
          (fixture-object-field pending-header "parentHash")
          :txpool-pending-header-hash
          (fixture-object-field pending-header "hash")
          :txpool-pending-header-nonce
          (fixture-object-field pending-header "nonce")
          :txpool-pending-header-base-fee
          (fixture-object-field pending-header "baseFeePerGas")
          :txpool-pending-fee-history-next-base-fee
          pending-fee-history-next-base-fee
          :txpool-pending-sender-nonce
          (fixture-object-field pending-nonce-rpc "result")
          :txpool-pending-block-transaction-hash
          (fixture-object-field pending-block-transaction "hash")
          :txpool-pending-block-transaction-block-hash
          (fixture-object-field pending-block-transaction "blockHash")
          :txpool-pending-index-transaction-hash
          (fixture-object-field pending-index-transaction "hash")
          :txpool-pending-index-block-hash
          (fixture-object-field pending-index-transaction "blockHash")
          :txpool-pending-raw-index-transaction
          (fixture-object-field pending-raw-index-rpc "result")
          :txpool-content-hash
          (fixture-object-field content-transaction "hash")
          :txpool-content-from-hash
          (fixture-object-field content-from-transaction "hash")
          :txpool-basefee-content-hash
          (fixture-object-field content-basefee-transaction "hash")
          :txpool-basefee-content-from-hash
          (fixture-object-field content-from-basefee-transaction "hash")
          :txpool-queued-content-hash
          (fixture-object-field content-queued-transaction "hash")
          :txpool-queued-content-from-hash
          (fixture-object-field content-from-queued-transaction "hash")
          :public-connections (getf summary :public-connections)))
  #-sbcl
  (declare (ignore node txpool-transactions))
  #-sbcl
  (error "Restored devnet txpool RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-side-reorg-rpc
    (path side-payload side-block child-block balance-targets
     checkpoint-balance-targets transaction-checks expected-safe-block-hash
     sender-address code-address storage-address storage-key config)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-side-reorg-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (devnet-smoke-gate-make-restored-node
                     path
                     config
                     :port 0
                     :public-port 0
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (primary-balance-target (first balance-targets))
                  (balance-address
                    (getf primary-balance-target :address))
                  (primary-checkpoint-balance-target
                    (first checkpoint-balance-targets))
                  (expected-checkpoint-balance
                    (getf primary-checkpoint-balance-target :balance))
                  (transaction-hash
                    (getf (first transaction-checks) :hash))
                  (expected-raw-transaction
                    (getf (first transaction-checks) :raw))
                  (transaction-hash-hex
                    (hash32-to-hex transaction-hash))
                  (displaced-transaction
                    (first (block-transactions child-block)))
                  (transaction-items
                    (loop for check in transaction-checks
                          for transaction in (block-transactions child-block)
                          collect
                          (list
                           :hash (getf check :hash)
                           :hash-hex (hash32-to-hex (getf check :hash))
                           :raw (getf check :raw)
                           :reinsertable-p
                           (not (null
                                 (transaction-sender
                                  transaction
                                  :expected-chain-id
                                  (chain-config-chain-id
                                   (ethereum-lisp.cli:devnet-node-config
                                    node))))))))
                  (reinsertable-transaction-items
                    (remove-if-not
                     (lambda (item) (getf item :reinsertable-p))
                     transaction-items))
                  (reinsertable-transaction-hashes
                    (mapcar
                     (lambda (item) (getf item :hash-hex))
                     reinsertable-transaction-items))
                  (extra-transaction-items
                    (rest transaction-items))
                  (side-public-connection-count
                    (+ 9 (length extra-transaction-items)))
                  (fresh-public-connection-count
                    (+ 20 (length extra-transaction-items)))
                  (side-block-hash (block-hash side-block))
                  (child-block-hash (block-hash child-block))
                  (node-chain-id
                    (chain-config-chain-id
                     (ethereum-lisp.cli:devnet-node-config node)))
                  (reinsertable-transaction-p
                    (not (null
                          (transaction-sender
                           displaced-transaction
                           :expected-chain-id node-chain-id))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (1- (block-header-number
                          (block-header child-block)))))
                  (expected-side-block-number
                    (quantity-to-hex
                     (block-header-number (block-header side-block))))
                  (side-payload-output (make-string-output-stream))
                  (side-rejected-forkchoice-output
                    (make-string-output-stream))
                  (side-forkchoice-output (make-string-output-stream))
                  (side-block-number-output (make-string-output-stream))
                  (side-latest-block-output (make-string-output-stream))
                  (side-transaction-output (make-string-output-stream))
                  (side-raw-transaction-output
                    (make-string-output-stream))
                  (side-pending-transactions-output
                    (make-string-output-stream))
                  (side-receipt-output (make-string-output-stream))
                  (side-extra-receipt-outputs
                    (loop repeat (length extra-transaction-items)
                          collect (make-string-output-stream)))
                  (child-block-output (make-string-output-stream))
                  (side-block-receipts-output (make-string-output-stream))
                  (side-logs-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 201 side-payload))
                      side-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        202 side-block-hash
                        :safe child-block-hash
                        :finalized expected-safe-block-hash))
                      side-rejected-forkchoice-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        210 side-block-hash
                        :safe expected-safe-block-hash
                        :finalized expected-safe-block-hash))
                      side-forkchoice-output)))
                  (public-requests
                    (append
                     (list
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 203)
                              (cons "method" "eth_blockNumber")
                              (cons "params" '())))
                       side-block-number-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 204)
                              (cons "method" "eth_getBlockByNumber")
                              (cons "params" (list "latest" :false))))
                       side-latest-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 205)
                              (cons "method" "eth_getTransactionByHash")
                              (cons "params"
                                    (list (hash32-to-hex
                                           transaction-hash)))))
                       side-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 206)
                              (cons "method" "eth_getRawTransactionByHash")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-raw-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 207)
                              (cons "method" "eth_pendingTransactions")
                              (cons "params" '())))
                       side-pending-transactions-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 208)
                              (cons "method" "eth_getTransactionReceipt")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-receipt-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 209)
                              (cons "method" "eth_getBlockByHash")
                              (cons "params"
                                    (list (hash32-to-hex child-block-hash)
                                          :false))))
                       child-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 211)
                              (cons "method" "eth_getBlockReceipts")
                              (cons "params" (list "latest"))))
                       side-block-receipts-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 212)
                              (cons "method" "eth_getLogs")
                              (cons "params"
                                    (list
                                     (list
                                      (cons "fromBlock"
                                            expected-side-block-number)
                                      (cons "toBlock"
                                            expected-side-block-number))))))
                       side-logs-output))
                     (loop for item in extra-transaction-items
                           for output in side-extra-receipt-outputs
                           for id from 230
                           collect
                           (cons
                            (json-encode
                             (list (cons "jsonrpc" "2.0")
                                   (cons "id" id)
                                   (cons "method" "eth_getTransactionReceipt")
                                   (cons "params"
                                         (list (getf item :hash-hex)))))
                            output))))
                  (engine-done-p nil)
                  (engine-served-count 0)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-side-reorg"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (body . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               body :token token))
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count 3)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public-side-reorg"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (body . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request body))
                             :output-stream output
                             :close-function (lambda () nil)))))
                     :close-function (lambda () nil))
                     :max-connections side-public-connection-count))
                  (side-payload-response
                    (get-output-stream-string side-payload-output))
                  (side-rejected-forkchoice-response
                    (get-output-stream-string
                     side-rejected-forkchoice-output))
                  (side-forkchoice-response
                    (get-output-stream-string side-forkchoice-output))
                  (side-block-number-response
                    (get-output-stream-string side-block-number-output))
                  (side-latest-block-response
                    (get-output-stream-string side-latest-block-output))
                  (side-transaction-response
                    (get-output-stream-string side-transaction-output))
                  (side-raw-transaction-response
                    (get-output-stream-string side-raw-transaction-output))
                  (side-pending-transactions-response
                    (get-output-stream-string
                     side-pending-transactions-output))
                  (side-receipt-response
                    (get-output-stream-string side-receipt-output))
                  (side-extra-receipt-responses
                    (mapcar #'get-output-stream-string
                            side-extra-receipt-outputs))
                  (child-block-response
                    (get-output-stream-string child-block-output))
                  (side-block-receipts-response
                    (get-output-stream-string side-block-receipts-output))
                  (side-logs-response
                    (get-output-stream-string side-logs-output))
                  (side-payload-rpc
                    (devnet-smoke-gate-rpc-body side-payload-response))
                  (side-rejected-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body
                     side-rejected-forkchoice-response))
                  (side-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body side-forkchoice-response))
                  (side-block-number-rpc
                    (devnet-smoke-gate-rpc-body side-block-number-response))
                  (side-latest-block-rpc
                    (devnet-smoke-gate-rpc-body side-latest-block-response))
                  (side-transaction-rpc
                    (devnet-smoke-gate-rpc-body side-transaction-response))
                  (side-raw-transaction-rpc
                    (devnet-smoke-gate-rpc-body
                     side-raw-transaction-response))
                  (side-pending-transactions-rpc
                    (devnet-smoke-gate-rpc-body
                     side-pending-transactions-response))
                  (side-receipt-rpc
                    (devnet-smoke-gate-rpc-body side-receipt-response))
                  (side-extra-receipt-rpcs
                    (mapcar #'devnet-smoke-gate-rpc-body
                            side-extra-receipt-responses))
                  (child-block-rpc
                    (devnet-smoke-gate-rpc-body child-block-response))
                  (side-block-receipts-rpc
                    (devnet-smoke-gate-rpc-body
                     side-block-receipts-response))
                  (side-logs-rpc
                    (devnet-smoke-gate-rpc-body side-logs-response))
                  (side-payload-result
                    (fixture-object-field side-payload-rpc "result"))
                  (side-rejected-forkchoice-error
                    (fixture-object-field side-rejected-forkchoice-rpc
                                          "error"))
                  (side-forkchoice-status
                    (fixture-object-field
                     (fixture-object-field side-forkchoice-rpc "result")
                     "payloadStatus"))
                  (side-latest-block
                    (fixture-object-field side-latest-block-rpc "result"))
                  (side-transaction
                    (fixture-object-field side-transaction-rpc "result"))
                  (side-raw-transaction
                    (fixture-object-field side-raw-transaction-rpc "result"))
                  (side-pending-transactions
                    (fixture-object-field side-pending-transactions-rpc
                                          "result"))
                  (side-pending-transaction
                    (find transaction-hash-hex side-pending-transactions
                          :test #'string=
                          :key (lambda (transaction)
                                 (fixture-object-field transaction
                                                       "hash"))))
                  (side-reinserted-transactions
                    (loop for item in reinsertable-transaction-items
                          collect
                          (find (getf item :hash-hex)
                                side-pending-transactions
                                :test #'string=
                                :key (lambda (transaction)
                                       (fixture-object-field transaction
                                                             "hash")))))
                  (child-block-by-hash
                    (fixture-object-field child-block-rpc "result"))
                  (side-block-receipts
                    (fixture-object-field side-block-receipts-rpc "result"))
                  (side-logs
                    (fixture-object-field side-logs-rpc "result"))
                  (side-hidden-receipt-count
                    (count-if
                     #'identity
                     (cons
                      (null (fixture-object-field side-receipt-rpc "result"))
                      (mapcar
                       (lambda (rpc)
                         (null (fixture-object-field rpc "result")))
                       side-extra-receipt-rpcs)))))
             (devnet-smoke-gate-require
              (= 3 (getf summary :engine-connections))
              "Expected 3 side-reorg Engine connections, got ~S"
              (getf summary :engine-connections))
             (devnet-smoke-gate-require
              (= side-public-connection-count
                 (getf summary :public-connections))
              "Expected ~S side-reorg public connections, got ~S"
              side-public-connection-count
              (getf summary :public-connections))
             (dolist (response
                      (append
                       (list side-payload-response
                             side-rejected-forkchoice-response
                             side-forkchoice-response
                             side-block-number-response
                             side-latest-block-response
                             side-transaction-response
                             side-raw-transaction-response
                             side-pending-transactions-response
                             side-receipt-response
                             child-block-response
                             side-block-receipts-response
                             side-logs-response)
                       side-extra-receipt-responses))
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status response))
                "Restored side-reorg RPC HTTP status mismatch"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-payload-result "status"))
              "Restored side sibling engine_newPayloadV2 status mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-payload-result
                                             "latestValidHash"))
              "Restored side sibling latestValidHash mismatch")
             (devnet-smoke-gate-require
              (= -38002
                 (fixture-object-field side-rejected-forkchoice-error
                                       "code"))
              "Restored side sibling rejected checkpoint error code mismatch")
             (devnet-smoke-gate-require
              (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field side-rejected-forkchoice-error
                                             "message"))
              "Restored side sibling rejected checkpoint error mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-forkchoice-status "status"))
              "Restored side sibling forkchoice status mismatch")
             (devnet-smoke-gate-require
              (string= expected-side-block-number
                       (fixture-object-field side-block-number-rpc "result"))
              "Restored side sibling eth_blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-latest-block "hash"))
              "Restored side sibling latest block hash mismatch")
             (if reinsertable-transaction-p
                 (progn
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-transaction "hash"))
                    "Restored side sibling should reinsert old canonical transaction")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction "blockHash"))
                    "Restored side sibling transaction should be pending")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "blockNumber"))
                    "Restored side sibling transaction should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "transactionIndex"))
                    "Restored side sibling transaction should not have an index")
                   (devnet-smoke-gate-require
                    (string= expected-raw-transaction side-raw-transaction)
                    "Restored side sibling should expose pending raw transaction")
                   (devnet-smoke-gate-require
                    side-pending-transaction
                    "Restored side sibling should expose displaced transaction in pending view")
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-pending-transaction
                                                   "hash"))
                    "Restored side sibling pending view transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockHash"))
                    "Restored side sibling pending view should not have a block hash")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockNumber"))
                    "Restored side sibling pending view should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "transactionIndex"))
                    "Restored side sibling pending view should not have an index")
                 (loop for item in reinsertable-transaction-items
                       for pending-transaction in side-reinserted-transactions
                       do
                          (devnet-smoke-gate-require
                           pending-transaction
                           "Restored side sibling missing displaced transaction in pending view")
                          (devnet-smoke-gate-require
                           (string= (getf item :hash-hex)
                                    (fixture-object-field
                                     pending-transaction
                                     "hash"))
                           "Restored side sibling displaced pending hash mismatch")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockHash"))
                           "Restored side sibling displaced pending kept old block hash")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockNumber"))
                           "Restored side sibling displaced pending kept old block number")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "transactionIndex"))
                           "Restored side sibling displaced pending kept old index")))
               (progn
                 (devnet-smoke-gate-require
                  (null side-transaction)
                  "Restored side sibling should reject wrong-chain displaced transaction")
                 (devnet-smoke-gate-require
                  (null side-raw-transaction)
                  "Restored side sibling should hide wrong-chain raw transaction")
                 (devnet-smoke-gate-require
                  (null side-pending-transaction)
                  "Restored side sibling should hide wrong-chain pending transaction")))
             (devnet-smoke-gate-require
              (null (fixture-object-field side-receipt-rpc "result"))
              "Restored side sibling should hide old canonical receipt")
             (loop for item in extra-transaction-items
                   for rpc in side-extra-receipt-rpcs
                   do
                      (devnet-smoke-gate-require
                       (null (fixture-object-field rpc "result"))
                       "Restored side sibling should hide displaced canonical receipt ~S"
                       (getf item :hash-hex)))
	             (devnet-smoke-gate-require
	              (string= (hash32-to-hex child-block-hash)
	                       (fixture-object-field child-block-by-hash "hash"))
	              "Restored side sibling lost child block hash lookup")
	             (devnet-smoke-gate-require
	              (zerop (length side-block-receipts))
	              "Restored side sibling should have no canonical receipts")
	             (devnet-smoke-gate-require
	              (zerop (length side-logs))
	              "Restored side sibling should have no canonical logs")
             (ethereum-lisp.cli::devnet-node-export-database node)
             (let* ((fresh-node
                      (devnet-smoke-gate-make-restored-node
                       path config :port 0))
                    (fresh-summary
                      (ethereum-lisp.cli:devnet-node-summary fresh-node))
                    (fresh-raw-transaction-output
                      (make-string-output-stream))
                    (fresh-pending-transactions-output
                      (make-string-output-stream))
                    (fresh-receipt-output
                      (make-string-output-stream))
                    (fresh-extra-receipt-outputs
                      (loop repeat (length extra-transaction-items)
                            collect (make-string-output-stream)))
                    (fresh-block-number-output
                      (make-string-output-stream))
                    (fresh-latest-block-output
                      (make-string-output-stream))
                    (fresh-child-block-output
                      (make-string-output-stream))
                    (fresh-block-receipts-output
                      (make-string-output-stream))
                    (fresh-logs-output
                      (make-string-output-stream))
                    (fresh-safe-block-output
                      (make-string-output-stream))
                    (fresh-finalized-block-output
                      (make-string-output-stream))
                    (fresh-safe-balance-output
                      (make-string-output-stream))
                    (fresh-finalized-balance-output
                      (make-string-output-stream))
                    (fresh-child-require-canonical-state-probes
                      (devnet-smoke-gate-state-error-probes
                       225
                       (list
                        (cons "blockHash" (hash32-to-hex child-block-hash))
                        (cons "requireCanonical" t))
                       (devnet-smoke-gate-noncanonical-state-error-messages)
                       balance-address
                       sender-address
                       code-address
                       storage-address
                       storage-key))
                    (fresh-public-requests
                      (append
                       (list
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 213)
                                (cons "method" "eth_getRawTransactionByHash")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-raw-transaction-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 214)
                                (cons "method" "eth_pendingTransactions")
                                (cons "params" '())))
                         fresh-pending-transactions-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 215)
                                (cons "method" "eth_getTransactionReceipt")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-receipt-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 216)
                                (cons "method" "eth_blockNumber")
                                (cons "params" '())))
                         fresh-block-number-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 217)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "latest" :false))))
                         fresh-latest-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 218)
                                (cons "method" "eth_getBlockByHash")
                                (cons "params"
                                      (list (hash32-to-hex child-block-hash)
                                            :false))))
                         fresh-child-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 219)
                                (cons "method" "eth_getBlockReceipts")
                                (cons "params" (list "latest"))))
                         fresh-block-receipts-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 220)
                                (cons "method" "eth_getLogs")
                                (cons "params"
                                      (list
                                       (list
                                        (cons "fromBlock"
                                              expected-side-block-number)
                                        (cons "toBlock"
                                              expected-side-block-number))))))
                         fresh-logs-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 221)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "safe" :false))))
                         fresh-safe-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 222)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "finalized" :false))))
                         fresh-finalized-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 223)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "safe"))))
                         fresh-safe-balance-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 224)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "finalized"))))
                         fresh-finalized-balance-output))
                       (loop for item in extra-transaction-items
                             for output in fresh-extra-receipt-outputs
                             for id from 240
                             collect
                             (cons
                              (json-encode
                               (list (cons "jsonrpc" "2.0")
                                     (cons "id" id)
                                     (cons "method"
                                           "eth_getTransactionReceipt")
                                     (cons "params"
                                           (list (getf item :hash-hex)))))
                              output))
                       (mapcar
                        (lambda (probe)
                          (cons (json-encode (getf probe :request))
                                (getf probe :output)))
                        fresh-child-require-canonical-state-probes)))
                    (fresh-rpc-summary
                      (ethereum-lisp.cli:start-devnet-node-listeners
                       fresh-node
                       (make-engine-rpc-http-listener
                        :endpoint "engine-side-reorg-fresh-restore"
                        :accept-function (lambda () nil)
                        :close-function (lambda () nil))
                       (make-engine-rpc-http-listener
                        :endpoint "public-side-reorg-fresh-restore"
                        :accept-function
                        (lambda ()
                          (when fresh-public-requests
                            (destructuring-bind (body . output)
                                (pop fresh-public-requests)
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function (lambda () nil)))))
                       :close-function (lambda () nil))
                       :max-connections fresh-public-connection-count))
                    (fresh-raw-transaction-response
                      (get-output-stream-string
                       fresh-raw-transaction-output))
                    (fresh-pending-transactions-response
                      (get-output-stream-string
                       fresh-pending-transactions-output))
                    (fresh-receipt-response
                      (get-output-stream-string fresh-receipt-output))
                    (fresh-extra-receipt-responses
                      (mapcar #'get-output-stream-string
                              fresh-extra-receipt-outputs))
                    (fresh-block-number-response
                      (get-output-stream-string fresh-block-number-output))
                    (fresh-latest-block-response
                      (get-output-stream-string fresh-latest-block-output))
                    (fresh-child-block-response
                      (get-output-stream-string fresh-child-block-output))
                    (fresh-block-receipts-response
                      (get-output-stream-string fresh-block-receipts-output))
                    (fresh-logs-response
                      (get-output-stream-string fresh-logs-output))
                    (fresh-safe-block-response
                      (get-output-stream-string fresh-safe-block-output))
                    (fresh-finalized-block-response
                      (get-output-stream-string fresh-finalized-block-output))
                    (fresh-safe-balance-response
                      (get-output-stream-string fresh-safe-balance-output))
                    (fresh-finalized-balance-response
                      (get-output-stream-string
                       fresh-finalized-balance-output))
                    (fresh-raw-transaction-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-raw-transaction-response))
                    (fresh-pending-transactions-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-pending-transactions-response))
                    (fresh-receipt-rpc
                      (devnet-smoke-gate-rpc-body fresh-receipt-response))
                    (fresh-extra-receipt-rpcs
                      (mapcar #'devnet-smoke-gate-rpc-body
                              fresh-extra-receipt-responses))
                    (fresh-block-number-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-number-response))
                    (fresh-latest-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-latest-block-response))
                    (fresh-child-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-child-block-response))
                    (fresh-block-receipts-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-receipts-response))
                    (fresh-logs-rpc
                      (devnet-smoke-gate-rpc-body fresh-logs-response))
                    (fresh-safe-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-block-response))
                    (fresh-finalized-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-block-response))
                    (fresh-safe-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-balance-response))
                    (fresh-finalized-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-balance-response))
                    (fresh-raw-transaction
                      (fixture-object-field fresh-raw-transaction-rpc
                                            "result"))
                    (fresh-pending-transactions
                      (fixture-object-field fresh-pending-transactions-rpc
                                            "result"))
                    (fresh-pending-transaction
                      (find transaction-hash-hex fresh-pending-transactions
                            :test #'string=
                            :key (lambda (transaction)
                                   (fixture-object-field transaction
                                                         "hash"))))
                    (fresh-reinserted-transactions
                      (loop for item in reinsertable-transaction-items
                            collect
                            (find (getf item :hash-hex)
                                  fresh-pending-transactions
                                  :test #'string=
                                  :key (lambda (transaction)
                                         (fixture-object-field transaction
                                                               "hash")))))
                    (fresh-latest-block
                      (fixture-object-field fresh-latest-block-rpc "result"))
                    (fresh-child-block
                      (fixture-object-field fresh-child-block-rpc "result"))
                    (fresh-block-receipts
                      (fixture-object-field fresh-block-receipts-rpc
                                            "result"))
                    (fresh-logs
                      (fixture-object-field fresh-logs-rpc "result"))
                    (fresh-safe-block
                      (fixture-object-field fresh-safe-block-rpc "result"))
                    (fresh-finalized-block
                      (fixture-object-field fresh-finalized-block-rpc
                                            "result"))
                    (fresh-safe-balance
                      (fixture-object-field fresh-safe-balance-rpc
                                            "result"))
                    (fresh-finalized-balance
                      (fixture-object-field fresh-finalized-balance-rpc
                                            "result"))
                    (fresh-child-require-canonical-state-errors
                      (devnet-smoke-gate-verify-state-error-probes
                       fresh-child-require-canonical-state-probes
                       "noncanonical-state"))
                    (fresh-hidden-receipt-count
                      (count-if
                       #'identity
                       (cons
                        (null (fixture-object-field fresh-receipt-rpc
                                                    "result"))
                        (mapcar
                         (lambda (rpc)
                           (null (fixture-object-field rpc "result")))
                         fresh-extra-receipt-rpcs)))))
               (devnet-smoke-gate-require
                (= (block-header-number (block-header side-block))
                   (getf fresh-summary :head-number))
                "Side-reorg database restore head number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (getf fresh-summary :head-hash))
                "Side-reorg database restore head hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :safe-hash))
                "Side-reorg database restore safe hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :safe-number)))
                "Side-reorg database restore safe number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :finalized-hash))
                "Side-reorg database restore finalized hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :finalized-number)))
                "Side-reorg database restore finalized number mismatch")
               (devnet-smoke-gate-require
                (chain-store-known-block
                 (ethereum-lisp.cli:devnet-node-store fresh-node)
                 child-block-hash)
                "Side-reorg database restore lost old child block")
               (devnet-smoke-gate-require
                (= 0 (getf fresh-rpc-summary :engine-connections))
                "Fresh side-reorg restore expected 0 Engine connections, got ~S"
                (getf fresh-rpc-summary :engine-connections))
               (devnet-smoke-gate-require
                (= fresh-public-connection-count
                   (getf fresh-rpc-summary :public-connections))
                "Fresh side-reorg restore expected ~S public connections, got ~S"
                fresh-public-connection-count
                (getf fresh-rpc-summary :public-connections))
               (dolist (response (append
                                   (list fresh-raw-transaction-response
                                         fresh-pending-transactions-response
                                         fresh-receipt-response
                                         fresh-block-number-response
                                         fresh-latest-block-response
                                         fresh-child-block-response
                                         fresh-block-receipts-response
                                         fresh-logs-response
                                         fresh-safe-block-response
                                         fresh-finalized-block-response
                                         fresh-safe-balance-response
                                         fresh-finalized-balance-response)
                                   fresh-extra-receipt-responses))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Fresh side-reorg restore public RPC HTTP status mismatch"))
               (if reinsertable-transaction-p
                   (progn
                     (devnet-smoke-gate-require
                      (string= expected-raw-transaction
                               fresh-raw-transaction)
                      "Fresh side-reorg restore lost pending raw transaction")
                     (devnet-smoke-gate-require
                      fresh-pending-transaction
                      "Fresh side-reorg restore lost pending transaction view")
                     (devnet-smoke-gate-require
                      (string= transaction-hash-hex
                               (fixture-object-field
                                fresh-pending-transaction
                                "hash"))
                      "Fresh side-reorg restore pending transaction hash mismatch")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockHash"))
                      "Fresh side-reorg restore pending view kept old block hash")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockNumber"))
                      "Fresh side-reorg restore pending view kept old block number")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "transactionIndex"))
                      "Fresh side-reorg restore pending view kept old index")
                     (loop for item in reinsertable-transaction-items
                           for pending-transaction in fresh-reinserted-transactions
                           do
                              (devnet-smoke-gate-require
                               pending-transaction
                               "Fresh side-reorg restore missing displaced transaction in pending view")
                              (devnet-smoke-gate-require
                               (string= (getf item :hash-hex)
                                        (fixture-object-field
                                         pending-transaction
                                         "hash"))
                               "Fresh side-reorg restore displaced pending hash mismatch")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockHash"))
                               "Fresh side-reorg restore displaced pending kept old block hash")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockNumber"))
                               "Fresh side-reorg restore displaced pending kept old block number")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "transactionIndex"))
                               "Fresh side-reorg restore displaced pending kept old index")))
                 (progn
                   (devnet-smoke-gate-require
                    (null fresh-raw-transaction)
                    "Fresh side-reorg restore exposed wrong-chain raw transaction")
                   (devnet-smoke-gate-require
                    (null fresh-pending-transaction)
                    "Fresh side-reorg restore exposed wrong-chain pending transaction")))
               (devnet-smoke-gate-require
                (null (fixture-object-field fresh-receipt-rpc "result"))
                "Fresh side-reorg restore kept old canonical receipt")
               (loop for item in extra-transaction-items
                     for rpc in fresh-extra-receipt-rpcs
                     do
                        (devnet-smoke-gate-require
                         (null (fixture-object-field rpc "result"))
                         "Fresh side-reorg restore kept displaced canonical receipt ~S"
                         (getf item :hash-hex)))
               (devnet-smoke-gate-require
                (string= expected-side-block-number
                         (fixture-object-field fresh-block-number-rpc
                                               "result"))
                "Fresh side-reorg restore public block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (fixture-object-field fresh-latest-block "hash"))
                "Fresh side-reorg restore latest block hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex child-block-hash)
                         (fixture-object-field fresh-child-block "hash"))
                "Fresh side-reorg restore lost old child block hash lookup")
               (devnet-smoke-gate-require
                (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                       fresh-child-require-canonical-state-errors)
                "Fresh side-reorg restore child requireCanonical state errors mismatch")
               (devnet-smoke-gate-require
                (zerop (length fresh-block-receipts))
                "Fresh side-reorg restore kept canonical receipts")
               (devnet-smoke-gate-require
                (zerop (length fresh-logs))
                "Fresh side-reorg restore kept canonical logs")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-safe-block "hash"))
                "Fresh side-reorg restore safe block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-safe-block "number"))
                "Fresh side-reorg restore safe block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-finalized-block "hash"))
                "Fresh side-reorg restore finalized block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-finalized-block "number"))
                "Fresh side-reorg restore finalized block number mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance fresh-safe-balance)
                "Fresh side-reorg restore safe balance mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance
                         fresh-finalized-balance)
                "Fresh side-reorg restore finalized balance mismatch")
               (list :side-block-hash (hash32-to-hex side-block-hash)
                     :side-forkchoice-status
                     (fixture-object-field side-forkchoice-status "status")
                     :side-rejected-checkpoint-error
                     (fixture-object-field side-rejected-forkchoice-error
                                           "message")
                     :side-block-number
                     (fixture-object-field side-block-number-rpc "result")
                     :side-latest-block-hash
                     (fixture-object-field side-latest-block "hash")
                     :side-transaction-reinserted-p
                     (if reinsertable-transaction-p t :false)
                     :side-transaction-by-hash
                     (or side-transaction :false)
                     :side-raw-transaction
                     (or side-raw-transaction :false)
                     :side-pending-transaction
                     (or side-pending-transaction :false)
                     :side-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-receipt
                     (or (fixture-object-field side-receipt-rpc "result")
                         :false)
                     :side-hidden-receipt-count
                     side-hidden-receipt-count
	                     :side-child-block-hash
	                     (fixture-object-field child-block-by-hash "hash")
                             :side-block-receipts-count
                             (length side-block-receipts)
                             :side-log-count
                             (length side-logs)
	                     :side-restored-head-number
                     (quantity-to-hex (getf fresh-summary :head-number))
                     :side-restored-head-hash
                     (getf fresh-summary :head-hash)
                     :side-restored-rpc-block-number
                     (fixture-object-field fresh-block-number-rpc "result")
                     :side-restored-rpc-latest-block-hash
                     (fixture-object-field fresh-latest-block "hash")
                     :side-restored-safe-number
                     (quantity-to-hex (getf fresh-summary :safe-number))
                     :side-restored-safe-hash
                     (getf fresh-summary :safe-hash)
                     :side-restored-finalized-number
                     (quantity-to-hex
                      (getf fresh-summary :finalized-number))
                     :side-restored-finalized-hash
                     (getf fresh-summary :finalized-hash)
                     :side-restored-rpc-safe-number
                     (fixture-object-field fresh-safe-block "number")
                     :side-restored-rpc-safe-hash
                     (fixture-object-field fresh-safe-block "hash")
                     :side-restored-rpc-finalized-number
                     (fixture-object-field fresh-finalized-block "number")
                     :side-restored-rpc-finalized-hash
                     (fixture-object-field fresh-finalized-block "hash")
                     :side-restored-safe-balance
                     fresh-safe-balance
                     :side-restored-finalized-balance
                     fresh-finalized-balance
                     :side-restored-raw-transaction
                     (or fresh-raw-transaction :false)
                     :side-restored-pending-transaction
                     (or fresh-pending-transaction :false)
                     :side-restored-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-restored-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-restored-receipt
                     (or (fixture-object-field fresh-receipt-rpc "result")
                         :false)
                     :side-restored-hidden-receipt-count
                     fresh-hidden-receipt-count
                     :side-restored-child-block-hash
                     (fixture-object-field fresh-child-block "hash")
                     :side-restored-child-require-canonical-error
                     (first fresh-child-require-canonical-state-errors)
                     :side-restored-child-require-canonical-errors
                     fresh-child-require-canonical-state-errors
                     :side-restored-block-receipts-count
                     (length fresh-block-receipts)
                     :side-restored-log-count
                     (length fresh-logs)
                     :side-restored-public-connections
                     (getf fresh-rpc-summary :public-connections)
                     :engine-connections (getf summary :engine-connections)
                     :public-connections
                     (getf summary :public-connections)))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (declare (ignore path side-payload side-block child-block transaction-checks
                   balance-targets expected-safe-block-hash sender-address
                   code-address storage-address storage-key config))
  #-sbcl
  (error "Restored devnet side reorg RPC verification requires SBCL threads"))

