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
                    (cons "params" #())))
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
                      (cons "params" #())))
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

