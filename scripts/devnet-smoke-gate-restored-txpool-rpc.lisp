(in-package #:ethereum-lisp.test)

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

